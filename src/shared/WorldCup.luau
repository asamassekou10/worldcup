--!strict
-- WorldCup: the real-tournament calendar. The `Fixtures` table drives an in-game
-- schedule panel AND the "matchday" spotlight -- nations playing a real fixture
-- today get the 2x World Cup Standings bonus.
--
-- These are the OFFICIAL 2026 World Cup group-stage fixtures (final draw, Dec
-- 2025; all 72 group matches, Jun 11-27), plus knockout-round markers (matchups
-- TBD until groups finish, so those rows carry empty home/away). `home`/`away`
-- are Catalog nation ids; `date` is "YYYY-MM-DD" (UTC).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog"))
local Progression = require(Shared:WaitForChild("Progression"))

local WorldCup = {}

WorldCup.StartDate = "2026-06-11" -- opening match (Estadio Azteca, Mexico City)
WorldCup.EndDate = "2026-07-19" -- final (MetLife Stadium, New Jersey)

export type Fixture = {
	date: string, -- "YYYY-MM-DD"
	stage: string,
	home: string, -- Catalog nation id
	away: string, -- Catalog nation id
	city: string,
}

-- Official 2026 World Cup group stage (all 72 matches).
WorldCup.Fixtures = {
	-- June 11
	{
		date = "2026-06-11",
		stage = "Group A",
		home = "mexico",
		away = "southafrica",
		city = "Mexico City",
	},
	{
		date = "2026-06-11",
		stage = "Group A",
		home = "korea",
		away = "czechia",
		city = "Guadalajara",
	},
	-- June 12
	{ date = "2026-06-12", stage = "Group B", home = "canada", away = "bosnia", city = "Toronto" },
	{
		date = "2026-06-12",
		stage = "Group D",
		home = "usa",
		away = "paraguay",
		city = "Los Angeles",
	},
	-- June 13
	{
		date = "2026-06-13",
		stage = "Group B",
		home = "qatar",
		away = "switzerland",
		city = "San Francisco",
	},
	{
		date = "2026-06-13",
		stage = "Group C",
		home = "brazil",
		away = "morocco",
		city = "New York / NJ",
	},
	{ date = "2026-06-13", stage = "Group C", home = "haiti", away = "scotland", city = "Boston" },
	{
		date = "2026-06-13",
		stage = "Group D",
		home = "australia",
		away = "turkiye",
		city = "Vancouver",
	},
	-- June 14
	{
		date = "2026-06-14",
		stage = "Group E",
		home = "germany",
		away = "curacao",
		city = "Houston",
	},
	{
		date = "2026-06-14",
		stage = "Group F",
		home = "netherlands",
		away = "japan",
		city = "Dallas",
	},
	{
		date = "2026-06-14",
		stage = "Group E",
		home = "ivorycoast",
		away = "ecuador",
		city = "Philadelphia",
	},
	{
		date = "2026-06-14",
		stage = "Group F",
		home = "sweden",
		away = "tunisia",
		city = "Monterrey",
	},
	-- June 15
	{
		date = "2026-06-15",
		stage = "Group H",
		home = "spain",
		away = "capeverde",
		city = "Atlanta",
	},
	{ date = "2026-06-15", stage = "Group G", home = "belgium", away = "egypt", city = "Seattle" },
	{ date = "2026-06-15", stage = "Group H", home = "saudi", away = "uruguay", city = "Miami" },
	{
		date = "2026-06-15",
		stage = "Group G",
		home = "iran",
		away = "newzealand",
		city = "Los Angeles",
	},
	-- June 16
	{
		date = "2026-06-16",
		stage = "Group I",
		home = "france",
		away = "senegal",
		city = "New York / NJ",
	},
	{ date = "2026-06-16", stage = "Group I", home = "iraq", away = "norway", city = "Boston" },
	{
		date = "2026-06-16",
		stage = "Group J",
		home = "argentina",
		away = "algeria",
		city = "Kansas City",
	},
	{
		date = "2026-06-16",
		stage = "Group J",
		home = "austria",
		away = "jordan",
		city = "San Francisco",
	},
	-- June 17
	{
		date = "2026-06-17",
		stage = "Group K",
		home = "portugal",
		away = "drcongo",
		city = "Houston",
	},
	{ date = "2026-06-17", stage = "Group L", home = "england", away = "croatia", city = "Dallas" },
	{ date = "2026-06-17", stage = "Group L", home = "ghana", away = "panama", city = "Toronto" },
	{
		date = "2026-06-17",
		stage = "Group K",
		home = "uzbekistan",
		away = "colombia",
		city = "Mexico City",
	},
	-- June 18
	{
		date = "2026-06-18",
		stage = "Group A",
		home = "czechia",
		away = "southafrica",
		city = "Atlanta",
	},
	{
		date = "2026-06-18",
		stage = "Group B",
		home = "switzerland",
		away = "bosnia",
		city = "Los Angeles",
	},
	{ date = "2026-06-18", stage = "Group B", home = "canada", away = "qatar", city = "Vancouver" },
	{
		date = "2026-06-18",
		stage = "Group A",
		home = "mexico",
		away = "korea",
		city = "Guadalajara",
	},
	-- June 19
	{ date = "2026-06-19", stage = "Group D", home = "usa", away = "australia", city = "Seattle" },
	{
		date = "2026-06-19",
		stage = "Group C",
		home = "scotland",
		away = "morocco",
		city = "Boston",
	},
	{
		date = "2026-06-19",
		stage = "Group C",
		home = "brazil",
		away = "haiti",
		city = "Philadelphia",
	},
	{
		date = "2026-06-19",
		stage = "Group D",
		home = "turkiye",
		away = "paraguay",
		city = "San Francisco",
	},
	-- June 20
	{
		date = "2026-06-20",
		stage = "Group F",
		home = "netherlands",
		away = "sweden",
		city = "Houston",
	},
	{
		date = "2026-06-20",
		stage = "Group E",
		home = "germany",
		away = "ivorycoast",
		city = "Toronto",
	},
	{
		date = "2026-06-20",
		stage = "Group E",
		home = "ecuador",
		away = "curacao",
		city = "Kansas City",
	},
	{
		date = "2026-06-20",
		stage = "Group F",
		home = "tunisia",
		away = "japan",
		city = "Monterrey",
	},
	-- June 21
	{ date = "2026-06-21", stage = "Group H", home = "spain", away = "saudi", city = "Atlanta" },
	{
		date = "2026-06-21",
		stage = "Group G",
		home = "belgium",
		away = "iran",
		city = "Los Angeles",
	},
	{
		date = "2026-06-21",
		stage = "Group H",
		home = "uruguay",
		away = "capeverde",
		city = "Miami",
	},
	{
		date = "2026-06-21",
		stage = "Group G",
		home = "newzealand",
		away = "egypt",
		city = "Vancouver",
	},
	-- June 22
	{
		date = "2026-06-22",
		stage = "Group J",
		home = "argentina",
		away = "austria",
		city = "Dallas",
	},
	{
		date = "2026-06-22",
		stage = "Group I",
		home = "france",
		away = "iraq",
		city = "Philadelphia",
	},
	{
		date = "2026-06-22",
		stage = "Group I",
		home = "norway",
		away = "senegal",
		city = "New York / NJ",
	},
	{
		date = "2026-06-22",
		stage = "Group J",
		home = "jordan",
		away = "algeria",
		city = "San Francisco",
	},
	-- June 23
	{
		date = "2026-06-23",
		stage = "Group K",
		home = "portugal",
		away = "uzbekistan",
		city = "Houston",
	},
	{ date = "2026-06-23", stage = "Group L", home = "england", away = "ghana", city = "Boston" },
	{ date = "2026-06-23", stage = "Group L", home = "panama", away = "croatia", city = "Toronto" },
	{
		date = "2026-06-23",
		stage = "Group K",
		home = "colombia",
		away = "drcongo",
		city = "Guadalajara",
	},
	-- June 24
	{
		date = "2026-06-24",
		stage = "Group B",
		home = "switzerland",
		away = "canada",
		city = "Vancouver",
	},
	{ date = "2026-06-24", stage = "Group B", home = "bosnia", away = "qatar", city = "Seattle" },
	{ date = "2026-06-24", stage = "Group C", home = "scotland", away = "brazil", city = "Miami" },
	{ date = "2026-06-24", stage = "Group C", home = "morocco", away = "haiti", city = "Atlanta" },
	{
		date = "2026-06-24",
		stage = "Group A",
		home = "czechia",
		away = "mexico",
		city = "Mexico City",
	},
	{
		date = "2026-06-24",
		stage = "Group A",
		home = "southafrica",
		away = "korea",
		city = "Monterrey",
	},
	-- June 25
	{
		date = "2026-06-25",
		stage = "Group E",
		home = "ecuador",
		away = "germany",
		city = "New York / NJ",
	},
	{
		date = "2026-06-25",
		stage = "Group E",
		home = "curacao",
		away = "ivorycoast",
		city = "Philadelphia",
	},
	{ date = "2026-06-25", stage = "Group F", home = "japan", away = "sweden", city = "Dallas" },
	{
		date = "2026-06-25",
		stage = "Group F",
		home = "tunisia",
		away = "netherlands",
		city = "Kansas City",
	},
	{
		date = "2026-06-25",
		stage = "Group D",
		home = "turkiye",
		away = "usa",
		city = "Los Angeles",
	},
	{
		date = "2026-06-25",
		stage = "Group D",
		home = "paraguay",
		away = "australia",
		city = "San Francisco",
	},
	-- June 26
	{ date = "2026-06-26", stage = "Group I", home = "norway", away = "france", city = "Boston" },
	{ date = "2026-06-26", stage = "Group I", home = "senegal", away = "iraq", city = "Toronto" },
	{
		date = "2026-06-26",
		stage = "Group H",
		home = "capeverde",
		away = "saudi",
		city = "Houston",
	},
	{
		date = "2026-06-26",
		stage = "Group H",
		home = "uruguay",
		away = "spain",
		city = "Guadalajara",
	},
	{ date = "2026-06-26", stage = "Group G", home = "egypt", away = "iran", city = "Seattle" },
	{
		date = "2026-06-26",
		stage = "Group G",
		home = "newzealand",
		away = "belgium",
		city = "Vancouver",
	},
	-- June 27
	{
		date = "2026-06-27",
		stage = "Group L",
		home = "panama",
		away = "england",
		city = "New York / NJ",
	},
	{
		date = "2026-06-27",
		stage = "Group L",
		home = "croatia",
		away = "ghana",
		city = "Philadelphia",
	},
	{
		date = "2026-06-27",
		stage = "Group K",
		home = "colombia",
		away = "portugal",
		city = "Miami",
	},
	{
		date = "2026-06-27",
		stage = "Group K",
		home = "drcongo",
		away = "uzbekistan",
		city = "Atlanta",
	},
	{
		date = "2026-06-27",
		stage = "Group J",
		home = "algeria",
		away = "austria",
		city = "Kansas City",
	},
	{
		date = "2026-06-27",
		stage = "Group J",
		home = "jordan",
		away = "argentina",
		city = "Dallas",
	},
	-- ===== KNOCKOUTS =====
	-- Round of 32 (the real draw resolved to these 16 ties; updated as the tournament reached the
	-- knockout stage). Later rounds stay as TBD markers until those matchups are decided.
	{
		date = "2026-06-28",
		stage = "🔥 Round of 32",
		home = "southafrica",
		away = "canada",
		city = "Los Angeles",
	},
	{
		date = "2026-06-29",
		stage = "Round of 32",
		home = "brazil",
		away = "japan",
		city = "Houston",
	},
	{
		date = "2026-06-29",
		stage = "Round of 32",
		home = "germany",
		away = "paraguay",
		city = "Boston",
	},
	{
		date = "2026-06-29",
		stage = "Round of 32",
		home = "netherlands",
		away = "morocco",
		city = "Monterrey",
	},
	{
		date = "2026-06-30",
		stage = "Round of 32",
		home = "ivorycoast",
		away = "norway",
		city = "Dallas",
	},
	{
		date = "2026-06-30",
		stage = "Round of 32",
		home = "france",
		away = "sweden",
		city = "New York / NJ",
	},
	{
		date = "2026-06-30",
		stage = "Round of 32",
		home = "mexico",
		away = "ecuador",
		city = "Mexico City",
	},
	{
		date = "2026-07-01",
		stage = "Round of 32",
		home = "england",
		away = "drcongo",
		city = "Atlanta",
	},
	{
		date = "2026-07-01",
		stage = "Round of 32",
		home = "belgium",
		away = "senegal",
		city = "Seattle",
	},
	{
		date = "2026-07-01",
		stage = "Round of 32",
		home = "usa",
		away = "bosnia",
		city = "San Francisco",
	},
	{
		date = "2026-07-02",
		stage = "Round of 32",
		home = "spain",
		away = "austria",
		city = "Los Angeles",
	},
	{
		date = "2026-07-02",
		stage = "Round of 32",
		home = "portugal",
		away = "croatia",
		city = "Toronto",
	},
	{
		date = "2026-07-02",
		stage = "Round of 32",
		home = "switzerland",
		away = "algeria",
		city = "Vancouver",
	},
	{
		date = "2026-07-03",
		stage = "Round of 32",
		home = "australia",
		away = "egypt",
		city = "Dallas",
	},
	{
		date = "2026-07-03",
		stage = "Round of 32",
		home = "argentina",
		away = "capeverde",
		city = "Miami",
	},
	{
		date = "2026-07-03",
		stage = "Round of 32",
		home = "colombia",
		away = "ghana",
		city = "Kansas City",
	},
	{ date = "2026-07-04", stage = "Round of 16", home = "", away = "", city = "" },
	{ date = "2026-07-09", stage = "Quarter-finals", home = "", away = "", city = "" },
	{ date = "2026-07-14", stage = "Semi-finals", home = "", away = "", city = "" },
	{ date = "2026-07-18", stage = "Third-place play-off", home = "", away = "", city = "" },
	{
		date = "2026-07-19",
		stage = "🏆 FINAL — MetLife Stadium",
		home = "",
		away = "",
		city = "",
	},
} :: { Fixture }

