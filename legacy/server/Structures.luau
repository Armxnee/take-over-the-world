--!strict
-- Buildings: placement, construction, upgrades, capture rules and effects.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Sim = require(script.Parent.Sim)

local DEFS = Config.Structures

export type Structure = {
	id: number,
	kind: string,
	owner: number,
	cell: number,
	level: number,
	done: boolean,
	readyTick: number, -- construction / upgrade completes at this tick
	upgrading: boolean,
	disabledUntil: number, -- tick (bombers, M3)
}

local Structures = {}
Structures.list = {} :: { [number]: Structure }
Structures.byCell = {} :: { [number]: number }
Structures.changed = false
Structures.onEvent = nil :: ((kind: string, s: Structure, info: any) -> ())?

local nextId = 0

function Structures.reset()
	Structures.list = {}
	Structures.byCell = {}
	Structures.changed = true
	nextId = 0
end

local function countOf(owner: number, kind: string): number
	local c = 0
	for _, s in Structures.list do
		if s.owner == owner and s.kind == kind then
			c += 1
		end
	end
	return c
end

function Structures.costFor(owner: number, kind: string): number
	local d = DEFS[kind]
	return math.floor(d.cost * d.growth ^ countOf(owner, kind))
end

function Structures.upgradeCost(s: Structure): number
	local d = DEFS[s.kind]
	return math.floor(d.cost * d.upgradeCost * s.level)
end

local function recomputeCap(owner: number)
	local n = Sim.nations[owner]
	if not n then
		return
	end
	local bonus = 0
	for _, s in Structures.list do
		if s.owner == owner and s.kind == "city" then
			local lvl = if s.done then s.level elseif s.upgrading then s.level - 1 else 0
			bonus += lvl * DEFS.city.capBonus
		end
	end
	n.capBonus = bonus
end

-- Validation shared by preview and order. Returns nil when legal, else a reason.
function Structures.whyNot(owner: number, kind: string, cell: number): string?
	local d = DEFS[kind]
	if not d then
		return "Unknown building"
	end
	if not Sim.isClaimable(cell) or Sim.ownerAt(cell) ~= owner then
		return "Build on your own land"
	end
	if d.coastal and not Sim.isCoastal(cell) then
		return "Ports need an ocean coast"
	end
	if d.maxPerNation and countOf(owner, kind) >= d.maxPerNation then
		return ("Max %d per nation"):format(d.maxPerNation)
	end
	local W = Sim.W
	local x, y = cell % W, cell // W
	for _, s in Structures.list do
		local sx, sy = s.cell % W, s.cell // W
		local gap = math.max(DEFS[s.kind].spacing, d.spacing)
		if math.max(math.abs(sx - x), math.abs(sy - y)) < gap then
			return "Too close to another building"
		end
	end
	local n = Sim.nations[owner]
	if not n or n.gold < Structures.costFor(owner, kind) then
		return "Not enough gold"
	end
	return nil
end

function Structures.build(owner: number, kind: string, cell: number): (boolean, string)
	local why = Structures.whyNot(owner, kind, cell)
	if why then
		return false, why
	end
	local d = DEFS[kind]
	local n = Sim.nations[owner]
	n.gold -= Structures.costFor(owner, kind)
	nextId += 1
	local s: Structure = {
		id = nextId,
		kind = kind,
		owner = owner,
		cell = cell,
		level = 1,
		done = false,
		readyTick = Sim.tick + math.floor(d.build * Config.TickRate),
		upgrading = false,
		disabledUntil = 0,
	}
	Structures.list[s.id] = s
	Structures.byCell[cell] = s.id
	Sim.cellHook[cell] = true
	Structures.changed = true
	return true, d.name .. " under construction"
end

function Structures.upgrade(owner: number, id: number): (boolean, string)
	local s = Structures.list[id]
	if not s or s.owner ~= owner then
		return false, "Not your building"
	end
	local d = DEFS[s.kind]
	if not d.maxLevel then
		return false, "Only cities can be upgraded"
	end
	if not s.done then
		return false, "Still under construction"
	end
	if s.level >= d.maxLevel then
		return false, "Already max level"
	end
	local cost = Structures.upgradeCost(s)
	local n = Sim.nations[owner]
	if n.gold < cost then
		return false, "Not enough gold"
	end
	n.gold -= cost
	s.level += 1
	s.done = false
	s.upgrading = true
	s.readyTick = Sim.tick + math.floor(d.build * Config.TickRate)
	recomputeCap(owner)
	Structures.changed = true
	return true, ("Upgrading to level %d"):format(s.level)
end

local function remove(s: Structure)
	Structures.list[s.id] = nil
	Structures.byCell[s.cell] = nil
	Sim.cellHook[s.cell] = nil
	Structures.changed = true
end
Structures.remove = remove

-- Sim reports ownership changes of cells that hold a structure.
function Structures.onCellOwner(cell: number, old: number, new: number)
	local id = Structures.byCell[cell]
	local s = id and Structures.list[id]
	if not s then
		return
	end
	local d = DEFS[s.kind]
	local unfinished = not s.done and not s.upgrading
	if new == 0 or unfinished or d.onCapture == "destroy" then
		remove(s)
		if Structures.onEvent then
			Structures.onEvent("destroyed", s, { by = new })
		end
	else
		s.owner = new
		if s.upgrading then
			-- the pending upgrade is lost; keep the finished level
			s.level -= 1
			s.upgrading = false
			s.done = true
		end
		Structures.changed = true
		if Structures.onEvent then
			Structures.onEvent("captured", s, { from = old })
		end
	end
	recomputeCap(old)
	recomputeCap(new)
end

-- attacker cost multiplier for taking `cell` from `target`
function Structures.defenseMult(cell: number, target: number): number
	local W = Sim.W
	local x, y = cell % W, cell // W
	local d = DEFS.defense
	local r2 = d.radius * d.radius
	for _, s in Structures.list do
		if s.kind == "defense" and s.owner == target and s.done and s.disabledUntil <= Sim.tick then
			local dx, dy = s.cell % W - x, s.cell // W - y
			if dx * dx + dy * dy <= r2 then
				return d.defenseMult
			end
		end
	end
	return 1
end

function Structures.step()
	for _, s in Structures.list do
		if not s.done and Sim.tick >= s.readyTick then
			s.done = true
			s.upgrading = false
			Structures.changed = true
			recomputeCap(s.owner)
			if Structures.onEvent then
				Structures.onEvent("completed", s, nil)
			end
		end
	end
end

function Structures.ofOwner(owner: number, kind: string?): { Structure }
	local out = {}
	for _, s in Structures.list do
		if s.owner == owner and (kind == nil or s.kind == kind) then
			out[#out + 1] = s
		end
	end
	return out
end

-- compact replication rows: { id, kind, owner, cell, level, done, readyTick, disabledUntil }
function Structures.rows(): { any }
	local out = {}
	for _, s in Structures.list do
		out[#out + 1] = { s.id, s.kind, s.owner, s.cell, s.level, s.done, s.readyTick, s.disabledUntil }
	end
	return out
end

Sim.onHookedCell = Structures.onCellOwner
Sim.defenseMult = Structures.defenseMult

return Structures
