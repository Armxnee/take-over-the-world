--!strict
-- A* on the cell grid (4-neighbour) with a node budget. Returns cells start..goal.
local Sim = require(script.Parent.Sim)

local Path = {}

function Path.find(start: number, goal: number, passable: (number) -> boolean, maxNodes: number, greed: number?): { number }?
	local hw = greed or 1.2
	local W, N = Sim.W, Sim.N
	if start == goal then
		return { start }
	end
	local gx, gy = goal % W, goal // W
	local came: { [number]: number } = {}
	local gScore: { [number]: number } = { [start] = 0 }
	-- binary heap of {f, cell}
	local hf: { number } = {}
	local hc: { number } = {}
	local size = 0
	local function push(f: number, c: number)
		size += 1
		local k = size
		hf[k], hc[k] = f, c
		while k > 1 do
			local p = k // 2
			if hf[p] <= hf[k] then
				break
			end
			hf[p], hf[k] = hf[k], hf[p]
			hc[p], hc[k] = hc[k], hc[p]
			k = p
		end
	end
	local function pop(): number
		local top = hc[1]
		hf[1], hc[1] = hf[size], hc[size]
		hf[size], hc[size] = nil :: any, nil :: any
		size -= 1
		local k = 1
		while true do
			local l, r = k * 2, k * 2 + 1
			local m = k
			if l <= size and hf[l] < hf[m] then m = l end
			if r <= size and hf[r] < hf[m] then m = r end
			if m == k then
				break
			end
			hf[m], hf[k] = hf[k], hf[m]
			hc[m], hc[k] = hc[k], hc[m]
			k = m
		end
		return top
	end
	push(0, start)
	local expanded = 0
	while size > 0 do
		local c = pop()
		if c == goal then
			local out = { c }
			while came[c] do
				c = came[c]
				table.insert(out, c)
			end
			-- reverse
			local n = #out
			for k = 1, n // 2 do
				out[k], out[n - k + 1] = out[n - k + 1], out[k]
			end
			return out
		end
		expanded += 1
		if expanded > maxNodes then
			return nil
		end
		local x = c % W
		local from = came[c]
		for k = 1, 4 do
			local j = if k == 1 then (if x > 0 then c - 1 else -1)
				elseif k == 2 then (if x < W - 1 then c + 1 else -1)
				elseif k == 3 then c - W
				else c + W
			if j >= 0 and j < N and (j == goal or passable(j)) then
				-- turning costs extra so routes are long straight runs
				local g = gScore[c] + 1 + (if from and (c - from) ~= (j - c) then 0.6 else 0)
				local old = gScore[j]
				if not old or g < old then
					gScore[j] = g
					came[j] = c
					local jx, jy = j % W, j // W
					-- slightly greedy heuristic keeps searches small on open water
					push(g + (math.abs(jx - gx) + math.abs(jy - gy)) * hw, j)
				end
			end
		end
	end
	return nil
end

-- grid route a..b for aircraft and missiles: one straight horizontal run, then one
-- vertical run (they fly over anything); everything on the map moves on the grid
function Path.line(a: number, b: number): { number }
	local W = Sim.W
	local x0, y0, x1, y1 = a % W, a // W, b % W, b // W
	local out = { a }
	local sx = if x1 >= x0 then 1 else -1
	local sy = if y1 >= y0 then 1 else -1
	local x, y = x0, y0
	while x ~= x1 do
		x += sx
		out[#out + 1] = y * W + x
	end
	while y ~= y1 do
		y += sy
		out[#out + 1] = y * W + x
	end
	return out
end

-- water cell next to a land cell (first found), or nil
function Path.waterBeside(i: number): number?
	local W, N = Sim.W, Sim.N
	local x = i % W
	for k = 1, 4 do
		local j = if k == 1 then (if x > 0 then i - 1 else -1)
			elseif k == 2 then (if x < W - 1 then i + 1 else -1)
			elseif k == 3 then i - W
			else i + W
		if j >= 0 and j < N and Sim.terrAt(j) == 0 then
			local b = buffer.readu32(Sim.water, j * 4)
			if Sim.waterSize[b] and Sim.waterSize[b] >= 200 then
				return j
			end
		end
	end
	return nil
end

return Path
