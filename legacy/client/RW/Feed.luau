--!nonstrict
-- Feeds RoWorld's GameState (ReplicatedStorage.Airfront.Core.GameState, AGPL; see NOTICE.md) from this
-- game's client State, so RoWorld's interface reads our match as if it were theirs: the map, owners,
-- tile ownership, stats, structures, units, nukes, fronts, alliances, messages, phases and results.
-- Our server stays authoritative; this is a display mirror of a display mirror.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local State = require(script.Parent.Parent.State)
local AF = ReplicatedStorage:WaitForChild("Airfront")
local Core = AF:WaitForChild("Core")
local Defs = require(Core:WaitForChild("Defs"))
local GameState = require(Core:WaitForChild("GameState"))
local WorldMap = require(Core:WaitForChild("WorldMap"))

local Feed = {}
Feed.state = nil :: any
Feed.epoch = 0 -- server time of tick 0

-- our structure kinds <-> RoWorld's slots (our AA battery takes the artillery slot)
Feed.S_OF = { city = Defs.S_CITY, port = Defs.S_PORT, factory = Defs.S_FACTORY, defense = Defs.S_DEFENSE, sam = Defs.S_SAM, silo = Defs.S_SILO, aa = Defs.S_ARTILLERY, airfield = Defs.S_AIRFIELD }
Feed.KIND_OF = {}
for k, v in Feed.S_OF do
	Feed.KIND_OF[v] = k
end
-- our sea units <-> RoWorld's unit kinds; missiles and nukes are RoWorld nukes
Feed.U_OF = { transport = Defs.U_TRANSPORT, trade = Defs.U_TRADE, cargo = Defs.U_TRADE, warship = Defs.U_WARSHIP }
Feed.N_OF = { missile = Defs.N_ATOM, nuke = Defs.N_HYDROGEN, bomber = Defs.N_AIRSTRIKE }

local function now(): number
	return workspace:GetServerTimeNow()
end

function Feed.tickAt(t: number): number
	return math.max(0, (t - Feed.epoch) * Defs.TICK_RATE)
end

function Feed.tick(): number
	return Feed.tickAt(now())
end

local function rgba(c: Color3): number
	return math.floor(c.R * 255 + 0.5) * 16777216 + math.floor(c.G * 255 + 0.5) * 65536 + math.floor(c.B * 255 + 0.5) * 256 + 255
end

-- our terrain (0 water, 1 plains, 2 highland, 3 mountain, 4 ice, 5 desert) as RoWorld tile bytes
local function buildMap(): any
	local W, H, N = State.W, State.H, State.N
	local m = WorldMap.new(W, H)
	m.id = State.map
	m.name = (Config.Maps[State.map] and Config.Maps[State.map].Name) or State.map
	local bytes = buffer.create(N)
	-- big water bodies are oceans (bit 0x20), small ones lakes
	for i = 0, N - 1 do
		local t = buffer.readu8(State.terrain, i)
		local b
		if t == 0 then
			local body = State.water and buffer.len(State.water) >= (i + 1) * 4 and buffer.readu32(State.water, i * 4) or 0
			local size = State.waterSize[body] or 0
			b = if size >= Config.OceanMin then 0x20 else 0x00
		elseif t == 4 then
			b = 0x9F
		elseif t == 3 then
			b = 128 + 25
		elseif t == 2 then
			b = 128 + 15
		else
			b = 128 + 4
		end
		buffer.writeu8(bytes, i, b)
	end
	m.tile_bytes = bytes
	m:_derive()
	-- only claimable land counts toward the win (ice / water excluded), like our server
	m.contestable_count = math.max(1, State.claimable)
	m.ok = true
	return m
end

local function kindOf(k: string): number
	return if k == "human" then Defs.KIND_HUMAN elseif k == "tribe" then Defs.KIND_TRIBE else Defs.KIND_NATION
end

local function centroidTile(id: number): number
	local c = State.cnt[id] or 0
	if c <= 0 then
		return -1
	end
	local x = math.floor(State.sumX[id] / c + 0.5)
	local y = math.floor(State.sumY[id] / c + 0.5)
	local t = y * State.W + x
	-- the centroid of a ring-shaped country can be outside it: fall back to any owned tile
	if t >= 0 and t < State.N and State.ownerAt(t) == id then
		return t
	end
	return Feed.anyTile[id] or t
