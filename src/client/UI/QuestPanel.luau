--!nonstrict
-- (Take Over the World!: daily and weekly quests, 2026-11-06; the QUESTS button replaces the Arsenal.
-- Laid out again 2026-11-08: a header, DAILY / WEEKLY tabs with their reset timers, and one big card a
-- quest.)
-- The player's active quests (server/Purchases.quests via OP.QUESTS: Session.quests), each with its
-- progress and coin reward; CLAIM asks the server (Session.claim_quest), which checks and pays.
--   card: an icon tile (a tick once done) | the quest and a progress bar with its count | the coins
--   and the CLAIM button. A card ready to claim glows amber; a claimed one dims.
local RunService = game:GetService("RunService")
local UITheme = require("./UITheme")
local Anim = require("./Anim") -- (the dim fades in, the panel rises, the cards pop up in turn)

local QuestPanel = {}
QuestPanel.__index = QuestPanel

QuestPanel.W, QuestPanel.H = 640, 520
QuestPanel.ICON = "rbxassetid://110859228590510" -- the quests icon
QuestPanel.CARDS = 3 -- a period's quests

local FONT = "rbxassetid://12187365977"
local NAVY = Color3.fromHex("0D1326")
local CARD = Color3.fromHex("18213D")
local AMBER = Color3.fromHex("FFB547")
local INK = Color3.fromHex("3A2400")
local TEXT = Color3.new(1, 1, 1)
local TEXT2 = Color3.fromHex("A9B4D0")
local MUTED = Color3.fromHex("2A3352")
local GREEN = Color3.fromHex("5BE38E")

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

local function label(parent: Instance, text: string, size: number, weight: Enum.FontWeight, color: Color3, props: { [string]: any }?): TextLabel
	local l = make("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextSize = size,
		FontFace = Font.new(FONT, weight),
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, 0, 0, size + 4),
		ZIndex = 43,
	}, parent)
	for k, v in props or {} do
		l[k] = v
	end
	return l
end

