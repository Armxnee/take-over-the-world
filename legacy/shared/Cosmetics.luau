--!strict
-- Cosmetic catalog (zero gameplay effect): territory skins and nation flags.
-- Skins are pixel patterns drawn over your territory; flags are procedural (no uploads).
local Cosmetics = {}

Cosmetics.Rarity = {
	common = { name = "COMMON", color = Color3.fromHex("8B98A8"), price = 150, refund = 60 },
	rare = { name = "RARE", color = Color3.fromHex("3FB6FF"), price = 400, refund = 160 },
	epic = { name = "EPIC", color = Color3.fromHex("C77DFF"), price = 900, refund = 360 },
	legendary = { name = "LEGENDARY", color = Color3.fromHex("F5C451"), price = 2000, refund = 800 },
}
Cosmetics.RarityOrder = { "common", "rare", "epic", "legendary" }

-- skins: pattern ids understood by Cosmetics.skinPixel
Cosmetics.Skins = {
	skin_stripes = { name = "Stripes", rarity = "common", pattern = "stripes" },
	skin_dots = { name = "Dotted", rarity = "common", pattern = "dots" },
	skin_grid = { name = "Survey Grid", rarity = "common", pattern = "grid" },
	skin_checker = { name = "Checkerboard", rarity = "rare", pattern = "checker" },
	skin_waves = { name = "Tidal", rarity = "rare", pattern = "waves" },
	skin_camo = { name = "Camo", rarity = "epic", pattern = "camo" },
	skin_hatch = { name = "Crosshatch", rarity = "epic", pattern = "hatch" },
	skin_gold = { name = "Gilded Border", rarity = "legendary", pattern = "gold" },
	skin_neon = { name = "Neon Frontier", rarity = "legendary", pattern = "neon" },
}

-- flags: kind + colours (hex)
Cosmetics.Flags = {
	flag_tri_v = { name = "Tricolore", rarity = "common", kind = "triV", colors = { "2B5BA8", "F2F2F2", "D23A3A" } },
	flag_tri_h = { name = "Horizon", rarity = "common", kind = "triH", colors = { "1E1E1E", "D23A3A", "F5C451" } },
	flag_bi = { name = "Dawn", rarity = "common", kind = "biH", colors = { "F2F2F2", "D23A3A" } },
	flag_cross = { name = "Northern Cross", rarity = "rare", kind = "cross", colors = { "2B5BA8", "F5C451" } },
	flag_sun = { name = "Rising Sun", rarity = "rare", kind = "disc", colors = { "F2F2F2", "D23A3A" } },
	flag_diag = { name = "Sash", rarity = "epic", kind = "diag", colors = { "1E7A46", "F5C451" } },
	flag_star = { name = "Lone Star", rarity = "epic", kind = "star", colors = { "1E3A8A", "F2F2F2" } },
	flag_royal = { name = "Royal Standard", rarity = "legendary", kind = "quarter", colors = { "6B21A8", "F5C451", "D23A3A", "1E3A8A" } },
}

-- vehicle skins: slot = boat (transports, warships, trade ships) | plane | missile (nukes)
Cosmetics.Vehicles = {}
Cosmetics.VehicleSlots = { "boat", "plane", "missile" }
-- skins from the Conquest Voxel Pack; Standard (no skin) uses your nation colour
local VEH = {
	{ "arctic", "Arctic", "common" },
	{ "desert", "Desert", "rare" },
	{ "midnight", "Midnight", "epic" },
	{ "gold", "Gold", "legendary" },
}
local SLOTNAME = { boat = "Boats", plane = "Planes", missile = "Missiles" }
for _, slot in Cosmetics.VehicleSlots do
	for _, v in VEH do
		Cosmetics.Vehicles[slot .. "_" .. v[1]] = { name = v[2] .. " " .. SLOTNAME[slot], rarity = v[3], slot = slot, palette = v[1] }
	end
end

