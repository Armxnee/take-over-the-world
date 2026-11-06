--!strict
-- Simplified real-world flags (shapes + colours, no emblems) used as territory skins for
-- AI countries and on nameplates. Flags.sample(spec, u, v) -> hex colour for u,v in [0,1).
-- Kinds: V2 V3 H2 H3 plain cross plus disc star cstar canton ensign union diamond diag
-- triangle quarter.
local Flags = {}

type Spec = { any }

Flags.byName = {
	-- Europe
	["France"] = { "V3", "002395", "FFFFFF", "ED2939" },
	["Italy"] = { "V3", "009246", "FFFFFF", "CE2B37" },
	["Ireland"] = { "V3", "169B62", "FFFFFF", "FF883E" },
	["Belgium"] = { "V3", "1A1A1A", "FAE042", "ED2939" },
	["Romania"] = { "V3", "002B7F", "FCD116", "CE1126" },
	["Moldova"] = { "V3", "0046AE", "FFD200", "CC092F" },
	["Germany"] = { "H3", "1A1A1A", "DD0000", "FFCE00" },
	["Russia"] = { "H3", "FFFFFF", "0039A6", "D52B1E" },
	["Netherlands"] = { "H3", "AE1C28", "FFFFFF", "21468B" },
	["Hungary"] = { "H3", "CE2939", "FFFFFF", "477050" },
	["Austria"] = { "H3", "ED2939", "FFFFFF", "ED2939" },
	["Bulgaria"] = { "H3", "FFFFFF", "00966E", "D62612" },
	["Lithuania"] = { "H3", "FDB913", "006A44", "C1272D" },
	["Estonia"] = { "H3", "0072CE", "1A1A1A", "FFFFFF" },
	["Latvia"] = { "H3", "9E3039", "FFFFFF", "9E3039" },
	["Luxembourg"] = { "H3", "ED2939", "FFFFFF", "00A1DE" },
	["Slovenia"] = { "H3", "FFFFFF", "005DA4", "ED1C24" },
	["Slovakia"] = { "H3", "FFFFFF", "0B4EA2", "EE1C25" },
	["Serbia"] = { "H3", "C6363C", "0C4076", "FFFFFF" },
	["Croatia"] = { "H3", "FF0000", "FFFFFF", "171796" },
	["Spain"] = { "H3", "AA151B", "F1BF00", "AA151B" },
	["Poland"] = { "H2", "FFFFFF", "DC143C" },
	["Ukraine"] = { "H2", "0057B7", "FFD700" },
	["Belarus"] = { "H2", "C8313E", "4AA657" },
	["Monaco"] = { "H2", "CE1126", "FFFFFF" },
	["Portugal"] = { "V2", "046A38", "DA291C" },
	["Sweden"] = { "cross", "006AA7", "FECC00" },
	["Denmark"] = { "cross", "C8102E", "FFFFFF" },
	["Norway"] = { "cross", "BA0C2F", "FFFFFF" },
	["Finland"] = { "cross", "FFFFFF", "002F6C" },
	["Iceland"] = { "cross", "02529C", "FFFFFF" },
	["Switzerland"] = { "plus", "FF0000", "FFFFFF" },
	["United Kingdom"] = { "union", "012169", "FFFFFF", "C8102E" },
	["Greece"] = { "canton", "0D5EAF", "FFFFFF", "0D5EAF" },
	["Czechia"] = { "triangle", "FFFFFF", "D7141A", "11457E" },
	["Czech Republic"] = { "triangle", "FFFFFF", "D7141A", "11457E" },
	["Albania"] = { "plain", "E41E20" },
	["North Macedonia"] = { "disc", "D20000", "FFE600" },
	["Bosnia and Herz."] = { "diag", "002395", "FECB00", "002395" },
	["Bosnia and Herzegovina"] = { "diag", "002395", "FECB00", "002395" },
	["Montenegro"] = { "plain", "C40308" },
	["Kosovo"] = { "plain", "244AA5" },
	["Cyprus"] = { "plain", "FFFFFF" },
	["Malta"] = { "V2", "FFFFFF", "CF142B" },
	["Turkey"] = { "star", "E30A17", "FFFFFF" },
	["Georgia"] = { "plus", "FFFFFF", "FF0000" },
	["Armenia"] = { "H3", "D90012", "0033A0", "F2A800" },
	["Azerbaijan"] = { "H3", "00B5E2", "EF3340", "509E2F" },
	["Greenland"] = { "H2", "FFFFFF", "D00C33" },
	-- Americas
	["United States of America"] = { "canton", "B22234", "FFFFFF", "3C3B6E" },
	["Canada"] = { "V3", "D52B1E", "FFFFFF", "D52B1E" },
	["Mexico"] = { "V3", "006847", "FFFFFF", "CE1126" },
	["Guatemala"] = { "V3", "4997D0", "FFFFFF", "4997D0" },
	["Honduras"] = { "H3", "0073CF", "FFFFFF", "0073CF" },
	["Nicaragua"] = { "H3", "0067C6", "FFFFFF", "0067C6" },
	["El Salvador"] = { "H3", "0047AB", "FFFFFF", "0047AB" },
	["Costa Rica"] = { "H3", "002B7F", "CE1126", "002B7F" },
	["Panama"] = { "quarter", "FFFFFF", "D21034", "005293", "FFFFFF" },
	["Cuba"] = { "triangle", "002A8F", "FFFFFF", "002A8F", "CF142B" },
	["Haiti"] = { "H2", "00209F", "D21034" },
	["Dominican Rep."] = { "quarter", "002D62", "CE1126", "CE1126", "002D62" },
	["Jamaica"] = { "diag", "009B3A", "FED100", "1A1A1A" },
	["Colombia"] = { "H3", "FCD116", "003893", "CE1126" },
	["Venezuela"] = { "H3", "FFCC00", "00247D", "CF142B" },
	["Ecuador"] = { "H3", "FFDD00", "034EA2", "ED1C24" },
	["Peru"] = { "V3", "D91023", "FFFFFF", "D91023" },
	["Bolivia"] = { "H3", "D52B1E", "F9E300", "007934" },
	["Brazil"] = { "diamond", "009C3B", "FEDF00", "002776" },
	["Paraguay"] = { "H3", "D52B1E", "FFFFFF", "0038A8" },
	["Uruguay"] = { "H3", "FFFFFF", "0038A8", "FFFFFF" },
	["Argentina"] = { "H3", "74ACDF", "FFFFFF", "74ACDF" },
	["Chile"] = { "canton", "FFFFFF", "D52B1E", "0039A6", 2 },
	["Guyana"] = { "triangle", "009E49", "FCD116", "009E49", "CE1126" },
	["Suriname"] = { "H3", "377E3F", "B40A2D", "377E3F" },
	-- Africa
	["Chad"] = { "V3", "002664", "FECB00", "C60C30" },
	["Mali"] = { "V3", "14B53A", "FCD116", "CE1126" },
	["Guinea"] = { "V3", "CE1126", "FCD116", "009460" },
	["Nigeria"] = { "V3", "008751", "FFFFFF", "008751" },
	["Cote d'Ivoire"] = { "V3", "F77F00", "FFFFFF", "009E60" },
	["Senegal"] = { "V3", "00853F", "FDEF42", "E31B23" },
	["Cameroon"] = { "V3", "007A5E", "CE1126", "FCD116" },
	["Gabon"] = { "H3", "009E60", "FCD116", "3A75C4" },
	["Sierra Leone"] = { "H3", "1EB53A", "FFFFFF", "0072C6" },
	["Egypt"] = { "H3", "CE1126", "FFFFFF", "1A1A1A" },
	["Sudan"] = { "triangle", "D21034", "FFFFFF", "1A1A1A", "007229" },
	["S. Sudan"] = { "triangle", "1A1A1A", "DA121A", "078930", "0F47AF" },
	["Ethiopia"] = { "H3", "078930", "FCDD09", "DA121A" },
	["Ghana"] = { "H3", "CE1126", "FCD116", "006B3F" },
	["Kenya"] = { "H3", "1A1A1A", "BB0000", "006600" },
	["Malawi"] = { "H3", "1A1A1A", "CE1126", "339E35" },
	["Libya"] = { "H3", "E70013", "1A1A1A", "239E46" },
	["Niger"] = { "H3", "E05206", "FFFFFF", "0DB02B" },
	["Gambia"] = { "H3", "CE1126", "0C1C8C", "3A7728" },
	["Algeria"] = { "V2", "006233", "FFFFFF" },
	["Morocco"] = { "star", "C1272D", "006233" },
	["Tunisia"] = { "disc", "E70013", "FFFFFF" },
	["Mauritania"] = { "plain", "00A95C" },
	["Somalia"] = { "star", "4189DD", "FFFFFF" },
	["Tanzania"] = { "diag", "1EB53A", "1A1A1A", "00A3DD" },
	["Dem. Rep. Congo"] = { "diag", "007FFF", "CE1021", "007FFF" },
	["Congo"] = { "diag", "009543", "FBDE4A", "DC241F" },
	["Zambia"] = { "plain", "198A00" },
	["Zimbabwe"] = { "H3", "006400", "FFD200", "D40000" },
	["Mozambique"] = { "H3", "009A44", "1A1A1A", "FCE100" },
	["Angola"] = { "H2", "CC092F", "1A1A1A" },
	["Namibia"] = { "diag", "003580", "D21034", "009543" },
	["Botswana"] = { "H3", "6DA9D2", "1A1A1A", "6DA9D2" },
	["South Africa"] = { "H3", "E03C31", "007749", "001489" },
	["Madagascar"] = { "triangle", "FC3D32", "FC3D32", "007E3A", "FFFFFF" },
	["Uganda"] = { "H3", "1A1A1A", "FCDC04", "D90000" },
	["Rwanda"] = { "H3", "20603D", "FAD201", "00A1DE" },
	["Burkina Faso"] = { "H2", "EF2B2D", "009E49" },
	["Benin"] = { "V2", "008751", "FCD116" },
	["Togo"] = { "H3", "006A4E", "FFCE00", "006A4E" },
	["Liberia"] = { "canton", "BF0A30", "FFFFFF", "002868" },
	["Eritrea"] = { "triangle", "4189DD", "EA0437", "12AD2B", "EA0437" },
	["Central African Rep."] = { "H3", "003082", "FFFFFF", "289728" },
	["Eq. Guinea"] = { "H3", "3E9A00", "FFFFFF", "E32118" },
	["W. Sahara"] = { "H3", "1A1A1A", "FFFFFF", "007A3D" },
	-- Asia / Middle East
	["China"] = { "cstar", "DE2910", "FFDE00" },
	["Japan"] = { "disc", "FFFFFF", "BC002D" },
	["South Korea"] = { "disc", "FFFFFF", "CD2E3A" },
	["North Korea"] = { "H3", "024FA2", "ED1C27", "024FA2" },
	["India"] = { "H3", "FF9933", "FFFFFF", "138808" },
	["Pakistan"] = { "V2", "FFFFFF", "01411C" },
	["Bangladesh"] = { "disc", "006A4E", "F42A41" },
	["Iran"] = { "H3", "239F40", "FFFFFF", "DA0000" },
	["Iraq"] = { "H3", "CE1126", "FFFFFF", "1A1A1A" },
	["Syria"] = { "H3", "CE1126", "FFFFFF", "1A1A1A" },
	["Yemen"] = { "H3", "CE1126", "FFFFFF", "1A1A1A" },
	["Saudi Arabia"] = { "plain", "006C35" },
	["Oman"] = { "plain", "DB161B" },
	["United Arab Emirates"] = { "triangle", "00732F", "FFFFFF", "1A1A1A", "FF0000" },
	["Qatar"] = { "V2", "FFFFFF", "8D1B3D" },
	["Kuwait"] = { "triangle", "007A3D", "FFFFFF", "CE1126", "1A1A1A" },
	["Jordan"] = { "triangle", "1A1A1A", "FFFFFF", "007A3D", "CE1126" },
	["Israel"] = { "H3", "FFFFFF", "0038B8", "FFFFFF" },
	["Lebanon"] = { "H3", "ED1C24", "FFFFFF", "ED1C24" },
	["Afghanistan"] = { "V3", "1A1A1A", "BE0000", "007A36" },
	["Kazakhstan"] = { "disc", "00AFCA", "FEC50C" },
	["Uzbekistan"] = { "H3", "0099B5", "FFFFFF", "1EB53A" },
	["Turkmenistan"] = { "plain", "00843D" },
	["Kyrgyzstan"] = { "disc", "E8112D", "FFEF00" },
	["Tajikistan"] = { "H3", "CC0000", "FFFFFF", "006600" },
	["Mongolia"] = { "V3", "C4272F", "015197", "C4272F" },
	["Nepal"] = { "plain", "DC143C" },
	["Myanmar"] = { "H3", "FECB00", "34B233", "EA2839" },
	["Thailand"] = { "H3", "A51931", "F4F5F8", "2D2A4A" },
	["Vietnam"] = { "star", "DA251D", "FFFF00" },
	["Laos"] = { "H3", "CE1126", "002868", "CE1126" },
	["Cambodia"] = { "H3", "032EA1", "E00025", "032EA1" },
	["Malaysia"] = { "canton", "CC0001", "FFFFFF", "010066" },
	["Indonesia"] = { "H2", "CE1126", "FFFFFF" },
	["Philippines"] = { "triangle", "0038A8", "0038A8", "CE1126", "FFFFFF" },
	["Taiwan"] = { "cstar", "FE0000", "000095" },
	["Sri Lanka"] = { "plain", "FFB700" },
	["Papua New Guinea"] = { "diag", "1A1A1A", "1A1A1A", "CE1126" },
	-- Oceania
	["Australia"] = { "ensign", "00008B" },
	["New Zealand"] = { "ensign", "012169" },
	["Fiji"] = { "ensign", "68BFE5" },
}

