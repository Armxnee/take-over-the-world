--!nonstrict
-- (Take Over the World!: armies and real-time ground warfare, 2026-11-06.)
-- Server-authoritative armies on top of the existing simulation (installed into Sim like SimState's
-- parts; stepped by Sim.step, no loop of its own):
--
--   recruiting   battalions (Data/Units) cost the country's existing troop pool (men) and gold
--   movement     orders route over the province graph (Core/Provinces adjacency) through provinces the
--                army's country or its allies control; an army walks tile by tile, segment by segment
--                (province centre to province centre), at the speed of its slowest unit x the terrain x
--                infrastructure. Clients see it through the existing unit events (UNIT_ADD / UNIT_PATH
--                / UNIT_MOVE / UNIT_DEL: the same path interpolation as ships) plus Ev.ARMY for the
--                composition and condition, sent only when something changed.
--   combat       an attack order walks to a province next to the target and starts a battle for the
--                target province: the attackers against the defender's armies there and its garrison (a
--                slice of the defender's troop pool, dug in). Rounds every ROUND_TICKS, deterministic:
--                unit roles (soft / hard attack, armour, artillery support and pierce), terrain,
--                fortifications, numbers, supply, morale and organization.
--   occupation   when the defence is broken the province's tiles of the defender pass to the attacker
--                (SimState.set_owner: province occupation, visuals and client sync as for any conquest).
--                A movement order never captures anything.
--   retreat      manual (casualties) or automatic at critical morale / organization
--   reinforce    tops an army up to its best composition at full price, in supply only
local Defs = require("./Defs")
local Ev = require("./Ev")
local Units = require("../Data/Units")

local readu16, readi32 = buffer.readu16, buffer.readi32

local SimArmies = {}

SimArmies.STATUS = { idle = 0, moving = 1, combat = 2, retreating = 3 }
local STATUS = SimArmies.STATUS
local TYPES = Units.TYPES
local DEFS = Units.DEFS

local function total(a: any): number
	return a.n.infantry + a.n.tank + a.n.artillery
end
SimArmies.total = total

-- tiles of the straight line from a to b (Bresenham), both ends included
local function line(W: number, a: number, b: number): { number }
	local x0, y0 = a % W, a // W
	local x1, y1 = b % W, b // W
	local dx, dy = math.abs(x1 - x0), -math.abs(y1 - y0)
	local sx = if x0 < x1 then 1 else -1
	local sy = if y0 < y1 then 1 else -1
	local err = dx + dy
	local out = {}
	while true do
		table.insert(out, y0 * W + x0)
		if x0 == x1 and y0 == y1 then
			break
		end
		local e2 = 2 * err
		if e2 >= dy then
			err += dy
			x0 += sx
		end
		if e2 <= dx then
			err += dx
			y0 += sy
		end
	end
	return out
end
SimArmies.line = line

