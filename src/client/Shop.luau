--!strict
-- Shop (layout after the user's classic item-shop reference, in our style):
-- tab bar on top, FEATURED ITEMS (tall cards) and DAILY ITEMS (2x3 grid) with timer
-- headers, rarity-coloured cards with NEW! tags and price bars, a purchase popup, a
-- CRATES tab with animated openings, LOCKER and COINS tabs. The backdrop is a pixel-art
-- take on the user's blue swoosh background, rendered at runtime (no uploads).
local AssetService = game:GetService("AssetService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local UI = require(script.Parent.UI)
local Art = require(script.Parent.Art)
local Audio = require(script.Parent.Audio)

local C, F = UI.C, UI.F
local make, label, button, panel = UI.make, UI.label, UI.button, UI.panel
local CHEST = "rbxassetid://104282838998597"
local BUY = Color3.fromHex("2FBF5B")
local NEWRED = Color3.fromHex("E5484D")
local NAVY = Color3.fromHex("0B1430")
local BAR = Color3.fromHex("1E4E9C")
local ITALIC = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold, Enum.FontStyle.Italic)

-- rarity card colours (gradient top / bottom)
local RCOL = {
	common = { Color3.fromHex("6C7A8C"), Color3.fromHex("3A4452") },
	rare = { Color3.fromHex("2E86DE"), Color3.fromHex("164A8C") },
	epic = { Color3.fromHex("A45EE5"), Color3.fromHex("5B2A91") },
	legendary = { Color3.fromHex("F0A43A"), Color3.fromHex("9A5A12") },
}

local Shop = {}
local gui: ScreenGui
local remote: RemoteFunction
local data: any = nil
local tab = "store"
local coinsLbl: TextLabel
local page: Frame
local timers: { TextLabel } = {}
local toastBox: Frame
local toastLbl: TextLabel
local opening: Frame
local reveal: Frame
local popup: Frame
local popupInner: Frame
local tabs: { [string]: TextButton } = {}
local selected: any = nil
local swatchCache: { [string]: EditableImage } = {}

local function fmt(n: number): string
	local s = tostring(math.floor(n))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

local tok = 0
local function toast(text: string, kind: string?)
	tok += 1
	local my = tok
	toastLbl.Text = text
	toastLbl.TextColor3 = if kind == "bad" then C.Bad elseif kind == "good" then C.Good else C.Text
	toastBox.Visible = true
	UI.slideIn(toastBox, 0, 30)
	task.delay(2.6, function()
		if tok == my then
			toastBox.Visible = false
		end
	end)
end

local function call(action: string, arg: any): (boolean, any)
	local ok, a, b, snap = pcall(remote.InvokeServer, remote, action, arg or {})
	if not ok then
		return false, "Network error"
	end
	if typeof(snap) == "table" then
		data = snap
	elseif action == "info" and a then
		data = b
	end
	return a, b
end

----------------------------------------------------------------------------
-- pixel backdrop: blue swooshes (after the user's reference), ordered dithering

local function backdrop(): EditableImage?
	local W, H = 192, 108
	local ok, img = pcall(function()
		return AssetService:CreateEditableImage({ Size = Vector2.new(W, H) })
	end)
	if not ok or not img then
		return nil
	end
	local pal = { Color3.fromHex("0A3F78"), Color3.fromHex("125A9E"), Color3.fromHex("1D77BD"), Color3.fromHex("3398D3"), Color3.fromHex("5BB8E2"), Color3.fromHex("8CD3EE") }
	local bayer = { 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 }
	local function inside(u: number, v: number, cx: number, cy: number, rx: number, ry: number): number
		return ((u - cx) / rx) ^ 2 + ((v - cy) / ry) ^ 2
	end
	local b = buffer.create(W * H * 4)
	for y = 0, H - 1 do
		for x = 0, W - 1 do
			local u, v = x / W, y / H
			local l = 0.62 - ((u - 0.6) ^ 2) * 0.9 - ((v - 0.5) ^ 2) * 1.2
			if inside(u, v, 0.62, -0.2, 0.62, 0.42) < 1 then
				l -= 0.22
			end
			if inside(u, v, 0.62, 1.22, 0.62, 0.42) < 1 then
				l -= 0.22
			end
			if inside(u, v, -0.05, 0.48, 0.42, 0.62) < 1 then
				l -= 0.16
			end
			if inside(u, v, 1.08, 0.5, 0.22, 0.38) < 1 then
				l -= 0.1
			end
			local d = (u - 0.62) * 0.55 + (v - 0.4) * 1.0
			if u > 0.62 and u < 0.98 and v < 0.42 and math.abs(d - (u - 0.62) * 0.85) < 0.012 then
				l += 0.3
			end
			local t = math.clamp(l, 0, 0.999) * (#pal - 1) + (bayer[(y % 4) * 4 + (x % 4) + 1] / 16 - 0.5) * 0.9
			local c = pal[math.clamp(math.floor(t + 0.5) + 1, 1, #pal)]
			local o = (y * W + x) * 4
			buffer.writeu8(b, o, math.floor(c.R * 255))
			buffer.writeu8(b, o + 1, math.floor(c.G * 255))
			buffer.writeu8(b, o + 2, math.floor(c.B * 255))
			buffer.writeu8(b, o + 3, 255)
		end
	end
	img:WritePixelsBuffer(Vector2.zero, Vector2.new(W, H), b)
	return img
end

----------------------------------------------------------------------------
-- item art

local function swatch(skinId: string?, parent: Instance, size: UDim2, pos: UDim2?): ImageLabel
	local l = make("ImageLabel", { BackgroundTransparency = 1, Size = size, Position = pos or UDim2.new(), ResampleMode = Enum.ResamplerMode.Pixelated, Parent = parent }, { UI.corner(6) })
	local key = skinId or "none"
	local img = swatchCache[key]
	if not img then
		local W, H = 48, 30
		local ok, e = pcall(function()
			return AssetService:CreateEditableImage({ Size = Vector2.new(W, H) })
		end)
		if not ok or not e then
			return l
		end
		img = e
		local skin = skinId and Cosmetics.Skins[skinId]
		local base = Color3.fromHex("3FB6FF")
		local shade = base:Lerp(Color3.new(0, 0, 0), 0.25)
		local hi = base:Lerp(Color3.new(1, 1, 1), 0.35)
		local edge = (skin and Cosmetics.edgeColor(skin.pattern)) or base:Lerp(Color3.new(0, 0, 0), 0.5)
		local b = buffer.create(W * H * 4)
		for y = 0, H - 1 do
			for x = 0, W - 1 do
				local col = base
				if x < 2 or y < 2 or x >= W - 2 or y >= H - 2 then
					col = edge
				elseif skin then
					local v = Cosmetics.skinPixel(skin.pattern, x, y)
					col = if v == 1 then shade elseif v == 2 then hi else base
				end
				local o = (y * W + x) * 4
				buffer.writeu8(b, o, math.floor(col.R * 255))
				buffer.writeu8(b, o + 1, math.floor(col.G * 255))
				buffer.writeu8(b, o + 2, math.floor(col.B * 255))
				buffer.writeu8(b, o + 3, 255)
			end
		end
		img:WritePixelsBuffer(Vector2.zero, Vector2.new(W, H), b)
		swatchCache[key] = img
	end
	l.ImageContent = Content.fromObject(img)
	return l
end

local function flagBox(flagId: string, parent: Instance, size: UDim2, pos: UDim2?): Frame
	local f = make("Frame", { BackgroundColor3 = C.Raise, BorderSizePixel = 0, ClipsDescendants = true, Size = size, Position = pos or UDim2.new(), Parent = parent }, { UI.corner(4), UI.stroke(Color3.fromHex("0E1217"), 2) })
	Cosmetics.drawFlag(f, flagId)
	return f
end

local VSPRITE = { boat = "warship", plane = "bomber", missile = "missile" }
local function art(id: string, parent: Instance, w: number, h: number, pos: UDim2)
	if Cosmetics.Skins[id] then
		swatch(id, parent, UDim2.fromOffset(w, h * 0.62), UDim2.new(pos.X.Scale, pos.X.Offset, pos.Y.Scale, pos.Y.Offset + h * 0.19))
	elseif Cosmetics.Vehicles[id] then
		local v = Cosmetics.Vehicles[id]
		local s = Art.spriteFrame(VSPRITE[v.slot], v.palette, parent)
		local side = math.min(w, h)
		s.frame.Size = UDim2.fromOffset(side, side)
		s.frame.Position = UDim2.new(pos.X.Scale, pos.X.Offset + w / 2, pos.Y.Scale, pos.Y.Offset + h / 2)
		Art.colorSprite(s, C.Accent)
	elseif Cosmetics.Flags[id] then
		local fw = math.min(w, h * 1.5)
		flagBox(id, parent, UDim2.fromOffset(fw, fw / 1.5), UDim2.new(pos.X.Scale, pos.X.Offset + (w - fw) / 2, pos.Y.Scale, pos.Y.Offset + (h - fw / 1.5) / 2))
	end
end

local function coinRow(parent: Instance, price: number, size: number, old: number?): Frame
	local row = make("Frame", { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, size), Parent = parent })
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), Parent = row })
	Art.coinLabel(size, row)
	label({ Text = fmt(price), TextSize = size, FontFace = F.Heavy, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, size), Parent = row })
	if old and old > price then
		local o = label({ Text = fmt(old), TextSize = size - 4, FontFace = F.Bold, TextColor3 = Color3.fromHex("9AA6B6"), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, size), Parent = row })
		make("Frame", { BackgroundColor3 = Color3.fromHex("9AA6B6"), BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.55), Size = UDim2.new(1, 0, 0, 2), Parent = o })
	end
	return row
