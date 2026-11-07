--!nonstrict
-- (Take Over the World!: the Countryball, 2026-11-06.)
-- A country's mascot: its flag (Data/FlagPix: this game's pixel flags, public-domain artwork) inside a
-- round body with a dark outline, a soft shine on top and two round eyes. This game's own simple
-- drawing from plain GUI objects and an EditableImage (no upload): Countryball.new(flag_code, px, name)
-- returns a Frame. A definition's `ball` field ("countryball:<code>", Data/Countries) names one.
local AssetService = game:GetService("AssetService")
local FlagPix = require(game:GetService("ReplicatedStorage"):WaitForChild("Airfront"):WaitForChild("Data"):WaitForChild("FlagPix"))

local Countryball = {}

local OUTLINE = Color3.fromRGB(16, 18, 28)

local cache: { [string]: any } = {}
--- A flag as image Content: the whole 30x20 flag, or (`square`) its centre 20x20 for the ball. nil when
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

local function eye(parent: Instance, x: number, look: number)
	local white = Instance.new("Frame")
	white.Name = "Eye"
	white.AnchorPoint = Vector2.new(0.5, 0.5)
	white.Position = UDim2.fromScale(x, 0.42)
	white.Size = UDim2.fromScale(0.2, 0.24)
	white.BackgroundColor3 = Color3.new(1, 1, 1)
	white.BorderSizePixel = 0
	white.ZIndex = 4
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = white
	local s = Instance.new("UIStroke")
	s.Color = OUTLINE
	s.Thickness = 1.5
	s.Parent = white
	local pupil = Instance.new("Frame")
	pupil.Name = "Pupil"
	pupil.AnchorPoint = Vector2.new(0.5, 0.5)
	pupil.Position = UDim2.fromScale(0.5 + look, 0.55)
	pupil.Size = UDim2.fromScale(0.42, 0.42)
	pupil.BackgroundColor3 = OUTLINE
	pupil.BorderSizePixel = 0
	pupil.ZIndex = 5
	local pc = Instance.new("UICorner")
	pc.CornerRadius = UDim.new(0.5, 0)
	pc.Parent = pupil
	pupil.Parent = white
	white.Parent = parent
	return white
end

--- A Countryball `px` wide for flag `code` (or the country `name`; a plain grey ball when unknown).
function Countryball.new(code: string?, px: number?, name: string?): Frame
	local size = px or 64
	local root = Instance.new("Frame")
	root.Name = "Countryball"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(size, size)

	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.AnchorPoint = Vector2.new(0.5, 0.5)
	shadow.Position = UDim2.fromScale(0.5, 0.97)
	shadow.Size = UDim2.fromScale(0.7, 0.12)
	shadow.BackgroundColor3 = Color3.new(0, 0, 0)
	shadow.BackgroundTransparency = 0.65
	shadow.BorderSizePixel = 0
	shadow.ZIndex = 1
	local shc = Instance.new("UICorner")
	shc.CornerRadius = UDim.new(0.5, 0)
	shc.Parent = shadow
	shadow.Parent = root

	local body = Instance.new("ImageLabel")
	body.Name = "Body"
	body.AnchorPoint = Vector2.new(0.5, 0.5)
	body.Position = UDim2.fromScale(0.5, 0.48)
	body.Size = UDim2.fromScale(0.9, 0.9)
	body.BackgroundColor3 = Color3.fromRGB(150, 156, 170)
	body.BorderSizePixel = 0
	body.ScaleType = Enum.ScaleType.Crop
	body.ZIndex = 2
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0.5, 0)
	bc.Parent = body
	local bs = Instance.new("UIStroke")
	bs.Color = OUTLINE
	bs.Thickness = math.max(1.5, size / 28)
	bs.Parent = body
	local flag = Countryball.flag_content(code, name, true)
	if flag ~= nil then
		body.ImageContent = flag
		body.ResampleMode = Enum.ResamplerMode.Pixelated
	end
	body.Parent = root

	-- shine: a soft white crescent at the top left
	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.AnchorPoint = Vector2.new(0.5, 0.5)
	shine.Position = UDim2.fromScale(0.34, 0.24)
	shine.Size = UDim2.fromScale(0.34, 0.18)
	shine.Rotation = -28
	shine.BackgroundColor3 = Color3.new(1, 1, 1)
	shine.BackgroundTransparency = 0.55
	shine.BorderSizePixel = 0
	shine.ZIndex = 3
	local sc = Instance.new("UICorner")
	sc.CornerRadius = UDim.new(0.5, 0)
	sc.Parent = shine
	shine.Parent = body

	eye(body, 0.36, 0.12)
	eye(body, 0.64, 0.12)
	return root
end

return Countryball
