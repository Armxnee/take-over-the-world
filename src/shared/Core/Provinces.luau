--!nonstrict
-- (Take Over the World!: provinces, 2026-11-06.)
-- Provinces are logical groups of the map's existing tiles: the tile grid, its ownership buffer and
-- the renderer stay as they are, and a province is simply "these tiles". Ownership is still decided
-- tile by tile by the existing combat (SimAttacks); a province's state is derived from its tiles:
--
--   original     the country whose region the province is in (fixed for the match)
--   controller   current occupation: the owner holding the most of its tiles
--   owner        permanent ownership: the original country until the province is annexed — held
--                outright (ANNEX_SHARE of its tiles) for ANNEX_TICKS, or its owner is eliminated;
--                the original country taking it back makes it theirs again
--
-- Generation is deterministic (same map + same capital tiles = same provinces), so a client can build
-- the same grid as the server. Two multi-source breadth-first fills over the tile grid:
--   1. countries: from every country's capital tile over land; land no capital reaches by land
--      (islands) goes to the country whose land is nearest across the water;
--   2. provinces: from the capital tiles and a seed grid (SPACING apart) over land of the seed's own
--      country; land left over (islets) joins the same country's province with the nearest centre.
--
-- Provinces.build is pure; Provinces.install adds the Sim's methods (SimState pattern).
local Defs = require("./Defs")
local Coop = require("../Net/Coop")

local readu8, readu16, writeu16, readi32, writei32 =
	buffer.readu8, buffer.readu16, buffer.writeu16, buffer.readi32, buffer.writei32

local Provinces = {}

--- Seed grid step in tiles: about SPACING x SPACING tiles per province (world map: ~600 provinces).
Provinces.SPACING = 34
--- Annexation: the occupier holds this share of a province's tiles ...
Provinces.ANNEX_SHARE = 0.95
--- ... for this many ticks (10 ticks = 1 s).
Provinces.ANNEX_TICKS = 600
--- How often (ticks) dirty provinces are re-evaluated.
Provinces.EVAL_TICKS = 10
--- People per tile by terrain (population is a game number, not a census).
Provinces.POP_PER_TILE = {
	[Defs.T_PLAINS] = 1200,
	[Defs.T_HIGHLAND] = 700,
	[Defs.T_MOUNTAIN] = 250,
	[Defs.T_TUNDRA] = 120,
	[Defs.T_ICECAP] = 0,
}
Provinces.COAST_POP = 1.3
Provinces.CAPITAL_POP = 3.0
Provinces.TERRAIN_NAMES = {
	[Defs.T_PLAINS] = "Plains",
	[Defs.T_HIGHLAND] = "Highlands",
	[Defs.T_MOUNTAIN] = "Mountains",
	[Defs.T_TUNDRA] = "Tundra",
	[Defs.T_ICECAP] = "Ice",
}
local COMPASS = { "East", "Northeast", "North", "Northwest", "West", "Southwest", "South", "Southeast" }
local ROMAN = { "", " II", " III", " IV", " V", " VI", " VII", " VIII", " IX", " X" }

-- =============================================================================================
-- Generation
-- =============================================================================================

-- multi-source BFS; `label` u16 per tile (0 = none), `queue` holds the seeded tiles [1, qn];
-- `ok(n, lab)` says whether tile n may take label lab
local function fill(W: number, N: number, label: buffer, queue: buffer, qn: number, ok: (number, number) -> boolean)
	local head = 0
	local tail = qn
	local steps = 0
	while head < tail do
		local t = readi32(queue, head * 4)
		head += 1
		local lab = readu16(label, t * 2)
		local x = t % W
		for k = 1, 4 do
			local n
			if k == 1 then
				n = if x > 0 then t - 1 else -1
			elseif k == 2 then
				n = if x < W - 1 then t + 1 else -1
			elseif k == 3 then
				n = t - W
			else
				n = t + W
			end
			if n >= 0 and n < N and readu16(label, n * 2) == 0 and ok(n, lab) then
				writeu16(label, n * 2, lab)
				writei32(queue, tail * 4, n)
				tail += 1
			end
		end
		steps += 1
		if steps % 20000 == 0 then
			Coop.check()
		end
	end
end

