--!strict
-- Moving map units (trains, trade ships, transports, warships, missiles, aircraft).
-- Each unit follows a cell path at a fixed speed; kind handlers react per cell and on arrival.
-- Replication: spawn rows carry the path so clients interpolate; gone rows remove.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Sim = require(script.Parent.Sim)

export type Unit = {
	id: number,
	kind: string,
	owner: number,
	path: { number },
	pos: number, -- 1-based float index into path
	speed: number, -- cells per second
	hp: number,
	data: any,
	dead: boolean,
}

type Handler = {
	onCell: ((u: Unit, cell: number) -> boolean)?, -- return false to stop (unit removed by handler)
	onArrive: ((u: Unit) -> ())?,
	onStep: ((u: Unit) -> ())?,
}

local Units = {}
Units.list = {} :: { [number]: Unit }
Units.handlers = {} :: { [string]: Handler }
local nextId = 0
local spawnQ: { any } = {}
local goneQ: { any } = {}

function Units.reset()
	Units.list = {}
	nextId = 0
	spawnQ, goneQ = {}, {}
end

local function pathBuffer(path: { number }): buffer
	local b = buffer.create(#path * 4)
	for k, c in path do
		buffer.writeu32(b, (k - 1) * 4, c)
	end
	return b
end

local function row(u: Unit): any
	return { u.id, u.kind, u.owner, pathBuffer(u.path), u.pos, u.speed, workspace:GetServerTimeNow(), u.hp }
end

function Units.spawn(kind: string, owner: number, path: { number }, speed: number, data: any, hp: number?): Unit
	nextId += 1
	local u: Unit = {
		id = nextId,
		kind = kind,
		owner = owner,
		path = path,
		pos = 1,
		speed = speed,
		hp = hp or 1,
		data = data or {},
		dead = false,
	}
	Units.list[u.id] = u
	spawnQ[#spawnQ + 1] = row(u)
	return u
end

-- new route for an existing unit (re-replicated under the same id)
function Units.setPath(u: Unit, path: { number }, speed: number?)
	u.path = path
	u.pos = 1
	if speed then
		u.speed = speed
	end
	spawnQ[#spawnQ + 1] = row(u)
end

function Units.remove(u: Unit, reason: string)
	if u.dead then
		return
	end
	u.dead = true
	Units.list[u.id] = nil
	goneQ[#goneQ + 1] = { u.id, reason, Units.cellOf(u) }
end

function Units.cellOf(u: Unit): number
	return u.path[math.clamp(math.floor(u.pos), 1, #u.path)]
end

function Units.step()
	local dt = 1 / Config.TickRate
	-- ordered by id for determinism
	local ids = {}
	for id in Units.list do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	for _, id in ids do
		local u = Units.list[id]
		if u and not u.dead then
			local h = Units.handlers[u.kind]
			if h and h.onStep then
				h.onStep(u)
			end
			if not u.dead and #u.path > 1 and u.pos < #u.path then
				local before = math.floor(u.pos)
				u.pos = math.min(#u.path, u.pos + u.speed * dt)
				local after = math.floor(u.pos)
				if h and h.onCell then
					for k = before + 1, after do
						if u.dead or not h.onCell(u, u.path[k]) then
							break
						end
					end
				end
				if not u.dead and u.pos >= #u.path and h and h.onArrive then
					h.onArrive(u)
				end
			end
		end
	end
end

-- units of kinds within r cells of cell (Chebyshev)
function Units.near(cell: number, r: number, filter: (Unit) -> boolean): { Unit }
	local W = Sim.W
	local x, y = cell % W, cell // W
	local out = {}
	for _, u in Units.list do
		if not u.dead and filter(u) then
			local c = Units.cellOf(u)
			if math.max(math.abs(c % W - x), math.abs(c // W - y)) <= r then
				out[#out + 1] = u
			end
		end
	end
	return out
end

function Units.flush(): ({ any }?, { any }?)
	if #spawnQ == 0 and #goneQ == 0 then
		return nil, nil
	end
	local s, g = spawnQ, goneQ
	spawnQ, goneQ = {}, {}
	return s, g
end

function Units.snapshotRows(): { any }
	local out = {}
	for _, u in Units.list do
		out[#out + 1] = row(u)
	end
	return out
end

return Units
