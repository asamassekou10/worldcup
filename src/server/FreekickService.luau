--!strict
-- FreekickService: Free Kick Challenge minigame.
-- The player stands at the "FreekickPad" Part in the Workspace, activates the
-- ProximityPrompt, then takes 5 shots at cycling target zones for coins.
--
-- Per shot:
--   1. FreekickStart fires (target zone info + deadline).
--   2. RoundStart fires to activate the shooter HUD (role = "Shooter").
--   3. Player submits via SubmitInput (same ShotRequest payload as a match).
--   4. RoundResult fires so the ShotAnimator plays the ball flight.
-- After all 5 shots: MatchOver returns the player to the lobby, FreekickOver
-- fires the summary toast.
--
-- Coin rewards: 5 per target hit, 2 per near miss, +25 bonus if all 5 hit.
-- Season XP: 5 per hit.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net    = require(Shared:WaitForChild("Net"))

local DataService = require(script.Parent:WaitForChild("DataService"))

local FreekickService = {}

-- Exposed so init.server.luau can route SubmitInput here.
FreekickService.sessionByPlayer = {} :: { [Player]: FreekickSession }

local TOTAL_SHOTS    = 5
local SHOT_SECONDS   = 7    -- window per shot
local RESULT_SECONDS = 1.8

local COIN_HIT   = 5
local COIN_NEAR  = 2
local COIN_BONUS = 25  -- all 5 targets hit
local XP_HIT     = 5

-- Target zones in shot-space: x ∈ [-1, 1] (left/right), y ∈ [0, 1] (low/high).
-- These match the coordinate system used by Penalty.resolveSkill and the aim grid.
local TARGET_ZONES: { { x: number, y: number, label: string } } = {
	{ x = -0.72, y = 0.78, label = "TOP-LEFT" },
	{ x =  0.72, y = 0.78, label = "TOP-RIGHT" },
	{ x =  0.72, y = 0.22, label = "BOTTOM-RIGHT" },
	{ x = -0.72, y = 0.22, label = "BOTTOM-LEFT" },
	{ x =  0.00, y = 0.88, label = "TOP-CENTRE" },
}

local HIT_RADIUS  = 0.30  -- direct hit
local NEAR_RADIUS = 0.50  -- partial credit

type FreekickSession = {
	player: Player,
	hits: number,
	totalCoins: number,
	pendingInput: { x: number, y: number }?,
	pendingEvent: BindableEvent?,
}

local function notify(player: Player, msg: string)
	Net.getEvent(Net.Events.Notify):FireClient(player, { message = msg })
end

local function dist(ax: number, ay: number, bx: number, by: number): number
	return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

