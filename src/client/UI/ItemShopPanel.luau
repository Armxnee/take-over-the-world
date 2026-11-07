--!nonstrict
-- (Take Over the World!: the item shop, 2026-11-06; it replaces the crate offers and the flag shop.)
-- Coins (the match currency) buy a crate (opened as before, in the Locker) or one of today's featured
-- territory skins (Data/ItemShop: the same list on every client and the server, by UTC day). BUY asks
-- the server (Session.buy_item), which checks the price and the balance and keeps the item.
local RunService = game:GetService("RunService")
local AssetService = game:GetService("AssetService")
local RS = game:GetService("ReplicatedStorage")
local Airfront = RS:WaitForChild("Airfront")
local ItemShop = require(Airfront.Data.ItemShop)
local Cosmetics = require(Airfront.Data.Cosmetics)

local ItemShopPanel = {}
ItemShopPanel.__index = ItemShopPanel

local FONT = "rbxassetid://12187365977"
local NAVY = Color3.fromHex("0D1326")
local AMBER = Color3.fromHex("FFB547")
local TEXT = Color3.new(1, 1, 1)
local TEXT2 = Color3.fromHex("A9B4D0")
local GREEN = Color3.fromHex("5BE38E")
local RARITY = {
	common = Color3.fromHex("A9B4D0"),
	uncommon = GREEN,
	rare = Color3.fromHex("49C6F2"),
	epic = Color3.fromHex("B48CFF"),
	legendary = AMBER,
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
		ZIndex = 43,
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

local function button(parent: Instance, text: string, props: { [string]: any }): TextButton
	local b = make("TextButton", {
		Text = text,
		TextSize = 13,
		FontFace = Font.new(FONT, Enum.FontWeight.Heavy),
		TextColor3 = Color3.fromHex("3A2400"),
		BackgroundColor3 = AMBER,
		ZIndex = 44,
		Selectable = true,
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, b)
	for k, v in props do
		b[k] = v
	end
	return b
end

-- a skin's pattern as a small picture (its mask over an amber territory)
local previews = {}
local function preview(id: string): Content?
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

function ItemShopPanel.new(ctx: any, gui: Instance, open_locker: () -> ())
	local self = setmetatable({}, ItemShopPanel)
	self.ctx = ctx
	self.is_open = false
	self.cards = {}
	self.day = -1
	local dim = make("TextButton", {
		Name = "ItemShop",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 40,
	}, gui)
	self.root = dim
	local panel = make("Frame", {
		BackgroundColor3 = NAVY,
		BackgroundTransparency = 0.04,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(600, 470),
		ZIndex = 41,
	}, dim)
	make("UICorner", { CornerRadius = UDim.new(0, 14) }, panel)
	make("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.85 }, panel)
	make("UIPadding", { PaddingTop = UDim.new(0, 16), PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18), PaddingBottom = UDim.new(0, 16) }, panel)
	label(panel, "ITEM SHOP", 22, Enum.FontWeight.Heavy, AMBER)
	self.balance = label(panel, "", 14, Enum.FontWeight.Heavy, TEXT, { Position = UDim2.fromOffset(0, 28) })
	local close = button(panel, "X", { TextColor3 = TEXT, BackgroundColor3 = Color3.fromHex("2A3352"), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(30, 30), TextSize = 16 })
	close.Activated:Connect(function()
		self:close()
	end)
	-- crates
	local crate = make("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.93, Position = UDim2.fromOffset(0, 56), Size = UDim2.new(1, 0, 0, 74), ZIndex = 42 }, panel)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, crate)
	label(crate, "CRATE", 16, Enum.FontWeight.Heavy, TEXT, { Position = UDim2.fromOffset(14, 10), Size = UDim2.fromOffset(200, 20) })
	self.crate_info = label(crate, "", 12, Enum.FontWeight.Medium, TEXT2, { Position = UDim2.fromOffset(14, 36), Size = UDim2.new(1, -330, 0, 30), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
	self.buy_crate = button(crate, "BUY · " .. commas(ItemShop.CRATE_PRICE), { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -140, 0.5, 0), Size = UDim2.fromOffset(150, 40) })
	self.buy_crate.Activated:Connect(function()
		self:_buy("crate")
	end)
	self.open_crates = button(crate, "OPEN CRATES", { TextColor3 = TEXT, BackgroundColor3 = Color3.fromHex("2A3352"), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(122, 40) })
	self.open_crates.Activated:Connect(function()
		self:close()
		open_locker()
	end)
	label(panel, "TODAY'S ITEMS", 13, Enum.FontWeight.Heavy, TEXT2, { Position = UDim2.fromOffset(0, 142) })
	self.reset = label(panel, "", 11, Enum.FontWeight.Medium, TEXT2, { Position = UDim2.fromOffset(120, 143), Size = UDim2.fromOffset(250, 15) })
	local grid = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 164), Size = UDim2.new(1, 0, 0, 240), ZIndex = 42 }, panel)
	make("UIGridLayout", { CellSize = UDim2.new(1 / 3, -8, 0, 114), CellPadding = UDim2.fromOffset(12, 10), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	for i = 1, ItemShop.FEATURED do
		local card = make("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.94, LayoutOrder = i, ZIndex = 42 }, grid)
		make("UICorner", { CornerRadius = UDim.new(0, 10) }, card)
		local pic = make("ImageLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(52, 52), ResampleMode = Enum.ResamplerMode.Pixelated, ZIndex = 43 }, card)
		make("UICorner", { CornerRadius = UDim.new(0, 8) }, pic)
		local name = label(card, "", 13, Enum.FontWeight.Bold, TEXT, { Position = UDim2.fromOffset(70, 12), Size = UDim2.new(1, -76, 0, 17) })
		local rar = label(card, "", 11, Enum.FontWeight.Bold, TEXT2, { Position = UDim2.fromOffset(70, 32), Size = UDim2.new(1, -76, 0, 14) })
		local buy = button(card, "", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.new(1, -16, 0, 34) })
		local c = { card = card, pic = pic, name = name, rarity = rar, buy = buy, id = nil, price = 0 }
		buy.Activated:Connect(function()
			if c.id ~= nil then
				self:_buy(c.id)
			end
		end)
		self.cards[i] = c
	end
	self.toast = label(panel, "", 13, Enum.FontWeight.Bold, GREEN, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 18) })
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

function ItemShopPanel._coins(self): number
	local s = self.ctx.session
	local inv = s and s.inventory
	return (inv and tonumber(inv.stars)) or 0
end

function ItemShopPanel._crates(self): number
	local s = self.ctx.session
	local c = s and s.credits
	return (c and tonumber(c.crate)) or 0
end

function ItemShopPanel._owned(self, id: string): boolean
	local s = self.ctx.session
	local inv = s and s.inventory
	if inv == nil or type(inv.owned) ~= "table" then
		return false
	end
	if inv.owned[id] == true then
		return true
	end
	return table.find(inv.owned, id) ~= nil
end

function ItemShopPanel.refresh(self)
	local coins = self:_coins()
	self.balance.Text = "Coins: " .. commas(coins)
	local n = self:_crates()
	self.crate_info.Text = string.format("A random territory skin. You have %d crate%s to open.", n, if n == 1 then "" else "s")
	self.buy_crate.BackgroundTransparency = if coins >= ItemShop.CRATE_PRICE then 0 else 0.5
	local now = os.time()
	local day = now // 86400
	local left = 86400 - now % 86400
	self.reset.Text = string.format("new items in %dh %02dm", left // 3600, (left % 3600) // 60)
	if day ~= self.day then
		self.day = day
		for i, f in ItemShop.featured(day) do
			local c = self.cards[i]
			c.id = f.id
			c.price = f.price
			c.name.Text = f.name
			c.rarity.Text = string.upper(tostring(f.rarity or "common"))
			c.rarity.TextColor3 = RARITY[f.rarity or "common"] or TEXT2
			local p = preview(f.id)
			if p ~= nil then
				c.pic.ImageContent = p
			end
		end
	end
	for _, c in self.cards do
		c.card.Visible = c.id ~= nil
		if c.id ~= nil then
			if self:_owned(c.id) then
				c.buy.Text = "OWNED"
				c.buy.BackgroundColor3 = Color3.fromHex("2A3352")
				c.buy.TextColor3 = GREEN
			else
				c.buy.Text = "BUY · " .. commas(c.price)
				c.buy.BackgroundColor3 = AMBER
				c.buy.TextColor3 = Color3.fromHex("3A2400")
				c.buy.BackgroundTransparency = if coins >= c.price then 0 else 0.5
			end
		end
	end
end

function ItemShopPanel._buy(self, id: string)
	local s = self.ctx.session
	if s == nil or type(s.buy_item) ~= "function" then
		return
	end
	s:buy_item(id)
	self.ctx:sfx("click")
	self.toast.Text = "Buying…"
	self.toast.TextColor3 = TEXT2
end

--- The server's answer (Session "item_result").
function ItemShopPanel.on_result(self, id: string, ok: boolean, why: string?)
	if ok then
		self.toast.Text = if id == "crate" then "Crate bought! Open it from OPEN CRATES." else "Bought! Wear it from the Locker."
		self.toast.TextColor3 = GREEN
		self.ctx:sfx("buy")
	else
		self.toast.Text = if why == "not enough" then "Not enough coins yet: play matches and finish quests." else ("Couldn't buy: " .. tostring(why))
		self.toast.TextColor3 = Color3.fromHex("FF5C61")
		self.ctx:sfx("deny", -4.0)
	end
	self:refresh()
end

function ItemShopPanel.open(self)
	self.is_open = true
	self.root.Visible = true
	self.toast.Text = ""
	self:refresh()
	self.ctx:sfx("open")
end

function ItemShopPanel.close(self)
	self.is_open = false
	self.root.Visible = false
	self.ctx:sfx("close")
end

return ItemShopPanel
