--!strict
-- Title screen, rebuilt to RoWorld's layout (our own code and art): the live pixel world behind a
-- vignette, an emblem, the shining gradient wordmark and a "CONQUER THE REAL WORLD" tag line up
-- top, and one frosted-glass dock at the bottom centre: a greeting, PLAY SOLO, a PUBLIC MATCHES
-- rule, the public-match card (quick play on the chosen map) and How to Play. PLAY SOLO turns the
-- dock into the solo panel (map button, Relaxed / Standard / Brutal chips, START); the map button
-- opens the map picker. The SHOP button sits top right, level with the wordmark.
-- Map thumbnails are drawn on the client from the shared map data (no image uploads).
local AssetService = game:GetService("AssetService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local MapGen = require(ReplicatedStorage.Shared.MapGen)
local UI = require(script.Parent.UI)
local Audio = require(script.Parent.Audio)
local Icons = require(script.Parent.Icons)

local C, F = UI.C, UI.F
local make, label, button, panel = UI.make, UI.label, UI.button, UI.panel

local Menu = {}
Menu.onClose = nil :: (() -> ())?
Menu.onOpen = nil :: (() -> ())?
Menu.onShop = nil :: (() -> ())?
Menu.onTutorial = nil :: (() -> ())?
Menu.toast = nil :: ((string, string?) -> ())?

local gui: ScreenGui
local remote: RemoteFunction
local selected = Config.MapOrder[1]
local difficulty = 1
local thumbs: { [string]: EditableImage } = {}
local el: { [string]: any } = {}
local busy = false

local function call(action: string, arg: any): (boolean, any)
	local ok, a, b = pcall(remote.InvokeServer, remote, action, arg or {})
	if not ok then
		return false, "Network error"
	end
	return a, b
end

-- small terrain thumbnail rendered from the map module
local function thumbFor(mapId: string): EditableImage?
	if thumbs[mapId] then
		return thumbs[mapId]
	end
	local def = if mapId == "__bg" then Config.Maps.earth else Config.Maps[mapId]
	if not def or not def.Module then
		return nil
	end
	local mod = ReplicatedStorage.Shared.Maps:FindFirstChild(def.Module)
	if not mod or not mod:IsA("ModuleScript") then
		return nil
	end
	local m = require(mod) :: any
	local terr = MapGen.decodeModule(m)
	local lookMod = ReplicatedStorage.Shared.Maps:FindFirstChild(def.Module .. "Look")
	local look: any = if lookMod then require(lookMod :: ModuleScript) else nil
	local lookCols: { { number } } = {}
	if look then
		for k, hx in look.pal do
			local c = Color3.fromHex(hx)
			lookCols[k - 1] = { math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255) }
		end
	end
	local DIG = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-_"
	local MAX = if mapId == "__bg" then 512 else 160
	local TW = MAX
	local TH = math.max(1, math.floor(TW * m.h / m.w))
	if TH > MAX then
		TH = MAX
		TW = math.floor(MAX * m.w / m.h)
	end
	local ok, img = pcall(function()
		return AssetService:CreateEditableImage({ Size = Vector2.new(TW, TH) })
	end)
	if not ok or not img then
		return nil
	end
	local b = buffer.create(TW * TH * 4)
	local cols = {
		[0] = { 22, 33, 44 },
		[1] = { 207, 200, 176 },
		[2] = { 181, 173, 150 },
		[3] = { 149, 143, 128 },
		[4] = { 235, 240, 245 },
		[5] = { 222, 196, 140 },
	}
	for y = 0, TH - 1 do
		local cy = math.floor((y + 0.5) * m.h / TH)
		for x = 0, TW - 1 do
			local cx = math.floor((x + 0.5) * m.w / TW)
			local c = cols[buffer.readu8(terr, cy * m.w + cx)] or cols[0]
			if look then
				local ch = string.sub(look.px, cy * m.w + cx + 1, cy * m.w + cx + 1)
				c = lookCols[(string.find(DIG, ch, 1, true) or 1) - 1] or c
			end
			local o = (y * TW + x) * 4
			buffer.writeu8(b, o, c[1])
			buffer.writeu8(b, o + 1, c[2])
			buffer.writeu8(b, o + 2, c[3])
			buffer.writeu8(b, o + 3, 255)
		end
	end
	img:WritePixelsBuffer(Vector2.zero, Vector2.new(TW, TH), b)
	thumbs[mapId] = img
	return img
