--!nonstrict
-- (Take Over the World!: supply, logistics and strategic resources, 2026-11-06.)
-- Installed into Sim after SimArmies (stepped by Sim.step; no loop of its own). Server-authoritative:
--
--   resources       national stocks of food, steel, oil, aluminum and rare materials next to the
--                   existing gold. Produced each second by the provinces a country controls (deposits
--                   from Data/Logistics, x farms / steel factories / oil facilities), stored up to a cap,
--                   spent on construction, recruitment (Data/Units `res`) and army supply.
--   infrastructure  province levels: road, rail, depot, farm, steel factory, oil facility; built one job
--                   per province over time, paid and validated here. Ports are the existing port
--                   structure (SimStructures.try_build) and link a country's coast in the network.
--   network         per country, a widest-path search over the province graph (SimArmies._prov_adj)
--                   from its sources (its capital, its depots) through provinces it or its allies
--                   control; link capacity from roads and rails. Cached: recalculated only for countries
--                   marked dirty (ownership, infrastructure, alliances), checked once a second, plus a
--                   slow refresh. Every province gets its bottleneck capacity, source and hops.
--   army supply     each round an army asks for supply (its battalions x activity x terrain) and gets
--                   what its province's link capacity and the source's stock allow; its supply level
--                   rises or falls accordingly, slowly when cut off. Status tiers (Data/Logistics)
--                   scale its combat, recovery and reinforcement; at zero it suffers attrition.
local Defs = require("./Defs")
local Ev = require("./Ev")
local Units = require("../Data/Units")
local Logistics = require("../Data/Logistics")

local readu16, readi32 = buffer.readu16, buffer.readi32

local SimLogistics = {}
local RES = Logistics.RESOURCES
local INFRA = Logistics.INFRA
local INFRA_KEYS = Logistics.INFRA_ORDER

