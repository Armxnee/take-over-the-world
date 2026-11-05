--!strict
-- 2D map renderer: one EditableImage (PPC px per cell) written in dirty chunks,
-- 2D camera (pan/zoom), nameplates and pick helpers. No Parts per cell.
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local State = require(script.Parent.State)
local Cosmetics = require(ReplicatedStorage.Shared.Cosmetics)
local Art = require(script.Parent.Art)
local Icons = require(script.Parent.Icons)
local Flags = require(ReplicatedStorage.Shared.Flags)
local FlagPix = require(ReplicatedStorage.Shared.FlagPix)

local PPC = Config.Map.PPC
local CH = Config.Map.Chunk

local MapView = {}
MapView.z = 6 -- screen px per cell
MapView.ox = 0
MapView.oy = 0
MapView.highlight = 0
MapView.error = nil :: string?
MapView.tileKey = ""
MapView.camDirty = true
-- rail connections drawn as grid L-lines: every own factory always, plus the placement preview
MapView.connections = {} :: { { from: number, to: { number }, preview: boolean? } }
MapView.allies = {} :: { [number]: boolean }

-- recolour borders of nations whose alliance with me changed
function MapView.setAllies(set: { [number]: boolean })
	local changed = {}
	for id in MapView.allies do
		if not set[id] then
			changed[#changed + 1] = id
		end
	end
	for id in set do
		if not MapView.allies[id] then
			changed[#changed + 1] = id
		end
	end
	MapView.allies = set
	for _, id in changed do
		MapView.redrawOwners(id, id)
	end
end

local frame: Frame
local image: Frame -- holds one ImageLabel per EditableImage tile
local labels: Frame
local markers: Frame
local ring: Frame
local buildPrev: Frame
local markerById: { [number]: any } = {}
local unitLayer: Frame
local unitById: { [number]: any } = {}
local dotPool: { Frame } = {}
local preview: Frame
local selMarker: Frame
local previewStroke: UIStroke
local reticle: Frame
local img: boolean = false -- true once tiles exist
local tiles: { any } = {}
local TILE = Config.Map.Tile
local chunks: { any } = {}
local chunkCols = 0
local dirtyChunks: { [any]: boolean } = {}
local plates: { [number]: { frame: Frame, name: TextLabel, troops: TextLabel } } = {}

local function pack(c: Color3): number
	return math.floor(c.R * 255 + 0.5) + math.floor(c.G * 255 + 0.5) * 256 + math.floor(c.B * 255 + 0.5) * 65536 + 255 * 16777216
end

-- Real-world look: every cell has a colour from the map's Look module (land cover and
-- relief on land, shallow shelves and deep basins at sea; tools/build_look.py).
local OCEAN = Color3.fromHex("2D6A9A")
local ME_EDGE = pack(Color3.fromHex("F4F7FA"))
local HL_EDGE = pack(Color3.fromHex("FFD84D"))
local ALLY_GREEN = Color3.fromHex("46D27A")
local allyEdgeCache: { [number]: number } = {}
local function allyEdge(o: number): number
	local v = allyEdgeCache[o]
	if not v then
		local n = State.nations[o]
		local c = if n then n.color else ALLY_GREEN
		v = pack(Color3.new(c.R * 0.74, c.G * 0.74, c.B * 0.74):Lerp(ALLY_GREEN, 0.35))
		allyEdgeCache[o] = v
	end
	return v
end
local lookIdx: buffer = buffer.create(1)
local lookCol: { [number]: Color3 } = {}
local lookPal: { [number]: number } = {}
local DIGITS: { [number]: number } = {}
for k, ch in string.split("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-_", "") do
	DIGITS[string.byte(ch)] = k - 1
end

local function loadLook(W: number, H: number)
	local maps = ReplicatedStorage.Shared:FindFirstChild("Maps")
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local want = remotes and remotes:GetAttribute("Map")
	local order = { want }
	for id in Config.Maps do
		table.insert(order, id)
	end
	local m: any = nil
	for _, id in order do
		local def = Config.Maps[id :: any]
		local mod = def and def.Module and maps and maps:FindFirstChild(def.Module .. "Look")
		if mod then
			local ok, res = pcall(require, mod)
			if ok and #res.px == W * H then
				m = res
				break
			end
		end
	end
	lookCol, lookPal = {}, {}
	lookIdx = buffer.create(W * H)
	if not m then
		lookCol[0], lookCol[1] = OCEAN, Color3.fromHex("CFC8B0")
		lookPal[0], lookPal[1] = pack(lookCol[0]), pack(lookCol[1])
		for i = 0, W * H - 1 do
			buffer.writeu8(lookIdx, i, if buffer.readu8(State.terrain, i) == 0 then 0 else 1)
		end
		return
	end
	for k, hx in m.pal do
		lookCol[k - 1] = Color3.fromHex(hx)
		lookPal[k - 1] = pack(lookCol[k - 1])
	end
	local px = m.px
	for i = 0, W * H - 1 do
		buffer.writeu8(lookIdx, i, DIGITS[string.byte(px, i + 1)] or 0)
	end
end

-- territory without a flag: the nation colour laid over the real terrain (semi-opaque)
local fillCache: { [number]: number } = {}
local edgeCache: { [number]: number } = {}
local function fillFor(o: number, li: number): number
	local key = o * 64 + li
	local v = fillCache[key]
	if not v then
		local n = State.nations[o]
		local base = lookCol[li] or OCEAN
		v = pack(if n then base:Lerp(n.color, 0.62) else base)
		if n then
			fillCache[key] = v
		end
	end
	return v
end
local function edgeFor(o: number): number
	local v = edgeCache[o]
	if not v then
		local n = State.nations[o]
		local c = if n then n.color else Color3.new(0, 0, 0)
		v = pack(Color3.new(c.R * 0.74, c.G * 0.74, c.B * 0.74)) -- a step darker than the fill
		if n then
			edgeCache[o] = v
		end
	end
	return v
end
function MapView.clearColorCache()
	fillCache, edgeCache, allyEdgeCache = {}, {}, {}
end

local function chunkOf(x: number, y: number)
	return chunks[(y // CH) * chunkCols + (x // CH) + 1]
end

-- per-owner skin cache: { pattern, shade, hi, edge? } or false
local skinCache: { [number]: any } = {}
local function skinFor(o: number, fill: number): any
	local n = State.nations[o]
	local sk = n and n.skin and Cosmetics.Skins[n.skin]
	if not sk then
		return nil
	end
	local key = o * 65536 + fill % 65536
	local v = skinCache[key]
	if v == nil then
		local r, g, b = fill % 256, (fill // 256) % 256, (fill // 65536) % 256
		local base = Color3.fromRGB(r, g, b)
		local ec = Cosmetics.edgeColor(sk.pattern)
		v = {
			pattern = sk.pattern,
			shade = pack(base:Lerp(Color3.new(0, 0, 0), 0.18)),
			hi = pack(base:Lerp(Color3.new(1, 1, 1), 0.3)),
			edge = if ec then pack(ec) else nil,
		}
		skinCache[key] = v
	end
	return v
end

-- Flag territory: the nation's (pixel) flag is stretched once over its whole land, like a
-- skin. AI countries fly their real flag, players their equipped shop flag; a territory
-- skin takes precedence. The flag frame covers the nation's bounding box and grows in
-- steps (x1.3), so a growing nation is repainted only a handful of times.
local FW, FH = FlagPix.W, FlagPix.H
local flagCache: { [number]: any } = {}
local cosGrid: { [string]: any } = {}
local blendCache: { [number]: { [number]: number } } = {}
local bbox: { [number]: { number } } = {}
local frames: { [number]: { number } } = {}
local refit: { [number]: boolean } = {}

function MapView.cosmeticGrid(id: string): any
	if cosGrid[id] == nil then
		local spec = Flags.fromCosmetic(Cosmetics.Flags[id])
		cosGrid[id] = if spec then FlagPix.fromSpec(spec) else false
	end
	return cosGrid[id] or nil
end

local function flagFor(o: number): any
	local v = flagCache[o]
	if v == nil then
		local n = State.nations[o]
		if not n then
			return nil
		end
		v = false
		if n.skin then
			v = false
		elseif n.flag and Cosmetics.Flags[n.flag] then
			v = MapView.cosmeticGrid(n.flag) or false
		elseif n.kind ~= "human" then
			v = FlagPix.forCountry(n.name) or false
		end
		flagCache[o] = v
	end
	return v or nil
end
MapView.flagFor = flagFor

local function fitFrame(o: number)
	local b = bbox[o]
	if not b then
		return
	end
	local bw, bh = b[3] - b[1] + 1, b[4] - b[2] + 1
	local fw = math.max(bw, bh * 1.5, 9)
	fw = 9 * 1.3 ^ math.ceil(math.log(fw / 9) / math.log(1.3) - 1e-6)
	local fh = fw / 1.5
	frames[o] = { (b[1] + b[3] + 1) / 2 - fw / 2, (b[2] + b[4] + 1) / 2 - fh / 2, fw, fh }
end

local function grow(o: number, x: number, y: number)
	local b = bbox[o]
	if not b then
		bbox[o] = { x, y, x, y }
		fitFrame(o)
		return
	end
	if x < b[1] then b[1] = x end
	if y < b[2] then b[2] = y end
	if x > b[3] then b[3] = x end
	if y > b[4] then b[4] = y end
	local f = frames[o]
	if x < f[1] or y < f[2] or x + 1 > f[1] + f[3] or y + 1 > f[2] + f[4] then
		refit[o] = true
	end
end

local function blendFor(o: number, g: any, fi: number, li: number): number
	local t = blendCache[o]
	if not t then
		t = {}
		blendCache[o] = t
	end
	local key = fi * 64 + li
	local v = t[key]
	if not v then
		local c = g.pal[fi + 1] or Color3.new(1, 1, 1)
		v = pack(c:Lerp(lookCol[li] or c, 0.16))
		t[key] = v
	end
	return v
end

function MapView.clearSkinCache()
	skinCache = {}
	flagCache = {}
	blendCache = {}
end

local function drawCell(i: number)
	local W, H = State.W, State.H
	local x, y = i % W, i // W
	local ch = chunkOf(x, y)
	local own = State.owner
	local o = buffer.readu16(own, i * 2)
	local t = buffer.readu8(State.terrain, i)
	local li = buffer.readu8(lookIdx, i)
	local fill, edge = 0, 0
	local eL, eR, eU, eD = false, false, false, false
	if t == 0 or o == 0 then
		fill = lookPal[li] or 0
	else
		fill = fillFor(o, li)
		edge = if o == State.me then ME_EDGE
			elseif o == MapView.highlight then HL_EDGE
			elseif MapView.allies[o] then allyEdge(o)
			else edgeFor(o)
		eL = x == 0 or buffer.readu16(own, (i - 1) * 2) ~= o
		eR = x == W - 1 or buffer.readu16(own, (i + 1) * 2) ~= o
		eU = y == 0 or buffer.readu16(own, (i - W) * 2) ~= o
		eD = y == H - 1 or buffer.readu16(own, (i + W) * 2) ~= o
	end
	local buf, pw = ch.buf, ch.pw
	local lx, ly = (x - ch.x0) * PPC, (y - ch.y0) * PPC
	local sk = if o ~= 0 then skinFor(o, fill) else nil
	if sk and sk.edge and o ~= MapView.highlight then
		edge = sk.edge
	end
	local g: any = nil
	local fx0, fy0, sx, sy = 0, 0, 0, 0
	if not sk and o ~= 0 and t ~= 0 then
		g = flagFor(o)
		if g then
			grow(o, x, y)
			local f = frames[o]
			fx0, fy0 = f[1], f[2]
			sx, sy = FW / (f[3] * PPC), FH / (f[4] * PPC)
		end
	end
	for py = 0, PPC - 1 do
		local base = ((ly + py) * pw + lx) * 4
		local rowEdge = (py == 0 and eU) or (py == PPC - 1 and eD)
		local fyi = 0
		if g then
			fyi = math.clamp(math.floor(((y - fy0) * PPC + py + 0.5) * sy), 0, FH - 1) * FW
		end
		for px = 0, PPC - 1 do
			local col = fill
			if rowEdge or (px == 0 and eL) or (px == PPC - 1 and eR) then
				col = edge
			elseif sk then
				local v = Cosmetics.skinPixel(sk.pattern, x * PPC + px, y * PPC + py)
				col = if v == 1 then sk.shade elseif v == 2 then sk.hi else fill
			elseif g then
				local fxi = math.clamp(math.floor(((x - fx0) * PPC + px + 0.5) * sx), 0, FW - 1)
				col = blendFor(o, g, buffer.readu8(g.idx, fyi + fxi), li)
			end
			buffer.writeu32(buf, base + px * 4, col)
		end
	end
	dirtyChunks[ch] = true
end

function MapView.cellsChanged(list: { number })
	if not img then
		return
	end
	local W, N = State.W, State.N
	local done: { [number]: boolean } = {}
	for _, i in list do
		local x = i % W
		for _, j in { i, if x > 0 then i - 1 else -1, if x < W - 1 then i + 1 else -1, i - W, i + W } do
			if j >= 0 and j < N and not done[j] then
				done[j] = true
				drawCell(j)
			end
		end
	end
end

function MapView.redrawAll(yield: boolean)
	for i = 0, State.N - 1 do
		drawCell(i)
		if yield and i % 6000 == 5999 then
			task.wait()
		end
	end
end

-- redraw only cells of the given owners (selection highlight changes)
function MapView.redrawOwners(a: number, b: number)
	local own = State.owner
	for i = 0, State.N - 1 do
		local o = buffer.readu16(own, i * 2)
		if o ~= 0 and (o == a or o == b) then
			drawCell(i)
		end
	end
end

function MapView.setHighlight(nid: number)
	if nid == MapView.highlight then
		return
	end
	local old = MapView.highlight
	MapView.highlight = nid
	MapView.redrawOwners(old, nid)
end

----------------------------------------------------------------------------
-- camera

local function apply()
	local z = MapView.z
	MapView.camDirty = true
	image.Size = UDim2.fromOffset(State.W * z, State.H * z)
	image.Position = UDim2.fromOffset(MapView.ox, MapView.oy)
	-- whole-pixel tile edges so neighbouring tiles never show a seam
	for _, t in tiles do
		local x0, y0 = math.floor(t.x0 * z), math.floor(t.y0 * z)
		local x1, y1 = math.floor((t.x0 + t.w) * z), math.floor((t.y0 + t.h) * z)
		t.label.Position = UDim2.fromOffset(x0, y0)
		t.label.Size = UDim2.fromOffset(x1 - x0 + 1, y1 - y0 + 1)
	end
end

local function clampCam()
	local s = frame.AbsoluteSize
	local mw, mh = State.W * MapView.z, State.H * MapView.z
	local m = 80
	MapView.ox = math.clamp(MapView.ox, s.X - mw - (s.X - m), s.X - m)
	MapView.oy = math.clamp(MapView.oy, s.Y - mh - (s.Y - m), s.Y - m)
end

function MapView.minZoom(): number
	local s = frame.AbsoluteSize
	return math.min(s.X / math.max(State.W, 1), s.Y / math.max(State.H, 1)) * 0.92
end

function MapView.fit()
	local s = frame.AbsoluteSize
	MapView.z = MapView.minZoom()
	MapView.ox = (s.X - State.W * MapView.z) / 2
	MapView.oy = (s.Y - State.H * MapView.z) / 2
	apply()
end

function MapView.pan(dx: number, dy: number)
	MapView.ox += dx
	MapView.oy += dy
	clampCam()
	apply()
end

function MapView.zoomAt(f: number, p: Vector2)
	local z0 = MapView.z
	local z1 = math.clamp(z0 * f, MapView.minZoom(), 48)
	local cx, cy = (p.X - MapView.ox) / z0, (p.Y - MapView.oy) / z0
	MapView.z = z1
	MapView.ox = p.X - cx * z1
	MapView.oy = p.Y - cy * z1
	clampCam()
	apply()
end

function MapView.centerOn(cx: number, cy: number, z: number?)
	local s = frame.AbsoluteSize
	if z then
		MapView.z = math.clamp(z, MapView.minZoom(), 48)
	end
	MapView.ox = s.X / 2 - (cx + 0.5) * MapView.z
	MapView.oy = s.Y / 2 - (cy + 0.5) * MapView.z
	clampCam()
	apply()
end

-- local (frame) coordinates from an InputObject position
function MapView.toLocal(p: Vector3 | Vector2): Vector2
	local a = frame.AbsolutePosition
	return Vector2.new(p.X - a.X, p.Y - a.Y)
end

function MapView.center(): Vector2
	return frame.AbsoluteSize / 2
end

-- Cell under a local point. Water clicks snap to land within ~14 screen px so
-- narrow coasts and small islands are selectable at any zoom.
function MapView.cellAt(p: Vector2, snap: boolean?): number?
	local W, H = State.W, State.H
	local z = MapView.z
	local fx, fy = (p.X - MapView.ox) / z, (p.Y - MapView.oy) / z
	local x, y = math.floor(fx), math.floor(fy)
	if x < 0 or y < 0 or x >= W or y >= H then
		return nil
	end
	local i = y * W + x
	if State.claimable_(i) or not snap then
		return i
	end
	local r = math.max(1, math.ceil(14 / z))
	local best, bd = nil, math.huge
	for yy = math.max(0, y - r), math.min(H - 1, y + r) do
		for xx = math.max(0, x - r), math.min(W - 1, x + r) do
			local j = yy * W + xx
			if State.claimable_(j) then
				local d = (xx + 0.5 - fx) ^ 2 + (yy + 0.5 - fy) ^ 2
				if d < bd then
					best, bd = j, d
				end
			end
		end
	end
	return best or i
end

function MapView.cellToLocal(x: number, y: number): Vector2
	return Vector2.new(MapView.ox + (x + 0.5) * MapView.z, MapView.oy + (y + 0.5) * MapView.z)
end

----------------------------------------------------------------------------
-- markers

function MapView.showPreview(cell: number?, r: number, ok: boolean)
	if not cell then
		preview.Visible = false
		return
	end
	local p = MapView.cellToLocal(cell % State.W, cell // State.W)
	local d = (r * 2 + 1) * MapView.z
	preview.Size = UDim2.fromOffset(d, d)
	preview.Position = UDim2.fromOffset(p.X, p.Y)
	local s = previewStroke
	s.Color = if ok then Color3.fromHex("4ADE80") else Color3.fromHex("FF5C61")
	preview.BackgroundColor3 = s.Color
	preview.Visible = true
end

function MapView.showSelection(cell: number?)
	if not cell or cell < 0 then
		selMarker.Visible = false
		return
	end
	local p = MapView.cellToLocal(cell % State.W, cell // State.W)
	local d = math.max(14, MapView.z * 2.5)
	selMarker.Size = UDim2.fromOffset(d, d)
	selMarker.Position = UDim2.fromOffset(p.X, p.Y)
	selMarker.Visible = true
end

function MapView.showReticle(on: boolean)
	reticle.Visible = on
end

----------------------------------------------------------------------------
-- nameplates

local FONT = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)
local FONT_M = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Medium)

local function plateFor(id: number)
	local p = plates[id]
	if p then
		return p
	end
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromOffset(200, 40)
	local nm = Instance.new("TextLabel")
	nm.BackgroundTransparency = 1
	nm.Size = UDim2.fromScale(1, 0.58)
	nm.FontFace = FONT
	nm.TextScaled = true
	nm.TextColor3 = Color3.new(0.05, 0.05, 0.05)
	local ns = Instance.new("UIStroke")
	ns.Thickness = 1.6
	ns.Parent = nm
	nm.Parent = f
	local tr = Instance.new("TextLabel")
	tr.BackgroundTransparency = 1
	tr.Position = UDim2.fromScale(0, 0.58)
	tr.Size = UDim2.fromScale(1, 0.42)
	tr.FontFace = FONT_M
	tr.TextScaled = true
	tr.TextColor3 = Color3.new(0.05, 0.05, 0.05)
	local ts = Instance.new("UIStroke")
	ts.Thickness = 1.3
	ts.Parent = tr
	tr.Parent = f
	local fl = Instance.new("ImageLabel")
	fl.BackgroundTransparency = 1
	fl.ResampleMode = Enum.ResamplerMode.Pixelated
	fl.Visible = false
	local fs = Instance.new("UIStroke")
	fs.Color = Color3.fromHex("0E1217")
	fs.Thickness = 1.5
	fs.Parent = fl
	fl.Parent = f
	f.Parent = labels
	p = { frame = f, name = nm, troops = tr, flag = fl, flagSpec = nil :: any, nameStroke = ns, troopStroke = ts }
	plates[id] = p
	return p
end

-- small flag image for nameplates (cached per pixel grid)
local flagImgCache: { [any]: EditableImage } = {}
function MapView.flagImage(g: any): EditableImage?
	if flagImgCache[g] then
		return flagImgCache[g]
	end
	local W, H = FW, FH
	local ok, e = pcall(function()
		return AssetService:CreateEditableImage({ Size = Vector2.new(W, H) })
	end)
	if not ok or not e then
		return nil
	end
	local b = buffer.create(W * H * 4)
	for y = 0, H - 1 do
		for x = 0, W - 1 do
			buffer.writeu32(b, (y * W + x) * 4, pack(g.pal[buffer.readu8(g.idx, y * W + x) + 1]))
		end
	end
	e:WritePixelsBuffer(Vector2.zero, Vector2.new(W, H), b)
	flagImgCache[g] = e
	return e
end

function MapView.updatePlates()
	local z = MapView.z
	for id, n in State.nations do
		local cnt = State.cnt[id] or 0
		local p = plateFor(id)
		if cnt <= 0 or not n.alive then
			p.frame.Visible = false
		else
			local cx, cy = State.sumX[id] / cnt, State.sumY[id] / cnt
			local size = math.sqrt(cnt) * z * 0.32
			if size < 5 and id ~= State.me then
				p.frame.Visible = false
			else
				size = math.clamp(size, 9, 30)
				local pos = MapView.cellToLocal(cx, cy)
				p.frame.Position = UDim2.fromOffset(pos.X, pos.Y)
				p.frame.Size = UDim2.fromOffset(size * 9, size * 1.75)
				p.name.Text = if id == State.me then ("★ " .. n.name) else n.name
				-- RoWorld-style plate: dark text (black players, grey nations / tribes) outlined in the owner's colour
				local shade = if n.kind == "human" then 0.04 elseif n.kind == "tribe" then 0.4 else 0.3
				p.name.TextColor3 = Color3.new(shade, shade, shade)
				p.troops.TextColor3 = p.name.TextColor3
				p.nameStroke.Color = n.color:Lerp(Color3.new(1, 1, 1), 0.15)
				p.troopStroke.Color = p.nameStroke.Color
				p.troops.Text = State.fmt(n.troops) .. (if MapView.allies[id] then "  · ally" else "")
				local spec = flagFor(id) or (n.flag and MapView.cosmeticGrid(n.flag))
				if p.flagSpec ~= spec then
					p.flagSpec = spec
					p.flag.Visible = spec ~= nil
					if spec then
						local fimg = MapView.flagImage(spec)
						if fimg then
							p.flag.ImageContent = Content.fromObject(fimg)
						end
					end
				end
				if spec then
					local h = p.frame.AbsoluteSize.Y * 0.5
					local tb = p.name.TextBounds.X
					p.flag.Size = UDim2.fromOffset(h * 1.5, h)
					p.flag.Position = UDim2.new(0.5, -tb / 2 - 6, 0.3, 0)
				end
				p.frame.Visible = true
			end
		end
	end
end

----------------------------------------------------------------------------

----------------------------------------------------------------------------
-- structure markers

local function markerSize(): number
	return math.clamp(MapView.z * 3, 12, 30)
end

function MapView.syncStructures()
	for id, m in markerById do
		if not State.structures[id] then
			m.frame:Destroy()
			markerById[id] = nil
		end
	end
	for id, s in State.structures do
		local m = markerById[id]
		if not m then
			local f = Instance.new("Frame")
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			f.BorderSizePixel = 0
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0.3, 0)
			c.Parent = f
			local st = Instance.new("UIStroke")
			st.Thickness = 1.5
			st.Color = Color3.fromHex("0E1217")
			st.Parent = f
			local icon = Instance.new("ImageLabel")
			icon.BackgroundTransparency = 1
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.fromScale(0.5, 0.5)
			icon.Size = UDim2.fromScale(0.72, 0.72)
			Icons.apply(icon, s.kind)
			icon.Parent = f
			local lvl = Instance.new("TextLabel")
			lvl.BackgroundTransparency = 1
			lvl.AnchorPoint = Vector2.new(1, 1)
			lvl.Position = UDim2.new(1, 4, 1, 4)
			lvl.Size = UDim2.fromScale(0.55, 0.55)
			lvl.TextScaled = true
			lvl.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.ExtraBold)
			lvl.TextColor3 = Color3.new(1, 1, 1)
			lvl.TextStrokeTransparency = 0.2
			lvl.Parent = f
			f.Parent = markers
			m = { frame = f, icon = icon, lvl = lvl, stroke = st }
			markerById[id] = m
		end
		local n = State.nations[s.owner]
		m.frame.BackgroundColor3 = if n then n.color:Lerp(Color3.new(0, 0, 0), 0.25) else Color3.new(0.3, 0.3, 0.3)
		m.stroke.Color = if s.owner == State.me then Color3.new(1, 1, 1) else Color3.fromHex("0E1217")
		m.lvl.Text = if s.kind == "city" and s.level > 1 then tostring(s.level) else ""
	end
	MapView.camDirty = true
end

function MapView.updateMarkers()
	local sz = markerSize()
	local now = workspace:GetServerTimeNow()
	local show = MapView.z >= 2.2
	for id, m in markerById do
		local s = State.structures[id]
		if s then
			local p = MapView.cellToLocal(s.cell % State.W, s.cell // State.W)
			m.frame.Position = UDim2.fromOffset(p.X, p.Y)
			m.frame.Size = UDim2.fromOffset(sz, sz)
			local building = not s.done and now < s.readyAt
			local disabled = s.disabledAt > now
			m.frame.BackgroundTransparency = if building then 0.55 else 0
			m.icon.ImageTransparency = if building or disabled then 0.5 else 0
			m.frame.Visible = show
		end
	end
end

-- pooled rings for overlays / incoming missiles: list of { cell, radius, color, alpha }
local ringPool: { Frame } = {}
function MapView.drawRings(list: { any })
	local z = MapView.z
	for k, r in list do
		local f = ringPool[k]
		if not f then
			f = Instance.new("Frame")
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0.5, 0)
			c.Parent = f
			local s = Instance.new("UIStroke")
			s.Thickness = 1.5
			s.Parent = f
			f.ZIndex = 1
			f.Parent = unitLayer
			ringPool[k] = f
		end
		local p = MapView.cellToLocal(r.cell % State.W, r.cell // State.W)
		local d = (r.radius * 2 + 1) * z
		f.Size = UDim2.fromOffset(d, d)
		f.Position = UDim2.fromOffset(p.X, p.Y)
		f.BackgroundColor3 = r.color
		f.BackgroundTransparency = r.alpha
		local s = f:FindFirstChildOfClass("UIStroke")
		if s then
			s.Color = r.color
		end
		f.Visible = true
	end
	for k = #list + 1, #ringPool do
		ringPool[k].Visible = false
	end
end

-- expanding flash for impacts / interceptions
function MapView.flash(cell: number, radius: number, color: Color3)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 0.1
	f.ZIndex = 6
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = f
	f.Parent = unitLayer
	local t0 = os.clock()
	local conn
	conn = game:GetService("RunService").RenderStepped:Connect(function()
		local a = (os.clock() - t0) / 0.9
		if a >= 1 then
			conn:Disconnect()
			f:Destroy()
			return
		end
		local p = MapView.cellToLocal(cell % State.W, cell // State.W)
		local d = (radius * 2 + 1) * MapView.z * (0.3 + 0.9 * a)
		f.Size = UDim2.fromOffset(d, d)
		f.Position = UDim2.fromOffset(p.X, p.Y)
		f.BackgroundTransparency = 0.1 + 0.9 * a
	end)
end

local UNIT_STYLE = {
	train = { shape = 0.25, scale = 1.1, fill = nil, stroke = Color3.new(1, 1, 1) },
	trade = { shape = 0.5, scale = 1.3, fill = Color3.fromHex("F5C451"), stroke = nil },
	transport = { shape = 0.5, scale = 1.8, fill = nil, stroke = Color3.fromHex("0E1217") },
	warship = { shape = 0.15, scale = 2.0, fill = Color3.fromHex("1A222C"), stroke = nil },
	missile = { shape = 0.5, scale = 1.4, fill = Color3.fromHex("FF5C61"), stroke = Color3.new(1, 1, 1) },
	fighter = { shape = 0.05, scale = 1.3, fill = nil, stroke = Color3.new(1, 1, 1), air = true },
	bomber = { shape = 0.2, scale = 1.9, fill = nil, stroke = Color3.fromHex("0E1217"), air = true, long = true },
}

-- unit kind -> sprite design, skin slot and size (in cells)
local SPRITE = {
	transport = { "transport", "boat", 2.4 },
	warship = { "warship", "boat", 2.6 },
	trade = { "trade", "boat", 2.4 },
	train = { "train", nil, 1.8 },
	fighter = { "fighter", "plane", 2.2 },
	bomber = { "bomber", "plane", 2.8 },
	missile = { "missile", "missile", 2.6 },
	rocket = { "rocket", "missile", 2.2 },
}

function MapView.updateUnits()
	local now = workspace:GetServerTimeNow()
	local z = MapView.z
	local W = State.W
	for id, m in unitById do
		if not State.units[id] then
			m.frame:Destroy()
			if m.shadow then
				m.shadow:Destroy()
			end
			unitById[id] = nil
		end
	end
	for id, u in State.units do
		local spec = SPRITE[u.kind] or SPRITE.transport
		local n = State.nations[u.owner]
		local skin = spec[2] and n and n.vehicles and n.vehicles[spec[2]] or nil
		local m = unitById[id]
		if not m then
			m = Art.spriteFrame(spec[1], skin, unitLayer)
			unitById[id] = m
		else
			Art.setSpriteSkin(m, spec[1], skin)
		end
		Art.colorSprite(m, if n then n.color else Color3.new(1, 1, 1))
		local x, y, pf = State.unitPos(u, now)
		local sz = math.clamp(z * spec[3], 12, 40)
		m.frame.Size = UDim2.fromOffset(sz, sz)
		m.frame.Position = UDim2.fromOffset(MapView.ox + (x + 0.5) * z, MapView.oy + (y + 0.5) * z)
		-- face the dominant grid direction of travel (0/90/180/270 only)
		local k = math.clamp(math.floor(pf), 1, u.n)
		local a = buffer.readu32(u.path, (k - 1) * 4)
		local b = buffer.readu32(u.path, (math.min(k + 6, u.n) - 1) * 4)
		if u.kind == "missile" or u.kind == "rocket" then
			-- ballistic arc: height = 4h·f(1-f) over the straight ground track
			local s0 = buffer.readu32(u.path, 0)
			local e = buffer.readu32(u.path, (u.n - 1) * 4)
			local gx, gy = e % W - s0 % W, e // W - s0 // W
			local d = math.sqrt(gx * gx + gy * gy)
			local f = math.clamp((pf - 1) / math.max(1, u.n - 1), 0, 1)
			local hmax = math.clamp(d * 0.4, 5, 70)
			local h = hmax * 4 * f * (1 - f)
			local vy = gy / math.max(d, 1) - hmax * 4 * (1 - 2 * f) / math.max(d, 1)
			local vx = gx / math.max(d, 1)
			m.frame.Rotation = math.deg(math.atan2(vy, vx)) + 90
			local big = sz * (1 + 0.45 * h / hmax)
			m.frame.Size = UDim2.fromOffset(big, big)
			m.frame.Position = UDim2.fromOffset(MapView.ox + (x + 0.5) * z, MapView.oy + (y + 0.5 - h) * z)
			local sh = m.shadow
			if not sh then
				sh = Instance.new("Frame")
				sh.AnchorPoint = Vector2.new(0.5, 0.5)
				sh.BackgroundColor3 = Color3.new(0, 0, 0)
				sh.BorderSizePixel = 0
				local cr = Instance.new("UICorner")
				cr.CornerRadius = UDim.new(0.5, 0)
				cr.Parent = sh
				sh.Parent = unitLayer
				m.shadow = sh
			end
			sh.BackgroundTransparency = 0.55 + 0.3 * h / hmax
			sh.Size = UDim2.fromOffset(sz * 0.6, sz * 0.3)
			sh.Position = UDim2.fromOffset(MapView.ox + (x + 0.5) * z, MapView.oy + (y + 0.5) * z)
		elseif a ~= b then
			local dx, dy = b % W - a % W, b // W - a // W
			-- sprites face up: right = 90, down = 180, left = 270, up = 0
			m.frame.Rotation = if math.abs(dx) >= math.abs(dy) then (if dx >= 0 then 90 else 270) else (if dy >= 0 then 180 else 0)
		end
	end
end

-- quick feedback ring where an order was given
function MapView.pulse(cell: number)
	MapView.flash(cell, 1, Color3.new(1, 1, 1))
end

-- Route lines live inside the map image (scale coordinates), so they pan and zoom with
-- the map exactly. Trade + rail lines are faint; my aircraft and inbound threats stronger.
local routeLayer: Frame
local linePool: { Frame } = {}
function MapView.updateRoutes()
	if not routeLayer then
		return
	end
	local used = 0
	local now = workspace:GetServerTimeNow()
	local W, H = State.W, State.H
	local function seg(ax: number, ay: number, bx: number, by: number, col: Color3, alpha: number, thick: number)
		used += 1
		local f = linePool[used]
		if not f then
			f = Instance.new("Frame")
			f.BorderSizePixel = 0
			f.Parent = routeLayer
			linePool[used] = f
		end
		f.BackgroundColor3 = col
		f.BackgroundTransparency = alpha
		if ay == by then
			f.Rotation = 0
			f.AnchorPoint = Vector2.new(0, 0.5)
			f.Position = UDim2.new((math.min(ax, bx) + 0.5) / W, 0, (ay + 0.5) / H, 0)
			f.Size = UDim2.new(math.abs(bx - ax) / W, thick, 0, thick)
		elseif ax == bx then
			f.Rotation = 0
			f.AnchorPoint = Vector2.new(0.5, 0)
			f.Position = UDim2.new((ax + 0.5) / W, 0, (math.min(ay, by) + 0.5) / H, 0)
			f.Size = UDim2.new(0, thick, math.abs(by - ay) / H, thick)
		else
			local dx, dy = bx - ax, by - ay
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			f.Position = UDim2.new((ax + bx + 1) / 2 / W, 0, (ay + by + 1) / 2 / H, 0)
			f.Size = UDim2.new(math.sqrt(dx * dx + dy * dy) / W, thick, 0, thick)
			f.Rotation = math.deg(math.atan2(dy, dx))
		end
		f.Visible = true
	end
	-- rail connections of every factory (all nations), plus the placement preview
	for _, conn in MapView.connections do
		local fx, fy = conn.from % W, conn.from // W
		for _, t in conn.to do
			local tx, ty = t % W, t // W
			if used < 1500 then
				local a = if conn.preview then 0.15 else 0.5
				local th = 2
				seg(fx, fy, tx, fy, Color3.new(1, 1, 1), a, th)
				seg(tx, fy, tx, ty, Color3.new(1, 1, 1), a, th)
			end
		end
	end
	for _, u in State.units do
		local last = buffer.readu32(u.path, (u.n - 1) * 4)
		local air = u.kind == "bomber" or u.kind == "fighter"
		local missile = u.kind == "missile" or u.kind == "rocket"
		local inbound = (air or missile) and u.owner ~= State.me and State.ownerAt(last) == State.me and not State.allied(u.owner)
		local mine = (air or missile) and u.owner == State.me
		local trade = (u.kind == "train" or u.kind == "trade") and State.overlays.routes
		if (trade or inbound or mine or missile) and used < 1500 then
			local x, y, p = State.unitPos(u, now)
			local n = State.nations[u.owner]
			local col = if inbound then Color3.fromHex("FF5C61") elseif trade then Color3.new(1, 1, 1) elseif n then n.color else Color3.new(1, 1, 1)
			local alpha = if trade then 0.6 else 0.25
			local thick = if trade then 1 else 2
			if missile then
				-- trail along the flown arc + a faint ground track to the target
				local s0 = buffer.readu32(u.path, 0)
				local sx0, sy0 = s0 % W, s0 // W
				local gx, gy = last % W - sx0, last // W - sy0
				local d = math.sqrt(gx * gx + gy * gy)
				local hmax = math.clamp(d * 0.4, 5, 70)
				local fNow = math.clamp((p - 1) / math.max(1, u.n - 1), 0, 1)
				local function at(f: number): (number, number)
					return sx0 + gx * f, sy0 + gy * f - hmax * 4 * f * (1 - f)
				end
				local ox, oy = at(0)
				for k = 1, 14 do
					local f = fNow * k / 14
					local nx, ny = at(f)
					if used < 1500 then
						seg(ox, oy, nx, ny, if n then n.color else col, 0.41, 2)
					end
					ox, oy = nx, ny
				end
				if (inbound or mine) and used < 1500 then
					seg(x, y, last % W, last // W, col, 0.75, 1)
				end
			else
				-- straight grid runs along the real path cells
				local k0 = math.max(1, math.floor(p))
				local sc = buffer.readu32(u.path, (k0 - 1) * 4)
				local sx, sy = sc % W, sc // W
				local px, py = sx, sy
				local dirX, dirY = 0, 0
				for kk = k0 + 1, u.n do
					local c = buffer.readu32(u.path, (kk - 1) * 4)
					local cx, cy = c % W, c // W
					local ddx, ddy = cx - px, cy - py
					if (ddx ~= dirX or ddy ~= dirY) and (dirX ~= 0 or dirY ~= 0) then
						if used < 1500 then
							seg(sx, sy, px, py, col, alpha, thick)
						end
						sx, sy = px, py
					end
					dirX, dirY = ddx, ddy
					px, py = cx, cy
				end
				if (sx ~= px or sy ~= py) and used < 1500 then
					seg(sx, sy, px, py, col, alpha, thick)
				end
			end
		end
	end
	for k = used + 1, #linePool do
		linePool[k].Visible = false
	end
end

-- (old dotted renderer, unused)
function MapView.updateRoutesDots()
	local used = 0
	do
		local now = workspace:GetServerTimeNow()
		local z = MapView.z
		local W = State.W
		for _, u in State.units do
			local last = buffer.readu32(u.path, (u.n - 1) * 4)
			local inbound = (u.kind == "bomber" or u.kind == "fighter") and u.owner ~= State.me
				and State.ownerAt(last) == State.me and not State.allied(u.owner)
			local mineAir = (u.kind == "bomber" or u.kind == "fighter") and u.owner == State.me
			if ((u.kind == "train" or u.kind == "trade") and State.overlays.routes) or inbound or mineAir then
				local _, _, p = State.unitPos(u, now)
				local n = State.nations[u.owner]
				local step = math.max(2, math.floor(6 / math.max(z, 0.5)))
				local k = math.floor(p) + step
				local drawn = 0
				while k <= u.n and drawn < 30 and used < 600 do
					local c = buffer.readu32(u.path, (k - 1) * 4)
					used += 1
					local d = dotPool[used]
					if not d then
						d = Instance.new("Frame")
						d.AnchorPoint = Vector2.new(0.5, 0.5)
						d.BorderSizePixel = 0
						d.BackgroundTransparency = 0.35
						local cr = Instance.new("UICorner")
						cr.CornerRadius = UDim.new(0.5, 0)
						cr.Parent = d
						d.Parent = unitLayer
						dotPool[used] = d
					end
					d.BackgroundColor3 = if inbound then Color3.fromHex("FF5C61")
						elseif u.kind == "trade" then Color3.fromHex("F5C451")
						elseif n then n.color
						else Color3.new(1, 1, 1)
					d.Size = UDim2.fromOffset(3, 3)
					d.Position = UDim2.fromOffset(MapView.ox + (c % W + 0.5) * z, MapView.oy + (c // W + 0.5) * z)
					d.Visible = true
					drawn += 1
					k += step
				end
			end
		end
	end
	for k = used + 1, #dotPool do
		dotPool[k].Visible = false
	end
end

function MapView.showRing(cell: number?, radius: number, color: Color3?)
	if not cell then
		ring.Visible = false
		return
	end
	local p = MapView.cellToLocal(cell % State.W, cell // State.W)
	local d = (radius * 2 + 1) * MapView.z
	ring.Size = UDim2.fromOffset(d, d)
	ring.Position = UDim2.fromOffset(p.X, p.Y)
	local st = ring:FindFirstChildOfClass("UIStroke")
	if st then
		st.Color = color or Color3.fromHex("3FB6FF")
	end
	ring.BackgroundColor3 = color or Color3.fromHex("3FB6FF")
	ring.Visible = true
end

function MapView.showBuildPreview(cell: number?, kind: string?, ok: boolean)
	if not cell or not kind then
		buildPrev.Visible = false
		return
	end
	local p = MapView.cellToLocal(cell % State.W, cell // State.W)
	local sz = markerSize()
	buildPrev.Size = UDim2.fromOffset(sz, sz)
	buildPrev.Position = UDim2.fromOffset(p.X, p.Y)
	buildPrev.BackgroundColor3 = if ok then Color3.fromHex("4ADE80") else Color3.fromHex("FF5C61")
	local icon = buildPrev:FindFirstChildOfClass("ImageLabel")
	if icon then
		Icons.apply(icon, kind)
	end
	buildPrev.Visible = true
end

local function deco(parent: Instance, class: string, props: { [string]: any }): any
	local o = Instance.new(class)
	for k, v in props do
		(o :: any)[k] = v
	end
	o.Parent = parent
	return o
end

function MapView.init(gui: ScreenGui)
	frame = Instance.new("Frame")
	frame.Name = "Map"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = OCEAN
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = true
	frame.Parent = gui

	image = Instance.new("Frame")
	image.Name = "Grid"
	image.BackgroundTransparency = 1
	image.Parent = frame

	labels = Instance.new("Frame")
	labels.Name = "Labels"
	labels.BackgroundTransparency = 1
	labels.Size = UDim2.fromScale(1, 1)
	labels.ZIndex = 3
	labels.Parent = frame

	markers = Instance.new("Frame")
	markers.Name = "Markers"
	markers.BackgroundTransparency = 1
	markers.Size = UDim2.fromScale(1, 1)
	markers.ZIndex = 2
	markers.Parent = frame

	routeLayer = Instance.new("Frame")
	routeLayer.Name = "Routes"
	routeLayer.BackgroundTransparency = 1
	routeLayer.Size = UDim2.fromScale(1, 1)
	routeLayer.ZIndex = 2
	routeLayer.Parent = image

	unitLayer = Instance.new("Frame")
	unitLayer.Name = "Units"
	unitLayer.BackgroundTransparency = 1
	unitLayer.Size = UDim2.fromScale(1, 1)
	unitLayer.ZIndex = 3
	unitLayer.Parent = frame

	ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.BackgroundTransparency = 0.88
	ring.Visible = false
	ring.ZIndex = 4
	deco(ring, "UICorner", { CornerRadius = UDim.new(0.5, 0) })
	deco(ring, "UIStroke", { Thickness = 2 })
	ring.Parent = frame

	buildPrev = Instance.new("Frame")
	buildPrev.AnchorPoint = Vector2.new(0.5, 0.5)
	buildPrev.BackgroundTransparency = 0.25
	buildPrev.Visible = false
	buildPrev.ZIndex = 5
	deco(buildPrev, "UICorner", { CornerRadius = UDim.new(0.3, 0) })
	deco(buildPrev, "ImageLabel", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.72, 0.72) })
	buildPrev.Parent = frame

	preview = Instance.new("Frame")
	preview.AnchorPoint = Vector2.new(0.5, 0.5)
	preview.BackgroundTransparency = 0.75
	preview.Visible = false
	preview.ZIndex = 4
	deco(preview, "UICorner", { CornerRadius = UDim.new(0.5, 0) })
	previewStroke = deco(preview, "UIStroke", { Thickness = 2 })
	preview.Parent = frame

	selMarker = Instance.new("Frame")
	selMarker.AnchorPoint = Vector2.new(0.5, 0.5)
	selMarker.BackgroundTransparency = 1
	selMarker.Visible = false
	selMarker.ZIndex = 4
	deco(selMarker, "UICorner", { CornerRadius = UDim.new(0.5, 0) })
	deco(selMarker, "UIStroke", { Thickness = 3, Color = Color3.fromHex("FFD84D") })
	selMarker.Parent = frame

	reticle = Instance.new("Frame")
	reticle.AnchorPoint = Vector2.new(0.5, 0.5)
	reticle.Position = UDim2.fromScale(0.5, 0.5)
	reticle.Size = UDim2.fromOffset(22, 22)
	reticle.BackgroundTransparency = 1
	reticle.Visible = false
	reticle.ZIndex = 5
	deco(reticle, "UICorner", { CornerRadius = UDim.new(0.5, 0) })
	deco(reticle, "UIStroke", { Thickness = 2, Color = Color3.new(1, 1, 1) })
	reticle.Parent = frame
end

-- (re)build the image after a snapshot
function MapView.load()
	local W, H = State.W, State.H
	MapView.clearColorCache()
	MapView.clearSkinCache()
	MapView.highlight = 0
	for _, p in plates do
		p.frame:Destroy()
	end
	plates = {}
	for _, m in markerById do
		m.frame:Destroy()
	end
	markerById = {}
	for _, m in unitById do
		m.frame:Destroy()
	end
	unitById = {}
	-- one EditableImage per TILE x TILE cells (each <= 1024 px per side)
	local key = W .. "x" .. H
	if not img or MapView.tileKey ~= key then
		for _, t in tiles do
			t.img:Destroy()
			t.label:Destroy()
		end
		tiles = {}
		img = false
		for ty = 0, math.ceil(H / TILE) - 1 do
			for tx = 0, math.ceil(W / TILE) - 1 do
				local x0, y0 = tx * TILE, ty * TILE
				local tw, th = math.min(TILE, W - x0), math.min(TILE, H - y0)
				local ok, res = pcall(function()
					return AssetService:CreateEditableImage({ Size = Vector2.new(tw * PPC, th * PPC) })
				end)
				if not ok or not res then
					MapView.error = "Map renderer unavailable (EditableImage): " .. tostring(res)
					warn(MapView.error)
					return
				end
				local lab = Instance.new("ImageLabel")
				lab.BackgroundTransparency = 1
				lab.ResampleMode = Enum.ResamplerMode.Pixelated
				lab.ImageContent = Content.fromObject(res)
				lab.Parent = image
				table.insert(tiles, { img = res, label = lab, x0 = x0, y0 = y0, w = tw, h = th })
			end
		end
		img = true
		MapView.tileKey = key
		-- routes must draw after (above) the tiles: the World gui uses Global ZIndex, so
		-- equal-ZIndex siblings render in tree order
		routeLayer.Parent = nil
		routeLayer.Parent = image
	end
	chunks = {}
	chunkCols = math.ceil(W / CH)
	for cy = 0, math.ceil(H / CH) - 1 do
		for cx = 0, chunkCols - 1 do
			local x0, y0 = cx * CH, cy * CH
			local cw, chh = math.min(CH, W - x0), math.min(CH, H - y0)
			local tile
			for _, t in tiles do
				if x0 >= t.x0 and x0 < t.x0 + t.w and y0 >= t.y0 and y0 < t.y0 + t.h then
					tile = t
				end
			end
			table.insert(chunks, {
				tile = tile,
				x0 = x0,
				y0 = y0,
				pw = cw * PPC,
				ph = chh * PPC,
				buf = buffer.create(cw * PPC * chh * PPC * 4),
			})
		end
	end
	loadLook(W, H)
	frame.BackgroundColor3 = lookCol[0] and OCEAN or OCEAN
	bbox, frames, refit = {}, {}, {}
	local own = State.owner
	for i = 0, State.N - 1 do
		local o = buffer.readu16(own, i * 2)
		if o ~= 0 then
			local x, y = i % W, i // W
			local b = bbox[o]
			if not b then
				bbox[o] = { x, y, x, y }
			else
				if x < b[1] then b[1] = x end
				if y < b[2] then b[2] = y end
				if x > b[3] then b[3] = x end
				if y > b[4] then b[4] = y end
			end
		end
	end
	for o in bbox do
		fitFrame(o)
	end
	MapView.redrawAll(true)
	MapView.fit()
end

function MapView.flush(budget: number)
	if not img then
		return
	end
	local o = next(refit)
	if o then
		refit[o] = nil
		fitFrame(o)
		MapView.redrawOwners(o, o)
	end
	local n = 0
	for ch in dirtyChunks do
		dirtyChunks[ch] = nil
		local t = ch.tile
		t.img:WritePixelsBuffer(Vector2.new((ch.x0 - t.x0) * PPC, (ch.y0 - t.y0) * PPC), Vector2.new(ch.pw, ch.ph), ch.buf)
		n += 1
		if n >= budget then
			break
		end
	end
end

function MapView.frame(): Frame
	return frame
end

return MapView
