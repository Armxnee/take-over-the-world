--!nonstrict
-- (Take Over the World!: country definitions, 2026-11-06.)
-- The one place a playable country is described. A country is one of the map's nations (its
-- `nations` list: name, flag code, capital position) together with the provinces generated for it
-- (Core/Provinces). Definitions are built per match, the same way on the server (Sim) and on a client
-- (the country picker, from its GameState mirror), so nothing about a country is hardcoded elsewhere.
--
-- A definition:
--   id            "<map>:<slug of the name>"          unique per map
--   owner         the match's owner id of this country (stable for the match)
--   name          display name
--   flag          flag code (Assets/Flags); flag_asset = Countries.flag_asset(flag)
--   ball          Countryball sprite reference: "countryball:<flag>" (UI/Countryball draws it)
--   capital       capital province id; capital_tile, capital_name
--   provinces     starting province ids (the whole region: full borders)
--   population    sum of its provinces' population
--   resources     { gold, income, food, industry, minerals, trade }
--   military      { troops, cap }
--   bonuses       { label, text, gold_mult, troop_growth_mult }
--   difficulty    1 (easiest, the largest countries) .. 5 (hardest); difficulty_name
--
-- OVERRIDES (by flag code, or by "<map>:<slug>") replace derived fields for authored countries.
local Provinces = require("../Core/Provinces")
local CountryGrid = require("./CountryGrid")
local Empires = require("./Empires") -- (Take Over the World!: empire names and flags)

local Countries = {}

--- Starting troops: this share of the country's troop cap.
Countries.START_TROOP_SHARE = 0.35
Countries.DIFFICULTY_NAMES = { "Easy", "Normal", "Hard", "Very Hard", "Extreme" }

--- Authored changes (none yet): e.g. ["fr"] = { bonuses = { label = "...", text = "...", gold_mult = 1.1 } }.
Countries.OVERRIDES = {} :: { [string]: { [string]: any } }

--- National bonuses from geography (first match wins; every country gets one).
Countries.BONUS_RULES = {
	{
		label = "Maritime Trade",
		text = "+10% gold from its long coastline",
		test = function(c)
			return c.coast_share >= 0.18
		end,
		gold_mult = 1.10,
	},
	{
		label = "Mountain Stronghold",
		text = "+10% troop growth from its mountain heartland",
		test = function(c)
			return c.mountain_share >= 0.25
		end,
		troop_growth_mult = 1.10,
	},
	{
		label = "Underdog Spirit",
		text = "+15% troop growth and +5% gold: small, but never beaten",
		test = function(c)
			return c.difficulty >= 4
		end,
		troop_growth_mult = 1.15,
		gold_mult = 1.05,
	},
	{
		label = "Breadbasket",
		text = "+8% gold from its farmland",
		test = function(c)
			return c.plains_share >= 0.6
		end,
		gold_mult = 1.08,
	},
	{
		label = "Steady Nation",
		text = "+5% troop growth",
		test = function()
			return true
		end,
		troop_growth_mult = 1.05,
	},
}

function Countries.slug(name: string): string
	return (string.gsub(string.lower(name), "[^%w]+", "_"))
end