function SimLogistics.install(C: any)
	function C._init_logistics(self: any)
		local P = self.P
		self.l_on = true
		self.l_infra = {} -- pid -> { road, rail, depot, farm, steel, oil, stock }
		self.l_job = {} -- pid -> { id, kind, owner, finish }
		self.l_next_job = 1
		self.l_dep = {} -- pid -> deposits
		self.l_res = {} -- owner -> { food = n, ... }
		self.l_rate = {} -- owner -> { food = n/s, ... } (last second's net production)
		self.l_net = {} -- owner -> { cap = {pid -> n}, src = {pid -> pid}, hops = {pid -> n}, home = {pid -> true} }
		self.l_dirty = {} -- owner -> true
		for pid, p in P.list do
			self.l_infra[pid] = { road = 0, rail = 0, depot = 0, farm = 0, steel = 0, oil = 0, stock = 0 }
			self.l_dep[pid] = Logistics.deposits(p, self.map_id)
		end
		-- starting stocks: a few minutes of each country's production
		for owner in self.country_defs or {} do
			local prod = self:_production(owner)
			local r = {}
			for _, k in RES do
				r[k] = math.floor((Logistics.START_BASE[k] or 0) + (prod[k] or 0) * Logistics.START_SECONDS)
			end
			self.l_res[owner] = r
			self.l_rate[owner] = prod
			self.l_dirty[owner] = true
		end
	end

	function C._stock(self: any, owner: number): { [string]: number }
		local r = self.l_res[owner]
		if r == nil then
			r = { food = 0, steel = 0, oil = 0, aluminum = 0, rare = 0 }
			self.l_res[owner] = r
		end
		return r
	end

	--- Storage cap of each resource for `owner`.
	function C._storage(self: any, owner: number): number
		local cap = Logistics.STORAGE_BASE
		for pid, inf in self.l_infra do
			if self.p_ctrl[pid] == owner then
				cap += inf.depot * Logistics.STORAGE_DEPOT + inf.oil * Logistics.STORAGE_OIL
			end
		end
		return cap
	end

	--- Gross production per second of the provinces `owner` controls.
	function C._production(self: any, owner: number): { [string]: number }
		local out = { food = 0, steel = 0, oil = 0, aluminum = 0, rare = 0 }
		for pid, p in self.P.list do
			if self.p_ctrl[pid] == owner then
				local d = self.l_dep[pid]
				local inf = self.l_infra[pid]
				out.food += d.food * (1 + inf.farm * Logistics.FARM_BONUS)
				out.steel += d.steel + inf.steel * Logistics.STEEL_FACTORY * (if d.steel > 0 then 1.5 else 1)
				out.oil += d.oil * (1 + inf.oil * Logistics.OIL_FACILITY)
				out.aluminum += d.aluminum
				out.rare += d.rare
			end
		end
		return out
	end

	--- True when `owner` can pay `gold` and `res` (resource -> amount).
	function C.can_pay(self: any, owner: number, gold: number, res: { [string]: number }?): boolean
		if self.o_gold[owner] < gold then
			return false
		end
		local s = self:_stock(owner)
		for k, v in res or {} do
			if (s[k] or 0) < v then
				return false
			end
		end
		return true
	end

	function C.pay(self: any, owner: number, gold: number, res: { [string]: number }?)
		self.o_gold[owner] -= gold
		local s = self:_stock(owner)
		for k, v in res or {} do
			s[k] = (s[k] or 0) - v
		end
	end

	-- =========================================================================================
	-- Construction
	-- =========================================================================================

	--- Builds infrastructure `kind` in the province at `tile` (next level). Ports are the existing
	--- port structure. Validated: own and controlled province, level, prerequisites, costs.
	function C.build_infra(self: any, owner: number, kind: string, tile: number): boolean
		if not self.l_on then
			return false
		end
		if kind == "port" then
			local ok = self:try_build(owner, "port", tile)
			if ok then
				self:_mark_dirty(owner)
			end
			return ok == true
		end
		local def = INFRA[kind]
		if def == nil or tile < 0 or tile >= self.N then
			return self:_army_fail(owner, "Unknown construction")
		end
		local pid = self:province_at(tile)
		if pid == 0 or self.p_ctrl[pid] ~= owner or self.p_owner[pid] ~= owner then
			return self:_army_fail(owner, "Build in a province you own and hold")
		end
		if self.l_job[pid] ~= nil then
			return self:_army_fail(owner, "Something is already being built there")
		end
		local inf = self.l_infra[pid]
		local level = inf[kind] + 1
		if level > def.max then
			return self:_army_fail(owner, def.name .. " is at its highest level")
		end
		if def.needs_road and inf.road < def.needs_road then
			return self:_army_fail(owner, "A railway needs a road first")
		end
		if def.needs_deposit and (self.l_dep[pid][def.needs_deposit] or 0) <= 0 then
			return self:_army_fail(owner, "No " .. def.needs_deposit .. " deposit in this province")
		end
		local gold, res = Logistics.cost(kind, level)
		if not self:can_pay(owner, gold, res) then
			return self:_army_fail(owner, "Not enough gold or resources")
		end
		self:pay(owner, gold, res)
		local job = { id = self.l_next_job, kind = kind, owner = owner, finish = self.tick + def.ticks * level, pid = pid }
		self.l_next_job += 1
		self.l_job[pid] = job
		self:_infra_event(pid)
		return true
	end

	function C._infra_event(self: any, pid: number)
		local inf = self.l_infra[pid]
		local job = self.l_job[pid]
		self:ev({
			Ev.INFRA,
			pid,
			inf.road,
			inf.rail,
			inf.depot,
			inf.farm,
			inf.steel,
			inf.oil,
			if job then INFRA[job.kind].code else 0,
			if job then job.finish else 0,
			math.floor(inf.stock),
		})
	end

	function C.infra_rows(self: any): { { any } }
		local out = {}
		if not self.l_on then
			return out
		end
		for pid, inf in self.l_infra do
			local job = self.l_job[pid]
			if job or inf.road + inf.rail + inf.depot + inf.farm + inf.steel + inf.oil > 0 then
				table.insert(out, { pid, inf.road, inf.rail, inf.depot, inf.farm, inf.steel, inf.oil, if job then INFRA[job.kind].code else 0, if job then job.finish else 0, math.floor(inf.stock) })
			end
		end
		return out
	end

	-- =========================================================================================
	-- Network
	-- =========================================================================================

	function C._mark_dirty(self: any, owner: number)
		if self.l_on and owner ~= nil and owner > 0 then
			self.l_dirty[owner] = true
		end
	end

	-- ownership, alliances: the countries involved recalculate
	local prev_ctrl = C._on_province_controller
	function C._on_province_controller(self: any, id: number, was: number, now: number)
		prev_ctrl(self, id, was, now)
		self:_mark_dirty(was)
		self:_mark_dirty(now)
		for _, o in { was, now } do
			if o ~= 0 then
				for _, al in self:allies_of(o) do
					self:_mark_dirty(al)
				end
			end
		end
	end
	local prev_form = C.form_alliance
	function C.form_alliance(self: any, a: number, b: number)
		prev_form(self, a, b)
		self:_mark_dirty(a)
		self:_mark_dirty(b)
	end
	local prev_end = C.end_alliance
	function C.end_alliance(self: any, a: number, b: number, traitor: number, expired: boolean?)
		prev_end(self, a, b, traitor, expired)
		self:_mark_dirty(a)
		self:_mark_dirty(b)
	end

	--- Capacity of the link between neighbouring provinces a and b.
	function C._link(self: any, a: number, b: number): number
		local ia, ib = self.l_infra[a], self.l_infra[b]
		return Logistics.LINK_BASE + Logistics.LINK_ROAD * math.min(ia.road, ib.road) + Logistics.LINK_RAIL * math.min(ia.rail, ib.rail)
	end

	--- Widest-path network of `owner`: from its capital (and, unless `capital_only`, its depots) over
	--- provinces it or its allies control. Returns { cap, src, hops } by province.
	function C._compute_net(self: any, owner: number, capital_only: boolean?): any
		local P = self.P
		local adj = self:_prov_adj()
		local cap, src, hops = {}, {}, {}
		local open = {}
		local cp = P.capital_of[owner]
		if cp ~= nil and self.p_ctrl[cp] == owner then
			cap[cp], src[cp], hops[cp] = Logistics.CAPITAL_OUTPUT, cp, 0
			table.insert(open, cp)
		end
		if not capital_only then
			for pid, inf in self.l_infra do
				if inf.depot > 0 and inf.stock > 0 and self.p_ctrl[pid] == owner then
					local out = Logistics.DEPOT_OUTPUT * inf.depot
					if (cap[pid] or 0) < out then
						cap[pid], src[pid], hops[pid] = out, pid, 0
						table.insert(open, pid)
					end
				end
			end
		end
		-- ports: the country's port provinces are linked by sea lanes
		local ports = {}
		for _, s in self.structs do
			if s.owner == owner and s.kind == Defs.S_PORT then
				local pid = readu16(P.prov_of, s.tile * 2)
				if pid ~= 0 and self.p_ctrl[pid] == owner then
					ports[pid] = true
				end
			end
		end
		local done = {}
		while #open > 0 do
			local bi, best = 1, open[1]
			for i = 2, #open do
				if cap[open[i]] > cap[best] then
					bi, best = i, open[i]
				end
			end
			table.remove(open, bi)
			if done[best] then
				continue
			end
			done[best] = true
			local function relax(nb: number, link: number)
				if done[nb] or not self:_passable(owner, nb) then
					return
				end
				local c = math.min(cap[best], link)
				if c > (cap[nb] or 0) then
					cap[nb], src[nb], hops[nb] = c, src[best], hops[best] + 1
					table.insert(open, nb)
				end
			end
			for _, nb in adj[best] do
				relax(nb, self:_link(best, nb))
			end
			if ports[best] then
				for pp in ports do
					if pp ~= best then
						relax(pp, Logistics.LINK_PORT)
					end
				end
			end
		end
		return { cap = cap, src = src, hops = hops }
	end

	function C._recompute_net(self: any, owner: number)
		local net = self:_compute_net(owner, false)
		net.home = self:_compute_net(owner, true).cap -- (depots linked to the capital refill)
		self.l_net[owner] = net
		self.l_dirty[owner] = nil
		if self:is_human(owner) then
			local packed = {}
			for pid, c in net.cap do
				table.insert(packed, pid * 4096 + math.clamp(math.floor(c), 0, 4095))
			end
			table.sort(packed)
			self:ev({ Ev.SUPPLYNET, owner, packed })
		end
	end

	--- The supply a province gives `owner`'s armies there: capacity after the distance falloff, and
	--- its source (0 = not connected).
	function C.supply_at(self: any, owner: number, pid: number): (number, number)
		local net = self.l_net[owner]
		if net == nil then
			return 0, 0
		end
		local c = net.cap[pid]
		if c == nil or c <= 0 then
			return 0, 0
		end
		local f = math.max(Logistics.HOP_FLOOR, 1 - net.hops[pid] * Logistics.HOP_FALLOFF)
		return c * f, net.src[pid]
	end

	-- =========================================================================================
	-- Army supply (called from SimArmies' round)
	-- =========================================================================================

	--- Supply units per second army `a` uses now.
	function C.army_consumption(self: any, a: any): number
		local use = 0
		for _, k in Units.TYPES do
			use += a.n[k] * Logistics.SUPPLY_USE[k]
		end
		local p = self.P.list[a.prov]
		local terr = if p then p.main_terrain else Defs.T_PLAINS
		return use * (Logistics.ACTIVITY[a.status] or 1) * (Logistics.TERRAIN_USE[terr + 1] or 1)
	end

	--- One supply round (dt seconds) for every army: delivery, resource cost, level, attrition.
	function C._supply_round(self: any, dt: number)
		-- demand by (owner, province)
		local groups = {}
		for _, id in self.army_order do
			local a = self.armies[id]
			if a ~= nil and not a.dead then
				local key = a.owner * 65536 + a.prov
				local g = groups[key]
				if g == nil then
					g = { owner = a.owner, pid = a.prov, armies = {}, demand = 0 }
					groups[key] = g
				end
				a.consumption = self:army_consumption(a)
				g.demand += a.consumption
				table.insert(g.armies, a)
			end
		end
		for _, g in groups do
			local capacity, src = self:supply_at(g.owner, g.pid)
			local ratio = if g.demand > 0 then math.min(1, capacity / g.demand) else 1
			-- the source pays: a depot from its stock, the capital from the national stocks
			if src ~= 0 and g.demand > 0 then
				local want = g.demand * ratio * dt
				local inf = self.l_infra[src]
				if inf.depot > 0 and src ~= self.P.capital_of[g.owner] then
					local give = math.min(want, inf.stock)
					inf.stock -= give
					ratio *= if want > 0 then give / want else 1
					if inf.stock <= 0 then
						self:_mark_dirty(g.owner)
					end
				else
					-- national stocks, by each army's unit mix
					local need = {}
					for _, a in g.armies do
						for _, k in Units.TYPES do
							local units = a.n[k] * Logistics.SUPPLY_USE[k] * ratio * dt
							for r, per in Logistics.SUPPLY_COST[k] do
								need[r] = (need[r] or 0) + units * per
							end
						end
					end
					local s = self:_stock(g.owner)
					local avail = 1
					for r, v in need do
						if v > 0 then
							avail = math.min(avail, (s[r] or 0) / v)
						end
					end
					avail = math.clamp(avail, 0, 1)
					for r, v in need do
						s[r] = math.max(0, (s[r] or 0) - v * avail)
					end
					ratio *= avail
				end
			end
			for _, a in g.armies do
				local before = a.supply
				a.connected = src ~= 0
				a.source = src
				if src == 0 then
					a.supply = math.max(0, a.supply - Logistics.ISOLATED_DRAIN * dt)
				else
					a.supply = math.clamp(a.supply + Logistics.REGEN * ratio * dt - Logistics.UNDER_DRAIN * (1 - ratio) * dt, 0, 1)
				end
				-- attrition when out of supply
				if a.supply <= 0 then
					for _, k in Units.TYPES do
						local d = Units.DEFS[k]
						if a.n[k] > 0 then
							a.carry[k] += a.n[k] * d.hp * Logistics.ATTRITION * dt
							local kills = math.min(a.n[k], math.floor(a.carry[k] / d.hp))
							if kills > 0 then
								a.n[k] -= kills
								a.carry[k] -= kills * d.hp
							end
						end
					end
					if SimLogistics.total(a) <= 0 then
						self:_army_destroy(a, "lost to attrition without supply")
						continue
					end
					a.dirty = true
				end
				if math.abs(a.supply - before) > 0.004 or a.was_connected ~= a.connected then
					a.dirty = true
				end
				a.was_connected = a.connected
			end
		end
	end

	--- Nearest province connected to `owner`'s supply that its armies can walk to from `from`.
	function C.nearest_supplied(self: any, owner: number, from: number): number
		local net = self.l_net[owner]
		if net == nil then
			return 0
		end
		local adj = self:_prov_adj()
		local seen = { [from] = true }
		local q = { from }
		local head = 1
		while head <= #q and head < 400 do
			local p = q[head]
			head += 1
			if (net.cap[p] or 0) > 0 and self:_passable(owner, p) then
				return p
			end
			for _, nb in adj[p] do
				if not seen[nb] and self:_passable(owner, nb) then
					seen[nb] = true
					table.insert(q, nb)
				end
			end
		end
		return 0
	end

	-- =========================================================================================
	-- Tick
	-- =========================================================================================

	function C._logistics_tick(self: any)
		if not self.l_on then
			return
		end
		local tick = self.tick
		-- construction finishes
		for pid, job in self.l_job do
			if tick >= job.finish then
				self.l_job[pid] = nil
				if self.p_ctrl[pid] == job.owner then
					self.l_infra[pid][job.kind] += 1
					if self:is_human(job.owner) then
						self:msg(job.owner, Defs.MSG_GOOD, string.format("%s built in %s", INFRA[job.kind].name, self.P.list[pid].name))
					end
				end
				self:_mark_dirty(job.owner)
				for o in self.l_net do
					if self.l_net[o].cap[pid] then
						self:_mark_dirty(o)
					end
				end
				self:_infra_event(pid)
			end
		end
		-- networks: dirty ones on the next tick (a capture cuts a route at once), every country with
		-- armies / players now and then
		local refresh = tick % Logistics.REFRESH_TICKS == 0
		local wants = {}
		for _, id in self.army_order do
			local a = self.armies[id]
			if a ~= nil and not a.dead then
				wants[a.owner] = true
			end
		end
		for _, h in self.humans do
			wants[h] = true
		end
		for owner in wants do
			if self.o_alive[owner] == 1 and (self.l_dirty[owner] or refresh or self.l_net[owner] == nil) then
				self:_recompute_net(owner)
			end
		end
		if tick % 10 ~= 0 then
			return
		end
		-- resources: production, storage cap, depot refills (each second)
		for owner = 1, self.owner_total do
			if self.o_alive[owner] == 1 and self.o_spawned[owner] == 1 and self.l_res[owner] ~= nil then
				local prod = self:_production(owner)
				local s = self:_stock(owner)
				local cap = self:_storage(owner)
				for _, k in RES do
					s[k] = math.min(cap, (s[k] or 0) + prod[k])
				end
				self.l_rate[owner] = prod
			end
		end
		for pid, inf in self.l_infra do
			if inf.depot > 0 then
				local owner = self.p_ctrl[pid]
				local net = self.l_net[owner]
				local room = Logistics.DEPOT_STORAGE * inf.depot - inf.stock
				if room > 0 and net ~= nil and net.home ~= nil and (net.home[pid] or 0) > 0 then
					local s = self:_stock(owner)
					local add = math.min(room, Logistics.DEPOT_REFILL * inf.depot, s.food or 0)
					if add > 0 then
						s.food -= add
						local was_empty = inf.stock <= 0
						inf.stock += add
						if was_empty then
							self:_mark_dirty(owner)
						end
					end
				end
			end
		end
		-- the players' stocks to clients, once a second
		for _, h in self.humans do
			if self.o_alive[h] == 1 then
				local s = self:_stock(h)
				local r = self.l_rate[h] or {}
				self:ev({
					Ev.RES,
					h,
					math.floor(s.food),
					math.floor(s.steel),
					math.floor(s.oil),
					math.floor(s.aluminum),
					math.floor(s.rare),
					math.floor((r.food or 0) * 10),
					math.floor((r.steel or 0) * 10),
					math.floor((r.oil or 0) * 10),
					math.floor((r.aluminum or 0) * 10),
					math.floor((r.rare or 0) * 10),
					self:_storage(h),
				})
			end
		end
	end

	--- Snapshot rows: the players' stocks and networks.
	function C.logistics_rows(self: any): any
		if not self.l_on then
			return nil
		end
		local res, nets = {}, {}
		for _, h in self.humans do
			local s = self:_stock(h)
			local r = self.l_rate[h] or {}
			table.insert(res, { h, math.floor(s.food), math.floor(s.steel), math.floor(s.oil), math.floor(s.aluminum), math.floor(s.rare),
				math.floor((r.food or 0) * 10), math.floor((r.steel or 0) * 10), math.floor((r.oil or 0) * 10), math.floor((r.aluminum or 0) * 10), math.floor((r.rare or 0) * 10), self:_storage(h) })
			local net = self.l_net[h]
			if net ~= nil then
				local packed = {}
				for pid, c in net.cap do
					table.insert(packed, pid * 4096 + math.clamp(math.floor(c), 0, 4095))
				end
				table.insert(nets, { h, packed })
			end
		end
		return { res = res, infra = self:infra_rows(), nets = nets }
	end
end

function SimLogistics.total(a: any): number
	return a.n.infantry + a.n.tank + a.n.artillery
end

return SimLogistics
