--!strict
-- Catalog: the cosmetics shop contents, shared so the client can render the
-- shop without a server round-trip. The server is still the only thing that
-- grants ownership or spends coins -- this is just the menu.
--
-- Theme: pick a NATIONAL TEAM to represent. Your equipped nation is your flag
-- AND the team your goals are credited to on the World Cup Standings board.
-- Popular nations are free so anyone can rep their country; the rest are a
-- collection (coin sink). The cosmetic `id` IS the nation id.

local Types = require(script.Parent:WaitForChild("Types"))

export type Cosmetic = {
	id: string,
	name: string,
	emoji: string,
	price: number, -- coins; 0 = free (always owned)
}

local Catalog = {}

-- All 48 qualified nations for the 2026 World Cup, free so anyone can rep their
-- country instantly (the national-pride hook). Ordered by group A–L. The `id`
-- IS the nation id used by WorldCup fixtures + the standings.
Catalog.Cosmetics = {
	-- Group A
	{ id = "mexico", name = "Mexico", emoji = "🇲🇽", price = 0 },
	{ id = "southafrica", name = "South Africa", emoji = "🇿🇦", price = 0 },
	{ id = "korea", name = "South Korea", emoji = "🇰🇷", price = 0 },
	{ id = "czechia", name = "Czechia", emoji = "🇨🇿", price = 0 },
	-- Group B
	{ id = "canada", name = "Canada", emoji = "🇨🇦", price = 0 },
	{ id = "bosnia", name = "Bosnia", emoji = "🇧🇦", price = 0 },
	{ id = "qatar", name = "Qatar", emoji = "🇶🇦", price = 0 },
	{ id = "switzerland", name = "Switzerland", emoji = "🇨🇭", price = 0 },
	-- Group C
	{ id = "brazil", name = "Brazil", emoji = "🇧🇷", price = 0 },
	{ id = "morocco", name = "Morocco", emoji = "🇲🇦", price = 0 },
	{ id = "haiti", name = "Haiti", emoji = "🇭🇹", price = 0 },
	{ id = "scotland", name = "Scotland", emoji = "🏴󠁧󠁢󠁳󠁣󠁴󠁿", price = 0 },
	-- Group D
	{ id = "usa", name = "USA", emoji = "🇺🇸", price = 0 },
	{ id = "paraguay", name = "Paraguay", emoji = "🇵🇾", price = 0 },
	{ id = "australia", name = "Australia", emoji = "🇦🇺", price = 0 },
	{ id = "turkiye", name = "Türkiye", emoji = "🇹🇷", price = 0 },
	-- Group E
	{ id = "germany", name = "Germany", emoji = "🇩🇪", price = 0 },
	{ id = "curacao", name = "Curaçao", emoji = "🇨🇼", price = 0 },
	{ id = "ivorycoast", name = "Ivory Coast", emoji = "🇨🇮", price = 0 },
	{ id = "ecuador", name = "Ecuador", emoji = "🇪🇨", price = 0 },
	-- Group F
	{ id = "netherlands", name = "Netherlands", emoji = "🇳🇱", price = 0 },
	{ id = "japan", name = "Japan", emoji = "🇯🇵", price = 0 },
	{ id = "sweden", name = "Sweden", emoji = "🇸🇪", price = 0 },
	{ id = "tunisia", name = "Tunisia", emoji = "🇹🇳", price = 0 },
	-- Group G
	{ id = "belgium", name = "Belgium", emoji = "🇧🇪", price = 0 },
	{ id = "egypt", name = "Egypt", emoji = "🇪🇬", price = 0 },
	{ id = "iran", name = "Iran", emoji = "🇮🇷", price = 0 },
	{ id = "newzealand", name = "New Zealand", emoji = "🇳🇿", price = 0 },
	-- Group H
	{ id = "spain", name = "Spain", emoji = "🇪🇸", price = 0 },
	{ id = "capeverde", name = "Cape Verde", emoji = "🇨🇻", price = 0 },
	{ id = "saudi", name = "Saudi Arabia", emoji = "🇸🇦", price = 0 },
	{ id = "uruguay", name = "Uruguay", emoji = "🇺🇾", price = 0 },
	-- Group I
	{ id = "france", name = "France", emoji = "🇫🇷", price = 0 },
	{ id = "senegal", name = "Senegal", emoji = "🇸🇳", price = 0 },
	{ id = "iraq", name = "Iraq", emoji = "🇮🇶", price = 0 },
	{ id = "norway", name = "Norway", emoji = "🇳🇴", price = 0 },
	-- Group J
	{ id = "argentina", name = "Argentina", emoji = "🇦🇷", price = 0 },
	{ id = "algeria", name = "Algeria", emoji = "🇩🇿", price = 0 },
	{ id = "austria", name = "Austria", emoji = "🇦🇹", price = 0 },
	{ id = "jordan", name = "Jordan", emoji = "🇯🇴", price = 0 },
	-- Group K
	{ id = "portugal", name = "Portugal", emoji = "🇵🇹", price = 0 },
	{ id = "drcongo", name = "DR Congo", emoji = "🇨🇩", price = 0 },
	{ id = "uzbekistan", name = "Uzbekistan", emoji = "🇺🇿", price = 0 },
	{ id = "colombia", name = "Colombia", emoji = "🇨🇴", price = 0 },
	-- Group L
	{ id = "england", name = "England", emoji = "🇬🇧", price = 0 },
	{ id = "croatia", name = "Croatia", emoji = "🇭🇷", price = 0 },
	{ id = "ghana", name = "Ghana", emoji = "🇬🇭", price = 0 },
	{ id = "panama", name = "Panama", emoji = "🇵🇦", price = 0 },
} :: { Cosmetic }

local byId: { [string]: Cosmetic } = {}
for _, cosmetic in Catalog.Cosmetics do
	byId[cosmetic.id] = cosmetic
end

-- The id every new player starts equipped with (must be a free cosmetic).
Catalog.DefaultEquipped = "usa"

function Catalog.get(id: string): Cosmetic?
	return byId[id]
end

-- True if the player may equip this cosmetic: free items are always owned,
-- otherwise it must be in their OwnedCosmetics set.
function Catalog.isOwned(data: Types.ProfileData, id: string): boolean
	local cosmetic = byId[id]
	if not cosmetic then
		return false
	end
	return cosmetic.price == 0 or data.OwnedCosmetics[id] == true
end

return Catalog
