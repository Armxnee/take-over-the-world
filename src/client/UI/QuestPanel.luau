--!nonstrict
-- (Take Over the World!: daily and weekly quests, 2026-11-06; the QUESTS button replaces the Arsenal.)
-- The player's active quests (server/Purchases.quests via OP.QUESTS: Session.quests), each with its
-- progress and coin reward; CLAIM asks the server (Session.claim_quest), which checks and pays.
local RunService = game:GetService("RunService")
local Anim = require("./Anim") -- (Take Over the World!: the dim fades in, the panel and its rows pop up)

local QuestPanel = {}
QuestPanel.__index = QuestPanel

local FONT = "rbxassetid://12187365977"
local NAVY = Color3.fromHex("0D1326")
local AMBER = Color3.fromHex("FFB547")
local TEXT = Color3.new(1, 1, 1)
local TEXT2 = Color3.fromHex("A9B4D0")
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
	self.rows = {}
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
	local panel = make("Frame", {
		BackgroundColor3 = NAVY,
		BackgroundTransparency = 0.04,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(480, 470),
		ZIndex = 41,
	}, dim)
	self.panel = panel
	make("UICorner", { CornerRadius = UDim.new(0, 14) }, panel)
	make("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.85 }, panel)
	make("UIPadding", { PaddingTop = UDim.new(0, 16), PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18), PaddingBottom = UDim.new(0, 16) }, panel)
	label(panel, "QUESTS", 22, Enum.FontWeight.Heavy, AMBER, { ZIndex = 42 })
	self.sub = label(panel, "Finish matches to complete quests, then claim their coins.", 12, Enum.FontWeight.Medium, TEXT2, { Position = UDim2.fromOffset(0, 28), ZIndex = 42 })
	local close = make("TextButton", {
		Text = "X",
		TextSize = 16,
		FontFace = Font.new(FONT, Enum.FontWeight.Heavy),
		TextColor3 = TEXT,
		BackgroundColor3 = Color3.fromHex("2A3352"),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(30, 30),
		ZIndex = 42,
	}, panel)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, close)
	Anim.button(close)
	close.Activated:Connect(function()
		self:close()
	end)
	self.heads = {}
	for i, period in { "daily", "weekly" } do
		local y = if i == 1 then 54 else 258
		self.heads[period] = label(panel, "", 13, Enum.FontWeight.Heavy, TEXT2, { Position = UDim2.fromOffset(0, y), ZIndex = 42 })
		for j = 1, 3 do
			local ry = y + 22 + (j - 1) * 60
			local row = make("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.94, Position = UDim2.fromOffset(0, ry), Size = UDim2.new(1, 0, 0, 54), ZIndex = 42 }, panel)
			make("UICorner", { CornerRadius = UDim.new(0, 10) }, row)
			local text = label(row, "", 14, Enum.FontWeight.Bold, TEXT, { Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -130, 0, 18), ZIndex = 43 })
			local reward = label(row, "", 12, Enum.FontWeight.Bold, AMBER, { Position = UDim2.fromOffset(12, 30), Size = UDim2.fromOffset(110, 16), ZIndex = 43 })
			local track = make("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.88, Position = UDim2.fromOffset(124, 35), Size = UDim2.new(1, -304, 0, 8), ZIndex = 43 }, row)
			make("UICorner", { CornerRadius = UDim.new(1, 0) }, track)
			local fill = make("Frame", { BackgroundColor3 = GREEN, Size = UDim2.fromScale(0, 1), ZIndex = 44 }, track)
			make("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)
			local count = label(row, "", 11, Enum.FontWeight.Bold, TEXT2, { Position = UDim2.new(1, -172, 0, 30), Size = UDim2.fromOffset(66, 16), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 43 })
			local btn = make("TextButton", {
				Text = "CLAIM",
				TextSize = 13,
				FontFace = Font.new(FONT, Enum.FontWeight.Heavy),
				TextColor3 = Color3.fromHex("3A2400"),
				BackgroundColor3 = AMBER,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.fromOffset(92, 34),
				ZIndex = 43,
				Selectable = true,
			}, row)
			make("UICorner", { CornerRadius = UDim.new(0, 8) }, btn)
			local r = { row = row, text = text, reward = reward, fill = fill, count = count, button = btn, id = nil }
			Anim.button(btn)
			btn.Activated:Connect(function()
				if r.id ~= nil and r.ready then
					local s = self.ctx.session
					if s ~= nil and type(s.claim_quest) == "function" then
						s:claim_quest(r.id)
						self.ctx:sfx("click")
						btn.Text = "…"
					end
				else
					self.ctx:sfx("deny", -4.0)
				end
			end)
			table.insert(self.rows, { period = period, slot = j, ui = r })
		end
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

--- Quests ready to claim (for the button's badge).
function QuestPanel.claimable(self): number
	local s = self.ctx.session
	local q = s and s.quests
	local n = 0
	for _, it in (q and q.list) or {} do
		if not it.claimed and (it.progress or 0) >= (it.goal or 1) then
			n += 1
		end
	end
	return n
end

function QuestPanel.refresh(self)
	local s = self.ctx.session
	local q = s and s.quests
	local list = (q and q.list) or {}
	local now = os.time()
	local day_left = 86400 - now % 86400
	-- (weeks start on Monday, UTC: the epoch was a Thursday)
	local week_left = (7 - (now // 86400 + 3) % 7) * 86400 - now % 86400
	self.heads.daily.Text = "DAILY  ·  new in " .. clock(day_left)
	self.heads.weekly.Text = "WEEKLY  ·  new in " .. clock(week_left)
	local by = { daily = {}, weekly = {} }
	for _, it in list do
		if by[it.period] then
			table.insert(by[it.period], it)
		end
	end
	for _, slot in self.rows do
		local ui = slot.ui
		local it = by[slot.period][slot.slot]
		ui.row.Visible = it ~= nil
		if it ~= nil then
			ui.id = it.id
			ui.text.Text = it.text
			ui.reward.Text = "+" .. commas(it.reward) .. " coins"
			local p = math.clamp((it.progress or 0) / math.max(it.goal or 1, 1), 0, 1)
			ui.fill.Size = UDim2.fromScale(p, 1)
			ui.count.Text = string.format("%d / %d", it.progress or 0, it.goal or 1)
			ui.ready = not it.claimed and p >= 1
			if it.claimed then
				ui.button.Text = "CLAIMED"
				ui.button.BackgroundColor3 = Color3.fromHex("2A3352")
				ui.button.TextColor3 = GREEN
			elseif ui.ready then
				if ui.button.Text ~= "…" then
					ui.button.Text = "CLAIM"
				end
				ui.button.BackgroundColor3 = AMBER
				ui.button.TextColor3 = Color3.fromHex("3A2400")
			else
				ui.button.Text = "CLAIM"
				ui.button.BackgroundColor3 = Color3.fromHex("2A3352")
				ui.button.TextColor3 = TEXT2
			end
		end
	end
	if #list == 0 then
		self.sub.Text = "Loading your quests…"
	else
		self.sub.Text = "Finish matches to complete quests, then claim their coins."
	end
end

function QuestPanel.open(self)
	self.is_open = true
	self:refresh()
	Anim.open(self.root, self.panel)
	for i, r in self.rows do
		Anim.pop(r.ui.row, Anim.FADE_S * 0.6 + 0.1 + i * 0.05, 0.6)
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
