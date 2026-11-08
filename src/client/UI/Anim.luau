--!nonstrict
-- (Take Over the World!: interface tweens, 2026-11-06; polished 2026-11-08.)
-- Modals open with the dim fading in while the panel grows from a little smaller with a soft
-- overshoot; they close by settling down while the dim fades. Contents can pop or rise in one after
-- another (Anim.pop / Anim.rise with a delay) and sink away (Anim.sink). Buttons grow on hover and
-- squash on press (Anim.button). Every tween is TweenService, so nothing runs while nothing moves; a
-- new tween on the same property replaces the old one (no fighting between hover and pop).
local TweenService = game:GetService("TweenService")

local Anim = {}

Anim.FADE_S = 0.24
Anim.POP_S = 0.42
Anim.POP_FROM = 0.86
--- how far (px) a rising element starts below its place
Anim.RISE_PX = 26

local Q = Enum.EasingStyle.Quint
local OUT, IN = Enum.EasingDirection.Out, Enum.EasingDirection.In

function Anim.tween(inst: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?, delay: number?): Tween
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Q, dir or OUT, 0, false, delay or 0), props)
	tw:Play()
	return tw
end

--- The UIScale named "PopScale" on `inst` (made once).
function Anim.scale_of(inst: Instance): UIScale
	local s = inst:FindFirstChild("PopScale")
	if s == nil then
		s = Instance.new("UIScale")
		s.Name = "PopScale"
		s.Parent = inst
	end
	return s :: UIScale
end

-- where each element rests (kept the first time it is moved, so repeated rises never drift)
local homes: { [Instance]: UDim2 } = setmetatable({}, { __mode = "k" }) :: any
function Anim.home(inst: GuiObject): UDim2
	local h = homes[inst]
	if h == nil then
		h = inst.Position
		homes[inst] = h
	end
	return h
end

--- A modal opens: `dim` (a full-screen button or frame) fades in, then `panel` grows into place.
function Anim.open(dim: GuiObject, panel: GuiObject)
	local target = dim:GetAttribute("DimTransparency")
	if target == nil then
		target = dim.BackgroundTransparency
		dim:SetAttribute("DimTransparency", target)
	end
	dim.Visible = true
	dim.BackgroundTransparency = 1
	Anim.tween(dim, Anim.FADE_S, { BackgroundTransparency = target }, Enum.EasingStyle.Sine)
	local s = Anim.scale_of(panel)
	s.Scale = Anim.POP_FROM
	Anim.tween(s, Anim.POP_S, { Scale = 1 }, Enum.EasingStyle.Back, OUT, 0.04)
	Anim.rise(panel, 0.04, 18)
end

--- A modal closes: the panel settles down and away while the dim fades out, then both hide.
function Anim.close(dim: GuiObject, panel: GuiObject)
	local s = Anim.scale_of(panel)
	Anim.tween(s, 0.18, { Scale = 0.9 }, Enum.EasingStyle.Quad, IN)
	Anim.sink(panel, 0, 14)
	local tw = Anim.tween(dim, 0.2, { BackgroundTransparency = 1 }, Enum.EasingStyle.Sine, IN, 0.04)
	tw.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed and s.Scale <= 0.91 then
			dim.Visible = false
			s.Scale = 1
			panel.Position = Anim.home(panel)
		end
	end)
end

--- `inst` pops in after `delay` seconds: it grows from `from` (default a little smaller) to full
--- size, overshooting softly.
function Anim.pop(inst: GuiObject, delay: number?, from: number?)
	local s = Anim.scale_of(inst)
	s.Scale = from or 0.5
	Anim.tween(s, Anim.POP_S, { Scale = 1 }, Enum.EasingStyle.Back, OUT, delay or 0)
end

--- `inst` rises into its place from `dist` px below after `delay` seconds (a smooth Quint glide).
function Anim.rise(inst: GuiObject, delay: number?, dist: number?)
	local home = Anim.home(inst)
	inst.Position = home + UDim2.fromOffset(0, dist or Anim.RISE_PX)
	Anim.tween(inst, 0.5, { Position = home }, Q, OUT, delay or 0)
end

--- `inst` sinks `dist` px out of its place (closing); Anim.home puts it back.
function Anim.sink(inst: GuiObject, delay: number?, dist: number?): Tween
	local home = Anim.home(inst)
	return Anim.tween(inst, 0.16, { Position = home + UDim2.fromOffset(0, dist or Anim.RISE_PX * 0.6) }, Enum.EasingStyle.Quad, IN, delay or 0)
end

--- Hover grows `btn` (or `target`, when the press area isn't what should move); a press squashes it
--- and the release springs back.
function Anim.button(btn: GuiButton, target: GuiObject?, grow: number?)
	local obj = target or btn
	local up = grow or 1.05
	-- (one UIScale an object: the pop's, shared, so a hover after the pop scales the same one)
	local sc = Anim.scale_of(obj)
	local function to(v: number, t: number, style: Enum.EasingStyle?)
		Anim.tween(sc, t, { Scale = v }, style or Q)
	end
	local over = false
	btn.MouseEnter:Connect(function()
		over = true
		to(up, 0.2)
	end)
	btn.MouseLeave:Connect(function()
		over = false
		to(1, 0.24)
	end)
	btn.MouseButton1Down:Connect(function()
		to(0.93, 0.07, Enum.EasingStyle.Quad)
	end)
	btn.MouseButton1Up:Connect(function()
		to(if over then up else 1, 0.34, Enum.EasingStyle.Back)
	end)
end

return Anim
