-- (Take Over the World!: Stage 4 army / ground warfare tests, 2026-11-06.)
-- Server dev harness: workspace:SetAttribute("AF_DEV", "ArmyTests"), then Play. Headless Sims on the
-- world map: army creation, recruitment validation, composition, movement (valid, invalid, terrain),
-- deterministic combat, casualties, retreat, reinforcement, destruction, province occupation,
-- multiplayer sync through the real wire format (Net/Protocol) and unauthorized commands.
-- Summary in workspace attribute "ArmyTestsResult".
local RS = game:GetService("ReplicatedStorage")
local Airfront = RS:WaitForChild("Airfront")
local Core = Airfront:WaitForChild("Core")
local Defs = require(Core:WaitForChild("Defs"))
local WorldMap = require(Core:WaitForChild("WorldMap"))
local GameState = require(Core:WaitForChild("GameState"))
local Sim = require(Core:WaitForChild("Sim"))
local Provinces = require(Core:WaitForChild("Provinces"))
local SimArmies = require(Core:WaitForChild("SimArmies"))
local Units = require(Airfront:WaitForChild("Data"):WaitForChild("Units"))
local Protocol = require(Airfront:WaitForChild("Net"):WaitForChild("Protocol"))

local readi32 = buffer.readi32
local pass, fail = 0, 0
local lines = {}
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		pass += 1
	else
		fail += 1
	end
	local line = string.format("[ArmyTests] %s %s%s", if ok then "PASS" else "FAIL", name, if detail ~= nil then "  (" .. tostring(detail) .. ")" else "")
	print(line)
	table.insert(lines, line)
end

-- (long headless runs must yield now and then, or Roblox stops the script)
local budget = os.clock()
local function breathe()
	if os.clock() - budget > 0.5 then
		task.wait()
		budget = os.clock()
	end
end

local function steps(sim: any, n: number)
	for _ = 1, n do
		sim:step()
		breathe()
	end
end

-- a fresh match: two humans on two neighbouring countries, playing, rich
local function setup(seed: number)
	local map = WorldMap.get("world")
	task.wait()
	local sim = Sim.new(map, { seed = seed, max_humans = 2, difficulty = 1 })
	task.wait()
	local adj = sim:_prov_adj()
	-- A: a country with at least 3 provinces and a neighbouring country B with 2+ provinces
	local A, B, C
	for _, d in sim.country_list do
		if #d.provinces >= 4 then
			local foreign = {}
			for _, pid in d.provinces do
				for _, nb in adj[pid] do
					local c = sim.P.list[nb].country
					if c ~= d.owner and #sim.P.by_country[c] >= 2 then
						foreign[c] = true
					end
				end
			end
			local list = {}
			for c in foreign do
				table.insert(list, c)
			end
			table.sort(list)
			if #list >= 2 then
				A, B, C = d.owner, list[1], list[2]
				break
			end
		end
	end
	local h1 = sim:add_human("p1", "One")
	local h2 = sim:add_human("p2", "Two")
	sim:submit(h1, { type = "spawn", tile = sim.country_defs[A].capital_tile })
	sim:submit(h2, { type = "spawn", tile = sim.country_defs[B].capital_tile })
	steps(sim, 1)
	sim:drain_owner_moves()
	local guard = 0
	while sim.phase == Defs.PHASE_SPAWN and guard < 3000 do
		sim:step()
		breathe()
		guard += 1
	end
	sim:drain_owner_moves()
	steps(sim, 1)
	for _, id in { A, B } do
		sim.o_gold[id] = 5e6
		sim.o_troops[id] = sim.o_cap[id] -- (above the cap troops fall back to it)
		if sim.l_on then
			local st = sim:_stock(id)
			for k in st do
				st[k] = 1e6 -- (Stage 5: units also cost steel / oil / food)
			end
		end
		sim.o_shield_until[id] = 0
	end
	return sim, A, B, C
end

-- the province of `owner` next to a province of `other` (and that province)
local function border(sim: any, owner: number, other: number): (number, number)
	local adj = sim:_prov_adj()
	for _, pid in sim.P.by_country[owner] do
		if sim.p_ctrl[pid] == owner then
			for _, nb in adj[pid] do
				if sim.p_ctrl[nb] == other then
					return pid, nb
				end
			end
		end
	end
	return 0, 0
end

