--!nonstrict
-- (Take Over the World!: the item shop, 2026-11-07 layout: a full screen over a pixel-art showroom.)
-- Coins (the match currency) buy today's gear (Data/ItemShop: the same list on every client and the
-- server, by UTC day): three tall FEATURED cards and six DAILY cards, each in its rarity's colours with
-- the item's picture (UI/GearArt), its name, its kind and its price. Hats are worn by the player's
-- Countryball; boat / nuke / missile skins colour those units. Supply crates (a random piece of gear)
-- are bought and opened from the top bar. BUY asks the server (Session.buy_item), which checks the
-- price and the balance, keeps the item and wears it when its slot is empty; an owned card wears it /
-- takes it off (Session.equip). Opening: the backdrop fades in, then everything pops in turn.
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local GuiService = game:GetService("GuiService")
local RS = game:GetService("ReplicatedStorage")
local Airfront = RS:WaitForChild("Airfront")
local ItemShop = require(Airfront.Data.ItemShop)
local Cosmetics = require(Airfront.Data.Cosmetics)
local UITheme = require("./UITheme")
local GearArt = require("./GearArt")
local Anim = require("./Anim")

local ItemShopPanel = {}
ItemShopPanel.__index = ItemShopPanel

--- the design canvas (scaled to the screen)
ItemShopPanel.W, ItemShopPanel.H = 1280, 720
ItemShopPanel.BACKDROP = "rbxassetid://84971757872319" -- tools/build_shop_bg.py
ItemShopPanel.ICON = "rbxassetid://116782632104302" -- the item shop stall

local FONT = "rbxassetid://12187365977"
local AMBER = Color3.fromHex("FFC23D")
local INK = Color3.fromHex("1B1000")
local TEXT = Color3.new(1, 1, 1)
local TEXT2 = Color3.fromHex("C9D2EA")
local GREEN = Color3.fromHex("5BE38E")
local RED = Color3.fromHex("FF5C61")
--- rarity -> { light, dark, band, accent }
local RARITY = {
	common = { Color3.fromHex("8E9BB5"), Color3.fromHex("4A556E"), Color3.fromHex("37405A"), Color3.fromHex("D7DEEE") },
	rare = { Color3.fromHex("49B6FF"), Color3.fromHex("1C5FC9"), Color3.fromHex("174A9E"), Color3.fromHex("A9E0FF") },
	epic = { Color3.fromHex("C176FF"), Color3.fromHex("6A2BC4"), Color3.fromHex("52209A"), Color3.fromHex("E6C6FF") },
	legendary = { Color3.fromHex("FFB13B"), Color3.fromHex("D2621A"), Color3.fromHex("A84A12"), Color3.fromHex("FFE3A1") },
}
local KIND_TEXT = { hat = "COUNTRYBALL HAT", boat = "BOAT SKIN", nuke = "NUKE SKIN", missile = "MISSILE SKIN" }
--- the balls hats are shown on (a few flags, by card)
local BALLS = { "gb", "fr", "de", "jp", "br", "us", "it", "ca", "mx" }

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
		ZIndex = 46,
	}, parent)
	for k, v in props or {} do
		i[k] = v
	end
	return i
end

--- A price: the coin and the number, centred as one row.
local function price_row(parent: Instance, size: number, y: number): any
	local row = make("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, y),
		Size = UDim2.new(1, -12, 0, size + 6),
		ZIndex = 45,
	}, parent)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)
	local coin = coin_icon(row, size + 4, { LayoutOrder = 1 })
	local text = label(row, "", size, Enum.FontWeight.Heavy, TEXT, {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, size + 4),
		LayoutOrder = 2,
		ZIndex = 46,
	})
	make("UIStroke", { Color = Color3.new(0, 0, 0), Transparency = 0.55, Thickness = 1.5 }, text)
	return { row = row, coin = coin, text = text }
end

