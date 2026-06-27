--!strict
-- DailyDeals: a deterministic, daily-rotating coin store (the FOMO hook -- "today only").
-- Three deals are featured each day, shifted by one slot from yesterday's, so the line-up always
-- looks fresh and a player who waited misses a deal. Everything is computed from the day index,
-- so the client and server agree without any live scheduler. The server validates the purchase and
-- applies the effect (DataService.buyDeal); coins are the only currency (all cosmetics are free).

local Progression = require(script.Parent:WaitForChild("Progression"))

local DailyDeals = {}

export type Deal = {
	id: string,
	label: string,
	emoji: string,
	desc: string,
	kind: "pack" | "boost", -- what buying it grants
	amount: number, -- packs (kind="pack") or boost seconds (kind="boost")
	price: number, -- coins
	tag: string?, -- optional badge ("BEST VALUE", "2× XP" ...)
}

-- The full pool the daily line-up is drawn from. Order matters: the day's three deals are a
-- sliding window over this list, so each day drops the oldest and adds the next.
local POOL: { Deal } = {
	{
		id = "pack1",
		label = "Card Pack",
		emoji = "🃏",
		desc = "1 pack · 3 cards",
		kind = "pack",
		amount = 1,
		price = 700,
	},
	{
		id = "boost30",
		label = "XP Boost",
		emoji = "⚡",
		desc = "2× XP for 30 min",
		kind = "boost",
		amount = 30 * 60,
		price = 1000,
	},
	{
		id = "pack3",
		label = "Pack Bundle",
		emoji = "🎁",
		desc = "3 packs · 9 cards",
		kind = "pack",
		amount = 3,
		price = 1800,
		tag = "SAVE 15%",
	},
	{
		id = "boost60",
		label = "Mega XP Boost",
		emoji = "🔥",
		desc = "2× XP for 1 hour",
		kind = "boost",
		amount = 60 * 60,
		price = 1700,
		tag = "2× XP",
	},
	{
		id = "pack5",
		label = "Mega Stash",
		emoji = "📦",
		desc = "5 packs · 15 cards",
		kind = "pack",
		amount = 5,
		price = 2800,
		tag = "BEST VALUE",
	},
}

local FEATURED = 3 -- deals shown per day

-- The three deals featured on a given day (defaults to today). Deterministic: a sliding window
-- over POOL keyed by the day index.
function DailyDeals.dealsFor(dayIndex: number?): { Deal }
	local day = dayIndex or Progression.dayIndex()
	local out: { Deal } = {}
	for i = 0, FEATURED - 1 do
		out[i + 1] = POOL[(day + i) % #POOL + 1]
	end
	return out
end

-- Look up one of today's deals by id (the server uses this to validate a purchase: a deal that
-- isn't featured today can't be bought).
function DailyDeals.todaysDeal(id: string, dayIndex: number?): Deal?
	for _, deal in DailyDeals.dealsFor(dayIndex) do
		if deal.id == id then
			return deal
		end
	end
	return nil
end

-- Unix time (UTC) when today's line-up resets (the FOMO countdown the client renders).
function DailyDeals.resetsAt(dayIndex: number?): number
	local day = dayIndex or Progression.dayIndex()
	return (day + 1) * 86400
end

return DailyDeals
