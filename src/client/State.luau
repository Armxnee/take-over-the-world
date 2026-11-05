--!strict
-- Client mirror of replicated match state. Display only; the server is authoritative.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local MapGen = require(ReplicatedStorage.Shared.MapGen)

export type NationInfo = {
	id: number,
	name: string,
	hex: string,
	color: Color3,
	kind: string,
	userId: number,
	alive: boolean,
	spawned: boolean,
	troops: number,
	max: number,
	land: number,
	gold: number,
	skin: string?,
	flag: string?,
	vehicles: any,
}

local State = {
	ready = false,
	W = 0,
	H = 0,
	N = 0,
	terrain = buffer.create(1),
	owner = buffer.create(2),
	seq = 0,
	round = 0,
	map = "",
	claimable = 1,
	me = 0,
	nations = {} :: { [number]: NationInfo },
	mine = {} :: { { number } },
	ratio = Config.Combat.DefaultRatio,
	sumX = {} :: { [number]: number },
	sumY = {} :: { [number]: number },
	cnt = {} :: { [number]: number },
	selectedCell = -1,
	structures = {} :: { [number]: any },
	water = buffer.create(4),
	waterSize = {} :: { number },
	placing = nil :: string?, -- structure kind in build mode
	selectedUnit = nil :: number?,
	diplo = { pairs = {}, requests = {} } :: any,
	airZones = {} :: { any }, -- { cell, target, untilServerTime }
	myStrikes = {} :: { number }, -- os.clock of my recent bomber launches (cost preview)
	units = {} :: { [number]: any },
	income = { base = 0, trade = 0 } :: { [string]: number },
	overlays = { routes = true, defense = false },
	results = nil :: any,
}

local listeners: { [string]: { (...any) -> () } } = {}
function State.on(ev: string, fn: (...any) -> ())
	listeners[ev] = listeners[ev] or {}
	table.insert(listeners[ev], fn)
end
function State.emit(ev: string, ...: any)
	for _, fn in listeners[ev] or {} do
		task.spawn(fn, ...)
	end
end

function State.ownerAt(i: number): number
	return buffer.readu16(State.owner, i * 2)
end
function State.terrAt(i: number): number
	return buffer.readu8(State.terrain, i)
end
function State.claimable_(i: number): boolean
	local t = Config.Terrain[State.terrAt(i)]
	return t ~= nil and t.claim
end

function State.setNations(list: { any })
	for _, row in list do
		local id = row[1]
		local n = State.nations[id]
		if not n then
			n = {
				id = id,
				name = "",
				hex = "FFFFFF",
				color = Color3.new(1, 1, 1),
				kind = "",
				userId = 0,
				alive = true,
				spawned = false,
				troops = 0,
				max = 1,
				land = 0,
				gold = 0,
			}
			State.nations[id] = n
		end
		n.name, n.hex, n.kind, n.userId, n.alive = row[2], row[3], row[4], row[5], row[6]
		local oldSkin, oldFlag = n.skin, n.flag
		n.skin = if row[7] then row[7] else nil
		n.flag = if row[8] then row[8] else nil
		n.vehicles = if row[9] then row[9] else nil
		if oldSkin ~= n.skin or oldFlag ~= n.flag then
			State.emit("skin", id)
		end
		n.color = Color3.fromHex(row[3])
	end
	State.emit("nations")
end

-- rows: { id, kind, owner, cell, level, done, readyAt, disabledAt }
function State.setStructures(rows: { any })
	local t = {}
	local byCell = {}
	for _, r in rows do
		t[r[1]] = { id = r[1], kind = r[2], owner = r[3], cell = r[4], level = r[5], done = r[6], readyAt = r[7], disabledAt = r[8] }
		byCell[r[4]] = r[1]
	end
	State.structures = t
	State.structureAt = byCell
	State.emit("structures")
end
State.structureAt = {} :: { [number]: number }

-- spawn rows: { id, kind, owner, pathBuffer, pos, speed, serverTime, hp }
function State.applyUnits(spawns: { any }, gones: { any }?)
	for _, r in spawns do
		State.units[r[1]] = {
			id = r[1],
			kind = r[2],
			owner = r[3],
			path = r[4],
			n = buffer.len(r[4]) // 4,
			pos0 = r[5],
			speed = r[6],
			t0 = r[7],
			hp = r[8],
		}
	end
	for _, g in gones or {} do
		State.units[g[1]] = nil
		if g[2] == "impact" or g[2] == "intercepted" then
			State.emit("blast", g[2], g[3])
		end
	end
	State.emit("units")