-- A stable key for a fixture (used by the prediction booth).
function WorldCup.fixtureKey(f: Fixture): string
	return f.date .. "|" .. f.home .. "|" .. f.away
end

-- Match RESULTS, for settling predictions. Fill in `fixtureKey -> winner nation
-- id` (or "draw") as matches finish -- there's no live results feed, so correct-
-- pick payouts stay dormant until these are provided. Example:
--   ["2026-06-11|mexico|southafrica"] = "mexico",
WorldCup.Results = {} :: { [string]: string }

function WorldCup.resultWinner(key: string): string?
	return WorldCup.Results[key]
end

function WorldCup.todayISO(): string
	return os.date("!%Y-%m-%d")
end

-- A milestone row (knockout round marker) has no teams.
function WorldCup.isMilestone(f: Fixture): boolean
	return f.home == "" or f.away == ""
end

-- A pretty "Flag Name" for a fixture side (falls back to the raw id).
function WorldCup.sideLabel(nationId: string): string
	local nation = Catalog.get(nationId)
	return if nation then nation.emoji .. " " .. nation.name else nationId
end

-- Fixtures on a given date.
function WorldCup.fixturesOn(dateISO: string): { Fixture }
	local out: { Fixture } = {}
	for _, f in WorldCup.Fixtures do
		if f.date == dateISO then
			table.insert(out, f)
		end
	end
	return out
