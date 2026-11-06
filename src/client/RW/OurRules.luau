--!nonstrict
-- This game's rules for RoWorld's interface (UIRules.hooks): build prices, placement checks and blast
-- radii come from Shared.Config / State (the same numbers the server uses), not RoWorld's Rules.
-- RoWorld kind names map onto ours: artillery = our AA battery, atom = missile, hydrogen = nuke,
-- airstrike = bomber sortie, fighter = fighter patrol.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local State = require(script.Parent.Parent.State)

local OurRules = {}

OurRules.BUILD = { city = "city", port = "port", factory = "factory", defense = "defense", sam = "sam", silo = "silo", artillery = "aa", airfield = "airfield" }

function OurRules.cost(kind: string): number?
	local ours = OurRules.BUILD[kind]
	if ours then
		return State.costFor(ours)
	elseif kind == "atom" then
		return Config.Missile.Cost
	elseif kind == "hydrogen" then
		return Config.Nuke.Cost
	elseif kind == "warship" then
		return Config.Naval and Config.Naval.WarshipCost or 0
	elseif kind == "airstrike" then
		return Config.Air.BomberCost or 0
	elseif kind == "fighter" then
		return Config.Air.FighterCost or 0
	end
	return nil
end

-- the city under a tile you could upgrade (ours: cities level up, other buildings don't)
function OurRules.upgradable(kind: string, tile: number): any
	if kind ~= "city" then
		return nil
	end
	local st = State.structureNear(tile, 1)
	if st and st.owner == State.me and st.kind == "city" and (st.level or 1) < (Config.Structures.city.maxLevel or 5) then
		return st
	end
	return nil
end

-- RoWorld's placement result: ok, reason, code ("gold" = only money is missing), upgrade info
function OurRules.place(kind: string, tile: number): { [string]: any }?
	local ours = OurRules.BUILD[kind]
	if not ours then
		return nil
	end
	local up = OurRules.upgradable(kind, tile)
	if up then
		local me = State.nations[State.me]
		local cost = math.floor(State.costFor("city") * (Config.Structures.city.upgradeCost or 1))
		local rich = me ~= nil and me.gold >= cost
		return { ok = rich, tile = up.cell, reason = if rich then "" else "Not enough gold", code = if rich then "" else "gold", upgrade = true, sid = up.id, level = (up.level or 1) + 1 }
	end
	local why = State.buildWhyNot(ours, tile)
	local code = if why == nil then "" elseif why:find("gold") then "gold" elseif why:find("coast") then "no_coast" elseif why:find("close") then "no_room" else "not_own"
	return { ok = why == nil, tile = tile, reason = why or "", code = code, upgrade = false, sid = 0, level = 1 }
end

function OurRules.nuke_radius(kind: string): (number?, number?)
	if kind == "atom" then
		return 0, Config.Missile.Radius
	elseif kind == "hydrogen" then
		return math.floor(Config.Nuke.Radius * 0.5), Config.Nuke.Radius
	elseif kind == "airstrike" then
		return 0, Config.Air.SuppressRadius or 3
	elseif kind == "fighter" then
		return 0, Config.Air.FighterRange or 5
	end
	return nil
end

return OurRules
