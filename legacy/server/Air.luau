--!strict
-- Aircraft: short tactical missions from airfields. Air power opens windows for
-- ground troops; only ground troops capture land.
--
-- Mission states (u.data.state): "out" (launch + transit) -> payload / "hold" (fighter
-- patrol) -> "back" (return) -> landed. Aircraft fly straight lines over any land
-- (allied, neutral or hostile); every non-allied AA battery they pass can fire.
-- Rules (provisional, all in Config.Air):
--   * 1 sortie per airfield at a time, turnaround after landing, max airfields per nation.
--   * bombers unlock once you own a finished factory; cost rises with recent strikes.
--   * front strike: defender loses min(share x troops, cap) and the area is suppressed
--     (attackers pay less) for SuppressTime. Building strike: disabled for DisableTime.
--   * the target is rechecked on arrival; if it vanished or turned friendly, the
--     bomber aborts and returns with its payload.
--   * home airfield captured/destroyed: divert to the nearest own airfield in reach,
--     otherwise the aircraft is lost.
--   * fighters engage hostile aircraft in range, fighters first; escorts fly in formation with
--     their bomber and shield it. AA (aircraft) and SAM (missiles) never overlap.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Sim = require(script.Parent.Sim)
local Structures = require(script.Parent.Structures)
local Units = require(script.Parent.Units)
local Path = require(script.Parent.Path)

local A = Config.Air
local AF = Config.Structures.airfield
local AA = Config.Structures.aa
local TR = Config.TickRate

local Air = {}
Air.onEvent = nil :: ((kind: string, info: any) -> ())?
Air.changed = false
Air.sorties = 0 -- launched this round (telemetry)

local turnaround: { [number]: number } = {} -- airfield id -> tick ready
local aaState: { [number]: { ammo: number, next: number } } = {}
local recentStrikes: { [number]: { number } } = {} -- nation -> strike ticks
-- suppression zones: { cell, target (nation), untilTick }
Air.zones = {} :: { any }

function Air.reset()
	turnaround, aaState, recentStrikes = {}, {}, {}
	Air.zones = {}
	Air.changed = true
	Air.sorties = 0
end

local function emit(kind: string, info: any)
	if Air.onEvent then
		Air.onEvent(kind, info)
	end
end

