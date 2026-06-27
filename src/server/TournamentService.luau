--!strict
-- TournamentService: runs the WEEKLY tournament on top of a week-keyed OrderedDataStore.
--  * Publishing: each online player's Tournament Points are written to this week's store on a slow
--    heartbeat (and when they leave), so the ladder is eventually-consistent without hammering it.
--  * Standings: the top-N is fetched periodically and pushed to every client (with each player's own
--    live rank merged in).
--  * Payouts: when a player joins we read the PREVIOUS week's frozen standings, find their rank, and
--    pay the prize once (DataService.payTournament is gated by their session-locked profile, so no
--    double-pay and no cross-server finalizer lock is needed).
-- Every DataStore call is pcall'd so Studio (no API access) degrades to an empty board.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Tournament = require(Shared:WaitForChild("Tournament"))
local DataService = require(script.Parent:WaitForChild("DataService"))

local TournamentService = {}

local TOP_N = 10
local PUBLISH_SECONDS = 45
local REFRESH_SECONDS = 60

local function tryGetStore(name: string): OrderedDataStore?
	local ok, store = pcall(function()
		return DataStoreService:GetOrderedDataStore(name)
	end)
	return if ok then store else nil
end

local nameCache: { [number]: string } = {}
local function resolveName(userId: number): string
	local known = nameCache[userId]
	if known then
		return known
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = if ok then name else `Player{userId}`
	nameCache[userId] = result
	return result
end

-- Cached top-N standings for the current week: { { name, value, userId } }.
type Row = { name: string, value: number, userId: number }
local standings: { Row } = {}

local function currentStore(): OrderedDataStore?
	return tryGetStore(Tournament.storeName(Tournament.weekId()))
end

-- Publish one player's points to this week's board.
local function publish(player: Player)
	local points = DataService.tournPoints(player)
	if not points then
		return
	end
	local store = currentStore()
	if not store then
		return
	end
	pcall(function()
		store:SetAsync(`{player.UserId}`, points)
	end)
end

local function fetchStandings()
	local store = currentStore()
	if not store then
		return
	end
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, TOP_N)
	end)
	if not ok then
		return
	end
	local ok2, page = pcall(function()
		return pages:GetCurrentPage()
	end)
	if not ok2 then
		return
	end
	local rows: { Row } = {}
	for _, item in page do
		local userId = tonumber(item.key)
		if userId then
			table.insert(rows, { name = resolveName(userId), value = item.value, userId = userId })
		end
	end
	standings = rows
end

-- The board payload tailored to one player (their own live rank merged into the shared standings).
local function pushTo(player: Player)
	local myPoints = DataService.tournPoints(player) or 0
	local myRank = 0
	for i, row in standings do
		if row.userId == player.UserId then
			myRank = i
			break
		end
	end
	local board = {}
	for i, row in standings do
		board[i] = { name = row.name, value = row.value }
	end
	Net.getEvent(Net.Events.TournamentState):FireClient(player, {
		points = myPoints,
		rank = myRank,
		resetsAt = Tournament.resetsAt(),
		standings = board,
		prizes = Tournament.prizeLadder(),
	})
end

-- On join, pay out the player's prize from LAST week's frozen standings (once).
local function payLastWeek(player: Player)
	local lastWeek = Tournament.weekId() - 1
	local store = tryGetStore(Tournament.storeName(lastWeek))
	if not store then
		return
	end
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, Tournament.PaidRanks)
	end)
	if not ok then
		return
	end
	local ok2, page = pcall(function()
		return pages:GetCurrentPage()
	end)
	if not ok2 then
		return
	end
	for rank, item in page do
		if tonumber(item.key) == player.UserId then
			local prize = Tournament.prizeForRank(rank)
			if prize and DataService.payTournament(player, lastWeek, prize.coins, prize.packs) then
				local extra = if prize.packs > 0
					then string.format(" + %d card pack(s)", prize.packs)
					else ""
				Net.getEvent(Net.Events.Notify):FireClient(player, {
					message = string.format(
						"🏆 You placed #%d in last week's tournament! +%d coins%s",
						rank,
						prize.coins,
						extra
					),
				})
			end
			break
		end
	end
end

function TournamentService.start()
	task.spawn(fetchStandings)

	DataService.onProfileLoaded(function(player)
		task.spawn(payLastWeek, player) -- claim last week's prize (DataStore reads off the hot path)
		pushTo(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		publish(player) -- bank their final score for the week before they go
	end)

	-- Publish online players' scores to the board.
	task.spawn(function()
		while true do
			task.wait(PUBLISH_SECONDS)
			for _, p in Players:GetPlayers() do
				publish(p)
			end
		end
	end)

	-- Refresh the standings + push to everyone.
	task.spawn(function()
		while true do
			task.wait(REFRESH_SECONDS)
			fetchStandings()
			for _, p in Players:GetPlayers() do
				pushTo(p)
			end
		end
	end)
end

return TournamentService