end

local function thumbLabel(mapId: string, size: UDim2, parent: Instance): ImageLabel
	local l = make("ImageLabel", {
		BackgroundColor3 = Color3.fromHex("16212C"),
		BorderSizePixel = 0,
		Size = size,
		ScaleType = Enum.ScaleType.Fit,
		Parent = parent,
	}, { UI.corner(6) })
	local img = thumbFor(mapId)
	if img then
		l.ImageContent = Content.fromObject(img)
	end
	return l
end

Menu.thumbLabel = thumbLabel

local function setThumb(l: ImageLabel, mapId: string)
	local img = thumbFor(mapId)
	if img then
		l.ImageContent = Content.fromObject(img)
	end
end

-- a centred row: [icon] TEXT inside a button (the button's own Text stays empty)
local function iconText(b: TextButton, icon: string, text: string, size: number, col: Color3, iconPx: number?): TextLabel
	local row = make("Frame", { Name = "Content", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, size + 6), Parent = b })
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Parent = row })
	local ic = Icons.label(icon, iconPx or 18, row)
	ic.LayoutOrder = 1
	ic.ImageColor3 = if col == C.Ink then Color3.fromHex("2A1A06") else Color3.new(1, 1, 1)
	local t = label({ Text = text, TextSize = size, FontFace = b.FontFace, TextColor3 = col, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, size + 6), LayoutOrder = 2, Parent = row })
	b.Text = ""
	return t
end

-- fade + slide a CanvasGroup in or out
local function show(g: CanvasGroup, on: boolean, dy: number?)
	local home = g:GetAttribute("Home") :: UDim2?
	if not home then
		home = g.Position
		g:SetAttribute("Home", home)
	end
	local h = home :: UDim2
	local off = UDim2.new(h.X.Scale, h.X.Offset, h.Y.Scale, h.Y.Offset + (dy or 16))
	if on then
		g.Visible = true
		g.GroupTransparency = 1
		g.Position = off
		UI.tween(g, 0.28, { GroupTransparency = 0, Position = h }, Enum.EasingStyle.Quint)
	else
		local tw = UI.tween(g, 0.18, { GroupTransparency = 1, Position = off })
		tw.Completed:Connect(function(st)
			if st == Enum.PlaybackState.Completed then
				g.Visible = false
			end
		end)
	end
end

local function refreshDiff()
	for i, set in el.chipSet do
		set(i - 1 == difficulty)
	end
	el.diffDesc.Text = Config.Difficulty[difficulty].Blurb
end

local function selectMap(id: string)
	selected = id
	local def = Config.Maps[id]
	el.mapText.Text = "Map:  " .. def.Name
	el.pubTitle.Text = "PUBLIC MATCH  ·  " .. string.upper(def.Name)
	setThumb(el.pubThumb, id)
	for mid, c in el.mapCards do
		c.stroke.Color = if mid == id then C.Accent else C.Line
		c.stroke.Transparency = if mid == id then 0 else UI.LineT
		c.check.Visible = mid == id
	end
	if el.lastInfo then
		Menu.status(el.lastInfo)
	end
end

-- the public card's status line from the server list
function Menu.status(info: any)
	el.lastInfo = info
	if busy then
		return
	end
	local live, playing = 0, 0
	local rows = { info.here }
	for _, s in info.servers or {} do
		table.insert(rows, s)
	end
	for _, s in rows do
		if s.map == selected and not s.solo then
			live += 1
			playing += s.players
		end
	end
	if live > 0 then
		el.pubStatus.Text = ("%d live  ·  %d playing"):format(live, playing)
		el.pubDot.BackgroundColor3 = C.Good
	else
		el.pubStatus.Text = "Starts a new match"
		el.pubDot.BackgroundColor3 = C.Dim
	end
end

function Menu.refresh()
	local ok, info = call("info")
	if ok and typeof(info) == "table" then
		Menu.status(info)
	end
end

local function openSolo(on: boolean)
	el.soloOpen = on
	show(el.dock, not on, 18)
	show(el.solo, on, 18)
end

local function openPicker(on: boolean)
	el.picker.Visible = true
	if on then
		el.pickerDim.BackgroundTransparency = 1
		UI.tween(el.pickerDim, 0.2, { BackgroundTransparency = 0.45 })
		el.pickerBox.Visible = true
		UI.popIn(el.pickerBox, 0.9)
	else
		UI.tween(el.pickerDim, 0.18, { BackgroundTransparency = 1 })
		UI.tween(UI.scaleOf(el.pickerBox), 0.15, { Scale = 0.94 })
		task.delay(0.16, function()
			el.picker.Visible = false
		end)
	end
