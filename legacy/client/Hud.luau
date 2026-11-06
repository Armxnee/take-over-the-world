--!strict
-- Strategy HUD (Clean Strategy style). Keeps the map dominant; panels sit at the edges.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Config = require(ReplicatedStorage.Shared.Config)
local State = require(script.Parent.State)
local UI = require(script.Parent.UI)
local Icons = require(script.Parent.Icons)
local Art = require(script.Parent.Art)
local Audio = require(script.Parent.Audio)

local C, F = UI.C, UI.F
local make, label, button, panel = UI.make, UI.label, UI.button, UI.panel

local Hud = {}
Hud.cb = {} :: { [string]: (...any) -> () }

local gui: ScreenGui
local scale: UIScale
local el: { [string]: any } = {}
local feedRows: { any } = {}
local frontChips: { any } = {}
local frontKey = ""
local lbRows: { any } = {}
local toastToken = 0
local draggingSlider = false
local reqCards: { Instance } = {}
local reqKey = ""
local incomeHist: { any } = {}

local function cb(name: string, ...: any)
	local f = Hud.cb[name]
	if f then
		f(...)
	end
end

local function statCell(parent: Instance, order: number, w: number, title: string, color: Color3?)
	local f = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0, w, 1, 0), LayoutOrder = order, Parent = parent })
	label({ Text = title, TextSize = 11, FontFace = F.Bold, TextColor3 = C.Sub, Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 4), Parent = f })
	local v = label({ Text = "-", TextSize = 18, FontFace = F.Bold, TextColor3 = color or C.Text, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 18), Parent = f })
	return f, v
end

local function swatch(parent: Instance, col: Color3, size: number): Frame
	return make("Frame", { BackgroundColor3 = col, Size = UDim2.fromOffset(size, size), BorderSizePixel = 0, Parent = parent }, { UI.corner(3) })
end

function Hud.toast(text: string, kind: string?)
	toastToken += 1
	local my = toastToken
	local t = el.toast :: TextLabel
	t.Text = text
	t.TextColor3 = if kind == "bad" then C.Bad elseif kind == "good" then C.Good else C.Text
	if not t.Parent.Visible then
		UI.slideIn(t.Parent, 0, -16)
	end
	t.Parent.Visible = true
	task.delay(2.4, function()
		if toastToken == my then
			t.Parent.Visible = false
		end
	end)
end

Hud.lastCoins = nil :: string?
local FEED_COL = { warn = C.Warn, elim = C.Bad, big = C.Gold, good = C.Good }
function Hud.feed(text: string, kind: string?)
	if text:match("^%+%d+ coins") then
		Hud.lastCoins = text
	end
	local col = FEED_COL[kind or ""] or C.Accent
	for k = #feedRows, 2, -1 do
		local r, q = feedRows[k], feedRows[k - 1]
		r.text.Text = q.text.Text
		r.bar.BackgroundColor3 = q.bar.BackgroundColor3
		r.frame.Visible = q.frame.Visible
	end
	local r = feedRows[1]
	r.text.Text = text
	r.bar.BackgroundColor3 = col
	r.frame.Visible = true
	UI.slideIn(r.frame, -24, 0)
	local my = text
	task.delay(12, function()
		for _, row in feedRows do
			if row.text.Text == my then
				row.frame.Visible = false
			end
		end
	end)
end

function Hud.setBanner(text: string?)
	el.banner.Visible = text ~= nil and text ~= ""
	el.bannerText.Text = text or ""
end

local function ratioText(): string
	local me = State.nations[State.me]
	local troops = if me then me.troops else 0
	return ("<b>%d%%</b> <font color=\"#8B98A8\">· %s</font>"):format(math.floor(State.ratio * 100 + 0.5), State.fmt(math.floor(troops * State.ratio)))
end

function Hud.setRatio(r: number)
	State.ratio = math.clamp(r, 0.01, 1)
	el.ratioText.Text = ratioText()
	el.ratioFill.Size = UDim2.fromScale(State.ratio, 1)
	for pct, chip in el.chips do
		local on = math.abs(pct / 100 - State.ratio) < 0.005
		chip.BackgroundColor3 = if on then C.Accent else C.Raise
		chip.TextColor3 = if on then C.Bg else C.Text
	end
	Hud.refreshTarget()
end

-- target panel
Hud.target = nil :: any
function Hud.showTarget(info: any)
	local was = el.target.Visible
	Hud.target = info
	el.target.Visible = info ~= nil
	if info and not was then
		UI.slideIn(el.target, 40, 0)
	end
	Hud.refreshTarget()
end

local function benefit(kind: string): string
	local d = Config.Structures[kind]
	if kind == "city" then
		return d.blurb:format(State.fmt(d.capBonus))
	elseif kind == "defense" then
		return d.blurb:format(d.defenseMult, d.radius)
	elseif kind == "sam" or kind == "airfield" or kind == "aa" then
		return d.blurb:format(d.radius)
	end
	return d.blurb
end
Hud.benefit = benefit

-- launch bar entries (server picks the nearest ready launcher)
Hud.LAUNCH = {
	warship = { name = "Warship", sprite = "warship", cost = 0, hint = "Click water to send a warship", from = "From your nearest port on that sea" },
	fighter = { name = "Fighter", sprite = "fighter", cost = 0, hint = "Click where it should patrol", from = "From a free airfield in range" },
	bomber = { name = "Bomber", sprite = "bomber", cost = 0, hint = "Click an enemy front or building", from = "From a free airfield in range" },
	missile = { name = "Missile", sprite = "rocket", cost = Config.Missile.Cost, hint = "Click an enemy target", from = "From your nearest silo" },
	nuke = { name = "Nuke", sprite = "missile", cost = Config.Nuke.Cost, hint = "Click an enemy target", from = "From your nearest silo" },
}
Hud.LAUNCH_ORDER = { "warship", "fighter", "bomber", "missile", "nuke" }
Hud.menuLocked = false

Hud.padMode = false
function Hud.setPadMode(on: boolean)
	Hud.padMode = on
	if el.tCancel then
		el.tCancel.Text = if on then "Cancel (B)" else "Cancel (X)"
	end
	Hud.refreshTarget()
end

-- controller: Y puts focus on the build menu (then the D-pad navigates)
function Hud.focusMenu()
	local first = el.buildBtns and el.buildBtns.city
	if first then
		game:GetService("GuiService").SelectedObject = first.btn
	end
end

function Hud.focusResults()
	if el.requeue then
		game:GetService("GuiService").SelectedObject = el.requeue
	end
end

local function setPrimary(text: string, enabled: boolean)
	if Hud.padMode then
		text = text:gsub("%(Space%)", "(X)")
	end
	el.tAttack.Text = text
	el.tAttack.AutoButtonColor = enabled
	el.tAttack.BackgroundColor3 = if enabled then C.Accent else C.Raise
	el.tAttack.TextColor3 = if enabled then C.Bg else C.Sub
end

