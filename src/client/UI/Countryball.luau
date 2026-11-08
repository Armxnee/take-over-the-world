--!nonstrict
-- (Take Over the World!: the Countryball, 2026-11-06.)
-- A country's mascot: its flag (Data/FlagPix: this game's pixel flags, public-domain artwork) as a
-- pixel-art ball (2026-11-06 redesign after the user's reference): dark outline, shaded rim, two eyes,
-- the gear it wears (2026-11-08: hats, beards, glasses) and, for an empire, the evil look.
-- Drawn into an EditableImage (no upload): Countryball.new(flag_code, px, name) returns a Frame.
-- A definition's `ball` field ("countryball:<code>", Data/Countries) names one.
local AssetService = game:GetService("AssetService")
local FlagPix = require(game:GetService("ReplicatedStorage"):WaitForChild("Airfront"):WaitForChild("Data"):WaitForChild("FlagPix"))
local Gear = require(game:GetService("ReplicatedStorage"):WaitForChild("Airfront"):WaitForChild("Data"):WaitForChild("Gear")) -- (Take Over the World!: hats)
local Empires = require(game:GetService("ReplicatedStorage"):WaitForChild("Airfront"):WaitForChild("Data"):WaitForChild("Empires")) -- (Take Over the World!: the evil look)
local GearSprites = require(game:GetService("ReplicatedStorage"):WaitForChild("Airfront"):WaitForChild("Data"):WaitForChild("GearSprites"))

local Countryball = {}

local cache: { [string]: any } = {}
--- A flag as image Content: the whole 30x20 flag, or (`square`) its centre 20x20. nil when
--- the flag is unknown or EditableImage is unavailable.
function Countryball.flag_content(code: string?, name: string?, square: boolean?): Content?
	local key = tostring(code) .. "|" .. tostring(name) .. "|" .. tostring(square)
	local hit = cache[key]
	if hit ~= nil then
		return hit or nil
	end
	cache[key] = false
	local g = FlagPix.forCode(code, name)
	if g == nil then
		return nil
	end
	local W, H = FlagPix.W, FlagPix.H
	local x0 = if square then (W - H) // 2 else 0
	local w = if square then H else W
	local ok, img = pcall(function()
		return AssetService:CreateEditableImage({ Size = Vector2.new(w, H) })
	end)
	if not ok or img == nil then
		return nil
	end
	local b = buffer.create(w * H * 4)
	for y = 0, H - 1 do
		for x = 0, w - 1 do
			local c = g.pal[buffer.readu8(g.idx, y * W + x + x0) + 1] or Color3.new(0.6, 0.6, 0.6)
			local o = (y * w + x) * 4
			buffer.writeu8(b, o, math.floor(c.R * 255 + 0.5))
			buffer.writeu8(b, o + 1, math.floor(c.G * 255 + 0.5))
			buffer.writeu8(b, o + 2, math.floor(c.B * 255 + 0.5))
			buffer.writeu8(b, o + 3, 255)
		end
	end
	img:WritePixelsBuffer(Vector2.zero, Vector2.new(w, H), b)
	local content = Content.fromObject(img)
	cache[key] = content
	return content
end

--- The flag code of a `ball` reference ("countryball:fr" -> "fr").
function Countryball.code_of(ref: string?): string?
	if type(ref) ~= "string" then
		return nil
	end
	return string.match(ref, "^countryball:(%w+)$")
end

--- The ball as one pixel sprite on a G x G canvas (the ball at OX, OY). A dark outline, the flag
--- across the body, a darker rim band on the upper right and along the bottom, two round-topped
--- white eyes with a grey glint, and the gear it wears (Data/Gear). Hats and beards are fitted to the
--- ball (2026-11-08, after the user's references): a hat fills the top down to a brim line over the
--- eyes, a beard the lower half under them; both stay inside the outline. An empire's ball looks
--- evil (Data/GearSprites.empire): angry eyes, the spiked helmet and a black handlebar moustache;
--- the player's own gear replaces each one (glasses the eyes, a hat the helmet, a beard the moustache).
Countryball.G = 32
Countryball.OX, Countryball.OY = 0, 0
local G, OX, OY = Countryball.G, Countryball.OX, Countryball.OY
local OUT = Color3.fromRGB(18, 20, 28)
local EYE = {
	"..kkk..",
	".kgwwk.",
	"kgwwwwk",
	"kwwwwwk",
	"kwwwwwk",
	".kkkkk.",
}
local EYE_COL = { k = OUT, w = Color3.new(1, 1, 1), g = Color3.fromRGB(200, 200, 205) }
--- the empire's moustache when it wears no beard of its own
Countryball.EMPIRE_BEARD = "beard_handlebar"
local balls: { [string]: any } = {}

--- The gear a ball wears: { hat?, beard?, glasses? } from a table (an equipped / cosmetics record)
--- or a single item id (any kind worn on the ball).
function Countryball.gear_of(gear: any): { [string]: string }
	local out = {}
	if type(gear) == "string" then
		local it = Gear.item(gear)
		if it ~= nil and Gear.on_ball(it.kind) then
			out[it.kind] = gear
		end
	elseif type(gear) == "table" then
		for _, kind in Gear.BALL_KINDS do
			local id = gear[kind]
			local it = if type(id) == "string" then Gear.item(id) else nil
			if it ~= nil and it.kind == kind then
				out[kind] = id
			end
		end
	end
	return out
end

--- `pose`: nil, or "rifle_left" / "rifle_right" (a soldier on a front: Map/FrontLayer).
function Countryball.ball_content(code: string?, name: string?, gear: any, pose: string?): Content?
	local worn = Countryball.gear_of(gear)
	local key = tostring(code)
		.. "|"
		.. tostring(name)
		.. "|"
		.. tostring(worn.hat)
		.. "|"
		.. tostring(worn.beard)
		.. "|"
		.. tostring(worn.glasses)
		.. "|"
		.. tostring(pose)
	local hit = balls[key]
	if hit ~= nil then
		return hit or nil
	end
	balls[key] = false
	local ok, img = pcall(function()
		return AssetService:CreateEditableImage({ Size = Vector2.new(G, G) })
	end)
	if not ok or img == nil then
		return nil
	end
	local g = FlagPix.forCode(code, name)
	local FW, FH = FlagPix.W, FlagPix.H
	local b = buffer.create(G * G * 4)
	local function put(x: number, y: number, c: Color3, k: number?)
		if x < 0 or y < 0 or x >= G or y >= G then
			return
		end
		local o = (y * G + x) * 4
		local m = k or 1
		buffer.writeu8(b, o, math.floor(c.R * 255 * m + 0.5))
		buffer.writeu8(b, o + 1, math.floor(c.G * 255 * m + 0.5))
		buffer.writeu8(b, o + 2, math.floor(c.B * 255 * m + 0.5))
		buffer.writeu8(b, o + 3, 255)
	end
	--- a pixel sprite { x, y, pal = { ch = {r, g, b} }, rows } at its canvas place
	local function sprite(s: any, dx: number?, dy: number?, mirror: boolean?)
		if s == nil or s.rows == nil then
			return
		end
		for j, row in s.rows do
			for i = 1, #row do
				local ch = string.sub(row, i, i)
				local rgb = s.pal[ch]
				local x = s.x + i - 1 + (dx or 0)
				if mirror then
					x = G - 1 - x
				end
				if rgb ~= nil then
					put(x, s.y + j - 1 + (dy or 0), Color3.fromRGB(rgb[1], rgb[2], rgb[3]))
				elseif ch == "o" then
					put(x, s.y + j - 1 + (dy or 0), OUT)
				end
			end
		end
	end
	local cx, cy, R = 15.5, 15.5, 13.6
	local grey = Color3.fromRGB(150, 156, 170)
	for y = 0, 31 do
		for x = 0, 31 do
			local dx, dy = x - cx, y - cy
			local d = math.sqrt(dx * dx + dy * dy)
			if d <= R + 0.5 then
				if d > R - 0.6 then
					put(x + OX, y + OY, OUT)
				else
					local u = math.clamp((x - (cx - R)) / (2 * R), 0, 0.999)
					local v = math.clamp((y - (cy - R)) / (2 * R), 0, 0.999)
					local c = grey
					if g ~= nil then
						c = g.pal[buffer.readu8(g.idx, math.floor(v * FH) * FW + math.floor(u * FW)) + 1] or grey
					end
					local nx, ny = dx / math.max(d, 1e-6), dy / math.max(d, 1e-6)
					local shade = (R - d) < 2.4 and (nx * 0.85 - ny * 0.25 > 0.45 or ny > 0.55)
					put(x + OX, y + OY, c, if shade then 0.8 else 1)
				end
			end
		end
	end
	local evil = Empires.is_empire(name) or (type(code) == "string" and string.sub(code, 1, 4) == "emp_")
	-- the beard (an empire's moustache) under the eyes, then the eyes, the glasses and the hat (an
	-- empire's helmet)
	local beard = Gear.item(worn.beard) or (if evil then Gear.item(Countryball.EMPIRE_BEARD) else nil)
	sprite(beard, 0, if evil and worn.beard == nil then 1 else 0)
	if evil and worn.glasses == nil then
		-- (Take Over the World!: the empire's angry eyes, from the user's evil ball; glasses the player
		-- wears replace them, as their hat replaces the helmet and their beard the moustache, so the
		-- empire's own pieces never sit under the player's: the glasses fit the ball's usual eyes)
		sprite(GearSprites.empire.eyes)
	else
		for _, spec in { { 8, false }, { 17, true } } do
			for j, row in EYE do
				for i = 1, #row do
					local ch = string.sub(row, if spec[2] then #row - i + 1 else i, if spec[2] then #row - i + 1 else i)
					local c = EYE_COL[ch]
					if c then
						put(spec[1] + i - 1 + OX, 11 + j + OY, c)
					end
				end
			end
		end
	end
	sprite(Gear.item(worn.glasses))
	if worn.hat ~= nil then
		sprite(Gear.item(worn.hat))
	elseif evil then
		sprite(GearSprites.empire.helmet)
	end
	-- (Take Over the World!: a front-line soldier's rifle, after the user's soldier balls: aiming left
	-- it rests on the ball's right side, aiming right (mirrored) on its left)
	if pose == "rifle_left" or pose == "rifle_right" then
		sprite(GearSprites.soldier.rifle, 0, 0, pose == "rifle_right")
	end
	img:WritePixelsBuffer(Vector2.zero, Vector2.new(G, G), b)
	local content = Content.fromObject(img)
	balls[key] = content
	return content
end

-- ===== (Take Over the World!, 2026-11-08) the map's little fighters =====

local function write_rgb(b: buffer, o: number, c: Color3, k: number?)
	local m = k or 1
	buffer.writeu8(b, o, math.floor(math.clamp(c.R * m, 0, 1) * 255 + 0.5))
	buffer.writeu8(b, o + 1, math.floor(math.clamp(c.G * m, 0, 1) * 255 + 0.5))
	buffer.writeu8(b, o + 2, math.floor(math.clamp(c.B * m, 0, 1) * 255 + 0.5))
	buffer.writeu8(b, o + 3, 255)
end

local function flag_at(g: any, u: number, v: number): Color3
	if g == nil then
		return Color3.fromRGB(150, 156, 170)
	end
	local FW, FH = FlagPix.W, FlagPix.H
	local x = math.clamp(math.floor(u * FW), 0, FW - 1)
	local y = math.clamp(math.floor(v * FH), 0, FH - 1)
	return g.pal[buffer.readu8(g.idx, y * FW + x) + 1] or Color3.fromRGB(150, 156, 170)
end

--- the mini soldier: a 16 x 16 sprite, shown at exactly 2x (Map/FrontLayer) so its circle stays round
Countryball.MINI = 16
local MINI_HELMET = {
	base = Color3.fromRGB(104, 113, 63),
	hi = Color3.fromRGB(126, 141, 75),
	dark = Color3.fromRGB(69, 81, 43),
}
local MINI_EMPIRE = {
	base = Color3.fromRGB(82, 82, 87),
	hi = Color3.fromRGB(129, 135, 146),
	dark = Color3.fromRGB(52, 52, 59),
	band = Color3.fromRGB(213, 165, 53),
}
local minis: { [string]: any } = {}

--- A front-line soldier as a little round Countryball (16 x 16): the flag, a helmet (an empire's
--- spiked one), eyes looking the way it faces and a rifle held across, aiming that way.
function Countryball.mini_content(code: string?, name: string?, right: boolean): Content?
	local key = tostring(code) .. "|" .. tostring(name) .. "|" .. tostring(right)
	local hit = minis[key]
	if hit ~= nil then
		return hit or nil
	end
	minis[key] = false
	local S = Countryball.MINI
	local ok, img = pcall(function()
		return AssetService:CreateEditableImage({ Size = Vector2.new(S, S) })
	end)
	if not ok or img == nil then
		return nil
	end
	local g = FlagPix.forCode(code, name)
	local evil = Empires.is_empire(name) or (type(code) == "string" and string.sub(code, 1, 4) == "emp_")
	local hm = if evil then MINI_EMPIRE else MINI_HELMET
	local b = buffer.create(S * S * 4)
	local function put(x: number, y: number, c: Color3, k: number?)
		if x >= 0 and y >= 0 and x < S and y < S then
			write_rgb(b, (y * S + x) * 4, c, k)
		end
	end
	local cx, cy, R = 7.5, 8.5, 6.6
	for y = 0, S - 1 do
		for x = 0, S - 1 do
			local dx, dy = x - cx, y - cy
			local d = math.sqrt(dx * dx + dy * dy)
			if d <= R + 0.5 then
				if d > R - 0.7 then
					put(x, y, OUT)
				elseif y <= 5 then -- the helmet over the top
					local c = if x - cx > 3 then hm.dark elseif x < 6 and y <= 3 then hm.hi else hm.base
					put(x, y, c)
				elseif y == 6 then -- its brim (an empire's gold band)
					put(x, y, if evil then hm.band else OUT)
				else
					local u = (x - (cx - R)) / (2 * R)
					local v = (y - (cy - R)) / (2 * R)
					local nx, ny = dx / math.max(d, 1e-6), dy / math.max(d, 1e-6)
					local shade = (R - d) < 1.8 and (nx * 0.8 - ny * 0.3 > 0.4 or ny > 0.6)
					put(x, y, flag_at(g, u, v), if shade then 0.8 else 1)
				end
			end
		end
	end
	if evil then -- the spike
		put(7, 0, OUT)
		put(7, 1, hm.hi)
		put(8, 1, hm.base)
	end
	-- the eyes: white with the pupil on the side it faces
	local white = Color3.new(1, 1, 1)
	for _, ex in { 4, 9 } do
		for i = 0, 2 do
			put(ex + i, 7, OUT)
		end
		for y = 8, 9 do
			put(ex, y, if right then white else OUT)
			put(ex + 1, y, white)
			put(ex + 2, y, if right then OUT else white)
		end
	end
	-- the rifle, across the lower half (drawn aiming right, mirrored to aim left)
	local stock, body, steel, dark = Color3.fromRGB(110, 66, 32), Color3.fromRGB(55, 60, 66), Color3.fromRGB(120, 140, 152), Color3.fromRGB(34, 40, 46)
	local function rp(x: number, y: number, c: Color3)
		put(if right then x else S - 1 - x, y, c)
	end
	for x = 2, 4 do
		rp(x, 10, OUT)
		rp(x, 11, stock)
		rp(x, 12, OUT)
	end
	rp(1, 11, OUT)
	for x = 5, 10 do
		rp(x, 11, body)
	end
	rp(9, 10, OUT)
	rp(6, 12, dark)
	rp(7, 12, dark)
	for x = 11, 15 do
		rp(x, 11, steel)
	end
	img:WritePixelsBuffer(Vector2.zero, Vector2.new(S, S), b)
	local content = Content.fromObject(img)
	minis[key] = content
	return content
end

local vehicles_drawn: { [string]: any } = {}
--- A Countryball vehicle (GearSprites.vehicles: "jet", "tank"), its ball in the owner's flag, facing
--- right or left (the art faces left: mirrored for right). 32 x 32.
function Countryball.vehicle_content(kind: string, code: string?, name: string?, right: boolean): Content?
	local key = kind .. "|" .. tostring(code) .. "|" .. tostring(name) .. "|" .. tostring(right)
	local hit = vehicles_drawn[key]
	if hit ~= nil then
		return hit or nil
	end
	vehicles_drawn[key] = false
	local v = GearSprites.vehicles and GearSprites.vehicles[kind]
	if v == nil then
		return nil
	end
	local S = 32
	local ok, img = pcall(function()
		return AssetService:CreateEditableImage({ Size = Vector2.new(S, S) })
	end)
	if not ok or img == nil then
		return nil
	end
	local g = FlagPix.forCode(code, name)
	local b = buffer.create(S * S * 4)
	local bx0, by0, bx1, by1 = v.ball[1], v.ball[2], v.ball[3], v.ball[4]
	for j, row in v.rows do
		local frow = v.flag[j]
		for i = 1, #row do
			local ch = string.sub(row, i, i)
			local x, y = v.x + i - 1, v.y + j - 1
			local c: Color3? = nil
			local k = 1
			local fc = if frow then string.sub(frow, i, i) else "."
			if fc == "F" or fc == "f" then
				-- the ball's flag (its lower part shows under the helmet)
				local u = (x - bx0) / math.max(1, bx1 - bx0)
				local vv = 0.3 + 0.7 * (y - by0) / math.max(1, by1 - by0)
				c = flag_at(g, u, vv)
				k = if fc == "f" then 0.72 else 1
			else
				local rgb = v.pal[ch]
				if rgb ~= nil then
					c = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
				end
			end
			if c ~= nil then
				local px = if right then S - 1 - x else x
				if px >= 0 and px < S and y >= 0 and y < S then
					write_rgb(b, (y * S + px) * 4, c, k)
				end
			end
		end
	end
	img:WritePixelsBuffer(Vector2.zero, Vector2.new(S, S), b)
	local content = Content.fromObject(img)
	vehicles_drawn[key] = content
	return content
end

--- A Countryball `px` wide for flag `code` (or the country `name`; a grey ball when unknown): one
--- crisp pixel sprite. `gear`: a hat id, or { hat?, beard?, glasses? }.
function Countryball.new(code: string?, px: number?, name: string?, gear: any): Frame
	local size = px or 64
	local root = Instance.new("Frame")
	root.Name = "Countryball"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(size, size)
	local body = Instance.new("ImageLabel")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Size = UDim2.fromScale(1, 1)
	body.ResampleMode = Enum.ResamplerMode.Pixelated
	body.ZIndex = 2
	local c = Countryball.ball_content(code, name, gear)
	if c ~= nil then
		body.ImageContent = c
	end
	body.Parent = root
	return root
end

return Countryball
