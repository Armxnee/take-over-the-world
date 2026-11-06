--!nonstrict
-- The playable maps for the UI: the replicated registry (Data/MapList)
-- joined with the uploaded thumbnails (Assets/MapThumbs, keyed by the source map folder name). Falls
-- back to the one built-in map when the registry is missing.
local RS = game:GetService("ReplicatedStorage")

local UIMaps = {}

UIMaps.DEFAULT_ID = "earth"
--- The source manifests' featured_rank (the registry does not carry it).
UIMaps.FEATURED_RANK = { world = 1, europe = 2, northamerica = 3, southamerica = 4, asia = 5, africa = 6 }

local _entries: { any }? = nil
local _by_id: { [string]: any } = {}

--- Registry ids and thumbnail keys compare case- and punctuation-insensitively.
local function norm(id: string): string
	return string.lower((string.gsub(id, "[^%w]", "")))
end
UIMaps.norm = norm

local function find(folder: Instance?, name: string): any
	local m = folder and folder:FindFirstChild(name)
	if m and m:IsA("ModuleScript") then
		local ok, v = pcall(require, m)
		if ok then
			return v
		end
	end
	return nil
end

--- { {id, name, width, height, categories, featured_rank, thumb}, ... }
--- Take Over the World!: this game's maps (Shared.Config), with RoWorld's thumbnails where the map is
--- the same region (Assets/MapThumbs); a map without one shows its name.
local OUR_THUMB = { earth = "world", northamerica = "northamerica", europe = "europe", africa = "africa" }
function UIMaps.entries(): { any }
	if _entries ~= nil then
		return _entries
	end
	local root = RS:FindFirstChild("Airfront")
	local thumbs = find(root and root:FindFirstChild("Assets"), "MapThumbs") or {}
	local Config = require(RS:WaitForChild("Shared"):WaitForChild("Config")) :: any
	local out = {}
	for k, id in Config.MapOrder do
		local def = Config.Maps[id]
		local e = {
			id = id,
			name = def.Name,
			width = def.W,
			height = def.H,
			categories = if def.Special then { "special" } elseif id == "earth" then { "featured", "world" } else { "featured", "continent" },
			featured_rank = k,
			thumb = thumbs[OUR_THUMB[id] or ""],
			nations = def.Nations,
			desc = def.Desc,
		}
		table.insert(out, e)
		_by_id[norm(id)] = e
	end
	_entries = out
	return out
end

function UIMaps.get(id: string?): any
	UIMaps.entries()
	local key = id or UIMaps.DEFAULT_ID
	-- a public match's smaller build ("world@80") shows as its map
	key = string.match(key, "^(.-)@%d+$") or key
	return _by_id[norm(key)]
end

function UIMaps.name_of(id: string?): string
	local e = UIMaps.get(id)
	return if e then e.name else "World"
end

--- A valid map id for `id` (the default when unknown).
function UIMaps.valid(id: string?): string
	local e = UIMaps.get(id)
	if e then
		return e.id
	end
	local first = UIMaps.entries()[1]
	return if first then first.id else UIMaps.DEFAULT_ID
end

return UIMaps
