--!strict
-- Donut action wheel for another nation (layout after the user's reference, in our style):
-- coloured ring segments with an icon each, the hovered segment lifts out and brightens,
-- the centre shows the nation. Options: Attack, Ally/Accept/Break, Troops, Gold, Info.
-- Input: mouse hover + click, touch tap, gamepad stick to aim + A (B closes).
-- Segment art is rendered once into EditableImages (no uploads).
local AssetService = game:GetService("AssetService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

-- mouse position in GUI space (GetMouseLocation includes the top-bar inset)
local function mouseGui(): Vector2
	return UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
end
local State = require(script.Parent.State)
local UI = require(script.Parent.UI)
local Art = require(script.Parent.Art)
local Audio = require(script.Parent.Audio)
local Icons = require(script.Parent.Icons)

local C, F = UI.C, UI.F
local make, label = UI.make, UI.label

local Wheel = {}
Wheel.cb = {} :: { [string]: (...any) -> () }

local SIZE = 240 -- wheel box (px)
local R_IN, R_OUT = 66, 116 -- ring radii in the box
local IMG = 256 -- texture resolution of a segment image

local gui: ScreenGui
local holder: Frame
local center: Frame
local segs: { any } = {}
local hovered = 0
local openFor = 0
local stick = Vector2.zero
local usingPad = false
local segCache: { [string]: EditableImage } = {}

local ICON = {
	attack = "rbxassetid://113909687292200",
	ally = "rbxassetid://104935631577035",
	accept = "rbxassetid://84767021947116",
	breakAlly = "rbxassetid://126107802518727",
	troops = "rbxassetid://125902527528067",
	info = "rbxassetid://108951237981614",
}

-- white ring segment i of n (top-centred first), rim band brighter; tinted at runtime
local function segImage(n: number, i: number): EditableImage?
	local key = n .. ":" .. i
	if segCache[key] then
		return segCache[key]
	end
	local ok, img = pcall(function()
		return AssetService:CreateEditableImage({ Size = Vector2.new(IMG, IMG) })
	end)
	if not ok or not img then
		return nil
	end
	local b = buffer.create(IMG * IMG * 4)
	local c = IMG / 2
	local rin, rout = R_IN / SIZE * IMG, R_OUT / SIZE * IMG
	local span = 2 * math.pi / n
	local a0 = -math.pi / 2 - span / 2 + (i - 1) * span
	local gap = 0.025
	for y = 0, IMG - 1 do
		for x = 0, IMG - 1 do
			local dx, dy = x + 0.5 - c, y + 0.5 - c
			local r = math.sqrt(dx * dx + dy * dy)
			local alpha = 0
			local shade = 1
			if r >= rin and r <= rout then
				local a = math.atan2(dy, dx)
				local rel = (a - a0) % (2 * math.pi)
				if rel > gap and rel < span - gap then
					-- outer rim and inner lip are brighter, body slightly darker (like the reference)
					shade = if r > rout - 7 then 1 elseif r < rin + 4 then 0.9 else 0.72
					alpha = math.clamp(math.min(r - rin, rout - r, (rel - gap) * r, (span - gap - rel) * r), 0, 1)
				end
			end
			local o = (y * IMG + x) * 4
			local v = math.floor(255 * shade)
			buffer.writeu8(b, o, v)
			buffer.writeu8(b, o + 1, v)
			buffer.writeu8(b, o + 2, v)
			buffer.writeu8(b, o + 3, math.floor(255 * alpha))
		end
	end
	img:WritePixelsBuffer(Vector2.zero, Vector2.new(IMG, IMG), b)
	segCache[key] = img
	return img
end

function Wheel.isOpen(): boolean
	return gui ~= nil and gui.Enabled
end

function Wheel.close()
	if gui and gui.Enabled then
		local s = UI.scaleOf(holder)
		UI.tween(s, 0.12, { Scale = 0.7 }).Completed:Once(function()
			if s.Scale < 0.8 then
				gui.Enabled = false
			end
		end)
		openFor = 0
		hovered = 0
	end
end

local function setHover(k: number)
	if k == hovered then
		return
	end
	if segs[hovered] then
		local s = segs[hovered]
		UI.tween(s.img, 0.12, { Size = UDim2.fromScale(1, 1), ImageTransparency = 0.12 })
		UI.tween(s.icon, 0.12, { Size = UDim2.fromOffset(26, 26) })
	end
	hovered = k
	local s = segs[k]
	if s and s.enabled then
		-- lift out + brighten (the reference's highlighted wedge)
		UI.tween(s.img, 0.14, { Size = UDim2.fromScale(1.07, 1.07), ImageTransparency = 0 }, Enum.EasingStyle.Back)
		UI.tween(s.icon, 0.14, { Size = UDim2.fromOffset(32, 32) }, Enum.EasingStyle.Back)
		Audio.play("click")
	end
end

-- segment under a screen point, 0 if none
local function segAt(p: Vector2): number
	local abs = holder.AbsolutePosition + holder.AbsoluteSize / 2
	local d = p - abs
	local scale = holder.AbsoluteSize.X / SIZE
	local r = d.Magnitude / math.max(scale, 0.01)
	if r < R_IN - 6 or r > R_OUT + 14 or #segs == 0 then
		return 0
	end
	local span = 2 * math.pi / #segs
	local a = (math.atan2(d.Y, d.X) + math.pi / 2 + span / 2) % (2 * math.pi)
	return math.floor(a / span) + 1
end

local function pick(k: number)
	local s = segs[k]
	if not s or not s.enabled then
		return
	end
	Wheel.close()
	s.onPick()
end

function Wheel.open(pos: Vector2, nid: number, cell: number, pad: boolean?)
	local n = State.nations[nid]
	local me = State.nations[State.me]
	if not n or not me or nid == State.me then
		return
	end
	for _, s in segs do
		s.img:Destroy()
		s.icon:Destroy()
		s.text:Destroy()
	end
	segs = {}
	hovered = 0
	usingPad = pad == true
	openFor = nid
	local st, pr = State.allyState(nid)
	local req = State.requestWith(nid)
	local isTribe = n.kind == "tribe"
	local allied = st ~= nil
	local share = math.clamp(State.ratio, 0.05, 0.5)
	local function cb(name: string, ...: any)
		local f = Wheel.cb[name]
		if f then
			f(...)
		end
	end
	local opts = {}
	table.insert(opts, { "attack", "Attack", not allied, Color3.fromHex("E5484D"), function()
		cb("attack", cell)
	end })
	if st == "allied" then
		table.insert(opts, { "breakAlly", "Break ally", true, Color3.fromHex("F08A3E"), function()
			cb("ally", "break", nid)
		end })
	elseif st == "breaking" then
		table.insert(opts, { "breakAlly", ("Ends %ds"):format(math.max(0, math.ceil(pr[4] - workspace:GetServerTimeNow()))), false, Color3.fromHex("F08A3E"), function() end })
	elseif req == "theirs" then
		table.insert(opts, { "accept", "Accept", true, Color3.fromHex("46B46E"), function()
			cb("ally", "accept", nid)
		end })
	else
		table.insert(opts, { "ally", if req == "mine" then "Sent" elseif isTribe then "No ally" else "Ally", not isTribe and req ~= "mine", Color3.fromHex("46B46E"), function()
			cb("ally", "request", nid)
		end })
	end
	table.insert(opts, { "troops", "Troops " .. State.fmt(math.floor(me.troops * share)), allied, Color3.fromHex("4A86D9"), function()
		cb("aid", "troops", nid)
	end })
	table.insert(opts, { "gold", "Gold " .. State.fmt(math.floor(me.gold * share)), allied, Color3.fromHex("D9A834"), function()
		cb("aid", "gold", nid)
	end })
	table.insert(opts, { "info", "Info", true, Color3.fromHex("8B6FD1"), function()
		cb("info", cell)
	end })

	local N = #opts
	for k, o in opts do
		local enabled, col = o[3], o[4]
		local img = make("ImageLabel", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			ImageColor3 = if enabled then col else Color3.fromHex("3A424D"),
			ImageTransparency = 0.12,
			ZIndex = 2,
			Parent = holder,
		})
		local e = segImage(N, k)
		if e then
			img.ImageContent = Content.fromObject(e)
		end
		local ang = -math.pi / 2 + (k - 1) * (2 * math.pi / N)
		local mid = (R_IN + R_OUT) / 2
		local cx, cy = math.cos(ang) * mid, math.sin(ang) * mid
		-- pixel icons (same style as the map and build menu)
		local icon = if o[1] == "gold" then Art.coinLabel(26) else Icons.label(o[1], 26)
		icon.Size = UDim2.fromOffset(26, 26)
		icon.Parent = holder
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.new(0.5, cx, 0.5, cy - 6)
		icon.ImageColor3 = if enabled then Color3.new(1, 1, 1) else Color3.fromHex("7A8390")
		icon.ImageTransparency = if enabled then 0 else 0.35
		icon.ZIndex = 3
		local text = label({ Text = o[2], TextSize = 11, FontFace = F.Bold, TextColor3 = if enabled then Color3.new(1, 1, 1) else C.Sub, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, cx, 0.5, cy + 8), Size = UDim2.fromOffset(70, 14), TextStrokeTransparency = 0.6, ZIndex = 3, Parent = holder })
		segs[k] = { img = img, icon = icon, text = text, enabled = enabled, onPick = o[5] }
	end

	-- centre disc: nation name + relation
	for _, c in center:GetChildren() do
		if c:IsA("TextLabel") or c:IsA("Frame") then
			c:Destroy()
		end
	end
	make("Frame", { BackgroundColor3 = n.color, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14), Size = UDim2.fromOffset(14, 14), Parent = center }, { UI.corner(7) })
	label({ Text = n.name, TextSize = 12, FontFace = F.Heavy, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true, Size = UDim2.new(1, -10, 0, 30), Position = UDim2.fromOffset(5, 30), Parent = center })
	label({ Text = if allied then "ALLY" elseif isTribe then "TRIBE" else "RIVAL", TextSize = 10, FontFace = F.Bold, TextColor3 = if allied then C.Good else C.Sub, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 12), Position = UDim2.fromOffset(0, 62), Parent = center })
	label({ Text = State.fmt(n.troops) .. " troops", TextSize = 10, TextColor3 = C.Sub, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 12), Position = UDim2.fromOffset(0, 76), Parent = center })

	local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	holder.Position = UDim2.fromOffset(math.clamp(pos.X, SIZE / 2, vp.X - SIZE / 2), math.clamp(pos.Y, SIZE / 2, vp.Y - SIZE / 2))
	gui.Enabled = true
	UI.popIn(holder, 0.6)
	Audio.play("whoosh")
	if usingPad then
		setHover(1)
	end
