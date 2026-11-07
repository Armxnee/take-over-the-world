--!nonstrict
-- (Take Over the World!: the military UI, 2026-11-06.)
-- Armies (Core/SimArmies) from the player's side. Everything here is a request: each button sends an
-- existing-style intent ("army_*", Net/Protocol) and the server's Sim decides.
--   ARMIES button (top left)   opens the recruit panel: battalions per type (Data/Units), their cost
--                              in gold and men, NEW ARMY in the province last clicked (default: the
--                              capital) or ADD TO the selected army
--   army panel (bottom left)   the selected army: name, country, battalions by type, health,
--                              morale, organization, supply, its orders; MOVE / ATTACK (then click the
--                              map), RETREAT, REINFORCE, MERGE, DISBAND
--   map                        click an army to select it; with your army selected a right click
--                              orders it there (your land: move, anyone else's: attack); Esc cancels
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
local Airfront = RS:WaitForChild("Airfront")
local Defs = require(Airfront.Core.Defs)
local Units = require(Airfront.Data.Units)
local ArmySprites = require("../Map/ArmySprites")
local UnitLayer = require("../Map/UnitLayer")
local UITheme = require("./UITheme")

local ArmyPanel = {}
ArmyPanel.__index = ArmyPanel

local FONT = "rbxassetid://12187365977"
local NAVY = Color3.fromHex("0D1326")
local AMBER = Color3.fromHex("FFB547")
local TEXT = Color3.new(1, 1, 1)
local TEXT2 = Color3.fromHex("A9B4D0")
local GREEN = Color3.fromHex("5BE38E")
local RED = Color3.fromHex("FF5C61")
local CYAN = Color3.fromHex("49C6F2")
local STATUS_TEXT = { [0] = "Standing", "Marching", "In battle", "Retreating" }

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

local function glass(parent: Instance, name: string): Frame
	local f = make("Frame", { Name = name, BackgroundColor3 = NAVY, BackgroundTransparency = 0.12, BorderSizePixel = 0 }, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 12) }, f)
	make("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.88, Thickness = 1 }, f)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 12),
		PaddingBottom = UDim.new(0, 12),
		PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 14),
	}, f)
	return f
end

