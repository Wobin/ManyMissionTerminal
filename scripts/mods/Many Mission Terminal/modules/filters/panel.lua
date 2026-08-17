local mod = get_mod("Many Mission Terminal")

local ScrollbarPassTemplates = require("scripts/ui/pass_templates/scrollbar_pass_templates")
local UIWidget = require("scripts/managers/ui/ui_widget")
local UIFontSettings = require("scripts/managers/ui/ui_font_settings")

local C = mod:io_dofile("Many Mission Terminal/scripts/mods/Many Mission Terminal/modules/constants")

local FILTER = C.FILTER
local FILTER_TABS = C.FILTER_TABS

local Panel = {}

local Filters
local FilterRows
local LAYOUT
local board_ui_hidden
local show_all

local set_filter_open
local cycle_filter_tab

local pending_filter_group
local pending_filter_key
local pending_filter_exclusion
local pending_filter_tab

local filter_ui = {
	open = false,
	slide = 0,
	rows = {},
	row_widgets = {},
	scan_dirty = true,
	tab = "filters",
	scroll = 0,
}

-- ─────────────────────────────────────────────────────────
-- Filter panel
-- ─────────────────────────────────────────────────────────

function Panel.cursor_over()
	if not filter_ui.open or filter_ui.slide < 0.98 or not filter_ui.panel_widget then
		return false
	end

	local hotspot = filter_ui.panel_widget.content.panel_hotspot

	return hotspot ~= nil and hotspot.is_hover == true
end

function Panel.color(key)
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


function Panel.body_top()
	return FILTER.top + FILTER.tab_pad + FILTER.tab_bar_height + FILTER.row_pad
end

function Panel.measure_rows()
	local top = Panel.body_top()
	local y = top

	for i = 1, #filter_ui.rows do
		local row = filter_ui.rows[i]

		row.y = y
		row.h = row.kind == "group" and FILTER.group_height or FILTER.row_height
		y = y + row.h
	end

	filter_ui.content_height = y - top
end

function Panel.content_height()
	return filter_ui.content_height or 0
end

function Panel.body_limit()
	return FILTER.canvas_height - Panel.body_top() - FILTER.bottom_margin
end

function Panel.body_height()
	if filter_ui.base_body then
		return filter_ui.base_body
	end

	return math.min(Panel.content_height(), Panel.body_limit())
end

function Panel.max_scroll()
	return math.max(0, Panel.content_height() - Panel.body_height())
end

function Panel.panel_height()
	return FILTER.tab_pad + FILTER.tab_bar_height + FILTER.row_pad + FILTER.pad + Panel.body_height()
end

function Panel.row_y(index)
	local row = filter_ui.rows[index]

	return row and row.y or Panel.body_top()
end

function Panel.row_in_view(index)
	local row = filter_ui.rows[index]

	if not row then
		return false
	end

	local top = Panel.body_top()
	local y = row.y - filter_ui.scroll

	return y >= top and y + row.h <= top + Panel.body_height()
end

