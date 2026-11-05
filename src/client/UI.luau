--!strict
-- UI kit, rebuilt to match RoWorld's design system (our own code; only the look is matched):
-- navy frosted glass with a 1 px white-10% border and a top sheen, amber primary buttons with a
-- darker 3 px lip, glass / ghost / danger buttons, pill chips, captions, dividers, the 8 px
-- spacing scale and Rubik everywhere. Every screen builds on these helpers.
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Audio = require(script.Parent.Audio)

local UI = {}

UI.C = {
	Bg = Color3.fromHex("0D1326"), -- navy glass
	Panel = Color3.fromHex("0B1020"), -- solid glass
	Raise = Color3.fromHex("1A213D"), -- raised glass / glass buttons
	Stroke = Color3.fromHex("2B3352"), -- an opaque stand-in for white @ 10 % over the glass
	Line = Color3.new(1, 1, 1),
	Text = Color3.new(0.94, 0.955, 1.0),
	Sub = Color3.new(0.68, 0.73, 0.86), -- text 2
	Dim = Color3.new(0.48, 0.53, 0.67), -- text 3
	Accent = Color3.fromHex("FFB547"), -- amber: primary actions + selection
	AccentHi = Color3.fromHex("FFCC78"),
	AccentLo = Color3.fromHex("CC7D21"),
	Info = Color3.fromHex("4FD1FF"), -- cyan: info / public matches
	Ink = Color3.fromHex("1A1105"), -- text on amber
	Good = Color3.fromHex("5EE399"),
	Warn = Color3.fromHex("FF945C"),
	Bad = Color3.fromHex("FF5463"),
	Violet = Color3.fromHex("B89EFF"),
	Gold = Color3.fromHex("FFD666"),
	Surrender = Color3.fromRGB(222, 48, 60),
	Night = Color3.new(0.01, 0.015, 0.05), -- title backdrop ink
}
UI.BgT = 0.08 -- glass alpha 84 % + 8 % boost (Roblox has no backdrop blur)
UI.LineT = 0.9 -- white border @ 10 %
UI.LineHiT = 0.82 -- white border @ 18 % (hover)
UI.S = { 4, 8, 12, 16, 24, 32, 48 } -- spacing scale
UI.R = { sm = 6, md = 10, lg = 14 }

-- Rubik (Roblox font library); falls back to Builder Sans if the family fails to load
local RUBIK = 12187365977
local function rubik(w: Enum.FontWeight): Font
	local ok, f = pcall(Font.fromId, RUBIK, w)
	return if ok and f then f else Font.new("rbxasset://fonts/families/BuilderSans.json", w)
end
UI.F = {
	Reg = rubik(Enum.FontWeight.Regular),
	Med = rubik(Enum.FontWeight.Medium),
	Semi = rubik(Enum.FontWeight.SemiBold),
	Bold = rubik(Enum.FontWeight.Bold),
	Heavy = rubik(Enum.FontWeight.Heavy),
	Black = rubik(Enum.FontWeight.Heavy),
}

function UI.make(class: string, props: { [string]: any }?, children: { Instance }?): any
	local o = Instance.new(class)
	local parent = nil
	for k, v in props or {} do
		if k == "Parent" then
			parent = v
		else
			(o :: any)[k] = v
		end
	end
	for _, c in children or {} do
		c.Parent = o
	end
	if parent then
		o.Parent = parent
	end
	return o
end
local make = UI.make

function UI.corner(r: number?): UICorner
	return make("UICorner", { CornerRadius = UDim.new(0, r or UI.R.md) })
end

-- 1 px border; with no colour it is RoWorld's white @ 10 %, drawn inside the edge
function UI.stroke(c: Color3?, t: number?): UIStroke
	local s = make("UIStroke", {
		Color = c or UI.C.Line,
		Transparency = if c then 0 else UI.LineT,
		Thickness = t or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
	})
	pcall(function()
		(s :: any).BorderStrokePosition = Enum.BorderStrokePosition.Inner
	end)
	return s
end

