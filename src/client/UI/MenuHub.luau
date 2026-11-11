--!nonstrict
-- (World Conquest, 2026-11-11) The main menu, laid out like the user's reference (Screenshot
-- 2026-11-10 204858.png and Videos/2026-11-11 00-14-29.mp4): a dark top bar (the wordmark in the
-- middle, the player and their coins on the right), DAILY CHALLENGES and a COMMUNITY GOAL on the left,
-- PUBLIC MATCHES with PLAY PRIVATE MATCH in the middle, FEATURED offers on the right, and a row of
-- big buttons along the bottom (PARTY, INVITE, COMING SOON, SHOP, LEADERBOARD, REWARDS).
--
-- It sits over TitleScreen (inside its GUI, so the map picker, Locker, help and game menu still open
-- above it) and drives TitleScreen's own logic: the public-match rows mirror TitleScreen's Quick Play
-- cards (their text, state and presses), PLAY PRIVATE MATCH opens a PRIVATE MATCH window (map,
-- party, difficulty, LAND TO WIN) whose START fires TitleScreen.play_solo. While the player waits in
-- a public match's waiting room the hub hides and TitleScreen's queue card shows.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")
local TweenService = game:GetService("TweenService")

local UITheme = require("./UITheme")
local UIMaps = require("./UIMaps")
local QuestPanel = require("./QuestPanel")
local ItemShopPanel = require("./ItemShopPanel")

local MenuHub = {}
MenuHub.__index = MenuHub

--- the reference's design size (desktop); phones lay out the middle column and the bottom row only
MenuHub.REF = Vector2.new(1870, 870)
MenuHub.REF_COMPACT = Vector2.new(1000, 620)
MenuHub.WIN_MIN, MenuHub.WIN_MAX, MenuHub.WIN_DEFAULT = 0.5, 0.95, 0.8
MenuHub.CREDITS = "© OpenFront and Contributors  ·  RoWorld © Snick Co.  ·  Music courtesy of APM Music  ·  "
	.. "GNU AGPL v3, no warranty: See Help & Credits  ·  Source: github.com/Armxnee/take-over-the-world"

local FONT = "rbxassetid://12187365977"
local PIXEL = Font.fromEnum(Enum.Font.Arcade)
local C = {
	bar = Color3.fromHex("15171C"),
	panel = Color3.fromHex("1C1F26"),
	row = Color3.fromHex("272A32"),
	row_hover = Color3.fromHex("30343D"),
	stroke = Color3.fromHex("3A3E48"),
	text = Color3.fromHex("F2F4F8"),
	text2 = Color3.fromHex("9AA3B4"),
	text3 = Color3.fromHex("6B7385"),
	gold = Color3.fromHex("F2C94C"),
	gold_bg = Color3.fromHex("4D3F12"),
	gold_hover = Color3.fromHex("5E4D16"),
	gold_line = Color3.fromHex("C9A227"),
	green = Color3.fromHex("5FD38A"),
	green_bg = Color3.fromHex("1C4A2D"),
	green_hover = Color3.fromHex("235C38"),
	green_line = Color3.fromHex("3FAE6A"),
	blue = Color3.fromHex("4D8BFF"),
	blue_text = Color3.fromHex("8FB4FF"),
	ink = Color3.fromHex("101216"),
	bar_bg = Color3.fromHex("14161B"),
}

local function make(class: string, props: { [string]: any }, parent: Instance?): any
	local o = Instance.new(class)
	for k, v in props do
		o[k] = v
	end
	if parent then
		o.Parent = parent
	end
	return o
end

