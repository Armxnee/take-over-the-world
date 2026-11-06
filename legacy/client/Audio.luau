--!strict
-- Music, ambience and sound effects. Licensed Creator Store audio (APM Music and
-- Pro Sound Effects, plus a few verified-creator UI sounds). Music crossfades between
-- the menu theme and the match playlist; SFX are throttled so spam never stacks.
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Audio = {}
Audio.musicOn = true
Audio.sfxOn = true

local SFX = {
	click = { id = 88442833509532, vol = 0.35, gap = 0.05 },
	attack = { id = 9042820510, vol = 0.35, gap = 1.6 },
	build = { id = 9114756724, vol = 0.4, gap = 0.4 },
	explosion = { id = 9126102254, vol = 0.8, gap = 0.3 },
	pop = { id = 9126102254, vol = 0.25, speed = 2.2, gap = 0.2 },
	plane = { id = 9125518572, vol = 0.35, gap = 0.5 },
	horn = { id = 9119561244, vol = 0.22, speed = 0.55, gap = 1.2 },
	siren = { id = 138099634, vol = 0.45, gap = 6 },
	coin = { id = 83107417896713, vol = 0.5, gap = 0.08 },
	shake = { id = 9125573400, vol = 0.45, gap = 0.05 },
	whoosh = { id = 9119466706, vol = 0.25, gap = 0.15 },
	alert = { id = 88442833509532, vol = 0.5, speed = 0.7, gap = 0.6 },
}
local MENU_MUSIC = 9042799548
local MATCH_MUSIC = { 9046506025, 1843722571, 1843229776 }
local OCEAN = 9112871350

local groups: { [string]: SoundGroup } = {}
local last: { [string]: number } = {}
local music: Sound
local ambience: Sound
local mode = ""
local trackIx = 0

local function group(name: string, vol: number): SoundGroup
	local g = Instance.new("SoundGroup")
	g.Name = "TOTW_" .. name
	g.Volume = vol
	g.Parent = SoundService
	groups[name] = g
	return g
end

function Audio.play(name: string)
	local s = SFX[name]
	if not s or not Audio.sfxOn then
		return
	end
	local t = os.clock()
	if t - (last[name] or -99) < (s.gap or 0) then
		return
	end
	last[name] = t
	local snd = Instance.new("Sound")
	snd.SoundId = "rbxassetid://" .. s.id
	snd.Volume = s.vol
	snd.PlaybackSpeed = s.speed or 1
	snd.SoundGroup = groups.SFX
	snd.Parent = SoundService
	snd:Play()
	snd.Ended:Once(function()
		snd:Destroy()
	end)
	task.delay(12, function()
		if snd.Parent then
			snd:Destroy()
		end
	end)
end

local function fadeTo(id: number, looped: boolean)
	local target = "rbxassetid://" .. id
	if music.SoundId == target and music.IsPlaying then
		return
	end
	local out = TweenService:Create(music, TweenInfo.new(0.8), { Volume = 0 })
	out:Play()
	out.Completed:Wait()
	music.SoundId = target
	music.Looped = looped
	music.TimePosition = 0
	music:Play()
	TweenService:Create(music, TweenInfo.new(1.2), { Volume = 0.35 }):Play()
end

-- "menu" | "match"
function Audio.setMode(m: string)
	if m == mode then
		return
	end
	mode = m
	task.spawn(function()
		if m == "menu" then
			fadeTo(MENU_MUSIC, true)
			TweenService:Create(ambience, TweenInfo.new(1), { Volume = 0 }):Play()
		else
			trackIx = trackIx % #MATCH_MUSIC + 1
			fadeTo(MATCH_MUSIC[trackIx], false)
			TweenService:Create(ambience, TweenInfo.new(2), { Volume = 0.12 }):Play()
		end
	end)
end

Audio.changed = {} :: { () -> () }
local function notify()
	for _, f in Audio.changed do
		task.spawn(f)
	end
end

function Audio.setMusic(on: boolean)
	Audio.musicOn = on
	groups.Music.Volume = if on then 1 else 0
	groups.Ambience.Volume = if on then 1 else 0
	notify()
end

function Audio.setSfx(on: boolean)
	Audio.sfxOn = on
	notify()
end

function Audio.init()
	group("Music", 1)
	group("SFX", 1)
	group("Ambience", 1)
	music = Instance.new("Sound")
	music.Name = "Music"
	music.Volume = 0
	music.SoundGroup = groups.Music
	music.Parent = SoundService
	-- match playlist advances when a track ends
	music.Ended:Connect(function()
		if mode == "match" then
			trackIx = trackIx % #MATCH_MUSIC + 1
			music.SoundId = "rbxassetid://" .. MATCH_MUSIC[trackIx]
			music:Play()
		end
	end)
	ambience = Instance.new("Sound")
	ambience.Name = "Ocean"
	ambience.SoundId = "rbxassetid://" .. OCEAN
	ambience.Looped = true
	ambience.Volume = 0
	ambience.SoundGroup = groups.Ambience
	ambience.Parent = SoundService
	ambience:Play()
end

return Audio
