--!nonstrict
-- Stand-in for RoWorld's client Session (AGPL; see NOTICE.md), backed by this game's server:
-- RoWorld's interface (UIRoot) reads `mode`, `state` and the signals below and calls the methods;
-- every order (intent) becomes one of our Cmd remote calls. Our server always runs a match, so the
-- title screen is a view over it: PLAY SOLO / a public match card ask the server's Menu remote
-- (a reserved solo server or matchmaking; in Studio the match restarts here), and "here" enters it.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Config = require(ReplicatedStorage.Shared.Config)
local State = require(script.Parent.Parent.State)
local Feed = require(script.Parent.Feed)
local AF = ReplicatedStorage:WaitForChild("Airfront")
local Signal = require(AF.Core.Signal)
local Defs = require(AF.Core.Defs)

local Session = {}
Session.__index = Session

Session.MODE_TITLE, Session.MODE_SOLO, Session.MODE_MULTI = 0, 1, 2

local SIGNALS = {
	"state_ready", "mode_changed", "lobby_updated", "lobbies_updated", "join_failed", "public_changed",
	"admin_changed", "joined_owner", "notice", "building_started", "settings_loaded", "credits_changed",
	"credit_result", "took_over", "inventory_changed", "stars_awarded", "unlock_result", "hop_result",
	"unlocked", "crate_result", "general_changed", "party_changed",
}

function Session.new(call: (string, any) -> (boolean, any), menu: (string, any) -> (boolean, any))
	local self = setmetatable({}, Session)
	for _, n in SIGNALS do
		self[n] = Signal.new()
	end
	self._call, self._menu = call, menu
	self.mode = Session.MODE_TITLE
	self.state_mode = Session.MODE_TITLE
	self.state = nil
	self.state_is_resync = false
	self.settings_ready = false
	self.difficulty = 0
	self.map_id = Config.MapOrder[1]
	self.admin_bots = false
	self.env = {}
	self.perf = {}
	self.lobby = {}
	self.lobbies = {}
	self.lobby_kinds = { "ffa" }
	self.public = { state = "idle" }
	self.party = nil
	-- no time limit in this game (Config.Match.TimeCap): the clock simply counts up
	self.MP_TIME_LIMIT_S = 0
	-- RoWorld's shop / Arsenal / starter pack read this: everything unlocked, no paid items here
	self.inventory = { unlocks = Defs.UNLOCK_ALL, crates_allowed = false, stars = 0, crates = 0, skins = {}, flags = {}, owned = {}, equipped = {} }
	self._settings = {}
	self._building = false
	-- the saved settings (server profile); RoWorld's UI waits for settings_loaded
	task.spawn(function()
		for _ = 1, 30 do
			local ok, v = self._menu("settings_get", {})
			if ok and typeof(v) == "table" then
				self._settings = v
				local m = type(v.ui) == "table" and v.ui.map_id
				if type(m) == "string" and Config.Maps[m] then
					self.map_id = m
				end
				break
			end
			task.wait(1)
		end
		self.settings_ready = true
		self.settings_loaded:Fire()
	end)
	return self
end

function Session.bind(_self) end
function Session.start_title(_self) end
function Session.process(_self, _dt) end
function Session.note_activity(_self) end
function Session.is_building(self): boolean
	return self._building
end
function Session.set_paused(self, on: boolean)
	on = on == true
	if self._paused == on then
		return
	end
	self._paused = on
	task.spawn(self._menu, "pause", { on = on })
end
function Session.has_unlock(_self, _key): boolean
	return true
end
function Session.buy_unlock(_self, _key): boolean
	return false
end
function Session.starter_seen(_self): boolean
	return true
end
function Session.new_player(_self): boolean
	return false
end
function Session.hop_solo(_self): boolean
	return false
end
function Session.open_crate(_self): boolean
	return false
end
function Session.equip(_self): boolean
	return false
end
function Session.use_credit(_self): boolean
	return false
