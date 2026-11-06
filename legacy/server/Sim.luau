--!strict
-- Authoritative grid simulation: ownership, troops, gold, attacks.
-- Deterministic per tick: attacks are processed in creation order, regen after combat.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local MapGen = require(ReplicatedStorage.Shared.MapGen)

local TR = Config.Troops
local CB = Config.Combat
local TERR = Config.Terrain

export type Nation = {
	id: number,
	name: string,
	color: string,
	kind: string, -- "human" | "nation" | "tribe"
	userId: number,
	troops: number,
	maxTroops: number,
	gold: number,
	land: number,
	peakLand: number,
	alive: boolean,
	spawned: boolean,
	spawnX: number,
	spawnY: number,
	minX: number,
	maxX: number,
	minY: number,
	maxY: number,
	attacks: { any },
	lastHitBy: number,
	elimTick: number,
	stats: { captured: number, attacks: number, eliminated: number, peakTroops: number },
	capBonus: number,
	income: { [string]: number }, -- gold earned per source this round
	disconnectedAt: number?, -- tick a human left (AI takes over after a grace)
	skin: string?, -- cosmetic territory pattern
	flag: string?, -- cosmetic nameplate flag
}

local Sim = {}
Sim.W = 0
Sim.H = 0
Sim.N = 0
Sim.tick = 0
Sim.seq = 0
Sim.claimable = 0
Sim.nations = {} :: { [number]: Nation }
Sim.attacks = {} :: { any }
Sim.onEliminated = nil :: ((victim: Nation, killer: Nation?) -> ())?
-- cells with a structure on them; owner changes are reported to onHookedCell
Sim.cellHook = {} :: { [number]: boolean }
Sim.onHookedCell = nil :: ((cell: number, old: number, new: number) -> ())?
-- attacker cost multiplier for taking `cell` from `target` (defense posts)
Sim.defenseMult = nil :: ((cell: number, target: number) -> number)?
Sim.water = buffer.create(4)
Sim.regions = nil :: buffer?
Sim.regionNames = nil :: { string }?
-- real-world name of the region under a cell (country or province), if the map has them
function Sim.regionName(i: number): string?
	local r, names = Sim.regions, Sim.regionNames
	if not r or not names then
		return nil
	end
	local id = buffer.readu16(r, i * 2)
	return if id > 0 then names[id + 1] else nil
end
-- diplomacy hook (replaced by Diplomacy): true if a and b are allies
Sim.allied = function(_a: number, _b: number): boolean
	return false
end
function Sim.friendly(a: number, b: number): boolean
	return a == b or (a ~= 0 and b ~= 0 and Sim.allied(a, b))
end
Sim.waterSize = {} :: { number }

local terrain: buffer = buffer.create(1)
local owner: buffer = buffer.create(2)
local W, H, N = 0, 0, 0
local rng = Random.new(1)
local nextAttackId = 0
local dirty: { number } = {}
local dirtySet: { [number]: boolean } = {}

local function ownerAt(i: number): number
	return buffer.readu16(owner, i * 2)
end
local function terrAt(i: number): number
	return buffer.readu8(terrain, i)
end
Sim.ownerAt = ownerAt
Sim.terrAt = terrAt

function Sim.reset(terr: buffer, w: number, h: number, seed: number)
	W, H, N = w, h, w * h
	Sim.W, Sim.H, Sim.N = w, h, N
	terrain = terr
	owner = buffer.create(N * 2)
	rng = Random.new(seed)
	Sim.nations = {}
	Sim.attacks = {}
	Sim.cellHook = {}
	Sim.clearCaches()
	Sim.water, Sim.waterSize = MapGen.waterBodies(terr, w, h)
	Sim.tick = 0
	nextAttackId = 0
	dirty, dirtySet = {}, {}
	local c = 0
	for i = 0, N - 1 do
		local t = TERR[terrAt(i)]
		if t and t.claim then
			c += 1
		end
	end
	Sim.claimable = c
end