end

----------------------------------------------------------------------------
-- crate opening (pop, escalating shake, rays, flash, card springs out)

local function showReveal(res: any)
	for _, c in reveal:GetChildren() do
		if not c:IsA("UICorner") and not c:IsA("UIStroke") then
			c:Destroy()
		end
	end
	local item = Cosmetics.item(res.item)
	local r = Cosmetics.Rarity[item.rarity]
	reveal.BackgroundColor3 = r.color:Lerp(C.Bg, 0.7)
	label({ Text = r.name, TextSize = 20, FontFace = ITALIC, TextColor3 = r.color, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 18), Parent = reveal })
	art(res.item, reveal, 220, 150, UDim2.new(0.5, -110, 0, 50))
	label({ Text = string.upper(item.name), TextSize = 28, FontFace = ITALIC, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 32), Position = UDim2.fromOffset(0, 206), Parent = reveal })
	label({ Text = if res.new then "NEW! Equip it in the Locker" else ("Duplicate: +%d coins"):format(res.refund), TextSize = 15, TextColor3 = if res.new then C.Good else C.Gold, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 242), Parent = reveal })
	button({ Text = "NICE", Kind = "primary", TextSize = 16, Size = UDim2.fromOffset(140, 40), Position = UDim2.new(0.5, -70, 1, -54) }, function()
		reveal.Visible = false
		opening.Visible = false
	end).Parent = reveal
	reveal.Visible = true