function Hud.refreshTarget()
	local t = Hud.target
	if not t then
		return
	end
	local mode = t.mode or "attack"
	if mode == "build" then
		el.tAlly.Visible = false
		local d = Config.Structures[t.kind]
		Icons.apply(el.tIcon, t.kind)
		el.tIcon.Visible = true
		el.tSwatch.BackgroundColor3 = C.Raise
		el.tName.Text = "Build " .. d.name
		el.tKind.Text = ("Build time %ds  ·  %s"):format(d.build, if t.cell then "spot picked" else "pick a spot on your land")
		el.tStats.Text = ("Cost <b><font color=\"#F5C451\">%s</font></b> gold"):format(State.fmt(State.costFor(t.kind)))
		el.tCommit.Text = benefit(t.kind)
		el.tWhy.Text = t.why or ""
		el.tWhy.Visible = t.why ~= nil
		setPrimary(if t.cell then "CONFIRM BUILD" else "PICK A SPOT", t.cell ~= nil and t.why == nil)
		return
	elseif mode == "air" then
		local pv = t.preview
		Icons.apply(el.tIcon, "airfield")
		el.tIcon.Visible = true
		el.tSwatch.BackgroundColor3 = C.Accent
		el.tName.Text = if t.mission == "cap" then "Fighter patrol" elseif t.escort then "Bomber + escort" else "Tactical bomber"
		el.tAlly.Visible = true
		el.tAlly.Text = "Change"
		el.tAlly.BackgroundColor3 = C.Raise
		el.tAlly:SetAttribute("Action", "airMode")
		if not t.cell or not pv then
			el.tKind.Text = "Click any target on the map"
			el.tStats.Text = if t.mission == "cap" then ("Patrols %ds, engages aircraft within %d cells"):format(Config.Air.CapTime, Config.Air.FighterRange)
				else "Hits an enemy front or building, opens a ground-attack window"
			el.tCommit.Text = ""
			el.tWhy.Visible = false
			setPrimary("PICK A TARGET", false)
			return
		end
		local o = State.nations[State.ownerAt(t.cell)]
		el.tKind.Text = ("%s  ·  ETA %ds%s"):format(if o then o.name else "neutral", math.ceil(pv.eta),
			if pv.payload == "structure" then ("  ·  hits %s"):format(Config.Structures[pv.struct].name) elseif pv.payload == "front" then "  ·  front strike" else "")
		el.tStats.Text = ("Cost <b><font color=\"#F5C451\">%s</font></b>   AA on route <b>%d</b>   Fighters <b>%d</b>"):format(State.fmt(pv.cost), pv.aa, pv.fighters)
		el.tCommit.Text = if pv.firstThreat then ("Risk: first contact ~%ds after launch"):format(math.ceil(pv.firstThreat))
			elseif t.mission == "cap" then "Clear skies on the way" else ("Strike: %ds ground-attack window"):format(Config.Air.SuppressTime)
		el.tWhy.Text = pv.why or ""
		el.tWhy.TextColor3 = C.Bad
		el.tWhy.Visible = pv.why ~= nil
		setPrimary("LAUNCH (Space)", pv.why == nil)
		return
	elseif mode == "launch" then
		local L = Hud.LAUNCH[t.kind]
		el.tAlly.Visible = false
		el.tIcon.Visible = false
		el.tSwatch.BackgroundColor3 = C.Accent
		el.tName.Text = "Launch " .. L.name
		el.tKind.Text = if t.cell then "Target picked" else L.hint
		el.tStats.Text = if L.cost > 0 then ("Cost <b><font color=\"#F5C451\">%s</font></b> gold"):format(State.fmt(L.cost)) else "<b>FREE</b>"
		el.tCommit.Text = L.from
		el.tWhy.Visible = false
		setPrimary(if t.cell then "LAUNCH (Space)" else "PICK A TARGET", t.cell ~= nil)
		return
	elseif mode == "nuke" then
		el.tAlly.Visible = false
		local NK = Config.Nuke
		local me = State.nations[State.me]
		Icons.apply(el.tIcon, "silo")
		el.tIcon.Visible = true
		el.tSwatch.BackgroundColor3 = C.Bad
		el.tName.Text = "Nuclear strike"
		local o = if t.cell then State.ownerAt(t.cell) else 0
		local on = State.nations[o]
		el.tKind.Text = if t.cell then ("Target: %s"):format(if on then on.name else "neutral land") else "Click a target on the map"
		el.tStats.Text = ("Cost <b><font color=\"#F5C451\">%s</font></b> gold   Blast <b>%d</b> cells"):format(State.fmt(NK.Cost), NK.Radius)
		el.tCommit.Text = if t.cell then ("Hostile SAMs covering target: <b>%d</b>"):format(t.sams or 0) else "Clears land, kills troops, destroys buildings"
		local why = t.why or (if me and me.gold < NK.Cost then "Not enough gold" else nil)
		el.tWhy.Text = why or ""
		el.tWhy.TextColor3 = C.Bad
		el.tWhy.Visible = why ~= nil
		setPrimary(if t.cell then "LAUNCH (Space)" else "PICK A TARGET", t.cell ~= nil and why == nil)
		return
	elseif mode == "unit" then
		el.tAlly.Visible = false
		local u = State.units[t.uid]
		if not u then
			Hud.showTarget(nil)
			return
		end
		local n = State.nations[u.owner]
		local mine = u.owner == State.me
		el.tIcon.Visible = false
		el.tSwatch.BackgroundColor3 = if n then n.color else C.Raise
		el.tName.Text = if u.kind == "warship" then "Warship" else "Transport"
		el.tKind.Text = (if n then n.name else "?") .. (if mine then "  ·  yours" else "")
		local maxHp = if u.kind == "warship" then Config.Naval.WarshipHp else Config.Naval.BoatHp
		el.tStats.Text = ("Hull <b>%d%%</b>   Range <b>%d</b> cells"):format(math.clamp(math.floor((u.hp or maxHp) / maxHp * 100), 0, 100), Config.Naval.WarshipRange)
		el.tCommit.Text = if mine and u.kind == "warship" then "Click water to move. Engages non-allied ships in range." elseif u.kind == "warship" then "Hostile warships sink transports and seize trade" else "Carrying troops to a landing"
		el.tWhy.Visible = false
		setPrimary("—", false)
		return
	elseif mode == "structure" then
		el.tAlly.Visible = false
		local st = State.structures[t.sid]
		if not st then
			Hud.showTarget(nil)
			return
		end
		local d = Config.Structures[st.kind]
		local n = State.nations[st.owner]
		Icons.apply(el.tIcon, st.kind)
		el.tIcon.Visible = true
		el.tSwatch.BackgroundColor3 = if n then n.color else C.Raise
		el.tName.Text = d.name .. (if st.kind == "city" then (" · Lv " .. st.level) else "")
		local left = st.readyAt - workspace:GetServerTimeNow()
		local status = if not st.done and left > 0 then ("Building · %ds"):format(math.ceil(left))
			elseif st.disabledAt > workspace:GetServerTimeNow() then "Disabled"
			else "Active"
		el.tKind.Text = (if n then n.name else "?") .. "  ·  " .. status
		el.tStats.Text = benefit(st.kind)
		local mine = st.owner == State.me
		if mine and st.kind == "city" then
			local cost = math.floor(d.cost * d.upgradeCost * st.level)
			local can = st.done and st.level < d.maxLevel
			el.tCommit.Text = if st.level >= d.maxLevel then "Max level" else ("Upgrade: <b>%s</b> gold → +%s capacity"):format(State.fmt(cost), State.fmt(d.capBonus))
			local me = State.nations[State.me]
			local why = if not can then nil elseif me and me.gold < cost then "Not enough gold" else nil
			el.tWhy.Text = why or ""
			el.tWhy.Visible = why ~= nil
			setPrimary("UPGRADE (Space)", can and why == nil)
		elseif mine and st.kind == "airfield" then
			el.tCommit.Text = ("Fighter %s · Bomber from %s gold"):format(State.fmt(Config.Air.FighterCost), State.fmt(Config.Air.BomberCost))
			el.tWhy.Visible = false
			setPrimary("PLAN MISSION", st.done)
		elseif mine and st.kind == "silo" then
			el.tCommit.Text = ("Nuke: <b>%s</b> gold · blast %d cells"):format(State.fmt(Config.Nuke.Cost), Config.Nuke.Radius)
			el.tWhy.Visible = false
			setPrimary("TARGET NUKE", st.done)
		elseif mine and st.kind == "port" then
			local cost = Config.Naval.WarshipCost
			local me = State.nations[State.me]
			el.tCommit.Text = ("Warship: <b>%s</b> gold · max %d per port"):format(State.fmt(cost), Config.Naval.MaxWarshipsPerPort)
			local why = if not st.done then "Still under construction" elseif me and me.gold < cost then "Not enough gold" else nil
			el.tWhy.Text = why or ""
			el.tWhy.Visible = why ~= nil
			setPrimary("BUILD WARSHIP", why == nil)
		else
			el.tCommit.Text = if mine then "" else "Enemy building: capture the land under it"
			el.tWhy.Visible = false
			setPrimary(if mine then "—" else "ATTACK (Space)", not mine)
		end
		return
	end
	el.tIcon.Visible = false
	local me = State.nations[State.me]
	local commit = if me then math.floor(me.troops * State.ratio) else 0
	local n = if t.owner ~= 0 then State.nations[t.owner] else nil
	-- alliance control
	local st, pr = nil, nil
	if n and n.kind ~= "tribe" and me and me.alive then
		st, pr = State.allyState(n.id)
		local req = State.requestWith(n.id)
		el.tAlly.Visible = true
		if st == "allied" then
			el.tAlly.Text, el.tAlly.BackgroundColor3 = "Break ally", C.Bad
		elseif st == "breaking" then
			el.tAlly.Text = ("Ends %ds"):format(math.max(0, math.ceil(pr[4] - workspace:GetServerTimeNow())))
			el.tAlly.BackgroundColor3 = C.Raise
		elseif req == "theirs" then
			el.tAlly.Text, el.tAlly.BackgroundColor3 = "Accept ally", C.Good
		elseif req == "mine" then
			el.tAlly.Text, el.tAlly.BackgroundColor3 = "Sent…", C.Raise
		else
			el.tAlly.Text, el.tAlly.BackgroundColor3 = "Propose ally", C.Raise
		end
		el.tAlly:SetAttribute("Target", n.id)
		el.tAlly:SetAttribute("Action", if st == "allied" then "break" elseif req == "theirs" then "accept" elseif st == nil and req == nil then "request" else "")
	else
		el.tAlly.Visible = false
	end
	el.tSwatch.BackgroundColor3 = if n then n.color else Color3.fromHex("CFC8B0")
	el.tName.Text = if n then n.name else "Neutral land"
	local rel = if not n then "Unclaimed · fast to take"
		elseif st == "allied" then "Ally"
		elseif st == "breaking" then "Ally · alliance ending"
		elseif n.kind == "human" then "Player · Rival"
		elseif n.kind == "tribe" then "Tribe · Rival (weak)"
		else "AI nation · Rival"
	el.tKind.Text = rel .. "  ·  " .. (Config.Terrain[t.terrain] and Config.Terrain[t.terrain].name or "")
	if n then
		el.tStats.Text = ("Troops <b>%s</b>   Land <b>%.1f%%</b>"):format(State.fmt(n.troops), n.land / State.claimable * 100)
	else
		el.tStats.Text = "No defenders"
	end
	el.tCommit.Text = ("%s <b>%s</b> troops (%d%%)"):format(if t.boat then "Boat carries" else "Commit", State.fmt(commit), math.floor(State.ratio * 100 + 0.5))
	el.tWhy.Text = if t.why then t.why elseif t.boat then "No land border: troops cross by sea and land on the nearest coast" else ""
	el.tWhy.TextColor3 = if t.why then C.Bad else C.Sub
	el.tWhy.Visible = t.why ~= nil or t.boat == true
	setPrimary(if t.boat then "SEND BOAT (Space)" else "ATTACK  (Space)", t.why == nil)
