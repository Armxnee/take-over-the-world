--!strict
-- (Take Over the World!: Robux bundles and coin packs for the item shop, 2026-11-07.)
-- A bundle is several pieces of gear (Data/Gear) for one Robux price; a coin pack adds coins. Both are
-- developer products (Data/Products: "bundle_<id>" granting "bundle:<id>", "coins_<id>" granting
-- "coins:<n>"); server/Purchases.grant stores what they give. A bundle item the player owns already
-- comes back as coins (its item shop price).
local Bundles = {}

Bundles.LIST = {
	{
		id = "royal",
		name = "Royal Bundle",
		rarity = "legendary",
		robux = 499,
		items = { "hat_steel_gold", "boat_gold", "nuke_gold", "missile_gold" },
	},
	{
		id = "admiral",
		name = "Admiral Bundle",
		rarity = "epic",
		robux = 249,
		items = { "hat_officer_navy", "boat_stealth", "nuke_black_ops" },
	},
	{
		id = "winter",
		name = "Winter War Bundle",
		rarity = "rare",
		robux = 129,
		items = { "hat_combat_arctic", "boat_arctic", "missile_ice" },
	},
	{
		id = "frontline",
		name = "Frontline Bundle",
		rarity = "common",
		robux = 99,
		items = { "hat_combat_helmet", "boat_navy_grey", "missile_red_streak", "nuke_hazard" },
	},
}

Bundles.COINS = {
	{ id = "s", coins = 2500, robux = 49 },
	{ id = "m", coins = 7000, robux = 129, tag = "POPULAR" },
	{ id = "l", coins = 16000, robux = 279 },
	{ id = "xl", coins = 40000, robux = 599, tag = "BEST VALUE" },
}

local by_id: { [string]: any } = {}
for _, b in Bundles.LIST do
	by_id[b.id] = b
end

function Bundles.get(id: any): any?
	return if type(id) == "string" then by_id[id] else nil
end

return Bundles