end

function Shop.playCrate(res: any)
	for _, c in opening:GetChildren() do
		c:Destroy()
	end
	local item = Cosmetics.item(res.item)
	local r = Cosmetics.Rarity[item.rarity]
	opening.Visible = true
	opening.BackgroundTransparency = 1
	UI.tween(opening, 0.25, { BackgroundTransparency = 0.25 })
	local rays = make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(640, 640), Parent = opening })
	for k = 0, 7 do
		make("Frame", { BackgroundColor3 = r.color, BackgroundTransparency = 1, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(18, 640), Rotation = k * 22.5, Parent = rays })
	end
	local chest = make("ImageLabel", { BackgroundTransparency = 1, Image = CHEST, ImageColor3 = r.color:Lerp(Color3.new(1, 1, 1), 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(20, 20), ZIndex = 3, Parent = opening })
	local flash = make("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = opening })
	task.spawn(function()
		UI.tween(chest, 0.3, { Size = UDim2.fromOffset(170, 170) }, Enum.EasingStyle.Back).Completed:Wait()
		for k = 1, 9 do
			local a = (if k % 2 == 0 then 1 else -1) * (4 + k * 1.6)
			Audio.play("shake")
			UI.tween(chest, 0.07, { Rotation = a }).Completed:Wait()
		end
		UI.tween(chest, 0.08, { Rotation = 0, Size = UDim2.fromOffset(200, 200) })
		for _, ray in rays:GetChildren() do
			UI.tween(ray, 0.3, { BackgroundTransparency = 0.55 })
		end
		task.spawn(function()
			local t0 = os.clock()
			while opening.Visible and rays.Parent do
				rays.Rotation = (os.clock() - t0) * 40
				task.wait()
			end
		end)
		Audio.play("explosion")
		UI.tween(flash, 0.12, { BackgroundTransparency = 0 }).Completed:Wait()
		chest.Visible = false
		showReveal(res)
		Audio.play("coin")
		local s = UI.scaleOf(reveal)
		s.Scale = 0.4
		UI.tween(flash, 0.5, { BackgroundTransparency = 1 })
		UI.tween(s, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
end

----------------------------------------------------------------------------
-- selections + purchase popup

local function buy(id: string)
	local ok, msg = call("buy", { item = id })
	toast(tostring(msg), if ok then "good" else "bad")
	if ok then
		Audio.play("coin")
	end
	Shop.render()
end

local function itemSel(id: string): any
	local item = Cosmetics.item(id)
	local slot = Cosmetics.slotOf(id)
	local owned = data.owned[id] == true
	local typeName = if Cosmetics.Skins[id] then "Territory skin" elseif Cosmetics.Flags[id] then "Flag" else (({ boat = "Boat skin", plane = "Plane skin", missile = "Missile skin" }) :: any)[slot]
	local sel: any = {
		kind = "item", id = id, name = item.name, rarity = item.rarity, sub = typeName,
		price = Cosmetics.Rarity[item.rarity].price, owned = owned, slot = slot,
		equipped = data.equipped[slot] == id,
		desc = if Cosmetics.Skins[id] then "A pattern drawn over all of your territory."
			elseif Cosmetics.Flags[id] then "Flies on your nameplate and over your land."
			else "Recolours your " .. string.lower((typeName:gsub(" skin", ""))) .. "s. Cosmetic only.",
	}
	sel.onAct = function()
		popup.Visible = false
		if sel.owned then
			local ok, msg = call("equip", { slot = slot, item = if sel.equipped then "" else id })
			toast(tostring(msg), if ok then "good" else "bad")
			Shop.render()
		else
			buy(id)
		end
	end
	return sel
end

local function openPopup(sel: any)
	selected = sel
	for _, c in popupInner:GetChildren() do
		if not c:IsA("UICorner") then
			c:Destroy()
		end
	end
	local rc = RCOL[sel.rarity or "rare"] or RCOL.rare
	popup.Visible = true
	UI.popIn(popupInner.Parent :: GuiObject, 0.85)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(rc[1], rc[2]), Parent = popupInner })
	if sel.kind == "bundle" then
		for k, it in sel.items do
			local col, row = (k - 1) % 2, (k - 1) // 2
			art(it, popupInner, 150, 110, UDim2.new(0, 40 + col * 190, 0, 30 + row * 120))
		end
	elseif sel.kind == "crate" then
		make("ImageLabel", { BackgroundTransparency = 1, Image = CHEST, ImageColor3 = C.Gold, Size = UDim2.fromOffset(200, 200), Position = UDim2.new(0.5, -100, 0, 30), Parent = popupInner })
	elseif sel.kind == "item" then
		art(sel.id, popupInner, 300, 230, UDim2.new(0.5, -150, 0, 20))
	end
	label({ Text = string.upper(sel.name), TextSize = 32, FontFace = ITALIC, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.5, Size = UDim2.new(1, -20, 0, 36), Position = UDim2.new(0, 10, 0, 270), Parent = popupInner })
	label({ Text = sel.sub or "", TextSize = 16, TextColor3 = Color3.fromHex("DCE3EC"), TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 308), Parent = popupInner })
	label({ Text = sel.desc or "", TextSize = 14, TextColor3 = Color3.fromHex("C3CCD8"), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, -40, 0, 36), Position = UDim2.fromOffset(20, 332), Parent = popupInner })
	local text, enabled = "BUY", true
	if sel.kind == "crate" then
		text = "OPEN"
	elseif sel.kind == "pack" then
		text = "GET"
	elseif sel.owned then
		text, enabled = (if sel.equipped then "UNEQUIP" elseif sel.slot then "EQUIP" else "OWNED"), sel.slot ~= nil
	end
	local b = button({ Text = "", BackgroundColor3 = if enabled then (if sel.owned then C.Accent else BUY) else C.Raise, Size = UDim2.new(1, -60, 0, 56), Position = UDim2.new(0, 30, 1, -76) }, function()
		if enabled and sel.onAct then
			sel.onAct()
		end
	end)
	if sel.price and not sel.owned then
		local r = coinRow(b, sel.price, 26, sel.old)
		r.AnchorPoint = Vector2.new(0.5, 0.5)
		r.Position = UDim2.fromScale(0.6, 0.5)
		label({ Text = text, TextSize = 18, FontFace = F.Heavy, Position = UDim2.fromOffset(16, 0), Size = UDim2.fromOffset(90, 56), Parent = b })
	else
		b.Text = text
		b.TextSize = 22
		b.FontFace = F.Heavy
		b.TextColor3 = if enabled then Color3.new(1, 1, 1) else C.Sub
	end
	b.Parent = popupInner
