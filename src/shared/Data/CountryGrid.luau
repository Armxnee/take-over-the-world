--!strict
-- (Take Over the World!: real country borders, 2026-11-06.)
-- The country of each tile on a map, from Data/CountryGrids/<Module> (tools/build_country_grids.py:
-- Natural Earth admin-0 countries rasterized onto the map's own projection). Decoded once per map.
--   CountryGrid.get(map_id) -> grid? { w, h, nations = { {name, flag, x, y} }, idx = buffer (u16 per
--                              full-size tile: nation index, 0 = none) }
--   CountryGrid.at(grid, map, tile) -> nation index under a tile of `map` (also a smaller "id@80" build)
--   CountryGrid.nations(grid, map) -> { {name, flag, tile, index} } in the map's tile coordinates
local MapList = require("./MapList")

local CountryGrid = {}

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DEC: { [number]: number } = {}
for i = 1, #B64 do
	DEC[string.byte(B64, i)] = i - 1
end

local function b64(s: string): buffer
	local n = #s
	local pad = 0
	if string.sub(s, -2) == "==" then
		pad = 2
	elseif string.sub(s, -1) == "=" then
		pad = 1
	end
	local out = buffer.create(n // 4 * 3 - pad)
	local o = 0
	local len = buffer.len(out)
	for i = 1, n, 4 do
		local a = DEC[string.byte(s, i)] or 0
		local b = DEC[string.byte(s, i + 1)] or 0
		local c = DEC[string.byte(s, i + 2)] or 0
		local d = DEC[string.byte(s, i + 3)] or 0
		local v = a * 262144 + b * 4096 + c * 64 + d
		if o < len then
			buffer.writeu8(out, o, v // 65536)
		end
		if o + 1 < len then
			buffer.writeu8(out, o + 1, (v // 256) % 256)
		end
		if o + 2 < len then
			buffer.writeu8(out, o + 2, v % 256)
		end
		o += 3
	end
	return out
end

local cache: { [string]: any } = {}

local function module_of(id: string): ModuleScript?
	local entry = MapList.get(id)
	if entry == nil then
		return nil
	end
	local ok, folder = pcall(function()
		return (script :: any).Parent:FindFirstChild("CountryGrids")
	end)
	if not ok or folder == nil then
		return nil
	end
	return folder:FindFirstChild(entry.module)
end

function CountryGrid.get(map_id: string?): any?
	if type(map_id) ~= "string" then
		return nil
	end
	local base = string.match(map_id, "^(.-)@%d+$") or map_id
	local hit = cache[base]
	if hit ~= nil then
		return hit or nil
	end
	cache[base] = false
	local m = module_of(base)
	if m == nil then
		return nil
	end
	local data = (require :: any)(m)
	local w, h = data.w, data.h
	local raw = b64(data.runs)
	local idx = buffer.create(w * h * 2)
	local i, t, n = 0, 0, buffer.len(raw)
	while i < n do
		local v = buffer.readu16(raw, i)
		i += 2
		local run, shift = 0, 0
		while true do
			local byte = buffer.readu8(raw, i)
			i += 1
			run += bit32.band(byte, 0x7F) * 2 ^ shift
			shift += 7
			if byte < 0x80 then
				break
			end
		end
		if v ~= 0 then
			for k = t, t + run - 1 do
				buffer.writeu16(idx, k * 2, v)
			end
		end
		t += run
	end
	local grid = { w = w, h = h, nations = data.nations, idx = idx }
	cache[base] = grid
	return grid
end

--- The nation index under tile `t` of `map` (which may be a smaller build of the grid's map).
function CountryGrid.at(grid: any, map: any, t: number): number
	local W = map.W
	if W == grid.w then
		return buffer.readu16(grid.idx, t * 2)
	end
	local x, y = t % W, t // W
	local fx = math.min(grid.w - 1, math.floor((x + 0.5) * grid.w / W))
	local fy = math.min(grid.h - 1, math.floor((y + 0.5) * grid.h / (map.N // W)))
	return buffer.readu16(grid.idx, (fy * grid.w + fx) * 2)
end

--- The grid's nations in `map`'s tile coordinates: { {name, flag, tile, index} }.
function CountryGrid.nations(grid: any, map: any): { any }
	local W = map.W
	local H = map.N // W
	local out = {}
	for i, nd in grid.nations do
		local x = math.min(W - 1, math.floor(nd[3] * W / grid.w))
		local y = math.min(H - 1, math.floor(nd[4] * H / grid.h))
		table.insert(out, { name = nd[1], flag = if nd[2] ~= "" then nd[2] else nil, tile = y * W + x, x = x, y = y, index = i })
	end
	return out
end

return CountryGrid