function Panel.panel_definition(height)
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
		FILTER.top + FILTER.tab_bar_height + 14,
		4,
	}
	title_style.text_color = Color.terminal_text_header(255, true)

	local tab_width = (FILTER.width - FILTER.pad * 2) / #FILTER_TABS

	local function tab_style(index, z)
		local style = table.clone(UIFontSettings.body_small)
		style.horizontal_alignment = "left"
		style.vertical_alignment = "top"
		style.text_horizontal_alignment = "center"
		style.text_vertical_alignment = "center"
		style.size = {
			tab_width,
			FILTER.tab_bar_height,
		}
		style.offset = {
			FILTER.pad + tab_width * (index - 1),
			FILTER.top + FILTER.tab_pad,
			z,
		}

		return style
	end

	local function tab_rect_style(index, z)
		return {
			horizontal_alignment = "left",
			vertical_alignment = "top",
			visible = false,
			size = {
				tab_width,
				FILTER.tab_bar_height,
			},
			offset = {
				FILTER.pad + tab_width * (index - 1),
				FILTER.top + FILTER.tab_pad,
				z,
			},
			color = Color.terminal_frame(160, true),
		}
	end

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
			content_id = "tab_hotspot_1",
			pass_type = "hotspot",
			style = table.clone(tab_style(1, 7)),
		},
		{
			content_id = "tab_hotspot_2",
			pass_type = "hotspot",
			style = table.clone(tab_style(2, 7)),
		},
		{
			pass_type = "rect",
			style_id = "tab_bg_1",
			style = tab_rect_style(1, 5),
		},
		{
			pass_type = "rect",
			style_id = "tab_bg_2",
			style = tab_rect_style(2, 5),
		},
		{
			pass_type = "text",
			style_id = "tab_label_1",
			value_id = "tab_label_1",
			value = "",
			style = tab_style(1, 8),
		},
		{
			pass_type = "text",
			style_id = "tab_label_2",
			value_id = "tab_label_2",
			value = "",
			style = tab_style(2, 8),
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
					FILTER.top + FILTER.tab_pad + FILTER.tab_bar_height,
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
					FILTER.top + FILTER.tab_pad + FILTER.tab_bar_height - 4,
					5,
				},
			},
		},
	}, FILTER.anchor)
end

function Panel.group_definition(index)
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
		Panel.row_y(index),
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

function Panel.row_definition(index)
	local row_y = Panel.row_y(index)
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

function Panel.tab_definition()
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

function Panel.destroy_widgets(view)
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
	filter_ui.scroll_widget = nil
	table.clear(filter_ui.row_widgets)
end

function Panel.reset()
	filter_ui.panel_widget = nil
	filter_ui.tab_widget = nil
	filter_ui.scroll_widget = nil
	filter_ui.signature = nil
	filter_ui.scan_page = nil
	filter_ui.open = mod:get("_filter_open") == true
	filter_ui.slide = filter_ui.open and 1 or 0
	filter_ui.scroll = 0
	filter_ui.base_body = nil
	filter_ui.content_height = nil
	table.clear(filter_ui.row_widgets)
end

