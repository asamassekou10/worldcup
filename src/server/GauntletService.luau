--!strict
-- GauntletService: Goalkeeper Gauntlet minigame.
-- The player stands at the "GauntletPad" Part in the Workspace, activates the
-- ProximityPrompt, and tries to save 10 AI-generated shots. Each shot fires with
-- a 5-second window to dive. Payout: 8 coins per save + quality bonuses.
--
-- Input routing: GauntletService registers sessions in `gauntletByPlayer` so that
-- init.server.luau can route SubmitInput to GauntletService.submit() when the
-- player isn't in a normal match.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local Penalty     = require(script.Parent:WaitForChild("Penalty"))

local GauntletService = {}

-- Which player is currently running a gauntlet session (max 1 per player).
-- Exposed so init.server.luau can route SubmitInput here.
GauntletService.gauntletByPlayer = {} :: { [Player]: GauntletSession }

local TOTAL_SHOTS    = 10
local TURN_SECONDS   = 5   -- seconds to submit a dive
local RESULT_SECONDS = 1.8 -- pause between shots

type GauntletSession = {
	player: Player,
	saves: number,
	pendingInput: Types.KeeperInput?,
	pendingInputEvent: BindableEvent?,
}

-- Generate a shot that becomes progressively harder as the session advances.
-- shotIndex: 1..10. Early shots are moderate; late shots are fast + cornered.
local function generateAiShot(shotIndex: number): Types.ShotRequest
	local difficulty = (shotIndex - 1) / (TOTAL_SHOTS - 1) -- 0..1

	-- Power scales from moderate (0.45) to aggressive (0.88).
	local basePower = 0.45 + difficulty * 0.43
	local power = basePower + (math.random() - 0.5) * 0.1
	power = math.clamp(power, 0.3, 0.95)

	-- Corner bias: early shots can go anywhere; late shots prefer the top corners.
	local x: number
	local y: number
	if math.random() < 0.3 + difficulty * 0.4 then
		-- Corner shot: x biased toward edges, y biased toward top
		x = (if math.random() > 0.5 then 1 else -1) * (0.55 + math.random() * 0.45)
		y = 0.5 + math.random() * 0.45
	else
		-- Any region, realistic placement (not too close to ground)
		x = math.random() * 2 - 1
		y = 0.12 + math.random() * 0.76
	end
	x = math.clamp(x, -0.97, 0.97)

	-- Curve: increases with difficulty
	local curve = (math.random() * 2 - 1) * (0.2 + difficulty * 0.3)

	return { x = x, y = y, power = power, curve = curve }
end

-- Resolve the outcome of one AI shot vs the keeper's input using the game's
-- authoritative skill resolver.
local function resolveShot(
	shot: Types.ShotRequest,
	input: Types.KeeperInput?
): (Types.ShotOutcome, number, number)
	local kx = if input then input.x else 0
	local ky = if input then input.y else 0.5
	local outcome = Penalty.resolveSkill(shot, { x = kx, y = ky }, Config.Skill)
	return outcome, kx, ky
end

