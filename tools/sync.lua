-- Sync src/ into the open place. Run from Studio's command bar (Edit mode):
--   loadstring(game:GetService("HttpService"):GetAsync("http://127.0.0.1:8767/file?path=tools/sync.lua", true))()
-- (MCP execute_luau can't reach 127.0.0.1 since 2026-11-06: the Assistant HTTP allowlist blocks it.)
-- Layout = RoWorld's default.project.json (rw.project.json), Rojo rules:
--   src/shared/**  -> ReplicatedStorage.Airfront                      (init.luau: a ModuleScript)
--   src/server/**  -> ServerScriptService.AirfrontServer             (init.server.luau: a Script)
--   src/client/**  -> StarterPlayer.StarterPlayerScripts.AirfrontClient (init.client.luau: a LocalScript)
-- The pre-port game (legacy/) is not synced; its old scripts are parked in ServerStorage.Legacy.
-- Every synced script is recreated (Edit-mode require caches modules otherwise).
local Http = game:GetService("HttpService")
local BASE = "http://127.0.0.1:8767"
local SSS = game:GetService("ServerScriptService")
local RS = game:GetService("ReplicatedStorage")
local SPS = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts")
local roots = {
	shared = { RS, "Airfront" },
	server = { SSS, "AirfrontServer" },
	client = { SPS, "AirfrontClient" },
}

-- the pre-port game's scripts: parked (not deleted) where they don't run
local SS = game:GetService("ServerStorage")
local legacy = SS:FindFirstChild("Legacy") or Instance.new("Folder")
legacy.Name = "Legacy"
legacy.Parent = SS
for _, old in { SSS:FindFirstChild("Server"), SPS:FindFirstChild("Client"), RS:FindFirstChild("Shared") } do
	if old then
		local prev = legacy:FindFirstChild(old.Name)
		if prev then
			prev:Destroy()
		end
		old.Parent = legacy
	end
end

-- RoWorld's place settings (rw.project.json)
game:GetService("Workspace").Gravity = 0
game:GetService("Players").CharacterAutoLoads = false
local SG = game:GetService("StarterGui")
SG.ResetPlayerGuiOnSpawn = false
SG.ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor
local L = game:GetService("Lighting")
L.Ambient = Color3.new(1, 1, 1)
L.OutdoorAmbient = Color3.new(1, 1, 1)
L.Brightness = 0
L.GlobalShadows = false
L.EnvironmentDiffuseScale = 0
L.EnvironmentSpecularScale = 0
L.ClockTime = 12
L.ExposureCompensation = 0
pcall(function()
	L.Technology = Enum.Technology.Compatibility
end)
local cg = L:FindFirstChild("ColorGrading") or Instance.new("ColorGradingEffect")
cg.Name = "ColorGrading"
pcall(function()
	cg.TonemapperPreset = Enum.TonemapperPreset.Retro
end)
cg.Parent = L

local CLASS = { ["init.luau"] = "ModuleScript", ["init.server.luau"] = "Script", ["init.client.luau"] = "LocalScript" }
local function get(rel)
	return Http:GetAsync(BASE .. "/file?path=" .. Http:UrlEncode(rel), true)
end
-- Source assignment stops at 199,999 characters; the big map modules go through ScriptEditorService
-- (the script must be in the DataModel first)
local SES = game:GetService("ScriptEditorService")
local function setSource(s, src)
	if #src < 199000 then
		s.Source = src
	else
		SES:UpdateSourceAsync(s, function()
			return src
		end)
	end
end

-- a directory with an init file is that script, holding its children (Rojo rules)
local inits = {}
local function folder(parent, name, initRel)
	local f = parent:FindFirstChild(name)
	if initRel then
		local class = CLASS[initRel:match("[^/]+$")]
		if not (f and f.ClassName == class) then
			local m = Instance.new(class)
			m.Name = name
			m:SetAttribute("Synced", true)
			if f then
				for _, c in f:GetChildren() do
					c.Parent = m
				end
				f:Destroy()
			end
			m.Parent = parent
			setSource(m, get(initRel))
			return m
		end
		return f
	end
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f
end

-- drop previously synced scripts
for _, r in pairs(roots) do
	local top = r[1]:FindFirstChild(r[2])
	if top and (top:GetAttribute("Synced") or top:IsA("Folder")) then
		top:Destroy()
	end
end

local list = Http:JSONDecode(Http:GetAsync(BASE .. "/list", true))
local count = 0
for _, rel in ipairs(list) do
	local dir, file = rel:match("^(.*)/([^/]+)$")
	if dir and CLASS[file] then
		inits[dir] = rel
	end
end
-- parents first so an init script created later can hold children
table.sort(list, function(a, b)
	return #a:split("/") < #b:split("/") or (#a:split("/") == #b:split("/") and a < b)
end)
for i, rel in ipairs(list) do
	local parts = rel:split("/") -- src, root, ..., file
	local r = roots[parts[2]]
	if r then
		local parent = folder(r[1], r[2], inits["src/" .. parts[2]])
		for j = 3, #parts - 1 do
			parent = folder(parent, parts[j], inits[table.concat(parts, "/", 1, j)])
		end
		local file = parts[#parts]
		if CLASS[file] then
			count += 1
			continue
		end
		local name, class = file:gsub("%.luau$", ""), "ModuleScript"
		if name:match("%.server$") then
			name, class = name:gsub("%.server$", ""), "Script"
		elseif name:match("%.client$") then
			name, class = name:gsub("%.client$", ""), "LocalScript"
		end
		local old = parent:FindFirstChild(name)
		local s = Instance.new(class)
		s.Name = name
		s:SetAttribute("Synced", true)
		local src = get(rel)
		if old then
			-- (a folder synced before its init file: keep its children)
			for _, c in old:GetChildren() do
				c.Parent = s
			end
			old:Destroy()
		end
		s.Parent = parent
		setSource(s, src)
		count += 1
	end
	if i % 20 == 0 then
		task.wait()
	end
end
print(("[sync] synced %d scripts"):format(count))
return ("synced %d scripts"):format(count)
