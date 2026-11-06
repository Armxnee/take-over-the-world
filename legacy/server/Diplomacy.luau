--!strict
-- Alliances. A request lasts RequestTime; accepting forms the alliance and cancels
-- any fronts between the two (troops refunded). Breaking is an announced betrayal:
-- the pair stays allied (no attacks) for BreakGrace seconds, then becomes rivals.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Sim = require(script.Parent.Sim)

local D = Config.Diplomacy
local Diplomacy = {}
Diplomacy.changed = false
Diplomacy.onEvent = nil :: ((kind: string, a: number, b: number) -> ())?

-- Alliances last D.Duration seconds; either side can ask to renew (the other accepts).
-- pair key "lo:hi" -> { state = "allied" | "breaking", breakTick, by, expireTick }
local pairs_: { [string]: any } = {}
-- requests[from][to] = expiry tick
local requests: { [number]: { [number]: number } } = {}
-- cooldown after a decline: key "from:to" -> tick
local cooldown: { [string]: number } = {}

local function key(a: number, b: number): string
	return if a < b then a .. ":" .. b else b .. ":" .. a
end

local function emit(kind: string, a: number, b: number)
	Diplomacy.changed = true
	if Diplomacy.onEvent then
		Diplomacy.onEvent(kind, a, b)
	end
end

function Diplomacy.reset()
	pairs_ = {}
	requests = {}
	cooldown = {}
	Diplomacy.changed = true
end

function Diplomacy.allied(a: number, b: number): boolean
	return pairs_[key(a, b)] ~= nil
end

function Diplomacy.allyCount(a: number): number
	local c = 0
	for k in pairs_ do
		local x, y = k:match("^(%d+):(%d+)$")
		if tonumber(x) == a or tonumber(y) == a then
			c += 1
		end
	end
	return c
end

local function form(a: number, b: number)
	pairs_[key(a, b)] = { state = "allied", breakTick = 0, by = 0, expireTick = Sim.tick + D.Duration * Config.TickRate }
	if requests[a] then requests[a][b] = nil end
	if requests[b] then requests[b][a] = nil end
	-- fronts between allies end; survivors go home
	for _, att in table.clone(Sim.attacks) do
		if (att.attacker == a and att.target == b) or (att.attacker == b and att.target == a) then
			Sim.retreatFull(att)
		end
	end
	emit("formed", a, b)
end

function Diplomacy.request(from: number, to: number): (boolean, string)
	local A, B = Sim.nations[from], Sim.nations[to]
	if not A or not B or not A.alive or not B.alive or from == to then
		return false, "Pick another nation"
	end
	if B.kind == "tribe" then
		return false, "Tribes don't make alliances"
	end
	local p = pairs_[key(from, to)]
	if p then
		if p.state ~= "allied" then
			return false, "That alliance is ending"
		end
		-- renewal: the other side's pending renew (or an AI partner) seals it
		if (requests[to] and (requests[to][from] or 0) > Sim.tick) or B.kind == "nation" then
			return Diplomacy.renew(from, to)
		end
		requests[from] = requests[from] or {}
		requests[from][to] = Sim.tick + D.RequestTime * Config.TickRate
		emit("renewreq", from, to)
		return true, "Renewal sent to " .. B.name
	end
	if Diplomacy.allyCount(from) >= D.MaxAllies or Diplomacy.allyCount(to) >= D.MaxAllies then
		return false, ("Alliance limit is %d"):format(D.MaxAllies)
	end
	if (cooldown[from .. ":" .. to] or 0) > Sim.tick then
		return false, "They declined recently"
	end
	-- crossing requests accept each other
	if requests[to] and (requests[to][from] or 0) > Sim.tick then
		form(from, to)
		return true, "Alliance formed with " .. B.name
	end
	requests[from] = requests[from] or {}
	requests[from][to] = Sim.tick + D.RequestTime * Config.TickRate
	emit("requested", from, to)
	if B.kind == "nation" then
		-- AI answers on the spot: accept partners that are not much weaker and not at war with it
		local fighting = false
		for _, att in Sim.attacks do
			if (att.attacker == from and att.target == to) or (att.attacker == to and att.target == from) then
				fighting = true
			end
		end
		if not fighting and A.troops >= B.troops * D.AiAcceptRatio then
			form(from, to)
			return true, B.name .. " accepted the alliance"
		end
		Diplomacy.decline(to, from)
		return true, B.name .. " declined"
	end
	return true, "Alliance request sent to " .. B.name