local function stroke(parent: Instance, color: Color3?, thick: number?, transp: number?)
	return make("UIStroke", {
		Color = color or C.stroke,
		Thickness = thick or 1,
		Transparency = transp or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

local function corner(parent: Instance, r: number?)
	return make("UICorner", { CornerRadius = UDim.new(0, r or 3) }, parent)
end

--- A text label: `spacing` is extra letter spacing (the reference's wide, uppercase captions).
local function text(parent: Instance, s: string, size: number, weight: Enum.FontWeight?, color: Color3?, props: { [string]: any }?): TextLabel
	local l = make("TextLabel", {
		BackgroundTransparency = 1,
		Text = s,
		TextSize = size,
		FontFace = Font.new(FONT, weight or Enum.FontWeight.Bold),
		TextColor3 = color or C.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, 0, 0, size + 6),
		ZIndex = 3,
	}, parent)
	for k, v in props or {} do
		l[k] = v
	end
	return l
end

--- Wide-tracked caps ("DAILY CHALLENGES"): Roblox has no letter spacing, so thin spaces between letters.
local function tracked(s: string, gap: string?): string
	local g = gap or " "
	local out = {}
	for _, cp in utf8.codes(s) do
		table.insert(out, utf8.char(cp))
	end
	return table.concat(out, g)
end

local function commas(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function hms(sec: number): string
	sec = math.max(0, math.floor(sec))
	return string.format("%d:%02d:%02d", sec // 3600, (sec % 3600) // 60, sec % 60)
end

local function tween(o: Instance, t: number, props: { [string]: any })
	TweenService:Create(o, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

--- A flat button in one of the reference's styles: "green" (JOIN), "gold" (PLAY / START), "dark"
--- (CHANGE, INVITE, WATCH) or a bottom-row tile ("nav", "nav_gold", "nav_green").
local STYLES = {
	green = { bg = C.green_bg, hover = C.green_hover, line = C.green_line, fg = Color3.fromHex("E8F7EE") },
	gold = { bg = C.gold_bg, hover = C.gold_hover, line = C.gold_line, fg = C.gold },
	dark = { bg = C.ink, hover = Color3.fromHex("22252C"), line = C.stroke, fg = C.text },
	nav = { bg = Color3.fromHex("24272E"), hover = Color3.fromHex("2E323A"), line = C.stroke, fg = C.text },
	nav_gold = { bg = Color3.fromHex("3A3216"), hover = Color3.fromHex("463B1A"), line = Color3.fromHex("8C7425"), fg = C.gold },
	nav_green = { bg = Color3.fromHex("1B3A28"), hover = Color3.fromHex("224631"), line = Color3.fromHex("3B7A50"), fg = Color3.fromHex("A6EBC0") },
	sel = { bg = Color3.fromHex("123A3A"), hover = Color3.fromHex("174A4A"), line = Color3.fromHex("4FD1C5"), fg = C.text },
	off = { bg = Color3.fromHex("1E2026"), hover = Color3.fromHex("1E2026"), line = Color3.fromHex("2E3139"), fg = C.text3 },
}

local function button(parent: Instance, label: string, style: string, size: number?, props: { [string]: any }?): TextButton
	local st = STYLES[style]
	local b = make("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = st.bg,
		Text = label,
		TextSize = size or 15,
		FontFace = Font.new(FONT, Enum.FontWeight.Heavy),
		TextColor3 = st.fg,
		ZIndex = 4,
	}, parent)
	corner(b, 3)
	local s = stroke(b, st.line, if style == "gold" then 1.5 else 1)
	b:SetAttribute("Style", style)
	b.MouseEnter:Connect(function()
		local cur = STYLES[b:GetAttribute("Style")]
		tween(b, 0.12, { BackgroundColor3 = cur.hover })
	end)
	b.MouseLeave:Connect(function()
		local cur = STYLES[b:GetAttribute("Style")]
		tween(b, 0.18, { BackgroundColor3 = cur.bg })
	end)
	b.MouseButton1Down:Connect(function()
		local sc = b:FindFirstChild("Press") or make("UIScale", { Name = "Press" }, b)
		tween(sc, 0.06, { Scale = 0.96 })
	end)
	b.MouseButton1Up:Connect(function()
		local sc = b:FindFirstChild("Press")
		if sc then
			tween(sc, 0.12, { Scale = 1 })
		end
	end)
	b.MouseLeave:Connect(function()
		local sc = b:FindFirstChild("Press")
		if sc then
			tween(sc, 0.12, { Scale = 1 })
		end
	end)
	for k, v in props or {} do
		b[k] = v
	end
	return b, s
end

local function restyle(b: TextButton, style: string)
	if b:GetAttribute("Style") == style then
		return
	end
	local st = STYLES[style]
	b:SetAttribute("Style", style)
	b.BackgroundColor3 = st.bg
	b.TextColor3 = st.fg
	local s = b:FindFirstChildOfClass("UIStroke")
	if s then
		s.Color = st.line
	end
end

local function panel(parent: Instance, props: { [string]: any }?): Frame
	local f = make("Frame", {
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, parent)
	corner(f, 3)
	stroke(f, Color3.fromHex("2C3038"))
	for k, v in props or {} do
		f[k] = v
	end
	return f
end

local function icon(parent: Instance, name: string, px: number, color: Color3?, props: { [string]: any }?): ImageLabel
	local img = make("ImageLabel", {
		BackgroundTransparency = 1,
		Image = UITheme.icon(name) or "",
		ImageColor3 = color or C.text,
		Size = UDim2.fromOffset(px, px),
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = 4,
	}, parent)
	for k, v in props or {} do
		img[k] = v
	end
	return img
end

-- =============================================================================================

function MenuHub.new(title: any)
	local self = setmetatable({}, MenuHub)
	self.title = title
	self.ctx = title.ctx
	self.rows = {}
	self.quest_rows = {}
	self._acc = 0
	local root = make("Frame", {
		Name = "MenuHub",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 200,
	}, title.gui)
	self.root = root
	local canvas = make("Frame", { Name = "Canvas", BackgroundTransparency = 1, ZIndex = 1 }, root)
	self.canvas = canvas
	self.scale = make("UIScale", {}, canvas)
	self:_build_top()
	self:_build_left()
	self:_build_center()
	self:_build_right()
	self:_build_nav()
	self.credits = text(canvas, MenuHub.CREDITS, 11, Enum.FontWeight.Medium, C.text3, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -3),
		Size = UDim2.new(1, -40, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTransparency = 0.15,
	})
	self:_build_private()
	self.toast = text(canvas, "", 15, Enum.FontWeight.Bold, C.text, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -140),
		Size = UDim2.fromOffset(520, 40),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.05,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		ZIndex = 30,
	})
	corner(self.toast, 3)
	stroke(self.toast, C.gold_line)
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:layout()
	end)
	self._conn = RunService.Heartbeat:Connect(function(dt)
		self:_step(dt)
	end)
	task.spawn(function()
		local lp = Players.LocalPlayer
		if lp == nil then
			return
		end
		local ok, img = pcall(function()
			return Players:GetUserThumbnailAsync(lp.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		end)
		if ok then
			self.avatar.Image = img
			self.pm_avatar.Image = img
		end
	end)
	self:layout()
	return self
end

-- ---------------------------------------------------------------------------------------------
-- Top bar
-- ---------------------------------------------------------------------------------------------

function MenuHub._build_top(self)
	local bar = make("Frame", {
		Name = "TopBar",
		BackgroundColor3 = C.bar,
		BackgroundTransparency = 0.03,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 68),
		ZIndex = 2,
	}, self.canvas)
	self.top = bar
	make("Frame", { -- a hairline under it
		BackgroundColor3 = Color3.fromHex("2A2E36"),
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 1, -1),
		Size = UDim2.new(1, 0, 0, 1),
		ZIndex = 3,
	}, bar)
	-- the wordmark: WORLD in white, CONQUEST in blue, both outlined in ink
	local logo = make("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(420, 56),
		ZIndex = 3,
	}, bar)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
	}, logo)
	for i, part in { { "WORLD", Color3.new(1, 1, 1) }, { "CONQUEST", C.blue } } do
		local l = text(logo, part[1], 40, Enum.FontWeight.Heavy, part[2], {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 50),
			TextTruncate = Enum.TextTruncate.None,
			LayoutOrder = i,
		})
		stroke(l, C.ink, 3).ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	end
	-- the player, right: their headshot, name and rank, then their coins (the item shop's currency)
	local who = make("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -118, 0.5, 0),
		Size = UDim2.fromOffset(330, 52),
		ZIndex = 3,
	}, bar)
	self.who = who
	self.avatar = make("ImageLabel", {
		BackgroundColor3 = Color3.fromHex("2A2E36"),
		Size = UDim2.fromOffset(44, 44),
		Position = UDim2.fromOffset(0, 4),
		ZIndex = 4,
	}, who)
	corner(self.avatar, 22)
	stroke(self.avatar, C.gold_line, 1.5)
	self.name = text(who, "", 17, Enum.FontWeight.Heavy, C.text, {
		Position = UDim2.fromOffset(56, 3),
		Size = UDim2.new(1, -56, 0, 22),
	})
	self.rank = text(who, "", 13, Enum.FontWeight.Bold, C.text2, {
		Position = UDim2.fromOffset(56, 25),
		Size = UDim2.new(1, -56, 0, 18),
		RichText = true,
	})
	local coins, coins_line = button(bar, "", "dark", 20, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.fromOffset(92, 50),
	})
	coins_line.Color = Color3.fromHex("3E66B8")
	icon(coins, "coin", 26, Color3.new(1, 1, 1), { Position = UDim2.new(0, 10, 0.5, -13) })
	self.coins = text(coins, "0", 20, Enum.FontWeight.Heavy, C.text, {
		Position = UDim2.new(0, 40, 0, 0),
		Size = UDim2.new(1, -46, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
	})
	self.coins_btn = coins
	coins.Activated:Connect(function()
		self.ctx:sfx("click")
		self.title.open_shop:Fire()
	end)
end

-- ---------------------------------------------------------------------------------------------
-- Left: daily challenges and the community goal
-- ---------------------------------------------------------------------------------------------

local function panel_head(parent: Instance, left: string, right: string?): (TextLabel, TextLabel?)
	local l = text(parent, tracked(left), 15, Enum.FontWeight.Heavy, C.text, {
		Position = UDim2.fromOffset(18, 14),
		Size = UDim2.new(1, -36, 0, 22),
	})
	local r = nil
	if right ~= nil then
		r = text(parent, right, 13, Enum.FontWeight.Heavy, C.gold, {
			Position = UDim2.fromOffset(18, 14),
			Size = UDim2.new(1, -36, 0, 22),
			TextXAlignment = Enum.TextXAlignment.Right,
		})
	end
	return l, r
end

function MenuHub._build_left(self)
	local col = make("Frame", { Name = "Left", BackgroundTransparency = 1, Size = UDim2.fromOffset(356, 500), ZIndex = 2 }, self.canvas)
	self.left = col
	local daily = panel(col, { Size = UDim2.fromOffset(356, 290) })
	self.daily = daily
	local _, timer = panel_head(daily, "DAILY CHALLENGES", "NEW IN 0:00:00")
	self.daily_timer = timer
	for i = 1, QuestPanel.CARDS do
		local row = make("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = C.row,
			Position = UDim2.fromOffset(16, 46 + (i - 1) * 78),
			Size = UDim2.new(1, -32, 0, 70),
			ZIndex = 3,
		}, daily)
		corner(row, 3)
		local rs = stroke(row)
		local r = { row = row, stroke = rs }
		r.text = text(row, "", 15, Enum.FontWeight.Bold, C.text, {
			Position = UDim2.fromOffset(14, 9),
			Size = UDim2.new(1, -120, 0, 20),
		})
		r.coin = icon(row, "coin", 18, Color3.new(1, 1, 1), { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -66, 0, 10) })
		r.reward = text(row, "", 16, Enum.FontWeight.Heavy, C.blue_text, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 8),
			Size = UDim2.fromOffset(56, 22),
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		local track = make("Frame", {
			BackgroundColor3 = C.bar_bg,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(14, 45),
			Size = UDim2.new(1, -110, 0, 5),
			ZIndex = 4,
		}, row)
		corner(track, 2)
		r.fill = make("Frame", { BackgroundColor3 = C.green, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), ZIndex = 5 }, track)
		corner(r.fill, 2)
		r.count = text(row, "", 13, Enum.FontWeight.Bold, C.text2, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 38),
			Size = UDim2.fromOffset(86, 18),
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		row.Activated:Connect(function()
			self:_claim(r)
		end)
		row.MouseEnter:Connect(function()
			tween(row, 0.12, { BackgroundColor3 = C.row_hover })
		end)
		row.MouseLeave:Connect(function()
			tween(row, 0.18, { BackgroundColor3 = C.row })
		end)
		self.quest_rows[i] = r
	end
	self.daily_empty = text(daily, "Loading today's challenges…", 14, Enum.FontWeight.Medium, C.text2, {
		Position = UDim2.fromOffset(18, 56),
		Size = UDim2.new(1, -36, 0, 20),
	})

	local goal = panel(col, { Position = UDim2.fromOffset(0, 306), Size = UDim2.fromOffset(356, 196) })
	self.goal = goal
	panel_head(goal, "COMMUNITY GOAL", "NEW FEATURE")
	local card = make("Frame", {
		BackgroundColor3 = C.row,
		Position = UDim2.fromOffset(16, 46),
		Size = UDim2.new(1, -32, 0, 82),
		ZIndex = 3,
	}, goal)
	corner(card, 3)
	stroke(card)
	local hex = make("Frame", {
		BackgroundColor3 = Color3.fromHex("2F5FB8"),
		Position = UDim2.fromOffset(12, 11),
		Size = UDim2.fromOffset(60, 60),
		Rotation = 0,
		ZIndex = 4,
	}, card)
	corner(hex, 12)
	stroke(hex, Color3.fromHex("7FA8FF"), 2)
	make("UIGradient", {
		Color = ColorSequence.new(Color3.fromHex("5B8CFF"), Color3.fromHex("2546A0")),
		Rotation = 90,
	}, hex)
	icon(hex, "attack", 34, Color3.new(1, 1, 1), { Position = UDim2.fromOffset(13, 13), ZIndex = 5 })
	text(card, "AIR STRIKES", 17, Enum.FontWeight.Heavy, C.text, {
		Position = UDim2.fromOffset(84, 14),
		Size = UDim2.new(1, -96, 0, 22),
	})
	text(card, "✓ " .. tracked("COMPLETED", ""), 12, Enum.FontWeight.Heavy, C.green, {
		Position = UDim2.fromOffset(84, 14),
		Size = UDim2.new(1, -96, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	text(card, "Try jets and bombers in your next match!", 13, Enum.FontWeight.Medium, C.text2, {
		Position = UDim2.fromOffset(84, 42),
		Size = UDim2.new(1, -96, 0, 18),
	})
	local watch = button(goal, "▶  " .. tracked("WATCH PREVIEW", ""), "gold", 14, {
		Position = UDim2.fromOffset(16, 142),
		Size = UDim2.new(1, -32, 0, 40),
	})
	watch.Activated:Connect(function()
		self.ctx:sfx("click")
		self.title.show_help:Fire()
	end)
end

--- A finished challenge's row claims its coins (Session.claim_quest checks and pays).
function MenuHub._claim(self, r: any)
	if not r.ready or r.id == nil then
		if r.id ~= nil then
			self.title.open_arsenal:Fire() -- (the quests window: the whole list)
		end
		return
	end
	local s = self.ctx.session
	if s ~= nil and type(s.claim_quest) == "function" then
		r.ready = false
		self.ctx:sfx("confirm")
		s:claim_quest(r.id)
	end
end

function MenuHub._refresh_quests(self)
	local s = self.ctx.session
	local q = s and s.quests
	local mine = {}
	for _, it in (q and q.list) or {} do
		if it.period == "daily" then
			table.insert(mine, it)
		end
	end
	local now = os.time()
	self.daily_timer.Text = "NEW IN " .. hms(86400 - now % 86400)
	self.daily_empty.Visible = #mine == 0
	for i, r in self.quest_rows do
		local it = mine[i]
		r.row.Visible = it ~= nil
		if it == nil then
			continue
		end
		r.id = it.id
		r.text.Text = it.text
		r.reward.Text = commas(it.reward or 0)
		local goal = math.max(it.goal or 1, 1)
		local p = math.clamp((it.progress or 0) / goal, 0, 1)
		r.fill.Size = UDim2.fromScale(p, 1)
		r.ready = not it.claimed and p >= 1
		if it.claimed then
			r.count.Text = "✓ CLAIMED"
			r.count.TextColor3 = C.green
			r.fill.BackgroundColor3 = C.green
			r.stroke.Color = C.stroke
			r.row.BackgroundTransparency = 0.4
		elseif r.ready then
			r.count.Text = "CLAIM ▶"
			r.count.TextColor3 = C.gold
			r.fill.BackgroundColor3 = C.gold
			r.stroke.Color = C.gold_line
			r.row.BackgroundTransparency = 0
		else
			r.count.Text = string.format("%s / %s", commas(it.progress or 0), commas(goal))
			r.count.TextColor3 = C.text2
			r.fill.BackgroundColor3 = C.green
			r.stroke.Color = C.stroke
			r.row.BackgroundTransparency = 0
		end
	end
end

-- ---------------------------------------------------------------------------------------------
-- Middle: public matches and PLAY PRIVATE MATCH
-- ---------------------------------------------------------------------------------------------

function MenuHub._build_center(self)
	local p = panel(self.canvas, { Name = "Matches", Size = UDim2.fromOffset(630, 486) })
	self.center = p
	text(p, "PUBLIC MATCHES", 26, Enum.FontWeight.Bold, C.text, {
		FontFace = PIXEL,
		Position = UDim2.fromOffset(22, 18),
		Size = UDim2.new(1, -44, 0, 32),
	})
	self.match_count = text(p, "", 13, Enum.FontWeight.Heavy, C.text2, {
		Position = UDim2.fromOffset(22, 22),
		Size = UDim2.new(1, -44, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	for i = 1, 3 do
		local row = make("Frame", {
			BackgroundColor3 = C.row,
			Position = UDim2.fromOffset(22, 64 + (i - 1) * 94),
			Size = UDim2.new(1, -44, 0, 84),
			ZIndex = 3,
		}, p)
		corner(row, 3)
		stroke(row)
		local r = { frame = row, index = i }
		local th = make("Frame", {
			BackgroundColor3 = C.bar_bg,
			Position = UDim2.fromOffset(14, 13),
			Size = UDim2.fromOffset(58, 58),
			ZIndex = 4,
		}, row)
		corner(th, 2)
		r.thumb = make("ImageLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ScaleType = Enum.ScaleType.Crop,
			ZIndex = 5,
		}, th)
		r.glyph = icon(th, "users", 30, C.text2, { Position = UDim2.fromOffset(14, 14), ZIndex = 5 })
		r.name = text(row, "", 20, Enum.FontWeight.Heavy, C.text, {
			Position = UDim2.fromOffset(88, 14),
			Size = UDim2.new(1, -260, 0, 26),
		})
		r.sub = text(row, "", 13, Enum.FontWeight.Bold, C.text2, {
			Position = UDim2.fromOffset(88, 44),
			Size = UDim2.new(1, -260, 0, 20),
		})
		r.btn = button(row, "JOIN", "green", 16, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(84, 46),
		})
		r.btn.Activated:Connect(function()
			local card = self.title._cards[i]
			if card ~= nil and not card.btn.disabled then
				card.btn.pressed:Fire()
				self:_refresh_matches()
			end
		end)
		self.rows[i] = r
	end
	self.divider = make("Frame", {
		BackgroundColor3 = Color3.fromHex("343842"),
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(22, 344),
		Size = UDim2.new(1, -44, 0, 2),
		ZIndex = 3,
	}, p)
	local play = button(p, "▶   " .. tracked("PLAY PRIVATE MATCH", " "), "gold", 21, {
		Position = UDim2.fromOffset(22, 360),
		Size = UDim2.new(1, -44, 0, 72),
	})
	self.play = play
	play.Activated:Connect(function()
		self:open_private()
	end)
	local how = make("TextButton", {
		BackgroundTransparency = 1,
		Text = tracked("HOW TO PLAY", ""),
		TextSize = 14,
		FontFace = Font.new(FONT, Enum.FontWeight.Heavy),
		TextColor3 = C.green,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 446),
		Size = UDim2.fromOffset(160, 24),
		ZIndex = 4,
	}, p)
	make("Frame", { -- the underline
		BackgroundColor3 = C.green,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(0.82, 0, 0, 1),
		ZIndex = 4,
	}, how)
	how.Activated:Connect(function()
		self.ctx:sfx("click")
		self.title.show_help:Fire()
	end)
end

--- The rows mirror TitleScreen's Quick Play cards (their title, status and JOIN pill).
function MenuHub._refresh_matches(self)
	local t = self.title
	local open, live = 0, 0
	for _, lb in t._lobbies or {} do
		if lb.live then
			live += tonumber(lb.players) or 0
		else
			open += 1
		end
	end
	self.match_count.Text = if t._lobbies ~= nil
		then string.format("%d OPEN  ·  %d LIVE", open, live)
		else "CONNECTING…"
	for i, r in self.rows do
		local card = t._cards[i]
		local shown = card ~= nil and (i == 1 or card.btn.visible)
		r.frame.Visible = shown
		if not shown then
			continue
		end
		local thumb = if card.thumb_node.visible then card.thumb.Image else ""
		if thumb == "" and card.mode == "world" then
			local e = UIMaps.get("world")
			thumb = (e and e.thumb) or ""
		end
		r.thumb.Image = thumb
		r.thumb.Visible = thumb ~= ""
		r.glyph.Visible = thumb == ""
		local name = card.title:get_text()
		if name == "PUBLIC MATCH" then
			name = "FREE FOR ALL"
		end
		r.name.Text = tracked(name, "")
		local sub = string.upper((card.status:get_text():gsub("%s+·%s+", "  ·  ")))
		r.sub.Text = sub
		local label = card.pill_l:get_text()
		if label == "" then
			label = "…"
		end
		r.btn.Text = label
		local wide = #label > 6
		r.btn.Size = UDim2.fromOffset(if wide then 150 else 96, 46)
		r.name.Size = UDim2.new(1, -(if wide then 260 else 206), 0, 26)
		r.sub.Size = r.name.Size - UDim2.fromOffset(0, 6)
		local off = card.btn.disabled
		restyle(r.btn, if off then "off" elseif label == "CANCEL" or label == "LEADER" then "dark" else "green")
		r.btn.AutoButtonColor = false
	end
	-- PLAY PRIVATE MATCH while a world is being built
	local building = self:_deploying()
	self.play.Text = if building then tracked("DEPLOYING…", " ") else "▶   " .. tracked("PLAY PRIVATE MATCH", " ")
end

-- ---------------------------------------------------------------------------------------------
-- Right: featured offers
-- ---------------------------------------------------------------------------------------------

function MenuHub._offer(self, parent: Instance, y: number, title: string, sub: string, art: string, on: () -> ())
	local row = make("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = C.row,
		Position = UDim2.fromOffset(16, y),
		Size = UDim2.new(1, -32, 0, 68),
		ZIndex = 3,
	}, parent)
	corner(row, 3)
	local st = stroke(row)
	local pic = make("ImageLabel", {
		BackgroundTransparency = 1,
		Image = art,
		Position = UDim2.fromOffset(8, 6),
		Size = UDim2.fromOffset(70, 56),
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = 4,
	}, row)
	local t = text(row, tracked(title, ""), 15, Enum.FontWeight.Heavy, C.text, {
		Position = UDim2.fromOffset(88, 12),
		Size = UDim2.new(1, -170, 0, 20),
	})
	local s = text(row, sub, 12, Enum.FontWeight.Heavy, C.text2, {
		Position = UDim2.fromOffset(88, 36),
		Size = UDim2.new(1, -170, 0, 18),
	})
	row.MouseEnter:Connect(function()
		tween(row, 0.12, { BackgroundColor3 = C.row_hover })
	end)
	row.MouseLeave:Connect(function()
		tween(row, 0.18, { BackgroundColor3 = C.row })
	end)
	row.Activated:Connect(function()
		self.ctx:sfx("click")
		on()
	end)
	return { row = row, stroke = st, pic = pic, title = t, sub = s }
end

local function tag(parent: Instance, s: string, color: Color3, bg: Color3): (Frame, TextLabel)
	local f = make("Frame", {
		BackgroundColor3 = bg,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(62, 34),
		ZIndex = 4,
	}, parent)
	corner(f, 3)
	stroke(f, color)
	local l = text(f, s, 15, Enum.FontWeight.Heavy, color, {
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 5,
	})
	return f, l
end

function MenuHub._build_right(self)
	local p = panel(self.canvas, { Name = "Featured", Size = UDim2.fromOffset(358, 282) })
	self.right = p
	panel_head(p, "FEATURED", "OFFERS")
	local T = self.title
	self.offer_shop = self:_offer(p, 46, "ITEM SHOP", "NEW IN 0:00:00", ItemShopPanel.ICON, function()
		T.open_shop:Fire()
	end)
	self.offer_shop.sub.TextColor3 = C.gold
	local _, shop_l = tag(self.offer_shop.row, "SHOP", C.green, C.green_bg)
	shop_l.TextSize = 13
	self.offer_crates = self:_offer(p, 122, "CRATES", "COSMETICS", ItemShopPanel.COIN_ART[3] or ItemShopPanel.ICON, function()
		T.open_locker:Fire()
	end)
	self.crate_tag, self.crate_l = tag(self.offer_crates.row, "0", C.gold, C.gold_bg)
	self.offer_quests = self:_offer(p, 198, "WEEKLY QUESTS", "BIG COIN REWARDS", QuestPanel.ICON, function()
		T.open_arsenal:Fire()
	end)
	self.offer_quests.stroke.Color = Color3.fromHex("3E66B8")
	self.quest_tag, self.quest_l = tag(self.offer_quests.row, "0", C.blue_text, Color3.fromHex("1A2A4D"))
end

function MenuHub._refresh_offers(self)
	local now = os.time()
	self.offer_shop.sub.Text = "NEW IN " .. hms(86400 - now % 86400)
	local s = self.ctx.session
	local crates = s and s.credits and tonumber(s.credits.crate) or 0
	self.crate_l.Text = "×" .. tostring(crates)
	self.crate_tag.Visible = crates > 0
	self.offer_crates.sub.Text = if crates > 0 then "READY TO OPEN" else "COSMETICS"
	local ready = 0
	for _, it in (s and s.quests and s.quests.list) or {} do
		if not it.claimed and (it.progress or 0) >= (it.goal or 1) then
			ready += 1
		end
	end
	self.quest_l.Text = tostring(ready)
	self.quest_tag.Visible = ready > 0
	self.offer_quests.sub.Text = if ready > 0 then "READY TO CLAIM" else "BIG COIN REWARDS"
end

-- ---------------------------------------------------------------------------------------------
-- Bottom row
-- ---------------------------------------------------------------------------------------------

function MenuHub._build_nav(self)
	local nav = make("Frame", { Name = "Nav", BackgroundTransparency = 1, Size = UDim2.fromOffset(806, 96), ZIndex = 2 }, self.canvas)
	self.nav = nav
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, nav)
	local T = self.title
	local items = {
		{ "PARTY", "users", "nav", 112, function()
			if T._party.state == nil then
				self:show_toast("Parties are offline right now. Try again in a moment.")
				return
			end
			T._party:set_visible(true)
			T._party:open_list()
		end },
		{ "INVITE", "alliance", "nav", 112, function()
			self:_invite()
		end },
		{ "COMING SOON!", "defense", "nav_gold", 140, function()
			self:show_toast("New modes are on the way. Stay tuned!")
		end },
		{ "SHOP", nil, "nav_green", 112, function()
			T.open_shop:Fire()
		end },
		{ "LEADERBOARD", "leaderboard", "nav", 140, function()
			self:show_toast("Global leaderboards are coming soon!")
		end },
		{ "REWARDS", "crown", "nav", 112, function()
			T.open_arsenal:Fire()
		end },
	}
	self.nav_buttons = {}
	for i, it in items do
		local b = button(nav, "", it[3], 13, {
			Size = UDim2.fromOffset(it[4], 96),
			LayoutOrder = i,
		})
		b.BackgroundTransparency = 0.03
		local st = STYLES[it[3]]
		if it[2] ~= nil then
			icon(b, it[2], 32, st.fg, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 18) })
		else
			make("ImageLabel", {
				BackgroundTransparency = 1,
				Image = ItemShopPanel.ICON,
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 14),
				Size = UDim2.fromOffset(40, 40),
				ScaleType = Enum.ScaleType.Fit,
				ZIndex = 5,
			}, b)
		end
		text(b, tracked(it[1], ""), 13, Enum.FontWeight.Heavy, st.fg, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 62),
			Size = UDim2.new(1, -8, 0, 20),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 5,
		})
		b.Activated:Connect(function()
			self.ctx:sfx("click")
			it[5]()
		end)
		self.nav_buttons[it[1]] = b
	end
