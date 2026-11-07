-- (Take Over the World!: country selection + province ownership tests, 2026-11-06.)
-- Server dev harness: workspace:SetAttribute("AF_DEV", "CountryTests"), then Play. Builds headless Sims
-- on a map (attribute CountryTestsMap, default "world") and checks provinces, full borders, country
-- definitions, server-side country picks (one country per player, simultaneous picks, re-picks,
-- invalid picks), occupation, capitals, annexation, elimination and client/server determinism.
-- Prints PASS / FAIL lines; the summary goes to workspace attribute "CountryTestsResult".
local RS = game:GetService("ReplicatedStorage")
local Core = RS:WaitForChild("Airfront"):WaitForChild("Core")
local Defs = require(Core:WaitForChild("Defs"))
local WorldMap = require(Core:WaitForChild("WorldMap"))
local GameState = require(Core:WaitForChild("GameState"))
local Sim = require(Core:WaitForChild("Sim"))
local Provinces = require(Core:WaitForChild("Provinces"))

local readu16, readi32 = buffer.readu16, buffer.readi32
local pass, fail = 0, 0
local lines = {}
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		pass += 1
	else
		fail += 1
	end
	local line = string.format("[CountryTests] %s %s%s", if ok then "PASS" else "FAIL", name, if detail ~= nil then "  (" .. tostring(detail) .. ")" else "")
	print(line)
	table.insert(lines, line)
end

local function steps(sim: any, n: number)
	for _ = 1, n do
		sim:step()
	end
end

