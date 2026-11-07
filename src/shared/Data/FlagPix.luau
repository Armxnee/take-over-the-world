--!strict
-- (Take Over the World!: this game's own pixel flags, moved from legacy/shared on 2026-11-06 because
-- RoWorld's flag atlases are private to its account.)
-- Pixel flags (30x20). Real flags come from FlagData (built by tools/build_flags.py from the
-- real flag artwork); shop flags are sampled from their Flags spec into the same grid.
-- grid = { pal = { Color3 } (1-based), idx = buffer of W*H palette indices (0-based) }
local Flags = require(script.Parent.FlagSpecs)

local FlagPix = {}
FlagPix.W, FlagPix.H = 30, 20
local W, H = FlagPix.W, FlagPix.H

local names: { [string]: string }? = nil
local parts: { { [string]: string } } = {}
local byCode: { [string]: any } = {}
local bySpec: { [any]: any } = {}

local function digit(b: number): number
	return if b <= 57 then b - 48 else b - 87 -- 0-9, a-z
end

local function decode(s: string): any
	local bar = string.find(s, "|", 1, true) :: number
	local pal = {}
	for k = 1, bar - 1, 6 do
		table.insert(pal, Color3.fromHex(string.sub(s, k, k + 5)))
	end
	local idx = buffer.create(W * H)
	for i = 0, W * H - 1 do
		buffer.writeu8(idx, i, digit(string.byte(s, bar + 1 + i)))
	end
	return { pal = pal, idx = idx }
end

--- (Take Over the World!: flags drawn by hand at 30 x 20, where the downscaled artwork smudges. The US:
--- 13 stripes, red 2 px and white 1 px, a 12 x 11 canton with 45 stars.)
FlagPix.OVERRIDES = {
	us = "ffffffb222343c3b6e|222222222222111111111111111111202020202022111111111111111111220202020202000000000000000000202020202022111111111111111111220202020202111111111111111111202020202022000000000000000000220202020202111111111111111111202020202022111111111111111111220202020202000000000000000000202020202022111111111111111111222222222222111111111111111111000000000000000000000000000000111111111111111111111111111111111111111111111111111111111111000000000000000000000000000000111111111111111111111111111111111111111111111111111111111111000000000000000000000000000000111111111111111111111111111111111111111111111111111111111111",
}

function FlagPix.code(name: string): string?
	if not names then
		local folder = script.Parent:FindFirstChild("FlagData")
		local nm = folder and folder:FindFirstChild("Names")
		names = if nm then require(nm :: ModuleScript) :: any else {}
		-- (Take Over the World!: flags drawn by hand win over the generated ones; then the empires)
		table.insert(parts, FlagPix.OVERRIDES)
		if folder then
			for _, part in { "Empires", "PixA", "PixB" } do
				local m = folder:FindFirstChild(part)
				if m then
					table.insert(parts, require(m :: ModuleScript) :: any)
				end
			end
		end
	end
	return (names :: any)[name]
end

-- the real flag of a country / state name, or nil
function FlagPix.forName(name: string): any
	local c = FlagPix.code(name)
	if not c then
		return nil
	end
	local g = byCode[c]
	if g == nil then
		g = false
		for _, p in parts do
			if p[c] then
				g = decode(p[c])
				break
			end
		end
		byCode[c] = g
	end
	return g or nil
end

-- a Flags sampler spec (shop flags / fallback) as a pixel grid
function FlagPix.fromSpec(spec: any): any
	local g = bySpec[spec]
	if g then
		return g
	end
	local pal, seen = {}, {}
	local idx = buffer.create(W * H)
	for y = 0, H - 1 do
		for x = 0, W - 1 do
			local hx = Flags.sample(spec, (x + 0.5) / W, (y + 0.5) / H)
			local k = seen[hx]
			if not k then
				table.insert(pal, Color3.fromHex(hx))
				k = #pal - 1
				seen[hx] = k
			end
			buffer.writeu8(idx, y * W + x, k)
		end
	end
	g = { pal = pal, idx = idx }
	bySpec[spec] = g
	return g
end

-- real flag first, then the hand-made spec list
function FlagPix.forCountry(name: string): any
	local g = FlagPix.forName(name)
	if g then
		return g
	end
	local spec = Flags.byName[name]
	return if spec then FlagPix.fromSpec(spec) else nil
end

--- A map nation's flag: by its flag code ("us", "ca"...), else by its name, else the spec list.
function FlagPix.forCode(code: string?, name: string?): any
	FlagPix.code("") -- loads the data parts
	if code ~= nil then
		local c = string.lower(code)
		local g = byCode[c]
		if g == nil then
			g = false
			for _, part in parts do
				if part[c] then
					g = decode(part[c])
					break
				end
			end
			byCode[c] = g
		end
		if g then
			return g
		end
	end
	return if name ~= nil then FlagPix.forCountry(name) else nil
end

--- (Take Over the World!: the colour a flag reads as: its most used colour, white, black and greys counting
--- for less; nil without a flag)
function FlagPix.main_color(code: string?, name: string?): Color3?
	local g = FlagPix.forCode(code, name)
	if g == nil then
		return nil
	end
	local count = {}
	for i = 0, W * H - 1 do
		local k = buffer.readu8(g.idx, i) + 1
		count[k] = (count[k] or 0) + 1
	end
	local best, best_s = nil, -1
	for k, n in count do
		local c = g.pal[k]
		if c ~= nil then
			local _, s, v = c:ToHSV()
			local weight = if s < 0.18 or v < 0.2 then 0.05 else 1
			local score = n * weight
			if score > best_s then
				best, best_s = c, score
			end
		end
	end
	return best
end

return FlagPix
