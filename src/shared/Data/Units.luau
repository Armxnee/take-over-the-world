--!strict
-- (Take Over the World!: ground units and army balance, 2026-11-06.)
-- The one place ground units and army combat are tuned. A unit is a battalion: recruiting one takes
-- `men` from the country's existing troop pool (o_troops, internal units: the HUD shows them / 10) and
-- `gold` from its treasury: no other currency or troop system. Core/SimArmies reads everything here.
local Units = {}

--- Order of the unit types (army composition rows, UI, wire).
Units.TYPES = { "infantry", "tank", "artillery" }

--- Unit definitions.
---   soft_attack / hard_attack: damage per second against unarmoured (infantry, artillery, garrison) /
---     armoured (tanks) targets, per battalion
---   defense: damage taken is divided by this
---   hp: hit points per battalion
---   speed: tiles per second on plains
---   upkeep: gold per second per battalion (its supply consumption)
---   terrain_attack: attack multiplier by terrain of the battle (tanks are poor in mountains)
---   pierce: share of the defender's terrain / fortification bonus it ignores (artillery)
---   exposure: share of incoming damage it takes while a frontline (infantry / tanks) protects it;
---     exposure_alone: the same without one (unprotected artillery)
Units.DEFS = {
	infantry = {
		id = "infantry",
		name = "Infantry",
		sprite = "unit:infantry",
		men = 10000,
		gold = 1500,
		soft_attack = 4,
		hard_attack = 1,
		defense = 1.4,
		hp = 100,
		speed = 4,
		upkeep = 2,
		armored = false,
		terrain_attack = { 1.0, 1.0, 1.0, 0.9, 0.9, 0.8 },
		pierce = 0,
		exposure = 1.0,
		exposure_alone = 1.0,
		occupy = true,
	},
	tank = {
		id = "tank",
		name = "Tank",
		sprite = "unit:tank",
		men = 3000,
		gold = 9000,
		soft_attack = 14,
		hard_attack = 8,
		defense = 1.6,
		hp = 300,
		speed = 6,
		upkeep = 9,
		armored = true,
		terrain_attack = { 1.0, 1.0, 1.1, 0.75, 0.45, 0.6 },
		pierce = 0.2,
		exposure = 1.0,
		exposure_alone = 1.0,
		occupy = false,
	},
	artillery = {
		id = "artillery",
		name = "Artillery",
		sprite = "unit:artillery",
		men = 4000,
		gold = 6000,
		soft_attack = 10,
		hard_attack = 3,
		defense = 0.8,
		hp = 120,
		speed = 3,
		upkeep = 5,
		armored = false,
		terrain_attack = { 1.0, 1.0, 1.0, 0.9, 0.8, 0.8 },
		pierce = 0.6,
		exposure = 0.35,
		exposure_alone = 1.6,
		occupy = false,
	},
}

--- Terrain (Defs.T_* + 1: 1 ocean, 2 lake, 3 plains, 4 highland, 5 mountain, 6 tundra, 7 icecap) ->
--- movement speed multiplier and defensive bonus.
Units.TERRAIN_SPEED = { 0.5, 0.5, 1.0, 0.75, 0.5, 0.7, 0.4 }
Units.TERRAIN_DEFENSE = { 1.0, 1.0, 1.0, 1.25, 1.6, 1.1, 1.2 }
--- terrain_attack above is indexed by the same terrain row minus 1 (plains = 2 .. icecap = 6), see
--- Units.terrain_attack.

--- A province with a finished city or factory of its controller moves armies faster.
Units.INFRA_SPEED = 1.3

--- Army limits and rules.
Units.MAX_ARMIES = 20
Units.MAX_BATTALIONS = 60
Units.MAX_RECRUIT = 20 -- per order
--- Damage scale: battalion damage per second x this (battles of tens of seconds).
Units.DAMAGE_SCALE = 0.25
--- Combat round length in ticks (10 ticks = 1 s).
Units.ROUND_TICKS = 10
--- Garrison: the defender's troops in a province fight as infantry, dug in.
Units.GARRISON_SHARE = 0.6 -- share of the province's slice of the troop pool that defends it
Units.GARRISON_ENTRENCH = 1.3
--- Province fortification: a defence post of the defender in the province.
Units.FORT_BONUS = 1.5
--- Numerical advantage: a side over OUTNUMBER x the other's strength hits this much harder.
Units.OUTNUMBER = 2.0
Units.OUTNUMBER_BONUS = 1.2
--- Morale, organization, supply (0..1).
Units.ORG_LOSS_ATTACK = 0.035 -- per round in combat
Units.ORG_LOSS_DEFEND = 0.025
Units.ORG_REGEN = 0.05 -- per second out of combat, in supply
Units.MORALE_LOSS_PER_CASUALTY = 1.5 -- x the share of battalions lost in a round
Units.MORALE_LOSS_ROUND = 0.01
Units.MORALE_REGEN = 0.02
Units.SUPPLY_REGEN = 0.1 -- per second in own / allied territory
Units.SUPPLY_LOSS = 0.04 -- per second elsewhere, or when the upkeep can't be paid
Units.CAPITAL_LOST_SUPPLY = 0.5 -- supply regen x this while the country has lost its capital
--- Automatic retreat.
Units.RETREAT_MORALE = 0.2
Units.RETREAT_ORG = 0.1
--- Manual retreat: share of battalions lost disengaging; organization afterwards.
Units.RETREAT_LOSS = 0.05
--- A retreat takes at least this many ticks (10 = 1 s): no new orders while disengaging.
Units.RETREAT_TICKS = 30
--- Disbanding returns this share of the men to the troop pool (no gold back).
Units.DISBAND_REFUND = 0.5
--- Reinforcing tops an army up to its best composition at full price; needs supply >= this.
Units.REINFORCE_MIN_SUPPLY = 0.5

--- Effectiveness from supply, organization and morale (0..1 each).
function Units.effectiveness(supply: number, org: number, morale: number): number
	return (0.5 + 0.5 * supply) * (0.4 + 0.6 * org) * (0.6 + 0.4 * morale)
end

--- A unit type's attack multiplier on terrain code `t` (Defs.T_*).
function Units.terrain_attack(def: any, t: number): number
	return def.terrain_attack[math.clamp(t - 1, 1, #def.terrain_attack)] or 1
end

--- Slowest unit type present (tiles per second), or the infantry's speed for an empty army.
function Units.army_speed(counts: { [string]: number }): number
	local s = math.huge
	for _, k in Units.TYPES do
		if (counts[k] or 0) > 0 then
			s = math.min(s, Units.DEFS[k].speed)
		end
	end
	return if s == math.huge then Units.DEFS.infantry.speed else s
end

--- Gold and men for `n` battalions of `kind`.
function Units.cost(kind: string, n: number): (number, number)
	local d = Units.DEFS[kind]
	return d.gold * n, d.men * n
end

return Units
