--[[
Name: Many Mission Terminal
Author: Wobin
Date: 19/08/2026
Repository: https://github.com/Wobin/ManyMissionTerminal
--]]

local mod = get_mod("Many Mission Terminal")
mod.version = mod.get_metadata and mod:get_metadata("version") or "unknown"

local MMT = get_mod("ManyMoreTry")
local MissionBoardViewSettings = require("scripts/ui/views/mission_board_view/mission_board_view_settings")
local CircumstanceTemplates = require("scripts/settings/circumstance/circumstance_templates")
local MissionTemplates = require("scripts/settings/mission/mission_templates")
local ScrollbarPassTemplates = require("scripts/ui/pass_templates/scrollbar_pass_templates")
local MissionObjectiveTemplates = require("scripts/settings/mission_objective/mission_objective_templates")
local Text = require("scripts/utilities/ui/text")
local UIWidget = require("scripts/managers/ui/ui_widget")
local UIFontSettings = require("scripts/managers/ui/ui_font_settings")
local InputDevice = require("scripts/managers/input/input_device")

local C = mod:io_dofile("Many Mission Terminal/scripts/mods/Many Mission Terminal/modules/constants")
local Missions = mod:io_dofile("Many Mission Terminal/scripts/mods/Many Mission Terminal/modules/missions/core")
local Archive = mod:io_dofile("Many Mission Terminal/scripts/mods/Many Mission Terminal/modules/archive")
local Intercept = mod:io_dofile("Many Mission Terminal/scripts/mods/Many Mission Terminal/modules/intercept")
local Filters = mod:io_dofile("Many Mission Terminal/scripts/mods/Many Mission Terminal/modules/filters/core")
local FilterRows = mod:io_dofile("Many Mission Terminal/scripts/mods/Many Mission Terminal/modules/filters/rows")
local Table = mod:io_dofile("Many Mission Terminal/scripts/mods/Many Mission Terminal/modules/missions/table")
local Overlays = mod:io_dofile("Many Mission Terminal/scripts/mods/Many Mission Terminal/modules/overlays")
local Panel = mod:io_dofile("Many Mission Terminal/scripts/mods/Many Mission Terminal/modules/filters/panel")
local Card = mod:io_dofile("Many Mission Terminal/scripts/mods/Many Mission Terminal/modules/card")
local Grid = mod:io_dofile("Many Mission Terminal/scripts/mods/Many Mission Terminal/modules/grid")

local GRID_COLS = C.GRID_COLS
local GRID_ROWS = C.GRID_ROWS
local GRID_X0 = C.GRID_X0
local TILE_SCALE = C.TILE_SCALE

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

local mission_is_live = Missions.mission_is_live
local refresh_now = Missions.refresh_now

local show_all_missions = false
local use_archive = false
local notify_skips = true
local expanded_map
local expanded_ids = {}
local layout_dirty = false
local incompatible_warned = false
local map_missions = {}
local tile_ids = {}
local mission_by_id = {}
local slot_for_mission = {}
local pending_collapse = false
local expand_card_pressed = false
local next_expiry_scan = 0

local Scrim = Overlays.Scrim
local Badge = Overlays.Badge
local Tooltip = Overlays.Tooltip
local board_ui_hidden = Overlays.board_ui_hidden

Overlays.install({
	table = Table,
	cursor_over = function ()
		return Panel.cursor_over()
	end,
	expanded_map = function ()
		return expanded_map
	end,
})

Card.install({
	grid = Grid,
	layout = LAYOUT,
})

Grid.install({
	panel = Panel,
	layout = LAYOUT,
	map_missions = map_missions,
	tile_ids = tile_ids,
	mission_by_id = mission_by_id,
	slot_for_mission = slot_for_mission,
	expanded_ids = expanded_ids,
})

Panel.install({
	filters = Filters,
	filter_rows = FilterRows,
	layout = LAYOUT,
	board_ui_hidden = board_ui_hidden,
	show_all = function ()
		return show_all_missions
	end,
})

