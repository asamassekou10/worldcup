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
