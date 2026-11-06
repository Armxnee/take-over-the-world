--!nonstrict
-- Stand-in for RoWorld's AudioDirector (its uploaded sounds are private to RoWorld's experience): the
-- same methods, played with this game's own sounds (Audio.luau). RoWorld's effect names map onto ours;
-- the music follows the screen's mood (title / waiting -> menu theme, a match -> match playlist).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Audio = require(script.Parent.Parent.Audio)
local Signal = require(ReplicatedStorage:WaitForChild("Airfront").Core.Signal)

local AudioShim = {}
AudioShim.__index = AudioShim

-- RoWorld sfx file names -> our Audio.play names
local MAP = {
	ui_click = "click", ui_open = "click", ui_back = "click", ui_confirm = "click", ui_tab = "click",
	ui_error = "alert", ui_locked = "alert", buy_spend = "coin", star_get = "coin", unlock = "coin",
	attack_launch = "attack", boat_launch = "horn", build = "build", warship = "horn",
	nuke_launch = "whoosh", nuke_explosion = "explosion", sam_intercept = "pop", nuke_alarm = "siren",
	eliminate = "explosion", victory = "coin", defeat = "alert", game_start = "attack",
	spawn_confirm = "build", under_attack = "alert", ally_request = "click", alliance = "coin",
	betrayal = "alert", ship_sunk = "explosion", ship_kill = "pop", countdown_tick = "click",
	shell_fire = "pop", shell_hit = "pop",
}

function AudioShim.new()
	local self = setmetatable({}, AudioShim)
	self.music_enabled_changed = Signal.new()
	self.pops_enabled_changed = Signal.new()
	self._pops = true
	self._volume = 1
	table.insert(Audio.changed, function()
		self.music_enabled_changed:Fire(Audio.musicOn)
	end)
	return self
end

function AudioShim.bind_settings(_self, _session) end
function AudioShim.has_sfx(_self, name: string): boolean
	return MAP[name] ~= nil
end
function AudioShim.play_sfx(_self, name: string, _db: number?, _jitter: number?, _pitch: number?)
	local ours = MAP[name]
	if ours then
		Audio.play(ours)
	end
end
function AudioShim.is_music_enabled(_self): boolean
	return Audio.musicOn
end
function AudioShim.set_music_enabled(_self, on: boolean)
	Audio.setMusic(on)
end
function AudioShim.music_volume(self): number
	return self._volume
end
function AudioShim.set_music_volume(self, v: number)
	self._volume = v
end
function AudioShim.is_pops_enabled(self): boolean
	return self._pops
end
function AudioShim.set_pops_enabled(self, on: boolean)
	self._pops = on
	self.pops_enabled_changed:Fire(on)
end
function AudioShim.set_music_mood(_self, mood: string)
	Audio.setMode(if mood == "title" or mood == "wait" or mood == "" then "menu" else "match")
end
function AudioShim.play_theme(_self, theme: string)
	Audio.setMode(if theme == "menu" then "menu" else "match")
end
function AudioShim.duck_music(_self, ...) end

return AudioShim