Cosmetics.Crates = {
	crate_std = { name = "Standard Crate", price = 250, odds = { common = 60, rare = 30, epic = 9, legendary = 1 } },
	crate_elite = { name = "Elite Crate", price = 800, odds = { common = 0, rare = 55, epic = 35, legendary = 10 } },
}
Cosmetics.CrateOrder = { "crate_std", "crate_elite" }

-- featured bundle (rotates weekly)
Cosmetics.Bundles = {
	{ id = "bundle_neon", name = "NEON FRONTIER SET", items = { "skin_neon", "flag_star" }, price = 2400 },
	{ id = "bundle_royal", name = "ROYAL SET", items = { "skin_gold", "flag_royal" }, price = 3200 },
	{ id = "bundle_camo", name = "DESERT STORM", items = { "skin_camo", "flag_diag", "boat_desert", "plane_desert" }, price = 2200 },
	{ id = "bundle_stealth", name = "MIDNIGHT FLEET", items = { "boat_midnight", "plane_midnight", "missile_midnight" }, price = 1800 },
}

-- Robux coin packs: set real developer product ids before publishing (0 = hidden)
Cosmetics.CoinPacks = {
	{ productId = 0, coins = 1000, robux = 99, name = "Pouch" },
	{ productId = 0, coins = 2800, robux = 249, name = "Chest" },
	{ productId = 0, coins = 6000, robux = 499, name = "Vault", tag = "BEST VALUE" },
}

-- match rewards
Cosmetics.Rewards = { win = 300, top3 = 150, played = 50, perCells = 20, cellCap = 100, startCoins = 500 }

function Cosmetics.item(id: string): any
	return Cosmetics.Skins[id] or Cosmetics.Flags[id] or Cosmetics.Vehicles[id]
end

function Cosmetics.slotOf(id: string): string?
	if Cosmetics.Skins[id] then
		return "skin"
	elseif Cosmetics.Flags[id] then
		return "flag"
	elseif Cosmetics.Vehicles[id] then
		return Cosmetics.Vehicles[id].slot
	end
	return nil
end

Cosmetics.Slots = { "skin", "flag", "boat", "plane", "missile" }

function Cosmetics.allIds(): { string }
	local out = {}
	for id in Cosmetics.Skins do
		table.insert(out, id)
	end
	for id in Cosmetics.Flags do
		table.insert(out, id)
	end
	for id in Cosmetics.Vehicles do
		table.insert(out, id)
	end
	table.sort(out)
	return out
end

