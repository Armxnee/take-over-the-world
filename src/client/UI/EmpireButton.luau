--!nonstrict
-- (Take Over the World!: founding an empire, 2026-11-07; restyled as a HUD glass card 2026-11-08.)
-- In a match, under the top bar: how close the player's country is to the land an empire needs
-- (Data/Empires.LAND_SHARE of the map's land), then, once it has it, an amber FOUND button. Pressing it
-- sends the "empire" intent; the Sim checks again and renames the nation (Sim.form_empire), and its
-- flag, its Countryball (an evil face) and its name on the map follow.
-- The card uses the HUD's own tokens (UITheme: GLASS panel, LINE border, AMBER progress like the top
-- status's world-control bar, TEXT / INK labels) and shows the empire's Countryball on its left.
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
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

--- the progress shows from this share of the requirement on
EmpireButton.SHOW_FROM = 0.4

local W, H = 340, 52
local BALL = 38
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
	props.ZIndex = 32
	return make("TextLabel", props, parent)
end

function EmpireButton.new(ctx: any, gui: Instance)
	local self = setmetatable({}, EmpireButton)
	self.ctx = ctx
	self.ready = false
	local top = GuiService:GetGuiInset().Y
	-- (the holder carries the HUD's scale; the button's own UIScale is the pop / hover one)
	local holder = make("Frame", {
		Name = "EmpireCard",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, top + 76),
		Size = UDim2.fromOffset(W, H),
		Visible = false,
		ZIndex = 30,
	}, gui)
	self.holder = holder
	self.hud_scale = make("UIScale", { Name = "HudScale", Scale = UITheme.scale or 1 }, holder)
	local root = make("TextButton", {
		Name = "EmpireButton",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = GLASS,
		BackgroundTransparency = GLASS_T,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 30,
	}, holder)
	self.root = root
	make("UICorner", { CornerRadius = UDim.new(0, UITheme.R_MD) }, root)
	self.stroke = make("UIStroke", {
		Color = Color3.new(1, 1, 1),
		Transparency = 0.88,
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, root)
	self.grad = make("UIGradient", { Rotation = 90, Enabled = false }, root)
	self.ball_holder = make("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 0),
		Size = UDim2.fromOffset(BALL, BALL),
		ZIndex = 31,
	}, root)
	local left = 8 + BALL + 10
	self.title = label({
		Text = "",
		RichText = true,
		TextColor3 = UITheme.TEXT,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextSize = 16,
		Position = UDim2.fromOffset(left, 7),
		Size = UDim2.new(1, -left - 64, 0, 20),
	}, root)
	self.pct = label({
		Text = "",
		FontFace = Font.new(FONT, Enum.FontWeight.Heavy),
		TextColor3 = UITheme.AMBER,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 17,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 7),
		Size = UDim2.fromOffset(56, 20),
	}, root)
	-- the progress bar: a faint track and an amber fill (the top status's world-control bar)
	self.track = make("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.9,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(left, 33),
		Size = UDim2.new(1, -left - 12, 0, 7),
		ZIndex = 31,
	}, root)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, self.track)
	self.fill = make("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		ZIndex = 32,
	}, self.track)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, self.fill)
	make("UIGradient", { Color = ColorSequence.new(UITheme.AMBER_HI, UITheme.AMBER) }, self.fill)
	-- the ready state: one centred call to action, dark ink on amber (no outline: it stays crisp)
	self.cta = label({
		Text = "",
		FontFace = Font.new(FONT, Enum.FontWeight.Heavy),
		TextColor3 = UITheme.INK,
		TextScaled = true,
		Position = UDim2.fromOffset(left, 0),
		Size = UDim2.new(1, -left - 12, 1, 0),
		Visible = false,
	}, root)
	make("UITextSizeConstraint", { MaxTextSize = 18, MinTextSize = 10 }, self.cta)
	Anim.button(root)
	root.Activated:Connect(function()
		if not self.ready then
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
	RunService.Heartbeat:Connect(function(dt)
		self._acc += dt
		if self._acc >= 0.25 then
			self._acc = 0
			self:refresh()
		end
	end)
	return self
end

--- The empire's Countryball (evil face, its flag) on the card's left; drawn again only when it changes.
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
	local ok, ball = pcall(Countryball.new, code, BALL, e.name)
	if ok and ball then
		ball.ZIndex = 31
		for _, d in ball:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex = 32
			end
		end
		ball.Parent = self.ball_holder
	end
end

function EmpireButton._set_ready(self, ready: boolean, name: string)
	self.title.Visible = not ready
	self.pct.Visible = not ready
	self.track.Visible = not ready
	self.cta.Visible = ready
	self.grad.Enabled = ready
	if ready then
		self.cta.Text = "FOUND THE " .. string.upper(name) .. "!"
		self.root.BackgroundColor3 = Color3.new(1, 1, 1)
		self.root.BackgroundTransparency = 0
		self.grad.Color = ColorSequence.new(UITheme.AMBER_HI, UITheme.AMBER_LO)
		self.stroke.Color = UITheme.AMBER_LO
		self.stroke.Transparency = 0
	else
		self.root.BackgroundColor3 = GLASS
		self.root.BackgroundTransparency = GLASS_T
		self.stroke.Color = Color3.new(1, 1, 1)
		self.stroke.Transparency = 0.88
	end
end

function EmpireButton.refresh(self)
	local se = self.ctx.session
	local st = se and se.state
	local o = st and st.owners and st.owners[st.local_owner]
	local land = st and st.map and st.map.land_count or 0
	local show = false
	if o ~= nil and o.alive and o.kind == Defs.KIND_HUMAN and st.phase == Defs.PHASE_PLAYING and land > 0 then
		if not Empires.is_empire(o.name) then
			local need = land * Empires.LAND_SHARE
			local k = math.clamp(o.tiles / need, 0, 1)
			if k >= EmpireButton.SHOW_FROM then
				show = true
				local e = Empires.of(o.name)
				self:_ball(st, o.name, e)
				self.hud_scale.Scale = UITheme.scale or 1
				local was = self.ready
				self.ready = k >= 1
				if self.ready ~= was or self._shown_name ~= e.name then
					self._shown_name = e.name
					self:_set_ready(self.ready, e.name)
				end
				if self.ready then
					if not was then
						Anim.pop(self.root, 0, 0.6)
						self.ctx:sfx("unlock")
					end
				else
					-- (a long empire name keeps the whole line; the muted note only fits after a short one)
					self.title.Text = string.upper(e.name)
						.. if #e.name <= 16
							then ' <font color="#' .. MUTED:ToHex() .. '" size="13">· land needed</font>'
							else ""
					self.pct.Text = string.format("%d%%", math.floor(k * 100))
					self.fill.Size = UDim2.fromScale(k, 1)
				end
			end
		end
	end
	if not show then
		self.ready = false
		self._shown_name = nil
	end
	self.holder.Visible = show
end

return EmpireButton