end

function Diplomacy.renew(a: number, b: number): (boolean, string)
	local p = pairs_[key(a, b)]
	if not p or p.state ~= "allied" then
		return false, "You are not allied"
	end
	p.expireTick = Sim.tick + D.Duration * Config.TickRate
	p.warned = false
	if requests[a] then requests[a][b] = nil end
	if requests[b] then requests[b][a] = nil end
	emit("renewed", a, b)
	return true, "Alliance renewed for 5 minutes"
end

function Diplomacy.accept(me: number, from: number): (boolean, string)
	if not requests[from] or (requests[from][me] or 0) <= Sim.tick then
		return false, "That request expired"
	end
	if pairs_[key(me, from)] then
		return Diplomacy.renew(me, from)
	end
	if Diplomacy.allyCount(from) >= D.MaxAllies or Diplomacy.allyCount(me) >= D.MaxAllies then
		return false, ("Alliance limit is %d"):format(D.MaxAllies)
	end
	form(from, me)
	return true, "Alliance formed with " .. Sim.nations[from].name
end

function Diplomacy.decline(me: number, from: number): (boolean, string)
	if requests[from] then
		requests[from][me] = nil
	end
	cooldown[from .. ":" .. me] = Sim.tick + D.DeclineCooldown * Config.TickRate
	emit("declined", from, me)
	return true, "Declined"
end

-- announced betrayal: still allied until the grace period ends
function Diplomacy.breakWith(me: number, other: number): (boolean, string)
	local p = pairs_[key(me, other)]
	if not p then
		return false, "You are not allied"
	end
	if p.state == "breaking" then
		return false, "Already breaking"
	end
	p.state = "breaking"
	p.by = me
	p.breakTick = Sim.tick + D.BreakGrace * Config.TickRate
	emit("breaking", me, other)
	return true, ("Alliance ends in %ds"):format(D.BreakGrace)
end

-- a nation that is eliminated loses its alliances
function Diplomacy.drop(nid: number)
	for k in table.clone(pairs_) do
		local x, y = k:match("^(%d+):(%d+)$")
		if tonumber(x) == nid or tonumber(y) == nid then
			pairs_[k] = nil
			Diplomacy.changed = true
		end
	end
	requests[nid] = nil
end

function Diplomacy.step()
	for k, p in table.clone(pairs_) do
		local x, y = k:match("^(%d+):(%d+)$")
		local a, b = tonumber(x) :: number, tonumber(y) :: number
		if p.state == "breaking" and Sim.tick >= p.breakTick then
			pairs_[k] = nil
			emit("ended", p.by, if p.by == a then b else a)
		elseif p.state == "allied" and Sim.tick >= p.expireTick then
			pairs_[k] = nil
			emit("expired", a, b)
		elseif p.state == "allied" and not p.warned and Sim.tick >= p.expireTick - D.RenewWarn * Config.TickRate then
			p.warned = true
			Diplomacy.changed = true
		end
	end
	-- expire requests
	for from, list in requests do
		for to, exp in table.clone(list) do
			if exp <= Sim.tick then
				list[to] = nil
				Diplomacy.changed = true
			end
		end
	end
end

-- replication: { pairs = { {a, b, state, breakAt(server time), by, expiresAt} }, requests = { {from, to, expiresAt} } }
function Diplomacy.rows(now: number): any
	local out = { pairs = {}, requests = {} }
	for k, p in pairs_ do
		local x, y = k:match("^(%d+):(%d+)$")
		table.insert(out.pairs, { tonumber(x), tonumber(y), p.state, now + math.max(0, p.breakTick - Sim.tick) / Config.TickRate, p.by, now + math.max(0, p.expireTick - Sim.tick) / Config.TickRate })
	end
	for from, list in requests do
		for to, exp in list do
			table.insert(out.requests, { from, to, now + (exp - Sim.tick) / Config.TickRate })
		end
	end
	return out
end

Sim.allied = Diplomacy.allied

return Diplomacy