-- shop cosmetic flags (Cosmetics.Flags kinds) -> same sampler
local COSMETIC = { triV = "V3", triH = "H3", biH = "H2", cross = "cross", disc = "disc", diag = "diag", star = "star", quarter = "quarter" }
function Flags.fromCosmetic(f: any): Spec?
	if not f then
		return nil
	end
	local kind = COSMETIC[f.kind]
	if not kind then
		return nil
	end
	local s: Spec = { kind }
	for _, c in f.colors do
		table.insert(s, c)
	end
	if kind == "diag" and #s == 3 then
		table.insert(s, s[2]) -- band, then repeat base
		s[3], s[4] = s[3], s[2]
	end
	return s
end

-- 5-point star centred at (cx, cy) with outer radius r (in u,v space with aspect 1.5)
local function inStar(x: number, y: number, cx: number, cy: number, r: number): boolean
	local dx, dy = (x - cx) * 1.5, y - cy
	local ang = math.atan2(dy, dx) + math.pi / 2
	local d = math.sqrt(dx * dx + dy * dy)
	local k = (ang % (2 * math.pi / 5)) / (2 * math.pi / 5)
	local edge = r * (0.42 + 0.58 * math.abs(k * 2 - 1))
	return d < edge
end

function Flags.sample(s: Spec, u: number, v: number): string
	local k = s[1]
	if k == "V3" then
		return if u < 1 / 3 then s[2] elseif u < 2 / 3 then s[3] else s[4]
	elseif k == "H3" then
		return if v < 1 / 3 then s[2] elseif v < 2 / 3 then s[3] else s[4]
	elseif k == "H2" then
		return if v < 0.5 then s[2] else s[3]
	elseif k == "V2" then
		return if u < 0.4 then s[2] else s[3]
	elseif k == "plain" then
		return s[2]
	elseif k == "cross" then
		local onV = u > 0.30 and u < 0.42
		local onH = v > 0.42 and v < 0.58
		return if onV or onH then s[3] else s[2]
	elseif k == "plus" then
		local onV = u > 0.43 and u < 0.57 and v > 0.2 and v < 0.8
		local onH = v > 0.4 and v < 0.6 and u > 0.25 and u < 0.75
		return if onV or onH then s[3] else s[2]
	elseif k == "disc" then
		return if ((u - 0.5) * 1.5) ^ 2 + (v - 0.5) ^ 2 < 0.09 then s[3] else s[2]
	elseif k == "star" then
		return if inStar(u, v, 0.5, 0.5, 0.3) then s[3] else s[2]
	elseif k == "cstar" then
		return if inStar(u, v, 0.17, 0.27, 0.17) then s[3] else s[2]
	elseif k == "canton" then
		local stripes = s[5] or 7
		if u < 0.42 and v < (if stripes == 2 then 0.5 else 0.54) then
			return s[4]
		end
		return if math.floor(v * stripes * (if stripes == 2 then 1 else 1.86)) % 2 == 0 then s[2] else s[3]
	elseif k == "ensign" then
		-- blue field, simplified union canton, white stars
		if u < 0.5 and v < 0.5 then
			return Flags.sample({ "union", "012169", "FFFFFF", "C8102E" }, u * 2, v * 2)
		end
		if inStar(u, v, 0.75, 0.62, 0.07) or inStar(u, v, 0.25, 0.75, 0.09) then
			return "FFFFFF"
		end
		return s[2]
	elseif k == "union" then
		local x, y = u * 1.5, v -- aspect-correct diagonals
		local d1 = math.abs(x / 1.5 - y)
		local d2 = math.abs((1 - x / 1.5) - y)
		local cv, ch = math.abs(u - 0.5), math.abs(v - 0.5)
		if cv < 0.05 or ch < 0.09 then
			return s[4]
		elseif cv < 0.09 or ch < 0.15 then
			return s[3]
		elseif d1 < 0.04 or d2 < 0.04 then
			return s[4]
		elseif d1 < 0.1 or d2 < 0.1 then
			return s[3]
		end
		return s[2]
	elseif k == "diamond" then
		if ((u - 0.5) * 1.5) ^ 2 + (v - 0.5) ^ 2 < 0.05 then
			return s[4]
		end
		return if math.abs(u - 0.5) * 1.1 + math.abs(v - 0.5) < 0.42 then s[3] else s[2]
	elseif k == "diag" then
		local t = u * 0.6 + (1 - v) * 0.4 -- lower-left to upper-right
		return if math.abs(t - 0.5) < 0.09 then s[3] elseif t < 0.5 then s[2] else (s[4] or s[2])
	elseif k == "triangle" then
		if u < 0.4 * (1 - math.abs(v - 0.5) * 2) then
			return s[5] or s[4]
		end
		return if v < 1 / 3 then s[2] elseif v < 2 / 3 then s[3] else s[4]
	elseif k == "quarter" then
		return if u < 0.5 then (if v < 0.5 then s[2] else s[4]) else (if v < 0.5 then s[3] else s[5])
	end
	return s[2] or "FFFFFF"
end

return Flags
