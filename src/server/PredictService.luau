--!strict
-- PredictService: the crowd-consensus layer over the match predictor. A player's picks live in their
-- profile (DataService); this aggregates EVERYONE's picks per fixture into a global tally (a
-- DataStore, same pattern as the Would You Rather votes) and ships "% of players picked X" back, so
-- the panel can show social-proof bars -- the hook that makes a pick'em feel alive even before any
-- result is in.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local WorldCup = require(Shared:WaitForChild("WorldCup"))
local DataService = require(script.Parent:WaitForChild("DataService"))

local PredictService = {}

type Tally = { home: number, away: number }

local store: DataStore? = (function(): DataStore?
	local ok, s = pcall(function()
		return DataStoreService:GetDataStore("PredictVotes_v1")
	end)
	return if ok then s else nil
end)()

local cache: { [string]: Tally } = {}

local function getTally(key: string): Tally
	local c = cache[key]
	if c then
		return c
	end
	local t: Tally = { home = 0, away = 0 }
	if store then
		pcall(function()
			local d = (store :: DataStore):GetAsync(key)
			if type(d) == "table" then
				t = { home = tonumber((d :: any).home) or 0, away = tonumber((d :: any).away) or 0 }
			end
		end)
	end
	cache[key] = t
	return t
end

-- Adjust the tally for a (possibly changed) pick. oldSide/newSide are "home"/"away" (old may be nil).
local function adjust(key: string, oldSide: string?, newSide: string)
	if oldSide == newSide then
		return
	end
	local t = getTally(key)
	if oldSide == "home" then
		t.home = math.max(0, t.home - 1)
	elseif oldSide == "away" then
		t.away = math.max(0, t.away - 1)
	end
	if newSide == "home" then
		t.home += 1
	else
		t.away += 1
	end
	if store then
		task.spawn(function()
			pcall(function()
				(store :: DataStore):UpdateAsync(key, function(old: any): Tally
					local v: Tally = if type(old) == "table"
						then { home = tonumber(old.home) or 0, away = tonumber(old.away) or 0 }
						else { home = 0, away = 0 }
					if oldSide == "home" then
						v.home = math.max(0, v.home - 1)
					elseif oldSide == "away" then
						v.away = math.max(0, v.away - 1)
					end
					if newSide == "home" then
						v.home += 1
					else
						v.away += 1
					end
					return v
				end)
			end)
		end)
	end
end

-- "date|home|away" -> home, away ids.
local function teams(key: string): (string?, string?)
	local parts = string.split(key, "|")
	return parts[2], parts[3]
end

-- Today's picks + crowd tallies for one player.
local function sendState(player: Player)
	local picks = DataService.allPredictions(player)
	local tallies: { [string]: Tally } = {}
	local myPicks: { [string]: string } = {}
	for _, f in WorldCup.fixturesOn(WorldCup.todayISO()) do
		if not WorldCup.isMilestone(f) then
			local key = WorldCup.fixtureKey(f)
			tallies[key] = getTally(key)
			if picks[key] then
				myPicks[key] = picks[key]
			end
		end
	end
	Net.getEvent(Net.Events.PredictState):FireClient(player, { picks = myPicks, tallies = tallies })
end

function PredictService.start()
	Net.getEvent(Net.Events.PredictRequest).OnServerEvent:Connect(function(player: Player)
		sendState(player)
	end)

	Net.getEvent(Net.Events.Predict).OnServerEvent
		:Connect(function(player: Player, payload: unknown)
			if typeof(payload) ~= "table" then
				return
			end
			local key = (payload :: any).key
			local pick = (payload :: any).pick
			if type(key) ~= "string" or type(pick) ~= "string" or pick == "" then
				return
			end
			local home, away = teams(key)
			if pick ~= home and pick ~= away then
				return -- the pick must be one of the fixture's two teams
			end
			local old = DataService.getPrediction(player, key)
			DataService.recordPrediction(player, key, pick) -- records + pays the daily analyst bonus
			local oldSide: string? = if old == home
				then "home"
				elseif old == away then "away"
				else nil
			adjust(key, oldSide, if pick == home then "home" else "away")
			sendState(player) -- reflect the new tally + pick
		end)
end

return PredictService