end

----------------------------------------------------------------------------
-- cards (after the reference: tag, art, name band, price bar, rarity border)

local function card(parent: Instance, sel: any, w: number, h: number, delay: number): TextButton
	local rc = RCOL[sel.rarity or "rare"] or RCOL.rare
	local b = make("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Size = UDim2.fromOffset(w, h), Selectable = true, Parent = parent })
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(rc[1], rc[2]), Parent = b })
	local st = make("UIStroke", { Color = rc[1]:Lerp(Color3.new(1, 1, 1), 0.25), Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = b })
	local artH = h - 92
	if sel.kind == "bundle" then
		for k, it in sel.items do
			if k <= 4 then
				local col, row = (k - 1) % 2, (k - 1) // 2
				art(it, b, (w - 30) / 2, artH / 2 - 6, UDim2.new(0, 10 + col * ((w - 30) / 2 + 10), 0, 30 + row * (artH / 2)))
			end
		end
	elseif sel.kind == "crate" then
		make("ImageLabel", { BackgroundTransparency = 1, Image = CHEST, ImageColor3 = C.Gold, Size = UDim2.fromOffset(artH * 0.7, artH * 0.7), Position = UDim2.new(0.5, -artH * 0.35, 0, 24), Parent = b })
	elseif sel.kind == "item" then
		art(sel.id, b, w - 36, artH - 20, UDim2.new(0, 18, 0, 24))
	end
	local band = make("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.55, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 54), Position = UDim2.new(0, 0, 1, -92), Parent = b })
	label({ Text = string.upper(sel.name), TextSize = if w > 200 then 26 else 19, FontFace = ITALIC, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.4, TextTruncate = Enum.TextTruncate.AtEnd, Size = UDim2.new(1, -10, 0, 30), Position = UDim2.fromOffset(5, 2), Parent = band })
	label({ Text = sel.sub or "", TextSize = 13, TextColor3 = Color3.fromHex("D7DCE3"), TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd, Size = UDim2.new(1, -6, 0, 16), Position = UDim2.fromOffset(3, 32), Parent = band })
	local pb = make("Frame", { Name = "PriceBar", BackgroundColor3 = NAVY, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 38), Position = UDim2.new(0, 0, 1, -38), Parent = b })
	if sel.owned then
		label({ Text = "OWNED", TextSize = 18, FontFace = F.Heavy, TextColor3 = C.Good, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), Parent = pb })
	elseif sel.price then
		local r = coinRow(pb, sel.price, 20, sel.old)
		r.AnchorPoint = Vector2.new(0.5, 0.5)
		r.Position = UDim2.fromScale(0.5, 0.5)
	end
	local tagText = if sel.owned then nil elseif sel.tag then sel.tag elseif sel.kind == "item" then "NEW!" else nil
	if tagText then
		local t = make("Frame", { BackgroundColor3 = NEWRED, BorderSizePixel = 0, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 28), Position = UDim2.fromOffset(-6, -8), ZIndex = 3, Parent = b })
		make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 16), Parent = t })
		label({ Text = tagText, TextSize = 17, FontFace = ITALIC, TextColor3 = Color3.new(1, 1, 1), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 28), ZIndex = 3, Parent = t })
		make("Frame", { BackgroundColor3 = NEWRED, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(20, 20), Rotation = 45, ZIndex = 2, Parent = t })
	end
	local sc = UI.scaleOf(b)
	sc.Scale = 0.92
	task.delay(delay, function()
		UI.tween(sc, 0.28, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	local baseCol = st.Color
	local function lift(on: boolean)
		UI.tween(sc, 0.14, { Scale = if on then 1.04 else 1 })
		st.Color = if on then Color3.fromHex("FFE34D") else baseCol
	end
	b.MouseEnter:Connect(function()
		lift(true)
	end)
	b.MouseLeave:Connect(function()
		lift(false)
	end)
	b.SelectionGained:Connect(function()
		lift(true)
	end)
	b.SelectionLost:Connect(function()
		lift(false)
	end)
	b.Activated:Connect(function()
		Audio.play("click")
		openPopup(sel)
	end)
	return b
end

local function sectionHeader(parent: Instance, text: string, x: number, y: number, w: number, timer: boolean)
	local hdr = make("Frame", { BackgroundColor3 = Color3.fromHex("B9D6F2"), BackgroundTransparency = 0.6, BorderSizePixel = 0, Size = UDim2.fromOffset(w, 40), Position = UDim2.fromOffset(x, y), Parent = parent })
	local tagW = #text * 15 + 40
	local slab = make("Frame", { BackgroundColor3 = Color3.fromHex("9CC3EA"), BackgroundTransparency = 0.4, BorderSizePixel = 0, Size = UDim2.fromOffset(tagW, 40), Parent = hdr })
	make("Frame", { BackgroundColor3 = Color3.fromHex("9CC3EA"), BackgroundTransparency = 0.4, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(28, 28), Rotation = 45, Parent = slab })
	label({ Text = string.upper(text), TextSize = 26, FontFace = ITALIC, TextColor3 = Color3.fromHex("F2F6FA"), TextStrokeTransparency = 0.6, Size = UDim2.fromOffset(tagW, 40), Position = UDim2.fromOffset(14, 0), Parent = hdr })
	if timer then
		local t = label({ Text = "", TextSize = 22, FontFace = F.Heavy, TextXAlignment = Enum.TextXAlignment.Right, Size = UDim2.fromOffset(160, 40), Position = UDim2.new(1, -172, 0, 0), Parent = hdr })
		table.insert(timers, t)
	end
	UI.slideIn(hdr, -30, 0)
end

----------------------------------------------------------------------------
-- pages

local function renderStore()
	local fb
	for _, b in Cosmetics.Bundles do
		if b.id == data.featured then
			fb = b
		end
	end
	sectionHeader(page, "Featured items", 0, 0, 700, true)
	local ownsAll, worth = true, 0
	for _, it in fb.items do
		if not data.owned[it] then
			ownsAll = false
		end
		worth += Cosmetics.Rarity[Cosmetics.item(it).rarity].price
	end
	local bsel: any = { kind = "bundle", id = fb.id, name = fb.name, items = fb.items, sub = "Bundle", price = fb.price, old = worth, owned = ownsAll, tag = if worth > fb.price then (fmt(worth - fb.price) .. " OFF") else nil, rarity = "legendary", desc = "Everything in this set, for less than buying each item." }
	bsel.onAct = function()
		popup.Visible = false
		if not ownsAll then
			buy(fb.id)
		end
	end
	local row = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(700, 470), Position = UDim2.fromOffset(0, 58), Parent = page })
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 20), Parent = row })
	card(row, bsel, 220, 470, 0)
	for k, it in fb.items do
		if k <= 2 then
			card(row, itemSel(it), 220, 470, 0.06 * k)
		end
	end
	sectionHeader(page, "Daily items", 740, 0, 500, true)
	local grid = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(500, 470), Position = UDim2.fromOffset(740, 58), Parent = page })
	make("UIGridLayout", { CellSize = UDim2.fromOffset(154, 225), CellPadding = UDim2.fromOffset(19, 20), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	for k, id in data.daily do
		local c = card(grid, itemSel(id), 154, 225, 0.12 + 0.04 * k)
		c.LayoutOrder = k
	end
	label({ Text = "<b>Note:</b> These items are cosmetic only and grant no gameplay advantage.", RichText = true, TextSize = 15, TextColor3 = Color3.fromHex("E3EBF4"), TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromOffset(1240, 20), Position = UDim2.fromOffset(0, 548), Parent = page })
end

local function renderCrates()
	sectionHeader(page, "Crates", 0, 0, 1240, false)
	local row = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(1240, 470), Position = UDim2.fromOffset(0, 58), Parent = page })
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 30), Parent = row })
	for k, cid in Cosmetics.CrateOrder do
		local c = Cosmetics.Crates[cid]
		local odds = {}
		for _, r in Cosmetics.RarityOrder do
			if (c.odds[r] or 0) > 0 then
				table.insert(odds, ("%s %d%%"):format(Cosmetics.Rarity[r].name:sub(1, 1) .. Cosmetics.Rarity[r].name:sub(2):lower(), c.odds[r]))
			end
		end
		local csel: any = { kind = "crate", id = cid, name = c.name, sub = table.concat(odds, " · "), price = c.price, rarity = if cid == "crate_elite" then "epic" else "rare", desc = "A random item. Odds: " .. table.concat(odds, ", ") .. ". Duplicates refund coins." }
		csel.onAct = function()
			popup.Visible = false
			local ok, res = call("crate", { crate = cid })
			if ok then
				Shop.playCrate(res)
			else
				toast(tostring(res), "bad")
			end
			Shop.render()
		end
		card(row, csel, 300, 470, 0.08 * k)
	end
