--!strict
-- 16x16 pixel icons (pixel style like the map and sprites), drawn from simple shapes with
-- an automatic 1px dark outline. Buildings: city, defense, port, factory, silo, sam,
-- airfield, aa. Wheel actions: attack, ally, troops, info, breakAlly, accept.
local AssetService = game:GetService("AssetService")

local Icons = {}
local cache: { [string]: EditableImage } = {}

type Shape = { any }
local P = {
	k = "0E1217", w = "F2F5F8", l = "C9D1DA", g = "8C98A6", d = "4A5562", y = "F5C451", r = "E5484D",
	b = "3F86D9", B = "2B5BA8", G = "46B46E", o = "6E7F45", n = "8A5A2B", s = "F1C7A1", c = "5FD3E8",
}

-- shape list: { "rect", x0, y0, x1, y1, col } | { "circ", cx, cy, r, col } | { "poly", {pts}, col } | { "ring", cx, cy, r0, r1, col }
local DEF: { [string]: { Shape } } = {
	city = {
		{ "rect", 1, 7, 5, 15, "g" }, { "rect", 5, 3, 10, 15, "l" }, { "rect", 10, 6, 15, 15, "g" },
		{ "rect", 2, 9, 3, 10, "y" }, { "rect", 2, 12, 3, 13, "y" }, { "rect", 6, 5, 7, 6, "y" }, { "rect", 8, 5, 9, 6, "y" },
		{ "rect", 6, 8, 7, 9, "y" }, { "rect", 8, 8, 9, 9, "y" }, { "rect", 6, 11, 7, 12, "y" }, { "rect", 8, 11, 9, 12, "y" },
		{ "rect", 11, 8, 12, 9, "y" }, { "rect", 13, 8, 14, 9, "y" }, { "rect", 11, 11, 12, 12, "y" }, { "rect", 13, 11, 14, 12, "y" },
	},
	defense = {
		{ "poly", { 3, 2, 13, 2, 13, 8, 8, 14.5, 3, 8 }, "b" },
		{ "poly", { 8, 2, 13, 2, 13, 8, 8, 14.5 }, "B" },
		{ "rect", 7, 4, 9, 11, "w" }, { "rect", 5, 6, 11, 8, "w" },
	},
	port = {
		{ "ring", 8, 3.5, 1.0, 2.3, "l" },
		{ "rect", 7, 5, 9, 14, "l" }, { "rect", 4, 6.5, 12, 8, "l" },
		{ "poly", { 1.5, 9.5, 3.5, 9.5, 8, 13.2, 12.5, 9.5, 14.5, 9.5, 8, 15.5 }, "l" },
	},
	factory = {
		{ "rect", 1, 8, 15, 15, "g" },
		{ "poly", { 1, 8, 1, 4.5, 5, 8 }, "d" }, { "poly", { 5, 8, 5, 4.5, 9, 8 }, "d" },
		{ "rect", 11, 2, 13, 8, "r" }, { "circ", 14, 1.4, 1.2, "l" },
		{ "rect", 3, 11, 4, 12, "y" }, { "rect", 6, 11, 7, 12, "y" }, { "rect", 9, 11, 10, 12, "y" }, { "rect", 12, 11, 13, 12, "y" },
	},
	silo = {
		{ "rect", 1, 12, 15, 15, "d" }, { "rect", 3.5, 5, 5, 12, "g" }, { "rect", 11, 5, 12.5, 12, "g" },
		{ "rect", 7, 3, 9, 12, "w" }, { "poly", { 7, 3, 8, 0.6, 9, 3 }, "r" },
		{ "poly", { 5.6, 12, 7, 8.5, 7, 12 }, "r" }, { "poly", { 9, 12, 9, 8.5, 10.4, 12 }, "r" },
		{ "rect", 7, 7, 9, 8, "y" },
	},
	sam = {
		{ "rect", 2, 11.5, 14, 14.5, "o" }, { "rect", 5, 8.5, 11, 11.5, "g" },
		{ "poly", { 5.5, 9, 11.5, 2.6, 12.7, 3.8, 6.7, 10.2 }, "w" }, { "poly", { 11.5, 2.6, 13.6, 1.6, 12.7, 3.8 }, "r" },
		{ "poly", { 8.5, 9, 14.2, 3.4, 15.2, 4.6, 9.6, 10.2 }, "w" },
	},
	airfield = {
		{ "rect", 6, 0, 10, 16, "d" }, { "rect", 7.6, 1, 8.4, 3, "w" }, { "rect", 7.6, 13, 8.4, 15, "w" },
		{ "rect", 7, 3.5, 9, 12.5, "l" }, { "poly", { 1.5, 8, 14.5, 8, 14.5, 9.6, 1.5, 9.6 }, "l" },
		{ "poly", { 5, 11.4, 11, 11.4, 11, 12.6, 5, 12.6 }, "l" }, { "rect", 7.4, 4.2, 8.6, 5.6, "c" },
	},
	aa = {
		{ "rect", 2, 11.5, 14, 14.5, "o" }, { "circ", 8, 10, 2.6, "g" },
		{ "poly", { 7, 10, 2.4, 2.8, 3.6, 2, 8.4, 9.2 }, "d" }, { "poly", { 9, 10, 13.6, 2.8, 12.4, 2, 7.6, 9.2 }, "d" },
		{ "circ", 3, 2.4, 0.9, "y" }, { "circ", 13, 2.4, 0.9, "y" },
	},
	attack = {
		{ "poly", { 2, 3, 3, 2, 13, 12, 12, 13 }, "l" }, { "poly", { 14, 3, 13, 2, 3, 12, 4, 13 }, "l" },
		{ "rect", 10.5, 11.5, 14.5, 12.8, "n" }, { "rect", 1.5, 11.5, 5.5, 12.8, "n" },
		{ "rect", 12.4, 12.8, 13.6, 15, "y" }, { "rect", 2.4, 12.8, 3.6, 15, "y" },
	},
	ally = {
		{ "circ", 5, 4.5, 2.3, "s" }, { "poly", { 1.5, 15, 1.5, 10, 3, 8, 7, 8, 8.5, 10, 8.5, 15 }, "b" },
		{ "circ", 11, 4.5, 2.3, "s" }, { "poly", { 7.5, 15, 7.5, 10, 9, 8, 13, 8, 14.5, 10, 14.5, 15 }, "G" },
		{ "rect", 6.5, 10, 9.5, 11.6, "s" },
	},
	accept = {
		{ "poly", { 1.5, 8.5, 3.5, 6.5, 6.5, 9.5, 12.5, 3.5, 14.5, 5.5, 6.5, 13.5 }, "G" },
	},
	troops = {
		{ "poly", { 3, 7, 4, 3.5, 8, 2, 12, 3.5, 13, 7 }, "o" }, { "rect", 2, 6.5, 14, 7.8, "o" },
		{ "circ", 8, 9.5, 3, "s" }, { "rect", 6.6, 9, 7.4, 9.8, "k" }, { "rect", 8.6, 9, 9.4, 9.8, "k" },
		{ "poly", { 3, 16, 4, 12.5, 12, 12.5, 13, 16 }, "o" },
	},
	info = {
		{ "circ", 8, 8, 6.8, "b" }, { "rect", 7, 6.5, 9, 12.5, "w" }, { "rect", 7, 3.5, 9, 5.2, "w" },
	},
	music = {
		{ "rect", 6, 2, 7.4, 12, "w" }, { "rect", 11, 1, 12.4, 10.5, "w" }, { "poly", { 6, 2, 12.4, 0.6, 12.4, 3.4, 6, 4.8 }, "w" },
		{ "circ", 4.6, 12.2, 2.2, "w" }, { "circ", 9.6, 10.8, 2.2, "w" },
	},
	sound = {
		{ "rect", 1.5, 6, 4.5, 10, "w" }, { "poly", { 4.5, 6, 9, 2, 9, 14, 4.5, 10 }, "w" },
		{ "ring", 9, 8, 3, 4, "l" }, { "ring", 9, 8, 5.4, 6.4, "l" },
		{ "rect", 0, 0, 9, 16, "_" },
	},
	exit = {
		{ "rect", 2, 1, 9, 15, "g" }, { "rect", 3, 2, 8, 14, "d" }, { "circ", 6.6, 8.5, 0.8, "y" },
		{ "poly", { 8, 6.6, 11.5, 6.6, 11.5, 4, 15.5, 8, 11.5, 12, 11.5, 9.4, 8, 9.4 }, "w" },
	},
	help = {
		{ "circ", 8, 8, 7, "b" },
		{ "rect", 5.4, 3, 10.6, 4.6, "w" }, { "rect", 9, 3, 10.6, 7.6, "w" }, { "rect", 5.4, 3, 7, 5.6, "w" },
		{ "rect", 7.2, 6.2, 10.6, 7.8, "w" }, { "rect", 7.2, 7.8, 8.8, 9.8, "w" }, { "rect", 7.2, 11, 8.8, 12.8, "w" },
	},
	board = {
		{ "rect", 1.5, 9, 5, 15, "l" }, { "rect", 6.3, 3, 9.7, 15, "y" }, { "rect", 11, 6.5, 14.5, 15, "l" },
		{ "rect", 7.3, 5, 8.7, 6.4, "n" },
	},
	play = { { "poly", { 4, 2, 14, 8, 4, 14 }, "w" } },
	globe = {
		{ "circ", 8, 8, 7, "b" },
		{ "poly", { 3, 4.5, 7, 3, 8.4, 6, 6.2, 8.2, 7, 11.5, 3.6, 10 }, "G" },
		{ "poly", { 9.4, 9, 13, 7, 14.4, 10, 11.4, 13.4, 10, 12 }, "G" },
	},
	close = { { "poly", { 2, 4, 4, 2, 8, 6, 12, 2, 14, 4, 10, 8, 14, 12, 12, 14, 8, 10, 4, 14, 2, 12, 6, 8 }, "w" } },
	gear = {
		{ "circ", 8, 8, 5.6, "l" }, { "rect", 6.8, 0.8, 9.2, 15.2, "l" }, { "rect", 0.8, 6.8, 15.2, 9.2, "l" },
		{ "poly", { 2.6, 4.2, 4.2, 2.6, 13.4, 11.8, 11.8, 13.4 }, "l" }, { "poly", { 11.8, 2.6, 13.4, 4.2, 4.2, 13.4, 2.6, 11.8 }, "l" },
		{ "circ", 8, 8, 2.4, "d" },
	},
	users = {
		{ "circ", 11.4, 5.4, 2.2, "l" }, { "poly", { 10, 8.6, 13.4, 8.6, 15, 10.6, 15, 13.6, 11, 13.6 }, "l" },
		{ "circ", 6, 5, 2.7, "c" }, { "poly", { 1.4, 14, 1.8, 10.2, 3.8, 8.6, 8.2, 8.6, 10.2, 10.2, 10.6, 14 }, "c" },
	},
	crown = { { "poly", { 2, 12, 1.4, 4, 5, 8, 8, 2.4, 11, 8, 14.6, 4, 14, 12 }, "y" }, { "rect", 2, 12.6, 14, 14.6, "y" } },
	breakAlly = {
		{ "ring", 5, 9, 1.4, 3.2, "l" }, { "ring", 11, 7, 1.4, 3.2, "l" },
		{ "poly", { 7.4, 1.5, 9.6, 1.5, 8.4, 5, 10.2, 5, 6.8, 11, 7.6, 6.6, 6, 6.6 }, "y" },
	},
}

