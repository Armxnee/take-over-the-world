-- (Take Over the World!: Stage 5 supply / logistics / resources tests, 2026-11-06.)
-- Server dev harness: workspace:SetAttribute("AF_DEV", "LogisticsTests"), then Play.
-- Summary in workspace attribute "LogisticsTestsResult".
local RS = game:GetService("ReplicatedStorage")
local Airfront = RS:WaitForChild("Airfront")
local Core = Airfront:WaitForChild("Core")
local Defs = require(Core:WaitForChild("Defs"))
local WorldMap = require(Core:WaitForChild("WorldMap"))
local GameState = require(Core:WaitForChild("GameState"))
local Sim = require(Core:WaitForChild("Sim"))
local Provinces = require(Core:WaitForChild("Provinces"))
local Units = require(Airfront:WaitForChild("Data"):WaitForChild("Units"))
local Logistics = require(Airfront:WaitForChild("Data"):WaitForChild("Logistics"))
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
	local line = string.format("[LogisticsTests] %s %s%s", if ok then "PASS" else "FAIL", name, if detail ~= nil then "  (" .. tostring(detail) .. ")" else "")
	print(line)
	table.insert(lines, line)
end

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

task.spawn(function()
	local map = WorldMap.get("world")
	task.wait()
	local sim = Sim.new(map, { seed = 21, max_humans = 2, difficulty = 1 })
	task.wait()
	-- two players: A (4+ provinces) and a neighbour B
	local adj = sim:_prov_adj()
	local A, B
	for _, d in sim.country_list do
		if #d.provinces >= 5 then
			for _, pid in d.provinces do
				for _, nb in adj[pid] do
					local c = sim.P.list[nb].country
					if c ~= d.owner and #sim.P.by_country[c] >= 2 then
						A, B = d.owner, c
					end
				end
			end
			if A then
				break
			end
		end
	end
	local h1, h2 = sim:add_human("a", "A"), sim:add_human("b", "B")
	sim:submit(h1, { type = "spawn", tile = sim.country_defs[A].capital_tile })
	sim:submit(h2, { type = "spawn", tile = sim.country_defs[B].capital_tile })
	steps(sim, 1)
	local guard = 0
	while sim.phase == Defs.PHASE_SPAWN and guard < 3000 do
		sim:step()
		breathe()
		guard += 1
	end
	sim:drain_owner_moves()
	steps(sim, 10)
	check("setup", sim.l_on and A ~= nil and B ~= nil and sim.phase == Defs.PHASE_PLAYING, tostring(sim.o_name[A]) .. " / " .. tostring(sim.o_name[B]))

	-- deposits differ between countries
	local patterns = {}
	local with_oil, n = 0, 0
	for _, d in sim.country_list do
		local prod = sim:_production(d.owner)
		n += 1
		if prod.oil > 0 then
			with_oil += 1
		end
		patterns[string.format("%d%d%d%d", if prod.steel > 0 then 1 else 0, if prod.oil > 0 then 1 else 0, if prod.aluminum > 0 then 1 else 0, if prod.rare > 0 then 1 else 0)] = true
	end
	local kinds = 0
	for _ in patterns do
		kinds += 1
	end
	check("countries get different deposits", kinds >= 3 and with_oil > 0 and with_oil < n, string.format("%d deposit patterns, %d/%d countries with oil", kinds, with_oil, n))

	-- production and storage
	local s = sim:_stock(A)
	for _, k in Logistics.RESOURCES do
		s[k] = 0
	end
	local prod = sim:_production(A)
	steps(sim, 50)
	check("resources are produced", math.abs(s.food - prod.food * 5) <= prod.food + 1 and s.food > 0, string.format("food %.1f/s -> %d in 5 s", prod.food, s.food))
	s.food = sim:_storage(A) - 1
	steps(sim, 20)
	check("storage cap holds", s.food <= sim:_storage(A))

	-- construction: costs, validation, completion
	sim.o_gold[A] = 1e7
	for _, k in Logistics.RESOURCES do
		s[k] = 5000
	end
	local capP = sim.P.capital_of[A]
	local capT = sim.P.list[capP].seed
	local g0, st0 = sim.o_gold[A], s.steel
	local okRoad = sim:build_infra(A, "road", capT)
	local gR, rR = Logistics.cost("road", 1)
	check("road costs gold and steel", okRoad and sim.o_gold[A] == g0 - gR and s.steel == st0 - rR.steel)
	check("one job per province", not sim:build_infra(A, "farm", capT))
	check("not in someone else's province", not sim:build_infra(A, "road", sim.country_defs[B].capital_tile))
	check("unauthorized: B can't build in A", not sim:build_infra(B, "road", capT))
	local noOil = 0
	for _, pid in sim.P.by_country[A] do
		if sim.l_dep[pid].oil <= 0 and pid ~= capP and sim.p_ctrl[pid] == A then
			noOil = pid
		end
	end
	check("oil facility needs a deposit", noOil == 0 or not sim:build_infra(A, "oil", sim.P.list[noOil].seed))
	local other = 0
	for _, pid in sim.P.by_country[A] do
		if pid ~= capP and pid ~= noOil and sim.p_ctrl[pid] == A then
			other = pid
		end
	end
	check("railway needs a road", not sim:build_infra(A, "rail", sim.P.list[other].seed))
	local poor = sim.o_gold[A]
	sim.o_gold[A] = 10
	check("construction needs gold", not sim:build_infra(A, "farm", sim.P.list[other].seed))
	sim.o_gold[A] = poor
	steps(sim, Logistics.INFRA.road.ticks + 2)
	check("construction completes after its build time", sim.l_infra[capP].road == 1 and sim.l_job[capP] == nil, Logistics.INFRA.road.ticks / 10 .. " s")
	local ok_unknown = pcall(function()
		sim:submit(A, { type = "set_resource", kind = "gold", troops = 999999 })
		steps(sim, 1)
	end)
	check("no command can set resources", ok_unknown and sim.o_gold[A] < 1e7 + 1e5)

	-- link capacity: base < road < rail
	local nb = adj[capP][1]
	for _, p in adj[capP] do
		if sim.p_ctrl[p] == A then
			nb = p
		end
	end
	local base = sim:_link(capP, nb)
	sim.l_infra[nb].road = 1
	local road = sim:_link(capP, nb)
	sim.l_infra[capP].rail, sim.l_infra[nb].rail = 1, 1
	local rail = sim:_link(capP, nb)
	check("roads and railways raise link capacity", base < road and road < rail, string.format("%d < %d < %d", base, road, rail))
	sim.l_infra[capP].rail, sim.l_infra[nb].rail = 0, 0

	-- connectivity from the capital
	sim:_recompute_net(A)
	local net = sim.l_net[A]
	local all_ok = true
	for _, pid in sim.P.by_country[A] do
		if sim.p_ctrl[pid] == A and (net.cap[pid] or 0) <= 0 then
			all_ok = false
		end
	end
	check("the home provinces are connected", net.cap[capP] == Logistics.CAPITAL_OUTPUT and all_ok)

	-- an army: consumption, recovery
	local st = sim:_stock(A)
	for _, k in Logistics.RESOURCES do
		st[k] = 3000 -- (under the storage cap)
	end
	sim.o_troops[A] = sim.o_cap[A]
	local far = other
	sim:army_recruit(A, 0, sim.P.list[far].seed, "infantry", 4)
	sim:army_recruit(A, 0, sim.P.list[far].seed, "tank", 2)
	local id = 0
	for aid, a in sim.armies do
		if a.owner == A then
			id = aid
		end
	end
	local a = sim.armies[id]
	local expect = (4 * Logistics.SUPPLY_USE.infantry + 2 * Logistics.SUPPLY_USE.tank) * (Logistics.TERRAIN_USE[sim.P.list[far].main_terrain + 1] or 1)
	check("consumption follows the unit mix and terrain", a ~= nil and math.abs(sim:army_consumption(a) - expect) < 1e-6, string.format("%.2f/s", expect))
	a.status = 2
	local fighting = sim:army_consumption(a)
	a.status = 0
	check("combat uses more supply", fighting > expect)
	a.supply = 0.5
	local food0, oil0 = st.food, st.oil
	steps(sim, 30)
	check("connected army recovers supply", a.supply > 0.5 and a.connected, string.format("%.2f", a.supply))
	local made = sim:_production(A)
	check("supply costs food and oil (tanks)", st.food - food0 < made.food * 3 - 1 and st.oil - oil0 < made.oil * 3 - 1,
		string.format("food %+d (made %.0f), oil %+d (made %.0f)", st.food - food0, made.food * 3, st.oil - oil0, made.oil * 3))

	-- thresholds and their effect on combat
	check("status tiers", Logistics.status(0.9).code == 0 and Logistics.status(0.5).code == 1 and Logistics.status(0.2).code == 2 and Logistics.status(0).code == 3)
	local e = {}
	for _, v in { 1.0, 0.5, 0.2, 0.0 } do
		table.insert(e, Units.effectiveness(v, 1, 1))
	end
	check("supply drives combat effectiveness", e[1] > e[2] and e[2] > e[3] and e[3] > e[4], string.format("%.2f %.2f %.2f %.2f", e[1], e[2], e[3], e[4]))

	-- encirclement: everything of A but the army's province falls to B
	local flipped = {}
	local function flip(to_owner: number, keep: number)
		for _, pid in sim.P.by_country[A] do
			if pid ~= keep then
				for _, t in Provinces.tiles_of(sim.P, pid) do
					local o = readi32(sim.owner, t * 4)
					if o == (if to_owner == B then A else B) and sim:claimable(t) then
						sim:set_owner(t, to_owner)
						flipped[t] = true
					end
				end
			end
		end
	end
	a.supply = 1
	local t0 = os.clock()
	flip(B, far)
	steps(sim, 21)
	check("capture cuts the route: army isolated", a.connected == false, sim.P.list[far].name)
	check("isolation drains supply slowly (not instantly)", a.supply > 0.85 and a.supply < 1, string.format("%.3f after 2 s", a.supply))
	sim.o_gold[A] = 1e7
	check("no reinforcement while cut off", not sim:army_reinforce(A, id))
	check("retreat toward supply when cut off: none left, it stands", sim:nearest_supplied(A, a.prov) == 0)
	steps(sim, 420)
	local hurt = a.carry.infantry + a.carry.tank + a.carry.artillery
	check("out of supply: attrition sets in, the army is not wiped out at once", a.supply == 0 and sim.armies[id] ~= nil and hurt > 0,
		string.format("%d battalions, %.0f hp of attrition", a.n.infantry + a.n.tank + a.n.artillery, hurt))
	-- the route comes back
	flip(A, far)
	steps(sim, 40)
	check("restored route: resupply resumes", sim.armies[id] == nil or (a.connected and a.supply > 0), string.format("%.2f", a.supply))

	-- depots: storage and distribution, also cut off
	local dp = far
	sim.l_infra[dp].depot = 1
	sim:_mark_dirty(A)
	steps(sim, 60)
	local stock1 = sim.l_infra[dp].stock
	check("depot fills from the national stocks", stock1 > 0 and stock1 <= Logistics.DEPOT_STORAGE, string.format("%d stored", stock1))
	if sim.armies[id] == nil then
		sim:army_recruit(A, 0, sim.P.list[far].seed, "infantry", 4)
		for aid, x in sim.armies do
			if x.owner == A then
				id = aid
			end
		end
	end
	a = sim.armies[id]
	flip(B, far)
	steps(sim, 21)
	local sa = sim.l_infra[dp].stock
	steps(sim, 50)
	check("an encircled depot keeps its army supplied", a.connected and a.source == dp and sim.l_infra[dp].stock < sa, string.format("stock %d -> %d in 5 s", sa, sim.l_infra[dp].stock))
	flip(A, far)
	steps(sim, 25)

	-- multiplayer: the wire carries stocks, infrastructure, networks and army supply
	local gs = GameState.new(sim.map)
	gs:load_snapshot(Protocol.decode_snapshot(Protocol.encode_snapshot(sim:snapshot())))
	check("snapshot carries logistics", gs.resources[A] ~= nil and gs.infra[capP] ~= nil and gs.infra[capP].road == 1 and gs.supplynet[A] ~= nil and gs.supplynet[A][capP] ~= nil)
	sim:build_infra(A, "farm", sim.P.list[nb].seed)
	for _ = 1, 12 do
		local d = sim:step()
		gs:apply_delta(Protocol.decode_delta(Protocol.encode_delta(d, nil, sim.W)))
	end
	local mirror = gs.armies[id]
	check("deltas carry stocks, construction and army supply", gs.infra[nb] ~= nil and gs.infra[nb].building == Logistics.INFRA.farm.code
		and math.abs(gs.resources[A].food - math.floor(sim:_stock(A).food)) <= math.ceil(sim:_production(A).food) + 1
		and mirror ~= nil and mirror.connected == a.connected and mirror.supply == math.floor(a.supply * 100 + 0.5))

	-- performance: every country's network at once, and a logistics tick
	local t1 = os.clock()
	local count = 0
	for _, d in sim.country_list do
		if sim.o_alive[d.owner] == 1 then
			sim:_recompute_net(d.owner)
			count += 1
		end
	end
	local all_ms = (os.clock() - t1) * 1000
	local t2 = os.clock()
	steps(sim, 100)
	local tick_ms = (os.clock() - t2) * 10
	check("network recalculation is cheap", all_ms < 400, string.format("%d networks in %.1f ms; %.2f ms per tick", count, all_ms, tick_ms))
	local _ = t0

	local summary = string.format("%d passed, %d failed", pass, fail)
	print("[LogisticsTests] " .. summary)
	workspace:SetAttribute("LogisticsTestsResult", summary .. "\n" .. table.concat(lines, "\n"))
end)
return nil
