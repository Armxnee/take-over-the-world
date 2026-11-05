--!strict
-- Persistent player profile (coins, owned cosmetics, equipped, wins).
-- Versioned schema; session lock via UpdateAsync so two servers can't both write;
-- autosave + save on leave + BindToClose. If DataStores are unavailable (Studio without
-- API access) the profile is kept in memory and marked offline (nothing is saved).
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)

local PlayerData = {}
PlayerData.onLoaded = nil :: ((p: Player) -> ())?

local SCHEMA = 1
local LOCK_STALE = 600 -- seconds
local store: DataStore? = nil
pcall(function()
	store = DataStoreService:GetDataStore("TOTW_Profiles_v1")
end)

export type Profile = {
	v: number,
	coins: number,
	owned: { [string]: boolean },
	equipped: { skin: string?, flag: string? },
	wins: number,
	matches: number,
	receipts: { string }, -- last processed purchase ids (idempotent receipts)
	rewardedRound: string?, -- last round id rewarded (retry-safe rewards)
	settings: { [string]: { [string]: any } }, -- interface settings by section (RoWorld UI)
}

local profiles: { [Player]: Profile } = {}
local offline: { [Player]: boolean } = {}

local function fresh(): Profile
	return {
		v = SCHEMA,
		coins = Cosmetics.Rewards.startCoins,
		owned = {},
		equipped = {},
		wins = 0,
		matches = 0,
		receipts = {},
		rewardedRound = nil,
		settings = {},
	}
end

local function migrate(d: any): Profile
	if typeof(d) ~= "table" then
		return fresh()
	end
	local p = fresh()
	p.coins = tonumber(d.coins) or p.coins
	p.owned = typeof(d.owned) == "table" and d.owned or {}
	p.equipped = typeof(d.equipped) == "table" and d.equipped or {}
	p.wins = tonumber(d.wins) or 0
	p.matches = tonumber(d.matches) or 0
	p.receipts = typeof(d.receipts) == "table" and d.receipts or {}
	p.rewardedRound = d.rewardedRound
	p.settings = typeof(d.settings) == "table" and d.settings or {}
	return p
end

local function key(p: Player): string
	return "u_" .. p.UserId
end

function PlayerData.get(p: Player): Profile?
	return profiles[p]
end

function PlayerData.isOffline(p: Player): boolean
	return offline[p] == true
end

local function load(p: Player)
	local data: any = nil
	local ok = false
	if store then
		for attempt = 1, 3 do
			ok = pcall(function()
				(store :: DataStore):UpdateAsync(key(p), function(old)
					old = old or {}
					local lock = old.lock
					if lock and lock.job ~= game.JobId and os.time() - (lock.t or 0) < LOCK_STALE then
						data = "locked"
						return nil -- don't write
					end
					old.lock = { job = game.JobId, t = os.time() }
					data = old.profile
					return old
				end)
			end)
			if ok and data ~= "locked" then
				break
			end
			task.wait(attempt * 2)
		end
	end
	if not p.Parent then
		return
	end
	if not ok or data == "locked" then
		offline[p] = true -- read-only session: spending works but won't persist
		profiles[p] = migrate(if data ~= "locked" then data else nil)
	else
		profiles[p] = migrate(data)
	end
	if PlayerData.onLoaded then
		PlayerData.onLoaded(p)
	end
end

-- returns true only when the profile was written
function PlayerData.save(p: Player, release: boolean?): boolean
	local prof = profiles[p]
	if not prof or offline[p] or not store then
		return false
	end
	local wrote = false
	local ok = pcall(function()
		(store :: DataStore):UpdateAsync(key(p), function(old)
			old = old or {}
			if old.lock and old.lock.job ~= game.JobId then
				return nil -- someone else owns the session now
			end
			old.profile = prof
			old.lock = if release then nil else { job = game.JobId, t = os.time() }
			wrote = true
			return old
		end)
	end)
	return ok and wrote
end

function PlayerData.init()
	Players.PlayerAdded:Connect(function(p)
		task.spawn(load, p)
	end)
	for _, p in Players:GetPlayers() do
		task.spawn(load, p)
	end
	Players.PlayerRemoving:Connect(function(p)
		PlayerData.save(p, true)
		profiles[p] = nil
		offline[p] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(60)
			for p in profiles do
				PlayerData.save(p, false)
			end
		end
	end)
	game:BindToClose(function()
		for p in profiles do
			PlayerData.save(p, true)
		end
	end)
end

return PlayerData
