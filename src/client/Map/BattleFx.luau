--!nonstrict
-- (Take Over the World!, 2026-11-08) The map's little battles' effects, drawn in screen px over the map
-- (Map/FrontLayer's soldiers and tanks, Map/UnitLayer's jets): a rifle shot (a muzzle flash, a tracer
-- flying to the target, a spark where it lands), a cannon shot (a big flash, a shell, an explosion with
-- smoke) and a jet's strafing (quick tracers and sparks). Pixel squares only: frames from a pool,
-- moved by hand every frame (no tweens), so a hundred shots cost little.
local BattleFx = {}
BattleFx.__index = BattleFx

BattleFx.FLASH_S = 0.07
BattleFx.TRACER_S = 0.11
BattleFx.SHELL_S = 0.22
BattleFx.BLAST_S = 0.38
BattleFx.SMOKE_S = 0.7
BattleFx.SPARK_S = 0.16

local FLASH = Color3.fromRGB(255, 236, 150)
local TRACER = Color3.fromRGB(255, 214, 90)
local SPARK = Color3.fromRGB(255, 250, 220)
local FIRE = Color3.fromRGB(255, 150, 40)
local FIRE_HOT = Color3.fromRGB(255, 230, 120)
local SMOKE = Color3.fromRGB(90, 90, 96)
local SHELL = Color3.fromRGB(40, 40, 44)

function BattleFx.new(parent: Instance, z: number)
	local self = setmetatable({}, BattleFx)
	self.parent = parent
	self.z = z
	self.live = {}
	self.free = {}
	self.corner = {} -- frame -> its UICorner (round blasts and smoke, square pixels)
	return self
end

function BattleFx._frame(self, color: Color3, w: number, h: number, round: boolean?): Frame
	local f = table.remove(self.free)
	if f == nil then
		f = Instance.new("Frame")
		f.Name = "Fx"
		f.BorderSizePixel = 0
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.ZIndex = self.z
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 0)
		c.Parent = f
		self.corner[f] = c
		f.Parent = self.parent
	end
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 0
	f.Size = UDim2.fromOffset(w, h)
	f.Rotation = 0
	f.Visible = true
	self.corner[f].CornerRadius = UDim.new(if round then 1 else 0, 0)
	return f
end

function BattleFx._add(self, fx: any)
	table.insert(self.live, fx)
end

--- A rifle shot from (x0, y0) to (x1, y1).
function BattleFx.shot(self, now: number, x0: number, y0: number, x1: number, y1: number)
	local flash = self:_frame(FLASH, 7, 7)
	flash.Position = UDim2.fromOffset(x0, y0)
	self:_add({ f = flash, kind = "flash", t0 = now, size = 7 })
	local tr = self:_frame(TRACER, 9, 2)
	tr.Rotation = math.deg(math.atan2(y1 - y0, x1 - x0))
	tr.Position = UDim2.fromOffset(x0, y0)
	self:_add({ f = tr, kind = "tracer", t0 = now, x = x0, y = y0, x1 = x1, y1 = y1, dur = BattleFx.TRACER_S })
end

--- A tank's cannon: a big flash and a puff at the muzzle, a shell, and an explosion where it lands.
function BattleFx.cannon(self, now: number, x0: number, y0: number, x1: number, y1: number)
	local flash = self:_frame(FIRE_HOT, 13, 13, true)
	flash.Position = UDim2.fromOffset(x0, y0)
	self:_add({ f = flash, kind = "flash", t0 = now, size = 13, dur = 0.12 })
	local puff = self:_frame(SMOKE, 8, 8, true)
	puff.Position = UDim2.fromOffset(x0, y0)
	self:_add({ f = puff, kind = "smoke", t0 = now, x = x0, y = y0, size = 8, dur = 0.5 })
	local sh = self:_frame(SHELL, 5, 4)
	sh.Rotation = math.deg(math.atan2(y1 - y0, x1 - x0))
	sh.Position = UDim2.fromOffset(x0, y0)
	self:_add({ f = sh, kind = "shell", t0 = now, x = x0, y = y0, x1 = x1, y1 = y1, dur = BattleFx.SHELL_S })
end

