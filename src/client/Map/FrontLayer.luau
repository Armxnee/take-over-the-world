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
local Empires = require(Airfront:WaitForChild("Data"):WaitForChild("Empires")) :: any
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
-- (Take Over the World!, 2026-11-08: a battle at every front label: two of the player's Countryball
-- soldiers face two of the other country's across the border, rifles out, firing at each other)
FrontLayer.SOLDIER_PX = 32 -- (Countryball.MINI 16 px at exactly 2x: a round ball)
FrontLayer.TANK_PX = 64 -- (the 32 px tank at 2x)
FrontLayer.TANK_BACK = 40 -- px behind its side's soldiers
FrontLayer.TANK_FIRE_MIN, FrontLayer.TANK_FIRE_MAX = 2.2, 4.0
FrontLayer.SOLDIER_GAP = 30 -- px from the front to each side's line
FrontLayer.SOLDIER_SPREAD = 24 -- px between the two soldiers of a side
FrontLayer.FIRE_MIN, FrontLayer.FIRE_MAX = 0.6, 1.5 -- seconds between a soldier's shots
FrontLayer.TRACER_S = 0.11
FrontLayer.FLASH_S = 0.07
FrontLayer.SOLDIER_HAT = "hat_combat_helmet" -- (an empire's soldiers wear its spiked helmet)
-- (and a few border posts everywhere on screen: a soldier of each country on its side of a border,
-- patrolling along it; when the two are at war they face each other and fire)
FrontLayer.MAX_POSTS = 10
FrontLayer.POST_SPACING = 120 -- px between posts (and from the front battles)
FrontLayer.POST_POLL_S = 0.7
FrontLayer.POST_SAMPLES = 24 -- random looks for a border, each poll
FrontLayer.POST_GAP = 15 -- px from the border to each soldier
FrontLayer.PATROL_PX = 10 -- how far a patrol walks either way along the border

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
	self._battles = {} -- (Take Over the World!: the soldiers at each shown front, and the shots)
	self._bfx = BattleFx.new(root, FrontLayer.Z) -- (the shots, shells and blasts)
	self._posts = {} -- (the border posts)
	self._post_poll = 0.0
	self._battle_pts = {} -- (where the battles are on screen this frame)
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

-- ===== (Take Over the World!) the battles: Countryball soldiers firing across each front =====

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

--- An owner's tank (the user's Countryball tank, its ball in the owner's flag), facing right or left.
local function tank_art(self: any, owner: number, right: boolean): Content?
	local code, name = owner_flag(self, owner)
	if name == nil then
		return nil
	end
	return Countryball.vehicle_content("tank", code, name, right)
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

--- Battle `n` at the front point (x, y) on screen: the player's two soldiers on their side of the
--- front, the other owner's two on theirs, each line facing the other and firing now and then.
local function battle(self: any, n: number, now: number, x: number, y: number, s: any, e: any)
	local st = self._state
	local me = st and st.local_owner or 0
	local b = self._battles[n]
	if b == nil then
		b = { soldiers = {}, tanks = {}, key = "" }
		for i = 1, 4 do
			b.soldiers[i] = {
				img = pixel_image(self, "Soldier", FrontLayer.SOLDIER_PX, FrontLayer.Z - 1),
				next = now + math.random() * FrontLayer.FIRE_MAX,
				kick = 0,
				x = 0,
				y = 0,
			}
		end
		for i = 1, 2 do
			b.tanks[i] = {
				img = pixel_image(self, "Tank", FrontLayer.TANK_PX, FrontLayer.Z - 2),
				next = now + 1 + math.random() * FrontLayer.TANK_FIRE_MAX,
				kick = 0,
				x = 0,
				y = 0,
			}
		end
		self._battles[n] = b
	end
	local ux, uy = s.ux or 1, s.uy or 0
	local right = ux >= 0 -- the player's soldiers face right when the enemy lies to the right
	local key = string.format("%d|%d|%s", me, e.other or 0, tostring(right))
	if b.key ~= key then
		b.key = key
		local mine, theirs = soldier_art(self, me, right), soldier_art(self, e.other or 0, not right)
		for i, sd in b.soldiers do
			local c = if i <= 2 then mine else theirs
			if c ~= nil then
				sd.img.ImageContent = c
			end
		end
		local tm, tt = tank_art(self, me, right), tank_art(self, e.other or 0, not right)
		if tm then
			b.tanks[1].img.ImageContent = tm
		end
		if tt then
			b.tanks[2].img.ImageContent = tt
		end
	end
	local px, py = -uy, ux
	local gap, spread = FrontLayer.SOLDIER_GAP, FrontLayer.SOLDIER_SPREAD / 2
	for i, sd in b.soldiers do
		local side = if i <= 2 then -1 else 1 -- -1: the player's side of the front
		local lane = if i % 2 == 1 then -1 else 1
		local back = if lane > 0 then 4 else 0 -- (the second soldier a step behind)
		-- (moving: each soldier steps up to the front and back again, hopping as it walks)
		local step = (math.sin(now * 1.4 + i * 2.1) * 0.5 + 0.5) * 7
		local hop = -math.abs(math.sin(now * 7 + i * 1.3)) * 2.5
		local faces = if side < 0 then (if right then 1 else -1) else (if right then -1 else 1)
		sd.kick = math.max(0, sd.kick - 0.12)
		local d = gap + back - step
		local sx = math.round(x + ux * side * d + px * lane * spread - faces * sd.kick * 3)
		local sy = math.round(y + uy * side * d + py * lane * spread + hop)
		sd.x, sd.y, sd.faces = sx, sy, faces
		sd.img.Position = UDim2.fromOffset(sx, sy)
		sd.img.Visible = true
	end
	-- a tank behind each side's soldiers: rolling a little back and forth, rocking on its tracks
	for i, tk in b.tanks do
		local side = if i == 1 then -1 else 1
		local faces = if side < 0 then (if right then 1 else -1) else (if right then -1 else 1)
		tk.kick = math.max(0, tk.kick - 0.06)
		local roll = math.sin(now * 0.7 + i * 2.5) * 5
		local rock = if math.sin(now * 13 + i) > 0 then 0 else 1
		local d = gap + FrontLayer.TANK_BACK + roll
		local tx = math.round(x + ux * side * d - faces * tk.kick * 5)
		local ty = math.round(y + uy * side * d + rock - 6)
		tk.x, tk.y, tk.faces = tx, ty, faces
		tk.img.Position = UDim2.fromOffset(tx, ty)
		tk.img.Visible = true
	end
	for i, sd in b.soldiers do
		if now >= sd.next then
			sd.next = now + FrontLayer.FIRE_MIN + math.random() * (FrontLayer.FIRE_MAX - FrontLayer.FIRE_MIN)
			sd.kick = 1
			local foe = b.soldiers[(if i <= 2 then 2 else 0) + math.random(1, 2)]
			-- (the muzzle: the rifle's tip on the mini ball, 2x: 15 px out, 7 px down from its middle)
			fire(self, now, sd.x + sd.faces * 15, sd.y + 7, foe.x + (math.random() - 0.5) * 6, foe.y + (math.random() - 0.5) * 6)
		end
	end
	for i, tk in b.tanks do
		if now >= tk.next then
			tk.next = now + FrontLayer.TANK_FIRE_MIN + math.random() * (FrontLayer.TANK_FIRE_MAX - FrontLayer.TANK_FIRE_MIN)
			tk.kick = 1
			-- (at the other side's tank or one of its soldiers)
			local foe = if math.random() < 0.5 then b.tanks[3 - i] else b.soldiers[(if i == 1 then 2 else 0) + math.random(1, 2)]
			self._bfx:cannon(now, tk.x + tk.faces * 28, tk.y - 1, foe.x + (math.random() - 0.5) * 10, foe.y + (math.random() - 0.5) * 8)
		end
	end
end

local function hide_battles(self: any, from: number)
	for j = from, #self._battles do
		local b = self._battles[j]
		for _, sd in b.soldiers do
			if sd.img.Visible then
				sd.img.Visible = false
			end
		end
		for _, tk in b.tanks do
			if tk.img.Visible then
				tk.img.Visible = false
			end
		end
		b.key = "" -- (drawn again when it shows)
	end
end

-- ===== (Take Over the World!) the border posts: a few soldiers on borders everywhere on screen =====

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

--- Keeps up to MAX_POSTS posts on borders between two owners' land in view: drops those that left
--- the screen or whose border moved, then looks for new ones (a random point walks a random way
--- until the owner changes: that is a border).
local function post_poll(self: any, now: number, battles: { { number } })
	local st = self._state
	local cam = self.view.rig
	-- (only in a match the player is in: not on the title screen's live world behind the menu)
	if st == nil or st.map == nil or st.phase ~= Defs.PHASE_PLAYING or (st.local_owner or 0) == 0 then
		for i = #self._posts, 1, -1 do
			drop_post(self, i)
		end
		return
	end
	local W = st.map.W or Defs.W
	local N = st.map.N or (W * (st.map.H or Defs.H))
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
	local i = 1
	while i <= #self._posts do
		local p = self._posts[i]
		local x, y = cam:tile_to_screen(p.t1)
		if
			not cam:on_screen(x, y, 30)
			or st:tile_owner(p.t1) ~= p.a
			or st:tile_owner(p.t2) ~= p.b
		then
			drop_post(self, i)
		else
			p.war = war[p.a * 65536 + p.b] == true
			i += 1
		end
	end
	if #self._posts >= FrontLayer.MAX_POSTS then
		return
	end
	local vp = cam:viewport_size()
	local sp2 = FrontLayer.POST_SPACING ^ 2
	local function free(x: number, y: number): boolean
		for _, p in self._posts do
			local px, py = cam:tile_to_screen(p.t1)
			if (px - x) ^ 2 + (py - y) ^ 2 < sp2 then
				return false
			end
		end
		for _, b in battles do
			if (b[1] - x) ^ 2 + (b[2] - y) ^ 2 < sp2 then
				return false
			end
		end
		return true
	end
	local tpp = math.max(cam:tiles_per_px(), 1e-3) -- tiles per screen px
	for _ = 1, FrontLayer.POST_SAMPLES do
		if #self._posts >= FrontLayer.MAX_POSTS then
			break
		end
		local sx, sy = 40 + math.random() * (vp.X - 80), 90 + math.random() * (vp.Y - 220)
		local u, v = cam:screen_to_map(sx, sy)
		if u < 0 or v < 0 or u >= W then
			continue
		end
		local t = math.floor(v) * W + math.floor(u)
		if t < 0 or t >= N then
			continue
		end
		local a = st:tile_owner(t)
		if a == 0 then
			continue
		end
		local ang = math.random() * 2 * math.pi
		local dx, dy = math.cos(ang), math.sin(ang)
		local stepl = math.max(1, 3 * tpp) -- (about 3 px a step)
		local prev = t
		for k = 1, 40 do
			local uu, vv = u + dx * stepl * k, v + dy * stepl * k
			if uu < 0 or vv < 0 or uu >= W then
				break
			end
			local tt = math.floor(vv) * W + math.floor(uu)
			if tt < 0 or tt >= N then
				break
			end
			local b = st:tile_owner(tt)
			if b ~= a then
				if b ~= 0 then
					local px, py = cam:tile_to_screen(prev)
					if cam:on_screen(px, py, -40) and free(px, py) then
						local ux, uy = front_dir(st, prev, W, a, b)
						local p = {
							t1 = prev,
							t2 = tt,
							a = a,
							b = b,
							ux = ux,
							uy = uy,
							war = war[a * 65536 + b] == true,
							phase = math.random() * 10,
							soldiers = {},
						}
						for s = 1, 2 do
							p.soldiers[s] = {
								img = post_soldier(self),
								key = "",
								next = now + math.random() * FrontLayer.FIRE_MAX,
								kick = 0,
								x = 0,
								y = 0,
								faces = 1,
							}
						end
						table.insert(self._posts, p)
					end
				end
				break
			end
			prev = tt
		end
	end
end

--- Draws the posts: at peace each soldier patrols along the border (walking, hopping, facing where
--- it walks); at war the two face each other across it, step in and out and fire.
local function post_tick(self: any, now: number)
	local cam = self.view.rig
	for _, p in self._posts do
		local bx, by = cam:tile_to_screen(p.t1)
		local ux, uy = p.ux, p.uy
		local px, py = -uy, ux
		for s, sd in p.soldiers do
			local owner = if s == 1 then p.a else p.b
			local side = if s == 1 then -1 else 1
			local ph = p.phase + s * 1.9
			local x, y, faces
			if p.war then
				local toward = ux * -side -- (+: the enemy lies to the right)
				faces = if toward >= 0 then 1 else -1
				local step = (math.sin(now * 1.4 + ph) * 0.5 + 0.5) * 6
				local d = FrontLayer.POST_GAP + 4 - step
				sd.kick = math.max(0, sd.kick - 0.12)
				x = bx + ux * side * d - faces * sd.kick * 3
				y = by + uy * side * d - math.abs(math.sin(now * 7 + ph)) * 2.5
			else
				-- patrol: walk along the border and back, facing the way it walks
				local w = math.sin(now * 0.8 + ph)
				local along = w * FrontLayer.PATROL_PX
				local vel = math.cos(now * 0.8 + ph) -- (its walking direction along the border)
				local walk_x = px * vel
				faces = if walk_x >= 0 then 1 else -1
				x = bx + ux * side * FrontLayer.POST_GAP + px * along
				y = by + uy * side * FrontLayer.POST_GAP + py * along - math.abs(math.sin(now * 6 + ph)) * 2 * math.min(1, math.abs(vel) * 2)
			end
			local key = owner .. (if faces > 0 then "r" else "l")
			if sd.key ~= key then
				local c = soldier_art(self, owner, faces > 0)
				if c ~= nil then
					sd.key = key
					sd.img.ImageContent = c
				end
			end
			x, y = math.round(x), math.round(y)
			sd.x, sd.y, sd.faces = x, y, faces
			sd.img.Position = UDim2.fromOffset(x, y)
		end
		if p.war then
			for s, sd in p.soldiers do
				if now >= sd.next then
					sd.next = now + FrontLayer.FIRE_MIN + math.random() * (FrontLayer.FIRE_MAX - FrontLayer.FIRE_MIN) + 0.4
					sd.kick = 1
					local foe = p.soldiers[3 - s]
					fire(self, now, sd.x + sd.faces * 15, sd.y + 7, foe.x + (math.random() - 0.5) * 6, foe.y + (math.random() - 0.5) * 6)
				end
			end
		end
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
			battle(self, n, now, x, y, s, e) -- (Take Over the World!: the soldiers at this front)
			local bp = self._battle_pts[n]
			if bp == nil then
				bp = {}
				self._battle_pts[n] = bp
			end
			bp[1], bp[2] = x, y
		end
	end
	hide_battles(self, n + 1)
	-- (Take Over the World!: the border posts, kept clear of the battles)
	for j = #self._battle_pts, n + 1, -1 do
		self._battle_pts[j] = nil
	end
	self._post_poll -= dt
	if self._post_poll <= 0 then
		self._post_poll = FrontLayer.POST_POLL_S
		post_poll(self, now, self._battle_pts)
	end
	post_tick(self, now)
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