local function button(parent: Instance, text: string, color: Color3, props: { [string]: any }?): TextButton
	local b = make("TextButton", {
		Text = text,
		TextSize = 13,
		FontFace = Font.new(FONT, Enum.FontWeight.Heavy),
		TextColor3 = if color == AMBER then Color3.fromHex("3A2400") else TEXT,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Selectable = true,
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, b)
	for k, v in props or {} do
		b[k] = v
	end
	return b
end

local function ordinal(n: number): string
	local suf = "th"
	if n % 100 < 11 or n % 100 > 13 then
		suf = ({ "st", "nd", "rd" })[n % 10] or "th"
	end
	return tostring(n) .. suf
end

function ArmyPanel.new(ctx: any, gui: Instance)
	local self = setmetatable({}, ArmyPanel)
	self.ctx = ctx
	self.visible = false
	self.selected = 0
	self.mode = "" -- "move" / "attack": the next map click is the target
	self.recruit_tile = -1
	self.counts = { infantry = 0, tank = 0, artillery = 0 }
	self._acc = 0

	local root = make("Frame", { Name = "Military", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 20 }, gui)
	self.root = root

	-- ARMIES toggle (below Roblox's own top-left buttons: this UI ignores the top inset)
	local tb = button(root, "⚔  ARMIES", AMBER, { Position = UDim2.fromOffset(16, 72), Size = UDim2.fromOffset(150, 40), TextSize = 15 })
	tb.Activated:Connect(function()
		self:_toggle_recruit()
	end)
	self.toggle = tb

	-- recruit panel
	local rp = glass(root, "Recruit")
	rp.Position = UDim2.fromOffset(16, 120)
	rp.Size = UDim2.fromOffset(300, 300)
	rp.Visible = false
	self.recruit = rp
	label(rp, "RECRUIT", 15, Enum.FontWeight.Heavy, AMBER)
	self.where = label(rp, "", 12, Enum.FontWeight.Medium, TEXT2, { Position = UDim2.fromOffset(0, 20) })
	self.rows = {}
	for i, k in Units.TYPES do
		local d = Units.DEFS[k]
		local row = make("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.95, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 44 + (i - 1) * 52), Size = UDim2.new(1, 0, 0, 46) }, rp)
		make("UICorner", { CornerRadius = UDim.new(0, 8) }, row)
		local icon = make("ImageLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(6, 7), Size = UDim2.fromOffset(32, 32), ResampleMode = Enum.ResamplerMode.Pixelated }, row)
		local c = ArmySprites.content(k)
		if c then
			icon.ImageContent = c
		end
		label(row, d.name, 14, Enum.FontWeight.Bold, TEXT, { Position = UDim2.fromOffset(46, 4), Size = UDim2.new(1, -150, 0, 18) })
		label(row, string.format("%s gold · %s men", UITheme.fmt_cost(d.gold), UITheme.fmt_troops(d.men)), 11, Enum.FontWeight.Medium, TEXT2, {
			Position = UDim2.fromOffset(46, 24),
			Size = UDim2.new(1, -150, 0, 14),
		})
		local minus = button(row, "−", Color3.fromHex("2A3352"), { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -66, 0.5, 0), Size = UDim2.fromOffset(28, 28), TextSize = 18 })
		local n = label(row, "0", 16, Enum.FontWeight.Heavy, TEXT, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -36, 0.5, 0),
			Size = UDim2.fromOffset(28, 20),
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		local plus = button(row, "+", Color3.fromHex("2A3352"), { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(28, 28), TextSize = 18 })
		minus.Activated:Connect(function()
			self.counts[k] = math.max(0, self.counts[k] - 1)
			self:_refresh_recruit()
		end)
		plus.Activated:Connect(function()
			self.counts[k] = math.min(Units.MAX_RECRUIT, self.counts[k] + 1)
			self:_refresh_recruit()
		end)
		self.rows[k] = n
	end
	self.cost = label(rp, "", 13, Enum.FontWeight.Bold, TEXT, { Position = UDim2.fromOffset(0, 202) })
	self.new_btn = button(rp, "NEW ARMY", AMBER, { Position = UDim2.fromOffset(0, 230), Size = UDim2.new(0.5, -4, 0, 40) })
	self.add_btn = button(rp, "ADD TO SELECTED", Color3.fromHex("2A3352"), { Position = UDim2.new(0.5, 4, 0, 230), Size = UDim2.new(0.5, -4, 0, 40), TextSize = 12 })
	self.new_btn.Activated:Connect(function()
		self:_recruit(0)
	end)
	self.add_btn.Activated:Connect(function()
		if self:_own_selected() then
			self:_recruit(self.selected)
		end
	end)

	-- army panel
	local ap = glass(root, "Army")
	ap.AnchorPoint = Vector2.new(0, 1)
	ap.Size = UDim2.fromOffset(310, 318)
	ap.Visible = false
	self.panel = ap
	self.icon = make("ImageLabel", { BackgroundColor3 = TEXT2, BorderSizePixel = 0, Size = UDim2.fromOffset(40, 40), ResampleMode = Enum.ResamplerMode.Pixelated }, ap)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, self.icon)
	make("UIStroke", { Color = Color3.fromRGB(16, 18, 28), Thickness = 2 }, self.icon)
	self.name = label(ap, "", 17, Enum.FontWeight.Heavy, TEXT, { Position = UDim2.fromOffset(50, 0), Size = UDim2.new(1, -80, 0, 20) })
	self.country = label(ap, "", 12, Enum.FontWeight.Medium, TEXT2, { Position = UDim2.fromOffset(50, 22), Size = UDim2.new(1, -80, 0, 16) })
	local close = button(ap, "X", Color3.fromHex("2A3352"), { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(26, 26) })
	close.Activated:Connect(function()
		self:select(0)
	end)
	self.comp = {}
	for i, k in Units.TYPES do
		local cell = make("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.95, BorderSizePixel = 0, Position = UDim2.new((i - 1) / 3, if i > 1 then 3 else 0, 0, 48), Size = UDim2.new(1 / 3, -4, 0, 36) }, ap)
		make("UICorner", { CornerRadius = UDim.new(0, 8) }, cell)
		local ic = make("ImageLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(4, 4), Size = UDim2.fromOffset(28, 28), ResampleMode = Enum.ResamplerMode.Pixelated }, cell)
		local c = ArmySprites.content(k)
		if c then
			ic.ImageContent = c
		end
		self.comp[k] = label(cell, "0", 16, Enum.FontWeight.Heavy, TEXT, { Position = UDim2.fromOffset(36, 8), Size = UDim2.new(1, -38, 0, 20) })
	end
	self.total = label(ap, "", 12, Enum.FontWeight.Bold, TEXT2, { Position = UDim2.fromOffset(0, 88) })
	self.bars = {}
	for i, spec in { { "health", "Health", GREEN }, { "morale", "Morale", AMBER }, { "org", "Organization", CYAN }, { "supply", "Supply", Color3.fromHex("B48CFF") } } do
		local y = 106 + (i - 1) * 22
		label(ap, spec[2], 11, Enum.FontWeight.Bold, TEXT2, { Position = UDim2.fromOffset(0, y), Size = UDim2.fromOffset(90, 16) })
		local track = make("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.9, BorderSizePixel = 0, Position = UDim2.fromOffset(92, y + 4), Size = UDim2.new(1, -132, 0, 8) }, ap)
		make("UICorner", { CornerRadius = UDim.new(1, 0) }, track)
		local fill = make("Frame", { BackgroundColor3 = spec[3], BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) }, track)
		make("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)
		local pct = label(ap, "", 11, Enum.FontWeight.Bold, TEXT, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, y),
			Size = UDim2.fromOffset(36, 16),
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		self.bars[spec[1]] = { fill = fill, pct = pct }
	end
	self.orders = label(ap, "", 13, Enum.FontWeight.Bold, AMBER, { Position = UDim2.fromOffset(0, 196), Size = UDim2.new(1, 0, 0, 18) })
	self.buttons = {}
	local cmds = {
		{ "move", "MOVE", AMBER },
		{ "attack", "ATTACK", RED },
		{ "retreat", "RETREAT", Color3.fromHex("2A3352") },
		{ "reinforce", "REINFORCE", Color3.fromHex("2A3352") },
		{ "merge", "MERGE", Color3.fromHex("2A3352") },
		{ "disband", "DISBAND", Color3.fromHex("4A2430") },
	}
	for i, c in cmds do
		local col = (i - 1) % 3
		local row = (i - 1) // 3
		local b = button(ap, c[2], c[3], {
			Position = UDim2.new(col / 3, if col > 0 then 3 else 0, 0, 222 + row * 44),
			Size = UDim2.new(1 / 3, -4, 0, 38),
		})
		b.Activated:Connect(function()
			self:command(c[1])
		end)
		self.buttons[c[1]] = b
	end

	self._conn = RunService.Heartbeat:Connect(function(dt)
		if self.visible then
			self._acc += dt
			if self._acc >= 0.2 then
				self._acc = 0
				self:_refresh()
			end
		end
	end)
	self._key = UserInputService.InputBegan:Connect(function(io, gp)
		if gp or not self.visible then
			return
		end
		if io.KeyCode == Enum.KeyCode.Escape or io.KeyCode == Enum.KeyCode.ButtonB then
			if self.mode ~= "" then
				self.mode = ""
				self:_refresh()
			elseif self.selected ~= 0 then
				self:select(0)
			end
		end
	end)
	self:apply_layout()
	return self
end

function ArmyPanel.apply_layout(self)
	local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	-- above the command bar's left end on a wide screen
	self.panel.Position = UDim2.fromOffset(16, vp.Y - 96)
end

function ArmyPanel.set_visible(self, on: boolean)
	self.visible = on
	self.root.Visible = on
	if not on then
		self.mode = ""
	end
end

function ArmyPanel._toggle_recruit(self)
	self.recruit.Visible = not self.recruit.Visible
	if self.recruit.Visible then
		self:_refresh_recruit()
	end
	self.ctx:sfx("click")
end

function ArmyPanel._province_name(self, pid: number): string
	local picker = self.ctx.country_picker
	local P = picker and picker.P
	local p = P and P.list[pid]
	return if p then p.name else ("province " .. tostring(pid))
end

function ArmyPanel._province_of(self, tile: number): number
	local picker = self.ctx.country_picker
	local P = picker and picker.P
	if P == nil or tile < 0 then
		return 0
	end
	return buffer.readu16(P.prov_of, tile * 2)
end

function ArmyPanel._recruit_tile(self): number
	local s = self.ctx.state
	local me = self.ctx:me()
	if self.recruit_tile >= 0 and s:tile_owner(self.recruit_tile) == me then
		return self.recruit_tile
	end
	local o = s.owners[me]
	return if o then o.spawn_tile else -1
end

function ArmyPanel._refresh_recruit(self)
	local gold, men = 0, 0
	for _, k in Units.TYPES do
		self.rows[k].Text = tostring(self.counts[k])
		local g, m = Units.cost(k, self.counts[k])
		gold += g
		men += m
	end
	local s = self.ctx.state
	local o = s and s.owners[self.ctx:me()]
	local ok = o ~= nil and o.gold >= gold and o.troops >= men and gold > 0
	self.cost.Text = string.format("Cost: %s gold · %s men", UITheme.fmt_cost(gold), UITheme.fmt_troops(men))
	self.cost.TextColor3 = if gold == 0 then TEXT2 elseif ok then GREEN else RED
	local t = self:_recruit_tile()
	self.where.Text = "In " .. self:_province_name(self:_province_of(t)) .. " · click your land to change"
	self.add_btn.Visible = self:_own_selected()
end

function ArmyPanel._recruit(self, uid: number)
	local tile = self:_recruit_tile()
	local any = false
	for _, k in Units.TYPES do
		local n = self.counts[k]
		if n > 0 then
			self.ctx:send({ type = "army_recruit", uid = uid, tile = tile, kind = k, troops = n })
			any = true
		end
	end
	if any then
		self.ctx:sfx("build")
		for _, k in Units.TYPES do
			self.counts[k] = 0
		end
		self:_refresh_recruit()
	else
		self.ctx:sfx("deny", -4.0)
	end
end

function ArmyPanel._own_selected(self): boolean
	local s = self.ctx.state
	local a = s and s.armies and s.armies[self.selected]
	return a ~= nil and a.owner == self.ctx:me()
end

--- Selects army `uid` (0 = none).
function ArmyPanel.select(self, uid: number)
	self.selected = uid
	self.mode = ""
	UnitLayer.selected_army = uid
	self.panel.Visible = uid ~= 0
	if uid ~= 0 then
		self.recruit.Visible = false -- (the two panels share the left side)
	end
	if uid ~= 0 then
		self.ctx:sfx("click")
	end
	self:_refresh()
end

function ArmyPanel.command(self, cmd: string)
	local uid = self.selected
	if not self:_own_selected() then
		return
	end
	local ctx = self.ctx
	if cmd == "move" or cmd == "attack" then
		self.mode = if self.mode == cmd then "" else cmd
		ctx:sfx("click")
	elseif cmd == "retreat" then
		ctx:send({ type = "army_retreat", uid = uid })
	elseif cmd == "reinforce" then
		ctx:send({ type = "army_reinforce", uid = uid })
	elseif cmd == "disband" then
		ctx:send({ type = "army_disband", uid = uid })
		self:select(0)
	elseif cmd == "merge" then
		-- every other standing army of ours in the same province joins this one
		local s = ctx.state
		local a = s.armies[uid]
		for id, x in s.armies do
			if id ~= uid and x.owner == a.owner and x.province == a.province and x.status == 0 then
				ctx:send({ type = "army_merge", uid = uid, target = id })
			end
		end
	end
	self:_refresh()
end

--- Map click (UIInteract): targeting, army selection, the recruiting province. True when used.
function ArmyPanel.on_map_click(self, tile: number, pos: Vector2): boolean
	if not self.visible then
		return false
	end
	local ctx = self.ctx
	if self.mode ~= "" and self:_own_selected() then
		ctx:send({ type = "army_" .. self.mode, uid = self.selected, tile = tile })
		ctx:sfx("click")
		self.mode = ""
		self:_refresh()
		return true
	end
	local v = ctx:world_call("unit_at_screen", { ctx:to_view(pos), 24 * ctx:ui_scale() })
	local s = ctx.state
	local u = if type(v) == "number" then s.units[v] else nil
	if u ~= nil and u.kind == Defs.U_ARMY then
		self:select(u.uid)
		return true
	end
	if tile >= 0 and s:tile_owner(tile) == ctx:me() then
		self.recruit_tile = tile
		if self.recruit.Visible then
			self:_refresh_recruit()
		end
	end
	if self.selected ~= 0 then
		self:select(0)
	end
	return false
end

--- Right click (UIInteract): the selected army of ours goes there (move or attack). True when used.
function ArmyPanel.on_map_context(self, tile: number): boolean
	if not self.visible or not self:_own_selected() or tile < 0 then
		return false
	end
	local ctx = self.ctx
	local s = ctx.state
	local own = s:tile_owner(tile)
	local me = ctx:me()
	local kind = if own == me or (own ~= 0 and s:are_allies(me, own)) then "army_move" else "army_attack"
	ctx:send({ type = kind, uid = self.selected, tile = tile })
	ctx:sfx("click")
	return true
end

function ArmyPanel._refresh(self)
	if self.recruit.Visible then
		self:_refresh_recruit()
	end
	local s = self.ctx.state
	local a = s and s.armies and s.armies[self.selected]
	if a == nil or s.units[self.selected] == nil then
		if self.selected ~= 0 then
			self:select(0)
		end
		return
	end
	local mine = a.owner == self.ctx:me()
	local kind = ArmySprites.kind_of(a)
	local c = ArmySprites.content(kind)
	if c then
		self.icon.ImageContent = c
	end
	self.icon.BackgroundColor3 = s:owner_color(a.owner)
	self.name.Text = ordinal(a.seq or 1) .. " Army"
	self.country.Text = s:owner_name(a.owner) .. (if mine then " · yours" else "")
	for _, k in Units.TYPES do
		self.comp[k].Text = tostring(a[k] or 0)
	end
	local n = (a.infantry or 0) + (a.tank or 0) + (a.artillery or 0)
	self.total.Text = string.format("%d battalions", n)
	for key, b in self.bars do
		local v = math.clamp((a[key] or 0) / 100, 0, 1)
		b.fill.Size = UDim2.fromScale(v, 1)
		b.pct.Text = string.format("%d%%", math.floor(v * 100 + 0.5))
	end
	local st = a.status or 0
	local text = STATUS_TEXT[st] or ""
	if st == 1 and (a.target_province or 0) ~= 0 then
		text = "Marching to attack " .. self:_province_name(a.target_province)
	elseif st == 1 and (a.dest_tile or -1) >= 0 then
		text = "Marching to " .. self:_province_name(self:_province_of(a.dest_tile))
	elseif st == 2 and (a.target_province or 0) ~= 0 then
		text = "Attacking " .. self:_province_name(a.target_province)
	elseif st == 2 then
		text = "Defending " .. self:_province_name(a.province or 0)
	elseif st == 0 then
		text = "Standing in " .. self:_province_name(a.province or 0)
	end
	if self.mode == "move" then
		text = "Click your land to move there (Esc cancels)"
	elseif self.mode == "attack" then
		text = "Click an enemy province to attack (Esc cancels)"
	end
	self.orders.Text = text
	self.orders.TextColor3 = if st == 2 then RED elseif self.mode ~= "" then GREEN else AMBER
	for cmd, b in self.buttons do
		b.Visible = mine
		local enabled = true
		if cmd == "move" or cmd == "attack" or cmd == "reinforce" or cmd == "merge" or cmd == "disband" then
			enabled = st == 0 or (st == 1 and (cmd == "move" or cmd == "attack"))
		elseif cmd == "retreat" then
			enabled = st == 1 or st == 2
		end
		b.AutoButtonColor = enabled
		b.TextTransparency = if enabled then 0 else 0.55
		b.BackgroundTransparency = if enabled then 0 else 0.4
		if cmd == self.mode then
			b.BackgroundColor3 = GREEN
		elseif cmd == "move" then
			b.BackgroundColor3 = AMBER
		elseif cmd == "attack" then
			b.BackgroundColor3 = RED
		end
	end
end

function ArmyPanel.destroy(self)
	self._conn:Disconnect()
	self._key:Disconnect()
	self.root:Destroy()
end

return ArmyPanel
