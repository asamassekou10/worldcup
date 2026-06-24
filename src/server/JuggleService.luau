--!strict
-- JuggleService: tap-timing juggling minigame on the JugglePad.
-- A virtual ball oscillates at `freq` Hz. The player taps when it passes the
-- sweet spot. Each valid tap scores +1 juggle; the ball speeds up each hit.
-- Sessions last 30 seconds; reward scales with total juggles.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))

local DataService = require(script.Parent:WaitForChild("DataService"))

local JuggleService = {}

local SESSION_SECONDS = 30
local FREQ_START      = 0.8   -- Hz at session start
local FREQ_INC        = 0.08  -- added per successful hit
local FREQ_MAX        = 3.0   -- cap — 3 taps/second is very hard
local HIT_COOLDOWN_F  = 0.55  -- min fraction of a cycle between accepted hits
local COIN_PER_JUGGLE = 1
local COIN_CAP        = 30    -- base coin cap
local COIN_BONUS_10   = 10    -- bonus at 10 juggles
local COIN_BONUS_20   = 15    -- bonus at 20 juggles
local XP_REWARD       = 5

-- Symmetric with TriviaKiosk (right side) on the left side of the pitch.
local PAD_POS = Vector3.new(-21.75, 2.62, 17.70)

type JuggleSession = {
	player:    Player,
	startTime: number,
	freq:      number,
	count:     number,
	streak:    number,
	lastHit:   number,
	active:    boolean,
}

JuggleService.sessions = {} :: { [Player]: JuggleSession }

local function coinsFor(count: number): number
	local coins = math.min(count * COIN_PER_JUGGLE, COIN_CAP)
	if count >= 10 then
		coins += COIN_BONUS_10
	end
	if count >= 20 then
		coins += COIN_BONUS_20
	end
	return coins
end

local function endSession(session: JuggleSession, pad: BasePart?)
	if not session.active then return end
	session.active = false
	JuggleService.sessions[session.player] = nil

	if pad then
		local prompt = pad:FindFirstChildOfClass("ProximityPrompt") :: ProximityPrompt?
		if prompt then
			prompt.Enabled = true
		end
	end

	local player = session.player
	if not (player.Parent == Players) then return end

	local coins = coinsFor(session.count)
	if coins > 0 or XP_REWARD > 0 then
		DataService.grantReward(player, coins, XP_REWARD)
	end
	Net.getEvent(Net.Events.JuggleOver):FireClient(player, {
		count      = session.count,
		totalCoins = coins,
	})
end

function JuggleService.handleHit(player: Player)
	local session = JuggleService.sessions[player]
	if not session or not session.active then return end

	local now = Workspace:GetServerTimeNow()
	local cooldown = (1 / session.freq) * HIT_COOLDOWN_F
	if (now - session.lastHit) < cooldown then
		return  -- fired too soon in the cycle — ignore
	end
	session.lastHit = now
	session.count  += 1
	session.streak += 1
	session.freq    = math.min(FREQ_MAX, session.freq + FREQ_INC)

	Net.getEvent(Net.Events.JuggleUpdate):FireClient(player, {
		count  = session.count,
		streak = session.streak,
		freq   = session.freq,
	})
end

local function setupPad(pad: BasePart)
	local prompt = pad:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		local p = Instance.new("ProximityPrompt")
		p.ActionText            = "Juggling Challenge"
		p.ObjectText            = "30 sec · tap the beat!"
		p.MaxActivationDistance = 8
		p.HoldDuration          = 0
		p.Parent                = pad
		prompt = p
	end

	(prompt :: ProximityPrompt).Triggered:Connect(function(player: Player)
		if JuggleService.sessions[player] then return end

		local pr = pad:FindFirstChildOfClass("ProximityPrompt") :: ProximityPrompt?
		if pr then
			pr.Enabled = false
		end

		local startTime = Workspace:GetServerTimeNow()
		local session: JuggleSession = {
			player    = player,
			startTime = startTime,
			freq      = FREQ_START,
			count     = 0,
			streak    = 0,
			lastHit   = startTime - 10,
			active    = true,
		}
		JuggleService.sessions[player] = session

		Net.getEvent(Net.Events.JuggleStart):FireClient(player, {
			duration  = SESSION_SECONDS,
			startTime = startTime,
			freq      = FREQ_START,
		})

		task.delay(SESSION_SECONDS, function()
			endSession(session, pad)
		end)
	end)
end

function JuggleService.start()
	local function tryFind()
		local pad = Workspace:FindFirstChild("JugglePad", true)
		if pad and pad:IsA("BasePart") then
			setupPad(pad :: BasePart)
			return
		end
		local part = Instance.new("Part")
		part.Name       = "JugglePad"
		part.Size       = Vector3.new(3, 0.4, 3)
		part.Position   = PAD_POS
		part.Anchored   = true
		part.CanCollide = true
		part.Material   = Enum.Material.SmoothPlastic
		part.Color      = Color3.fromRGB(60, 200, 100)
		part.Parent     = Workspace
		setupPad(part)
	end
	tryFind()

	Workspace.DescendantAdded:Connect(function(inst)
		if inst.Name == "JugglePad" and inst:IsA("BasePart") then
			setupPad(inst :: BasePart)
		end
	end)

	Net.getEvent(Net.Events.JuggleHit).OnServerEvent:Connect(function(player: Player)
		JuggleService.handleHit(player)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		local session = JuggleService.sessions[player]
		if session then
			session.active = false
			JuggleService.sessions[player] = nil
		end
	end)
end

return JuggleService
