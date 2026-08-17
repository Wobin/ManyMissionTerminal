local mod = get_mod("Many Mission Terminal")

local MissionBoardViewSettings = require("scripts/ui/views/mission_board_view/mission_board_view_settings")
local MissionBoardViewStyles = require("scripts/ui/views/mission_board_view/mission_board_view_styles")
local Text = require("scripts/utilities/ui/text")

local C = mod:io_dofile("Many Mission Terminal/scripts/mods/Many Mission Terminal/modules/constants")
local Missions = mod:io_dofile("Many Mission Terminal/scripts/mods/Many Mission Terminal/modules/missions/core")

local PLAIN_STYLES = C.PLAIN_STYLES
local FADE_ALPHA = C.FADE_ALPHA
local FADE_COLOR_KEYS = C.FADE_COLOR_KEYS
local EXPIRED_BAR_COLOR = C.EXPIRED_BAR_COLOR
local mission_is_live = Missions.mission_is_live

local Card = {}

local Grid
local LAYOUT

local faded_widgets = {}

-- ─────────────────────────────────────────────────────────
-- Mission tiles
-- ─────────────────────────────────────────────────────────

function Card.capture_baseline(widget)
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

function Card.apply_gradients(widget, category)
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

function Card.normalise_size(widget)
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

function Card.apply_category_chrome(widget, category)
	local baseline = widget.mmt_baseline

	for i = 1, #PLAIN_STYLES do
		local id = PLAIN_STYLES[i]
		local style = widget.style[id]
		if style and baseline then
			style.visible = baseline.visible[id] == true
		end
	end

	Card.apply_gradients(widget, category)
end

function Card.make_plain(widget)
	for i = 1, #PLAIN_STYLES do
		local style = widget.style[PLAIN_STYLES[i]]
		if style then
			style.visible = false
		end
	end

	Card.apply_gradients(widget, "common")
end

function Card.banner_base_label(mission)
	if mission.category == "event" then
		return Localize("loc_mission_board_mission_category_event")
	end

	local key = MissionBoardViewSettings.mission_tile_banner_category_texts[mission.category]

	if not key or key == "n/a" then
		return ""
	end

	return Localize(key)
end

function Card.apply_banner(view, widget, mission)
	local style = widget.style
	local banner = style.mission_type_banner
	local banner_text = style.mission_type_banner_text
	local baseline = widget.mmt_baseline

	if not banner or not banner_text or not baseline then
		return
	end

	local label = Card.banner_base_label(mission)

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

function Card.fade_widget(widget)
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

function Card.restore_faded()
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

function Card.style_expired_timer(widget)
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

function Card.style(view, widget, mission)
	widget.scale = LAYOUT.scale

	if not mission_is_live(mission) then
		Card.style_expired_timer(widget)
	end

	Card.normalise_size(widget)

	if Grid.mission_is_notable(mission) then
		Card.apply_category_chrome(widget, mission.category)
	else
		Card.make_plain(widget)
	end

	Card.apply_banner(view, widget, mission)
end

function Card.set_input(widget, blocked)
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

function Card.forget(widget)
	for i = #faded_widgets, 1, -1 do
		if faded_widgets[i].widget == widget then
			table.remove(faded_widgets, i)
		end
	end
end

function Card.reset()
	table.clear(faded_widgets)
end

function Card.install(deps)
	Grid = deps.grid
	LAYOUT = deps.layout
end

return Card