end
function Session.can_take_over(_self): boolean
	return false
end
function Session.take_over(_self): boolean
	return false
end
function Session.in_party(_self): (boolean, boolean)
	return false, false
end
function Session.party_action(_self) end
function Session.report(_self): boolean
	return false
end
function Session.vote_start(_self) end
function Session.local_sim(_self)
	return nil
end
function Session.multiplayer_available(_self): boolean
	return true
end
function Session.multiplayer_status(_self): string
	return "online"
end
function Session.local_display_name(_self): string
	return Players.LocalPlayer.DisplayName
end

function Session.load_settings(self, section: string): { [string]: any }
	return table.clone(self._settings[section] or {})
end
function Session.save_settings(self, section: string, values: { [string]: any })
	self._settings[section] = table.clone(values)
	-- one write per section per 2 s at most
	self._dirty = self._dirty or {}
	if self._dirty[section] then
		return
	end
	self._dirty[section] = true
	task.delay(2, function()
		self._dirty[section] = nil
		self._menu("settings_set", { section = section, values = self._settings[section] })
	end)
end

function Session._set_mode(self, m: number)
	if self.mode ~= m then
		self.mode = m
		self.mode_changed:Fire(m)
	end
end

-- a snapshot arrived (Feed.build made a new GameState)
function Session.on_state(self, s: any)
	self.state = s
	self.state_mode = self.mode
	self.state_ready:Fire(s)
	if State.me ~= 0 then
		self.joined_owner:Fire(State.me)
	end
end

-- enter the match this server is running
function Session._enter(self, m: number)
	self._building = false
	self:_set_mode(m)
	self.state_mode = m
	if self.state then
		self.state_ready:Fire(self.state)
	end
	if self.on_enter then
		self.on_enter(m)
	end
end

function Session._answer(self, ok: boolean, msg: any, m: number)
	if ok and msg == "here" then
		self:_enter(m)
		return true
	end
	if ok then
		-- Studio restarts this server's match ("Starting X here"); live servers teleport
		self.notice:Fire(tostring(msg), 0)
		self:_enter(m)
		return true
	end
	self._building = false
	self.notice:Fire(tostring(msg), 2)
	self.join_failed:Fire(tostring(msg))
	return false
end

function Session.start_solo(self, difficulty: number, map_id: string?)
	self.difficulty = difficulty or 0
	if map_id and Config.Maps[map_id] then
		self.map_id = map_id
	end
	self._building = true
	self.building_started:Fire(Session.MODE_SOLO)
	task.spawn(function()
		local ok, msg = self._menu("solo", { map = self.map_id, diff = self.difficulty })
		self:_answer(ok, msg, Session.MODE_SOLO)
	end)
end

function Session.join_public(self, mode: string)
	self.public = { state = "joining", mode = mode }
	self.public_changed:Fire(self.public)
	task.spawn(function()
		local ok, msg = self._menu("match", { map = self.map_id })
		self.public = { state = "idle" }
		self.public_changed:Fire(self.public)
		self:_answer(ok, msg, Session.MODE_MULTI)
	end)
end
Session.join_multiplayer = function(self)
	self:join_public("ffa")
end
function Session.join_lobby(self, id: string)
	task.spawn(function()
		local ok, msg = self._menu("join", { key = id })
		self:_answer(ok, msg, Session.MODE_MULTI)
	end)
end
Session.spectate_lobby = Session.join_lobby
function Session.leave_line(self)
	self.public = { state = "idle" }
	self.public_changed:Fire(self.public)
end

function Session.leave_match(self)
	self:_set_mode(Session.MODE_TITLE)
	self.state_mode = Session.MODE_TITLE
	if self.state then
		self.state_ready:Fire(self.state)
	end
	if self.on_leave then
		self.on_leave()
	end
end

