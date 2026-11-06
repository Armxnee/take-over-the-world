--!strict
-- Trade: factories send trains over friendly land to cities/ports/factories;
-- ports send trade ships to other nations' ports. Gold is paid on arrival.
-- A train whose next cell is no longer friendly is lost ("trade interrupted").
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Sim = require(script.Parent.Sim)
local Structures = require(script.Parent.Structures)
local Units = require(script.Parent.Units)
local Path = require(script.Parent.Path)

local T = Config.Trade
local Trade = {}
Trade.onInterrupted = nil :: ((owner: number) -> ())?

local nextDue: { [number]: number } = {} -- structure id -> tick
-- uncached path searches allowed per tick (keeps tick time flat)
local seaBudget, railBudget = 0, 0
local railCache: { [string]: { number } } = {}
local seaCache: { [string]: { number } | false } = {}

function Trade.reset()
	nextDue = {}
	railCache = {}
	seaCache = {}
end

local function pay(nid: number, amount: number)
	local n = Sim.nations[nid]
	if n and n.alive then
		n.gold += amount
		n.income.trade += amount
	end
end

local function railPath(a: any, b: any): ({ number }?, boolean)
	local key = a.id .. ":" .. b.id
	local owner = a.owner
	local function ok(j: number): boolean
		return Sim.isClaimable(j) and Sim.friendly(owner, Sim.ownerAt(j))
	end
	local cached = railCache[key]
	if cached then
		local valid = true
		for _, c in cached do
			if not ok(c) then
				valid = false
				break
			end
		end
		if valid then
			return cached, false
		end
	end
	if railBudget <= 0 then
		return nil, true
	end
	railBudget -= 1
	local p = Path.find(a.cell, b.cell, ok, 6000)
	if p then
		railCache[key] = p
	end
	return p, false
end

local function seaPath(a: any, b: any): ({ number }?, boolean)
	local key = a.id .. ":" .. b.id
	local cached = seaCache[key]
	if cached ~= nil then
		return cached or nil, false
	end
	if seaBudget <= 0 then
		return nil, true -- try again next tick
	end
	seaBudget -= 1
	local wa, wb = Path.waterBeside(a.cell), Path.waterBeside(b.cell)
	local p = nil
	if wa and wb and buffer.readu32(Sim.water, wa * 4) == buffer.readu32(Sim.water, wb * 4) then
		p = Path.find(wa, wb, function(j)
			return Sim.terrAt(j) == 0
		end, 25000, 3)
	end
	seaCache[key] = p or false
	return p, false
end

local function due(s: any, interval: number, rng: Random): boolean
	local t = nextDue[s.id]
	if not t then
		-- stagger first departures
		nextDue[s.id] = Sim.tick + math.floor(rng:NextNumber() * interval * Config.TickRate)
		return false
	end
	if Sim.tick < t then
		return false
	end
	nextDue[s.id] = Sim.tick + math.floor(interval * Config.TickRate)
	return true
end

local function sendTrain(f: any, rng: Random)
	local W = Sim.W
	local fx, fy = f.cell % W, f.cell // W
	local options = {}
	for _, s in Structures.list do
		if s.id ~= f.id and s.done and (s.kind == "city" or s.kind == "port" or s.kind == "factory")
			and Sim.friendly(f.owner, s.owner)
			and (s.cell % W - fx) ^ 2 + (s.cell // W - fy) ^ 2 <= T.MaxRail * T.MaxRail then
			options[#options + 1] = s
		end
	end
	if #options == 0 then
		return
	end
	local dest = options[rng:NextInteger(1, #options)]
	local p, deferred = railPath(f, dest)
	if deferred then
		nextDue[f.id] = Sim.tick + 1
		return
	end
	if p and #p > 1 then
		Units.spawn("train", f.owner, p, T.TrainSpeed, { dest = dest.id, len = #p })
	end
end

local function sendShip(port: any, rng: Random)
	local options = {}
	for _, s in Structures.list do
		if s.kind == "port" and s.done and s.owner ~= port.owner then
			options[#options + 1] = s
		end
	end
	-- a few tries: some ports sit on other oceans
	for _ = 1, 3 do
		if #options == 0 then
			return
		end
		local k = rng:NextInteger(1, #options)
		local dest = options[k]
		local p, deferred = seaPath(port, dest)
		if deferred then
			nextDue[port.id] = Sim.tick + 1
			return
		end
		if p and #p > 1 then
			Units.spawn("trade", port.owner, p, T.ShipSpeed, { from = port.id, dest = dest.id, len = #p }, 1)
			return
		end
		table.remove(options, k)
	end
end

function Trade.step()
	local rng = Sim.rng()
	seaBudget, railBudget = 1, 2
	for _, s in Structures.list do
		if s.done and s.disabledUntil <= Sim.tick then
			if s.kind == "factory" and due(s, T.TrainInterval, rng) then
				sendTrain(s, rng)
			elseif s.kind == "port" and due(s, T.ShipInterval, rng) then
				sendShip(s, rng)
			end
		end
	end
end

Units.handlers.train = {
	onCell = function(u, cell)
		if not Sim.friendly(u.owner, Sim.ownerAt(cell)) then
			Units.remove(u, "interrupted")
			if Trade.onInterrupted then
				Trade.onInterrupted(u.owner)
			end
			return false
		end
		return true
	end,
	onArrive = function(u)
		local dest = Structures.list[u.data.dest]
		if dest and Sim.friendly(u.owner, dest.owner) then
			local g = T.TrainBase + T.TrainPerCell * u.data.len
			pay(u.owner, g)
			if dest.owner ~= u.owner then
				pay(dest.owner, g * 0.5)
			end
			Units.remove(u, "delivered")
		else
			Units.remove(u, "lost")
		end
	end,
}

Units.handlers.trade = {
	onArrive = function(u)
		local dest = Structures.list[u.data.dest]
		if dest and dest.kind == "port" then
			local g = T.ShipBase + T.ShipPerCell * u.data.len
			pay(u.owner, g)
			pay(dest.owner, g)
			Units.remove(u, "delivered")
		else
			Units.remove(u, "lost")
		end
	end,
}

return Trade