end
Feed.anyTile = {} :: { [number]: number }
Feed.anchorOf = function(id: number): number
	return centroidTile(id)
end

-- owners: created on first sight, updated from State.nations (names, colours, stats)
function Feed.syncOwners(fireEvents: boolean)
	local s = Feed.state
	if not s then
		return
	end
	for id, n in State.nations do
		local o = s.owners[id]
		local fresh = o == nil
		if fresh then
			o = GameState.new_owner_info(id)
			s.owners[id] = o
		end
		local wasAlive, wasSpawned = o.alive, o.spawned
		o.name = n.name
		o.color = n.color
		o.rgba = rgba(n.color)
		o.kind = kindOf(n.kind)
		o.alive = n.alive
		o.spawned = n.spawned or (State.cnt[id] or 0) > 0
		o.tiles = State.cnt[id] or n.land or 0
		o.troops = n.troops * 10
		o.max_troops = n.max * 10
		o.gold = n.gold
		o.cx = State.sumX[id] or 0
		o.cy = State.sumY[id] or 0
		if id == State.me then
			o.income = (State.income.base or 0) + (State.income.trade or 0)
		end
		if fireEvents then
			if fresh then
				s.owner_added:Fire(id)
			end
			if o.spawned and not wasSpawned and not fresh then
				local t = centroidTile(id)
				o.spawn_tile = t
				s.owner_spawned:Fire(id, t)
			end
			if wasAlive and not o.alive and not fresh then
				s.owner_eliminated:Fire(id, o.killer or 0)
			end
		end
	end
end

-- full rebuild of the tile owner grid (i32 per tile)
local function fillOwners()
	local s = Feed.state
	local N = State.N
	local ob = s.owner
	for i = 0, N - 1 do
		local o = buffer.readu16(State.owner, i * 2)
		buffer.writei32(ob, i * 4, o)
		if o ~= 0 then
			Feed.anyTile[o] = i
		end
	end
end

function Feed.syncStructures(fireEvents: boolean)
	local s = Feed.state
	if not s then
		return
	end
	local seen = {}
	for id, st in State.structures do
		local kind = Feed.S_OF[st.kind]
		if kind then
			seen[id] = true
			local old = s.structures[id]
			local ready = st.readyAt or 0
			local info = old or { sid = id }
			local oldOwner = info.owner
			local oldLevel, oldActive = info.level, info.active_tick
			info.kind = kind
			info.owner = st.owner
			info.tile = st.cell
			info.level = math.max(1, st.level or 1)
			info.active_tick = if st.done then 0 else Feed.tickAt(ready)
			info.shots = info.shots or {}
			s.structures[id] = info
			if fireEvents then
				if not old then
					s.structure_added:Fire(id)
				elseif oldOwner ~= st.owner then
					s.structure_changed:Fire(id, oldOwner)
				elseif oldLevel ~= info.level or oldActive ~= info.active_tick then
					s.structure_leveled:Fire(id)
				end
			end
		end
	end
	for id in s.structures do
		if not seen[id] then
			if fireEvents then
				s.structure_removed:Fire(id)
			end
			s.structures[id] = nil
		end
	end
end

