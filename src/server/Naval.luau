--!strict
-- Transports (troops across water) and warships (contest transports, trade and warships).
-- Landing rule: on arrival the boat pays the normal cost for the landing cell; if it
-- can't, the landing is repelled and the troops are lost. If the landing cell already
-- became ours, the troops return to the pool. Hostile = not friendly (allies are safe).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Sim = require(script.Parent.Sim)
local Structures = require(script.Parent.Structures)
local Units = require(script.Parent.Units)
local Path = require(script.Parent.Path)

local NV = Config.Naval
local CB = Config.Combat
local Naval = {}
Naval.onEvent = nil :: ((kind: string, info: any) -> ())?

local function emit(kind: string, info: any)
	if Naval.onEvent then
		Naval.onEvent(kind, info)
	end
end

local function sameBody(a: number, b: number): boolean
	return buffer.readu32(Sim.water, a * 4) == buffer.readu32(Sim.water, b * 4)
end

local function seaPath(a: number, b: number): { number }?
	return Path.find(a, b, function(j)
		return Sim.terrAt(j) == 0
	end, 30000, 3)
end

function Naval.countOf(owner: number, kind: string): number
	local c = 0
	for _, u in Units.list do
		if u.owner == owner and u.kind == kind then
			c += 1
		end
	end
	return c
end

-- landing cell: target itself if coastal, else the nearest coastal cell of the same owner
local function landingFor(target: number): number?
	if Sim.isCoastal(target) then
		return target
	end
	local W, H = Sim.W, Sim.H
	local tx, ty = target % W, target // W
	local owner = Sim.ownerAt(target)
	local r = NV.LandingSearch
	local best, bd = nil, math.huge
	for y = math.max(0, ty - r), math.min(H - 1, ty + r) do
		for x = math.max(0, tx - r), math.min(W - 1, tx + r) do
			local c = y * W + x
			if Sim.ownerAt(c) == owner and Sim.isClaimable(c) and Sim.isCoastal(c) then
				local d = (x - tx) ^ 2 + (y - ty) ^ 2
				if d < bd then
					best, bd = c, d
				end
			end
		end
	end
	return best
end

-- Send a transport toward target cell with `troops` (taken from the pool here).
function Naval.sendBoat(nid: number, target: number, troops: number): (boolean, string)
	local n = Sim.nations[nid]
	if not n or not n.alive then
		return false, "You have no nation"
	end
	if not Sim.isClaimable(target) then
		return false, "Pick land across the water"
	end
	if Sim.friendly(nid, Sim.ownerAt(target)) then
		return false, "That land is friendly"
	end
	if Naval.countOf(nid, "transport") >= NV.MaxBoats then
		return false, ("Max %d boats at sea"):format(NV.MaxBoats)
	end
	troops = math.floor(math.min(troops, n.troops))
	if troops < CB.MinSend then
		return false, "Not enough troops to send"
	end
	local land = landingFor(target)
	local wl = land and Path.waterBeside(land)
	if not land or not wl then
		return false, "No coast to land on near there"
	end
	-- nearest own ocean coast on the same water body: expanding rings around the landing
	local W, H = Sim.W, Sim.H
	local lx, ly = land % W, land // W
	local launch = nil
	for r = 1, NV.LaunchSearch do
		for dy = -r, r do
			local y = ly + dy
			if y >= 0 and y < H then
				local step = if dy == -r or dy == r then 1 else 2 * r
				local dx = -r
				while dx <= r do
					local x = lx + dx
					if x >= 0 and x < W then
						local c = y * W + x
						if Sim.ownerAt(c) == nid and Sim.isCoastal(c) then
							local w = Path.waterBeside(c)
							if w and sameBody(w, wl) then
								launch = w
								break
							end
						end
					end
					dx += step
				end
			end
			if launch then
				break
			end
		end
		if launch then
			break
		end
	end
	if not launch then
		return false, "You have no coast on that sea"
	end
	local p = seaPath(launch, wl)
	if not p then
		return false, "No sea route found"
	end
	table.insert(p, land) -- last step lands
	n.troops -= troops
	n.stats.attacks += 1
	Units.spawn("transport", nid, p, NV.BoatSpeed, { troops = troops, land = land }, NV.BoatHp)
	return true, ("Boat launched with %d troops"):format(troops)
end

Units.handlers.transport = {
	onArrive = function(u)
		local nid, land, troops = u.owner, u.data.land, u.data.troops
		local n = Sim.nations[nid]
		Units.remove(u, "landed")
		if not n or not n.alive then
			return
		end
		local owner = Sim.ownerAt(land)
		if owner == nid then
			n.troops += troops
			return
		end
		local t = if owner ~= 0 then Sim.nations[owner] else nil
		local tc = Config.Terrain[Sim.terrAt(land)].cost
		local cost = if t then CB.EnemyBaseCost * tc + t.troops / math.max(t.land, 1) * CB.DensityCost else CB.NeutralCost * tc
		if Sim.friendly(nid, owner) or troops < cost then
			emit("repelled", { owner = nid, cell = land })
			return
		end
		troops -= cost
		Sim.setOwner(land, nid)
		n.stats.captured += 1
		-- the beachhead pushes on against the former owner with what's left
		local ok = Sim.startAttackReserved(nid, owner, troops)
		if not ok then
			n.troops += troops
		end
		emit("landed", { owner = nid, target = owner, cell = land })
	end,
}

----------------------------------------------------------------------------
-- warships

