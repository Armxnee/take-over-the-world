--!strict
-- (Take Over the World!: item shop gear, 2026-11-06; Countryball gear from the user's reference
-- sheets 2026-11-08.)
-- Countryball gear (pixel art drawn on the ball: Countryball.ball_content): hats, beards and
-- moustaches, glasses (Data/GearSprites, built by tools/build_gear.py) and unit skins (a colour the
-- boats, nukes or missiles wear instead of the owner's: Map/UnitLayer). Sold in the item shop
-- (Data/ItemShop) and given by crates. Data/Cosmetics resolves them by id like any item.
--   hat / beard / glasses: rows (top to bottom; "." = clear), x / y = where row 1's first character
--         lands on the 40 x 40 ball canvas (Countryball.G), pal = character -> {r, g, b}
--   boat / nuke / missile: color = {r, g, b}
local GearSprites = require(script.Parent.GearSprites)

local Gear = {}

Gear.KINDS = { "hat", "beard", "glasses", "boat", "nuke", "missile" }
--- the kinds worn on the Countryball, in the order they are drawn
Gear.BALL_KINDS = { "beard", "glasses", "hat" }
Gear.KIND_NAMES = {
	hat = "Hat",
	beard = "Beard",
	glasses = "Glasses",
	boat = "Boat Skin",
	nuke = "Nuke Skin",
	missile = "Missile Skin",
}

Gear.items = {
	-- boat skins
	{ id = "boat_navy_grey", kind = "boat", name = "Navy Grey Fleet", rarity = "common", color = { 128, 138, 150 } },
	{ id = "boat_arctic", kind = "boat", name = "Arctic Camo Fleet", rarity = "common", color = { 214, 232, 246 } },
	{ id = "boat_crimson", kind = "boat", name = "Crimson Fleet", rarity = "rare", color = { 200, 36, 48 } },
	{ id = "boat_stealth", kind = "boat", name = "Stealth Fleet", rarity = "epic", color = { 44, 48, 58 } },
	{ id = "boat_gold", kind = "boat", name = "Golden Fleet", rarity = "legendary", color = { 255, 196, 40 } },
	-- nuke skins
	{ id = "nuke_hazard", kind = "nuke", name = "Hazard Warhead", rarity = "common", color = { 250, 214, 30 } },
	{ id = "nuke_black_ops", kind = "nuke", name = "Black Ops Warhead", rarity = "rare", color = { 36, 36, 42 } },
	{ id = "nuke_toxic", kind = "nuke", name = "Toxic Warhead", rarity = "epic", color = { 120, 255, 60 } },
	{ id = "nuke_gold", kind = "nuke", name = "Golden Warhead", rarity = "legendary", color = { 255, 200, 50 } },
	-- missile skins
	{ id = "missile_red_streak", kind = "missile", name = "Red Streak", rarity = "common", color = { 236, 50, 50 } },
	{ id = "missile_ice", kind = "missile", name = "Ice Missile", rarity = "common", color = { 140, 220, 255 } },
	{ id = "missile_plasma", kind = "missile", name = "Plasma Missile", rarity = "epic", color = { 190, 90, 255 } },
	{ id = "missile_gold", kind = "missile", name = "Golden Missile", rarity = "legendary", color = { 255, 206, 60 } },
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
