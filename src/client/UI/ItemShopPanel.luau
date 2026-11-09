--!nonstrict
-- (Take Over the World!: the item shop, 2026-11-07 layout: a full screen over a pixel-art showroom.)
-- Coins (the match currency) buy today's gear (Data/ItemShop: the same list on every client and the
-- server, by UTC day): three tall FEATURED cards and six DAILY cards, each in its rarity's colours with
-- the item's picture (UI/GearArt), its name, its kind and its price. Below them (the sections scroll):
-- BUNDLES, several pieces of gear for Robux (Data/Bundles). The top bar's pills slide between three
-- pages: ITEM SHOP, MY ITEMS (owned gear, pressed to wear / take off) and BUY COINS (coin packs for Robux). Hats are worn by the player's
-- Countryball; boat / nuke / missile skins colour those units. BUY asks the server (Session.buy_item),
-- which checks the price and the balance, keeps the item and wears it when its slot is empty; Robux
-- products go through Roblox's prompt and the server's receipt (server/Purchases.grant). Opening: the
-- backdrop fades in, then everything pops in turn.
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local GuiService = game:GetService("GuiService")
local RS = game:GetService("ReplicatedStorage")
local Airfront = RS:WaitForChild("Airfront")
local TweenService = game:GetService("TweenService")
local ItemShop = require(Airfront.Data.ItemShop)
local Cosmetics = require(Airfront.Data.Cosmetics)
local UITheme = require("./UITheme")
local GearArt = require("./GearArt")
local Countryball = require("./Countryball")
local Anim = require("./Anim")
local Bundles = require(Airfront.Data.Bundles)
local Products = require(Airfront.Data.Products)
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ROBUX = "rbxasset://textures/ui/common/robux@3x.png"

local ItemShopPanel = {}
ItemShopPanel.__index = ItemShopPanel

--- the design canvas (scaled to the screen)
ItemShopPanel.W, ItemShopPanel.H = 1280, 720
ItemShopPanel.BACKDROP = "rbxassetid://80157115981891" -- tools/build_shop_bg_blue.py: a blue grid (the Fortnite-style shop)
ItemShopPanel.ICON = "rbxassetid://85914348579343" -- tools/build_gear.py: the user's basket, pixelated
--- tools/build_coin_packs.py: the coin packs' piles (smallest to biggest) and the cards' rays
ItemShopPanel.COIN_ART = {
	"rbxassetid://101681398880263",
	"rbxassetid://90572924963464",
	"rbxassetid://139567959618041",
	"rbxassetid://88545773509125",
}
ItemShopPanel.RAYS = "rbxassetid://95061794432591"