function UI.pad(px: number, py: number?): UIPadding
	local u, v = UDim.new(0, px), UDim.new(0, py or px)
	return make("UIPadding", { PaddingLeft = u, PaddingRight = u, PaddingTop = v, PaddingBottom = v })
end

-- top sheen: the glass is a touch lighter at the top (a gradient on the frame itself, so it never
-- joins a layout or covers content). It follows later BackgroundColor3 changes.
local SHEEN_T = { 0, 0.074, 0.259, 0.5, 0.741, 0.926, 1 }
local function sheen(f: GuiObject, amount: number)
	local g = make("UIGradient", { Name = "Sheen", Rotation = 90, Parent = f })
	local function apply()
		local c = f.BackgroundColor3
		local lit = c:Lerp(Color3.new(1, 1, 1), amount)
		local keys = {}
		for i, t in SHEEN_T do
			local k = (i - 1) / 10
			-- multiply: the frame shows `lit` at the top, easing to the true colour by 60 %
			local tgt = lit:Lerp(c, t)
			table.insert(keys, ColorSequenceKeypoint.new(k, Color3.new(
				if lit.R > 0 then math.min(1, tgt.R / lit.R) else 1,
				if lit.G > 0 then math.min(1, tgt.G / lit.G) else 1,
				if lit.B > 0 then math.min(1, tgt.B / lit.B) else 1
			)))
		end
		local last = keys[#keys].Value
		table.insert(keys, ColorSequenceKeypoint.new(1, last))
		g.Color = ColorSequence.new(keys)
		g:SetAttribute("Lit", lit)
		f:SetAttribute("SheenBusy", true)
		f.BackgroundColor3 = lit
		f:SetAttribute("SheenBusy", false)
	end
	f:SetAttribute("BaseColor", f.BackgroundColor3)
	apply()
	f:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
		if f:GetAttribute("SheenBusy") then
			return
		end
		apply()
	end)
end
UI.sheen = sheen

-- frosted glass panel (navy tint, white-10 % border, top sheen); callers may recolour it
function UI.panel(props: { [string]: any }): Frame
	local r = props.Radius or UI.R.lg
	props.Radius = nil
	local noSheen = props.NoSheen
	props.NoSheen = nil
	props.BackgroundColor3 = props.BackgroundColor3 or UI.C.Bg
	props.BackgroundTransparency = props.BackgroundTransparency or UI.BgT
	props.BorderSizePixel = 0
	if props.Active == nil then
		props.Active = true -- sinks input so the map doesn't react under panels
	end
	local f = make("Frame", props, { UI.corner(r), UI.stroke() })
	if not noSheen then
		sheen(f, 0.045)
	end
	return f
end
UI.glass = UI.panel

function UI.label(props: { [string]: any }): TextLabel
	props.BackgroundTransparency = 1
	props.FontFace = props.FontFace or UI.F.Med
	props.TextColor3 = props.TextColor3 or UI.C.Text
	props.TextSize = props.TextSize or 16
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	return make("TextLabel", props)
end

-- small upper-case caption ("TROOPS", "GOLD"): 11 px bold, text 3
function UI.caption(text: string, props: { [string]: any }?): TextLabel
	local p = props or {}
	p.Text = string.upper(text)
	p.TextSize = p.TextSize or 11
	p.FontFace = p.FontFace or UI.F.Bold
	p.TextColor3 = p.TextColor3 or UI.C.Dim
	return UI.label(p)
end

-- thin white-10 % rule
function UI.divider(props: { [string]: any }?): Frame
	local p = props or {}
	p.BackgroundColor3 = UI.C.Line
	p.BackgroundTransparency = UI.LineT
	p.BorderSizePixel = 0
	p.Size = p.Size or UDim2.new(1, 0, 0, 1)
	return make("Frame", p)
end

