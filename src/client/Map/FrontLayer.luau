--!native
-- Troop counts on the local player's fronts (a label per attack front, floating over the map):
-- every 200 ms, for each attack by the local player on another owner (blue
-- #3fa9f5) and each attack on the local player by a player or nation, not a tribe (red #f87171),
-- the front is split into connected clusters (8-neighbours); the two largest (clusters under 30
-- full-size tiles dropped, the largest always kept) get a label with the attack's troops
-- (render_troops) at the front tile nearest the cluster's centroid. Labels glide to new positions
-- over 250 ms (snap beyond 200 full-size tiles) and keep a constant on-screen size.
--
-- The front: the label belongs on the attack's frontier, the whole shared border; the
-- client has no frontier, so it uses the local player's border tiles (UI BorderTracker, handed
-- over with set_borders) that touch the other owner.
-- (2026-10-26, phones' slow frames: a poll works in tables kept from one poll to the next, and a label
-- is written only what changed.)
local RS = game:GetService("ReplicatedStorage")
local Airfront = RS:WaitForChild("Airfront")
local Core = Airfront:WaitForChild("Core")
local Defs = require(Core:WaitForChild("Defs")) :: any
local Rules = require(Core:WaitForChild("Rules")) :: any
local NumberFormat = require(Core:WaitForChild("NumberFormat")) :: any
local FrameClock = require(script.Parent:WaitForChild("FrameClock")) :: any
local Countries = require(Airfront:WaitForChild("Data"):WaitForChild("Countries")) :: any -- (Take Over the World!: soldiers)
local Countryball = require("../UI/Countryball")
local BattleFx = require(script.Parent:WaitForChild("BattleFx")) :: any -- (the shots and blasts)

local FrontLayer = {}
FrontLayer.__index = FrontLayer

FrontLayer.POLL_S = 0.2
FrontLayer.ANIM_S = 0.25
FrontLayer.SNAP_FULL = 200 -- full-size tiles
FrontLayer.MIN_CLUSTER_FULL = 30 -- full-size tiles
FrontLayer.MAX_CLUSTERS = 2
FrontLayer.OUTGOING = Color3.fromRGB(0x3f, 0xa9, 0xf5)
FrontLayer.INCOMING = Color3.fromRGB(0xf8, 0x71, 0x71)
FrontLayer.TEXT_PX = 17
FrontLayer.FONT = Font.fromId(12187365977, Enum.FontWeight.Bold)
FrontLayer.Z = 24
-- (Take Over the World!, 2026-11-08: squads of mini Countryball soldiers from every defense post in
-- view; they roam their country and fire across a border when the two countries are at war)
FrontLayer.SOLDIER_PX = 32 -- (Countryball.MINI 16 px at exactly 2x: a round ball)
FrontLayer.FIRE_MIN, FrontLayer.FIRE_MAX = 0.6, 1.5 -- seconds between a soldier's shots
FrontLayer.MAX_POSTS = 16 -- squads at once (the posts nearest the middle of the screen)
FrontLayer.SQUAD = 3 -- soldiers a post
FrontLayer.POST_POLL_S = 0.5
FrontLayer.ROAM_FULL = 40 -- full-size tiles from its post a soldier roams
FrontLayer.FIGHT_FULL = 4 -- full-size tiles from enemy land a soldier stops to fight
FrontLayer.WALK_FULL = 3.5 -- full-size tiles a second
FrontLayer.AIM_PX = 90 -- an enemy soldier this close is shot at instead of the border
FrontLayer.MIN_SCALE = 1.6 -- px a map tile: zoomed out further, no soldiers
-- (2026-11-09, the user) while the player attacks a country, the player's squads move with the front
FrontLayer.FOLLOW_FULL = 120 -- full-size tiles from a soldier the front may be to pull it along
FrontLayer.RUSH = 2.2 -- walking speed x, catching up with the front
FrontLayer.GAP_PX = 26 -- on-screen room kept between soldiers on the front