local function inPoly(pts: { number }, x: number, y: number): boolean
	local inside = false
	local n = #pts // 2
	local j = n
	for i = 1, n do
		local xi, yi, xj, yj = pts[i * 2 - 1], pts[i * 2], pts[j * 2 - 1], pts[j * 2]
		if (yi > y) ~= (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi then
			inside = not inside
		end
		j = i
	end
	return inside
end

function Icons.image(name: string): EditableImage?
	if cache[name] then
		return cache[name]
	end
	local def = DEF[name]
	if not def then
		return nil
	end
	local S = 16
	local ok, img = pcall(function()
		return AssetService:CreateEditableImage({ Size = Vector2.new(S, S) })
	end)
	if not ok or not img then
		return nil
	end
	local cols: { string? } = table.create(S * S, nil)
	for y = 0, S - 1 do
		for x = 0, S - 1 do
			local px, py = x + 0.5, y + 0.5
			for _, sh in def do
				local kind = sh[1]
				local hit = false
				local col
				if kind == "rect" then
					hit = px >= sh[2] and px < sh[4] and py >= sh[3] and py < sh[5]
					col = sh[6]
				elseif kind == "circ" then
					hit = (px - sh[2]) ^ 2 + (py - sh[3]) ^ 2 <= sh[4] ^ 2
					col = sh[5]
				elseif kind == "ring" then
					local d = math.sqrt((px - sh[2]) ^ 2 + (py - sh[3]) ^ 2)
					hit = d >= sh[4] and d <= sh[5]
					col = sh[6]
				elseif kind == "poly" then
					hit = inPoly(sh[2], px, py)
					col = sh[3]
				end
				if hit then
					cols[y * S + x + 1] = if col == "_" then (if (cols[y * S + x + 1] == "l") then nil else cols[y * S + x + 1]) else col
				end
			end
		end
	end
	local b = buffer.create(S * S * 4)
	for y = 0, S - 1 do
		for x = 0, S - 1 do
			local c = cols[y * S + x + 1]
			local hex: string? = if c then P[c] else nil
			if not hex then
				-- outline ring around the drawing
				for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
					local nx, ny = x + d[1], y + d[2]
					if nx >= 0 and ny >= 0 and nx < S and ny < S and cols[ny * S + nx + 1] then
						hex = P.k
					end
				end
			end
			local o = (y * S + x) * 4
			if hex then
				local col = Color3.fromHex(hex)
				buffer.writeu8(b, o, math.floor(col.R * 255))
				buffer.writeu8(b, o + 1, math.floor(col.G * 255))
				buffer.writeu8(b, o + 2, math.floor(col.B * 255))
				buffer.writeu8(b, o + 3, 255)
			end
		end
	end
	img:WritePixelsBuffer(Vector2.zero, Vector2.new(S, S), b)
	cache[name] = img
	return img
end

-- ImageLabel showing an icon, pixelated
function Icons.label(name: string, size: number, parent: Instance?): ImageLabel
	local l = Instance.new("ImageLabel")
	l.BackgroundTransparency = 1
	l.ResampleMode = Enum.ResamplerMode.Pixelated
	l.Size = UDim2.fromOffset(size, size)
	local img = Icons.image(name)
	if img then
		l.ImageContent = Content.fromObject(img)
	end
	if parent then
		l.Parent = parent
	end
	return l
end

-- set an existing ImageLabel to an icon
function Icons.apply(l: ImageLabel, name: string)
	local img = Icons.image(name)
	if img then
		l.Image = ""
		l.ImageContent = Content.fromObject(img)
		l.ResampleMode = Enum.ResamplerMode.Pixelated
	end
end

return Icons