-- a 3 px darker lip under solid buttons (amber / green / red): a hard-stop gradient that
-- multiplies the button's own colour, so it follows any BackgroundColor3 the code sets later
local function lip(b: GuiObject, px: number)
	local g = make("UIGradient", { Name = "Lip", Rotation = 90, Parent = b })
	local function fit()
		local h = math.max(b.AbsoluteSize.Y, px * 2 + 1)
		local k = 1 - px / h
		local dark = Color3.new(0.72, 0.68, 0.62)
		g.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(math.max(0.01, k - 0.001), Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(k, dark),
			ColorSequenceKeypoint.new(1, dark),
		})
	end
	local function solid()
		local c = b.BackgroundColor3
		local _, s, v = c:ToHSV()
		-- glass colours (dark navy) get no lip
		g.Enabled = s > 0.35 and v > 0.45
	end
	fit()
	solid()
	b:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	b:GetPropertyChangedSignal("BackgroundColor3"):Connect(solid)
end
UI.lip = lip

-- Kinds: "primary" (amber, ink text), "danger" (red tint), "surrender" (solid red), "ghost"
-- (no fill), "chip" (pill), "public" (cyan accent); default is a glass button.
function UI.button(props: { [string]: any }, onClick: () -> ()): TextButton
	local kind = props.Kind
	props.Kind = nil
	local r = props.Radius or (if kind == "chip" then 999 else UI.R.md)
	props.Radius = nil
	local bg, txt, strokeCol, strokeT = UI.C.Raise, UI.C.Text, UI.C.Line, UI.LineT
	local fill = 0
	if kind == "primary" then
		bg, txt, strokeT = UI.C.Accent, UI.C.Ink, 1
	elseif kind == "surrender" then
		bg, txt, strokeT = UI.C.Surrender, Color3.new(1, 1, 1), 1
	elseif kind == "danger" then
		bg, txt, strokeCol, strokeT = UI.C.Bad:Lerp(UI.C.Bg, 0.82), Color3.new(1, 0.78, 0.8), UI.C.Bad, 0.55
	elseif kind == "public" then
		bg, txt, strokeCol, strokeT = UI.C.Info:Lerp(UI.C.Bg, 0.88), UI.C.Text, UI.C.Info, 0.45
	elseif kind == "ghost" then
		bg, txt, fill = UI.C.Raise, UI.C.Sub, 1
	elseif kind == "chip" then
		bg, txt = Color3.fromHex("151B33"), UI.C.Sub
	end
	props.BackgroundColor3 = props.BackgroundColor3 or bg
	if props.BackgroundTransparency == nil then
		props.BackgroundTransparency = fill
	end
	props.BorderSizePixel = 0
	if props.AutoButtonColor == nil then
		props.AutoButtonColor = true
	end
	props.FontFace = props.FontFace or (if kind == "primary" or kind == "surrender" then UI.F.Heavy else UI.F.Bold)
	props.TextColor3 = props.TextColor3 or txt
	props.TextSize = props.TextSize or 16
	props.Selectable = true
	local st = UI.stroke(strokeCol, 1)
	st.Transparency = if kind == "ghost" then 1 else strokeT
	local b = make("TextButton", props, { UI.corner(r), st })
	if kind ~= "ghost" and kind ~= "chip" then
		lip(b, if kind == "primary" or kind == "surrender" then 3 else 2)
	end
	UI.hover(b)
	-- the border brightens on hover (glass buttons)
	if strokeT < 1 then
		b.MouseEnter:Connect(function()
			UI.tween(st, 0.12, { Transparency = math.max(0, strokeT - 0.25) })
		end)
		b.MouseLeave:Connect(function()
			UI.tween(st, 0.12, { Transparency = strokeT })
		end)
	end
	if kind == "ghost" then
		b.MouseEnter:Connect(function()
			UI.tween(b, 0.12, { BackgroundTransparency = 0.6, TextColor3 = UI.C.Text })
		end)
		b.MouseLeave:Connect(function()
			UI.tween(b, 0.12, { BackgroundTransparency = 1, TextColor3 = UI.C.Sub })
		end)
	end
	b.Activated:Connect(function()
		Audio.play("click")
		onClick()
	end)
	return b
end