end

function Hud.update()
	local me = State.nations[State.me]
	local phase = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:GetAttribute("Phase") or "Lobby"
	if me then
		el.troops.Text = ("%s <font color=\"#8B98A8\">/ %s</font>"):format(State.fmt(me.troops), State.fmt(me.max))
		el.troopBar.Size = UDim2.fromScale(math.clamp(me.troops / me.max, 0, 1), 1)
		el.gold.Text = State.fmt(me.gold)
		el.land.Text = ("%.1f%% of the world"):format(me.land / State.claimable * 100)
		el.meName.Text = me.name
		el.meSwatch.BackgroundColor3 = me.color
	else
		el.troops.Text = "-"
		el.troopBar.Size = UDim2.fromScale(0, 1)
		el.gold.Text = "-"
		el.land.Text = "Spectating"
		el.meName.Text = Players.LocalPlayer.DisplayName
	end
	local rs = ReplicatedStorage:FindFirstChild("Remotes")
	local start = rs and rs:GetAttribute("RoundStart") or 0
	local now = workspace:GetServerTimeNow()
	if phase == "Playing" then
		local s = math.max(0, now - start)
		el.time.Text = ("%02d:%02d"):format(s // 60, s % 60)
	else
		local ends = rs and rs:GetAttribute("PhaseEnds") or now
		el.time.Text = ("%ds"):format(math.max(0, math.ceil(ends - now)))
	end
	el.phase.Text = if phase == "Playing" then "MATCH TIME" else string.upper(phase)
	if phase == "Spawn" and Hud.lastPhase ~= "Spawn" then
		el.lb.Visible = false -- every match starts with the board closed
	end
	Hud.lastPhase = phase
	Hud.menuLocked = phase == "Playing" or phase == "Spawn"
	el.menuIcon.ImageTransparency = if Hud.menuLocked then 0.6 else 0
	if me then
		for _, sp in el.launchSprites do
			Art.colorSprite(sp, me.color)
		end
	end
	-- income by source: rate over the last ~10 s of cumulative totals
	local inc = State.income
	local tnow = os.clock()
	local ib, it = inc.base or 0, inc.trade or 0
	if #incomeHist > 0 and ib < incomeHist[#incomeHist].base then
		incomeHist = {} -- new round
	end
	table.insert(incomeHist, { t = tnow, base = ib, trade = it })
	while #incomeHist > 2 and tnow - incomeHist[1].t > 10 do
		table.remove(incomeHist, 1)
	end
	local h0 = incomeHist[1]
	local span = math.max(tnow - h0.t, 0.5)
	local rb = math.max(0, (ib - h0.base) / span)
	local rt = math.max(0, (it - h0.trade) / span)
	el.income.Text = ("+%s/s"):format(State.fmt(math.floor(rb + rt)))
	el.incomeSub.Text = ("trade +%d/s"):format(math.floor(rt))
	for kind, b in el.buildBtns do
		local cost = State.costFor(kind)
		b.cost.Text = State.fmt(cost)
		local can = me ~= nil and me.alive and me.gold >= cost and phase == "Playing"
		b.cost.TextColor3 = if can then C.Gold else C.Sub
		b.btn.BackgroundColor3 = if State.placing == kind then C.Accent else C.Raise
		b.icon.ImageTransparency = if can or State.placing == kind then 0 else 0.45
	end
	for kind, b in el.launchBtns do
		local L = Hud.LAUNCH[kind]
		local can = me ~= nil and me.alive and me.gold >= L.cost and phase == "Playing"
		b.cost.TextColor3 = if L.cost == 0 then C.Good elseif can then C.Gold else C.Sub
		b.btn.BackgroundColor3 = if Hud.target and Hud.target.mode == "launch" and Hud.target.kind == kind then C.Accent else C.Raise
	end
	el.ratioText.Text = ratioText()
	Hud.refreshTarget()

	-- leaderboard
	local list = {}
	for _, n in State.nations do
		if n.alive and n.land > 0 then
			list[#list + 1] = n
		end
	end
	table.sort(list, function(a, b)
		return if a.land ~= b.land then a.land > b.land else a.id < b.id
	end)
	local myRank = 0
	for k, n in list do
		if n.id == State.me then
			myRank = k
		end
	end
	local share = function(n: any): number
		return if n then n.land / math.max(1, State.claimable) else 0
	end
	local goal = Config.Match.VictoryShare
	local lead = list[1]
	el.rank.Text = if me and myRank > 0 then ("#%d  ·  %.1f%%"):format(myRank, share(me) * 100) else "Spectating"
	el.wcFill.Size = UDim2.fromScale(math.clamp(share(me) / goal, 0, 1), 1)
	el.wcLead.Position = UDim2.fromScale(math.clamp(share(lead) / goal, 0, 1), 0.5)
	el.wcLead.Visible = lead ~= nil and (not me or lead.id ~= State.me)
	el.wcYou.Text = if me then ("You %.1f%%"):format(share(me) * 100) else "Spectating"
	el.wcText.Text = if lead == nil then "No one yet"
		elseif me and lead.id == State.me then "You lead!"
		else ("%s %.1f%%"):format(lead.name, share(lead) * 100)
	for k, row in lbRows do
		local n = list[k]
		if k == #lbRows and myRank > #lbRows then
			n = State.nations[State.me]
		end
		row.frame.Visible = n ~= nil
		row.id = n and n.id
		if n then
			local rank = if n.id == State.me and myRank > 0 then myRank else k
			row.rank.Text = tostring(rank)
			row.sw.BackgroundColor3 = n.color
			row.name.Text = n.name
			row.name.FontFace = if n.id == State.me then F.Heavy else F.Med
			row.name.TextColor3 = if State.allied(n.id) then Color3.fromHex("7CF2B0") else C.Text
			row.land.Text = ("%.1f%%"):format(n.land / State.claimable * 100)
			row.troops.Text = State.fmt(n.troops)
		end
	end

	Hud.refreshRequests()

	-- active fronts (commitments): rebuild only when the set changes
	local key = ""
	for _, a in State.mine do
		key ..= a[1] .. ","
	end
	if key ~= frontKey then
		frontKey = key
		for _, c in frontChips do
			c.chip:Destroy()
		end
		frontChips = {}
		for _, a in State.mine do
			local id, target = a[1], a[2]
			local tn = State.nations[target]
			local chip = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = id, Parent = el.fronts })
			swatch(chip, if tn then tn.color else Color3.fromHex("CFC8B0"), 9).Position = UDim2.fromOffset(2, 6)
			local txt = label({ Text = "", TextSize = 13, RichText = true, Size = UDim2.new(1, -44, 1, 0), Position = UDim2.fromOffset(16, 0), TextTruncate = Enum.TextTruncate.AtEnd, Parent = chip })
			button({ Text = "X", Size = UDim2.fromOffset(20, 18), TextSize = 11, FontFace = F.Heavy, Position = UDim2.new(1, -22, 0, 2) }, function()
				cb("retreat", id)
			end).Parent = chip
			table.insert(frontChips, { chip = chip, text = txt, name = if tn then tn.name else "Neutral" })
		end
	end
	for k, a in State.mine do
		local c = frontChips[k]
		if c then
			c.text.Text = ("%s  <font color=\"#8B98A8\">%s</font>"):format(c.name, State.fmt(a[3]))
		end
	end
	el.attacks.Visible = #State.mine > 0
