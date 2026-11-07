--!strict
-- (Take Over the World!: supply, logistics and strategic resources, 2026-11-06.)
-- The one place supply, infrastructure and resources are tuned (Core/SimLogistics reads everything
-- here). Money is the game's existing gold (o_gold); the strategic resources below are national
-- stocks next to it. Province deposits are derived from each province's terrain and id (the same on
-- the server and the clients), so countries do not all get the same deposits.
local Logistics = {}

Logistics.RESOURCES = { "food", "steel", "oil", "aluminum", "rare" }
Logistics.RESOURCE_NAMES = { food = "Food", steel = "Steel", oil = "Oil", aluminum = "Aluminum", rare = "Rare materials" }

-- =============================================================================================
-- Supply status
-- =============================================================================================

--- Status tiers by supply level (0..1): code, name, combat x, recovery x.
Logistics.STATUS = {
	{ code = 0, min = 0.8, name = "Fully supplied", combat = 1.0, recovery = 1.0 },
	{ code = 1, min = 0.4, name = "Undersupplied", combat = 0.8, recovery = 0.6 },
	{ code = 2, min = 0.0001, name = "Critical", combat = 0.55, recovery = 0.3 },
	{ code = 3, min = -1, name = "Out of supply", combat = 0.35, recovery = 0.0 },
}

