local mod = get_mod("Many Mission Terminal")
local MMT = get_mod("ManyMoreTry")

local MissionBoardViewSettings = require("scripts/ui/views/mission_board_view/mission_board_view_settings")
local CircumstanceTemplates = require("scripts/settings/circumstance/circumstance_templates")
local UIWidget = require("scripts/managers/ui/ui_widget")
local UIFontSettings = require("scripts/managers/ui/ui_font_settings")

local C = mod:io_dofile("Many Mission Terminal/scripts/mods/Many Mission Terminal/modules/constants")
local Missions = mod:io_dofile("Many Mission Terminal/scripts/mods/Many Mission Terminal/modules/missions/core")
local Filters = mod:io_dofile("Many Mission Terminal/scripts/mods/Many Mission Terminal/modules/filters/core")

local MTABLE = C.MTABLE
local HORIZON_MINUTES = C.HORIZON_MINUTES
local EXPIRED_BAR_COLOR = C.EXPIRED_BAR_COLOR
local FILTER_CONDITIONS = C.FILTER_CONDITIONS
local minutes_past_expiry = Missions.minutes_past_expiry
local map_display_name = Missions.map_display_name

local Table = {}

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

function Table.hover_label()
	if table_ui.row_count == 0 then
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
function Table.category_icon(mission)
	local entry = MissionBoardViewSettings.mission_category_icons[mission.category]

	return entry and entry.mission_board_icon
end

function Table.category_label(mission)
	local entry = MissionBoardViewSettings.mission_category_icons[mission.category]

	if entry and entry.name then
		return Localize(entry.name)
	end

	return mod:localize("cat_common")
end

function Table.circumstance_ui(mission)
	local template = mission.circumstance and CircumstanceTemplates[mission.circumstance]

	return template and template.ui
end

function Table.circumstance_icon(mission)
	local ui = Table.circumstance_ui(mission)

	return ui and (ui.mission_board_icon or ui.icon)
end

function Table.circumstance_label(mission)
	local ui = Table.circumstance_ui(mission)

	if ui and ui.display_name then
		return Localize(ui.display_name)
	end

	return nil
end

function Table.side_icon(mission)
	return C.SIDE_ICONS[Missions.side_key(mission)]
end

function Table.time_state(mission)
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

function Table.sort_by_time_left(a, b)
	local minutes_a, live_a = Table.time_state(a)
	local minutes_b, live_b = Table.time_state(b)

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

function Table.format_minutes(minutes)
	if not minutes then
		return "--"
	end

	if minutes >= 60 then
		return string.format("%dh %02dm", math.floor(minutes / 60), minutes % 60)
	end

	return string.format("%dm", minutes)
end

function Table.height(row_count)
	return MTABLE.title_height + MTABLE.header_height + row_count * MTABLE.row_height + MTABLE.pad * 2
end

function Table.origin(row_count)
	return C.GRID_CENTRE_X - MTABLE.width * 0.5, C.GRID_CENTRE_Y - Table.height(row_count) * 0.5
end

function Table.text_style(size_x, offset_x, offset_y, font, align)
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

function Table.definition(row_count)
	local height = Table.height(row_count)
	local origin_x, origin_y = Table.origin(row_count)
	local inner = MTABLE.width - MTABLE.pad * 2
	local header_y = origin_y + MTABLE.pad + MTABLE.title_height

	local title_style = Table.text_style(inner, origin_x + MTABLE.pad, origin_y + MTABLE.pad, "terminal_header_3")
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
		local style = Table.text_style(width, origin_x + MTABLE.pad + offset_x, header_y, "body_small", align)
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

function Table.row_definition(index, row_count)
	local origin_x, origin_y = Table.origin(row_count)
	local inner = MTABLE.width - MTABLE.pad * 2
	local row_y = origin_y + MTABLE.pad + MTABLE.title_height + MTABLE.header_height + (index - 1) * MTABLE.row_height
	local icon_y = row_y + (MTABLE.row_height - MTABLE.icon) * 0.5

	local bar_y = row_y + (MTABLE.row_height - MTABLE.bar_height) * 0.5
	local time_style = Table.text_style(MTABLE.col_type - MTABLE.col_time - 8, origin_x + MTABLE.pad + MTABLE.col_time, row_y, "body_small")
	local cond_style = Table.text_style(MTABLE.col_w.cond, origin_x + MTABLE.pad + MTABLE.col_cond, row_y, "body_small", "center")
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
		local tag_style = Table.text_style(MTABLE.cond_slot, slot_x, row_y, "body_small", "center")
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

function Table.destroy(view)
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
end

function Table.reset()
	table.clear(table_ui.widgets)
	table.clear(table_ui.rows)
	table_ui.row_count = 0
	table_ui.source_count = 0
end

