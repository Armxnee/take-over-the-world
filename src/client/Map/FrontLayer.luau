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
FrontLayer.SOLDIER_PX = 26
FrontLayer.SOLDIER_GAP = 24 -- px from the front to each side's line
FrontLayer.SOLDIER_SPREAD = 18 -- px between the two soldiers of a side
FrontLayer.FIRE_MIN, FrontLayer.FIRE_MAX = 0.6, 1.5 -- seconds between a soldier's shots
FrontLayer.TRACER_S = 0.11
FrontLayer.FLASH_S = 0.07
FrontLayer.SOLDIER_HAT = "hat_combat_helmet" -- (an empire's soldiers wear its spiked helmet)

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
	self._fx = {}
	self._fx_free = {}
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

--- An owner's soldier picture facing right or left (the rifle on its far side, aiming at the enemy).
local function soldier_art(self: any, owner: number, right: boolean): Content?
	local st = self._state
	local o = st and st:get_owner(owner)
	if o == nil then
		return nil
	end
	if self._flags_map ~= st.map then
		self._flags_map = st.map
		local ok, f = pcall(Countries.flags_by_name, st.map)
		self._flags = if ok then f else {}
	end
	local name = o.name
	local gear = if Empires.is_empire(name) then {} else { hat = FrontLayer.SOLDIER_HAT }
	return Countryball.ball_content(self._flags[name], name, gear, if right then "rifle_right" else "rifle_left")
end

local function fx_frame(self: any, color: Color3, w: number, h: number): Frame
	local pool = self._fx_free
	local f = table.remove(pool)
	if f == nil then
		f = Instance.new("Frame")
		f.Name = "Shot"
		f.BorderSizePixel = 0
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.ZIndex = FrontLayer.Z
		f.Parent = self.root
	end
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 0
	f.Size = UDim2.fromOffset(w, h)
	f.Rotation = 0
	f.Visible = true
	return f
end

--- One shot from (x0, y0) to (x1, y1): a muzzle flash, a tracer flying across, a spark where it lands.
local function fire(self: any, now: number, x0: number, y0: number, x1: number, y1: number)
	local flash = fx_frame(self, Color3.fromRGB(255, 236, 150), 7, 7)
	flash.Position = UDim2.fromOffset(x0, y0)
	table.insert(self._fx, { f = flash, kind = "flash", t0 = now, x = x0, y = y0 })
	local tr = fx_frame(self, Color3.fromRGB(255, 214, 90), 9, 2)
	tr.Rotation = math.deg(math.atan2(y1 - y0, x1 - x0))
	tr.Position = UDim2.fromOffset(x0, y0)
	table.insert(self._fx, { f = tr, kind = "tracer", t0 = now, x = x0, y = y0, x1 = x1, y1 = y1 })
end

local function fx_tick(self: any, now: number)
	local list = self._fx
	local i = 1
	while i <= #list do
		local fx = list[i]
		local age = now - fx.t0
		local done = false
		if fx.kind == "flash" then
			local k = age / FrontLayer.FLASH_S
			fx.f.BackgroundTransparency = math.clamp(k, 0, 1)
			fx.f.Size = UDim2.fromOffset(7 - 3 * math.clamp(k, 0, 1), 7 - 3 * math.clamp(k, 0, 1))
			done = k >= 1
		elseif fx.kind == "tracer" then
			local k = age / FrontLayer.TRACER_S
			if k >= 1 then
				-- it lands: a little spark
				fx.kind, fx.t0 = "spark", now
				fx.f.Rotation = 45
				fx.f.Size = UDim2.fromOffset(5, 5)
				fx.f.BackgroundColor3 = Color3.fromRGB(255, 250, 220)
				fx.f.Position = UDim2.fromOffset(fx.x1, fx.y1)
			else
				fx.f.Position = UDim2.fromOffset(fx.x + (fx.x1 - fx.x) * k, fx.y + (fx.y1 - fx.y) * k)
			end
		else -- spark
			local k = age / 0.16
			fx.f.BackgroundTransparency = math.clamp(k, 0, 1)
			fx.f.BackgroundColor3 = Color3.fromRGB(255, 250, 220):Lerp(Color3.fromRGB(120, 120, 120), math.clamp(k, 0, 1))
			done = k >= 1
		end
		if done then
			fx.f.Visible = false
			table.insert(self._fx_free, fx.f)
			list[i] = list[#list]
			list[#list] = nil
		else
			i += 1
		end
	end
end

--- Battle `n` at the front point (x, y) on screen: the player's two soldiers on their side of the
--- front, the other owner's two on theirs, each line facing the other and firing now and then.
local function battle(self: any, n: number, now: number, x: number, y: number, s: any, e: any)
	local st = self._state
	local me = st and st.local_owner or 0
	local b = self._battles[n]
	if b == nil then
		b = { soldiers = {}, key = "" }
		for i = 1, 4 do
			local img = Instance.new("ImageLabel")
			img.Name = "Soldier"
			img.BackgroundTransparency = 1
			img.AnchorPoint = Vector2.new(0.5, 0.5)
			img.ResampleMode = Enum.ResamplerMode.Pixelated
			img.Size = UDim2.fromOffset(FrontLayer.SOLDIER_PX, FrontLayer.SOLDIER_PX)
			img.ZIndex = FrontLayer.Z - 1
			img.Parent = self.root
			b.soldiers[i] = { img = img, next = now + math.random() * FrontLayer.FIRE_MAX, kick = 0, x = 0, y = 0 }
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
	end
	local px, py = -uy, ux
	local gap, spread = FrontLayer.SOLDIER_GAP, FrontLayer.SOLDIER_SPREAD / 2
	for i, sd in b.soldiers do
		local side = if i <= 2 then -1 else 1 -- -1: the player's side of the front
		local lane = if i % 2 == 1 then -1 else 1
		local back = if lane > 0 then 4 else 0 -- (the second soldier a step behind)
		local bob = math.sin(now * 5 + i * 1.7) * 1.2
		local faces = if side < 0 then (if right then 1 else -1) else (if right then -1 else 1)
		sd.kick = math.max(0, sd.kick - 0.12)
		local sx = x + ux * side * (gap + back) + px * lane * spread - faces * sd.kick * 3
		local sy = y + uy * side * (gap + back) + py * lane * spread + bob
		sd.x, sd.y, sd.faces = sx, sy, faces
		sd.img.Position = UDim2.fromOffset(sx, sy)
		sd.img.Visible = true
	end
	for i, sd in b.soldiers do
		if now >= sd.next then
			sd.next = now + FrontLayer.FIRE_MIN + math.random() * (FrontLayer.FIRE_MAX - FrontLayer.FIRE_MIN)
			sd.kick = 1
			local foe = b.soldiers[(if i <= 2 then 2 else 0) + math.random(1, 2)]
			-- (the muzzle: the barrel's tip, just past the middle of the ball on the aiming side)
			local S = FrontLayer.SOLDIER_PX
			fire(self, now, sd.x + sd.faces * S * 0.14, sd.y + S * 0.13, foe.x + (math.random() - 0.5) * 6, foe.y + (math.random() - 0.5) * 6)
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
		b.key = "" -- (drawn again when it shows)
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
		end
	end
	hide_battles(self, n + 1)
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
