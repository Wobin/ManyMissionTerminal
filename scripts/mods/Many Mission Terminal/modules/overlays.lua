local mod = get_mod("Many Mission Terminal")

local Text = require("scripts/utilities/ui/text")
local UIWidget = require("scripts/managers/ui/ui_widget")
local UIFontSettings = require("scripts/managers/ui/ui_font_settings")
local InputDevice = require("scripts/managers/input/input_device")

local C = mod:io_dofile("Many Mission Terminal/scripts/mods/Many Mission Terminal/modules/constants")
local Missions = mod:io_dofile("Many Mission Terminal/scripts/mods/Many Mission Terminal/modules/missions/core")

local BADGE = C.BADGE
local TOOLTIP = C.TOOLTIP
local SCRIM = C.SCRIM
local TILE_BOX_W = C.TILE_BOX_W
local TILE_BOX_H = C.TILE_BOX_H
local map_display_name = Missions.map_display_name

local Scrim = {}
local Badge = {}
local Tooltip = {}

local Table
local cursor_over_fn
local expanded_map_fn

local scrim_widget
local scrim_pressed = false
local tooltip_widget
local tooltip_card
local badge_widgets = {}
local badge_dx = BADGE.dx
local badge_dy = BADGE.dy

local SCRIM_BANDS = {
	"top",
	"bottom",
	"left",
	"right",
}

-- ─────────────────────────────────────────────────────────
-- Scrim
-- ─────────────────────────────────────────────────────────

function Scrim.definition()
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

function Scrim.set_band(widget, name, x, y, w, h)
	local style = widget.style["band_" .. name]

	if not style then
		return
	end

	style.offset[1] = x
	style.offset[2] = y
	style.size[1] = math.max(w, 0)
	style.size[2] = math.max(h, 0)
end

function Scrim.layout_bands(widget, hole_x, hole_y, hole_w, hole_h)
	local x0, y0 = SCRIM.x, SCRIM.y
	local x1, y1 = SCRIM.x + SCRIM.w, SCRIM.y + SCRIM.h

	if not hole_x then
		Scrim.set_band(widget, "top", x0, y0, SCRIM.w, SCRIM.h)
		Scrim.set_band(widget, "bottom", x0, y0, 0, 0)
		Scrim.set_band(widget, "left", x0, y0, 0, 0)
		Scrim.set_band(widget, "right", x0, y0, 0, 0)

		return
	end

	local hx1, hy1 = hole_x + hole_w, hole_y + hole_h

	Scrim.set_band(widget, "top", x0, y0, SCRIM.w, hole_y - y0)
	Scrim.set_band(widget, "bottom", x0, hy1, SCRIM.w, y1 - hy1)
	Scrim.set_band(widget, "left", x0, hole_y, hole_x - x0, hole_h)
	Scrim.set_band(widget, "right", hx1, hole_y, x1 - hx1, hole_h)
end

function Scrim.sync()
	if not scrim_widget then
		return
	end

	local x, y, w, h = Table.hole_rect()

	if x then
		Scrim.layout_bands(scrim_widget, x, y, w, h)
	else
		Scrim.layout_bands(scrim_widget)
	end
end

function Scrim.ensure(view)
	if scrim_widget then
		return scrim_widget
	end

	local widgets = view._mission_widgets
	if not widgets then
		return nil
	end

	scrim_widget = view:_create_widget("mmt_expand_scrim", Scrim.definition())
	scrim_widget.offset[3] = SCRIM.z
	scrim_widget.visible = false
	for i = 1, #SCRIM_BANDS do
		scrim_widget.content["band_" .. SCRIM_BANDS[i]].pressed_callback = function ()
			scrim_pressed = true
		end
	end

	Scrim.layout_bands(scrim_widget)
	widgets[#widgets + 1] = scrim_widget

	return scrim_widget
end

function Scrim.take_press()
	if not scrim_pressed then
		return false
	end

	scrim_pressed = false

	return true
end

function Scrim.forget(widget)
	if widget == scrim_widget then
		scrim_widget = nil
	end
end

-- ─────────────────────────────────────────────────────────
-- Count badges
-- ─────────────────────────────────────────────────────────

function Badge.definition()
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

function Badge.ensure(view, index)
	local widget = badge_widgets[index]
	if widget then
		return widget
	end

	local widgets = view._widgets
	if not widgets then
		return nil
	end

	widget = view:_create_widget("mmt_badge_" .. index, Badge.definition())
	widget.offset[3] = BADGE.z
	widget.visible = false
	badge_widgets[index] = widget
	widgets[#widgets + 1] = widget

	return widget
end

function Badge.place(view, index, card, count)
	local widget = Badge.ensure(view, index)
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

local function board_ui_hidden(view)
	if not view or view._mission_board_options or view._is_loading then
		return true
	end

	local mission_list = view:_element("mission_list")

	return mission_list ~= nil and mission_list:visible() == true
end

function Badge.hide_from(index)
	for i = index, #badge_widgets do
		local widget = badge_widgets[i]
		if widget and widget.visible then
			widget.visible = false
			widget.dirty = true
		end
	end
end

-- ─────────────────────────────────────────────────────────
-- Tooltips
-- ─────────────────────────────────────────────────────────

function Tooltip.definition()
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

function Tooltip.ensure(view)
	if tooltip_widget then
		return tooltip_widget
	end

	local widgets = view._widgets
	if not widgets then
		return nil
	end

	tooltip_widget = view:_create_widget("mmt_map_tooltip", Tooltip.definition())
	tooltip_widget.offset[3] = TOOLTIP.z
	tooltip_widget.visible = false
	widgets[#widgets + 1] = tooltip_widget

	return tooltip_widget
end

function Tooltip.hide()
	if tooltip_widget then
		tooltip_widget.visible = false
	end
end

function Tooltip.hovered_card(view)
	if expanded_map_fn() or InputDevice.gamepad_active or cursor_over_fn() then
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

function Tooltip.from_table()
	if not expanded_map_fn() then
		return nil
	end

	return Table.hover_label()
end

function Tooltip.update(view)
	local widget = Tooltip.ensure(view)
	if not widget then
		return
	end

	local label, centre_x, top_y, owner = Tooltip.from_table()
	local card

	if not label then
		card = Tooltip.hovered_card(view)

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

local function install(deps)
	Table = deps.table
	cursor_over_fn = deps.cursor_over
	expanded_map_fn = deps.expanded_map
end

local function reset()
	scrim_widget = nil
	scrim_pressed = false
	tooltip_widget = nil
	tooltip_card = nil
	table.clear(badge_widgets)
end

return {
	Scrim = Scrim,
	Badge = Badge,
	Tooltip = Tooltip,
	install = install,
	reset = reset,
	board_ui_hidden = board_ui_hidden,
}
