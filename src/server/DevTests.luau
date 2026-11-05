--!strict
-- Studio-only test hook: game.ServerStorage.DevHook:Invoke(name, arg)
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Sim = require(script.Parent.Sim)
local Match = require(script.Parent.Match)

local DevTests = {}

local tests: { [string]: (any) -> string } = {}

tests.summary = function()
	local lines = {
		("phase=%s round=%d tick=%d seq=%d claimable=%d tickMs=%.2f"):format(Match.phase, Match.roundId, Sim.tick, Sim.seq, Sim.claimable, Match.tickMs),
	}
	for _, n in Sim.nations do
		lines[#lines + 1] = ("%d %s [%s] land=%d (%.1f%%) troops=%d/%d gold=%d alive=%s fronts=%d"):format(
			n.id, n.name, n.kind, n.land, n.land / math.max(Sim.claimable, 1) * 100, n.troops, n.maxTroops, n.gold, tostring(n.alive), #n.attacks)
	end
	return table.concat(lines, "\n")
end

tests.hash = function()
	local h = 0
	for i = 0, Sim.N - 1 do
		h = (h + Sim.ownerAt(i) * (i % 9973 + 1)) % 2147483647
	end
	return ("hash=%d seq=%d"):format(h, Sim.seq)
end

-- replication bytes per second per player since the last call (resets)
tests.net = function()
	local n = math.max(#game:GetService("Players"):GetPlayers(), 1)
	local dt = os.clock() - Match.net.since
	local rate = Match.net.bytes / math.max(dt, 0.001) / n
	Match.net.bytes, Match.net.since = 0, os.clock()
	local Units = require(script.Parent.Units)
	local S = require(script.Parent.Structures)
	local nu, ns = 0, 0
	for _ in Units.list do
		nu += 1
	end
	for _ in S.list do
		ns += 1
	end
	return ("%.0f B/s per player over %.0fs | tickMs avg %.2f | units %d structures %d | server mem %.0f MB"):format(rate, dt, Match.tickMs, nu, ns, game:GetService("Stats"):GetTotalMemoryUsageMb())
end

-- disconnect / AI takeover / rejoin (async; attribute "DC")
tests.disconnect = function()
	local p = game:GetService("Players"):GetPlayers()[1]
	local nid = p and Match._dev.playerNation[p]
	if not nid then
		return "need a player nation"
	end
	ServerStorage:SetAttribute("DC", "running")
	task.spawn(function()
		local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
		local n = Sim.nations[nid]
		local out = {}
		Match._dev.playerRemoving(p)
		out[#out + 1] = ("%s still human during grace (%s)"):format(if n.kind == "human" then "PASS" else "FAIL", n.kind)
		task.wait(Config.Match.ReconnectGrace + 1)
		out[#out + 1] = ("%s AI took over after grace (%s)"):format(if n.kind == "nation" then "PASS" else "FAIL", n.kind)
		local back = Match._dev.rejoin(p)
		out[#out + 1] = ("%s rejoin reclaims nation (%d, kind %s)"):format(if back == nid and n.kind == "human" then "PASS" else "FAIL", back, n.kind)
		ServerStorage:SetAttribute("DC", table.concat(out, " | "))
	end)
	return "started"
end

-- keep rounds running even if every human is eliminated (load tests)
tests.noend = function()
	local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
	Config.Match.EndWhenNoHumans = false
	return "EndWhenNoHumans=false"
end

-- give the first player coins (shop tests)
tests.coins = function(arg)
	local PlayerData = require(script.Parent.PlayerData)
	local p = game:GetService("Players"):GetPlayers()[1]
	local prof = p and PlayerData.get(p)
	if not prof then
		return "no profile"
	end
	prof.coins += tonumber(arg) or 5000
	return "coins=" .. prof.coins
end

-- skip the current phase timer
tests.skip = function()
	if Match.phase == "Playing" then
		return "refused: use win to end a live round"
	end
	Match._dev.setPhaseEnds(0)
	return "skipped " .. Match.phase
end

-- give nation `arg` (default 1) most of the map to test victory
tests.win = function(arg)
	local id = tonumber(arg) or 1
	local need = math.ceil(Sim.claimable * 0.81)
	local c = Sim.nations[id].land
	for i = 0, Sim.N - 1 do
		if c >= need then
			break
		end
		if Sim.isClaimable(i) and Sim.ownerAt(i) ~= id then
			Sim.setOwner(i, id)
			c += 1
		end
	end
	return "nation " .. id .. " land=" .. Sim.nations[id].land
end

-- server-side rejection checks against the real handlers
tests.rejects = function()
	local h = Match._dev.handlers
	local p = game:GetService("Players"):GetPlayers()[1]
	if not p then
		return "need a player"
	end
	local out = {}
	local function check(name: string, kind: string, args: any, wantOk: boolean)
		local ok, msg = h[kind](p, args)
		out[#out + 1] = ("%s %s -> %s %s"):format(if ok == wantOk then "PASS" else "FAIL", name, tostring(ok), tostring(msg))
	end
	check("nan cell", "attack", { cell = 0 / 0, ratio = 0.5 }, false)
	check("huge cell", "attack", { cell = 1e12, ratio = 0.5 }, false)
	check("frac cell", "attack", { cell = 10.5, ratio = 0.5 }, false)
	check("string cell", "attack", { cell = "x", ratio = 0.5 }, false)
	check("bad ratio", "attack", { cell = 100, ratio = "1" }, false)
	-- water cell
	local water
	for i = 0, Sim.N - 1 do
		if not Sim.isClaimable(i) then
			water = i
			break
		end
	end
	check("water", "attack", { cell = water, ratio = 0.5 }, false)
	-- far away land with no border
	local nid = Match._dev.playerNation[p]
	local me = nid and Sim.nations[nid]
	if me then
		local far
		local nb = Sim.neighborOwners(me)
		for _, n in Sim.nations do
			if n.id ~= me.id and n.alive and not nb[n.id] and n.land > 0 then
				far = n
				break
			end
		end
		if far then
			for i = 0, Sim.N - 1 do
				if Sim.ownerAt(i) == far.id then
					check("no border", "attack", { cell = i, ratio = 0.5 }, false)
					break
				end
			end
		end
		-- double submit with the same id is processed once
		local before = me.troops
		local cell
		for i = 0, Sim.N - 1 do
			if Sim.ownerAt(i) == 0 and Sim.isClaimable(i) then
				cell = i
				break
			end
		end
		h.attack(p, { cell = cell, ratio = 0.1, id = "dupe-test" })
		local mid = me.troops
		h.attack(p, { cell = cell, ratio = 0.1, id = "dupe-test" })
		out[#out + 1] = ("%s dedupe (troops %d -> %d -> %d)"):format(if me.troops == mid then "PASS" else "FAIL", before, mid, me.troops)
	end
	return table.concat(out, "\n")
end

-- Fast-forward the live round headless (bots only, humans idle) for up to `arg`
-- minutes. Runs async; result lands in ServerStorage attribute "FF". Clients resync after.
tests.ff = function(arg)
	if Match.phase ~= "Playing" then
		return "need Playing phase"
	end
	local Bots = require(script.Parent.Bots)
	local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
	local keep = typeof(arg) == "string" and arg:sub(-1) == "k" -- "15k": stop at 15 min and keep playing live
	local mins = tonumber(if keep then (arg :: string):sub(1, -2) else arg) or 25
	Match.paused = true
	Match.prof = {}
	Bots.reset() -- think timers were in real server time
	ServerStorage:SetAttribute("FF", "running")
	task.spawn(function()
		local tr = Config.TickRate
		local log = {}
		local fake = 0
		local maxMs = 0
		local done = false
		for t = 1, mins * 60 * tr do
			fake += 1 / tr
			local t0 = os.clock()
			Match.simStep(fake)
			Sim.flushDelta()
			maxMs = math.max(maxMs, (os.clock() - t0) * 1000)
			local top, alive = nil, 0
			for _, n in Sim.nations do
				if n.alive and n.spawned then
					alive += 1
					if not top or n.land > top.land then
						top = n
					end
				end
			end
			local share = if top then top.land / Sim.claimable else 0
			if t % (60 * tr) == 0 or share >= Config.Match.VictoryShare or alive <= 1 then
				log[#log + 1] = ("%dm%02ds top=%s %.1f%% alive=%d"):format(fake // 60, fake % 60, if top then top.name else "-", share * 100, alive)
				if share >= Config.Match.VictoryShare or alive <= 1 then
					done = true
					break
				end
			end
			if t % 50 == 0 then
				task.wait()
			end
		end
		local S = require(script.Parent.Structures)
		local U = require(script.Parent.Units)
		local kinds = {}
		for _, st in S.list do
			kinds[st.kind] = (kinds[st.kind] or 0) + 1
		end
		local ks = {}
		for k, v in kinds do
			ks[#ks + 1] = k .. "=" .. v
		end
		local nu = 0
		for _ in U.list do
			nu += 1
		end
		local pf = {}
		for k, v in Match.prof do
			pf[#pf + 1] = ("%s=%.1f"):format(k, v)
		end
		log[#log + 1] = ("finished=%s maxTickMs=%.2f structures[%s] units=%d prof[%s] sorties=%d"):format(tostring(done), maxMs, table.concat(ks, ","), nu, table.concat(pf, ","), require(script.Parent.Air).sorties)
		ServerStorage:SetAttribute("FF", table.concat(log, " | "))
		Match.paused = false
		if not keep then
			Match._dev.setPhaseEnds(0)
			Match.endRound("fast-forward test", nil)
		end
	end)
	return "started"
end

-- structures: placement rules, dedupe, upgrade -> cap bonus (async; result in attribute "ST")
tests.structures = function()
	local S = require(script.Parent.Structures)
	local h = Match._dev.handlers
	local p = game:GetService("Players"):GetPlayers()[1]
	local nid = p and Match._dev.playerNation[p]
	local me = nid and Sim.nations[nid]
	if not me or Match.phase ~= "Playing" then
		return "need a live player nation"
	end
	ServerStorage:SetAttribute("ST", "running")
	task.spawn(function()
		me.gold = 20000
		local out = {}
		local own, coast
		for i = 0, Sim.N - 1 do
			if Sim.ownerAt(i) == me.id then
				own = own or i
				if Sim.isCoastal(i) then
					coast = i
				end
			end
		end
		local function r(name, want, ok, msg)
			out[#out + 1] = ("%s %s -> %s %s"):format(if ok == want then "PASS" else "FAIL", name, tostring(ok), tostring(msg))
		end
		r("city", true, h.build(p, { kind = "city", cell = own, id = "b1" }))
		local g = me.gold
		h.build(p, { kind = "city", cell = own, id = "b1" })
		out[#out + 1] = (if me.gold == g then "PASS" else "FAIL") .. " dup id charged once"
		r("too close", false, h.build(p, { kind = "defense", cell = own, id = "b2" }))
		r("water", false, h.build(p, { kind = "city", cell = 0, id = "b3" }))
		r("bad kind", false, h.build(p, { kind = "nope", cell = own, id = "b4" }))
		r("nan cell", false, h.build(p, { kind = "city", cell = 0 / 0, id = "b6" }))
		if coast then
			r("port on coast", true, h.build(p, { kind = "port", cell = coast, id = "b5" }))
		else
			out[#out + 1] = "SKIP port (no coastal land)"
		end
		local cap0 = me.capBonus
		task.wait(7)
		local cap1 = me.capBonus
		local sid
		for id, st in S.list do
			if st.owner == me.id and st.kind == "city" then
				sid = id
			end
		end
		r("upgrade", true, h.upgrade(p, { structure = sid, id = "u1" }))
		task.wait(7)
		out[#out + 1] = ("%s cap bonus %d -> %d -> %d"):format(if cap1 > cap0 and me.capBonus > cap1 then "PASS" else "FAIL", cap0, cap1, me.capBonus)
		-- capture transfers a city to the capturer
		local other
		for _, n in Sim.nations do
			if n.id ~= me.id and n.alive and n.kind == "nation" then
				other = n
				break
			end
		end
		local st = S.list[sid]
		Sim.setOwner(st.cell, other.id)
		out[#out + 1] = ("%s capture transfers city (owner %d, want %d)"):format(if st.owner == other.id then "PASS" else "FAIL", st.owner, other.id)
		local kinds = {}
		for _, s2 in S.list do
			kinds[#kinds + 1] = s2.kind
		end
		out[#out + 1] = "total structures " .. #kinds
		ServerStorage:SetAttribute("ST", table.concat(out, " | "))
	end)
	return "started"
end

-- trade: train delivery, interruption, port-to-port ships (async; result in attribute "TR")
tests.trade = function()
	local S = require(script.Parent.Structures)
	local Units = require(script.Parent.Units)
	if Match.phase ~= "Playing" then
		return "need Playing"
	end
	ServerStorage:SetAttribute("TR", "running")
	task.spawn(function()
		local out = {}
		local W = Sim.W
		-- biggest AI nation hosts the rail test
		local host
		for _, n in Sim.nations do
			if n.alive and n.kind == "nation" and (not host or n.land > host.land) then
				host = n
			end
		end
		local function placeFar(n, kind, from, minD)
			for _ = 1, 4000 do
				local x, y = Sim.rng():NextInteger(n.minX, n.maxX), Sim.rng():NextInteger(n.minY, n.maxY)
				local c = y * W + x
				if Sim.ownerAt(c) == n.id and (not from or math.max(math.abs(x - from % W), math.abs(y - from // W)) >= minD) then
					n.gold = 1e6
					local ok = S.build(n.id, kind, c)
					if ok then
						local st = S.list[S.byCell[c]]
						st.readyTick = Sim.tick
						return st
					end
				end
			end
			return nil
		end
		local f = placeFar(host, "factory", nil, 0)
		local city = f and placeFar(host, "city", f.cell, 12)
		out[#out + 1] = ("host %s land=%d factory=%s city=%s"):format(host.name, host.land, tostring(f ~= nil), tostring(city ~= nil))
		local trade0 = host.income.trade
		local sawTrain = false
		for _ = 1, 40 do
			task.wait(1)
			for _, u in Units.list do
				if u.kind == "train" and u.owner == host.id then
					sawTrain = true
				end
			end
			if host.income.trade > trade0 then
				break
			end
		end
		out[#out + 1] = ("%s train delivered (trade %d -> %d, sawTrain=%s)"):format(if host.income.trade > trade0 then "PASS" else "FAIL", trade0, host.income.trade, tostring(sawTrain))
		-- interruption: hand the cell in front of the next train to someone else
		local cut = false
		for _ = 1, 30 do
			task.wait(0.5)
			for _, u in Units.list do
				if u.kind == "train" and u.owner == host.id and #u.path - math.floor(u.pos) > 4 then
					local c = u.path[math.floor(u.pos) + 3]
					local other = if host.id == 2 then 3 else 2
					Sim.setOwner(c, other)
					cut = true
					break
				end
			end
			if cut then
				break
			end
		end
		local gone = false
		task.wait(1.5)
		out[#out + 1] = (if cut then "PASS" else "SKIP") .. " cut a track cell under a moving train (feed shows interruption)"
		-- ports: two different nations with coast
		local ports = {}
		for _, n in Sim.nations do
			if #ports >= 2 then
				break
			end
			if n.alive and n.kind == "nation" then
				for _ = 1, 3000 do
					local x, y = Sim.rng():NextInteger(n.minX, n.maxX), Sim.rng():NextInteger(n.minY, n.maxY)
					local c = y * W + x
					if Sim.ownerAt(c) == n.id and Sim.isCoastal(c) then
						n.gold = 1e6
						local ok = S.build(n.id, "port", c)
						if ok then
							S.list[S.byCell[c]].readyTick = Sim.tick
							ports[#ports + 1] = n
							break
						end
					end
				end
			end
		end
		local ship = false
		for _ = 1, 45 do
			task.wait(1)
			for _, u in Units.list do
				if u.kind == "trade" then
					ship = true
				end
			end
			if ship then
				break
			end
		end
		out[#out + 1] = ("%s trade ship launched (%d ports built)"):format(if ship then "PASS" else "FAIL", #ports)
		local _ = gone
		ServerStorage:SetAttribute("TR", table.concat(out, " | "))
	end)
	return "started"
end

tests.ports = function()
	local S = require(script.Parent.Structures)
	local Path = require(script.Parent.Path)
	local out = {}
	local ports = {}
	for _, st in S.list do
		if st.kind == "port" then
			ports[#ports + 1] = st
		end
	end
	for _, a in ports do
		local wa = Path.waterBeside(a.cell)
		out[#out + 1] = ("port %d owner %d done=%s water=%s body=%s"):format(a.id, a.owner, tostring(a.done), tostring(wa), tostring(wa and buffer.readu32(Sim.water, wa * 4)))
	end
	if #ports >= 2 then
		local wa, wb = Path.waterBeside(ports[1].cell), Path.waterBeside(ports[2].cell)
		if wa and wb then
			local t0 = os.clock()
			local p = Path.find(wa, wb, function(j)
				return Sim.terrAt(j) == 0
			end, 200000, 3)
			out[#out + 1] = ("path len=%s in %.1f ms"):format(tostring(p and #p), (os.clock() - t0) * 1000)
		end
	end
	return table.concat(out, " | ")
end

-- naval: boat landing across water, warship interception (async; attribute "NV")
tests.naval = function()
	local Units = require(script.Parent.Units)
	local Naval = require(script.Parent.Naval)
	local S = require(script.Parent.Structures)
	local Path = require(script.Parent.Path)
	if Match.phase ~= "Playing" then
		return "need Playing"
	end
	ServerStorage:SetAttribute("NV", "running")
	task.spawn(function()
		local out = {}
		local W = Sim.W
		-- attacker: an AI nation with ocean coast; target: coastal land of another nation 15-60 cells away
		local att, tgt
		for _, n in Sim.nations do
			if att then
				break
			end
			if n.alive and n.kind == "nation" then
				for y = n.minY, n.maxY do
					for x = n.minX, n.maxX do
						local c = y * W + x
						if not att and Sim.ownerAt(c) == n.id and Sim.isCoastal(c) then
							for _ = 1, 400 do
								local tx = math.clamp(x + Sim.rng():NextInteger(-60, 60), 0, W - 1)
								local ty = math.clamp(y + Sim.rng():NextInteger(-60, 60), 0, Sim.H - 1)
								local tc = ty * W + tx
								local d = math.max(math.abs(tx - x), math.abs(ty - y))
								if d >= 15 and Sim.isClaimable(tc) and Sim.isCoastal(tc) and Sim.ownerAt(tc) ~= n.id then
									local wa, wb = Path.waterBeside(c), Path.waterBeside(tc)
									if wa and wb and buffer.readu32(Sim.water, wa * 4) == buffer.readu32(Sim.water, wb * 4) then
										att, tgt = n, tc
										break
									end
								end
							end
						end
					end
				end
			end
		end
		if not att then
			ServerStorage:SetAttribute("NV", "SKIP no coastal pair")
			return
		end
		att.troops = math.max(att.troops, 8000)
		local enemy
		for _, n in Sim.nations do
			if n.alive and n.id ~= att.id and n.kind == "nation" then
				enemy = n
				break
			end
		end
		-- 1) interception: hostile warship parked mid-route
		local ok1, msg1 = Naval.sendBoat(att.id, tgt, 2000)
		local boat1
		for _, u in Units.list do
			if u.kind == "transport" and u.owner == att.id and not u.dead then
				boat1 = u
			end
		end
		out[#out + 1] = ("%s boat launched (%s, route %d)"):format(if ok1 then "PASS" else "FAIL", msg1, if boat1 then #boat1.path else 0)
		if boat1 and #boat1.path > 12 then
			local mid = boat1.path[math.floor(#boat1.path / 2)]
			local ws = Units.spawn("warship", enemy.id, { mid }, 4, { port = -1, anchor = mid, nextPatrol = Sim.tick + 600, cooldown = 0 }, 100)
			for _ = 1, 80 do
				task.wait(0.25)
				if boat1.dead then
					break
				end
			end
			out[#out + 1] = ("%s warship intercepted transport mid-sea (dead=%s at %d/%d)"):format(if boat1.dead and boat1.pos < #boat1.path then "PASS" else "FAIL", tostring(boat1.dead), math.floor(boat1.pos), #boat1.path)
			Units.remove(ws, "test")
		else
			out[#out + 1] = "SKIP interception (route too short)"
		end
		-- 2) unopposed landing
		local before = Sim.ownerAt(tgt)
		local ok2, msg2 = Naval.sendBoat(att.id, tgt, 3000)
		local boat
		for _, u in Units.list do
			if u.kind == "transport" and u.owner == att.id and not u.dead then
				boat = u
			end
		end
		for _ = 1, 80 do
			task.wait(0.5)
			if Sim.ownerAt(tgt) == att.id or (boat and boat.dead) then
				break
			end
		end
		out[#out + 1] = ("%s landing (%s; cell owner %d -> %d)"):format(if Sim.ownerAt(tgt) == att.id then "PASS" else "FAIL", tostring(msg2), before, Sim.ownerAt(tgt))
		local _ = ok2
		local _ = S
		ServerStorage:SetAttribute("NV", table.concat(out, " | "))
	end)
	return "started"
end

-- diplomacy: request/accept, no attacks between allies, betrayal grace (async; attribute "DP")
tests.diplomacy = function()
	local D = require(script.Parent.Diplomacy)
	local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
	if Match.phase ~= "Playing" then
		return "need Playing"
	end
	ServerStorage:SetAttribute("DP", "running")
	task.spawn(function()
		local out = {}
		local function r(name, want, ok, msg)
			out[#out + 1] = ("%s %s -> %s %s"):format(if ok == want then "PASS" else "FAIL", name, tostring(ok), tostring(msg))
		end
		-- two AI nations that border each other
		local a, b
		for _, n in Sim.nations do
			if n.alive and n.kind == "nation" and not a then
				for oid in Sim.neighborOwners(n) do
					local o = Sim.nations[oid]
					if o and o.kind == "nation" and o.alive then
						a, b = n, o
						break
					end
				end
			end
		end
		if not a then
			ServerStorage:SetAttribute("DP", "SKIP no bordering AI pair yet")
			return
		end
		a.troops = math.max(a.troops, b.troops * 2) -- so the AI accepts
		D.reset()
		r("request (AI accepts)", true, D.request(a.id, b.id))
		r("allied", true, D.allied(a.id, b.id))
		r("attack ally blocked", false, Sim.startAttack(a.id, b.id, 100))
		r("request while allied renews (5 min)", true, D.request(a.id, b.id))
		r("break", true, D.breakWith(a.id, b.id))
		r("still allied in grace", true, D.allied(a.id, b.id))
		task.wait(Config.Diplomacy.BreakGrace + 0.6)
		r("rivals after grace", false, D.allied(a.id, b.id))
		r("tribe refuses", false, (function()
			for _, n in Sim.nations do
				if n.kind == "tribe" and n.alive then
					return D.request(a.id, n.id)
				end
			end
			return false, "no tribe"
		end)())
		ServerStorage:SetAttribute("DP", table.concat(out, " | "))
	end)
	return "started"
end

-- force an alliance between the first player and AI nation `arg` (visual checks)
tests.allyme = function(arg)
	local D = require(script.Parent.Diplomacy)
	local p = game:GetService("Players"):GetPlayers()[1]
	local nid = p and Match._dev.playerNation[p]
	local me = nid and Sim.nations[nid]
	local other = Sim.nations[tonumber(arg) or 0]
	if not other and me then
		local bd = math.huge
		for _, n in Sim.nations do
			if n.kind == "nation" and n.alive then
				local d = (n.spawnX - me.spawnX) ^ 2 + (n.spawnY - me.spawnY) ^ 2
				if d < bd then
					other, bd = n, d
				end
			end
		end
	end
	if not me or not other then
		return "no nations"
	end
	me.troops = math.max(me.troops, other.troops * 2)
	return select(2, D.request(me.id, other.id))
end

-- nukes: launch, impact clears land, SAM intercepts (async; attribute "NK")
tests.nukes = function()
	local S = require(script.Parent.Structures)
	local Nukes = require(script.Parent.Nukes)
	local Units = require(script.Parent.Units)
	local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
	if Match.phase ~= "Playing" then
		return "need Playing"
	end
	ServerStorage:SetAttribute("NK", "running")
	task.spawn(function()
		local out = {}
		local W = Sim.W
		local list = {}
		for _, n in Sim.nations do
			if n.alive and n.kind == "nation" then
				list[#list + 1] = n
			end
		end
		table.sort(list, function(a, b)
			return a.land > b.land
		end)
		local att, vic, vic2 = list[1], list[2], list[3]
		local function place(n, kind)
			for _ = 1, 3000 do
				local x, y = Sim.rng():NextInteger(n.minX, n.maxX), Sim.rng():NextInteger(n.minY, n.maxY)
				local c = y * W + x
				if Sim.ownerAt(c) == n.id then
					n.gold = math.max(n.gold, 1e5)
					if S.build(n.id, kind, c) then
						local st = S.list[S.byCell[c]]
						st.readyTick = Sim.tick
						return st
					end
				end
			end
			return nil
		end
		local silo = place(att, "silo")
		task.wait(0.3)
		-- 1) unprotected target
		local tc = vic.spawnY * W + vic.spawnX -- the heartland
		local R = Config.Nuke.Radius
		local function inBlast()
			local c = 0
			for y = -R, R do
				for x = -R, R do
					local i = tc + y * W + x
					if x * x + y * y <= R * R and i >= 0 and i < Sim.N and Sim.ownerAt(i) == vic.id then
						c += 1
					end
				end
			end
			return c
		end
		local land0 = inBlast()
		att.gold = 1e5
		local ok, msg = Nukes.launch(att.id, silo.id, tc)
		out[#out + 1] = ("%s launch -> %s"):format(if ok then "PASS" else "FAIL", msg)
		local ok2, msg2 = Nukes.launch(att.id, silo.id, tc)
		out[#out + 1] = ("%s no silo reload: 2nd launch fires at once -> %s"):format(if ok2 then "PASS" else "FAIL", msg2)
		local miss
		for _, u in Units.list do
			if u.kind == "missile" and u.owner == att.id then
				miss = u
			end
		end
		for _ = 1, 240 do -- long flights on the world map
			task.wait(0.25)
			if not miss or miss.dead then
				break
			end
		end
		local land1b = inBlast()
		out[#out + 1] = ("%s impact cleared land (%s cells in blast %d -> %d)"):format(if land1b < land0 * 0.6 then "PASS" else "FAIL", vic.name, land0, land1b)
		-- 2) SAM-protected target
		local sam = place(vic2, "sam")
		task.wait(0.3)
		local tc2 = sam and sam.cell
		local silo2 = place(att, "silo")
		task.wait(0.3)
		att.gold = 1e5
		local land1 = vic2.land
		local ok3, msg3 = Nukes.launch(att.id, silo2.id, tc2)
		local miss2
		for _, u in Units.list do
			if u.kind == "missile" and u.owner == att.id and not u.dead then
				miss2 = u
			end
		end
		for _ = 1, 80 do
			task.wait(0.25)
			if not miss2 or miss2.dead then
				break
			end
		end
		out[#out + 1] = ("%s SAM intercepted (%s, land %d -> %d, sam alive=%s)"):format(if ok3 and vic2.land >= land1 - 2 and S.list[sam.id] ~= nil then "PASS" else "FAIL", tostring(msg3), land1, vic2.land, tostring(S.list[sam.id] ~= nil))
		ServerStorage:SetAttribute("NK", table.concat(out, " | "))
	end)
	return "started"
end

-- air: bomber front strike + ground follow-up, fighter intercept, escort, AA, captured airfield
tests.air = function()
	local S = require(script.Parent.Structures)
	local Air = require(script.Parent.Air)
	local Units = require(script.Parent.Units)
	local Path = require(script.Parent.Path)
	local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
	if Match.phase ~= "Playing" then
		return "need Playing"
	end
	ServerStorage:SetAttribute("AIR", "running")
	task.spawn(function()
		local out = {}
		local W = Sim.W
		local function r(name, ok, extra)
			out[#out + 1] = ("%s %s %s"):format(if ok then "PASS" else "FAIL", name, extra or "")
		end
		-- attacker A and defender B sharing a border
		local a, b
		for _, n in Sim.nations do
			if not a and n.alive and n.kind == "nation" and n.land > 150 then
				for oid in Sim.neighborOwners(n) do
					local o = Sim.nations[oid]
					if o and o.kind == "nation" and o.alive and o.land > 150 then
						a, b = n, o
						break
					end
				end
			end
		end
		if not a then
			ServerStorage:SetAttribute("AIR", "SKIP no bordering pair")
			return
		end
		local Bots = require(script.Parent.Bots)
		Bots.frozen[a.id], Bots.frozen[b.id] = true, true
		local function place(n, kind, near, maxD)
			for _ = 1, 5000 do
				local x, y = Sim.rng():NextInteger(n.minX, n.maxX), Sim.rng():NextInteger(n.minY, n.maxY)
				local c = y * W + x
				if Sim.ownerAt(c) == n.id and (not near or math.max(math.abs(x - near % W), math.abs(y - near // W)) <= maxD) then
					n.gold = 1e6
					if not S.whyNot(n.id, kind, c) and S.build(n.id, kind, c) then
						local st = S.list[S.byCell[c]]
						st.readyTick = Sim.tick
						return st
					end
				end
			end
			return nil
		end
		-- a front cell of B next to A
		local front
		for y = b.minY, b.maxY do
			for x = b.minX, b.maxX do
				local c = y * W + x
				if not front and Sim.ownerAt(c) == b.id then
					for _, j in { c - 1, c + 1, c - W, c + W } do
						if j >= 0 and j < Sim.N and Sim.ownerAt(j) == a.id then
							front = c
						end
					end
				end
			end
		end
		front = front or (b.spawnY * W + b.spawnX)
		place(a, "factory")
		local af1 = place(a, "airfield", front, 30)
		local af2 = place(a, "airfield", front, 40)
		task.wait(0.3)
		a.gold = 1e6
		-- record air events for this test
		local events = {}
		local prevEv = Air.onEvent
		Air.onEvent = function(k, i)
			table.insert(events, { k, i })
			if prevEv then
				prevEv(k, i)
			end
		end
		local function saw(kind)
			for _, e in events do
				if e[1] == kind then
					return e[2]
				end
			end
			return nil
		end
		-- 1) front strike + suppression window + ground follow-up
		local t0 = b.troops
		local ok, msg = Air.launch(a.id, af1.id, "strike", front)
		r("bomber launch", ok, msg)
		local zone = false
		for _ = 1, 60 do
			task.wait(0.25)
			if #Air.zones > 0 then
				zone = true
				break
			end
		end
		local hit = saw("bombed")
		r("front strike hit", zone and hit ~= nil, ("defender lost %s troops (from %d)"):format(tostring(hit and hit.loss), t0))
		r("ground-attack window", Air.suppressMult(front, b.id) < 1, ("defense mult %.2f"):format(Air.suppressMult(front, b.id)))
		local function bNear()
			local c = 0
			for dy = -8, 8 do
				for dx = -8, 8 do
					local i = front + dy * W + dx
					if i >= 0 and i < Sim.N and Sim.ownerAt(i) == b.id then
						c += 1
					end
				end
			end
			return c
		end
		local land0 = bNear()
		a.troops = math.max(a.troops, 6000)
		local okA = Sim.startAttack(a.id, b.id, 4000)
		task.wait(4)
		r("ground follow-up captures near the strike", okA and bNear() < land0, ("B cells near front %d -> %d"):format(land0, bNear()))
		-- 2) defender fighter intercepts a lone bomber
		local bf = place(b, "airfield", front, 40)
		task.wait(0.3)
		local target2 = front
		if Sim.ownerAt(target2) ~= b.id then
			for y = b.minY, b.maxY do
				for x = b.minX, b.maxX do
					local c = y * W + x
					if Sim.ownerAt(c) == b.id and Air.bomberPayload(a.id, c) and math.sqrt((x - af2.cell % W) ^ 2 + (y - af2.cell // W) ^ 2) < 40 then
						target2 = c
					end
				end
			end
		end
		local route = Path.line(af2.cell, target2)
		local mid = route[math.max(1, math.floor(#route * 0.55))]
		local okc, mc = Air.launch(b.id, bf.id, "cap", mid)
		task.wait(math.max(1, #Path.line(bf.cell, mid) / Config.Air.FighterSpeed) + 0.3)
		a.gold = 1e6
		local ok2, m2 = Air.launch(a.id, af2.id, "strike", target2)
		local bomber
		for _, u in Units.list do
			if u.kind == "bomber" and u.owner == a.id and u.data.airfield == af2.id then
				bomber = u
			end
		end
		for _ = 1, 80 do
			task.wait(0.25)
			if not bomber or bomber.dead or bomber.data.state ~= "out" then
				break
			end
		end
		r("fighter intercepts bomber", ok2 and okc and bomber and bomber.dead and bomber.data.state == "out", ("cap=%s strike=%s route=%d"):format(tostring(mc), tostring(m2), #route))
		-- 3) captured airfield: bomber in flight loses its home
		for _ = 1, 80 do
			task.wait(0.5)
			if Air.sortiesFrom(af1.id) == 0 and Air.turnaroundLeft(af1.id) <= 0 then
				break
			end
		end
		a.gold = 1e6
		local ok3, m3 = Air.launch(a.id, af1.id, "strike", target2)
		local b3
		for _, u in Units.list do
			if u.kind == "bomber" and u.owner == a.id and u.data.airfield == af1.id then
				b3 = u
			end
		end
		Sim.setOwner(af1.cell, b.id) -- airfield transfers to B
		for _ = 1, 120 do
			task.wait(0.25)
			if not b3 or b3.dead then
				break
			end
		end
		r("captured home airfield handled", ok3 and b3 and b3.dead, ("%s; home now owned by %d, diverted to %s, lost=%s"):format(tostring(m3), S.list[af1.id] and S.list[af1.id].owner or -1, tostring(b3 and b3.data.airfield), tostring(saw("lost") ~= nil)))
		Air.onEvent = prevEv
		Bots.frozen[a.id], Bots.frozen[b.id] = nil, nil
		ServerStorage:SetAttribute("AIR", table.concat(out, " | "))
	end)
	return "started"
end

-- air2: AA engages a bomber; an escort beats a patrol so the strike lands (attribute "AIR2")
tests.air2 = function()
	local S = require(script.Parent.Structures)
	local Air = require(script.Parent.Air)
	local Units = require(script.Parent.Units)
	local Path = require(script.Parent.Path)
	local Bots = require(script.Parent.Bots)
	local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
	if Match.phase ~= "Playing" then
		return "need Playing"
	end
	ServerStorage:SetAttribute("AIR2", "running")
	task.spawn(function()
		local out = {}
		local W = Sim.W
		local function r(name, ok, extra)
			out[#out + 1] = ("%s %s %s"):format(if ok then "PASS" else "FAIL", name, extra or "")
		end
		local a, b, front
		for _, n in Sim.nations do
			if not a and n.alive and n.kind == "nation" and n.land > 150 then
				for y = n.minY, n.maxY do
					for x = n.minX, n.maxX do
						local c = y * W + x
						if not a and Sim.ownerAt(c) == n.id then
							for _, j in { c - 1, c + 1, c - W, c + W } do
								local o = j >= 0 and j < Sim.N and Sim.nations[Sim.ownerAt(j)]
								if not a and o and o.kind == "nation" and o.id ~= n.id and o.alive and o.land > 150 then
									a, b, front = o, n, c -- a attacks b at c
								end
							end
						end
					end
				end
			end
		end
		if not a then
			ServerStorage:SetAttribute("AIR2", "SKIP no pair")
			return
		end
		Bots.frozen[a.id], Bots.frozen[b.id] = true, true
		local events = {}
		local prevEv = Air.onEvent
		Air.onEvent = function(k, i)
			table.insert(events, { k, i })
			if prevEv then
				prevEv(k, i)
			end
		end
		local function count(kind)
			local c = 0
			for _, e in events do
				if e[1] == kind then
					c += 1
				end
			end
			return c
		end
		local function place(n, kind, near, minD, maxD)
			for _ = 1, 6000 do
				local x, y = Sim.rng():NextInteger(n.minX, n.maxX), Sim.rng():NextInteger(n.minY, n.maxY)
				local c = y * W + x
				local d = if near then math.max(math.abs(x - near % W), math.abs(y - near // W)) else 0
				if Sim.ownerAt(c) == n.id and d >= (minD or 0) and d <= (maxD or 999) then
					n.gold = 1e6
					if not S.whyNot(n.id, kind, c) and S.build(n.id, kind, c) then
						local st = S.list[S.byCell[c]]
						st.readyTick = Sim.tick
						return st
					end
				end
			end
			return nil
		end
		place(a, "factory")
		local af1 = place(a, "airfield", front, 8, 30)
		local af2 = place(a, "airfield", front, 8, 40)
		-- AA right next to the target
		local aa = place(b, "aa", front, 0, 3)
		task.wait(0.3)
		a.gold = 1e6
		local ok1, m1 = Air.launch(a.id, af1.id, "strike", front)
		for _ = 1, 60 do
			task.wait(0.25)
			if count("aa") > 0 and Air.sortiesFrom(af1.id) == 0 then
				break
			end
		end
		r("AA engaged the bomber", ok1 and count("aa") > 0, ("%s; aa shots=%d (hits reported to both sides) shotdown=%d aa=%s"):format(tostring(m1), count("aa"), count("shotdown"), tostring(aa ~= nil)))
		-- escort vs patrol: B patrols mid-route; escorted bomber still delivers
		if aa then
			S.remove(aa)
		end
		local bf = place(b, "airfield", front, 6, 40)
		task.wait(0.3)
		local route = Path.line(af1.cell, front)
		local mid = route[math.max(1, math.floor(#route * 0.75))]
		local okc = bf and Air.launch(b.id, bf.id, "cap", mid)
		task.wait(1.5)
		for _ = 1, 60 do
			task.wait(0.5)
			if Air.sortiesFrom(af1.id) == 0 and Air.turnaroundLeft(af1.id) <= 0 then
				break
			end
		end
		events = {}
		a.gold = 1e6
		local ok2, m2 = Air.launch(a.id, af1.id, "strike", front, true)
		for _ = 1, 80 do
			task.wait(0.25)
			if count("bombed") + count("struck") > 0 or count("aborted") > 0 then
				break
			end
		end
		r("escorted bomber delivers through a patrol", ok2 and count("bombed") + count("struck") > 0,
			("%s; patrol=%s shotdown=%d"):format(tostring(m2), tostring(okc), count("shotdown")))
		Air.onEvent = prevEv
		Bots.frozen[a.id], Bots.frozen[b.id] = nil, nil
		ServerStorage:SetAttribute("AIR2", table.concat(out, " | "))
	end)
	return "started"
end

-- give the first player a factory + airfield (done) and gold; returns "airfieldId,frontCell"
tests.airkit = function()
	local S = require(script.Parent.Structures)
	local p = game:GetService("Players"):GetPlayers()[1]
	local nid = p and Match._dev.playerNation[p]
	local me = nid and Sim.nations[nid]
	if not me then
		return "no player nation"
	end
	me.gold = 1e5
	local W = Sim.W
	Sim.claimFootprint(me, me.spawnX, me.spawnY, 14) -- room for two buildings
	local af, front
	for _, kind in { "factory", "airfield" } do
		for _ = 1, 4000 do
			local x, y = Sim.rng():NextInteger(me.minX, me.maxX), Sim.rng():NextInteger(me.minY, me.maxY)
			local c = y * W + x
			if Sim.ownerAt(c) == me.id and not S.whyNot(me.id, kind, c) and S.build(me.id, kind, c) then
				local st = S.list[S.byCell[c]]
				st.readyTick = Sim.tick
				if kind == "airfield" then
					af = st
				end
				break
			end
		end
	end
	local Air = require(script.Parent.Air)
	if af then
		local ax, ay = af.cell % W, af.cell // W
		for rr = 3, 40 do
			for y = ay - rr, ay + rr do
				for x = ax - rr, ax + rr do
					local c = y * W + x
					if not front and x >= 0 and y >= 0 and x < W and y < Sim.H and (x - ax) ^ 2 + (y - ay) ^ 2 <= rr * rr then
						if Air.bomberPayload(me.id, c) then
							front = c
						end
					end
				end
			end
			if front then
				break
			end
		end
	end
	return ("%s,%s"):format(tostring(af and af.id), tostring(front))
end

-- tutorial drill end-to-end through the real handler (attribute "DR")
tests.drill = function()
	local Units = require(script.Parent.Units)
	local p = game:GetService("Players"):GetPlayers()[1]
	if not p then
		return "need a player"
	end
	ServerStorage:SetAttribute("DR", "running")
	task.spawn(function()
		local h = Match._dev.handlers
		local out = {}
		local ok, msg = h.drill(p, { action = "start" })
		out[#out + 1] = ("%s start -> %s"):format(if ok then "PASS" else "FAIL", tostring(msg))
		local drone
		for _, u in Units.list do
			if u.kind == "bomber" and u.data.drill then
				drone = u
			end
		end
		local dn = Sim.nations[Match.drillNation]
		out[#out + 1] = ("%s drill nation holds no land (land=%d spawned=%s)"):format(if dn.land == 0 and not dn.spawned then "PASS" else "FAIL", dn.land, tostring(dn.spawned))
		if drone then
			-- patrol ahead of the drone on its route
			local ahead = drone.path[math.min(#drone.path, math.floor(drone.pos) + 12)]
			local ok2, m2 = h.drill(p, { action = "patrol", cell = ahead })
			out[#out + 1] = ("%s patrol -> %s"):format(if ok2 then "PASS" else "FAIL", tostring(m2))
			for _ = 1, 60 do
				task.wait(0.5)
				if drone.dead then
					break
				end
			end
			out[#out + 1] = ("%s drone intercepted before reaching land (dead=%s pos %d/%d)"):format(if drone.dead and drone.pos < #drone.path then "PASS" else "FAIL", tostring(drone.dead), math.floor(drone.pos), #drone.path)
		end
		ServerStorage:SetAttribute("DR", table.concat(out, " | "))
	end)
	return "started"
end

function DevTests.init()
	if not RunService:IsStudio() then
		return
	end
	local f = Instance.new("BindableFunction")
	f.Name = "DevHook"
	f.OnInvoke = function(name: string, arg: any)
		local t = tests[name]
		if not t then
			return "unknown test"
		end
		local ok, res = pcall(t, arg)
		return if ok then res else ("error: " .. tostring(res))
	end
	f.Parent = ServerStorage
end

return DevTests
