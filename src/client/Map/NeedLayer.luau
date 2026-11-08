--!nonstrict
-- (Take Over the World!, 2026-11-08) The land an empire still needs, in red over the map: the empire
-- circle's click (UI/EmpireButton -> MapView.show_empire_need) asks for `left` more tiles; the nearest
-- land beyond the player's borders that would make them up (a breadth-first search out from the
-- border) is painted red, pulsing, for SHOW_S seconds. One EditableImage a few tiles to a pixel,
-- stretched over the whole map each frame.
local AssetService = game:GetService("AssetService")
local RS = game:GetService("ReplicatedStorage")
local Defs = require(RS:WaitForChild("Airfront"):WaitForChild("Core"):WaitForChild("Defs")) :: any
local FrameClock = require(script.Parent:WaitForChild("FrameClock")) :: any

local NeedLayer = {}
NeedLayer.__index = NeedLayer

NeedLayer.SHOW_S = 8
NeedLayer.MAX_PX = 1024 -- (an EditableImage's largest side)
NeedLayer.Z = 13
NeedLayer.RED = { 255, 40, 50 }

function NeedLayer.new(parent: Instance, view: any)
	local self = setmetatable({}, NeedLayer)
	self.view = view
	local img = Instance.new("ImageLabel")
	img.Name = "EmpireNeed"
	img.BackgroundTransparency = 1
	img.ResampleMode = Enum.ResamplerMode.Pixelated
	img.Visible = false
	img.ZIndex = NeedLayer.Z
	img.Parent = parent
	self.img = img
	self._state = nil
	self._until = 0
	return self
end

function NeedLayer.bind(self, state: any)
	self._state = state
end

function NeedLayer.unbind(self)
	self._state = nil
	self:hide()
end

function NeedLayer.destroy(self)
	self.img:Destroy()
end

function NeedLayer.hide(self)
	self.img.Visible = false
	self._until = 0
end

function NeedLayer.showing(self): boolean
	return self.img.Visible
end

--- Paints the `left` tiles of land nearest the local player's borders (and returns how many it found).
function NeedLayer.show(self, left: number, border: { [number]: boolean }?): number
	local st = self._state
	local map = st and st.map
	local me = st and st.local_owner or 0
	if map == nil or me == 0 or left <= 0 then
		self:hide()
		return 0
	end
	local W = map.W or Defs.W
	local H = map.H or Defs.H
	local N = W * H
	-- where to start: the player's border tiles (the UI's BorderTracker), else every tile of theirs
	local queue, seen = {}, {}
	local head = 1
	local function push(t: number)
		if not seen[t] then
			seen[t] = true
			table.insert(queue, t)
		end
	end
	if border ~= nil and next(border) ~= nil then
		for t in border do
			push(t)
		end
	else
		for t = 0, N - 1 do
			if st:tile_owner(t) == me then
				push(t)
			end
		end
	end
	local picked = {}
	local n = 0
	while head <= #queue and n < left do
		local t = queue[head]
		head += 1
		local x = t % W
		for _, nb in { if x > 0 then t - 1 else -1, if x < W - 1 then t + 1 else -1, t - W, t + W } do
			if nb >= 0 and nb < N and not seen[nb] then
				local mine = st:tile_owner(nb) == me
				if mine then
					seen[nb] = true -- (the player's own land: walked through, not counted)
					table.insert(queue, nb)
				elseif map:is_land(nb) then
					seen[nb] = true
					table.insert(queue, nb)
					table.insert(picked, nb)
					n += 1
					if n >= left then
						break
					end
				end
			end
		end
	end
	-- paint them: a pixel per s x s tiles
	local s = math.max(1, math.ceil(math.max(W, H) / NeedLayer.MAX_PX))
	local gw, gh = math.ceil(W / s), math.ceil(H / s)
	if self._ei == nil or self._gw ~= gw or self._gh ~= gh then
		local ok, ei = pcall(function()
			return AssetService:CreateEditableImage({ Size = Vector2.new(gw, gh) })
		end)
		if not ok or ei == nil then
			return n
		end
		self._ei, self._gw, self._gh = ei, gw, gh
		self.img.ImageContent = Content.fromObject(ei)
	end
	local b = buffer.create(gw * gh * 4)
	local r, g, bl = NeedLayer.RED[1], NeedLayer.RED[2], NeedLayer.RED[3]
	for _, t in picked do
		local o = ((t // W) // s * gw + (t % W) // s) * 4
		buffer.writeu8(b, o, r)
		buffer.writeu8(b, o + 1, g)
		buffer.writeu8(b, o + 2, bl)
		buffer.writeu8(b, o + 3, 170)
	end
	self._ei:WritePixelsBuffer(Vector2.zero, Vector2.new(gw, gh), b)
	self._s = s
	self._until = FrameClock.now() + NeedLayer.SHOW_S
	self.img.Visible = n > 0
	return n
end

function NeedLayer.tick(self, _dt: number)
	if not self.img.Visible then
		return
	end
	local now = FrameClock.now()
	if now >= self._until then
		self:hide()
		return
	end
	local cam = self.view.rig
	local x0, y0 = cam:map_to_screen(0, 0)
	local x1, y1 = cam:map_to_screen(self._gw * self._s, self._gh * self._s)
	self.img.Position = UDim2.fromOffset(x0, y0)
	self.img.Size = UDim2.fromOffset(x1 - x0, y1 - y0)
	-- a slow pulse, fading out over the last second
	local fade = math.clamp(self._until - now, 0, 1)
	self.img.ImageTransparency = 1 - fade * (0.55 + 0.35 * (0.5 + 0.5 * math.sin(now * 5)))
end

return NeedLayer