function Logistics.status(supply: number): any
	for _, s in Logistics.STATUS do
		if supply >= s.min then
			return s
		end
	end
	return Logistics.STATUS[#Logistics.STATUS]
end

-- =============================================================================================
-- Army supply model (supply units per second; an army's supply level is 0..1)
-- =============================================================================================

--- Supply units a battalion uses per second, and what one supply unit costs the nation.
Logistics.SUPPLY_USE = { infantry = 1.0, tank = 3.0, artillery = 2.0 }
Logistics.SUPPLY_COST = {
	infantry = { food = 1.0 },
	tank = { food = 0.4, oil = 1.0 },
	artillery = { food = 0.6, steel = 0.4 },
}
--- Activity multipliers (status codes of Core/SimArmies: idle, moving, combat, retreating).
Logistics.ACTIVITY = { [0] = 1.0, 1.25, 2.0, 1.5 }
--- Terrain multipliers on consumption (Defs.T_* + 1: ocean, lake, plains, highland, mountain, tundra, icecap).
Logistics.TERRAIN_USE = { 1.0, 1.0, 1.0, 1.1, 1.3, 1.25, 1.5 }
--- Per second: gain at full delivery, loss when undersupplied (x the missing share), loss while cut off.
Logistics.REGEN = 0.08
Logistics.UNDER_DRAIN = 0.03
Logistics.ISOLATED_DRAIN = 0.025 -- ~40 s from full to empty: never instant
--- Out of supply: share of each battalion's hp lost per second (attrition), and no reinforcing below this.
Logistics.ATTRITION = 0.01
Logistics.REINFORCE_MIN = 0.4

-- =============================================================================================
-- Network
-- =============================================================================================

--- Supply units per second a link between neighbouring provinces carries: a base, + per road level,
--- + per rail level (the lower of the two provinces' levels counts: both ends need the road).
Logistics.LINK_BASE = 6
Logistics.LINK_ROAD = 10
Logistics.LINK_RAIL = 30
--- Sea lane between two of the country's port provinces (prepares naval supply).
Logistics.LINK_PORT = 12
--- Sources: the capital (unlimited stock) and depots (their own stock).
Logistics.CAPITAL_OUTPUT = 80
Logistics.DEPOT_OUTPUT = 25 -- per level
Logistics.DEPOT_STORAGE = 3000 -- supply units per level
Logistics.DEPOT_REFILL = 20 -- per second per level, from national stocks, while linked to the capital
--- Delivery falls off with distance (province hops from the source), down to this floor.
Logistics.HOP_FALLOFF = 0.04
Logistics.HOP_FLOOR = 0.3
--- Networks are recalculated when ownership / infrastructure / alliances change (checked every
--- second), and all of them every REFRESH_TICKS anyway.
Logistics.REFRESH_TICKS = 200

-- =============================================================================================
-- Infrastructure (province levels)
-- =============================================================================================

--- kind -> { name, max level, gold, resources, build ticks (x level), needs }
Logistics.INFRA = {
	road = { code = 1, name = "Road", max = 3, gold = 3000, res = { steel = 15 }, ticks = 150 },
	rail = { code = 2, name = "Railway", max = 2, gold = 9000, res = { steel = 60 }, ticks = 300, needs_road = 1 },
	depot = { code = 3, name = "Supply Depot", max = 3, gold = 6000, res = { steel = 30 }, ticks = 200 },
	farm = { code = 4, name = "Farm", max = 3, gold = 4000, res = {}, ticks = 150 },
	steel = { code = 5, name = "Steel Factory", max = 3, gold = 10000, res = { aluminum = 5 }, ticks = 300 },
	oil = { code = 6, name = "Oil Facility", max = 3, gold = 8000, res = { steel = 25 }, ticks = 250, needs_deposit = "oil" },
}
Logistics.INFRA_ORDER = { "road", "rail", "depot", "farm", "steel", "oil" }
--- Each level costs (1 + level x this) times the base price.
Logistics.LEVEL_COST = 0.6
--- Army movement speed x per road / rail level of the province it walks into.
Logistics.ROAD_SPEED = 0.2
Logistics.RAIL_SPEED = 0.5

-- =============================================================================================
-- Resources
-- =============================================================================================

--- Production per second: deposits (per province), x facilities.
Logistics.FARM_BONUS = 0.6 -- food x (1 + level x this)
Logistics.STEEL_FACTORY = 1.5 -- steel per second per level (+50% on an iron deposit)
Logistics.OIL_FACILITY = 0.8 -- oil x (1 + level x this) of the deposit
--- Storage cap per resource; depots and oil facilities add room.
Logistics.STORAGE_BASE = 4000
Logistics.STORAGE_DEPOT = 1500
Logistics.STORAGE_OIL = 1500
--- Starting stocks: this many seconds of the country's production, plus a base.
Logistics.START_SECONDS = 180
Logistics.START_BASE = { food = 400, steel = 150, oil = 80, aluminum = 40, rare = 10 }

local function rnd(seed: number): number
	-- (deterministic: xorshift on 32 bits)
	local x = seed % 4294967296
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	return (x % 1000003) / 1000003
end

--- A province's deposits (per second at level 0), from its terrain and id: food on farmland, and
--- iron (steel), oil, bauxite (aluminum) and rare earths where its roll finds them.
function Logistics.deposits(p: any, map_id: string?): { [string]: number }
	local salt = 0
	for i = 1, #(map_id or "") do
		salt = salt * 31 + string.byte(map_id :: string, i)
	end
	local base = p.id * 2654435761 + salt
	local tr = p.terrain or {}
	local tiles = math.max(p.tiles or 1, 1)
	local plains, high, mount, tundra = tr[2] or 0, tr[3] or 0, tr[4] or 0, tr[5] or 0
	local size = tiles / 1000
	local d = {
		food = (plains * 2 + high) / 1000 * 0.6,
		steel = 0,
		oil = 0,
		aluminum = 0,
		rare = 0,
	}
	if rnd(base + 1) < 0.2 + 0.5 * (high + mount) / tiles then
		d.steel = (0.3 + rnd(base + 11)) * size * 0.5
	end
	if rnd(base + 2) < 0.14 + 0.2 * tundra / tiles + (if (p.coast or 0) > 0 then 0.06 else 0) then
		d.oil = (0.3 + rnd(base + 12)) * size * 0.4
	end
	if rnd(base + 3) < 0.1 + 0.4 * mount / tiles then
		d.aluminum = (0.3 + rnd(base + 13)) * size * 0.25
	end
	if rnd(base + 4) < 0.04 + 0.25 * mount / tiles then
		d.rare = (0.3 + rnd(base + 14)) * size * 0.1
	end
	return d
end

--- Gold and resources for building `kind` up to level `level` (1 = the first).
function Logistics.cost(kind: string, level: number): (number, { [string]: number })
	local def = Logistics.INFRA[kind]
	local k = 1 + (level - 1) * Logistics.LEVEL_COST
	local res = {}
	for r, v in def.res do
		res[r] = math.floor(v * k + 0.5)
	end
	return math.floor(def.gold * k + 0.5), res
end

return Logistics