end

local function renderLocker()
	local scroll = make("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 5, Size = UDim2.fromOffset(1240, 600), CanvasSize = UDim2.new(), Parent = page })
	local bySlot: { [string]: { string } } = { skin = {}, flag = {}, boat = {}, plane = {}, missile = {} }
	for id in data.owned do
		local slot = Cosmetics.slotOf(id)
		if slot then
			table.insert(bySlot[slot], id)
		end
	end
	local y = 10
	for _, t in { { "skin", "Territory" }, { "flag", "Flags" }, { "boat", "Boats" }, { "plane", "Planes" }, { "missile", "Missiles" } } do
		local ids = bySlot[t[1]]
		table.sort(ids)
		sectionHeader(scroll, t[2], 0, y, 1220, false)
		y += 54
		if #ids == 0 then
			label({ Text = "Nothing yet. Get some in the Store!", TextSize = 15, TextColor3 = Color3.fromHex("E3EBF4"), Size = UDim2.fromOffset(500, 20), Position = UDim2.fromOffset(6, y), Parent = scroll })
			y += 40
		else
			local grid = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(1220, 0), AutomaticSize = Enum.AutomaticSize.Y, Position = UDim2.fromOffset(0, y + 10), Parent = scroll })
			make("UIGridLayout", { CellSize = UDim2.fromOffset(150, 220), CellPadding = UDim2.fromOffset(16, 18), Parent = grid })
			for k, id in ids do
				card(grid, itemSel(id), 150, 220, 0.02 * k)
			end
			y += math.ceil(#ids / 7) * 238 + 20
		end
	end
	scroll.CanvasSize = UDim2.fromOffset(0, y)
end

local function renderCoins()
	sectionHeader(page, "Get coins", 0, 0, 1240, false)
	label({ Text = "Coins buy crates, bundles and daily items. You also earn coins every match you play, win or lose.", TextSize = 16, TextColor3 = Color3.fromHex("E3EBF4"), TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromOffset(1240, 20), Position = UDim2.fromOffset(0, 50), Parent = page })
	local row = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(1240, 400), Position = UDim2.fromOffset(0, 90), Parent = page })
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 30), Parent = row })
	for k, pack in Cosmetics.CoinPacks do
		local sel: any = { kind = "pack", name = fmt(pack.coins) .. " Coins", sub = (pack.name or "") .. " of coins", rarity = if k == 3 then "legendary" elseif k == 2 then "epic" else "rare", tag = pack.tag, desc = if pack.productId ~= 0 then ("Costs R$ %d."):format(pack.robux) else "Coming soon." }
		sel.onAct = function()
			popup.Visible = false
			local ok, msg = call("pack", { index = k })
			toast(tostring(msg), if ok then "good" else "bad")
		end
		local b = card(row, sel, 260, 400, 0.06 * k)
		for c = 1, math.min(k + 1, 4) do
			local l = Art.coinLabel(90, b)
			l.Position = UDim2.new(0.5, -45 + (c - (math.min(k + 1, 4) + 1) / 2) * 30, 0, 90 - c * 4)
		end
		-- Robux price as plain "R$" text (never confused with our coin)
		local pb = b:FindFirstChild("PriceBar")
		if pb then
			label({ Text = if pack.productId ~= 0 then ("R$ %d"):format(pack.robux) else "SOON", TextSize = 20, FontFace = F.Heavy, TextColor3 = C.Gold, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), Parent = pb })
		end
	end
