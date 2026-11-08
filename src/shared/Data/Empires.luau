--!strict
-- (Take Over the World!: empires, 2026-11-07.)
-- A country whose leader holds LAND_SHARE of the map's land can found its empire (Sim.form_empire):
-- the nation takes the empire's name and flag (Data/FlagData/Empires, historical flags pixelated by
-- tools/build_empire_flags.py) and its Countryball grows a moustache and a beard. A country with no
-- historical empire of its own founds the "Empire of <name>" under its own flag.
--   Empires.of(country) -> { name, flag }      (flag: a FlagPix code)
--   Empires.is_empire(name) -> boolean
--   Empires.flag_of(name) -> flag code?         (an empire's flag by the empire's name)
local Empires = {}

--- the share of the map's land a country must hold to found its empire
Empires.LAND_SHARE = 0.05
--- (2026-11-08) and the share of the map it must have conquered beyond its own country: a country that
--- starts big (Russia, China...) still has to take land first, the AI's as much as a player's
Empires.CONQUER_SHARE = 0.02

--- The land (tiles) a country needs to found its empire: LAND_SHARE of the map's `land`, and at
--- least its own `home` country's land (Data/Countries def.tiles) plus CONQUER_SHARE of the map.
function Empires.need(land: number, home: number?): number
	return math.max(land * Empires.LAND_SHARE, (home or 0) + land * Empires.CONQUER_SHARE)
end

--- country (CountryGrid / Natural Earth name) -> { empire name, flag key (FlagData/Empires "emp_<key>") }
Empires.HISTORICAL = {
	["United Kingdom"] = { "British Empire", "british" },
	["Germany"] = { "German Empire", "german" },
	["Russia"] = { "Russian Empire", "russian" },
	["Turkey"] = { "Ottoman Empire", "ottoman" },
	["Japan"] = { "Empire of Japan", "japanese" },
	["France"] = { "French Empire", "french" },
	["Austria"] = { "Austrian Empire", "austrian" },
	["Spain"] = { "Spanish Empire", "spanish" },
	["Portugal"] = { "Portuguese Empire", "portuguese" },
	["China"] = { "Qing Empire", "qing" },
	["Iran"] = { "Persian Empire", "persian" },
	["Brazil"] = { "Empire of Brazil", "brazilian" },
	["Mexico"] = { "Mexican Empire", "mexican" },
	["Ethiopia"] = { "Ethiopian Empire", "ethiopian" },
	["Greece"] = { "Byzantine Empire", "byzantine" },
	["Italy"] = { "Roman Empire", "roman" },
	["South Korea"] = { "Korean Empire", "korean" },
	["Sweden"] = { "Swedish Empire", "swedish" },
	["Netherlands"] = { "Dutch Empire", "dutch" },
}

local by_name: { [string]: string } = {}
for _, e in Empires.HISTORICAL do
	by_name[e[1]] = "emp_" .. e[2]
end

--- The empire `country` founds: its name and its flag code (nil `flag`: the country keeps its own).
function Empires.of(country: string): { name: string, flag: string? }
	local e = Empires.HISTORICAL[country]
	if e ~= nil then
		return { name = e[1], flag = "emp_" .. e[2] }
	end
	return { name = "Empire of " .. country, flag = nil }
end

function Empires.is_empire(name: string?): boolean
	if type(name) ~= "string" then
		return false
	end
	return by_name[name] ~= nil or string.sub(name, 1, 10) == "Empire of "
end

--- A historical empire's flag code by the empire's name ("German Empire" -> "emp_german").
function Empires.flag_of(name: string?): string?
	return if type(name) == "string" then by_name[name] else nil
end

--- The country an "Empire of <country>" was founded by.
function Empires.country_of(name: string?): string?
	if type(name) ~= "string" then
		return nil
	end
	for country, e in Empires.HISTORICAL do
		if e[1] == name then
			return country
		end
	end
	if string.sub(name, 1, 10) == "Empire of " then
		return string.sub(name, 11)
	end
	return nil
end

return Empires
