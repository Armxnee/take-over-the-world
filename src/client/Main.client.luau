--!strict
-- Client entry: networking, input (mouse / touch / gamepad / keys) and glue.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local State = require(script.Parent.State)
local MapView = require(script.Parent.MapView)
local Hud = require(script.Parent.Hud)
local Tutorial = require(script.Parent.Tutorial)
local Menu = require(script.Parent.Menu)
local Shop = require(script.Parent.Shop)
local Wheel = require(script.Parent.Wheel)
local Audio = require(script.Parent.Audio)
Audio.init()
-- RoWorld's interface (AGPL, see NOTICE.md) drives the screens; our Hud / Menu stay unused
local RW_ON = true
local RW = require(script.Parent.RW.Boot)
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Cmd = Remotes:WaitForChild("Cmd") :: RemoteFunction

local world = Instance.new("ScreenGui")
world.Name = "World"
world.IgnoreGuiInset = true
world.ScreenInsets = Enum.ScreenInsets.None
world.ResetOnSpawn = false
world.DisplayOrder = 0
MapView.init(world)
world.Parent = player:WaitForChild("PlayerGui")
local hudGui = Hud.init()

local function call(kind: string, args: any?): (boolean, any)
	local ok, a, b = pcall(Cmd.InvokeServer, Cmd, kind, args or {})
	if not ok then
		return false, "Network error"
	end
	return a, b
end

local function phase(): string
	return Remotes:GetAttribute("Phase") or "Lobby"
end

if RW_ON then
	hudGui.Enabled = false
end
Tutorial.init(hudGui)
Tutorial.call = call
Tutorial.toast = Hud.toast
Menu.onTutorial = function()
	Tutorial.start()
end
Menu.onShop = function()
	Shop.open()
end
task.spawn(Shop.init)
if not RW_ON then
	task.spawn(Wheel.init)
end
State.on("skin", function(id: number)
	MapView.clearSkinCache()
	MapView.redrawOwners(id, id)
end)
Hud.cb.menu = function()
	Menu.open()
end
Hud.thumb = Menu.thumbLabel
Remotes:WaitForChild("Vote").OnClientEvent:Connect(function(counts)
	Hud.setVotes(counts)
end)
Hud.cb.vote = function(map: string)
	local ok, msg = call("vote", { map = map })
	Hud.toast(tostring(msg), if ok then "good" else "bad")
end
Menu.onOpen = function()
	hudGui.Enabled = false
end
Menu.onClose = function()
	hudGui.Enabled = true
end
if RW_ON then
	local MenuRemote = Remotes:WaitForChild("Menu") :: RemoteFunction
	local function menuCall(action: string, arg: any): (boolean, any)
		local ok, a, b = pcall(MenuRemote.InvokeServer, MenuRemote, action, arg or {})
		if not ok then
			return false, "Network error"
		end
		return a, b
	end
	task.spawn(function()
		local ui = RW.start(call, menuCall)
		ui.external_shop = Shop.open
	end)
	-- phase attributes -> RoWorld phases
	local function phaseSync()
		RW.Feed.syncPhase(Remotes:GetAttribute("Phase") or "Lobby", Remotes:GetAttribute("PhaseEnds") or 0, Remotes:GetAttribute("RoundStart"))
	end
	Remotes:GetAttributeChangedSignal("Phase"):Connect(phaseSync)
	Remotes:GetAttributeChangedSignal("PhaseEnds"):Connect(phaseSync)
	Remotes:GetAttributeChangedSignal("RoundStart"):Connect(phaseSync)
else
	task.spawn(Menu.init)
end

----------------------------------------------------------------------------
-- snapshot / deltas

local loading = false
local applyDiplo: () -> ()
local pending: { number } = {}
local resyncing = false
local centeredRound = -1

local function clearSelection()
	State.selectedUnit = nil
	State.selectedCell = -1
	State.placing = nil
	Hud.showTarget(nil)
	MapView.setHighlight(0)
	MapView.showSelection(nil)
	MapView.showRing(nil, 0)
	MapView.showBuildPreview(nil, nil, false)
end

local function loadSnapshot(s: any)
	loading = true
	pending = {}
	State.applySnapshot(s)
	MapView.load()
	loading = false
	if #pending > 0 then
		MapView.cellsChanged(pending)
		pending = {}
	end
	if MapView.error then
		Hud.toast(MapView.error, "bad")
	end
	MapView.syncStructures()
	MapView.allies = {}
	applyDiplo()
	clearSelection()
	if RW_ON then
		RW.snapshot()
	end
end

local function resync()
	if resyncing then
		return
	end
	resyncing = true
	task.spawn(function()
		for _ = 1, 5 do
			local ok, s = call("resync")
			if ok then
				loadSnapshot(s)
				break
			end
			task.wait(2)
		end
		resyncing = false
	end)
end