local FONT = "rbxassetid://12187365977"
local AMBER = Color3.fromHex("FFC23D")
local INK = Color3.fromHex("1B1000")
local TEXT = Color3.new(1, 1, 1)
local TEXT2 = Color3.fromHex("C9D2EA")
local GREEN = Color3.fromHex("5BE38E")
local RED = Color3.fromHex("FF5C61")
--- rarity -> { top, foot, (unused), glow } (2026-11-08: the reference's card colours)
local RARITY = {
	common = { Color3.fromHex("A4ACBC"), Color3.fromHex("5C6578"), Color3.fromHex("37405A"), Color3.fromHex("E8ECF5") },
	uncommon = { Color3.fromHex("6FD35A"), Color3.fromHex("2E7D2A"), Color3.fromHex("235E20"), Color3.fromHex("D2F7C4") },
	rare = { Color3.fromHex("4AA8FF"), Color3.fromHex("1E5BD8"), Color3.fromHex("174A9E"), Color3.fromHex("BFE3FF") },
	epic = { Color3.fromHex("B66BFF"), Color3.fromHex("5B22C2"), Color3.fromHex("52209A"), Color3.fromHex("ECD4FF") },
	legendary = { Color3.fromHex("FFB347"), Color3.fromHex("C8531A"), Color3.fromHex("A84A12"), Color3.fromHex("FFE7B3") },
}
local KIND_TEXT = {
	hat = "Countryball Hat",
	beard = "Countryball Beard",
	glasses = "Countryball Glasses",
	boat = "Boat Skin",
	nuke = "Nuke Skin",
	missile = "Missile Skin",
}
--- the balls hats are shown on (a few flags, by card)
local BALLS = { "gb", "fr", "de", "jp", "br", "us", "it", "ca", "mx" }
--- the Countryball on a bundle's card
local BUNDLE_BALL = { royal = "gb", admiral = "us", winter = "fi", frontline = "fr" }
--- the coin packs' cards, smallest to biggest (top, foot): green, blue, purple, orange
local PACK_COLORS = {
	{ Color3.fromHex("3FCB3A"), Color3.fromHex("128A12") },
	{ Color3.fromHex("2FA6FF"), Color3.fromHex("0A62D8") },
	{ Color3.fromHex("B254E0"), Color3.fromHex("6A1FA8") },
	{ Color3.fromHex("FF9A2E"), Color3.fromHex("D35A0E") },
}

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
		Image = UITheme.icon("coin") or "",
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

function ItemShopPanel.new(ctx: any, gui: Instance, open_locker: () -> ())
	local self = setmetatable({}, ItemShopPanel)
	self.ctx = ctx
	self.is_open = false
	self.cards = {}
	self.day = -1
	self._pops = {}
	-- (2026-11-08: after the user's Fortnite item shop reference) the screen: a blue backdrop with a
	-- glowing grid, nav pills along the top, section dots down the left, and rows of tall cards
	local root = make("TextButton", {
		Name = "ItemShop",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromHex("0C1660"),
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 40,
	}, gui)
	self.root = root
	self.backdrop = make("ImageLabel", {
		BackgroundTransparency = 1,
		Image = ItemShopPanel.BACKDROP,
		ScaleType = Enum.ScaleType.Crop,
		-- (centred, so the opening zoom and the slow drift scale about the middle)
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 40,
	}, root)
	self.shade = make("Frame", { -- (a little darker under the nav, for the words)
		BackgroundColor3 = Color3.fromHex("060B33"),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 41,
	}, root)
	make("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(0.14, 0.85),
			NumberSequenceKeypoint.new(1, 0.95),
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
	-- the nav: the basket, ITEM SHOP (this page, a lit pill), MY ITEMS, BUY COINS; the wallet, close
	local nav = pop(make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(28, 14), Size = UDim2.fromOffset(820, 48), ZIndex = 43 }, canvas))
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, nav)
	make("ImageLabel", {
		BackgroundTransparency = 1,
		Image = ItemShopPanel.ICON,
		Size = UDim2.fromOffset(46, 46),
		LayoutOrder = 0,
		ZIndex = 44,
	}, nav)
	local function nav_pill(text: string, order: number, lit: boolean): TextButton
		local b = make("TextButton", {
			Text = text,
			TextSize = 20,
			FontFace = Font.new(FONT, Enum.FontWeight.Heavy),
			TextColor3 = if lit then Color3.fromHex("1A1F4D") else TEXT,
			BackgroundColor3 = Color3.fromHex("C9C8FF"),
			BackgroundTransparency = if lit then 0 else 1,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 40),
			LayoutOrder = order,
			ZIndex = 44,
		}, nav)
		make("UICorner", { CornerRadius = UDim.new(0, 10) }, b)
		make("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }, b)
		b.MouseEnter:Connect(function()
			if self.pills[self.page] ~= b then
				b.BackgroundTransparency = 0.82
			end
		end)
		b.MouseLeave:Connect(function()
			if self.pills[self.page] ~= b then
				b.BackgroundTransparency = 1
			end
		end)
		Anim.button(b, nil, 1.04)
		b.Activated:Connect(function()
			if self.page ~= order then
				self.ctx:sfx("click")
				self:_page(order)
			end
		end)
		self.pills[order] = b
		return b
	end
	-- (2026-11-08: the three are pages side by side; a pill slides the row over to its page, no pop-up)
	self.pills = {}
	self.page = 1
	nav_pill("ITEM SHOP", 1, true)
	nav_pill("MY ITEMS", 2, false)
	nav_pill("BUY COINS", 3, false)
	local close = pop(make("TextButton", {
		Text = "X",
		TextSize = 22,
		FontFace = Font.new(FONT, Enum.FontWeight.Heavy),
		TextColor3 = TEXT,
		BackgroundColor3 = Color3.fromHex("C83A3A"),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -28, 0, 14),
		Size = UDim2.fromOffset(44, 44),
		ZIndex = 44,
	}, canvas))
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, close)
	make("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2, Transparency = 0.6, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, close)
	close.Activated:Connect(function()
		self:close()
	end)
	Anim.button(close)
	local wallet = pop(make("Frame", {
		BackgroundColor3 = Color3.fromHex("0A1450"),
		BackgroundTransparency = 0.25,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -84, 0, 16),
		Size = UDim2.fromOffset(180, 40),
		ZIndex = 43,
	}, canvas))
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, wallet)
	coin_icon(wallet, 26, { Position = UDim2.fromOffset(10, 7) })
	self.balance = label(wallet, "0", 22, Enum.FontWeight.Heavy, TEXT, {
		Position = UDim2.fromOffset(42, 7),
		Size = UDim2.new(1, -56, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 45,
	})
	self.wallet = wallet
	-- the pages: a row of three (ITEM SHOP | MY ITEMS | BUY COINS) in a window the canvas wide; the
	-- row slides left and right (_page)
	local pages = make("Frame", {
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(0, 72),
		Size = UDim2.fromOffset(ItemShopPanel.W, 600),
		ZIndex = 42,
	}, canvas)
	self.strip = make("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(ItemShopPanel.W * 3, 600),
		ZIndex = 42,
	}, pages)
	-- the sections scroll: FEATURED, DAILY, then the BUNDLES
	local CW, CH, GAP = 206, 286, 16 -- a card
	local X0 = 108
	self._grid = { CW = CW, CH = CH, GAP = GAP, X0 = X0 }
	local scroll = make("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(0, ItemShopPanel.W, 1, 0),
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Color3.fromHex("C9C8FF"),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 42,
	}, self.strip)
	self.scroll = scroll
	local function section(y: number, title: string): (TextLabel, number)
		local t = pop(label(scroll, title, 44, Enum.FontWeight.Heavy, TEXT, {
			FontFace = Font.new(FONT, Enum.FontWeight.Heavy, Enum.FontStyle.Italic),
			Position = UDim2.fromOffset(X0, y),
			Size = UDim2.fromOffset(700, 50),
			ZIndex = 44,
		}))
		make("UIStroke", { Color = Color3.fromHex("0A1450"), Thickness = 2, Transparency = 0.4 }, t)
		local timer = label(scroll, "", 16, Enum.FontWeight.Bold, Color3.fromHex("C9C8FF"), {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromOffset(X0 + 5 * CW + 4 * GAP, y + 18),
			Size = UDim2.fromOffset(300, 20),
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 44,
		})
		return timer, y + 58
	end
	-- a card: the rarity's colours, the picture over most of it, the words at its foot
	-- (`parent`: MY ITEMS' grid; else the shop's scroll, and the card joins the opening wave)
	local function card(x: number, y: number, w: number, h: number, big: boolean, parent: Instance?): any
		local hit = make("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x + w / 2, y + h / 2),
			Size = UDim2.fromOffset(w, h),
			ZIndex = 42,
			Selectable = true,
		}, parent or scroll)
		if parent == nil then
			pop(hit)
		end
		-- (the white frame of a card under the pointer, as in the reference)
		local edge = make("UIStroke", { Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = TEXT, Transparency = 1 }, hit)
		make("UICorner", { CornerRadius = UDim.new(0, 12) }, hit)
		local body = make("CanvasGroup", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			Size = UDim2.fromScale(1, 1),
			ZIndex = 42,
		}, hit)
		make("UICorner", { CornerRadius = UDim.new(0, 12) }, body)
		local bg = make("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 42,
		}, body)
		local grad = make("UIGradient", { Rotation = 90 }, bg)
		local glow = make("ImageLabel", {
			BackgroundTransparency = 1,
			Image = UITheme.crate_art().glow or "",
			ImageTransparency = 0.55,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.36),
			Size = UDim2.fromScale(1.3, 0.8),
			ZIndex = 43,
		}, body)
		local art = make("ImageLabel", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.37),
			Size = UDim2.fromScale(0.86, 0.86),
			ResampleMode = Enum.ResamplerMode.Pixelated,
			ZIndex = 44,
		}, body)
		make("UIAspectRatioConstraint", { AspectRatio = 1 }, art)
		-- (a darker foot for the words)
		local foot = make("Frame", {
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 96),
			ZIndex = 44,
		}, body)
		make("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.45, 0.6),
				NumberSequenceKeypoint.new(1, 0.45),
			}),
			Rotation = 90,
		}, foot)
		local name = label(body, "", 21, Enum.FontWeight.Heavy, TEXT, {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 12, 1, -46),
			Size = UDim2.new(1, -24, 0, 46),
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.None,
			TextYAlignment = Enum.TextYAlignment.Bottom,
			TextScaled = true, -- (a long name shrinks to fit two lines)
			ZIndex = 46,
		})
		make("UITextSizeConstraint", { MaxTextSize = 21, MinTextSize = 10 }, name)
		local kind = label(body, "", 13, Enum.FontWeight.Bold, Color3.fromHex("E3E8FF"), {
			Position = UDim2.new(0, 12, 1, -44),
			Size = UDim2.new(1, -24, 0, 16),
			ZIndex = 46,
		})
		-- the price at the foot, left: the coin and the number
		local prow = make("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 12, 1, -26),
			Size = UDim2.new(1, -40, 0, 20),
			ZIndex = 45,
		}, body)
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 5),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, prow)
		local coin = coin_icon(prow, 18, { LayoutOrder = 1 })
		local ptext = label(prow, "", 16, Enum.FontWeight.Heavy, TEXT, {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 20),
			LayoutOrder = 2,
			ZIndex = 46,
		})
		label(body, "+", 20, Enum.FontWeight.Heavy, TEXT, {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -10, 1, -6),
			Size = UDim2.fromOffset(16, 22),
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 46,
		})
		local tag = make("TextLabel", {
			Text = "NEW!",
			TextSize = 13,
			FontFace = Font.new(FONT, Enum.FontWeight.Heavy),
			TextColor3 = INK,
			BackgroundColor3 = Color3.fromHex("FFE14D"),
			Position = UDim2.fromOffset(8, 8),
			Size = UDim2.fromOffset(48, 22),
			Visible = false,
			ZIndex = 48,
		}, hit)
		make("UICorner", { CornerRadius = UDim.new(0, 6) }, tag)
		local c = {
			hit = hit,
			edge = edge,
			grad = grad,
			glow = glow,
			art = art,
			name = name,
			kind = kind,
			price = { coin = coin, text = ptext },
			tag = tag,
			big = big,
		}
		hit.MouseEnter:Connect(function()
			edge.Transparency = 0
		end)
		hit.MouseLeave:Connect(function()
			edge.Transparency = 1
		end)
		Anim.button(hit, nil, 1.04)
		hit.Activated:Connect(function()
			self:_activate(c)
		end)
		return c
	end
	self._card = card
	local PER_ROW = 5
	local function place(i: number, y: number): (number, number)
		local col, row = (i - 1) % PER_ROW, (i - 1) // PER_ROW
		return X0 + col * (CW + GAP), y + row * (CH + GAP)
	end
	self.sections = {}
	local y = 4
	local ta
	ta, y = section(y, "FEATURED")
	table.insert(self.sections, y - 58)
	for i = 1, ItemShop.FEATURED do
		local x, cy = place(i, y)
		self.cards[i] = card(x, cy, CW, CH, true)
	end
	y += math.ceil(ItemShop.FEATURED / PER_ROW) * (CH + GAP) + 18
	local tb
	tb, y = section(y, "DAILY")
	table.insert(self.sections, y - 58)
	for i = 1, ItemShop.DAILY do
		local x, cy = place(i, y)
		self.cards[ItemShop.FEATURED + i] = card(x, cy, CW, CH, false)
	end
	y += math.ceil(ItemShop.DAILY / PER_ROW) * (CH + GAP) + 18
	self.timer_a, self.timer_b = ta, tb
	-- the bundles (Robux), portrait cards after the user's reference (a Fortnite pack): the bundle's
	-- Countryball big over rays in its rarity's colours, its name, and its items in a bracketed row
	local tc
	tc, y = section(y, "BUNDLES")
	table.insert(self.sections, y - 58)
	tc.Text = "Robux only"
	self.bundle_cards = {}
	local BW = (5 * CW + 4 * GAP - 3 * GAP) / 4
	local BH = math.floor(BW * 4 / 3)
	for i, b in Bundles.LIST do
		local flag = BUNDLE_BALL[b.id] or BALLS[(i - 1) % #BALLS + 1]
		local r = RARITY[b.rarity] or RARITY.common
		local hit = pop(make("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(X0 + (i - 1) % 4 * (BW + GAP) + BW / 2, y + BH / 2),
			Size = UDim2.fromOffset(BW, BH),
			ZIndex = 42,
			Selectable = true,
		}, scroll))
		local edge = make("UIStroke", { Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = TEXT, Transparency = 1 }, hit)
		make("UICorner", { CornerRadius = UDim.new(0, 12) }, hit)
		local body = make("CanvasGroup", { BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(1, 1), ZIndex = 42 }, hit)
		make("UICorner", { CornerRadius = UDim.new(0, 12) }, body)
		-- (the colours on a frame of their own: a gradient on the CanvasGroup would tint everything in it)
		local bg = make("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 42 }, body)
		make("UIGradient", { Color = ColorSequence.new(r[1], r[2]), Rotation = 90 }, bg)
		make("ImageLabel", { -- (the rays)
			BackgroundTransparency = 1,
			Image = ItemShopPanel.RAYS,
			ImageTransparency = 0.25,
			ScaleType = Enum.ScaleType.Crop,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 43,
		}, body)
		-- the hero: the bundle's Countryball wearing its gear, big
		local worn = {}
		for _, id in b.items do
			local it = Cosmetics.item(id)
			if it ~= nil and (it.kind == "hat" or it.kind == "beard" or it.kind == "glasses") then
				worn[it.kind] = id
			end
		end
		local heroimg = make("ImageLabel", {
			BackgroundTransparency = 1,
			ResampleMode = Enum.ResamplerMode.Pixelated,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, BH * 0.32),
			Size = UDim2.fromOffset(BW * 0.74, BW * 0.74),
			ZIndex = 44,
		}, body)
		heroimg.ImageContent = Countryball.ball_content(flag, nil, worn) or Content.none
		-- (a white fade under the hero, as the reference's ground)
		local fade = make("Frame", {
			BackgroundColor3 = Color3.fromHex("0A1450"),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, BH * 0.48),
			ZIndex = 44,
		}, body)
		make("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.35, 0.45),
				NumberSequenceKeypoint.new(1, 0.15),
			}),
			Rotation = 90,
		}, fade)
		local title = label(body, string.upper(b.name), 22, Enum.FontWeight.Heavy, TEXT, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, BH * 0.6),
			Size = UDim2.new(1, -16, 0, 26),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextScaled = true,
			ZIndex = 46,
		})
		make("UITextSizeConstraint", { MaxTextSize = 22, MinTextSize = 12 }, title)
		make("UIStroke", { Color = INK, Thickness = 2, Transparency = 0.2 }, title)
		-- the items, a row of tiles between corner brackets
		local n = #b.items
		local ts = math.min(54, math.floor((BW - 36 - (n - 1) * 5) / n))
		local rw = n * ts + (n - 1) * 5
		local row = make("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, BH * 0.6 + 34),
			Size = UDim2.fromOffset(rw + 14, ts + 14),
			ZIndex = 45,
		}, body)
		for _, cn in { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } } do
			local ax, ay = cn[1], cn[2]
			make("Frame", { BackgroundColor3 = TEXT, BorderSizePixel = 0, AnchorPoint = Vector2.new(ax, ay), Position = UDim2.fromScale(ax, ay), Size = UDim2.fromOffset(12, 3), ZIndex = 46 }, row)
			make("Frame", { BackgroundColor3 = TEXT, BorderSizePixel = 0, AnchorPoint = Vector2.new(ax, ay), Position = UDim2.fromScale(ax, ay), Size = UDim2.fromOffset(3, 12), ZIndex = 46 }, row)
		end
		for k, id in b.items do
			local it = Cosmetics.item(id)
			local tile = make("Frame", {
				BackgroundColor3 = r[1],
				Position = UDim2.fromOffset(7 + (k - 1) * (ts + 5), 7),
				Size = UDim2.fromOffset(ts, ts),
				ZIndex = 46,
			}, row)
			make("UICorner", { CornerRadius = UDim.new(0, 4) }, tile)
			make("UIGradient", { Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromHex("B8C3D6")), Rotation = 90 }, tile)
			local pic = make("ImageLabel", {
				BackgroundTransparency = 1,
				ResampleMode = Enum.ResamplerMode.Pixelated,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 47,
			}, tile)
			pic.ImageContent = GearArt.content(it, flag) or Content.none
		end
		-- the price at the foot, centred
		local prow = make("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -10),
			Size = UDim2.new(1, -20, 0, 22),
			ZIndex = 45,
		}, body)
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, prow)
		local coin = coin_icon(prow, 20, { LayoutOrder = 1, Image = ROBUX, ImageColor3 = TEXT })
		local ptext = label(prow, "", 18, Enum.FontWeight.Heavy, TEXT, {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 22),
			LayoutOrder = 2,
			ZIndex = 46,
		})
		local tag = make("TextLabel", {
			Text = "OWNED",
			TextSize = 13,
			FontFace = Font.new(FONT, Enum.FontWeight.Heavy),
			TextColor3 = INK,
			BackgroundColor3 = GREEN,
			Position = UDim2.fromOffset(8, 8),
			Size = UDim2.fromOffset(62, 22),
			Visible = false,
			ZIndex = 48,
		}, hit)
		make("UICorner", { CornerRadius = UDim.new(0, 6) }, tag)
		local c = { hit = hit, bundle = b, price = { coin = coin, text = ptext }, owned_tag = tag, body = body }
		hit.MouseEnter:Connect(function()
			edge.Transparency = 0
		end)
		hit.MouseLeave:Connect(function()
			edge.Transparency = 1
		end)
		Anim.button(hit, nil, 1.04)
		hit.Activated:Connect(function()
			self:_activate(c)
		end)
		self.bundle_cards[i] = c
	end
	y += BH + 30
	scroll.CanvasSize = UDim2.fromOffset(0, y)
	-- the section dots down the left: one a section, the one in view lit
	local dots = pop(make("Frame", {
		BackgroundColor3 = Color3.fromHex("0A1450"),
		BackgroundTransparency = 0.35,
		Position = UDim2.fromOffset(40, 120),
		Size = UDim2.fromOffset(28, 30 + #self.sections * 30),
		ZIndex = 43,
	}, canvas))
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, dots)
	self.dots_frame = dots
	self.dots = {}
	for i = 1, #self.sections do
		local d = make("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = TEXT,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(14, 15 + i * 30),
			Size = UDim2.fromOffset(8, 8),
			ZIndex = 44,
		}, dots)
		make("UICorner", { CornerRadius = UDim.new(1, 0) }, d)
		d.Activated:Connect(function()
			TweenService:Create(scroll, TweenInfo.new(0.35, Enum.EasingStyle.Quint), { CanvasPosition = Vector2.new(0, self.sections[i]) }):Play()
		end)
		self.dots[i] = d
	end
	scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		self:_dots()
	end)
	self:_dots()
	self:_build_pages()
	-- the note and the toast
	pop(label(canvas, "Note: these items change how your Countryball and units look. They give no advantage in battle.", 13, Enum.FontWeight.Bold, Color3.fromHex("C9C8FF"), {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 692),
		Size = UDim2.fromOffset(1000, 20),
		TextXAlignment = Enum.TextXAlignment.Center,
	}))
	self.toast = label(canvas, "", 18, Enum.FontWeight.Heavy, GREEN, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 664),
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

