--!nonstrict
-- (Take Over the World!: the item shop, 2026-11-07 layout: a full screen over a pixel-art showroom.)
-- Coins (the match currency) buy today's gear (Data/ItemShop: the same list on every client and the
-- server, by UTC day): three tall FEATURED cards and six DAILY cards, each in its rarity's colours with
-- the item's picture (UI/GearArt), its name, its kind and its price. Below them (the sections scroll):
-- BUNDLES, several pieces of gear for Robux (Data/Bundles). The top bar: BUY COINS (coin packs for
-- Robux) and MY ITEMS (owned gear, pressed to wear / take off). Hats are worn by the player's
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
		if not lit then
			b.MouseEnter:Connect(function()
				b.BackgroundTransparency = 0.82
			end)
			b.MouseLeave:Connect(function()
				b.BackgroundTransparency = 1
			end)
		end
		Anim.button(b, nil, 1.04)
		return b
	end
	nav_pill("ITEM SHOP", 1, true)
	-- (no crates: coins are bought with Robux, owned gear is worn from MY ITEMS)
	nav_pill("MY ITEMS", 2, false).Activated:Connect(function()
		self.ctx:sfx("click")
		self:_overlay("items")
	end)
	nav_pill("BUY COINS", 3, false).Activated:Connect(function()
		self.ctx:sfx("click")
		self:_overlay("coins")
	end)
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
	-- the sections scroll: FEATURED, DAILY, then the BUNDLES
	local CW, CH, GAP = 206, 286, 16 -- a card
	local X0 = 108
	local scroll = make("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 72),
		Size = UDim2.new(1, 0, 0, 600),
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Color3.fromHex("C9C8FF"),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = 42,
	}, canvas)
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
		}, scroll))
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
	-- the bundles (Robux)
	local tc
	tc, y = section(y, "BUNDLES")
	table.insert(self.sections, y - 58)
	tc.Text = "Robux only"
	self.bundle_cards = {}
	local BW = (5 * CW + 4 * GAP - 3 * GAP) / 4
	for i, b in Bundles.LIST do
		local c = card(X0 + (i - 1) % 4 * (BW + GAP), y, BW, CH, false)
		c.bundle = b
		c.f = nil
		c.name.Text = string.upper(b.name)
		c.kind.Text = string.format("Bundle · %d items", #b.items)
		local r = RARITY[b.rarity] or RARITY.common
		c.grad.Color = ColorSequence.new(r[1], r[2])
		c.glow.ImageColor3 = r[4]
		c.price.coin.Image = ROBUX
		c.price.coin.ImageColor3 = TEXT
		-- the bundle's items, side by side over the art
		c.art.Visible = false
		local strip = make("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.36),
			Size = UDim2.new(1, -16, 0, BW / 2),
			ZIndex = 44,
		}, c.art.Parent)
		make("UIGridLayout", {
			CellSize = UDim2.fromOffset(BW / 2 - 12, BW / 2 - 12),
			CellPadding = UDim2.fromOffset(4, 4),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, strip)
		strip.Size = UDim2.new(1, -16, 0, BW - 16)
		for k, id in b.items do
			local img = make("ImageLabel", {
				BackgroundTransparency = 1,
				ResampleMode = Enum.ResamplerMode.Pixelated,
				LayoutOrder = k,
				ZIndex = 44,
			}, strip)
			img.ImageContent = GearArt.content(Cosmetics.item(id), BALLS[(i + k) % #BALLS + 1]) or Content.none
		end
		self.bundle_cards[i] = c
	end
	y += CH + 30
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
	self:_build_overlay(canvas)
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

--- The two panels over the shop: coin packs ("coins") and the gear the player owns ("items").
function ItemShopPanel._build_overlay(self, canvas: Frame)
	local dim = make("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
		-- (past the canvas on every side: the whole screen dims)
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(4, 4),
		Visible = false,
		ZIndex = 60,
	}, canvas)
	self.overlay = dim
	local panel = make("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 14 / 4),
		Size = UDim2.fromOffset(980, 480),
		ZIndex = 61,
	}, dim)
	self.overlay_panel = panel
	make("UICorner", { CornerRadius = UDim.new(0, 16) }, panel)
	make("UIStroke", { Color = AMBER, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, panel)
	make("UIGradient", { Color = ColorSequence.new(Color3.fromHex("22306A"), Color3.fromHex("0C1230")), Rotation = 90 }, panel)
	self.overlay_title = label(panel, "", 32, Enum.FontWeight.Heavy, AMBER, {
		Position = UDim2.fromOffset(24, 16),
		Size = UDim2.fromOffset(600, 38),
		ZIndex = 63,
	})
	make("UIStroke", { Color = INK, Thickness = 2 }, self.overlay_title)
	local x = make("TextButton", {
		Text = "X",
		TextSize = 20,
		FontFace = Font.new(FONT, Enum.FontWeight.Heavy),
		TextColor3 = TEXT,
		BackgroundColor3 = Color3.fromHex("C83A3A"),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.fromOffset(42, 42),
		ZIndex = 63,
	}, panel)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, x)
	make("UIStroke", { Color = INK, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, x)
	Anim.button(x)
	x.Activated:Connect(function()
		self.ctx:sfx("close")
		dim.Visible = false
	end)
	dim.Activated:Connect(function()
		dim.Visible = false
	end)
	-- coin packs
	local packs = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(24, 76), Size = UDim2.new(1, -48, 1, -100), ZIndex = 62 }, panel)
	self.overlay_coins = packs
	local PW = (980 - 48 - 3 * 18) / 4
	for i, pk in Bundles.COINS do
		local b = make("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Color3.new(1, 1, 1),
			Position = UDim2.fromOffset((i - 1) * (PW + 18), 0),
			Size = UDim2.fromOffset(PW, 380),
			ZIndex = 62,
		}, packs)
		make("UICorner", { CornerRadius = UDim.new(0, 12) }, b)
		make("UIStroke", { Color = INK, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
		make("UIGradient", { Color = ColorSequence.new(Color3.fromHex("FFC94A"), Color3.fromHex("C46A12")), Rotation = 90 }, b)
		make("ImageLabel", {
			BackgroundTransparency = 1,
			Image = UITheme.icon("gold") or "",
			ImageColor3 = Color3.fromHex("FFF2B0"),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.34),
			Size = UDim2.fromOffset(70 + i * 18, 70 + i * 18),
			ZIndex = 63,
		}, b)
		local amount = label(b, commas(pk.coins), 34, Enum.FontWeight.Heavy, TEXT, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 236),
			Size = UDim2.new(1, -12, 0, 38),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 63,
		})
		make("UIStroke", { Color = INK, Thickness = 2 }, amount)
		label(b, "COINS", 16, Enum.FontWeight.Heavy, INK, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 276),
			Size = UDim2.new(1, -12, 0, 20),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 63,
		})
		local price = make("Frame", {
			BackgroundColor3 = Color3.fromHex("2F6B2F"),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -14),
			Size = UDim2.new(1, -28, 0, 44),
			ZIndex = 63,
		}, b)
		make("UICorner", { CornerRadius = UDim.new(0, 10) }, price)
		make("UIStroke", { Color = INK, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, price)
		local row = price_row(price, 20, 9)
		row.coin.Image = ROBUX
		row.coin.ImageColor3 = TEXT
		row.coin.ZIndex = 64
		row.text.ZIndex = 64
		row.text.Text = commas(pk.robux)
		if pk.tag ~= nil then
			local tag = make("TextLabel", {
				Text = pk.tag,
				TextSize = 15,
				FontFace = Font.new(FONT, Enum.FontWeight.Heavy),
				TextColor3 = TEXT,
				BackgroundColor3 = Color3.fromHex("D13B3B"),
				Position = UDim2.fromOffset(-8, -10),
				Size = UDim2.fromOffset(118, 26),
				Rotation = -6,
				ZIndex = 65,
			}, b)
			make("UIStroke", { Color = INK, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, tag)
		end
		Anim.button(b, nil, 1.04)
		b.Activated:Connect(function()
			self:_prompt("coins_" .. pk.id)
		end)
	end
	-- my items: a grid of owned gear (pressing one wears it / takes it off)
	local grid = make("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(24, 76),
		Size = UDim2.new(1, -48, 1, -96),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = AMBER,
		ZIndex = 62,
	}, panel)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(140, 170), CellPadding = UDim2.fromOffset(12, 12), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	self.overlay_items = grid
	self.item_tiles = {}
	self.items_empty = label(panel, "You don't own any gear yet: buy some in the shop!", 18, Enum.FontWeight.Bold, TEXT2, {
		Position = UDim2.fromOffset(24, 90),
		Size = UDim2.new(1, -48, 0, 24),
		Visible = false,
		ZIndex = 63,
	})
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

function ItemShopPanel._overlay(self, which: string)
	self.overlay_which = which
	self.overlay_title.Text = if which == "coins" then "BUY COINS" else "MY ITEMS"
	self.overlay_coins.Visible = which == "coins"
	self.overlay_items.Visible = which == "items"
	self.overlay.Visible = true
	self.overlay.BackgroundTransparency = 1
	Anim.tween(self.overlay, Anim.FADE_S, { BackgroundTransparency = 0.35 })
	Anim.pop(self.overlay_panel, 0.05)
	self:_refresh_overlay()
end

function ItemShopPanel._refresh_overlay(self)
	local items = self.overlay_which == "items"
	local owned = {}
	if items then
		for _, it in Cosmetics.gear() do
			if self:_owned(it.id) then
				table.insert(owned, it)
			end
		end
	end
	self.items_empty.Visible = items and #owned == 0
	for i, it in owned do
		local t = self.item_tiles[i]
		if t == nil then
			local b = make("TextButton", {
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = Color3.new(1, 1, 1),
				LayoutOrder = i,
				ZIndex = 62,
			}, self.overlay_items)
			make("UICorner", { CornerRadius = UDim.new(0, 10) }, b)
			local stroke = make("UIStroke", { Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = INK }, b)
			local grad = make("UIGradient", { Rotation = 90 }, b)
			local pic = make("ImageLabel", {
				BackgroundTransparency = 1,
				ResampleMode = Enum.ResamplerMode.Pixelated,
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 8),
				Size = UDim2.fromOffset(100, 100),
				ZIndex = 63,
			}, b)
			local name = label(b, "", 13, Enum.FontWeight.Heavy, TEXT, {
				Position = UDim2.fromOffset(6, 112),
				Size = UDim2.new(1, -12, 0, 17),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextScaled = true,
				ZIndex = 63,
			})
			make("UITextSizeConstraint", { MaxTextSize = 13 }, name)
			local state = label(b, "", 13, Enum.FontWeight.Heavy, AMBER, {
				Position = UDim2.fromOffset(6, 140),
				Size = UDim2.new(1, -12, 0, 17),
				TextXAlignment = Enum.TextXAlignment.Center,
				ZIndex = 63,
			})
			t = { b = b, stroke = stroke, grad = grad, pic = pic, name = name, state = state }
			b.Activated:Connect(function()
				local id = t.id
				local item = id and Cosmetics.item(id)
				local se = self.ctx.session
				if item ~= nil and se ~= nil and type(se.equip) == "function" then
					local wearing = self:_worn(item.kind, id)
					se:equip(item.kind, if wearing then false else id)
					self.ctx:sfx("click")
					self:_toast(if wearing then (item.name .. " taken off.") else (item.name .. " equipped!"), GREEN)
				end
			end)
			Anim.button(b, nil, 1.05)
			self.item_tiles[i] = t
		end
		t.b.Visible = true
		if t.id ~= it.id then
			t.id = it.id
			local r = RARITY[it.rarity or "common"] or RARITY.common
			t.grad.Color = ColorSequence.new(r[1], r[2])
			t.name.Text = string.upper(it.name)
			t.pic.ImageContent = GearArt.content(it, BALLS[i % #BALLS + 1]) or Content.none
		end
		local worn = self:_worn(it.kind, it.id)
		t.state.Text = if worn then "EQUIPPED" else "EQUIP"
		t.state.TextColor3 = if worn then GREEN else AMBER
		t.stroke.Color = if worn then GREEN else INK
	end
	for i = #owned + 1, #self.item_tiles do
		self.item_tiles[i].b.Visible = false
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
		local all = true
		for _, id in b.items do
			if not self:_owned(id) then
				all = false
			end
		end
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
	if self.overlay ~= nil and self.overlay.Visible then
		self:_refresh_overlay()
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
	if self.overlay ~= nil then
		self.overlay.Visible = false
	end
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
