--!strict
-- (Take Over the World!: the item shop, 2026-11-06; it replaces the crate offers and the flag shop.)
-- Bought with coins (the match currency: Data/Stars). Crates stay: a crate costs CRATE_PRICE and is
-- opened as before (server/Purchases.open_crate). The featured items are cosmetics (Data/Cosmetics)
-- picked by the UTC day, priced by rarity.
local Cosmetics = require("./Cosmetics")

local ItemShop = {}

ItemShop.CRATE_PRICE = 1500
ItemShop.FEATURED = 6
ItemShop.PRICES = { common = 800, uncommon = 1500, rare = 2500, epic = 5000, legendary = 12000 }
ItemShop.DEFAULT_PRICE = 2000

function ItemShop.price(it: any): number
	return ItemShop.PRICES[tostring(it.rarity or "")] or ItemShop.DEFAULT_PRICE
end

local pool: { any }? = nil
local function items(): { any }
	if pool == nil then
		local list = {}
		for _, it in Cosmetics.all() do
			if it.kind == "skin" and Cosmetics.may_own(it.id, nil) and it.shop ~= false then -- (skins: drawn from masks, no images)
				table.insert(list, it)
			end
		end
		table.sort(list, function(a, b)
			return tostring(a.id) < tostring(b.id)
		end)
		pool = list
	end
	return pool :: { any }
end

--- Today's featured items (UTC day `day`): { {id, name, kind, rarity, price} }.
function ItemShop.featured(day: number): { any }
	local list = items()
	local idx = {}
	for i = 1, #list do
		idx[i] = i
	end
	local x = (day * 40503 + 17) % 2147483648
	for i = #idx, 2, -1 do
		x = (x * 1103515245 + 12345) % 2147483648
		local j = x % i + 1
		idx[i], idx[j] = idx[j], idx[i]
	end
	local out = {}
	for i = 1, math.min(ItemShop.FEATURED, #idx) do
		local it = list[idx[i]]
		table.insert(out, { id = it.id, name = it.name or it.id, kind = it.kind, rarity = it.rarity, price = ItemShop.price(it) })
	end
	return out
end

--- The price of `id` today (nil when it is not for sale today): "crate" or a featured item.
function ItemShop.price_of(id: string, day: number): number?
	if id == "crate" then
		return ItemShop.CRATE_PRICE
	end
	for _, f in ItemShop.featured(day) do
		if f.id == id then
			return f.price
		end
	end
	return nil
end

return ItemShop
