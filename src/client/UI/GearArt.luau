--!nonstrict
-- (Take Over the World!: gear pictures, 2026-11-07.)
-- What the item shop, the Locker and the crate reveal show for an item of Data/Gear: a hat on a
-- Countryball (Countryball.ball_content), a boat / nuke / missile skin as pixel art in its colour, and
-- the supply crate. Drawn into EditableImages once each, then cached.
--   GearArt.content(it, flag?) -> Content?   (flag: the ball a hat sits on, an ISO code; "gb" otherwise)
--   GearArt.crate() -> Content?
local AssetService = game:GetService("AssetService")
local Airfront = game:GetService("ReplicatedStorage"):WaitForChild("Airfront")
local Gear = require(Airfront.Data.Gear)
local Countryball = require("./Countryball")

local GearArt = {}

--- pixel art for the unit skins and the crate ("." clear, "o" outline, "a" the colour, "d" lighter,
--- "k" darker, "f" flame, "c" metal)
local ART = {
	boat = {
		"................",
		"......oo........",
		"......oco.......",
		".....oooooo.....",
		"....oaaaaaao....",
		"..oooaddaaaooo..",
		"oooaaaaaaaaaaooo",
		"oaaaaaaaaaaaaaao",
		".oaaaaaaaaaaaao.",
		"..okkkkkkkkkko..",
		"...oooooooooo...",
	},
	nuke = {
		"....oo....oo....",
		"....okko.okko...",
		".....okkookko...",
		"......okkkko....",
		".....oooooooo...",
		"....oaaaaaaaao..",
		"...oaddaaaaaaao.",
		"...oadaaaaaaaao.",
		"...oaaaaaaaaaao.",
		"...oaaaaaaaaaao.",
		"....oaaaaaaaao..",
		".....oaaaaaao...",
		"......oaaaao....",
		".......oooo.....",
	},
	missile = {
		".......oo.......",
		"......oaao......",
		"......oaao......",
		".....oaaaao.....",
		".....oadaao.....",
		".....oadaao.....",
		".....oaaaao.....",
		".....oaaaao.....",
		".....oaaaao.....",
		"....ooaaaaoo....",
		"...okoaaaaoko...",
		"...okkoooookko..",
		"...oo..ff..oo...",
		".......ff.......",
	},
	crate = {
		"oooooooooooooooo",
		"oddddddddddddddo",
		"oaaaaaaaaaaaaaao",
		"oooooooooooooooo",
		"okkkkkkcckkkkkko",
		"okaaaaaccaaaaako",
		"okaaaaaccaaaaako",
		"occcccccccccccco",
		"okaaaaaccaaaaako",
		"okaaaaaccaaaaako",
		"okkkkkkcckkkkkko",
		"oooooooooooooooo",
	},
}
local OUTLINE = Color3.fromRGB(18, 20, 28)
local arts: { [string]: any } = {}
--- `ART[shape]` drawn in colour `col` (cached by `key`), as Content.
function GearArt.pixel(key: string, shape: string, col: Color3): Content?
	if arts[key] ~= nil then
		return arts[key] or nil
	end
	arts[key] = false
	local rows = ART[shape]
	local S = 16
	local okI, img = pcall(function()
		return AssetService:CreateEditableImage({ Size = Vector2.new(S, S) })
	end)
	if not okI or img == nil then
		return nil
	end
	local pal = {
		o = OUTLINE,
		a = col,
		d = col:Lerp(Color3.new(1, 1, 1), 0.45),
		k = Color3.new(col.R * 0.62, col.G * 0.62, col.B * 0.62),
		f = Color3.fromRGB(255, 150, 40),
		c = Color3.fromRGB(214, 218, 228),
	}
	local b = buffer.create(S * S * 4)
	local oy = (S - #rows) // 2
	for j, row in rows do
		for i = 1, #row do
			local c = pal[string.sub(row, i, i)]
			if c ~= nil then
				local o = ((oy + j - 1) * S + i - 1) * 4
				buffer.writeu8(b, o, math.floor(c.R * 255 + 0.5))
				buffer.writeu8(b, o + 1, math.floor(c.G * 255 + 0.5))
				buffer.writeu8(b, o + 2, math.floor(c.B * 255 + 0.5))
				buffer.writeu8(b, o + 3, 255)
			end
		end
	end
	img:WritePixelsBuffer(Vector2.zero, Vector2.new(S, S), b)
	local content = Content.fromObject(img)
	arts[key] = content
	return content
end
--- the balls hats are shown on (a few flags, by card)
local BALLS = { "gb", "fr", "de", "jp", "br", "us", "it", "ca" }


--- An item's picture (nil for items that aren't gear).
function GearArt.content(it: any, flag: string?): Content?
	if it == nil then
		return nil
	end
	if it.kind == "hat" then
		return Countryball.ball_content(flag or "gb", nil, it.id)
	end
	if ART[it.kind] ~= nil then
		return GearArt.pixel(it.id, it.kind, Gear.color(it.id) or Color3.new(1, 1, 1))
	end
	return nil
end

function GearArt.crate(): Content?
	return GearArt.pixel("crate", "crate", Color3.fromRGB(122, 132, 64))
end

return GearArt
