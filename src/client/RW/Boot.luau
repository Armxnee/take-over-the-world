--!nonstrict
-- Boots RoWorld's interface (UIRoot + AudioDirector; AGPL, see NOTICE.md) over this game: our Session
-- and World stand-ins, the GameState Feed, and the hooks Main calls from its network handlers.
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local Feed = require(script.Parent.Feed)
local Session = require(script.Parent.Session)
local World = require(script.Parent.World)

local Boot = {}
Boot.ui = nil :: any
Boot.session = nil :: any
Boot.world = nil :: any
Boot.audio = nil :: any
Boot.ready = false

function Boot.start(call: (string, any) -> (boolean, any), menu: (string, any) -> (boolean, any))
	task.spawn(function()
		for _ = 1, 50 do
			local ok = pcall(function()
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.EmotesMenu, false)
			end)
			if ok then
				return
			end
			task.wait(0.2)
		end
	end)
	local session = Session.new(call, menu)
	Boot.session = session
	local world = World.new()
	Boot.world = world
	-- RoWorld's own sounds are private to its experience: its AudioDirector's calls play ours
	Boot.audio = require(script.Parent.AudioShim).new()
	-- this game's prices and placement rules in RoWorld's command bar
	require(script.Parent.UI.UIRules).hooks = require(script.Parent.OurRules)
	pcall(function()
		local Defs = require(game:GetService("ReplicatedStorage").Airfront.Core.Defs)
		Defs.STRUCT_TITLES[Defs.S_ARTILLERY] = "AA Battery"
	end)
	local UIRoot = require(script.Parent.UI.UIRoot)
	local ui = UIRoot.new()
	Boot.ui = ui
	ui:setup(session, world, Boot.audio)
	-- the map picked on the title is the map PLAY SOLO and the public card ask for
	if ui.map_picker and ui.map_picker.picked then
		ui.map_picker.picked:Connect(function(id: string)
			session.map_id = id
		end)
	end
	Boot.ready = true
	-- RoWorld's top bar: music, help & credits, leaderboard, home, settings, game menu
	local okT, errT = pcall(function()
		require(script.Parent.TopBar).start(Boot, Players.LocalPlayer)
	end)
	if not okT then
		warn("[TOTW] top bar failed: " .. tostring(errT))
	end
	if Feed.state then
		session:on_state(Feed.state)
	end
	-- the title's public card: the server list, refreshed while the title shows
	task.spawn(function()
		while true do
			if session.mode == Session.MODE_TITLE then
				pcall(session.refresh_lobbies, session)
			end
			task.wait(8)
		end
	end)
	return ui
end

-- Main's network hooks ------------------------------------------------------
function Boot.snapshot()
	local s = Feed.build()
	if Boot.ready then
		Boot.session:on_state(s)
	end
end

function Boot.me(id: number)
	local s = Feed.state
	if s then
		s.local_owner = id
		Feed.syncOwners(false)
		if Boot.ready and id ~= 0 then
			Boot.session.joined_owner:Fire(id)
		end
	end
end

function Boot.notice(text: string, kind: string?)
	if Boot.ready then
		Boot.session.notice:Fire(text, if kind == "bad" then 2 elseif kind == "good" then 1 else 0)
	end
end

Boot.Feed = Feed
Boot.player = Players.LocalPlayer
return Boot