--- MY ITEMS and BUY COINS: the pages right of the shop, in its look (a section title, rows of cards).
function ItemShopPanel._build_pages(self)
	local G = self._grid
	local W = ItemShopPanel.W
	local ROW = 5 * G.CW + 4 * G.GAP -- (the shop's rows' width)
	local function page(i: number, title: string, note: string): Frame
		local pg = make("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset((i - 1) * W, 0),
			Size = UDim2.fromOffset(W, 600),
			ZIndex = 42,
		}, self.strip)
		local t = label(pg, title, 44, Enum.FontWeight.Heavy, TEXT, {
			FontFace = Font.new(FONT, Enum.FontWeight.Heavy, Enum.FontStyle.Italic),
			Position = UDim2.fromOffset(G.X0, 4),
			Size = UDim2.fromOffset(700, 50),
		})
		make("UIStroke", { Color = Color3.fromHex("0A1450"), Thickness = 2, Transparency = 0.4 }, t)
		label(pg, note, 16, Enum.FontWeight.Bold, Color3.fromHex("C9C8FF"), {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromOffset(G.X0 + ROW, 22),
			Size = UDim2.fromOffset(500, 20),
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		return pg
	end
	-- MY ITEMS: the owned gear as shop cards (pressing one wears it / takes it off)
	local items = page(2, "MY ITEMS", "Press an item to wear it or take it off")
	local grid = make("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 62),
		Size = UDim2.new(1, 0, 1, -62),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Color3.fromHex("C9C8FF"),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 42,
	}, items)
	make("UIPadding", { PaddingLeft = UDim.new(0, G.X0), PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 20) }, grid)
	make("UIGridLayout", {
		CellSize = UDim2.fromOffset(G.CW, G.CH),
		CellPadding = UDim2.fromOffset(G.GAP, G.GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, grid)
	self.items_grid = grid
	self.item_cards = {}
	self.items_empty = label(items, "You don't own any gear yet: buy some in the ITEM SHOP!", 20, Enum.FontWeight.Bold, TEXT2, {
		Position = UDim2.fromOffset(G.X0, 80),
		Size = UDim2.fromOffset(ROW, 26),
		Visible = false,
	})
	-- BUY COINS: the coin packs after the user's reference (Fortnite's V-Bucks packs): a card a pack in
	-- its own colour with rays, a pixel pile of star coins growing with the pack (tools/build_coin_packs.py),
	-- the amount, and a yellow price button; "N% EXTRA" against the smallest pack
	local coins = page(3, "BUY COINS", "Coins buy the shop's gear")
	self.coin_cards = {}
	local n = #Bundles.COINS
	local PW = (ROW - (n - 1) * G.GAP) / math.max(n, 1)
	local base = Bundles.COINS[1]
	local per = if base ~= nil then base.coins / base.robux else 1
	for i, pk in Bundles.COINS do
		local col = PACK_COLORS[(i - 1) % #PACK_COLORS + 1]
		local b = make("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Color3.new(1, 1, 1),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(G.X0 + (i - 1) * (PW + G.GAP) + PW / 2, 72 + 210),
			Size = UDim2.fromOffset(PW, 420),
			ZIndex = 42,
		}, coins)
		make("UICorner", { CornerRadius = UDim.new(0, 14) }, b)
		local edge = make("UIStroke", { Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = TEXT, Transparency = 1 }, b)
		make("UIGradient", { Color = ColorSequence.new(col[1], col[2]), Rotation = 90 }, b)
		local rays = make("ImageLabel", {
			BackgroundTransparency = 1,
			Image = ItemShopPanel.RAYS,
			ImageTransparency = 0.35,
			ScaleType = Enum.ScaleType.Crop,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 43,
		}, b)
		make("UICorner", { CornerRadius = UDim.new(0, 14) }, rays)
		make("ImageLabel", {
			BackgroundTransparency = 1,
			Image = ItemShopPanel.COIN_ART[i] or ItemShopPanel.COIN_ART[#ItemShopPanel.COIN_ART],
			ResampleMode = Enum.ResamplerMode.Pixelated,
			ScaleType = Enum.ScaleType.Fit,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.42),
			Size = UDim2.new(1, -6, 0, (PW - 6) * 0.75),
			ZIndex = 44,
		}, b)
		local amount = label(b, commas(pk.coins), 34, Enum.FontWeight.Heavy, TEXT, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -102),
			Size = UDim2.new(1, -20, 0, 38),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 46,
		})
		make("UIStroke", { Color = INK, Thickness = 2, Transparency = 0.3 }, amount)
		local unit = label(b, "COINS", 22, Enum.FontWeight.Heavy, TEXT, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -76),
			Size = UDim2.new(1, -20, 0, 26),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 46,
		})
		make("UIStroke", { Color = INK, Thickness = 2, Transparency = 0.3 }, unit)
		local price = make("Frame", {
			BackgroundColor3 = Color3.fromHex("F5F51E"),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -14),
			Size = UDim2.new(1, -24, 0, 48),
			ZIndex = 45,
		}, b)
		make("UICorner", { CornerRadius = UDim.new(0, 8) }, price)
		local row = price_row(price, 22, 10)
		row.coin.Image = ROBUX
		row.coin.ImageColor3 = INK
		row.text.TextColor3 = INK
		row.text.Text = commas(pk.robux)
		local s = row.text:FindFirstChildOfClass("UIStroke")
		if s ~= nil then
			s.Enabled = false
		end
		local extra = math.floor((pk.coins / pk.robux / per - 1) * 100 + 0.5)
		local pill = if extra >= 1 then string.format("%d%% EXTRA", extra) else pk.tag
		if pill ~= nil then
			local tag = make("TextLabel", {
				Text = pill,
				TextSize = 15,
				FontFace = Font.new(FONT, Enum.FontWeight.Heavy, Enum.FontStyle.Italic),
				TextColor3 = INK,
				BackgroundColor3 = TEXT,
				AutomaticSize = Enum.AutomaticSize.X,
				Position = UDim2.fromOffset(12, 12),
				Size = UDim2.fromOffset(40, 26),
				ZIndex = 48,
			}, b)
			make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, tag)
			make("UICorner", { CornerRadius = UDim.new(1, 0) }, tag)
		end
		if pk.tag ~= nil and pill ~= pk.tag then
			local note = label(b, pk.tag, 13, Enum.FontWeight.Heavy, TEXT, {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -14, 0, 17),
				Size = UDim2.fromOffset(110, 16),
				TextXAlignment = Enum.TextXAlignment.Right,
				ZIndex = 48,
			})
			make("UIStroke", { Color = INK, Thickness = 1.5, Transparency = 0.3 }, note)
		end
		b.MouseEnter:Connect(function()
			edge.Transparency = 0
		end)
		b.MouseLeave:Connect(function()
			edge.Transparency = 1
		end)
		Anim.button(b, nil, 1.04)
		b.Activated:Connect(function()
			self:_prompt("coins_" .. pk.id)
		end)
		self.coin_cards[i] = b
	end
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(_uid, _product, bought)
		if self._prompted ~= nil and self.is_open then
			self:_toast(if bought then "Thank you! It's being added to your account." else "Purchase cancelled.", if bought then GREEN else TEXT2)
			if bought then
				self.ctx:sfx("buy")
			end
		end
		self._prompted = nil
	end)