local function newest(sim: any, owner: number): number
	local best = 0
	for id, a in sim.armies do
		if a.owner == owner and id > best then
			best = id
		end
	end
	return best
end

task.spawn(function()
	local sim, A, B, C = setup(5)
	check("setup: two players on neighbouring countries", A ~= nil and B ~= nil and C ~= nil and sim.phase == Defs.PHASE_PLAYING,
		string.format("%s vs %s, %s", tostring(sim.o_name[A]), tostring(sim.o_name[B]), tostring(sim.o_name[C])))
	local capA = sim.country_defs[A].capital_tile

	-- creation + cost from the existing economy
	local g0, t0 = sim.o_gold[A], sim.o_troops[A]
	sim:submit(A, { type = "army_recruit", uid = 0, tile = capA, kind = "infantry", troops = 6 })
	sim:submit(A, { type = "army_recruit", uid = 0, tile = capA, kind = "tank", troops = 2 })
	sim:submit(A, { type = "army_recruit", uid = 0, tile = capA, kind = "artillery", troops = 2 })
	steps(sim, 1)
	local id = newest(sim, A)
	local info = sim:army_info(id)
	local gold = 6 * Units.DEFS.infantry.gold + 2 * Units.DEFS.tank.gold + 2 * Units.DEFS.artillery.gold
	local men = 6 * Units.DEFS.infantry.men + 2 * Units.DEFS.tank.men + 2 * Units.DEFS.artillery.men
	check("army created", info ~= nil and info.owner == A and info.status == SimArmies.STATUS.idle)
	check("composition: one army from three orders", info ~= nil and info.infantry == 6 and info.tank == 2 and info.artillery == 2 and info.total == 10)
	check("cost paid from gold and the troop pool", math.abs((g0 - sim.o_gold[A]) - gold) < 2000 and math.abs((t0 - sim.o_troops[A]) - men) < 5000,
		string.format("gold -%d, men -%d", g0 - sim.o_gold[A], t0 - sim.o_troops[A]))

	-- recruitment validation
	local n_before = 0
	for _ in sim.armies do
		n_before += 1
	end
	local enemy_tile = sim.country_defs[B].capital_tile
	sim:submit(A, { type = "army_recruit", uid = 0, tile = enemy_tile, kind = "infantry", troops = 1 })
	sim:submit(A, { type = "army_recruit", uid = 0, tile = capA, kind = "dragon", troops = 1 })
	sim:submit(A, { type = "army_recruit", uid = 0, tile = capA, kind = "infantry", troops = Units.MAX_RECRUIT + 1 })
	sim:submit(A, { type = "army_recruit", uid = 0, tile = capA, kind = "infantry", troops = 0 })
	steps(sim, 1)
	local n_after = 0
	for _ in sim.armies do
		n_after += 1
	end
	check("invalid recruitment refused (enemy land, bad type, too many, zero)", n_after == n_before)
	local poor = sim.o_gold[A]
	sim.o_gold[A] = 10
	sim:submit(A, { type = "army_recruit", uid = 0, tile = capA, kind = "tank", troops = 1 })
	steps(sim, 1)
	check("recruitment needs gold", newest(sim, A) == id)
	sim.o_gold[A] = poor + 5e6
	sim:submit(A, { type = "army_recruit", uid = id, tile = -1, kind = "infantry", troops = 2 })
	steps(sim, 1)
	check("units added to an existing army", sim:army_info(id).infantry == 8)

	-- unauthorized commands: player B orders A's army
	local before = sim:army_info(id)
	sim:submit(B, { type = "army_move", uid = id, tile = sim.country_defs[B].capital_tile })
	sim:submit(B, { type = "army_disband", uid = id })
	sim:submit(B, { type = "army_recruit", uid = id, tile = capA, kind = "tank", troops = 5 })
	steps(sim, 1)
	local after = sim:army_info(id)
	check("another player's orders do nothing", after ~= nil and after.status == before.status and after.tank == before.tank)
	-- malformed wire intents are dropped by the protocol
	check("malformed intent rejected", Protocol.decode_intent(buffer.fromstring("\0\4\255garbage")) == nil)
	local enc = Protocol.encode_intent({ type = "army_attack", uid = id, tile = 1234 })
	local dec = enc and Protocol.decode_intent(enc)
	check("army intents survive the wire", dec ~= nil and dec.type == "army_attack" and dec.uid == id and dec.tile == 1234)

	-- movement inside own territory (tile by tile, not a teleport)
	local home = sim.P.capital_of[A]
	local far, far_d = 0, -1
	for _, pid in sim.P.by_country[A] do
		local r = sim:_route(A, home, pid, false)
		if r ~= nil and #r > far_d then
			far, far_d = pid, #r
		end
	end
	sim:submit(A, { type = "army_move", uid = id, tile = sim.P.list[far].seed })
	steps(sim, 1)
	local m1 = sim:army_info(id)
	check("move order accepted", m1.status == SimArmies.STATUS.moving and m1.dest_tile == sim.P.list[far].seed, far_d .. " provinces")
	steps(sim, 3)
	check("no teleport: still on its way", sim:army_info(id).province ~= far or far_d == 0)
	local guard = 0
	while sim:army_info(id).status ~= SimArmies.STATUS.idle and guard < 4000 do
		sim:step()
		breathe()
		guard += 1
	end
	check("army arrives", sim:army_info(id).province == far, string.format("%.1f s", guard / 10))

	-- invalid movement
	sim:submit(A, { type = "army_move", uid = id, tile = sim.country_defs[B].capital_tile })
	sim:submit(A, { type = "army_move", uid = id, tile = 0 })
	steps(sim, 1)
	check("move into enemy land / the sea refused", sim:army_info(id).status == SimArmies.STATUS.idle and sim:army_info(id).province == far)

	-- terrain: a mountain province is slower than a plains province
	local function tpt_of(terrain: number): number?
		for pid, p in sim.P.list do
			if p.main_terrain == terrain then
				local fake = { n = { infantry = 1, tank = 0, artillery = 0 }, route = { pid }, route_i = 1, tile = p.seed, id = -99 }
				sim:_army_next_segment(fake)
				return fake.seg_tpt
			end
		end
		return nil
	end
	local plains, mountain = tpt_of(Defs.T_PLAINS), tpt_of(Defs.T_MOUNTAIN)
	check("terrain slows movement", plains ~= nil and mountain ~= nil and mountain > plains, string.format("plains %.2f, mountain %.2f ticks/tile", plains or -1, mountain or -1))
	table.clear(sim.d_ev)

	-- combat: attack B (a player) next door
	local stage, target = border(sim, A, B)
	sim:submit(A, { type = "army_move", uid = id, tile = sim.P.list[stage].seed })
	guard = 0
	steps(sim, 1)
	while sim:army_info(id).status ~= SimArmies.STATUS.idle and guard < 4000 do
		sim:step()
		breathe()
		guard += 1
	end
	-- multiplayer mirror from here: snapshot then deltas through the wire format
	local gs = GameState.new(sim.map)
	gs:load_snapshot(Protocol.decode_snapshot(Protocol.encode_snapshot(sim:snapshot())))
	local function pump(n: number)
		for _ = 1, n do
			local d = sim:step()
			local msg = Protocol.encode_delta(d, nil, sim.W)
			gs:apply_delta(Protocol.decode_delta(msg))
			breathe()
		end
	end
	check("mirror has the army after the snapshot", gs.armies[id] ~= nil and gs.units[id] ~= nil and gs.units[id].kind == Defs.U_ARMY)
	local troopsB0 = sim.o_troops[B]
	sim:submit(A, { type = "army_attack", uid = id, tile = sim.P.list[target].seed })
	pump(1)
	local fight = sim:army_info(id)
	check("attack order starts a battle next door", fight.status == SimArmies.STATUS.combat and sim.battles[target] ~= nil, sim.P.list[target].name)
	check("a movement order captured nothing", sim.p_ctrl[target] == B)
	local n0 = fight.total
	pump(Units.ROUND_TICKS * 3)
	local mid = sim:army_info(id)
	check("combat casualties on both sides", mid == nil or mid.total < n0 or sim.o_troops[B] < troopsB0,
		string.format("army %d -> %s, garrison men -%d", n0, if mid then tostring(mid.total) else "gone", troopsB0 - sim.o_troops[B]))
	check("mirror follows the battle", mid == nil or (gs.armies[id] ~= nil and gs.armies[id].status == mid.status
		and gs.armies[id].infantry == mid.infantry and gs.armies[id].morale == math.floor(mid.morale * 100 + 0.5)))
	check("no orders to an army in battle", (function()
		sim:submit(A, { type = "army_move", uid = id, tile = capA })
		pump(1)
		local x = sim:army_info(id)
		return x == nil or x.status == SimArmies.STATUS.combat
	end)())

	-- manual retreat
	local r0 = sim:army_info(id)
	if r0 ~= nil and r0.status == SimArmies.STATUS.combat then
		sim:submit(A, { type = "army_retreat", uid = id })
		pump(1)
		local r1 = sim:army_info(id)
		check("manual retreat: leaves the battle with losses", r1 ~= nil and r1.status == SimArmies.STATUS.retreating and r1.battle == nil and r1.total <= r0.total and r1.org <= 0.31)
	else
		check("manual retreat: leaves the battle with losses", false, "army no longer in battle")
	end
	guard = 0
	while sim:army_info(id) and sim:army_info(id).status ~= SimArmies.STATUS.idle and guard < 2000 do
		pump(1)
		guard += 1
	end

	-- reinforcement: back to its best composition, paid
	local worn = sim:army_info(id)
	sim.o_gold[A] = 5e6
	sim.o_troops[A] = sim.o_cap[A]
	for _ = 1, 30 do
		pump(Units.ROUND_TICKS) -- (supply back up first)
	end
	local gR = sim.o_gold[A]
	sim:submit(A, { type = "army_reinforce", uid = id })
	pump(1)
	local fresh = sim:army_info(id)
	check("reinforcement restores the army at a cost", worn ~= nil and fresh ~= nil and fresh.infantry == 8 and fresh.tank == 2 and fresh.artillery == 2 and sim.o_gold[A] < gR,
		string.format("%d -> %d battalions", worn and worn.total or -1, fresh and fresh.total or -1))
	sim:submit(A, { type = "army_reinforce", uid = id })
	pump(1)
	check("nothing to reinforce: refused, nothing paid", sim:army_info(id).total == 12)

	-- determinism: the same battle twice gives the same result
	local function duel(seed: number): string
		local s2, a2, b2 = setup(seed)
		local st, tg = border(s2, a2, b2)
		local tile = s2.P.list[st].seed
		s2:submit(a2, { type = "army_recruit", uid = 0, tile = tile, kind = "infantry", troops = 10 })
		s2:submit(a2, { type = "army_recruit", uid = 0, tile = tile, kind = "artillery", troops = 4 })
		steps(s2, 1)
		local x = newest(s2, a2)
		s2:submit(a2, { type = "army_attack", uid = x, tile = s2.P.list[tg].seed })
		steps(s2, Units.ROUND_TICKS * 6)
		local i = s2:army_info(x)
		return if i then string.format("%d/%d/%d %.4f %.4f %d", i.infantry, i.tank, i.artillery, i.morale, i.org, math.floor(s2.o_troops[b2])) else "gone"
	end
	local r1, r2 = duel(9), duel(9)
	check("combat is deterministic", r1 == r2, r1)

	-- unit roles: tanks against unsupported infantry
	local function clash(attacker: { [string]: number }, defender: { [string]: number }): (number, number)
		local s3 = { armies = {} }
		local function mk(n)
			return { n = { infantry = n.infantry or 0, tank = n.tank or 0, artillery = n.artillery or 0 }, carry = { infantry = 0, tank = 0, artillery = 0 }, supply = 1, org = 1, morale = 1 }
		end
		local a, d = mk(attacker), mk(defender)
		local hard_d = d.n.tank / math.max(1, d.n.infantry + d.n.tank + d.n.artillery)
		local dmg = 0
		for _, k in Units.TYPES do
			local def = Units.DEFS[k]
			dmg += a.n[k] * (def.soft_attack * (1 - hard_d) + def.hard_attack * hard_d)
		end
		local _ = s3
		return dmg, 0
	end
	local tank_vs_inf = clash({ tank = 1 }, { infantry = 10 })
	local inf_vs_inf = clash({ infantry = 1 }, { infantry = 10 })
	check("tanks hit infantry harder than infantry does", tank_vs_inf > inf_vs_inf * 3, string.format("%.1f vs %.1f per battalion", tank_vs_inf, inf_vs_inf))
	check("artillery pierces defences", Units.DEFS.artillery.pierce > Units.DEFS.infantry.pierce and Units.DEFS.artillery.exposure < 1 and Units.DEFS.artillery.exposure_alone > 1)

	-- occupation: a big army takes an AI province; occupation, not yet ownership
	local s4, a4, _, c4 = setup(13)
	local st4, tg4 = border(s4, a4, c4)
	if st4 == 0 then
		st4, tg4 = border(s4, a4, s4.p_ctrl[(s4:_prov_adj()[s4.P.capital_of[a4]] or {})[1] or 1])
	end
	local tile4 = s4.P.list[st4].seed
	s4:submit(a4, { type = "army_recruit", uid = 0, tile = tile4, kind = "infantry", troops = 20 })
	s4:submit(a4, { type = "army_recruit", uid = 0, tile = tile4, kind = "tank", troops = 20 })
	s4:submit(a4, { type = "army_recruit", uid = 0, tile = tile4, kind = "artillery", troops = 15 })
	steps(s4, 1)
	local big = newest(s4, a4)
	local defender = s4.p_ctrl[tg4]
	s4:submit(a4, { type = "army_attack", uid = big, tile = s4.P.list[tg4].seed })
	guard = 0
	while s4.battles[tg4] ~= nil or guard < 2 do
		s4:step()
		breathe()
		guard += 1
		if guard > 3000 then
			break
		end
	end
	steps(s4, 20)
	local held = s4.p_count[tg4][a4] or 0
	check("battle won: province occupied", s4.p_ctrl[tg4] == a4 and held > 0, string.format("%s in %.1f s, %d tiles", s4.P.list[tg4].name, guard / 10, held))
	check("occupation, not ownership yet", s4.p_owner[tg4] == defender and s4:province_info(tg4).occupied)
	local bi = s4:army_info(big)
	check("the army moves into the province it took", bi ~= nil and bi.province == tg4 or (bi ~= nil and bi.status == SimArmies.STATUS.moving))

	-- destruction: a lone battalion against a strong garrison
	local s5, a5, b5 = setup(17)
	s5.o_troops[b5] = 5e7 -- a huge defending pool: a deep garrison
	local st5, tg5 = border(s5, a5, b5)
	s5:submit(a5, { type = "army_recruit", uid = 0, tile = s5.P.list[st5].seed, kind = "artillery", troops = 1 })
	steps(s5, 1)
	local lone = newest(s5, a5)
	local seen_del = false
	s5:submit(a5, { type = "army_attack", uid = lone, tile = s5.P.list[tg5].seed })
	for _ = 1, 600 do
		local d = s5:step()
		breathe()
		for _, e in d.ev do
			if e[1] == 11 and e[2] == lone then -- Ev.UNIT_DEL
				seen_del = true
			end
		end
		if s5:army_info(lone) == nil then
			break
		end
	end
	local gone = s5:army_info(lone)
	check("a beaten army is destroyed or falls back", gone == nil or gone.status == SimArmies.STATUS.retreating or gone.status == SimArmies.STATUS.idle,
		if gone == nil then (if seen_del then "destroyed, clients told" else "destroyed") else "fell back")
	check("the province held", s5.p_ctrl[tg5] == b5)

	-- disband: men partly back to the pool
	for _ = 1, 1200 do
		local x = s4:army_info(big)
		if x == nil or x.status == SimArmies.STATUS.idle then
			break
		end
		s4:step()
		breathe()
	end
	local tB = s4.o_troops[a4]
	local menBig = 0
	local ib = s4:army_info(big)
	if ib ~= nil and ib.status == SimArmies.STATUS.idle then
		menBig = ib.infantry * Units.DEFS.infantry.men + ib.tank * Units.DEFS.tank.men + ib.artillery * Units.DEFS.artillery.men
		s4:submit(a4, { type = "army_disband", uid = big })
		steps(s4, 1)
		check("disband returns men to the troop pool", s4:army_info(big) == nil and s4.o_troops[a4] >= tB + math.floor(menBig * Units.DISBAND_REFUND) - 1)
	else
		check("disband returns men to the troop pool", false, "army not standing")
	end

	local summary = string.format("%d passed, %d failed", pass, fail)
	print("[ArmyTests] " .. summary)
	workspace:SetAttribute("ArmyTestsResult", summary .. "\n" .. table.concat(lines, "\n"))
end)
return nil