function Panel.create_widgets(view)
	local widgets = view._widgets

	filter_ui.panel_widget = view:_create_widget("mmt_filter_panel", Panel.panel_definition(Panel.panel_height()))
	filter_ui.panel_widget.mmt_filter = true
	filter_ui.panel_widget.offset[3] = FILTER.z
	for i = 1, #FILTER_TABS do
		local tab = FILTER_TABS[i]

		filter_ui.panel_widget.content["tab_label_" .. i] = mod:localize(tab.mod_loc)
		filter_ui.panel_widget.content["tab_hotspot_" .. i].pressed_callback = function ()
			if tab.key == filter_ui.tab then
				set_filter_open(view, false)
			else
				pending_filter_tab = tab.key
			end
		end
	end

	widgets[#widgets + 1] = filter_ui.panel_widget

	local bar_definition = UIWidget.create_definition(ScrollbarPassTemplates.terminal_scrollbar, FILTER.anchor, nil, {
		FILTER.bar_width,
		Panel.body_height(),
	})

	filter_ui.scroll_widget = view:_create_widget("mmt_filter_scrollbar", bar_definition)
	filter_ui.scroll_widget.mmt_filter = true
	filter_ui.scroll_widget.offset[3] = FILTER.z + 2
	filter_ui.scroll_widget.content.axis = 2
	filter_ui.scroll_widget.content.value = 0
	filter_ui.scroll_widget.content.enable_gamepad_scrolling = true
	filter_ui.scroll_widget.content.gamepad_axis_name = "navigate_controller"
	filter_ui.scroll_widget.style.mouse_scroll.scenegraph_id = FILTER.anchor
	widgets[#widgets + 1] = filter_ui.scroll_widget

	for i = 1, #filter_ui.rows do
		local row = filter_ui.rows[i]
		local widget

		if row.kind == "group" then
			widget = view:_create_widget("mmt_filter_group_" .. i, Panel.group_definition(i))
		else
			widget = view:_create_widget("mmt_filter_row_" .. i, Panel.row_definition(i))
			widget.content.hotspot.pressed_callback = function ()
				pending_filter_group = row.group
				pending_filter_key = row.key
				pending_filter_exclusion = row.exclusion
			end
		end

		widget.mmt_filter = true
		widget.mmt_row = row
		widget.offset[3] = FILTER.z
		widget.content.label = row.label
		filter_ui.row_widgets[#filter_ui.row_widgets + 1] = widget
		widgets[#widgets + 1] = widget
	end

	filter_ui.tab_widget = view:_create_widget("mmt_filter_tab", Panel.tab_definition())
	filter_ui.tab_widget.mmt_filter = true
	filter_ui.tab_widget.offset[3] = FILTER.z
	filter_ui.tab_widget.content.hotspot.pressed_callback = function ()
		set_filter_open(view, not filter_ui.open)
	end
	widgets[#widgets + 1] = filter_ui.tab_widget
end

set_filter_open = function (view, open)
	filter_ui.open = open
	mod:set("_filter_open", open, false)
	LAYOUT.applied_intrusion = nil
end

cycle_filter_tab = function (view)
	if not filter_ui.open then
		if filter_ui.tab ~= FILTER_TABS[1].key then
			filter_ui.tab = FILTER_TABS[1].key
			filter_ui.scroll = 0
			filter_ui.scan_dirty = true
		end

		set_filter_open(view, true)

		return
	end

	for i = 1, #FILTER_TABS do
		if FILTER_TABS[i].key == filter_ui.tab then
			local next_tab = FILTER_TABS[i + 1]

			if next_tab then
				filter_ui.tab = next_tab.key
				filter_ui.scroll = 0
				filter_ui.scan_dirty = true
			else
				set_filter_open(view, false)
			end

			return
		end
	end

	set_filter_open(view, false)
end

function Panel.visible(view)
	return not board_ui_hidden(view)
end

function Panel.update(view, dt)
	if not show_all() then
		if filter_ui.panel_widget then
			Panel.destroy_widgets(view)
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
		local signature

		if filter_ui.tab == "exclusions" then
			signature = FilterRows.build_exclusions(filter_ui.rows)
		else
			signature = FilterRows.build_filters(filter_ui.rows, logic)
		end

		Panel.measure_rows()

		if filter_ui.tab == "filters" then
			filter_ui.base_body = nil
			filter_ui.base_body = math.min(Panel.content_height(), Panel.body_limit())
		end
		if signature ~= filter_ui.signature then
			filter_ui.signature = signature
			filter_ui.scroll = 0
			Panel.destroy_widgets(view)
			if signature ~= "" then
				Panel.create_widgets(view)
			end
		end
	end

	if not filter_ui.panel_widget then
		return
	end

	local max_scroll = Panel.max_scroll()

	local target = filter_ui.open and 1 or 0
	if filter_ui.slide ~= target then
		filter_ui.slide = filter_ui.slide + (target - filter_ui.slide) * math.min(dt * FILTER.slide_rate, 1)
		if math.abs(target - filter_ui.slide) < 0.002 then
			filter_ui.slide = target
		end
	end

	local x = (filter_ui.slide - 1) * FILTER.width
	local visible = Panel.visible(view)

	filter_ui.panel_widget.offset[1] = x
	filter_ui.panel_widget.visible = visible

	filter_ui.panel_widget.dirty = true

	if filter_ui.scroll_widget then
		local bar = filter_ui.scroll_widget
		local bar_content = bar.content

		bar_content.scroll_length = max_scroll
		bar_content.area_length = Panel.content_height()

		if max_scroll > 0 then
			if not bar_content.in_scroll_area and not bar_content.drag_active and Panel.cursor_over() then
				local input_service = Managers.ui and Managers.ui:input_service()
				local scroll_axis = input_service and input_service:get("scroll_axis")
				local scroll_delta = scroll_axis and scroll_axis[2] or 0

				if scroll_delta ~= 0 then
					local moved = filter_ui.scroll - scroll_delta * FILTER.scroll_step

					bar_content.value = math.clamp(moved / max_scroll, 0, 1)
				end
			end

			filter_ui.scroll = math.clamp((bar_content.value or 0) * max_scroll, 0, max_scroll)
		else
			bar_content.value = 0
			filter_ui.scroll = 0
		end

		bar.offset[1] = x + FILTER.width - FILTER.bar_inset - FILTER.bar_width
		bar.offset[2] = Panel.body_top()
		bar.visible = visible and max_scroll > 0 and filter_ui.slide > 0.02
		bar.dirty = true
	end

	filter_ui.tab_widget.offset[1] = x + FILTER.width
	filter_ui.tab_widget.visible = visible and filter_ui.slide < 0.98
	filter_ui.tab_widget.dirty = true

	if filter_ui.tab_widget.content.hotspot.is_hover then
		filter_ui.tab_widget.style.frame.color = Panel.color("frame_hover")
		filter_ui.tab_widget.style.icon.color = Panel.color("frame_hover")
	else
		filter_ui.tab_widget.style.frame.color = Panel.color("frame")
		filter_ui.tab_widget.style.icon.color = Panel.color("text_header")
	end

	local panel_style = filter_ui.panel_widget.style
	local panel_content = filter_ui.panel_widget.content

	for i = 1, #FILTER_TABS do
		local is_active = FILTER_TABS[i].key == filter_ui.tab
		local is_hover = panel_content["tab_hotspot_" .. i].is_hover == true

		panel_style["tab_bg_" .. i].visible = is_active

		if is_active then
			panel_style["tab_label_" .. i].text_color = Panel.color("text_header")
		elseif is_hover then
			panel_style["tab_label_" .. i].text_color = Panel.color("frame_hover")
		else
			panel_style["tab_label_" .. i].text_color = Panel.color("text_body")
		end
	end

	for i = 1, #filter_ui.row_widgets do
		local widget = filter_ui.row_widgets[i]
		local row = widget.mmt_row

		widget.offset[1] = x
		widget.offset[2] = -filter_ui.scroll
		widget.visible = visible and filter_ui.slide > 0.02 and Panel.row_in_view(i)
		widget.dirty = true

		if row.kind == "row" then
			local style = widget.style
			local is_hover = widget.content.hotspot.is_hover == true

			style.tick.visible = Filters.row_enabled(row)
			style.highlight.visible = is_hover

			if is_hover then
				style.label.text_color = Panel.color("text_header")
				style.box.color = Panel.color("frame_hover")
			else
				style.label.text_color = Panel.color("text_body")
				style.box.color = Panel.color("frame")
			end
		end
	end
end

function Panel.is_open()
	return filter_ui.open == true
end

function Panel.mark_scan_dirty()
	filter_ui.scan_dirty = true
end

function Panel.cycle_tab(view)
	cycle_filter_tab(view)
end

function Panel.commit_pending_tab()
	if not pending_filter_tab then
		return
	end

	local tab = pending_filter_tab
	pending_filter_tab = nil

	if tab ~= filter_ui.tab then
		filter_ui.tab = tab
		filter_ui.scroll = 0
		filter_ui.scan_dirty = true
	end
end

function Panel.take_pending()
	if not pending_filter_group then
		return nil
	end

	local group, key, is_exclusion = pending_filter_group, pending_filter_key, pending_filter_exclusion
	pending_filter_group, pending_filter_key, pending_filter_exclusion = nil, nil, nil

	return group, key, is_exclusion
end

function Panel.install(deps)
	Filters = deps.filters
	FilterRows = deps.filter_rows
	LAYOUT = deps.layout
	board_ui_hidden = deps.board_ui_hidden
	show_all = deps.show_all
end

return Panel
