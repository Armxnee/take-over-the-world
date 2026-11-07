--!nonstrict
-- (Take Over the World!: the Countryball, 2026-11-06.)
-- A country's mascot: its flag (Data/FlagPix: this game's pixel flags, public-domain artwork) as a
-- pixel-art ball (2026-11-06 redesign after the user's reference): dark outline, shaded rim, two eyes.
-- Drawn into an EditableImage (no upload): Countryball.new(flag_code, px, name) returns a Frame.
-- A definition's `ball` field ("countryball:<code>", Data/Countries) names one.
local AssetService = game:GetService("AssetService")
local FlagPix = require(game:GetService("ReplicatedStorage"):WaitForChild("Airfront"):WaitForChild("Data"):WaitForChild("FlagPix"))
local Gear = require(game:GetService("ReplicatedStorage"):WaitForChild("Airfront"):WaitForChild("Data"):WaitForChild("Gear")) -- (Take Over the World!: hats)

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

--- The ball as one pixel sprite (G x G): a dark outline, the flag across the body, a darker rim band
--- on the upper right and along the bottom, and two round-topped white eyes with a grey glint.
Countryball.G = 32
local G = Countryball.G
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
local balls: { [string]: any } = {}

function Countryball.ball_content(code: string?, name: string?, hat: string?): Content?
	local key = tostring(code) .. "|" .. tostring(name) .. "|" .. tostring(hat)
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
		local o = (y * G + x) * 4
		local m = k or 1
		buffer.writeu8(b, o, math.floor(c.R * 255 * m + 0.5))
		buffer.writeu8(b, o + 1, math.floor(c.G * 255 * m + 0.5))
		buffer.writeu8(b, o + 2, math.floor(c.B * 255 * m + 0.5))
		buffer.writeu8(b, o + 3, 255)
	end
	local cx, cy, R = 15.5, 15.5, 13.6
	local grey = Color3.fromRGB(150, 156, 170)
	for y = 0, G - 1 do
		for x = 0, G - 1 do
			local dx, dy = x - cx, y - cy
			local d = math.sqrt(dx * dx + dy * dy)
			if d <= R + 0.5 then
				if d > R - 0.6 then
					put(x, y, OUT)
				else
					local u = math.clamp((x - (cx - R)) / (2 * R), 0, 0.999)
					local v = math.clamp((y - (cy - R)) / (2 * R), 0, 0.999)
					local c = grey
					if g ~= nil then
						c = g.pal[buffer.readu8(g.idx, math.floor(v * FH) * FW + math.floor(u * FW)) + 1] or grey
					end
					local nx, ny = dx / math.max(d, 1e-6), dy / math.max(d, 1e-6)
					local shade = (R - d) < 2.4 and (nx * 0.85 - ny * 0.25 > 0.45 or ny > 0.55)
					put(x, y, c, if shade then 0.8 else 1)
				end
			end
		end
	end
	for _, spec in { { 8, false }, { 17, true } } do
		for j, row in EYE do
			for i = 1, #row do
				local ch = string.sub(row, if spec[2] then #row - i + 1 else i, if spec[2] then #row - i + 1 else i)
				local c = EYE_COL[ch]
				if c then
					put(spec[1] + i - 1, 11 + j, c)
				end
			end
		end
	end
	-- (Take Over the World!: a hat from the item shop, over the top of the ball)
	local hg = if hat ~= nil then Gear.item(hat) else nil
	if hg ~= nil and hg.rows ~= nil then
		for j, row in hg.rows do
			local y = hg.y + j - 1
			for i = 1, #row do
				local ch = string.sub(row, i, i)
				local x = hg.x + i - 1
				if ch ~= "." and x >= 0 and x < G and y >= 0 and y < G then
					if ch == "o" then
						put(x, y, OUT)
					else
						local rgb = hg.pal[ch]
						if rgb ~= nil then
							put(x, y, Color3.fromRGB(rgb[1], rgb[2], rgb[3]))
						end
					end
				end
			end
		end
	end
	img:WritePixelsBuffer(Vector2.zero, Vector2.new(G, G), b)
	local content = Content.fromObject(img)
	balls[key] = content
	return content
end

--- A Countryball `px` wide for flag `code` (or the country `name`; a grey ball when unknown): one
--- crisp pixel sprite.
function Countryball.new(code: string?, px: number?, name: string?, hat: string?): Frame
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
	local c = Countryball.ball_content(code, name, hat)
	if c ~= nil then
		body.ImageContent = c
	end
	body.Parent = root
	return root
end

return Countryball
