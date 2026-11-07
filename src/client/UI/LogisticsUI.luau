--!nonstrict
-- (Take Over the World!: logistics and resources UI, 2026-11-06.)
--   resource bar (top right)   money (the existing gold) and the five strategic stocks with their
--                              production per second (GameState.resources, from Ev.RES)
--   LOGISTICS (top left)       the logistics view over the map: supply links between the player's
--                              connected provinces (railway / road / plain, by the lower level of the two
--                              ends), provinces cut off from supply, depots with their stock, isolated
--                              armies, work sites; and the build panel
--   build panel (right)        in logistics view, click one of your provinces: its deposits, levels and
--                              the next level of each infrastructure with its cost; BUILD sends the
--                              "build_infra" intent (the server's Sim validates and pays)
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
local Airfront = RS:WaitForChild("Airfront")
local Defs = require(Airfront.Core.Defs)
local Logistics = require(Airfront.Data.Logistics)
local UITheme = require("./UITheme")

local LogisticsUI = {}
LogisticsUI.__index = LogisticsUI

local FONT = "rbxassetid://12187365977"
local NAVY = Color3.fromHex("0D1326")
local AMBER = Color3.fromHex("FFB547")
local TEXT = Color3.new(1, 1, 1)
local TEXT2 = Color3.fromHex("A9B4D0")
local GREEN = Color3.fromHex("5BE38E")
local RED = Color3.fromHex("FF5C61")
local CYAN = Color3.fromHex("49C6F2")
local RES_COLORS = {
	gold = AMBER,
	food = GREEN,
	steel = Color3.fromHex("9DB0C8"),
	oil = Color3.fromHex("C9A27E"),
	aluminum = Color3.fromHex("E3E8F0"),
	rare = Color3.fromHex("B48CFF"),
}
local RES_SHORT = { gold = "Money", food = "Food", steel = "Steel", oil = "Oil", aluminum = "Alum.", rare = "Rare" }

local function make(class: string, props: { [string]: any }, parent: Instance?): any
	local o = Instance.new(class)
	for k, v in props do
		o[k] = v
	end
	if parent then
		o.Parent = parent
	end
	return o
end

local function label(parent: Instance, text: string, size: number, weight: Enum.FontWeight, color: Color3, props: { [string]: any }?): TextLabel
	local l = make("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextSize = size,
		FontFace = Font.new(FONT, weight),
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, 0, 0, size + 4),
	}, parent)
	for k, v in props or {} do
		l[k] = v
	end
	return l
end