type Slot = { cx: number, cy: number, sx: number, sy: number, dx: number, dy: number, t0: number }
type Entry = { text: string, incoming: boolean, slots: { Slot }, seen: boolean }
--- A label and what it was last given (Roblox's own values, kept here).
type Label = { label: TextLabel, vis: boolean, text: string?, incoming: boolean?, x: number, y: number }
--- An attack worth a label, this poll.
type Todo = { aid: number, other: number, incoming: boolean, troops: number }

function FrontLayer.new(parent: Instance, view: any)
	local self = setmetatable({}, FrontLayer) :: any
	local root = Instance.new("Frame")
	root.Name = "Fronts"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = FrontLayer.Z
	root.Parent = parent
	self.root = root
	self.view = view
	self._state = nil :: any
	self._borders = nil :: any
	--- aid -> label entry
	self._entries = {} :: { [number]: Entry }
	self._labels = {} :: { Label }
	self._bfx = BattleFx.new(root, FrontLayer.Z) -- (the shots, shells and blasts)
	self._posts = {} -- (the border posts)
	self._post_poll = 0.0
	self._poll = 0.0
	--- (a poll's working tables: the owners wanted, the attacks (records reused), owner -> front
	--- tiles (an empty list: none))
	self._wanted = {} :: { [number]: boolean }
	self._todo = {} :: { Todo }
	self._fronts = {} :: { [number]: { number } }
	return self
end

function FrontLayer.bind(self: any, state: any)
	self._state = state
	table.clear(self._entries)
	self._poll = 0.0
end

function FrontLayer.unbind(self: any)
	self._state = nil
	table.clear(self._entries)
	for _, l in self._labels do
		l.vis = false
		l.label.Visible = false
	end
	for _, p in self._posts do -- (Take Over the World!: the border posts go with the match)
		for _, sd in p.soldiers do
			sd.img:Destroy()
		end
	end
	table.clear(self._posts)
	self._bfx:clear()
end

function FrontLayer.destroy(self: any)
	self:unbind()
	self.root:Destroy()
end

--- The UI's BorderTracker (its `border` set holds the local player's border tiles).
function FrontLayer.set_borders(self: any, tracker: any)
	self._borders = tracker
end

--- Border tiles of the local player touching each owner in `wanted`, into `out`: owner -> { tile }
--- (its lists emptied first and kept; an owner with none has an empty list or none).
local function fronts_by_owner(
	st: any,
	border: { [number]: boolean },
	wanted: { [number]: boolean },
	out: { [number]: { number } }
)
	for _, list in out do
		table.clear(list)
	end
	local W = st.map.W or Defs.W
	local N = st.map.N or (W * (st.map.H or Defs.H))
	for t in border do
		local x = t % W
		local hit = 0
		local o = 0
		if x > 0 then
			o = st:tile_owner(t - 1)
			if wanted[o] then
				hit = o
			end
		end
		if hit == 0 and x < W - 1 then
			o = st:tile_owner(t + 1)
			if wanted[o] then
				hit = o
			end
		end
		if hit == 0 and t >= W then
			o = st:tile_owner(t - W)
			if wanted[o] then
				hit = o
			end
		end
		if hit == 0 and t + W < N then
			o = st:tile_owner(t + W)
			if wanted[o] then
				hit = o
			end
		end
		if hit ~= 0 then
			local list = out[hit]
			if list == nil then
				list = {}
				out[hit] = list
			end
			table.insert(list, t)
		end
	end
end

-- clusters()'s working tables, kept (it runs for each front every POLL_S): the tiles, those reached,
-- one cluster's queue, the clusters found (records reused from c_pool) and the result
local c_set: { [number]: boolean } = {}
local c_seen: { [number]: boolean } = {}
local c_queue: { number } = {}
local c_found: { { tile: number, size: number } } = {}
local c_pool: { { tile: number, size: number } } = {}
local c_out: { number } = {}

local function by_size(a: { tile: number, size: number }, b: { tile: number, size: number }): boolean
	return a.size > b.size
end

