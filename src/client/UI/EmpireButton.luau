--!nonstrict
-- (Take Over the World!: founding an empire, 2026-11-07.)
-- In a match, under the top bar: how close the player's country is to the land an empire needs
-- (Data/Empires.LAND_SHARE of the map's land), then, once it has it, a gold FOUND button. Pressing it
-- sends the "empire" intent; the Sim checks again and renames the nation (Sim.form_empire), and its
-- flag, its Countryball (a moustache and a beard) and its name on the map follow.
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local Airfront = game:GetService("ReplicatedStorage"):WaitForChild("Airfront")
local Defs = require(Airfront.Core.Defs)
local Empires = require(Airfront.Data.Empires)
local Anim = require("./Anim")

local EmpireButton = {}
EmpireButton.__index = EmpireButton

--- the progress shows from this share of the requirement on
EmpireButton.SHOW_FROM = 0.4

local FONT = "rbxassetid://12187365977"
local INK = Color3.fromHex("1B1000")

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

function EmpireButton.new(ctx: any, gui: Instance)
	local self = setmetatable({}, EmpireButton)
	self.ctx = ctx
	self.ready = false
	local top = GuiService:GetGuiInset().Y
	local root = make("TextButton", {
		Name = "EmpireButton",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(1, 1, 1),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, top + 76),
		Size = UDim2.fromOffset(380, 48),
		Visible = false,
		ZIndex = 30,
	}, gui)
	self.root = root
	make("UICorner", { CornerRadius = UDim.new(0, 12) }, root)
	make("UIStroke", { Color = INK, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, root)
	self.grad = make("UIGradient", { Rotation = 90 }, root)
	self.fill = make("Frame", {
		BackgroundColor3 = Color3.fromHex("FFD34D"),
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		ZIndex = 31,
	}, root)
	make("UICorner", { CornerRadius = UDim.new(0, 12) }, self.fill)
	self.label = make("TextLabel", {
		BackgroundTransparency = 1,
		Text = "",
		TextSize = 17,
		FontFace = Font.new(FONT, Enum.FontWeight.Heavy),
		TextColor3 = Color3.new(1, 1, 1),
		Size = UDim2.new(1, -20, 1, -10),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		TextScaled = true, -- (a long empire name shrinks to fit)
		ZIndex = 32,
	}, root)
	make("UITextSizeConstraint", { MaxTextSize = 20, MinTextSize = 9 }, self.label)
	make("UIStroke", { Color = INK, Thickness = 1.5, Transparency = 0.2 }, self.label)
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
			self.root.Visible = false
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
				local was = self.ready
				self.ready = k >= 1
				self.fill.Size = UDim2.fromScale(if self.ready then 1 else k, 1)
				if self.ready then
					self.label.Text = "FOUND THE " .. string.upper(e.name) .. "!"
					self.grad.Color = ColorSequence.new(Color3.fromHex("FFE07A"), Color3.fromHex("E8892A"))
					self.label.TextColor3 = INK
					if not was then
						Anim.pop(self.root, 0, 0.6)
						self.ctx:sfx("unlock")
					end
				else
					self.label.Text = string.format("EMPIRE: %d%% OF THE LAND NEEDED", math.floor(k * 100))
					self.grad.Color = ColorSequence.new(Color3.fromHex("2D3A6E"), Color3.fromHex("141B36"))
					self.label.TextColor3 = Color3.new(1, 1, 1)
				end
			end
		end
	end
	if not show then
		self.ready = false
	end
	self.root.Visible = show
end

return EmpireButton