end

function Menu.open()
	gui.Enabled = true
	Audio.setMode("menu")
	if el.soloOpen then
		openSolo(false)
	end
	el.picker.Visible = false
	show(el.head, true, -20)
	show(el.dock, true, 24)
	el.solo.Visible = false
	UI.popIn(el.shop, 0.7)
	if Menu.onOpen then
		Menu.onOpen()
	end
	task.spawn(Menu.refresh)
end

function Menu.close()
	gui.Enabled = false
	Audio.setMode("match")
	if Menu.onClose then
		Menu.onClose()
	end
end

function Menu.isOpen(): boolean
	return gui ~= nil and gui.Enabled
end

local function result(ok: boolean, msg: any)
	if ok and msg == "here" then
		Menu.close()
		return
	end
	if Menu.toast then
		Menu.toast(tostring(msg), if ok then "good" else "bad")
	end
	if ok then
		Menu.close()
	end
end

function Menu.init()
	remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Menu") :: RemoteFunction
	gui = make("ScreenGui", { Name = "Menu", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 30, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })

	-- backdrop: the real pixel world, a vignette, a dark top and bottom
	local bg = make("ImageLabel", { Name = "Backdrop", BackgroundColor3 = Color3.fromHex("2D6A9A"), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Active = true, ScaleType = Enum.ScaleType.Crop, ResampleMode = Enum.ResamplerMode.Pixelated, Parent = gui })
	local bgImg = thumbFor("__bg")
	if bgImg then
		bg.ImageContent = Content.fromObject(bgImg)
	end
	make("Frame", { BackgroundColor3 = C.Night, BackgroundTransparency = 0.55, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = bg })
	local vig = make("ImageLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ImageColor3 = C.Night, ScaleType = Enum.ScaleType.Stretch, Parent = bg })
	local vigImg = UI.blob("vignette", 128, 72, 0.55, 1.45, true)
	if vigImg then
		vig.ImageContent = Content.fromObject(vigImg)
	end
	local top = make("Frame", { BackgroundColor3 = Color3.new(0.005, 0.01, 0.035), BorderSizePixel = 0, Size = UDim2.fromScale(1, 0.5), Parent = bg })
	make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.08), NumberSequenceKeypoint.new(0.55, 0.4), NumberSequenceKeypoint.new(1, 1) }), Parent = top })
	local bot = make("Frame", { BackgroundColor3 = C.Night, BorderSizePixel = 0, Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromScale(1, 0.5), Parent = bg })
	make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0.2), Parent = bot })

	-- logical canvas: 1280 x 720 design px scaled to the screen, any aspect
	local root = make("Frame", { Name = "Root", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(1280, 720), Parent = gui })
	local scale = make("UIScale", { Parent = root })
	local function rescale()
		local v = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
		local s = math.clamp(math.min(v.X / 1280, v.Y / 720), 0.5, 1.6)
		scale.Scale = s
		root.Size = UDim2.fromOffset(v.X / s, v.Y / s)
	end
	rescale()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	end

	-- toast (bottom centre, over the credits line)
	local toastBox = panel({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.fromOffset(0, 36), AutomaticSize = Enum.AutomaticSize.X, Visible = false, ZIndex = 20, Parent = root })
	UI.pad(14, 0).Parent = toastBox
	local toastLbl = label({ Text = "", TextSize = 14, FontFace = F.Semi, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1), ZIndex = 20, Parent = toastBox })
	local tok = 0
	Menu.toast = function(text: string, kind: string?)
		tok += 1
		local my = tok
		toastLbl.Text = text
		toastLbl.TextColor3 = if kind == "bad" then C.Bad elseif kind == "good" then C.Good else C.Text
		toastBox.Visible = true
		UI.popIn(toastBox, 0.9)
		task.delay(2.8, function()
			if tok == my then
				toastBox.Visible = false
			end
		end)
	end

	-- top-left: music and sound switches (glass squares)
	local icons = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 14), Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X, Parent = root })
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), Parent = icons })
	local function muteBtn(icon: string, get: () -> boolean, set: (boolean) -> ())
		local b = button({ Text = "", Size = UDim2.fromOffset(40, 40), BackgroundColor3 = C.Bg, BackgroundTransparency = 0.12 }, function()
			set(not get())
		end)
		local ic = Icons.label(icon, 20, b)
		ic.AnchorPoint = Vector2.new(0.5, 0.5)
		ic.Position = UDim2.fromScale(0.5, 0.5)
		b.Parent = icons
		local slash = make("Frame", { BackgroundColor3 = C.Bad, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(26, 3), Rotation = -45, Visible = false, Parent = b })
		local function sync()
			slash.Visible = not get()
			ic.ImageTransparency = if get() then 0 else 0.5
		end
		sync()
		table.insert(Audio.changed, sync)
	end
	muteBtn("music", function()
		return Audio.musicOn
	end, Audio.setMusic)
	muteBtn("sound", function()
		return Audio.sfxOn
	end, Audio.setSfx)

	-- head: emblem, wordmark, tag line (a warm glow behind)
	local head = make("CanvasGroup", { Name = "Head", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 34), Size = UDim2.fromOffset(1000, 250), Parent = root })
	el.head = head
	local glow = make("ImageLabel", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 118), Size = UDim2.fromOffset(980, 230), ImageColor3 = Color3.fromRGB(255, 176, 84), ImageTransparency = 0.72, Parent = head })
	local glowImg = UI.blob("glow", 128, 64, 0.0, 1.0)
	if glowImg then
		glow.ImageContent = Content.fromObject(glowImg)
	end
	local emblem = Icons.label("globe", 58, head)
	emblem.AnchorPoint = Vector2.new(0.5, 0)
	emblem.Position = UDim2.fromScale(0.5, 0)
	local wordBox = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 62), Size = UDim2.fromOffset(1000, 100), Parent = head })
	local word, setPx = UI.wordmark("TAKE OVER THE WORLD!", wordBox, { Spacing = 6 })
	word.AnchorPoint = Vector2.new(0.5, 0)
	word.Position = UDim2.fromScale(0.5, 0)
	-- fit the word to the head (it is long): 78 px at most, never wider than 960 logical px
	local px = 78
	setPx(px)
	local function fitWord()
		task.defer(function()
			local s = scale.Scale
			local w = word.AbsoluteSize.X / math.max(s, 0.01)
			if w > 960 then
				px = math.max(40, px * 960 / w)
				setPx(px)
			end
		end)
	end
	fitWord()
	word:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitWord)
	local tagRow = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 160), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 20), Parent = head })
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 16), VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Parent = tagRow })
	local function tagLine(order: number, flip: boolean)
		local l = make("Frame", { BackgroundColor3 = C.Accent, BorderSizePixel = 0, Size = UDim2.fromOffset(72, 2), LayoutOrder = order, Parent = tagRow })
		make("UIGradient", { Transparency = if flip then NumberSequence.new(0.15, 1) else NumberSequence.new(1, 0.15), Parent = l })
	end
	tagLine(1, false)
	-- letter-spaced tag (one label per word keeps it crisp; RichText has no tracking)
	local tag = label({ Text = "C O N Q U E R   T H E   R E A L   W O R L D", TextSize = 15, FontFace = F.Semi, TextColor3 = Color3.new(0.86, 0.89, 0.97), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 20), LayoutOrder = 2, Parent = tagRow })
	tag.TextXAlignment = Enum.TextXAlignment.Center
	tagLine(3, true)

	-- top right: SHOP (level with the wordmark), wiggles now and then
	local shop = button({ Name = "Shop", Text = "", Size = UDim2.fromOffset(96, 104), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, 60), BackgroundColor3 = C.Bg, BackgroundTransparency = 0.12, Radius = UI.R.lg }, function()
		if Menu.onShop then
			Menu.onShop()
		end
	end)
	shop.Parent = root
	el.shop = shop
	local rays = make("ImageLabel", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 42), Size = UDim2.fromOffset(86, 86), ImageColor3 = C.Gold, ImageTransparency = 0.7, Parent = shop })
	local rayImg = UI.blob("glow", 128, 64, 0.0, 1.0)
	if rayImg then
		rays.ImageContent = Content.fromObject(rayImg)
	end
	local Art = require(script.Parent.Art)
	local coin = Art.coinLabel(54, shop)
	coin.AnchorPoint = Vector2.new(0.5, 0.5)
	coin.Position = UDim2.new(0.5, 0, 0, 42)
	local pill = make("Frame", { BackgroundColor3 = C.Accent, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.fromOffset(72, 22), Parent = shop }, { UI.corner(999) })
	UI.lip(pill, 2)
	label({ Text = "SHOP", TextSize = 13, FontFace = F.Heavy, TextColor3 = C.Ink, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), Parent = pill })
	task.spawn(function()
		while true do
			task.wait(5)
			if gui.Enabled then
				local s = UI.scaleOf(coin)
				for _, r in { -12, 10, -6, 0 } do
					UI.tween(coin, 0.09, { Rotation = r })
					task.wait(0.09)
				end
				UI.tween(s, 0.15, { Scale = 1.12 }, Enum.EasingStyle.Back)
				task.wait(0.16)
				UI.tween(s, 0.2, { Scale = 1 })
			end
		end
	end)

	-- the dock: bottom centre, 540 wide
	local function dockGroup(name: string): (CanvasGroup, Frame)
		local g = make("CanvasGroup", { Name = name, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -44), Size = UDim2.fromOffset(580, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = root })
		make("UIPadding", { PaddingLeft = UDim.new(0, 20), PaddingRight = UDim.new(0, 20), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 20), Parent = g })
		-- soft shadow under the glass
		local p = panel({ Name = "Glass", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Radius = 18, Parent = g })
		make("UIPadding", { PaddingLeft = UDim.new(0, 20), PaddingRight = UDim.new(0, 20), PaddingTop = UDim.new(0, 18), PaddingBottom = UDim.new(0, 18), Parent = p })
		make("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = p })
		return g, p
	end
	local dock, dv = dockGroup("Dock")
	el.dock = dock
	local who = Players.LocalPlayer
	local greet = label({ Text = ("Welcome, %s"):format(who.DisplayName), TextSize = 13, FontFace = F.Med, TextColor3 = C.Sub, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 1, Parent = dv })
	greet.Name = "Greet"
	local solo = button({ Name = "PlaySolo", Kind = "primary", TextSize = 17, Size = UDim2.new(1, 0, 0, 50), LayoutOrder = 2 }, function()
		openSolo(true)
	end)
	iconText(solo, "play", "PLAY SOLO", 17, C.Ink)
	solo.Parent = dv
	-- PUBLIC MATCHES between two rules
	local sec = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 14), LayoutOrder = 3, Parent = dv })
	local capW = 128
	UI.divider({ AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(0.5, -capW / 2 - 10, 0, 1), Parent = sec })
	UI.divider({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.new(0.5, -capW / 2 - 10, 0, 1), Parent = sec })
	local cap = UI.caption("Public matches", { TextColor3 = C.Info, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(capW, 14), Parent = sec })
	cap.Text = "P U B L I C   M A T C H E S"
	-- the public-match card + How to Play
	local row = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 62), LayoutOrder = 4, Parent = dv })
	local pub = button({ Name = "FindMatch", Kind = "public", Text = "", Size = UDim2.new(1, -72, 1, 0) }, function()
		if busy then
			return
		end
		busy = true
		el.pubStatus.Text = "Finding a match…"
		el.pubDot.BackgroundColor3 = C.Accent
		el.pubPill.Text = "…"
		local ok, msg = call("match", { map = selected })
		busy = false
		el.pubPill.Text = "JOIN"
		if el.lastInfo then
			Menu.status(el.lastInfo)
		end
		result(ok, msg)
	end)
	pub.Parent = row
	local th = thumbLabel(selected, UDim2.fromOffset(58, 40), pub)
	th.AnchorPoint = Vector2.new(0, 0.5)
	th.Position = UDim2.new(0, 10, 0.5, 0)
	el.pubThumb = th
	el.pubTitle = label({ Text = "PUBLIC MATCH", TextSize = 15, FontFace = F.Heavy, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(80, 12), Size = UDim2.new(1, -160, 0, 18), Parent = pub })
	el.pubDot = make("Frame", { BackgroundColor3 = C.Dim, BorderSizePixel = 0, Position = UDim2.fromOffset(80, 37), Size = UDim2.fromOffset(7, 7), Parent = pub }, { UI.corner(4) })
	el.pubStatus = label({ Text = "Connecting…", TextSize = 12, FontFace = F.Med, TextColor3 = C.Sub, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(93, 32), Size = UDim2.new(1, -175, 0, 16), Parent = pub })
	local jp = make("Frame", { BackgroundColor3 = C.Info, BackgroundTransparency = 0.84, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(56, 24), Parent = pub }, { UI.corner(999) })
	local js = UI.stroke(C.Info)
	js.Transparency = 0.45
	js.Parent = jp
	el.pubPill = label({ Text = "JOIN", TextSize = 11, FontFace = F.Heavy, TextColor3 = C.Info, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), Parent = jp })
	local help = button({ Name = "Help", Text = "", Size = UDim2.fromOffset(62, 62), AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0) }, function()
		Menu.close()
		if Menu.onTutorial then
			Menu.onTutorial()
		end
	end)
	local hi = Icons.label("help", 26, help)
	hi.AnchorPoint = Vector2.new(0.5, 0.5)
	hi.Position = UDim2.fromScale(0.5, 0.5)
	help.Parent = row

	-- the solo panel (same place as the dock)
	local soloG, sv = dockGroup("Solo")
	el.solo = soloG
	soloG.Visible = false
	local sh = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 1, Parent = sv })
	local pic = Icons.label("play", 18, sh)
	pic.ImageColor3 = C.Accent
	pic.AnchorPoint = Vector2.new(0, 0.5)
	pic.Position = UDim2.fromScale(0, 0.5)
	label({ Text = "PLAY SOLO", TextSize = 17, FontFace = F.Heavy, Position = UDim2.fromOffset(28, 0), Size = UDim2.new(1, -80, 1, 0), Parent = sh })
	local close = button({ Kind = "ghost", Text = "", Size = UDim2.fromOffset(44, 44), AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0) }, function()
		openSolo(false)
	end)
	local ci = Icons.label("close", 16, close)
	ci.AnchorPoint = Vector2.new(0.5, 0.5)
	ci.Position = UDim2.fromScale(0.5, 0.5)
	close.Parent = sh
	local mapBtn = button({ Name = "Map", Text = "", Size = UDim2.new(1, 0, 0, 42), LayoutOrder = 2 }, function()
		openPicker(true)
	end)
	local mgi = Icons.label("globe", 18, mapBtn)
	mgi.AnchorPoint = Vector2.new(0, 0.5)
	mgi.Position = UDim2.new(0, 16, 0.5, 0)
	el.mapText = label({ Text = "Map:  World", TextSize = 14, FontFace = F.Bold, Position = UDim2.fromOffset(44, 0), Size = UDim2.new(1, -80, 1, 0), Parent = mapBtn })
	label({ Text = "›", TextSize = 22, FontFace = F.Bold, TextColor3 = C.Sub, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 0), Size = UDim2.new(0, 12, 1, -2), Parent = mapBtn })
	mapBtn.Parent = sv
	local dr = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 3, Parent = sv })
	UI.caption("Difficulty", { Size = UDim2.new(0, 84, 1, 0), Parent = dr })
	local chips = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(92, 0), Size = UDim2.new(1, -92, 1, 0), Parent = dr })
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = chips })
	el.chipSet = {}
	for i = 0, 2 do
		local b, set = UI.chip({ Text = Config.Difficulty[i].Name, Size = UDim2.new(1 / 3, -6, 1, 0), LayoutOrder = i }, function()
			difficulty = i
			refreshDiff()
		end)
		b.Parent = chips
		table.insert(el.chipSet, set)
	end
	el.diffDesc = label({ Text = "", TextSize = 12, FontFace = F.Med, TextColor3 = C.Sub, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 4, Parent = sv })
	local start = button({ Name = "Start", Kind = "primary", TextSize = 19, Size = UDim2.new(1, 0, 0, 58), LayoutOrder = 5 }, function()
		if busy then
			return
		end
		busy = true
		local ok, msg = call("solo", { map = selected, diff = difficulty })
		busy = false
		result(ok, msg)
	end)
	iconText(start, "play", "START", 19, C.Ink)
	start.Parent = sv
	refreshDiff()

	-- map picker modal
	local picker = make("Frame", { Name = "Picker", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 10, Parent = root })
	el.picker = picker
	local dim = make("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = C.Night, BackgroundTransparency = 0.45, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = picker })
	dim.Activated:Connect(function()
		openPicker(false)
	end)
	el.pickerDim = dim
	local pbox = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(720, 470), Parent = picker })
	el.pickerBox = pbox
	local pp = panel({ Size = UDim2.fromScale(1, 1), Radius = 18, BackgroundColor3 = C.Panel, BackgroundTransparency = 0.02, Parent = pbox })
	label({ Text = "CHOOSE A MAP", TextSize = 20, FontFace = F.Heavy, Position = UDim2.fromOffset(24, 18), Size = UDim2.new(1, -100, 0, 26), Parent = pp })
	local tabs = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(24, 56), Size = UDim2.new(1, -48, 0, 30), Parent = pp })
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = tabs })
	local pclose = button({ Kind = "ghost", Text = "", Size = UDim2.fromOffset(40, 40), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 12) }, function()
		openPicker(false)
	end)
	local pci = Icons.label("close", 16, pclose)
	pci.AnchorPoint = Vector2.new(0.5, 0.5)
	pci.Position = UDim2.fromScale(0.5, 0.5)
	pclose.Parent = pp
	local gridF = make("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(24, 100), Size = UDim2.new(1, -40, 1, -146), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4, ScrollBarImageColor3 = C.Sub, Parent = pp })
	make("UIGridLayout", { CellSize = UDim2.fromOffset(212, 150), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = gridF })
	make("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingLeft = UDim.new(0, 2), Parent = gridF })
	label({ Text = "Map data: Natural Earth (public domain)  ·  Flags: flagcdn.com", TextSize = 11, FontFace = F.Med, TextColor3 = C.Dim, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -14), Size = UDim2.new(1, 0, 0, 14), Parent = pp })
	el.mapCards = {}
	for k, id in Config.MapOrder do
		local def = Config.Maps[id]
		local mc = button({ Name = "Map_" .. id, Text = "", LayoutOrder = k, Radius = 12 }, function()
			selectMap(id)
			openPicker(false)
		end)
		-- lihfolk-ignore: findfirstchild-chain (UI.button always adds the stroke)
		local st = mc:FindFirstChildOfClass("UIStroke") :: UIStroke
		thumbLabel(id, UDim2.new(1, -12, 0, 92), mc).Position = UDim2.fromOffset(6, 6)
		label({ Text = def.Name, TextSize = 15, FontFace = F.Bold, Position = UDim2.fromOffset(12, 104), Size = UDim2.new(1, -24, 0, 18), Parent = mc })
		label({ Text = ("%d nations  ·  %s"):format(def.Nations, def.Desc or ""), TextSize = 11, FontFace = F.Med, TextColor3 = C.Sub, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(12, 124), Size = UDim2.new(1, -24, 0, 14), Parent = mc })
		local check = make("Frame", { BackgroundColor3 = C.Accent, BorderSizePixel = 0, Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(58, 18), Visible = false, Parent = mc }, { UI.corner(999) })
		label({ Text = "SELECTED", TextSize = 10, FontFace = F.Heavy, TextColor3 = C.Ink, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), Parent = check })
		if def.Special then
			local tg = make("Frame", { BackgroundColor3 = C.Violet, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), Size = UDim2.fromOffset(54, 18), Parent = mc }, { UI.corner(999) })
			label({ Text = "SPECIAL", TextSize = 10, FontFace = F.Heavy, TextColor3 = C.Ink, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), Parent = tg })
		end
		mc.Parent = gridF
		el.mapCards[id] = { card = mc, stroke = st, check = check, special = def.Special == true }
	end
	local tabSet: { (boolean) -> () } = {}
	for i, t in { "All", "Continents", "Special" } do
		local b, set = UI.chip({ Text = t, Size = UDim2.fromOffset(104, 30), LayoutOrder = i }, function()
			for j, s in tabSet do
				s(j == i)
			end
			for _, c in el.mapCards do
				c.card.Visible = i == 1 or (i == 2 and not c.special) or (i == 3 and c.special)
			end
		end)
		b.Parent = tabs
		table.insert(tabSet, set)
	end
	tabSet[1](true)

	-- credits line
	label({ Text = "Take Over the World!  ·  Map data: Natural Earth  ·  Flags: flagcdn.com", TextSize = 11, FontFace = F.Med, TextColor3 = C.Dim, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -14), Size = UDim2.new(1, 0, 0, 14), Parent = root })

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	selectMap(selected)
	Menu.open()
	-- live status refresh while the menu is open
	task.spawn(function()
		while true do
			task.wait(10)
			if gui.Enabled then
				Menu.refresh()
			end
		end
	end)
end

return Menu