local function refresh_settings()
	show_all_missions = mod:get("show_all_missions") == true
	use_archive = mod:get("use_archive") == true
	notify_skips = mod:get("notify_skips") == true
end

local function board_is_open()
	return Managers.ui and Managers.ui:view_instance("mission_board_view") ~= nil
end

-- ─────────────────────────────────────────────────────────
-- Tile rendering
-- ─────────────────────────────────────────────────────────

local function render_cards(view)
	local badge_index = 0
	local scrim = Scrim.ensure(view)
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
				Card.style(view, widget, mission)
				widget.dirty = true
			end

			local slot = slot_for_mission[mission.id]
			if slot and (widget.offset[1] ~= slot.position[1] or widget.offset[2] ~= slot.position[2]) then
				widget.offset[1] = slot.position[1]
				widget.offset[2] = slot.position[2]
				widget.dirty = true
			end

			Card.set_input(widget, expanded_map ~= nil)

			if expanded_map and not widget.mmt_faded then
				widget.mmt_faded = true
				Card.fade_widget(widget)
			end

			if not expanded_map and widget.visible ~= false then
				local options = map_missions[mission.map]
				local count = options and #options or 1
				if count > 1 then
					badge_index = badge_index + 1
					Badge.place(view, badge_index, widget, count)
				end
			end
		end
	end

	Badge.hide_from(badge_index + 1)

	if Table.update(view, expanded_map, expanded_map and map_missions[expanded_map]) then
		Scrim.sync()
	end

	Tooltip.update(view)
end

-- ─────────────────────────────────────────────────────────
-- Expanded map view
-- ─────────────────────────────────────────────────────────

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

	Table.build(view, map, map_missions[map])
	Scrim.sync()

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

	Table.destroy(view)
	Scrim.sync()
	Card.restore_faded()

	if view then
		for _, widget in ipairs(view._mission_widgets or {}) do
			widget.mmt_faded = nil
		end
	end

	table.clear(expanded_ids)
	layout_dirty = true

	return true
end

local function toggle_filter(view, group, key, is_exclusion)
	if is_exclusion then
		Filters.set_exclusion(group, key, not Filters.exclusion_enabled(group, key))

		Panel.mark_scan_dirty()
	else
		Filters.set(group, key, not Filters.enabled(group, key))
	end

	collapse_expanded(view)

	local selected = view._selected_mission_id
	local mission = selected and mission_by_id[selected]
	if mission and not Filters.passes(mission) then
		view:_clear_selected()
	end

	view:_open_current_page()
end

local function resolve_press(view)
	if Scrim.take_press() then
		if expanded_map and not expand_card_pressed then
			pending_collapse = true
		end
	end
	expand_card_pressed = false

	if pending_collapse then
		pending_collapse = false
		collapse_expanded(view)
	end

	Panel.commit_pending_tab()
	Panel.commit_pending_section()

	local group, key, is_exclusion = Panel.take_pending()

	if group then
		toggle_filter(view, group, key, is_exclusion)
	end
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

mod.mmt_missions_for_map = function (map)
	return map_missions[map]
end

mod.mmterm_is_tile_mission = function (mission_id)
	return tile_ids[mission_id] == true
end

local MMT_INPUT_ACTIONS = {
	"mmterm_filter_board",
}

-- ─────────────────────────────────────────────────────────
-- Input, settings and lifecycle
-- ─────────────────────────────────────────────────────────

local function update_input_alias()
	if Managers.input and Managers.input._aliases and Managers.input._aliases.View then
		for i = 1, #MMT_INPUT_ACTIONS do
			local action = MMT_INPUT_ACTIONS[i]
			Managers.input._aliases.View._aliases[action] = Managers.input._aliases.View._default_aliases[action]
		end
	end
end

local MMT_INPUT_ALIAS = {
	"keyboard_f",
	"xbox_controller_left_trigger",
	"ps4_controller_l2",
	description = "",
	bindable = false,
}

