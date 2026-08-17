local mod = get_mod("Many Mission Terminal")
local MissionTemplates = require("scripts/settings/mission/mission_templates")

local C = mod:io_dofile("Many Mission Terminal/scripts/mods/Many Mission Terminal/modules/constants")
local Filters = mod:io_dofile("Many Mission Terminal/scripts/mods/Many Mission Terminal/modules/filters/core")
local Missions = mod:io_dofile("Many Mission Terminal/scripts/mods/Many Mission Terminal/modules/missions/core")

local FILTER_CATEGORIES = C.FILTER_CATEGORIES
local FILTER_CONDITIONS = C.FILTER_CONDITIONS
local EXCLUDE_MISSION_TYPES = C.EXCLUDE_MISSION_TYPES
local mission_is_live = Missions.mission_is_live
local side_display_name = Missions.side_display_name

local FilterRows = {}

local function grouper(rows, parts, key_of)
	return function (title_key, entries)
		if #entries == 0 then
			return
		end

		rows[#rows + 1] = {
			kind = "group",
			label = mod:localize(title_key),
		}
		parts[#parts + 1] = title_key

		for i = 1, #entries do
			rows[#rows + 1] = entries[i]
			parts[#parts + 1] = key_of(entries[i])
		end
	end
end

function FilterRows.build_exclusions(rows)
	table.clear(rows)

	local parts = {
		"exclusions",
	}
	local add_group = grouper(rows, parts, function (entry)
		return entry.key
	end)

	local conditions = {}

	for i = 1, #FILTER_CONDITIONS do
		local entry = FILTER_CONDITIONS[i]

		conditions[#conditions + 1] = {
			kind = "row",
			exclusion = true,
			group = "condition",
			key = entry.key,
			label = mod:localize(entry.mod_loc),
		}
	end

	add_group("exclude_group_condition", conditions)

	local maps = {}

	for name, template in pairs(MissionTemplates) do
		if not template.not_available_on_mission_board and not EXCLUDE_MISSION_TYPES[template.mission_type] then
			maps[#maps + 1] = {
				kind = "row",
				exclusion = true,
				group = "map",
				key = name,
				label = template.mission_name and Localize(template.mission_name) or name,
			}
		end
	end

	table.sort(maps, function (a, b)
		return a.label < b.label
	end)

	add_group("exclude_group_mission", maps)

	return table.concat(parts, "|")
end

function FilterRows.build_filters(rows, logic)
	table.clear(rows)

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

			local conditions = Filters.conditions_for_circumstance(mission.circumstance)

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
	local add_group = grouper(rows, parts, function (entry)
		return entry.group .. "." .. entry.key
	end)

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

return FilterRows