end

-- The set of nation ids playing a real fixture today (milestones excluded).
function WorldCup.todaysNations(): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for _, f in WorldCup.fixturesOn(WorldCup.todayISO()) do
		if not WorldCup.isMilestone(f) then
			set[f.home] = true
			set[f.away] = true
		end
	end
	return set
end

-- Whole days from today until an ISO date (0 = today, 1 = tomorrow, ...).
local function toEpochDay(iso: string): number
	local y, m, d = iso:match("(%d+)-(%d+)-(%d+)")
	local t = os.time({
		year = tonumber(y) or 1970,
		month = tonumber(m) or 1,
		day = tonumber(d) or 1,
		hour = 12,
	})
	return math.floor(t / 86400)
end

function WorldCup.daysUntil(iso: string): number
	return toEpochDay(iso) - toEpochDay(WorldCup.todayISO())
end

-- The next real fixture (today onward) involving `nationId`, or nil.
function WorldCup.nextFixtureFor(nationId: string): Fixture?
	local today = WorldCup.todayISO()
	local best: Fixture? = nil
	for _, f in WorldCup.Fixtures do
		if not WorldCup.isMilestone(f) and f.date >= today then
			if f.home == nationId or f.away == nationId then
				if best == nil or f.date < best.date then
					best = f
				end
			end
		end
	end
	return best
