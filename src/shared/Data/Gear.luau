--!strict
-- (Take Over the World!: item shop gear, 2026-11-06.)
-- Countryball hats (pixel art drawn over the top of the ball: Countryball.ball_content) and unit
-- skins (a colour the boats, nukes or missiles wear instead of the owner's: Map/UnitLayer). Sold in
-- the item shop (Data/ItemShop), never in crates. Data/Cosmetics resolves them by id like any item.
--   hat:  rows (top to bottom; "." = clear), x / y = where row 1's first character lands on the
--         32 x 32 ball, pal = character -> {r, g, b} ("o" is the ball's outline colour)
--   boat / nuke / missile: color = {r, g, b}
local Gear = {}

Gear.KINDS = { "hat", "boat", "nuke", "missile" }
Gear.KIND_NAMES = { hat = "Hat", boat = "Boat Skin", nuke = "Nuke Skin", missile = "Missile Skin" }

Gear.items = {
	-- hats
	{
		id = "hat_army_helmet",
		kind = "hat",
		name = "Army Helmet",
		rarity = "common",
		x = 4,
		y = 0,
		pal = { a = { 92, 110, 58 }, b = { 64, 78, 40 }, d = { 128, 148, 84 } },
		rows = {
			"........oooooooo........",
			"......ooaaaaaaaaoo......",
			".....oaaddaaaaaaabo.....",
			"....oaaddaaaaaaaaabo....",
			"....oaadaaaaaaaaaaabo...",
			"...oaaaaaaaaaaaaaaaabo..",
			"..obbbbbbbbbbbbbbbbbbbo.",
			"..oooooooooooooooooooooo",
		},
	},
	{
		id = "hat_beret",
		kind = "hat",
		name = "Red Beret",
		rarity = "common",
		x = 4,
		y = 1,
		pal = { a = { 196, 38, 48 }, b = { 140, 22, 32 }, c = { 255, 204, 64 } },
		rows = {
			"............oo..........",
			"........oooooooooo......",
			"......ooaaaaaaaaaaoo....",
			".....oaaaaaaaaaaaaaaoo..",
			"....oaacaaaaaaaaaaaaaao.",
			"....obbbbbbbbbbbbbbbbbo.",
			"....oooooooooooooooooo..",
		},
	},
	{
		id = "hat_officer_cap",
		kind = "hat",
		name = "Officer Cap",
		rarity = "rare",
		x = 4,
		y = 0,
		pal = {
			a = { 52, 74, 60 },
			b = { 36, 52, 42 },
			c = { 255, 200, 50 },
			k = { 24, 24, 28 },
			v = { 30, 30, 34 },
		},
		rows = {
			"....oooooooooooooooo....",
			"...oaaaaaaaaaaaaaaaao...",
			"...oaaaaaaacccaaaaaao...",
			"....oaaaaaacccaaaaao....",
			"....obbbbbbbbbbbbbbo....",
			"....okkkkkkkkkkkkkko....",
			"....ovvvvvvvvvvvvvvvo...",
			".....ooooooooooooooo....",
		},
	},
	{
		id = "hat_ushanka",
		kind = "hat",
		name = "Fur Ushanka",
		rarity = "common",
		x = 4,
		y = 0,
		pal = { a = { 120, 84, 52 }, f = { 176, 140, 100 }, c = { 220, 40, 40 } },
		rows = {
			"......oooooooooooo......",
			".....offffffffffffo.....",
			"....offaaaaaaaaaaffo....",
			"....offaaaaacaaaaffo....",
			"...offffffffffffffffo...",
			"...offffffffffffffffo...",
			"...ofo..........ofo.....",
			"...ofo..........ofo.....",
			"...ooo..........ooo.....",
		},
	},
	{
		id = "hat_top_hat",
		kind = "hat",
		name = "Top Hat",
		rarity = "rare",
		x = 4,
		y = 0,
		pal = { a = { 40, 40, 48 }, r = { 190, 30, 40 }, d = { 70, 70, 82 } },
		rows = {
			".......oooooooooo.......",
			".......odaaaaaaao.......",
			".......odaaaaaaao.......",
			".......odaaaaaaao.......",
			".......orrrrrrrro.......",
			".......oaaaaaaaao.......",
			"....oooooooooooooooo....",
			"....oaaaaaaaaaaaaaao....",
			"....oooooooooooooooo....",
		},
	},
	{
		id = "hat_spiked_helmet",
		kind = "hat",
		name = "Spiked Helmet",
		rarity = "epic",
		x = 4,
		y = 0,
		pal = { a = { 34, 34, 40 }, c = { 240, 190, 60 }, d = { 70, 70, 84 } },
		rows = {
			"...........oo...........",
			"..........occo..........",
			"..........occo..........",
			".......oooooooooo.......",
			".....ooaadaaaaaaaoo.....",
			"....oaadaaccccaaaaao....",
			"....oaaaaacccccaaaao....",
			"...oaaaaaaaccaaaaaaao...",
			"..oooooooooooooooooooo..",
		},
	},
	{
		id = "hat_viking_helmet",
		kind = "hat",
		name = "Viking Helmet",
		rarity = "rare",
		x = 4,
		y = 0,
		pal = { a = { 150, 156, 170 }, b = { 104, 110, 124 }, h = { 236, 226, 196 } },
		rows = {
			".o....................o.",
			"oho..................oho",
			"ohho....oooooooo....ohho",
			".ohhooooaaaaaaaaoooohho.",
			"..ohhoaaaaaaaaaaaaohho..",
			"...oooaaaaaaaaaaaaooo...",
			"....obbbbbbbbbbbbbbo....",
			"....oooooooooooooooo....",
		},
	},
	{
		id = "hat_bicorne",
		kind = "hat",
		name = "Admiral Bicorne",
		rarity = "epic",
		x = 4,
		y = 1,
		pal = { a = { 28, 30, 44 }, c = { 240, 190, 60 }, r = { 210, 40, 50 } },
		rows = {
			".........oooooo.........",
			"......oooaaaaaaooo......",
			"...oooaaaaaaaaaaaaooo...",
			".ooaaaaaaaaccaaaaaaaaoo.",
			"oaaaaaaaaaacrcaaaaaaaaao",
			"occcccccccccccccccccccco",
			".oooooooooooooooooooooo.",
		},
	},
	{
		id = "hat_crown",
		kind = "hat",
		name = "Royal Crown",
		rarity = "legendary",
		x = 4,
		y = 0,
		pal = {
			a = { 250, 196, 48 },
			c = { 255, 250, 230 },
			r = { 220, 30, 50 },
			g = { 40, 190, 90 },
			b = { 50, 110, 240 },
		},
		rows = {
			".....o.....oo.....o.....",
			"....oco...occo...oco....",
			"....oaao..oaao..oaao....",
			"....oaaaooaaaaooaaao....",
			"....oaaaaaaaaaaaaaao....",
			"....oaraabaagaabaraao...",
			"....oaaaaaaaaaaaaaao....",
			"....oooooooooooooooo....",
		},
	},
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

local by_id: { [string]: any } = {}
for _, it in Gear.items do
	by_id[it.id] = it
end

function Gear.item(id: any): any?
	return if type(id) == "string" then by_id[id] else nil
end

function Gear.is_kind(kind: any): boolean
	return kind == "hat" or kind == "boat" or kind == "nuke" or kind == "missile"
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