function Naval.buildWarship(nid: number, portId: number): (boolean, string)
	local port = Structures.list[portId]
	local n = Sim.nations[nid]
	if not port or port.kind ~= "port" or port.owner ~= nid or not n then
		return false, "Pick one of your ports"
	end
	if not port.done then
		return false, "Port still under construction"
	end
	local here = 0
	for _, u in Units.list do
		if u.kind == "warship" and u.data.port == portId then
			here += 1
		end
	end
	if here >= NV.MaxWarshipsPerPort then
		return false, ("Max %d warships per port"):format(NV.MaxWarshipsPerPort)
	end
	if n.gold < NV.WarshipCost then
		return false, "Not enough gold"
	end
	local w = Path.waterBeside(port.cell)
	if not w then
		return false, "Port has no ocean access"
	end
	n.gold -= NV.WarshipCost
	Units.spawn("warship", nid, { w }, NV.WarshipSpeed, { port = portId, anchor = w, nextPatrol = Sim.tick + 20, cooldown = 0 }, NV.WarshipHp)
	return true, "Warship launched"
end

-- launch button: a warship from the nearest own port on that sea, sailing to `cell`
function Naval.launchWarship(nid: number, cell: number): (boolean, string)
	if Sim.terrAt(cell) ~= 0 then
		return false, "Pick open water for the warship"
	end
	local W = Sim.W
	local best, bd = nil, math.huge
	for _, s in Structures.list do
		if s.kind == "port" and s.owner == nid and s.done then
			local w = Path.waterBeside(s.cell)
			if w and sameBody(w, cell) then
				local here = 0
				for _, u in Units.list do
					if u.kind == "warship" and u.data.port == s.id then
						here += 1
					end
				end
				local d = (s.cell % W - cell % W) ^ 2 + (s.cell // W - cell // W) ^ 2
				if here < NV.MaxWarshipsPerPort and d < bd then
					best, bd = s, d
				end
			end
		end
	end
	if not best then
		return false, "Build a port on this sea first (max 3 warships per port)"
	end
	local ok, msg = Naval.buildWarship(nid, best.id)
	if not ok then
		return false, msg
	end
	for _, u in Units.list do
		if u.kind == "warship" and u.data.port == best.id and #u.path == 1 then
			Naval.moveWarship(nid, u.id, cell)
		end
	end
	return true, "Warship launched"
end

function Naval.moveWarship(nid: number, unitId: number, cell: number): (boolean, string)
	local u = Units.list[unitId]
	if not u or u.kind ~= "warship" or u.owner ~= nid then
		return false, "Pick one of your warships"
	end
	if Sim.terrAt(cell) ~= 0 then
		return false, "Warships move on water"
	end
	local here = Units.cellOf(u)
	if not sameBody(here, cell) then
		return false, "That water is not connected"
	end
	local p = seaPath(here, cell)
	if not p then
		return false, "No route"
	end
	u.data.anchor = cell
	u.data.nextPatrol = Sim.tick + math.floor(NV.PatrolEvery * Config.TickRate) + #p * Config.TickRate // NV.WarshipSpeed
	Units.setPath(u, p)
	return true, "Warship moving"
end

local function hostileNaval(owner: number)
	return function(o: Units.Unit): boolean
		return (o.kind == "transport" or o.kind == "trade" or o.kind == "warship") and not Sim.friendly(owner, o.owner)
	end
end

local PRIORITY = { transport = 1, warship = 2, trade = 3 }

Units.handlers.warship = {
	onStep = function(u)
		local d = u.data
		local here = Units.cellOf(u)
		-- engage the highest-priority hostile in range
		local targets = Units.near(here, NV.WarshipRange, hostileNaval(u.owner))
		table.sort(targets, function(a, b)
			local pa, pb = PRIORITY[a.kind], PRIORITY[b.kind]
			return if pa ~= pb then pa < pb else a.id < b.id
		end)
		local tgt = targets[1]
		if tgt then
			tgt.hp -= NV.WarshipDps / Config.TickRate
			if tgt.hp <= 0 then
				if tgt.kind == "trade" then
					-- cargo seized
					local n = Sim.nations[u.owner]
					if n then
						n.gold += Config.Trade.ShipBase
						n.income.trade += Config.Trade.ShipBase
					end
					emit("seized", { owner = u.owner, victim = tgt.owner, cell = Units.cellOf(tgt) })
				else
					emit("sunk", { owner = u.owner, victim = tgt.owner, kind = tgt.kind, cell = Units.cellOf(tgt) })
				end
				Units.remove(tgt, "sunk")
			end
			return
		end
		-- idle patrol around the anchor
		if u.pos >= #u.path and Sim.tick >= d.nextPatrol then
			d.nextPatrol = Sim.tick + math.floor(NV.PatrolEvery * Config.TickRate)
			local rng = Sim.rng()
			local W = Sim.W
			local ax, ay = d.anchor % W, d.anchor // W
			for _ = 1, 12 do
				local x = math.clamp(ax + rng:NextInteger(-NV.PatrolRadius, NV.PatrolRadius), 0, W - 1)
				local y = math.clamp(ay + rng:NextInteger(-NV.PatrolRadius, NV.PatrolRadius), 0, Sim.H - 1)
				local c = y * W + x
				if Sim.terrAt(c) == 0 and sameBody(c, here) then
					local p = Path.find(here, c, function(j)
						return Sim.terrAt(j) == 0
					end, 3000, 2)
					if p and #p > 1 then
						Units.setPath(u, p)
					end
					break
				end
			end
		end
	end,
}

return Naval