--- Builds the provinces of `map` (WorldMap: W, H, N, land buffer, terrain buffer, coastal) for the
--- countries `capitals` = { [country id] = capital tile }. Returns
--- { country_of: buffer (u16 per tile), prov_of: buffer (u16 per tile), list = { province }, by_country =
--- { [country] = { province ids } }, capital_of = { [country] = province id } }.
function Provinces.build(map: any, capitals: { [number]: number }): any
	local W, N = map.W, map.N
	local land: buffer = map.land
	local terr: buffer = map.terrain
	local function is_land(t: number): boolean
		return readu8(land, t) == 1
	end
	local queue = buffer.create(N * 4)

	-- 1. countries over land, in id order (deterministic)
	local country_of = buffer.create(N * 2)
	local ids = {}
	for id in capitals do
		table.insert(ids, id)
	end
	table.sort(ids)
	local qn = 0
	for _, id in ids do
		local t = capitals[id]
		if t >= 0 and t < N and is_land(t) and readu16(country_of, t * 2) == 0 then
			writeu16(country_of, t * 2, id)
			writei32(queue, qn * 4, t)
			qn += 1
		end
	end
	fill(W, N, country_of, queue, qn, function(n)
		return is_land(n)
	end)
	Coop.check()
	-- 1b. land no capital reaches by land: nearest country across the water
	local reach = buffer.create(N * 2)
	qn = 0
	local stranded = false
	for t = 0, N - 1 do
		local c = readu16(country_of, t * 2)
		if c ~= 0 then
			writeu16(reach, t * 2, c)
			writei32(queue, qn * 4, t)
			qn += 1
		elseif is_land(t) then
			stranded = true
		end
		if t % 200000 == 0 then
			Coop.check()
		end
	end
	if stranded and qn > 0 then
		fill(W, N, reach, queue, qn, function()
			return true
		end)
		for t = 0, N - 1 do
			if is_land(t) and readu16(country_of, t * 2) == 0 then
				writeu16(country_of, t * 2, readu16(reach, t * 2))
			end
		end
	end
	reach = nil :: any
	Coop.check()

	-- 2. provinces: capital seeds first (ids 1..#capitals), then the seed grid
	local prov_of = buffer.create(N * 2)
	local list = {}
	local function new_prov(country: number, seed: number, capital: boolean): number
		local id = #list + 1
		list[id] = { id = id, country = country, seed = seed, capital = capital }
		writeu16(prov_of, seed * 2, id)
		return id
	end
	qn = 0
	local capital_of = {}
	for _, id in ids do
		local t = capitals[id]
		if t >= 0 and t < N and is_land(t) and readu16(country_of, t * 2) == id and readu16(prov_of, t * 2) == 0 then
			capital_of[id] = new_prov(id, t, true)
			writei32(queue, qn * 4, t)
			qn += 1
		end
	end
	local S = Provinces.SPACING
	local H = N // W
	for y = S // 2, H - 1, S do
		for x = S // 2, W - 1, S do
			local t = y * W + x
			local c = readu16(country_of, t * 2)
			if c ~= 0 and is_land(t) and readu16(prov_of, t * 2) == 0 then
				new_prov(c, t, false)
				writei32(queue, qn * 4, t)
				qn += 1
			end
		end
	end
	fill(W, N, prov_of, queue, qn, function(n, lab)
		return is_land(n) and readu16(country_of, n * 2) == list[lab].country
	end)
	Coop.check()

	-- stats per province (tiles, centre, terrain, coast)
	for _, p in list do
		p.tiles = 0
		p.sx = 0
		p.sy = 0
		p.coast = 0
		p.terrain = {}
		p.pop = 0
	end
	local leftover = {}
	for t = 0, N - 1 do
		if is_land(t) then
			local id = readu16(prov_of, t * 2)
			if id == 0 then
				table.insert(leftover, t)
			else
				local p = list[id]
				p.tiles += 1
				p.sx += t % W
				p.sy += t // W
			end
		end
		if t % 200000 == 0 then
			Coop.check()
		end
	end
	-- islets: the same country's province with the nearest centre
	if #leftover > 0 then
		local by_c = {}
		for _, p in list do
			if p.tiles > 0 then
				by_c[p.country] = by_c[p.country] or {}
				table.insert(by_c[p.country], p)
			end
		end
		for i, t in leftover do
			local c = readu16(country_of, t * 2)
			local x, y = t % W, t // W
			local best, bd = nil, math.huge
			for _, p in by_c[c] or {} do
				local dx, dy = p.sx / p.tiles - x, p.sy / p.tiles - y
				local d = dx * dx + dy * dy
				if d < bd then
					best, bd = p, d
				end
			end
			if best ~= nil then
				writeu16(prov_of, t * 2, best.id)
			end
			if i % 5000 == 0 then
				Coop.check()
			end
		end
	end

	-- drop empty provinces (a seed that lost every tile cannot happen, but keep ids dense anyway)
	-- and gather each province's tiles (CSR: offsets into one tile buffer), terrain and coast
	local count = table.create(#list, 0)
	for t = 0, N - 1 do
		local id = readu16(prov_of, t * 2)
		if id ~= 0 then
			count[id] += 1
		end
	end
	local offs = table.create(#list + 1, 0)
	local acc = 0
	for id = 1, #list do
		offs[id] = acc
		acc += count[id]
	end
	offs[#list + 1] = acc
	local tiles = buffer.create(math.max(acc, 1) * 4)
	local fillp = table.clone(offs)
	for _, p in list do
		p.tiles = 0
		p.sx = 0
		p.sy = 0
	end
	local pop_per = Provinces.POP_PER_TILE
	for t = 0, N - 1 do
		local id = readu16(prov_of, t * 2)
		if id ~= 0 then
			writei32(tiles, fillp[id] * 4, t)
			fillp[id] += 1
			local p = list[id]
			p.tiles += 1
			p.sx += t % W
			p.sy += t // W
			local tr = readu8(terr, t)
			p.terrain[tr] = (p.terrain[tr] or 0) + 1
			local coastal = map:is_coastal(t)
			if coastal then
				p.coast += 1
			end
			p.pop += (pop_per[tr] or 0) * (if coastal then Provinces.COAST_POP else 1)
		end
		if t % 200000 == 0 then
			Coop.check()
		end
	end
	local by_country = {}
	for _, p in list do
		p.first = offs[p.id]
		p.cx = if p.tiles > 0 then p.sx / p.tiles else p.seed % W
		p.cy = if p.tiles > 0 then p.sy / p.tiles else p.seed // W
		p.sx, p.sy = nil, nil
		local best, bn = Defs.T_PLAINS, -1
		for tr, n in p.terrain do
			if n > bn then
				best, bn = tr, n
			end
		end
		p.main_terrain = best
		if p.capital then
			p.pop *= Provinces.CAPITAL_POP
		end
		p.pop = math.floor(p.pop + 0.5)
		by_country[p.country] = by_country[p.country] or {}
		table.insert(by_country[p.country], p.id)
	end
	return {
		W = W,
		country_of = country_of,
		prov_of = prov_of,
		tiles = tiles,
		list = list,
		by_country = by_country,
		capital_of = capital_of,
	}
end

--- Names the provinces of `P` from their countries' names: the capital province is "<country>
--- Capital", the others "<compass> <country>" from the capital, numbered when repeated.
function Provinces.name_all(P: any, name_of: (number) -> string)
	local used = {}
	for _, p in P.list do
		local cname = name_of(p.country)
		if p.capital then
			p.name = cname .. " Capital"
		else
			local cap = P.list[P.capital_of[p.country] or 0]
			local dir = "Central"
			if cap ~= nil then
				local dx, dy = p.cx - cap.cx, cap.cy - p.cy
				if dx * dx + dy * dy > 64 then
					local a = math.atan2(dy, dx)
					dir = COMPASS[(math.floor((a / (math.pi / 4)) + 0.5) % 8) + 1]
				end
			end
			local base = dir .. " " .. cname
			used[base] = (used[base] or 0) + 1
			p.name = base .. (ROMAN[used[base]] or (" " .. used[base]))
		end
	end
end

--- Province `id`'s tiles (a list; the "associated map tiles").
function Provinces.tiles_of(P: any, id: number): { number }
	local p = P.list[id]
	local out = table.create(p.tiles)
	for i = 0, p.tiles - 1 do
		out[i + 1] = readi32(P.tiles, (p.first + i) * 4)
	end
	return out
end

--- Province resources: what its land yields (game numbers derived from terrain and coast).
function Provinces.resources_of(p: any): { [string]: number }
	local tr = p.terrain
	return {
		food = (tr[Defs.T_PLAINS] or 0) * 2 + (tr[Defs.T_HIGHLAND] or 0),
		industry = (tr[Defs.T_HIGHLAND] or 0) * 2 + (tr[Defs.T_PLAINS] or 0) // 2,
		minerals = (tr[Defs.T_MOUNTAIN] or 0) * 3 + (tr[Defs.T_TUNDRA] or 0),
		trade = p.coast * 3,
	}
end

--- Strategic importance 1..10: capitals, size, coast.
function Provinces.importance_of(p: any, avg_tiles: number): number
	local v = 2
	if p.capital then
		v += 5
	end
	if p.tiles > avg_tiles * 1.5 then
		v += 1
	end
	if p.coast > 0 then
		v += 1
	end
	if (p.terrain[Defs.T_MOUNTAIN] or 0) > p.tiles * 0.3 then
		v += 1
	end
	return math.clamp(v, 1, 10)
end

-- =============================================================================================
-- Sim integration (installed into Sim: provinces on top of tile ownership)
-- =============================================================================================

function Provinces.install(C: any)
	--- Builds the provinces from the countries' capital tiles and starts tracking them. With
	--- `full_borders`, every country claims all of its region (Take Over the World!'s start).
	function C._init_provinces(self: any, capitals: { [number]: number }, full_borders: boolean)
		local P = Provinces.build(self.map, capitals)
		Provinces.name_all(P, function(id)
			return self.o_name[id] or "Nation"
		end)
		self.P = P
		local np = #P.list
		-- per province: tiles held per owner, controller, permanent owner, annexation clock
		self.p_count = table.create(np)
		self.p_ctrl = table.create(np, 0)
		self.p_owner = table.create(np, 0)
		self.p_since = table.create(np, 0)
		self.p_dirty = {}
		local avg = 0
		for _, p in P.list do
			avg += p.tiles
		end
		avg = if np > 0 then avg / np else 1
		for id, p in P.list do
			self.p_count[id] = {}
			self.p_owner[id] = p.country
			p.importance = Provinces.importance_of(p, avg)
			p.resources = Provinces.resources_of(p)
		end
		if full_borders then
			local country_of = P.country_of
			for t = 0, self.N - 1 do
				local c = readu16(country_of, t * 2)
				if c ~= 0 and self:claimable(t) and readi32(self.owner, t * 4) ~= c then
					self:set_owner(t, c)
				end
				if t % 4000 == 0 then
					Coop.check()
				end
			end
		end
		-- counts from the tiles as they are now (the hook keeps them up to date from here)
		local owner = self.owner
		local prov_of = P.prov_of
		for t = 0, self.N - 1 do
			local id = readu16(prov_of, t * 2)
			if id ~= 0 then
				local o = readi32(owner, t * 4)
				if o ~= 0 then
					local c = self.p_count[id]
					c[o] = (c[o] or 0) + 1
				end
			end
			if t % 200000 == 0 then
				Coop.check()
			end
		end
		for id = 1, np do
			self.p_ctrl[id] = self:_prov_leader(id)
		end
		self._prov_on = true
	end

	--- set_owner's hook (SimState): keeps the province tile counts current.
	function C._prov_tile_changed(self: any, t: number, old: number, nw: number)
		local id = readu16(self.P.prov_of, t * 2)
		if id == 0 then
			return
		end
		local c = self.p_count[id]
		if old ~= 0 then
			local v = (c[old] or 0) - 1
			c[old] = if v > 0 then v else nil
		end
		if nw ~= 0 then
			c[nw] = (c[nw] or 0) + 1
		end
		self.p_dirty[id] = true
	end

	--- The owner holding the most tiles of province `id` (ties: the current controller, then the
	--- lower id), or 0 when nobody holds any.
	function C._prov_leader(self: any, id: number): number
		local best, bn = 0, 0
		local cur = self.p_ctrl[id]
		for o, n in self.p_count[id] do
			if n > bn or (n == bn and (o == cur or (best ~= cur and o < best))) then
				best, bn = o, n
			end
		end
		return best
	end

	--- Every EVAL_TICKS: occupation changes, annexation, capitals. Server-authoritative (the Sim runs
	--- on the server in multiplayer); clients only ever see the tiles and the messages.
	function C._provinces_tick(self: any)
		if not self._prov_on or self.tick % Provinces.EVAL_TICKS ~= 0 then
			return
		end
		local P = self.P
		local dirty = self.p_dirty
		if next(dirty) ~= nil then
			self.p_dirty = {}
			for id in dirty do
				local was = self.p_ctrl[id]
				local now = self:_prov_leader(id)
				if now ~= was then
					self.p_ctrl[id] = now
					self.p_since[id] = self.tick
					self:_on_province_controller(id, was, now)
				end
			end
		end
		-- annexation (checked every second for the occupied ones)
		for id, p in P.list do
			local ctrl = self.p_ctrl[id]
			local own = self.p_owner[id]
			if ctrl ~= own and ctrl ~= 0 then
				if ctrl == p.country then
					self.p_owner[id] = ctrl -- liberated: back to its original owner
				elseif self.o_alive[own] == 0 then
					self.p_owner[id] = ctrl
				elseif self.tick - self.p_since[id] >= Provinces.ANNEX_TICKS
					and (self.p_count[id][ctrl] or 0) >= p.tiles * Provinces.ANNEX_SHARE
				then
					self.p_owner[id] = ctrl
					if self:is_human(ctrl) then
						self:msg(ctrl, Defs.MSG_GOOD, "You annexed " .. p.name)
					end
				end
			end
		end
	end

	--- Occupation changed hands: the capital rules and the news.
	function C._on_province_controller(self: any, id: number, was: number, now: number)
		local p = self.P.list[id]
		if not p.capital or now == 0 then
			return
		end
		local country = p.country
		if now == country then
			if self:is_human(country) then
				self:msg(country, Defs.MSG_GOOD, "You liberated your capital")
			end
			return
		end
		-- a capital fell: the taker loots it; the country lives on (it is out only when it holds no land)
		local loot = math.floor(self.o_gold[country] * Provinces.CAPITAL_LOOT)
		if loot > 0 and self.o_alive[country] == 1 then
			self.o_gold[country] -= loot
			self.o_gold[now] += loot
		end
		local text = string.format("%s captured the capital of %s", self:name_of(now), self:name_of(country))
		for _, h in self.humans do
			if self.o_alive[h] == 1 and (h == now or h == country) then
				self:msg(h, if h == now then Defs.MSG_GOOD else Defs.MSG_BAD, text)
			end
		end
	end

	--- True while country `id` controls its own capital province.
	function C.holds_capital(self: any, id: number): boolean
		if not self._prov_on then
			return false
		end
		local cap = self.P.capital_of[id]
		return cap ~= nil and self.p_ctrl[cap] == id
	end

	--- Economy multiplier from the capital and national bonuses (Data/Countries): gold, troop growth.
	function C.country_mults(self: any, id: number): (number, number)
		local g, tr = 1.0, 1.0
		local def = self.country_defs and self.country_defs[id]
		if def ~= nil then
			g *= def.bonuses.gold_mult or 1
			tr *= def.bonuses.troop_growth_mult or 1
		end
		if self._prov_on and self.P.capital_of[id] ~= nil then
			if self:holds_capital(id) then
				g *= 1 + Provinces.CAPITAL_GOLD_BONUS
				tr *= 1 + Provinces.CAPITAL_SUPPLY_BONUS
			end
		end
		return g, tr
	end

	--- Province `id`'s state for UI / tests: a fresh table.
	function C.province_info(self: any, id: number): any?
		local p = self._prov_on and self.P.list[id]
		if not p then
			return nil
		end
		local infra = 0
		for _, s in self.structs or {} do
			if type(s) == "table" and s.tile ~= nil and readu16(self.P.prov_of, s.tile * 2) == id then
				infra += 1
			end
		end
		return {
			id = id,
			name = p.name,
			country = p.country,
			original = p.country,
			controller = self.p_ctrl[id],
			owner = self.p_owner[id],
			occupied = self.p_ctrl[id] ~= self.p_owner[id],
			capital = p.capital,
			population = p.pop,
			terrain = Provinces.TERRAIN_NAMES[p.main_terrain] or "Land",
			resources = p.resources,
			infrastructure = infra,
			importance = p.importance,
			tiles = p.tiles,
			centre = p.seed,
		}
	end

	--- The province under tile `t` (0 = none).
	function C.province_at(self: any, t: number): number
		if not self._prov_on or t < 0 or t >= self.N then
			return 0
		end
		return readu16(self.P.prov_of, t * 2)
	end

	--- Country `id`'s territory statistics: provinces it controls, its own it lost, others' it occupies.
	function C.country_stats(self: any, id: number): { [string]: any }
		local held, own_held, lost, occupying = 0, 0, 0, 0
		if self._prov_on then
			for pid, p in self.P.list do
				local ctrl = self.p_ctrl[pid]
				if ctrl == id then
					held += 1
					if p.country == id then
						own_held += 1
					else
						occupying += 1
					end
				elseif p.country == id then
					lost += 1
				end
			end
		end
		return {
			provinces = held,
			home = own_held,
			lost = lost,
			occupying = occupying,
			capital = self:holds_capital(id),
			tiles = self.o_tiles[id] or 0,
		}
	end
end

--- The capital's economic bonus (gold) and supply bonus (troop growth) while its country holds it,
--- and the share of the country's gold its taker loots.
Provinces.CAPITAL_GOLD_BONUS = 0.15
Provinces.CAPITAL_SUPPLY_BONUS = 0.10
Provinces.CAPITAL_LOOT = 0.25

return Provinces