end

-- interpolated (x, y) in cell units, plus the float path index
function State.unitPos(u: any, now: number): (number, number, number)
	local p = math.clamp(u.pos0 + u.speed * (now - u.t0), 1, u.n)
	local k = math.floor(p)
	local f = p - k
	local W = State.W
	local a = buffer.readu32(u.path, (k - 1) * 4)
	local b = if k < u.n then buffer.readu32(u.path, k * 4) else a
	local ax, ay, bx, by = a % W, a // W, b % W, b // W
	return ax + (bx - ax) * f, ay + (by - ay) * f, p
end

-- relation with me: "allied" | "breaking" | nil, plus the pair row
function State.allyState(nid: number): (string?, any)
	for _, p in State.diplo.pairs do
		if (p[1] == State.me and p[2] == nid) or (p[2] == State.me and p[1] == nid) then
			return p[3], p
		end
	end
	return nil, nil
end

function State.allied(nid: number): boolean
	return nid ~= 0 and nid ~= State.me and State.allyState(nid) ~= nil
end

-- "theirs" if nid asked me, "mine" if I asked nid
function State.requestWith(nid: number): string?
	local now = workspace:GetServerTimeNow()
	for _, r in State.diplo.requests do
		if r[3] > now then
			if r[1] == nid and r[2] == State.me then
				return "theirs"
			elseif r[1] == State.me and r[2] == nid then
				return "mine"
			end
		end
	end
	return nil
end