local function commas(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function clock(sec: number): string
	sec = math.max(0, math.floor(sec))
	local h = sec // 3600
	local m = (sec % 3600) // 60
	if h >= 24 then
		return string.format("%dd %dh", h // 24, h % 24)
	end
	return string.format("%dh %02dm", h, m)
end

function QuestPanel.new(ctx: any, gui: Instance)
	local self = setmetatable({}, QuestPanel)
	self.ctx = ctx
	self.is_open = false
	self.period = "daily"
	self.cards = {}
	local dim = make("TextButton", {
		Name = "Quests",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 40,
	}, gui)
	self.root = dim
	dim.Activated:Connect(function()
		self:close()
	end)
	-- (the holder fits small screens; the panel inside keeps its own scale for the pop)
	local holder = make("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(QuestPanel.W, QuestPanel.H),
		ZIndex = 41,
	}, dim)
	self.fit = make("UIScale", { Name = "Fit" }, holder)
	local panel = make("TextButton", { -- (a button, so a click on it doesn't reach the dim)
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = NAVY,
		BackgroundTransparency = 0.03,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 41,
	}, holder)
	self.panel = panel
	make("UICorner", { CornerRadius = UDim.new(0, 16) }, panel)
	make("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.86 }, panel)
	-- the header: a band with the icon, the title and what quests are for
	local head = make("Frame", {
		BackgroundColor3 = Color3.fromHex("1A2550"),
		Size = UDim2.new(1, 0, 0, 84),
		ZIndex = 42,
	}, panel)
	make("UICorner", { CornerRadius = UDim.new(0, 16) }, head)
	make("UIGradient", {
		Color = ColorSequence.new(Color3.fromHex("2B3C86"), Color3.fromHex("141B36")),
		Rotation = 90,
	}, head)
	make("Frame", { -- (squares the band's lower corners)
		BackgroundColor3 = Color3.fromHex("141B36"),
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 1, -16),
		Size = UDim2.new(1, 0, 0, 16),
		ZIndex = 42,
	}, head)
	make("ImageLabel", {
		BackgroundTransparency = 1,
		Image = QuestPanel.ICON,
		ScaleType = Enum.ScaleType.Fit,
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.fromOffset(68, 68),
		ZIndex = 43,
	}, head)
	local title = label(head, "QUESTS", 30, Enum.FontWeight.Heavy, TEXT, {
		Position = UDim2.fromOffset(94, 14),
		Size = UDim2.fromOffset(300, 34),
	})
	make("UIGradient", { Color = ColorSequence.new(Color3.fromHex("FFF1B8"), AMBER), Rotation = 90 }, title)
	make("UIStroke", { Color = Color3.fromHex("7A3E00"), Thickness = 2 }, title)
	self.sub = label(head, "", 13, Enum.FontWeight.Medium, TEXT2, {
		Position = UDim2.fromOffset(96, 50),
		Size = UDim2.new(1, -170, 0, 18),
	})
	local close = make("TextButton", {
		Text = "X",
		TextSize = 18,
		FontFace = Font.new(FONT, Enum.FontWeight.Heavy),
		TextColor3 = TEXT,
		BackgroundColor3 = Color3.fromHex("C83A3A"),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 20),
		Size = UDim2.fromOffset(42, 42),
		ZIndex = 44,
	}, head)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, close)
	make("UIStroke", { Color = Color3.fromHex("1B1000"), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, close)
	Anim.button(close)
	close.Activated:Connect(function()
		self:close()
	end)
	-- the tabs: DAILY / WEEKLY, each with its reset timer and a badge of quests ready to claim
	self.tabs = {}
	for i, period in { "daily", "weekly" } do
		local tab = make("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = MUTED,
			Position = UDim2.new((i - 1) * 0.5, if i == 1 then 18 else 6, 0, 98),
			Size = UDim2.new(0.5, -24, 0, 50),
			ZIndex = 42,
		}, panel)
		make("UICorner", { CornerRadius = UDim.new(0, 12) }, tab)
		local stroke = make("UIStroke", { Color = AMBER, Thickness = 2, Transparency = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, tab)
		local name = label(tab, string.upper(period), 18, Enum.FontWeight.Heavy, TEXT, {
			Position = UDim2.fromOffset(16, 6),
			Size = UDim2.new(1, -60, 0, 22),
		})
		local timer = label(tab, "", 12, Enum.FontWeight.Bold, TEXT2, {
			Position = UDim2.fromOffset(16, 28),
			Size = UDim2.new(1, -60, 0, 16),
		})
		local badge = make("TextLabel", {
			Text = "",
			TextSize = 13,
			FontFace = Font.new(FONT, Enum.FontWeight.Heavy),
			TextColor3 = TEXT,
			BackgroundColor3 = Color3.fromHex("E5484D"),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(26, 26),
			Visible = false,
			ZIndex = 43,
		}, tab)
		make("UICorner", { CornerRadius = UDim.new(1, 0) }, badge)
		Anim.button(tab, nil, 1.03)
		tab.Activated:Connect(function()
			if self.period ~= period then
				self.period = period
				self.ctx:sfx("click")
				self:refresh()
				for j, c in self.cards do
					Anim.pop(c.card, (j - 1) * 0.05, 0.85)
				end
			end
		end)
		self.tabs[period] = { tab = tab, stroke = stroke, name = name, timer = timer, badge = badge }
	end
	-- the cards
	for j = 1, QuestPanel.CARDS do
		local card = make("Frame", {
			BackgroundColor3 = CARD,
			Position = UDim2.fromOffset(18, 162 + (j - 1) * 112),
			Size = UDim2.new(1, -36, 0, 100),
			ZIndex = 42,
		}, panel)
		make("UICorner", { CornerRadius = UDim.new(0, 14) }, card)
		local stroke = make("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.9, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, card)
		-- the icon tile: the quest's number, a tick once it is done
		local tile = make("Frame", {
			BackgroundColor3 = Color3.fromHex("26315A"),
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 14, 0.5, 0),
			Size = UDim2.fromOffset(68, 68),
			ZIndex = 43,
		}, card)
		make("UICorner", { CornerRadius = UDim.new(0, 12) }, tile)
		local mark = make("TextLabel", {
			BackgroundTransparency = 1,
			Text = tostring(j),
			TextSize = 30,
			FontFace = Font.new(FONT, Enum.FontWeight.Heavy),
			TextColor3 = TEXT2,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 44,
		}, tile)
		local text = label(card, "", 17, Enum.FontWeight.Bold, TEXT, {
			Position = UDim2.fromOffset(96, 14),
			Size = UDim2.new(1, -250, 0, 22),
		})
		-- the progress bar, its count inside
		local track = make("Frame", {
			BackgroundColor3 = Color3.fromHex("0A0F20"),
			Position = UDim2.fromOffset(96, 50),
			Size = UDim2.new(1, -250, 0, 26),
			ZIndex = 43,
		}, card)
		make("UICorner", { CornerRadius = UDim.new(1, 0) }, track)
		make("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.88 }, track)
		local fill = make("Frame", { BackgroundColor3 = GREEN, Size = UDim2.fromScale(0, 1), ZIndex = 44 }, track)
		make("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)
		make("UIGradient", { Color = ColorSequence.new(Color3.fromHex("8DF0B4"), GREEN), Rotation = 90 }, fill)
		local count = make("TextLabel", {
			BackgroundTransparency = 1,
			Text = "",
			TextSize = 14,
			FontFace = Font.new(FONT, Enum.FontWeight.Heavy),
			TextColor3 = TEXT,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 45,
		}, track)
		make("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1.2, Transparency = 0.3 }, count)
		-- the reward and the button
		local reward = make("Frame", {
			BackgroundColor3 = Color3.fromHex("2A2410"),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 12),
			Size = UDim2.fromOffset(126, 30),
			ZIndex = 43,
		}, card)
		make("UICorner", { CornerRadius = UDim.new(1, 0) }, reward)
		make("ImageLabel", {
			BackgroundTransparency = 1,
			Image = UITheme.icon("gold") or "",
			ImageColor3 = AMBER,
			ScaleType = Enum.ScaleType.Fit,
			Position = UDim2.fromOffset(8, 5),
			Size = UDim2.fromOffset(20, 20),
			ZIndex = 44,
		}, reward)
		local coins = label(reward, "", 15, Enum.FontWeight.Heavy, AMBER, {
			Position = UDim2.fromOffset(32, 5),
			Size = UDim2.new(1, -40, 0, 20),
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 44,
		})
		local btn = make("TextButton", {
			Text = "CLAIM",
			TextSize = 15,
			FontFace = Font.new(FONT, Enum.FontWeight.Heavy),
			TextColor3 = INK,
			BackgroundColor3 = AMBER,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 50),
			Size = UDim2.fromOffset(126, 36),
			ZIndex = 43,
			Selectable = true,
		}, card)
		make("UICorner", { CornerRadius = UDim.new(0, 10) }, btn)
		local c = {
			card = card,
			stroke = stroke,
			tile = tile,
			mark = mark,
			text = text,
			fill = fill,
			count = count,
			coins = coins,
			button = btn,
			id = nil,
			ready = false,
		}
		Anim.button(btn)
		btn.Activated:Connect(function()
			if c.id ~= nil and c.ready then
				local s = self.ctx.session
				if s ~= nil and type(s.claim_quest) == "function" then
					s:claim_quest(c.id)
					self.ctx:sfx("click")
					btn.Text = "…"
				end
			else
				self.ctx:sfx("deny", -4.0)
			end
		end)
		self.cards[j] = c
	end
	self._acc = 0
	self._conn = RunService.Heartbeat:Connect(function(dt)
		if not self.is_open then
			return
		end
		self._acc += dt
		if self._acc >= 0.5 then
			self._acc = 0
			self:refresh()
		end
	end)
	return self
end

--- Quests ready to claim (for the button's badge); `period`: only that period's.
function QuestPanel.claimable(self, period: string?): number
	local s = self.ctx.session
	local q = s and s.quests
	local n = 0
	for _, it in (q and q.list) or {} do
		if not it.claimed and (it.progress or 0) >= (it.goal or 1) and (period == nil or it.period == period) then
			n += 1
		end
	end
	return n
end

--- Fits the panel to small screens.
function QuestPanel._fit(self)
	local cam = workspace.CurrentCamera
	local vp = if cam then cam.ViewportSize else Vector2.new(1280, 720)
	self.fit.Scale = math.min(1, (vp.X - 24) / QuestPanel.W, (vp.Y - 70) / QuestPanel.H)
end

function QuestPanel.refresh(self)
	local s = self.ctx.session
	local q = s and s.quests
	local list = (q and q.list) or {}
	local now = os.time()
	local day_left = 86400 - now % 86400
	-- (weeks start on Monday, UTC: the epoch was a Thursday)
	local week_left = (7 - (now // 86400 + 3) % 7) * 86400 - now % 86400
	for period, t in self.tabs do
		local on = period == self.period
		t.tab.BackgroundColor3 = if on then Color3.fromHex("2B3C86") else MUTED
		t.stroke.Transparency = if on then 0 else 1
		t.name.TextColor3 = if on then AMBER else TEXT
		t.timer.Text = "New in " .. clock(if period == "daily" then day_left else week_left)
		local n = self:claimable(period)
		t.badge.Visible = n > 0
		t.badge.Text = tostring(n)
	end
	local mine = {}
	for _, it in list do
		if it.period == self.period then
			table.insert(mine, it)
		end
	end
	for j, c in self.cards do
		local it = mine[j]
		c.card.Visible = it ~= nil
		if it == nil then
			continue
		end
		c.id = it.id
		c.text.Text = it.text
		c.coins.Text = "+" .. commas(it.reward)
		local p = math.clamp((it.progress or 0) / math.max(it.goal or 1, 1), 0, 1)
		c.fill.Size = UDim2.fromScale(math.max(p, 0.001), 1)
		c.fill.Visible = p > 0
		c.count.Text = string.format("%s / %s", commas(it.progress or 0), commas(it.goal or 1))
		c.ready = not it.claimed and p >= 1
		local btn = c.button
		if it.claimed then
			btn.Text = "CLAIMED"
			btn.BackgroundColor3 = MUTED
			btn.TextColor3 = GREEN
			c.mark.Text = "✓"
			c.mark.TextColor3 = GREEN
			c.tile.BackgroundColor3 = Color3.fromHex("1D3B2E")
			c.stroke.Color, c.stroke.Transparency = Color3.new(1, 1, 1), 0.92
			c.card.BackgroundTransparency = 0.35
		elseif c.ready then
			if btn.Text ~= "…" then
				btn.Text = "CLAIM"
			end
			btn.BackgroundColor3 = AMBER
			btn.TextColor3 = INK
			c.mark.Text = "★"
			c.mark.TextColor3 = AMBER
			c.tile.BackgroundColor3 = Color3.fromHex("3A2E10")
			c.stroke.Color, c.stroke.Transparency = AMBER, 0.15
			c.card.BackgroundTransparency = 0
		else
			btn.Text = "IN PROGRESS"
			btn.TextSize = 12
			btn.BackgroundColor3 = MUTED
			btn.TextColor3 = TEXT2
			c.mark.Text = tostring(j)
			c.mark.TextColor3 = TEXT2
			c.tile.BackgroundColor3 = Color3.fromHex("26315A")
			c.stroke.Color, c.stroke.Transparency = Color3.new(1, 1, 1), 0.9
			c.card.BackgroundTransparency = 0
		end
		if btn.Text ~= "IN PROGRESS" then
			btn.TextSize = 15
		end
	end
	if #list == 0 then
		self.sub.Text = "Loading your quests…"
	else
		self.sub.Text = "Play matches to finish quests, then claim their coins."
	end
end

function QuestPanel.open(self)
	self.is_open = true
	self:_fit()
	self:refresh()
	Anim.open(self.root, self.panel)
	for j, c in self.cards do
		Anim.pop(c.card, Anim.FADE_S * 0.6 + 0.1 + j * 0.06, 0.7)
	end
	for _, t in self.tabs do
		Anim.pop(t.tab, Anim.FADE_S * 0.6 + 0.05, 0.8)
	end
	self.ctx:sfx("open")
end

function QuestPanel.close(self)
	if not self.is_open then
		return
	end
	self.is_open = false
	Anim.close(self.root, self.panel)
	self.ctx:sfx("close")
end

return QuestPanel
