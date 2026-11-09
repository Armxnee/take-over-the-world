--!nonstrict
-- (Take Over the World!: the country picker, 2026-11-06.)
-- Spawn phase of a countries match (Sim.countries): instead of "place your capital", the player picks
-- a country. A list of every country (Countryball, flag, name, difficulty, taken / yours) on the left,
-- the chosen country's card on the right (capital, population, economy, military, provinces, national
-- bonus, difficulty) with CONFIRM. Choosing a country (in the list or by clicking it on the map:
-- UIInteract routes spawn clicks here) highlights its territory on the existing map and brings the
-- camera to it. CONFIRM sends the existing spawn intent at the country's capital; the server's Sim
-- validates it (Sim.pick_country) and the Session re-points the player when it is accepted.
--
-- The definitions come from Data/Countries, built here from the GameState mirror: the provinces are
-- generated from the map and the nations' capitals exactly as on the server (Core/Provinces is
-- deterministic), in a Coop job over a few frames.
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
local Airfront = RS:WaitForChild("Airfront")
local Defs = require(Airfront.Core.Defs)
local Coop = require(Airfront.Net.Coop)
local Provinces = require(Airfront.Core.Provinces)
local Countries = require(Airfront.Data.Countries)
local CountryGrid = require(Airfront.Data.CountryGrid)
local Rules = require(Airfront.Core.Rules)
local Countryball = require("./Countryball")
local Empires = require(Airfront.Data.Empires) -- (Take Over the World!: the empire a country can found)
local UITheme = require("./UITheme")

local CountryPicker = {}
CountryPicker.__index = CountryPicker

local FONT = "rbxassetid://12187365977"
local NAVY = Color3.fromHex("0D1326")
local AMBER = Color3.fromHex("FFB547")
local TEXT = Color3.new(1, 1, 1)
local TEXT2 = Color3.fromHex("A9B4D0")
local GREEN = Color3.fromHex("5BE38E")
local RED = Color3.fromHex("FF5C61")
local DIFF_COLORS = { GREEN, Color3.fromHex("49C6F2"), AMBER, Color3.fromHex("FF9147"), RED }

local function font(weight: Enum.FontWeight): Font
	return Font.new(FONT, weight)
end

local function fmt(n: number): string
	n = math.floor(n + 0.5)
	if n >= 1e9 then
		return string.format("%.1fB", n / 1e9)
	elseif n >= 1e6 then
		return string.format("%.1fM", n / 1e6)
	elseif n >= 1e4 then
		return string.format("%.0fK", n / 1e3)
	elseif n >= 1e3 then
		return string.format("%.1fK", n / 1e3)
	end
	return tostring(n)
end

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