-- client mirror of Air rules for the mission preview (the server re-validates)
function State.airPreview(sid: number, mission: string, cell: number, escort: boolean): any
	local A = Config.Air
	local af = State.structures[sid]
	local W = State.W
	local out: any = { cost = A.FighterCost }
	if not af then
		out.why = "Airfield gone"
		return out
	end
	local d = math.sqrt((af.cell % W - cell % W) ^ 2 + (af.cell // W - cell // W) ^ 2)
	if d < 2 then
		out.why = "Pick a target further from the airfield"
	end
	local speed = if mission == "strike" then A.BomberSpeed else A.FighterSpeed
	-- straight line
	local line = {}
	local x0, y0, x1, y1 = af.cell % W, af.cell // W, cell % W, cell // W
	local n = math.max(math.abs(x1 - x0), math.abs(y1 - y0), 1)
	for k = 0, n do
		line[#line + 1] = math.floor(y0 + (y1 - y0) * k / n + 0.5) * W + math.floor(x0 + (x1 - x0) * k / n + 0.5)
	end
	out.eta = #line / speed
	-- threats along the route: hostile AA batteries and fighters
	local aa, first = 0, math.huge
	for _, s in State.structures do
		if s.kind == "aa" and s.done and s.owner ~= State.me and not State.allied(s.owner) then
			local r2 = Config.Structures.aa.radius ^ 2
			for k, c in line do
				if (c % W - s.cell % W) ^ 2 + (c // W - s.cell // W) ^ 2 <= r2 then
					aa += 1
					first = math.min(first, k)
					break
				end
			end
		end
	end
	local fighters = 0
	local now = workspace:GetServerTimeNow()
	for _, u in State.units do
		if u.kind == "fighter" and u.owner ~= State.me and not State.allied(u.owner) then
			local ux, uy = State.unitPos(u, now)
			for k, c in line do
				if (c % W - ux) ^ 2 + (c // W - uy) ^ 2 <= (A.FighterRange + 2) ^ 2 then
					fighters += 1
					first = math.min(first, k)
					break
				end
			end
		end
	end
	out.aa, out.fighters = aa, fighters
	out.firstThreat = if first < math.huge then first / speed else nil
	if mission == "strike" then
		local recent = 0
		for _, t in State.myStrikes do
			if os.clock() - t < A.StrikeWindow then
				recent += 1
			end
		end
		out.cost = math.floor(A.BomberCost * (1 + A.StrikeEscalation * recent)) + (if escort then A.FighterCost else 0)
		local hasFactory = false
		for _, s in State.structures do
			if s.owner == State.me and s.kind == "factory" and s.done then
				hasFactory = true
			end
		end
		local owner = State.ownerAt(cell)
		if not hasFactory then
			out.why = out.why or "Bombers unlock with a finished factory"
		elseif owner == 0 or not State.claimable_(cell) then
			out.why = out.why or "Bombers hit enemy fronts or buildings"
		elseif owner == State.me or State.allied(owner) then
			out.why = out.why or "That land is friendly"
		else
			local st = nil
			for _, s in State.structures do
				if s.owner == owner and A.Strikeable[s.kind] and math.max(math.abs(s.cell % W - cell % W), math.abs(s.cell // W - cell // W)) <= 1 then
					st = s
				end
			end
			if st then
				out.payload = "structure"
				out.struct = st.kind
				if st.disabledAt > now then
					out.why = out.why or "That building is already disabled"
				end
			else
				local front = false
				local r = A.FrontDepth
				for yy = -r, r do
					for xx = -r, r do
						local c = cell + yy * W + xx
						if c >= 0 and c < State.N and State.claimable_(c) and State.ownerAt(c) ~= owner then
							front = true
						end
					end
				end
				out.payload = "front"
				if not front then
					out.why = out.why or "Pick a spot on their front line or a building"
				end
			end
		end
	end
	local me = State.nations[State.me]
	if not out.why and me and me.gold < out.cost then
		out.why = "Not enough gold"
	end
	return out
end

-- coverage shown while placing / selecting: defense, SAM, AA, airfield radius; factory rail reach
function State.reachOf(kind: string): number?
	if kind == "factory" then
		return Config.Trade.MaxRail
	end
	return Config.Structures[kind] and Config.Structures[kind].radius
end

-- cities / ports / factories a factory at `cell` would send trains to (same rule as the server)
-- finished building (the server flags `done` lazily; the timer is authoritative here)
function State.built(s: any): boolean
	return s.done or workspace:GetServerTimeNow() >= (s.readyAt or math.huge)
end

function State.railStops(cell: number, exceptId: number?, owner: number?): { number }
	local who = owner or State.me
	local W = State.W
	local fx, fy = cell % W, cell // W
	local R = Config.Trade.MaxRail
	local out = {}
	for _, s in State.structures do
		if s.id ~= exceptId and State.built(s) and (s.kind == "city" or s.kind == "port" or s.kind == "factory")
			and (s.owner == who or (who == State.me and State.allied(s.owner)))
			and (s.cell % W - fx) ^ 2 + (s.cell // W - fy) ^ 2 <= R * R and s.cell ~= cell then
			table.insert(out, s.cell)
		end
	end
	return out
end

function State.costFor(kind: string): number
	local d = Config.Structures[kind]
	local c = 0
	for _, s in State.structures do
		if s.owner == State.me and s.kind == kind then
			c += 1
		end
	end
	return math.floor(d.cost * d.growth ^ c)
end

-- mirrors Structures.whyNot on the server
function State.buildWhyNot(kind: string, cell: number): string?
	local d = Config.Structures[kind]
	if not State.claimable_(cell) or State.ownerAt(cell) ~= State.me then
		return "Build on your own land"
	end
	if d.coastal and not MapGen.isCoastal(State.water, State.waterSize, State.W, State.N, cell, Config.OceanMin) then
		return "Ports need an ocean coast"
	end
	local W = State.W
	local x, y = cell % W, cell // W
	for _, s in State.structures do
		local gap = math.max(Config.Structures[s.kind].spacing, d.spacing)
		if math.max(math.abs(s.cell % W - x), math.abs(s.cell // W - y)) < gap then
			return "Too close to another building"
		end
	end
	local me = State.nations[State.me]
	if not me or me.gold < State.costFor(kind) then
		return "Not enough gold"
	end
	return nil
end

-- nearest structure within r cells of cell (for click selection)
function State.structureNear(cell: number, r: number): any
	local W = State.W
	local x, y = cell % W, cell // W
	local best, bd = nil, math.huge
	for _, s in State.structures do
		local d = math.max(math.abs(s.cell % W - x), math.abs(s.cell // W - y))
		if d <= r and d < bd then
			best, bd = s, d
		end
	end
	return best
end

function State.applySnapshot(s: any)
	State.W, State.H, State.N = s.w, s.h, s.w * s.h
	State.map = s.map
	State.terrain = MapGen.rleDecode(s.terrain, State.N, 1)
	State.owner = MapGen.rleDecode(s.owner, State.N, 2)
	State.seq, State.round, State.claimable, State.me = s.seq, s.round, math.max(s.claimable, 1), s.me
	State.nations = {}
	State.mine = {}
	State.selectedCell = -1
	State.sumX, State.sumY, State.cnt = {}, {}, {}
	local W = State.W
	for i = 0, State.N - 1 do
		local o = buffer.readu16(State.owner, i * 2)
		if o ~= 0 then
			State.sumX[o] = (State.sumX[o] or 0) + i % W
			State.sumY[o] = (State.sumY[o] or 0) + i // W
			State.cnt[o] = (State.cnt[o] or 0) + 1
		end
	end
	State.water, State.waterSize = MapGen.waterBodies(State.terrain, State.W, State.H)
	State.placing = nil
	State.setNations(s.nations)
	State.setStructures(s.structures or {})
	State.units = {}
	State.applyUnits(s.units or {}, {})
	State.diplo = s.diplomacy or { pairs = {}, requests = {} }
	State.airZones = s.air or {}
	State.myStrikes = {}
	State.ready = true
	State.emit("snapshot")
end

-- returns the changed cell list, or nil if a gap means we need a resync
function State.applyDelta(b: buffer): ({ number }?, boolean)
	local seq = buffer.readu32(b, 0)
	if seq <= State.seq then
		return {}, false -- already contained in our snapshot
	end
	if seq ~= State.seq + 1 then
		return nil, true
	end
	State.seq = seq
	local count = buffer.readu32(b, 4)
	local W = State.W
	local out = table.create(count)
	local o = 8
	for k = 1, count do
		local i = buffer.readu32(b, o)
		local nw = buffer.readu16(b, o + 4)
		o += 6
		local old = buffer.readu16(State.owner, i * 2)
		if old ~= nw then
			local x, y = i % W, i // W
			if old ~= 0 then
				State.sumX[old] -= x
				State.sumY[old] -= y
				State.cnt[old] -= 1
			end
			if nw ~= 0 then
				State.sumX[nw] = (State.sumX[nw] or 0) + x
				State.sumY[nw] = (State.sumY[nw] or 0) + y
				State.cnt[nw] = (State.cnt[nw] or 0) + 1
			end
			buffer.writeu16(State.owner, i * 2, nw)
			out[#out + 1] = i
		end
	end
	return out, false
end

function State.applyStats(b: buffer)
	local count = buffer.readu16(b, 0)
	local o = 2
	for _ = 1, count do
		local id = buffer.readu16(b, o)
		local n = State.nations[id]
		if n then
			n.troops = buffer.readu32(b, o + 2)
			n.max = math.max(buffer.readu32(b, o + 6), 1)
			n.land = buffer.readu32(b, o + 10)
			n.gold = buffer.readu32(b, o + 14)
			local f = buffer.readu8(b, o + 18)
			n.alive = bit32.band(f, 1) ~= 0
			n.spawned = bit32.band(f, 2) ~= 0
		end
		o += 19
	end
	State.emit("stats")
end

-- does nation `me` share a land border with `target` (0 = neutral land)?
function State.borders(me: number, target: number): boolean
	local W, H = State.W, State.H
	local own = State.owner
	for i = 0, State.N - 1 do
		if buffer.readu16(own, i * 2) == me then
			local x = i % W
			if x > 0 and buffer.readu16(own, (i - 1) * 2) == target and State.claimable_(i - 1) then return true end
			if x < W - 1 and buffer.readu16(own, (i + 1) * 2) == target and State.claimable_(i + 1) then return true end
			if i >= W and buffer.readu16(own, (i - W) * 2) == target and State.claimable_(i - W) then return true end
			if i < State.N - W and buffer.readu16(own, (i + W) * 2) == target and State.claimable_(i + W) then return true end
		end
	end
	return false
end

function State.fmt(n: number): string
	if n >= 1e6 then
		return ("%.2fM"):format(n / 1e6)
	elseif n >= 1e4 then
		return ("%.1fK"):format(n / 1e3)
	end
	local s = tostring(math.floor(n))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

return State
