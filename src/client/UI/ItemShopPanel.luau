--!nonstrict
-- (Take Over the World!: the item shop, 2026-11-06; it replaces the crate offers and the flag shop.)
-- Coins (the match currency) buy today's items (Data/ItemShop: the same list on every client and the
-- server, by UTC day): two big FEATURED cards (hats and unit skins), six DAILY cards (hats, unit skins,
-- territory skins) and supply crates (opened as before, in the Locker). BUY asks the server
-- (Session.buy_item), which checks the price and the balance and keeps the item; an owned item's card
-- equips it (Session.equip). Opening: the screen dims, the panel pops up, then the cards pop in turn.
local RunService = game:GetService("RunService")
local AssetService = game:GetService("AssetService")
local Workspace = game:GetService("Workspace")
local GuiService = game:GetService("GuiService")
local RS = game:GetService("ReplicatedStorage")
local Airfront = RS:WaitForChild("Airfront")
local ItemShop = require(Airfront.Data.ItemShop)
local Cosmetics = require(Airfront.Data.Cosmetics)
local Gear = require(Airfront.Data.Gear)
local UITheme = require("./UITheme")
local Countryball = require("./Countryball")
local Anim = require("./Anim")

local ItemShopPanel = {}
ItemShopPanel.__index = ItemShopPanel

ItemShopPanel.W, ItemShopPanel.H = 960, 580