function SimArmies.install(C: any)
	function C._init_armies(self: any)
		self.armies = {} :: { [number]: any }
		self.army_order = {} :: { number }
		self.battles = {} :: { [number]: any }
		self._army_seq = {} :: { [number]: number }
		self._padj = nil
	end

	-- =========================================================================================
	-- Province graph
	-- =========================================================================================

	--- Province adjacency over land (built once, from the province grid).
	function C._prov_adj(self: any): { [number]: { number } }
		if self._padj ~= nil then
			return self._padj
		end
		local P = self.P
		local W, N = self.W, self.N
		local prov_of = P.prov_of
		local seen = {}
		local adj = {}
		for id = 1, #P.list do
			adj[id] = {}
		end
		local function link(a: number, b: number)
			local k = if a < b then a * 65536 + b else b * 65536 + a
			if not seen[k] then
				seen[k] = true
				table.insert(adj[a], b)
				table.insert(adj[b], a)
			end
		end
		for t = 0, N - 1 do
			local p = readu16(prov_of, t * 2)
			if p ~= 0 then
				if t % W < W - 1 then
					local q = readu16(prov_of, (t + 1) * 2)
					if q ~= 0 and q ~= p then
						link(p, q)
					end
				end
				if t + W < N then
					local q = readu16(prov_of, (t + W) * 2)
					if q ~= 0 and q ~= p then
						link(p, q)
					end
				end
			end
		end
		self._padj = adj
		return adj
	end

	--- True when `owner`'s armies may walk through province `pid` (its own or an ally's).
	function C._passable(self: any, owner: number, pid: number): boolean
		local ctrl = self.p_ctrl[pid]
		return ctrl == owner or (ctrl ~= 0 and self:allied(owner, ctrl))
	end

	--- Cheapest route of provinces from `from` to `to` (excluding `from`) through passable
	--- provinces; with `into_hostile`, `to` itself need not be passable (an attack's target). nil when
	--- there is none.
	function C._route(self: any, owner: number, from: number, to: number, into_hostile: boolean?, through: number?): { number }?
		if from == to then
			return {}
		end
		local adj = self:_prov_adj()
		local list = self.P.list
		local dist = { [from] = 0 }
		local prev = {}
		local open = { from }
		local done = {}
		while #open > 0 do
			-- (a few hundred provinces: a linear scan is plenty)
			local bi, best = 1, open[1]
			for i = 2, #open do
				if dist[open[i]] < dist[best] then
					bi, best = i, open[i]
				end
			end
			table.remove(open, bi)
			if best == to then
				break
			end
			if done[best] then
				continue
			end
			done[best] = true
			local pb = list[best]
			for _, nb in adj[best] do
				if done[nb] then
					continue
				end
				local ok = self:_passable(owner, nb) or (into_hostile and nb == to) or (through ~= nil and self.p_ctrl[nb] == through)
				if not ok then
					continue
				end
				local pn = list[nb]
				local dx, dy = pn.cx - pb.cx, pn.cy - pb.cy
				local d = dist[best] + math.sqrt(dx * dx + dy * dy) / (Units.TERRAIN_SPEED[pn.main_terrain + 1] or 1)
				if dist[nb] == nil or d < dist[nb] then
					dist[nb] = d
					prev[nb] = best
					table.insert(open, nb)
				end
			end
		end
		if dist[to] == nil then
			return nil
		end
		local route = {}
		local at = to
		while at ~= from do
			table.insert(route, 1, at)
			at = prev[at]
		end
		return route
	end

	--- Province `pid` has a finished city or factory of its controller (infrastructure) / a defence
	--- post of `owner` (fortification).
	function C._prov_has(self: any, pid: number, kinds: { number }, owner: number): boolean
		for _, s in self.structs do
			if s.owner == owner and table.find(kinds, s.kind) and readu16(self.P.prov_of, s.tile * 2) == pid then
				return true
			end
		end
		return false
	end

	-- =========================================================================================
	-- Events
	-- =========================================================================================

	function C._army_event(self: any, a: any)
		local hp, maxhp = 0, 0
		for _, k in TYPES do
			local h = a.n[k] * DEFS[k].hp
			maxhp += h
			hp += h - (a.carry[k] or 0)
		end
		self:ev({
			Ev.ARMY,
			a.id,
			a.owner,
			a.seq,
			a.n.infantry,
			a.n.tank,
			a.n.artillery,
			if maxhp > 0 then math.floor(100 * math.max(hp, 0) / maxhp + 0.5) else 0,
			math.floor(a.morale * 100 + 0.5),
			math.floor(a.org * 100 + 0.5),
			math.floor(a.supply * 100 + 0.5),
			a.status,
			a.dest_tile,
			a.target_prov,
			a.prov,
		})
		a.dirty = false
	end

	function C.army_rows(self: any): { { any } }
		local out = {}
		for _, id in self.army_order do
			local a = self.armies[id]
			if a ~= nil and not a.dead then
				local hp, maxhp = 0, 0
				for _, k in TYPES do
					local h = a.n[k] * DEFS[k].hp
					maxhp += h
					hp += h - (a.carry[k] or 0)
				end
				table.insert(out, {
					a.id,
					a.owner,
					a.seq,
					a.n.infantry,
					a.n.tank,
					a.n.artillery,
					if maxhp > 0 then math.floor(100 * math.max(hp, 0) / maxhp + 0.5) else 0,
					math.floor(a.morale * 100 + 0.5),
					math.floor(a.org * 100 + 0.5),
					math.floor(a.supply * 100 + 0.5),
					a.status,
					a.dest_tile,
					a.target_prov,
					a.prov,
				})
			end
		end
		return out
	end

	-- armies travel in the snapshot's unit rows like any other unit
	local prev_rows = C.unit_rows
	function C.unit_rows(self: any): { { any } }
		local out = prev_rows(self)
		for _, id in self.army_order or {} do
			local a = self.armies[id]
			if a ~= nil and not a.dead then
				table.insert(out, {
					a.id,
					Defs.U_ARMY,
					a.owner,
					a.seg_path or { a.tile },
					a.seg_start or self.tick,
					math.floor((a.seg_tpt or 10) * 100),
					total(a),
					0,
					0,
					0,
					a.status,
					a.dest_tile,
				})
			end
		end
		return out
	end

	function C._army_fail(self: any, owner: number, text: string): boolean
		if self:is_human(owner) then
			self:msg(owner, Defs.MSG_INFO, text)
		end
		return false
	end

	-- =========================================================================================
	-- Orders (validated here; the client's request is only a request)
	-- =========================================================================================

	--- Recruits `count` battalions of `kind`: a new army at `tile` (uid 0) or into army `uid`.
	function C.army_recruit(self: any, owner: number, uid: number, tile: number, kind: string, count: number): boolean
		if not self._prov_on then
			return false
		end
		local def = DEFS[kind]
		if def == nil or count < 1 or count > Units.MAX_RECRUIT or count ~= math.floor(count) then
			return self:_army_fail(owner, "Invalid recruitment order")
		end
		local a = nil
		local pid
		-- several unit types for one new army arrive as several orders in the same tick: one army
		local fresh = self._new_army and self._new_army[owner]
		if uid == 0 and fresh ~= nil and fresh.tick == self.tick and tile >= 0 and self:province_at(tile) == fresh.pid then
			uid = fresh.id
		end
		if uid ~= 0 then
			a = self.armies[uid]
			if a == nil or a.dead or a.owner ~= owner then
				return false
			end
			if a.status ~= STATUS.idle then
				return self:_army_fail(owner, "Units join an army that is standing still")
			end
			pid = a.prov
			if self.p_ctrl[pid] ~= owner then
				return self:_army_fail(owner, "Units join an army in your own territory")
			end
			if total(a) + count > Units.MAX_BATTALIONS then
				return self:_army_fail(owner, "That army is full")
			end
		else
			if tile < 0 or tile >= self.N or readi32(self.owner, tile * 4) ~= owner then
				return self:_army_fail(owner, "Recruit in your own territory")
			end
			pid = self:province_at(tile)
			if pid == 0 or self.p_ctrl[pid] ~= owner or self.p_owner[pid] ~= owner then
				return self:_army_fail(owner, "Recruit in a province you own")
			end
			if self.battles[pid] ~= nil then
				return self:_army_fail(owner, "That province is under attack")
			end
			local n = 0
			for _, id in self.army_order do
				local x = self.armies[id]
				if x ~= nil and not x.dead and x.owner == owner then
					n += 1
				end
			end
			if n >= Units.MAX_ARMIES then
				return self:_army_fail(owner, "You command the most armies allowed")
			end
		end
		local gold, men = Units.cost(kind, count)
		if self.o_gold[owner] < gold then
			return self:_army_fail(owner, "Not enough gold")
		end
		if self.o_troops[owner] < men then
			return self:_army_fail(owner, "Not enough troops")
		end
		self.o_gold[owner] -= gold
		self.o_troops[owner] -= men
		if a == nil then
			local seed = self.P.list[pid].seed
			local at = if readi32(self.owner, seed * 4) == owner then seed else tile
			local seq = (self._army_seq[owner] or 0) + 1
			self._army_seq[owner] = seq
			a = {
				id = self.next_uid,
				owner = owner,
				seq = seq,
				n = { infantry = 0, tank = 0, artillery = 0 },
				best = { infantry = 0, tank = 0, artillery = 0 },
				carry = { infantry = 0, tank = 0, artillery = 0 },
				morale = 1.0,
				org = 1.0,
				supply = 1.0,
				tile = at,
				prov = pid,
				status = STATUS.idle,
				order = "",
				dest_tile = -1,
				target_prov = 0,
				route = {},
				route_i = 0,
				seg_path = { at },
				seg_start = self.tick,
				seg_tpt = 10,
				dead = false,
				dirty = true,
			}
			self.next_uid += 1
			self._new_army = self._new_army or {}
			self._new_army[owner] = { tick = self.tick, pid = pid, id = a.id }
			self.armies[a.id] = a
			table.insert(self.army_order, a.id)
			a.n[kind] += count
			a.best[kind] = math.max(a.best[kind], a.n[kind])
			self:ev({ Ev.UNIT_ADD, a.id, Defs.U_ARMY, owner, { at }, self.tick, 1000, total(a) })
		else
			a.n[kind] += count
			a.best[kind] = math.max(a.best[kind], a.n[kind])
		end
		a.dirty = true
		return true
	end

	-- starts walking route[route_i] (a province) from the army's tile
	function C._army_next_segment(self: any, a: any): boolean
		local pid = a.route[a.route_i]
		if pid == nil then
			return false
		end
		local to = self.P.list[pid].seed
		local path = line(self.W, a.tile, to)
		local p = self.P.list[pid]
		local speed = Units.army_speed(a.n) * (Units.TERRAIN_SPEED[p.main_terrain + 1] or 1)
		local ctrl = self.p_ctrl[pid]
		if ctrl ~= 0 and self:_prov_has(pid, { Defs.S_CITY, Defs.S_FACTORY }, ctrl) then
			speed *= Units.INFRA_SPEED
		end
		local tpt = math.max(1, Defs.TICK_RATE / speed)
		a.seg_path = path
		a.seg_start = self.tick
		a.seg_tpt = tpt
		self:ev({ Ev.UNIT_PATH, a.id, path, self.tick, math.floor(tpt * 100) })
		return true
	end

	function C._army_stop(self: any, a: any)
		a.status = STATUS.idle
		a.order = ""
		a.route = {}
		a.route_i = 0
		a.dest_tile = -1
		a.target_prov = 0
		a.seg_path = { a.tile }
		a.seg_start = self.tick
		self:ev({ Ev.UNIT_MOVE, a.id, a.tile })
		a.dirty = true
	end

	--- Move order: to `tile` in a province `owner` or an ally controls.
	function C.army_move(self: any, owner: number, uid: number, tile: number): boolean
		local a = self.armies[uid]
		if a == nil or a.dead or a.owner ~= owner then
			return false
		end
		if a.status == STATUS.combat or a.status == STATUS.retreating then
			return self:_army_fail(owner, "That army is in battle: retreat first")
		end
		local pid = self:province_at(tile)
		if pid == 0 then
			return self:_army_fail(owner, "Armies march on land")
		end
		if not self:_passable(owner, pid) then
			return self:_army_fail(owner, "Use an attack order for enemy land")
		end
		local route = self:_route(owner, a.prov, pid, false)
		if route == nil then
			return self:_army_fail(owner, "No route through your territory")
		end
		if #route == 0 then
			self:_army_stop(a)
			return true
		end
		a.order = "move"
		a.route = route
		a.route_i = 1
		a.dest_tile = self.P.list[pid].seed
		a.target_prov = 0
		a.status = STATUS.moving
		self:_army_next_segment(a)
		a.dirty = true
		return true
	end

	--- Attack order: the province at `tile`, controlled by a country `owner` may fight.
	function C.army_attack(self: any, owner: number, uid: number, tile: number): boolean
		local a = self.armies[uid]
		if a == nil or a.dead or a.owner ~= owner then
			return false
		end
		if a.status == STATUS.combat or a.status == STATUS.retreating then
			return self:_army_fail(owner, "That army is in battle: retreat first")
		end
		local pid = self:province_at(tile)
		if pid == 0 then
			return self:_army_fail(owner, "Armies attack on land")
		end
		local ctrl = self.p_ctrl[pid]
		if ctrl == owner or (ctrl ~= 0 and self:allied(owner, ctrl)) then
			return self:_army_fail(owner, "That province is already yours: use a move order")
		end
		if ctrl ~= 0 and self:shielded(ctrl) and self.o_kind[ctrl] == Defs.KIND_HUMAN then
			return self:_army_fail(owner, self.o_name[ctrl] .. " is still protected")
		end
		local route = self:_route(owner, a.prov, pid, true)
		if route == nil and ctrl ~= 0 then
			-- a target deeper in that country: the army attacks its first province on the way there
			route = self:_route(owner, a.prov, pid, true, ctrl)
			if route ~= nil then
				for i, q in route do
					if not self:_passable(owner, q) then
						pid = q
						route = table.move(route, 1, i, 1, {})
						break
					end
				end
			end
		end
		if route == nil or #route == 0 then
			return self:_army_fail(owner, "No route to that province")
		end
		local b = self.battles[pid]
		if b ~= nil and b.attacker ~= owner then
			return self:_army_fail(owner, "Another country is already attacking there")
		end
		table.remove(route) -- the army stops next to the target and fights from there
		a.order = "attack"
		a.route = route
		a.route_i = 1
		a.dest_tile = self.P.list[pid].seed
		a.target_prov = pid
		if #route == 0 then
			self:_army_engage(a)
		else
			a.status = STATUS.moving
			self:_army_next_segment(a)
		end
		a.dirty = true
		return true
	end

	--- Retreat order: out of battle (with losses) to the army's own side of the front.
	function C.army_retreat(self: any, owner: number, uid: number): boolean
		local a = self.armies[uid]
		if a == nil or a.dead or a.owner ~= owner then
			return false
		end
		if a.status ~= STATUS.combat and a.status ~= STATUS.moving then
			return self:_army_fail(owner, "That army is not fighting or marching")
		end
		self:_army_retreat(a, true)
		return true
	end

	function C._army_retreat(self: any, a: any, manual: boolean)
		local was_combat = a.status == STATUS.combat
		self:_army_leave_battle(a)
		if was_combat then
			for _, k in TYPES do
				local lost = math.ceil(a.n[k] * Units.RETREAT_LOSS)
				a.n[k] = math.max(0, a.n[k] - lost)
			end
			a.org = math.min(a.org, 0.3)
		end
		if total(a) <= 0 then
			self:_army_destroy(a, "destroyed while retreating")
			return
		end
		-- back to the nearest province of its own side: where it stands if that is still its own
		local home = a.prov
		if not self:_passable(a.owner, home) then
			home = 0
			for _, nb in self:_prov_adj()[a.prov] do
				if self:_passable(a.owner, nb) then
					home = nb
					break
				end
			end
		end
		if home == 0 then
			self:_army_stop(a) -- surrounded: it stands its ground
			return
		end
		a.order = "retreat"
		a.target_prov = 0
		if home == a.prov then
			a.route = { home }
		else
			a.route = { home }
		end
		a.route_i = 1
		a.dest_tile = self.P.list[home].seed
		a.status = STATUS.retreating
		a.retreat_until = self.tick + Units.RETREAT_TICKS
		self:_army_next_segment(a)
		a.dirty = true
		if not manual and self:is_human(a.owner) then
			self:msg(a.owner, Defs.MSG_BAD, self:_army_label(a) .. " is falling back")
		end
	end

	--- Disband order: men partly back to the troop pool; never in battle.
	function C.army_disband(self: any, owner: number, uid: number): boolean
		local a = self.armies[uid]
		if a == nil or a.dead or a.owner ~= owner then
			return false
		end
		if a.status == STATUS.combat or a.status == STATUS.retreating then
			return self:_army_fail(owner, "An army can't disband in battle")
		end
		local men = 0
		for _, k in TYPES do
			men += a.n[k] * DEFS[k].men
		end
		self.o_troops[owner] += math.floor(men * Units.DISBAND_REFUND)
		self:_army_destroy(a, nil)
		return true
	end

	--- Merge order: army `other` joins army `uid` (same country, same province, both standing).
	function C.army_merge(self: any, owner: number, uid: number, other: number): boolean
		local a, b = self.armies[uid], self.armies[other]
		if a == nil or b == nil or a.dead or b.dead or a == b or a.owner ~= owner or b.owner ~= owner then
			return false
		end
		if a.status ~= STATUS.idle or b.status ~= STATUS.idle then
			return self:_army_fail(owner, "Armies merge while standing still")
		end
		if a.prov ~= b.prov then
			return self:_army_fail(owner, "Armies merge in the same province")
		end
		if total(a) + total(b) > Units.MAX_BATTALIONS then
			return self:_army_fail(owner, "Too many battalions for one army")
		end
		local ta, tb = total(a), total(b)
		local w = ta / math.max(ta + tb, 1)
		a.morale = a.morale * w + b.morale * (1 - w)
		a.org = a.org * w + b.org * (1 - w)
		a.supply = a.supply * w + b.supply * (1 - w)
		for _, k in TYPES do
			a.n[k] += b.n[k]
			a.carry[k] += b.carry[k]
			a.best[k] = math.max(a.best[k], a.n[k])
		end
		self:_army_destroy(b, nil)
		a.dirty = true
		return true
	end

	--- Reinforce order: back to its best composition, paid in gold and men; in supply, standing.
	function C.army_reinforce(self: any, owner: number, uid: number): boolean
		local a = self.armies[uid]
		if a == nil or a.dead or a.owner ~= owner then
			return false
		end
		if a.status ~= STATUS.idle then
			return self:_army_fail(owner, "Reinforcements reach an army that is standing still")
		end
		if self.p_ctrl[a.prov] ~= owner or a.supply < Units.REINFORCE_MIN_SUPPLY then
			return self:_army_fail(owner, "Reinforcements need a supplied army in your territory")
		end
		local added = 0
		for _, k in TYPES do
			local want = a.best[k] - a.n[k]
			local def = DEFS[k]
			while want > 0 and self.o_gold[owner] >= def.gold and self.o_troops[owner] >= def.men do
				self.o_gold[owner] -= def.gold
				self.o_troops[owner] -= def.men
				a.n[k] += 1
				want -= 1
				added += 1
			end
			a.carry[k] = 0
		end
		if added == 0 then
			return self:_army_fail(owner, "Nothing to reinforce, or not enough gold and troops")
		end
		a.dirty = true
		return true
	end

	function C._army_label(self: any, a: any): string
		local n = a.seq
		local suf = "th"
		if n % 100 < 11 or n % 100 > 13 then
			suf = ({ "st", "nd", "rd" })[n % 10] or "th"
		end
		return string.format("%s's %d%s Army", self.o_name[a.owner], n, suf)
	end

	function C._army_destroy(self: any, a: any, why: string?)
		if a.dead then
			return
		end
		self:_army_leave_battle(a)
		a.dead = true
		self.armies[a.id] = nil
		local i = table.find(self.army_order, a.id)
		if i ~= nil then
			table.remove(self.army_order, i)
		end
		self:ev({ Ev.UNIT_DEL, a.id, if why ~= nil then 1 else 0 })
		if why ~= nil and self:is_human(a.owner) then
			self:msg(a.owner, Defs.MSG_BAD, self:_army_label(a) .. " was " .. why)
		end
	end

	-- =========================================================================================
	-- Battles
	-- =========================================================================================

	--- The army (standing next to its target) starts or joins the battle for a.target_prov.
	function C._army_engage(self: any, a: any)
		local pid = a.target_prov
		local ctrl = self.p_ctrl[pid]
		if ctrl == a.owner or (ctrl ~= 0 and self:allied(a.owner, ctrl)) then
			self:_army_stop(a) -- already ours
			return
		end
		local b = self.battles[pid]
		if b ~= nil and b.attacker ~= a.owner then
			self:_army_fail(a.owner, "Another country is already attacking there")
			self:_army_stop(a)
			return
		end
		if b == nil then
			local garrison = 0
			if ctrl ~= 0 and self.o_tiles[ctrl] > 0 then
				local held = self.p_count[pid][ctrl] or 0
				garrison = self.o_troops[ctrl] * (held / self.o_tiles[ctrl]) * Units.GARRISON_SHARE
			end
			b = {
				pid = pid,
				attacker = a.owner,
				defender = ctrl,
				attackers = {},
				garrison = garrison,
				garrison0 = garrison,
				started = self.tick,
				fort = ctrl ~= 0 and self:_prov_has(pid, { Defs.S_DEFENSE }, ctrl),
			}
			self.battles[pid] = b
			-- attacking a country ends one's own spawn protection, and it remembers
			if ctrl ~= 0 then
				self.o_shield_until[a.owner] = 0
				self:add_grudge(ctrl, a.owner, 600)
				self.o_attacked_tick[ctrl] = self.tick
				if self:is_human(ctrl) then
					self:msg(ctrl, Defs.MSG_ALERT, string.format("%s is attacking %s!", self.o_name[a.owner], self.P.list[pid].name))
				end
			end
		end
		b.attackers[a.id] = true
		a.status = STATUS.combat
		a.order = "attack"
		a.battle = pid
		a.dirty = true
	end

	function C._army_leave_battle(self: any, a: any)
		local pid = a.battle
		if pid == nil then
			return
		end
		a.battle = nil
		local b = self.battles[pid]
		if b ~= nil then
			b.attackers[a.id] = nil
		end
	end

	-- the defender's armies in the battle's province
	function C._battle_defenders(self: any, b: any): { any }
		local out = {}
		for _, id in self.army_order do
			local x = self.armies[id]
			if x ~= nil and not x.dead and x.prov == b.pid and x.status ~= STATUS.retreating
				and x.owner ~= b.attacker and not self:allied(x.owner, b.attacker)
				and (x.owner == b.defender or (b.defender ~= 0 and self:allied(x.owner, b.defender)))
			then
				table.insert(out, x)
			end
		end
		return out
	end

	-- damage one side's armies deal to the other, before the receiver's defence (and the pierce
	-- weighted part separately); enemy mix = share of hard targets
	local function side_damage(armies: { any }, hard_share: number, terrain: number, extra: number?): (number, number)
		local plain, pierce = 0, 0
		for _, a in armies do
			local eff = Units.effectiveness(a.supply, a.org, a.morale)
			for _, k in TYPES do
				local n = a.n[k]
				if n > 0 then
					local d = DEFS[k]
					local dmg = n * (d.soft_attack * (1 - hard_share) + d.hard_attack * hard_share)
						* Units.terrain_attack(d, terrain) * eff
					plain += dmg * (1 - d.pierce)
					pierce += dmg * d.pierce
				end
			end
		end
		local x = extra or 0
		return plain + x, pierce
	end

	local function strength(armies: { any }, garrison_bn: number): number
		local s = garrison_bn * DEFS.infantry.hp
		for _, a in armies do
			for _, k in TYPES do
				s += a.n[k] * DEFS[k].hp
			end
		end
		return s
	end

	local function hard_share(armies: { any }, garrison_bn: number): number
		local hard, all = 0, garrison_bn
		for _, a in armies do
			hard += a.n.tank
			all += total(a)
		end
		return if all > 0 then hard / all else 0
	end

	-- spreads damage `dmg` over armies (and a garrison pool), returns the garrison's damage
	local function take(armies: { any }, garrison_bn: number, dmg: number): (number, { [any]: number })
		local front = garrison_bn
		for _, a in armies do
			front += a.n.infantry + a.n.tank
		end
		local weights = {}
		local W = garrison_bn * DEFS.infantry.hp * Units.GARRISON_ENTRENCH
		for _, a in armies do
			for _, k in TYPES do
				local d = DEFS[k]
				local e = if k == "artillery" then (if front > 0 then d.exposure else d.exposure_alone) else d.exposure
				local w = a.n[k] * d.hp * e
				weights[a] = weights[a] or {}
				weights[a][k] = w
				W += w
			end
		end
		local lost = {}
		if W <= 0 then
			return 0, lost
		end
		for _, a in armies do
			local before = total(a)
			for _, k in TYPES do
				local w = weights[a][k]
				if w > 0 then
					local d = DEFS[k]
					a.carry[k] += dmg * (w / W) / d.defense
					local kills = math.min(a.n[k], math.floor(a.carry[k] / d.hp))
					if kills > 0 then
						a.n[k] -= kills
						a.carry[k] -= kills * d.hp
					end
					if a.n[k] == 0 then
						a.carry[k] = 0
					end
				end
			end
			lost[a] = before - total(a)
			a.dirty = true
		end
		local g = garrison_bn * DEFS.infantry.hp * Units.GARRISON_ENTRENCH
		return dmg * (g / W) / (DEFS.infantry.defense * Units.GARRISON_ENTRENCH), lost
	end

	--- One round of the battle for province `b.pid`. Deterministic.
	function C._battle_round(self: any, b: any)
		local P = self.P
		local p = P.list[b.pid]
		-- the province changed hands meanwhile (a front took it, or the defender is gone)
		local ctrl = self.p_ctrl[b.pid]
		if ctrl == b.attacker then
			self:_battle_won(b)
			return
		end
		if ctrl ~= b.defender then
			self:_battle_end(b)
			return
		end
		local att = {}
		for id in b.attackers do
			local a = self.armies[id]
			if a ~= nil and not a.dead then
				table.insert(att, a)
			else
				b.attackers[id] = nil
			end
		end
		if #att == 0 then
			if self:is_human(b.defender) then
				self:msg(b.defender, Defs.MSG_GOOD, "You held " .. p.name)
			end
			self:_battle_end(b)
			return
		end
		local def = self:_battle_defenders(b)
		for _, x in def do
			if x.status ~= STATUS.combat then
				x.status = STATUS.combat
				x.battle_def = b.pid
				x.dirty = true
			end
		end
		local inf = DEFS.infantry
		local g_bn = b.garrison / inf.men
		if #def == 0 and g_bn < 0.05 then
			self:_battle_won(b)
			return
		end
		local terrain = p.main_terrain
		local bonus = (Units.TERRAIN_DEFENSE[terrain + 1] or 1) * (if b.fort then Units.FORT_BONUS else 1)
		-- damage out
		local s_att = strength(att, 0)
		local s_def = strength(def, g_bn)
		local hs_def = hard_share(def, g_bn)
		local hs_att = hard_share(att, 0)
		local a_plain, a_pierce = side_damage(att, hs_def, terrain)
		local g_out = g_bn * (inf.soft_attack * (1 - hs_att) + inf.hard_attack * hs_att)
		local d_plain, d_pierce = side_damage(def, hs_att, terrain, g_out)
		local scale = Units.DAMAGE_SCALE * Units.ROUND_TICKS / Defs.TICK_RATE
		local to_def = (a_plain / bonus + a_pierce / (1 + (bonus - 1) * 0.4)) * scale
		local to_att = (d_plain + d_pierce) * scale
		if s_att >= s_def * Units.OUTNUMBER then
			to_def *= Units.OUTNUMBER_BONUS
		elseif s_def >= s_att * Units.OUTNUMBER then
			to_att *= Units.OUTNUMBER_BONUS
		end
		-- casualties
		local g_dmg, lost_def = take(def, g_bn, to_def)
		local _, lost_att = take(att, 0, to_att)
		if g_bn > 0 and g_dmg > 0 then
			local men = math.min(b.garrison, g_dmg / inf.hp * inf.men)
			b.garrison -= men
			if b.defender ~= 0 then
				self.o_troops[b.defender] = math.max(0, self.o_troops[b.defender] - men)
			end
		end
		-- morale / organization, destruction, automatic retreat
		local function after(list: { any }, lost: { [any]: number }, org_loss: number)
			for _, a in list do
				if a.dead then
					continue
				end
				local before = total(a) + (lost[a] or 0)
				local frac = if before > 0 then (lost[a] or 0) / before else 0
				a.morale = math.clamp(a.morale - frac * Units.MORALE_LOSS_PER_CASUALTY - Units.MORALE_LOSS_ROUND, 0, 1)
				a.org = math.clamp(a.org - org_loss, 0, 1)
				a.dirty = true
				if total(a) <= 0 then
					self:_army_destroy(a, "destroyed in battle for " .. p.name)
				elseif a.morale < Units.RETREAT_MORALE or a.org < Units.RETREAT_ORG then
					if a.battle ~= nil then
						self:_army_retreat(a, false)
					else
						-- a defender falls back to a neighbouring province of its own side
						a.battle_def = nil
						local home = 0
						for _, nb in self:_prov_adj()[a.prov] do
							if nb ~= b.pid and self:_passable(a.owner, nb) then
								home = nb
								break
							end
						end
						if home ~= 0 then
							a.status = STATUS.idle
							self:army_move(a.owner, a.id, P.list[home].seed)
							a.status = if a.status == STATUS.moving then STATUS.retreating else a.status
							a.retreat_until = self.tick + Units.RETREAT_TICKS
							a.order = "retreat"
						end
					end
				end
			end
		end
		after(att, lost_att, Units.ORG_LOSS_ATTACK)
		after(def, lost_def, Units.ORG_LOSS_DEFEND)
		b.last_round = self.tick
	end

	--- The defence is broken: the defender's tiles in the province pass to the attacker (occupation)
	--- and the attacking armies move in.
	function C._battle_won(self: any, b: any)
		local P = self.P
		local p = P.list[b.pid]
		local att = b.attacker
		local victim = b.defender
		local first = p.first
		for i = 0, p.tiles - 1 do
			local t = readi32(P.tiles, (first + i) * 4)
			local o = readi32(self.owner, t * 4)
			if o == victim and self:claimable(t) then
				self:set_owner(t, att)
			end
		end
		if self:is_human(att) then
			self:msg(att, Defs.MSG_GOOD, "Your army took " .. p.name)
		end
		if victim ~= 0 and self:is_human(victim) then
			self:msg(victim, Defs.MSG_BAD, self.o_name[att] .. " occupied " .. p.name)
		end
		local movers = {}
		for id in b.attackers do
			table.insert(movers, self.armies[id])
		end
		self:_battle_end(b)
		for _, a in movers do
			if a ~= nil and not a.dead then
				a.org = math.max(a.org, 0.2)
				a.order = "move"
				a.route = { b.pid }
				a.route_i = 1
				a.dest_tile = p.seed
				a.target_prov = 0
				a.status = STATUS.moving
				self:_army_next_segment(a)
				a.dirty = true
			end
		end
	end

	function C._battle_end(self: any, b: any)
		self.battles[b.pid] = nil
		for id in b.attackers do
			local a = self.armies[id]
			if a ~= nil and not a.dead then
				a.battle = nil
				if a.status == STATUS.combat then
					self:_army_stop(a)
				end
			end
		end
		for _, id in self.army_order do
			local x = self.armies[id]
			if x ~= nil and x.battle_def == b.pid then
				x.battle_def = nil
				if x.status == STATUS.combat then
					self:_army_stop(x)
				end
			end
		end
	end

	-- =========================================================================================
	-- Tick
	-- =========================================================================================

	function C._armies_tick(self: any)
		if self.armies == nil or not self._prov_on then
			return
		end
		local tick = self.tick
		local round = tick % Units.ROUND_TICKS == 0
		-- movement: arrivals at the end of the current segment
		for _, id in table.clone(self.army_order) do
			local a = self.armies[id]
			if a == nil or a.dead then
				continue
			end
			if self.o_alive[a.owner] == 0 then
				self:_army_destroy(a, nil)
				continue
			end
			if a.status == STATUS.moving or a.status == STATUS.retreating then
				local path = a.seg_path
				local idx = math.floor((tick - a.seg_start) / a.seg_tpt)
				if idx >= #path - 1 and (a.status ~= STATUS.retreating or tick >= (a.retreat_until or 0)) then
					a.tile = path[#path]
					a.prov = a.route[a.route_i] or a.prov
					a.route_i += 1
					local nxt = a.route[a.route_i]
					if nxt == nil then
						if a.order == "attack" and a.target_prov ~= 0 then
							self:_army_engage(a)
						else
							self:_army_stop(a)
						end
					elseif not self:_passable(a.owner, nxt) then
						-- the route was cut (the province fell): stop here
						self:_army_fail(a.owner, self:_army_label(a) .. " stopped: its route was cut")
						self:_army_stop(a)
					else
						self:_army_next_segment(a)
					end
				end
			end
		end
		if round then
			for _, b in table.clone(self.battles) do
				self:_battle_round(b)
			end
			-- supply, upkeep, recovery
			for _, id in self.army_order do
				local a = self.armies[id]
				if a == nil or a.dead then
					continue
				end
				local own = self:_passable(a.owner, a.prov)
				local upkeep = 0
				for _, k in TYPES do
					upkeep += a.n[k] * DEFS[k].upkeep
				end
				upkeep *= Units.ROUND_TICKS / Defs.TICK_RATE
				local paid = self.o_gold[a.owner] >= upkeep
				if paid then
					self.o_gold[a.owner] -= upkeep
				end
				local s0, o0, m0 = a.supply, a.org, a.morale
				if own and paid then
					local regen = Units.SUPPLY_REGEN
					if self.P.capital_of[a.owner] ~= nil and not self:holds_capital(a.owner) then
						regen *= Units.CAPITAL_LOST_SUPPLY
					end
					a.supply = math.min(1, a.supply + regen)
				else
					a.supply = math.max(0, a.supply - Units.SUPPLY_LOSS)
				end
				if a.status ~= STATUS.combat then
					a.org = math.min(1, a.org + Units.ORG_REGEN * a.supply)
					a.morale = math.min(1, a.morale + Units.MORALE_REGEN * a.supply)
				end
				if math.abs(a.supply - s0) + math.abs(a.org - o0) + math.abs(a.morale - m0) > 0.004 then
					a.dirty = true
				end
			end
		end
		for _, id in self.army_order do
			local a = self.armies[id]
			if a ~= nil and a.dirty and not a.dead then
				self:_army_event(a)
			end
		end
	end

	--- An army's state for tests / tools.
	function C.army_info(self: any, uid: number): any?
		local a = self.armies and self.armies[uid]
		if a == nil or a.dead then
			return nil
		end
		return {
			id = a.id,
			owner = a.owner,
			name = self:_army_label(a),
			infantry = a.n.infantry,
			tank = a.n.tank,
			artillery = a.n.artillery,
			total = total(a),
			morale = a.morale,
			org = a.org,
			supply = a.supply,
			status = a.status,
			order = a.order,
			tile = a.tile,
			province = a.prov,
			dest_tile = a.dest_tile,
			target_province = a.target_prov,
			battle = a.battle,
		}
	end
end

return SimArmies
