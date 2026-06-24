--!strict
-- ChoiceBank: the "Would You Rather" dilemmas for the Choices runner -- ALL soccer / World
-- Cup themed, with plenty of funny ones. Every gate that isn't a scored trivia gate pulls
-- a dilemma from here. Both options are always valid; the fun is the GLOBAL vote split
-- shown after you pick -- and, on the iconic ones, the door you choose MORPHS your avatar
-- and adds that "legend" to your permanent collection.
--
-- Each dilemma has a STABLE `id` -- the server tallies votes per id in a DataStore, so the
-- "62% chose X" numbers persist and grow across every server. Never renumber an existing
-- id (it would orphan its votes); add new ones at the end.
--
-- Optional per-choice fields:
--   image  -- rbxassetid:// picture shown on the door (nil = text only).
--   audio  -- rbxassetid:// pre-rendered narration clip (DORMANT: voice is skipped for now).
--   morph  -- how the door changes your avatar. `bodyColor` is the reliable approximation;
--             shirt/pants/accessories are optional real catalog ids to make a kit exact.
--   legend -- a stable id from ChoiceBank.Legends; picking this door permanently unlocks
--             that legend in your "Become a Legend" collection.

export type Morph = {
	bodyColor: Color3?,
	shirt: number?,
	pants: number?,
	accessories: { number }?,
}

-- An EFFECT a door applies to you/your world when you run through it. All optional; mix
-- freely. Body/gameplay effects are server-applied (everyone sees them); `weather`/`sound`
-- are per-player client effects. They persist for the rest of the run (same category
-- replaces) and reset at the finish. See ChoiceBank.AURAS / WEATHERS for valid keys.
export type Effect = {
	walkSpeed: number?, -- multiplier on the run speed (1.5 = faster, 0.6 = slower)
	jump: number?, -- absolute JumpPower (e.g. 90 = moon-jump)
	scale: number?, -- body size multiplier (0.5 tiny .. 1.6 giant)
	invisible: boolean?, -- go see-through
	aura: string?, -- particle aura: "fire"|"ice"|"sparkle"|"wind"|"thunder"
	weather: string?, -- per-player weather: "rain"|"heat"|"snow"|"storm"|"fog"|"night"
	sound: string?, -- a one-shot rbxassetid:// clip
	costume: string?, -- a full welded costume that hides your body (e.g. "mascot")
}

export type Choice = {
	text: string,
	image: string?,
	audio: string?,
	morph: Morph?,
	legend: string?,
	effect: Effect?,
}

export type Dilemma = {
	id: string,
	a: Choice,
	b: Choice,
}

-- National / kit colour approximations (used as body recolours).
local ARG = Color3.fromRGB(108, 192, 230)
local POR = Color3.fromRGB(200, 45, 50)
local BRA = Color3.fromRGB(245, 212, 52)
local FRA = Color3.fromRGB(42, 64, 156)
local ENG = Color3.fromRGB(238, 238, 240)
local ESP = Color3.fromRGB(196, 40, 46)
local NOR = Color3.fromRGB(120, 170, 220)
local REF = Color3.fromRGB(28, 28, 32)
local GREEN = Color3.fromRGB(70, 175, 80)
local GOLD = Color3.fromRGB(225, 180, 55)

local ChoiceBank = {}

-- The collectible legends (id -> display name). Total = the collection size shown as
-- "X / Y legends". Add new ones here when you add new morph choices.
ChoiceBank.Legends = {
	messi = "Messi 🐐",
	ronaldo = "Ronaldo 🚀",
	brazil = "Brazil 🇧🇷",
	france = "France 🇫🇷",
	argentina = "Argentina 🇦🇷",
	england = "England 🏴",
	spain = "Spain 🇪🇸",
	mbappe = "Mbappé ⚡",
	haaland = "Haaland 🤖",
	pele = "Pelé 👑",
	striker = "Striker 🎯",
	keeper = "Keeper 🧤",
	referee = "Referee 🟥",
	mascot = "Mascot 🦁",
	goldenboot = "Golden Boot 👟",
	goldenglove = "Golden Glove 🧤",
	maradona = "Maradona 🇦🇷",
} :: { [string]: string }

-- Swatch colour per legend (matches the body-recolour morph) + a stable display order,
-- both for the collection panel.
ChoiceBank.LegendColor = {
	messi = ARG,
	ronaldo = POR,
	brazil = BRA,
	france = FRA,
	argentina = ARG,
	england = ENG,
	spain = ESP,
	mbappe = FRA,
	haaland = NOR,
	pele = BRA,
	striker = GOLD,
	keeper = GREEN,
	referee = REF,
	mascot = GREEN,
	goldenboot = GOLD,
	goldenglove = GREEN,
	maradona = ARG,
} :: { [string]: Color3 }

ChoiceBank.LegendOrder = {
	"messi",
	"ronaldo",
	"brazil",
	"france",
	"argentina",
	"england",
	"spain",
	"mbappe",
	"haaland",
	"pele",
	"striker",
	"keeper",
	"referee",
	"mascot",
	"goldenboot",
	"goldenglove",
	"maradona",
} :: { string }

