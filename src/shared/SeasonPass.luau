--!strict
-- SeasonPass: "Road to the Final" — World Cup 2026 battle pass.
-- Runs June 13 – July 19 (36 days). 40 tiers, free + premium tracks.
-- SeasonXP accrues independently of the normal level-XP so both curves
-- are tunable without affecting each other.
--
-- Progression estimate for a daily questing player:
--   Login: 25 XP/day × 36 = 900
--   Matches (~5/day): ~15 avg XP each × 5 × 36 = 2 700
--   Quest completions (3/day × 50): 150/day × 36 = 5 400
--   Total ≈ 9 000 XP → clears all 40 tiers (8 000 needed) before the Final.

local SeasonPass = {}

SeasonPass.StartDate  = "2026-06-13"
SeasonPass.EndDate    = "2026-07-19"
SeasonPass.TierCount  = 40
SeasonPass.XpPerTier  = 200 -- 8 000 XP to tier 40

-- Season XP granted per game event (on top of normal level XP).
SeasonPass.XpPerGoal  = 10
SeasonPass.XpPerSave  =  8
SeasonPass.XpPerWin   = 30
SeasonPass.XpPerLoss  =  5
SeasonPass.XpPerLogin = 25 -- granted in evaluateDaily
SeasonPass.XpPerQuest = 50 -- granted when a daily quest is completed

-- Reward kinds. "xpboost" extends XpBoostExpiry by `amount` seconds (2× XP while active).
export type RewardKind = "coins" | "title" | "xpboost"
export type Reward = { kind: RewardKind, amount: number?, id: string? }
export type Tier   = { tier: number, free: Reward, premium: Reward }

-- 40-tier table: free track gives coins + milestone titles every 10 tiers;
-- premium track gives larger coins + exclusive titles + timed XP boosts.
SeasonPass.Tiers = {
	{ tier= 1,  free={kind="coins",amount=75},                   premium={kind="coins",amount=200} },
	{ tier= 2,  free={kind="coins",amount=75},                   premium={kind="coins",amount=200} },
	{ tier= 3,  free={kind="coins",amount=75},                   premium={kind="coins",amount=200} },
	{ tier= 4,  free={kind="coins",amount=75},                   premium={kind="coins",amount=250} },
	{ tier= 5,  free={kind="coins",amount=75},                   premium={kind="coins",amount=250} },
	{ tier= 6,  free={kind="coins",amount=75},                   premium={kind="coins",amount=250} },
	{ tier= 7,  free={kind="coins",amount=75},                   premium={kind="coins",amount=300} },
	{ tier= 8,  free={kind="coins",amount=75},                   premium={kind="coins",amount=300} },
	{ tier= 9,  free={kind="coins",amount=75},                   premium={kind="coins",amount=300} },
	{ tier=10,  free={kind="title",id="rookie"},                 premium={kind="xpboost",amount=86400} },
	{ tier=11,  free={kind="coins",amount=100},                  premium={kind="coins",amount=350} },
	{ tier=12,  free={kind="coins",amount=100},                  premium={kind="coins",amount=350} },
	{ tier=13,  free={kind="coins",amount=100},                  premium={kind="coins",amount=350} },
	{ tier=14,  free={kind="coins",amount=100},                  premium={kind="coins",amount=400} },
	{ tier=15,  free={kind="coins",amount=100},                  premium={kind="title",id="contender"} },
	{ tier=16,  free={kind="coins",amount=100},                  premium={kind="coins",amount=400} },
	{ tier=17,  free={kind="coins",amount=100},                  premium={kind="coins",amount=400} },
	{ tier=18,  free={kind="coins",amount=100},                  premium={kind="coins",amount=450} },
	{ tier=19,  free={kind="coins",amount=100},                  premium={kind="coins",amount=450} },
	{ tier=20,  free={kind="title",id="striker"},                premium={kind="xpboost",amount=172800} },
	{ tier=21,  free={kind="coins",amount=150},                  premium={kind="coins",amount=500} },
	{ tier=22,  free={kind="coins",amount=150},                  premium={kind="coins",amount=500} },
	{ tier=23,  free={kind="coins",amount=150},                  premium={kind="coins",amount=550} },
	{ tier=24,  free={kind="coins",amount=150},                  premium={kind="coins",amount=550} },
	{ tier=25,  free={kind="coins",amount=150},                  premium={kind="title",id="playmaker"} },
	{ tier=26,  free={kind="coins",amount=150},                  premium={kind="coins",amount=600} },
	{ tier=27,  free={kind="coins",amount=150},                  premium={kind="coins",amount=600} },
	{ tier=28,  free={kind="coins",amount=150},                  premium={kind="coins",amount=650} },
	{ tier=29,  free={kind="coins",amount=150},                  premium={kind="coins",amount=650} },
	{ tier=30,  free={kind="title",id="captain"},                premium={kind="xpboost",amount=259200} },
	{ tier=31,  free={kind="coins",amount=200},                  premium={kind="coins",amount=700} },
	{ tier=32,  free={kind="coins",amount=200},                  premium={kind="coins",amount=700} },
	{ tier=33,  free={kind="coins",amount=200},                  premium={kind="coins",amount=750} },
	{ tier=34,  free={kind="coins",amount=200},                  premium={kind="coins",amount=750} },
	{ tier=35,  free={kind="coins",amount=200},                  premium={kind="title",id="icon"} },
	{ tier=36,  free={kind="coins",amount=200},                  premium={kind="coins",amount=800} },
	{ tier=37,  free={kind="coins",amount=200},                  premium={kind="coins",amount=850} },
	{ tier=38,  free={kind="coins",amount=200},                  premium={kind="coins",amount=900} },
	{ tier=39,  free={kind="coins",amount=200},                  premium={kind="title",id="finalist"} },
	{ tier=40,  free={kind="title",id="world_cup_legend"},       premium={kind="title",id="world_cup_champion"} },
} :: { Tier }

-- Display labels for title IDs (shown in player billboard + future player card).
SeasonPass.TitleLabels = {
	rookie             = "Rookie",
	contender          = "Contender",
	striker            = "Striker",
	playmaker          = "Playmaker",
	captain            = "Captain",
	icon               = "Icon",
	finalist           = "Finalist",
	world_cup_legend   = "WC Legend",
	world_cup_champion = "WC Champion",
}

-- How many full tiers are unlocked for a given SeasonXP total.
function SeasonPass.tierFromXp(xp: number): number
	return math.min(math.floor(xp / SeasonPass.XpPerTier), SeasonPass.TierCount)
end

-- True while the pass is running (UTC date check).
function SeasonPass.isActive(): boolean
	local today = os.date("!%Y-%m-%d") :: string
	return today >= SeasonPass.StartDate and today <= SeasonPass.EndDate
end

function SeasonPass.getReward(tier: number, track: "free" | "premium"): Reward?
	local t = SeasonPass.Tiers[tier]
	if not t then
		return nil
	end
	return t[track]
end

return SeasonPass
