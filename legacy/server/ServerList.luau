--!strict
-- Cross-server list + teleports for the main menu.
-- Every match server publishes { map, players, max, phase, ... } to a MemoryStore sorted
-- map (expires if the server dies). Solo servers are reserved and never listed.
-- Studio can't teleport: solo/create fall back to restarting this server's match.
local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local ServerList = {}
ServerList.solo = false
ServerList.code = nil :: string? -- access code when this is a reserved (created) server
ServerList.onLocalMap = nil :: ((mapId: string, solo: boolean) -> (boolean, string))?

local STORE = "TOTW_Servers_v1"
local TTL = 45
local map: MemoryStoreSortedMap? = nil
local cache: { any } = {}
local cacheAt = -math.huge

local function key(): string
	return if game.JobId ~= "" then game.JobId else "studio"
end

local function store(): MemoryStoreSortedMap?
	if not map then
		local ok, m = pcall(function()
			return MemoryStoreService:GetSortedMap(STORE)
		end)
		map = if ok then m else nil
	end
	return map
end

function ServerList.validMap(id: any): boolean
	return typeof(id) == "string" and Config.Maps[id] ~= nil and not Config.Maps[id].Hidden
end

-- info about this server (also used as the first menu row)
function ServerList.selfInfo(getState: () -> (string, string, number)): any
	local mapId, phase, maxHumans = getState()
	return {
		key = key(),
		map = mapId,
		players = #Players:GetPlayers(),
		max = maxHumans,
		phase = phase,
		here = true,
		solo = ServerList.solo,
	}
end

function ServerList.publish(getState: () -> (string, string, number))
	if ServerList.solo then
		return
	end
	local s = store()
	if not s then
		return
	end
	local info = ServerList.selfInfo(getState)
	info.here = nil
	info.code = ServerList.code
	info.placeId = game.PlaceId
	info.t = os.time()
	pcall(function()
		s:SetAsync(key(), info, TTL)
	end)
end

function ServerList.unpublish()
	local s = store()
	if s then
		pcall(function()
			s:RemoveAsync(key())
		end)
	end
end

function ServerList.list(): { any }
	if os.clock() - cacheAt < 8 then
		return cache
	end
	cacheAt = os.clock()
	local s = store()
	local out = {}
	if s then
		local ok, items = pcall(function()
			return s:GetRangeAsync(Enum.SortDirection.Ascending, 50)
		end)
		if ok and items then
			for _, it in items do
				local v = it.value
				if typeof(v) == "table" and it.key ~= key() and ServerList.validMap(v.map) then
					table.insert(out, { key = it.key, map = v.map, players = v.players or 0, max = v.max or 0, phase = v.phase or "?" })
				end
			end
		end
	end
	table.sort(out, function(a, b)
		return a.players > b.players
	end)
	cache = out
	return out
end

local function teleportTo(p: Player, placeId: number, code: string?, jobId: string?, data: any): (boolean, string)
	local opts = Instance.new("TeleportOptions")
	if code then
		opts.ReservedServerAccessCode = code
	elseif jobId then
		opts.ServerInstanceId = jobId
	end
	if data then
		opts:SetTeleportData(data)
	end
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(placeId, { p }, opts)
	end)
	return ok, if ok then "Teleporting…" else ("Teleport failed: " .. tostring(err))
end

-- new private server with a chosen map; solo servers have one human slot
function ServerList.host(p: Player, mapId: string, solo: boolean, diff: number?): (boolean, string)
	if not ServerList.validMap(mapId) then
		return false, "Unknown map"
	end
	if RunService:IsStudio() then
		if ServerList.onLocalMap then
			return ServerList.onLocalMap(mapId, solo, diff)
		end
		return false, "Not available in Studio"
	end
	local ok, code = pcall(function()
		return TeleportService:ReserveServer(game.PlaceId)
	end)
	if not ok then
		return false, "Couldn't create a server"
	end
	return teleportTo(p, game.PlaceId, code :: string, nil, { map = mapId, solo = solo, diff = diff, code = if solo then nil else code })
end

function ServerList.join(p: Player, k: any): (boolean, string)
	if typeof(k) ~= "string" or #k > 64 then
		return false, "Bad server"
	end
	if k == key() then
		return true, "here"
	end
	local s = store()
	if not s then
		return false, "Server list unavailable"
	end
	local ok, v = pcall(function()
		return s:GetAsync(k)
	end)
	if not ok or typeof(v) ~= "table" then
		return false, "That server closed"
	end
	if (v.players or 0) >= (v.max or 0) + 4 then
		return false, "That server is full"
	end
	return teleportTo(p, v.placeId or game.PlaceId, v.code, if v.code then nil else k, nil)
end

-- Matchmaking: join the fullest open server already running this map; if none,
-- generate a new public match server for it (listed so others can join).
function ServerList.matchmake(p: Player, mapId: string, here: any): (boolean, string)
	if not ServerList.validMap(mapId) then
		return false, "Unknown map"
	end
	if here.map == mapId and not ServerList.solo and here.players <= here.max then
		return true, "here"
	end
	if RunService:IsStudio() then
		if ServerList.onLocalMap then
			return ServerList.onLocalMap(mapId, false)
		end
		return false, "Not available in Studio"
	end
	cacheAt = -math.huge -- fresh list
	local best = nil
	for _, s in ServerList.list() do
		if s.map == mapId and s.players < s.max and (not best or s.players > best.players) then
			best = s
		end
	end
	if best then
		return ServerList.join(p, best.key)
	end
	return ServerList.host(p, mapId, false)
end

-- reserved servers learn their map from the first arrival's teleport data
function ServerList.readJoinData(p: Player): any
	local ok, jd = pcall(function()
		return p:GetJoinData()
	end)
	local data = ok and jd and jd.TeleportData
	if typeof(data) == "table" and ServerList.validMap(data.map) then
		return data
	end
	return nil
end

return ServerList