-- 6 daily offers, same for everyone on a UTC day
function Cosmetics.dailyOffers(day: number): { string }
	local ids = Cosmetics.allIds()
	local rng = Random.new(day * 7919 + 17)
	local out = {}
	while #out < 6 and #ids > 0 do
		local k = rng:NextInteger(1, #ids)
		table.insert(out, table.remove(ids, k) :: string)
	end
	return out
end

function Cosmetics.featured(day: number): any
	return Cosmetics.Bundles[(day // 7) % #Cosmetics.Bundles + 1]
end

-- skin pattern: returns 0 = base fill, 1 = shade, 2 = highlight (gx, gy = global pixel coords)
function Cosmetics.skinPixel(pattern: string, gx: number, gy: number): number
	if pattern == "stripes" then
		return if ((gx + gy) // 3) % 2 == 0 then 1 else 0
	elseif pattern == "dots" then
		return if gx % 4 == 1 and gy % 4 == 1 then 2 else 0
	elseif pattern == "grid" then
		return if gx % 8 == 0 or gy % 8 == 0 then 1 else 0
	elseif pattern == "checker" then
		return if ((gx // 4) + (gy // 4)) % 2 == 0 then 1 else 0
	elseif pattern == "waves" then
		return if ((gx + math.floor(2 * math.sin(gy / 3))) // 3) % 2 == 0 then 1 else 0
	elseif pattern == "camo" then
		local v = math.sin(gx * 0.31) + math.sin(gy * 0.27) + math.sin((gx + gy) * 0.13)
		return if v > 0.8 then 1 elseif v < -1.2 then 2 else 0
	elseif pattern == "hatch" then
		return if (gx + gy) % 6 == 0 or (gx - gy) % 6 == 0 then 1 else 0
	end
	return 0
end

-- edge colour override for border skins
function Cosmetics.edgeColor(pattern: string?): Color3?
	if pattern == "gold" then
		return Color3.fromHex("F5C451")
	elseif pattern == "neon" then
		return Color3.fromHex("39FFD4")
	end
	return nil
end

-- build a flag as GUI frames inside `parent` (fills it)
function Cosmetics.drawFlag(parent: Instance, flagId: string?)
	for _, c in parent:GetChildren() do
		if c:GetAttribute("FlagPart") then
			c:Destroy()
		end
	end
	local f = flagId and Cosmetics.Flags[flagId]
	if not f then
		return
	end
	local function part(props: { [string]: any })
		local fr = Instance.new("Frame")
		fr.BorderSizePixel = 0
		for k, v in props do
			(fr :: any)[k] = v
		end
		fr:SetAttribute("FlagPart", true)
		fr.Parent = parent
		return fr
	end
	local c = {}
	for i, h in f.colors do
		c[i] = Color3.fromHex(h)
	end
	if f.kind == "triV" then
		for i = 1, 3 do
			part({ BackgroundColor3 = c[i], Size = UDim2.fromScale(1 / 3, 1), Position = UDim2.fromScale((i - 1) / 3, 0) })
		end
	elseif f.kind == "triH" then
		for i = 1, 3 do
			part({ BackgroundColor3 = c[i], Size = UDim2.fromScale(1, 1 / 3), Position = UDim2.fromScale(0, (i - 1) / 3) })
		end
	elseif f.kind == "biH" then
		part({ BackgroundColor3 = c[1], Size = UDim2.fromScale(1, 0.5) })
		part({ BackgroundColor3 = c[2], Size = UDim2.fromScale(1, 0.5), Position = UDim2.fromScale(0, 0.5) })
	elseif f.kind == "cross" then
		part({ BackgroundColor3 = c[1], Size = UDim2.fromScale(1, 1) })
		part({ BackgroundColor3 = c[2], Size = UDim2.fromScale(1, 0.2), Position = UDim2.fromScale(0, 0.4) })
		part({ BackgroundColor3 = c[2], Size = UDim2.fromScale(0.14, 1), Position = UDim2.fromScale(0.3, 0) })
	elseif f.kind == "disc" then
		part({ BackgroundColor3 = c[1], Size = UDim2.fromScale(1, 1) })
		local d = part({ BackgroundColor3 = c[2], AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.36, 0.6) })
		local uc = Instance.new("UICorner")
		uc.CornerRadius = UDim.new(0.5, 0)
		uc.Parent = d
	elseif f.kind == "diag" then
		part({ BackgroundColor3 = c[1], Size = UDim2.fromScale(1, 1) })
		part({ BackgroundColor3 = c[2], AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1.3, 0.22), Rotation = -30 })
	elseif f.kind == "star" then
		part({ BackgroundColor3 = c[1], Size = UDim2.fromScale(1, 1) })
		part({ BackgroundColor3 = c[2], Size = UDim2.fromScale(0.62, 1), Position = UDim2.fromScale(0.38, 0) })
		local s = part({ BackgroundColor3 = c[2], AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.19, 0.5), Size = UDim2.fromScale(0.16, 0.26), Rotation = 45 })
		local _ = s
	elseif f.kind == "quarter" then
		for i = 1, 4 do
			part({ BackgroundColor3 = c[i], Size = UDim2.fromScale(0.5, 0.5), Position = UDim2.fromScale(((i - 1) % 2) * 0.5, ((i - 1) // 2) * 0.5) })
		end
	end
end

return Cosmetics
