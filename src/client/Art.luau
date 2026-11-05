--!strict
-- Procedural art (no uploads): our coin icon and vehicle sprites with skins.
-- Sprites face right (+x), drawn as 16x16 hard-edged pixel art (shown with Pixelated
-- resampling, like the map). Each is two layers: base colours + a white "tint" layer that
-- the renderer colours with the owner's nation colour.
local AssetService = game:GetService("AssetService")

local Art = {}
local cache: { [string]: any } = {}

local function newImage(w: number, h: number): EditableImage?
	local ok, img = pcall(function()
		return AssetService:CreateEditableImage({ Size = Vector2.new(w, h) })
	end)
	return if ok then img else nil
end

local function put(b: buffer, w: number, x: number, y: number, c: Color3, a: number?)
	local o = (y * w + x) * 4
	buffer.writeu8(b, o, math.floor(c.R * 255 + 0.5))
	buffer.writeu8(b, o + 1, math.floor(c.G * 255 + 0.5))
	buffer.writeu8(b, o + 2, math.floor(c.B * 255 + 0.5))
	buffer.writeu8(b, o + 3, math.floor((a or 1) * 255 + 0.5))
end

----------------------------------------------------------------------------
-- coin: gold disc with a globe emblem (clearly not the Robux hexagon)

function Art.coin(): EditableImage?
	if cache.coin then
		return cache.coin
	end
	local S = 64
	local img = newImage(S, S)
	if not img then
		return nil
	end
	local b = buffer.create(S * S * 4)
	local rimC, faceC, shineC, lineC = Color3.fromHex("B7791F"), Color3.fromHex("F5C451"), Color3.fromHex("FFE7A3"), Color3.fromHex("C98A1E")
	local c = (S - 1) / 2
	for y = 0, S - 1 do
		for x = 0, S - 1 do
			local dx, dy = x - c, y - c
			local d = math.sqrt(dx * dx + dy * dy)
			if d <= 31 then
				local col = faceC
				if d > 27 then
					col = rimC
				else
					-- globe: outline circle, equator, two meridian ellipses
					local g = math.sqrt(dx * dx + dy * dy)
					local onCircle = math.abs(g - 16) < 1.3
					local onEq = math.abs(dy) < 1.1 and g < 16
					local e = (dx / 7) ^ 2 + (dy / 16) ^ 2
					local onMer = math.abs(e - 1) < 0.14 and g < 16
					local onMid = math.abs(dx) < 1.1 and g < 16
					local lat = (math.abs(dy - 8) < 1 or math.abs(dy + 8) < 1) and g < 15
					if onCircle or onEq or onMer or onMid or lat then
						col = lineC
					elseif dx + dy < -22 and d < 26 then
						col = shineC
					end
				end
				-- soft edge
				put(b, S, x, y, col, math.clamp(31.6 - d, 0, 1))
			else
				put(b, S, x, y, Color3.new(), 0)
			end
		end
	end
	img:WritePixelsBuffer(Vector2.zero, Vector2.new(S, S), b)
	cache.coin = img
	return img
end

