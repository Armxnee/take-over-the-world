--!nonstrict
-- (Take Over the World!: founding an empire, 2026-11-07; a progress circle beside the top bar
-- 2026-11-08.)
-- In a match, right of the top status bar: a ring that fills as the player's country nears the land
-- its empire needs (Data/Empires.need: LAND_SHARE of the map, and CONQUER_SHARE of it beyond the
-- country's own land), with the empire's Countryball in the middle. Hovering it (or tapping it) shows
-- how far along it is and what is left; once it is full the ring turns gold and pulses, and a click
-- sends the "empire" intent: the Sim checks again and renames the nation (Sim.form_empire), and its
-- flag, its Countryball and its name on the map follow.
local RunService = game:GetService("RunService")
local AssetService = game:GetService("AssetService")
local TweenService = game:GetService("TweenService")
local Airfront = game:GetService("ReplicatedStorage"):WaitForChild("Airfront")
local Defs = require(Airfront.Core.Defs)
local Empires = require(Airfront.Data.Empires)
local Countries = require(Airfront.Data.Countries)
local FlagPix = require(Airfront.Data.FlagPix)
local UITheme = require("./UITheme")
local Countryball = require("./Countryball")
local Anim = require("./Anim")

local EmpireButton = {}
EmpireButton.__index = EmpireButton

--- the circle shows from this share of the requirement on
EmpireButton.SHOW_FROM = 0.0
--- the gap (px) between the top bar and the circle
EmpireButton.GAP = 10

local RING = 64 -- the ring's pixels
local FONT = "rbxassetid://" .. tostring(UITheme.FONT_ID)
local GLASS = UITheme.color3(UITheme.GLASS)
local GLASS_T = 1 - UITheme.alpha(UITheme.GLASS)
local MUTED = Color3.fromRGB(140, 151, 184)

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

local function label(props: { [string]: any }, parent: Instance): TextLabel
	props.BackgroundTransparency = 1
	props.FontFace = props.FontFace or Font.new(FONT, Enum.FontWeight.Bold)
	props.ZIndex = 34
	return make("TextLabel", props, parent)
end

--- `top`: () -> the top status bar's GuiObject (the circle sits right of it).
function EmpireButton.new(ctx: any, gui: Instance, top: (() -> GuiObject?)?)
	local self = setmetatable({}, EmpireButton)
	self.ctx = ctx
	self.ready = false
	self.top = top
	local holder = make("Frame", {
		Name = "EmpireCircle",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(56, 56),
		Visible = false,
		ZIndex = 30,
	}, gui)
	self.holder = holder
	self.disk = make("Frame", {
		BackgroundColor3 = GLASS,
		BackgroundTransparency = GLASS_T,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 30,
	}, holder)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, self.disk)
	self.glow = make("UIStroke", { Color = UITheme.GOLD, Thickness = 0, Transparency = 1 }, self.disk)
	-- the ring, drawn into its own pixels (Countryball style: no uploaded art)
	self.ring = make("ImageLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 31,
	}, holder)
	local ok, img = pcall(function()
		return AssetService:CreateEditableImage({ Size = Vector2.new(RING, RING) })
	end)
	if ok and img then
		self.img = img
		self.ring.ImageContent = Content.fromObject(img)
	end
	self.ball_holder = make("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.64, 0.64),
		ZIndex = 32,
	}, holder)
	self.hit = make("TextButton", {
		Text = "",
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 35,
	}, holder)
	-- the tip under the circle: the empire and how far along it is
	local tip = make("Frame", {
		BackgroundColor3 = GLASS,
		BackgroundTransparency = GLASS_T,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 8),
		Size = UDim2.fromOffset(300, 50),
		Visible = false,
		ZIndex = 33,
	}, holder)
	self.tip = tip
	make("UICorner", { CornerRadius = UDim.new(0, UITheme.R_MD) }, tip)
	make("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.88 }, tip)
	self.tip_title = label({
		Text = "",
		TextColor3 = UITheme.TEXT,
		TextSize = 15,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(10, 6),
		Size = UDim2.new(1, -20, 0, 18),
	}, tip)
	self.tip_line = label({
		Text = "",
		RichText = true,
		TextColor3 = MUTED,
		TextSize = 13,
		Position = UDim2.fromOffset(10, 26),
		Size = UDim2.new(1, -20, 0, 16),
	}, tip)
	self.hovered = false
	self.pinned = false
	self.hit.MouseEnter:Connect(function()
		self.hovered = true
		self:_tip()
	end)
	self.hit.MouseLeave:Connect(function()
		self.hovered = false
		self:_tip()
	end)
	Anim.button(self.hit, holder, 1.08)
	self.hit.Activated:Connect(function()
		if not self.ready then
			-- (a click shows the land still needed in red on the map, and keeps the tip up; another
			-- hides both)
			self.pinned = not self.pinned
			self:_tip()
			local left = self._left or 0
			if left > 0 then
				self.ctx:world_call("show_empire_need", { left })
				self.ctx:sfx("click")
			end
			return
		end
		local se = self.ctx.session
		if se ~= nil and type(se.send_intent) == "function" then
			se:send_intent({ type = "empire" })
			self.ctx:sfx("confirm")
			self.ready = false
			self.holder.Visible = false
		end
	end)
	self._acc = 0
	self._k = -1
	RunService.Heartbeat:Connect(function(dt)
		self._acc += dt
		if self._acc >= 0.25 then
			self._acc = 0
			self:refresh()
		end
	end)
	return self
end

function EmpireButton._tip(self)
	local on = (self.hovered or self.pinned) and self.holder.Visible
	if on and not self.tip.Visible then
		self.tip.Visible = true
		Anim.pop(self.tip, 0, 0.8)
	elseif not on then
		self.tip.Visible = false
	end
end

--- The ring at `k` (0..1): a dark track with an amber arc from the top, clockwise; gold when full.
function EmpireButton._draw(self, k: number, ready: boolean)
	local img = self.img
	if img == nil then
		return
	end
	local b = buffer.create(RING * RING * 4)
	local c = (RING - 1) / 2
	local R1, R0 = RING / 2 - 1, RING / 2 - 8 -- the ring's outer and inner radius
	local fill = if ready then Color3.fromRGB(255, 214, 102) else UITheme.AMBER
	local hi = if ready then Color3.fromRGB(255, 240, 180) else UITheme.AMBER_HI
	for y = 0, RING - 1 do
		for x = 0, RING - 1 do
			local dx, dy = x - c, y - c
			local d = math.sqrt(dx * dx + dy * dy)
			if d <= R1 + 0.5 and d >= R0 - 0.5 then
				local o = (y * RING + x) * 4
				local a = math.atan2(dx, -dy)
				if a < 0 then
					a += 2 * math.pi
				end
				local col, alpha
				if d > R1 - 0.6 or d < R0 + 0.6 then
					col, alpha = Color3.fromRGB(10, 12, 20), 230 -- the dark edges
				elseif a / (2 * math.pi) <= k then
					col, alpha = if d > (R0 + R1) / 2 + 1 then hi else fill, 255
				else
					col, alpha = Color3.new(1, 1, 1), 34 -- the track
				end
				buffer.writeu8(b, o, math.floor(col.R * 255 + 0.5))
				buffer.writeu8(b, o + 1, math.floor(col.G * 255 + 0.5))
				buffer.writeu8(b, o + 2, math.floor(col.B * 255 + 0.5))
				buffer.writeu8(b, o + 3, alpha)
			end
		end
	end
	img:WritePixelsBuffer(Vector2.zero, Vector2.new(RING, RING), b)
end

--- The empire's Countryball in the middle; drawn again only when it changes.
function EmpireButton._ball(self, st: any, country: string, e: any)
	local key = tostring(st.map and st.map.id) .. "|" .. e.name
	if self._ball_key == key then
		return
	end
	self._ball_key = key
	local code = e.flag
	if code == nil then
		local ok, by_name = pcall(Countries.flags_by_name, st.map)
		code = if ok and by_name then by_name[country] else nil
		if code == nil then
			code = FlagPix.code(country)
		end
	end
	self.ball_holder:ClearAllChildren()
	local ok, ball = pcall(Countryball.new, code, 32, e.name)
	if ok and ball then
		ball.Size = UDim2.fromScale(1, 1)
		ball.ZIndex = 32
		for _, d in ball:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex = 32
			end
		end
		ball.Parent = self.ball_holder
	end
end

--- The home land of the local player's country (Data/Countries def.tiles), as the Sim counts it.
function EmpireButton._home(self, st: any): number?
	local picker = self.ctx.country_picker
	local defs = picker and picker.defs
	local d = defs and defs[st.local_owner]
	return d and d.tiles or nil
end

--- Right of the top status bar, as tall as it.
function EmpireButton._place(self)
	local top = self.top and self.top()
	local parent = self.holder.Parent
	if top == nil or parent == nil or not parent:IsA("GuiBase2d") then
		return
	end
	local size = math.clamp(math.floor(top.AbsoluteSize.Y + 0.5), 44, 72)
	local p = top.AbsolutePosition - (parent :: any).AbsolutePosition
	local x = p.X + top.AbsoluteSize.X + EmpireButton.GAP
	local y = p.Y + (top.AbsoluteSize.Y - size) / 2
	if self._px ~= x or self._py ~= y or self._ps ~= size then
		self._px, self._py, self._ps = x, y, size
		self.holder.Position = UDim2.fromOffset(x, y)
		self.holder.Size = UDim2.fromOffset(size, size)
	end
end

function EmpireButton.refresh(self)
	local se = self.ctx.session
	local st = se and se.state
	local o = st and st.owners and st.owners[st.local_owner]
	local land = st and st.map and st.map.land_count or 0
	local show = false
	if o ~= nil and o.alive and o.kind == Defs.KIND_HUMAN and st.phase == Defs.PHASE_PLAYING and land > 0 and Empires.allowed(st.map.id) then
		if not Empires.is_empire(o.name) then
			local need = Empires.need(land, self:_home(st))
			local k = math.clamp(o.tiles / need, 0, 1)
			self._left = math.max(0, math.ceil(need - o.tiles))
			if k >= EmpireButton.SHOW_FROM then
				show = true
				local e = Empires.of(o.name)
				self:_ball(st, o.name, e)
				self:_place()
				local was = self.ready
				self.ready = k >= 1
				local pct = math.floor(k * 100)
				if pct ~= self._k or self.ready ~= was then
					self._k = pct
					self:_draw(k, self.ready)
				end
				self.tip_title.Text = string.upper(e.name)
				if self.ready then
					self.tip_line.Text = '<font color="#FFD666">Ready!</font> Click to found it'
				else
					self.tip_line.Text = string.format('<font color="#FFB547">%d%%</font> done · %d%% to go · <font color="#FF5C61">click: land to take</font>', pct, 100 - pct)
				end
				if self.ready and not was then
					Anim.pop(self.holder, 0, 0.6)
					self.ctx:sfx("unlock")
					self.glow.Thickness = 3
					self._pulse = TweenService:Create(
						self.glow,
						TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
						{ Transparency = 0.1 }
					)
					self.glow.Transparency = 0.8
					self._pulse:Play()
				elseif not self.ready and was then
					if self._pulse then
						self._pulse:Cancel()
					end
					self.glow.Transparency = 1
				end
			end
		end
	end
	if not show then
		self.ready = false
		self._k = -1
		if self._pulse then
			self._pulse:Cancel()
			self._pulse = nil
		end
		self.glow.Transparency = 1
	end
	self.holder.Visible = show
	self:_tip()
end

return EmpireButton