-- the server list (Menu "info") as RoWorld lobbies: one public card, live matches you can join
function Session.refresh_lobbies(self)
	local ok, info = self._menu("info", {})
	if not ok or typeof(info) ~= "table" then
		return
	end
	local list = {}
	local rows = { info.here }
	for _, s in info.servers or {} do
		table.insert(rows, s)
	end
	for _, s in rows do
		if s and not s.solo then
			local def = Config.Maps[s.map] or Config.Maps.earth
			table.insert(list, {
				id = s.key,
				map = s.map,
				map_name = def.Name,
				max = s.max,
				players = s.players,
				-- our matches are joinable while they run (RoWorld's lobbies count down to a start)
				starts_in = 3600,
				joinable = s.players < s.max,
				mode = "ffa",
				status = ("%s  ·  %d / %d playing%s"):format(def.Name, s.players, s.max, if s.here then "  ·  this server" else ""),
			})
		end
	end
	self.lobbies = list
	self.lobbies_updated:Fire(list)
end

-- RoWorld intents -> our Cmd calls (the server validates each one)
local function guid(): string
	return HttpService:GenerateGUID(false)
end

function Session.send_intent(self, it: { [string]: any })
	local call = self._call
	local t = it.type
	local function say(ok: boolean, msg: any)
		if not ok and msg and msg ~= "dup" then
			self.notice:Fire(tostring(msg), 2)
		end
	end
	task.spawn(function()
		if t == "spawn" then
			say(call("spawn", { cell = it.tile }))
		elseif t == "attack" then
			say(call("attack", { cell = it.tile or Feed.anchorOf(it.target), ratio = it.ratio, id = guid() }))
		elseif t == "boat" then
			say(call("boat", { cell = it.tile, ratio = it.ratio, id = guid() }))
		elseif t == "build" then
			local kind = if type(it.kind) == "number" then Feed.KIND_OF[it.kind] else (Session.BUILD_OF[it.kind] or it.kind)
			local up = require(script.Parent.OurRules).upgradable(it.kind, it.tile)
			if up then
				say(call("upgrade", { structure = up.id, id = guid() }))
			elseif kind == "warship" then
				say(call("launch", { kind = "warship", cell = it.tile, id = guid() }))
			else
				say(call("build", { kind = kind, cell = it.tile, id = guid() }))
			end
		elseif t == "nuke" then
			local k = Session.LAUNCH_OF[it.kind] or "missile"
			say(call("launch", { kind = k, cell = it.tile, id = guid() }))
		elseif t == "retreat" then
			say(call("retreat", { attack = it.id or it.aid, id = guid() }))
		elseif t == "ally_request" or t == "ally_extend" then
			say(call("ally", { action = "request", target = it.target, id = guid() }))
		elseif t == "ally_reply" then
			say(call("ally", { action = if it.accept then "accept" else "decline", target = it.target or it.from, id = guid() }))
		elseif t == "ally_break" then
			say(call("ally", { action = "break", target = it.target, id = guid() }))
		elseif t == "donate" then
			local me = State.nations[State.me]
			local ratio = if me and it.troops and me.troops > 0 then (it.troops / 10) / me.troops else 0.25
			say(call("aid", { target = it.target, kind = if it.gold then "gold" else "troops", ratio = ratio, id = guid() }))
		elseif t == "move_warship" then
			say(call("moveship", { unit = it.uid, cell = it.tile }))
		elseif t == "vote" then
			say(call("vote", { map = it.map }))
		end
	end)
end

-- RoWorld slot names -> our kinds
Session.BUILD_OF = { city = "city", port = "port", factory = "factory", defense = "defense", sam = "sam", silo = "silo", artillery = "aa", aa = "aa", airfield = "airfield", warship = "warship" }
Session.LAUNCH_OF = { atom = "missile", hydrogen = "nuke", mirv = "nuke", airstrike = "bomber", fighter = "fighter", [0] = "missile", [1] = "nuke", [2] = "nuke", [7] = "bomber" }

return Session
