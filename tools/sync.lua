-- Sync src/ into the open place (run in Studio Edit via execute_luau):
--   loadstring(game:GetService("HttpService"):GetAsync("http://127.0.0.1:8767/file?path=tools/sync.lua"))()
-- Layout (Rojo-like):
--   src/shared/**  -> ReplicatedStorage.Shared
--   src/server/**  -> ServerScriptService.Server   (*.server.luau = Script)
--   src/client/**  -> StarterPlayer.StarterPlayerScripts.Client (*.client.luau = LocalScript)
--   src/gui/**     -> StarterGui (*.client.luau = LocalScript)
-- Every synced script is recreated (Edit-mode require caches modules otherwise).
local Http = game:GetService("HttpService")
local BASE = "http://127.0.0.1:8767"
local roots = {
	shared = { game:GetService("ReplicatedStorage"), "Shared" },
	server = { game:GetService("ServerScriptService"), "Server" },
	client = { game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts"), "Client" },
	-- RoWorld's shared modules (AGPL, see NOTICE.md): ReplicatedStorage.Airfront, a ModuleScript (init.luau)
	airfront = { game:GetService("ReplicatedStorage"), "Airfront" },
}

-- a directory with an init.luau is a ModuleScript holding its children (Rojo rules)
local inits = {}
local function folder(parent, name, initRel)
	local f = parent:FindFirstChild(name)
	if initRel and not (f and f:IsA("ModuleScript")) then
		local m = Instance.new("ModuleScript")
		m.Name = name
		m:SetAttribute("Synced", true)
		m.Source = Http:GetAsync(BASE .. "/file?path=" .. Http:UrlEncode(initRel), true)
		if f then
			for _, c in f:GetChildren() do
				c.Parent = m
			end
			f:Destroy()
		end
		m.Parent = parent
		return m
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
	if top and top:IsA("LuaSourceContainer") and top:GetAttribute("Synced") then
		top:Destroy()
	elseif top then
		for _, d in ipairs(top:GetDescendants()) do
			if d:IsA("LuaSourceContainer") and d:GetAttribute("Synced") then
				d:Destroy()
			end
		end
	end
end

local list = Http:JSONDecode(Http:GetAsync(BASE .. "/list", true))
local count = 0
for _, rel in ipairs(list) do
	local dir = rel:match("^(.*)/init%.luau$")
	if dir then
		inits[dir] = rel
	end
end
-- modules first so a parent script created later can hold children
table.sort(list, function(a, b)
	return #a:split("/") < #b:split("/") or (#a:split("/") == #b:split("/") and a < b)
end)
for _, rel in ipairs(list) do
	local parts = rel:split("/") -- src, root, ..., file
	local r = roots[parts[2]]
	if r then
		local parent = folder(r[1], r[2], inits["src/" .. parts[2]])
		for i = 3, #parts - 1 do
			parent = folder(parent, parts[i], inits[table.concat(parts, "/", 1, i)])
		end
		local file = parts[#parts]
		if file == "init.luau" then
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
		if old and old:IsA("LuaSourceContainer") then
			old:Destroy()
		end
		local s = Instance.new(class)
		s.Name = name
		s:SetAttribute("Synced", true)
		s.Source = Http:GetAsync(BASE .. "/file?path=" .. Http:UrlEncode(rel), true)
		s.Parent = parent
		count += 1
	end
end
return ("synced %d scripts"):format(count)
