--!strict
-- Progression: the retention math, shared so client and server agree -- the XP
-- curve + level, the daily-quest definitions, and the login-streak reward. Pure
-- functions only (no Instances), so it's safe on both sides.

local Progression = {}

-- ===== XP / Levels =====
-- Cost to go from level L to L+1 is 100*L, so the total XP to *reach* level L is
-- 50*(L-1)*L: level 2 at 100, 3 at 300, 4 at 600, ... a gentle, legible curve.
Progression.XpPerGoal = 12
Progression.XpPerSave = 6
Progression.XpPerWin = 50
Progression.XpPerLoss = 12

function Progression.levelFloorXp(level: number): number
	return 50 * (level - 1) * level
end

function Progression.levelFromXp(xp: number): number
	local level = 1
	while Progression.levelFloorXp(level + 1) <= xp do
		level += 1
	end
	return level
end

-- Progress within the current level: (xpIntoLevel, xpThisLevelNeeds, fraction).
function Progression.levelProgress(xp: number): (number, number, number)
	local level = Progression.levelFromXp(xp)
	local floor = Progression.levelFloorXp(level)
	local need = Progression.levelFloorXp(level + 1) - floor
	local into = xp - floor
	return into, need, math.clamp(into / math.max(need, 1), 0, 1)
end

-- ===== Daily login streak =====
-- 50 coins on day 1, +25 per consecutive day, capped at day 7 (200).
function Progression.dailyReward(streak: number): number
	return 50 + math.min(math.max(streak, 1) - 1, 6) * 25
end

-- The current day bucket (UTC). Used for streak + quest resets.
function Progression.dayIndex(): number
	return math.floor(os.time() / 86400)
end

-- ===== Daily quests =====
-- `stat` is the per-match counter it tracks; completing it pays coins + XP.
export type Quest = {
	id: string,
	stat: "goals" | "wins" | "saves",
	target: number,
	coins: number,
	xp: number,
	label: string, -- a %d for the target
}

Progression.Quests = {
	{ id = "goals", stat = "goals", target = 5, coins = 60, xp = 40, label = "Score %d goals" },
	{ id = "wins", stat = "wins", target = 2, coins = 90, xp = 60, label = "Win %d matches" },
	{ id = "saves", stat = "saves", target = 3, coins = 45, xp = 30, label = "Make %d saves" },
} :: { Quest }

-- ===== Live-ops (Phase 4): Nation of the Day =====
-- A deterministic daily rotation (no scheduler needed). Goals scored by players
-- repping the featured nation count double toward the World Cup standings -- a
-- rotating FOMO spotlight that rewards switching to today's country.
Progression.FeaturedRotation = {
	"brazil",
	"argentina",
	"france",
	"england",
	"spain",
	"germany",
	"portugal",
	"usa",
	"mexico",
	"netherlands",
	"japan",
	"canada",
}
Progression.FeaturedMultiplier = 2

function Progression.featuredNationId(): string
	local i = Progression.dayIndex() % #Progression.FeaturedRotation
	return Progression.FeaturedRotation[i + 1]
end

-- Double-XP weekends (Sat/Sun, UTC) -- a recurring reason to grind on weekends.
Progression.WeekendXpMultiplier = 2
function Progression.isBonusWeekend(): boolean
	local wday = os.date("!*t").wday -- 1 = Sunday ... 7 = Saturday
	return wday == 1 or wday == 7
end

return Progression
