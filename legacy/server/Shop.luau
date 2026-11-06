--!strict
-- Shop: crates (odds always shown), daily offers, featured bundle, locker/equip,
-- match coin rewards and Robux coin packs (idempotent ProcessReceipt).
-- Crates are hidden for players where paid random items are restricted (PolicyService).
local MarketplaceService = game:GetService("MarketplaceService")
local PolicyService = game:GetService("PolicyService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local PlayerData = require(script.Parent.PlayerData)

local Shop = {}
Shop.onEquip = nil :: ((p: Player) -> ())?

local restricted: { [Player]: boolean } = {}
local rng = Random.new()
local lastCall: { [Player]: number } = {}

local function day(): number
	return os.time() // 86400
end

local function snapshot(p: Player): any
	local prof = PlayerData.get(p)
	local d = day()
	return {
		loaded = prof ~= nil,
		offline = PlayerData.isOffline(p),
		coins = prof and prof.coins or 0,
		owned = prof and prof.owned or {},
		equipped = prof and prof.equipped or {},
		daily = Cosmetics.dailyOffers(d),
		featured = Cosmetics.featured(d).id,
		resetIn = 86400 - os.time() % 86400,
		cratesAllowed = not restricted[p],
		packs = Cosmetics.CoinPacks,
	}
end

local function grant(prof: any, id: string): (boolean, number)
	if prof.owned[id] then
		local r = Cosmetics.Rarity[Cosmetics.item(id).rarity].refund
		prof.coins += r
		return false, r
	end
	prof.owned[id] = true
	return true, 0
end

local handlers: { [string]: (Player, any, any) -> (boolean, any) } = {}

handlers.info = function(p)
	return true, snapshot(p)
end

handlers.buy = function(p, prof, a)
	local id = a.item
	if typeof(id) ~= "string" then
		return false, "Bad item"
	end
	local d = day()
	-- featured bundle
	local fb = Cosmetics.featured(d)
	if id == fb.id then
		local missing = false
		for _, it in fb.items do
			if not prof.owned[it] then
				missing = true
			end
		end
		if not missing then
			return false, "You own this set"
		end
		if prof.coins < fb.price then
			return false, "Not enough coins"
		end
		prof.coins -= fb.price
		for _, it in fb.items do
			prof.owned[it] = true
		end
		return true, fb.name .. " unlocked!"
	end
	-- daily offer
	if not table.find(Cosmetics.dailyOffers(d), id) then
		return false, "Not on sale today"
	end
	local item = Cosmetics.item(id)
	if prof.owned[id] then
		return false, "Already owned"
	end
	local price = Cosmetics.Rarity[item.rarity].price
	if prof.coins < price then
		return false, "Not enough coins"
	end
	prof.coins -= price
	prof.owned[id] = true
	return true, item.name .. " unlocked!"
end

handlers.crate = function(p, prof, a)
	if restricted[p] then
		return false, "Crates are not available in your region"
	end
	local c = typeof(a.crate) == "string" and Cosmetics.Crates[a.crate]
	if not c then
		return false, "Bad crate"
	end
	if prof.coins < c.price then
		return false, "Not enough coins"
	end
	prof.coins -= c.price
	-- roll rarity by published odds, then a uniform item of that rarity
	local roll, acc, rarity = rng:NextNumber() * 100, 0, "common"
	for _, r in Cosmetics.RarityOrder do
		acc += c.odds[r] or 0
		if roll < acc then
			rarity = r
			break
		end
	end
	local pool = {}
	for _, id in Cosmetics.allIds() do
		if Cosmetics.item(id).rarity == rarity then
			table.insert(pool, id)
		end
	end
	local id = pool[rng:NextInteger(1, #pool)]
	local new, refund = grant(prof, id)
	return true, { item = id, new = new, refund = refund }
end

handlers.equip = function(p, prof, a)
	local id = a.item
	local slot = typeof(a.slot) == "string" and a.slot
	if not slot or not table.find(Cosmetics.Slots, slot) then
		return false, "Bad slot"
	end
	if id == nil or id == "" then
		prof.equipped[slot] = nil
	elseif typeof(id) == "string" and prof.owned[id] and Cosmetics.slotOf(id) == slot then
		prof.equipped[slot] = id
	else
		return false, "You don't own that"
	end
	if Shop.onEquip then
		Shop.onEquip(p)
	end
	return true, if prof.equipped[slot] then "Equipped" else "Unequipped"
end

handlers.pack = function(p, _prof, a)
	local pack = typeof(a.index) == "number" and Cosmetics.CoinPacks[a.index]
	if not pack or pack.productId == 0 then
		return false, "Coin packs aren't set up yet"
	end
	MarketplaceService:PromptProductPurchase(p, pack.productId)
	return true, "Opening purchase…"
end

-- Robux coin packs: grant, record the receipt in the profile, then confirm
MarketplaceService.ProcessReceipt = function(info)
	local p = Players:GetPlayerByUserId(info.PlayerId)
	local prof = p and PlayerData.get(p)
	if not p or not prof or PlayerData.isOffline(p) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if table.find(prof.receipts, info.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	for _, pack in Cosmetics.CoinPacks do
		if pack.productId == info.ProductId then
			-- grant + record the receipt, and confirm only once that is saved
			prof.coins += pack.coins
			table.insert(prof.receipts, info.PurchaseId)
			if not PlayerData.save(p, false) then
				prof.coins -= pack.coins
				table.remove(prof.receipts, table.find(prof.receipts, info.PurchaseId) :: number)
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end
			while #prof.receipts > 50 do
				table.remove(prof.receipts, 1)
			end
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

-- end-of-round coins; roundKey makes it retry-safe (granted once per round)
function Shop.reward(p: Player, roundKey: string, place: number, captured: number, won: boolean): number
	local prof = PlayerData.get(p)
	if not prof or prof.rewardedRound == roundKey then
		return 0
	end
	local R = Cosmetics.Rewards
	local coins = (if won then R.win elseif place <= 3 then R.top3 else R.played) + math.min(R.cellCap, captured // R.perCells)
	prof.coins += coins
	prof.matches += 1
	if won then
		prof.wins += 1
	end
	prof.rewardedRound = roundKey
	return coins
end

function Shop.equippedOf(p: Player): (string?, string?, any)
	local prof = PlayerData.get(p)
	if not prof then
		return nil, nil, nil
	end
	local e = prof.equipped :: any
	local veh = nil
	for _, slot in Cosmetics.VehicleSlots do
		local id = e[slot]
		if id and Cosmetics.Vehicles[id] then
			veh = veh or {}
			veh[slot] = Cosmetics.Vehicles[id].palette
		end
	end
	return e.skin, e.flag, veh
end

function Shop.init(remotes: Folder)
	local rf = Instance.new("RemoteFunction")
	rf.Name = "Shop"
	rf.Parent = remotes
	rf.OnServerInvoke = function(p: Player, action: any, a: any)
		local t = os.clock()
		if typeof(action) ~= "string" or t - (lastCall[p] or 0) < 0.25 then
			return false, "slow down"
		end
		lastCall[p] = t
		local h = handlers[action]
		if not h then
			return false, "unknown"
		end
		if typeof(a) ~= "table" then
			a = {}
		end
		local prof = PlayerData.get(p)
		if action ~= "info" and not prof then
			return false, "Loading your profile…"
		end
		local ok, res, extra = pcall(h, p, prof, a)
		if not ok then
			warn("[Shop]", action, res)
			return false, "Shop error"
		end
		return res, extra, snapshot(p)
	end
	Players.PlayerAdded:Connect(function(p)
		task.spawn(function()
			local ok, pol = pcall(function()
				return PolicyService:GetPolicyInfoForPlayerAsync(p)
			end)
			restricted[p] = ok and pol and pol.ArePaidRandomItemsRestricted == true
		end)
	end)
	Players.PlayerRemoving:Connect(function(p)
		restricted[p], lastCall[p] = nil, nil
	end)
end

return Shop
