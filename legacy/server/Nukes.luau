--!strict
-- Nuclear missiles from silos; SAM launchers intercept hostile missiles in range.
-- Default rules (unverified against the reference, all in Config.Nuke):
--   * blast radius R: every cell within 0.6R becomes neutral; the outer ring keeps
--     OuterKeep of its cells (random). Friendly fire applies to everyone in the blast.
--   * each hit nation loses troops in proportion to the land it lost x TroopLoss.
--   * structures on cleared cells are destroyed; ships inside the blast sink.
--   * a SAM intercepts one hostile missile per reload while the missile is inside its radius.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Sim = require(script.Parent.Sim)
local Structures = require(script.Parent.Structures)
local Units = require(script.Parent.Units)

local NK = Config.Nuke
local SAM = Config.Structures.sam
local Nukes = {}
Nukes.onEvent = nil :: ((kind: string, info: any) -> ())?

local siloReady: { [number]: number } = {}
local samReady: { [number]: number } = {}

function Nukes.reset()
	siloReady = {}
	samReady = {}
end

local function emit(kind: string, info: any)
	if Nukes.onEvent then
		Nukes.onEvent(kind, info)
	end
end

local function line(a: number, b: number): { number }
	local W = Sim.W
	local x0, y0, x1, y1 = a % W, a // W, b % W, b // W
	local dx, dy = math.abs(x1 - x0), -math.abs(y1 - y0)
	local sx, sy = if x0 < x1 then 1 else -1, if y0 < y1 then 1 else -1
	local err = dx + dy
	local out = {}
	while true do
		out[#out + 1] = y0 * W + x0
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

function Nukes.siloCooldownLeft(sid: number): number
	return math.max(0, ((siloReady[sid] or 0) - Sim.tick) / Config.TickRate)
end

function Nukes.launch(nid: number, siloId: number, target: number): (boolean, string)
	local n = Sim.nations[nid]
	local silo = Structures.list[siloId]
	if not n or not n.alive or not silo or silo.kind ~= "silo" or silo.owner ~= nid then
		return false, "Pick one of your silos"
	end
	if not silo.done or silo.disabledUntil > Sim.tick then
		return false, "Silo not ready"
	end
	if (siloReady[siloId] or 0) > Sim.tick then
		return false, ("Silo reloading (%ds)"):format(math.ceil(Nukes.siloCooldownLeft(siloId)))
	end
	local owner = Sim.ownerAt(target)
	if owner ~= 0 and Sim.friendly(nid, owner) then
		return false, "You can't target your own or allied land"
	end
	if n.gold < NK.Cost then
		return false, "Not enough gold"
	end
	n.gold -= NK.Cost
	siloReady[siloId] = Sim.tick + NK.SiloCooldown * Config.TickRate
	local path = line(silo.cell, target) -- missiles fly straight
	local u = Units.spawn("missile", nid, path, NK.Speed, { target = target }, 1)
	emit("launched", { owner = nid, target = target, victim = owner, eta = #path / NK.Speed, unit = u.id })
	return true, "Missile launched"
end

local function detonate(u: Units.Unit)
	local W, H = Sim.W, Sim.H
	local c = u.data.target
	local cx, cy = c % W, c // W
	local R = NK.Radius
	local inner = (R * 0.6) ^ 2
	local rng = Sim.rng()
	local lost: { [number]: number } = {}
	for y = math.max(0, cy - R), math.min(H - 1, cy + R) do
		for x = math.max(0, cx - R), math.min(W - 1, cx + R) do
			local d = (x - cx) ^ 2 + (y - cy) ^ 2
			if d <= R * R then
				local i = y * W + x
				local o = Sim.ownerAt(i)
				if o ~= 0 and (d <= inner or rng:NextNumber() > NK.OuterKeep) then
					lost[o] = (lost[o] or 0) + 1
					Sim.setOwner(i, 0) -- structures on it are destroyed by Structures
				end
			end
		end
	end
	for o, cells in lost do
		local n = Sim.nations[o]
		if n then
			local share = cells / math.max(n.land + cells, 1)
			n.troops = math.max(0, n.troops - n.troops * math.min(1, share * NK.TroopLoss))
			n.lastHitBy = u.owner
		end
	end
	-- ships in the blast sink
	for _, s in Units.near(c, R, function(o)
		return o.kind == "warship" or o.kind == "transport" or o.kind == "trade" or o.kind == "train"
	end) do
		Units.remove(s, "sunk")
	end
	emit("impact", { owner = u.owner, target = c, lost = lost })
end

Units.handlers.missile = {
	onStep = function(u)
		-- SAM interception
		local here = Units.cellOf(u)
		local W = Sim.W
		local hx, hy = here % W, here // W
		local r2 = SAM.radius * SAM.radius
		for _, s in Structures.list do
			if s.kind == "sam" and s.done and s.disabledUntil <= Sim.tick and not Sim.friendly(s.owner, u.owner)
				and (samReady[s.id] or 0) <= Sim.tick then
				local dx, dy = s.cell % W - hx, s.cell // W - hy
				if dx * dx + dy * dy <= r2 then
					samReady[s.id] = Sim.tick + SAM.reload * Config.TickRate
					Units.remove(u, "intercepted")
					emit("intercepted", { owner = u.owner, sam = s.owner, cell = here })
					return
				end
			end
		end
	end,
	onArrive = function(u)
		Units.remove(u, "impact")
		detonate(u)
	end,
}

-- conventional missile from a silo (shares the silo reload)
function Nukes.launchMissile(nid: number, siloId: number, target: number): (boolean, string)
	local MS = Config.Missile
	local n = Sim.nations[nid]
	local silo = Structures.list[siloId]
	if not n or not n.alive or not silo or silo.kind ~= "silo" or silo.owner ~= nid then
		return false, "Pick one of your silos"
	end
	if not silo.done or silo.disabledUntil > Sim.tick then
		return false, "Silo not ready"
	end
	if (siloReady[siloId] or 0) > Sim.tick then
		return false, ("Silo reloading (%ds)"):format(math.ceil(Nukes.siloCooldownLeft(siloId)))
	end
	local owner = Sim.ownerAt(target)
	if owner ~= 0 and Sim.friendly(nid, owner) then
		return false, "You can't target your own or allied land"
	end
	if n.gold < MS.Cost then
		return false, "Not enough gold"
	end
	n.gold -= MS.Cost
	siloReady[siloId] = Sim.tick + math.floor(NK.SiloCooldown * 0.5) * Config.TickRate
	Units.spawn("rocket", nid, line(silo.cell, target), MS.Speed, { target = target }, 1)
	emit("launched", { owner = nid, target = target, victim = owner, eta = 1, unit = 0, small = true })
	return true, "Missile launched"
end

local function detonateSmall(u: Units.Unit)
	local MS = Config.Missile
	local W, H = Sim.W, Sim.H
	local c = u.data.target
	local cx, cy = c % W, c // W
	local hit: { [number]: number } = {}
	for y = math.max(0, cy - MS.Radius), math.min(H - 1, cy + MS.Radius) do
		for x = math.max(0, cx - MS.Radius), math.min(W - 1, cx + MS.Radius) do
			if (x - cx) ^ 2 + (y - cy) ^ 2 <= MS.Radius ^ 2 then
				local o = Sim.ownerAt(y * W + x)
				if o ~= 0 then
					hit[o] = (hit[o] or 0) + 1
				end
			end
		end
	end
	for o, cells in hit do
		local n = Sim.nations[o]
		if n then
			n.troops = math.max(0, n.troops - n.troops * math.min(1, cells / math.max(n.land, 1) * 20 * MS.TroopLoss))
			n.lastHitBy = u.owner
		end
	end
	for _, s in table.clone(Structures.list) do
		if math.max(math.abs(s.cell % W - cx), math.abs(s.cell // W - cy)) <= MS.Radius - 1 and not Sim.friendly(u.owner, s.owner) then
			Structures.remove(s)
		end
	end
	emit("impact", { owner = u.owner, target = c, lost = {}, small = true })
end

Units.handlers.rocket = {
	onStep = Units.handlers.missile.onStep,
	onArrive = function(u)
		Units.remove(u, "impact")
		detonateSmall(u)
	end,
}

-- for clients: SAM reload state
function Nukes.samCooldownLeft(sid: number): number
	return math.max(0, ((samReady[sid] or 0) - Sim.tick) / Config.TickRate)
end

return Nukes