-- convenience: ImageLabel with the coin
function Art.coinLabel(size: number, parent: Instance?): ImageLabel
	local l = Instance.new("ImageLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromOffset(size, size)
	local img = Art.coin()
	if img then
		l.ImageContent = Content.fromObject(img)
	end
	if parent then
		l.Parent = parent
	end
	return l
end

----------------------------------------------------------------------------
-- vehicle sprites

-- skin palettes for vehicles: hull / detail / accent
Art.VehiclePalettes = {
	standard = { hull = "6B7785", detail = "D9DEE4", accent = "2B323B" },
	stealth = { hull = "1C2128", detail = "3A434F", accent = "0B0E12" },
	gold = { hull = "C99A2E", detail = "FFE08A", accent = "7A5A12" },
	camo = { hull = "5B6B3A", detail = "8C7B4A", accent = "2F3A1E" },
	arctic = { hull = "DCE6EE", detail = "9FB7C9", accent = "5D7487" },
	neon = { hull = "141A22", detail = "39FFD4", accent = "FF4FD8" },
}

type Shape = { kind: string, pts: { number }?, cx: number?, cy: number?, rx: number?, ry: number?, col: string }

local function inPoly(pts: { number }, x: number, y: number): boolean
	local inside = false
	local n = #pts // 2
	local j = n
	for i = 1, n do
		local xi, yi = pts[i * 2 - 1], pts[i * 2]
		local xj, yj = pts[j * 2 - 1], pts[j * 2]
		if (yi > y) ~= (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi then
			inside = not inside
		end
		j = i
	end
	return inside
end

-- 32x32 designs; col = "hull" | "detail" | "accent" | "tint" | fixed hex
local DESIGNS: { [string]: { Shape } } = {
	transport = {
		{ kind = "poly", pts = { 3, 11, 24, 11, 30, 16, 24, 21, 3, 21 }, col = "tint" },
		{ kind = "poly", pts = { 7, 13, 19, 13, 19, 19, 7, 19 }, col = "detail" },
		{ kind = "ell", cx = 11, cy = 16, rx = 1.6, ry = 1.6, col = "accent" },
		{ kind = "ell", cx = 15, cy = 16, rx = 1.6, ry = 1.6, col = "accent" },
	},
	warship = {
		{ kind = "poly", pts = { 1, 12, 25, 12, 31, 16, 25, 20, 1, 20 }, col = "hull" },
		{ kind = "poly", pts = { 3, 15, 27, 15, 28, 16, 27, 17, 3, 17 }, col = "tint" },
		{ kind = "ell", cx = 9, cy = 16, rx = 2.6, ry = 2.6, col = "accent" },
		{ kind = "ell", cx = 19, cy = 16, rx = 2.6, ry = 2.6, col = "accent" },
		{ kind = "poly", pts = { 19, 15, 25, 15, 25, 17, 19, 17 }, col = "detail" },
	},
	trade = {
		{ kind = "poly", pts = { 2, 11, 25, 11, 31, 16, 25, 21, 2, 21 }, col = "tint" },
		{ kind = "poly", pts = { 5, 13, 10, 13, 10, 19, 5, 19 }, col = "F5C451" },
		{ kind = "poly", pts = { 11, 13, 16, 13, 16, 19, 11, 19 }, col = "E8734A" },
		{ kind = "poly", pts = { 17, 13, 22, 13, 22, 19, 17, 19 }, col = "4FA3E0" },
	},
	train = {
		{ kind = "poly", pts = { 4, 12, 28, 12, 28, 20, 4, 20 }, col = "tint" },
		{ kind = "poly", pts = { 22, 13, 27, 13, 27, 19, 22, 19 }, col = "detail" },
		{ kind = "poly", pts = { 6, 14, 20, 14, 20, 18, 6, 18 }, col = "accent" },
	},
	fighter = {
		{ kind = "poly", pts = { 4, 15, 26, 14, 31, 16, 26, 18, 4, 17 }, col = "hull" },
		{ kind = "poly", pts = { 12, 15, 20, 15, 10, 3, 7, 3 }, col = "tint" },
		{ kind = "poly", pts = { 12, 17, 20, 17, 10, 29, 7, 29 }, col = "tint" },
		{ kind = "poly", pts = { 2, 15, 6, 15, 3, 9, 1, 9 }, col = "accent" },
		{ kind = "poly", pts = { 2, 17, 6, 17, 3, 23, 1, 23 }, col = "accent" },
		{ kind = "ell", cx = 22, cy = 16, rx = 2.6, ry = 1.2, col = "detail" },
	},
	bomber = {
		{ kind = "poly", pts = { 3, 14, 26, 14, 31, 16, 26, 18, 3, 18 }, col = "hull" },
		{ kind = "poly", pts = { 13, 15, 19, 15, 16, 1, 12, 1 }, col = "tint" },
		{ kind = "poly", pts = { 13, 17, 19, 17, 16, 31, 12, 31 }, col = "tint" },
		{ kind = "ell", cx = 15, cy = 7, rx = 2, ry = 1.4, col = "accent" },
		{ kind = "ell", cx = 15, cy = 25, rx = 2, ry = 1.4, col = "accent" },
		{ kind = "poly", pts = { 2, 14, 6, 14, 4, 9, 2, 9 }, col = "accent" },
		{ kind = "poly", pts = { 2, 18, 6, 18, 4, 23, 2, 23 }, col = "accent" },
		{ kind = "ell", cx = 25, cy = 16, rx = 2.4, ry = 1.1, col = "detail" },
	},
	missile = {
		{ kind = "poly", pts = { 6, 14, 25, 14, 30, 16, 25, 18, 6, 18 }, col = "detail" },
		{ kind = "poly", pts = { 25, 14, 30, 16, 25, 18 }, col = "D23A3A" },
		{ kind = "poly", pts = { 6, 14, 10, 14, 6, 9, 3, 9 }, col = "tint" },
		{ kind = "poly", pts = { 6, 18, 10, 18, 6, 23, 3, 23 }, col = "tint" },
		{ kind = "poly", pts = { 17, 14, 19, 14, 19, 18, 17, 18 }, col = "F5C451" },
		{ kind = "poly", pts = { 1, 15, 5, 15, 5, 17, 1, 17 }, col = "FFB547" },
	},
}

-- User pixel sprite pack (tools/build_sprites.py): per sprite a base layer, a grey "paint"
-- layer tinted at runtime (nation colour for Standard, a fixed colour for skins) and a
-- 1px edge ring shown in the nation colour on skinned units. Sprites face up.
local SpriteData = require(script.Parent.SpriteData) :: any
local PACK_UNIT = {
	transport = "TroopTransport",
	trade = "Cargo",
	warship = "Warship",
	fighter = "Fighter",
	bomber = "Bomber",
	missile = "Nuke",
	rocket = "Missile",
}
-- skins recolour the paint layer
Art.FixedTint = {
	arctic = Color3.fromHex("DDEBF5"),
	desert = Color3.fromHex("D9B77E"),
	midnight = Color3.fromHex("5A4B96"),
	gold = Color3.fromHex("F5C451"),
}

-- procedural fallback (trains); faces up; returns base, tint, edge buffers and size
local function procedural(kind: string): (buffer, buffer, buffer, number)
	local design = DESIGNS[kind] or DESIGNS.train
	local pal = Art.VehiclePalettes.standard
	local S = 16
	local bb, tb, eb = buffer.create(S * S * 4), buffer.create(S * S * 4), buffer.create(S * S * 4)
	for y = 0, S - 1 do
		for x = 0, S - 1 do
			local px, py = (S - 1 - y) * 2 + 1, x * 2 + 1
			local col: string? = nil
			for _, sh in design do
				local hitS = if sh.kind == "poly" then inPoly(sh.pts :: { number }, px, py)
					else ((px - (sh.cx :: number)) / (sh.rx :: number)) ^ 2 + ((py - (sh.cy :: number)) / (sh.ry :: number)) ^ 2 <= 1
				if hitS then
					col = sh.col
				end
			end
			put(bb, S, x, y, Color3.new(), 0)
			put(tb, S, x, y, Color3.new(1, 1, 1), 0)
			put(eb, S, x, y, Color3.new(1, 1, 1), 0)
			if col == "tint" then
				put(tb, S, x, y, Color3.new(1, 1, 1), 1)
			elseif col then
				local hex = if col == "hull" then pal.hull elseif col == "detail" then pal.detail elseif col == "accent" then pal.accent else col
				put(bb, S, x, y, Color3.fromHex(hex), 1)
			end
		end
	end
	return bb, tb, eb, S
end

function Art.sprite(kind: string, _skin: string?): (EditableImage?, EditableImage?, EditableImage?)
	local key = kind
	local hit = cache[key]
	if hit then
		return hit[1], hit[2], hit[3]
	end
	local unit = PACK_UNIT[kind]
	local d = unit and SpriteData[unit]
	local bb, tb, eb, S
	if d then
		S = d.size
		bb, tb, eb = buffer.create(S * S * 4), buffer.create(S * S * 4), buffer.create(S * S * 4)
		-- compact format: one char per pixel (palette index / grey level from ALPHA, "." = none)
		local ALPHA = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-_"
		local pal = {}
		for k, h in d.pal do
			pal[k - 1] = Color3.fromHex(h)
		end
		for i = 0, S * S - 1 do
			local bc = d.base:sub(i + 1, i + 1)
			if bc ~= "." then
				local c = pal[(string.find(ALPHA, bc, 1, true) :: number) - 1]
				buffer.writeu8(bb, i * 4, math.floor(c.R * 255))
				buffer.writeu8(bb, i * 4 + 1, math.floor(c.G * 255))
				buffer.writeu8(bb, i * 4 + 2, math.floor(c.B * 255))
				buffer.writeu8(bb, i * 4 + 3, 255)
			end
			local tc = d.tint:sub(i + 1, i + 1)
			local t = if tc ~= "." then math.min(255, ((string.find(ALPHA, tc, 1, true) :: number) - 1) * 4 + 2) else 0
			buffer.writeu8(tb, i * 4, t)
			buffer.writeu8(tb, i * 4 + 1, t)
			buffer.writeu8(tb, i * 4 + 2, t)
			buffer.writeu8(tb, i * 4 + 3, if tc ~= "." then 255 else 0)
			local e = d.edge:sub(i + 1, i + 1) == "1"
			buffer.writeu8(eb, i * 4, 255)
			buffer.writeu8(eb, i * 4 + 1, 255)
			buffer.writeu8(eb, i * 4 + 2, 255)
			buffer.writeu8(eb, i * 4 + 3, if e then 255 else 0)
		end
	else
		bb, tb, eb, S = procedural(kind)
	end
	local bi, ti, ei = newImage(S, S), newImage(S, S), newImage(S, S)
	if not bi or not ti or not ei then
		return nil, nil, nil
	end
	bi:WritePixelsBuffer(Vector2.zero, Vector2.new(S, S), bb)
	ti:WritePixelsBuffer(Vector2.zero, Vector2.new(S, S), tb)
	ei:WritePixelsBuffer(Vector2.zero, Vector2.new(S, S), eb)
	cache[key] = { bi, ti, ei }
	return bi, ti, ei
end

local function layer(z: number, parent: Instance): ImageLabel
	local l = Instance.new("ImageLabel")
	l.BackgroundTransparency = 1
	l.ResampleMode = Enum.ResamplerMode.Pixelated
	l.Size = UDim2.fromScale(1, 1)
	l.ZIndex = z
	l.Parent = parent
	return l
end

-- sprite frame: { frame, base, tint, edge, fixedTint } (renderer sets tint/edge colours)
function Art.spriteFrame(kind: string, skin: string?, parent: Instance?): any
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	local s = { frame = f, edge = layer(1, f), tint = layer(2, f), base = layer(3, f), skin = nil :: string?, fixedTint = nil :: Color3? }
	local b, t, e = Art.sprite(kind, skin)
	if b and t and e then
		s.base.ImageContent = Content.fromObject(b)
		s.tint.ImageContent = Content.fromObject(t)
		s.edge.ImageContent = Content.fromObject(e)
	end
	Art.setSpriteSkin(s, kind, skin)
	if parent then
		f.Parent = parent
	end
	return s
end

-- skin = nil/"standard" (nation colour) or a palette key from Art.FixedTint
function Art.setSpriteSkin(s: any, _kind: string, skin: string?)
	s.skin = skin
	s.fixedTint = skin and Art.FixedTint[skin]
	s.edge.Visible = s.fixedTint ~= nil
end

-- colour a sprite for its owner
function Art.colorSprite(s: any, nationColor: Color3)
	s.tint.ImageColor3 = s.fixedTint or nationColor
	s.edge.ImageColor3 = nationColor
end

return Art
