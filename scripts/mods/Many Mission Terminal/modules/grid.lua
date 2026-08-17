local mod = get_mod("Many Mission Terminal")

local MissionBoardThemes = require("scripts/ui/views/mission_board_view/mission_board_view_themes")
local MissionBoardViewSettings = require("scripts/ui/views/mission_board_view/mission_board_view_settings")

local C = mod:io_dofile("Many Mission Terminal/scripts/mods/Many Mission Terminal/modules/constants")
local Missions = mod:io_dofile("Many Mission Terminal/scripts/mods/Many Mission Terminal/modules/missions/core")

local GRID_COLS = C.GRID_COLS
local GRID_ROWS = C.GRID_ROWS
local GRID_X0 = C.GRID_X0
local TILE_SCALE = C.TILE_SCALE
local CATEGORY_ORDER = C.CATEGORY_ORDER
local TILE_BOX_W = C.TILE_BOX_W
local TILE_BOX_H = C.TILE_BOX_H
local TILE_PLATE_W = C.TILE_PLATE_W
local FILTER = C.FILTER
local mission_is_live = Missions.mission_is_live
local map_display_name = Missions.map_display_name

local Grid = {}

local Panel
local LAYOUT

local map_missions
local tile_ids
local mission_by_id
local slot_for_mission
local expanded_ids

local vanilla_slots
local vanilla_story_size

-- ─────────────────────────────────────────────────────────
-- Grid slots and layout
-- ─────────────────────────────────────────────────────────

function Grid.backup_vanilla_slots()
	if vanilla_slots then
		return
	end
	vanilla_slots = {}
	for name, theme in pairs(MissionBoardThemes) do
		local slots = theme.slots and theme.slots.small
		if slots then
			local copy = {}
			for i = 1, #slots do
				local slot = slots[i]
				copy[i] = {
					zoom = slot.zoom,
					rotation = slot.rotation,
					category_priority = slot.category_priority,
					position = {
						slot.position[1],
						slot.position[2],
					},
				}
			end
			vanilla_slots[name] = copy
		end
	end
end

local ROT_NEAR = 33.75
local ROT_FAR = 60
local ROT_SWEEP = 1000 / 1200

function Grid.slot_rotation(col, row)
	local last_col = math.max(LAYOUT.cols - 1, 1)
	local last_row = math.max(LAYOUT.rows - 1, 1)
	local base = ROT_NEAR + (row - 1) / last_row * (ROT_FAR - ROT_NEAR)

	return base * (1 - col / last_col * ROT_SWEEP)
end

function Grid.apply_slots(enabled)
	Grid.backup_vanilla_slots()

	local size_multipliers = MissionBoardViewSettings.mission_widgets_size_multipliers
	if size_multipliers then
		vanilla_story_size = vanilla_story_size or size_multipliers.story
		size_multipliers.story = enabled and size_multipliers.common or vanilla_story_size
	end

	local step_x = LAYOUT.step_x
	local grid_total = LAYOUT.cols * LAYOUT.rows
	local total = grid_total + C.EXPAND_SLOT_RESERVE

	for name, theme in pairs(MissionBoardThemes) do
		local slots = theme.slots and theme.slots.small
		local saved = vanilla_slots[name]
		if slots and saved then
			local target = enabled and total or #saved
			while #slots > target do
				table.remove(slots)
			end
			while #slots < target do
				slots[#slots + 1] = {
					zoom = 1,
					position = {
						0,
						0,
					},
				}
			end
			for i = 1, target do
				local slot = slots[i]
				slot.group = "small"
				slot.index = i
				if enabled then
					local col = (i - 1) % LAYOUT.cols
					local row = math.floor((i - 1) / LAYOUT.cols) + 1
					slot.zoom = 1
					slot.category_priority = nil
					if i > grid_total then
						slot.position[1] = C.GRID_CENTRE_X
						slot.position[2] = C.GRID_CENTRE_Y
					else
						slot.position[1] = GRID_X0 + LAYOUT.shift + col * step_x
						slot.position[2] = LAYOUT.row_y[math.min(row, LAYOUT.rows)]
					end
					slot.rotation = Grid.slot_rotation(col, row)
				else
					local source = saved[i]
					slot.zoom = source.zoom
					slot.rotation = source.rotation
					slot.category_priority = source.category_priority
					slot.position[1] = source.position[1]
					slot.position[2] = source.position[2]
				end
			end
		end
	end