-- pill chip with a pressed (amber) state; returns the button and a setter
function UI.chip(props: { [string]: any }, onClick: () -> ()): (TextButton, (boolean) -> ())
	props.Kind = "chip"
	props.TextSize = props.TextSize or 13
	local b = UI.button(props, onClick)
	-- lihfolk-ignore: findfirstchild-chain (UI.button always adds the stroke)
	local st = b:FindFirstChildOfClass("UIStroke") :: UIStroke
	local function set(on: boolean)
		b.BackgroundColor3 = if on then UI.C.Accent:Lerp(UI.C.Bg, 0.8) else Color3.fromHex("151B33")
		b.TextColor3 = if on then UI.C.AccentHi else UI.C.Sub
		st.Color = if on then UI.C.Accent else UI.C.Line
		st.Transparency = if on then 0.1 else UI.LineT
	end
	set(false)
	return b, set
end

-- tween helpers -------------------------------------------------------------
function UI.tween(o: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local function scaleOf(o: GuiObject): UIScale
	local s = o:FindFirstChild("TweenScale")
	if s and s:IsA("UIScale") then
		return s
	end
	local n = Instance.new("UIScale")
	n.Name = "TweenScale"
	n.Parent = o
	return n
end
UI.scaleOf = scaleOf

-- hover grows a little, press squashes (every button gets this)
function UI.hover(b: GuiButton, amount: number?)
	local up = amount or 1.04
	local s = scaleOf(b)
	b.MouseEnter:Connect(function()
		UI.tween(s, 0.12, { Scale = up })
	end)
	b.MouseLeave:Connect(function()
		UI.tween(s, 0.12, { Scale = 1 })
	end)
	b.SelectionGained:Connect(function()
		UI.tween(s, 0.12, { Scale = up })
	end)
	b.SelectionLost:Connect(function()
		UI.tween(s, 0.12, { Scale = 1 })
	end)
	b.MouseButton1Down:Connect(function()
		UI.tween(s, 0.06, { Scale = 0.95 })
	end)
	b.MouseButton1Up:Connect(function()
		UI.tween(s, 0.12, { Scale = up }, Enum.EasingStyle.Back)
	end)
end

-- pop a panel in (scale from small with a slight overshoot)
function UI.popIn(o: GuiObject, from: number?)
	local s = scaleOf(o)
	s.Scale = from or 0.85
	UI.tween(s, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
end

-- slide a panel in from an offset (x, y in pixels)
function UI.slideIn(o: GuiObject, dx: number, dy: number)
	local home = o:GetAttribute("HomePos") :: UDim2?
	if not home then
		home = o.Position
		o:SetAttribute("HomePos", home)
	end
	local h = home :: UDim2
	o.Position = UDim2.new(h.X.Scale, h.X.Offset + dx, h.Y.Scale, h.Y.Offset + dy)
	UI.tween(o, 0.25, { Position = h }, Enum.EasingStyle.Quint)
end

-- Gradient wordmark: per-glyph Rubik Heavy with letter spacing, a vertical white -> warm
-- gradient, a fat dark outline + drop shadow and a diagonal shine that sweeps across every few
-- seconds. Built at TextSize 100 and scaled with a UIScale (Roblox caps TextSize at 100).
-- Returns the holder (AutomaticSize) and a function to set the pixel size.
function UI.wordmark(text: string, parent: Instance, opts: { [string]: any }?): (Frame, (number) -> ())
	local o = opts or {}
	local top = o.Top or Color3.new(1, 1, 1)
	local bottom = o.Bottom or Color3.new(1.0, 0.8, 0.52)
	local spacing = o.Spacing or 12
	local holder = make("Frame", { Name = "Wordmark", BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.new(), Parent = parent })
	local sc = make("UIScale", { Parent = holder })
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, spacing), VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Parent = holder })
	local shines: { UIGradient } = {}
	local glyphs: { TextLabel } = {}
	local k = 0
	for _, cp in utf8.codes(text) do
		k += 1
		local ch = utf8.char(cp)
		local cell = make("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(if ch == " " then 22 else 0, 112), LayoutOrder = k, Parent = holder })
		if ch ~= " " then
			-- drop shadow (fat outline, offset down)
			local sh = make("TextLabel", { BackgroundTransparency = 1, Text = ch, FontFace = UI.F.Heavy, TextSize = 100, TextColor3 = Color3.new(0, 0.02, 0.08), TextTransparency = 0.45, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 112), Position = UDim2.fromOffset(0, 7), Parent = cell })
			make("UIStroke", { Thickness = 11, Color = Color3.new(0, 0.02, 0.08), Transparency = 0.45, LineJoinMode = Enum.LineJoinMode.Round, Parent = sh })
			local g = make("TextLabel", { BackgroundTransparency = 1, Text = ch, FontFace = UI.F.Heavy, TextSize = 100, TextColor3 = Color3.new(1, 1, 1), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 112), Parent = cell })
			make("UIStroke", { Thickness = 6, Color = Color3.fromHex("1B1208"), LineJoinMode = Enum.LineJoinMode.Round, Parent = g })
			make("UIGradient", { Rotation = 90, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, top), ColorSequenceKeypoint.new(0.25, top), ColorSequenceKeypoint.new(0.9, bottom), ColorSequenceKeypoint.new(1, bottom) }), Parent = g })
			-- shine layer: white text with a narrow slanted band of opacity
			local s = make("TextLabel", { BackgroundTransparency = 1, Text = ch, FontFace = UI.F.Heavy, TextSize = 100, TextColor3 = Color3.new(1, 1, 1), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 112), Parent = cell })
			local sg = make("UIGradient", { Rotation = 20, Offset = Vector2.new(-2, 0), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.42, 1), NumberSequenceKeypoint.new(0.5, 0.35), NumberSequenceKeypoint.new(0.58, 1), NumberSequenceKeypoint.new(1, 1) }), Parent = s })
			table.insert(shines, sg)
			table.insert(glyphs, g)
		end
	end
	-- the sweep: one band crosses the whole word every 4.5 s (each glyph maps it to local space)
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if not holder.Parent then
			conn:Disconnect()
			return
		end
		local gui = holder:FindFirstAncestorWhichIsA("ScreenGui")
		if gui and not gui.Enabled then
			return
		end
		local x0, w = holder.AbsolutePosition.X, math.max(holder.AbsoluteSize.X, 1)
		local ph = ((os.clock() - t0) % 4.5) / 1.6 -- 0..1 sweeps, then rests
		local sweep = x0 - 0.2 * w + ph * 1.4 * w
		for i, sg in shines do
			local gl = glyphs[i]
			local gx, gw = gl.AbsolutePosition.X, math.max(gl.AbsoluteSize.X, 1)
			sg.Offset = Vector2.new(if ph > 1 then -2 else (sweep - (gx + gw * 0.5)) / gw, 0)
		end
	end)
	local function setPx(px: number)
		sc.Scale = px / 100
	end
	return holder, setPx