local function runSession(session: FreekickSession)
	local player = session.player

	for i = 1, TOTAL_SHOTS do
		if not (player.Parent == Players) then
			break
		end

		session.pendingInput = nil

		local zone = TARGET_ZONES[i]
		local deadline = Workspace:GetServerTimeNow() + SHOT_SECONDS

		-- 1. Tell the client which target to aim at.
		Net.getEvent(Net.Events.FreekickStart):FireClient(player, {
			shotIndex   = i,
			totalShots  = TOTAL_SHOTS,
			targetX     = zone.x,
			targetY     = zone.y,
			targetLabel = zone.label,
			deadline    = deadline,
		})

		-- 2. Activate the shooter HUD (reuses the standard match shooter screen).
		Net.getEvent(Net.Events.RoundStart):FireClient(player, {
			role        = "Shooter",
			shooterName = player.DisplayName,
			keeperName  = "Free Kick",
			turnIndex   = i,
			totalTurns  = TOTAL_SHOTS,
			deadline    = deadline,
			standings   = { { name = player.DisplayName, goals = session.hits, isYou = true } },
			isFreekick  = true,
		})

		-- 3. Wait for SubmitInput or timeout.
		local evt = Instance.new("BindableEvent")
		session.pendingEvent = evt

		local timedOut = false
		task.delay(SHOT_SECONDS, function()
			if evt.Parent then
				timedOut = true
				evt:Fire()
			end
		end)

		evt.Event:Wait()
		evt:Destroy()
		session.pendingEvent = nil

		if not (player.Parent == Players) then
			break
		end

		-- 4. Evaluate shot.
		local input = session.pendingInput
		local coins = 0
		local outcome: string
		local shotX = zone.x  -- default display to target if timed out
		local shotY = zone.y

		if input and not timedOut then
			shotX = input.x
			shotY = input.y
			local d = dist(input.x, input.y, zone.x, zone.y)
			if d <= HIT_RADIUS then
				coins = COIN_HIT
				session.hits += 1
				outcome = "Goal"
				notify(player, string.format("TARGET HIT! +%d coins", coins))
			elseif d <= NEAR_RADIUS then
				coins = COIN_NEAR
				outcome = "Miss"
				notify(player, string.format("Close! +%d coin", coins))
			else
				outcome = "Miss"
				notify(player, "Missed the zone — aim for the " .. zone.label)
			end
		else
			outcome = "Miss"
			notify(player, "Time's up!")
		end

		session.totalCoins += coins

		-- 5. Fire RoundResult so the ShotAnimator plays ball flight.
		Net.getEvent(Net.Events.RoundResult):FireClient(player, {
			outcome        = outcome,
			shotX          = shotX,
			shotY          = shotY,
			keeperX        = 0,
			keeperY        = 0.5,
			curve          = 0,
			youWereShooter = true,
			youWereKeeper  = false,
			shooterName    = player.DisplayName,
			keeperName     = "Free Kick",
			standings      = { { name = player.DisplayName, goals = session.hits, isYou = true } },
			isFreekick     = true,
		})

		task.wait(RESULT_SECONDS)
	end

	FreekickService.sessionByPlayer[player] = nil

	-- Bonus for a perfect round.
	if session.hits == TOTAL_SHOTS then
		session.totalCoins += COIN_BONUS
	end

	local totalCoins = session.totalCoins
	local seasonXp   = session.hits * XP_HIT

	if player.Parent == Players then
		if totalCoins > 0 or seasonXp > 0 then
			DataService.grantReward(player, totalCoins, seasonXp)
		end

		-- MatchOver returns the camera and lobby UI to the player.
		Net.getEvent(Net.Events.MatchOver):FireClient(player, {
			won       = session.hits >= 3,
			placement = session.hits,
			total     = TOTAL_SHOTS,
			standings = { { name = player.DisplayName, goals = session.hits, isYou = true } },
			reason    = string.format(
				"Free Kick: %d / %d targets  ·  +%d coins",
				session.hits, TOTAL_SHOTS, totalCoins
			),
		})

		Net.getEvent(Net.Events.FreekickOver):FireClient(player, {
			hits       = session.hits,
			totalShots = TOTAL_SHOTS,
			totalCoins = totalCoins,
		})
	end
end

-- Called from init.server.luau SubmitInput fallthrough.
-- Returns true if the input was consumed (player is in a freekick session).
function FreekickService.submit(player: Player, payload: unknown): boolean
	local session = FreekickService.sessionByPlayer[player]
	if not session then
		return false
	end
	if typeof(payload) ~= "table" then
		return false
	end
	local t = payload :: { [string]: unknown }
	local x = tonumber(t.x)
	local y = tonumber(t.y)
	if not x or not y then
		return false
	end
	session.pendingInput = {
		x = math.clamp(x, -1.5, 1.5),
		y = math.clamp(y, -0.1, 1.1),
	}
	local ev = session.pendingEvent
	if ev and ev.Parent then
		ev:Fire()
	end
	return true
end

function FreekickService.start()
	local function setupPad(part: BasePart)
		local prompt = part:FindFirstChildOfClass("ProximityPrompt")
		if not prompt then
			prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Free Kick Challenge"
			prompt.ObjectText = "5 shots · hit the target zones!"
			prompt.MaxActivationDistance = 8
			prompt.HoldDuration = 0
			prompt.Parent = part
		end
		(prompt :: ProximityPrompt).Triggered:Connect(function(player: Player)
			if FreekickService.sessionByPlayer[player] then
				return
			end
			local session: FreekickSession = {
				player      = player,
				hits        = 0,
				totalCoins  = 0,
				pendingInput = nil,
				pendingEvent = nil,
			}
			FreekickService.sessionByPlayer[player] = session
			task.spawn(runSession, session)
		end)
	end

	local function tryFind()
		local pad = Workspace:FindFirstChild("FreekickPad", true)
		if pad and pad:IsA("BasePart") then
			setupPad(pad)
		end
	end
	tryFind()
	Workspace.DescendantAdded:Connect(function(inst)
		if inst.Name == "FreekickPad" and inst:IsA("BasePart") then
			setupPad(inst :: BasePart)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local session = FreekickService.sessionByPlayer[player]
		if session then
			FreekickService.sessionByPlayer[player] = nil
			local ev = session.pendingEvent
			if ev and ev.Parent then
				ev:Fire()
			end
		end
	end)
end

return FreekickService