end

-- alliance cards (bottom-left, above the feed): incoming proposals, renewal requests and
-- "about to expire" prompts. Alliances last Config.Diplomacy.Duration seconds.
local ignored: { [string]: boolean } = {}
local expiryLabels: { any } = {}
function Hud.refreshRequests()
	local now = workspace:GetServerTimeNow()
	local list = {}
	for _, r in State.diplo.requests do
		if r[2] == State.me and r[3] > now then
			list[#list + 1] = { kind = if State.allyState(r[1]) then "renewreq" else "req", id = r[1] }
		end
	end
	for _, p in State.diplo.pairs do
		local other = if p[1] == State.me then p[2] elseif p[2] == State.me then p[1] else nil
		local ends = p[6]
		if other and p[3] == "allied" and ends and ends - now <= Config.Diplomacy.RenewWarn and not ignored[other .. ":" .. math.floor(ends)] then
			local pending = false
			for _, l in list do
				if l.id == other then
					pending = true
				end
			end
			if not pending then
				list[#list + 1] = { kind = "expire", id = other, ends = ends }
			end
		end
	end
	local parts = {}
	for _, l in list do
		parts[#parts + 1] = l.kind .. l.id
	end
	local key = table.concat(parts, ",")
	for _, e in expiryLabels do
		e.label.Text = ("Alliance expires in %ds"):format(math.max(0, math.ceil(e.ends - now)))
	end
	if key == reqKey then
		return
	end
	reqKey = key
	for _, c in reqCards do
		c:Destroy()
	end
	reqCards = {}
	expiryLabels = {}
	for k, l in list do
		local n = State.nations[l.id]
		if n then
			local card = panel({ Size = UDim2.new(1, 0, 0, 58), LayoutOrder = k, Parent = el.reqs })
			swatch(card, n.color, 10).Position = UDim2.fromOffset(10, 10)
			label({ Text = n.name, TextSize = 14, FontFace = F.Bold, TextTruncate = Enum.TextTruncate.AtEnd, Size = UDim2.new(1, -34, 0, 16), Position = UDim2.fromOffset(26, 4), Parent = card })
			local sub = label({ Text = if l.kind == "req" then "proposes an alliance" elseif l.kind == "renewreq" then "wants to renew your alliance" else "", TextSize = 11, TextColor3 = C.Sub, Size = UDim2.new(1, -34, 0, 12), Position = UDim2.fromOffset(26, 19), Parent = card })
			local id = l.id
			if l.kind == "expire" then
				table.insert(expiryLabels, { label = sub, ends = l.ends })
				button({ Text = "Renew", Kind = "primary", BackgroundColor3 = C.Warn, TextSize = 13, Size = UDim2.new(0.5, -12, 0, 22), Position = UDim2.new(0, 8, 0, 32) }, function()
					cb("ally", "request", id)
				end).Parent = card
				button({ Text = "Ignore", TextSize = 13, Size = UDim2.new(0.5, -12, 0, 22), Position = UDim2.new(0.5, 4, 0, 32) }, function()
					ignored[id .. ":" .. math.floor(l.ends)] = true
					reqKey = ""
					Hud.refreshRequests()
				end).Parent = card
			else
				button({ Text = if l.kind == "renewreq" then "Renew" else "Accept", Kind = "primary", BackgroundColor3 = if l.kind == "renewreq" then C.Warn else C.Good, TextSize = 13, Size = UDim2.new(0.5, -12, 0, 22), Position = UDim2.new(0, 8, 0, 32) }, function()
					cb("ally", "accept", id)
				end).Parent = card
				button({ Text = "Decline", TextSize = 13, Size = UDim2.new(0.5, -12, 0, 22), Position = UDim2.new(0.5, 4, 0, 32) }, function()
					cb("ally", "decline", id)
				end).Parent = card
			end
			UI.slideIn(card, -30, 0)
			table.insert(reqCards, card)
		end
	end
end

-- hover tooltip (RoWorld-style): who owns the cell under the cursor and what a click does
function Hud.hover(cell: number?)
	local tip = el.tip
	if not cell then
		tip.Visible = false
		return
	end
	local t = buffer.readu8(State.terrain, cell)
	if t == 0 then
		tip.Visible = false
		return
	end
	local o = State.ownerAt(cell)
	local n = if o ~= 0 then State.nations[o] else nil
	local me = State.nations[State.me]
	local terr = Config.Terrain[t] and Config.Terrain[t].name or ""
	local send = if me then math.floor(me.troops * State.ratio) else 0
	el.tipSwatch.BackgroundColor3 = if n then n.color else Color3.fromHex("CFC8B0")
	if n then
		local ally = State.allied(o)
		local tag = if o == State.me then "YOU" elseif ally then "ALLY" elseif n.kind == "human" then "PLAYER" elseif n.kind == "tribe" then "TRIBE" else "NATION"
		el.tipName.Text = n.name
		el.tipTag.Text = tag
		el.tipTag.TextColor3 = if o == State.me then C.Accent elseif ally then C.Good else C.Sub
		el.tipKind.Text = terr
		el.tipStats.Text = ("Troops <b>%s</b>   Land <b>%.1f%%</b>"):format(State.fmt(n.troops), n.land / math.max(1, State.claimable) * 100)
		el.tipAct.Text = if o == State.me then "Your land  ·  click to inspect"
			elseif ally then "Allied  ·  right-click for actions"
			else ("Click: attack with <b>%s</b>"):format(State.fmt(send))
		el.tipAct.TextColor3 = if o == State.me or ally then C.Sub else C.Bad
	else
		el.tipName.Text = "Neutral land"
		el.tipTag.Text = ""
		el.tipKind.Text = terr .. "  ·  unclaimed"
		el.tipStats.Text = "No defenders"
		el.tipAct.Text = ("Click: expand with <b>%s</b>"):format(State.fmt(send))
		el.tipAct.TextColor3 = C.Good
	end
	el.tipHint.Visible = n ~= nil and o ~= State.me
	local pos = UserInputService:GetMouseLocation() - game:GetService("GuiService"):GetGuiInset()
	local inv = 1 / math.max(scale.Scale, 0.01)
	local vw = gui.AbsoluteSize.X * inv
	local x = pos.X * inv + 18
	if x + 230 > vw then
		x = pos.X * inv - 238
	end
	tip.Position = UDim2.fromOffset(x, pos.Y * inv + 14)
	tip.Visible = true
end

-- map vote cards (thumbnail, name, live count)
Hud.voteCards = {} :: { [string]: any }
Hud.thumb = nil :: ((string, UDim2, Instance) -> ImageLabel)?
function Hud.buildVote(maps: { string })
	for _, c in el.voteRow:GetChildren() do
		if c:IsA("GuiButton") then
			c:Destroy()
		end
	end
	Hud.voteCards = {}
	for _, id in maps do
		local def = Config.Maps[id]
		local b = button({ Text = "", Size = UDim2.fromOffset(170, 136), BackgroundColor3 = C.Panel }, function()
			cb("vote", id)
			for mid, vc in Hud.voteCards do
				vc.stroke.Color = if mid == id then C.Accent else C.Stroke
				vc.stroke.Thickness = if mid == id then 3 else 1
			end
		end)
		local st = b:FindFirstChildOfClass("UIStroke") :: UIStroke
		if Hud.thumb then
			Hud.thumb(id, UDim2.new(1, -12, 0, 78), b).Position = UDim2.fromOffset(6, 6)
		end
		label({ Text = def.Name, TextSize = 15, FontFace = F.Bold, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 88), Parent = b })
		local cnt = label({ Text = "0 votes", TextSize = 12, TextColor3 = C.Sub, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 110), Parent = b })
		b.Parent = el.voteRow
		Hud.voteCards[id] = { stroke = st, count = cnt }
	end
end

function Hud.setVotes(counts: { [string]: number })
	for id, vc in Hud.voteCards do
		local n = counts[id] or 0
		vc.count.Text = ("%d vote%s"):format(n, if n == 1 then "" else "s")
		UI.popIn(vc.count, 0.7)
	end
end

function Hud.showResults(r: any)
	State.results = r
	local box = el.results
	for _, c in el.resRows:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	local w = nil
	for _, row in r.rows do
		if row.id == r.winner then
			w = row
		end
	end
	el.resTitle.Text = if w then (w.name .. " takes the world!") else "Round over"
	local mine = nil
	for _, row in r.rows do
		if row.id == State.me then
			mine = row
		end
	end
	local won = w ~= nil and w.id == State.me
	local word, top, bot = "ROUND OVER", Color3.new(1, 1, 1), Color3.fromHex("C8D2EE")
	if won then
		word, bot = "VICTORY", Color3.new(1.0, 0.8, 0.4)
	elseif w and mine then
		word, bot = if mine.alive then "DEFEAT" else "ELIMINATED", Color3.fromHex("FF8C8C")
	elseif tostring(r.reason):lower():find("time") then
		word, bot = "TIME UP", Color3.fromHex("8FE1FF")
	end
	for _, c in el.resHead:GetChildren() do
		c:Destroy()
	end
	local hw, setPx = UI.wordmark(word, el.resHead, { Top = top, Bottom = bot, Spacing = 10 })
	hw.AnchorPoint = Vector2.new(0.5, 0)
	hw.Position = UDim2.fromScale(0.5, 0)
	setPx(52)
	el.resTiles[1].Text = if mine then ("#%d"):format(mine.place) else "-"
	el.resTiles[2].Text = if mine then ("%.1f%%"):format(mine.peak * 100) else "-"
	el.resTiles[3].Text = if mine then tostring(mine.captured) else "-"
	el.resTiles[4].Text = if mine then tostring(mine.eliminated) else "-"
	el.resSub.Text = ("Ended by %s  ·  %02d:%02d%s"):format(r.reason, r.duration // 60, math.floor(r.duration % 60), if Hud.lastCoins then ("  ·  You earned %s"):format(Hud.lastCoins:sub(2)) else "")
	el.resSub.RichText = false
	Hud.lastCoins = nil
	for k, row in r.rows do
		if k > 10 and row.id ~= State.me then
			continue
		end
		local f = make("Frame", { BackgroundColor3 = if row.id == State.me then C.Accent:Lerp(C.Bg, 0.82) else C.Raise, BackgroundTransparency = if row.id == State.me then 0 else 0.5, Size = UDim2.new(1, -6, 0, 26), LayoutOrder = row.place, Parent = el.resRows }, { UI.corner(UI.R.sm) })
		label({ Text = "#" .. row.place, TextSize = 14, FontFace = F.Bold, Size = UDim2.fromOffset(34, 24), Position = UDim2.fromOffset(6, 0), Parent = f })
		swatch(f, Color3.fromHex(row.color), 12).Position = UDim2.fromOffset(40, 6)
		label({ Text = row.name .. (if row.alive then "" else "  (out)"), TextSize = 14, Size = UDim2.new(0.42, 0, 1, 0), Position = UDim2.fromOffset(58, 0), Parent = f })
		label({
			Text = ("peak %.1f%%   taken %d   KOs %d"):format(row.peak * 100, row.captured, row.eliminated),
			TextSize = 13,
			TextColor3 = C.Sub,
			TextXAlignment = Enum.TextXAlignment.Right,
			Size = UDim2.new(0.5, -10, 1, 0),
			Position = UDim2.new(0.5, 0, 0, 0),
			Parent = f,
		})
	end
	box.Visible = true
	UI.popIn(box, 0.8)
	Hud.buildVote(r.vote or {})
	el.voteTitle.Visible = r.vote ~= nil and #r.vote > 0
end

function Hud.hideResults()
	el.results.Visible = false
end

function Hud.isSliderDragging(): boolean
	return draggingSlider
end

function Hud.init(): ScreenGui
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = make("ScreenGui", { Name = "HUD", ResetOnSpawn = false, IgnoreGuiInset = false, ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets, DisplayOrder = 5, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
	scale = make("UIScale", { Parent = gui })
	local function rescale()
		local cam = workspace.CurrentCamera
		local v = cam and cam.ViewportSize or Vector2.new(1280, 720)
		scale.Scale = math.clamp(math.min(v.X / 1210, v.Y / 680), 0.55, 1.2)
	end
	rescale()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	end

	-- top-left icon bar: menu, music, sound effects, how to play, leaderboard
	local icons = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(8, 6), Size = UDim2.fromOffset(0, 36), AutomaticSize = Enum.AutomaticSize.X, Parent = gui })
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = icons })
	local function iconBtn(icon: string, order: number, tip: string, onClick: () -> ()): (TextButton, ImageLabel)
		local b = button({ Text = "", Size = UDim2.fromOffset(36, 36), LayoutOrder = order, BackgroundColor3 = C.Bg, BackgroundTransparency = UI.BgT }, onClick)
		b:SetAttribute("Tip", tip)
		local ic = Icons.label(icon, 20, b)
		ic.AnchorPoint = Vector2.new(0.5, 0.5)
		ic.Position = UDim2.fromScale(0.5, 0.5)
		b.Parent = icons
		return b, ic
	end
	el.menuBtn, el.menuIcon = iconBtn("exit", 1, "Menu", function()
		if Hud.menuLocked then
			Hud.toast("The menu unlocks when the round has a winner", "bad")
			return
		end
		cb("menu")
	end)
	local function muteBtn(icon: string, order: number, get: () -> boolean, set: (boolean) -> ())
		local b, ic
		b, ic = iconBtn(icon, order, if icon == "music" then "Music" else "Sound effects", function()
			set(not get())
			Audio.play("click")
		end)
		local slash = make("Frame", { BackgroundColor3 = C.Bad, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(26, 3), Rotation = -45, Visible = false, ZIndex = 3, Parent = b })
		local function sync()
			slash.Visible = not get()
			ic.ImageTransparency = if get() then 0 else 0.5
		end
		sync()
		table.insert(Audio.changed, sync)
	end
	muteBtn("music", 2, function()
		return Audio.musicOn
	end, Audio.setMusic)
	muteBtn("sound", 3, function()
		return Audio.sfxOn
	end, Audio.setSfx)
	iconBtn("help", 4, "How to play", function()
		cb("tutorial")
	end)
	iconBtn("board", 5, "Leaderboard", function()
		el.lb.Visible = not el.lb.Visible
	end)

	-- top centre: match time + WORLD CONTROL race to the goal
	-- (RoWorld's status pill: clock block | world-control block with a 7 px amber bar, you vs the leader)
	local wc = panel({ Name = "TopStatus", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.fromOffset(470, 60), Parent = gui })
	el.phase = UI.caption("Match time", { Size = UDim2.fromOffset(88, 12), Position = UDim2.fromOffset(18, 11), Parent = wc })
	el.time = label({ Text = "00:00", TextSize = 22, FontFace = F.Bold, Size = UDim2.fromOffset(88, 26), Position = UDim2.fromOffset(18, 25), Parent = wc })
	UI.divider({ Size = UDim2.new(0, 1, 1, -20), Position = UDim2.fromOffset(114, 10), Parent = wc })
	local gi = Icons.label("globe", 12, wc)
	gi.Position = UDim2.fromOffset(130, 10)
	UI.caption("World control", { Size = UDim2.fromOffset(160, 12), Position = UDim2.fromOffset(148, 10), Parent = wc })
	UI.caption(("Goal %d%%"):format(math.floor(Config.Match.VictoryShare * 100 + 0.5)), { TextColor3 = C.Gold, TextXAlignment = Enum.TextXAlignment.Right, Size = UDim2.fromOffset(100, 12), Position = UDim2.new(1, -118, 0, 10), Parent = wc })
	local track = make("Frame", { BackgroundColor3 = C.Line, BackgroundTransparency = 0.9, BorderSizePixel = 0, Size = UDim2.new(1, -148, 0, 7), Position = UDim2.fromOffset(130, 27), Parent = wc }, { UI.corner(4) })
	el.wcFill = make("Frame", { BackgroundColor3 = C.Accent, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), Parent = track }, { UI.corner(4) })
	make("UIGradient", { Color = ColorSequence.new(C.AccentLo, C.AccentHi), Parent = el.wcFill })
	el.wcLead = make("Frame", { BackgroundColor3 = C.Gold, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(3, 13), Position = UDim2.fromScale(0, 0.5), ZIndex = 2, Parent = track }, { UI.corner(2) })
	el.wcYou = label({ Text = "You 0.0%", TextSize = 12, FontFace = F.Semi, Size = UDim2.fromOffset(120, 14), Position = UDim2.fromOffset(130, 39), Parent = wc })
	local leadBox = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 39), Size = UDim2.new(1, -290, 0, 14), Parent = wc })
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder, Parent = leadBox })
	Icons.label("crown", 12, leadBox).LayoutOrder = 1
	el.wcText = label({ Text = "", TextSize = 12, FontFace = F.Semi, TextColor3 = C.Sub, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 14), LayoutOrder = 2, Parent = leadBox })

	-- banner + toast
	el.banner = panel({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 76), Size = UDim2.fromOffset(0, 32), AutomaticSize = Enum.AutomaticSize.X, Visible = false, Active = false, Parent = gui })
	make("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), Parent = el.banner })
	el.bannerText = label({ Text = "", TextSize = 17, FontFace = F.Bold, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1), Parent = el.banner })
	local toastBox = panel({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 114), Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, Visible = false, Active = false, Parent = gui })
	make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), Parent = toastBox })
	el.toast = label({ Text = "", TextSize = 15, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1), Parent = toastBox })

	-- top right: rank pill, leaderboard, active attacks
	local right = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 6), Size = UDim2.fromOffset(230, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = gui })
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Right, Parent = right })
	-- rank pill opens / closes the leaderboard (closed at the start of every match)
	local pill = button({ Text = "", Size = UDim2.fromOffset(0, 28), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 1, BackgroundColor3 = C.Bg, BackgroundTransparency = UI.BgT }, function()
		el.lb.Visible = not el.lb.Visible
	end)
	pill:SetAttribute("Tip", "Leaderboard")
	pill.Parent = right
	make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), Parent = pill })
	el.rank = label({ Text = "", TextSize = 14, FontFace = F.Bold, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1), Parent = pill })
	local lb = panel({ Size = UDim2.fromOffset(230, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Visible = false, Parent = right })
	el.lb = lb
	make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = lb })
	UI.pad(8).Parent = lb
	label({ Text = "LEADERBOARD", TextSize = 10, FontFace = F.Bold, TextColor3 = C.Sub, Size = UDim2.new(1, 0, 0, 14), LayoutOrder = 0, Parent = lb })
	for k = 1, 8 do
		local f = make("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = C.Raise, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 19), LayoutOrder = k, Parent = lb }, { UI.corner(4) })
		local row: any
		f.MouseEnter:Connect(function()
			f.BackgroundTransparency = 0.4
		end)
		f.MouseLeave:Connect(function()
			f.BackgroundTransparency = 1
		end)
		f.Activated:Connect(function()
			if row.id then
				cb("focus", row.id)
			end
		end)
		row = {
			frame = f,
			rank = label({ Text = "", TextSize = 12, TextColor3 = C.Sub, Size = UDim2.fromOffset(18, 19), Parent = f }),
			sw = swatch(f, C.Text, 9),
			name = label({ Text = "", TextSize = 13, Size = UDim2.new(1, -116, 1, 0), Position = UDim2.fromOffset(34, 0), TextTruncate = Enum.TextTruncate.AtEnd, Parent = f }),
			land = label({ Text = "", TextSize = 12, TextColor3 = C.Good, TextXAlignment = Enum.TextXAlignment.Right, Size = UDim2.fromOffset(42, 19), Position = UDim2.new(1, -86, 0, 0), Parent = f }),
			troops = label({ Text = "", TextSize = 12, TextColor3 = C.Sub, TextXAlignment = Enum.TextXAlignment.Right, Size = UDim2.fromOffset(42, 19), Position = UDim2.new(1, -42, 0, 0), Parent = f }),
		}
		row.sw.Position = UDim2.fromOffset(20, 5)
		lbRows[k] = row
	end
	local atk = panel({ Size = UDim2.fromOffset(230, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3, Visible = false, Parent = right })
	el.attacks = atk
	make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = atk })
	UI.pad(8).Parent = atk
	label({ Text = "ATTACKS", TextSize = 10, FontFace = F.Bold, TextColor3 = C.Sub, Size = UDim2.new(1, 0, 0, 14), LayoutOrder = 0, Parent = atk })
	el.fronts = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = atk })
	make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = el.fronts })

	-- bottom-left: alliance cards above the event feed (cards)
	local bl = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 8, 1, -80), Size = UDim2.fromOffset(290, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = gui })
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Bottom, Parent = bl })
	el.reqs = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = bl })
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = el.reqs })
	local feedBox = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Parent = bl })
	make("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Bottom, Parent = feedBox })
	for k = 1, 5 do
		local f = panel({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = -k, Visible = false, Active = false, Parent = feedBox })
		local bar = make("Frame", { BackgroundColor3 = C.Accent, BorderSizePixel = 0, Size = UDim2.new(0, 3, 1, -8), Position = UDim2.fromOffset(5, 4), Parent = f }, { UI.corner(2) })
		local txt = label({ Text = "", TextSize = 12, FontFace = F.Med, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, -22, 0, 14), Position = UDim2.fromOffset(14, 5), Parent = f })
		make("UIPadding", { PaddingBottom = UDim.new(0, 5), Parent = f })
		feedRows[k] = { frame = f, bar = bar, text = txt }
	end

	-- bottom command bar: me | troops | attack % | gold | build | launch | shop
	local cmd = panel({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -6), Size = UDim2.fromOffset(0, 66), AutomaticSize = Enum.AutomaticSize.X, Parent = gui })
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = cmd })
	make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 6), Parent = cmd })
	local function section(order: number, w: number): Frame
		return make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(w, 56), LayoutOrder = order, Parent = cmd })
	end
	local function divider(order: number)
		make("Frame", { BackgroundColor3 = C.Stroke, BorderSizePixel = 0, Size = UDim2.fromOffset(1, 44), LayoutOrder = order, Parent = cmd })
	end
	local s1 = section(1, 118)
	el.meSwatch = swatch(s1, C.Accent, 10)
	el.meSwatch.Position = UDim2.fromOffset(0, 12)
	el.meName = label({ Text = "", TextSize = 14, FontFace = F.Heavy, TextTruncate = Enum.TextTruncate.AtEnd, Size = UDim2.new(1, -14, 0, 18), Position = UDim2.fromOffset(14, 8), Parent = s1 })
	el.land = label({ Text = "", TextSize = 11, TextColor3 = C.Sub, Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 28), Parent = s1 })
	divider(2)
	local s2 = section(3, 116)
	label({ Text = "TROOPS", TextSize = 10, FontFace = F.Bold, TextColor3 = C.Sub, Size = UDim2.new(1, 0, 0, 12), Position = UDim2.fromOffset(0, 6), Parent = s2 })
	el.troops = label({ Text = "-", RichText = true, TextSize = 15, FontFace = F.Heavy, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 19), Parent = s2 })
	local tbar = make("Frame", { BackgroundColor3 = C.Raise, BorderSizePixel = 0, Size = UDim2.new(1, -6, 0, 4), Position = UDim2.fromOffset(0, 41), Parent = s2 }, { UI.corner(2) })
	el.troopBar = make("Frame", { BackgroundColor3 = C.Info, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), Parent = tbar }, { UI.corner(2) })
	divider(4)
	local s3 = section(5, 176)
	label({ Text = "ATTACK", TextSize = 10, FontFace = F.Bold, TextColor3 = C.Sub, Size = UDim2.fromOffset(60, 12), Position = UDim2.fromOffset(0, 6), Parent = s3 })
	el.ratioText = label({ Text = "", RichText = true, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right, Size = UDim2.new(1, -50, 0, 14), Position = UDim2.fromOffset(46, 5), Parent = s3 })
	local rtrack = make("Frame", { BackgroundColor3 = C.Raise, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 3), Position = UDim2.fromOffset(0, 22), Parent = s3 }, { UI.corner(2) })
	el.ratioFill = make("Frame", { BackgroundColor3 = C.Accent, BorderSizePixel = 0, Size = UDim2.fromScale(0.25, 1), Parent = rtrack }, { UI.corner(2) })
	local chips = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 30), Parent = s3 })
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 3), Parent = chips })
	el.chips = {}
	for _, pct in { 10, 25, 50, 75, 100 } do
		el.chips[pct] = button({ Text = pct .. "%", TextSize = 11, FontFace = F.Bold, Size = UDim2.new(0.2, -3, 1, 0) }, function()
			Hud.setRatio(pct / 100)
		end)
		el.chips[pct].Parent = chips
	end
	divider(6)
	local s4 = section(7, 84)
	label({ Text = "GOLD", TextSize = 10, FontFace = F.Bold, TextColor3 = C.Sub, Size = UDim2.new(1, 0, 0, 12), Position = UDim2.fromOffset(0, 6), Parent = s4 })
	el.gold = label({ Text = "-", TextSize = 16, FontFace = F.Heavy, TextColor3 = C.Gold, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 19), Parent = s4 })
	el.income = label({ Text = "", TextSize = 11, FontFace = F.Bold, TextColor3 = C.Good, Size = UDim2.new(1, 0, 0, 12), Position = UDim2.fromOffset(0, 38), Parent = s4 })
	el.incomeSub = label({ Text = "", TextSize = 1, Visible = false, Parent = s4 })
	divider(8)
	local function tool(order: number, keyText: string, tipText: string, onClick: () -> ()): (TextButton, TextLabel)
		local b = button({ Text = "", Size = UDim2.fromOffset(42, 56), LayoutOrder = order }, onClick)
		b:SetAttribute("Tip", tipText)
		if keyText ~= "" then
			label({ Text = keyText, TextSize = 9, FontFace = F.Bold, TextColor3 = C.Sub, Size = UDim2.fromOffset(10, 10), Position = UDim2.fromOffset(3, 2), Parent = b })
		end
		local cost = label({ Text = "", TextSize = 10, FontFace = F.Bold, TextColor3 = C.Gold, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 1, -14), Parent = b })
		b.Parent = cmd
		return b, cost
	end
	el.buildBtns = {}
	for k, kind in Config.StructureOrder do
		local d = Config.Structures[kind]
		local b, cost = tool(10 + k, tostring(k), d.name, function()
			cb("buildMode", kind)
		end)
		local ic = Icons.label(kind, 24, b)
		ic.AnchorPoint = Vector2.new(0.5, 0)
		ic.Position = UDim2.new(0.5, 0, 0, 10)
		el.buildBtns[kind] = { btn = b, cost = cost, icon = ic }
	end
	divider(30)
	el.launchSprites = {}
	el.launchBtns = {}
	for k, kind in Hud.LAUNCH_ORDER do
		local L = Hud.LAUNCH[kind]
		local b, cost = tool(30 + k, "", "Launch " .. L.name, function()
			cb("launchMode", kind)
		end)
		cost.Text = if L.cost > 0 then State.fmt(L.cost) else "FREE"
		local sp = Art.spriteFrame(L.sprite, nil, b)
		sp.frame.AnchorPoint = Vector2.new(0.5, 0)
		sp.frame.Position = UDim2.new(0.5, 0, 0, 6)
		sp.frame.Size = UDim2.fromOffset(32, 32)
		el.launchSprites[kind] = sp
		el.launchBtns[kind] = { btn = b, cost = cost }
	end
	local shopBtn = button({ Text = "", BackgroundColor3 = C.Gold, Size = UDim2.fromOffset(56, 56), LayoutOrder = 50 }, function()
		cb("shop")
	end)
	local coin = Art.coinLabel(26, shopBtn)
	coin.AnchorPoint = Vector2.new(0.5, 0)
	coin.Position = UDim2.new(0.5, 0, 0, 6)
	label({ Text = "SHOP", TextSize = 13, FontFace = F.Heavy, TextColor3 = C.Bg, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 1, -18), Parent = shopBtn })
	shopBtn.Parent = cmd

	-- name tooltip for icon / tool buttons
	local btip = panel({ AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, Visible = false, Active = false, ZIndex = 30, Parent = gui })
	make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = btip })
	local btipText = label({ Text = "", TextSize = 13, FontFace = F.Bold, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1), ZIndex = 30, Parent = btip })
	for _, d in gui:GetDescendants() do
		if d:IsA("GuiButton") and d:GetAttribute("Tip") then
			d.MouseEnter:Connect(function()
				btipText.Text = d:GetAttribute("Tip")
				local inv = 1 / math.max(scale.Scale, 0.01)
				local p = d.AbsolutePosition
				local top = p.Y < 100
				btip.AnchorPoint = if top then Vector2.new(0, 0) else Vector2.new(0.5, 1)
				btip.Position = if top then UDim2.fromOffset(p.X * inv, (p.Y + d.AbsoluteSize.Y) * inv + 6) else UDim2.fromOffset((p.X + d.AbsoluteSize.X / 2) * inv, p.Y * inv - 6)
				btip.Visible = true
			end)
			d.MouseLeave:Connect(function()
				btip.Visible = false
			end)
		end
	end

	-- hover tooltip over the map
	local tip = panel({ Size = UDim2.fromOffset(220, 0), AutomaticSize = Enum.AutomaticSize.Y, Visible = false, Active = false, ZIndex = 25, Parent = gui })
	el.tip = tip
	make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = tip })
	UI.pad(8).Parent = tip
	local head = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 1, ZIndex = 25, Parent = tip })
	el.tipSwatch = swatch(head, C.Text, 10)
	el.tipSwatch.Position = UDim2.fromOffset(0, 4)
	el.tipSwatch.ZIndex = 25
	el.tipName = label({ Text = "", TextSize = 15, FontFace = F.Heavy, TextTruncate = Enum.TextTruncate.AtEnd, Size = UDim2.new(1, -70, 1, 0), Position = UDim2.fromOffset(16, 0), ZIndex = 25, Parent = head })
	el.tipTag = label({ Text = "", TextSize = 10, FontFace = F.Heavy, TextXAlignment = Enum.TextXAlignment.Right, Size = UDim2.fromOffset(52, 18), Position = UDim2.new(1, -52, 0, 0), ZIndex = 25, Parent = head })
	el.tipKind = label({ Text = "", TextSize = 11, TextColor3 = C.Sub, Size = UDim2.new(1, 0, 0, 13), LayoutOrder = 2, ZIndex = 25, Parent = tip })
	el.tipStats = label({ Text = "", RichText = true, TextSize = 12, Size = UDim2.new(1, 0, 0, 15), LayoutOrder = 3, ZIndex = 25, Parent = tip })
	el.tipAct = label({ Text = "", RichText = true, TextSize = 12, FontFace = F.Bold, Size = UDim2.new(1, 0, 0, 15), LayoutOrder = 4, ZIndex = 25, Parent = tip })
	el.tipHint = label({ Text = "Right-click for more actions", TextSize = 10, TextColor3 = C.Sub, Size = UDim2.new(1, 0, 0, 12), LayoutOrder = 5, ZIndex = 25, Parent = tip })

	-- selected target panel (bottom-right, above the command bar)
	local tp = panel({ AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -8, 1, -80), Size = UDim2.fromOffset(270, 168), Visible = false, Parent = gui })
	el.target = tp
	el.tSwatch = swatch(tp, C.Text, 14)
	el.tSwatch.Position = UDim2.fromOffset(12, 14)
	el.tName = label({ Text = "", TextSize = 18, FontFace = F.Bold, Size = UDim2.new(1, -134, 0, 22), Position = UDim2.fromOffset(32, 10), TextTruncate = Enum.TextTruncate.AtEnd, Parent = tp })
	el.tKind = label({ Text = "", TextSize = 13, TextColor3 = C.Sub, Size = UDim2.new(1, -24, 0, 16), Position = UDim2.fromOffset(12, 34), Parent = tp })
	el.tStats = label({ Text = "", RichText = true, TextSize = 14, Size = UDim2.new(1, -24, 0, 18), Position = UDim2.fromOffset(12, 54), Parent = tp })
	el.tCommit = label({ Text = "", RichText = true, TextSize = 14, TextColor3 = C.Accent, Size = UDim2.new(1, -24, 0, 18), Position = UDim2.fromOffset(12, 74), Parent = tp })
	el.tWhy = label({ Text = "", TextSize = 13, TextColor3 = C.Bad, TextWrapped = true, Size = UDim2.new(1, -24, 0, 30), Position = UDim2.fromOffset(12, 92), Parent = tp })
	el.tAlly = button({ Text = "Propose ally", TextSize = 12, Size = UDim2.fromOffset(84, 22), Position = UDim2.new(1, -94, 0, 10), Visible = false }, function()
		local a, t = el.tAlly:GetAttribute("Action"), el.tAlly:GetAttribute("Target")
		if a == "airMode" then
			cb("airMode")
		elseif a and a ~= "" and t then
			cb("ally", a, t)
		end
	end)
	el.tAlly.Parent = tp
	el.tIcon = make("ImageLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(18, 18), Position = UDim2.fromOffset(10, 12), ZIndex = 2, Visible = false, Parent = tp })
	el.tAttack = button({ Text = "ATTACK  (Space)", Kind = "primary", Size = UDim2.new(0.62, -14, 0, 36), Position = UDim2.new(0, 12, 1, -46) }, function()
		cb("primary")
	end)
	el.tAttack.Parent = tp
	el.tCancel = button({ Text = "Cancel (X)", TextSize = 14, Size = UDim2.new(0.38, -10, 0, 36), Position = UDim2.new(0.62, 4, 1, -46) }, function()
		cb("cancel")
	end)
	el.tCancel.Parent = tp

	-- results modal
	local res = panel({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(620, 640), Visible = false, BackgroundColor3 = C.Panel, BackgroundTransparency = 0.03, Radius = 18, ZIndex = 20, Parent = gui })
	el.results = res
	-- RoWorld-style game over: a gradient headline, the winner, your stat tiles, the standings
	el.resHead = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 64), Position = UDim2.fromOffset(0, 14), Parent = res })
	el.resTitle = label({ Text = "", TextSize = 18, FontFace = F.Bold, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 80), Parent = res })
	el.resSub = label({ Text = "", TextSize = 13, FontFace = F.Med, TextColor3 = C.Sub, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 104), Parent = res })
	local tiles = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -32, 0, 60), Position = UDim2.fromOffset(16, 130), Parent = res })
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = tiles })
	el.resTiles = {}
	for i, t in { { "Place", C.Accent }, { "Peak land", C.Info }, { "Cells taken", C.Gold }, { "Eliminations", C.Bad } } do
		local tf = make("Frame", { BackgroundColor3 = C.Raise, BackgroundTransparency = 0.2, BorderSizePixel = 0, Size = UDim2.new(0.25, -6, 1, 0), LayoutOrder = i, Parent = tiles }, { UI.corner(UI.R.md), UI.stroke() })
		make("Frame", { BackgroundColor3 = t[2], BorderSizePixel = 0, Size = UDim2.new(0, 3, 1, -20), Position = UDim2.fromOffset(0, 10), Parent = tf })
		UI.caption(t[1], { Size = UDim2.new(1, -24, 0, 12), Position = UDim2.fromOffset(14, 11), Parent = tf })
		el.resTiles[i] = label({ Text = "-", TextSize = 20, FontFace = F.Bold, TextColor3 = t[2], Size = UDim2.new(1, -24, 0, 24), Position = UDim2.fromOffset(14, 26), Parent = tf })
	end
	el.voteTitle = label({ Text = "VOTE FOR THE NEXT MAP", TextSize = 13, FontFace = F.Bold, TextColor3 = C.Sub, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 1, -208), Parent = res })
	el.voteRow = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -32, 0, 136), Position = UDim2.new(0, 16, 1, -188), Parent = res })
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 10), Parent = el.voteRow })
	el.resRows = make("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, -32, 1, -428), Position = UDim2.fromOffset(16, 202), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4, Parent = res })
	make("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder, Parent = el.resRows })
	local queued = true
	local rq
	rq = button({ Text = "✓ Queued for next round", Kind = "primary", Size = UDim2.new(0.5, -22, 0, 40), Position = UDim2.new(0, 16, 1, -54) }, function()
		queued = not queued
		rq.Text = if queued then "✓ Queued for next round" else "Spectate next round"
		rq.BackgroundColor3 = if queued then C.Accent else C.Raise
		rq.TextColor3 = if queued then C.Bg else C.Text
		cb("requeue", queued)
	end)
	rq.Parent = res
	el.requeue = rq
	button({ Text = "View map", Size = UDim2.new(0.5, -22, 0, 40), Position = UDim2.new(0.5, 6, 1, -54) }, function()
		Hud.hideResults()
	end).Parent = res

	gui.Parent = pg
	Hud.setRatio(State.ratio)
	return gui
end

return Hud