--- A section banner: a slanted amber tab with the title, a long bar with the time left.
local function banner(parent: Instance, x: number, y: number, w: number, title: string): (TextLabel, Frame, Frame)
	local bar = make("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.1,
		Position = UDim2.fromOffset(x + 8, y + 6),
		Size = UDim2.fromOffset(w - 8, 34),
		ZIndex = 42,
	}, parent)
	make("UIGradient", { Color = ColorSequence.new(Color3.fromHex("2D4BA8"), Color3.fromHex("1B2556")) }, bar)
	local tab = make("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(250, 46),
		ZIndex = 43,
	}, parent)
	make("UIGradient", { Color = ColorSequence.new(Color3.fromHex("FFE07A"), Color3.fromHex("FFA928")), Rotation = 90 }, tab)
	make("UIStroke", { Color = INK, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, tab)
	label(tab, title, 26, Enum.FontWeight.Heavy, INK, {
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.fromOffset(230, 30),
		ZIndex = 45,
	})
	local timer = label(bar, "", 22, Enum.FontWeight.Heavy, TEXT, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(160, 26),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 45,
	})
	return timer, tab, bar
end

function ItemShopPanel.new(ctx: any, gui: Instance, open_locker: () -> ())
	local self = setmetatable({}, ItemShopPanel)
	self.ctx = ctx
	self.is_open = false
	self.cards = {}
	self.day = -1
	self._pops = {}
	-- the screen: the showroom backdrop (pixel art), dimmed at the top and bottom for the words
	local root = make("TextButton", {
		Name = "ItemShop",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromHex("05060C"),
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 40,
	}, gui)
	self.root = root
	self.backdrop = make("ImageLabel", {
		BackgroundTransparency = 1,
		Image = ItemShopPanel.BACKDROP,
		ResampleMode = Enum.ResamplerMode.Pixelated,
		ScaleType = Enum.ScaleType.Crop,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 40,
	}, root)
	self.shade = make("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 41,
	}, root)
	make("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(0.22, 0.72),
			NumberSequenceKeypoint.new(0.75, 0.8),
			NumberSequenceKeypoint.new(1, 0.35),
		}),
		Rotation = 90,
	}, self.shade)
	-- the design canvas, scaled to the screen below Roblox's top bar
	local canvas = make("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(ItemShopPanel.W, ItemShopPanel.H),
		ZIndex = 42,
	}, root)
	self.canvas = canvas
	self.fit = make("UIScale", {}, canvas)
	local function pop(inst: GuiObject): any
		table.insert(self._pops, inst)
		return inst
	end
	-- top bar: the title, crates, the wallet, close
	local head = pop(make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(24, 10), Size = UDim2.fromOffset(420, 70), ZIndex = 43 }, canvas))
	make("ImageLabel", {
		BackgroundTransparency = 1,
		Image = ItemShopPanel.ICON,
		Size = UDim2.fromOffset(66, 66),
		ZIndex = 44,
	}, head)
	local title = label(head, "ITEM SHOP", 44, Enum.FontWeight.Heavy, TEXT, {
		Position = UDim2.fromOffset(76, 12),
		Size = UDim2.fromOffset(340, 48),
	})
	make("UIStroke", { Color = Color3.fromHex("7A3E00"), Thickness = 3 }, title)
	make("UIGradient", { Color = ColorSequence.new(Color3.fromHex("FFF1B8"), AMBER), Rotation = 90 }, title)
	local close = pop(make("TextButton", {
		Text = "X",
		TextSize = 22,
		FontFace = Font.new(FONT, Enum.FontWeight.Heavy),
		TextColor3 = TEXT,
		BackgroundColor3 = Color3.fromHex("C83A3A"),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 20),
		Size = UDim2.fromOffset(48, 48),
		ZIndex = 44,
	}, canvas))
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, close)
	make("UIStroke", { Color = INK, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, close)
	close.Activated:Connect(function()
		self:close()
	end)
	Anim.button(close)
	local wallet = pop(make("Frame", {
		BackgroundColor3 = Color3.fromHex("141B36"),
		BackgroundTransparency = 0.1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -84, 0, 22),
		Size = UDim2.fromOffset(200, 44),
		ZIndex = 43,
	}, canvas))
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, wallet)
	make("UIStroke", { Color = AMBER, Thickness = 2, Transparency = 0.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, wallet)
	coin_icon(wallet, 30, { Position = UDim2.fromOffset(10, 7) })
	self.balance = label(wallet, "0", 24, Enum.FontWeight.Heavy, TEXT, {
		Position = UDim2.fromOffset(46, 8),
		Size = UDim2.new(1, -58, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 45,
	})
	self.wallet = wallet
	local function pill(x: number, w: number): (TextButton, TextLabel)
		local b = pop(make("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Color3.new(1, 1, 1),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, x, 0, 22),
			Size = UDim2.fromOffset(w, 44),
			ZIndex = 43,
		}, canvas))
		make("UICorner", { CornerRadius = UDim.new(0, 10) }, b)
		make("UIStroke", { Color = INK, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
		make("UIGradient", { Color = ColorSequence.new(Color3.fromHex("9BBE58"), Color3.fromHex("5A7A2A")), Rotation = 90 }, b)
		local l = label(b, "", 17, Enum.FontWeight.Heavy, TEXT, {
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 45,
		})
		make("UIStroke", { Color = INK, Transparency = 0.4 }, l)
		Anim.button(b)
		return b, l
	end
	local buy_crate, buy_l = pill(-296, 200)
	self.buy_crate_l = buy_l
	buy_l.Text = "BUY CRATE · " .. commas(ItemShop.CRATE_PRICE)
	buy_crate.Activated:Connect(function()
		self:_buy("crate")
	end)
	local open_crates, open_l = pill(-508, 200)
	self.open_crates_l = open_l
	open_crates.Activated:Connect(function()
		self.ctx:sfx("click")
		self:close()
		open_locker()
	end)
	-- the two sections
	local FX, FW = 24, 724
	local DX = FX + FW + 32
	local DW = ItemShopPanel.W - 24 - DX
	local TOP, CARD_H = 156, 476
	local ta, tab_a, bar_a = banner(canvas, FX, 96, FW, "FEATURED ITEMS")
	local tb, tab_b, bar_b = banner(canvas, DX, 96, DW, "DAILY ITEMS")
	self.timer_a, self.timer_b = ta, tb
	for _, o in { tab_a, bar_a, tab_b, bar_b } do
		pop(o)
	end
	-- a card: the rarity's colours with light rays, the picture, a slanted band with the words
	local function card(x: number, y: number, w: number, h: number, big: boolean): any
		local hit = pop(make("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x + w / 2, y + h / 2),
			Size = UDim2.fromOffset(w, h),
			ZIndex = 42,
			Selectable = true,
		}, canvas))
		local edge = make("UIStroke", { Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = INK }, hit)
		-- (a canvas group clips the slanted band and the rays)
		local body = make("CanvasGroup", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			Size = UDim2.fromScale(1, 1),
			ZIndex = 42,
		}, hit)
		-- (the colours on a frame of their own: a gradient on the canvas group would tint all of it)
		local bg = make("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 42,
		}, body)
		local grad = make("UIGradient", { Rotation = 90 }, bg)
		for i = 1, 3 do
			make("Frame", {
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = 0.88,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.18 + (i - 1) * 0.34, 0, 0.3, 0),
				Size = UDim2.new(0, if big then 26 else 16, 1.6, 0),
				Rotation = 24,
				ZIndex = 42,
			}, body)
		end
		local glow = make("ImageLabel", {
			BackgroundTransparency = 1,
			Image = UITheme.crate_art().glow or "",
			ImageTransparency = 0.45,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.36),
			Size = UDim2.fromScale(1.2, 0.7),
			ZIndex = 43,
		}, body)
		local art = make("ImageLabel", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, if big then 0.37 else 0.36),
			Size = UDim2.fromScale(if big then 0.86 else 0.74, if big then 0.86 else 0.74),
			ResampleMode = Enum.ResamplerMode.Pixelated,
			ZIndex = 44,
		}, body)
		make("UIAspectRatioConstraint", { AspectRatio = 1 }, art)
		local band_h = if big then 150 else 86
		local band = make("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 1, -band_h),
			Size = UDim2.new(1.3, 0, 0, band_h + 40),
			Rotation = -6,
			ZIndex = 44,
		}, body)
		local band_grad = make("UIGradient", { Rotation = 90 }, band)
		-- (a notch of lightning on its top edge)
		local notch = make("Frame", {
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.6, 0, 0, 0),
			Size = UDim2.fromOffset(if big then 30 else 18, if big then 30 else 18),
			Rotation = 45,
			ZIndex = 44,
		}, band)
		local name = label(body, "", if big then 28 else 17, Enum.FontWeight.Heavy, TEXT, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 1, if big then -104 else -64),
			Size = UDim2.new(1, -16, 0, if big then 32 else 20),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextScaled = true, -- (a long name shrinks to fit)
			ZIndex = 46,
		})
		make("UITextSizeConstraint", { MaxTextSize = if big then 28 else 17, MinTextSize = 8 }, name)
		make("UIStroke", { Color = Color3.new(0, 0, 0), Transparency = 0.5, Thickness = 1.5 }, name)
		local kind = label(body, "", if big then 14 else 10, Enum.FontWeight.Heavy, TEXT2, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 1, if big then -70 else -43),
			Size = UDim2.new(1, -16, 0, if big then 16 else 12),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 46,
		})
		local price = price_row(body, if big then 24 else 16, h - (if big then 50 else 28))
		local tag = make("TextLabel", {
			Text = "NEW!",
			TextSize = if big then 22 else 15,
			FontFace = Font.new(FONT, Enum.FontWeight.Heavy),
			TextColor3 = INK,
			BackgroundColor3 = Color3.fromHex("FFE14D"),
			Position = UDim2.fromOffset(-10, -10),
			Size = UDim2.fromOffset(if big then 82 else 58, if big then 34 else 24),
			Rotation = -6,
			Visible = false,
			ZIndex = 48,
		}, hit)
		make("UIStroke", { Color = INK, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, tag)
		local c = {
			hit = hit,
			edge = edge,
			grad = grad,
			glow = glow,
			art = art,
			band_grad = band_grad,
			notch = notch,
			name = name,
			kind = kind,
			price = price,
			tag = tag,
			big = big,
		}
		Anim.button(hit, nil, 1.04)
		hit.Activated:Connect(function()
			self:_activate(c)
		end)
		return c
	end
	local fw = (FW - 2 * 18) / 3
	for i = 1, ItemShop.FEATURED do
		self.cards[i] = card(FX + (i - 1) * (fw + 18), TOP, fw, CARD_H, true)
	end
	local dw = (DW - 2 * 16) / 3
	local dh = (CARD_H - 16) / 2
	for i = 1, ItemShop.DAILY do
		local col, row = (i - 1) % 3, (i - 1) // 3
		self.cards[ItemShop.FEATURED + i] = card(DX + col * (dw + 16), TOP + row * (dh + 16), dw, dh, false)
	end
	-- the note and the toast
	pop(label(canvas, "Note: these items change how your Countryball and units look. They give no advantage in battle.", 15, Enum.FontWeight.Bold, Color3.fromHex("8FB8FF"), {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 676),
		Size = UDim2.fromOffset(1000, 20),
		TextXAlignment = Enum.TextXAlignment.Center,
	}))
	self.toast = label(canvas, "", 18, Enum.FontWeight.Heavy, GREEN, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 646),
		Size = UDim2.fromOffset(1000, 24),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 47,
	})
	make("UIStroke", { Color = Color3.new(0, 0, 0), Transparency = 0.3, Thickness = 2 }, self.toast)
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
	-- (below Roblox's top bar: clicks there go to its buttons)
	local top = GuiService:GetGuiInset().Y
	self.fit.Scale = math.min((vp.X - 12) / ItemShopPanel.W, (vp.Y - top - 8) / ItemShopPanel.H)
	self.canvas.Position = UDim2.new(0.5, 0, 0.5, top / 2)
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
	return string.format("%d:%02d:%02d", left // 3600, (left % 3600) // 60, left % 60)
end

function ItemShopPanel.refresh(self)
	local coins = self:_coins()
	self.balance.Text = commas(coins)
	local now = os.time()
	local day = now // 86400
	local left = 86400 - now % 86400
	self.timer_a.Text = clock(left)
	self.timer_b.Text = clock(left)
	local n = self:_crates()
	self.open_crates_l.Text = if n > 0 then string.format("OPEN CRATES (%d)", n) else "OPEN CRATES"
	self.buy_crate_l.TextColor3 = if coins >= ItemShop.CRATE_PRICE then TEXT else Color3.fromHex("FFC4C4")
	if day ~= self.day then
		self.day = day
		local list = ItemShop.featured(day)
		for i, c in self.cards do
			local f = list[i]
			c.f = f
			c.hit.Visible = f ~= nil
			if f ~= nil then
				local r = RARITY[f.rarity or "common"] or RARITY.common
				c.grad.Color = ColorSequence.new(r[1], r[2])
				c.band_grad.Color = ColorSequence.new(r[3], r[3]:Lerp(Color3.new(0, 0, 0), 0.3))
				c.notch.BackgroundColor3 = r[3]
				c.edge.Color = r[4]:Lerp(INK, 0.6)
				c.glow.ImageColor3 = r[4]
				c.kind.TextColor3 = r[4]
				c.name.Text = string.upper(f.name)
				c.kind.Text = KIND_TEXT[f.kind] or "ITEM"
				c.tag.Visible = not ItemShop.on_sale(f.id, day - 1)
				c.art.ImageContent = GearArt.content(Cosmetics.item(f.id), BALLS[(i - 1) % #BALLS + 1]) or Content.none
			end
		end
	end
	for _, c in self.cards do
		local f = c.f
		if f ~= nil then
			local p = c.price
			if self:_owned(f.id) then
				p.coin.Visible = false
				if self:_worn(f.kind, f.id) then
					p.text.Text = "EQUIPPED"
					p.text.TextColor3 = GREEN
				else
					p.text.Text = if c.big then "OWNED · EQUIP" else "EQUIP"
					p.text.TextColor3 = AMBER
				end
			else
				p.coin.Visible = true
				p.text.Text = commas(f.price)
				p.text.TextColor3 = if coins >= f.price then TEXT else Color3.fromHex("FFC4C4")
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
	self:_toast(if wearing then (f.name .. " taken off.") else (f.name .. " equipped!"), GREEN)
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
				then "Crate bought! Press OPEN CRATES to open it."
				else ((if it then it.name else "Item") .. " bought! It's on."),
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
	-- the backdrop fades in, then everything on it pops in turn
	local root = self.root
	root.Visible = true
	root.BackgroundTransparency = 1
	self.backdrop.ImageTransparency = 1
	self.shade.BackgroundTransparency = 1
	Anim.tween(root, Anim.FADE_S, { BackgroundTransparency = 0 })
	Anim.tween(self.backdrop, Anim.FADE_S + 0.1, { ImageTransparency = 0 })
	Anim.tween(self.shade, Anim.FADE_S + 0.1, { BackgroundTransparency = 0 })
	local d = Anim.FADE_S + 0.05
	for i, o in self._pops do
		Anim.pop(o, d + i * 0.03)
	end
	self.ctx:sfx("open")
end

function ItemShopPanel.close(self)
	if not self.is_open then
		return
	end
	self.is_open = false
	for _, o in self._pops do
		Anim.tween(Anim.scale_of(o), 0.14, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	end
	Anim.tween(self.backdrop, 0.22, { ImageTransparency = 1 }, nil, nil, 0.08)
	Anim.tween(self.shade, 0.22, { BackgroundTransparency = 1 }, nil, nil, 0.08)
	local tw = Anim.tween(self.root, 0.22, { BackgroundTransparency = 1 }, nil, nil, 0.08)
	tw.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed and not self.is_open then
			self.root.Visible = false
		end
	end)
	self.ctx:sfx("close")
end

return ItemShopPanel