-- sea units -> state.units; missiles / nukes -> state.nukes
function Feed.syncUnits(fireEvents: boolean)
	local s = Feed.state
	if not s then
		return
	end
	local seenU, seenN = {}, {}
	for id, u in State.units do
		local uk, nk = Feed.U_OF[u.kind], Feed.N_OF[u.kind]
		if uk then
			seenU[id] = true
			if not s.units[id] then
				local path = table.create(u.n)
				for k = 0, u.n - 1 do
					path[k + 1] = buffer.readu32(u.path, k * 4)
				end
				local tps = if u.speed > 0 then math.max(1, math.floor(Defs.TICK_RATE / u.speed * 100)) else 100
				s.units[id] = {
					uid = id,
					kind = uk,
					owner = u.owner,
					path = path,
					start_tick = Feed.tickAt(u.t0) - (u.pos0 - 1) * tps / 100,
					ticks_per_tile_x100 = tps,
					troops = 0,
					prev_tile = path[1] or -1,
					move_tick = 0,
					hp = u.hp or 1,
					max_hp = math.max(u.hp or 1, 1),
					veterancy = 0,
					state = 0,
					patrol_tile = -1,
				}
				if fireEvents then
					s.unit_added:Fire(id)
				end
			end
		elseif nk then
			seenN[id] = true
			if not s.nukes[id] then
				local from = buffer.readu32(u.path, 0)
				local to = buffer.readu32(u.path, (u.n - 1) * 4)
				s.nukes[id] = {
					uid = id,
					kind = nk,
					owner = u.owner,
					from_tile = from,
					to_tile = to,
					launch_tick = Feed.tickAt(u.t0),
					flight_ticks = if u.speed > 0 then math.floor(u.n / u.speed * Defs.TICK_RATE) else 100,
				}
				if fireEvents then
					s.nuke_launched:Fire(id)
				end
			end
		end
	end
	for id in s.units do
		if not seenU[id] then
			if fireEvents then
				s.unit_removed:Fire(id, Defs.DEL_ARRIVED)
			end
			s.units[id] = nil
		end
	end
	for id, nk in s.nukes do
		if not seenN[id] then
			if fireEvents then
				local r = if nk.kind == Defs.N_HYDROGEN then Config.Nuke.Radius else (Config.Missile and Config.Missile.Radius or 3)
				s.nuke_detonated:Fire(id, nk.kind, nk.to_tile, r, nk.owner)
			end
			s.nukes[id] = nil
		end
	end
end

-- my fronts (Mine.fronts) and the fronts aimed at me (Mine.incoming) -> state.attacks
function Feed.syncAttacks(mine: { any }, incoming: { any }?)
	local s = Feed.state
	if not s then
		return
	end
	local seen = {}
	local function put(aid: number, attacker: number, target: number, troops: number)
		seen[aid] = true
		local a = s.attacks[aid]
		local anchor = if target ~= 0 then centroidTile(target) else centroidTile(attacker)
		if not a then
			s.attacks[aid] = { aid = aid, attacker = attacker, target = target, troops = troops, anchor_tile = anchor, retreating = false }
			s.attack_started:Fire(aid)
		elseif a.troops ~= troops then
			a.troops = troops
			a.anchor_tile = anchor
			s.attack_updated:Fire(aid)
		end
	end
	for _, f in mine do
		put(f[1], State.me, f[2], f[3] * 10)
	end
	for _, f in incoming or {} do
		put(f[1], f[2], State.me, f[3] * 10)
	end
	for aid in s.attacks do
		if not seen[aid] then
			s.attacks[aid] = nil
			s.attack_ended:Fire(aid)
		end
	end
end

local function pairKey(a: number, b: number): number
	return math.min(a, b) * 1024 + math.max(a, b)
end

