--!strict
-- Matchmaking: a public free-for-all queue. When 2+ players are waiting we gather
-- for a few seconds (to scoop up more, up to 8) then start one match for the
-- group. Tracks which match each player is in to route inputs and clean up on
-- disconnect.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Types = require(Shared:WaitForChild("Types"))

local Match = require(script.Parent:WaitForChild("Match"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local LeaderboardService = require(script.Parent:WaitForChild("LeaderboardService"))
local MonetizationService = require(script.Parent:WaitForChild("MonetizationService"))

local MIN_PLAYERS = 2
local MAX_PLAYERS = 8
local GATHER_SECONDS = 5

local Matchmaking = {}

local queue: { Player } = {}
local matchByPlayer: { [Player]: Match.Match } = {}
local gathering = false

local function sendQueueUpdate(player: Player, inQueue: boolean)
	local info: Types.QueueInfo = { inQueue = inQueue, size = #queue }
	Net.getEvent(Net.Events.QueueUpdate):FireClient(player, info)
end

local function startMatch(group: { Player })
	local match = Match.new(group)
	for _, player in group do
		matchByPlayer[player] = match
	end
	match.onPlayerResult = function(player, won, goals, saves)
		local multiplier = MonetizationService.coinMultiplier(player)
		DataService.applyMatchResult(player, won, goals, saves, multiplier)
		LeaderboardService.submit(player)
		LeaderboardService.addNationGoals(player, goals) -- World Cup standings
		LeaderboardService.addScorerGoals(player, goals) -- weekly Golden Boot race
	end
	match.onFinished = function()
		for _, player in group do
			-- rawequal (identity, no __eq) so we only clear if they haven't been
			-- placed into a newer match.
			if rawequal(matchByPlayer[player], match) then
				matchByPlayer[player] = nil
			end
		end
	end
	task.spawn(function()
		Match.run(match)
	end)
end

-- Pull up to MAX_PLAYERS who are still connected out of the queue.
local function takeGroup(): { Player }
	local group: { Player } = {}
	while #queue > 0 and #group < MAX_PLAYERS do
		local player = table.remove(queue, 1) :: Player
		if player.Parent == Players then
			table.insert(group, player)
		end
	end
	return group
end

local function tryStart()
	if gathering or #queue < MIN_PLAYERS then
		return
	end
	gathering = true
	task.delay(GATHER_SECONDS, function()
		gathering = false
		if #queue < MIN_PLAYERS then
			return
		end
		startMatch(takeGroup())
		-- Anyone left over (overflow past MAX) can start another match.
		tryStart()
	end)
end

function Matchmaking.join(player: Player)
	if matchByPlayer[player] or table.find(queue, player) then
		return
	end
	table.insert(queue, player)
	sendQueueUpdate(player, true)
	tryStart()
end

function Matchmaking.leave(player: Player)
	local index = table.find(queue, player)
	if index then
		table.remove(queue, index)
		sendQueueUpdate(player, false)
	end
end

function Matchmaking.submit(player: Player, payload: unknown)
	local match = matchByPlayer[player]
	if match then
		Match.submit(match, player, payload)
	end
end

-- ===== Friend challenges: in-server private 1v1 =====

local CHALLENGE_TTL = 20 -- seconds an invite stays open
-- challenger -> { target, expires }
local pending: { [Player]: { target: Player, expires: number } } = {}

local function notify(player: Player, message: string)
	Net.getEvent(Net.Events.Notify):FireClient(player, { message = message })
end

local function isBusy(player: Player): boolean
	if matchByPlayer[player] then
		return true
	end
	return false
end

-- `from` challenges the player with `targetUserId` to a private 1v1.
function Matchmaking.challenge(from: Player, payload: unknown)
	if typeof(payload) ~= "table" then
		return
	end
	local targetUserId = tonumber((payload :: { [string]: unknown }).targetUserId)
	if not targetUserId then
		return
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target or rawequal(target, from) then
		return
	end
	if isBusy(from) or isBusy(target) then
		notify(from, "That player is busy right now.")
		return
	end
	pending[from] = { target = target, expires = os.clock() + CHALLENGE_TTL }
	Net.getEvent(Net.Events.ChallengeInvite):FireClient(target, {
		fromUserId = from.UserId,
		fromName = from.DisplayName,
	})
	notify(from, string.format("Challenge sent to %s.", target.DisplayName))
end

-- `target` accepts/declines a challenge from the player with `fromUserId`.
function Matchmaking.respondChallenge(target: Player, payload: unknown)
	if typeof(payload) ~= "table" then
		return
	end
	local data = payload :: { [string]: unknown }
	local fromUserId = tonumber(data.fromUserId)
	local accept = data.accept == true
	if not fromUserId then
		return
	end
	local from = Players:GetPlayerByUserId(fromUserId)
	local entry = if from then pending[from] else nil
	if not from or not entry or not rawequal(entry.target, target) then
		return -- no such challenge (already taken, expired, or spoofed)
	end
	pending[from] = nil
	if os.clock() > entry.expires then
		notify(target, "That challenge expired.")
		return
	end
	if not accept then
		notify(from, string.format("%s declined your challenge.", target.DisplayName))
		return
	end
	if isBusy(from) or isBusy(target) then
		notify(target, "Can't start — someone's already in a match.")
		return
	end
	-- Pull both out of the public queue and start their private 1v1.
	Matchmaking.leave(from)
	Matchmaking.leave(target)
	notify(from, string.format("Match on vs %s!", target.DisplayName))
	notify(target, string.format("Match on vs %s!", from.DisplayName))
	startMatch({ from, target })
end

function Matchmaking.onPlayerRemoving(player: Player)
	Matchmaking.leave(player)
	pending[player] = nil -- drop a challenge they sent
	for challenger, entry in pending do
		if rawequal(entry.target, player) then
			pending[challenger] = nil -- drop a challenge aimed at them
		end
	end
	local match = matchByPlayer[player]
	if match then
		Match.onPlayerLeft(match, player)
	end
end

return Matchmaking
