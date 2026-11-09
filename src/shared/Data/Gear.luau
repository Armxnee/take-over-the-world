--!strict
-- (Take Over the World!: item shop gear, 2026-11-06; Countryball gear from the user's reference
-- sheets 2026-11-08.)
-- Countryball gear (pixel art drawn on the ball: Countryball.ball_content): hats, beards and
-- moustaches, glasses (Data/GearSprites, built by tools/build_gear.py) and unit skins (a colour the
-- boats, nukes or missiles wear instead of the owner's: Map/UnitLayer). Sold in the item shop
-- (Data/ItemShop) and given by crates. Data/Cosmetics resolves them by id like any item.
--   hat / beard / glasses: rows (top to bottom; "." = clear), x / y = where row 1's first character
--         lands on the 32 x 32 ball (Countryball.G); hats and beards fit the ball's shape
--   boat / nuke / missile: color = {r, g, b}
local GearSprites = require(script.Parent.GearSprites)

local Gear = {}

Gear.KINDS = { "hat", "beard", "glasses", "boat", "nuke", "missile", "warship" }
--- the kinds worn on the Countryball, in the order they are drawn
Gear.BALL_KINDS = { "beard", "glasses", "hat" }
Gear.KIND_NAMES = {
	hat = "Hat",
	beard = "Beard",
	glasses = "Glasses",
	boat = "Boat Skin",
	nuke = "Nuke Skin",
	missile = "Missile Skin",
	warship = "Warship Skin",
}

Gear.items = {
	-- boat skins
	{ id = "boat_navy_grey", kind = "boat", name = "Navy Grey Fleet", rarity = "common", color = { 128, 138, 150 } },
	{ id = "boat_arctic", kind = "boat", name = "Arctic Camo Fleet", rarity = "common", color = { 214, 232, 246 } },
	{ id = "boat_crimson", kind = "boat", name = "Crimson Fleet", rarity = "rare", color = { 200, 36, 48 } },
	{ id = "boat_stealth", kind = "boat", name = "Stealth Fleet", rarity = "epic", color = { 44, 48, 58 } },
	{ id = "boat_gold", kind = "boat", name = "Golden Fleet", rarity = "legendary", color = { 255, 196, 40 } },
	-- (2026-11-08: more boat / nuke / missile skins, so the item shop has its own beside the bundles)
	{ id = "boat_jungle", kind = "boat", name = "Jungle Fleet", rarity = "common", color = { 84, 120, 62 } },
	{ id = "boat_ocean", kind = "boat", name = "Ocean Blue Fleet", rarity = "common", color = { 46, 120, 200 } },
	{ id = "boat_rust", kind = "boat", name = "Rusty Fleet", rarity = "common", color = { 160, 84, 44 } },
	{ id = "boat_royal", kind = "boat", name = "Royal Purple Fleet", rarity = "rare", color = { 120, 64, 190 } },
	{ id = "boat_neon", kind = "boat", name = "Neon Fleet", rarity = "epic", color = { 60, 255, 200 } },
	{ id = "boat_ivory", kind = "boat", name = "Ivory Fleet", rarity = "epic", color = { 240, 232, 210 } },
	-- nuke skins
	{ id = "nuke_hazard", kind = "nuke", name = "Hazard Warhead", rarity = "common", color = { 250, 214, 30 } },
	{ id = "nuke_black_ops", kind = "nuke", name = "Black Ops Warhead", rarity = "rare", color = { 36, 36, 42 } },
	{ id = "nuke_toxic", kind = "nuke", name = "Toxic Warhead", rarity = "epic", color = { 120, 255, 60 } },
	{ id = "nuke_gold", kind = "nuke", name = "Golden Warhead", rarity = "legendary", color = { 255, 200, 50 } },
	{ id = "nuke_camo", kind = "nuke", name = "Camo Warhead", rarity = "common", color = { 96, 112, 70 } },
	{ id = "nuke_ice", kind = "nuke", name = "Frost Warhead", rarity = "common", color = { 170, 220, 250 } },
	{ id = "nuke_crimson", kind = "nuke", name = "Crimson Warhead", rarity = "rare", color = { 196, 30, 44 } },
	{ id = "nuke_plasma", kind = "nuke", name = "Plasma Warhead", rarity = "epic", color = { 180, 80, 255 } },
	{ id = "nuke_candy", kind = "nuke", name = "Candy Warhead", rarity = "rare", color = { 255, 120, 190 } },
	-- missile skins
	{ id = "missile_red_streak", kind = "missile", name = "Red Streak", rarity = "common", color = { 236, 50, 50 } },
	{ id = "missile_ice", kind = "missile", name = "Ice Missile", rarity = "common", color = { 140, 220, 255 } },
	{ id = "missile_plasma", kind = "missile", name = "Plasma Missile", rarity = "epic", color = { 190, 90, 255 } },
	{ id = "missile_gold", kind = "missile", name = "Golden Missile", rarity = "legendary", color = { 255, 206, 60 } },
	{ id = "missile_jungle", kind = "missile", name = "Jungle Missile", rarity = "common", color = { 90, 130, 64 } },
	{ id = "missile_shadow", kind = "missile", name = "Shadow Missile", rarity = "rare", color = { 40, 42, 52 } },
	{ id = "missile_neon", kind = "missile", name = "Neon Missile", rarity = "rare", color = { 60, 255, 140 } },
	{ id = "missile_inferno", kind = "missile", name = "Inferno Missile", rarity = "epic", color = { 255, 110, 30 } },
	-- (2026-11-08: the user's sprite sheets; every boat / nuke / missile skin is now pixel art, Data/UnitSkins,
	-- and a few new ones come with them; `color` stays for what still tints)
	{ id = "boat_barge", kind = "boat", name = "Gravel Barge", rarity = "common", color = { 120, 96, 80 } },
	{ id = "nuke_rust", kind = "nuke", name = "Rusted Warhead", rarity = "common", color = { 200, 110, 50 } },
	{ id = "missile_field", kind = "missile", name = "Field Missile", rarity = "common", color = { 120, 118, 70 } },
	{ id = "missile_hazard", kind = "missile", name = "Hazard Missile", rarity = "rare", color = { 250, 210, 30 } },
	{ id = "missile_rust", kind = "missile", name = "Rusty Missile", rarity = "common", color = { 160, 96, 56 } },
	-- warship skins (2026-11-08, the user's warship sheet)
	{ id = "warship_destroyer", kind = "warship", name = "Grey Destroyer", rarity = "common", color = { 110, 118, 130 } },
	{ id = "warship_desert", kind = "warship", name = "Desert Camo Gunboat", rarity = "common", color = { 150, 140, 90 } },
	{ id = "warship_jungle", kind = "warship", name = "Jungle Camo Cruiser", rarity = "rare", color = { 96, 112, 70 } },
	{ id = "warship_battle", kind = "warship", name = "Battle Cruiser", rarity = "rare", color = { 140, 146, 160 } },
	{ id = "warship_sub", kind = "warship", name = "Submarine", rarity = "epic", color = { 60, 66, 80 } },
	{ id = "warship_stealth", kind = "warship", name = "Stealth Corvette", rarity = "epic", color = { 40, 50, 80 } },
	{ id = "warship_carrier", kind = "warship", name = "Aircraft Carrier", rarity = "legendary", color = { 120, 126, 140 } },
	{ id = "warship_dread", kind = "warship", name = "Dreadnought", rarity = "legendary", color = { 110, 100, 86 } },
}

-- the Countryball gear goes first (hats, beards, glasses: Data/GearSprites)
for i, it in GearSprites.items do
	local art = GearSprites.art[it.id]
	table.insert(Gear.items, i, {
		id = it.id,
		kind = it.kind,
		name = it.name,
		rarity = it.rarity,
		x = art.x,
		y = art.y,
		pal = art.pal,
		rows = art.rows,
	})
end

local by_id: { [string]: any } = {}
for _, it in Gear.items do
	by_id[it.id] = it
end

function Gear.item(id: any): any?
	return if type(id) == "string" then by_id[id] else nil
end

function Gear.is_kind(kind: any): boolean
	return table.find(Gear.KINDS, kind) ~= nil
end

--- Is `kind` worn on the Countryball (a hat, a beard or glasses)?
function Gear.on_ball(kind: any): boolean
	return table.find(Gear.BALL_KINDS, kind) ~= nil
end

--- A unit skin's colour (Color3), or nil.
function Gear.color(id: any): Color3?
	local it = Gear.item(id)
	if it == nil or it.color == nil then
		return nil
	end
	return Color3.fromRGB(it.color[1], it.color[2], it.color[3])
end

return Gear
