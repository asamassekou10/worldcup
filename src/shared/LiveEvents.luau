--!strict
-- LiveEvents: a deterministic, always-on event schedule (no live scheduler infra needed -- it's
-- computed from the clock, identical for everyone). There's ALWAYS an event running, so there's
-- always a "play now" reason; weekends get a special boost. The server applies the multipliers in
-- DataService.grantReward/grantPack; the client shows a countdown banner.

local LiveEvents = {}

export type Event = {
	key: string,
	label: string,
	emoji: string,
	coinMult: number,
	xpMult: number,
	packBonus: number,
	endsAt: number, -- unix time (UTC) the event ends
}

local SLOT = 2 * 3600 -- rotating events change every 2 hours
local ROTATION = {
	{
		key = "coins",
		label = "DOUBLE COINS",
		emoji = "⚡",
		coinMult = 2,
		xpMult = 1,
		packBonus = 0,
	},
	{ key = "xp", label = "DOUBLE XP", emoji = "✨", coinMult = 1, xpMult = 2, packBonus = 0 },
	{
		key = "packs",
		label = "PACK FRENZY",
		emoji = "🃏",
		coinMult = 1,
		xpMult = 1,
		packBonus = 1,
	},
}

function LiveEvents.current(now: number?): Event
	local t = now or os.time()
	local d = os.date("!*t", t) :: any -- UTC
	-- Weekend (Sat=7 / Sun=1) -> a persistent World Cup Weekend, double coins, until Monday 00:00.
	if d.wday == 1 or d.wday == 7 then
		local daysToMon = (2 - d.wday) % 7
		if daysToMon == 0 then
			daysToMon = 7
		end
		local midnight = t - (d.hour * 3600 + d.min * 60 + d.sec)
		return {
			key = "weekend",
			label = "WORLD CUP WEEKEND",
			emoji = "🎉",
			coinMult = 2,
			xpMult = 1,
			packBonus = 0,
			endsAt = midnight + daysToMon * 86400,
		}
	end
	local slot = math.floor(t / SLOT)
	local e = ROTATION[slot % #ROTATION + 1]
	return {
		key = e.key,
		label = e.label,
		emoji = e.emoji,
		coinMult = e.coinMult,
		xpMult = e.xpMult,
		packBonus = e.packBonus,
		endsAt = (slot + 1) * SLOT,
	}
end

return LiveEvents
