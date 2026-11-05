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
}

local function folder(parent, name)
	local f = parent:FindFirstChild(name)
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
	if top then
		for _, d in ipairs(top:GetDescendants()) do
			if d:IsA("LuaSourceContainer") and d:GetAttribute("Synced") then
				d:Destroy()
			end
		end
	end
end

local list = Http:JSONDecode(Http:GetAsync(BASE .. "/list", true))
local count = 0
-- modules first so a parent script created later can hold children
table.sort(list, function(a, b)
	return #a:split("/") < #b:split("/") or (#a:split("/") == #b:split("/") and a < b)
end)
for _, rel in ipairs(list) do
	local parts = rel:split("/") -- src, root, ..., file
	local r = roots[parts[2]]
	if r then
		local parent = folder(r[1], r[2])
		for i = 3, #parts - 1 do
			parent = folder(parent, parts[i])
		end
		local file = parts[#parts]
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
