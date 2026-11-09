--!native
-- Units on the 2D map:
--   * sprites from the unit atlas (13 x 13 px, drawn 13 full-size tiles wide, so they
--     scale with the map), recoloured: light pixels in the owner's territory
--     colour, dark pixels in its border colour (two tinted mask layers, Pixelated);
--   * ships / trains follow their path tile to tile (the sim's timing: start_tick +
--     ticks_per_tile); warships interpolate prev_tile -> current over a second;
--   * a train is drawn as the engine, TRAIN_CARRIAGES carriages and a
--     tail engine, TRAIN_SPACING full-size tiles apart along the rails behind it (the sim moves one
--     unit; the cars are cosmetic);
--   * nukes fly a cubic Bezier (Rules.nuke_arc: control points a quarter / three quarters
--     along, raised by max(dist / 3, 50 full-size tiles) toward the top, clamped to the map; the
--     Sim flies the same arc), leave a trail in the owner's colour (alpha 0.588) and mark their
--     target with a pulsing blast ring;
--   * shells and SAM missiles are small sprites flying straight to their target;
--   * transport ships leave a wake: the way sailed so far,
--     one full-size tile wide in the owner's territory colour at alpha 0.588, gone with the ship.
--     The ship and its wake follow the route with its corners rounded (Map/WakeRoute: the Sim's
--     paths are straight legs meeting at sharp corners, and the wake was a few straight bars until
--     2026-10-07, when it was made to curve smoothly), drawn as short straight bars.
--
-- What it costs (2026-10-08; players on Windows had stutter bad enough to quit, ten minutes into a
-- match). Twenty minutes into a World match there are 700 units, and with the
-- whole map in view this layer was the frame's biggest cost: 2.9 of the map's 3.5 ms of script a frame,
-- about 3,000 GUI objects and some 9,000 Position writes a second for Roblox to lay out again
-- (docs/performance.md has the trace). So:
--   * a train's cars are drawn only where they can be told apart (CARS_MIN_ZOOM, where the rails fade
--     in too): 2 full-size tiles apart, seven 13-tile sprites are one blob on a map zoomed out, yet
--     they were six of every seven sprites that moved;
--   * a sprite is one image (Sprites.units_one: both of the sprite's colours in one tint) once that atlas
--     has loaded, and until then two, the second inside the first; it was two inside a frame;
--   * while the camera stands still and many sprites are on screen, the whole layer is redrawn 20 to
--     30 times a second, not every frame (THROTTLE_*): at that zoom a ship moves a fraction of a
--     pixel a frame, and a frame in which nothing here changes costs Roblox nothing (MapView's
--     header);
--   * the pools keep a few spares and destroy the rest (POOL_SPARE): every object in this ScreenGui
--     is gone over on each frame something moved, shown or not, and the pools had grown to 7,700.
local RS = game:GetService("ReplicatedStorage")
local Airfront = RS:WaitForChild("Airfront")
local Defs = require(Airfront:WaitForChild("Core"):WaitForChild("Defs")) :: any
local Rules = require(Airfront:WaitForChild("Core"):WaitForChild("Rules")) :: any
local Sprites = require(Airfront:WaitForChild("Assets"):WaitForChild("MapSprites")) :: any
local WakeRoute = require(script.Parent:WaitForChild("WakeRoute")) :: any
local TrailBudget = require(script.Parent:WaitForChild("TrailBudget")) :: any
local FrameClock = require(script.Parent:WaitForChild("FrameClock")) :: any
local Gear = require(Airfront:WaitForChild("Data"):WaitForChild("Gear")) :: any
local Countries = require(Airfront:WaitForChild("Data"):WaitForChild("Countries")) :: any -- (Take Over the World!: jets)
local Countryball = require("../UI/Countryball")
local BattleFx = require(script.Parent:WaitForChild("BattleFx")) :: any

--- The one-image sprites (Sprites.units_one) are used once the atlas is known to have loaded: an image
--- still in moderation would leave every unit invisible.
local ONE: any = Sprites.units_one
local one_ready = false
if ONE ~= nil then
	(require(script.Parent:WaitForChild("AtlasReady")) :: any).watch(ONE.id, function()
		one_ready = true
	end)
end

local UnitLayer = {}
UnitLayer.__index = UnitLayer

UnitLayer.UNIT_SIZE = 13 -- full-size tiles
UnitLayer.MIN_PX = 5
UnitLayer.TRAIL_ALPHA = 0.588
UnitLayer.TRAIL_STEP = 2.0 -- full-size tiles between a trail's points
UnitLayer.TRAIL_WIDTH = 0.9 -- a nuke trail's width, map tiles
--- ship wakes: the least a wake is wide on screen (the route's shape: Map/WakeRoute)
UnitLayer.TRAIL_MIN_PX = 1.5
--- Trains: 5 cars, 2 tiles between cars, the nearest car 2 tiles
--- behind the engine and the tail engine last.
UnitLayer.TRAIN_CARRIAGES = 5
UnitLayer.TRAIN_SPACING = 2.0
--- A train's cars are drawn from this zoom on (device px per full-size tile, with
--- RoadLayer's device ratio, where the rails start to fade in): below it the engine stands for the train.
UnitLayer.CARS_MIN_ZOOM = 3.0
UnitLayer.DEVICE_RATIO = 2.0
--- With the camera still and this many unit sprites on screen, the layer is redrawn no sooner than
--- THROTTLE_S after the last time (every second frame at 60 a second); from THROTTLE_3 on,
--- THROTTLE_3_S (every third). While a munition flies or a unit is selected, THROTTLE_S at most.
UnitLayer.THROTTLE_FROM = 160
UnitLayer.THROTTLE_3 = 480
UnitLayer.THROTTLE_S = 0.030
UnitLayer.THROTTLE_3_S = 0.045
--- Sprites, wake bars and trail dots kept hidden for reuse; the rest are destroyed.
UnitLayer.POOL_SPARE = 48
UnitLayer.Z = 14

-- unit atlas columns
local COL_TRANSPORT, COL_TRADE, COL_WARSHIP = 0, 1, 2
local COL_ATOM, COL_HYDROGEN, COL_MIRV, COL_SAM, COL_SHELL, COL_WARHEAD, COL_TRAIN = 3, 4, 5, 6, 7, 8, 9
local COL_CARRIAGE = 10
local UNIT_COL = {
	[Defs.U_TRANSPORT] = COL_TRANSPORT,
	[Defs.U_TRADE] = COL_TRADE,
	[Defs.U_WARSHIP] = COL_WARSHIP,
	[Defs.U_TRUCK] = COL_TRAIN,
}
local NUKE_COL = {
	[Defs.N_ATOM] = COL_ATOM,
	[Defs.N_HYDROGEN] = COL_HYDROGEN,
	[Defs.N_MIRV] = COL_MIRV,
	[Defs.N_WARHEAD] = COL_WARHEAD,
	-- the Arsenal's munitions (Data/Arsenal) wear existing sprites: a mega nuke the hydrogen bomb,
	-- a scattershot the MIRV, an air strike the missile, a railgun slug the shell
	[Defs.N_MEGA] = COL_HYDROGEN,
	[Defs.N_SCATTER] = COL_MIRV,
	[Defs.N_SHELL] = COL_SHELL,
	[Defs.N_AIRSTRIKE] = COL_SAM,
	[Defs.N_SLUG] = COL_SHELL,
}
--- (Take Over the World!: the item shop's unit skins: which skin slot a munition wears; nukes otherwise)
local NUKE_SLOT = { [Defs.N_AIRSTRIKE] = "missile", [Defs.N_SHELL] = false, [Defs.N_SLUG] = false }
local gear_tints: { [string]: Color3 | false } = {}
--- The colour owner `owner`'s `slot` skin ("boat" / "nuke" / "missile") paints, or nil.
local function tint_of(st: any, owner: number, slot: string | false | nil): Color3?
	if not slot then
		return nil
	end
	local cz = st.cosmetics and st.cosmetics[owner]
	local id = if cz ~= nil then cz[slot] else nil
	if id == nil then
		return nil
	end
	local t = gear_tints[id]
	if t == nil then
		t = Gear.color(id) or false
		gear_tints[id] = t
	end
	return t or nil
end

--- Munitions drawn without a trail and a target ring (a battery's shells: there are many).
local NUKE_PLAIN = { [Defs.N_SHELL] = true }
--- Munitions drawn bigger than the others.
local NUKE_SCALE = { [Defs.N_MEGA] = 1.5, [Defs.N_SHELL] = 0.75, [Defs.N_SLUG] = 1.2 }

type Sprite = {
	frame: ImageLabel,
	fill: ImageLabel,
	--- nil: a one-image sprite
	rim: ImageLabel?,
	col: number,
	owner: number,
	px: number,
	x: number,
	y: number,
}

-- Sprite keys are numbers (a string per sprite per frame churned the GC in late games): id * 16 +
-- the kind of sprite (a unit 0, its train cars 1..6, a nuke 8, a shell 9, a SAM missile 10).
local KEY_NUKE, KEY_SHELL, KEY_SAM = 8, 9, 10

local function border_of(c: Color3): Color3
	local h, s, v = c:ToHSV()
	-- HSL lightness - 0.125 approximated in HSV (value drop keeps hue / saturation)
	return Color3.fromHSV(h, s, math.max(0, v - 0.16))
end

function UnitLayer.new(parent: Instance, view: any)
	local self = setmetatable({}, UnitLayer) :: any
	local root = Instance.new("Frame")
	root.Name = "Units"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = UnitLayer.Z
	root.Parent = parent
	self.root = root
	self.view = view
	self._state = nil :: any
	self._sprites = {} :: { [number]: Sprite }
	self._seen = {} :: { [number]: boolean }
	self._pool = {} :: { Sprite }
	self._dots = {} :: { Frame }
	self._dots_used = 0
	--- wake bars: the Frame and what it was last given (a still camera writes nothing)
	self._bars = {} :: { { [string]: any } }
	self._bars_used = 0
	--- uid -> the ship's path (to notice a new one), its smooth route (WakeRoute) and where the
	--- ship is on it this frame (map tiles)
	self._wakes = {} :: { [number]: { path: { number }, route: any, x: number, y: number } }
	self._rings = {} :: { [number]: Frame }
	self._selected = -1
	self._sel_ring = self:_ring(root, "Selected", UnitLayer.Z + 3)
	--- uid -> screen pos this frame, of the units a press can pick (warships, transports)
	self._screen = {} :: { [number]: Vector2 }
	--- the throttle: the camera's version and the sprite size last frame, the unit sprites drawn then,
	--- and when
	self._cam_seen = -1
	self._px_seen = -1
	self._drawn = 0
	self._drawn_at = 0.0
	-- (Take Over the World!: air strikes fly as Countryball jets and strafe their target)
	self._jets = {} :: { [number]: any }
	self._bfx = BattleFx.new(root, UnitLayer.Z + 4)
	return self
end

function UnitLayer.bind(self: any, state: any)
	self:unbind()
	self._state = state
end

function UnitLayer.unbind(self: any)
	self._state = nil
	for key, s in self._sprites do
		self:_release(s)
		self._sprites[key] = nil
	end
	for uid, r in self._rings do
		r:Destroy()
		self._rings[uid] = nil
	end
	for _, d in self._dots do
		d.Visible = false
	end
	for _, b in self._bars do
		b.shown = false
		b.f.Visible = false
	end
	table.clear(self._wakes)
	self._sel_ring.Visible = false
	table.clear(self._screen)
	for uid, j in self._jets do
		j.img:Destroy()
		self._jets[uid] = nil
	end
	self._bfx:clear()
end

function UnitLayer.destroy(self: any)
	self:unbind()
	self.root:Destroy()
end

function UnitLayer.set_selected(self: any, uid: number)
	self._selected = uid
end

-- ---------------------------------------------------------------------------------------------
-- Pools
-- ---------------------------------------------------------------------------------------------

function UnitLayer._ring(_self: any, parent: Instance, name: string, z: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BackgroundTransparency = 1
	f.ZIndex = z
	f.Visible = false
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = f
	local s = Instance.new("UIStroke")
	s.Thickness = 2
	s.Color = Color3.new(1, 1, 1)
	s.Parent = f
	f.Parent = parent
	return f
end

local function mask(parent: Instance, name: string, row: number, z: number): ImageLabel
	local l = Instance.new("ImageLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Image = Sprites.units.id
	l.ImageRectSize = Vector2.new(Sprites.units.cell, Sprites.units.cell)
	l.ImageRectOffset = Vector2.new(0, row * Sprites.units.cell)
	l.ResampleMode = Enum.ResamplerMode.Pixelated
	l.Size = UDim2.fromScale(1, 1)
	l.ZIndex = z
	l.Parent = parent
	return l
end

function UnitLayer._acquire(self: any): Sprite
	local s = table.remove(self._pool)
	if s then
		s.frame.Visible = true
		return s
	end
	-- (one object a sprite; two, the rim inside the fill, while the one-image atlas isn't here)
	local fill = mask(nil :: any, "Unit", 0, UnitLayer.Z)
	fill.AnchorPoint = Vector2.new(0.5, 0.5)
	local rim: ImageLabel? = nil
	if one_ready then
		fill.Image = ONE.id
	else
		rim = mask(fill, "Rim", 1, UnitLayer.Z + 1)
	end
	fill.Parent = self.root
	return { frame = fill, fill = fill, rim = rim, col = -1, owner = -1, px = -1, x = -1e9, y = -1e9 }
end

function UnitLayer._release(self: any, s: Sprite)
	if #self._pool >= UnitLayer.POOL_SPARE then
		s.frame:Destroy()
		return
	end
	s.frame.Visible = false
	s.col = -1
	s.owner = -1
	s.x, s.y = -1e9, -1e9
	table.insert(self._pool, s)
end

function UnitLayer._sprite(
	self: any,
	key: number,
	col: number,
	owner: number,
	x: number,
	y: number,
	px: number,
	seen: { [number]: boolean },
	tint: Color3?
)
	seen[key] = true
	local s = self._sprites[key]
	if s == nil then
		s = self:_acquire()
		self._sprites[key] = s
	end
	if s.col ~= col then
		s.col = col
		local cell = Sprites.units.cell
		s.fill.ImageRectOffset = Vector2.new(col * cell, 0)
		if s.rim ~= nil then
			s.rim.ImageRectOffset = Vector2.new(col * cell, cell)
		end
	end
	if s.owner ~= owner or (s :: any).tint ~= tint then
		s.owner = owner;
		(s :: any).tint = tint
		local c = tint or self._state:owner_color(owner)
		s.fill.ImageColor3 = c
		if s.rim ~= nil then
			s.rim.ImageColor3 = border_of(c)
		end
	end
	if s.px ~= px then
		s.px = px
		s.frame.Size = UDim2.fromOffset(px, px)
	end
	-- (a GUI property write per sprite per frame adds up: only when it moved a pixel)
	local rx, ry = math.round(x), math.round(y)
	if rx ~= s.x or ry ~= s.y then
		s.x, s.y = rx, ry
		s.frame.Position = UDim2.fromOffset(rx, ry)
	end
end

function UnitLayer._dot(self: any, x: number, y: number, px: number, col: Color3)
	self._dots_used += 1
	local d = self._dots[self._dots_used]
	if d == nil then
		d = Instance.new("Frame")
		d.Name = "Trail"
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.BorderSizePixel = 0
		d.BackgroundTransparency = 1 - UnitLayer.TRAIL_ALPHA
		d.ZIndex = UnitLayer.Z - 1
		d.Parent = self.root
		self._dots[self._dots_used] = d
	end
	d.Visible = true
	d.BackgroundColor3 = col
	d.Size = UDim2.fromOffset(px, px)
	d.Position = UDim2.fromOffset(math.round(x), math.round(y))
end

--- A straight wake bar between two screen points, `w` px thick.
function UnitLayer._bar(self: any, x0: number, y0: number, x1: number, y1: number, w: number, col: Color3)
	self._bars_used += 1
	local b = self._bars[self._bars_used]
	if b == nil then
		local f = Instance.new("Frame")
		f.Name = "Wake"
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BorderSizePixel = 0
		f.BackgroundTransparency = 1 - UnitLayer.TRAIL_ALPHA
		f.ZIndex = UnitLayer.Z - 1
		f.Parent = self.root
		b = { f = f, shown = true }
		self._bars[self._bars_used] = b
	end
	local f: Frame = b.f
	if not b.shown then
		b.shown = true
		f.Visible = true
	end
	if b.col ~= col then
		b.col = col
		f.BackgroundColor3 = col
	end
	if b.x0 ~= x0 or b.y0 ~= y0 or b.x1 ~= x1 or b.y1 ~= y1 or b.w ~= w then
		b.x0, b.y0, b.x1, b.y1, b.w = x0, y0, x1, y1, w
		local dx, dy = x1 - x0, y1 - y0
		local len = math.sqrt(dx * dx + dy * dy)
		f.Position = UDim2.fromOffset((x0 + x1) * 0.5, (y0 + y1) * 0.5)
		f.Size = UDim2.fromOffset(math.max(len, w), w)
		f.Rotation = if len > 0 then math.deg(math.atan2(dy, dx)) else 0
	end
end

--- A route's straight runs (Map/WakeRoute.runs).
UnitLayer.wake_runs = WakeRoute.runs

-- ---------------------------------------------------------------------------------------------
-- Poses (map tiles)
-- ---------------------------------------------------------------------------------------------

local function centre(t: number, W: number): (number, number)
	return t % W + 0.5, t // W + 0.5
end

--- Tiles of its path a unit has moved through at `rt` (fractional).
function UnitLayer.path_done(u: any, rt: number): number
	return math.max(0.0, (rt - u.start_tick) * 100.0 / math.max(u.ticks_per_tile_x100, 1))
end

--- Map position of a moving unit at `rt` (fractional ticks).
function UnitLayer.unit_uv(st: any, u: any, rt: number): (number, number)
	local path = u.path
	local n = #path
	if u.kind == Defs.U_WARSHIP and (u.prev_tile or -1) >= 0 then
		local W = st.map.W or Defs.W
		local cx, cy = centre(if n > 0 then path[1] else 0, W)
		local ax, ay = centre(u.prev_tile, W)
		local f = math.clamp((rt - (u.move_tick or 0)) / Defs.TICK_RATE, 0, 1)
		return ax + (cx - ax) * f, ay + (cy - ay) * f
	end
	return UnitLayer.path_uv(st, u, UnitLayer.path_done(u, rt))
end

--- Map position `done` tiles along a unit's path (clamped to its ends).
function UnitLayer.path_uv(st: any, u: any, done: number): (number, number)
	local W = st.map.W or Defs.W
	local path = u.path
	local n = #path
	if n < 2 then
		return centre(if n > 0 then path[1] else 0, W)
	end
	done = math.max(0.0, done)
	local seg = math.min(math.floor(done), n - 2)
	local f = math.clamp(done - seg, 0, 1)
	local ax, ay = centre(path[seg + 1], W)
	local bx, by = centre(path[seg + 2], W)
	return ax + (bx - ax) * f, ay + (by - ay) * f
end

--- What a redraw draws for the munitions in `nukes` (GameState.nukes): the trail dots each one keeps
--- and whether MIRV warheads get their target rings (Map/TrailBudget: hundreds fly at once).
function UnitLayer.trail_allowance(nukes: { [number]: any }): (number, boolean)
	local flying = 0
	for _, n in nukes do
		if not NUKE_PLAIN[n.kind] then
			flying += 1
		end
	end
	return TrailBudget.allowance(flying)
end

--- A nuke's position at flight fraction t: its arc (Rules.nuke_arc, a Bezier toward the top,
--- constant speed along it), the same path the Sim flies and SAMs intercept. Built once per nuke.
function UnitLayer.nuke_uv(st: any, n: any, t: number): (number, number)
	local R = st.rules or Rules
	local arc = n._arc
	if arc == nil then
		-- (a shell, an air strike and a slug fly straight: Rules.munition_arc)
		arc = R.munition_arc(st.map.W or Defs.W, st.map.H or Defs.H, n.from_tile, n.to_tile, n.kind)
		n._arc = arc
	end
	return R.nuke_arc_at(arc, t)
end

-- ---------------------------------------------------------------------------------------------
-- Frame
-- ---------------------------------------------------------------------------------------------

--- (Take Over the World!) Air strike `uid` as a Countryball jet at (x, y): facing and tilting the way it
--- flies; over the last stretch it strafes the target (tracers and sparks), and blows it up at the end.
UnitLayer.JET_PX = 32 -- (the 32 px jet at 1x: it was 2x, too big next to the map)
UnitLayer.STRAFE_FROM = 0.55 -- of the flight
UnitLayer.STRAFE_S = 0.07
UnitLayer.GUN_S = 0.55 -- a machine-gun burst's sound this often while strafing
UnitLayer.BOMB_AT = 0.8 -- of the flight: the bombs drop
UnitLayer.SAMPLES = 48 -- points along a jet's route

--- (2026-11-08) An air strike's route, as a boat's: not a straight line but a smooth curve from its
--- airfield to the target, swinging out to one side and weaving back (a cubic curve whose bends come
--- from the strike's id), flown at an even speed. The sim only times the flight (a strike can't be
--- intercepted), so the picture can take any route that starts and ends where the sim's does.
function UnitLayer.jet_uv(st: any, n: any, t: number, uid: number): (number, number)
	local path = n._jet_path
	if path == nil then
		local W = st.map.W or Defs.W
		local ax, ay = centre(n.from_tile, W)
		local bx, by = centre(n.to_tile, W)
		local dx, dy = bx - ax, by - ay
		local L = math.max(math.sqrt(dx * dx + dy * dy), 1)
		local px, py = -dy / L, dx / L
		local rnd = Random.new(uid * 7919 + n.from_tile)
		local a1 = (0.22 + rnd:NextNumber() * 0.25) * (if rnd:NextNumber() < 0.5 then -1 else 1)
		local a2 = if rnd:NextNumber() < 0.7 then -a1 * (0.6 + rnd:NextNumber() * 0.5) else a1 * 0.5
		local c1x, c1y = ax + dx * 0.3 + px * L * a1, ay + dy * 0.3 + py * L * a1
		local c2x, c2y = ax + dx * 0.72 + px * L * a2, ay + dy * 0.72 + py * L * a2
		local xs, ys, lens = {}, {}, {}
		local total = 0
		for i = 0, UnitLayer.SAMPLES do
			local q = i / UnitLayer.SAMPLES
			local r = 1 - q
			local x = r * r * r * ax + 3 * r * r * q * c1x + 3 * r * q * q * c2x + q * q * q * bx
			local y = r * r * r * ay + 3 * r * r * q * c1y + 3 * r * q * q * c2y + q * q * q * by
			if i > 0 then
				total += math.sqrt((x - xs[i]) ^ 2 + (y - ys[i]) ^ 2)
			end
			xs[i + 1], ys[i + 1], lens[i + 1] = x, y, total
		end
		path = { xs = xs, ys = ys, lens = lens, total = total }
		n._jet_path = path
	end
	-- (by length flown: an even speed along the curve)
	local want = math.clamp(t, 0, 1) * path.total
	local lens = path.lens
	local lo, hi = 1, #lens
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if lens[mid] < want then
			lo = mid
		else
			hi = mid
		end
	end
	local seg = lens[hi] - lens[lo]
	local f = if seg > 0 then (want - lens[lo]) / seg else 0
	return path.xs[lo] + (path.xs[hi] - path.xs[lo]) * f, path.ys[lo] + (path.ys[hi] - path.ys[lo]) * f
end
function UnitLayer._jet(self: any, uid: number, n: any, t: number, x: number, y: number, now: number)
	local st = self._state
	local cam = self.view.rig
	local j = self._jets[uid]
	if j == nil then
		local img = Instance.new("ImageLabel")
		img.Name = "Jet"
		img.BackgroundTransparency = 1
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.ResampleMode = Enum.ResamplerMode.Pixelated
		img.Size = UDim2.fromOffset(UnitLayer.JET_PX, UnitLayer.JET_PX)
		img.ZIndex = UnitLayer.Z + 3
		img.Parent = self.root
		j = { img = img, key = "", next = 0, boomed = false, gun = 0, bombs = false }
		self._jets[uid] = j
		if cam:on_screen(x, y, 200) then
			BattleFx.sfx("flyby")
		end
	end
	local x2, y2 = cam:map_to_screen(UnitLayer.jet_uv(st, n, math.min(1, t + 0.02), uid))
	local dx, dy = x2 - x, y2 - y
	-- (the side it faces changes only on a clear turn: flying straight up or down it would flip every frame)
	local right = j.right
	if right == nil or math.abs(dx) > 0.6 then
		right = dx >= 0
		j.right = right
	end
	local key = tostring(n.owner) .. (if right then "r" else "l")
	if j.key ~= key then
		if self._flags_map ~= st.map then
			self._flags_map = st.map
			local ok, f = pcall(Countries.flags_by_name, st.map)
			self._flags = if ok then f else {}
		end
		local o = st:get_owner(n.owner)
		local name = o and o.name
		local c = Countryball.vehicle_content("jet", name and self._flags[name], name, right)
		if c ~= nil then
			j.key = key
			j.img.ImageContent = c
		end
	end
	local tilt = 0
	if math.abs(dx) + math.abs(dy) > 0.01 then
		-- (nose along its course, up to straight up or down)
		tilt = if right then math.deg(math.atan2(dy, dx)) else math.deg(math.atan2(-dy, -dx))
		tilt = math.clamp(tilt, -95, 95)
	end
	j.img.Rotation = tilt
	j.img.Position = UDim2.fromOffset(math.round(x), math.round(y))
	j.img.Visible = cam:on_screen(x, y, UnitLayer.JET_PX)
	local tx, ty = cam:tile_to_screen(n.to_tile)
	if t >= UnitLayer.STRAFE_FROM and now >= j.next and j.img.Visible then
		j.next = now + UnitLayer.STRAFE_S
		local face = if right then 1 else -1
		self._bfx:shot(now, x + face * 14, y + 3, tx + (math.random() - 0.5) * 22, ty + (math.random() - 0.5) * 22, true)
		if now >= j.gun then
			j.gun = now + UnitLayer.GUN_S
			BattleFx.sfx("gun")
		end
	end
	if t >= UnitLayer.BOMB_AT and not j.bombs and j.img.Visible then
		-- the bombs: three dropping onto the target, landing as the strike hits
		j.bombs = true
		local fall = math.max(0.2, (0.97 - t) * (n.flight_ticks or 30) / Defs.TICK_RATE)
		self._bfx:bomb(now, x, y + 4, tx, ty, fall)
		self._bfx:bomb(now, x - 6, y + 4, tx + 10, ty - 6, fall * 1.05)
		self._bfx:bomb(now, x + 6, y + 4, tx - 9, ty + 5, fall * 1.1)
	end
	if t >= 0.97 and not j.boomed then
		j.boomed = true
		if j.img.Visible or cam:on_screen(tx, ty, 40) then
			BattleFx.sfx("boom")
		end
		self._bfx:blast(now, tx, ty, 26)
		self._bfx:blast(now + 0.1, tx + 10, ty - 6, 16)
		self._bfx:blast(now + 0.18, tx - 9, ty + 5, 14)
	end
end

function UnitLayer.tick(self: any, _dt: number)
	local st = self._state
	if st == nil then
		return
	end
	self._bfx:tick(FrameClock.now()) -- (Take Over the World!: the jets' shots, every frame)
	local cam = self.view.rig
	local rt = st.render_tick or st.tick or 0
	local k = tonumber(st.map and st.map.k_lin) or Rules.K_LIN
	local px = math.max(UnitLayer.MIN_PX, math.round(UnitLayer.UNIT_SIZE / k * cam.scale))
	-- a still camera over a crowded map: not every frame (see the header)
	local still = cam.version == self._cam_seen and px == self._px_seen and (cam._shake or 0) <= 0.01
	self._cam_seen, self._px_seen = cam.version, px
	local clock = FrameClock.now()
	if still and self._drawn >= UnitLayer.THROTTLE_FROM then
		local lively = self._selected >= 0
			or next(st.nukes) ~= nil
			or next(st.shells) ~= nil
			or next(st.sam_missiles) ~= nil
		local wait_s = if self._drawn >= UnitLayer.THROTTLE_3 and not lively
			then UnitLayer.THROTTLE_3_S
			else UnitLayer.THROTTLE_S
		if clock - self._drawn_at < wait_s then
			return
		end
	end
	self._drawn_at = clock
	local seen = self._seen
	table.clear(seen)
	self._dots_used = 0
	self._bars_used = 0
	table.clear(self._screen)
	local cars_shown = cam.scale / k * UnitLayer.DEVICE_RATIO >= UnitLayer.CARS_MIN_ZOOM
	local drawn = 0
	-- transport ships' wakes (under the sprites)
	local map = st.map
	local W0 = map.W or Defs.W
	local wake_w = math.max(UnitLayer.TRAIL_MIN_PX, cam.scale / k)
	for uid, w in self._wakes do
		local u = st.units[uid]
		if u == nil or u.path ~= w.path then
			self._wakes[uid] = nil
		end
	end
	for uid, u in st.units do
		if u.kind ~= Defs.U_TRANSPORT or #u.path < 2 then
			continue
		end
		local w = self._wakes[uid]
		if w == nil then
			-- (a curve may not pass over land: the map's water bodies, 0 on land)
			local wb, N0 = map.water_body, map.N or 0
			local is_water = if wb ~= nil
				then function(t: number): boolean
					return t >= 0 and t < N0 and buffer.readu16(wb, t * 2) ~= 0
				end
				else nil
			w = { path = u.path, route = WakeRoute.build(u.path, W0, k, is_water), x = 0, y = 0 }
			self._wakes[uid] = w
		end
		local route = w.route
		local ux, uy, seg = WakeRoute.at(route, UnitLayer.path_done(u, rt))
		w.x, w.y = ux, uy
		local c = st:owner_color(u.owner)
		local xs, ys = route.xs, route.ys
		local sx0, sy0 = cam:map_to_screen(xs[1], ys[1])
		for j = 1, seg do
			local sx1, sy1
			if j < seg then
				sx1, sy1 = cam:map_to_screen(xs[j + 1], ys[j + 1])
			else
				sx1, sy1 = cam:map_to_screen(ux, uy)
			end
			local half = math.abs(sx1 - sx0) + math.abs(sy1 - sy0)
			if half > 0 and cam:on_screen((sx0 + sx1) * 0.5, (sy0 + sy1) * 0.5, half * 0.5 + wake_w) then
				self:_bar(sx0, sy0, sx1, sy1, wake_w, c)
			end
			sx0, sy0 = sx1, sy1
		end
	end
	-- ships / trains
	local U_TRUCK, U_TRANSPORT, U_WARSHIP = Defs.U_TRUCK, Defs.U_TRANSPORT, Defs.U_WARSHIP
	local cars = UnitLayer.TRAIN_CARRIAGES
	for uid, u in st.units do
		local kind = u.kind
		local col = UNIT_COL[kind]
		if col == nil then
			continue
		end
		local pick = kind == U_TRANSPORT or kind == U_WARSHIP
		if kind == U_TRUCK and cars_shown then
			-- the cars behind the engine, back to front (the engine is drawn last, on top)
			local done = UnitLayer.path_done(u, rt)
			local step = UnitLayer.TRAIN_SPACING / k
			for j = cars + 1, 1, -1 do
				local cx, cy = cam:map_to_screen(UnitLayer.path_uv(st, u, done - j * step))
				if cam:on_screen(cx, cy, px) then
					self:_sprite(uid * 16 + j, if j > cars then COL_TRAIN else COL_CARRIAGE, u.owner, cx, cy, px, seen)
					drawn += 1
				end
			end
		end
		-- (a transport rides its smoothed route, at the head of its wake)
		local wake = if kind == U_TRANSPORT then self._wakes[uid] else nil
		local x, y
		if wake ~= nil then
			x, y = cam:map_to_screen(wake.x, wake.y)
		else
			x, y = cam:map_to_screen(UnitLayer.unit_uv(st, u, rt))
		end
		if not cam:on_screen(x, y, px) then
			continue
		end
		if pick then
			self._screen[uid] = Vector2.new(x, y)
		end
		local tint = if pick then tint_of(st, u.owner, "boat") else nil
		self:_sprite(uid * 16, col, u.owner, x, y, px, seen, tint)
		drawn += 1
	end
	self._drawn = drawn
	-- nukes: trail, sprite, target ring
	local now = FrameClock.now()
	local rings_seen = {}
	local trail_dots, rings_for_warheads = UnitLayer.trail_allowance(st.nukes)
	for uid, n in st.nukes do
		local t = math.clamp((rt - n.launch_tick) / math.max(n.flight_ticks, 1), 0, 1)
		local col = NUKE_COL[n.kind] or COL_ATOM
		local npx = px * (NUKE_SCALE[n.kind] or 1)
		local slot = NUKE_SLOT[n.kind]
		local ntint = tint_of(st, n.owner, if slot == nil then "nuke" else slot)
		if NUKE_PLAIN[n.kind] then
			local sx0, sy0 = cam:map_to_screen(UnitLayer.nuke_uv(st, n, t))
			if cam:on_screen(sx0, sy0, npx) then
				self:_sprite(uid * 16 + KEY_NUKE, col, n.owner, sx0, sy0, npx, seen, ntint)
			end
			continue
		end
		local c = ntint or st:owner_color(n.owner)
		-- trail: the curve flown so far, a line through points every TRAIL_STEP full-size tiles, up to
		-- the munition (it was a dot at each point, spaced wider than a dot: a broken line that looked
		-- glitchy; solid since 2026-10-12)
		local W = st.map.W or Defs.W
		local sx, sy = centre(n.from_tile, W)
		local dx, dy = centre(n.to_tile, W)
		local len = math.sqrt((dx - sx) ^ 2 + (dy - sy) ^ 2) * 1.4 + 1
		local steps = math.clamp(math.floor(len * k / UnitLayer.TRAIL_STEP), 2, TrailBudget.MAX)
		local thick = math.max(2, math.round(cam.scale * UnitLayer.TRAIL_WIDTH))
		-- (an air strike flies its curved route: UnitLayer.jet_uv)
		local uv = UnitLayer.nuke_uv
		if n.kind == Defs.N_AIRSTRIKE then
			uv = function(s0: any, n0: any, q: number)
				return UnitLayer.jet_uv(s0, n0, q, uid)
			end
		end
		local x, y = cam:map_to_screen(uv(st, n, t))
		-- (the newest `trail_dots` points: the whole trail unless many munitions fly at once)
		local newest = math.floor(steps * t)
		local px0, py0 = nil, nil
		for i = math.max(0, newest - trail_dots + 1), newest + 1 do
			local tx, ty
			if i > newest then
				tx, ty = x, y
			else
				tx, ty = cam:map_to_screen(uv(st, n, i / steps))
			end
			if px0 ~= nil and (cam:on_screen(tx, ty, thick) or cam:on_screen(px0, py0, thick)) then
				self:_bar(px0, py0, tx, ty, thick, c)
			end
			px0, py0 = tx, ty
		end
		if n.kind == Defs.N_AIRSTRIKE then
			-- (Take Over the World!: an air strike is the owner's Countryball jet, strafing at the end)
			self:_jet(uid, n, t, x, y, now)
		elseif cam:on_screen(x, y, npx) then
			self:_sprite(uid * 16 + KEY_NUKE, col, n.owner, x, y, npx, seen, ntint)
		end
		if n.kind == Defs.N_WARHEAD and not rings_for_warheads then
			continue
		end
		-- (none for a MIRV itself, rings only for the atom, the
		-- hydrogen bomb and the warhead; a ring as wide as its spread, 1,500 full-size tiles, tinted
		-- the whole screen for the seconds it flew, 2026-10-12)
		if n.kind == Defs.N_MIRV then
			continue
		end
		-- target: the blast ring, pulsing (red when it hits the local player)
		local ViewRules = self.view.view_rules
		local _, outer = 0, 12
		if ViewRules then
			_, outer = ViewRules.nuke_radii(n.kind)
		end
		local ring = self._rings[uid]
		if ring == nil then
			ring = self:_ring(self.root, "NukeTarget", UnitLayer.Z - 2)
			self._rings[uid] = ring
		end
		rings_seen[uid] = true
		local rx, ry = cam:tile_to_screen(n.to_tile)
		local d = math.max(8, outer * 2 * cam.scale)
		ring.Size = UDim2.fromOffset(d, d)
		ring.Position = UDim2.fromOffset(math.round(rx), math.round(ry))
		local mine = st:tile_owner(n.to_tile) == st.local_owner and st.local_owner ~= 0
		local rc = if mine then Color3.new(1, 0.16, 0.12) else c
		local stroke = ring:FindFirstChildOfClass("UIStroke") :: UIStroke
		stroke.Color = rc
		stroke.Transparency = 0.2 + 0.3 * (0.5 + 0.5 * math.sin(now * 6))
		ring.BackgroundColor3 = rc
		ring.BackgroundTransparency = 0.85
		ring.Visible = true
	end
	for uid, j in self._jets do -- (the jets whose strike has landed)
		if st.nukes[uid] == nil then
			j.img:Destroy()
			self._jets[uid] = nil
		end
	end
	for uid, r in self._rings do
		if not rings_seen[uid] then
			r:Destroy()
			self._rings[uid] = nil
		end
	end
	-- shells: from the shooter's tile to the target unit, arriving at impact_tick
	local W = st.map.W or Defs.W
	for id, sh in st.shells do
		local target = st.units[sh.target_uid]
		if target == nil then
			continue
		end
		local t = math.clamp((rt - sh.fire_tick) / math.max(sh.impact_tick - sh.fire_tick, 1), 0, 1)
		local ax, ay = centre(sh.from_tile, W)
		local bx, by = UnitLayer.unit_uv(st, target, sh.impact_tick)
		local x, y = cam:map_to_screen(ax + (bx - ax) * t, ay + (by - ay) * t)
		if cam:on_screen(x, y, px) then
			local owner = if sh.shooter_kind == 0 and st.units[sh.shooter_id]
				then st.units[sh.shooter_id].owner
				else st:tile_owner(sh.from_tile)
			self:_sprite(id * 16 + KEY_SHELL, COL_SHELL, owner, x, y, px, seen)
		end
	end
	-- SAM missiles: from the SAM to the nuke's position at the intercept
	for nuke_uid, m in st.sam_missiles do
		local n = st.nukes[nuke_uid]
		local sam = st.structures[m.sam_sid]
		if n == nil or sam == nil then
			continue
		end
		local t = math.clamp((rt - m.fire_tick) / math.max(m.intercept_tick - m.fire_tick, 1), 0, 1)
		local ax, ay = centre(sam.tile, W)
		local ti = math.clamp((m.intercept_tick - n.launch_tick) / math.max(n.flight_ticks, 1), 0, 1)
		local bx, by = UnitLayer.nuke_uv(st, n, ti)
		local x, y = cam:map_to_screen(ax + (bx - ax) * t, ay + (by - ay) * t)
		if cam:on_screen(x, y, px) then
			self:_sprite(nuke_uid * 16 + KEY_SAM, COL_SAM, sam.owner, x, y, px, seen, tint_of(st, sam.owner, "missile"))
		end
	end
	for key, s in self._sprites do
		if not seen[key] then
			self:_release(s)
			self._sprites[key] = nil
		end
	end
	-- (the pools: a few spares stay hidden, the rest go)
	local spare = UnitLayer.POOL_SPARE
	for i = #self._dots, self._dots_used + 1, -1 do
		local d = self._dots[i]
		if i > self._dots_used + spare then
			d:Destroy()
			self._dots[i] = nil
		elseif d.Visible then
			d.Visible = false
		end
	end
	for i = #self._bars, self._bars_used + 1, -1 do
		local b = self._bars[i]
		if i > self._bars_used + spare then
			b.f:Destroy()
			self._bars[i] = nil
		elseif b.shown then
			b.shown = false
			b.f.Visible = false
		end
	end
	-- selection ring
	local sp = self._screen[self._selected]
	if sp then
		local ring = self._sel_ring
		ring.Size = UDim2.fromOffset(px * 2, px * 2)
		ring.Position = UDim2.fromOffset(math.round(sp.X), math.round(sp.Y))
		ring.Visible = true
	else
		self._sel_ring.Visible = false
	end
end

--- The warship or transport drawn nearest `pos` within `radius_px`, or -1.
function UnitLayer.unit_at_screen(self: any, pos: Vector2, radius_px: number): number
	local st = self._state
	if st == nil then
		return -1
	end
	local best, best_d = -1, radius_px
	for uid, p in self._screen do
		local u = st.units[uid]
		if u and (u.kind == Defs.U_WARSHIP or u.kind == Defs.U_TRANSPORT) then
			local d = (p - pos).Magnitude
			if d <= best_d then
				best, best_d = uid, d
			end
		end
	end
	return best
end

return UnitLayer