local FONT = "rbxassetid://12187365977"
local NAVY = Color3.fromHex("0B1022")
local AMBER = Color3.fromHex("FFC23D")
local TEXT = Color3.new(1, 1, 1)
local TEXT2 = Color3.fromHex("A9B4D0")
local GREEN = Color3.fromHex("5BE38E")
local RED = Color3.fromHex("FF5C61")
--- rarity -> { top, bottom, edge }
local RARITY = {
	common = { Color3.fromHex("7E8AA3"), Color3.fromHex("3B4357"), Color3.fromHex("B9C3D8") },
	uncommon = { Color3.fromHex("5FC24A"), Color3.fromHex("1F5A23"), Color3.fromHex("9CF07E") },
	rare = { Color3.fromHex("3FA6F5"), Color3.fromHex("163E8A"), Color3.fromHex("8FD3FF") },
	epic = { Color3.fromHex("B46CFF"), Color3.fromHex("4A1E8C"), Color3.fromHex("DDB6FF") },
	legendary = { Color3.fromHex("FFB13B"), Color3.fromHex("9A4A0E"), Color3.fromHex("FFE08A") },
}
local KIND_TEXT = { skin = "TERRITORY SKIN", hat = "HAT", boat = "BOAT SKIN", nuke = "NUKE SKIN", missile = "MISSILE SKIN" }
--- pixel art for the unit skins and the crate ("." clear, "o" outline, "a" the colour, "d" lighter,
--- "k" darker, "f" flame, "c" metal)
local ART = {
	boat = {
		"................",
		"......oo........",
		"......oco.......",
		".....oooooo.....",
		"....oaaaaaao....",
		"..oooaddaaaooo..",
		"oooaaaaaaaaaaooo",
		"oaaaaaaaaaaaaaao",
		".oaaaaaaaaaaaao.",
		"..okkkkkkkkkko..",
		"...oooooooooo...",
	},
	nuke = {
		"....oo....oo....",
		"....okko.okko...",
		".....okkookko...",
		"......okkkko....",
		".....oooooooo...",
		"....oaaaaaaaao..",
		"...oaddaaaaaaao.",
		"...oadaaaaaaaao.",
		"...oaaaaaaaaaao.",
		"...oaaaaaaaaaao.",
		"....oaaaaaaaao..",
		".....oaaaaaao...",
		"......oaaaao....",
		".......oooo.....",
	},
	missile = {
		".......oo.......",
		"......oaao......",
		"......oaao......",
		".....oaaaao.....",
		".....oadaao.....",
		".....oadaao.....",
		".....oaaaao.....",
		".....oaaaao.....",
		".....oaaaao.....",
		"....ooaaaaoo....",
		"...okoaaaaoko...",
		"...okkoooookko..",
		"...oo..ff..oo...",
		".......ff.......",
	},
	crate = {
		"oooooooooooooooo",
		"oddddddddddddddo",
		"oaaaaaaaaaaaaaao",
		"oooooooooooooooo",
		"okkkkkkcckkkkkko",
		"okaaaaaccaaaaako",
		"okaaaaaccaaaaako",
		"occcccccccccccco",
		"okaaaaaccaaaaako",
		"okaaaaaccaaaaako",
		"okkkkkkcckkkkkko",
		"oooooooooooooooo",
	},
}
local OUTLINE = Color3.fromRGB(18, 20, 28)
local arts: { [string]: any } = {}
--- `ART[shape]` drawn in colour `col` (cached by `key`), as Content.
local function pixel_art(key: string, shape: string, col: Color3): Content?
	if arts[key] ~= nil then
		return arts[key] or nil
	end
	arts[key] = false
	local rows = ART[shape]
	local S = 16
	local okI, img = pcall(function()
		return AssetService:CreateEditableImage({ Size = Vector2.new(S, S) })
	end)
	if not okI or img == nil then
		return nil
	end
	local pal = {
		o = OUTLINE,
		a = col,
		d = col:Lerp(Color3.new(1, 1, 1), 0.45),
		k = Color3.new(col.R * 0.62, col.G * 0.62, col.B * 0.62),
		f = Color3.fromRGB(255, 150, 40),
		c = Color3.fromRGB(214, 218, 228),
	}
	local b = buffer.create(S * S * 4)
	local oy = (S - #rows) // 2
	for j, row in rows do
		for i = 1, #row do
			local c = pal[string.sub(row, i, i)]
			if c ~= nil then
				local o = ((oy + j - 1) * S + i - 1) * 4
				buffer.writeu8(b, o, math.floor(c.R * 255 + 0.5))
				buffer.writeu8(b, o + 1, math.floor(c.G * 255 + 0.5))
				buffer.writeu8(b, o + 2, math.floor(c.B * 255 + 0.5))
				buffer.writeu8(b, o + 3, 255)
			end
		end
	end
	img:WritePixelsBuffer(Vector2.zero, Vector2.new(S, S), b)
	local content = Content.fromObject(img)
	arts[key] = content
	return content
end
--- the balls hats are shown on (a few flags, by card)
local BALLS = { "gb", "fr", "de", "jp", "br", "us", "it", "ca" }

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
		ZIndex = 44,
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

local function coin_icon(parent: Instance, px: number, props: { [string]: any }?): ImageLabel
	local i = make("ImageLabel", {
		BackgroundTransparency = 1,
		Image = UITheme.icon("gold") or "",
		ImageColor3 = AMBER,
		Size = UDim2.fromOffset(px, px),
		ZIndex = 45,
	}, parent)
	for k, v in props or {} do
		i[k] = v
	end
	return i
end

-- a territory skin's pattern as a small picture (its mask over an amber territory)
local previews = {}
local function skin_preview(id: string): Content?
	if previews[id] ~= nil then
		return previews[id] or nil
	end
	previews[id] = false
	local it = Cosmetics.item(id)
	if it == nil or it.kind ~= "skin" then
		return nil
	end
	local ok, mask, w, h = pcall(Cosmetics.mask, it)
	if not ok then
		return nil
	end
	local S = 32
	local okI, img = pcall(function()
		return AssetService:CreateEditableImage({ Size = Vector2.new(S, S) })
	end)
	if not okI or img == nil then
		return nil
	end
	local base = { 0.86, 0.56, 0.2 }
	local sr, sg, sb = Cosmetics.secondary(it, base[1], base[2], base[3])
	local cell = math.max(1, 2 ^ (it.scale or 0))
	local b = buffer.create(S * S * 4)
	for y = 0, S - 1 do
		for x = 0, S - 1 do
			local k = buffer.readu8(mask, ((y // cell) % h) * w + (x // cell) % w)
			local r, g, bl = base[1], base[2], base[3]
			if k == 1 and it.colors == nil then
				r, g, bl = sr, sg, sb
			elseif k >= 1 and it.colors ~= nil then
				local cr, cg, cb = Cosmetics.color(it, k)
				if cr ~= nil then
					r, g, bl = cr, cg, cb
				end
			end
			local o = (y * S + x) * 4
			buffer.writeu8(b, o, math.floor(r * 255))
			buffer.writeu8(b, o + 1, math.floor(g * 255))
			buffer.writeu8(b, o + 2, math.floor(bl * 255))
			buffer.writeu8(b, o + 3, 255)
		end
	end
	img:WritePixelsBuffer(Vector2.zero, Vector2.new(S, S), b)
	local c = Content.fromObject(img)
	previews[id] = c
	return c
end

--- Show item `f` in the card's art slot.
local function set_art(c: any, f: any, n: number)
	local pic = c.pic
	pic.Visible = false
	pic.ImageContent = Content.none
	pic.Image = ""
	if f.kind == "skin" then
		local p = skin_preview(f.id)
		if p ~= nil then
			pic.ImageContent = p
			pic.Visible = true
		end
		c.pic_corner.CornerRadius = UDim.new(0.18, 0)
		pic.Size = UDim2.fromScale(0.62, 0.62)
	elseif f.kind == "hat" then
		local p = Countryball.ball_content(BALLS[(n - 1) % #BALLS + 1], nil, f.id)
		if p ~= nil then
			pic.ImageContent = p
			pic.Visible = true
		end
		c.pic_corner.CornerRadius = UDim.new(0, 0)
		pic.Size = UDim2.fromScale(0.86, 0.86)
	elseif ART[f.kind] ~= nil then
		local p = pixel_art(f.id, f.kind, Gear.color(f.id) or TEXT)
		if p ~= nil then
			pic.ImageContent = p
			pic.Visible = true
		end
		c.pic_corner.CornerRadius = UDim.new(0, 0)
		pic.Size = UDim2.fromScale(0.8, 0.8)
	end
end

function ItemShopPanel.new(ctx: any, gui: Instance, open_locker: () -> ())
	local self = setmetatable({}, ItemShopPanel)
	self.ctx = ctx
	self.is_open = false
	self.cards = {}
	self.day = -1
	self._open_locker = open_locker
	local dim = make("TextButton", {
		Name = "ItemShop",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromHex("03050C"),
		BackgroundTransparency = 0.25,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 40,
	}, gui)
	self.root = dim
	-- (the holder fits the panel to the screen; the panel's own scale is the pop)
	local holder = make("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(ItemShopPanel.W, ItemShopPanel.H),
		ZIndex = 41,
	}, dim)
	self.fit = make("UIScale", {}, holder)
	self.holder = holder
	local panel = make("Frame", {
		Name = "Panel",
		BackgroundColor3 = NAVY,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 41,
	}, holder)
	self.panel = panel
	make("UICorner", { CornerRadius = UDim.new(0, 18) }, panel)
	make("UIStroke", { Color = AMBER, Transparency = 0.55, Thickness = 2 }, panel)
	make("UIGradient", {
		Color = ColorSequence.new(Color3.fromHex("1A2350"), Color3.fromHex("080B18")),
		Rotation = 90,
	}, panel)
	make("UIPadding", { PaddingTop = UDim.new(0, 16), PaddingLeft = UDim.new(0, 20), PaddingRight = UDim.new(0, 20), PaddingBottom = UDim.new(0, 16) }, panel)
	-- header: the title, the balance, close
	local title = label(panel, "ITEM SHOP", 34, Enum.FontWeight.Heavy, TEXT, { Size = UDim2.fromOffset(300, 40), ZIndex = 44 })
	make("UIStroke", { Color = Color3.fromHex("7A3E00"), Thickness = 2 }, title)
	make("UIGradient", { Color = ColorSequence.new(Color3.fromHex("FFF1B8"), AMBER), Rotation = 90 }, title)
	self.title = title
	local close = make("TextButton", {
		Text = "X",
		TextSize = 18,
		FontFace = Font.new(FONT, Enum.FontWeight.Heavy),
		TextColor3 = TEXT,
		BackgroundColor3 = Color3.fromHex("2A3352"),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 2),
		Size = UDim2.fromOffset(36, 36),
		ZIndex = 45,
	}, panel)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, close)
	close.Activated:Connect(function()
		self:close()
	end)
	Anim.button(close)
	local wallet = make("Frame", {
		BackgroundColor3 = Color3.fromHex("141B36"),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -48, 0, 4),
		Size = UDim2.fromOffset(170, 32),
		ZIndex = 44,
	}, panel)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, wallet)
	make("UIStroke", { Color = AMBER, Transparency = 0.5 }, wallet)
	coin_icon(wallet, 22, { Position = UDim2.fromOffset(8, 5) })
	self.balance = label(wallet, "0", 18, Enum.FontWeight.Heavy, TEXT, {
		Position = UDim2.fromOffset(36, 5),
		Size = UDim2.new(1, -46, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	self.wallet = wallet
	-- the two sections
	local function banner(x: number, w: number, text: string): TextLabel
		local b = make("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			Position = UDim2.fromOffset(x, 56),
			Size = UDim2.fromOffset(w, 34),
			ZIndex = 42,
		}, panel)
		make("UICorner", { CornerRadius = UDim.new(0, 8) }, b)
		make("UIGradient", {
			Color = ColorSequence.new(Color3.fromHex("FFD25A"), Color3.fromHex("E8892A")),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.6, 0.55), NumberSequenceKeypoint.new(1, 1) }),
		}, b)
		label(b, text, 20, Enum.FontWeight.Heavy, Color3.fromHex("1B1000"), { Position = UDim2.fromOffset(12, 5), Size = UDim2.fromOffset(240, 24) })
		local chip = make("Frame", {
			BackgroundColor3 = Color3.fromHex("0B1022"),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -6, 0.5, 0),
			Size = UDim2.fromOffset(130, 24),
			ZIndex = 43,
		}, b)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, chip)
		local t = label(chip, "", 13, Enum.FontWeight.Bold, TEXT, {
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		return t
	end
	local FW = 404
	local DX = FW + 18
	local DW = ItemShopPanel.W - 40 - DX
	self.timer_a = banner(0, FW, "FEATURED ITEMS")
	self.timer_b = banner(DX, DW, "DAILY ITEMS")
	local TOP, BOTTOM = 100, ItemShopPanel.H - 32 - 26
	local big_w = (FW - 14) / 2
	local cols, rows = 4, 2
	local cw = (DW - (cols - 1) * 12) / cols
	local ch = (BOTTOM - TOP - (rows - 1) * 12) / rows
	-- a card: rarity gradient, art, a dark band with the name, the kind and the price
	local function card(x: number, y: number, w: number, h: number, big: boolean): any
		local hit = make("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Color3.new(1, 1, 1),
			Position = UDim2.fromOffset(x + w / 2, y + h / 2),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(w, h),
			ZIndex = 42,
			Selectable = true,
		}, panel)
		make("UICorner", { CornerRadius = UDim.new(0, 12) }, hit)
		local grad = make("UIGradient", { Rotation = 90 }, hit)
		local edge = make("UIStroke", { Thickness = 2, Transparency = 0.1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, hit)
		-- a soft light behind the art
		local glow = make("ImageLabel", {
			BackgroundTransparency = 1,
			Image = UITheme.crate_art().glow or "",
			ImageTransparency = 0.55,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, if big then 0.36 else 0.34),
			Size = UDim2.fromScale(1.1, if big then 0.62 else 0.7),
			ZIndex = 42,
		}, hit)
		local art = make("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, if big then 0.37 else 0.34),
			Size = UDim2.new(1, -16, if big then 0.62 else 0.56, 0),
			ZIndex = 43,
		}, hit)
		make("UIAspectRatioConstraint", { AspectRatio = 1 }, art)
		local pic = make("ImageLabel", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.86, 0.86),
			ResampleMode = Enum.ResamplerMode.Pixelated,
			ZIndex = 44,
		}, art)
		local pic_corner = make("UICorner", { CornerRadius = UDim.new(0, 0) }, pic)
		local band_h = if big then 92 else 74
		local band = make("Frame", {
			BackgroundColor3 = Color3.fromHex("060812"),
			BackgroundTransparency = 0.25,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, band_h),
			ZIndex = 44,
		}, hit)
		make("UICorner", { CornerRadius = UDim.new(0, 12) }, band)
		local name = label(band, "", if big then 20 else 14, Enum.FontWeight.Heavy, TEXT, {
			Position = UDim2.fromOffset(10, 8),
			Size = UDim2.new(1, -20, 0, if big then 24 else 18),
			ZIndex = 45,
		})
		local kind = label(band, "", if big then 12 else 10, Enum.FontWeight.Bold, TEXT2, {
			Position = UDim2.fromOffset(10, if big then 34 else 27),
			Size = UDim2.new(1, -20, 0, 14),
			ZIndex = 45,
		})
		local price_y = if big then 56 else 46
		local coin = coin_icon(band, if big then 22 else 17, { Position = UDim2.fromOffset(10, price_y) })
		local price = label(band, "", if big then 20 else 15, Enum.FontWeight.Heavy, TEXT, {
			Position = UDim2.fromOffset(if big then 38 else 31, price_y),
			Size = UDim2.new(1, -48, 0, if big then 22 else 17),
			ZIndex = 45,
		})
		local tag = make("TextLabel", {
			Text = "NEW!",
			TextSize = if big then 16 else 12,
			FontFace = Font.new(FONT, Enum.FontWeight.Heavy),
			TextColor3 = Color3.fromHex("1B1000"),
			BackgroundColor3 = Color3.fromHex("FFE14D"),
			Position = UDim2.fromOffset(-6, 8),
			Size = UDim2.fromOffset(if big then 58 else 44, if big then 24 else 19),
			Rotation = -8,
			Visible = false,
			ZIndex = 46,
		}, hit)
		make("UICorner", { CornerRadius = UDim.new(0, 5) }, tag)
		make("UIStroke", { Color = Color3.fromHex("1B1000"), Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, tag)
		local c = {
			hit = hit,
			grad = grad,
			edge = edge,
			glow = glow,
			pic = pic,
			pic_corner = pic_corner,
			name = name,
			kind = kind,
			coin = coin,
			price = price,
			tag = tag,
			big = big,
			id = nil,
		}
		Anim.button(hit, nil, 1.04)
		return c
	end
	for i = 1, ItemShop.FEATURED do
		local c = card((i - 1) * (big_w + 14), TOP, big_w, BOTTOM - TOP, true)
		c.hit.Activated:Connect(function()
			self:_activate(c)
		end)
		self.cards[i] = c
	end
	for i = 1, cols * rows do
		local col, row = (i - 1) % cols, (i - 1) // cols
		local c = card(DX + col * (cw + 12), TOP + row * (ch + 12), cw, ch, false)
		c.hit.Activated:Connect(function()
			self:_activate(c)
		end)
		self.cards[ItemShop.FEATURED + i] = c
	end
	-- the last two daily cells: a crate to buy, and the crates waiting to be opened
	local n = #self.cards
	self.crate_card = self.cards[n - 1]
	self.locker_card = self.cards[n]
	self.cards[n - 1], self.cards[n] = nil, nil
	for _, c in { self.crate_card, self.locker_card } do
		local p = pixel_art("crate", "crate", Color3.fromRGB(122, 132, 64))
		if p ~= nil then
			c.pic.ImageContent = p
		end
		c.pic.Visible = true
		c.pic.Size = UDim2.fromScale(0.8, 0.8)
		c.grad.Color = ColorSequence.new(Color3.fromHex("C98A3A"), Color3.fromHex("5A3410"))
		c.edge.Color = Color3.fromHex("FFD38A")
	end
	self.crate_card.name.Text = "CRATE"
	self.crate_card.kind.Text = "RANDOM SKIN"
	self.crate_card.price.Text = commas(ItemShop.CRATE_PRICE)
	self.crate_card.hit.Activated:Connect(function()
		self:_buy("crate")
	end)
	self.locker_card.name.Text = "MY CRATES"
	self.locker_card.kind.Text = "IN THE LOCKER"
	self.locker_card.coin.Visible = false
	self.locker_card.price.Position = UDim2.fromOffset(10, self.locker_card.price.Position.Y.Offset)
	self.locker_card.hit.Activated:Connect(function()
		self.ctx:sfx("click")
		self:close()
		open_locker()
	end)
	-- the toast
	self.toast = label(panel, "", 15, Enum.FontWeight.Heavy, GREEN, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
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

function ItemShopPanel._fit(self)
	local cam = Workspace.CurrentCamera
	local vp = if cam then cam.ViewportSize else Vector2.new(1280, 720)
	-- (below Roblox's top bar: clicks there go to its buttons, not the panel's)
	local top = GuiService:GetGuiInset().Y
	self.fit.Scale = math.min(1, (vp.X - 24) / ItemShopPanel.W, (vp.Y - top - 24) / ItemShopPanel.H)
	self.holder.Position = UDim2.new(0.5, 0, 0.5, top / 2)
end

function ItemShopPanel._inv(self): any
	local s = self.ctx.session
	return s and s.inventory
end

function ItemShopPanel._coins(self): number
	local inv = self:_inv()
	return (inv and tonumber(inv.stars)) or 0
end

function ItemShopPanel._crates(self): number
	local s = self.ctx.session
	local c = s and s.credits
	return (c and tonumber(c.crate)) or 0
end

function ItemShopPanel._owned(self, id: string): boolean
	local inv = self:_inv()
	if inv == nil or type(inv.owned) ~= "table" then
		return false
	end
	if inv.owned[id] == true then
		return true
	end
	return table.find(inv.owned, id) ~= nil
end

function ItemShopPanel._worn(self, kind: string, id: string): boolean
	local inv = self:_inv()
	return inv ~= nil and type(inv.equipped) == "table" and inv.equipped[kind] == id
end

local function clock(left: number): string
	return string.format("%02d:%02d:%02d", left // 3600, (left % 3600) // 60, left % 60)
end

function ItemShopPanel.refresh(self)
	local coins = self:_coins()
	self.balance.Text = commas(coins)
	local now = os.time()
	local day = now // 86400
	local left = 86400 - now % 86400
	self.timer_a.Text = "RESETS " .. clock(left)
	self.timer_b.Text = "RESETS " .. clock(left)
	local n = self:_crates()
	self.locker_card.price.Text = string.format("%d READY", n)
	self.locker_card.tag.Visible = n > 0
	self.locker_card.tag.Text = "OPEN!"
	self.crate_card.price.TextColor3 = if coins >= ItemShop.CRATE_PRICE then TEXT else RED
	if day ~= self.day then
		self.day = day
		local list = ItemShop.featured(day)
		for i, c in self.cards do
			local f = list[i]
			c.id = f and f.id
			c.f = f
			c.hit.Visible = f ~= nil
			if f ~= nil then
				local r = RARITY[f.rarity or "common"] or RARITY.common
				c.grad.Color = ColorSequence.new(r[1], r[2])
				c.edge.Color = r[3]
				c.glow.ImageColor3 = r[3]
				c.name.Text = string.upper(f.name)
				c.kind.Text = (KIND_TEXT[f.kind] or "ITEM")
					.. (if c.big then "  ·  " .. string.upper(tostring(f.rarity or "common")) else "")
				c.tag.Visible = not ItemShop.on_sale(f.id, day - 1)
				set_art(c, f, i)
			end
		end
	end
	for _, c in self.cards do
		local f = c.f
		if f ~= nil then
			if self:_owned(f.id) then
				c.coin.Visible = false
				c.price.Position = UDim2.fromOffset(10, c.price.Position.Y.Offset)
				if self:_worn(f.kind, f.id) then
					c.price.Text = "EQUIPPED"
					c.price.TextColor3 = GREEN
				else
					c.price.Text = if c.big then "OWNED · EQUIP" else "EQUIP"
					c.price.TextColor3 = AMBER
				end
			else
				c.coin.Visible = true
				c.price.Position = UDim2.fromOffset(if c.big then 38 else 31, c.price.Position.Y.Offset)
				c.price.Text = commas(f.price)
				c.price.TextColor3 = if coins >= f.price then TEXT else RED
			end
		end
	end
end

--- A card pressed: buy it, or (owned) wear it / take it off.
function ItemShopPanel._activate(self, c: any)
	local f = c.f
	if f == nil then
		return
	end
	if not self:_owned(f.id) then
		self:_buy(f.id)
		return
	end
	local s = self.ctx.session
	if s == nil or type(s.equip) ~= "function" then
		return
	end
	local wearing = self:_worn(f.kind, f.id)
	s:equip(f.kind, if wearing then false else f.id)
	self.ctx:sfx("click")
	self:_toast(if wearing then "Taken off." else (f.name .. " equipped!"), GREEN)
end

function ItemShopPanel._buy(self, id: string)
	local s = self.ctx.session
	if s == nil or type(s.buy_item) ~= "function" then
		return
	end
	s:buy_item(id)
	self.ctx:sfx("click")
	self:_toast("Buying…", TEXT2)
end

function ItemShopPanel._toast(self, text: string, color: Color3)
	self.toast.Text = text
	self.toast.TextColor3 = color
	Anim.pop(self.toast, 0, 0.7)
end

--- The server's answer (Session "item_result").
function ItemShopPanel.on_result(self, id: string, ok: boolean, why: string?)
	if ok then
		local it = Cosmetics.item(id)
		self:_toast(
			if id == "crate"
				then "Crate bought! Open it from MY CRATES."
				else ((if it then it.name else "Item") .. " bought! Press its card to equip it."),
			GREEN
		)
		self.ctx:sfx("buy")
		Anim.pop(self.wallet, 0, 0.8)
	else
		self:_toast(
			if why == "not enough" then "Not enough coins yet: play matches and finish quests." else ("Couldn't buy: " .. tostring(why)),
			RED
		)
		self.ctx:sfx("deny", -4.0)
	end
	self:refresh()
end

function ItemShopPanel.open(self)
	self.is_open = true
	self.toast.Text = ""
	self:_fit()
	self:refresh()
	-- the screen dims, the panel pops, then everything in it pops in turn
	Anim.open(self.root, self.panel)
	local d = Anim.FADE_S * 0.6 + 0.12
	Anim.pop(self.title, d)
	Anim.pop(self.wallet, d + 0.04)
	local k = 0
	for _, c in self.cards do
		Anim.pop(c.hit, d + 0.1 + k * 0.05)
		k += 1
	end
	Anim.pop(self.crate_card.hit, d + 0.1 + k * 0.05)
	Anim.pop(self.locker_card.hit, d + 0.15 + k * 0.05)
	self.ctx:sfx("open")
end

function ItemShopPanel.close(self)
	if not self.is_open then
		return
	end
	self.is_open = false
	Anim.close(self.root, self.panel)
	self.ctx:sfx("close")
end

return ItemShopPanel
