--!strict
-- ResultsService: the match-results feed that SETTLES predictions. Results live in a DataStore (so
-- they persist + apply across servers), with the WorldCup.Results code table as a fallback. When a
-- result lands, matching predictions settle via DataService (correct -> escalating streak payout;
-- miss -> streak reset). Admins enter results live with the "/result" chat command; the dev can also
-- bake winners into WorldCup.Results and republish.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local WorldCup = require(Shared:WaitForChild("WorldCup"))
local Config = require(Shared:WaitForChild("Config"))
local Catalog = require(Shared:WaitForChild("Catalog"))
local DataService = require(script.Parent:WaitForChild("DataService"))

local ResultsService = {}

local RESULTS_KEY = "all"
local store: DataStore? = (function(): DataStore?
	local ok, s = pcall(function()
		return DataStoreService:GetDataStore("MatchResults_v1")
	end)
	return if ok then s else nil
end)()

local cache: { [string]: string } = {} -- fixtureKey -> winner nation id (or "draw")

local function loadAll()
	if not store then
		return
	end
	pcall(function()
		local d = (store :: DataStore):GetAsync(RESULTS_KEY)
		if type(d) == "table" then
			for k, v in d do
				if type(k) == "string" and type(v) == "string" then
					cache[k] = v
				end
			end
		end
	end)
end

-- The known winner of a fixture (live DataStore cache first, then the code table), or nil if TBD.
function ResultsService.winner(key: string): string?
	return cache[key] or WorldCup.resultWinner(key)
end

local function settleEveryone()
	for _, p in Players:GetPlayers() do
		DataService.settlePredictions(p, ResultsService.winner)
	end
end

-- Record a result: cache + persist + settle everyone online right away.
local function setResult(key: string, winner: string)
	cache[key] = winner
	if store then
		task.spawn(function()
			pcall(function()
				(store :: DataStore):UpdateAsync(RESULTS_KEY, function(old: any)
					local t: { [string]: string } = if type(old) == "table" then old else {}
					t[key] = winner
					return t
				end)
			end)
		end)
	end
	settleEveryone()
end

local function isAdmin(userId: number): boolean
	if userId == game.CreatorId then
		return true
	end
	return table.find(Config.Admins, userId) ~= nil
end

function ResultsService.start()
	loadAll()

	-- Settle predictions whenever a profile loads -- covers offline players collecting on return.
	DataService.onProfileLoaded(function(player: Player)
		DataService.settlePredictions(player, ResultsService.winner)
	end)

	-- Admin chat command:  /result <date>|<home>|<away> <winnerId|draw>
	-- e.g.  /result 2026-06-28|southafrica|canada southafrica
	-- (TextChatCommands exists under TextChatService when it's the active chat; skip if absent -- the
	-- WorldCup.Results code table is always available as the fallback way to enter results.)
	local cmds = TextChatService:FindFirstChildOfClass("TextChatCommands")
	if cmds then
		local cmd = Instance.new("TextChatCommand")
		cmd.Name = "ResultCommand"
		cmd.PrimaryAlias = "/result"
		cmd.Parent = cmds
		cmd.Triggered:Connect(function(source: TextSource, text: string)
			if not isAdmin(source.UserId) then
				return
			end
			local rest = string.gsub(text, "^/result%s+", "")
			local key, winner = string.match(rest, "^(%S+)%s+(%S+)$")
			if not key or not winner then
				return
			end
			if winner ~= "draw" and not Catalog.get(winner) then
				return -- unknown nation id
			end
			setResult(key, winner)
			local player = Players:GetPlayerByUserId(source.UserId)
			if player then
				Net.getEvent(Net.Events.Notify):FireClient(
					player,
					{ message = "✅ Result recorded: " .. key .. " → " .. winner }
				)
			end
		end)
	end
end

return ResultsService