--- Flag code of each nation name on `map` (its nations list).
function Countries.flags_by_name(map: any): { [string]: string }
	local out = {}
	local g = CountryGrid.get(map.id)
	if g ~= nil then
		for _, nd in g.nations do
			if nd[2] ~= "" then
				out[nd[1]] = nd[2]
				-- (Take Over the World!: and the empire it can found, under that empire's flag or its own)
				local e = Empires.of(nd[1])
				out[e.name] = e.flag or nd[2]
			end
		end
		return out
	end
	local list = if type(map.load_nations) == "function" then map:load_nations() else map.nations
	for _, nd in list or {} do
		if type(nd) == "table" and nd.name ~= nil and nd.flag ~= nil then
			out[tostring(nd.name)] = string.lower(tostring(nd.flag))
		end
	end
	return out
end

local _flags: any = nil
--- { image, offset: Vector2, size: Vector2 } for a flag code (Assets/Flags atlases), or nil.
function Countries.flag_asset(code: string?): any?
	if code == nil then
		return nil
	end
	if _flags == nil then
		local ok, m = pcall(function()
			return require("../Assets/Flags")
		end)
		_flags = {}
		if ok and type(m) == "table" then
			for _, f in m.flags or {} do
				_flags[f.code] = {
					image = m.atlases[f.atlas],
					offset = Vector2.new(f.x, f.y),
					size = Vector2.new(f.w, f.h),
				}
			end
		end
	end
	return _flags[string.lower(code)]
end

--- Builds the definitions. `P` = Provinces.build result (named); `src` = {
---   map_id, names = { [owner] = name }, flags = { [owner] = code },
---   max_troops = (tiles) -> number, income = (tiles) -> gold per second, start_gold = number }.
--- Returns defs = { [owner] = def } and a list sorted by name.
function Countries.build(P: any, src: any): ({ [number]: any }, { any })
	local defs = {}
	local list = {}
	-- size ranks for difficulty (largest fifth = 1)
	local sizes = {}
	for owner, ids in P.by_country do
		local tiles = 0
		for _, pid in ids do
			tiles += P.list[pid].tiles
		end
		table.insert(sizes, { owner = owner, tiles = tiles })
	end
	table.sort(sizes, function(a, b)
		return a.tiles > b.tiles or (a.tiles == b.tiles and a.owner < b.owner)
	end)
	local rank = {}
	for i, s in sizes do
		rank[s.owner] = math.clamp(math.ceil(i / math.max(#sizes, 1) * 5), 1, 5)
	end
	for owner, ids in P.by_country do
		local name = src.names[owner] or "Nation"
		local flag = src.flags[owner]
		local tiles, pop, coast, mountain, plains = 0, 0, 0, 0, 0
		local res = { food = 0, industry = 0, minerals = 0, trade = 0 }
		for _, pid in ids do
			local p = P.list[pid]
			tiles += p.tiles
			pop += p.pop
			coast += p.coast
			mountain += p.terrain[4] or 0 -- Defs.T_MOUNTAIN
			plains += p.terrain[2] or 0 -- Defs.T_PLAINS
			for k, v in p.resources or Provinces.resources_of(p) do
				res[k] += v
			end
		end
		local cap_id = P.capital_of[owner]
		local cap = cap_id and P.list[cap_id]
		local cap_troops = src.max_troops(tiles)
		local d = {
			id = (src.map_id or "map") .. ":" .. Countries.slug(name),
			owner = owner,
			name = name,
			flag = flag,
			ball = "countryball:" .. (flag or "xx"),
			capital = cap_id or 0,
			capital_tile = if cap then cap.seed else -1,
			capital_name = if cap then cap.name else name,
			provinces = table.clone(ids),
			tiles = tiles,
			population = pop,
			resources = {
				gold = src.start_gold,
				income = src.income(tiles),
				food = res.food,
				industry = res.industry,
				minerals = res.minerals,
				trade = res.trade,
			},
			military = { troops = math.floor(cap_troops * Countries.START_TROOP_SHARE), cap = cap_troops },
			difficulty = rank[owner] or 3,
		}
		local facts = {
			coast_share = if tiles > 0 then coast / tiles else 0,
			mountain_share = if tiles > 0 then mountain / tiles else 0,
			plains_share = if tiles > 0 then plains / tiles else 0,
			difficulty = d.difficulty,
		}
		for _, r in Countries.BONUS_RULES do
			if r.test(facts) then
				d.bonuses = {
					label = r.label,
					text = r.text,
					gold_mult = r.gold_mult or 1,
					troop_growth_mult = r.troop_growth_mult or 1,
				}
				break
			end
		end
		local ov = Countries.OVERRIDES[d.id] or (flag and Countries.OVERRIDES[flag])
		if ov ~= nil then
			for k, v in ov do
				d[k] = v
			end
		end
		d.difficulty_name = Countries.DIFFICULTY_NAMES[d.difficulty] or "Normal"
		defs[owner] = d
		table.insert(list, d)
	end
	table.sort(list, function(a, b)
		return a.name < b.name
	end)
	return defs, list
end

return Countries
