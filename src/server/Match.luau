--!strict
-- Match flow (Lobby -> Spawn -> Playing -> Ended), remotes, validation, replication.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Config = require(ReplicatedStorage.Shared.Config)
local MapGen = require(ReplicatedStorage.Shared.MapGen)
local Sim = require(script.Parent.Sim)
local Bots = require(script.Parent.Bots)
local Structures = require(script.Parent.Structures)
local Units = require(script.Parent.Units)
local Trade = require(script.Parent.Trade)
local Naval = require(script.Parent.Naval)
local Diplomacy = require(script.Parent.Diplomacy)
local Nukes = require(script.Parent.Nukes)
local Air = require(script.Parent.Air)
local ServerList = require(script.Parent.ServerList)
local Shop = require(script.Parent.Shop)
local PlayerData = require(script.Parent.PlayerData)

local Match = {}
Match.phase = "Lobby"
Match.roundId = 0
Match.pinnedVersion = Config.Version
Match.mapId = Config.Map.Id
Match.nextMap = nil :: string?
local rotation = 0

local function maxHumans(): number
	return if ServerList.solo then 1 else Config.Match.MaxHumans
end

local MC = Config.Match
local remotes: Folder
local R: { [string]: any } = {}
local playerNation: { [Player]: number } = {}
local queued: { [Player]: boolean } = {}
local bucket: { [Player]: { t: number, tokens: number } } = {}
local seenCmd: { [Player]: { [string]: boolean } } = {}
local seenCount: { [Player]: number } = {}
local lastResync: { [Player]: number } = {}
local phaseEnds = 0
local voteOptions: { string } = {} -- random maps offered at the end of the round
local votes: { [Player]: string } = {}
local drills: { [Player]: { count: number, drone: number?, patrol: boolean } } = {}
Match.drillNation = 0
-- replication accounting (bytes sent, all players)
Match.net = { bytes = 0, since = os.clock() }
local function account(bytes: number, toAll: boolean)
	Match.net.bytes += bytes * (if toAll then #Players:GetPlayers() else 1)
end
local roundStart = 0
local noHumanSince: number? = nil
local hadHumans = false

local function now(): number
	return workspace:GetServerTimeNow()
end

local function setPhase(p: string, dur: number)
	Match.phase = p
	phaseEnds = now() + dur
	remotes:SetAttribute("Phase", p)
	remotes:SetAttribute("PhaseEnds", phaseEnds)
end

local function structureRows()
	local rows = Structures.rows()
	local t = now()
	for _, r in rows do
		r[7] = t + (r[7] - Sim.tick) / Config.TickRate -- readyTick -> server time
		r[8] = t + math.max(0, r[8] - Sim.tick) / Config.TickRate
	end
	return rows
end

local function nationList()
	local out = {}
	for _, n in Sim.nations do
		out[#out + 1] = { n.id, n.name, n.color, n.kind, n.userId, n.alive, n.skin or false, n.flag or false, (n :: any).vehicles or false }
	end
	return out
end

local function snapshotFor(p: Player)
	return {
		round = Match.roundId,
		version = Match.pinnedVersion,
		map = Match.mapId,
		w = Sim.W,
		h = Sim.H,
		claimable = Sim.claimable,
		terrain = MapGen.rleEncode(Sim.terrain(), Sim.N, 1),
		owner = MapGen.rleEncode(Sim.ownerCopy(), Sim.N, 2),
		seq = Sim.seq,
		nations = nationList(),
		structures = structureRows(),
		units = Units.snapshotRows(),
		diplomacy = Diplomacy.rows(now()),
		air = Air.rows(now()),
		me = playerNation[p] or 0,
	}
end

local function pushNations()
	R.Nations:FireAllClients(nationList())
end

local function feed(text: string, kind: string, to: Player?)
	if to then
		R.Feed:FireClient(to, text, kind)
	else
		R.Feed:FireAllClients(text, kind)
	end
end

local function playerOf(nid: number): Player?
	for p, id in playerNation do
		if id == nid then
			return p
		end
	end
	return nil
end

----------------------------------------------------------------------------
-- round lifecycle

local function spawnBots(rng: Random, used: { [string]: boolean })
	local B = Config.Maps[Match.mapId] or Config.Maps.compact
	for k = 1, B.Nations + B.Tribes do
		local tribe = k > B.Nations
		local kind = if tribe then "tribe" else "nation"
		local pal = if tribe then Config.TribeColors else Config.BotColors
		local x, y = Bots.findSpawn(rng, Config.Spawn.MinDist)
		local name = x and y and Sim.regionName(y * Sim.W + x)
		-- prefer a region nobody holds yet
		for _ = 1, 25 do
			if not name or not used[name] then
				break
			end
			x, y = Bots.findSpawn(rng, Config.Spawn.MinDist)
			name = x and y and Sim.regionName(y * Sim.W + x)
		end
		if name and used[name] then
			name = nil
		end
		if x and y then
			if name then
				used[name] = true
			end
			local n = Sim.addNation(name or Bots.name(rng, kind, used), pal[(k - 1) % #pal + 1], kind, 0)
			Sim.claimFootprint(n, x, y, if tribe then Config.Spawn.TribeRadius else Config.Spawn.BotRadius)
		end
	end
end

function Match.startRound()
	Match.roundId += 1
	Match.pinnedVersion = Config.Version
	-- chosen map (menu / reserved server) or the public rotation
	if Match.nextMap then
		Match.mapId = Match.nextMap
		Match.nextMap = nil
	end
	remotes:SetAttribute("Map", Match.mapId)
	local seed = math.random(1, 2 ^ 30)
	local terr, w, h, regions, names = MapGen.load(Match.mapId, seed)
	Sim.reset(terr, w, h, seed + Match.roundId)
	Sim.regions, Sim.regionNames = regions, names
	Structures.reset()
	Structures.changed = false
	Units.reset()
	Trade.reset()
	Diplomacy.reset()
	Nukes.reset()
	Air.reset()
	Bots.reset()
	table.clear(playerNation)
	local used: { [string]: boolean } = {}
	local ci = 0
	for _, p in Players:GetPlayers() do
		if queued[p] ~= false and ci < maxHumans() then
			ci += 1
			local n = Sim.addNation(p.DisplayName, Config.HumanColors[(ci - 1) % #Config.HumanColors + 1], "human", p.UserId)
			used[n.name] = true
			n.skin, n.flag, (n :: any).vehicles = Shop.equippedOf(p)
			playerNation[p] = n.id
		end
	end
	spawnBots(Sim.rng(), used)
	-- hidden nation that owns tutorial training drones (never spawns land)
	Match.drillNation = Sim.addNation("Training Drone", "9AA4B2", "drill", 0).id
	table.clear(drills)
	hadHumans = ci > 0
	noHumanSince = nil
	setPhase("Spawn", MC.SpawnTime)
	remotes:SetAttribute("Round", Match.roundId)
	remotes:SetAttribute("Claimable", Sim.claimable)
	for _, p in Players:GetPlayers() do
		p:SetAttribute("NationId", playerNation[p] or 0)
		R.Snapshot:FireClient(p, snapshotFor(p))
	end
	feed("Pick your starting land!", "info")
end

local function beginPlaying()
	local rng = Sim.rng()
	for _, n in Sim.nations do
		if not n.spawned and n.kind ~= "drill" then
			local x, y = Bots.findSpawn(rng, Config.Spawn.MinDist)
			if x and y then
				Sim.claimFootprint(n, x, y, Config.Spawn.Radius)
			end
		end
	end
	roundStart = now()
	remotes:SetAttribute("RoundStart", roundStart)
	setPhase("Playing", MC.TimeCap)
	pushNations()
	feed("The war begins. Expand into neutral land!", "info")
end

local function rankRows()
	local rows = {}
	for _, n in Sim.nations do
		if n.spawned or n.land > 0 then
			rows[#rows + 1] = n
		end
	end
	-- tiebreak (documented): alive first; land, peak land, troops, lower id; dead by later elimination
	table.sort(rows, function(a, b)
		if a.alive ~= b.alive then
			return a.alive
		end
		if not a.alive then
			return a.elimTick > b.elimTick
		end
		if a.land ~= b.land then
			return a.land > b.land
		end
		if a.peakLand ~= b.peakLand then
			return a.peakLand > b.peakLand
		end
		if a.troops ~= b.troops then
			return a.troops > b.troops
		end
		return a.id < b.id
	end)
	return rows
end

function Match.endRound(reason: string, winner: Sim.Nation?)
	if Match.phase ~= "Playing" then
		return
	end
	local c = math.max(Sim.claimable, 1)
	local rows = rankRows()
	local out = {}
	for place, n in rows do
		out[#out + 1] = {
			id = n.id,
			name = n.name,
			color = n.color,
			kind = n.kind,
			place = place,
			land = n.land / c,
			peak = n.peakLand / c,
			captured = n.stats.captured,
			attacks = n.stats.attacks,
			eliminated = n.stats.eliminated,
			alive = n.alive,
		}
	end
	local w = winner or rows[1]
	-- random maps to vote on (always shuffled, never fixed)
	local pool = table.clone(Config.MapOrder)
	voteOptions = {}
	table.clear(votes)
	for _ = 1, math.min(MC.VoteOptions, #pool) do
		table.insert(voteOptions, table.remove(pool, math.random(1, #pool)) :: string)
	end
	-- coins for every player who held a nation this round (once per round)
	for pl, nid in playerNation do
		for place, n in rows do
			if n.id == nid then
				local coins = Shop.reward(pl, game.JobId .. ":" .. Match.roundId, place, n.stats.captured, w ~= nil and w.id == nid)
				if coins > 0 then
					feed(("+%d coins"):format(coins), "big", pl)
				end
			end
		end
	end
	R.Results:FireAllClients({
		reason = reason,
		winner = if w then w.id else 0,
		duration = now() - roundStart,
		rows = out,
		vote = voteOptions,
		voteEnds = now() + MC.ResultsTime,
	})
	setPhase("Ended", MC.ResultsTime)
	feed(if w then (w.name .. " wins the round!") else "Round over", "big")
end

local function checkEnd()
	local need = Sim.claimable * MC.VictoryShare
	local alive, last = 0, nil
	local humansAlive = 0
	for _, n in Sim.nations do
		if n.alive and n.spawned then
			alive += 1
			last = n
			if n.kind == "human" then
				humansAlive += 1
			end
			if n.land >= need then
				return Match.endRound("victory", n)
			end
		end
	end
	if alive <= 1 then
		return Match.endRound("last nation standing", last)
	end
	if now() >= phaseEnds then
		return Match.endRound("time cap", nil)
	end
	if MC.EndWhenNoHumans and hadHumans then
		if humansAlive == 0 then
			noHumanSince = noHumanSince or now()
			if now() - (noHumanSince :: number) >= MC.NoHumanGrace then
				return Match.endRound("all players eliminated", nil)
			end
		else
			noHumanSince = nil
		end
	end
end

----------------------------------------------------------------------------
-- replication

local function statsBuffer(): buffer
	local list = Sim.nations
	local b = buffer.create(2 + #list * 19)
	buffer.writeu16(b, 0, #list)
	local o = 2
	for _, n in list do
		buffer.writeu16(b, o, n.id)
		buffer.writeu32(b, o + 2, math.floor(math.max(n.troops, 0)))
		buffer.writeu32(b, o + 6, math.floor(n.maxTroops))
		buffer.writeu32(b, o + 10, n.land)
		buffer.writeu32(b, o + 14, math.floor(n.gold))
		buffer.writeu8(b, o + 18, (if n.alive then 1 else 0) + (if n.spawned then 2 else 0))
		o += 19
	end
	return b
end

local function pushStats()
	local sb = statsBuffer()
	account(buffer.len(sb) + 16, true)
	R.Stats:FireAllClients(sb, Sim.seq)
	for p, nid in playerNation do
		local n = Sim.nations[nid]
		if n then
			local mine = {}
			for _, att in n.attacks do
				mine[#mine + 1] = { att.id, att.target, math.floor(att.troops) }
			end
			-- fronts aimed at this player (RoWorld's attacks panel lists incoming wars too)
			local incoming = {}
			for _, o in Sim.nations do
				if o.id ~= nid and o.alive then
					for _, att in o.attacks do
						if att.target == nid then
							incoming[#incoming + 1] = { att.id, o.id, math.floor(att.troops) }
						end
					end
				end
			end
			account(48 + (#mine + #incoming) * 16, false)
			R.Mine:FireClient(p, { fronts = mine, incoming = incoming, income = n.income })
		end
	end
end

----------------------------------------------------------------------------
-- commands (all client input is untrusted)

local function validCell(c: any): number?
	if typeof(c) ~= "number" or c ~= c or c % 1 ~= 0 or c < 0 or c >= Sim.N then
		return nil
	end
	return c
end

local function allow(p: Player): boolean
	local t = os.clock()
	local b = bucket[p]
	if not b then
		b = { t = t, tokens = Config.Net.CmdPerSecond }
		bucket[p] = b
	end
	b.tokens = math.min(Config.Net.CmdPerSecond, b.tokens + (t - b.t) * Config.Net.CmdPerSecond)
	b.t = t
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

-- returns true if this command id was already processed
local function duplicate(p: Player, id: any): boolean
	if typeof(id) ~= "string" or #id > 40 then
		return false
	end
	local s = seenCmd[p]
	if not s then
		s = {}
		seenCmd[p] = s
		seenCount[p] = 0
	end
	if s[id] then
		return true
	end
	s[id] = true
	seenCount[p] += 1
	if seenCount[p] > 256 then
		seenCmd[p] = { [id] = true }
		seenCount[p] = 1
	end
	return false
end

local handlers: { [string]: (Player, { [any]: any }) -> (boolean, any) } = {}

handlers.hello = function(p)
	return true, snapshotFor(p)
end

handlers.resync = function(p)
	local t = os.clock()
	if t - (lastResync[p] or 0) < Config.Net.ResyncCooldown then
		return false, "wait"
	end
	lastResync[p] = t
	return true, snapshotFor(p)
end

handlers.spawn = function(p, a)
	if Match.phase ~= "Spawn" then
		return false, "Spawning is closed"
	end
	local nid = playerNation[p]
	local n = nid and Sim.nations[nid]
	if not n then
		return false, "You are spectating this round"
	end
	local c = validCell(a.cell)
	if not c then
		return false, "Bad location"
	end
	if not Sim.isClaimable(c) then
		return false, "Pick land, not water"
	end
	local o = Sim.ownerAt(c)
	if o ~= 0 and o ~= n.id then
		return false, "That land is taken"
	end
	local x, y = c % Sim.W, c // Sim.W
	if Sim.foreignNear(x, y, Config.Spawn.MinDist, n.id) then
		return false, "Too close to another nation"
	end
	Sim.releaseLand(n)
	Sim.claimFootprint(n, x, y, Config.Spawn.Radius)
	return true, "Spawn set"
end

handlers.attack = function(p, a)
	if Match.phase ~= "Playing" then
		return false, "The round has not started"
	end
	if duplicate(p, a.id) then
		return true, "dup"
	end
	local nid = playerNation[p]
	local n = nid and Sim.nations[nid]
	if not n or not n.alive then
		return false, "You are spectating"
	end
	local c = validCell(a.cell)
	local ratio = a.ratio
	if not c or typeof(ratio) ~= "number" or ratio ~= ratio then
		return false, "Bad order"
	end
	ratio = math.clamp(ratio, 0.01, 1)
	if not Sim.isClaimable(c) then
		return false, "Water: crossing needs ports and transports (coming next)"
	end
	local target = Sim.ownerAt(c)
	if target == n.id then
		return false, "That is your own land"
	end
	local ok, msg = Sim.startAttack(n.id, target, n.troops * ratio)
	if ok and target ~= 0 then
		local tp = playerOf(target)
		if tp then
			feed(n.name .. " is attacking you!", "warn", tp)
		end
	end
	return ok, msg
end

handlers.retreat = function(p, a)
	if duplicate(p, a.id) then
		return true, "dup"
	end
	local nid = playerNation[p]
	local aid = a.attack
	if not nid or typeof(aid) ~= "number" or aid ~= aid then
		return false, "Bad order"
	end
	if Sim.retreat(nid, aid) then
		return true, ("Retreated (%d%% of troops return)"):format(Config.Combat.RetreatRefund * 100)
	end
	return false, "That front already ended"
end

local function liveNation(p: Player): Sim.Nation?
	local nid = playerNation[p]
	local n = nid and Sim.nations[nid]
	if Match.phase ~= "Playing" or not n or not n.alive then
		return nil
	end
	return n
end

handlers.build = function(p, a)
	if duplicate(p, a.id) then
		return true, "dup"
	end
	local n = liveNation(p)
	if not n then
		return false, "You can't build right now"
	end
	local c = validCell(a.cell)
	if not c or typeof(a.kind) ~= "string" or not Config.Structures[a.kind] then
		return false, "Bad order"
	end
	return Structures.build(n.id, a.kind, c)
end

handlers.upgrade = function(p, a)
	if duplicate(p, a.id) then
		return true, "dup"
	end
	local n = liveNation(p)
	if not n or typeof(a.structure) ~= "number" or a.structure ~= a.structure then
		return false, "Bad order"
	end
	return Structures.upgrade(n.id, a.structure)
end

handlers.boat = function(p, a)
	if duplicate(p, a.id) then
		return true, "dup"
	end
	local n = liveNation(p)
	local c = validCell(a.cell)
	local ratio = a.ratio
	if not n or not c or typeof(ratio) ~= "number" or ratio ~= ratio then
		return false, "Bad order"
	end
	local ok, msg = Naval.sendBoat(n.id, c, n.troops * math.clamp(ratio, 0.01, 1))
	if ok then
		local tp = playerOf(Sim.ownerAt(c))
		if tp then
			feed(n.name .. " launched a boat toward you!", "warn", tp)
		end
	end
	return ok, msg
end

handlers.warship = function(p, a)
	if duplicate(p, a.id) then
		return true, "dup"
	end
	local n = liveNation(p)
	if not n or typeof(a.port) ~= "number" or a.port ~= a.port then
		return false, "Bad order"
	end
	return Naval.buildWarship(n.id, a.port)
end

handlers.moveship = function(p, a)
	local n = liveNation(p)
	local c = validCell(a.cell)
	if not n or not c or typeof(a.unit) ~= "number" or a.unit ~= a.unit then
		return false, "Bad order"
	end
	return Naval.moveWarship(n.id, a.unit, c)
end

handlers.ally = function(p, a)
	if duplicate(p, a.id) then
		return true, "dup"
	end
	local n = liveNation(p)
	local t = a.target
	if not n or typeof(t) ~= "number" or t ~= t or not Sim.nations[t] or typeof(a.action) ~= "string" then
		return false, "Bad order"
	end
	if a.action == "request" then
		return Diplomacy.request(n.id, t)
	elseif a.action == "accept" then
		return Diplomacy.accept(n.id, t)
	elseif a.action == "decline" then
		return Diplomacy.decline(n.id, t)
	elseif a.action == "break" then
		return Diplomacy.breakWith(n.id, t)
	end
	return false, "Bad order"
end

handlers.nuke = function(p, a)
	if duplicate(p, a.id) then
		return true, "dup"
	end
	local n = liveNation(p)
	local c = validCell(a.cell)
	if not n or not c or typeof(a.silo) ~= "number" or a.silo ~= a.silo then
		return false, "Bad order"
	end
	return Nukes.launch(n.id, a.silo, c)
end

handlers.air = function(p, a)
	if duplicate(p, a.id) then
		return true, "dup"
	end
	local n = liveNation(p)
	local c = validCell(a.cell)
	if not n or not c or typeof(a.airfield) ~= "number" or a.airfield ~= a.airfield
		or (a.mission ~= "strike" and a.mission ~= "cap") then
		return false, "Bad order"
	end
	return Air.launch(n.id, a.airfield, a.mission, c, a.escort == true)
end

-- tutorial air drill: a slow harmless drone flies at your land; place a free patrol on its route
handlers.drill = function(p, a)
	local n = liveNation(p)
	if not n then
		return false, "Join a round first"
	end
	local d = drills[p] or { count = 0, drone = nil, patrol = false }
	drills[p] = d
	local drone = d.drone and Units.list[d.drone]
	local W = Sim.W
	local home = n.spawnY * W + n.spawnX
	if a.action == "start" then
		if drone then
			return false, "A drill is already running"
		end
		if d.count >= MC.MaxDrills then
			return false, "No drills left this round"
		end
		d.count += 1
		d.patrol = false
		local ang = Sim.rng():NextNumber() * math.pi * 2
		local sx = math.clamp(n.spawnX + math.floor(math.cos(ang) * 30), 0, W - 1)
		local sy = math.clamp(n.spawnY + math.floor(math.sin(ang) * 30), 0, Sim.H - 1)
		local Path = require(script.Parent.Path)
		local u = Units.spawn("bomber", Match.drillNation, Path.line(sy * W + sx, home), 2.5,
			{ mission = "strike", state = "out", drill = true, target = home, airfield = -1, victim = n.id }, Config.Air.BomberHp)
		d.drone = u.id
		return true, "Training drone inbound: click its route to place your free fighter"
	elseif a.action == "patrol" then
		local c = validCell(a.cell)
		if not drone or not c then
			return false, "Start a drill first"
		end
		if d.patrol then
			return false, "Your patrol is already out"
		end
		d.patrol = true
		local Path = require(script.Parent.Path)
		Units.spawn("fighter", n.id, Path.line(home, c), Config.Air.FighterSpeed,
			{ mission = "cap", state = "out", drill = true, target = c, airfield = -1 }, Config.Air.FighterHp)
		return true, "Fighter scrambled"
	end
	return false, "Bad order"
end

-- aid: send a share of your troops or gold to an ally
handlers.aid = function(p, a)
	if duplicate(p, a.id) then
		return true, "dup"
	end
	local n = liveNation(p)
	local t = a.target
	local T = typeof(t) == "number" and t == t and Sim.nations[t]
	local ratio = a.ratio
	if not n or not T or not T.alive or typeof(ratio) ~= "number" or ratio ~= ratio then
		return false, "Bad order"
	end
	if not Sim.allied(n.id, T.id) then
		return false, "You can only send aid to allies"
	end
	ratio = math.clamp(ratio, 0.05, 0.5)
	local tp = playerOf(T.id)
	if a.kind == "troops" then
		local amt = math.floor(n.troops * ratio)
		if amt < 10 then
			return false, "Not enough troops"
		end
		n.troops -= amt
		T.troops += amt
		if tp then
			feed(("%s sent you %d troops"):format(n.name, amt), "info", tp)
		end
		return true, ("Sent %d troops to %s"):format(amt, T.name)
	elseif a.kind == "gold" then
		local amt = math.floor(n.gold * ratio)
		if amt < 10 then
			return false, "Not enough gold"
		end
		n.gold -= amt
		T.gold += amt
		if tp then
			feed(("%s sent you %d gold"):format(n.name, amt), "info", tp)
		end
		return true, ("Sent %d gold to %s"):format(amt, T.name)
	end
	return false, "Bad order"
end

-- launch buttons: the nearest ready launcher is chosen for you
handlers.launch = function(p, a)
	if duplicate(p, a.id) then
		return true, "dup"
	end
	local n = liveNation(p)
	local c = validCell(a.cell)
	if not n or not c or typeof(a.kind) ~= "string" then
		return false, "Bad order"
	end
	local W = Sim.W
	local function nearest(kind: string, filter: ((any) -> boolean)?): any
		local best, bd = nil, math.huge
		for _, s in Structures.list do
			if s.kind == kind and s.owner == n.id and s.done and s.disabledUntil <= Sim.tick and (not filter or filter(s)) then
				local d = (s.cell % W - c % W) ^ 2 + (s.cell // W - c // W) ^ 2
				if d < bd then
					best, bd = s, d
				end
			end
		end
		return best
	end
	if a.kind == "warship" then
		return Naval.launchWarship(n.id, c)
	elseif a.kind == "fighter" or a.kind == "bomber" then
		local mission = if a.kind == "fighter" then "cap" else "strike"
		local af = nearest("airfield", function(s)
			return Air.sortiesFrom(s.id) < Config.Air.SortiesPerAirfield and Air.turnaroundLeft(s.id) <= 0
		end)
		if not af then
			return false, "No free airfield (build one, or wait for the sortie to land)"
		end
		return Air.launch(n.id, af.id, mission, c, a.escort == true)
	elseif a.kind == "missile" or a.kind == "nuke" then
		local silo = nearest("silo", function(s)
			return Nukes.siloCooldownLeft(s.id) <= 0
		end)
		if not silo then
			return false, "Build a Missile Silo first"
		end
		if a.kind == "nuke" then
			return Nukes.launch(n.id, silo.id, c)
		end
		return Nukes.launchMissile(n.id, silo.id, c)
	end
	return false, "Bad order"
end

-- end-of-round map vote (voteOptions / votes are declared at the top)
handlers.vote = function(p, a)
	if Match.phase ~= "Ended" or typeof(a.map) ~= "string" or not table.find(voteOptions, a.map) then
		return false, "Voting is closed"
	end
	votes[p] = a.map
	local counts = {}
	for _, m in votes do
		counts[m] = (counts[m] or 0) + 1
	end
	R.Vote:FireAllClients(counts)
	return true, "Vote counted"
end

local function pickVoted(): string
	local counts, best, bestN = {}, {}, 0
	for _, m in votes do
		counts[m] = (counts[m] or 0) + 1
	end
	for _, m in voteOptions do
		local c = counts[m] or 0
		if c > bestN then
			best, bestN = { m }, c
		elseif c == bestN then
			table.insert(best, m)
		end
	end
	if #best == 0 then
		return voteOptions[math.random(1, #voteOptions)] or Config.MapOrder[1]
	end
	return best[math.random(1, #best)] -- ties (and no votes) are random
end

handlers.requeue = function(p, a)
	queued[p] = a.on ~= false
	return true, if queued[p] then "Queued for next round" else "Spectating next round"
end

----------------------------------------------------------------------------

function Match.init()
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	for _, nm in { "Snapshot", "Delta", "Stats", "Mine", "Nations", "Feed", "Results", "Structures", "Units", "Diplomacy", "Air", "AirFx", "Vote" } do
		local e = Instance.new("RemoteEvent")
		e.Name = nm
		e.Parent = remotes
		R[nm] = e
	end
	local cmd = Instance.new("RemoteFunction")
	cmd.Name = "Cmd"
	cmd.Parent = remotes
	remotes:SetAttribute("Version", Config.Version)
	remotes:SetAttribute("Map", Config.Map.Id)
	remotes.Parent = ReplicatedStorage

	local menu = Instance.new("RemoteFunction")
	menu.Name = "Menu"
	menu.Parent = remotes
	local function state()
		return Match.mapId, Match.phase, maxHumans()
	end
	Players.PlayerRemoving:Connect(function()
		Match.paused = false -- a paused solo match never stays frozen
	end)
	menu.OnServerInvoke = function(p: Player, action: any, arg: any)
		if typeof(action) ~= "string" or not allow(p) then
			return false, "slow down"
		end
		if typeof(arg) ~= "table" then
			arg = {}
		end
		if action == "pause" then
			-- solo only (a reserved solo server, one human): the game menu / help freeze the match
			if not ServerList.solo or #Players:GetPlayers() ~= 1 then
				Match.paused = false
				return false, "Only solo matches pause"
			end
			Match.paused = arg.on == true and Match.phase == "Playing"
			return true, if Match.paused then "paused" else "resumed"
		elseif action == "settings_get" then
			local prof = PlayerData.get(p)
			if not prof then
				return false, "loading"
			end
			local out = table.clone(prof.settings or {})
			out.stats = { matches = prof.matches, wins = prof.wins }
			return true, out
		elseif action == "settings_set" then
			-- one section of plain values; capped so a client can't bloat its profile
			local prof = PlayerData.get(p)
			local sec, vals = arg.section, arg.values
			if not prof or typeof(sec) ~= "string" or #sec > 24 or sec == "stats" or typeof(vals) ~= "table" then
				return false, "bad"
			end
			local ok, json = pcall(HttpService.JSONEncode, HttpService, vals)
			if not ok or #json > 4000 then
				return false, "too big"
			end
			prof.settings = prof.settings or {}
			local n = 0
			for _ in prof.settings do
				n += 1
			end
			if prof.settings[sec] == nil and n >= 8 then
				return false, "too many"
			end
			prof.settings[sec] = HttpService:JSONDecode(json)
			return true, "ok"
		elseif action == "info" then
			return true, { here = ServerList.selfInfo(state), servers = ServerList.list() }
		elseif action == "solo" then
			local d = if typeof(arg.diff) == "number" and Config.Difficulty[arg.diff] then arg.diff else 1
			return ServerList.host(p, arg.map, true, d)
		elseif action == "match" then
			return ServerList.matchmake(p, arg.map, ServerList.selfInfo(state))
		elseif action == "join" then
			return ServerList.join(p, arg.key)
		end
		return false, "unknown"
	end
	-- Studio can't teleport: restart this server's match on the chosen map
	ServerList.onLocalMap = function(mapId, solo, diff)
		Match.nextMap = mapId
		ServerList.solo = solo
		Bots.thinkMul = if solo and diff and Config.Difficulty[diff] then Config.Difficulty[diff].Think else 1
		if Match.phase == "Playing" then
			Match.endRound("new map chosen", nil)
		end
		setPhase("Lobby", 1)
		return true, ("Starting %s here (Studio can't teleport)"):format(Config.Maps[mapId].Name)
	end
	task.spawn(function()
		while true do
			ServerList.publish(state)
			task.wait(10)
		end
	end)
	game:BindToClose(function()
		ServerList.unpublish()
	end)

	cmd.OnServerInvoke = function(p: Player, kind: any, args: any)
		if typeof(kind) ~= "string" or not allow(p) then
			return false, "slow down"
		end
		local h = handlers[kind]
		if not h then
			return false, "unknown"
		end
		if typeof(args) ~= "table" then
			args = {}
		end
		local ok, res, extra = pcall(h, p, args)
		if not ok then
			warn("[Cmd]", kind, res)
			return false, "server error"
		end
		return res, extra
	end

	Structures.onEvent = function(kind, s, info)
		local def = Config.Structures[s.kind]
		if kind == "captured" then
			local lp = playerOf(info.from)
			if lp then
				feed(("Your %s was captured by %s"):format(def.name, Sim.nations[s.owner].name), "warn", lp)
			end
		elseif kind == "destroyed" then
			local lp = playerOf(s.owner)
			if lp then
				feed(("Your %s was destroyed"):format(def.name), "warn", lp)
			end
		elseif kind == "completed" then
			local lp = playerOf(s.owner)
			if lp then
				feed(("%s ready"):format(def.name), "info", lp)
			end
		end
	end

	Sim.defenseMult = function(cell, target)
		return Structures.defenseMult(cell, target) * Air.suppressMult(cell, target)
	end
	local lastAaMsg: { [string]: number } = {}
	Air.onEvent = function(kind, info)
		local op = playerOf(info.owner)
		local vp = info.victim and playerOf(info.victim)
		local O = Sim.nations[info.owner]
		local oname = if O then O.name else "?"
		if kind == "launched" then
			if vp then
				feed(("Enemy bomber from %s inbound! ETA %ds. Launch fighters or build AA."):format(oname, math.ceil(info.eta)), "warn", vp)
			end
		elseif kind == "bombed" then
			if op then
				feed(("Strike hit: -%d troops. Ground-attack window %ds!"):format(info.loss, info.window), "info", op)
			end
			if vp then
				feed(("Bombers hit your front: -%d troops"):format(info.loss), "warn", vp)
			end
		elseif kind == "struck" then
			local nm = Config.Structures[info.kind].name
			if op then
				feed(("Strike disabled their %s for %ds"):format(nm, info.recover), "info", op)
			end
			if vp then
				feed(("Your %s was bombed: offline for %ds"):format(nm, info.recover), "warn", vp)
			end
		elseif kind == "aborted" then
			if op then
				feed("Bomber aborted: " .. info.why, "warn", op)
			end
		elseif kind == "lost" then
			if op then
				feed(("Your %s was lost (no airfield to land)"):format(info.kind), "warn", op)
			end
		elseif kind == "shotdown" then
			local by = if info.by == "aa" then "AA" else "a fighter"
			if op then
				feed(("Your %s shot down a %s"):format(by, info.kind), "info", op)
			end
			if vp then
				feed(("Your %s was shot down by %s"):format(info.kind, by), "warn", vp)
			end
		end
		if kind == "drillOk" or kind == "drillFail" then
			local pl = playerOf(info.owner)
			if pl then
				R.Feed:FireClient(pl, if kind == "drillOk" then "Drill passed: drone intercepted!" else "Drone got through. Try again: put the patrol right on its path.", if kind == "drillOk" then "drill_ok" else "drill_fail")
				local dd = drills[pl]
				if dd then
					dd.drone = nil
				end
			end
			return
		end
		if kind == "aa" or kind == "shotdown" then
			R.AirFx:FireAllClients(kind, info.cell, info.hit, info.aa)
			-- per-shot result to both sides (throttled toasts)
			if kind == "aa" then
				for _, pl in { op, vp } do
					if pl then
						local key = pl.UserId .. ":" .. tostring(info.hit)
						if os.clock() - (lastAaMsg[key] or 0) > 2 then
							lastAaMsg[key] = os.clock()
							R.Feed:FireClient(pl, if info.hit then "AA hit an aircraft" else "AA shot missed", "toast")
						end
					end
				end
			end
		end
	end

	Nukes.onEvent = function(kind, info)
		local A = Sim.nations[info.owner]
		if not A then
			return
		end
		if kind == "launched" and info.small then
			local vp = playerOf(info.victim)
			if vp then
				feed(A.name .. " fired a missile at you!", "warn", vp)
			end
		elseif kind == "impact" and info.small then
			return
		elseif kind == "launched" then
			feed(A.name .. " launched a nuclear missile!", "elim")
			-- warn everyone with land inside the blast
			local W = Sim.W
			local cx, cy = info.target % W, info.target // W
			local R = Config.Nuke.Radius
			local hit = {}
			for y = math.max(0, cy - R), math.min(Sim.H - 1, cy + R) do
				for x = math.max(0, cx - R), math.min(W - 1, cx + R) do
					local o = Sim.ownerAt(y * W + x)
					if o ~= 0 and o ~= info.owner then
						hit[o] = true
					end
				end
			end
			for o in hit do
				local vp = playerOf(o)
				if vp then
					feed(("INCOMING NUKE! Impact in %ds. Build SAMs to intercept."):format(math.ceil(info.eta)), "warn", vp)
				end
			end
		elseif kind == "impact" then
			local names = {}
			for o, cells in info.lost do
				local n = Sim.nations[o]
				if n then
					table.insert(names, ("%s -%d"):format(n.name, cells))
				end
			end
			feed("Nuclear impact: " .. (if #names > 0 then table.concat(names, ", ") else "no land hit"), "elim")
		elseif kind == "intercepted" then
			local S = Sim.nations[info.sam]
			feed(("%s's SAM intercepted a missile from %s"):format(if S then S.name else "A", A.name), "info")
		end
	end

	Shop.onEquip = function(pl)
		local nid = playerNation[pl]
		local n = nid and Sim.nations[nid]
		if n then
			n.skin, n.flag, (n :: any).vehicles = Shop.equippedOf(pl)
			pushNations()
		end
	end

	Diplomacy.onEvent = function(kind, a, b)
		local A, B = Sim.nations[a], Sim.nations[b]
		if not A or not B then
			return
		end
		local pa, pb = playerOf(a), playerOf(b)
		if kind == "formed" then
			feed(("%s and %s formed an alliance"):format(A.name, B.name), "info")
		elseif kind == "requested" then
			if pb then
				feed(A.name .. " proposes an alliance", "info", pb)
			end
		elseif kind == "declined" then
			if pa then
				feed(B.name .. " declined your alliance", "warn", pa)
			end
		elseif kind == "breaking" then
			feed(("%s is breaking its alliance with %s (%ds)"):format(A.name, B.name, Config.Diplomacy.BreakGrace), "warn")
		elseif kind == "ended" then
			feed(("%s and %s are no longer allies"):format(A.name, B.name), "elim")
		elseif kind == "expired" then
			feed(("The alliance between %s and %s expired"):format(A.name, B.name), "warn")
		elseif kind == "renewed" then
			feed(("%s and %s renewed their alliance"):format(A.name, B.name), "info")
		elseif kind == "renewreq" then
			if pb then
				feed(A.name .. " wants to renew your alliance", "info", pb)
			end
		end
	end

	Naval.onEvent = function(kind, info)
		local op = playerOf(info.owner)
		local vp = info.victim and playerOf(info.victim)
		if kind == "repelled" and op then
			feed("Your landing was repelled", "warn", op)
		elseif kind == "landed" then
			if op then
				feed("Your troops landed", "info", op)
			end
			local tp = playerOf(info.target)
			if tp then
				feed(Sim.nations[info.owner].name .. " landed on your coast!", "warn", tp)
			end
		elseif kind == "sunk" then
			if op then
				feed(("Your warship sank a %s"):format(if info.kind == "transport" then "transport" else "warship"), "info", op)
			end
			if vp then
				feed(("Your %s was sunk"):format(if info.kind == "transport" then "transport" else "warship"), "warn", vp)
			end
		elseif kind == "seized" then
			if op then
				feed("Your warship seized a trade ship", "info", op)
			end
			if vp then
				feed("A trade ship was seized: trade interrupted", "warn", vp)
			end
		end
	end

	local lastInterrupt: { [number]: number } = {}
	Trade.onInterrupted = function(owner)
		local lp = playerOf(owner)
		local t = os.clock()
		if lp and t - (lastInterrupt[owner] or -99) >= Config.Trade.InterruptNotice then
			lastInterrupt[owner] = t
			feed("Trade interrupted: a train was cut off by enemy land", "warn", lp)
		end
	end

	Sim.onEliminated = function(victim, killer)
		feed(if killer then (killer.name .. " eliminated " .. victim.name) else (victim.name .. " collapsed"), "elim")
		Diplomacy.drop(victim.id)
		local vp = playerOf(victim.id)
		if vp then
			feed("Your nation fell. You are now spectating.", "warn", vp)
		end
		pushNations()
	end

	Players.PlayerAdded:Connect(function(p)
		queued[p] = true
		p:SetAttribute("NationId", 0)
		-- reserved servers (solo / hosted) learn their map from the teleport data
		local jd = ServerList.readJoinData(p)
		if jd and Match.roundId == 0 then
			ServerList.solo = jd.solo == true
			ServerList.code = jd.code
			local d = Config.Difficulty[tonumber(jd.diff) or 1]
			Bots.thinkMul = if jd.solo == true and d then d.Think else 1
			Match.nextMap = jd.map
		end
		-- rejoin: reclaim your nation if it's still standing
		if Match.phase == "Playing" or Match.phase == "Spawn" then
			for _, n in Sim.nations do
				if n.userId == p.UserId and n.userId ~= 0 and n.alive then
					n.kind = "human"
					n.disconnectedAt = nil
					playerNation[p] = n.id
					p:SetAttribute("NationId", n.id)
					pushNations()
					feed(n.name .. " is back in command", "info")
					return
				end
			end
		end
		-- late arrival during spawn phase gets a slot if one is free
		if Match.phase == "Spawn" then
			local humans = 0
			for _ in playerNation do
				humans += 1
			end
			if humans < maxHumans() then
				local n = Sim.addNation(p.DisplayName, Config.HumanColors[humans % #Config.HumanColors + 1], "human", p.UserId)
				playerNation[p] = n.id
				p:SetAttribute("NationId", n.id)
				pushNations()
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		local nid = playerNation[p]
		local n = nid and Sim.nations[nid]
		if n and n.alive then
			n.disconnectedAt = Sim.tick
			feed(n.name .. " disconnected", "warn")
		end
		drills[p] = nil
		playerNation[p] = nil
		queued[p], bucket[p], seenCmd[p], seenCount[p], lastResync[p] = nil, nil, nil, nil, nil
	end)

	-- empty world so clients have something to draw in the lobby
	Match.mapId = Config.Map.Id
	local terr, w, h, regions, names = MapGen.load(Match.mapId, 1)
	Sim.reset(terr, w, h, 1)
	Sim.regions, Sim.regionNames = regions, names
	Structures.reset()
	Units.reset()
	setPhase("Lobby", MC.LobbyTime)

	local acc, statAcc = 0, 0
	local dt = 1 / Config.TickRate
	RunService.Heartbeat:Connect(function(step)
		acc = math.min(acc + step, dt * 5)
		statAcc += step
		while acc >= dt do
			acc -= dt
			Match.tick()
		end
		if statAcc >= 1 / Config.Net.StatsHz then
			statAcc = 0
			pushStats()
		end
	end)
end

Match.tickMs = 0
Match.paused = false

-- one simulation tick in a fixed system order (also used by the headless ff test)
Match.prof = {} :: { [string]: number } -- max ms per system (dev profiling)
local SYSTEMS = {
	{ "bots", function(t) Bots.step(t) end },
	{ "sim", function() Sim.step() end },
	{ "structures", function() Structures.step() end },
	{ "trade", function() Trade.step() end },
	{ "units", function() Units.step() end },
	{ "air", function() Air.step() end },
	{ "diplomacy", function() Diplomacy.step() end },
}
function Match.simStep(t: number)
	for _, s in SYSTEMS do
		local t0 = os.clock()
		s[2](t)
		local ms = (os.clock() - t0) * 1000
		if ms > (Match.prof[s[1]] or 0) then
			Match.prof[s[1]] = ms
		end
	end
end
function Match.tick()
	local t0 = os.clock()
	if Match.paused then
		return
	end
	local ph = Match.phase
	local t = now()
	if ph == "Lobby" then
		if #Players:GetPlayers() < MC.MinHumans then
			phaseEnds = t + MC.LobbyTime
			remotes:SetAttribute("PhaseEnds", phaseEnds)
		elseif t >= phaseEnds then
			Match.startRound()
		end
	elseif ph == "Spawn" then
		if t >= phaseEnds then
			beginPlaying()
		end
	elseif ph == "Playing" then
		-- disconnected players: AI takes over after the grace period
		for _, n in Sim.nations do
			if n.kind == "human" and n.disconnectedAt and Sim.tick - n.disconnectedAt >= MC.ReconnectGrace * Config.TickRate then
				n.kind = "nation"
				pushNations()
				feed(n.name .. " is now AI-controlled", "info")
			end
		end
		Match.simStep(t)
		checkEnd()
	elseif ph == "Ended" then
		if t >= phaseEnds then
			if #voteOptions > 0 and not Match.nextMap then
				Match.nextMap = pickVoted()
				feed(("Next map: %s"):format(Config.Maps[Match.nextMap].Name), "big")
			end
			setPhase("Lobby", MC.LobbyTime)
		end
	end
	local d = Sim.flushDelta()
	if d then
		R.Delta:FireAllClients(d)
		account(buffer.len(d) + 16, true)
	end
	if Air.changed then
		Air.changed = false
		R.Air:FireAllClients(Air.rows(now()))
	end
	if Diplomacy.changed then
		Diplomacy.changed = false
		R.Diplomacy:FireAllClients(Diplomacy.rows(now()))
	end
	local us, ug = Units.flush()
	if us then
		local b = 16
		for _, r in us do
			b += buffer.len(r[4]) + 48
		end
		account(b + #(ug :: any) * 24, true)
		R.Units:FireAllClients(us, ug)
	end
	if Structures.changed then
		Structures.changed = false
		R.Structures:FireAllClients(structureRows())
	end
	Match.tickMs = Match.tickMs * 0.95 + (os.clock() - t0) * 1000 * 0.05
end

-- dev/test helpers (Studio only, used by DevTests)
Match._dev = {
	playerNation = playerNation,
	setPhaseEnds = function(t: number)
		phaseEnds = t
		remotes:SetAttribute("PhaseEnds", t)
	end,
	handlers = handlers,
	playerRemoving = function(p: Player)
		-- simulate a disconnect without kicking (Studio test)
		local nid = playerNation[p]
		local n = nid and Sim.nations[nid]
		if n then
			n.disconnectedAt = Sim.tick
		end
		playerNation[p] = nil
		p:SetAttribute("NationId", 0)
	end,
	rejoin = function(p: Player)
		for _, n in Sim.nations do
			if n.userId == p.UserId and n.alive then
				n.kind = "human"
				n.disconnectedAt = nil
				playerNation[p] = n.id
				p:SetAttribute("NationId", n.id)
				pushNations()
				return n.id
			end
		end
		return 0
	end,
}

return Match