end

--- Slides the row of pages to page `i` (1 ITEM SHOP, 2 MY ITEMS, 3 BUY COINS) and lights its pill.
function ItemShopPanel._page(self, i: number, instant: boolean?)
	self.page = i
	local to = UDim2.fromOffset(-(i - 1) * ItemShopPanel.W, 0)
	if self._slide ~= nil then
		self._slide:Cancel()
		self._slide = nil
	end
	if instant then
		self.strip.Position = to
	else
		self._slide = Anim.tween(self.strip, 0.45, { Position = to }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	end
	for k, b in self.pills do
		local on = k == i
		local goal = { BackgroundTransparency = if on then 0 else 1, TextColor3 = if on then Color3.fromHex("1A1F4D") else TEXT }
		if instant then
			for prop, v in goal do
				b[prop] = v
			end
		else
			Anim.tween(b, 0.2, goal, Enum.EasingStyle.Sine)
		end
	end
	self.dots_frame.Visible = i == 1 -- (the section dots are the shop page's)
	if i == 2 then
		self:_refresh_items()
	end
	if not instant then
		-- the page's cards settle in as it slides up
		local list = if i == 2 then self.item_cards elseif i == 3 then self.coin_cards else {}
		for k, c in list do
			local o = if type(c) == "table" then c.hit else c
			if o.Visible then
				Anim.pop(o, 0.08 + (k - 1) % 5 * 0.04, 0.9)
			end
		end
	end
end

--- MY ITEMS' cards: one per owned piece of gear, with EQUIP / EQUIPPED at its foot.
function ItemShopPanel._refresh_items(self)
	local owned = {}
	for _, it in Cosmetics.gear() do
		if self:_owned(it.id) then
			table.insert(owned, it)
		end
	end
	self.items_empty.Visible = #owned == 0
	local G = self._grid
	for i, it in owned do
		local c = self.item_cards[i]
		if c == nil then
			c = self._card(0, 0, G.CW, G.CH, false, self.items_grid)
			c.hit.LayoutOrder = i
			self.item_cards[i] = c
		end
		c.hit.Visible = true
		if c.f == nil or c.f.id ~= it.id then
			c.f = { id = it.id, name = it.name or it.id, kind = it.kind, rarity = it.rarity, price = 0 }
			local r = RARITY[it.rarity or "common"] or RARITY.common
			c.grad.Color = ColorSequence.new(r[1], r[2])
			c.glow.ImageColor3 = r[4]
			c.name.Text = c.f.name
			c.kind.Text = KIND_TEXT[it.kind] or "ITEM"
			c.art.ImageContent = GearArt.content(it, BALLS[(i - 1) % #BALLS + 1]) or Content.none
		end
		self:_price(c, 0)
	end
	for i = #owned + 1, #self.item_cards do
		self.item_cards[i].hit.Visible = false
		self.item_cards[i].f = nil
	end
end

--- Lights the dot of the section in view.
function ItemShopPanel._dots(self)
	local y = self.scroll.CanvasPosition.Y + 40
	local at = 1
	for i, top in self.sections do
		if y >= top then
			at = i
		end
	end
	for i, d in self.dots do
		local on = i == at
		d.Size = UDim2.fromOffset(if on then 12 else 8, if on then 12 else 8)
		d.BackgroundTransparency = if on then 0 else 0.55
	end
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

--- Does the player own every item of bundle `b`?
function ItemShopPanel._bundle_owned(self, b: any): boolean
	for _, id in b.items do
		if not self:_owned(id) then
			return false
		end
	end
	return true
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
	self.timer_a.Text = "Refreshes in " .. clock(left)
	self.timer_b.Text = "Refreshes in " .. clock(left)
	-- the bundles: their Robux price, or OWNED once every item is
	for _, c in self.bundle_cards or {} do
		local b = c.bundle
		local all = self:_bundle_owned(b)
		c.owned_tag.Visible = all
		c.body.GroupColor3 = if all then Color3.fromHex("9AA0B0") else Color3.new(1, 1, 1)
		local prod = Products["bundle_" .. b.id]
		c.price.coin.Visible = not all
		if all then
			c.price.text.Text = "OWNED"
			c.price.text.TextColor3 = GREEN
		elseif prod == nil or prod.id == 0 then
			c.price.text.Text = "SOON"
			c.price.text.TextColor3 = TEXT2
		else
			c.price.text.Text = commas(prod.robux)
			c.price.text.TextColor3 = TEXT
		end
	end
	if self.page == 2 then
		self:_refresh_items()
	end
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
				c.glow.ImageColor3 = r[4]
				c.name.Text = f.name
				c.kind.Text = KIND_TEXT[f.kind] or "ITEM"
				c.tag.Visible = not ItemShop.on_sale(f.id, day - 1)
				c.art.ImageContent = GearArt.content(Cosmetics.item(f.id), BALLS[(i - 1) % #BALLS + 1]) or Content.none
			end
		end
	end
	for _, c in self.cards do
		self:_price(c, coins)
	end
end

--- A card's foot: its price, or EQUIP / EQUIPPED once owned.
function ItemShopPanel._price(self, c: any, coins: number)
	local f = c.f
	if f ~= nil then
		local p = c.price
		if self:_owned(f.id) then
			p.coin.Visible = false
			if self:_worn(f.kind, f.id) then
				p.text.Text = "EQUIPPED"
				p.text.TextColor3 = GREEN
			else
				p.text.Text = "EQUIP"
				p.text.TextColor3 = AMBER
			end
		else
			p.coin.Visible = true
			p.text.Text = commas(f.price)
			p.text.TextColor3 = if coins >= f.price then TEXT else Color3.fromHex("FFC4C4")
		end
	end
end

--- A Robux product (Data/Products key): Roblox's purchase prompt; the server's receipt grants it.
function ItemShopPanel._prompt(self, key: string)
	local prod = Products[key]
	if prod == nil or prod.id == 0 then
		self:_toast("Coming soon!", TEXT2)
		self.ctx:sfx("deny", -4.0)
		return
	end
	self.ctx:sfx("click")
	self._prompted = key
	pcall(function()
		MarketplaceService:PromptProductPurchase(Players.LocalPlayer, prod.id)
	end)
end

--- A card pressed: buy it, or (owned) wear it / take it off.
function ItemShopPanel._activate(self, c: any)
	if c.bundle ~= nil then
		-- (a developer product can be bought again and again: once every item is the player's, the
		-- bundle can't be; the server also pays an owned item back in coins)
		if self:_bundle_owned(c.bundle) then
			self:_toast("You already own the " .. c.bundle.name .. "!", TEXT2)
			self.ctx:sfx("deny", -4.0)
			return
		end
		self:_prompt("bundle_" .. c.bundle.id)
		return
	end
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
			(if it then it.name else "Item") .. " bought! It's on.",
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
	self:_page(1, true)
	self:refresh()
	-- (2026-11-08 rework) the screen fades up while the stormy city settles from a slow zoom, then
	-- drifts on its own; the title bar drops in from above and every card and button glides up
	-- into place in a wave from the top left to the bottom right, its picture fading in with it
	local root = self.root
	root.Visible = true
	root.BackgroundTransparency = 1
	self.backdrop.ImageTransparency = 1
	self.shade.BackgroundTransparency = 1
	Anim.tween(root, Anim.FADE_S, { BackgroundTransparency = 0 }, Enum.EasingStyle.Sine)
	Anim.tween(self.shade, 0.5, { BackgroundTransparency = 0 }, Enum.EasingStyle.Sine)
	Anim.tween(self.backdrop, 0.6, { ImageTransparency = 0 }, Enum.EasingStyle.Sine)
	if self._drift ~= nil then
		self._drift:Cancel()
	end
	self.backdrop.Size = UDim2.fromScale(1.14, 1.14)
	self.backdrop.Position = UDim2.fromScale(0.5, 0.5)
	local settle = Anim.tween(self.backdrop, 1.4, { Size = UDim2.fromScale(1.04, 1.04) })
	settle.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed and self.is_open then
			-- a slow breathing drift while the shop stays open
			self._drift = TweenService:Create(
				self.backdrop,
				TweenInfo.new(9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Size = UDim2.fromScale(1.09, 1.09), Position = UDim2.new(0.5, -14, 0.5, -6) }
			)
			self._drift:Play()
		end
	end)
	local base = 0.12
	for i, o in self._pops do
		local home = Anim.home(o)
		-- the wave: later towards the right and further down (the scrolled sections sit 88 px lower)
		local y = home.Y.Offset + (if o.Parent == self.scroll then 88 else 0)
		local x = home.X.Offset + home.X.Scale * ItemShopPanel.W
		local d = base + math.clamp(x / ItemShopPanel.W, 0, 1) * 0.2 + math.clamp(y / ItemShopPanel.H, 0, 1) * 0.28
		if i == 1 then
			-- the title bar drops down from above
			o.Position = home + UDim2.fromOffset(0, -40)
			Anim.tween(o, 0.55, { Position = home }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, 0.05)
		else
			Anim.rise(o, d, 34)
			Anim.pop(o, d, 0.84)
		end
		local body = o:FindFirstChildOfClass("CanvasGroup")
		if body ~= nil then
			body.GroupTransparency = 1
			Anim.tween(body, 0.4, { GroupTransparency = 0 }, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, d)
		end
	end
	self.ctx:sfx("open")
end

function ItemShopPanel.close(self)
	if not self.is_open then
		return
	end
	self.is_open = false
	if self._drift ~= nil then
		self._drift:Cancel()
		self._drift = nil
	end
	-- everything sinks a little and fades, quickly; the backdrop pulls back as it goes dark
	for _, o in self._pops do
		Anim.tween(Anim.scale_of(o), 0.16, { Scale = 0.92 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		Anim.sink(o, 0, 18)
		local body = o:FindFirstChildOfClass("CanvasGroup")
		if body ~= nil then
			Anim.tween(body, 0.14, { GroupTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
	end
	Anim.tween(self.backdrop, 0.26, { ImageTransparency = 1, Size = UDim2.fromScale(1.1, 1.1) }, Enum.EasingStyle.Sine, Enum.EasingDirection.In, 0.04)
	Anim.tween(self.shade, 0.24, { BackgroundTransparency = 1 }, Enum.EasingStyle.Sine, Enum.EasingDirection.In, 0.06)
	local tw = Anim.tween(self.root, 0.24, { BackgroundTransparency = 1 }, Enum.EasingStyle.Sine, Enum.EasingDirection.In, 0.08)
	tw.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed and not self.is_open then
			self.root.Visible = false
			-- back in place for the next opening
			for _, o in self._pops do
				o.Position = Anim.home(o)
				Anim.scale_of(o).Scale = 1
			end
		end
	end)
	self.ctx:sfx("close")
end

return ItemShopPanel
