--!nonstrict
-- (Take Over the World!: interface tweens, 2026-11-06.)
-- Modals open with the dim fading in, then the panel popping up (a UIScale with a Back ease); their
-- contents can pop in one after another (Anim.pop with a delay). Buttons grow on hover and squash
-- on press (Anim.button). Every tween is TweenService, so nothing runs while nothing moves.
local TweenService = game:GetService("TweenService")

local Anim = {}

Anim.FADE_S = 0.22
Anim.POP_S = 0.34
Anim.POP_FROM = 0.82

function Anim.tween(inst: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?, delay: number?): Tween
	local tw = TweenService:Create(
		inst,
		TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out, 0, false, delay or 0),
		props
	)
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

--- A modal opens: `dim` (a full-screen button or frame) fades in, then `panel` pops up.
function Anim.open(dim: GuiObject, panel: GuiObject)
	local target = dim:GetAttribute("DimTransparency")
	if target == nil then
		target = dim.BackgroundTransparency
		dim:SetAttribute("DimTransparency", target)
	end
	dim.Visible = true
	dim.BackgroundTransparency = 1
	Anim.tween(dim, Anim.FADE_S, { BackgroundTransparency = target })
	local s = Anim.scale_of(panel)
	s.Scale = 0
	Anim.tween(s, Anim.POP_S, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out, Anim.FADE_S * 0.6)
end

--- A modal closes: the panel shrinks away and the dim fades out, then both hide.
function Anim.close(dim: GuiObject, panel: GuiObject)
	local s = Anim.scale_of(panel)
	Anim.tween(s, 0.16, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	local tw = Anim.tween(dim, 0.2, { BackgroundTransparency = 1 }, nil, nil, 0.06)
	tw.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed and s.Scale <= 0.01 then
			dim.Visible = false
		end
	end)
end

--- `inst` pops in after `delay` seconds (from nothing to full size, overshooting a little).
function Anim.pop(inst: GuiObject, delay: number?, from: number?)
	local s = Anim.scale_of(inst)
	s.Scale = from or 0
	Anim.tween(s, Anim.POP_S, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out, delay or 0)
end

--- Hover grows `btn` (or `target`, when the press area isn't what should move); a press squashes it.
function Anim.button(btn: GuiButton, target: GuiObject?, grow: number?)
	local obj = target or btn
	local up = grow or 1.06
	-- (one UIScale an object: the pop's, shared, so a hover after the pop scales the same one)
	local sc = Anim.scale_of(obj)
	local function to(v: number, t: number, style: Enum.EasingStyle?)
		Anim.tween(sc, t, { Scale = v }, style or Enum.EasingStyle.Quad)
	end
	local over = false
	btn.MouseEnter:Connect(function()
		over = true
		to(up, 0.14)
	end)
	btn.MouseLeave:Connect(function()
		over = false
		to(1, 0.16)
	end)
	btn.MouseButton1Down:Connect(function()
		to(0.94, 0.08)
	end)
	btn.MouseButton1Up:Connect(function()
		to(if over then up else 1, 0.22, Enum.EasingStyle.Back)
	end)
end

return Anim
