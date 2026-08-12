--[[
Name: Many Mission Terminal
Author: Wobin
Date: 13/08/2026
Version: 1.1.0
Repository: https://github.com/Wobin/ManyMissionTerminal
--]]

local mod = get_mod("Many Mission Terminal")
mod.version = "1.1.0"

local MMT = get_mod("ManyMoreTry")
local MissionBoardViewSettings = require("scripts/ui/views/mission_board_view/mission_board_view_settings")
local CircumstanceTemplates = require("scripts/settings/circumstance/circumstance_templates")
local MissionObjectiveTemplates = require("scripts/settings/mission_objective/mission_objective_templates")
local MissionBoardThemes = require("scripts/ui/views/mission_board_view/mission_board_view_themes")
local MissionBoardViewStyles = require("scripts/ui/views/mission_board_view/mission_board_view_styles")
local Text = require("scripts/utilities/ui/text")
local UIWidget = require("scripts/managers/ui/ui_widget")
local UIFontSettings = require("scripts/managers/ui/ui_font_settings")
local InputDevice = require("scripts/managers/input/input_device")

local C = mod:io_dofile("Many Mission Terminal/scripts/mods/Many Mission Terminal/modules/constants")
local Missions = mod:io_dofile("Many Mission Terminal/scripts/mods/Many Mission Terminal/modules/missions")
local Archive = mod:io_dofile("Many Mission Terminal/scripts/mods/Many Mission Terminal/modules/archive")

local GRID_COLS = C.GRID_COLS
local GRID_ROWS = C.GRID_ROWS
local GRID_X0 = C.GRID_X0
local TILE_SCALE = C.TILE_SCALE

local set_filter_open

local LAYOUT = {
	shift = 0,
	scale = C.TILE_SCALE,
	step_x = (C.GRID_X1 - C.GRID_X0) / (C.GRID_COLS - 1),
	intrusion = 0,
	pin_shifts_grid = true,
	cols = C.GRID_COLS,
	rows = C.GRID_ROWS,
	row_y = C.GRID_ROW_Y,
	pinned_cols = 6,
	pinned_rows = 4,
	spread = 1.03,
	step_trim = 12,
	max_scale = 1.0,
	edge_margin = 8,
	margin_right = 100,
	margin_bottom = 10,
	min_bottom = 400,
	margin_left = 10,
	glow_w = 300,
	pin_nudge = 0.2,
	vspread = 1.0,
}
local PLAIN_STYLES = C.PLAIN_STYLES
local CATEGORY_ORDER = C.CATEGORY_ORDER
local TILE_BOX_W = C.TILE_BOX_W
local TILE_BOX_H = C.TILE_BOX_H
local TILE_PLATE_W = C.TILE_PLATE_W
local FADE_ALPHA = C.FADE_ALPHA
local HORIZON_MINUTES = C.HORIZON_MINUTES
local MTABLE = C.MTABLE
local BADGE = C.BADGE
local TOOLTIP = C.TOOLTIP
local SCRIM = C.SCRIM
local FILTER = C.FILTER
local FILTER_CATEGORIES = C.FILTER_CATEGORIES
local FILTER_CONDITIONS = C.FILTER_CONDITIONS
local EXPIRED_BAR_COLOR = C.EXPIRED_BAR_COLOR
local FADE_COLOR_KEYS = C.FADE_COLOR_KEYS

local mission_is_live = Missions.mission_is_live
local minutes_past_expiry = Missions.minutes_past_expiry
local map_display_name = Missions.map_display_name
local refresh_now = Missions.refresh_now

local show_all_missions = false
local use_archive = false
local vanilla_slots
local vanilla_story_size
local expanded_map
local expanded_ids = {}
local faded_widgets = {}
local layout_dirty = false
local incompatible_warned = false
local map_missions = {}
local tile_ids = {}
local mission_by_id = {}
local slot_for_mission = {}
local scrim_widget
local scrim_pressed = false
local pending_collapse = false
local pending_filter_group
local pending_filter_key
local expand_card_pressed = false
local tooltip_widget
local tooltip_card
local badge_widgets = {}
local badge_dx = BADGE.dx
local badge_dy = BADGE.dy
local next_expiry_scan = 0
local table_ui = {
	widgets = {},
	rows = {},
	row_count = 0,
	source_count = 0,
	dx = MTABLE.dx,
	dy = MTABLE.dy,
	cell_cx = {},
	slot_cx = {},
}

local filter_ui = {
	open = false,
	slide = 0,
	rows = {},
	row_widgets = {},
	scan_dirty = true,
}

local TABLE_CELLS = {
	"type",
	"cond",
	"side",
	"saved",
}

local saved_ids = {}

local function refresh_saved_ids()
	table.clear(saved_ids)

	local list = MMT and MMT:is_enabled() and MMT:get("_saved_mission")

	if not list then
		return
	end

	for i = 1, #list do
		local entry = list[i]

		if entry and entry.id then
			saved_ids[entry.id] = true
		end
	end
end

local function refresh_settings()
	show_all_missions = mod:get("show_all_missions") == true
	use_archive = mod:get("use_archive") == true
end

local function board_is_open()
	return Managers.ui and Managers.ui:view_instance("mission_board_view") ~= nil
end

local function backup_vanilla_slots()
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

local function slot_rotation(col, row)
	local last_col = math.max(LAYOUT.cols - 1, 1)
	local last_row = math.max(LAYOUT.rows - 1, 1)
	local base = ROT_NEAR + (row - 1) / last_row * (ROT_FAR - ROT_NEAR)

	return base * (1 - col / last_col * ROT_SWEEP)
end

local function apply_grid_slots(enabled)
	backup_vanilla_slots()

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
					slot.rotation = slot_rotation(col, row)
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

local function filters()
	if not filter_ui.state then
		local stored = mod:get("_filters")
		filter_ui.state = type(stored) == "table" and stored or {}
	end

	return filter_ui.state
end

local function filter_default(group, key)
	if group == "match" then
		return false
	end

	if group == "category" then
		for i = 1, #FILTER_CATEGORIES do
			if FILTER_CATEGORIES[i].key == key then
				return not FILTER_CATEGORIES[i].off_by_default
			end
		end
	end

	return true
end

local function filter_enabled(group, key)
	local group_state = filters()[group]
	local value = group_state and group_state[key]

	if value == nil then
		return filter_default(group, key)
	end

	return value == true
end

local function set_filter(group, key, value)
	local state = filters()
	state[group] = state[group] or {}
	state[group][key] = value
	mod:set("_filters", state, false)
end

local function conditions_for_circumstance(circumstance)
	if not filter_ui.conditions_by_circumstance then
		filter_ui.conditions_by_circumstance = {}

		local key_by_mutator = {}
		for i = 1, #FILTER_CONDITIONS do
			local condition = FILTER_CONDITIONS[i]
			for j = 1, #condition.mutators do
				key_by_mutator[condition.mutators[j]] = condition.key
			end
		end

		for name, template in pairs(CircumstanceTemplates) do
			local mutators = template.mutators
			if mutators then
				local found
				for j = 1, #mutators do
					local key = key_by_mutator[mutators[j]]
					if key then
						found = found or {}
						found[key] = true
					end
				end
				filter_ui.conditions_by_circumstance[name] = found
			end
		end
	end

	return circumstance and filter_ui.conditions_by_circumstance[circumstance]
end

local function panel_intrusion(view)
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

local function compute_grid_layout(view)
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
	local pinned = filter_ui.open and intrusion > 0

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

local function mission_side_key(mission)
	return mission.side_mission or mission.sideMission or FILTER.side_none
end

local function mission_passes_filters(mission)
	if not filter_enabled("category", mission.category) then
		return false
	end

	local conditions = conditions_for_circumstance(mission.circumstance)

	if filter_enabled("match", "any") then
		local any_ticked = false

		for i = 1, #FILTER_CONDITIONS do
			if filter_enabled("condition", FILTER_CONDITIONS[i].key) then
				any_ticked = true
				break
			end
		end

		local matched = not any_ticked

		if conditions and not matched then
			for key in pairs(conditions) do
				if filter_enabled("condition", key) then
					matched = true
					break
				end
			end
		end

		if not matched then
			return false
		end
	elseif conditions then
		for key in pairs(conditions) do
			if not filter_enabled("condition", key) then
				return false
			end
		end
	end

	local side = mission.side_mission or mission.sideMission

	if side and not filter_enabled("side", side) then
		return false
	end

	if not filter_enabled("state", "expired") and not mission_is_live(mission) then
		return false
	end

	return true
end

local function mission_is_notable(mission)
	return C.NOTABLE_CATEGORY[mission.category] == true and mission_is_live(mission)
end

local function sort_map_missions(a, b)
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

local function rebuild_map_missions(logic)
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
		table.sort(list, sort_map_missions)
		tile_ids[list[1].id] = true
	end

	for id in pairs(filtered) do
		if not tile_ids[id] and not expanded_ids[id] then
			filtered[id] = nil
		end
	end
end

local function convert_expired_missions(logic, t)
	local mission_data = logic._mission_data
	if not mission_data then
		return false
	end

	local now_ms = os.time() * 1000
	local converted = false

	for i = 1, #mission_data do
		local mission = mission_data[i]
		local expiry = tonumber(mission.expiry)

		if expiry and not mission.mmt_horizon and mission.expiry_game_time and t > mission.expiry_game_time then
			local past = (now_ms - expiry) / 60000
			local remaining = HORIZON_MINUTES - past

			if remaining > 0 then
				mission.mmt_expiry_game_time = t - past * 60
				mission.expiry_game_time = t + remaining * 60
				mission.start_game_time = mission.expiry_game_time - HORIZON_MINUTES * 60
				mission.mmt_horizon = true
				converted = true
			end
		end
	end

	return converted
end

local function tile_is_renderable(mission, t)
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