end

function Wheel.init()
	gui = make("ScreenGui", { Name = "Wheel", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 25, Enabled = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
	-- full-screen catcher: clicks / taps pick the segment under them, or close
	local catcher = make("TextButton", { Text = "", BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.7, Size = UDim2.fromScale(1, 1), Selectable = false, AutoButtonColor = false, Parent = gui })
	catcher.Activated:Connect(function(io: InputObject?)
		local p = if io then Vector2.new(io.Position.X, io.Position.Y) else mouseGui()
		local k = segAt(p)
		if k > 0 then
			pick(k)
		else
			Wheel.close()
		end
	end)
	holder = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(SIZE, SIZE), Parent = gui })
	center = make("Frame", { BackgroundColor3 = Color3.fromHex("1A1F26"), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(R_IN * 2 - 14, R_IN * 2 - 14), ZIndex = 2, Parent = holder }, { UI.corner(R_IN), UI.stroke(C.Stroke, 2) })

	-- hover tracking (mouse) and stick aiming (gamepad)
	RunService.RenderStepped:Connect(function()
		if not gui.Enabled then
			return
		end
		if stick.Magnitude > 0.5 and #segs > 0 then
			local span = 2 * math.pi / #segs
			local a = (math.atan2(-stick.Y, stick.X) + math.pi / 2 + span / 2) % (2 * math.pi)
			setHover(math.floor(a / span) + 1)
		elseif not usingPad then
			setHover(segAt(mouseGui()))
		end
	end)
	UserInputService.InputChanged:Connect(function(io)
		if io.KeyCode == Enum.KeyCode.Thumbstick1 or io.KeyCode == Enum.KeyCode.Thumbstick2 then
			stick = Vector2.new(io.Position.X, io.Position.Y)
		end
	end)
	UserInputService.InputBegan:Connect(function(io)
		if not gui.Enabled then
			return
		end
		if io.KeyCode == Enum.KeyCode.ButtonA then
			pick(hovered)
		elseif io.KeyCode == Enum.KeyCode.ButtonB then
			Wheel.close()
		elseif io.KeyCode == Enum.KeyCode.DPadRight or io.KeyCode == Enum.KeyCode.DPadDown then
			usingPad = true
			setHover(hovered % #segs + 1)
		elseif io.KeyCode == Enum.KeyCode.DPadLeft or io.KeyCode == Enum.KeyCode.DPadUp then
			usingPad = true
			setHover((hovered - 2) % #segs + 1)
		end
	end)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function Wheel.target(): number
	return openFor
end

return Wheel