--- Representative tiles of the largest connected clusters of `tiles` (the list is reused by the
--- next call).
local function clusters(tiles: { number }, W: number, min_size: number, max_n: number): { number }
	local set, seen, queue, found = c_set, c_seen, c_queue, c_found
	table.clear(set)
	table.clear(seen)
	table.clear(found)
	for _, t in tiles do
		set[t] = true
	end
	for _, start in tiles do
		if seen[start] then
			continue
		end
		seen[start] = true
		table.clear(queue)
		queue[1] = start
		local qi = 1
		local sx, sy = 0, 0
		while qi <= #queue do
			local t = queue[qi]
			qi += 1
			local x = t % W
			sx += x
			sy += t // W
			for dy = -1, 1 do
				for dx = -1, 1 do
					if dx == 0 and dy == 0 then
						continue
					end
					local nx = x + dx
					if nx < 0 or nx >= W then
						continue
					end
					local n = t + dy * W + dx
					if set[n] and not seen[n] then
						seen[n] = true
						table.insert(queue, n)
					end
				end
			end
		end
		local count = #queue
		local cx, cy = sx / count, sy / count
		local best, bd = queue[1], math.huge
		for _, t in queue do
			local ddx, ddy = t % W - cx, t // W - cy
			local d = ddx * ddx + ddy * ddy
			if d < bd then
				bd = d
				best = t
			end
		end
		local nf = #found + 1
		local rec = c_pool[nf]
		if rec == nil then
			rec = { tile = 0, size = 0 }
			c_pool[nf] = rec
		end
		rec.tile, rec.size = best, count
		found[nf] = rec
	end
	table.sort(found, by_size)
	local out = c_out
	table.clear(out)
	for i, c in found do
		if #out >= max_n then
			break
		end
		if i == 1 or c.size >= min_size then
			table.insert(out, c.tile)
		end
	end
	return out
end

--- (Take Over the World!) Which way the front faces at tile `t`: the unit vector from the player's
--- land around it to the other owner's (an 11 x 11 window), so each side's soldiers stand on their
--- own land facing the enemy.
local function front_dir(st: any, t: number, W: number, me: number, other: number): (number, number)
	local N = st.map.N or (W * (st.map.H or Defs.H))
	local tx, ty = t % W, t // W
	local mx, my, mn, ex, ey, en = 0, 0, 0, 0, 0, 0
	for dy = -5, 5 do
		for dx = -5, 5 do
			local x, y = tx + dx, ty + dy
			if x >= 0 and x < W and y >= 0 then
				local i = y * W + x
				if i < N then
					local o = st:tile_owner(i)
					if o == me then
						mx += dx
						my += dy
						mn += 1
					elseif o == other then
						ex += dx
						ey += dy
						en += 1
					end
				end
			end
		end
	end
	if mn == 0 or en == 0 then
		return 1, 0
	end
	local vx, vy = ex / en - mx / mn, ey / en - my / mn
	local l = math.sqrt(vx * vx + vy * vy)
	if l < 1e-3 then
		return 1, 0
	end
	return vx / l, vy / l
end