--- An explosion at (x, y): a hot core growing and fading to orange, sparks and a puff of smoke.
function BattleFx.blast(self, now: number, x: number, y: number, r: number?)
	local size = r or 18
	local core = self:_frame(FIRE_HOT, 4, 4, true)
	core.Position = UDim2.fromOffset(x, y)
	self:_add({ f = core, kind = "blast", t0 = now, size = size, dur = BattleFx.BLAST_S })
	for _ = 1, 4 do
		local a = math.random() * math.pi * 2
		local s = self:_frame(SPARK, 3, 3)
		s.Position = UDim2.fromOffset(x, y)
		local d = size * (0.6 + math.random() * 0.6)
		self:_add({ f = s, kind = "tracer", t0 = now, x = x, y = y, x1 = x + math.cos(a) * d, y1 = y + math.sin(a) * d, dur = 0.25, fade = true })
	end
	local smoke = self:_frame(SMOKE, 6, 6, true)
	smoke.Position = UDim2.fromOffset(x, y)
	self:_add({ f = smoke, kind = "smoke", t0 = now + 0.08, x = x, y = y, size = size * 0.8, dur = BattleFx.SMOKE_S })
end

function BattleFx.tick(self, now: number)
	local list = self.live
	local i = 1
	while i <= #list do
		local fx = list[i]
		local age = now - fx.t0
		local done = false
		local f = fx.f
		if age < 0 then
			f.BackgroundTransparency = 1
		elseif fx.kind == "flash" then
			local k = math.clamp(age / (fx.dur or BattleFx.FLASH_S), 0, 1)
			f.BackgroundTransparency = k
			local s = fx.size * (1 - 0.5 * k)
			f.Size = UDim2.fromOffset(s, s)
			done = k >= 1
		elseif fx.kind == "tracer" or fx.kind == "shell" then
			local k = age / fx.dur
			if k >= 1 then
				if fx.kind == "shell" then
					-- the shell lands: an explosion
					fx.kind, fx.t0, fx.size, fx.dur = "blast", now, 16, BattleFx.BLAST_S
					f.BackgroundColor3 = FIRE_HOT
					f.Rotation = 0
					self.corner[f].CornerRadius = UDim.new(1, 0)
					f.Position = UDim2.fromOffset(fx.x1, fx.y1)
					self:blast(now, fx.x1, fx.y1, 14)
				elseif fx.fade then
					done = true
				else
					-- a bullet lands: a spark
					fx.kind, fx.t0 = "spark", now
					f.Rotation = 45
					f.Size = UDim2.fromOffset(5, 5)
					f.BackgroundColor3 = SPARK
					f.Position = UDim2.fromOffset(fx.x1, fx.y1)
				end
			else
				f.Position = UDim2.fromOffset(fx.x + (fx.x1 - fx.x) * k, fx.y + (fx.y1 - fx.y) * k)
				if fx.fade then
					f.BackgroundTransparency = k
				end
			end
		elseif fx.kind == "spark" then
			local k = math.clamp(age / BattleFx.SPARK_S, 0, 1)
			f.BackgroundTransparency = k
			f.BackgroundColor3 = SPARK:Lerp(Color3.fromRGB(120, 120, 120), k)
			done = k >= 1
		elseif fx.kind == "blast" then
			local k = math.clamp(age / fx.dur, 0, 1)
			local s = 4 + fx.size * math.sqrt(k)
			f.Size = UDim2.fromOffset(s, s)
			f.BackgroundColor3 = FIRE_HOT:Lerp(FIRE, math.min(1, k * 2))
			f.BackgroundTransparency = k * k
			done = k >= 1
		elseif fx.kind == "smoke" then
			local k = math.clamp(age / fx.dur, 0, 1)
			local s = fx.size * (0.6 + k)
			f.Size = UDim2.fromOffset(s, s)
			f.Position = UDim2.fromOffset(fx.x, fx.y - k * 10)
			f.BackgroundTransparency = 0.35 + 0.65 * k
			done = k >= 1
		end
		if done then
			f.Visible = false
			table.insert(self.free, f)
			list[i] = list[#list]
			list[#list] = nil
		else
			i += 1
		end
	end
end

--- Every effect gone at once (a match ends).
function BattleFx.clear(self)
	for _, fx in self.live do
		fx.f.Visible = false
		table.insert(self.free, fx.f)
	end
	table.clear(self.live)
end

return BattleFx