end

function Shop.render()
	if not data then
		return
	end
	coinsLbl.Text = fmt(data.coins) .. (if data.offline then "  (not saved)" else "")
	for _, c in page:GetChildren() do
		c:Destroy()
	end
	timers = {}
	if tab == "store" then
		renderStore()
	elseif tab == "crates" then
		if data.cratesAllowed then
			renderCrates()
		else
			label({ Text = "Crates are not available in your region.", TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromOffset(1240, 40), Parent = page })
		end
	elseif tab == "locker" then
		renderLocker()
	else
		renderCoins()
	end
end

local function setTab(t: string)
	tab = t
	for name, b in tabs do
		local on = name == t
		UI.tween(b, 0.15, { BackgroundTransparency = if on then 0 else 1 })
		b.TextColor3 = if on then BAR else Color3.new(1, 1, 1)
	end
	Shop.render()
end

function Shop.open()
	gui.Enabled = true
	local root = gui:FindFirstChild("Root")
	if root and root:IsA("GuiObject") then
		UI.popIn(root, 0.95)
	end
	Audio.play("whoosh")
	task.spawn(function()
		call("info")
		Shop.render()
	end)
end

function Shop.close()
	Audio.play("whoosh")
	gui.Enabled = false
end

function Shop.isOpen(): boolean
	return gui ~= nil and gui.Enabled