--- A slot's distance to tile `t`'s centre (map units, Manhattan).
local function slot_dist(s: Slot, t: number, W: number): number
	return math.abs(s.dx - (t % W + 0.5)) + math.abs(s.dy - (t // W + 0.5))
end

function FrontLayer._poll_fronts(self: any, now: number)
	local st = self._state
	local me = if st ~= nil then st.local_owner else 0
	local tracker = self._borders
	for _, e in self._entries do
		e.seen = false
	end
	if st == nil or me == 0 or tracker == nil or tracker.me ~= me then
		table.clear(self._entries)
		return
	end
	-- attacks worth a label (outgoing on players, incoming from non-tribe players)
	local wanted = self._wanted
	table.clear(wanted)
	local todo = self._todo
	local todo_n = 0
	for aid, a in st.attacks do
		local other = 0
		local incoming = false
		if a.attacker == me and a.target ~= 0 then
			other = a.target
		elseif a.target == me and a.attacker ~= 0 then
			local o = st:get_owner(a.attacker)
			if o ~= nil and o.kind ~= Defs.KIND_TRIBE then
				other = a.attacker
				incoming = true
			end
		end
		if other ~= 0 then
			wanted[other] = true
			todo_n += 1
			local rec = todo[todo_n]
			if rec == nil then
				rec = {} :: any
				todo[todo_n] = rec
			end
			rec.aid, rec.other, rec.incoming, rec.troops = aid, other, incoming, a.troops
		end
	end
	if todo_n > 0 then
		local k = tonumber(st.map.k_lin) or Rules.K_LIN
		local W = st.map.W or Defs.W
		local fronts = self._fronts
		fronts_by_owner(st, tracker.border, wanted, fronts)
		local snap = FrontLayer.SNAP_FULL / k
		for ti = 1, todo_n do
			local a = todo[ti]
			local tiles = fronts[a.other]
			if tiles == nil or #tiles == 0 then
				continue
			end
			local reps = clusters(tiles, W, FrontLayer.MIN_CLUSTER_FULL / k, FrontLayer.MAX_CLUSTERS)
			local e = self._entries[a.aid]
			if e == nil then
				e = { text = "", incoming = a.incoming, slots = {}, seen = true }
				self._entries[a.aid] = e
			end
			e.seen = true
			e.incoming = a.incoming
			e.other = a.other
			e.text = NumberFormat.render_troops(a.troops)
			local slots = e.slots
			-- keep two labels on their own clusters (swapped when that is shorter)
			if #reps == 2 and #slots == 2 then
				local s1, s2 = slots[1], slots[2]
				if
					slot_dist(s1, reps[2], W) + slot_dist(s2, reps[1], W)
					< slot_dist(s1, reps[1], W) + slot_dist(s2, reps[2], W)
				then
					reps[1], reps[2] = reps[2], reps[1]
				end
			end
			while #slots > #reps do
				table.remove(slots)
			end
			for i, t in reps do
				local nx, ny = t % W + 0.5, t // W + 0.5
				local ux, uy = front_dir(st, t, W, me, a.other)
				local s = slots[i]
				if s == nil then
					slots[i] = { cx = nx, cy = ny, sx = nx, sy = ny, dx = nx, dy = ny, t0 = now, ux = ux, uy = uy } :: any
					continue
				end
				local sa = s :: any
				sa.ux, sa.uy = ux, uy
				local f = math.min(1, (now - s.t0) / FrontLayer.ANIM_S)
				local cx, cy = s.sx + (s.dx - s.sx) * f, s.sy + (s.dy - s.sy) * f
				if math.sqrt((nx - cx) ^ 2 + (ny - cy) ^ 2) > snap then
					cx, cy = nx, ny
				end
				s.sx, s.sy, s.cx, s.cy = cx, cy, cx, cy
				s.dx, s.dy, s.t0 = nx, ny, now
			end
		end
	end
	for aid, e in self._entries do
		if not e.seen then
			self._entries[aid] = nil
		end
	end
end

local function label(self: any, n: number): Label
	local rec = self._labels[n]
	if rec ~= nil then
		return rec
	end
	local l = Instance.new("TextLabel")
	l.Name = "FrontTroops"
	l.BackgroundTransparency = 1
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.AutomaticSize = Enum.AutomaticSize.XY
	l.Size = UDim2.fromOffset(0, 0)
	l.FontFace = FrontLayer.FONT
	l.TextSize = FrontLayer.TEXT_PX
	l.ZIndex = FrontLayer.Z
	l.Parent = self.root
	local s = Instance.new("UIStroke")
	s.Color = Color3.new(0, 0, 0)
	s.Thickness = 1.5
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = l
	rec = { label = l, vis = true, text = nil, incoming = nil, x = math.huge, y = math.huge }
	self._labels[n] = rec
	return rec :: Label
end

-- ===== (Take Over the World!) the soldiers: mini Countryballs and their shots =====

--- An owner's name and flag code (the flags by name are read once a map).
local function owner_flag(self: any, owner: number): (string?, string?)
	local st = self._state
	local o = st and st:get_owner(owner)
	if o == nil then
		return nil, nil
	end
	if self._flags_map ~= st.map then
		self._flags_map = st.map
		local ok, f = pcall(Countries.flags_by_name, st.map)
		self._flags = if ok then f else {}
	end
	return self._flags[o.name], o.name
end

--- An owner's soldier facing right or left: a little round Countryball (Countryball.mini_content,
--- 16 px shown at exactly 2x so the circle stays round) with a helmet and a rifle aiming that way.
local function soldier_art(self: any, owner: number, right: boolean): Content?
	local code, name = owner_flag(self, owner)
	if name == nil then
		return nil
	end
	return Countryball.mini_content(code, name, right)
end

--- One rifle shot (Map/BattleFx): a muzzle flash, a tracer flying across, a spark where it lands.
local function fire(self: any, now: number, x0: number, y0: number, x1: number, y1: number)
	self._bfx:shot(now, x0, y0, x1, y1)
end

local function fx_tick(self: any, now: number)
	self._bfx:tick(now)
end

local function pixel_image(self: any, name: string, px: number, z: number): ImageLabel
	local img = Instance.new("ImageLabel")
	img.Name = name
	img.BackgroundTransparency = 1
	img.AnchorPoint = Vector2.new(0.5, 0.5)
	img.ResampleMode = Enum.ResamplerMode.Pixelated
	img.Size = UDim2.fromOffset(px, px)
	img.ZIndex = z
	img.Parent = self.root
	return img
end

-- ===== (Take Over the World!) the defense posts' soldiers =====
-- (2026-11-08, reworked the same day after the user) Every defense post in view, the player's and the
-- AI's, sends out a squad of mini Countryball soldiers. They roam their own country around the post,
-- walking from spot to spot and mostly to its borders; one that reaches a border with a country its
-- owner is at war with (an attack either way) stops, faces it and fires across, at an enemy soldier
-- when one is near. Zoomed far out (MIN_SCALE) none show. (2026-11-09) While the player attacks a
-- country, the player's squads within FOLLOW_FULL of that front walk out to it, spread along it, and
-- move on with it as the land is taken (RUSH speed), fighting wherever they stand on it.

local function post_soldier(self: any): ImageLabel
	return pixel_image(self, "Patrol", FrontLayer.SOLDIER_PX, FrontLayer.Z - 2)
end

local function drop_post(self: any, i: number)
	local p = self._posts[i]
	for _, sd in p.soldiers do
		sd.img:Destroy()
	end
	table.remove(self._posts, i)
end

local function drop_posts(self: any)
	for i = #self._posts, 1, -1 do
		drop_post(self, i)
	end
end

local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }

