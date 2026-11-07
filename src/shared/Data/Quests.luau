--!strict
-- (Take Over the World!: daily and weekly quests, 2026-11-06; they replace the Arsenal.)
-- Three daily and three weekly quests, picked from the pools below by the UTC day / week number (the
-- same for everyone). Progress comes from the results of finished matches (Data/Stars results: the
-- same numbers that pay a match's coins); a completed quest is claimed for coins. Server-side:
-- server/Purchases keeps progress and claims in the player's record.
--
--   kinds: play (matches finished), win (matches won), kills (nations conquered), minutes (minutes
--   alive), land (matches ending with at least `shares` fair shares of land at their peak)
local Quests = {}

Quests.DAILY_COUNT = 3
Quests.WEEKLY_COUNT = 3

Quests.DAILY = {
	{ id = "d_play2", text = "Finish 2 matches", kind = "play", goal = 2, reward = 600 },
	{ id = "d_play3", text = "Finish 3 matches", kind = "play", goal = 3, reward = 900 },
	{ id = "d_win1", text = "Win a match", kind = "win", goal = 1, reward = 1200 },
	{ id = "d_kills3", text = "Conquer 3 nations", kind = "kills", goal = 3, reward = 800 },
	{ id = "d_kills5", text = "Conquer 5 nations", kind = "kills", goal = 5, reward = 1200 },
	{ id = "d_min20", text = "Survive 20 minutes in total", kind = "minutes", goal = 20, reward = 700 },
	{ id = "d_land2", text = "End a match with 2x a fair share of land", kind = "land", shares = 2, goal = 1, reward = 900 },
}

Quests.WEEKLY = {
	{ id = "w_play15", text = "Finish 15 matches", kind = "play", goal = 15, reward = 4000 },
	{ id = "w_win5", text = "Win 5 matches", kind = "win", goal = 5, reward = 6000 },
	{ id = "w_kills30", text = "Conquer 30 nations", kind = "kills", goal = 30, reward = 5000 },
	{ id = "w_min180", text = "Survive 180 minutes in total", kind = "minutes", goal = 180, reward = 5000 },
	{ id = "w_land5", text = "End 3 matches with 5x a fair share of land", kind = "land", shares = 5, goal = 3, reward = 6000 },
}

local by_id: { [string]: any } = {}
for _, q in Quests.DAILY do
	q.period = "daily"
	by_id[q.id] = q
end
for _, q in Quests.WEEKLY do
	q.period = "weekly"
	by_id[q.id] = q
end

function Quests.get(id: string): any?
	return by_id[id]
end

function Quests.day(t: number): number
	return math.floor(t / 86400)
end

function Quests.week(t: number): number
	return math.floor((t / 86400 + 3) / 7) -- (weeks start on Monday, UTC)
end

-- `n` distinct quests of `pool`, picked by `seed` (deterministic)
local function pick(pool: { any }, n: number, seed: number): { any }
	local idx = {}
	for i = 1, #pool do
		idx[i] = i
	end
	local x = seed * 2654435761 % 4294967296
	for i = #idx, 2, -1 do
		x = (x * 1103515245 + 12345) % 2147483648
		local j = x % i + 1
		idx[i], idx[j] = idx[j], idx[i]
	end
	local out = {}
	for i = 1, math.min(n, #idx) do
		table.insert(out, pool[idx[i]])
	end
	return out
end

--- The quests active at time `t` (seconds, UTC): daily ones then weekly ones.
function Quests.active(t: number): { any }
	local out = {}
	for _, q in pick(Quests.DAILY, Quests.DAILY_COUNT, Quests.day(t)) do
		table.insert(out, q)
	end
	for _, q in pick(Quests.WEEKLY, Quests.WEEKLY_COUNT, Quests.week(t) + 7919) do
		table.insert(out, q)
	end
	return out
end

--- How much a match result advances quest `q`.
function Quests.progress_of(q: any, r: any): number
	if not r.spawned then
		return 0
	end
	if q.kind == "play" then
		return if r.left then 0 else 1
	elseif q.kind == "win" then
		return if r.won and not r.left then 1 else 0
	elseif q.kind == "kills" then
		return math.max(0, math.floor(r.kills or 0))
	elseif q.kind == "minutes" then
		return math.max(0, math.floor(r.minutes or 0))
	elseif q.kind == "land" then
		return if (r.shares or 0) >= (q.shares or 1) then 1 else 0
	end
	return 0
end

return Quests