function Feed.syncDiplomacy()
	local s = Feed.state
	if not s then
		return
	end
	local t = now()
	local newA, newR = {}, {}
	for _, p in State.diplo.pairs or {} do
		local k = pairKey(p[1], p[2])
		newA[k] = true
		s.alliance_expires[k] = Feed.tickAt(p[6] or t)
	end
	for _, r in State.diplo.requests or {} do
		if r[3] > t then
			newR[r[1] * 1024 + r[2]] = Feed.tick()
		end
	end
	for k in newA do
		if not s.alliances[k] then
			s.alliances[k] = true
			s.alliance_changed:Fire(k // 1024, k % 1024, true, false, false)
		end
	end
	for k in s.alliances do
		if not newA[k] then
			s.alliances[k] = nil
			s.alliance_expires[k] = nil
			s.alliance_changed:Fire(k // 1024, k % 1024, false, false, false)
		end
	end
	for k, v in newR do
		if not s.requests[k] then
			s.requests[k] = v
			s.alliance_requested:Fire(k // 1024, k % 1024)
		end
	end
	for k in s.requests do
		if not newR[k] then
			s.requests[k] = nil
			s.alliance_request_closed:Fire(k // 1024, k % 1024)
		end
	end
end

local PHASE = { Spawn = Defs.PHASE_SPAWN, Playing = Defs.PHASE_PLAYING }
function Feed.syncPhase(phase: string, ends: number, roundStart: number?)
	local s = Feed.state
	if not s then
		return
	end
	local ph = PHASE[phase] or Defs.PHASE_OVER
	local left = math.max(0, math.floor((ends - now()) * Defs.TICK_RATE))
	if ph == Defs.PHASE_PLAYING and roundStart and roundStart > 0 then
		s.playing_since = Feed.tickAt(roundStart)
	end
	if ph ~= s.phase then
		s.phase = ph
		s.phase_ticks_left = left
		s.phase_changed:Fire(ph, left)
	else
		s.phase_ticks_left = left
	end
end

local CATEGORY = { warn = Defs.MSG_BAD, elim = Defs.MSG_ALERT, big = Defs.MSG_GOOD, info = Defs.MSG_INFO, toast = Defs.MSG_INFO }
-- RoWorld's advisor already announces these from the state's signals (alliances, the war's start,
-- eliminations): our server's copies would show twice
Feed.SKIP = { "formed an alliance", "are no longer allies", "renewed their alliance", "alliance between",
	"The war begins", "Pick your starting land", " collapsed", " eliminated " }
function Feed.message(text: string, kind: string)
	local s = Feed.state
	for _, pat in Feed.SKIP do
		if string.find(text, pat, 1, true) then
			return
		end
	end
	if s then
		s.message:Fire(State.me, CATEGORY[kind] or Defs.MSG_INFO, text)
	end
end

function Feed.gameOver(r: any)
	local s = Feed.state
	if not s then
		return
	end
	s.winner = r.winner or 0
	local reason = tostring(r.reason or ""):lower()
	s.over_reason = if reason:find("time") then Defs.OVER_TIME
		elseif reason:find("abandon") or reason:find("no human") then Defs.OVER_ABANDONED
		else Defs.OVER_DOMINATION
	s.results = r
	s.vote_counts = {} -- (this round's map vote starts at zero; Main fills it from the Vote remote)
	if s.phase ~= Defs.PHASE_OVER then
		s.phase = Defs.PHASE_OVER
		s.phase_changed:Fire(Defs.PHASE_OVER, 0)
	end
	s.game_over:Fire(s.winner, s.over_reason)
end

-- the tiles a delta changed: write them, then fire tiles_changed (tile * 1024 + owner, olds)
local changedBuf, oldBuf = {}, {}
function Feed.tilesChanged(list: { number })
	local s = Feed.state
	if not s or #list == 0 then
		return
	end
	table.clear(changedBuf)
	table.clear(oldBuf)
	local ob = s.owner
	for k, i in list do
		local nw = buffer.readu16(State.owner, i * 2)
		local old = buffer.readi32(ob, i * 4)
		buffer.writei32(ob, i * 4, nw)
		changedBuf[k] = i * 1024 + nw
		oldBuf[k] = old
		if nw ~= 0 then
			Feed.anyTile[nw] = i
		end
	end
	s.tiles_changed:Fire(changedBuf, oldBuf)
end

function Feed.stats()
	local s = Feed.state
	if not s then
		return
	end
	Feed.syncOwners(true)
	s.tick = math.floor(Feed.tick())
	s.stats_changed:Fire()
end

-- a fresh snapshot: a new GameState (a new match as far as RoWorld's UI knows)
function Feed.build(): any
	Feed.epoch = now()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local rs = remotes:GetAttribute("RoundStart")
	if typeof(rs) == "number" and rs > 0 and rs < Feed.epoch then
		Feed.epoch = rs
	end
	local m = buildMap()
	local s = GameState.new(m)
	Feed.state = s
	table.clear(Feed.anyTile)
	s.local_owner = State.me
	s.tick = math.floor(Feed.tick())
	s.render_tick = s.tick
	fillOwners()
	Feed.syncOwners(false)
	Feed.syncStructures(false)
	Feed.syncUnits(false)
	Feed.syncDiplomacy()
	Feed.syncPhase(remotes:GetAttribute("Phase") or "Lobby", remotes:GetAttribute("PhaseEnds") or 0, remotes:GetAttribute("RoundStart"))
	s.loaded = true
	return s
end

-- per frame: the smoothed tick RoWorld's views animate with
function Feed.frame()
	local s = Feed.state
	if s then
		local t = Feed.tick()
		s.render_tick = t
		local whole = math.floor(t)
		if whole ~= s.tick then
			s.tick = whole
			s.ticked:Fire(whole)
		end
	end
end

return Feed