--- The nearest tile within `reach` (8 ways) of an owner `owner` is at war with: (u, v) of its centre.
local function enemy_near(st: any, tile: number, W: number, N: number, owner: number, reach: number, war: any): (number?, number?)
	local tx, ty = tile % W, tile // W
	local best, bu, bv = math.huge, nil, nil
	for _, d in DIRS do
		for k = 1, reach do
			local x, y = tx + d[1] * k, ty + d[2] * k
			if x < 0 or x >= W or y < 0 then
				break
			end
			local t = y * W + x
			if t >= N then
				break
			end
			local o = st:tile_owner(t)
			if o ~= owner then
				if o ~= 0 and war[owner * 65536 + o] and k < best then
					best, bu, bv = k, x + 0.5, y + 0.5
				end
				break
			end
		end
	end
	return bu, bv
end

--- Somewhere for a soldier to walk to: a tile of `owner`'s within `r` tiles of its post, a border tile
--- when one turns up (most of the time), else the post itself.
local function roam_target(st: any, post: number, W: number, N: number, owner: number, r: number): (number, number)
	local px, py = post % W, post // W
	local inner = nil
	for _ = 1, 18 do
		local a = math.random() * math.pi * 2
		local d = r * math.sqrt(math.random())
		local x, y = math.floor(px + math.cos(a) * d), math.floor(py + math.sin(a) * d)
		if x >= 0 and x < W and y >= 0 then
			local t = y * W + x
			if t < N and st:tile_owner(t) == owner then
				local edge = false
				for _, nb in { t - 1, t + 1, t - W, t + W } do
					if nb >= 0 and nb < N and st:tile_owner(nb) ~= owner then
						edge = true
						break
					end
				end
				if edge and math.random() < 0.8 then
					return x + 0.5, y + 0.5
				end
				inner = inner or { x + 0.5, y + 0.5 }
			end
		end
	end
	if inner ~= nil then
		return inner[1], inner[2]
	end
	return px + 0.5, py + 0.5