local function glass(parent: Instance, name: string): Frame
	local f = make("Frame", {
		Name = name,
		BackgroundColor3 = NAVY,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 12) }, f)
	make("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.88, Thickness = 1 }, f)
	return f
end

local function label(parent: Instance, text: string, size: number, weight: Enum.FontWeight, color: Color3, props: { [string]: any }?): TextLabel
	local l = make("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextSize = size,
		FontFace = font(weight),
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

function CountryPicker.new(ctx: any, gui: Instance)
	local self = setmetatable({}, CountryPicker)
	self.ctx = ctx
	self.visible = false
	self.defs = nil :: { [number]: any }?
	self.list = {} :: { any }
	self.selected = 0
	self._state = nil
	self._job = nil
	self._rows = {} :: { [number]: any }
	self._acc = 0

	local root = make("Frame", {
		Name = "CountryPicker",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 20,
	}, gui)
	self.root = root

	-- list panel
	local lp = glass(root, "List")
	lp.Position = UDim2.fromOffset(16, 76)
	self.list_panel = lp
	make("UIPadding", {
		PaddingTop = UDim.new(0, 12),
		PaddingBottom = UDim.new(0, 12),
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 8),
	}, lp)
	self.title = label(lp, "CHOOSE YOUR COUNTRY", 15, Enum.FontWeight.Heavy, AMBER, { Position = UDim2.fromOffset(0, 0) })
	self.sub = label(lp, "", 12, Enum.FontWeight.Medium, TEXT2, { Position = UDim2.fromOffset(0, 20) })
	local search = make("TextBox", {
		Name = "Search",
		PlaceholderText = "Search countries",
		Text = "",
		ClearTextOnFocus = false,
		TextSize = 13,
		FontFace = font(Enum.FontWeight.Medium),
		TextColor3 = TEXT,
		PlaceholderColor3 = TEXT2,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.94,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 42),
		Size = UDim2.new(1, -4, 0, 30),
	}, lp)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, search)
	make("UIPadding", { PaddingLeft = UDim.new(0, 10) }, search)
	search:GetPropertyChangedSignal("Text"):Connect(function()
		self:_filter(search.Text)
	end)
	self.search = search
	local scroll = make("ScrollingFrame", {
		Name = "Rows",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 80),
		Size = UDim2.new(1, 0, 1, -80),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = TEXT2,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, lp)
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
	self.scroll = scroll
	self.loading = label(scroll, "Mapping provinces…", 13, Enum.FontWeight.Medium, TEXT2)

	-- detail card
	local card = glass(root, "Card")
	card.AnchorPoint = Vector2.new(1, 1)
	self.card = card
	make("UIPadding", {
		PaddingTop = UDim.new(0, 14),
		PaddingBottom = UDim.new(0, 14),
		PaddingLeft = UDim.new(0, 16),
		PaddingRight = UDim.new(0, 16),
	}, card)
	self.ball_holder = make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(84, 84) }, card)
	self.flag = make("ImageLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(96, 4),
		Size = UDim2.fromOffset(36, 24),
		ScaleType = Enum.ScaleType.Stretch,
		ResampleMode = Enum.ResamplerMode.Pixelated,
	}, card)
	make("UICorner", { CornerRadius = UDim.new(0, 3) }, self.flag)
	self.name = label(card, "", 24, Enum.FontWeight.Heavy, TEXT, { Position = UDim2.fromOffset(96, 30), Size = UDim2.new(1, -96, 0, 28) })
	self.capital = label(card, "", 13, Enum.FontWeight.Medium, TEXT2, { Position = UDim2.fromOffset(96, 60), Size = UDim2.new(1, -96, 0, 16) })
	self.diff = make("TextLabel", {
		BackgroundColor3 = GREEN,
		BackgroundTransparency = 0.8,
		TextSize = 11,
		FontFace = font(Enum.FontWeight.Heavy),
		TextColor3 = GREEN,
		Position = UDim2.fromOffset(140, 6),
		Size = UDim2.fromOffset(84, 20),
		BorderSizePixel = 0,
	}, card)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, self.diff)
	local grid = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 94), Size = UDim2.new(1, 0, 0, 96) }, card)
	make("UIGridLayout", { CellSize = UDim2.new(0.5, -6, 0, 44), CellPadding = UDim2.fromOffset(12, 6), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	self.stats = {}
	for i, key in { "Population", "Economy", "Military", "Provinces" } do
		local cell = make("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.95, BorderSizePixel = 0, LayoutOrder = i }, grid)
		make("UICorner", { CornerRadius = UDim.new(0, 8) }, cell)
		make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingTop = UDim.new(0, 5) }, cell)
		label(cell, string.upper(key), 10, Enum.FontWeight.Bold, TEXT2)
		self.stats[key] = label(cell, "", 17, Enum.FontWeight.Heavy, TEXT, { Position = UDim2.fromOffset(0, 15) })
	end
	self.bonus = label(card, "", 13, Enum.FontWeight.Bold, AMBER, { Position = UDim2.fromOffset(0, 196), Size = UDim2.new(1, 0, 0, 16) })
	self.bonus_text = label(card, "", 12, Enum.FontWeight.Medium, TEXT2, {
		Position = UDim2.fromOffset(0, 214),
		Size = UDim2.new(1, 0, 0, 30),
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	-- (Take Over the World!: the empire this country can found, and the land it takes)
	local emp = make("Frame", {
		Name = "Empire",
		BackgroundColor3 = Color3.fromHex("FFB547"),
		BackgroundTransparency = 0.88,
		Position = UDim2.fromOffset(0, 250),
		Size = UDim2.new(1, 0, 0, 48),
	}, card)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, emp)
	make("UIStroke", { Color = Color3.fromHex("FFB547"), Transparency = 0.6 }, emp)
	self.empire_row = emp
	self.empire_ball = make("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.fromOffset(36, 36),
	}, emp)
	self.empire_name = label(emp, "", 13, Enum.FontWeight.Heavy, AMBER, {
		Position = UDim2.fromOffset(48, 6),
		Size = UDim2.new(1, -54, 0, 16),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	self.empire_need = label(emp, "", 11, Enum.FontWeight.Medium, TEXT2, {
		Position = UDim2.fromOffset(48, 24),
		Size = UDim2.new(1, -54, 0, 18),
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
	})
	local btn = make("TextButton", {
		Name = "Confirm",
		Text = "CONFIRM",
		TextSize = 17,
		FontFace = font(Enum.FontWeight.Heavy),
		TextColor3 = Color3.fromHex("3A2400"),
		BackgroundColor3 = AMBER,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 46),
	}, card)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, btn)
	btn.Activated:Connect(function()
		self:_confirm()
	end)
	self.confirm = btn
	self.card.Visible = false

	self._conn = RunService.Heartbeat:Connect(function(dt)
		if self.visible then
			self:_process(dt)
		end
	end)
	self:apply_layout()
	return self
end

function CountryPicker.apply_layout(self)
	local compact = self.ctx.compact == true
	local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	local lw = if compact then 230 else 300
	self.list_panel.Size = UDim2.new(0, lw, 0, math.max(200, vp.Y - 76 - 16))
	local cw = if compact then 300 else 360
	self.card.Size = UDim2.fromOffset(cw, 372)
	self.card.Position = UDim2.new(1, -16, 1, -16)
end

--- Shown on the spawn screen of a countries match.
function CountryPicker.set_visible(self, on: boolean)
	self.visible = on
	if on and self.ctx.state ~= self._state then
		self:_reset()
	end
	self.root.Visible = on and (self.defs ~= nil or self._job ~= nil)
	if not on then
		self.ctx:world_call("set_selected_owner", { 0 })
	end
end

--- True when this match is a countries match (the picker should take over the spawn phase).
function CountryPicker.active(self): boolean
	return self.visible and (self.defs ~= nil and next(self.defs) ~= nil or self._job ~= nil)
end

function CountryPicker._reset(self)
	local s = self.ctx.state
	self._state = s
	self.defs = nil
	self.list = {}
	self.selected = 0
	for _, r in self._rows do
		r.frame:Destroy()
	end
	self._rows = {}
	self.loading.Visible = true
	self.card.Visible = false
	self._job = nil
	if s == nil or s.map == nil then
		return
	end
	-- countries mode: every nation started with land and there are no tribes
	local caps, names = {}, {}
	local nations = 0
	for id, o in s.owners do
		if o.kind == Defs.KIND_TRIBE then
			return -- a RoWorld-rules match: no picker
		end
		if o.spawn_tile ~= nil and o.spawn_tile >= 0 then
			caps[id] = o.spawn_tile
			names[id] = o.name
			nations += 1
		end
	end
	if nations == 0 then
		return
	end
	local map = s.map
	local R = s.rules
	self._job = Coop.job(function()
		-- the same real borders as the server (Data/CountryGrid), by name
		local G = CountryGrid.get(map.id)
		local fn = nil
		if G ~= nil then
			local by_name, owner_of = {}, {}
			for id, nm in names do
				by_name[nm] = id
			end
			for i, nd in G.nations do
				owner_of[i] = by_name[nd[1]]
			end
			fn = function(t: number): number
				return owner_of[CountryGrid.at(G, map, t)] or 0
			end
		end
		local P = Provinces.build(map, caps, fn)
		Provinces.name_all(P, function(id)
			return names[id] or "Nation"
		end)
		for _, p in P.list do
			p.resources = Provinces.resources_of(p)
		end
		local by_name = Countries.flags_by_name(map)
		local flags = {}
		for id, nm in names do
			flags[id] = by_name[nm]
		end
		local defs, list = Countries.build(P, {
			map_id = map.id,
			names = names,
			flags = flags,
			max_troops = function(tiles)
				return R.max_troops(Defs.KIND_NATION, tiles, 0, 1)
			end,
			income = function(tiles)
				return Rules.passive_income(Defs.KIND_NATION, tiles)
			end,
			start_gold = 0,
		})
		return { defs = defs, list = list }
	end)
end

function CountryPicker._process(self, dt: number)
	if self.ctx.state ~= self._state then
		self:_reset()
	end
	local job = self._job
	if job ~= nil and not job.done then
		self.root.Visible = true
		job:step(0.006)
		if job.done then
			self._job = nil
			if job.ok then
				self.defs = job.result.defs
				self.list = job.result.list
				self:_build_rows()
			else
				warn("[CountryPicker] " .. tostring(job.err))
			end
		end
		return
	end
	self._acc += dt
	if self._acc >= 0.4 and self.defs ~= nil then
		self._acc = 0
		self:_refresh_rows()
		self:_refresh_card()
	end
end

function CountryPicker._status(self, owner: number): string
	local s = self.ctx.state
	local o = s and s.owners[owner]
	if o == nil or not o.alive then
		return "gone"
	end
	if owner == self.ctx:me() then
		return "mine"
	end
	if o.kind == Defs.KIND_HUMAN then
		return "taken"
	end
	return "free"
end

function CountryPicker._build_rows(self)
	self.loading.Visible = false
	for i, d in self.list do
		local row = make("TextButton", {
			Name = d.name,
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			LayoutOrder = i,
			Size = UDim2.new(1, -6, 0, 40),
		}, self.scroll)
		make("UICorner", { CornerRadius = UDim.new(0, 8) }, row)
		local ball = Countryball.new(d.flag, 34, d.name)
		ball.Position = UDim2.fromOffset(2, 3)
		ball.Parent = row
		local nm = label(row, d.name, 14, Enum.FontWeight.Bold, TEXT, { Position = UDim2.fromOffset(42, 3), Size = UDim2.new(1, -110, 0, 18) })
		local sub = label(row, string.format("%s · %d provinces", d.difficulty_name, #d.provinces), 11, Enum.FontWeight.Medium, DIFF_COLORS[d.difficulty] or TEXT2, {
			Position = UDim2.fromOffset(42, 21),
			Size = UDim2.new(1, -110, 0, 14),
		})
		local tag = label(row, "", 11, Enum.FontWeight.Heavy, TEXT2, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -6, 0, 12),
			Size = UDim2.fromOffset(60, 14),
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		row.MouseEnter:Connect(function()
			if self.selected ~= d.owner then
				row.BackgroundTransparency = 0.94
			end
		end)
		row.MouseLeave:Connect(function()
			if self.selected ~= d.owner then
				row.BackgroundTransparency = 1
			end
		end)
		row.Activated:Connect(function()
			self:select_owner(d.owner, true)
		end)
		self._rows[d.owner] = { frame = row, name = nm, sub = sub, tag = tag, def = d }
	end
	self:_refresh_rows()
	-- start on the player's own country, else the first free one
	local me = self.ctx:me()
	if self.defs[me] ~= nil then
		self:select_owner(me, true)
	else
		for _, d in self.list do
			if self:_status(d.owner) == "free" then
				self:select_owner(d.owner, false)
				break
			end
		end
	end
end

function CountryPicker._filter(self, text: string)
	local q = string.lower(text)
	for _, r in self._rows do
		r.frame.Visible = q == "" or string.find(string.lower(r.def.name), q, 1, true) ~= nil
	end
end

function CountryPicker._refresh_rows(self)
	local free = 0
	for owner, r in self._rows do
		local st = self:_status(owner)
		if st == "free" then
			free += 1
		end
		r.tag.Text = if st == "mine" then "YOU" elseif st == "taken" then "TAKEN" elseif st == "gone" then "FALLEN" else ""
		r.tag.TextColor3 = if st == "mine" then AMBER elseif st == "taken" then RED else TEXT2
		r.name.TextColor3 = if st == "taken" or st == "gone" then TEXT2 else TEXT
		r.frame.BackgroundTransparency = if owner == self.selected then 0.88 else 1
	end
	self.sub.Text = string.format("%d countries · %d free", #self.list, free)
end

--- Selects country `owner` (list click, or a click on its land on the map: UIInteract).
function CountryPicker.select_owner(self, owner: number, focus: boolean?)
	if self.defs == nil or self.defs[owner] == nil then
		return
	end
	self.selected = owner
	self.ctx:world_call("set_selected_owner", { owner })
	if focus then
		self.ctx:world_call("focus_owner", { owner })
	end
	self.ctx:sfx("click", -9.0) -- (quieter: a click on a country, 2026-11-08)
	self.card.Visible = true
	local d = self.defs[owner]
	local ball = self.ball_holder:FindFirstChild("Countryball")
	if ball then
		ball:Destroy()
	end
	-- (Take Over the World!: with the player's hat from the item shop)
	local se = self.ctx.session
	local eq = se and se.inventory and se.inventory.equipped
	Countryball.new(d.flag, 84, d.name, eq).Parent = self.ball_holder
	local f = Countryball.flag_content(d.flag, d.name, false)
	self.flag.Visible = f ~= nil
	if f ~= nil then
		self.flag.ImageContent = f
	end
	self.name.Text = d.name
	self.capital.Text = "Capital: " .. d.capital_name
	self.diff.Text = string.upper(d.difficulty_name)
	local dc = DIFF_COLORS[d.difficulty] or TEXT2
	self.diff.TextColor3 = dc
	self.diff.BackgroundColor3 = dc
	self.stats.Population.Text = fmt(d.population)
	self:_live_stats()
	self.stats.Provinces.Text = tostring(#d.provinces)
	self.bonus.Text = "★ " .. d.bonuses.label
	self.bonus_text.Text = d.bonuses.text
	-- (Take Over the World!: the empire it can found: its Countryball, its name, the land it takes)
	local e = Empires.of(d.name)
	self.empire_ball:ClearAllChildren()
	local eb = Countryball.new(e.flag or d.flag, 36, e.name)
	eb.Parent = self.empire_ball
	self.empire_name.Text = "EMPIRE: " .. string.upper(e.name)
	local land = self.ctx.state and self.ctx.state.map and self.ctx.state.map.land_count or 0
	-- (no empires on some maps: Empires.allowed)
	self.empire_row.Visible = Empires.allowed(self.ctx.state and self.ctx.state.map and self.ctx.state.map.id)
	if land > 0 then
		local share = Empires.need(land, d.tiles) / land * 100
		local more = math.max(0, Empires.need(land, d.tiles) - d.tiles) / land * 100
		self.empire_need.Text = string.format("Hold %.1f%% of the map · conquer %.1f%% more", share, more)
	else
		self.empire_need.Text = "Conquer land to found it"
	end
	self:_refresh_rows()
	self:_refresh_card()
end

--- Military and economy as the match has them now (the mirror's numbers, formatted like the HUD).
function CountryPicker._live_stats(self)
	local d = self.defs and self.defs[self.selected]
	local o = self.ctx.state and self.ctx.state.owners[self.selected]
	if d == nil then
		return
	end
	if o ~= nil and (o.troops or 0) > 0 then
		self.stats.Military.Text = UITheme.fmt_troops(o.troops) .. " troops"
		local inc = if (o.income or 0) > 0 then o.income else d.resources.income -- (AI income starts with the match)
		self.stats.Economy.Text = "+" .. UITheme.fmt_cost(inc) .. "/s"
	else
		self.stats.Military.Text = fmt(d.military.troops) .. " troops"
		self.stats.Economy.Text = string.format("+%s/s", fmt(d.resources.income))
	end
end

function CountryPicker._refresh_card(self)
	local owner = self.selected
	if owner == 0 then
		return
	end
	self:_live_stats()
	local st = self:_status(owner)
	local btn = self.confirm
	if st == "mine" then
		btn.Text = "YOU LEAD " .. string.upper(self.defs[owner].name)
		btn.BackgroundColor3 = GREEN
		btn.Active = false
	elseif st == "taken" then
		btn.Text = "TAKEN BY ANOTHER PLAYER"
		btn.BackgroundColor3 = Color3.fromHex("4A5168")
		btn.Active = false
	elseif st == "gone" then
		btn.Text = "THIS COUNTRY HAS FALLEN"
		btn.BackgroundColor3 = Color3.fromHex("4A5168")
		btn.Active = false
	else
		btn.Text = "CONFIRM"
		btn.BackgroundColor3 = AMBER
		btn.Active = true
	end
end

function CountryPicker._confirm(self)
	local owner = self.selected
	if owner == 0 or self:_status(owner) ~= "free" then
		self.ctx:sfx("deny", -4.0)
		return
	end
	local d = self.defs[owner]
	-- the existing spawn intent, at the country's capital: the server's Sim decides (pick_country)
	self.ctx:send({ type = "spawn", tile = d.capital_tile })
	self.ctx:sfx("spawn", -5.0)
	self.confirm.Text = "JOINING " .. string.upper(d.name) .. "…"
end

function CountryPicker.destroy(self)
	if self._conn then
		self._conn:Disconnect()
	end
	self.root:Destroy()
end

return CountryPicker
