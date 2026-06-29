--!strict
-- CardBank: the collectible "World Cup cards" pool. Players earn packs from playing, open them
-- for cards across four rarities, and complete the set for a big reward. Collection is one of the
-- strongest retention drivers on Roblox -- a reason to keep playing + come back.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local CardBank = {}

-- `image` (optional) = a custom card face (rbxassetid). When set, the UI shows the picture; otherwise
-- it falls back to the emoji in `name`.
export type Card = { id: string, name: string, rarity: string, image: string? }

-- Real player cards (Panini-style art). `image` is the uploaded card face.
CardBank.Cards = {
	-- Common
	{
		id = "jsanchez",
		name = "J. Sánchez",
		rarity = "common",
		image = "rbxassetid://124121751932020",
	},
	{ id = "endrick", name = "Endrick", rarity = "common", image = "rbxassetid://75982793168422" },
	{ id = "barcola", name = "Barcola", rarity = "common", image = "rbxassetid://105312337174258" },
	{
		id = "guler",
		name = "Arda Güler",
		rarity = "common",
		image = "rbxassetid://88674121143390",
	},
	{
		id = "aflores",
		name = "A. Flores",
		rarity = "common",
		image = "rbxassetid://111232938371833",
	},
	{
		id = "lothar",
		name = "Lothar '06",
		rarity = "common",
		image = "rbxassetid://86563612568790",
	},
	-- Rare
	{ id = "mahrez", name = "Mahrez", rarity = "rare", image = "rbxassetid://133502500081434" },
	{
		id = "doue",
		name = "Désiré Doué",
		rarity = "rare",
		image = "rbxassetid://92755841316363",
	},
	{ id = "palmer", name = "Cole Palmer", rarity = "rare", image = "rbxassetid://95310436287327" },
	{ id = "saka", name = "Saka", rarity = "rare", image = "rbxassetid://122067098059716" },
	{ id = "bsilva", name = "B. Silva", rarity = "rare", image = "rbxassetid://98625349544542" },
	{ id = "rabiot", name = "Rabiot", rarity = "rare", image = "rbxassetid://130199718830552" },
	-- Epic
	{
		id = "vinicius",
		name = "Vinícius Jr",
		rarity = "epic",
		image = "rbxassetid://70516307682082",
	},
	{
		id = "bellingham",
		name = "Bellingham",
		rarity = "epic",
		image = "rbxassetid://104346068882335",
	},
	{
		id = "brunof",
		name = "B. Fernandes",
		rarity = "epic",
		image = "rbxassetid://86873227056935",
	},
	{
		id = "dibu",
		name = "Dibu Martínez",
		rarity = "epic",
		image = "rbxassetid://81951799268689",
	},
	-- Legendary (the chase cards)
	{ id = "pele", name = "Pelé", rarity = "legendary", image = "rbxassetid://99401503798170" },
	{ id = "goat", name = "Messi", rarity = "legendary", image = Config.Icons.StickerMessi },
	{ id = "maestro", name = "Ronaldo", rarity = "legendary", image = Config.Icons.StickerRonaldo },
	{
		id = "worldchamp",
		name = "Mbappé",
		rarity = "legendary",
		image = Config.Icons.StickerMbappe,
	},
	{ id = "neymar", name = "Neymar", rarity = "legendary", image = Config.Icons.StickerNeymar },
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
