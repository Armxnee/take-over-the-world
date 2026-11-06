--!strict
-- Procedural compact test map. Cells are numbered i = y * W + x (stable ids),
-- adjacency is the implicit 4-neighbourhood. Output terrain buffer is u8 per cell.
local MapGen = {}

local function lattice(rng: Random, gw: number, gh: number): { number }
	local t = table.create(gw * gh)
	for k = 1, gw * gh do
		t[k] = rng:NextNumber()
	end
	return t
end

local function smooth(v: number): number
	return v * v * (3 - 2 * v)
end

function MapGen.generate(W: number, H: number, seed: number, landTarget: number, minIsland: number)
	local rng = Random.new(seed)
	local N = W * H
	local elev = table.create(N, 0)
	local octaves = { { 48, 1.0 }, { 24, 0.5 }, { 12, 0.25 }, { 6, 0.12 } }
	for _, o in octaves do
		local s, amp = o[1], o[2]
		local gw, gh = W // s + 2, H // s + 2
		local lat = lattice(rng, gw, gh)
		for y = 0, H - 1 do
			local gy = y / s
			local y0 = math.floor(gy)
			local fy = smooth(gy - y0)
			for x = 0, W - 1 do
				local gx = x / s
				local x0 = math.floor(gx)
				local fx = smooth(gx - x0)
				local a = lat[y0 * gw + x0 + 1]
				local b = lat[y0 * gw + x0 + 2]
				local c = lat[(y0 + 1) * gw + x0 + 1]
				local d = lat[(y0 + 1) * gw + x0 + 2]
				local v = (a + (b - a) * fx) + ((c + (d - c) * fx) - (a + (b - a) * fx)) * fy
				local i = y * W + x + 1
				elev[i] += v * amp
			end
		end
	end
	-- ocean margin falloff
	for y = 0, H - 1 do
		for x = 0, W - 1 do
			local dx = math.min(x, W - 1 - x) / (W * 0.12)
			local dy = math.min(y, H - 1 - y) / (H * 0.12)
			local f = math.clamp(math.min(dx, dy), 0, 1)
			local i = y * W + x + 1
			elev[i] = elev[i] * (0.35 + 0.65 * f)
		end
	end
	-- sea level from target land share
	local sorted = table.clone(elev)
	table.sort(sorted)
	local sea = sorted[math.clamp(math.floor(N * (1 - landTarget)), 1, N)]
	local hi = sorted[math.clamp(math.floor(N * 0.97), 1, N)]
	local mid = sorted[math.clamp(math.floor(N * 0.88), 1, N)]

	local terrain = buffer.create(N)
	for i = 0, N - 1 do
		local e = elev[i + 1]
		local t = 0
		if e > hi then
			t = 3
		elseif e > mid then
			t = 2
		elseif e > sea then
			t = 1
		end
		buffer.writeu8(terrain, i, t)
	end

	-- drop tiny islands (flood fill)
	local seen = buffer.create(N)
	local stack = table.create(256)
	for start = 0, N - 1 do
		if buffer.readu8(terrain, start) ~= 0 and buffer.readu8(seen, start) == 0 then
			local blob = { start }
			buffer.writeu8(seen, start, 1)
			stack[1] = start
			local sp = 1
			while sp > 0 do
				local i = stack[sp]
				sp -= 1
				local x = i % W
				local nb = {
					if x > 0 then i - 1 else -1,
					if x < W - 1 then i + 1 else -1,
					if i >= W then i - W else -1,
					if i < N - W then i + W else -1,
				}
				for _, n in nb do
					if n >= 0 and buffer.readu8(seen, n) == 0 and buffer.readu8(terrain, n) ~= 0 then
						buffer.writeu8(seen, n, 1)
						sp += 1
						stack[sp] = n
						blob[#blob + 1] = n
					end
				end
			end
			if #blob < minIsland then
				for _, i in blob do
					buffer.writeu8(terrain, i, 0)
				end
			end
		end
	end
	return terrain
end

-- Decode "<value>:<len base36>," strings written by tools/build_maps.py.
local function decodeRle(str: string, N: number, bytes: number): buffer
	local out = buffer.create(N * bytes)
	local o = 0
	for v, len in string.gmatch(str, "(%d+):(%w+),") do
		local n = tonumber(len, 36) :: number
		local val = tonumber(v) :: number
		if bytes == 1 then
			buffer.fill(out, o, val, n)
		elseif val ~= 0 then
			for k = o, o + n - 1 do
				buffer.writeu16(out, k * 2, val)
			end
		end
		o += n
	end
	assert(o == N, "map rle size mismatch")
	return out
end

local function decodeModule(m: any): (buffer, buffer?)
	local N = m.w * m.h
	return decodeRle(m.rle, N, 1), if m.regions then decodeRle(m.regions, N, 2) else nil
end
MapGen.decodeModule = decodeModule

-- Returns terrain buffer, W, H, region buffer (u16, or nil) and region names for a map id.
function MapGen.load(id: string, seed: number): (buffer, number, number, buffer?, { string }?)
	local Config = require(script.Parent.Config)
	local def = Config.Maps[id] or Config.Maps.compact
	if def.Module then
		local mod = script.Parent.Maps:FindFirstChild(def.Module)
		assert(mod and mod:IsA("ModuleScript"), "missing map module " .. def.Module)
		local m = require(mod) :: any
		local terr, regions = decodeModule(m)
		return terr, m.w, m.h, regions, m.names
	end
	local s = if def.Seed ~= 0 then def.Seed else seed
	return MapGen.generate(def.W, def.H, s, def.LandTarget, def.MinIsland), def.W, def.H, nil, nil
end

-- Label connected water bodies (4-neighbour). Returns per-cell body id (0 = land)
-- and body sizes. Ice/land never count as water.
function MapGen.waterBodies(terrain: buffer, W: number, H: number): (buffer, { number })
	local N = W * H
	local body = buffer.create(N * 4)
	local sizes: { number } = {}
	local stack = table.create(1024)
	for start = 0, N - 1 do
		if buffer.readu8(terrain, start) == 0 and buffer.readu32(body, start * 4) == 0 then
			local id = #sizes + 1
			local count = 1
			buffer.writeu32(body, start * 4, id)
			stack[1] = start
			local sp = 1
			while sp > 0 do
				local i = stack[sp]
				sp -= 1
				local x = i % W
				for k = 1, 4 do
					local j = if k == 1 then (if x > 0 then i - 1 else -1)
						elseif k == 2 then (if x < W - 1 then i + 1 else -1)
						elseif k == 3 then i - W
						else i + W
					if j >= 0 and j < N and buffer.readu8(terrain, j) == 0 and buffer.readu32(body, j * 4) == 0 then
						buffer.writeu32(body, j * 4, id)
						count += 1
						sp += 1
						stack[sp] = j
					end
				end
			end
			sizes[id] = count
		end
	end
	return body, sizes
end

-- true if land cell i touches a water body of at least minSize cells
function MapGen.isCoastal(body: buffer, sizes: { number }, W: number, N: number, i: number, minSize: number): boolean
	local x = i % W
	for k = 1, 4 do
		local j = if k == 1 then (if x > 0 then i - 1 else -1)
			elseif k == 2 then (if x < W - 1 then i + 1 else -1)
			elseif k == 3 then i - W
			else i + W
		if j >= 0 and j < N then
			local b = buffer.readu32(body, j * 4)
			if b ~= 0 and sizes[b] >= minSize then
				return true
			end
		end
	end
	return false
end

-- Run-length encoding for snapshots: u32 runs, then runs x (u16 value, u32 length).
-- `bytes` is 1 (u8 cells) or 2 (u16 cells).
function MapGen.rleEncode(src: buffer, n: number, bytes: number): buffer
	local read = if bytes == 1 then buffer.readu8 else buffer.readu16
	local vals, lens = {}, {}
	local i = 0
	while i < n do
		local v = read(src, i * bytes)
		local j = i + 1
		while j < n and read(src, j * bytes) == v do
			j += 1
		end
		vals[#vals + 1] = v
		lens[#lens + 1] = j - i
		i = j
	end
	local out = buffer.create(4 + #vals * 6)
	buffer.writeu32(out, 0, #vals)
	local o = 4
	for k = 1, #vals do
		buffer.writeu16(out, o, vals[k])
		buffer.writeu32(out, o + 2, lens[k])
		o += 6
	end
	return out
end

function MapGen.rleDecode(src: buffer, n: number, bytes: number): buffer
	local out = buffer.create(n * bytes)
	local runs = buffer.readu32(src, 0)
	local o, i = 4, 0
	for _ = 1, runs do
		local v = buffer.readu16(src, o)
		local len = buffer.readu32(src, o + 2)
		o += 6
		if bytes == 1 then
			buffer.fill(out, i, v, len)
		elseif v == 0 then
			-- buffers start zeroed
		else
			for k = i, i + len - 1 do
				buffer.writeu16(out, k * 2, v)
			end
		end
		i += len
	end
	return out
end

return MapGen
