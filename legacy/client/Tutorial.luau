--!strict
-- Replayable first-match coach: neutral capture, troop commitment, a real attack,
-- city placement and a practice air interception. Runs inside a normal match, so
-- skipping it is the direct path to multiplayer.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local State = require(script.Parent.State)
local UI = require(script.Parent.UI)

local C, F = UI.C, UI.F
local make, label, button, panel = UI.make, UI.label, UI.button, UI.panel

local Tutorial = {}
Tutorial.active = false
Tutorial.call = nil :: ((string, any) -> (boolean, any))?
Tutorial.toast = nil :: ((string, string?) -> ())?

local box: Frame
local title: TextLabel
local body: TextLabel
local action: TextButton
local offer: Frame
local step = 1
local ctx: { [string]: any } = {}
local drillOk = false
Tutorial.drillRunning = false

local function me()
	return State.nations[State.me]
end

local function phase(): string
	local r = ReplicatedStorage:FindFirstChild("Remotes")
	return r and r:GetAttribute("Phase") or "Lobby"
end

type Step = { text: string, init: (() -> ())?, done: () -> boolean, action: string?, needsPlay: boolean? }

local STEPS: { Step } = {
	{
		text = "Click the map to pick where you start.",
		done = function()
			local m = me()
			return m ~= nil and m.land > 0
		end,
	},
	{
		text = "Click beige land to grow. Drag to move the map.",
		needsPlay = true,
		init = function()
			local m = me()
			ctx.land0 = if m then m.land else 0
		end,
		done = function()
			local m = me()
			return m ~= nil and m.land >= (ctx.land0 or 0) + 40
		end,
	},
	{
		text = "Press Q / E to pick how many troops to send.",
		needsPlay = true,
		init = function()
			ctx.r0 = State.ratio
		end,
		done = function()
			return math.abs(State.ratio - (ctx.r0 or 0)) > 0.001
		end,
	},
	{
		text = "Click a neighbour to attack. Right-click for ally / aid.",
		needsPlay = true,
		done = function()
			for _, a in State.mine do
				if a[2] ~= 0 then
					return true
				end
			end
			return false
		end,
	},
	{
		text = "Press 1, then click your land to build a City.",
		needsPlay = true,
		done = function()
			for _, s in State.structures do
				if s.owner == State.me and s.kind == "city" then
					return true
				end
			end
			return false
		end,
	},
	{
		text = "Press START, then click the red line to stop the drone.",
		needsPlay = true,
		action = "START",
		done = function()
			return drillOk
		end,
	},
	{
		text = "You're ready. Take over the world!",
		action = "FINISH",
		done = function()
			return false
		end,
	},
}

local function show()
	local s = STEPS[step]
	box.Visible = Tutorial.active
	if not s then
		return
	end
	title.Text = ("STEP %d / %d"):format(step, #STEPS)
	local waiting = s.needsPlay and phase() ~= "Playing"
	body.Text = if waiting then "Waiting for the round…" else s.text
	action.Visible = s.action ~= nil and not waiting
	action.Text = s.action or ""
end

local function enter(k: number)
	step = k
	if box then
		UI.slideIn(box, 30, 0)
	end
	local s = STEPS[step]
	if s and s.init then
		s.init()
	end
	show()
end

function Tutorial.start()
	Tutorial.active = true
	offer.Visible = false
	drillOk = false
	Tutorial.drillRunning = false
	ctx = {}
	enter(if phase() == "Spawn" or (me() == nil) then 1 else 2)
end

function Tutorial.stop()
	Tutorial.active = false
	Tutorial.drillRunning = false
	box.Visible = false
end

-- called every ~0.25 s
function Tutorial.update()
	if not Tutorial.active then
		return
	end
	local s = STEPS[step]
	if not s then
		return
	end
	if s.needsPlay and phase() ~= "Playing" then
		show()
		return
	end
	if ctx.pendingInit then
		ctx.pendingInit = nil
		if s.init then
			s.init()
		end
	end
	if s.done() then
		enter(step + 1)
	else
		show()
	end
end

-- the drill wants map clicks while the drone is in the air
function Tutorial.wantsClick(): boolean
	return Tutorial.active and Tutorial.drillRunning
end

function Tutorial.click(cell: number)
	if Tutorial.call then
		local ok, msg = Tutorial.call("drill", { action = "patrol", cell = cell })
		if Tutorial.toast then
			Tutorial.toast(tostring(msg), if ok then "good" else "bad")
		end
	end
end

function Tutorial.onFeed(kind: string)
	if kind == "drill_ok" then
		drillOk = true
		Tutorial.drillRunning = false
	elseif kind == "drill_fail" then
		Tutorial.drillRunning = false
	end
end

local function onAction()
	local s = STEPS[step]
	if not s then
		return
	end
	if s.action == "FINISH" then
		Tutorial.stop()
	elseif s.action == "START" and Tutorial.call then
		local ok, msg = Tutorial.call("drill", { action = "start" })
		Tutorial.drillRunning = ok
		if Tutorial.toast then
			Tutorial.toast(tostring(msg), if ok then "good" else "bad")
		end
	end
end

function Tutorial.init(gui: ScreenGui)
	-- right side, under the leaderboard (the left edge holds the build menu)
	box = panel({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 262), Size = UDim2.fromOffset(240, 0), AutomaticSize = Enum.AutomaticSize.Y, Visible = false, Parent = gui })
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = box })
	UI.pad(10).Parent = box
	title = label({ Text = "", TextSize = 11, FontFace = F.Bold, TextColor3 = C.Accent, Size = UDim2.new(1, 0, 0, 14), LayoutOrder = 1, Parent = box })
	body = label({ Text = "", TextSize = 17, FontFace = F.Bold, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 2, Parent = box })
	local row = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 3, Parent = box })
	action = button({ Text = "", Kind = "primary", TextSize = 14, Size = UDim2.new(0.6, -4, 1, 0) }, onAction)
	action.Parent = row
	button({ Text = "Skip", TextSize = 13, Size = UDim2.new(0.4, -4, 1, 0), Position = UDim2.new(0.6, 4, 0, 0) }, function()
		Tutorial.stop()
	end).Parent = row

	-- first-visit offer: tutorial or straight to multiplayer
	offer = panel({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 262), Size = UDim2.fromOffset(240, 96), Parent = gui })
	label({ Text = "First time here?", TextSize = 16, FontFace = F.Bold, Size = UDim2.new(1, -20, 0, 20), Position = UDim2.fromOffset(10, 8), Parent = offer })
	label({ Text = "Quick 6-step guide.", TextSize = 13, TextColor3 = C.Sub, Size = UDim2.new(1, -20, 0, 16), Position = UDim2.fromOffset(10, 30), Parent = offer })
	button({ Text = "Start tutorial", Kind = "primary", TextSize = 14, Size = UDim2.new(0.5, -14, 0, 32), Position = UDim2.new(0, 10, 1, -42) }, function()
		Tutorial.start()
	end).Parent = offer
	button({ Text = "Play now", TextSize = 14, Size = UDim2.new(0.5, -14, 0, 32), Position = UDim2.new(0.5, 4, 1, -42) }, function()
		offer.Visible = false
	end).Parent = offer
	-- once per session; profile persistence comes with the save system
	offer.Visible = Players.LocalPlayer:GetAttribute("TutorialSeen") ~= true
	Players.LocalPlayer:SetAttribute("TutorialSeen", true)
end

function Tutorial.hideOffer()
	offer.Visible = false
end

return Tutorial