end

function Grid.panel_intrusion(view)
	local scenegraph = view and view._ui_scenegraph

	if not scenegraph then
		return 0
	end

	local corner = scenegraph[FILTER.anchor]
	local area = scenegraph.mission_area

	if not corner or not area or not corner.world_position or not area.world_position then
		return 0
	end

	return math.max(0, corner.world_position[1] + FILTER.width - area.world_position[1])
end

function Grid.compute_layout(view)
	local scenegraph = view and view._ui_scenegraph
	local area = scenegraph and scenegraph.mission_area
	local sidebar = scenegraph and scenegraph.sidebar
	local canvas = scenegraph and scenegraph.canvas
	local corner = scenegraph and scenegraph[FILTER.anchor]

	if not LAYOUT.pin_shifts_grid or not area or not sidebar or not canvas or not corner then
		LAYOUT.cols = GRID_COLS
		LAYOUT.rows = GRID_ROWS
		LAYOUT.row_y = C.GRID_ROW_Y
		LAYOUT.shift = 0
		LAYOUT.scale = TILE_SCALE
		LAYOUT.step_x = (C.GRID_X1 - GRID_X0) / (GRID_COLS - 1)

		return true
	end

	local render_scale = RESOLUTION_LOOKUP.scale
	local nx, ny = area.world_position[1], area.world_position[2]

	local left = canvas.world_position[1] + LAYOUT.margin_left
	local right = sidebar.world_position[1] - LAYOUT.margin_right
	local top = ny + LAYOUT.edge_margin
	local bottom = ny + (area.size and area.size[2] or 920)
	local found = false

	for _, widget in ipairs(view._mission_widgets or {}) do
		local name = tostring(widget.name or "")
		local is_mission = widget.content and widget.content.mission ~= nil

		if widget.offset and not is_mission and string.sub(name, 1, 4) ~= "mmt_" then
			local art_top = math.huge

			for _, pass in pairs(widget.style) do
				if type(pass) == "table" and pass.size and pass.offset
					and type(pass.size[1]) == "number" and type(pass.size[2]) == "number" then
					local oy = pass.offset[2] or 0

					if pass.vertical_alignment == "center" then
						oy = oy + (TILE_BOX_H - pass.size[2]) * 0.5
					end

					if oy < art_top then
						art_top = oy
					end
				end
			end

			if art_top == math.huge then
				art_top = 0
			end

			local mult = widget.scale and render_scale * widget.scale or 1
			local edge = mult * (ny + widget.offset[2] + art_top) - LAYOUT.margin_bottom

			found = true

			if edge < bottom then
				bottom = edge
			end
		end
	end

	if not found then
		return false
	end

	bottom = math.max(bottom, ny + LAYOUT.min_bottom)

	local intrusion = corner.world_position[1] + FILTER.width - (nx + GRID_X0)
	local pinned = Panel.is_open() and intrusion > 0

	LAYOUT.intrusion = intrusion

	if pinned then
		left = math.max(left, corner.world_position[1] + FILTER.width + LAYOUT.pin_nudge * TILE_PLATE_W)
	end

	local cols = pinned and LAYOUT.pinned_cols or GRID_COLS
	local rows = pinned and LAYOUT.pinned_rows or GRID_ROWS

	local gw = LAYOUT.glow_w
	local gh = C.TILE_PLATE_H
	local al = (gw - TILE_BOX_W) * 0.5
	local at = (gh - TILE_BOX_H) * 0.5

	local by_width = (right - left + (cols - 1) * LAYOUT.step_trim)
		/ ((cols - 1) * LAYOUT.spread * TILE_PLATE_W + gw)
	local by_height = (bottom - top) / (((rows - 1) * LAYOUT.vspread + 1) * gh)
	local k = math.min(LAYOUT.max_scale * render_scale, math.max(0.2, math.min(by_width, by_height)))

	local step_v = LAYOUT.spread * TILE_PLATE_W * k - LAYOUT.step_trim
	local step_y = ((bottom - top) - gh * k) / (rows - 1)
	local row_y = {}

	for i = 1, rows do
		row_y[i] = (top + at * k + (i - 1) * step_y) / k - ny
	end

	LAYOUT.cols = cols
	LAYOUT.rows = rows
	LAYOUT.row_y = row_y
	LAYOUT.scale = k / render_scale
	LAYOUT.step_x = step_v / k
	LAYOUT.shift = (left / k - nx + al) - GRID_X0

	return true