task.spawn(function()
	local map_id = workspace:GetAttribute("CountryTestsMap") or "world"
	-- MapData lives on the server (non-default maps)
	local server = game:GetService("ServerScriptService"):FindFirstChild("AirfrontServer")
	local md = server and server:FindFirstChild("MapData")
	if md ~= nil then
		WorldMap.add_provider(function(id)
			local m = md:FindFirstChild(id) or md:FindFirstChild((string.gsub(id, "^%l", string.upper)))
			for _, c in md:GetChildren() do
				if string.lower(c.Name) == string.lower(id) then
					m = c
				end
			end
			return if m then require(m) :: any else nil
		end)
	end
	local map = WorldMap.get(map_id)
	local t0 = os.clock()
	local sim = Sim.new(map, { seed = 7, max_humans = 2, difficulty = 1 })
	local build_s = os.clock() - t0
	check("sim built with countries", sim.countries == true and sim._prov_on == true, string.format("%.2f s", build_s))

	-- provinces cover the land; every country has a capital province
	local P = sim.P
	local missing, claim = 0, 0
	for t = 0, sim.N - 1 do
		if sim:claimable(t) then
			claim += 1
			if readu16(P.prov_of, t * 2) == 0 then
				missing += 1
			end
		end
	end
	check("every land tile is in a province", missing == 0, string.format("%d provinces, %d land tiles, %d missing", #P.list, claim, missing))
	local caps_ok = true
	for id in sim.country_defs do
		if P.capital_of[id] == nil or not P.list[P.capital_of[id]].capital then
			caps_ok = false
		end
	end
	check("every country has a capital province", caps_ok)

	-- full borders: each tile belongs to its country at the start
	local wrong = 0
	for t = 0, sim.N - 1 do
		if sim:claimable(t) then
			local c = readu16(P.country_of, t * 2)
			if c ~= 0 and readi32(sim.owner, t * 4) ~= c then
				wrong += 1
			end
		end
	end
	check("full borders: countries own their whole region", wrong == 0, wrong .. " tiles off")
	check("no tribes in countries mode", sim.tribe_count == 0)

	-- definitions
	local fields_ok, n_defs = true, 0
	for _, d in sim.country_list do
		n_defs += 1
		for _, k in { "id", "name", "ball", "capital", "provinces", "population", "resources", "military", "bonuses", "difficulty" } do
			if d[k] == nil then
				fields_ok = false
				warn("[CountryTests] missing", k, d.name)
			end
		end
	end
	check("country definitions complete", fields_ok and n_defs > 0, n_defs .. " countries")
	local ids = {}
	for _, d in sim.country_list do
		if ids[d.id] then
			fields_ok = false
		end
		ids[d.id] = true
	end
	check("country ids unique", fields_ok)

	-- province info fields
	local info = sim:province_info(1)
	check("province info", info ~= nil and info.name ~= nil and info.population ~= nil and info.resources ~= nil and info.importance ~= nil and info.owner == info.original,
		info and info.name)

	-- picks: two humans
	local h1 = sim:add_human("k1", "Alice")
	local h2 = sim:add_human("k2", "Bob")
	local A = sim.country_list[1].owner
	local B = sim.country_list[2].owner
	local C = sim.country_list[3].owner
	local capA = sim.country_defs[A].capital_tile
	-- simultaneous: both pick A in the same tick; the first intent wins
	sim:submit(h1, { type = "spawn", tile = capA })
	sim:submit(h2, { type = "spawn", tile = capA })
	steps(sim, 1)
	local moves = sim:drain_owner_moves()
	check("simultaneous picks: one winner", #moves == 1 and moves[1][1] == h1 and moves[1][2] == A and sim.o_kind[A] == Defs.KIND_HUMAN,
		#moves .. " moves")
	check("loser keeps no country", sim.o_spawned[h2] == 0 and sim.o_alive[h2] == 1)
	-- taken country is refused, a free one works
	sim:submit(h2, { type = "spawn", tile = sim.country_defs[A].capital_tile })
	steps(sim, 1)
	check("taken country refused", #sim:drain_owner_moves() == 0)
	sim:submit(h2, { type = "spawn", tile = sim.country_defs[B].capital_tile })
	steps(sim, 1)
	moves = sim:drain_owner_moves()
	check("free country accepted", #moves == 1 and moves[1][2] == B)
	-- re-pick during the spawn phase: A goes back to its AI
	sim:submit(A, { type = "spawn", tile = sim.country_defs[C].capital_tile })
	steps(sim, 1)
	moves = sim:drain_owner_moves()
	check("re-pick: new country, old one back to AI", #moves == 1 and moves[1][2] == C and sim.o_kind[A] == Defs.KIND_NATION and sim.o_kind[C] == Defs.KIND_HUMAN)
	-- a pick of water / nobody's tile does nothing
	sim:submit(C, { type = "spawn", tile = 0 })
	steps(sim, 1)
	check("pick on water refused", #sim:drain_owner_moves() == 0 and sim.o_kind[C] == Defs.KIND_HUMAN)
	-- a third human with nothing picked gets a random free country when the spawn phase ends
	local h3 = sim:add_human("k3", "Cara")
	local guard = 0
	while sim.phase == Defs.PHASE_SPAWN and guard < 2000 do
		sim:step()
		guard += 1
	end
	moves = sim:drain_owner_moves()
	local got3 = 0
	for _, mv in moves do
		if mv[1] == h3 then
			got3 = mv[2]
		end
	end
	check("unpicked player gets a free country", got3 > 0 and sim.o_kind[got3] == Defs.KIND_HUMAN and got3 ~= B and got3 ~= C, got3)
	check("match playing", sim.phase == Defs.PHASE_PLAYING)
	-- after the spawn phase a human can't hop to another country
	sim:submit(C, { type = "spawn", tile = sim.country_defs[A].capital_tile })
	steps(sim, 1)
	check("no country hopping after spawn", #sim:drain_owner_moves() == 0)
	-- disconnect keeps the country (passive, still owned)
	sim:remove_human(B)
	steps(sim, 1)
	check("disconnect keeps the country", sim.o_alive[B] == 1 and sim.o_tiles[B] > 0)
	check("reconnect returns the same country", sim:add_human("k2", "Bob") == B)

	-- occupation: C takes A's capital province tile by tile (what combat does: set_owner)
	local capP = P.capital_of[A]
	local tilesA = Provinces.tiles_of(P, capP)
	for _, t in tilesA do
		sim:set_owner(t, C)
	end
	steps(sim, 10)
	local pi = sim:province_info(capP)
	check("occupation: controller follows the tiles", pi.controller == C and pi.owner == A and pi.occupied, pi.name)
	check("capital captured, country not eliminated", sim.o_alive[A] == 1 and not sim:holds_capital(A) and sim:holds_capital(C) == (P.capital_of[C] ~= nil and sim.p_ctrl[P.capital_of[C]] == C))
	local st = sim:country_stats(C)
	check("territory statistics updated", st.occupying >= 1 and sim:country_stats(A).lost >= 1, string.format("C occupies %d, A lost %d", st.occupying, sim:country_stats(A).lost))
	-- annexation after ANNEX_TICKS
	steps(sim, Provinces.ANNEX_TICKS + 20)
	check("annexed after holding it", sim.p_owner[capP] == C, sim.p_owner[capP])
	-- liberation: A takes it back
	for _, t in tilesA do
		sim:set_owner(t, A)
	end
	steps(sim, 10)
	check("liberated: back to its original owner", sim.p_ctrl[capP] == A and sim.p_owner[capP] == A)

	-- incremental counts equal a full recount
	local bad = 0
	for id = 1, #P.list do
		local fresh = {}
		for _, t in Provinces.tiles_of(P, id) do
			local o = readi32(sim.owner, t * 4)
			if o ~= 0 then
				fresh[o] = (fresh[o] or 0) + 1
			end
		end
		for o, n in fresh do
			if (sim.p_count[id][o] or 0) ~= n then
				bad += 1
			end
		end
	end
	check("province counts match the tiles", bad == 0, bad)

	-- elimination only when all land is gone
	local victim = sim.country_list[4].owner
	if sim.o_kind[victim] ~= Defs.KIND_NATION then
		victim = sim.country_list[5].owner
	end
	for _, pid in sim.P.by_country[victim] do
		for _, t in Provinces.tiles_of(P, pid) do
			if readi32(sim.owner, t * 4) == victim then
				sim:set_owner(t, C)
			end
		end
	end
	steps(sim, 2)
	check("country with no land is eliminated", sim.o_alive[victim] == 0)

	-- the economy bonus: holding the capital raises gold income
	local g1 = select(1, sim:country_mults(C))
	check("capital + national bonus multiplier", g1 >= 1.0, string.format("x%.2f", g1))

	-- a real AI match keeps running with provinces (no errors), and the client mirror can rebuild the
	-- same provinces from its snapshot (determinism)
	local sim2 = Sim.new(map, { seed = 11, max_humans = 0, difficulty = 1 })
	local gs = GameState.new(map)
	gs:load_snapshot(sim2:snapshot())
	local caps = {}
	for id = 1, sim2.owner_total do
		local o = gs:get_owner(id)
		if o ~= nil and o.spawn_tile ~= nil and o.spawn_tile >= 0 and sim2.country_defs[id] ~= nil then
			caps[id] = o.spawn_tile
		end
	end
	local P2 = Provinces.build(map, caps)
	local same = #P2.list == #sim2.P.list
	if same then
		for t = 0, sim2.N - 1, 7 do
			if readu16(P2.prov_of, t * 2) ~= readu16(sim2.P.prov_of, t * 2) then
				same = false
				break
			end
		end
	end
	check("client rebuilds the same provinces", same, #P2.list .. " vs " .. #sim2.P.list)
	local t1 = os.clock()
	local errs = 0
	for _ = 1, 600 do
		local ok, e = pcall(sim2.step, sim2)
		if not ok then
			errs += 1
			warn("[CountryTests] step error", e)
			break
		end
	end
	local changed = 0
	for id = 1, #sim2.P.list do
		if sim2.p_ctrl[id] ~= sim2.P.list[id].country then
			changed += 1
		end
	end
	check("60 s AI war runs with provinces", errs == 0, string.format("%.1f ms/tick, %d provinces changed hands", (os.clock() - t1) * 1000 / 600, changed))

	local summary = string.format("%d passed, %d failed", pass, fail)
	print("[CountryTests] " .. summary)
	workspace:SetAttribute("CountryTestsResult", summary .. "\n" .. table.concat(lines, "\n"))
end)
return nil