local function dist(a: number, b: number): number
	local W = Sim.W
	return math.sqrt((a % W - b % W) ^ 2 + (a // W - b // W) ^ 2)
end

local function isAircraft(u: Units.Unit): boolean
	return u.kind == "fighter" or u.kind == "bomber"
end

function Air.sortiesFrom(sid: number): number
	local c = 0
	for _, u in Units.list do
		if isAircraft(u) and u.data.airfield == sid then
			c += 1
		end
	end
	return c
end

function Air.bomberCost(nid: number): number
	local list = recentStrikes[nid] or {}
	local c = 0
	for _, t in list do
		if Sim.tick - t < A.StrikeWindow * TR then
			c += 1
		end
	end
	return math.floor(A.BomberCost * (1 + A.StrikeEscalation * c))
end

local function hasFactory(nid: number): boolean
	for _, s in Structures.list do
		if s.owner == nid and s.kind == "factory" and s.done then
			return true
		end
	end
	return false
end

-- building within 1 cell of target owned by `owner` that bombers may hit
local function strikeableAt(cell: number, owner: number): any
	local W = Sim.W
	for _, s in Structures.list do
		if s.owner == owner and A.Strikeable[s.kind] and math.max(math.abs(s.cell % W - cell % W), math.abs(s.cell // W - cell // W)) <= 1 then
			return s
		end
	end
	return nil
end

-- is the cell part of a visible front (within FrontDepth of land the owner doesn't hold)?
local function onFront(cell: number, owner: number): boolean
	local W, H = Sim.W, Sim.H
	local x, y = cell % W, cell // W
	local r = A.FrontDepth
	for yy = math.max(0, y - r), math.min(H - 1, y + r) do
		for xx = math.max(0, x - r), math.min(W - 1, x + r) do
			local c = yy * W + xx
			if Sim.isClaimable(c) and Sim.ownerAt(c) ~= owner then
				return true
			end
		end
	end
	return false
end

-- what a bomber would do at `cell` for nation nid: payload kind + reason when illegal
function Air.bomberPayload(nid: number, cell: number): (string?, any, string?)
	local owner = Sim.ownerAt(cell)
	if owner == 0 or not Sim.isClaimable(cell) then
		return nil, nil, "Bombers hit enemy fronts or buildings"
	end
	if Sim.friendly(nid, owner) then
		return nil, nil, "That land is friendly"
	end
	local s = strikeableAt(cell, owner)
	if s then
		if s.disabledUntil > Sim.tick then
			return nil, nil, "That building is already disabled"
		end
		return "structure", s, nil
	end
	if not onFront(cell, owner) then
		return nil, nil, "Pick a spot on their front line or a building"
	end
	return "front", nil, nil
end

local function freeAirfield(nid: number, near: number, except: number?): any
	local best, bd = nil, math.huge
	for _, s in Structures.list do
		if s.kind == "airfield" and s.owner == nid and s.done and s.id ~= except and s.disabledUntil <= Sim.tick
			and (turnaround[s.id] or 0) <= Sim.tick and Air.sortiesFrom(s.id) < A.SortiesPerAirfield then
			local d = dist(s.cell, near)
			if d < bd then
				best, bd = s, d
			end
		end
	end
	return best
end

-- mission = "strike" | "cap"; escort = also send a fighter from another airfield
function Air.launch(nid: number, airfieldId: number, mission: string, target: number, escort: boolean?): (boolean, string)
	local n = Sim.nations[nid]
	local af = Structures.list[airfieldId]
	if not n or not n.alive or not af or af.kind ~= "airfield" or af.owner ~= nid then
		return false, "Pick one of your airfields"
	end
	if not af.done or af.disabledUntil > Sim.tick then
		return false, "Airfield not operational"
	end
	if Air.sortiesFrom(af.id) >= A.SortiesPerAirfield then
		return false, "This airfield's sortie is already flying"
	end
	if (turnaround[af.id] or 0) > Sim.tick then
		return false, ("Turnaround: ready in %ds"):format(math.ceil(((turnaround[af.id] :: number) - Sim.tick) / TR))
	end
	if dist(af.cell, target) < 2 then
		return false, "Pick a target further from the airfield"
	end
	if mission == "strike" then
		if not hasFactory(nid) then
			return false, "Bombers unlock with a finished factory"
		end
		local payload, s, why = Air.bomberPayload(nid, target)
		if not payload then
			return false, why :: string
		end
		local cost = Air.bomberCost(nid)
		local escortAf = nil
		if escort then
			escortAf = freeAirfield(nid, target, af.id)
			if not escortAf then
				return false, "No second free airfield for an escort"
			end
			cost += A.FighterCost
		end
		if n.gold < cost then
			return false, "Not enough gold"
		end
		n.gold -= cost
		recentStrikes[nid] = recentStrikes[nid] or {}
		table.insert(recentStrikes[nid], Sim.tick)
		local path = Path.line(af.cell, target)
		local b = Units.spawn("bomber", nid, path, A.BomberSpeed, {
			mission = "strike", airfield = af.id, target = target, state = "out",
			payload = payload, structId = s and s.id, victim = Sim.ownerAt(target),
		}, A.BomberHp)
		if escortAf then
			-- escort flies in formation with the bomber (its sortie slot and home are its own field)
			Units.spawn("fighter", nid, table.clone(path), A.BomberSpeed, {
				mission = "escort", airfield = escortAf.id, target = target, state = "out", escortOf = b.id,
			}, A.FighterHp)
		end
		Air.sorties += 1
		emit("launched", { owner = nid, kind = "bomber", target = target, victim = Sim.ownerAt(target), eta = #path / A.BomberSpeed })
		return true, ("Bomber launched (%s strike)%s"):format(payload, if escortAf then " with escort" else "")
	elseif mission == "cap" then
		if n.gold < A.FighterCost then
			return false, "Not enough gold"
		end
		n.gold -= A.FighterCost
		local path = Path.line(af.cell, target)
		Units.spawn("fighter", nid, path, A.FighterSpeed, {
			mission = "cap", airfield = af.id, target = target, state = "out",
		}, A.FighterHp)
		Air.sorties += 1
		return true, ("Fighter patrol launched (%ds on station)"):format(A.CapTime)
	end
	return false, "Unknown mission"
end

local function goHome(u: Units.Unit)
	local here = Units.cellOf(u)
	if u.data.drill then
		Units.remove(u, "landed") -- tutorial aircraft just leave
		return
	end
	local af = Structures.list[u.data.airfield]
	if not af or af.owner ~= u.owner then
		-- home lost: divert to the nearest own airfield in reach
		local best, bd = nil, math.huge
		for _, s in Structures.list do
			if s.kind == "airfield" and s.owner == u.owner then
				local d = dist(s.cell, here)
				if d < bd then
					best, bd = s, d
				end
			end
		end
		if not best then
			Units.remove(u, "lost")
			emit("lost", { owner = u.owner, kind = u.kind, cell = here })
			return
		end
		u.data.airfield = best.id
		af = best
	end
	u.data.state = "back"
	Units.setPath(u, Path.line(here, af.cell))
end

local function payload(u: Units.Unit)
	local d = u.data
	if d.drill then
		emit("drillFail", { owner = d.victim, cell = d.target })
		return
	end
	local target = d.target
	local owner = Sim.ownerAt(target)
	-- recheck legality on arrival
	if owner == 0 or Sim.friendly(u.owner, owner) then
		emit("aborted", { owner = u.owner, why = "target is no longer hostile", cell = target })
		return
	end
	if d.payload == "structure" then
		local s = Structures.list[d.structId]
		if not s or Sim.friendly(u.owner, s.owner) then
			emit("aborted", { owner = u.owner, why = "the building is gone", cell = target })
			return
		end
		s.disabledUntil = Sim.tick + A.DisableTime * TR
		Structures.changed = true
		emit("struck", { owner = u.owner, victim = s.owner, kind = s.kind, cell = s.cell, recover = A.DisableTime })
	else
		local v = Sim.nations[owner]
		local loss = math.min(v.troops * A.FrontShare, A.FrontCap)
		v.troops -= loss
		v.lastHitBy = u.owner
		-- refresh, don't stack, suppression on the same area
		local merged = false
		for _, z in Air.zones do
			if z.target == owner and dist(z.cell, target) <= A.SuppressRadius then
				z.untilTick = Sim.tick + A.SuppressTime * TR
				merged = true
			end
		end
		if not merged then
			table.insert(Air.zones, { cell = target, target = owner, untilTick = Sim.tick + A.SuppressTime * TR })
		end
		Air.changed = true
		emit("bombed", { owner = u.owner, victim = owner, loss = math.floor(loss), cell = target, window = A.SuppressTime })
	end
end

local function onArrive(u: Units.Unit)
	local d = u.data
	if d.state == "out" then
		if u.kind == "bomber" then
			payload(u)
			goHome(u)
		elseif d.mission == "cap" then
			d.state = "hold"
			d.holdUntil = Sim.tick + A.CapTime * TR
		else -- escort reached the target with its bomber
			goHome(u)
		end
	elseif d.state == "back" then
		local af = Structures.list[d.airfield]
		turnaround[d.airfield] = Sim.tick + A.Turnaround * TR
		Units.remove(u, "landed")
		if not af or af.owner ~= u.owner then
			emit("lost", { owner = u.owner, kind = u.kind, cell = Units.cellOf(u) })
		end
	end
end

local function onStep(u: Units.Unit)
	local d = u.data
	if d.state == "hold" and Sim.tick >= d.holdUntil then
		goHome(u)
	elseif d.mission == "escort" and d.state == "out" then
		local b = Units.list[d.escortOf]
		if not b then
			goHome(u) -- bomber lost: escort heads home
		end
	end
end

Units.handlers.bomber = { onArrive = onArrive, onStep = onStep }
Units.handlers.fighter = { onArrive = onArrive, onStep = onStep }

-- defense multiplier inside bomber suppression (attackers pay less)
function Air.suppressMult(cell: number, target: number): number
	for _, z in Air.zones do
		if z.target == target and z.untilTick > Sim.tick and dist(z.cell, cell) <= A.SuppressRadius then
			return A.SuppressMult
		end
	end
	return 1
end

local function damage(victim: Units.Unit, amount: number, byOwner: number, byKind: string)
	victim.hp -= amount
	if victim.hp <= 0 and not victim.dead then
		Units.remove(victim, "shot")
		if victim.data.drill and victim.kind == "bomber" then
			emit("drillOk", { owner = byOwner, cell = Units.cellOf(victim) })
		end
		emit("shotdown", { owner = byOwner, by = byKind, victim = victim.owner, kind = victim.kind, cell = Units.cellOf(victim) })
	end
end

-- air combat + AA, after movement. Deterministic: ordered by id.
function Air.step()
	-- expire zones
	for k = #Air.zones, 1, -1 do
		if Air.zones[k].untilTick <= Sim.tick then
			table.remove(Air.zones, k)
			Air.changed = true
		end
	end
	local planes = {}
	for _, u in Units.list do
		if isAircraft(u) then
			planes[#planes + 1] = u
		end
	end
	if #planes == 0 then
		return
	end
	table.sort(planes, function(a, b)
		return a.id < b.id
	end)
	-- fighters
	for _, f in planes do
		if f.kind == "fighter" and not f.dead then
			local here = Units.cellOf(f)
			local best = nil
			for _, o in planes do
				if not o.dead and o ~= f and not Sim.friendly(f.owner, o.owner) and dist(Units.cellOf(o), here) <= A.FighterRange then
					-- fighters first (escorts shield bombers), then bombers, then lower id
					if not best or (o.kind == "fighter" and best.kind ~= "fighter") then
						best = o
					end
				end
			end
			if best then
				damage(best, A.FighterDps / TR, f.owner, "fighter")
			end
		end
	end
	-- AA batteries: finite magazine + reload
	local rng = Sim.rng()
	for _, s in Structures.list do
		if s.kind == "aa" and s.done and s.disabledUntil <= Sim.tick then
			local st = aaState[s.id]
			if not st then
				st = { ammo = AA.magazine, next = 0 }
				aaState[s.id] = st
			end
			if st.ammo <= 0 and Sim.tick >= st.next then
				st.ammo = AA.magazine
			end
			if st.ammo > 0 and Sim.tick >= st.next then
				for _, o in planes do
					if not o.dead and not Sim.friendly(s.owner, o.owner) and dist(Units.cellOf(o), s.cell) <= AA.radius then
						local hit = rng:NextNumber() < AA.hitChance
						st.ammo -= 1
						st.next = Sim.tick + (if st.ammo <= 0 then AA.reload * TR else AA.shotGap * TR)
						emit("aa", { owner = s.owner, victim = o.owner, hit = hit, kind = o.kind, cell = Units.cellOf(o), aa = s.cell })
						if hit then
							damage(o, AA.damage, s.owner, "aa")
						end
						break
					end
				end
			end
		end
	end
end

-- replication rows: suppression zones { cell, target, untilServerTime }
function Air.rows(now: number): { any }
	local out = {}
	for _, z in Air.zones do
		out[#out + 1] = { z.cell, z.target, now + (z.untilTick - Sim.tick) / TR }
	end
	return out
end

function Air.turnaroundLeft(sid: number): number
	return math.max(0, ((turnaround[sid] or 0) - Sim.tick) / TR)
end

return Air