end

function Grid.mission_is_notable(mission)
	return C.NOTABLE_CATEGORY[mission.category] == true and mission_is_live(mission)
end

function Grid.sort_map_missions(a, b)
	local live_a = mission_is_live(a)
	local live_b = mission_is_live(b)
	if live_a ~= live_b then
		return live_a
	end

	local order_a = CATEGORY_ORDER[a.category] or 99
	local order_b = CATEGORY_ORDER[b.category] or 99
	if order_a ~= order_b then
		return order_a < order_b
	end
	return a.id < b.id
end

function Grid.rebuild_map_missions(logic)
	table.clear(map_missions)
	table.clear(tile_ids)
	table.clear(mission_by_id)

	local filtered = logic and logic._filtered_missions
	if not filtered then
		return
	end

	for _, mission in pairs(filtered) do
		local map = mission.map
		if map then
			local list = map_missions[map]
			if not list then
				list = {}
				map_missions[map] = list
			end
			list[#list + 1] = mission
			mission_by_id[mission.id] = mission
		end
	end

	for _, list in pairs(map_missions) do
		table.sort(list, Grid.sort_map_missions)
		tile_ids[list[1].id] = true
	end

	for id in pairs(filtered) do
		if not tile_ids[id] and not expanded_ids[id] then
			filtered[id] = nil
		end
	end
end

local function card_is_renderable(mission, t)
	if not t then
		return true
	end
	if mission.start_game_time and t < mission.start_game_time then
		return false
	end
	if mission.expiry_game_time and t > mission.expiry_game_time then
		return false
	end
	return true
end

function Grid.layout_tiles(view, t)
	local logic = view._mission_board_logic
	if not logic then
		return
	end

	Grid.apply_slots(true)

	local filtered = logic._filtered_missions or {}
	local ordered = {}
	for id in pairs(tile_ids) do
		local mission = filtered[id]
		if mission and card_is_renderable(mission, t) then
			ordered[#ordered + 1] = mission
		end
	end

	table.sort(ordered, function (a, b)
		local notable_a = Grid.mission_is_notable(a)
		local notable_b = Grid.mission_is_notable(b)
		if notable_a ~= notable_b then
			return notable_a
		end

		if notable_a then
			local order_a = CATEGORY_ORDER[a.category] or 99
			local order_b = CATEGORY_ORDER[b.category] or 99
			if order_a ~= order_b then
				return order_a < order_b
			end
		end

		local name_a = map_display_name(a.map)
		local name_b = map_display_name(b.map)
		if name_a ~= name_b then
			return name_a < name_b
		end
		return a.map < b.map
	end)

	local slots = MissionBoardThemes.default.slots.small
	table.clear(slot_for_mission)
	for i = 1, #ordered do
		slot_for_mission[ordered[i].id] = slots[math.min(i, #slots)]
	end
end

function Grid.install(deps)
	Panel = deps.panel
	LAYOUT = deps.layout
	map_missions = deps.map_missions
	tile_ids = deps.tile_ids
	mission_by_id = deps.mission_by_id
	slot_for_mission = deps.slot_for_mission
	expanded_ids = deps.expanded_ids
end

return Grid