function ChoiceBank.legendCount(): number
	return #ChoiceBank.LegendOrder
end

ChoiceBank.Dilemmas = {
	{
		id = "messi_ronaldo",
		a = {
			text = "Be MESSI 🐐",
			morph = { shirt = 7233856275, pants = 197796805 },
			legend = "messi",
			effect = { walkSpeed = 1.25 },
		},
		b = {
			text = "Be RONALDO 🚀",
			morph = { shirt = 11398107072, pants = 11634680098 },
			legend = "ronaldo",
			effect = { jump = 92, aura = "thunder" },
		},
	},
	{
		id = "brazil_france",
		a = {
			text = "Win it with BRAZIL",
			morph = { bodyColor = BRA },
			legend = "brazil",
			effect = { aura = "sparkle" },
		},
		b = {
			text = "Win it with FRANCE",
			morph = { bodyColor = FRA },
			legend = "france",
			effect = { walkSpeed = 1.2 },
		},
	},
	{
		id = "argentina_brazil",
		a = {
			text = "ARGENTINA 🇦🇷",
			morph = { bodyColor = ARG },
			legend = "argentina",
			effect = { walkSpeed = 1.2 },
		},
		b = {
			text = "BRAZIL 🇧🇷",
			morph = { bodyColor = BRA },
			legend = "brazil",
			effect = { aura = "sparkle" },
		},
	},
	{
		id = "england_spain",
		a = {
			text = "ENGLAND 🏴",
			morph = { bodyColor = ENG },
			legend = "england",
			effect = { weather = "rain" },
		},
		b = {
			text = "SPAIN 🇪🇸",
			morph = { bodyColor = ESP },
			legend = "spain",
			effect = { weather = "heat" },
		},
	},
	{
		id = "mbappe_haaland",
		a = {
			text = "MBAPPÉ's SPEED",
			morph = { shirt = 11623961708, pants = 11634669895 },
			legend = "mbappe",
			effect = { walkSpeed = 1.5, aura = "wind" },
		},
		b = {
			text = "HAALAND's POWER",
			morph = { shirt = 10102720676, pants = 10422270544 },
			legend = "haaland",
			effect = { scale = 1.25, aura = "fire" },
		},
	},
	{
		id = "messi_pele",
		a = {
			text = "Modern MESSI",
			morph = { shirt = 7233856275, pants = 197796805 },
			legend = "messi",
			effect = { walkSpeed = 1.25 },
		},
		b = {
			text = "Classic PELÉ",
			morph = { shirt = 4546078841, pants = 196955749 },
			legend = "pele",
			effect = { aura = "sparkle" },
		},
	},
	{
		id = "striker_keeper",
		a = {
			text = "Be a GOAL MACHINE",
			morph = { bodyColor = GOLD },
			legend = "striker",
			effect = { aura = "fire" },
		},
		b = {
			text = "Be a WALL in goal",
			morph = { bodyColor = GREEN },
			legend = "keeper",
			effect = { aura = "ice" },
		},
	},
	{
		id = "ref_or_var",
		a = {
			text = "Be the REFEREE 🟥",
			morph = { shirt = 5968621570 },
			legend = "referee",
			effect = { aura = "sparkle" },
		},
		b = { text = "Run the VAR booth 📺", effect = { weather = "night" } },
	},
	{
		id = "mascot_anthem",
		a = {
			text = "Be the team MASCOT 🦁",
			morph = { bodyColor = GREEN },
			legend = "mascot",
			effect = { costume = "mascot" },
		},
		b = {
			text = "Sing the loudest ANTHEM 🎤",
			effect = { sound = "rbxassetid://1423619896" },
		},
	},
	{
		id = "golden_boot_glove",
		a = {
			text = "Win the GOLDEN BOOT 👟",
			morph = { bodyColor = GOLD },
			legend = "goldenboot",
			effect = { aura = "fire" },
		},
		b = {
			text = "Win the GOLDEN GLOVE 🧤",
			morph = { bodyColor = GREEN },
			legend = "goldenglove",
			effect = { aura = "ice" },
		},
	},
	{
		id = "captain_topscorer",
		a = { text = "Wear the CAPTAIN armband", effect = { walkSpeed = 1.1 } },
		b = {
			text = "Win the GOLDEN BOOT",
			morph = { bodyColor = GOLD },
			legend = "goldenboot",
			effect = { aura = "fire" },
		},
	},
	{
		id = "worldcup_ucl",
		a = { text = "Win the WORLD CUP 🏆", effect = { aura = "sparkle" } },
		b = { text = "Win the CHAMPIONS LEAGUE ⭐", effect = { weather = "night" } },
	},
	{
		id = "goldenball_cup",
		a = { text = "Best player, no trophy 🥇", effect = { aura = "sparkle" } },
		b = { text = "Lift the actual CUP 🏆", effect = { jump = 90 } },
	},
	{
		id = "penalty_freekick",
		a = { text = "NEVER miss a PENALTY", effect = { aura = "fire" } },
		b = { text = "NEVER miss a FREE KICK", effect = { jump = 85 } },
	},
	{
		id = "hattrick_cleansheet",
		a = { text = "HAT-TRICK every game", effect = { aura = "fire" } },
		b = { text = "CLEAN SHEET every game", effect = { aura = "ice" } },
	},
	{
		id = "nutmeg_bicycle",
		a = { text = "Nutmeg everyone 🥜", effect = { aura = "sparkle" } },
		b = { text = "Score a BICYCLE kick 🚲", effect = { jump = 90 } },
	},
	{
		id = "injury_time_never",
		a = { text = "Always score in INJURY TIME ⏱️", effect = { walkSpeed = 1.3 } },
		b = { text = "NEVER get injured 🩹", effect = { scale = 1.1 } },
	},
	{
		id = "celebration",
		a = { text = "Celebrate with a BACKFLIP 🤸", effect = { jump = 95 } },
		b = { text = "Celebrate by CRYING on the grass 😭", effect = { weather = "rain" } },
	},
	{
		id = "smell_squeak",
		a = { text = "Swap shirts… it SMELLS forever 👃", effect = { weather = "fog" } },
		b = { text = "Boots that SQUEAK every step 🥾", effect = { jump = 85 } },
	},
	{
		id = "rain_heat",
		a = { text = "Play in pouring RAIN 🌧️", effect = { weather = "rain" } },
		b = { text = "Play in 40°C HEAT 🥵", effect = { weather = "heat" } },
	},
	{
		id = "fans_silence",
		a = { text = "Packed ROARING stadium 📣", effect = { sound = "rbxassetid://1423619896" } },
		b = { text = "Eerie total SILENCE 🤫", effect = { weather = "fog" } },
	},
	{
		id = "own_goal_winner",
		a = { text = "Score the WINNER", effect = { aura = "fire" } },
		b = { text = "Never score an OWN GOAL again 🙃", effect = { invisible = true } },
	},
	{
		id = "coach_player",
		a = { text = "Manage the DREAM TEAM 📋", effect = { weather = "night" } },
		b = { text = "PLAY for a good team ⚽", effect = { walkSpeed = 1.2 } },
	},
	{
		id = "legend_now",
		a = { text = "Be a 90s LEGEND 📼", effect = { weather = "night" } },
		b = { text = "Be today's BIGGEST STAR 🌟", effect = { aura = "sparkle" } },
	},
	{
		id = "tiny_giant",
		a = { text = "Tiny unstoppable DRIBBLER 🐜", effect = { scale = 0.55, walkSpeed = 1.4 } },
		b = { text = "Giant HEADER machine 🦒", effect = { scale = 1.5 } },
	},
	{
		id = "boots_jersey",
		a = { text = "Keep every JERSEY you swap 👕", effect = { aura = "sparkle" } },
		b = { text = "Boots that never wear out 👟", effect = { walkSpeed = 1.2 } },
	},
	{
		id = "maradona_pele",
		a = {
			text = "Be MARADONA 🇦🇷",
			morph = { shirt = 492150155, pants = 492079501 },
			legend = "maradona",
			effect = { walkSpeed = 1.25 },
		},
		b = {
			text = "Be PELÉ 👑",
			morph = { shirt = 4546078841, pants = 196955749 },
			legend = "pele",
			effect = { aura = "sparkle" },
		},
	},
} :: { Dilemma }