function Sim.addNation(name: string, color: string, kind: string, userId: number): Nation
	local id = #Sim.nations + 1
	local n: Nation = {
		id = id,
		name = name,
		color = color,
		kind = kind,
		userId = userId,
		troops = TR.Start * (if kind == "tribe" then TR.TribeMult else 1),
		maxTroops = TR.Base,
		gold = Config.Gold.Start,
		land = 0,
		peakLand = 0,
		alive = true,
		spawned = false,
		spawnX = -1,
		spawnY = -1,
		minX = W,
		maxX = -1,
		minY = H,
		maxY = -1,
		attacks = {},
		lastHitBy = 0,
		elimTick = 0,
		stats = { captured = 0, attacks = 0, eliminated = 0, peakTroops = 0 },
		capBonus = 0,
		income = { base = 0, trade = 0 },
	}
	Sim.nations[id] = n
	return n
end

function Sim.setOwner(i: number, nid: number)
	local old = ownerAt(i)
	if old == nid then
		return
	end
	buffer.writeu16(owner, i * 2, nid)
	if old ~= 0 then
		local o = Sim.nations[old]
		o.land -= 1
	end
	if nid ~= 0 then
		local n = Sim.nations[nid]
		n.land += 1
		if n.land > n.peakLand then
			n.peakLand = n.land
		end
		local x, y = i % W, i // W
		if x < n.minX then n.minX = x end
		if x > n.maxX then n.maxX = x end
		if y < n.minY then n.minY = y end
		if y > n.maxY then n.maxY = y end
	end
	if not dirtySet[i] then
		dirtySet[i] = true
		dirty[#dirty + 1] = i
	end
	if Sim.cellHook[i] and Sim.onHookedCell then
		Sim.onHookedCell(i, old, nid)
	end
end

function Sim.isCoastal(i: number): boolean
	return MapGen.isCoastal(Sim.water, Sim.waterSize, W, N, i, Config.OceanMin)
end

local function isClaimable(i: number): boolean
	local t = TERR[terrAt(i)]
	return t ~= nil and t.claim
end
Sim.isClaimable = isClaimable

-- true if any cell within r of (cx, cy) is owned by someone other than nid
function Sim.foreignNear(cx: number, cy: number, r: number, nid: number): boolean
	for y = math.max(0, cy - r), math.min(H - 1, cy + r) do
		for x = math.max(0, cx - r), math.min(W - 1, cx + r) do
			local o = ownerAt(y * W + x)
			if o ~= 0 and o ~= nid and (x - cx) ^ 2 + (y - cy) ^ 2 <= r * r then
				return true
			end
		end
	end
	return false
end

function Sim.releaseLand(n: Nation)
	if n.maxX < 0 then
		return
	end
	for y = n.minY, n.maxY do
		for x = n.minX, n.maxX do
			local i = y * W + x
			if ownerAt(i) == n.id then
				Sim.setOwner(i, 0)
			end
		end
	end
	n.minX, n.maxX, n.minY, n.maxY = W, -1, H, -1
end

function Sim.claimFootprint(n: Nation, cx: number, cy: number, r: number): number
	local c = 0
	for y = math.max(0, cy - r), math.min(H - 1, cy + r) do
		for x = math.max(0, cx - r), math.min(W - 1, cx + r) do
			local i = y * W + x
			if (x - cx) ^ 2 + (y - cy) ^ 2 <= r * r + 1 and isClaimable(i) and ownerAt(i) == 0 then
				Sim.setOwner(i, n.id)
				c += 1
			end
		end
	end
	n.spawned = c > 0
	n.spawnX, n.spawnY = cx, cy
	return c
end

-- cached variant for AI (rescans at most every maxAge ticks)
local nbCache: { [number]: { tick: number, data: { [number]: number } } } = {}
function Sim.neighborOwnersCached(n: Nation, maxAge: number): { [number]: number }
	local c = nbCache[n.id]
	if c and Sim.tick - c.tick < maxAge then
		return c.data
	end
	local d = Sim.neighborOwners(n)
	nbCache[n.id] = { tick = Sim.tick, data = d }
	return d
end
function Sim.clearCaches()
	nbCache = {}
end

-- Owners bordering nation n (0 = neutral land) -> shared edge count.
function Sim.neighborOwners(n: Nation): { [number]: number }
	local out: { [number]: number } = {}
	if n.maxX < 0 then
		return out
	end
	local id = n.id
	for y = n.minY, n.maxY do
		local row = y * W
		for x = n.minX, n.maxX do
			local i = row + x
			if ownerAt(i) == id then
				if x > 0 then
					local j = i - 1
					local o = ownerAt(j)
					if o ~= id and (o ~= 0 or isClaimable(j)) then out[o] = (out[o] or 0) + 1 end
				end
				if x < W - 1 then
					local j = i + 1
					local o = ownerAt(j)
					if o ~= id and (o ~= 0 or isClaimable(j)) then out[o] = (out[o] or 0) + 1 end
				end
				if y > 0 then
					local j = i - W
					local o = ownerAt(j)
					if o ~= id and (o ~= 0 or isClaimable(j)) then out[o] = (out[o] or 0) + 1 end
				end
				if y < H - 1 then
					local j = i + W
					local o = ownerAt(j)
					if o ~= id and (o ~= 0 or isClaimable(j)) then out[o] = (out[o] or 0) + 1 end
				end
			end
		end
	end
	return out
end

local function frontPush(att: any, j: number)
	if not att.inFront[j] then
		att.inFront[j] = true
		local f = att.front
		f[#f + 1] = j
	end
end

local function buildFrontier(att: any)
	local n = Sim.nations[att.attacker]
	local t = att.target
	att.front, att.inFront = {}, {}
	if n.maxX < 0 then
		return
	end
	local id = n.id
	for y = n.minY, n.maxY do
		local row = y * W
		for x = n.minX, n.maxX do
			local i = row + x
			if ownerAt(i) == id then
				if x > 0 and ownerAt(i - 1) == t and isClaimable(i - 1) then frontPush(att, i - 1) end
				if x < W - 1 and ownerAt(i + 1) == t and isClaimable(i + 1) then frontPush(att, i + 1) end
				if y > 0 and ownerAt(i - W) == t and isClaimable(i - W) then frontPush(att, i - W) end
				if y < H - 1 and ownerAt(i + W) == t and isClaimable(i + W) then frontPush(att, i + W) end
			end
		end
	end
end

local function ownNeighbors(i: number, id: number): number
	local x = i % W
	local c = 0
	if x > 0 and ownerAt(i - 1) == id then c += 1 end
	if x < W - 1 and ownerAt(i + 1) == id then c += 1 end
	if i >= W and ownerAt(i - W) == id then c += 1 end
	if i < N - W and ownerAt(i + W) == id then c += 1 end
	return c
end

local function removeAt(att: any, k: number)
	local f = att.front
	local c = f[k]
	f[k] = f[#f]
	f[#f] = nil
	att.inFront[c] = nil
end

-- Pick the next frontier cell: best of 3 random valid samples (smooth fronts).
local function pickCell(att: any): number?
	local f = att.front
	local bestK, bestScore = 0, -1
	local tries = 0
	local function drop(k: number)
		if bestK == #f then
			bestK = k -- the last slot is about to move into k
		end
		removeAt(att, k)
	end
	while #f > 0 and tries < 3 do
		local k = rng:NextInteger(1, #f)
		local c = f[k]
		if ownerAt(c) ~= att.target then
			drop(k)
		else
			local s = ownNeighbors(c, att.attacker)
			if s == 0 then
				drop(k)
			else
				tries += 1
				if s > bestScore then
					bestK, bestScore = k, s
				end
			end
		end
	end
	if bestK == 0 or bestK > #f then
		return nil
	end
	local c = f[bestK]
	removeAt(att, bestK)
	return c
end

local function detach(att: any)
	local idx = table.find(Sim.attacks, att)
	if idx then
		table.remove(Sim.attacks, idx)
	end
	local a = Sim.nations[att.attacker]
	local k = table.find(a.attacks, att)
	if k then
		table.remove(a.attacks, k)
	end
	att.ended = true
end

local function endAttack(att: any, refundShare: number)
	local a = Sim.nations[att.attacker]
	if a.alive then
		a.troops += math.max(0, att.troops) * refundShare
	end
	detach(att)
end

function Sim.findAttack(nid: number, target: number): any
	for _, att in Sim.nations[nid].attacks do
		if att.target == target then
			return att
		end
	end
	return nil
end

-- Commit `troops` from nid's pool against target (0 = neutral). Returns ok, message.
-- reserved = troops were already taken from the pool (beachheads).
local function commit(nid: number, target: number, troops: number, reserved: boolean): (boolean, string)
	local a = Sim.nations[nid]
	if not a or not a.alive then
		return false, "You have no nation"
	end
	if target == nid then
		return false, "That is your own land"
	end
	local t = if target ~= 0 then Sim.nations[target] else nil
	if target ~= 0 and (not t or not t.alive) then
		return false, "That nation is gone"
	end
	if not reserved then
		troops = math.floor(math.min(troops, a.troops))
		if troops < CB.MinSend then
			return false, "Not enough troops to send"
		end
	end
	if target ~= 0 and Sim.allied(nid, target) then
		return false, "You are allied with them"
	end
	local existing = Sim.findAttack(nid, target)
	if not existing and #a.attacks >= CB.MaxAttacks then
		return false, ("Max %d fronts at once"):format(CB.MaxAttacks)
	end
	-- legality: a real shared land border
	local probe = existing or { attacker = nid, target = target }
	buildFrontier(probe)
	if #probe.front == 0 then
		return false, if target == 0 then "No neutral land borders you" else "No shared land border (water needs transports)"
	end
	if not reserved then
		a.troops -= troops -- reserve once, on the server
		a.stats.attacks += 1
	end
	-- opposing attack on the same front: troops cancel out first
	if t then
		local opp = Sim.findAttack(target, nid)
		if opp then
			local m = math.min(troops, opp.troops)
			troops -= m
			opp.troops -= m
			if opp.troops <= 0 then
				detach(opp)
			end
			if troops <= 0 then
				return true, "Your troops clashed with their attack"
			end
		end
	end
	if existing then
		existing.troops += troops
		return true, "Reinforced front"
	end
	nextAttackId += 1
	probe.id = nextAttackId
	probe.troops = troops
	probe.startTick = Sim.tick
	table.insert(Sim.attacks, probe)
	table.insert(a.attacks, probe)
	return true, "Attack launched"
end

-- end a front and return all of its troops (alliances forming)
function Sim.retreatFull(att: any)
	endAttack(att, 1)
end

function Sim.startAttack(nid: number, target: number, troops: number): (boolean, string)
	return commit(nid, target, troops, false)
end

function Sim.startAttackReserved(nid: number, target: number, troops: number): (boolean, string)
	return commit(nid, target, troops, true)
end

function Sim.retreat(nid: number, attackId: number): boolean
	for _, att in Sim.nations[nid].attacks do
		if att.id == attackId then
			endAttack(att, CB.RetreatRefund)
			return true
		end
	end
	return false
end

local function stepAttack(att: any)
	local a = Sim.nations[att.attacker]
	local target = att.target
	local t = if target ~= 0 then Sim.nations[target] else nil
	if t and not t.alive then
		return endAttack(att, 1)
	end
	local f = att.front
	if #f == 0 then
		return endAttack(att, 1)
	end
	local budget
	if t then
		local ratio = math.clamp(att.troops / math.max(t.troops, 1), 0.3, 2.5)
		budget = math.floor(#f * CB.EnemyFrontFrac * ratio) + 1
	else
		budget = math.floor(#f * CB.NeutralFrontFrac) + 1
	end
	budget = math.min(budget, CB.MaxCellsPerTick)
	local density = if t then t.troops / math.max(t.land, 1) else 0
	for _ = 1, budget do
		local c = pickCell(att)
		if not c then
			break
		end
		local tc = TERR[terrAt(c)].cost
		local cost = if t then CB.EnemyBaseCost * tc + density * CB.DensityCost else CB.NeutralCost * tc
		if t and Sim.defenseMult then
			cost *= Sim.defenseMult(c, target)
		end
		if att.troops < cost then
			-- not enough to take this cell: front collapses, survivors return
			return endAttack(att, 1)
		end
		att.troops -= cost
		if t then
			t.troops = math.max(0, t.troops - density * CB.DefenderLoss)
			t.lastHitBy = a.id
		end
		Sim.setOwner(c, a.id)
		a.stats.captured += 1
		-- grow every front of this attacker that targets the cell's neighbours
		local x = c % W
		local nb1 = if x > 0 then c - 1 else -1
		local nb2 = if x < W - 1 then c + 1 else -1
		local nb3 = if c >= W then c - W else -1
		local nb4 = if c < N - W then c + W else -1
		for _, other in a.attacks do
			local ot = other.target
			for _, j in { nb1, nb2, nb3, nb4 } do
				if j >= 0 and ownerAt(j) == ot and isClaimable(j) then
					frontPush(other, j)
				end
			end
		end
	end
	if #att.front == 0 then
		endAttack(att, 1)
	end
end

local function maxTroopsOf(n: Nation): number
	local m = TR.Base + TR.PerCell * n.land ^ TR.CapExp + n.capBonus
	if n.kind == "tribe" then
		m *= TR.TribeMult
	end
	return m
end
Sim.maxTroopsOf = maxTroopsOf

function Sim.step()
	Sim.tick += 1
	local dt = 1 / Config.TickRate
	-- combat, in attack creation order
	local list = table.clone(Sim.attacks)
	for _, att in list do
		if not att.ended then
			stepAttack(att)
		end
	end
	-- eliminations
	for _, n in Sim.nations do
		if n.alive and n.spawned and n.land <= 0 then
			n.alive = false
			n.elimTick = Sim.tick
			n.troops = 0
			for _, att in table.clone(n.attacks) do
				detach(att) -- an eliminated nation's commitments are lost
			end
			local killer = Sim.nations[n.lastHitBy]
			if killer then
				killer.stats.eliminated += 1
			end
			if Sim.onEliminated then
				Sim.onEliminated(n, killer)
			end
		end
	end
	-- regen + income
	local G = Config.Gold
	for _, n in Sim.nations do
		if n.alive and n.spawned then
			local m = maxTroopsOf(n)
			n.maxTroops = m
			local mult = if n.kind == "tribe" then TR.TribeMult else 1
			if n.troops < m then
				n.troops = math.min(m, n.troops + (TR.RegenBase * mult + (m - n.troops) * TR.RegenFrac) * dt)
			else
				n.troops -= (n.troops - m) * TR.OverCapDecay * dt
			end
			if n.troops > n.stats.peakTroops then
				n.stats.peakTroops = n.troops
			end
			local g = (G.Base + G.PerCell * n.land) * dt
			n.gold += g
			n.income.base += g
		end
	end
end

-- Sequenced owner delta: u32 seq, u32 count, then count x (u32 cell, u16 owner).
function Sim.flushDelta(): buffer?
	if #dirty == 0 then
		return nil
	end
	Sim.seq += 1
	local b = buffer.create(8 + #dirty * 6)
	buffer.writeu32(b, 0, Sim.seq)
	buffer.writeu32(b, 4, #dirty)
	local o = 8
	for _, i in dirty do
		buffer.writeu32(b, o, i)
		buffer.writeu16(b, o + 4, ownerAt(i))
		o += 6
	end
	dirty, dirtySet = {}, {}
	return b
end

function Sim.ownerCopy(): buffer
	local b = buffer.create(N * 2)
	buffer.copy(b, 0, owner, 0, N * 2)
	return b
end

function Sim.terrain(): buffer
	return terrain
end

function Sim.rng(): Random
	return rng
end

return Sim
