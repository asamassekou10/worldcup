--!strict
-- CardBank: the collectible "World Cup cards" pool. Players earn packs from playing, open them
-- for cards across four rarities, and complete the set for a big reward. Collection is one of the
-- strongest retention drivers on Roblox -- a reason to keep playing + come back.

local CardBank = {}

export type Card = { id: string, name: string, rarity: string }

CardBank.Cards = {
	-- Common
	{ id = "gk", name = "🧤 Keeper", rarity = "common" },
	{ id = "def", name = "🛡️ Defender", rarity = "common" },
	{ id = "mid", name = "⚙️ Midfielder", rarity = "common" },
	{ id = "str", name = "⚡ Striker", rarity = "common" },
	{ id = "wing", name = "🏃 Winger", rarity = "common" },
	{ id = "cap", name = "©️ Captain", rarity = "common" },
	{ id = "sub", name = "🔁 Super Sub", rarity = "common" },
	{ id = "fan", name = "📣 Ultra Fan", rarity = "common" },
	-- Rare (nations)
	{ id = "brazil", name = "🇧🇷 Brazil", rarity = "rare" },
	{ id = "argentina", name = "🇦🇷 Argentina", rarity = "rare" },
	{ id = "france", name = "🇫🇷 France", rarity = "rare" },
	{ id = "spain", name = "🇪🇸 Spain", rarity = "rare" },
	{ id = "england", name = "🏴 England", rarity = "rare" },
	{ id = "germany", name = "🇩🇪 Germany", rarity = "rare" },
	-- Epic (skills)
	{ id = "goldenboot", name = "🥇 Golden Boot", rarity = "epic" },
	{ id = "hattrick", name = "🎩 Hat-Trick", rarity = "epic" },
	{ id = "panenka", name = "🥄 Panenka", rarity = "epic" },
	{ id = "bicycle", name = "🚲 Bicycle Kick", rarity = "epic" },
	-- Legendary (icons)
	{ id = "goat", name = "🐐 The GOAT", rarity = "legendary" },
	{ id = "maestro", name = "🎼 The Maestro", rarity = "legendary" },
	{ id = "worldchamp", name = "🏆 World Champion", rarity = "legendary" },
} :: { Card }

CardBank.RarityOrder = { common = 1, rare = 2, epic = 3, legendary = 4 }
CardBank.RarityColor = {
	common = Color3.fromRGB(150, 160, 180),
	rare = Color3.fromRGB(70, 160, 255),
	epic = Color3.fromRGB(190, 100, 255),
	legendary = Color3.fromRGB(255, 195, 60),
}
CardBank.RarityLabel = { common = "Common", rare = "Rare", epic = "Epic", legendary = "Legendary" }

local PACK_WEIGHTS = { common = 58, rare = 28, epic = 11, legendary = 3 }

local byId: { [string]: Card } = {}
local byRarity: { [string]: { Card } } = {}
for _, c in CardBank.Cards do
	byId[c.id] = c
	byRarity[c.rarity] = byRarity[c.rarity] or {}
	table.insert(byRarity[c.rarity], c)
end

function CardBank.byId(id: string): Card?
	return byId[id]
end

function CardBank.count(): number
	return #CardBank.Cards
end

-- Roll a single card id, weighted by rarity (then uniform within the rarity).
function CardBank.rollOne(): string
	local total = 0
	for _, w in PACK_WEIGHTS do
		total += w
	end
	local r = math.random() * total
	local picked = "common"
	for rarity, w in PACK_WEIGHTS do
		r -= w
		if r <= 0 then
			picked = rarity
			break
		end
	end
	local pool = byRarity[picked]
	if not pool or #pool == 0 then
		pool = CardBank.Cards
	end
	return pool[math.random(#pool)].id
end

return CardBank
