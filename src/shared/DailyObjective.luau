--!strict
-- DailyObjective: ONE big, session-spanning goal per day (distinct from the per-match daily quests).
-- It's deterministic from the day index (same for everyone, no scheduler) and rotates type daily so
-- it stays fresh. Progress is tracked server-side and pays a chunky coin + pack reward once. The
-- client shows it as a progress banner -- a clear "play a full session today" target.

local Progression = require(script.Parent:WaitForChild("Progression"))

local DailyObjective = {}

export type Objective = {
	kind: "xp" | "goals" | "packs", -- which counter advances it (the server bumps the matching one)
	label: string,
	emoji: string,
	target: number,
	coins: number,
	packs: number,
}

local POOL: { Objective } = {
	{
		kind = "xp",
		label = "Earn %d XP today",
		emoji = "🎯",
		target = 600,
		coins = 1200,
		packs = 1,
	},
	{
		kind = "goals",
		label = "Score %d goals today",
		emoji = "⚽",
		target = 6,
		coins = 1200,
		packs = 1,
	},
	{
		kind = "packs",
		label = "Open %d card packs today",
		emoji = "🃏",
		target = 3,
		coins = 1000,
		packs = 1,
	},
}

-- Today's objective (defaults to the current day). Deterministic rotation through the pool.
function DailyObjective.today(dayIndex: number?): Objective
	local day = dayIndex or Progression.dayIndex()
	return POOL[day % #POOL + 1]
end

-- The label with its target filled in ("Earn 600 XP today").
function DailyObjective.text(obj: Objective): string
	return string.format(obj.label, obj.target)
end

return DailyObjective
