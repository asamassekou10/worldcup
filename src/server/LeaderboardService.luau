--!strict
-- LeaderboardService: global "Most Wins" / "Most Coins" boards via
-- OrderedDataStore. A player's totals are submitted when a match ends; every
-- client gets a periodically-refreshed top-N. All DataStore calls are pcall'd
-- so Studio (no API access -> mock unavailable for OrderedDataStore) degrades
-- to empty boards instead of erroring.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Types = require(Shared:WaitForChild("Types"))
local Catalog = require(Shared:WaitForChild("Catalog"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local Progression = require(Shared:WaitForChild("Progression"))
local WorldCup = require(Shared:WaitForChild("WorldCup"))

local LeaderboardService = {}

local TOP_N = 10
local REFRESH_SECONDS = 60

-- GetOrderedDataStore() itself throws when API access is unavailable (Studio
-- with the setting off, or an unpublished place), so even acquiring the store
-- is pcall'd. If it fails the boards stay empty and the rest of the game runs.
local function tryGetStore(name: string): OrderedDataStore?
	local ok, store = pcall(function()
		return DataStoreService:GetOrderedDataStore(name)
	end)
	return if ok then store else nil
end

local winsStore = tryGetStore("Leaderboard_Wins_v1")
local coinsStore = tryGetStore("Leaderboard_Coins_v1")
-- Cumulative goals per nation across ALL players/servers (the World Cup table).
local nationStore = tryGetStore("NationGoals_v1")

-- Golden Boot: individual top scorers, in a store keyed to the current week so it
-- resets every Monday (new store name -> a fresh race, recurring FOMO).
local function weekId(): number
	return math.floor(os.time() / 604800) -- 7 * 24 * 3600
end
local goldenBootStore = tryGetStore("GoldenBoot_w" .. weekId())

-- Last fetched snapshot, sent to clients (and to joiners immediately).
local cached: Types.LeaderboardData = { Wins = {}, Coins = {}, Nations = {}, Scorers = {} }
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

local function fetchBoard(store: OrderedDataStore?): { Types.LeaderEntry }
	local entries: { Types.LeaderEntry } = {}
	if not store then
		return entries
	end
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, TOP_N)
	end)
	if not ok then
		return entries
	end

	local ok2, page = pcall(function()
		return pages:GetCurrentPage()
	end)
	if not ok2 then
		return entries
	end

	for _, item in page do
		local userId = tonumber(item.key)
		if userId then
			table.insert(entries, { name = resolveName(userId), value = item.value })
		end
	end
	return entries
end

-- Nations board: keys are nation ids; map them to "🇧🇷 Brazil" labels.
local function fetchNations(store: OrderedDataStore?): { Types.LeaderEntry }
	local entries: { Types.LeaderEntry } = {}
	if not store then
		return entries
	end
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, TOP_N)
	end)
	if not ok then
		return entries
	end
	local ok2, page = pcall(function()
		return pages:GetCurrentPage()
	end)
	if not ok2 then
		return entries
	end
	for _, item in page do
		local nationId = tostring(item.key)
		local nation = Catalog.get(nationId)
		local label = if nation then `{nation.emoji} {nation.name}` else nationId
		table.insert(entries, { name = label, value = item.value })
	end
	return entries
end

local function refresh()
	cached = {
		Wins = fetchBoard(winsStore),
		Coins = fetchBoard(coinsStore),
		Nations = fetchNations(nationStore),
		Scorers = fetchBoard(goldenBootStore),
	}
	Net.getEvent(Net.Events.LeaderboardUpdate):FireAllClients(cached)
end

-- Push a player's current totals to the boards (call after a match updates them).
function LeaderboardService.submit(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	local key = `{player.UserId}`
	if winsStore then
		pcall(function()
			winsStore:SetAsync(key, data.Wins)
		end)
	end
	if coinsStore then
		pcall(function()
			coinsStore:SetAsync(key, data.Coins)
		end)
	end
end

-- Credit the goals a player just scored to the nation they're repping (their
-- equipped flag). Cumulative across everyone -> the global World Cup standings.
function LeaderboardService.addNationGoals(player: Player, goals: number)
	if goals <= 0 then
		return
	end
	local data = DataService.get(player)
	if not data or data.Equipped == "" then
		return
	end
	-- Matchday spotlight: goals for a nation playing a real fixture today (or the
	-- daily rotation when there are none) count double toward the standings.
	local credited = goals
	if WorldCup.isFeatured(data.Equipped) then
		credited = goals * Progression.FeaturedMultiplier
	end
	if nationStore then
		pcall(function()
			nationStore:IncrementAsync(data.Equipped, credited)
		end)
	end
end

-- Credit a player's goals to the weekly Golden Boot race (individual scorers).
function LeaderboardService.addScorerGoals(player: Player, goals: number)
	if goals <= 0 or not goldenBootStore then
		return
	end
	pcall(function()
		goldenBootStore:IncrementAsync(`{player.UserId}`, goals)
	end)
end

function LeaderboardService.start()
	task.spawn(refresh)

	-- New joiners get the current snapshot right away.
	Players.PlayerAdded:Connect(function(player)
		Net.getEvent(Net.Events.LeaderboardUpdate):FireClient(player, cached)
	end)

	-- Periodic refresh so boards stay live without hammering the DataStore.
	task.spawn(function()
		while true do
			task.wait(REFRESH_SECONDS)
			refresh()
		end
	end)
end

return LeaderboardService