local MMT_INPUT_SETTING = {
	key_alias = "mmterm_filter_board",
	type = "pressed",
}

local view_input_settings

local function install_input_alias(enabled)
	if not view_input_settings then
		return
	end

	view_input_settings.aliases.mmterm_filter_board = enabled and MMT_INPUT_ALIAS or nil
	view_input_settings.settings.mmterm_filter_board = enabled and MMT_INPUT_SETTING or nil

	local aliases = Managers.input and Managers.input._aliases and Managers.input._aliases.View

	if aliases then
		if enabled then
			update_input_alias()
		else
			aliases._aliases.mmterm_filter_board = nil
		end
	end
end

mod:hook_require("scripts/settings/input/default_view_input_settings", function (DefaultViewInputSettings)
	view_input_settings = DefaultViewInputSettings

	install_input_alias(true)
end)

mod.on_all_mods_loaded = function ()
	mod:info(mod.version)

	refresh_settings()
	update_input_alias()
	Grid.apply_slots(show_all_missions)

	Intercept.install(Filters.mission_excluded, function ()
		return Filters.exclusion_count() > 0
	end, Filters.skip_backfill, function ()
		return notify_skips
	end, Filters.event_only)
end

mod:add_global_localize_strings({
	loc_mmterm_skip_backfill = {
		en = "Only Start New Missions",
		["zh-cn"] = "仅开始新任务",
		ru = "Только новые миссии",
		["zh-tw"] = "僅開始新任務",
	},
	loc_mmterm_skip_backfill_desc = {
		en = "Quickplay will leave and search again if it matches you into a mission that is already underway.",
		["zh-cn"] = "快速游戏若匹配到已在进行中的任务，将退出并重新搜索。",
		ru = "Если быстрая игра подберёт уже идущую миссию, поиск начнётся заново.",
		["zh-tw"] = "快速遊戲若匹配到已在進行中的任務，將退出並重新搜尋。",
	},
	loc_mmterm_event_only = {
		en = "Only Play Event Missions",
		["zh-cn"] = "仅进行活动任务",
		ru = "Только событийные миссии",
		["zh-tw"] = "僅進行活動任務",
	},
	loc_mmterm_event_only_desc = {
		en = "Quickplay will leave and search again unless the mission is an Event mission.",
		["zh-cn"] = "快速游戏若匹配到非活动任务，将退出并重新搜索。",
		ru = "Если быстрая игра подберёт не событийную миссию, поиск начнётся заново.",
		["zh-tw"] = "快速遊戲若匹配到非活動任務，將退出並重新搜尋。",
	},
})

mod:hook(CLASS.ViewElemenMissionBoardOptions, "present", function (func, self, presentation_data)
	if type(presentation_data) == "table" then
		presentation_data[#presentation_data + 1] = {
			display_name = "loc_mmterm_skip_backfill",
			id = "mmterm_skip_backfill",
			tooltip_text = "loc_mmterm_skip_backfill_desc",
			widget_type = "checkbox",
			start_value = Filters.skip_backfill(),
			get_function = function ()
				return Filters.skip_backfill()
			end,
			on_activated = function (value)
				Filters.set_skip_backfill(value)
			end,
		}
		presentation_data[#presentation_data + 1] = {
			display_name = "loc_mmterm_event_only",
			id = "mmterm_event_only",
			tooltip_text = "loc_mmterm_event_only_desc",
			widget_type = "checkbox",
			start_value = Filters.event_only(),
			get_function = function ()
				return Filters.event_only()
			end,
			on_activated = function (value)
				Filters.set_event_only(value)
				Intercept.cancel()
			end,
		}
	end

	return func(self, presentation_data)
end)

mod.mmt_tune_table = function (dx, dy)
	local ox, oy = Table.set_offset(dx, dy)

	Scrim.sync()

	return ox, oy
end

local teardown_pending = false

local function mod_is_active()
	local ok, enabled = pcall(function ()
		return mod:is_enabled()
	end)

	return not ok or enabled ~= false
