--!strict
-- AI: tribes (weak, mostly expand) and nations (expand, defend, exploit openings).
-- Decisions are staggered per bot so the tick cost stays flat.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Sim = require(script.Parent.Sim)
local Structures = require(script.Parent.Structures)
local Naval = require(script.Parent.Naval)
local Diplomacy = require(script.Parent.Diplomacy)
local Nukes = require(script.Parent.Nukes)
local Air = require(script.Parent.Air)
local Units = require(script.Parent.Units)

local Bots = {}
Bots.frozen = {} :: { [number]: boolean } -- dev tests: nations the AI leaves alone
local nextThink: { [number]: number } = {}

local PRE = { "Var", "Kel", "Os", "Tir", "Mar", "Bel", "Dun", "Ast", "Cor", "Lum", "Zan", "Ery", "Hal", "Nor", "Pel", "Quen", "Sol", "Tav", "Ulm", "Vex", "Gar", "Iso", "Rho", "Bra" }
local SUF = { "ia", "or", "land", "mark", "heim", "ova", "esh", "ara", "un", "ith", "aro", "enne" }

function Bots.name(rng: Random, kind: string, used: { [string]: boolean }): string
	for _ = 1, 50 do
		local base = PRE[rng:NextInteger(1, #PRE)] .. SUF[rng:NextInteger(1, #SUF)]
		local n = if kind == "tribe" then base .. " Tribe" else base
		if not used[n] then
			used[n] = true
			return n
		end
	end
	return kind .. tostring(rng:NextInteger(100, 999))
end

-- Random spawn far enough from everyone else.
function Bots.findSpawn(rng: Random, r: number): (number?, number?)
	local W, H = Sim.W, Sim.H
	for _ = 1, 400 do
		local x, y = rng:NextInteger(2, W - 3), rng:NextInteger(2, H - 3)
		local i = y * W + x
		if Sim.isClaimable(i) and Sim.ownerAt(i) == 0 and not Sim.foreignNear(x, y, Config.Spawn.MinDist, 0) then
			return x, y
		end
	end
	return nil, nil
end

function Bots.reset()
	nextThink = {}
end

-- try a few random owned cells for a legal site
local function tryBuild(n: Sim.Nation, kind: string, rng: Random): boolean
	if n.maxX < 0 then
		return false
	end
	for _ = 1, 40 do
		local x, y = rng:NextInteger(n.minX, n.maxX), rng:NextInteger(n.minY, n.maxY)
		local c = y * Sim.W + x
		if Sim.ownerAt(c) == n.id and not Structures.whyNot(n.id, kind, c) then
			return (Structures.build(n.id, kind, c))
		end
	end
	return false
end

local function economy(n: Sim.Nation, rng: Random)
	local cities = #Structures.ofOwner(n.id, "city")
	local lateGame = Sim.tick > Config.Nuke.AiMinMinutes * 60 * Config.TickRate
	-- late game: launch at the strongest non-allied rival's heartland
	if lateGame then
		local silos = Structures.ofOwner(n.id, "silo")
		if #silos > 0 and n.gold >= Config.Nuke.Cost * 1.2 and rng:NextNumber() < 0.25 then
			local rival
			for _, o in Sim.nations do
				if o.alive and o.id ~= n.id and o.kind ~= "tribe" and not Sim.friendly(n.id, o.id) and (not rival or o.land > rival.land) then
					rival = o
				end
			end
			if rival and rival.land > n.land * 0.8 then
				local tx, ty = (rival.minX + rival.maxX) // 2, (rival.minY + rival.maxY) // 2
				local target = ty * Sim.W + tx
				if Sim.ownerAt(target) == rival.id then
					Nukes.launch(n.id, silos[1].id, target)
					return
				end
			end
		end
	end
	-- air: an airfield mid-game; AA once hostile airfields are near
	if n.land > 900 and #Structures.ofOwner(n.id, "airfield") < 1 and n.gold >= Structures.costFor(n.id, "airfield") then
		if tryBuild(n, "airfield", rng) then
			return
		end
	end
	if #Structures.ofOwner(n.id, "aa") < 2 and n.gold >= Structures.costFor(n.id, "aa") * 1.2 then
		local cx, cy = (n.minX + n.maxX) / 2, (n.minY + n.maxY) / 2
		for _, s in Structures.list do
			if s.kind == "airfield" and not Sim.friendly(n.id, s.owner)
				and math.abs(s.cell % Sim.W - cx) + math.abs(s.cell // Sim.W - cy) < 80 then
				if tryBuild(n, "aa", rng) then
					return
				end
				break
			end
		end
	end
	local roll = rng:NextNumber()
	local want = if cities < 1 then "city"
		elseif lateGame and n.land > 1200 and #Structures.ofOwner(n.id, "sam") < 1 then "sam"
		elseif lateGame and n.land > 1500 and #Structures.ofOwner(n.id, "silo") < 1 then "silo"
		elseif roll < 0.35 then "city"
		elseif roll < 0.55 then "factory"
		elseif roll < 0.75 then "port"
		else "defense"
	if n.gold >= Structures.costFor(n.id, want) * 1.1 then
		tryBuild(n, want, rng)
	elseif n.gold >= Config.Naval.WarshipCost * 2 and rng:NextNumber() < 0.15 and Naval.countOf(n.id, "warship") < 2 then
		local ports = Structures.ofOwner(n.id, "port")
		if #ports > 0 then
			Naval.buildWarship(n.id, ports[rng:NextInteger(1, #ports)].id)
		end
	end
end

-- sorties: patrol over our land when a hostile bomber targets us; otherwise
-- bomb the front we're already attacking to open it up for ground troops
local function airOps(n: Sim.Nation, rng: Random)
	local fields = Structures.ofOwner(n.id, "airfield")
	if #fields == 0 then
		return
	end
	for _, u in Units.list do
		if u.kind == "bomber" and u.data.state == "out" and u.data.victim == n.id then
			-- meet it two thirds of the way in
			local mid = u.path[math.max(1, math.floor(#u.path * 2 / 3))]
			for _, f in fields do
				if Air.launch(n.id, f.id, "cap", mid) then
					return
				end
			end
		end
	end
	if rng:NextNumber() > 0.35 then
		return
	end
	for _, att in n.attacks do
		if att.target ~= 0 and #att.front > 0 then
			local cell = att.front[rng:NextInteger(1, #att.front)]
			for _, f in fields do
				if n.gold >= Air.bomberCost(n.id) * 1.5 and Air.launch(n.id, f.id, "strike", cell) then
					return
				end
			end
		end
	end
end

local function think(n: Sim.Nation, rng: Random)
	if n.kind == "nation" then
		economy(n, rng)
		airOps(n, rng)
	end
	local ratio = n.troops / math.max(n.maxTroops, 1)
	local nb = Sim.neighborOwnersCached(n, 2 * Config.TickRate)
	local tribe = n.kind == "tribe"
	-- 0) nothing attackable by land (island, boxed in, only allies around): go by sea
	local landTarget = nb[0] ~= nil
	for oid in nb do
		if oid ~= 0 and not Sim.friendly(n.id, oid) then
			landTarget = true
		end
	end
	if not landTarget then
		if not tribe and ratio > 0.5 and Naval.countOf(n.id, "transport") < 2 then
			local W = Sim.W
			local best, bd = nil, math.huge
			local cx, cy = (n.minX + n.maxX) // 2, (n.minY + n.maxY) // 2
			for _ = 1, 500 do
				local x, y = rng:NextInteger(0, W - 1), rng:NextInteger(0, Sim.H - 1)
				local c = y * W + x
				if Sim.isClaimable(c) and not Sim.friendly(n.id, Sim.ownerAt(c)) and Sim.isCoastal(c) then
					local d = (x - cx) ^ 2 + (y - cy) ^ 2
					if d < bd then
						best, bd = c, d
					end
				end
			end
			if best then
				Naval.sendBoat(n.id, best, n.troops * 0.5)
			end
		end
		return
	end
	-- 1) neutral land first
	if nb[0] then
		if ratio > (if tribe then 0.6 else 0.35) then
			Sim.startAttack(n.id, 0, n.troops * (if tribe then 0.25 else 0.4))
		end
		if not tribe or rng:NextNumber() < 0.8 then
			return
		end
	end
	-- 2) defend: if someone is attacking us with a big force, keep reserves
	local underAttack = 0
	for _, att in Sim.attacks do
		if att.target == n.id then
			underAttack += att.troops
		end
	end
	if underAttack > n.troops * 0.8 then
		local opp
		for _, att in Sim.attacks do
			if att.target == n.id and (not opp or att.troops > opp.troops) then
				opp = att
			end
		end
		-- counter-attack the strongest attacker to cancel its front
		if opp and n.troops > opp.troops * 0.5 then
			Sim.startAttack(n.id, opp.attacker, math.min(n.troops * 0.5, opp.troops))
		end
		return
	end
	if ratio < (if tribe then 0.8 else 0.5) then
		return
	end
	-- 3) attack the weakest neighbour (by troop density), preferring openings
	local best, bestScore = nil, math.huge
	local weakAlly = nil
	for oid, edges in nb do
		if oid ~= 0 and Sim.allied(n.id, oid) then
			local o = Sim.nations[oid]
			if o and o.troops < n.troops * 0.4 then
				weakAlly = o
			end
		elseif oid ~= 0 then
			local o = Sim.nations[oid]
			if o and o.alive then
				local dens = o.troops / math.max(o.land, 1)
				local busy = 0
				for _, att in o.attacks do
					busy += att.troops
				end
				local score = dens - busy / math.max(o.land, 1) * 0.5 - edges * 0.02
				if o.kind == "tribe" then
					score *= 0.6
				end
				if tribe and o.kind ~= "tribe" then
					score *= 4 -- tribes rarely pick on real nations
				end
				if score < bestScore and o.troops < n.troops * (if tribe then 0.5 else 0.75) then
					best, bestScore = o, score
				end
			end
		end
	end
	if best then
		Sim.startAttack(n.id, best.id, n.troops * (if tribe then 0.3 else 0.35))
	elseif weakAlly and rng:NextNumber() < Config.Diplomacy.AiBetrayChance then
		-- exploit an opening: announced betrayal of a weak ally
		Diplomacy.breakWith(n.id, weakAlly.id)
	end
end

Bots.thinkMul = 1 -- solo difficulty (Config.Difficulty[d].Think)

function Bots.step(now: number)
	local rng = Sim.rng()
	for _, n in Sim.nations do
		if n.alive and n.spawned and n.kind ~= "human" and not Bots.frozen[n.id] then
			local t = nextThink[n.id]
			if not t then
				nextThink[n.id] = now + rng:NextNumber() * 2
			elseif now >= t then
				local range = if n.kind == "tribe" then Config.Bots.TribeThink else Config.Bots.NationThink
				nextThink[n.id] = now + (range[1] + rng:NextNumber() * (range[2] - range[1])) * (if n.kind == "tribe" then 1 else Bots.thinkMul)
				think(n, rng)
			end
		end
	end
end

return Bots