-- Deal a shuffled list of `count` distinct dilemmas (so a single run never repeats one).
-- A deterministic "Today's featured" set of n dilemmas for a given day -- same for everyone,
-- every server, all day (seeded by the day index), so it's a shared daily talking point.
function ChoiceBank.dailyPack(day: number, n: number): { Dilemma }
	local pool = table.clone(ChoiceBank.Dilemmas)
	local rng = Random.new(day * 2654435761 + 11)
	for i = #pool, 2, -1 do
		local j = rng:NextInteger(1, i)
		pool[i], pool[j] = pool[j], pool[i]
	end
	local out = {}
	for i = 1, math.min(n, #pool) do
		out[i] = pool[i]
	end
	return out
end

-- Deal `count` distinct shuffled dilemmas for a run. Any in `guaranteed` (the daily pack) are
-- folded in first so they always appear, then positions are reshuffled so they're not clumped.
function ChoiceBank.deal(count: number, guaranteed: { Dilemma }?): { Dilemma }
	local pool = table.clone(ChoiceBank.Dilemmas)
	for i = #pool, 2, -1 do
		local j = math.random(i)
		pool[i], pool[j] = pool[j], pool[i]
	end
	local out: { Dilemma } = {}
	local used: { [string]: boolean } = {}
	if guaranteed then
		for _, d in guaranteed do
			if #out >= count then
				break
			end
			if not used[d.id] then
				used[d.id] = true
				out[#out + 1] = d
			end
		end
	end
	for _, d in pool do
		if #out >= count then
			break
		end
		if not used[d.id] then
			used[d.id] = true
			out[#out + 1] = d
		end
	end
	for i = #out, 2, -1 do
		local j = math.random(i)
		out[i], out[j] = out[j], out[i]
	end
	return out
end

return ChoiceBank
