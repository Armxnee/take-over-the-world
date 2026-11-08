--!strict
-- (Take Over the World!: the item shop, 2026-11-06; it replaces the crate offers and the flag shop.)
-- Bought with coins (the match currency: Data/Stars). Crates stay: a crate costs CRATE_PRICE and is
-- opened as before (server/Purchases.open_crate). The featured items are cosmetics (Data/Cosmetics)
-- and the gear (Data/Gear: hats, boat / nuke / missile skins) picked by the UTC day, priced by rarity.
local Cosmetics = require("./Cosmetics")
local Bundles = require("./Bundles")

local ItemShop = {}

ItemShop.CRATE_PRICE = 1500
ItemShop.FEATURED = 5 -- the featured cards (rare and up), a row of five
ItemShop.DAILY = 10 -- the daily cards (anything for sale), two rows of five
ItemShop.PRICES = { common = 800, uncommon = 1500, rare = 2500, epic = 5000, legendary = 12000 }
ItemShop.DEFAULT_PRICE = 2000

function ItemShop.price(it: any): number
	return ItemShop.PRICES[tostring(it.rarity or "")] or ItemShop.DEFAULT_PRICE
end

local pools: any = nil
--- { big = { item }, all = { item } }: what the featured and the daily cards are drawn from.
local function items(): any
	if pools == nil then
		local all, big = {}, {}
		-- (gear only: hats and boat / nuke / missile skins; no territory skins, a country wears its flag.
		-- 2026-11-08: nothing that comes in a Robux bundle; the shop always sells other things)
		local in_bundle = {}
		for _, b in Bundles.LIST do
			for _, id in b.items do
				in_bundle[id] = true
			end
		end
		for _, it in Cosmetics.gear() do
			if in_bundle[it.id] then
				continue
			end
			table.insert(all, it)
			if it.rarity == "rare" or it.rarity == "epic" or it.rarity == "legendary" then
				table.insert(big, it)
			end
		end
		local function by_id(a: any, b: any): boolean
			return tostring(a.id) < tostring(b.id)
		end
		table.sort(all, by_id)
		table.sort(big, by_id)
		pools = { all = all, big = big }
	end
	return pools
end

-- a day's shuffle of 1..n (the same on every client and the server)
local function shuffle(n: number, seed: number): { number }
	local idx = {}
	for i = 1, n do
		idx[i] = i
	end
	local x = (seed * 40503 + 17) % 2147483648
	for i = n, 2, -1 do
		x = (x * 1103515245 + 12345) % 2147483648
		local j = x % i + 1
		idx[i], idx[j] = idx[j], idx[i]
	end
	return idx
end

local function entry(it: any, big: boolean): any
	return { id = it.id, name = it.name or it.id, kind = it.kind, rarity = it.rarity, price = ItemShop.price(it), big = big }
end

--- Today's items (UTC day `day`): ItemShop.FEATURED big cards, then ItemShop.DAILY small ones:
--- { {id, name, kind, rarity, price, big} }. No item shows twice.
function ItemShop.featured(day: number): { any }
	local p = items()
	local out, taken = {}, {}
	for _, i in shuffle(#p.big, day * 7 + 3) do
		if #out >= ItemShop.FEATURED then
			break
		end
		local it = p.big[i]
		taken[it.id] = true
		table.insert(out, entry(it, true))
	end
	local n = 0
	for _, i in shuffle(#p.all, day) do
		if n >= ItemShop.DAILY then
			break
		end
		local it = p.all[i]
		if not taken[it.id] then
			taken[it.id] = true
			n += 1
			table.insert(out, entry(it, false))
		end
	end
	return out
end

--- Was `id` for sale on day `day`?
function ItemShop.on_sale(id: string, day: number): boolean
	for _, f in ItemShop.featured(day) do
		if f.id == id then
			return true
		end
	end
	return false
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