function Table.set_icon_cell(widget, style_id, value_id, material)
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

function Table.build(view, map, list)
	refresh_saved_ids()
	Table.destroy(view)

	if not list then
		return
	end

	for i = 1, #list do
		table_ui.rows[i] = list[i]
	end

	table.sort(table_ui.rows, Table.sort_by_time_left)

	while #table_ui.rows > MTABLE.max_rows do
		table.remove(table_ui.rows)
	end

	table_ui.source_count = #list
	table_ui.row_count = #table_ui.rows
	if table_ui.row_count == 0 then
		return
	end

	local widgets = view._widgets
	local panel = view:_create_widget("mmt_table_panel", Table.definition(table_ui.row_count))
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

	local origin_x, origin_y = Table.origin(table_ui.row_count)
	for i = 1, #TABLE_CELLS do
		local key = TABLE_CELLS[i]
		table_ui.cell_cx[key] = origin_x + MTABLE.pad + MTABLE["col_" .. key] + MTABLE.col_w[key] * 0.5
	end

	for i = 1, MTABLE.cond_slots do
		table_ui.slot_cx[i] = origin_x + MTABLE.pad + MTABLE.col_conds + (i - 1) * MTABLE.cond_slot + MTABLE.cond_slot * 0.5
	end

	for i = 1, table_ui.row_count do
		local mission = table_ui.rows[i]
		local widget = view:_create_widget("mmt_table_row_" .. i, Table.row_definition(i, table_ui.row_count))
		widget.mmt_table = true
		widget.mmt_mission = mission
		widget.offset[1] = table_ui.dx
		widget.offset[2] = table_ui.dy
		widget.offset[3] = MTABLE.z

		local keys = Filters.conditions_for_circumstance(mission.circumstance)
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
		Table.set_icon_cell(widget, "type_icon", "type_icon", Table.category_icon(mission))
		Table.set_icon_cell(widget, "side_icon", "side_icon", Table.side_icon(mission))
		Table.set_icon_cell(widget, "saved_icon", "saved_icon", saved_ids[mission.id] and C.BOOKMARK_ICON or nil)

		local cond_material = Table.circumstance_icon(mission)
		Table.set_icon_cell(widget, "cond_icon", "cond_icon", cond_material)
		if not cond_material then
			local label = Table.circumstance_label(mission)
			widget.content.cond_text = label and string.sub(label, 1, 3) or ""
		else
			widget.content.cond_text = ""
		end

		widget.mmt_row_y = origin_y + MTABLE.pad + MTABLE.title_height + MTABLE.header_height + (i - 1) * MTABLE.row_height
		widget.mmt_labels = {
			type = Table.category_label(mission),
			cond = Table.circumstance_label(mission),
			side = Missions.side_display_name(Missions.side_key(mission)),
			saved = saved_ids[mission.id] and mod:localize("tip_saved") or nil,
		}

		widget.content.hotspot.pressed_callback = function ()
			view:set_selected_mission(mission.id)
		end

		table_ui.widgets[#table_ui.widgets + 1] = widget
		widgets[#widgets + 1] = widget
	end
end

function Table.set_offset(dx, dy)
	table_ui.dx = dx or table_ui.dx
	table_ui.dy = dy or table_ui.dy

	for i = 1, #table_ui.widgets do
		local widget = table_ui.widgets[i]
		widget.offset[1] = table_ui.dx
		widget.offset[2] = table_ui.dy
		widget.dirty = true
	end

	return table_ui.dx, table_ui.dy
end

function Table.hole_rect()
	if table_ui.row_count == 0 then
		return nil
	end

	local hole_x, hole_y = Table.origin(table_ui.row_count)

	return hole_x + table_ui.dx, hole_y + table_ui.dy, MTABLE.width, Table.height(table_ui.row_count)
end

function Table.rows_ordered()
	for i = 2, table_ui.row_count do
		if Table.sort_by_time_left(table_ui.rows[i], table_ui.rows[i - 1]) then
			return false
		end
	end

	return true
end

function Table.update(view, map, list)
	if table_ui.row_count == 0 then
		return
	end

	if map and list and #list ~= table_ui.source_count then
		Table.build(view, map, list)

		return true
	end

	local selected = view._selected_mission_id
	local ticked = false

	for i = 1, table_ui.row_count do
		local widget = table_ui.widgets[i + 1]
		local mission = widget and widget.mmt_mission

		if mission then
			local minutes, live, ratio = Table.time_state(mission)

			if widget.mmt_minutes ~= minutes then
				ticked = true
				widget.mmt_minutes = minutes
				widget.content.time = Table.format_minutes(minutes)

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

	if ticked and map and list and not Table.rows_ordered() then
		Table.build(view, map, list)

		return true
	end

	return false
end

return Table
