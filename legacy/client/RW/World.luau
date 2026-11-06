--!nonstrict
-- Stand-in for RoWorld's WorldView (AGPL; see NOTICE.md) over this game's 2D map (MapView): screen <->
-- tile conversion in viewport px, camera focus, the selected / hovered nation highlight, aim and
-- range rings, and the tile_hovered / tile_clicked / tile_context signals Main fires from its input.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local State = require(script.Parent.Parent.State)
local MapView = require(script.Parent.Parent.MapView)
local Signal = require(ReplicatedStorage:WaitForChild("Airfront").Core.Signal)

local World = {}
World.__index = World

local AIM_RED = Color3.fromHex("FF5C61")
local AIM_OK = Color3.fromHex("FFB547")

function World.new()
	local self = setmetatable({}, World)
	self.tile_hovered = Signal.new()
	self.tile_clicked = Signal.new()
	self.tile_context = Signal.new()
	self.territory_status_changed = Signal.new()
	self.input_enabled = true
	self.hud_controls = {}
	self._aim = nil
	return self
end

local function origin(): Vector2
	return MapView.frame().AbsolutePosition
end

-- viewport px -> tile (or -1)
function World.tile_at_screen(_self, p: Vector2): number
	local c = MapView.cellAt(p - origin(), false)
	return if c then c else -1
end

function World.screen_pos_of_tile(_self, tile: number): Vector2
	if not State.ready or tile < 0 or tile >= State.N then
		return Vector2.new(-1, -1)
	end
	return MapView.cellToLocal(tile % State.W + 0.5, tile // State.W + 0.5) + origin()
end

function World.unit_at_screen(_self, p: Vector2): number
	local q = p - origin()
	local now = workspace:GetServerTimeNow()
	local best, bd = -1, 14 * 14
	for id, u in State.units do
		if u.kind == "warship" or u.kind == "transport" then
			local x, y = State.unitPos(u, now)
			local d = (MapView.cellToLocal(x, y) - q).Magnitude ^ 2
			if d < bd then
				best, bd = id, d
			end
		end
	end
	return best
end

function World.focus_tile(_self, tile: number, zoom: number?)
	if tile and tile >= 0 and State.ready then
		MapView.centerOn(tile % State.W, tile // State.W, math.max(MapView.z, zoom or 3))
	end
end

function World.focus_owner(_self, id: number)
	local c = State.cnt[id] or 0
	if c > 0 then
		MapView.centerOn(State.sumX[id] / c, State.sumY[id] / c, math.max(MapView.z, 3))
	end
end

function World.set_selected_owner(_self, id: number)
	MapView.setHighlight(if id and id > 0 and id ~= State.me then id else 0)
end
function World.set_hover_owner(_self, _id: number) end
function World.set_selected_unit(_self, uid: number)
	State.selectedUnit = if uid and uid > 0 then uid else nil
end

-- aim preview: kind is a RoWorld kind name ("city", "atom", ...), radius in tiles (0 = none)
function World.set_aim(self, kind: string, tile: number, radius: number, valid: boolean, _detail: string, _level: number)
	if kind == "" or kind == "none" or not tile or tile < 0 then
		self._aim = nil
		MapView.showBuildPreview(nil, nil, false)
		MapView.showRing(nil, 0)
		return
	end
	self._aim = { kind = kind, tile = tile }
	local ours = ({ artillery = "aa" } :: any)[kind] or kind
	if Config.Structures[ours] then
		MapView.showBuildPreview(tile, ours, valid)
		local r = State.reachOf(ours)
		MapView.showRing(if r then tile else nil, r or 0)
	else
		MapView.showBuildPreview(nil, nil, false)
		MapView.showRing(if radius and radius > 0 then tile else nil, radius or 0, if valid then AIM_OK else AIM_RED)
	end
end

function World.set_range_mode(_self, _mode: any) end
function World.set_range_focus(_self, tile: number?, radius: number?)
	if tile and tile >= 0 and radius and radius > 0 then
		MapView.showRing(tile, radius)
	end
end
function World.set_range_owner(_self, _id: number) end
-- hostile finished SAMs whose radius covers the current missile / nuke aim (RoWorld's tooltip row)
function World.aim_sams(self): number
	local a = self._aim
	if not a or (a.kind ~= "atom" and a.kind ~= "hydrogen" and a.kind ~= "mirv") then
		return 0
	end
	local r = Config.Structures.sam.radius
	local ax, ay = a.tile % State.W, a.tile // State.W
	local n = 0
	for _, s in State.structures do
		if s.kind == "sam" and s.owner ~= State.me and not State.allied(s.owner) and State.built(s) then
			if (s.cell % State.W - ax) ^ 2 + (s.cell // State.W - ay) ^ 2 <= r * r then
				n += 1
			end
		end
	end
	return n
end
function World.set_labels_visible(_self, _on: boolean) end
function World.set_hud_controls(self, list: { GuiObject })
	self.hud_controls = list
end
function World.set_safe_area(_self, ...) end
function World.set_borders(_self, _b: any) end
function World.set_attract_mode(_self, _on: boolean) end
function World.set_admin_bots(_self, _on: boolean) end
function World.set_input_enabled(self, on: boolean)
	self.input_enabled = on
end
function World.territory_status(_self)
	return nil
end
function World.local_label_rect(_self)
	return nil
end

-- is a viewport point over one of RoWorld's HUD panels? (Main skips map input there)
function World.over_hud(self, p: Vector2): boolean
	for _, g in self.hud_controls do
		if typeof(g) == "Instance" and g:IsA("GuiObject") and g.Visible then
			local a, s = g.AbsolutePosition, g.AbsoluteSize
			if p.X >= a.X and p.Y >= a.Y and p.X <= a.X + s.X and p.Y <= a.Y + s.Y then
				return true
			end
		end
	end
	return false
end

return World