end

function MenuHub._invite(self)
	local lp = Players.LocalPlayer
	if lp == nil then
		return
	end
	local ok, can = pcall(function()
		return SocialService:CanSendGameInviteAsync(lp)
	end)
	if ok and can then
		pcall(function()
			SocialService:PromptGameInvite(lp)
		end)
	else
		self:show_toast("Invites aren't available right now.")
	end
end

function MenuHub.show_toast(self, s: string)
	local t = self.toast
	t.Text = s
	t.Visible = true
	t.TextTransparency = 0
	t.BackgroundTransparency = 0.05
	self._toast_at = os.clock()
end

-- ---------------------------------------------------------------------------------------------
-- PRIVATE MATCH window
-- ---------------------------------------------------------------------------------------------

MenuHub.DIFFS = {
	{ id = 0, name = "RELAXED", skulls = 1 },
	{ id = 1, name = "STANDARD", skulls = 2 },
	{ id = 2, name = "BRUTAL", skulls = 3 },
}

function MenuHub._build_private(self)
	local dim = make("TextButton", {
		Name = "PrivateMatch",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 20,
	}, self.canvas)
	self.pm = dim
	dim.Activated:Connect(function()
		self:close_private()
	end)
	local p = make("TextButton", { -- (a button: a click inside doesn't reach the dim)
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = C.panel,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(780, 700),
		ZIndex = 21,
	}, dim)
	self.pm_panel = p
	corner(p, 3)
	stroke(p, Color3.fromHex("343842"))
	self.pm_pop = make("UIScale", {}, p)
	local function z(o)
		for _, d in o:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex += 20
			end
		end
		if o:IsA("GuiObject") then
			o.ZIndex += 20
		end
	end
	text(p, "PRIVATE MATCH", 28, Enum.FontWeight.Bold, C.text, {
		FontFace = PIXEL,
		Position = UDim2.fromOffset(26, 26),
		Size = UDim2.new(1, -120, 0, 40),
	})
	local close = button(p, "", "dark", 22, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 22),
		Size = UDim2.fromOffset(56, 56),
	})
	icon(close, "close", 22, C.text, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 5 })
	close.Activated:Connect(function()
		self:close_private()
	end)
	-- the map
	local mrow = make("Frame", { BackgroundColor3 = C.row, Position = UDim2.fromOffset(26, 96), Size = UDim2.new(1, -52, 0, 100), ZIndex = 3 }, p)
	corner(mrow, 3)
	stroke(mrow)
	self.pm_thumb = make("ImageLabel", {
		BackgroundColor3 = C.bar_bg,
		Position = UDim2.fromOffset(18, 15),
		Size = UDim2.fromOffset(72, 70),
		ScaleType = Enum.ScaleType.Crop,
		ZIndex = 4,
	}, mrow)
	self.pm_map = text(mrow, "WORLD", 22, Enum.FontWeight.Heavy, C.text, { Position = UDim2.fromOffset(110, 24), Size = UDim2.new(1, -290, 0, 28) })
	self.pm_map_sub = text(mrow, "", 14, Enum.FontWeight.Bold, C.text2, { Position = UDim2.fromOffset(110, 56), Size = UDim2.new(1, -290, 0, 20) })
	local change = button(mrow, tracked("CHANGE", ""), "dark", 16, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -18, 0.5, 0),
		Size = UDim2.fromOffset(134, 58),
	})
	change.Activated:Connect(function()
		self.ctx:sfx("click")
		self.title.pick_map:Fire()
	end)
	-- who plays: just you (a party plays public matches together: INVITE opens the party)
	local prow = make("Frame", { BackgroundColor3 = C.row, Position = UDim2.fromOffset(26, 210), Size = UDim2.new(1, -52, 0, 82), ZIndex = 3 }, p)
	corner(prow, 3)
	stroke(prow)
	self.pm_avatar = make("ImageLabel", {
		BackgroundColor3 = Color3.fromHex("2A2E36"),
		Position = UDim2.fromOffset(16, 15),
		Size = UDim2.fromOffset(52, 52),
		ZIndex = 4,
	}, prow)
	corner(self.pm_avatar, 26)
	text(prow, tracked("JUST YOU", ""), 17, Enum.FontWeight.Heavy, C.text, { Position = UDim2.fromOffset(84, 16), Size = UDim2.new(1, -260, 0, 22) })
	text(prow, "You against the AI nations. Invite friends to your party for public matches.", 13, Enum.FontWeight.Medium, C.text2, {
		Position = UDim2.fromOffset(84, 44),
		Size = UDim2.new(1, -260, 0, 18),
	})
	local inv = button(prow, tracked("INVITE", ""), "dark", 16, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -18, 0.5, 0),
		Size = UDim2.fromOffset(134, 58),
	})
	inv.Activated:Connect(function()
		self.ctx:sfx("click")
		self:_invite()
	end)
	-- difficulty
	text(p, tracked("DIFFICULTY", ""), 14, Enum.FontWeight.Heavy, C.text2, { Position = UDim2.fromOffset(26, 306), Size = UDim2.new(1, -52, 0, 20) })
	self.pm_diffs = {}
	local dw = (780 - 52 - 2 * 14) / 3
	for i, d in MenuHub.DIFFS do
		local b, bline = button(p, "", "dark", 14, {
			Position = UDim2.fromOffset(26 + (i - 1) * (dw + 14), 334),
			Size = UDim2.fromOffset(dw, 78),
		})
		local skulls = make("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 12),
			Size = UDim2.fromOffset(90, 28),
			ZIndex = 5,
		}, b)
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 4),
		}, skulls)
		local sk = {}
		for k = 1, 3 do
			sk[k] = icon(skulls, "skull", 26, C.text3, { LayoutOrder = k, ZIndex = 6 })
		end
		local n = text(b, tracked(d.name, ""), 14, Enum.FontWeight.Heavy, C.text2, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 46),
			Size = UDim2.new(1, -8, 0, 20),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 6,
		})
		b.Activated:Connect(function()
			self.ctx:sfx("click")
			self:_set_difficulty(d.id)
		end)
		self.pm_diffs[i] = { btn = b, line = bline, skulls = sk, name = n, def = d }
	end
	self.pm_desc = text(p, "", 15, Enum.FontWeight.Medium, Color3.fromHex("C9CFDB"), {
		Position = UDim2.fromOffset(26, 422),
		Size = UDim2.new(1, -52, 0, 44),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
	})
	-- LAND TO WIN
	text(p, tracked("LAND TO WIN", ""), 14, Enum.FontWeight.Heavy, C.text2, { Position = UDim2.fromOffset(26, 482), Size = UDim2.fromOffset(170, 20) })
	self.pm_win = text(p, "80%", 22, Enum.FontWeight.Heavy, C.gold, { Position = UDim2.fromOffset(26, 504), Size = UDim2.fromOffset(170, 28) })
	local minus = button(p, "−", "dark", 24, { Position = UDim2.fromOffset(212, 482), Size = UDim2.fromOffset(56, 56) })
	local plus = button(p, "+", "dark", 24, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -26, 0, 482), Size = UDim2.fromOffset(56, 56) })
	local track = make("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = C.bar_bg,
		Position = UDim2.fromOffset(284, 502),
		Size = UDim2.new(1, -284 - 26 - 56 - 16, 0, 14),
		ZIndex = 4,
	}, p)
	corner(track, 7)
	stroke(track, Color3.fromHex("3A3E48"))
	self.pm_track = track
	self.pm_fill = make("Frame", { BackgroundColor3 = C.gold_bg, BorderSizePixel = 0, Size = UDim2.fromScale(0.5, 1), ZIndex = 5 }, track)
	corner(self.pm_fill, 7)
	self.pm_knob = make("Frame", {
		BackgroundColor3 = C.gold,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(30, 30),
		ZIndex = 6,
	}, track)
	corner(self.pm_knob, 15)
	local function step(d: number)
		self.ctx:sfx("click")
		self:_set_win(self:_win() + d)
	end
	minus.Activated:Connect(function()
		step(-0.05)
	end)
	plus.Activated:Connect(function()
		step(0.05)
	end)
	local dragging = false
	local function from_x(x: number)
		local a = track.AbsolutePosition.X
		local w = math.max(track.AbsoluteSize.X, 1)
		local t = math.clamp((x - a) / w, 0, 1)
		self:_set_win(MenuHub.WIN_MIN + t * (MenuHub.WIN_MAX - MenuHub.WIN_MIN))
	end
	track.InputBegan:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			from_x(io.Position.X)
		end
	end)
	game:GetService("UserInputService").InputChanged:Connect(function(io)
		if dragging and (io.UserInputType == Enum.UserInputType.MouseMovement or io.UserInputType == Enum.UserInputType.Touch) then
			from_x(io.Position.X)
		end
	end)
	game:GetService("UserInputService").InputEnded:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	-- what the match pays (the solo coins scale with difficulty: Data/Quests' "win on Brutal" etc.)
	self.pm_note = text(p, "", 15, Enum.FontWeight.Bold, C.text2, {
		Position = UDim2.fromOffset(26, 552),
		Size = UDim2.new(1, -52, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local start = button(p, "▶   " .. tracked("START", " "), "gold", 24, {
		Position = UDim2.fromOffset(26, 594),
		Size = UDim2.new(1, -52, 0, 80),
	})
	self.pm_start = start
	start.Activated:Connect(function()
		self.title.play_solo:Fire(self.title.difficulty)
	end)
	z(p)
end

function MenuHub._win(self): number
	return math.clamp(tonumber(self.ctx:setting("win_share", MenuHub.WIN_DEFAULT)) or MenuHub.WIN_DEFAULT, MenuHub.WIN_MIN, MenuHub.WIN_MAX)
end

function MenuHub._set_win(self, v: number)
	v = math.clamp(math.floor(v * 100 + 0.5) / 100, MenuHub.WIN_MIN, MenuHub.WIN_MAX)
	self.ctx:set_setting("win_share", v)
	self:_refresh_private()
end

function MenuHub._set_difficulty(self, id: number)
	local t = self.title
	t.difficulty = id
	for j, ch in ipairs(t._chips) do
		ch:set_pressed_no_signal(j - 1 == id)
	end
	self.ctx:set_setting("difficulty", id)
	t:_refresh_diff()
	self:_refresh_private()
end

function MenuHub._refresh_private(self)
	local t = self.title
	local id = UIMaps.valid(self.ctx:setting("map_id", UIMaps.DEFAULT_ID))
	local e = UIMaps.get(id)
	self.pm_map.Text = tracked(string.upper(e and e.name or "World"), "")
	local size = if e and e.width and e.height then string.format("%d × %d  ·  ", e.width, e.height) else ""
	self.pm_map_sub.Text = size .. "YOU VS AI NATIONS"
	self.pm_thumb.Image = (e and e.thumb) or ""
	for _, d in self.pm_diffs do
		local on = d.def.id == t.difficulty
		restyle(d.btn, if on then "sel" else "dark")
		d.name.TextColor3 = if on then C.text else C.text2
		for k, sk in d.skulls do
			sk.ImageColor3 = if k <= d.def.skulls then Color3.fromHex("E5484D") else C.text3
		end
	end
	self.pm_desc.Text = t._diff_desc:get_text()
	local w = self:_win()
	self.pm_win.Text = string.format("%d%%", math.floor(w * 100 + 0.5))
	local f = (w - MenuHub.WIN_MIN) / (MenuHub.WIN_MAX - MenuHub.WIN_MIN)
	self.pm_knob.Position = UDim2.fromScale(f, 0.5)
	self.pm_fill.Size = UDim2.fromScale(f, 1)
	self.pm_note.Text = string.format("Own %d%% of the land to win  ·  %s", math.floor(w * 100 + 0.5), (e and e.name) or "World")
	local building = self:_deploying()
	self.pm_start.Text = if building then tracked("DEPLOYING…", " ") else "▶   " .. tracked("START", " ")
	self.pm_start.Active = not building
end

--- A solo match is being built (TitleScreen.set_building; the title's own globe builds quietly).
function MenuHub._deploying(self): boolean
	local st = self.title._start
	return st ~= nil and st.text == "DEPLOYING…"
end

function MenuHub.open_private(self)
	self.ctx:sfx("open")
	self:_refresh_private()
	self.pm.Visible = true
	self.pm.BackgroundTransparency = 1
	tween(self.pm, 0.2, { BackgroundTransparency = 0.5 })
	local fit = self:_pm_fit()
	self.pm_pop.Scale = fit * 0.94
	tween(self.pm_pop, 0.25, { Scale = fit })
end

--- The PRIVATE MATCH window's scale: it fits between the screen's top and bottom.
function MenuHub._pm_fit(self): number
	local H = self.canvas.Size.Y.Offset
	return math.clamp((H - 40) / 700, 0.5, 1)
end

function MenuHub.close_private(self, quiet: boolean?)
	if not self.pm.Visible then
		return
	end
	if not quiet then
		self.ctx:sfx("close")
	end
	self.pm.Visible = false
end

-- ---------------------------------------------------------------------------------------------
-- Layout and updates
-- ---------------------------------------------------------------------------------------------

function MenuHub.layout(self)
	local abs = self.root.AbsoluteSize
	if abs.X < 10 or abs.Y < 10 then
		return
	end
	local ctx = self.ctx
	-- fit the reference size; any UIScale above the hub is undone
	local k = 1
	local up = self.root.Parent
	while up ~= nil and up:IsA("GuiObject") do
		local u = up:FindFirstChildOfClass("UIScale")
		if u ~= nil then
			k *= u.Scale
		end
		up = up.Parent
	end
	local compact = ctx.compact or abs.X < 1100 or abs.Y < 640
	self.compact = compact
	local ref = if compact then MenuHub.REF_COMPACT else MenuHub.REF
	local s = math.clamp(math.min(abs.X / ref.X, abs.Y / ref.Y), 0.35, 1.6)
	local unit = s / k
	self.scale.Scale = unit
	-- (in design units the canvas is abs / s wide)
	local W, H = abs.X / s, abs.Y / s
	self.canvas.Size = UDim2.fromOffset(W, H)
	self.canvas.Position = UDim2.fromOffset(0, 0)
	self.left.Visible = not compact
	self.right.Visible = not compact
	self.who.Visible = W > 1300
	local top = 68 + 26
	self.left.Position = UDim2.fromOffset(22, top)
	self.right.AnchorPoint = Vector2.new(1, 0)
	self.right.Position = UDim2.new(0, W - 22, 0, top)
	self.center.AnchorPoint = Vector2.new(0.5, 0)
	self.center.Position = UDim2.fromOffset(W * 0.5, top)
	self.nav.AnchorPoint = Vector2.new(0.5, 1)
	self.nav.Position = UDim2.fromOffset(W * 0.5, H - 22)
	self.credits.Position = UDim2.new(0.5, 0, 1, -3)
	-- phones: the matches panel shrinks to fit between the top bar and the bottom row
	if compact then
		local room = H - top - 96 - 22 - 16
		local sc = math.clamp(room / 486, 0.6, 1)
		local fit = self.center:FindFirstChild("Fit") or make("UIScale", { Name = "Fit" }, self.center)
		fit.Scale = sc
		self.center.Position = UDim2.fromOffset(W * 0.5, top - 10 * (1 - sc))
	else
		local fit = self.center:FindFirstChild("Fit")
		if fit then
			fit.Scale = 1
		end
	end
end

function MenuHub._step(self, dt: number)
	local t = self.title
	local on = t.visible and not self.ctx:mp_waiting()
	if self.root.Visible ~= on then
		self.root.Visible = on
		if not on then
			self:close_private(true)
		end
	end
	if not on then
		return
	end
	if self._toast_at ~= nil and os.clock() - self._toast_at > 2.4 then
		self._toast_at = nil
		tween(self.toast, 0.3, { TextTransparency = 1, BackgroundTransparency = 1 })
		task.delay(0.3, function()
			if self._toast_at == nil then
				self.toast.Visible = false
			end
		end)
	end
	self._acc += dt
	if self._acc < 0.25 then
		return
	end
	self._acc = 0
	local ctx = self.ctx
	local s = ctx.session
	-- the player
	local lp = Players.LocalPlayer
	self.name.Text = if lp then lp.DisplayName else ctx:username()
	local general = s ~= nil and s.general == true
	local admin = s ~= nil and s.admin_bots ~= nil
	self.rank.Text = string.format(
		'<font color="#F2C94C">%s</font>  ·  World Conquest%s',
		if general then "General" else "Commander",
		if admin then "  ·  Admin" else ""
	)
	local coins = s and s.inventory and tonumber(s.inventory.stars) or 0
	self.coins.Text = commas(coins)
	local cw = math.max(92, 52 + 12 * #self.coins.Text)
	self.coins_btn.Size = UDim2.fromOffset(cw, 50)
	self.who.Position = UDim2.new(1, -(cw + 30), 0.5, 0)
	self:_refresh_quests()
	self:_refresh_matches()
	self:_refresh_offers()
	if self.pm.Visible then
		self:_refresh_private()
	end
end

function MenuHub.destroy(self)
	if self._conn then
		self._conn:Disconnect()
	end
	self.root:Destroy()
end

return MenuHub
