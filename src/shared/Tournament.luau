--!strict
-- Tournament: the shared rules for the WEEKLY tournament (the recurring competitive hook). Players
-- earn Tournament Points (= the XP they earn that week, so every mode feeds it) into a week-keyed
-- OrderedDataStore. When the week rolls over, the previous week's standings are frozen; each player
-- reads them on their next join and claims their own rank prize once (gated by their session-locked
-- profile -- no finalizer/lock needed, no double-pay). Client + server share this so the prize
-- ladder and the countdown always agree.

local Tournament = {}

local WEEK = 604800 -- 7 * 24 * 3600 seconds

-- The current week index (weeks since the Unix epoch). The store name is keyed to this, so a new
-- week is automatically a fresh, empty board.
function Tournament.weekId(now: number?): number
	return math.floor((now or os.time()) / WEEK)
end

-- Unix time (UTC) the current week ends / the next one begins (the countdown the client renders).
function Tournament.resetsAt(now: number?): number
	return (Tournament.weekId(now) + 1) * WEEK
end

function Tournament.storeName(week: number): string
	return "Tournament_w" .. week
end

export type Prize = { coins: number, packs: number }

-- Coin (+ card pack) prize by final rank. Top 3 also get packs. Returns nil outside the paid ranks.
local PRIZES: { Prize } = {
	{ coins = 15000, packs = 3 }, -- 🥇
	{ coins = 9000, packs = 2 }, -- 🥈
	{ coins = 6000, packs = 1 }, -- 🥉
	{ coins = 3000, packs = 0 }, -- 4th
	{ coins = 3000, packs = 0 }, -- 5th
	{ coins = 1500, packs = 0 }, -- 6th
	{ coins = 1500, packs = 0 }, -- 7th
	{ coins = 1500, packs = 0 }, -- 8th
	{ coins = 1500, packs = 0 }, -- 9th
	{ coins = 1500, packs = 0 }, -- 10th
}

Tournament.PaidRanks = #PRIZES

function Tournament.prizeForRank(rank: number): Prize?
	return PRIZES[rank]
end

-- A compact prize ladder for the client to render ("🥇 #1 — 15,000 🪙 +3🃏").
function Tournament.prizeLadder(): { { rank: number, coins: number, packs: number } }
	local out = {}
	for rank, p in PRIZES do
		out[rank] = { rank = rank, coins = p.coins, packs = p.packs }
	end
	return out
end

return Tournament