Remotes:WaitForChild("Snapshot").OnClientEvent:Connect(function(s)
	Hud.hideResults()
	loadSnapshot(s)
end)
Remotes:WaitForChild("Delta").OnClientEvent:Connect(function(b: buffer)
	if not State.ready or resyncing then
		return
	end
	local list, gap = State.applyDelta(b)
	if gap then
		resync()
	elseif list and #list > 0 then
		if loading then
			table.move(list, 1, #list, #pending + 1, pending)
		else
			MapView.cellsChanged(list)
			if RW_ON then
				RW.Feed.tilesChanged(list)
			end
		end
	end
end)
Remotes:WaitForChild("Stats").OnClientEvent:Connect(function(b: buffer, seq: number)
	if State.ready then
		State.applyStats(b)
		if RW_ON then
			RW.Feed.stats()
		end
		-- a stats packet newer than our map means we missed deltas
		if seq > State.seq + 2 and not loading then
			resync()
		end
	end
end)
Remotes:WaitForChild("Structures").OnClientEvent:Connect(function(rows)
	if State.ready then
		State.setStructures(rows)
		MapView.syncStructures()
		if RW_ON then
			RW.Feed.syncStructures(true)
		end
		Hud.refreshTarget()
	end
end)
function applyDiplo()
	local set = {}
	for _, pr in State.diplo.pairs do
		if pr[1] == State.me then
			set[pr[2]] = true
		elseif pr[2] == State.me then
			set[pr[1]] = true
		end
	end
	MapView.setAllies(set)
	Hud.refreshRequests()
	Hud.refreshTarget()
end
Remotes:WaitForChild("Diplomacy").OnClientEvent:Connect(function(rows)
	if State.ready then
		State.diplo = rows
		applyDiplo()
		if RW_ON then
			RW.Feed.syncDiplomacy()
		end
	end
end)
Remotes:WaitForChild("Mine").OnClientEvent:Connect(function(m)
	State.mine = m.fronts
	State.income = m.income
	if RW_ON then
		RW.Feed.syncAttacks(m.fronts, m.incoming)
	end
end)
Remotes:WaitForChild("Units").OnClientEvent:Connect(function(spawns, gones)
	if State.ready then
		-- launch sounds for things that matter to me
		for _, r in spawns do
			if not State.units[r[1]] then
				local kind, owner = r[2], r[3]
				local last = buffer.readu32(r[4], buffer.len(r[4]) - 4)
				if kind == "missile" then
					Audio.play(if State.ownerAt(last) == State.me then "siren" else "plane")
				elseif (kind == "bomber" or kind == "fighter") and (owner == State.me or State.ownerAt(last) == State.me) then
					Audio.play("plane")
				elseif kind == "warship" and owner == State.me then
					Audio.play("horn")
				end
			end
		end
		State.applyUnits(spawns, gones)
		if RW_ON then
			RW.Feed.syncUnits(true)
		end
	end
end)
Remotes:WaitForChild("Nations").OnClientEvent:Connect(function(list)
	State.setNations(list)
	if RW_ON then
		RW.Feed.syncOwners(true)
	end
end)
Remotes:WaitForChild("Feed").OnClientEvent:Connect(function(text, kind)
	if RW_ON then
		RW.Feed.message(text, kind)
		if kind == "warn" then
			Audio.play("alert")
		end
		return
	end
	if kind == "toast" then
		Hud.toast(text)
	elseif kind == "warn" then
		Audio.play("alert")
		Hud.feed(text, kind)
	elseif kind == "drill_ok" or kind == "drill_fail" then
		Tutorial.onFeed(kind)
		Hud.feed(text, if kind == "drill_ok" then "big" else "warn")
	else
		Hud.feed(text, kind)
	end
end)
Remotes:WaitForChild("Air").OnClientEvent:Connect(function(rows)
	State.airZones = rows
	MapView.camDirty = true
end)
Remotes:WaitForChild("AirFx").OnClientEvent:Connect(function(kind, cell, hit)
	if not State.ready or not cell then
		return
	end
	if kind == "shotdown" then
		MapView.flash(cell, 2, Color3.fromHex("FF8A5C"))
	else
		MapView.flash(cell, 1, if hit then Color3.fromHex("FF5C61") else Color3.new(0.8, 0.8, 0.8))
	end
end)
Remotes:WaitForChild("Results").OnClientEvent:Connect(function(r)
	Audio.play("coin")
	world:SetAttribute("Winner", r.winner)
	clearSelection()
	if RW_ON then
		RW.Feed.gameOver(r)
		return
	end
	Hud.showResults(r)
	if UserInputService:GetLastInputType().Name:match("^Gamepad") then
		Hud.focusResults()
	end
end)
player:GetAttributeChangedSignal("NationId"):Connect(function()
	State.me = player:GetAttribute("NationId") or 0
	if RW_ON then
		RW.me(State.me)
	end
end)

task.spawn(function()
	while true do
		local ok, s = call("hello")
		if ok then
			loadSnapshot(s)
			break
		end
		task.wait(1)
	end
end)

----------------------------------------------------------------------------
-- orders

-- returns (reason it can't be attacked, needs a boat)
local function whyNot(cell: number, owner: number): (string?, boolean)
	if not State.claimable_(cell) then
		return "Water: pick land across the sea to send a boat", false
	end
	local me = State.nations[State.me]
	if not me or not me.alive then
		return "You are spectating", false
	end
	if phase() ~= "Playing" then
		return "Wait for the round to start", false
	end
	if State.allied and State.allied(owner) then
		return "You are allied with them", false
	end
	if not State.borders(State.me, owner) then
		return nil, true -- no land border: cross by sea
	end
	return nil, false
end

local function select(cell: number)
	local owner = State.ownerAt(cell)
	if owner == State.me and State.me ~= 0 then
		clearSelection()
		Hud.toast("That is your land", nil)
		return
	end
	State.selectedCell = cell
	MapView.setHighlight(owner)
	MapView.showSelection(cell)
	local why, boat = whyNot(cell, owner)
	Hud.showTarget({ cell = cell, owner = owner, terrain = State.terrAt(cell), why = why, boat = boat })
end

local usingPad = false
local lastTouch = false
local hoverPos: Vector2? = nil
local doLaunch: (string, number) -> ()
local quickAttack: (number) -> ()

local function selectStructure(st: any)
	State.selectedCell = st.cell
	State.placing = nil
	MapView.setHighlight(if st.owner ~= State.me then st.owner else 0)
	MapView.showSelection(st.cell)
	local r = State.reachOf(st.kind)
	MapView.showRing(if r then st.cell else nil, r or 0)
	Hud.showTarget({ mode = "structure", sid = st.id, cell = st.cell, owner = st.owner })
end

local function enterBuild(kind: string)
	if State.placing == kind then
		clearSelection()
		return
	end
	clearSelection()
	if phase() ~= "Playing" or not State.nations[State.me] then
		Hud.toast("You can build once the round starts", "bad")
		return
	end
	State.placing = kind
	Hud.showTarget({ mode = "build", kind = kind })
end

local function placeAt(cell: number)
	local kind = State.placing :: string
	local why = State.buildWhyNot(kind, cell)
	if usingPad or lastTouch then
		-- touch / controller: pick a spot, then confirm
		Hud.showTarget({ mode = "build", kind = kind, cell = cell, why = why })
		MapView.showSelection(cell)
		return
	end
	if why then
		Hud.toast(why, "bad")
		return
	end
	local ok, msg = call("build", { kind = kind, cell = cell, id = HttpService:GenerateGUID(false) })
	Hud.toast(tostring(msg), if ok then "good" else "bad")
	if ok then
		Audio.play("build")
	end
	if ok then
		clearSelection()
	end
end

local function attack()
	local t = Hud.target
	if not t then
		return
	end
	if t.why then
		Hud.toast(t.why, "bad")
		return
	end
	local ok, msg = call(if t.boat then "boat" else "attack", { cell = t.cell, ratio = State.ratio, id = HttpService:GenerateGUID(false) })
	Hud.toast(tostring(msg), if ok then "good" else "bad")
end

local function trySpawn(cell: number)
	local ok, msg = call("spawn", { cell = cell })
	Hud.toast(tostring(msg), if ok then "good" else "bad")
end

local function recenter()
	local c = State.cnt[State.me] or 0
	if c > 0 then
		MapView.centerOn(State.sumX[State.me] / c, State.sumY[State.me] / c, math.max(MapView.z, 10))
	else
		MapView.fit()
	end
end

local NUKE_RED = Color3.fromHex("FF5C61")
State.on("blast", function(reason: string, cell: number)
	Audio.play(if reason == "impact" then "explosion" else "pop")
	if reason == "impact" then
		MapView.flash(cell, Config.Nuke.Radius, Color3.fromHex("FFE3A3"))
	else
		MapView.flash(cell, 2, Color3.new(1, 1, 1))
	end
end)

-- SAMs that cover a cell (hostile to me)
local function samsCovering(cell: number): number
	local W = State.W
	local r2 = Config.Structures.sam.radius ^ 2
	local c = 0
	for _, s in State.structures do
		if s.kind == "sam" and s.done and s.owner ~= State.me and not State.allied(s.owner) then
			if (s.cell % W - cell % W) ^ 2 + (s.cell // W - cell // W) ^ 2 <= r2 then
				c += 1
			end
		end
	end
	return c
end

-- rings: incoming missile targets always; SAM/defense coverage when the overlay is on
local function overlayRings(): { any }
	local list = {}
	for _, u in State.units do
		if u.kind == "missile" then
			local t = buffer.readu32(u.path, (u.n - 1) * 4)
			table.insert(list, { cell = t, radius = Config.Nuke.Radius, color = NUKE_RED, alpha = 0.8 })
		end
	end
	local t = Hud.target
	if t and t.mode == "launch" and (t.kind == "nuke" or t.kind == "missile") then
		local c = t.cell or (hoverPos and MapView.cellAt(hoverPos, false))
		if c then
			table.insert(list, { cell = c, radius = if t.kind == "nuke" then Config.Nuke.Radius else Config.Missile.Radius, color = NUKE_RED, alpha = 0.75 })
		end
	end
	if t and t.mode == "nuke" and t.cell then
		table.insert(list, { cell = t.cell, radius = Config.Nuke.Radius, color = NUKE_RED, alpha = 0.7 })
	end
	local nowT = workspace:GetServerTimeNow()
	for _, z in State.airZones do
		if z[3] > nowT then
			table.insert(list, { cell = z[1], radius = Config.Air.SuppressRadius, color = Color3.fromHex("FFB547"), alpha = 0.75 })
		end
	end
	if t and t.mode == "air" then
		local af = State.structures[t.sid]
		if t.cell then
			table.insert(list, { cell = t.cell, radius = if t.mission == "cap" then Config.Air.FighterRange else Config.Air.SuppressRadius,
				color = if t.preview and t.preview.why then NUKE_RED else Color3.fromHex("FFB547"), alpha = 0.8 })
		end
		for _, s in State.structures do
			if s.kind == "aa" and s.done and s.owner ~= State.me and not State.allied(s.owner) then
				table.insert(list, { cell = s.cell, radius = Config.Structures.aa.radius, color = Color3.fromHex("C77DFF"), alpha = 0.88 })
			end
		end
	end
	if State.overlays.defense then
		for _, s in State.structures do
			if s.done and s.kind == "aa" then
				table.insert(list, { cell = s.cell, radius = Config.Structures.aa.radius, color = Color3.fromHex("C77DFF"), alpha = 0.9 })
			end
		end
	end
	if State.overlays.defense or (t and t.mode == "nuke") then
		for _, s in State.structures do
			if s.done and (s.kind == "sam" or (s.kind == "defense" and State.overlays.defense)) then
				local mine = s.owner == State.me or State.allied(s.owner)
				table.insert(list, {
					cell = s.cell,
					radius = Config.Structures[s.kind].radius,
					color = if s.kind == "sam" then (if mine then Color3.fromHex("3FB6FF") else Color3.fromHex("FF8A5C")) else Color3.new(1, 1, 1),
					alpha = 0.9,
				})
			end
		end
	end
	return list
end

local function unitAt(p: Vector2): any
	local now = workspace:GetServerTimeNow()
	local best, bd = nil, 14 * 14
	for _, u in State.units do
		if u.kind == "warship" or u.kind == "transport" then
			local x, y = State.unitPos(u, now)
			local q = MapView.cellToLocal(x, y)
			local d = (q - p).Magnitude ^ 2
			if d < bd then
				best, bd = u, d
			end
		end
	end
	return best
end

local function selectUnit(u: any)
	State.placing = nil
	State.selectedUnit = u.id
	State.selectedCell = -1
	MapView.showSelection(nil)
	MapView.showRing(nil, 0)
	Hud.showTarget({ mode = "unit", uid = u.id })
end

-- one click = one order: attack land you border, or send a boat across water.
-- Neutral attacks keep expanding until the troops run out or they reach a border.
function quickAttack(cell: number)
	if phase() ~= "Playing" then
		return
	end
	local owner = State.ownerAt(cell)
	if owner == State.me then
		clearSelection()
		return
	end
	local why, boat = whyNot(cell, owner)
	if why then
		Hud.toast(why, "bad")
		return
	end
	MapView.pulse(cell)
	local ok, msg = call(if boat then "boat" else "attack", { cell = cell, ratio = State.ratio, id = HttpService:GenerateGUID(false) })
	Hud.toast(tostring(msg), if ok then "good" else "bad")
	if ok then
		Audio.play(if boat then "horn" else "attack")
	end
end

local function rwCell(p: Vector2): number?
	return MapView.cellAt(p, false)
end

local function click(p: Vector2)
	if not State.ready then
		return
	end
	if RW_ON then
		local c = rwCell(p)
		if c and RW.world and RW.world.input_enabled then
			RW.world.tile_clicked:Fire(c)
		end
		return
	end
	-- move order for a selected warship (raw cell, no land snap)
	local su = State.selectedUnit and State.units[State.selectedUnit]
	if su and su.kind == "warship" and su.owner == State.me and phase() == "Playing" then
		local raw = MapView.cellAt(p, false)
		if raw and State.terrAt(raw) == 0 then
			local ok, msg = call("moveship", { unit = su.id, cell = raw })
			Hud.toast(tostring(msg), if ok then "good" else "bad")
			return
		end
	end
	State.selectedUnit = nil
	-- tutorial air drill: place the free patrol (raw cell, water allowed)
	if Tutorial.wantsClick() and phase() == "Playing" then
		local raw = MapView.cellAt(p, false)
		if raw then
			Tutorial.click(raw)
		end
		return
	end
	-- launch buttons: click a target (mouse launches at once, touch/pad confirm)
	if Hud.target and Hud.target.mode == "launch" then
		local raw = MapView.cellAt(p, false)
		if raw then
			local kind = Hud.target.kind
			if lastTouch or usingPad then
				Hud.showTarget({ mode = "launch", kind = kind, cell = raw })
				MapView.showSelection(raw)
			else
				doLaunch(kind, raw)
			end
		end
		return
	end
	-- air mission planning: pick a target, preview, confirm
	if Hud.target and Hud.target.mode == "air" then
		local raw = MapView.cellAt(p, false)
		if raw then
			local t = Hud.target
			Hud.showTarget({ mode = "air", sid = t.sid, mission = t.mission, escort = t.escort, cell = raw,
				preview = State.airPreview(t.sid, t.mission, raw, t.escort) })
			MapView.showSelection(raw)
			MapView.camDirty = true
		end
		return
	end
	-- nuke targeting: any cell, then confirm
	if Hud.target and Hud.target.mode == "nuke" then
		local raw = MapView.cellAt(p, false)
		if raw then
			local o = State.ownerAt(raw)
			local why = if o ~= 0 and (o == State.me or State.allied(o)) then "You can't target your own or allied land" else nil
			Hud.showTarget({ mode = "nuke", sid = Hud.target.sid, cell = raw, why = why, sams = samsCovering(raw) })
			MapView.showSelection(raw)
		end
		return
	end
	local cell = MapView.cellAt(p, true)
	if not cell then
		return
	end
	if phase() ~= "Spawn" and not State.placing then
		local u = unitAt(p)
		if u then
			selectUnit(u)
			return
		end
	end
	if phase() == "Spawn" and State.me ~= 0 then
		trySpawn(cell)
	elseif State.placing then
		placeAt(cell)
	else
		-- own buildings open their panel; everything else is a direct order
		local st = State.structureNear(cell, math.max(1, math.ceil(10 / MapView.z)))
		if st and st.owner == State.me then
			selectStructure(st)
		else
			quickAttack(cell)
		end
	end
end

local function primary()
	local t = Hud.target
	if not t then
		return
	end
	if t.mode == "launch" then
		if t.cell then
			doLaunch(t.kind, t.cell)
		end
		return
	end
	if t.mode == "air" then
		local pv = t.preview
		if t.cell and pv and not pv.why then
			local ok, msg = call("air", { airfield = t.sid, mission = t.mission, cell = t.cell, escort = t.escort, id = HttpService:GenerateGUID(false) })
			Hud.toast(tostring(msg), if ok then "good" else "bad")
			if ok then
				if t.mission == "strike" then
					table.insert(State.myStrikes, os.clock())
				end
				clearSelection()
			end
		elseif pv and pv.why then
			Hud.toast(pv.why, "bad")
		end
		return
	end
	if t.mode == "nuke" then
		if t.cell and not t.why then
			local ok, msg = call("nuke", { silo = t.sid, cell = t.cell, id = HttpService:GenerateGUID(false) })
			Hud.toast(tostring(msg), if ok then "good" else "bad")
			if ok then
				clearSelection()
			end
		elseif t.why then
			Hud.toast(t.why, "bad")
		end
		return
	end
	if t.mode == "build" then
		if t.cell and not t.why then
			local ok, msg = call("build", { kind = t.kind, cell = t.cell, id = HttpService:GenerateGUID(false) })
			Hud.toast(tostring(msg), if ok then "good" else "bad")
			if ok then
				clearSelection()
			end
		elseif t.why then
			Hud.toast(t.why, "bad")
		end
	elseif t.mode == "structure" then
		local st = State.structures[t.sid]
		if not st then
			return
		end
		if st.owner == State.me then
			if st.kind == "city" then
				local ok, msg = call("upgrade", { structure = st.id, id = HttpService:GenerateGUID(false) })
				Hud.toast(tostring(msg), if ok then "good" else "bad")
			elseif st.kind == "port" then
				local ok, msg = call("warship", { port = st.id, id = HttpService:GenerateGUID(false) })
				Hud.toast(tostring(msg), if ok then "good" else "bad")
			elseif st.kind == "silo" then
				Hud.showTarget({ mode = "nuke", sid = st.id })
			elseif st.kind == "airfield" then
				Hud.showTarget({ mode = "air", sid = st.id, mission = "strike", escort = false })
				MapView.camDirty = true
			end
		else
			select(st.cell)
			attack()
		end
	else
		attack()
	end
end

Hud.cb.attack = attack
Hud.cb.primary = primary
Hud.cb.buildMode = enterBuild
Hud.cb.launchMode = function(kind: string)
	clearSelection()
	if phase() ~= "Playing" then
		Hud.toast("Launch once the round starts", "bad")
		return
	end
	Hud.showTarget({ mode = "launch", kind = kind })
end
function doLaunch(kind: string, cell: number)
	local ok, msg = call("launch", { kind = kind, cell = cell, id = HttpService:GenerateGUID(false) })
	Hud.toast(tostring(msg), if ok then "good" else "bad")
	if ok then
		Audio.play(if kind == "warship" then "horn" elseif kind == "nuke" or kind == "missile" then "whoosh" else "plane")
		clearSelection()
	end
end
Wheel.cb.attack = function(cell: number)
	quickAttack(cell)
end
Wheel.cb.info = function(cell: number)
	select(cell)
end
Wheel.cb.aid = function(kind: string, nid: number)
	local ok, msg = call("aid", { target = nid, kind = kind, ratio = math.clamp(State.ratio, 0.05, 0.5), id = HttpService:GenerateGUID(false) })
	Hud.toast(tostring(msg), if ok then "good" else "bad")
end
-- open the wheel for whatever nation is under a point; neutral land / buildings get the inspector
local function wheelAt(p: Vector2, pad: boolean?)
	if not State.ready then
		return
	end
	if RW_ON then
		local c = rwCell(p)
		if c and RW.world and RW.world.input_enabled then
			RW.world.tile_context:Fire(c, p + MapView.frame().AbsolutePosition)
		end
		return
	end
	local cell = MapView.cellAt(p, true)
	if not cell then
		return
	end
	local owner = State.ownerAt(cell)
	if owner ~= 0 and owner ~= State.me and State.nations[owner] then
		clearSelection()
		Wheel.open(p, owner, cell, pad)
	else
		local st = State.structureNear(cell, math.max(1, math.ceil(10 / MapView.z)))
		if st then
			selectStructure(st)
		else
			select(cell)
		end
	end
end
Hud.cb.cancel = clearSelection
Hud.cb.shop = function()
	Shop.open()
end
Hud.cb.retreat = function(id: number)
	local ok, msg = call("retreat", { attack = id, id = HttpService:GenerateGUID(false) })
	Hud.toast(tostring(msg), if ok then nil else "bad")
end
Hud.cb.zoom = function(f: number)
	MapView.zoomAt(f, MapView.center())
end
Hud.cb.recenter = recenter
Hud.cb.focus = function(nid: number)
	local c = State.cnt[nid] or 0
	if c > 0 then
		MapView.centerOn(State.sumX[nid] / c, State.sumY[nid] / c, math.max(MapView.z, 3))
	end
end
Hud.cb.tutorial = function()
	Tutorial.start()
end
-- cycle mission type: Bomber -> Bomber + escort -> Fighter patrol
Hud.cb.airMode = function()
	local t = Hud.target
	if not t or t.mode ~= "air" then
		return
	end
	local m, e = t.mission, t.escort
	if m == "strike" and not e then
		e = true
	elseif m == "strike" then
		m, e = "cap", false
	else
		m, e = "strike", false
	end
	Hud.showTarget({ mode = "air", sid = t.sid, mission = m, escort = e, cell = t.cell,
		preview = if t.cell then State.airPreview(t.sid, m, t.cell, e) else nil })
	MapView.camDirty = true
end
Wheel.cb.ally = function(action: string, target: number)
	local ok, msg = call("ally", { action = action, target = target, id = HttpService:GenerateGUID(false) })
	Hud.toast(tostring(msg), if ok then "good" else "bad")
end
Hud.cb.ally = function(action: string, target: number)
	local ok, msg = call("ally", { action = action, target = target, id = HttpService:GenerateGUID(false) })
	Hud.toast(tostring(msg), if ok then "good" else "bad")
end
Hud.cb.overlay = function(name: string)
	State.overlays[name] = not State.overlays[name]
	MapView.camDirty = true
	Hud.toast(("%s overlay %s"):format(if name == "routes" then "Trade routes" else "Air defense (blue/orange SAM = missiles, purple AA = aircraft)", if State.overlays[name] then "on" else "off"))
	return State.overlays[name]
end
Hud.cb.requeue = function(on: boolean)
	local _, msg = call("requeue", { on = on })
	Hud.toast(tostring(msg))
end

local function spawnPreviewOk(cell: number): boolean
	if not State.claimable_(cell) then
		return false
	end
	local o = State.ownerAt(cell)
	if o ~= 0 and o ~= State.me then
		return false
	end
	local W, H = State.W, State.H
	local cx, cy = cell % W, cell // W
	local r = Config.Spawn.MinDist
	for y = math.max(0, cy - r), math.min(H - 1, cy + r) do
		for x = math.max(0, cx - r), math.min(W - 1, cx + r) do
			local oo = State.ownerAt(y * W + x)
			if oo ~= 0 and oo ~= State.me and (x - cx) ^ 2 + (y - cy) ^ 2 <= r * r then
				return false
			end
		end
	end
	return true
end

-- (hoverPos is declared near the top)
local function updatePreview()
	if phase() ~= "Spawn" or State.me == 0 or not State.ready or not hoverPos then
		MapView.showPreview(nil, 0, false)
		return
	end
	local cell = MapView.cellAt(hoverPos, true)
	if cell then
		MapView.showPreview(cell, Config.Spawn.Radius, spawnPreviewOk(cell))
	else
		MapView.showPreview(nil, 0, false)
	end
end

----------------------------------------------------------------------------
-- input

local UIT = Enum.UserInputType
local KC = Enum.KeyCode
local down: Vector2? = nil
local rdown: Vector2? = nil
local pressAt = 0
local longFired = false
local lastDrag: Vector2? = nil
local dragging = false
local touches: { [InputObject]: Vector2 } = {}
local touchCount = 0
local pinchDist = 0
local stick = Vector2.zero
local zoomIn, zoomOut = false, false
local function pos2(io: InputObject): Vector2
	return MapView.toLocal(io.Position)
end

local function stepRatio(d: number)
	Hud.setRatio(State.ratio + d)
end

UserInputService.InputBegan:Connect(function(io, gpe)
	local t = io.UserInputType
	if t == UIT.MouseButton1 then
		lastTouch = false
		if not gpe then
			down = pos2(io)
			dragging = false
		end
	elseif t == UIT.MouseButton2 then
		if not gpe then
			rdown = pos2(io)
		end
	elseif t == UIT.Touch then
		if gpe then
			return
		end
		lastTouch = true
		touches[io] = pos2(io)
		touchCount += 1
		if touchCount == 1 then
			down = touches[io]
			dragging = false
			pressAt = os.clock()
			longFired = false
		elseif touchCount == 2 then
			dragging = true
			local a, b
			for _, v in touches do
				if not a then a = v else b = v end
			end
			pinchDist = if a and b then (a - b).Magnitude else 0
		end
	elseif t == UIT.Keyboard then
		if gpe then
			return
		end
		local k = io.KeyCode
		if RW_ON and k ~= KC.R and k ~= KC.T and k ~= KC.G and k ~= KC.Equals and k ~= KC.Minus then
			return -- RoWorld's interface owns the other hotkeys
		end
		if k == KC.Q then
			stepRatio(-Config.Combat.RatioStep)
		elseif k == KC.E then
			stepRatio(Config.Combat.RatioStep)
		elseif k == KC.Space or k == KC.F then
			primary()
		elseif k.Value >= KC.One.Value and k.Value <= KC.Eight.Value then
			enterBuild(Config.StructureOrder[k.Value - KC.One.Value + 1])
		elseif k == KC.X or k == KC.Backspace then
			Wheel.close()
			clearSelection()
		elseif k == KC.R then
			recenter()
		elseif k == KC.T then
			Hud.cb.overlay("routes")
		elseif k == KC.G then
			Hud.cb.overlay("defense")
		elseif k == KC.F1 then
			Tutorial.start()
		elseif k == KC.Equals then
			MapView.zoomAt(1.3, MapView.center())
		elseif k == KC.Minus then
			MapView.zoomAt(1 / 1.3, MapView.center())
		end
	elseif t == UIT.Gamepad1 then
		local k = io.KeyCode
		if k == KC.ButtonA and not gpe and not GuiService.SelectedObject and not Wheel.isOpen() then
			click(MapView.center())
		elseif k == KC.ButtonX then
			primary()
		elseif k == KC.ButtonY then
			if Wheel.isOpen() then
				Wheel.close()
			elseif GuiService.SelectedObject then
				GuiService.SelectedObject = nil
			else
				local cell = MapView.cellAt(MapView.center(), true)
				local owner = cell and State.ownerAt(cell) or 0
				if owner ~= 0 and owner ~= State.me then
					wheelAt(MapView.center(), true)
				else
					Hud.focusMenu()
				end
			end
		elseif k == KC.ButtonB then
			if Wheel.isOpen() then
				Wheel.close()
			elseif GuiService.SelectedObject then
				GuiService.SelectedObject = nil
			else
				clearSelection()
			end
		elseif k == KC.ButtonL1 then
			stepRatio(-Config.Combat.RatioStep)
		elseif k == KC.ButtonR1 then
			stepRatio(Config.Combat.RatioStep)
		elseif k == KC.ButtonL2 then
			zoomOut = true
		elseif k == KC.ButtonR2 then
			zoomIn = true
		elseif k == KC.ButtonL3 then
			recenter()
		end
	end
end)

UserInputService.InputChanged:Connect(function(io, gpe)
	local t = io.UserInputType
	if t == UIT.MouseMovement then
		local p = pos2(io)
		hoverPos = p
		if RW_ON and RW.world and State.ready then
			local c = rwCell(p) or -1
			if c ~= RW.lastHover then
				RW.lastHover = c
				RW.world.tile_hovered:Fire(c)
			end
		end
		if down and not Hud.isSliderDragging() then
			if not dragging and (p - down).Magnitude > 6 then
				dragging = true
				lastDrag = down
			end
			if dragging then
				local d = p - (lastDrag :: Vector2)
				lastDrag = p
				MapView.pan(d.X, d.Y)
			end
		end
	elseif t == UIT.MouseWheel then
		if not gpe then
			MapView.zoomAt(1.15 ^ io.Position.Z, pos2(io))
		end
	elseif t == UIT.Touch then
		local old = touches[io]
		if not old or Hud.isSliderDragging() then
			return
		end
		local p = pos2(io)
		touches[io] = p
		hoverPos = p
		if touchCount == 1 and down then
			if not dragging and (p - down).Magnitude > 10 then
				dragging = true
			end
			if dragging then
				MapView.pan(p.X - old.X, p.Y - old.Y)
			end
		elseif touchCount == 2 then
			local a, b
			for _, v in touches do
				if not a then a = v else b = v end
			end
			if a and b then
				local d = (a - b).Magnitude
				if pinchDist > 0 and d > 0 then
					MapView.zoomAt(d / pinchDist, (a + b) / 2)
				end
				pinchDist = d
				MapView.pan((p.X - old.X) / 2, (p.Y - old.Y) / 2)
			end
		end
	elseif t == UIT.Gamepad1 and io.KeyCode == KC.Thumbstick1 then
		stick = Vector2.new(io.Position.X, io.Position.Y)
	end
end)

UserInputService.InputEnded:Connect(function(io)
	local t = io.UserInputType
	if t == UIT.MouseButton1 then
		if down and not dragging then
			click(pos2(io))
		end
		down = nil
		dragging = false
	elseif t == UIT.MouseButton2 then
		local p = pos2(io)
		if State.placing then
			clearSelection()
		elseif rdown and (p - rdown).Magnitude < 6 and State.ready then
			-- right click: action wheel on nations, inspector elsewhere
			wheelAt(p, false)
		end
		rdown = nil
	elseif t == UIT.Touch then
		if touches[io] then
			if touchCount == 1 and down and not dragging and not longFired then
				click(touches[io])
			end
			touches[io] = nil
			touchCount = math.max(0, touchCount - 1)
			if touchCount == 0 then
				down = nil
				dragging = false
			end
		end
	elseif t == UIT.Gamepad1 then
		if io.KeyCode == KC.ButtonL2 then
			zoomOut = false
		elseif io.KeyCode == KC.ButtonR2 then
			zoomIn = false
		end
	end
end)

UserInputService.LastInputTypeChanged:Connect(function(t)
	usingPad = t.Name:match("^Gamepad") ~= nil
	MapView.showReticle(usingPad)
	Hud.setPadMode(usingPad)
end)

----------------------------------------------------------------------------
-- frame loop

-- ownership checksum for multi-client consistency checks (read by tests)
task.spawn(function()
	while true do
		task.wait(2)
		if State.ready and not loading then
			local h = 0
			for i = 0, State.N - 1 do
				h = (h + buffer.readu16(State.owner, i * 2) * (i % 9973 + 1)) % 2147483647
			end
			world:SetAttribute("OwnerHash", h)
			world:SetAttribute("Seq", State.seq)
		end
	end
end)

local hudAcc, plateAcc, selAcc, tutAcc = 0, 0, 0, 0
local connAcc = 0
local lastPreviewFrom: number? = nil
local lastPhase = ""
RunService.RenderStepped:Connect(function(dt)
	if usingPad and not Wheel.isOpen() then
		if stick.Magnitude > 0.15 then
			MapView.pan(-stick.X * 700 * dt, stick.Y * 700 * dt)
		end
		if zoomIn then
			MapView.zoomAt(1 + 1.6 * dt, MapView.center())
		elseif zoomOut then
			MapView.zoomAt(1 / (1 + 1.6 * dt), MapView.center())
		end
		hoverPos = MapView.center()
	end
	MapView.flush(16)
	MapView.updateUnits()
	if RW_ON then
		RW.Feed.frame()
	end
	-- touch long-press (0.45 s without moving) opens the wheel
	if touchCount == 1 and down and not dragging and not longFired and os.clock() - pressAt > 0.45 and lastTouch then
		longFired = true
		wheelAt(down :: Vector2, false)
	end
	if State.selectedCell >= 0 then
		MapView.showSelection(State.selectedCell)
	end
	updatePreview()
	-- rail connections: every own factory always, plus the placement preview
	connAcc += dt
	local previewFrom = if State.placing == "factory" then (if Hud.target and Hud.target.cell then Hud.target.cell elseif hoverPos and not (lastTouch or usingPad) then MapView.cellAt(hoverPos, true) else nil) else nil
	if connAcc > 0.5 or previewFrom ~= lastPreviewFrom then
		connAcc = 0
		lastPreviewFrom = previewFrom
		local list = {}
		for _, st in State.structures do
			if st.kind == "factory" and State.built(st) then
				table.insert(list, { from = st.cell, to = State.railStops(st.cell, st.id, st.owner) })
			end
		end
		if previewFrom then
			table.insert(list, { from = previewFrom, to = State.railStops(previewFrom, nil), preview = true })
		end
		MapView.connections = list
		MapView.camDirty = true
	end
	if State.placing and hoverPos and not (lastTouch or usingPad) then
		local cell = MapView.cellAt(hoverPos, true)
		if cell then
			MapView.showBuildPreview(cell, State.placing, State.buildWhyNot(State.placing, cell) == nil)
			local r = State.reachOf(State.placing)
			MapView.showRing(if r then cell else nil, r or 0)
		end
	elseif State.placing and Hud.target and Hud.target.cell then
		local r = State.reachOf(State.placing)
		MapView.showRing(if r then Hud.target.cell else nil, r or 0)
	end
	if MapView.camDirty then
		MapView.camDirty = false
		MapView.updatePlates()
		MapView.updateMarkers()
		if Hud.target and Hud.target.mode == "structure" then
			local st = State.structures[Hud.target.sid]
			local r = st and State.reachOf(st.kind)
			MapView.showRing(if r then st.cell else nil, r or 0)
		end
	end

	plateAcc += dt
	if plateAcc > 0.066 then
		plateAcc = 0
		MapView.updatePlates()
		MapView.updateMarkers()
		MapView.updateRoutes()
		MapView.drawRings(overlayRings())
	end

	tutAcc += dt
	if tutAcc > 0.25 then
		tutAcc = 0
		Tutorial.update()
	end
	hudAcc += dt
	if hudAcc > 0.1 then
		hudAcc = 0
		Hud.update()
		-- hover tooltip: only over the open map, never over UI
		local tipCell = nil
		if hoverPos and not lastTouch and not usingPad and State.ready and phase() == "Playing" and not State.placing
			and not (Hud.target and Hud.target.mode ~= nil and Hud.target.mode ~= "attack") and not Wheel.isOpen() and not Menu.isOpen() then
			local m = UserInputService:GetMouseLocation()
			local overUi = false
			for _, o in Players.LocalPlayer.PlayerGui:GetGuiObjectsAtPosition(m.X, m.Y) do
				if not o:IsDescendantOf(world) and o.Visible and (o:IsA("GuiButton") or o.BackgroundTransparency < 0.95) then
					overUi = true
					break
				end
			end
			if not overUi then
				tipCell = MapView.cellAt(hoverPos, false)
			end
		end
		Hud.hover(tipCell)
		local ph = phase()
		local me = State.nations[State.me]
		local ends = Remotes:GetAttribute("PhaseEnds") or 0
		local left = math.max(0, math.ceil(ends - workspace:GetServerTimeNow()))
		if ph == "Lobby" then
			Hud.setBanner(("Next round in %ds"):format(left))
		elseif ph == "Spawn" then
			Hud.setBanner(if State.me ~= 0 then ("Click land to pick your start  ·  %ds"):format(left) else "Spectating  ·  round starting")
		elseif ph == "Playing" then
			local incoming = false
			for _, u in State.units do
				if u.kind == "missile" then
					local tc = buffer.readu32(u.path, (u.n - 1) * 4)
					local W = State.W
					local R = Config.Nuke.Radius
					for y = -R, R, 2 do
						for x = -R, R, 2 do
							local c = tc + y * W + x
							if c >= 0 and c < State.N and State.ownerAt(c) == State.me then
								incoming = true
							end
						end
					end
				end
			end
			Hud.setBanner(if not me or not me.alive then "Spectating"
				elseif incoming then "INCOMING NUCLEAR MISSILE!"
				elseif Hud.target and Hud.target.mode == "nuke" then "Nuke targeting · click a target · X to cancel"
				elseif Hud.target and Hud.target.mode == "air" then "Air mission · click a target in range · X to cancel"
				elseif Hud.target and Hud.target.mode == "launch" then ("Launch %s · click a target · X to cancel"):format(Hud.LAUNCH[Hud.target.kind].name)
				elseif State.placing then ("Placing %s  ·  click your land  ·  X to cancel"):format(Config.Structures[State.placing].name)
				else nil)
		else
			Hud.setBanner("Round over")
		end
		if ph ~= lastPhase then
			lastPhase = ph
			if ph == "Playing" and centeredRound ~= State.round then
				centeredRound = State.round
				recenter()
			end
		end
	end

	-- keep the selected target's panel current (owner can change under it)
	selAcc += dt
	if selAcc > 0.5 and State.selectedCell >= 0 and (Hud.target == nil or (Hud.target.mode or "attack") == "attack") then
		selAcc = 0
		local cell = State.selectedCell
		local owner = State.ownerAt(cell)
		if owner == State.me then
			clearSelection()
		else
			MapView.setHighlight(owner)
			local why, boat = whyNot(cell, owner)
			Hud.showTarget({ cell = cell, owner = owner, terrain = State.terrAt(cell), why = why, boat = boat })
		end
	end
end)