local function glass(parent: Instance, name: string): Frame
	local f = make("Frame", { Name = name, BackgroundColor3 = NAVY, BackgroundTransparency = 0.12, BorderSizePixel = 0 }, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 12) }, f)
	make("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.88, Thickness = 1 }, f)
	return f
end

local function short(n: number): string
	n = math.floor(n + 0.5)
	if math.abs(n) >= 1e6 then
		return string.format("%.1fM", n / 1e6)
	elseif math.abs(n) >= 1e4 then
		return string.format("%.0fK", n / 1e3)
	elseif math.abs(n) >= 1e3 then
		return string.format("%.1fK", n / 1e3)
	end
	return tostring(n)
end

function LogisticsUI.new(ctx: any, gui: Instance)
	local self = setmetatable({}, LogisticsUI)
	self.ctx = ctx
	self.visible = false
	self.view = false
	self.pid = 0
	self.tile = -1
	self._acc = 0
	self._adj = nil
	self._adj_for = nil
	self._building_adj = false
	self._lines = {}
	self._marks = {}

	local root = make("Frame", { Name = "Logistics", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 18 }, gui)
	self.root = root
	-- overlay under the panels
	self.overlay = make("Frame", { Name = "Overlay", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false }, root)

	-- resource bar
	local bar = glass(root, "Resources")
	bar.AnchorPoint = Vector2.new(1, 0)
	bar.Size = UDim2.fromOffset(600, 40)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), VerticalAlignment = Enum.VerticalAlignment.Center }, bar)
	make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, bar)
	self.bar = bar
	self.chips = {}
	for i, k in { "gold", "food", "steel", "oil", "aluminum", "rare" } do
		local chip = make("Frame", { BackgroundTransparency = 1, LayoutOrder = i, Size = UDim2.fromOffset(94, 34) }, bar)
		make("Frame", { BackgroundColor3 = RES_COLORS[k], BorderSizePixel = 0, Position = UDim2.fromOffset(0, 8), Size = UDim2.fromOffset(6, 18) }, chip)
		label(chip, RES_SHORT[k], 10, Enum.FontWeight.Bold, TEXT2, { Position = UDim2.fromOffset(10, 1), Size = UDim2.new(1, -10, 0, 12) })
		local v = label(chip, "0", 14, Enum.FontWeight.Heavy, TEXT, { Position = UDim2.fromOffset(10, 13), Size = UDim2.new(1, -10, 0, 16) })
		local r = label(chip, "", 9, Enum.FontWeight.Bold, GREEN, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -2, 0, 2),
			Size = UDim2.fromOffset(44, 10),
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		self.chips[k] = { value = v, rate = r }
	end

	-- toggle
	local tb = make("TextButton", {
		Text = "LOGISTICS",
		TextSize = 15,
		FontFace = Font.new(FONT, Enum.FontWeight.Heavy),
		TextColor3 = TEXT,
		BackgroundColor3 = Color3.fromHex("2A3352"),
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(172, 72),
		Size = UDim2.fromOffset(150, 40),
		Selectable = true,
	}, root)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, tb)
	tb.Activated:Connect(function()
		self:set_view(not self.view)
	end)
	self.toggle = tb

	-- legend (logistics view)
	local lg = glass(root, "Legend")
	lg.Position = UDim2.fromOffset(330, 72)
	lg.Size = UDim2.fromOffset(250, 92)
	lg.Visible = false
	make("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 10) }, lg)
	for i, spec in { { CYAN, "Railway link" }, { AMBER, "Road link" }, { GREEN, "Basic link" }, { RED, "Cut off / isolated" } } do
		make("Frame", { BackgroundColor3 = spec[1], BorderSizePixel = 0, Position = UDim2.fromOffset(0, (i - 1) * 19 + 6), Size = UDim2.fromOffset(18, 4) }, lg)
		label(lg, spec[2], 12, Enum.FontWeight.Medium, TEXT2, { Position = UDim2.fromOffset(26, (i - 1) * 19), Size = UDim2.new(1, -26, 0, 16) })
	end
	label(lg, "Click your province to build", 11, Enum.FontWeight.Bold, AMBER, { Position = UDim2.fromOffset(120, 0), Size = UDim2.fromOffset(120, 14), Visible = false })
	self.legend = lg

	-- build panel
	local bp = glass(root, "Build")
	bp.AnchorPoint = Vector2.new(1, 0)
	bp.Size = UDim2.fromOffset(320, 380)
	bp.Visible = false
	make("UIPadding", {
		PaddingTop = UDim.new(0, 12),
		PaddingBottom = UDim.new(0, 12),
		PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 14),
	}, bp)
	self.panel = bp
	self.p_name = label(bp, "", 16, Enum.FontWeight.Heavy, TEXT)
	self.p_info = label(bp, "", 11, Enum.FontWeight.Medium, TEXT2, {
		Position = UDim2.fromOffset(0, 20),
		Size = UDim2.new(1, 0, 0, 28),
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	self.p_job = label(bp, "", 12, Enum.FontWeight.Bold, AMBER, { Position = UDim2.fromOffset(0, 50) })
	self.rows = {}
	local kinds = table.clone(Logistics.INFRA_ORDER)
	table.insert(kinds, "port")
	for i, k in kinds do
		local y = 70 + (i - 1) * 40
		local row = make("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.95, BorderSizePixel = 0, Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 36) }, bp)
		make("UICorner", { CornerRadius = UDim.new(0, 8) }, row)
		local name = label(row, "", 13, Enum.FontWeight.Bold, TEXT, { Position = UDim2.fromOffset(8, 2), Size = UDim2.new(1, -90, 0, 16) })
		local cost = label(row, "", 10, Enum.FontWeight.Medium, TEXT2, { Position = UDim2.fromOffset(8, 19), Size = UDim2.new(1, -90, 0, 13) })
		local b = make("TextButton", {
			Text = "BUILD",
			TextSize = 12,
			FontFace = Font.new(FONT, Enum.FontWeight.Heavy),
			TextColor3 = Color3.fromHex("3A2400"),
			BackgroundColor3 = AMBER,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -4, 0.5, 0),
			Size = UDim2.fromOffset(74, 28),
			Selectable = true,
		}, row)
		make("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
		b.Activated:Connect(function()
			self:_build(k)
		end)
		self.rows[k] = { name = name, cost = cost, button = b }
	end

	self._conn = RunService.RenderStepped:Connect(function(dt)
		if not self.visible then
			return
		end
		self._acc += dt
		if self._acc >= 0.25 then
			self._acc = 0
			self:_refresh_bar()
			if self.panel.Visible then
				self:_refresh_panel()
			end
		end
		if self.view then
			self:_draw()
		end
	end)
	self:apply_layout()
	return self
end

function LogisticsUI.apply_layout(self)
	local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	self.bar.Position = UDim2.fromOffset(vp.X - 16, 46)
	self.panel.Position = UDim2.fromOffset(vp.X - 16, 96)
end

function LogisticsUI.set_visible(self, on: boolean)
	self.visible = on
	self.root.Visible = on
	if not on then
		self:set_view(false)
	end
end

function LogisticsUI.set_view(self, on: boolean)
	self.view = on
	self.overlay.Visible = on
	self.legend.Visible = on
	self.toggle.BackgroundColor3 = if on then CYAN else Color3.fromHex("2A3352")
	self.toggle.TextColor3 = if on then NAVY else TEXT
	if not on then
		self.panel.Visible = false
		for _, f in self._lines do
			f.Visible = false
		end
		for _, f in self._marks do
			f.Visible = false
		end
	end
	self.ctx:sfx("click")
end

function LogisticsUI._P(self): any
	local picker = self.ctx.country_picker
	return picker and picker.P
end

-- province adjacency on the client (from the same province grid as the server), built once in slices
function LogisticsUI._adjacency(self): any
	local P = self:_P()
	if P == nil then
		return nil
	end
	if self._adj_for == P then
		return self._adj
	end
	if self._building_adj then
		return nil
	end
	self._building_adj = true
	task.spawn(function()
		local W = P.W
		local prov_of = P.prov_of
		local N = buffer.len(prov_of) // 2
		local seen, adj = {}, {}
		for id = 1, #P.list do
			adj[id] = {}
		end
		for t = 0, N - 1 do
			local p = buffer.readu16(prov_of, t * 2)
			if p ~= 0 then
				for _, n in { if t % W < W - 1 then t + 1 else -1, if t + W < N then t + W else -1 } do
					if n >= 0 then
						local q = buffer.readu16(prov_of, n * 2)
						if q ~= 0 and q ~= p then
							local k = if p < q then p * 65536 + q else q * 65536 + p
							if not seen[k] then
								seen[k] = true
								table.insert(adj[p], q)
								table.insert(adj[q], p)
							end
						end
					end
				end
			end
			if t % 150000 == 0 then
				task.wait()
			end
		end
		self._adj, self._adj_for = adj, P
		self._building_adj = false
	end)
	return nil
end

function LogisticsUI._refresh_bar(self)
	local s = self.ctx.state
	local me = self.ctx:me()
	local o = s and s.owners[me]
	local r = s and s.resources and s.resources[me]
	self.chips.gold.value.Text = short(o and o.gold or 0)
	self.chips.gold.rate.Text = if o and (o.income or 0) > 0 then "+" .. short(o.income) else ""
	for _, k in Logistics.RESOURCES do
		local c = self.chips[k]
		local v = r and r[k] or 0
		c.value.Text = short(v)
		local rate = r and r.rate[k] or 0
		c.rate.Text = if rate > 0 then string.format("+%.1f", rate) else ""
		c.value.TextColor3 = if r and v >= (r.cap or math.huge) then AMBER elseif v <= 0 then RED else TEXT
	end
end

local function infra_of(s: any, pid: number): any
	return (s.infra and s.infra[pid]) or { road = 0, rail = 0, depot = 0, farm = 0, steel = 0, oil = 0, building = 0, finish = 0, stock = 0 }
end

function LogisticsUI._line(self, i: number, a: Vector2, b: Vector2, col: Color3, w: number)
	local f = self._lines[i]
	if f == nil then
		f = make("Frame", { BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 0.15 }, self.overlay)
		self._lines[i] = f
	end
	local d = b - a
	f.Visible = true
	f.BackgroundColor3 = col
	f.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
	f.Size = UDim2.fromOffset(d.Magnitude, w)
	f.Rotation = math.deg(math.atan2(d.Y, d.X))
end

function LogisticsUI._mark(self, i: number, p: Vector2, col: Color3, text: string, size: number)
	local f = self._marks[i]
	if f == nil then
		f = make("TextLabel", {
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			TextColor3 = NAVY,
			FontFace = Font.new(FONT, Enum.FontWeight.Heavy),
			TextSize = 11,
			ZIndex = 2,
		}, self.overlay)
		make("UICorner", { CornerRadius = UDim.new(0, 4) }, f)
		make("UIStroke", { Color = NAVY, Thickness = 1.5 }, f)
		self._marks[i] = f
	end
	f.Visible = true
	f.BackgroundColor3 = col
	f.Text = text
	f.Size = UDim2.fromOffset(size, size)
	f.Position = UDim2.fromOffset(p.X, p.Y)
end

-- the logistics view, every frame while it is on (only what is on screen)
function LogisticsUI._draw(self)
	local ctx = self.ctx
	local s = ctx.state
	local P = self:_P()
	local adj = self:_adjacency()
	local me = ctx:me()
	local net = s and s.supplynet and s.supplynet[me]
	if s == nil or P == nil or adj == nil or net == nil then
		return
	end
	local vp = workspace.CurrentCamera.ViewportSize
	local pos = {}
	local function at(pid: number): Vector2?
		local v = pos[pid]
		if v == nil then
			v = ctx:world_call("screen_pos_of_tile", { P.list[pid].seed })
			if typeof(v) ~= "Vector2" then
				v = Vector2.new(-1, -1)
			end
			pos[pid] = v
		end
		return if v.X >= 0 then v else nil
	end
	local function on_screen(v: Vector2?): boolean
		return v ~= nil and v.X > -50 and v.Y > -50 and v.X < vp.X + 50 and v.Y < vp.Y + 50
	end
	local li, mi = 0, 0
	for a in net do
		for _, b in adj[a] or {} do
			if b > a and net[b] ~= nil then
				local pa, pb = at(a), at(b)
				if pa and pb and (on_screen(pa) or on_screen(pb)) then
					local ia, ib = infra_of(s, a), infra_of(s, b)
					local rail, road = math.min(ia.rail, ib.rail), math.min(ia.road, ib.road)
					li += 1
					if rail > 0 then
						self:_line(li, pa, pb, CYAN, 3 + rail)
					elseif road > 0 then
						self:_line(li, pa, pb, AMBER, 2 + road)
					else
						self:_line(li, pa, pb, GREEN, 2)
					end
				end
			end
		end
	end
	-- the player's provinces cut off from supply; depots; work sites
	for pid, p in P.list do
		local v = at(pid)
		if v and on_screen(v) then
			local mine = s:tile_owner(p.seed) == me
			local inf = infra_of(s, pid)
			if mine and net[pid] == nil then
				mi += 1
				self:_mark(mi, v, RED, "!", 14)
			end
			if inf.depot > 0 and (mine or net[pid]) then
				mi += 1
				self:_mark(mi, v + Vector2.new(0, -14), if inf.stock > 0 then AMBER else TEXT2, "D" .. inf.depot, 20)
			end
			if (inf.building or 0) > 0 and mine then
				mi += 1
				self:_mark(mi, v + Vector2.new(16, -14), TEXT, "…", 16)
			end
		end
	end
	-- isolated armies
	for id, a in s.armies or {} do
		if a.owner == me and not a.connected and s.units[id] ~= nil then
			local v = at(a.province or 0)
			if v and on_screen(v) then
				mi += 1
				self:_mark(mi, v + Vector2.new(0, 18), RED, "CUT", 30)
			end
		end
	end
	for i = li + 1, #self._lines do
		self._lines[i].Visible = false
	end
	for i = mi + 1, #self._marks do
		self._marks[i].Visible = false
	end
end

--- Map click (UIInteract) while the logistics view is on: one of your provinces opens its build panel.
function LogisticsUI.on_map_click(self, tile: number, pos: Vector2?): boolean
	if not (self.visible and self.view) or tile < 0 then
		return false
	end
	-- an army under the click is the army panel's (select it, even in the logistics view)
	if pos ~= nil then
		local v = self.ctx:world_call("unit_at_screen", { self.ctx:to_view(pos), 24 * self.ctx:ui_scale() })
		local u = if type(v) == "number" then self.ctx.state.units[v] else nil
		if u ~= nil and u.kind == Defs.U_ARMY then
			return false
		end
	end
	local P = self:_P()
	if P == nil then
		return false
	end
	local pid = buffer.readu16(P.prov_of, tile * 2)
	if pid == 0 or self.ctx.state:tile_owner(tile) ~= self.ctx:me() then
		self.panel.Visible = false
		return false
	end
	self.pid = pid
	self.tile = tile
	self.panel.Visible = true
	self.ctx:sfx("click")
	self:_refresh_panel()
	return true
end

function LogisticsUI._refresh_panel(self)
	local s = self.ctx.state
	local P = self:_P()
	local pid = self.pid
	if s == nil or P == nil or P.list[pid] == nil then
		return
	end
	local p = P.list[pid]
	local me = self.ctx:me()
	local inf = infra_of(s, pid)
	local dep = Logistics.deposits(p, P.map_id or (s.map and s.map.id))
	local parts = {}
	for _, k in Logistics.RESOURCES do
		if dep[k] > 0.005 then
			table.insert(parts, string.format("%s %.1f/s", Logistics.RESOURCE_NAMES[k], dep[k]))
		end
	end
	local net = s.supplynet and s.supplynet[me]
	self.p_name.Text = p.name
	self.p_info.Text = "Deposits: " .. (if #parts > 0 then table.concat(parts, " · ") else "none")
		.. (if net and net[pid] then string.format("  ·  supply link %d/s", net[pid]) else "  ·  CUT OFF")
	if (inf.building or 0) > 0 then
		local left = math.max(0, (inf.finish - (s.tick or 0)) / Defs.TICK_RATE)
		local kind = "?"
		for k, d in Logistics.INFRA do
			if d.code == inf.building then
				kind = d.name
			end
		end
		self.p_job.Text = string.format("Building %s · %ds", kind, math.ceil(left))
	else
		self.p_job.Text = ""
	end
	local stock = s.resources and s.resources[me]
	local gold = (s.owners[me] and s.owners[me].gold) or 0
	for k, row in self.rows do
		if k == "port" then
			row.name.Text = "Port (existing port structure)"
			row.cost.Text = "Coastal tiles only · links your coast by sea"
			row.button.AutoButtonColor = true
			row.button.BackgroundTransparency = 0
			continue
		end
		local def = Logistics.INFRA[k]
		local level = inf[k] or 0
		local nxt = level + 1
		row.name.Text = string.format("%s  %d/%d", def.name, level, def.max)
		local why = nil
		if nxt > def.max then
			why = "Highest level"
		elseif (inf.building or 0) > 0 then
			why = "Building"
		elseif def.needs_road and inf.road < def.needs_road then
			why = "Needs a road"
		elseif def.needs_deposit and (dep[def.needs_deposit] or 0) <= 0 then
			why = "No " .. def.needs_deposit .. " here"
		end
		if nxt <= def.max then
			local g, res = Logistics.cost(k, nxt)
			local bits = { UITheme.fmt_cost(g) .. " gold" }
			local afford = gold >= g
			for r, v in res do
				table.insert(bits, string.format("%d %s", v, r))
				if stock == nil or (stock[r] or 0) < v then
					afford = false
				end
			end
			row.cost.Text = (if why then why .. " · " else "") .. table.concat(bits, " · ")
			if why == nil and not afford then
				why = "Can't afford"
			end
		else
			row.cost.Text = why or ""
		end
		row.button.AutoButtonColor = why == nil
		row.button.BackgroundTransparency = if why == nil then 0 else 0.6
	end
end

function LogisticsUI._build(self, kind: string)
	if self.pid == 0 then
		return
	end
	self.ctx:send({ type = "build_infra", kind = kind, tile = self.tile })
	self.ctx:sfx("build")
end

function LogisticsUI.destroy(self)
	self._conn:Disconnect()
	self.root:Destroy()
end

return LogisticsUI