end

function Shop.init()
	remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Shop") :: RemoteFunction
	gui = make("ScreenGui", { Name = "Shop", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 40, Enabled = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
	local bg = make("ImageLabel", { Name = "Backdrop", BackgroundColor3 = Color3.fromHex("0A3F78"), BorderSizePixel = 0, ScaleType = Enum.ScaleType.Crop, ResampleMode = Enum.ResamplerMode.Pixelated, Size = UDim2.fromScale(1, 1), Active = true, Parent = gui })
	task.spawn(function()
		local img = backdrop()
		if img then
			bg.ImageContent = Content.fromObject(img)
		end
	end)
	make("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.72, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = bg })
	local scale = make("UIScale", { Parent = gui })
	local function rescale()
		local v = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
		scale.Scale = math.clamp(math.min(v.X / 1300, v.Y / 720), 0.45, 1.3)
	end
	rescale()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	end
	local root = make("Frame", { Name = "Root", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(1240, 700), Parent = gui })

	local bar = make("Frame", { Name = "TabBar", BackgroundColor3 = BAR, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(0, 44), AutomaticSize = Enum.AutomaticSize.X, Position = UDim2.new(0.5, 0, 0, 6), Parent = root })
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder, Parent = bar })
	for k, t in { { "store", "STORE" }, { "crates", "CRATES" }, { "locker", "LOCKER" }, { "coins", "COINS" } } do
		local b = make("TextButton", { Name = "Tab_" .. t[1], Text = t[2], TextSize = 22, FontFace = F.Heavy, TextColor3 = Color3.new(1, 1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, AutoButtonColor = false, Size = UDim2.fromOffset(150, 44), LayoutOrder = k, Parent = bar })
		UI.hover(b, 1.04)
		b.Activated:Connect(function()
			Audio.play("click")
			setTab(t[1])
		end)
		tabs[t[1]] = b
	end
	local coins = make("Frame", { BackgroundColor3 = BAR, BorderSizePixel = 0, Size = UDim2.fromOffset(170, 44), Position = UDim2.new(1, -230, 0, 6), Parent = root }, { UI.stroke(Color3.fromHex("6FA8E8"), 2) })
	Art.coinLabel(28, coins).Position = UDim2.fromOffset(10, 8)
	coinsLbl = label({ Text = "-", TextSize = 22, FontFace = F.Heavy, Size = UDim2.new(1, -50, 1, 0), Position = UDim2.fromOffset(46, 0), Parent = coins })
	button({ Text = "X", Kind = "danger", TextSize = 20, FontFace = F.Heavy, Size = UDim2.fromOffset(50, 44), Position = UDim2.new(1, -50, 0, 6) }, function()
		Shop.close()
	end).Parent = root

	page = make("Frame", { Name = "Page", BackgroundTransparency = 1, Size = UDim2.fromOffset(1240, 600), Position = UDim2.fromOffset(0, 84), Parent = root })

	popup = make("Frame", { Name = "Popup", BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Visible = false, Active = true, ZIndex = 6, Parent = gui })
	local box = make("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(420, 470), Parent = popup }, { UI.corner(10), UI.stroke(Color3.fromHex("FFE34D"), 3) })
	popupInner = make("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = box }, { UI.corner(10) })
	local px = button({ Text = "X", Kind = "danger", TextSize = 16, FontFace = F.Heavy, Size = UDim2.fromOffset(36, 36), Position = UDim2.new(1, -44, 0, 8) }, function()
		popup.Visible = false
	end)
	px.ZIndex = 3
	px.Parent = box

	opening = make("Frame", { Name = "Opening", BackgroundColor3 = Color3.fromHex("05070A"), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Visible = false, Active = true, ZIndex = 8, Parent = gui })
	reveal = panel({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(420, 330), Visible = false, ClipsDescendants = true, Parent = gui })
	reveal.ZIndex = 20
	toastBox = panel({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -24), Size = UDim2.fromOffset(0, 34), AutomaticSize = Enum.AutomaticSize.X, Visible = false, ZIndex = 30, Parent = gui })
	UI.pad(10).Parent = toastBox
	toastLbl = label({ Text = "", TextSize = 15, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1), ZIndex = 30, Parent = toastBox })

	UserInputService.InputBegan:Connect(function(io)
		if not gui.Enabled then
			return
		end
		if io.KeyCode == Enum.KeyCode.ButtonX and popup.Visible and selected and selected.onAct then
			selected.onAct()
		elseif io.KeyCode == Enum.KeyCode.ButtonB then
			if opening.Visible then
				reveal.Visible = false
				opening.Visible = false
			elseif popup.Visible then
				popup.Visible = false
			else
				Shop.close()
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			if gui.Enabled and data then
				data.resetIn = math.max(0, (data.resetIn or 0) - 1)
				local left = data.resetIn
				for _, t in timers do
					t.Text = ("%d:%02d:%02d"):format(left // 3600, (left // 60) % 60, left % 60)
				end
			end
		end
	end)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	task.defer(function()
		setTab("store")
	end)
end

return Shop