local function layout_tiles(view, t)
	local logic = view._mission_board_logic
	if not logic then
		return
	end

	apply_grid_slots(true)

	local filtered = logic._filtered_missions or {}
	local ordered = {}
	for id in pairs(tile_ids) do
		local mission = filtered[id]
		if mission and tile_is_renderable(mission, t) then
			ordered[#ordered + 1] = mission
		end
	end

	table.sort(ordered, function (a, b)
		local notable_a = mission_is_notable(a)
		local notable_b = mission_is_notable(b)
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

local function capture_card_baseline(widget)
	local style = widget.style
	local banner = style.mission_type_banner
	local banner_text = style.mission_type_banner_text
	local baseline = {
		visible = {},
	}

	for i = 1, #PLAIN_STYLES do
		local id = PLAIN_STYLES[i]
		local plain_style = style[id]
		if plain_style then
			baseline.visible[id] = plain_style.visible ~= false
		end
	end

	if banner and banner.offset and banner_text and banner_text.offset then
		baseline.banner = {
			bx = banner.offset[1],
			by = banner.offset[2],
			tx = banner_text.offset[1],
			ty = banner_text.offset[2],
			bdx = banner.default_offset and banner.default_offset[1],
			bdy = banner.default_offset and banner.default_offset[2],
			tdx = banner_text.default_offset and banner_text.default_offset[1],
			tdy = banner_text.default_offset and banner_text.default_offset[2],
		}
	end

	widget.mmt_baseline = baseline
end

local function apply_gradients(widget, category)
	local gradient = MissionBoardViewStyles.gradient_by_category[category] or MissionBoardViewStyles.gradient_by_category.default
	if not gradient then
		return
	end

	for i = 1, #C.GRADIENT_STYLES do
		local style = widget.style[C.GRADIENT_STYLES[i]]
		if style then
			style.default_gradient = gradient.default_gradient
			style.selected_gradient = gradient.selected_gradient
			style.disabled_gradient = gradient.disabled_gradient
			if style.material_values and style.material_values.gradient_map then
				style.material_values.gradient_map = gradient.default_gradient
			end
		end
	end
end

local function normalise_tile_size(widget)
	local background_frame = widget.style.background_frame
	if background_frame then
		background_frame.visible = true
	end

	local location_corner = widget.style.location_corner
	if location_corner and location_corner.size_addition then
		location_corner.size_addition[1] = 0
		location_corner.size_addition[2] = 0
	end

	local selected_frame_detail = widget.style.selected_frame_detail
	if selected_frame_detail and selected_frame_detail.size_addition then
		selected_frame_detail.size_addition[1] = 40
		selected_frame_detail.size_addition[2] = 40
	end
end

local function apply_category_chrome(widget, category)
	local baseline = widget.mmt_baseline

	for i = 1, #PLAIN_STYLES do
		local id = PLAIN_STYLES[i]
		local style = widget.style[id]
		if style and baseline then
			style.visible = baseline.visible[id] == true
		end
	end

	apply_gradients(widget, category)
end

local function make_tile_plain(widget)
	for i = 1, #PLAIN_STYLES do
		local style = widget.style[PLAIN_STYLES[i]]
		if style then
			style.visible = false
		end
	end

	apply_gradients(widget, "common")
end

local function banner_base_label(mission)
	if mission.category == "event" then
		return Localize("loc_mission_board_mission_category_event")
	end

	local key = MissionBoardViewSettings.mission_tile_banner_category_texts[mission.category]

	if not key or key == "n/a" then
		return ""
	end

	return Localize(key)
end

local function apply_banner(view, widget, mission)
	local style = widget.style
	local banner = style.mission_type_banner
	local banner_text = style.mission_type_banner_text
	local baseline = widget.mmt_baseline

	if not banner or not banner_text or not baseline then
		return
	end

	local label = banner_base_label(mission)

	widget.content.mission_type_banner_text = label

	if banner.visible == false or label == "" then
		return
	end

	local ui_renderer = view and view._ui_renderer
	if ui_renderer then
		local width = Text.text_size(ui_renderer, label, banner_text, C.BADGE_TEXT_BOUNDS)
		if banner_text.size then
			banner_text.size[1] = width + 26
		end
		if banner.size then
			banner.size[1] = width + 46
		end
	end

	local base = baseline.banner
	local size = widget.content.size
	if not base or not size then
		return
	end

	local banner_width = banner.size and banner.size[1] or size[1]
	local target_x = (size[1] - banner_width) * 0.5
	local target_y = size[2] + C.BANNER_GAP
	local shift_x = target_x - base.bx
	local shift_y = target_y - base.by

	banner.offset[1] = target_x
	banner.offset[2] = target_y
	banner_text.offset[1] = base.tx + shift_x
	banner_text.offset[2] = base.ty + shift_y

	if banner.default_offset and base.bdx then
		banner.default_offset[1] = base.bdx + shift_x
		banner.default_offset[2] = base.bdy + shift_y
	end
	if banner_text.default_offset and base.tdx then
		banner_text.default_offset[1] = base.tdx + shift_x
		banner_text.default_offset[2] = base.tdy + shift_y
	end
end

local function fade_widget(widget)
	local entry = {
		widget = widget,
		alpha = widget.alpha_multiplier,
		colors = {},
		gradients = {},
		visibility = {},
		was_locked = widget.content.is_locked,
	}

	for style_id, style in pairs(widget.style) do
		if type(style) == "table" then
			for i = 1, #FADE_COLOR_KEYS do
				local color = style[FADE_COLOR_KEYS[i]]
				if type(color) == "table" and color[1] then
					entry.colors[#entry.colors + 1] = {
						color,
						color[1],
					}
					color[1] = math.floor(color[1] * FADE_ALPHA)
				end
			end

			local material_values = style.material_values
			if type(material_values) == "table" and material_values.gradient_map and style.disabled_gradient then
				entry.gradients[#entry.gradients + 1] = {
					material_values,
					material_values.gradient_map,
				}
				material_values.gradient_map = style.disabled_gradient
			end

			if style_id == "mission_type_banner" or style_id == "mission_type_banner_text" then
				entry.visibility[#entry.visibility + 1] = {
					style,
					style.visible,
				}
				style.visible = false
			end
		end
	end

	widget.content.is_locked = true
	widget.alpha_multiplier = FADE_ALPHA
	widget.dirty = true

	faded_widgets[#faded_widgets + 1] = entry
end

local function restore_faded_widgets()
	for i = 1, #faded_widgets do
		local entry = faded_widgets[i]
		local widget = entry.widget

		for j = 1, #entry.colors do
			entry.colors[j][1][1] = entry.colors[j][2]
		end
		for j = 1, #entry.gradients do
			entry.gradients[j][1].gradient_map = entry.gradients[j][2]
		end
		for j = 1, #entry.visibility do
			entry.visibility[j][1].visible = entry.visibility[j][2]
		end
		widget.content.is_locked = entry.was_locked
		widget.alpha_multiplier = entry.alpha
		widget.dirty = true
	end
	table.clear(faded_widgets)
end

local function style_expired_timer(widget)
	local timer_bar = widget.style.timer_bar
	if not timer_bar then
		return
	end

	timer_bar.visible = true
	timer_bar.color = table.clone(EXPIRED_BAR_COLOR)
	timer_bar.default_color = table.clone(EXPIRED_BAR_COLOR)
	timer_bar.selected_color = table.clone(EXPIRED_BAR_COLOR)
	timer_bar.hover_color = table.clone(EXPIRED_BAR_COLOR)
end

local function style_card(view, widget, mission)
	widget.scale = LAYOUT.scale

	if not mission_is_live(mission) then
		style_expired_timer(widget)
	end

	normalise_tile_size(widget)

	if mission_is_notable(mission) then
		apply_category_chrome(widget, mission.category)
	else
		make_tile_plain(widget)
	end

	apply_banner(view, widget, mission)
end

local SCRIM_BANDS = {
	"top",
	"bottom",
	"left",
	"right",
}

local function scrim_definition()
	local passes = {
		{
			pass_type = "rect",
			style_id = "veil",
			style = {
				horizontal_alignment = "left",
				vertical_alignment = "top",
				size = {
					SCRIM.w,
					SCRIM.h,
				},
				offset = {
					SCRIM.x,
					SCRIM.y,
					0,
				},
				color = SCRIM.color,
			},
		},
	}

	for i = 1, #SCRIM_BANDS do
		passes[#passes + 1] = {
			content_id = "band_" .. SCRIM_BANDS[i],
			style_id = "band_" .. SCRIM_BANDS[i],
			pass_type = "hotspot",
			style = {
				horizontal_alignment = "left",
				vertical_alignment = "top",
				size = {
					0,
					0,
				},
				offset = {
					SCRIM.x,
					SCRIM.y,
					1,
				},
			},
		}
	end

	return UIWidget.create_definition(passes, "mission_area", {
		static = true,
	}, {
		SCRIM.w,
		SCRIM.h,
	})
end

local function set_scrim_band(widget, name, x, y, w, h)
	local style = widget.style["band_" .. name]

	if not style then
		return
	end

	style.offset[1] = x
	style.offset[2] = y
	style.size[1] = math.max(w, 0)
	style.size[2] = math.max(h, 0)
end

local function layout_scrim_bands(widget, hole_x, hole_y, hole_w, hole_h)
	local x0, y0 = SCRIM.x, SCRIM.y
	local x1, y1 = SCRIM.x + SCRIM.w, SCRIM.y + SCRIM.h

	if not hole_x then
		set_scrim_band(widget, "top", x0, y0, SCRIM.w, SCRIM.h)
		set_scrim_band(widget, "bottom", x0, y0, 0, 0)
		set_scrim_band(widget, "left", x0, y0, 0, 0)
		set_scrim_band(widget, "right", x0, y0, 0, 0)

		return
	end

	local hx1, hy1 = hole_x + hole_w, hole_y + hole_h

	set_scrim_band(widget, "top", x0, y0, SCRIM.w, hole_y - y0)
	set_scrim_band(widget, "bottom", x0, hy1, SCRIM.w, y1 - hy1)
	set_scrim_band(widget, "left", x0, hole_y, hole_x - x0, hole_h)
	set_scrim_band(widget, "right", hx1, hole_y, x1 - hx1, hole_h)
end

local function ensure_scrim(view)
	if scrim_widget then
		return scrim_widget
	end

	local widgets = view._mission_widgets
	if not widgets then
		return nil
	end

	scrim_widget = view:_create_widget("mmt_expand_scrim", scrim_definition())
	scrim_widget.offset[3] = SCRIM.z
	scrim_widget.visible = false
	for i = 1, #SCRIM_BANDS do
		scrim_widget.content["band_" .. SCRIM_BANDS[i]].pressed_callback = function ()
			scrim_pressed = true
		end
	end

	layout_scrim_bands(scrim_widget)
	widgets[#widgets + 1] = scrim_widget

	return scrim_widget
end

local function badge_definition()
	local count_style = table.clone(UIFontSettings.body_small)
	count_style.horizontal_alignment = "center"
	count_style.vertical_alignment = "bottom"
	count_style.text_horizontal_alignment = "center"
	count_style.text_vertical_alignment = "center"
	count_style.size = {
		BADGE.size,
		BADGE.size,
	}
	count_style.offset = {
		badge_dx,
		badge_dy,
		2,
	}
	count_style.text_color = Color.terminal_text_header(255, true)

	return UIWidget.create_definition({
		{
			pass_type = "texture",
			style_id = "plate",
			value = BADGE.material,
			style = {
				horizontal_alignment = "center",
				vertical_alignment = "bottom",
				size = {
					BADGE.size,
					BADGE.size,
				},
				offset = {
					badge_dx,
					badge_dy,
					1,
				},
				color = Color.terminal_background(255, true),
			},
		},
		{
			pass_type = "text",
			style_id = "count",
			value_id = "count",
			value = "",
			style = count_style,
		},
	}, "mission_area", nil, {
		TILE_BOX_W,
		TILE_BOX_H,
	})
end

local function ensure_badge(view, index)
	local widget = badge_widgets[index]
	if widget then
		return widget
	end

	local widgets = view._widgets
	if not widgets then
		return nil
	end

	widget = view:_create_widget("mmt_badge_" .. index, badge_definition())
	widget.offset[3] = BADGE.z
	widget.visible = false
	badge_widgets[index] = widget
	widgets[#widgets + 1] = widget

	return widget
end

local function place_badge(view, index, card, count)
	local widget = ensure_badge(view, index)
	if not widget then
		return
	end

	widget.scale = card.scale
	widget.offset[1] = card.offset[1]
	widget.offset[2] = card.offset[2]
	widget.visible = true

	if widget.mmt_count ~= count then
		widget.mmt_count = count
		widget.content.count = tostring(count)
	end

	local plate = card.style.background_frame
	local grow = 0

	if plate and plate.size and plate.default_size then
		grow = (plate.size[2] - plate.default_size[2]) * BADGE.grow_factor
	end

	local y = badge_dy + grow

	if widget.mmt_grow ~= y then
		widget.mmt_grow = y
		widget.style.plate.offset[2] = y
		widget.style.count.offset[2] = y
	end

	widget.dirty = true
end

mod.mmt_tune_badge = function (dx, dy)
	badge_dx = dx or badge_dx
	badge_dy = dy or badge_dy

	for i = 1, #badge_widgets do
		local widget = badge_widgets[i]
		if widget then
			widget.style.plate.offset[1] = badge_dx
			widget.style.plate.offset[2] = badge_dy
			widget.style.count.offset[1] = badge_dx
			widget.style.count.offset[2] = badge_dy
			widget.dirty = true
		end
	end

	return badge_dx, badge_dy
end

local function hide_badges_from(index)
	for i = index, #badge_widgets do
		local widget = badge_widgets[i]
		if widget and widget.visible then
			widget.visible = false
			widget.dirty = true
		end
	end
end

local function tooltip_definition()
	local label_style = table.clone(UIFontSettings.body_small)
	label_style.horizontal_alignment = "center"
	label_style.vertical_alignment = "top"
	label_style.text_horizontal_alignment = "center"
	label_style.text_vertical_alignment = "center"
	label_style.size = {
		200,
		TOOLTIP.height,
	}
	label_style.offset = {
		0,
		0,
		3,
	}
	label_style.text_color = Color.terminal_text_header(255, true)

	return UIWidget.create_definition({
		{
			pass_type = "rect",
			style_id = "background",
			style = {
				horizontal_alignment = "center",
				vertical_alignment = "top",
				size = {
					200,
					TOOLTIP.height,
				},
				offset = {
					0,
					0,
					1,
				},
				color = Color.terminal_grid_background(240, true),
			},
		},
		{
			pass_type = "texture",
			style_id = "frame",
			value = "content/ui/materials/frames/frame_tile_2px",
			style = {
				horizontal_alignment = "center",
				vertical_alignment = "top",
				size = {
					200,
					TOOLTIP.height,
				},
				offset = {
					0,
					0,
					2,
				},
				color = Color.terminal_frame(255, true),
			},
		},
		{
			pass_type = "text",
			style_id = "label",
			value_id = "label",
			value = "",
			style = label_style,
		},
	}, "mission_area", nil, {
		0,
		0,
	})
end

local function ensure_tooltip(view)
	if tooltip_widget then
		return tooltip_widget
	end

	local widgets = view._widgets
	if not widgets then
		return nil
	end

	tooltip_widget = view:_create_widget("mmt_map_tooltip", tooltip_definition())
	tooltip_widget.offset[3] = TOOLTIP.z
	tooltip_widget.visible = false
	widgets[#widgets + 1] = tooltip_widget

	return tooltip_widget
end

local function cursor_over_panel()
	if not filter_ui.open or filter_ui.slide < 0.98 or not filter_ui.panel_widget then
		return false
	end

	local hotspot = filter_ui.panel_widget.content.panel_hotspot

	return hotspot ~= nil and hotspot.is_hover == true
end

local function hovered_card(view)
	if expanded_map or InputDevice.gamepad_active or cursor_over_panel() then
		return nil
	end

	for _, card in ipairs(view._mission_widgets or {}) do
		local content = card.content
		local hotspot = content and content.hotspot
		if content and content.mission and hotspot and hotspot.is_hover and not hotspot.disabled then
			return card
		end
	end

	return nil
end

local function tooltip_from_table()
	if not expanded_map or table_ui.row_count == 0 then
		return nil
	end

	for i = 1, table_ui.row_count do
		local widget = table_ui.widgets[i + 1]
		local labels = widget and widget.mmt_labels

		if labels then
			for j = 1, #TABLE_CELLS do
				local key = TABLE_CELLS[j]
				local hotspot = widget.content["cell_" .. key]

				if hotspot and hotspot.is_hover and labels[key] then
					return labels[key], table_ui.cell_cx[key] + table_ui.dx, widget.mmt_row_y + table_ui.dy, widget
				end
			end

			local slot_labels = widget.mmt_slot_labels

			if slot_labels then
				for j = 1, MTABLE.cond_slots do
					local hotspot = widget.content["slot_hotspot_" .. j]

					if hotspot and hotspot.is_hover and slot_labels[j] then
						return slot_labels[j], table_ui.slot_cx[j] + table_ui.dx, widget.mmt_row_y + table_ui.dy, widget
					end
				end
			end
		end
	end

	return nil
end

local function update_tooltip(view)
	local widget = ensure_tooltip(view)
	if not widget then
		return
	end

	local label, centre_x, top_y, owner = tooltip_from_table()
	local card

	if not label then
		card = hovered_card(view)

		if not card then
			widget.visible = false
			tooltip_card = nil
			return
		end

		label = map_display_name(card.content.mission.map)
		owner = card

	end

	if owner ~= tooltip_card or widget.content.label ~= label then
		tooltip_card = owner

		local ui_renderer = view._ui_renderer
		local text_width = ui_renderer and Text.text_size(ui_renderer, label, widget.style.label, TOOLTIP.bounds) or 160
		local width = text_width + TOOLTIP.pad * 2

		widget.content.label = label
		widget.style.background.size[1] = width
		widget.style.frame.size[1] = width
		widget.style.label.size[1] = width
		widget.mmt_width = width
	end

	local size = widget.content.size
	local above

	if card then
		widget.scale = card.scale
		size[1] = TILE_BOX_W
		size[2] = TILE_BOX_H
		widget.offset[1] = card.offset[1]
		widget.offset[2] = card.offset[2]
		above = (TILE_BOX_H - C.TILE_PLATE_H) * 0.5 - TOOLTIP.gap - TOOLTIP.height + TOOLTIP.card_dy
	else
		widget.scale = nil
		size[1] = 0
		size[2] = 0
		widget.offset[1] = centre_x
		widget.offset[2] = top_y - TOOLTIP.gap - TOOLTIP.height
		above = 0
	end

	widget.style.background.offset[2] = above
	widget.style.frame.offset[2] = above
	widget.style.label.offset[2] = above
	widget.visible = true
	widget.dirty = true
end

local function filter_color(key)
	if not filter_ui.colors then
		filter_ui.colors = {
			frame = Color.terminal_frame(255, true),
			frame_hover = Color.terminal_frame_hover(255, true),
			text_body = Color.terminal_text_body(255, true),
			text_header = Color.terminal_text_header(255, true),
		}
	end

	return filter_ui.colors[key]
end

local function side_display_name(key)
	if key == FILTER.side_none then
		return mod:localize("side_none")
	end

	local objectives = MissionObjectiveTemplates.side_mission and MissionObjectiveTemplates.side_mission.objectives
	local objective = objectives and objectives[key]

	if objective and objective.header then
		return Localize(objective.header)
	end

	return key
end

local function rebuild_filter_rows(logic)
	table.clear(filter_ui.rows)

	local mission_data = logic and logic._mission_data
	local page = logic and logic:get_current_page()
	local page_filter = page and page.filter and {
		page.filter,
	}

	if not mission_data or not page_filter then
		return ""
	end

	local seen_category = {}
	local seen_condition = {}
	local seen_side = {}
	local seen_expired = false

	for i = 1, #mission_data do
		local mission = mission_data[i]
		if logic:_mission_passes_all_filters(mission, page_filter) then
			if mission.category then
				seen_category[mission.category] = true
			end

			local conditions = conditions_for_circumstance(mission.circumstance)
			if conditions then
				for key in pairs(conditions) do
					seen_condition[key] = true
				end
			end

			local side = mission.side_mission or mission.sideMission
			if side then
				seen_side[side] = true
			end

			if not mission_is_live(mission) then
				seen_expired = true
			end
		end
	end

	local parts = {}

	local function add_group(title_key, entries)
		if #entries == 0 then
			return
		end

		filter_ui.rows[#filter_ui.rows + 1] = {
			kind = "group",
			label = mod:localize(title_key),
		}
		parts[#parts + 1] = title_key

		for i = 1, #entries do
			filter_ui.rows[#filter_ui.rows + 1] = entries[i]
			parts[#parts + 1] = entries[i].group .. "." .. entries[i].key
		end
	end

	local conditions = {}
	for i = 1, #FILTER_CONDITIONS do
		local entry = FILTER_CONDITIONS[i]
		if seen_condition[entry.key] then
			conditions[#conditions + 1] = {
				kind = "row",
				group = "condition",
				key = entry.key,
				label = mod:localize(entry.mod_loc),
			}
		end
	end

	if #conditions > 0 then
		add_group("filter_group_match", {
			{
				kind = "row",
				group = "match",
				key = "any",
				label = mod:localize("filter_match_any"),
			},
		})
	end

	local categories = {}
	for i = 1, #FILTER_CATEGORIES do
		local entry = FILTER_CATEGORIES[i]
		if seen_category[entry.key] then
			categories[#categories + 1] = {
				kind = "row",
				group = "category",
				key = entry.key,
				label = entry.game_loc and Localize(entry.game_loc) or mod:localize(entry.mod_loc),
			}
		end
	end
	add_group("filter_group_category", categories)

	add_group("filter_group_condition", conditions)

	local sides = {}
	local side_keys = {}
	for key in pairs(seen_side) do
		side_keys[#side_keys + 1] = key
	end
	table.sort(side_keys)
	for i = 1, #side_keys do
		sides[#sides + 1] = {
			kind = "row",
			group = "side",
			key = side_keys[i],
			label = side_display_name(side_keys[i]),
		}
	end
	if #sides < 1 then
		sides = {}
	end
	add_group("filter_group_side", sides)

	local state_rows = {}
	if seen_expired then
		state_rows[#state_rows + 1] = {
			kind = "row",
			group = "state",
			key = "expired",
			label = mod:localize("state_expired"),
		}
	end
	add_group("filter_group_state", state_rows)

	return table.concat(parts, ",")
end

local function filter_panel_height()
	local height = FILTER.header_height + FILTER.pad

	for i = 1, #filter_ui.rows do
		height = height + (filter_ui.rows[i].kind == "group" and FILTER.group_height or FILTER.row_height)
	end

	return height
end

local function filter_row_y(index)
	local y = FILTER.top + FILTER.header_height

	for i = 1, index - 1 do
		y = y + (filter_ui.rows[i].kind == "group" and FILTER.group_height or FILTER.row_height)
	end

	return y
end

local function filter_panel_definition(height)
	local title_style = table.clone(UIFontSettings.terminal_header_3)
	title_style.horizontal_alignment = "left"
	title_style.vertical_alignment = "top"
	title_style.text_horizontal_alignment = "left"
	title_style.text_vertical_alignment = "center"
	title_style.size = {
		FILTER.width - FILTER.pad * 2,
		34,
	}
	title_style.offset = {
		FILTER.pad,
		FILTER.top + 14,
		4,
	}
	title_style.text_color = Color.terminal_text_header(255, true)

	return UIWidget.create_definition({
		{
			pass_type = "rect",
			style_id = "background",
			style = {
				horizontal_alignment = "left",
				vertical_alignment = "top",
				size = {
					FILTER.width,
					height,
				},
				offset = {
					0,
					FILTER.top,
					1,
				},
				color = Color.black(178.5, true),
			},
		},
		{
			content_id = "header_hotspot",
			pass_type = "hotspot",
			style = {
				horizontal_alignment = "left",
				vertical_alignment = "top",
				size = {
					FILTER.width,
					FILTER.header_height,
				},
				offset = {
					0,
					FILTER.top,
					6,
				},
			},
		},
		{
			content_id = "panel_hotspot",
			pass_type = "hotspot",
			style = {
				horizontal_alignment = "left",
				vertical_alignment = "top",
				size = {
					FILTER.width,
					height,
				},
				offset = {
					0,
					FILTER.top,
					0,
				},
			},
		},
		{
			pass_type = "texture_uv",
			style_id = "terminal",
			value = "content/ui/materials/backgrounds/terminal_basic",
			style = {
				horizontal_alignment = "left",
				vertical_alignment = "top",
				scale_to_material = true,
				size = {
					FILTER.width,
					height,
				},
				offset = {
					0,
					FILTER.top,
					2,
				},
				uvs = {
					{
						0,
						0,
					},
					{
						1,
						1,
					},
				},
				color = Color.terminal_grid_background(255, true),
			},
		},
		{
			pass_type = "texture",
			style_id = "frame",
			value = "content/ui/materials/frames/frame_tile_2px",
			style = {
				horizontal_alignment = "left",
				vertical_alignment = "top",
				size = {
					FILTER.width,
					height,
				},
				offset = {
					0,
					FILTER.top,
					3,
				},
				color = Color.terminal_frame(255, true),
			},
		},
		{
			pass_type = "texture_uv",
			style_id = "divider",
			value = "content/ui/materials/dividers/horizontal_dynamic_lower",
			style = {
				horizontal_alignment = "left",
				vertical_alignment = "top",
				scale_to_material = true,
				size = {
					FILTER.width - FILTER.pad * 2,
					10,
				},
				offset = {
					FILTER.pad,
					FILTER.top + 48,
					4,
				},
				uvs = {
					{
						0,
						0,
					},
					{
						1,
						1,
					},
				},
			},
		},
		{
			pass_type = "texture",
			style_id = "divider_skull",
			value = "content/ui/materials/dividers/skull_rendered_center_02",
			style = {
				horizontal_alignment = "left",
				vertical_alignment = "top",
				scale_to_material = true,
				size = {
					140,
					18,
				},
				offset = {
					(FILTER.width - 140) * 0.5,
					FILTER.top + 44,
					5,
				},
			},
		},
		{
			pass_type = "text",
			style_id = "title",
			value_id = "title",
			value = "",
			style = title_style,
		},
	}, FILTER.anchor)
end

local function filter_group_definition(index)
	local label_style = table.clone(UIFontSettings.body_small)
	label_style.horizontal_alignment = "left"
	label_style.vertical_alignment = "top"
	label_style.text_horizontal_alignment = "left"
	label_style.text_vertical_alignment = "bottom"
	label_style.size = {
		FILTER.width - FILTER.pad * 2,
		FILTER.group_height,
	}
	label_style.offset = {
		FILTER.pad,
		filter_row_y(index),
		4,
	}
	label_style.text_color = Color.terminal_text_header(255, true)

	return UIWidget.create_definition({
		{
			pass_type = "text",
			style_id = "label",
			value_id = "label",
			value = "",
			style = label_style,
		},
	}, FILTER.anchor)
end

local function filter_row_definition(index)
	local row_y = filter_row_y(index)
	local box_y = row_y + (FILTER.row_height - FILTER.box_size) * 0.5
	local label_style = table.clone(UIFontSettings.body_small)
	label_style.horizontal_alignment = "left"
	label_style.vertical_alignment = "top"
	label_style.text_horizontal_alignment = "left"
	label_style.text_vertical_alignment = "center"
	label_style.size = {
		FILTER.width - FILTER.pad * 2 - FILTER.box_size - 14,
		FILTER.row_height,
	}
	label_style.offset = {
		FILTER.pad + FILTER.box_size + 14,
		row_y,
		4,
	}
	label_style.text_color = Color.terminal_text_body(255, true)

	return UIWidget.create_definition({
		{
			content_id = "hotspot",
			pass_type = "hotspot",
			style = {
				horizontal_alignment = "left",
				vertical_alignment = "top",
				size = {
					FILTER.width - FILTER.pad * 2,
					FILTER.row_height,
				},
				offset = {
					FILTER.pad,
					row_y,
					6,
				},
			},
		},
		{
			pass_type = "rect",
			style_id = "highlight",
			style = {
				horizontal_alignment = "left",
				vertical_alignment = "top",
				visible = false,
				size = {
					FILTER.width - FILTER.pad * 2,
					FILTER.row_height,
				},
				offset = {
					FILTER.pad,
					row_y,
					3,
				},
				color = Color.terminal_background_selected(140, true),
			},
		},
		{
			pass_type = "texture",
			style_id = "box",
			value = "content/ui/materials/frames/frame_tile_2px",
			style = {
				horizontal_alignment = "left",
				vertical_alignment = "top",
				size = {
					FILTER.box_size,
					FILTER.box_size,
				},
				offset = {
					FILTER.pad,
					box_y,
					4,
				},
				color = Color.terminal_frame(255, true),
			},
		},
		{
			pass_type = "rect",
			style_id = "tick",
			style = {
				horizontal_alignment = "left",
				vertical_alignment = "top",
				visible = false,
				size = {
					FILTER.box_size - 8,
					FILTER.box_size - 8,
				},
				offset = {
					FILTER.pad + 4,
					box_y + 4,
					5,
				},
				color = Color.terminal_text_header(255, true),
			},
		},
		{
			pass_type = "text",
			style_id = "label",
			value_id = "label",
			value = "",
			style = label_style,
		},
	}, FILTER.anchor)
end

local function filter_tab_definition()
	return UIWidget.create_definition({
		{
			content_id = "hotspot",
			pass_type = "hotspot",
			style = {
				horizontal_alignment = "left",
				vertical_alignment = "top",
				size = {
					FILTER.tab_width,
					FILTER.tab_height,
				},
				offset = {
					0,
					FILTER.top,
					6,
				},
			},
		},
		{
			pass_type = "rect",
			style_id = "background",
			style = {
				horizontal_alignment = "left",
				vertical_alignment = "top",
				size = {
					FILTER.tab_width,
					FILTER.tab_height,
				},
				offset = {
					0,
					FILTER.top,
					1,
				},
				color = Color.terminal_grid_background(240, true),
			},
		},
		{
			pass_type = "texture",
			style_id = "frame",
			value = "content/ui/materials/frames/frame_tile_2px",
			style = {
				horizontal_alignment = "left",
				vertical_alignment = "top",
				size = {
					FILTER.tab_width,
					FILTER.tab_height,
				},
				offset = {
					0,
					FILTER.top,
					2,
				},
				color = Color.terminal_frame(255, true),
			},
		},
		{
			pass_type = "texture",
			style_id = "icon",
			value = "content/ui/materials/icons/weapons/actions/activate",
			style = {
				horizontal_alignment = "left",
				vertical_alignment = "top",
				size = {
					FILTER.tab_icon,
					FILTER.tab_icon,
				},
				offset = {
					(FILTER.tab_width - FILTER.tab_icon) * 0.5,
					FILTER.top + (FILTER.tab_height - FILTER.tab_icon) * 0.5,
					4,
				},
				color = Color.terminal_text_header(255, true),
			},
		},
	}, FILTER.anchor)
end

local function destroy_filter_widgets(view)
	local widgets = view and view._widgets

	if widgets then
		for i = #widgets, 1, -1 do
			local widget = widgets[i]
			if widget.mmt_filter then
				table.remove(widgets, i)
				view:_unregister_widget_name(widget.name)
				UIWidget.destroy(view._ui_renderer, widget)
			end
		end
	end

	filter_ui.panel_widget = nil
	filter_ui.tab_widget = nil
	table.clear(filter_ui.row_widgets)
end

local function reset_filter_panel()
	filter_ui.panel_widget = nil
	filter_ui.tab_widget = nil
	filter_ui.signature = nil
	filter_ui.scan_page = nil
	filter_ui.open = false
	filter_ui.slide = 0
	table.clear(filter_ui.row_widgets)
end

local function category_icon(mission)
	local entry = MissionBoardViewSettings.mission_category_icons[mission.category]

	return entry and entry.mission_board_icon
end

local function category_label(mission)
	local entry = MissionBoardViewSettings.mission_category_icons[mission.category]

	if entry and entry.name then
		return Localize(entry.name)
	end

	return mod:localize("cat_common")
end

local function circumstance_ui(mission)
	local template = mission.circumstance and CircumstanceTemplates[mission.circumstance]

	return template and template.ui
end

local function circumstance_icon(mission)
	local ui = circumstance_ui(mission)

	return ui and (ui.mission_board_icon or ui.icon)
end

local function circumstance_label(mission)
	local ui = circumstance_ui(mission)

	if ui and ui.display_name then
		return Localize(ui.display_name)
	end

	return nil
end

local function side_icon(mission)
	return C.SIDE_ICONS[mission_side_key(mission)]
end

local function mission_time_state(mission)
	local past = minutes_past_expiry(mission)

	if not past then
		return nil, true, 0
	end

	if past <= 0 then
		local remaining = math.max(-past, 0)
		local start = tonumber(mission.start)
		local expiry = tonumber(mission.expiry)
		local lifetime = start and expiry and (expiry - start) / 60000 or HORIZON_MINUTES

		return math.floor(remaining), true, math.min(remaining / math.max(lifetime, 1), 1)
	end

	local left = math.max(HORIZON_MINUTES - past, 0)

	return math.floor(left), false, left / HORIZON_MINUTES
end

local function sort_by_time_left(a, b)
	local minutes_a, live_a = mission_time_state(a)
	local minutes_b, live_b = mission_time_state(b)

	if live_a ~= live_b then
		return live_a
	end

	minutes_a = minutes_a or 0
	minutes_b = minutes_b or 0

	if minutes_a ~= minutes_b then
		return minutes_a > minutes_b
	end

	return a.id < b.id
end

local function format_minutes(minutes)
	if not minutes then
		return "--"
	end

	if minutes >= 60 then
		return string.format("%dh %02dm", math.floor(minutes / 60), minutes % 60)
	end

	return string.format("%dm", minutes)
end

local function mission_table_height(row_count)
	return MTABLE.title_height + MTABLE.header_height + row_count * MTABLE.row_height + MTABLE.pad * 2
end

local function mission_table_origin(row_count)
	return C.GRID_CENTRE_X - MTABLE.width * 0.5, C.GRID_CENTRE_Y - mission_table_height(row_count) * 0.5
end

local function table_text_style(size_x, offset_x, offset_y, font, align)
	local style = table.clone(UIFontSettings[font])
	style.horizontal_alignment = "left"
	style.vertical_alignment = "top"
	style.text_horizontal_alignment = align or "left"
	style.text_vertical_alignment = "center"
	style.size = {
		size_x,
		MTABLE.row_height,
	}
	style.offset = {
		offset_x,
		offset_y,
		4,
	}

	return style
end

local function mission_table_definition(row_count)
	local height = mission_table_height(row_count)
	local origin_x, origin_y = mission_table_origin(row_count)
	local inner = MTABLE.width - MTABLE.pad * 2
	local header_y = origin_y + MTABLE.pad + MTABLE.title_height

	local title_style = table_text_style(inner, origin_x + MTABLE.pad, origin_y + MTABLE.pad, "terminal_header_3")
	title_style.size[2] = MTABLE.title_height
	title_style.text_color = Color.terminal_text_header(255, true)

	local passes = {
		{
			pass_type = "texture",
			style_id = "dropshadow",
			value = "content/ui/materials/frames/dropshadow_medium",
			style = {
				horizontal_alignment = "left",
				vertical_alignment = "top",
				size = {
					MTABLE.width + 40,
					height + 40,
				},
				offset = {
					origin_x - 20,
					origin_y - 20,
					0,
				},
				color = Color.black(200, true),
			},
		},
		{
			pass_type = "rect",
			style_id = "background",
			style = {
				horizontal_alignment = "left",
				vertical_alignment = "top",
				size = {
					MTABLE.width,
					height,
				},
				offset = {
					origin_x,
					origin_y,
					1,
				},
				color = Color.terminal_background(255, true),
			},
		},
		{
			pass_type = "texture_uv",
			style_id = "terminal",
			value = "content/ui/materials/backgrounds/terminal_basic",
			style = {
				horizontal_alignment = "left",
				vertical_alignment = "top",
				scale_to_material = true,
				size = {
					MTABLE.width,
					height,
				},
				offset = {
					origin_x,
					origin_y,
					2,
				},
				uvs = {
					{
						0,
						0,
					},
					{
						1,
						1,
					},
				},
				color = Color.terminal_grid_background(255, true),
			},
		},
		{
			pass_type = "rect",
			style_id = "header_band",
			style = {
				horizontal_alignment = "left",
				vertical_alignment = "top",
				size = {
					inner,
					MTABLE.header_height,
				},
				offset = {
					origin_x + MTABLE.pad,
					header_y,
					3,
				},
				color = Color.terminal_background_selected(180, true),
			},
		},
		{
			pass_type = "texture",
			style_id = "frame",
			value = "content/ui/materials/frames/frame_tile_2px",
			style = {
				horizontal_alignment = "left",
				vertical_alignment = "top",
				size = {
					MTABLE.width,
					height,
				},
				offset = {
					origin_x,
					origin_y,
					6,
				},
				color = Color.terminal_frame(255, true),
			},
		},
		{
			pass_type = "texture",
			style_id = "corners",
			value = "content/ui/materials/frames/frame_corner_2px",
			style = {
				horizontal_alignment = "left",
				vertical_alignment = "top",
				size = {
					MTABLE.width,
					height,
				},
				offset = {
					origin_x,
					origin_y,
					7,
				},
				color = Color.terminal_corner(255, true),
			},
		},
		{
			pass_type = "texture_uv",
			style_id = "edge_top",
			value = "content/ui/materials/dividers/horizontal_dynamic_upper",
			style = {
				horizontal_alignment = "left",
				vertical_alignment = "top",
				scale_to_material = true,
				size = {
					MTABLE.width,
					10,
				},
				offset = {
					origin_x,
					origin_y - 5,
					8,
				},
				uvs = {
					{
						0,
						0,
					},
					{
						1,
						1,
					},
				},
				color = Color.terminal_frame(255, true),
			},
		},
		{
			pass_type = "texture",
			style_id = "skull_top",
			value = "content/ui/materials/dividers/skull_rendered_center_01",
			style = {
				horizontal_alignment = "left",
				vertical_alignment = "top",
				size = {
					140,
					18,
				},
				offset = {
					origin_x + MTABLE.width * 0.5 - 70,
					origin_y - 12,
					9,
				},
				color = Color.terminal_frame(255, true),
			},
		},
		{
			pass_type = "texture_uv",
			style_id = "edge_bottom",
			value = "content/ui/materials/dividers/horizontal_dynamic_lower",
			style = {
				horizontal_alignment = "left",
				vertical_alignment = "top",
				scale_to_material = true,
				size = {
					MTABLE.width,
					10,
				},
				offset = {
					origin_x,
					origin_y + height - 5,
					8,
				},
				uvs = {
					{
						0,
						0,
					},
					{
						1,
						1,
					},
				},
				color = Color.terminal_frame(255, true),
			},
		},
		{
			pass_type = "texture",
			style_id = "skull_bottom",
			value = "content/ui/materials/dividers/skull_rendered_center_02",
			style = {
				horizontal_alignment = "left",
				vertical_alignment = "top",
				size = {
					306,
					48,
				},
				offset = {
					origin_x + MTABLE.width * 0.5 - 153,
					origin_y + height - 18,
					9,
				},
				color = Color.terminal_frame(255, true),
			},
		},
		{
			pass_type = "text",
			style_id = "title",
			value_id = "title",
			value = "",
			style = title_style,
		},
	}

	local headers = {
		{
			"header_time",
			MTABLE.col_bar,
			MTABLE.col_type - MTABLE.col_bar - 8,
			"left",
		},
		{
			"header_type",
			MTABLE.col_type,
			MTABLE.col_w.type,
			"center",
		},
		{
			"header_cond",
			MTABLE.col_cond,
			MTABLE.col_w.cond,
			"center",
		},
		{
			"header_side",
			MTABLE.col_side,
			MTABLE.col_w.side,
			"center",
		},
		{
			"header_conds",
			MTABLE.col_conds,
			inner - MTABLE.col_conds,
			"left",
		},
	}

	for i = 1, #headers do
		local id, offset_x, width, align = headers[i][1], headers[i][2], headers[i][3], headers[i][4]
		local style = table_text_style(width, origin_x + MTABLE.pad + offset_x, header_y, "body_small", align)
		style.size[2] = MTABLE.header_height
		style.text_color = Color.terminal_text_header(255, true)

		passes[#passes + 1] = {
			pass_type = "text",
			style_id = id,
			value_id = id,
			value = "",
			style = style,
		}
	end

	return UIWidget.create_definition(passes, "mission_area")
end

local function mission_table_row_definition(index, row_count)
	local origin_x, origin_y = mission_table_origin(row_count)
	local inner = MTABLE.width - MTABLE.pad * 2
	local row_y = origin_y + MTABLE.pad + MTABLE.title_height + MTABLE.header_height + (index - 1) * MTABLE.row_height
	local icon_y = row_y + (MTABLE.row_height - MTABLE.icon) * 0.5

	local bar_y = row_y + (MTABLE.row_height - MTABLE.bar_height) * 0.5
	local time_style = table_text_style(MTABLE.col_type - MTABLE.col_time - 8, origin_x + MTABLE.pad + MTABLE.col_time, row_y, "body_small")
	local cond_style = table_text_style(MTABLE.col_w.cond, origin_x + MTABLE.pad + MTABLE.col_cond, row_y, "body_small", "center")
	cond_style.text_color = Color.terminal_text_body(255, true)

	local passes = {
		{
			content_id = "hotspot",
			pass_type = "hotspot",
			style = {
				horizontal_alignment = "left",
				vertical_alignment = "top",
				size = {
					inner,
					MTABLE.row_height,
				},
				offset = {
					origin_x + MTABLE.pad,
					row_y,
					6,
				},
			},
		},
		{
			pass_type = "rect",
			style_id = "highlight",
			style = {
				horizontal_alignment = "left",
				vertical_alignment = "top",
				visible = false,
				size = {
					inner,
					MTABLE.row_height,
				},
				offset = {
					origin_x + MTABLE.pad,
					row_y,
					3,
				},
				color = Color.terminal_background_selected(150, true),
			},
		},
		{
			pass_type = "rect",
			style_id = "bar_bg",
			style = {
				horizontal_alignment = "left",
				vertical_alignment = "top",
				size = {
					MTABLE.bar_width,
					MTABLE.bar_height,
				},
				offset = {
					origin_x + MTABLE.pad + MTABLE.col_bar,
					bar_y,
					3,
				},
				color = Color.black(160, true),
			},
		},
		{
			pass_type = "rect",
			style_id = "bar_fill",
			style = {
				horizontal_alignment = "left",
				vertical_alignment = "top",
				size = {
					MTABLE.bar_width,
					MTABLE.bar_height,
				},
				offset = {
					origin_x + MTABLE.pad + MTABLE.col_bar,
					bar_y,
					4,
				},
				color = Color.terminal_text_header(255, true),
			},
		},
		{
			pass_type = "texture",
			style_id = "bar_frame",
			value = "content/ui/materials/frames/frame_tile_2px",
			style = {
				horizontal_alignment = "left",
				vertical_alignment = "top",
				size = {
					MTABLE.bar_width,
					MTABLE.bar_height,
				},
				offset = {
					origin_x + MTABLE.pad + MTABLE.col_bar,
					bar_y,
					5,
				},
				color = Color.terminal_frame(255, true),
			},
		},
		{
			pass_type = "text",
			style_id = "time",
			value_id = "time",
			value = "",
			style = time_style,
		},
		{
			pass_type = "text",
			style_id = "cond_text",
			value_id = "cond_text",
			value = "",
			style = cond_style,
		},

	}

	for i = 1, #TABLE_CELLS do
		local key = TABLE_CELLS[i]
		local offset_x = MTABLE["col_" .. key]

		passes[#passes + 1] = {
			content_id = "cell_" .. key,
			pass_type = "hotspot",
			style = {
				horizontal_alignment = "left",
				vertical_alignment = "top",
				size = {
					MTABLE.col_w[key],
					MTABLE.row_height,
				},
				offset = {
					origin_x + MTABLE.pad + offset_x,
					row_y,
					7,
				},
			},
		}
	end

	local green = {
		255,
		101,
		145,
		102,
	}
	local icons = {
		{
			"type_icon",
			MTABLE.col_type,
			MTABLE.col_w.type,
		},
		{
			"cond_icon",
			MTABLE.col_cond,
			MTABLE.col_w.cond,
		},
		{
			"side_icon",
			MTABLE.col_side,
			MTABLE.col_w.side,
		},
		{
			"saved_icon",
			MTABLE.col_saved,
			MTABLE.col_w.saved,
		},
	}

	for i = 1, MTABLE.cond_slots do
		local slot_x = origin_x + MTABLE.pad + MTABLE.col_conds + (i - 1) * MTABLE.cond_slot
		local tag_style = table_text_style(MTABLE.cond_slot, slot_x, row_y, "body_small", "center")
		tag_style.visible = false
		tag_style.text_color = Color.terminal_text_header(255, true)

		passes[#passes + 1] = {
			content_id = "slot_hotspot_" .. i,
			style_id = "slot_hotspot_" .. i,
			pass_type = "hotspot",
			style = {
				horizontal_alignment = "left",
				vertical_alignment = "top",
				size = {
					MTABLE.cond_slot,
					MTABLE.row_height,
				},
				offset = {
					slot_x,
					row_y,
					7,
				},
			},
		}

		passes[#passes + 1] = {
			pass_type = "texture",
			style_id = "cond_slot_" .. i,
			value_id = "cond_slot_" .. i,
			value = "content/ui/materials/icons/mission_types_pj/mission_type_undefined",
			style = {
				horizontal_alignment = "left",
				vertical_alignment = "top",
				visible = false,
				size = {
					MTABLE.icon,
					MTABLE.icon,
				},
				offset = {
					slot_x + (MTABLE.cond_slot - MTABLE.icon) * 0.5,
					icon_y,
					4,
				},
				color = Color.white(255, true),
			},
		}

		passes[#passes + 1] = {
			pass_type = "text",
			style_id = "cond_tag_" .. i,
			value_id = "cond_tag_" .. i,
			value = "",
			style = tag_style,
		}
	end

	for i = 1, #icons do
		local id, offset_x, col_width = icons[i][1], icons[i][2], icons[i][3]
		local tint = id == "cond_icon" and green or Color.terminal_text_header(255, true)

		passes[#passes + 1] = {
			pass_type = "texture",
			style_id = id,
			value_id = id,
			value = "content/ui/materials/icons/mission_types_pj/mission_type_undefined",
			style = {
				horizontal_alignment = "left",
				vertical_alignment = "top",
				visible = false,
				size = {
					MTABLE.icon,
					MTABLE.icon,
				},
				offset = {
					origin_x + MTABLE.pad + offset_x + (col_width - MTABLE.icon) * 0.5,
					icon_y,
					4,
				},
				color = tint,
			},
		}
	end

	return UIWidget.create_definition(passes, "mission_area")
end

local function destroy_mission_table(view)
	local widgets = view and view._widgets

	if widgets then
		for i = #widgets, 1, -1 do
			local widget = widgets[i]
			if widget.mmt_table then
				table.remove(widgets, i)
				view:_unregister_widget_name(widget.name)
				UIWidget.destroy(view._ui_renderer, widget)
			end
		end
	end

	table.clear(table_ui.widgets)
	table.clear(table_ui.rows)
	table_ui.row_count = 0
	table_ui.source_count = 0
	next_expiry_scan = 0

	if scrim_widget then
		layout_scrim_bands(scrim_widget)
	end
end

local function set_icon_cell(widget, style_id, value_id, material)
	local style = widget.style[style_id]

	if not style then
		return
	end

	if material then
		widget.content[value_id] = material
		style.visible = true
	else
		style.visible = false
	end
end

local function build_mission_table(view, map)
	refresh_saved_ids()
	destroy_mission_table(view)

	local list = map_missions[map]
	if not list then
		return
	end

	for i = 1, #list do
		table_ui.rows[i] = list[i]
	end

	table.sort(table_ui.rows, sort_by_time_left)

	while #table_ui.rows > MTABLE.max_rows do
		table.remove(table_ui.rows)
	end

	table_ui.source_count = #list
	table_ui.row_count = #table_ui.rows
	if table_ui.row_count == 0 then
		return
	end

	local widgets = view._widgets
	local panel = view:_create_widget("mmt_table_panel", mission_table_definition(table_ui.row_count))
	panel.mmt_table = true
	panel.offset[1] = table_ui.dx
	panel.offset[2] = table_ui.dy
	panel.offset[3] = MTABLE.z
	panel.content.title = map_display_name(map)
	panel.content.header_time = mod:localize("col_time")
	panel.content.header_type = mod:localize("col_type")
	panel.content.header_cond = mod:localize("col_cond")
	panel.content.header_side = mod:localize("col_side")
	panel.content.header_conds = mod:localize("col_conds")
	table_ui.widgets[#table_ui.widgets + 1] = panel
	widgets[#widgets + 1] = panel

	local origin_x, origin_y = mission_table_origin(table_ui.row_count)
	for i = 1, #TABLE_CELLS do
		local key = TABLE_CELLS[i]
		table_ui.cell_cx[key] = origin_x + MTABLE.pad + MTABLE["col_" .. key] + MTABLE.col_w[key] * 0.5
	end

	for i = 1, MTABLE.cond_slots do
		table_ui.slot_cx[i] = origin_x + MTABLE.pad + MTABLE.col_conds + (i - 1) * MTABLE.cond_slot + MTABLE.cond_slot * 0.5
	end

	if scrim_widget then
		local hole_x, hole_y = mission_table_origin(table_ui.row_count)
		layout_scrim_bands(scrim_widget, hole_x + table_ui.dx, hole_y + table_ui.dy, MTABLE.width, mission_table_height(table_ui.row_count))
	end

	for i = 1, table_ui.row_count do
		local mission = table_ui.rows[i]
		local widget = view:_create_widget("mmt_table_row_" .. i, mission_table_row_definition(i, table_ui.row_count))
		widget.mmt_table = true
		widget.mmt_mission = mission
		widget.offset[1] = table_ui.dx
		widget.offset[2] = table_ui.dy
		widget.offset[3] = MTABLE.z

		local keys = conditions_for_circumstance(mission.circumstance)
		local slot = 0

		widget.mmt_slot_labels = {}

		if keys then
			for c = 1, #FILTER_CONDITIONS do
				local key = FILTER_CONDITIONS[c].key
				if keys[key] and slot < MTABLE.cond_slots then
					slot = slot + 1
					widget.mmt_slot_labels[slot] = mod:localize(FILTER_CONDITIONS[c].mod_loc)
					local icon = C.CONDITION_ICONS[key]
					if icon then
						widget.content["cond_slot_" .. slot] = icon
						widget.style["cond_slot_" .. slot].visible = true
					else
						widget.content["cond_tag_" .. slot] = C.CONDITION_TAGS[key] or "?"
						widget.style["cond_tag_" .. slot].visible = true
					end
				end
			end
		end
		set_icon_cell(widget, "type_icon", "type_icon", category_icon(mission))
		set_icon_cell(widget, "side_icon", "side_icon", side_icon(mission))
		set_icon_cell(widget, "saved_icon", "saved_icon", saved_ids[mission.id] and C.BOOKMARK_ICON or nil)

		local cond_material = circumstance_icon(mission)
		set_icon_cell(widget, "cond_icon", "cond_icon", cond_material)
		if not cond_material then
			local label = circumstance_label(mission)
			widget.content.cond_text = label and string.sub(label, 1, 3) or ""
		else
			widget.content.cond_text = ""
		end

		widget.mmt_row_y = origin_y + MTABLE.pad + MTABLE.title_height + MTABLE.header_height + (i - 1) * MTABLE.row_height
		widget.mmt_labels = {
			type = category_label(mission),
			cond = circumstance_label(mission),
			side = side_display_name(mission_side_key(mission)),
			saved = saved_ids[mission.id] and mod:localize("tip_saved") or nil,
		}

		widget.content.hotspot.pressed_callback = function ()
			view:set_selected_mission(mission.id)
		end

		table_ui.widgets[#table_ui.widgets + 1] = widget
		widgets[#widgets + 1] = widget
	end
end

mod.mmt_tune_table = function (dx, dy)
	table_ui.dx = dx or table_ui.dx
	table_ui.dy = dy or table_ui.dy

	for i = 1, #table_ui.widgets do
		local widget = table_ui.widgets[i]
		widget.offset[1] = table_ui.dx
		widget.offset[2] = table_ui.dy
		widget.dirty = true
	end

	if scrim_widget and table_ui.row_count > 0 then
		local hole_x, hole_y = mission_table_origin(table_ui.row_count)
		layout_scrim_bands(scrim_widget, hole_x + table_ui.dx, hole_y + table_ui.dy, MTABLE.width, mission_table_height(table_ui.row_count))
	end

	return table_ui.dx, table_ui.dy
end

local function update_mission_table(view)
	if table_ui.row_count == 0 then
		return
	end

	if expanded_map then
		local list = map_missions[expanded_map]
		if list and #list ~= table_ui.source_count then
			build_mission_table(view, expanded_map)
			return
		end
	end

	local selected = view._selected_mission_id

	for i = 1, table_ui.row_count do
		local widget = table_ui.widgets[i + 1]
		local mission = widget and widget.mmt_mission

		if mission then
			local minutes, live, ratio = mission_time_state(mission)

			if widget.mmt_minutes ~= minutes then
				widget.mmt_minutes = minutes
				widget.content.time = format_minutes(minutes)

				widget.style.bar_fill.color = table.clone(live and C.LIVE_BAR_COLOR or EXPIRED_BAR_COLOR)
				widget.style.time.text_color = live and Color.terminal_text_body(255, true) or table.clone(EXPIRED_BAR_COLOR)
				widget.style.bar_fill.size[1] = math.max(MTABLE.bar_width * (ratio or 0), 2)
				widget.dirty = true
			end

			local hot = widget.content.hotspot.is_hover or mission.id == selected
			if widget.style.highlight.visible ~= hot then
				widget.style.highlight.visible = hot
				widget.dirty = true
			end
		end
	end
end

local function set_card_input(widget, blocked)
	local hotspot = widget.content.hotspot
	if not hotspot then
		return
	end

	if blocked then
		if not widget.mmt_input_blocked then
			widget.mmt_input_blocked = true
			widget.mmt_input_was = hotspot.disabled
			hotspot.disabled = true
		end
	elseif widget.mmt_input_blocked then
		widget.mmt_input_blocked = nil
		hotspot.disabled = widget.mmt_input_was
		widget.mmt_input_was = nil
	end
end

local function render_cards(view)
	local badge_index = 0
	local scrim = ensure_scrim(view)
	if scrim then
		scrim.visible = expanded_map ~= nil and not InputDevice.gamepad_active
	end

	for _, widget in ipairs(view._mission_widgets or {}) do
		local content = widget.content
		local mission = content and content.mission

		if mission and widget.mmt_baseline then
			local role = mission_is_live(mission) and "live" or "expired"

			if not widget.mmt_faded and widget.mmt_role ~= role then
				widget.mmt_role = role
				style_card(view, widget, mission)
				widget.dirty = true
			end

			local slot = slot_for_mission[mission.id]
			if slot and (widget.offset[1] ~= slot.position[1] or widget.offset[2] ~= slot.position[2]) then
				widget.offset[1] = slot.position[1]
				widget.offset[2] = slot.position[2]
				widget.dirty = true
			end

			set_card_input(widget, expanded_map ~= nil)

			if expanded_map and not widget.mmt_faded then
				widget.mmt_faded = true
				fade_widget(widget)
			end

			if not expanded_map and widget.visible ~= false then
				local options = map_missions[mission.map]
				local count = options and #options or 1
				if count > 1 then
					badge_index = badge_index + 1
					place_badge(view, badge_index, widget, count)
				end
			end
		end
	end

	hide_badges_from(badge_index + 1)
	update_mission_table(view)
	update_tooltip(view)
end

local function expand_map(view, map)
	local options = map_missions[map]
	if not options or #options < 2 then
		return false
	end

	expanded_map = map
	table.clear(expanded_ids)

	local filtered = view._mission_board_logic and view._mission_board_logic._filtered_missions
	for i = 1, #options do
		local mission = options[i]
		expanded_ids[mission.id] = true
		if filtered then
			filtered[mission.id] = mission
		end
	end

	build_mission_table(view, map)
	layout_dirty = true

	return true
end

local function collapse_expanded(view)
	if not expanded_map then
		return false
	end

	local list = map_missions[expanded_map]
	expanded_map = nil

	local filtered = view and view._mission_board_logic and view._mission_board_logic._filtered_missions
	if filtered and list then
		for i = 1, #list do
			local mission = list[i]
			if not tile_ids[mission.id] then
				filtered[mission.id] = nil
			end
		end
	end

	destroy_mission_table(view)
	restore_faded_widgets()

	if view then
		for _, widget in ipairs(view._mission_widgets or {}) do
			widget.mmt_faded = nil
		end
	end

	table.clear(expanded_ids)
	layout_dirty = true

	return true
end

local function toggle_filter(view, group, key)
	set_filter(group, key, not filter_enabled(group, key))

	collapse_expanded(view)

	local selected = view._selected_mission_id
	local mission = selected and mission_by_id[selected]
	if mission and not mission_passes_filters(mission) then
		view:_clear_selected()
	end

	view:_open_current_page()
end

local function resolve_scrim_press(view)
	if scrim_pressed then
		scrim_pressed = false
		if expanded_map and not expand_card_pressed then
			pending_collapse = true
		end
	end
	expand_card_pressed = false

	if pending_collapse then
		pending_collapse = false
		collapse_expanded(view)
	end

	if pending_filter_group then
		local group, key = pending_filter_group, pending_filter_key
		pending_filter_group, pending_filter_key = nil, nil
		toggle_filter(view, group, key)
	end
end

local function create_filter_widgets(view)
	local widgets = view._widgets
	local title = mod:localize("filter_title")

	filter_ui.panel_widget = view:_create_widget("mmt_filter_panel", filter_panel_definition(filter_panel_height()))
	filter_ui.panel_widget.mmt_filter = true
	filter_ui.panel_widget.offset[3] = FILTER.z
	filter_ui.panel_widget.content.title = title
	filter_ui.panel_widget.content.header_hotspot.pressed_callback = function ()
		set_filter_open(view, false)
	end
	widgets[#widgets + 1] = filter_ui.panel_widget

	for i = 1, #filter_ui.rows do
		local row = filter_ui.rows[i]
		local widget

		if row.kind == "group" then
			widget = view:_create_widget("mmt_filter_group_" .. i, filter_group_definition(i))
		else
			widget = view:_create_widget("mmt_filter_row_" .. i, filter_row_definition(i))
			widget.content.hotspot.pressed_callback = function ()
				pending_filter_group = row.group
				pending_filter_key = row.key
			end
		end

		widget.mmt_filter = true
		widget.mmt_row = row
		widget.offset[3] = FILTER.z
		widget.content.label = row.label
		filter_ui.row_widgets[#filter_ui.row_widgets + 1] = widget
		widgets[#widgets + 1] = widget
	end

	filter_ui.tab_widget = view:_create_widget("mmt_filter_tab", filter_tab_definition())
	filter_ui.tab_widget.mmt_filter = true
	filter_ui.tab_widget.offset[3] = FILTER.z
	filter_ui.tab_widget.content.hotspot.pressed_callback = function ()
		set_filter_open(view, not filter_ui.open)
	end
	widgets[#widgets + 1] = filter_ui.tab_widget
end

local function relayout_cards(view)
	local widgets = view and view._mission_widgets

	if not widgets then
		return
	end

	for i = 1, #widgets do
		local widget = widgets[i]
		local slot = widget and widget.mmt_slot

		if slot and widget.offset then
			widget.offset[1] = slot.position[1]
			widget.offset[2] = slot.position[2]
			widget.scale = LAYOUT.scale
			widget.dirty = true
		end
	end
end

set_filter_open = function (view, open)
	filter_ui.open = open
	mod:set("_filter_open", open, false)
	LAYOUT.applied_intrusion = nil
end

local function filter_panel_visible(view)
	if view._mission_board_options or view._is_loading then
		return false
	end

	local mission_list = view:_element("mission_list")
	if mission_list and mission_list:visible() then
		return false
	end

	return true
end

local function update_filter_panel(view, dt)
	if not show_all_missions then
		if filter_ui.panel_widget then
			destroy_filter_widgets(view)
			filter_ui.signature = nil
			filter_ui.scan_page = nil
		end
		return
	end

	local logic = view._mission_board_logic
	local mission_data = logic and logic._mission_data
	local page_index = logic and logic._page_index or 0
	local mission_count = mission_data and #mission_data or 0

	if filter_ui.scan_dirty or page_index ~= filter_ui.scan_page then
		filter_ui.scan_dirty = false
		filter_ui.scan_page = page_index

		local signature = rebuild_filter_rows(logic)
		if signature ~= filter_ui.signature then
			filter_ui.signature = signature
			destroy_filter_widgets(view)
			if signature ~= "" then
				create_filter_widgets(view)
			end
		end
	end

	if not filter_ui.panel_widget then
		return
	end

	local target = filter_ui.open and 1 or 0
	if filter_ui.slide ~= target then
		filter_ui.slide = filter_ui.slide + (target - filter_ui.slide) * math.min(dt * FILTER.slide_rate, 1)
		if math.abs(target - filter_ui.slide) < 0.002 then
			filter_ui.slide = target
		end
	end

	local x = (filter_ui.slide - 1) * FILTER.width
	local visible = filter_panel_visible(view)

	filter_ui.panel_widget.offset[1] = x
	filter_ui.panel_widget.visible = visible

	local header = filter_ui.panel_widget.content.header_hotspot
	filter_ui.panel_widget.style.title.text_color = filter_color(header and header.is_hover and "frame_hover" or "text_header")
	filter_ui.panel_widget.dirty = true

	filter_ui.tab_widget.offset[1] = x + FILTER.width
	filter_ui.tab_widget.visible = visible and filter_ui.slide < 0.98
	filter_ui.tab_widget.dirty = true

	if filter_ui.tab_widget.content.hotspot.is_hover then
		filter_ui.tab_widget.style.frame.color = filter_color("frame_hover")
		filter_ui.tab_widget.style.icon.color = filter_color("frame_hover")
	else
		filter_ui.tab_widget.style.frame.color = filter_color("frame")
		filter_ui.tab_widget.style.icon.color = filter_color("text_header")
	end

	for i = 1, #filter_ui.row_widgets do
		local widget = filter_ui.row_widgets[i]
		local row = widget.mmt_row

		widget.offset[1] = x
		widget.visible = visible and filter_ui.slide > 0.02
		widget.dirty = true

		if row.kind == "row" then
			local style = widget.style
			local is_hover = widget.content.hotspot.is_hover == true

			style.tick.visible = filter_enabled(row.group, row.key)
			style.highlight.visible = is_hover

			if is_hover then
				style.label.text_color = filter_color("text_header")
				style.box.color = filter_color("frame_hover")
			else
				style.label.text_color = filter_color("text_body")
				style.box.color = filter_color("frame")
			end
		end
	end
end

mod.mmt_missions_for_map = function (map)
	return map_missions[map]
end

mod.mmterm_is_tile_mission = function (mission_id)
	return tile_ids[mission_id] == true
end

local MMT_INPUT_ACTIONS = {
	"mmterm_filter_board",
}

local function update_input_alias()
	if Managers.input and Managers.input._aliases and Managers.input._aliases.View then
		for i = 1, #MMT_INPUT_ACTIONS do
			local action = MMT_INPUT_ACTIONS[i]
			Managers.input._aliases.View._aliases[action] = Managers.input._aliases.View._default_aliases[action]
		end
	end
end

mod:hook_require("scripts/settings/input/default_view_input_settings", function (DefaultViewInputSettings)
	DefaultViewInputSettings.aliases.mmterm_filter_board = {
		"keyboard_f",
		"xbox_controller_left_trigger",
		"ps4_controller_l2",
		description = "",
		bindable = false,
	}
	DefaultViewInputSettings.settings.mmterm_filter_board = {
		key_alias = "mmterm_filter_board",
		type = "pressed",
	}
	update_input_alias()
end)

mod.on_all_mods_loaded = function ()
	mod:info(mod.version)

	refresh_settings()
	update_input_alias()
	apply_grid_slots(show_all_missions)
end

local function warn_incompatible_mods()
	if incompatible_warned or not show_all_missions then
		return
	end
	incompatible_warned = true

	for _, name in ipairs(C.INCOMPATIBLE_MODS) do
		local other = get_mod(name)
		if other and other:is_enabled() then
			mod:notify(string.gsub(mod:localize("msg_incompatible_mod"), "#", name))
		end
	end
end

mod.on_setting_changed = function (setting_id)
	refresh_settings()

	if setting_id == "show_all_missions" then
		if board_is_open() then
			mod:notify(mod:localize("msg_reopen_board"))
			return
		end
		apply_grid_slots(show_all_missions)
	end
end

local MMT_LEGEND_INPUTS = {
	{
		on_pressed_callback = "__mod_mmterm_filter_callback",
		input_action = "mmterm_filter_board",
		display_name = "loc_mod_mmterm_filter",
		alignment = "left_alignment",
		visibility_function = function (mission_board_view)
			return show_all_missions == true and not mission_board_view._mission_board_options
		end
	},
}

mod.on_enabled = function ()
	refresh_settings()
	apply_grid_slots(show_all_missions)

	local legend_inputs = MissionBoardViewSettings.view_elements.input_legend.context.legend_inputs
	for i = 1, #MMT_LEGEND_INPUTS do
		local entry = MMT_LEGEND_INPUTS[i]
		local exist = false
		for _, value in ipairs(legend_inputs) do
			if value.input_action == entry.input_action then
				exist = true
				break
			end
		end
		if not exist then
			table.insert(legend_inputs, entry)
		end
	end
end

mod.on_disabled = function ()
	table.array_remove_if(MissionBoardViewSettings.view_elements.input_legend.context.legend_inputs, function (v)
		return v.input_action == "mmterm_filter_board"
	end)
	if not board_is_open() then
		apply_grid_slots(false)
	end
end

mod:hook(CLASS.MissionBoardViewLogic, "_should_show_mission", function (func, self, mission)
	if show_all_missions and not mission_passes_filters(mission) then
		return false
	end
	if func(self, mission) then
		return true
	end
	if not show_all_missions then
		return false
	end
	if mission.category ~= "story" then
		return false
	end
	if mission.circumstance and not CircumstanceTemplates[mission.circumstance] then
		return false
	end
	return self:_is_story_mission_complete(mission) == true
end)

mod:hook(CLASS.MissionBoardViewLogic, "_remove_unwanted_missions", function (func, self, missions)
	if not show_all_missions then
		return func(self, missions)
	end
	self._filtered_missions = missions
end)

mod:hook_safe(CLASS.MissionBoardViewLogic, "refresh_filtered_missions", function (self)
	if not show_all_missions then
		return
	end
	refresh_now()
	rebuild_map_missions(self)
	filter_ui.scan_dirty = true
	layout_dirty = true
end)

mod:hook_safe(CLASS.MissionBoardViewLogic, "update", function (self, dt, t)
	if not show_all_missions or not use_archive then
		return
	end

	Archive.fetch(self)

	if not self._mission_data then
		return
	end

	local now = t or Managers.time:time("main")
	if now >= next_expiry_scan then
		next_expiry_scan = now + 5
		if convert_expired_missions(self, now) then
			self:refresh_filtered_missions()
		end
	end

	if Archive.inject(self, t or Managers.time:time("main")) then
		self:refresh_filtered_missions()
	end
end)

mod:hook(CLASS.MissionBoardView, "_update_mission_widgets", function (func, self, t)
	if not show_all_missions then
		return func(self, t)
	end

	resolve_scrim_press(self)

	if layout_dirty then
		layout_dirty = false
		warn_incompatible_mods()
		layout_tiles(self, t)
	end

	local result = func(self, t)

	render_cards(self)

	return result
end)

mod:hook_safe(CLASS.MissionBoardView, "update", function (self, dt)
	refresh_now()

	if show_all_missions then
		local intrusion = panel_intrusion(self)

		if intrusion ~= LAYOUT.applied_intrusion or filter_ui.open ~= LAYOUT.applied_open then
			if compute_grid_layout(self) then
				LAYOUT.applied_intrusion = intrusion
				LAYOUT.applied_open = filter_ui.open
				apply_grid_slots(show_all_missions)
				relayout_cards(self)
			end
		end

		update_filter_panel(self, dt)
	end
end)

mod:hook_safe(CLASS.MissionBoardView, "on_exit", function ()
	reset_filter_panel()
end)

mod:hook(CLASS.MissionBoardView, "_set_selected", function (func, self, id, ...)
	if not show_all_missions then
		return func(self, id, ...)
	end

	if cursor_over_panel() then
		return
	end

	if id and expanded_ids[id] then
		expand_card_pressed = true
	end

	if expanded_map and (not id or not expanded_ids[id]) then
		pending_collapse = true
	end

	if id and id ~= "qp_mission_widget" and not expanded_ids[id] then
		local mission = mission_by_id[id]
		local map = mission and mission.map
		local options = map and map_missions[map]
		if options and #options > 1 then
			expand_map(self, map)
		end
	end

	if id and expanded_ids[id] and not self._widgets_by_name[id] then
		local mission = mission_by_id[id]
		local list = mission and map_missions[mission.map]
		local representative = list and list[1]
		local widget = representative and self._widgets_by_name[representative.id]
		local slot = widget and widget.content.slot

		if slot then
			self._target_zoom = slot.zoom or self._target_zoom
			self._target_rotation = slot.rotation or self._target_rotation
		end
	end

	return func(self, id, ...)
end)

mod:hook(CLASS.MissionBoardView, "_on_back_pressed", function (func, self, ...)
	if expanded_map then
		collapse_expanded(self)
		return
	end
	return func(self, ...)
end)

mod:hook(CLASS.MissionBoardView, "_create_mission_widget_from_mission", function (func, self, mission, blueprint_name, slot)
	if not show_all_missions then
		return func(self, mission, blueprint_name, slot)
	end

	local widget = func(self, mission, blueprint_name, slot)
	if widget then
		capture_card_baseline(widget)

		local override = slot_for_mission[mission.id]
		if override and widget.offset then
			widget.mmt_slot = override
			widget.offset[1] = override.position[1]
			widget.offset[2] = override.position[2]
		end
	end
	return widget
end)

mod:hook(CLASS.MissionBoardView, "_clear_selected", function (func, self)
	local selected = self._selected_mission_id
	if expanded_map and selected and expanded_ids[selected] then
		return
	end
	return func(self)
end)

mod:hook(CLASS.MissionBoardView, "_mission", function (func, self, mission_id, ignore_filter)
	return func(self, mission_id, ignore_filter) or mission_by_id[mission_id]
end)

mod:hook(CLASS.MissionBoardView, "_remove_mission_widget", function (func, self, widget)
	local mission_widgets = self._mission_widgets
	if not widget or not mission_widgets or table.index_of(mission_widgets, widget) < 1 then
		return
	end

	for i = #faded_widgets, 1, -1 do
		if faded_widgets[i].widget == widget then
			table.remove(faded_widgets, i)
		end
	end

	if widget == scrim_widget then
		scrim_widget = nil
	end

	return func(self, widget)
end)

mod:hook(CLASS.MissionBoardView, "_release_slot", function (func, self, slot)
	local used_slots = self._used_slots
	local slot_group = slot and slot.group
	if used_slots and slot_group and not used_slots[slot_group] then
		used_slots[slot_group] = {}
	end
	return func(self, slot)
end)

mod:hook(CLASS.MissionBoardView, "_add_mission_widget", function (func, self, mission)
	if not show_all_missions then
		return func(self, mission)
	end
	if not tile_ids[mission.id] then
		return
	end
	return func(self, mission)
end)

mod:hook_safe("MissionBoardView", "init", function (self, settings)
	expanded_map = nil
	scrim_widget = nil
	scrim_pressed = false
	expand_card_pressed = false
	tooltip_widget = nil
	tooltip_card = nil
	table.clear(badge_widgets)
	table.clear(table_ui.widgets)
	table.clear(table_ui.rows)
	table_ui.row_count = 0
	table.clear(expanded_ids)
	table.clear(faded_widgets)
	reset_filter_panel()

	filter_ui.open = mod:get("_filter_open") == true
	filter_ui.slide = filter_ui.open and 1 or 0
	LAYOUT.applied_intrusion = nil
	LAYOUT.applied_open = nil

	self.__mod_mmterm_filter_callback = function ()
		set_filter_open(self, not filter_ui.open)
	end
end)