end

--- The nearest tile to (u, v) within `r` tiles on the player's front with a country it attacks (`lists`:
--- FrontLayer._fronts' tile lists), at least `gap` tiles from every spot in `taken` (u1, v1, u2, v2...).
local function front_spot(lists: { { number } }, W: number, u: number, v: number, r: number, gap: number, taken: { number }): (number?, number?)
	local best, bu, bv = r * r, nil, nil
	local g2 = gap * gap
	for _, list in lists do
		for _, t in list do
			local x, y = t % W + 0.5, t // W + 0.5
			local d = (x - u) ^ 2 + (y - v) ^ 2
			if d < best then
				local free = true
				for i = 1, #taken, 2 do
					if (taken[i] - x) ^ 2 + (taken[i + 1] - y) ^ 2 < g2 then
						free = false
						break
					end
				end
				if free then
					best, bu, bv = d, x, y
				end
			end
		end
	end
	return bu, bv
end

--- Keeps a squad at each defense post in view (any owner's, up to MAX_POSTS, nearest the middle of the
--- screen first) and gives each soldier its next walk or its fight.
local function post_poll(self: any, now: number)
	local st = self._state
	local cam = self.view.rig
	local me = if st ~= nil then st.local_owner or 0 else 0
	-- (only in a match the player is in, not on the title screen's live world; none zoomed far out)
	if st == nil or st.map == nil or st.phase ~= Defs.PHASE_PLAYING or me == 0 or cam.scale < FrontLayer.MIN_SCALE then
		drop_posts(self)
		return
	end
	local W = st.map.W or Defs.W
	local N = st.map.N or (W * (st.map.H or Defs.H))
	local k = tonumber(st.map.k_lin) or Rules.K_LIN
	local roam = math.max(6, FrontLayer.ROAM_FULL / k)
	local reach = math.max(2, math.ceil(FrontLayer.FIGHT_FULL / k))
	-- the owners at war with each other (an attack either way)
	local war = self._war or {}
	self._war = war
	table.clear(war)
	for _, a in st.attacks do
		if a.attacker ~= 0 and a.target ~= 0 then
			war[a.attacker * 65536 + a.target] = true
			war[a.target * 65536 + a.attacker] = true
		end
	end
	-- (2026-11-09) the player's fronts with the countries it attacks (filled by _poll_fronts): its squads
	-- walk out to them and move on with them as the land is taken
	local follow: { { number } }? = nil
	for _, a in st.attacks do
		if a.attacker == me and a.target ~= 0 then
			local list = self._fronts[a.target]
			if list ~= nil and #list > 0 then
				follow = follow or {}
				table.insert(follow :: any, list)
			end
		end
	end
	local follow_r = FrontLayer.FOLLOW_FULL / k
	local gap = math.clamp(FrontLayer.GAP_PX / math.max(cam.scale, 0.01), 1, 20)
	local vp = cam._vp or Vector2.new(1280, 720)
	local cands = {}
	for sid, s in st.structures do
		if s.kind == Defs.S_DEFENSE and s.owner ~= 0 then
			local x, y = cam:tile_to_screen(s.tile)
			if cam:on_screen(x, y, 120) then
				table.insert(cands, { sid = sid, s = s, d = (x - vp.X / 2) ^ 2 + (y - vp.Y / 2) ^ 2 })
			end
		end
	end
	table.sort(cands, function(a, b)
		return a.d < b.d
	end)
	local wanted = {}
	for i = 1, math.min(#cands, FrontLayer.MAX_POSTS) do
		wanted[cands[i].sid] = cands[i].s
	end
	for i = #self._posts, 1, -1 do
		if wanted[self._posts[i].sid] == nil then
			drop_post(self, i)
		end
	end
	local have = {}
	for _, p in self._posts do
		have[p.sid] = p
	end
	for sid, s in wanted do
		local p = have[sid]
		if p == nil then
			p = { sid = sid, tile = s.tile, soldiers = {} }
			local u0, v0 = s.tile % W + 0.5, s.tile // W + 0.5
			for i = 1, FrontLayer.SQUAD do
				p.soldiers[i] = {
					img = post_soldier(self),
					key = "",
					u = u0 + (math.random() - 0.5) * 2,
					v = v0 + (math.random() - 0.5) * 2,
					wait = now + math.random() * 1.5,
					next = now + math.random() * FrontLayer.FIRE_MAX,
					kick = 0,
					faces = if i % 2 == 0 then -1 else 1,
					ph = math.random() * 10,
					x = 0,
					y = 0,
				}
			end
			table.insert(self._posts, p)
		end
		p.owner = s.owner
		p.tile = s.tile
		local taken: { number }? = if follow ~= nil and p.owner == me then {} else nil
		for _, sd in p.soldiers do
			local t = math.clamp(math.floor(sd.v), 0, (N // W) - 1) * W + math.clamp(math.floor(sd.u), 0, W - 1)
			sd.rush = false
			if st:tile_owner(t) ~= p.owner then
				-- (its ground was lost: back to the post)
				sd.fu, sd.fv = nil, nil
				sd.tu, sd.tv = s.tile % W + 0.5, s.tile // W + 0.5
				continue
			end
			local eu, ev = enemy_near(st, t, W, N, p.owner, reach, war)
			sd.fu, sd.fv = eu, ev
			if eu ~= nil then
				sd.tu, sd.tv = nil, nil
				if taken ~= nil then
					table.insert(taken, sd.u)
					table.insert(taken, sd.v)
				end
				continue
			end
			if taken ~= nil then
				-- (the front moved on, or it hasn't got there yet: on to the nearest free spot on it)
				local fu, fv = front_spot(follow :: any, W, sd.u, sd.v, follow_r, gap, taken)
				if fu ~= nil then
					sd.tu, sd.tv, sd.rush = fu, fv, true
					table.insert(taken, fu)
					table.insert(taken, fv :: number)
					continue
				end
			end
			if sd.tu == nil and now >= sd.wait then
				sd.tu, sd.tv = roam_target(st, s.tile, W, N, p.owner, roam)
			end
		end
	end
end

--- Moves and draws the soldiers: walking (a hop in the step, facing the way they go), waiting, or at a
--- border at war: facing the enemy, stepping in and out, firing.
local function post_tick(self: any, now: number, dt: number)
	local st = self._state
	if st == nil or #self._posts == 0 then
		return
	end
	local cam = self.view.rig
	local k = tonumber(st.map and st.map.k_lin) or Rules.K_LIN
	local speed = FrontLayer.WALK_FULL / k -- map tiles a second
	local all = {}
	for _, p in self._posts do
		for _, sd in p.soldiers do
			local walking = false
			if sd.fu ~= nil then
				local fx, _ = cam:map_to_screen(sd.fu, sd.fv)
				local sx, _ = cam:map_to_screen(sd.u, sd.v)
				sd.faces = if fx >= sx then 1 else -1
			elseif sd.tu ~= nil then
				local du, dv = sd.tu - sd.u, sd.tv - sd.v
				local d = math.sqrt(du * du + dv * dv)
				local step = speed * dt * (if sd.rush then FrontLayer.RUSH else 1)
				if d <= step or d < 0.05 then
					sd.u, sd.v = sd.tu, sd.tv
					sd.tu, sd.tv = nil, nil
					sd.wait = now + (if sd.rush then 0 else 0.6 + math.random() * 2.2)
				else
					sd.u += du / d * step
					sd.v += dv / d * step
					walking = true
					if math.abs(du) > 0.05 then
						sd.faces = if du > 0 then 1 else -1
					end
				end
			end
			local x, y = cam:map_to_screen(sd.u, sd.v)
			if walking then
				y -= math.abs(math.sin(now * 9 + sd.ph)) * 2.5
			elseif sd.fu ~= nil then
				sd.kick = math.max(0, sd.kick - 0.12)
				x -= sd.faces * (sd.kick * 3 + (math.sin(now * 1.4 + sd.ph) * 0.5 + 0.5) * 3)
				y -= math.abs(math.sin(now * 7 + sd.ph)) * 1.5
			end
			local key = p.owner .. (if sd.faces > 0 then "r" else "l")
			if sd.key ~= key then
				local c = soldier_art(self, p.owner, sd.faces > 0)
				if c ~= nil then
					sd.key = key
					sd.img.ImageContent = c
				end
			end
			x, y = math.round(x), math.round(y)
			sd.x, sd.y = x, y
			sd.img.Position = UDim2.fromOffset(x, y)
			sd.img.Visible = cam:on_screen(x, y, FrontLayer.SOLDIER_PX)
			sd.owner = p.owner
			table.insert(all, sd)
		end
	end
	-- the fights: each soldier at a border at war fires now and then, at the nearest enemy soldier in
	-- reach or else across the border
	for _, sd in all do
		if sd.fu == nil or not sd.img.Visible or now < sd.next then
			continue
		end
		sd.next = now + FrontLayer.FIRE_MIN + math.random() * (FrontLayer.FIRE_MAX - FrontLayer.FIRE_MIN)
		sd.kick = 1
		local tx, ty = cam:map_to_screen(sd.fu, sd.fv)
		local bd = FrontLayer.AIM_PX * FrontLayer.AIM_PX
		for _, o in all do
			if o.owner ~= sd.owner and o.img.Visible then
				local d2 = (o.x - sd.x) ^ 2 + (o.y - sd.y) ^ 2
				if d2 < bd then
					bd, tx, ty = d2, o.x, o.y
				end
			end
		end
		fire(self, now, sd.x + sd.faces * 15, sd.y + 7, tx + (math.random() - 0.5) * 6, ty + (math.random() - 0.5) * 6)
	end
end

function FrontLayer.tick(self: any, dt: number)
	local now = FrameClock.now()
	self._poll -= dt
	if self._poll <= 0 then
		self._poll = FrontLayer.POLL_S
		self:_poll_fronts(now)
	end
	local cam = self.view.rig
	local n = 0
	for _, e in self._entries do
		for _, s in e.slots do
			local f = math.min(1, (now - s.t0) / FrontLayer.ANIM_S)
			s.cx = s.sx + (s.dx - s.sx) * f
			s.cy = s.sy + (s.dy - s.sy) * f
			local x, y = cam:map_to_screen(s.cx, s.cy)
			if not cam:on_screen(x, y, 40) then
				continue
			end
			n += 1
			local rec = label(self, n)
			local l = rec.label
			-- (each written only when it changed: the text is measured again on every write)
			if not rec.vis then
				rec.vis = true
				l.Visible = true
			end
			if rec.text ~= e.text then
				rec.text = e.text
				l.Text = e.text
			end
			if rec.incoming ~= e.incoming then
				rec.incoming = e.incoming
				l.TextColor3 = if e.incoming then FrontLayer.INCOMING else FrontLayer.OUTGOING
			end
			if rec.x ~= x or rec.y ~= y then
				rec.x, rec.y = x, y
				l.Position = UDim2.fromOffset(x, y)
			end
		end
	end
	-- (Take Over the World!: the soldiers at the player's defense posts)
	self._post_poll -= dt
	if self._post_poll <= 0 then
		self._post_poll = FrontLayer.POST_POLL_S
		post_poll(self, now)
	end
	post_tick(self, now, dt)
	fx_tick(self, now)
	for j = n + 1, #self._labels do
		local rec = self._labels[j]
		if rec.vis then
			rec.vis = false
			rec.label.Visible = false
		end
	end
end

return FrontLayer
