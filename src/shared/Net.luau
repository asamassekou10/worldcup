--!strict
-- Net: single source of truth for every remote in the game.
-- The server lazily creates the RemoteEvents; the client waits for them.
-- Add a new remote in ONE place (Net.Events) and both sides stay in sync.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FOLDER_NAME = "PenaltyKingsRemotes"

local Net = {}

Net.Events = {
	-- Practice mode (Slice 1) -- kept for a future warmup mode.
	TakeShot = "TakeShot", -- client -> server: a ShotRequest
	ShotResult = "ShotResult", -- server -> client: a ShotResult

	-- PvP (Slice 2): client -> server
	JoinQueue = "JoinQueue", -- ask to enter matchmaking
	LeaveQueue = "LeaveQueue", -- ask to leave matchmaking
	SubmitInput = "SubmitInput", -- a ShotRequest (shooter) or KeeperInput (keeper)

	-- PvP (Slice 2): server -> client
	QueueUpdate = "QueueUpdate", -- QueueInfo: are you queued + queue size
	RoundStart = "RoundStart", -- RoundStartInfo: your role + score + deadline
	RoundResult = "RoundResult", -- RoundResultInfo: what happened this round
	MatchOver = "MatchOver", -- MatchOverInfo: win/loss + final score

	-- Persistence (Slice 3): server -> client
	ProfileUpdate = "ProfileUpdate", -- ProfileData: coins/stats snapshot for the HUD

	-- Cosmetics shop (Slice 4): client -> server
	BuyCosmetic = "BuyCosmetic", -- { id: string }
	EquipCosmetic = "EquipCosmetic", -- { id: string }
	-- Cosmetics shop (Slice 4): server -> client
	Notify = "Notify", -- { message: string }: a transient toast

	-- Global leaderboards (Slice 4): server -> client
	LeaderboardUpdate = "LeaderboardUpdate", -- LeaderboardData: top players per board

	-- Monetization (Slice 5): server -> client
	MonetizationInfo = "MonetizationInfo", -- MonetizationInfo: gamepass perks

	-- Friend challenges (Phase 3): in-server private 1v1
	ChallengePlayer = "ChallengePlayer", -- client -> server: { targetUserId }
	ChallengeInvite = "ChallengeInvite", -- server -> client: { fromUserId, fromName }
	ChallengeRespond = "ChallengeRespond", -- client -> server: { fromUserId, accept }

	-- Emotes/taunts (Phase 3): in-match expression
	Emote = "Emote", -- client -> server: { emoji: string }
	EmoteShown = "EmoteShown", -- server -> client: { userId, emoji } (broadcast)

	-- Warmup target range (hub activity): client -> server
	WarmupReward = "WarmupReward", -- { score: number } -> server grants capped coins/XP

	-- Prediction booth (hub): client -> server
	Predict = "Predict", -- { key: string, pick: string } -> record a match prediction

	-- Season Pass ("Road to the Final"): server -> client
	SeasonUpdate = "SeasonUpdate", -- { SeasonXP, SeasonTierGranted, HasPremiumPass, EquippedTitle }

	-- Walk-Off 1v1 queue: client -> server / server -> client
	JoinWalkOffQueue = "JoinWalkOffQueue", -- client -> server: enter the walk-off queue
	LeaveWalkOffQueue = "LeaveWalkOffQueue", -- client -> server: leave the walk-off queue
	WalkOffQueueUpdate = "WalkOffQueueUpdate", -- server -> client: { inQueue, size }

	-- Goalkeeper Gauntlet (minigame): server fires RoundStart/RoundResult/MatchOver
	-- with a gauntlet flag so the client can show the right UI context.
	GauntletStart = "GauntletStart", -- server -> client: shot N/10 beginning (like RoundStartInfo + isGauntlet=true)
	GauntletOver = "GauntletOver", -- server -> client: { saves, totalShots, reward }

	-- Trivia Kiosk (minigame): World Cup knowledge quiz for coins.
	TriviaQuestion = "TriviaQuestion", -- server -> client: { index, total, question, options, deadline }
	TriviaSubmit = "TriviaSubmit", -- client -> server: { answer: "A"|"B"|"C"|"D" }
	TriviaResult = "TriviaResult", -- server -> client: { correct, correctAnswer, coinsEarned }
	TriviaOver = "TriviaOver", -- server -> client: { score, total, totalCoins }

	-- Free Kick Challenge (minigame): player shoots at target zones for coins.
	-- Per-shot: server fires FreekickStart then the standard RoundStart/RoundResult.
	-- End:      server fires MatchOver then FreekickOver.
	FreekickStart = "FreekickStart", -- server -> client: { shotIndex, totalShots, targetX, targetY, targetLabel, deadline }
	FreekickOver = "FreekickOver", -- server -> client: { hits, totalShots, totalCoins }

	-- First-time onboarding: client tells the server the welcome flow is complete.
	MarkOnboarded = "MarkOnboarded", -- client -> server: set HasOnboarded = true

	-- Juggling Pitch (minigame): tap-timing ball juggle for coins.
	JuggleStart = "JuggleStart", -- server -> client: { duration, startTime, freq }
	JuggleHit = "JuggleHit", -- client -> server: (no payload — tap event)
	JuggleUpdate = "JuggleUpdate", -- server -> client: { count, streak, freq }
	JuggleOver = "JuggleOver", -- server -> client: { count, totalCoins }

	-- Choices runner: per-player scary atmosphere swap (client-side Lighting), used only
	-- for the optional intense finale -- the run is bright by default.
	GauntletAtmosphere = "GauntletAtmosphere", -- server -> client: { active: boolean }
	-- Choices runner: after you walk through a door, the server sends the GLOBAL vote
	-- tally so the client can pop the "X% chose A / Y% chose B" splash (the viral hook).
	ChoiceResult = "ChoiceResult", -- server -> client:
	-- { prompt, aText, bText, aPct, bPct, picked: "a"|"b", correct: "a"|"b"? }
	-- Choices runner: fired on entry/exit so the client can hide the penalty-game HUD
	-- (clean screen) and restore the camera when leaving.
	ChoicesMode = "ChoicesMode", -- server -> client: { active: boolean }
	-- Choices runner: the course manifest (each gate's world-Z, prompt and the two door
	-- texts), so the client can frame/zoom the doors you're approaching (+ optional voice).
	ChoicesCourse = "ChoicesCourse", -- server -> client: { gates: { {z, prompt, a, b} } }
	-- Choices runner: the end-of-run summary that drives the shareable "personality card"
	-- (how often you sided with the crowd) + the legend-collection progress.
	ChoicesSummary = "ChoicesSummary", -- server -> client:
	-- { agreed, dilemmas, points, legendsUnlocked, legendsTotal, newLegends: {string} }

	-- Treadmill "Training Grounds": a tick of earnings while you're on a treadmill, so the
	-- client can pop a "+X coins / +Y XP" ticker (and note an active Energy Drink boost).
	TreadmillTick = "TreadmillTick", -- server -> client: { coins, xp, energy: boolean }

	-- Choices runner: a door's PER-PLAYER effect (personal weather + a sound). Body/gameplay
	-- effects are applied server-side; this carries the things only the local client can do.
	ChoicesEffect = "ChoicesEffect", -- server -> client: { weather: string?, sound: string? }

	-- "PLAY" menu: the client asks to be teleported to an activity (so solo players can find
	-- every mode -- especially Would You Rather -- instead of a PvP-only Find Match button).
	GotoActivity = "GotoActivity", -- client -> server: { key: string }

	-- Idle "Football Club": passive coin earner (the daily return hook).
	ClubState = "ClubState", -- server -> client: { level, ratePerHr, pending, cap, upgradeCost, coins }
	ClubAction = "ClubAction", -- client -> server: { action: "claim" | "upgrade" }

	-- Collectible cards: earn packs, open them, complete the set.
	CardState = "CardState", -- server -> client: { owned, packs, distinct, total }
	CardOpen = "CardOpen", -- client -> server: (no payload) open one pack
	CardOpened = "CardOpened", -- server -> client: { rolled: {string}, newIds: {[string]: boolean} }

	-- Live events: the current always-on event (Double Coins / XP / Pack Frenzy / Weekend).
	LiveEvent = "LiveEvent", -- server -> client: { key, label, emoji, coinMult, xpMult, endsAt }
}

local folder: Folder?

local function getFolder(): Folder
	if folder then
		return folder
	end
	local resolved: Folder
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if existing then
			resolved = existing :: Folder
		else
			local new = Instance.new("Folder")
			new.Name = FOLDER_NAME
			new.Parent = ReplicatedStorage
			resolved = new
		end
	else
		resolved = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
	end
	folder = resolved
	return resolved
end

function Net.getEvent(name: string): RemoteEvent
	local f = getFolder()
	if RunService:IsServer() then
		local ev = f:FindFirstChild(name)
		if not ev then
			local new = Instance.new("RemoteEvent")
			new.Name = name
			new.Parent = f
			ev = new
		end
		return ev :: RemoteEvent
	end
	return f:WaitForChild(name) :: RemoteEvent
end

return Net