end

-- soft radial blob (glows, vignettes) drawn once into an EditableImage
local blobs: { [string]: EditableImage } = {}
function UI.blob(key: string, w: number, h: number, inner: number, outer: number, invert: boolean?): EditableImage?
	local id = ("%s:%d:%d"):format(key, w, h)
	if blobs[id] then
		return blobs[id]
	end
	local ok, img = pcall(function()
		return game:GetService("AssetService"):CreateEditableImage({ Size = Vector2.new(w, h) })
	end)
	if not ok or not img then
		return nil
	end
	local b = buffer.create(w * h * 4)
	for y = 0, h - 1 do
		for x = 0, w - 1 do
			local dx, dy = (x + 0.5) / w * 2 - 1, (y + 0.5) / h * 2 - 1
			local d = math.sqrt(dx * dx + dy * dy)
			local t = math.clamp((d - inner) / math.max(outer - inner, 0.001), 0, 1)
			t = t * t * (3 - 2 * t)
			local a = if invert then t else 1 - t
			local o = (y * w + x) * 4
			buffer.writeu8(b, o, 255)
			buffer.writeu8(b, o + 1, 255)
			buffer.writeu8(b, o + 2, 255)
			buffer.writeu8(b, o + 3, math.floor(a * 255 + 0.5))
		end
	end
	img:WritePixelsBuffer(Vector2.zero, Vector2.new(w, h), b)
	blobs[id] = img
	return img
end

return UI