end

local function restore_vanilla_state()
	Grid.apply_slots(false)
	Card.restore_faded()

	expanded_map = nil
	table.clear(expanded_ids)
	Card.reset()
	Overlays.reset()
	Table.reset()
	Panel.reset()

	layout_dirty = true
end

mod.update = function ()
	if not mod_is_active() then
		if teardown_pending and not board_is_open() then
			teardown_pending = false

			restore_vanilla_state()
		end

		return
	end

	Intercept.update()
end

mod.mmterm_intercept_state = function ()
	return Intercept.debug_state()
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
		Grid.apply_slots(show_all_missions)
	end
end


mod.on_settings_reset = function()
	refresh_settings()
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
	teardown_pending = false

	refresh_settings()
	install_input_alias(true)
	Grid.apply_slots(show_all_missions)

	layout_dirty = true

	Panel.mark_scan_dirty()

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

	install_input_alias(false)
	Intercept.cancel()

	if board_is_open() then
		teardown_pending = true
	else
		teardown_pending = false

		restore_vanilla_state()
	end
end

-- ─────────────────────────────────────────────────────────
-- View hooks
-- ─────────────────────────────────────────────────────────

mod:hook(CLASS.MissionBoardViewLogic, "_should_show_mission", function (func, self, mission)
	if show_all_missions and not Filters.passes(mission) then
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
	Grid.rebuild_map_missions(self)
	Panel.mark_scan_dirty()
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
		if Missions.convert_expired_missions(self, now) then
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

	resolve_press(self)

	if layout_dirty then
		layout_dirty = false
		warn_incompatible_mods()
		Grid.layout_tiles(self, t)
	end

	local result = func(self, t)

	render_cards(self)

	return result
end)

mod:hook_safe(CLASS.MissionBoardView, "update", function (self, dt)
	refresh_now()

	if show_all_missions and board_ui_hidden(self) then
		Badge.hide_from(1)

		if expanded_map then
			collapse_expanded(self)
		end

		Tooltip.hide()
	end

	if show_all_missions then
		local intrusion = Grid.panel_intrusion(self)

		if intrusion ~= LAYOUT.applied_intrusion or Panel.is_open() ~= LAYOUT.applied_open then
			if Grid.compute_layout(self) then
				LAYOUT.applied_intrusion = intrusion
				LAYOUT.applied_open = Panel.is_open()
				Grid.apply_slots(show_all_missions)
				relayout_cards(self)
			end
		end

		Panel.update(self, dt)
	end
end)

mod:hook_safe(CLASS.MissionBoardView, "on_exit", function ()
	Panel.reset()
end)

mod:hook(CLASS.MissionBoardView, "_set_selected", function (func, self, id, ...)
	if not show_all_missions then
		return func(self, id, ...)
	end

	if board_ui_hidden(self) then
		return func(self, id, ...)
	end

	if Panel.cursor_over() then
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

mod:hook(CLASS.MissionBoardView, "_handle_input", function (func, self, input_service, dt, t)
	if not show_all_missions or not InputDevice.gamepad_active or self._mission_board_options then
		return func(self, input_service, dt, t)
	end

	if not Panel.is_open() or not input_service then
		return func(self, input_service, dt, t)
	end

	local ok, owned = pcall(function ()
		if input_service:get("back") then
			Panel.close()

			return true
		end

		return Panel.handle_gamepad(input_service)
	end)

	if not ok or not owned then
		return func(self, input_service, dt, t)
	end

	return func(self, input_service:null_service(), dt, t)
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
		Card.capture_baseline(widget)

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

	Card.forget(widget)

	Scrim.forget(widget)

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
	expand_card_pressed = false
	Overlays.reset()
	Table.reset()
	table.clear(expanded_ids)
	Card.reset()
	Panel.reset()

	LAYOUT.applied_intrusion = nil
	LAYOUT.applied_open = nil

	self.__mod_mmterm_filter_callback = function ()
		Panel.cycle_tab(self)
	end
end)
