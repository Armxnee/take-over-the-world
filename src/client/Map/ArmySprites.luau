--!strict
-- (Take Over the World!: army sprites, 2026-11-06.)
-- This game's own 16x16 pixel sprites for the ground units: a soldier, a tank and a field gun, one
-- dark outline, a shared olive palette, drawn into EditableImages at load (no uploads) and shown with
-- Pixelated resampling so they stay crisp at any zoom.
local AssetService = game:GetService("AssetService")

local ArmySprites = {}

local PAL: { [string]: Color3 } = {
	k = Color3.fromRGB(16, 18, 28), -- outline
	d = Color3.fromRGB(52, 64, 40), -- dark olive
	m = Color3.fromRGB(88, 108, 60), -- olive
	l = Color3.fromRGB(138, 160, 92), -- light olive
	s = Color3.fromRGB(232, 190, 150), -- skin
	g = Color3.fromRGB(78, 82, 94), -- gun metal
	h = Color3.fromRGB(150, 156, 170), -- metal highlight
	w = Color3.fromRGB(38, 38, 44), -- wheels / tracks
}

ArmySprites.ART = {
	infantry = {
		"................",
		"......kkkk......",
		".....kmlmmk.....",
		"....kmllmmmk....",
		"....kkkkkkkk....",
		".....kssssk.....",
		".....kskksk.....",
		"......kssk...kk.",
		".....kmmmmk.khk.",
		"....kmmlmmmkgk..",
		"....kmlmmmmgk...",
		"....kmmmmmmk....",
		".....kddkddk....",
		".....kddkddk....",
		".....kkk.kkk....",
		"................",
	},
	tank = {
		"................",
		"................",
		"................",
		"................",
		"......kkkkk.....",
		".....kmllmmkkkkk",
		".....kmmmmmkhhgk",
		"..kkkkkkkkkkkkk.",
		".kmlllmmmmmmmmk.",
		".kmmmmmmmmmmmmk.",
		"..kkkkkkkkkkkk..",
		".kwhwhwhwhwhwhk.",
		".kwwwwwwwwwwwwk.",
		"..kkkkkkkkkkkk..",
		"................",
		"................",
	},
	artillery = {
		"................",
		"................",
		"..............k.",
		"............khk.",
		"..........kggk..",
		"........kggk....",
		"......kggk......",
		"....kmmmmmk.....",
		"...kmllmmmmk....",
		"..kkkkkkkkkkk...",
		".kwwk....kwwk...",
		"kwhkwk..kwhkwk..",
		"kwkkwk..kwkkwk..",
		".kwwk....kwwk...",
		"................",
		"................",
	},
}

local cache: { [string]: Content } = {}

--- The sprite of unit type `kind` ("infantry" / "tank" / "artillery") as image Content, or nil.
function ArmySprites.content(kind: string): Content?
	local hit = cache[kind]
	if hit ~= nil then
		return hit
	end
	local rows = ArmySprites.ART[kind]
	if rows == nil then
		return nil
	end
	local ok, img = pcall(function()
		return AssetService:CreateEditableImage({ Size = Vector2.new(16, 16) })
	end)
	if not ok or img == nil then
		return nil
	end
	local b = buffer.create(16 * 16 * 4)
	for y = 1, 16 do
		local row = rows[y]
		for x = 1, 16 do
			local c = PAL[string.sub(row, x, x)]
			local o = ((y - 1) * 16 + (x - 1)) * 4
			if c ~= nil then
				buffer.writeu8(b, o, math.floor(c.R * 255 + 0.5))
				buffer.writeu8(b, o + 1, math.floor(c.G * 255 + 0.5))
				buffer.writeu8(b, o + 2, math.floor(c.B * 255 + 0.5))
				buffer.writeu8(b, o + 3, 255)
			end
		end
	end
	img:WritePixelsBuffer(Vector2.zero, Vector2.new(16, 16), b)
	local content = Content.fromObject(img)
	cache[kind] = content
	return content
end

--- The type an army shows: tanks when they lead its numbers, else artillery-heavy, else infantry.
function ArmySprites.kind_of(a: any): string
	if a == nil then
		return "infantry"
	end
	local inf, tank, art = a.infantry or 0, a.tank or 0, a.artillery or 0
	if tank >= inf and tank >= art and tank > 0 then
		return "tank"
	elseif art > inf then
		return "artillery"
	end
	return "infantry"
end

return ArmySprites