-- Run the full gauntlet session for one player (called in task.spawn).
local function runSession(session: GauntletSession)
	local player = session.player

	for i = 1, TOTAL_SHOTS do
		if not (player.Parent == Players) then
			break
		end

		local shot = generateAiShot(i)
		session.pendingInput = nil

		-- Per-shot BindableEvent: fires exactly once (input received OR timeout).
		local inputEvent = Instance.new("BindableEvent")
		session.pendingInputEvent = inputEvent

		local deadline = Workspace:GetServerTimeNow() + TURN_SECONDS
		Net.getEvent(Net.Events.GauntletStart):FireClient(player, {
			role        = "Keeper",
			shooterName = "AI Striker",
			keeperName  = player.DisplayName,
			turnIndex   = i,
			totalTurns  = TOTAL_SHOTS,
			deadline    = deadline,
			standings   = { { name = player.DisplayName, goals = session.saves, isYou = true } },
			isGauntlet  = true,
		})

		-- Arm a timeout that fires the event if the player doesn't dive in time.
		task.delay(TURN_SECONDS, function()
			local ev = session.pendingInputEvent
			if ev and ev.Parent then
				ev:Fire()
			end
		end)

		inputEvent.Event:Wait()
		inputEvent:Destroy()
		session.pendingInputEvent = nil

		if not (player.Parent == Players) then
			break
		end

		local outcome, kx, ky = resolveShot(shot, session.pendingInput)
		if outcome == "Save" then
			session.saves += 1
		end

		Net.getEvent(Net.Events.RoundResult):FireClient(player, {
			outcome         = outcome,
			shotX           = shot.x,
			shotY           = shot.y,
			keeperX         = kx,
			keeperY         = ky,
			curve           = shot.curve,
			youWereShooter  = false,
			youWereKeeper   = true,
			shooterName     = "AI Striker",
			keeperName      = player.DisplayName,
			standings       = { { name = player.DisplayName, goals = session.saves, isYou = true } },
		})

		task.wait(RESULT_SECONDS)
	end

	-- Clean up and pay out.
	GauntletService.gauntletByPlayer[player] = nil

	local saves   = session.saves
	-- Base: 8 coins per save. Quality bonus: 50 if 8+, 100 if 10/10.
	local reward  = saves * 8
		+ (if saves >= 10 then 100 else if saves >= 8 then 50 else 0)
	-- Season XP: 5 per save.
	local bonusXp = saves * 5

	if player.Parent == Players then
		DataService.grantReward(player, reward, bonusXp)
		Net.getEvent(Net.Events.GauntletOver):FireClient(player, {
			saves      = saves,
			totalShots = TOTAL_SHOTS,
			reward     = reward,
		})
		Net.getEvent(Net.Events.MatchOver):FireClient(player, {
			won       = saves >= 5,
			placement = saves,
			total     = TOTAL_SHOTS,
			standings = { { name = player.DisplayName, goals = saves, isYou = true } },
			reason    = string.format("Saved %d / %d  •  +%d coins!", saves, TOTAL_SHOTS, reward),
		})
	end
end

-- Called from init.server.luau when SubmitInput arrives and the player is in a
-- gauntlet session (not in a normal match).
-- Returns true if the input was consumed (player is in a gauntlet), false otherwise.
function GauntletService.submit(player: Player, payload: unknown): boolean
	local session = GauntletService.gauntletByPlayer[player]
	if not session then
		return false
	end
	if typeof(payload) ~= "table" then
		return
	end
	local t  = payload :: { [string]: unknown }
	local x  = tonumber(t.x)
	local y  = tonumber(t.y)
	if not x or not y then
		return
	end
	session.pendingInput = {
		x = math.clamp(x, -1.5, 1.5),
		y = math.clamp(y, -0.5, 1.5),
	}
	-- Unblock the gauntlet loop.
	local ev = session.pendingInputEvent
	if ev and ev.Parent then
		ev:Fire()
	end
	return true
end

-- Boot the service: find (or create) the ProximityPrompt on the GauntletPad Part.
function GauntletService.start()
	local function setupPad(part: BasePart)
		local prompt = part:FindFirstChildOfClass("ProximityPrompt")
		if not prompt then
			prompt = Instance.new("ProximityPrompt")
			prompt.ActionText  = "Goalkeeper Gauntlet"
			prompt.ObjectText  = "10 Shots • Save as many as you can!"
			prompt.MaxActivationDistance = 8
			prompt.HoldDuration = 0
			prompt.Parent = part
		end
		(prompt :: ProximityPrompt).Triggered:Connect(function(player: Player)
			if GauntletService.gauntletByPlayer[player] then
				return -- already in a gauntlet
			end
			-- Don't start if the player is in a match (matchByPlayer checked in init).
			local session: GauntletSession = {
				player           = player,
				saves            = 0,
				pendingInput     = nil,
				pendingInputEvent = nil,
			}
			GauntletService.gauntletByPlayer[player] = session
			task.spawn(runSession, session)
		end)
	end

	-- The map builder places a Part named "GauntletPad" anywhere in the Workspace.
	-- GauntletService finds it by name; if it doesn't exist yet, it watches for it.
	local function tryFind()
		local pad = Workspace:FindFirstChild("GauntletPad", true)
		if pad and pad:IsA("BasePart") then
			setupPad(pad)
		end
	end
	tryFind()
	-- Also watch in case the Part loads after this script.
	Workspace.DescendantAdded:Connect(function(inst)
		if inst.Name == "GauntletPad" and inst:IsA("BasePart") then
			setupPad(inst)
		end
	end)

	-- Clean up on disconnect.
	Players.PlayerRemoving:Connect(function(player)
		local session = GauntletService.gauntletByPlayer[player]
		if session then
			GauntletService.gauntletByPlayer[player] = nil
			local ev = session.pendingInputEvent
			if ev and ev.Parent then
				ev:Fire() -- unblock the coroutine so it can exit cleanly
			end
		end
	end)
end

return GauntletService