end

-- Lobby line: "🇲🇽 Mexico play 🇿🇦 South Africa — TODAY · 2×!" (nil if none left).
function WorldCup.nextMatchText(nationId: string): string?
	local f = WorldCup.nextFixtureFor(nationId)
	if not f then
		return nil
	end
	local opponent = if f.home == nationId then f.away else f.home
	local days = WorldCup.daysUntil(f.date)
	local when: string
	if days <= 0 then
		when = "TODAY · score 2×!"
	elseif days == 1 then
		when = "tomorrow"
	else
		when = string.format("in %d days", days)
	end
	return string.format(
		"⚽ %s play %s — %s",
		WorldCup.sideLabel(nationId),
		WorldCup.sideLabel(opponent),
		when
	)
end

-- Is this nation featured (2x standings) right now? Today's matchday nations if
-- there are fixtures, otherwise the deterministic daily rotation.
function WorldCup.isFeatured(nationId: string): boolean
	local todays = WorldCup.todaysNations()
	if next(todays) ~= nil then
		return todays[nationId] == true
	end
	return nationId == Progression.featuredNationId()
end

-- Banner text for the lobby (matchday vs. rotation).
function WorldCup.featuredText(): string
	if next(WorldCup.todaysNations()) ~= nil then
		return "⚽ WORLD CUP MATCHDAY — today's nations score 2×!  📅 tap for fixtures"
	end
	local nation = Catalog.get(Progression.featuredNationId())
	if nation then
		return string.format(
			"⭐ Nation of the Day: %s %s — 2×!  📅 tap for fixtures",
			nation.emoji,
			nation.name
		)
	end
	return "📅 World Cup fixtures"
end

-- Fixtures from today onward (sorted by date), capped at `limit`.
function WorldCup.upcoming(limit: number): { Fixture }
	local today = WorldCup.todayISO()
	local out: { Fixture } = {}
	for _, f in WorldCup.Fixtures do
		if f.date >= today then
			table.insert(out, f)
		end
	end
	table.sort(out, function(a, b)
		return a.date < b.date
	end)
	if #out > limit then
		local trimmed: { Fixture } = {}
		for i = 1, limit do
			trimmed[i] = out[i]
		end
		return trimmed
	end
	return out
end

return WorldCup
