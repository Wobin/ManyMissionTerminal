local mod = get_mod("Many Mission Terminal")
local MissionTemplates = require("scripts/settings/mission/mission_templates")
local CircumstanceTemplates = require("scripts/settings/circumstance/circumstance_templates")

local C = mod:io_dofile("Many Mission Terminal/scripts/mods/Many Mission Terminal/modules/constants")
local Missions = mod:io_dofile("Many Mission Terminal/scripts/mods/Many Mission Terminal/modules/missions/core")

local FILTER_CATEGORIES = C.FILTER_CATEGORIES
local FILTER_CONDITIONS = C.FILTER_CONDITIONS
local map_display_name = Missions.map_display_name
local mission_is_live = Missions.mission_is_live

local Filters = {}

local filter_state
local exclusion_state
local exclusion_total
local conditions_by_circumstance
local skip_backfill
local event_only

local function filters()
	if not filter_state then
		local stored = mod:get("_filters")

		filter_state = type(stored) == "table" and stored or {}
	end

	return filter_state
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

local function prune_exclusions(state)
	local known_condition = {}

	for i = 1, #FILTER_CONDITIONS do
		known_condition[FILTER_CONDITIONS[i].key] = true
	end

	local known_announcer = {}
	local announcers = Missions.announcers()

	for i = 1, #announcers do
		known_announcer[announcers[i].key] = true
	end

	local dropped = 0

	for group, entries in pairs(state) do
		if group ~= "condition" and group ~= "map" and group ~= "announcer" then
			state[group] = nil
			dropped = dropped + 1
		else
			for key in pairs(entries) do
				local valid = group == "condition" and known_condition[key]
					or group == "map" and MissionTemplates[key]
					or group == "announcer" and known_announcer[key]

				if not valid then
					entries[key] = nil
					dropped = dropped + 1
				end
			end
		end
	end

	if dropped > 0 then
		mod:set("_exclusions", state, false)
	end

	return state
end

local function exclusions()
	if not exclusion_state then
		local stored = mod:get("_exclusions")

		exclusion_state = prune_exclusions(type(stored) == "table" and stored or {})
	end

	return exclusion_state
end

local function condition_label(key)
	for i = 1, #FILTER_CONDITIONS do
		if FILTER_CONDITIONS[i].key == key then
			return mod:localize(FILTER_CONDITIONS[i].mod_loc)
		end
	end

	return key
end

function Filters.enabled(group, key)
	local group_state = filters()[group]
	local value = group_state and group_state[key]

	if value == nil then
		return filter_default(group, key)
	end

	return value == true
end

function Filters.set(group, key, value)
	local state = filters()

	state[group] = state[group] or {}
	state[group][key] = value

	mod:set("_filters", state, false)
end

function Filters.exclusion_enabled(group, key)
	local group_state = key ~= nil and exclusions()[group]

	return group_state ~= nil and group_state[key] == true
end

function Filters.set_exclusion(group, key, value)
	local state = exclusions()

	state[group] = state[group] or {}

	if value == true then
		state[group][key] = true
	else
		state[group][key] = nil
	end

	mod:set("_exclusions", state, false)

	exclusion_total = nil
end

function Filters.exclusion_count()
	if not exclusion_total then
		local n = 0

		for _, group_state in pairs(exclusions()) do
			for _, value in pairs(group_state) do
				if value == true then
					n = n + 1
				end
			end
		end

		exclusion_total = n
	end

	return exclusion_total
end

function Filters.row_enabled(row)
	if row.exclusion then
		return Filters.exclusion_enabled(row.group, row.key)
	end

	return Filters.enabled(row.group, row.key)
end

function Filters.conditions_for_circumstance(circumstance)
	if not conditions_by_circumstance then
		conditions_by_circumstance = {}

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

				conditions_by_circumstance[name] = found
			end
		end
	end

	return circumstance and conditions_by_circumstance[circumstance]
end

function Filters.mission_excluded(mission)
	if Filters.exclusion_count() == 0 then
		return false, "no exclusions set"
	end

	if Filters.exclusion_enabled("map", mission.map) then
		return true, "map " .. tostring(mission.map), map_display_name(mission.map)
	end

	local voices, giver = Missions.mission_voice_keys(mission)

	if giver and Filters.exclusion_enabled("announcer", giver) then
		return true, "announcer " .. tostring(Missions.mission_giver(mission)), Localize(giver)
	end

	local supporting = {}

	for key in pairs(voices) do
		if key ~= giver and Filters.exclusion_enabled("announcer", key) then
			supporting[#supporting + 1] = key
		end
	end

	if #supporting > 0 then
		table.sort(supporting)

		return true, "supporting voice " .. supporting[1], Localize(supporting[1])
	end

	local conditions = Filters.conditions_for_circumstance(mission.circumstance)

	if not conditions then
		return false, "circumstance " .. tostring(mission.circumstance) .. " maps to no tracked condition"
	end

	local candidates = {}

	for key in pairs(conditions) do
		if Filters.exclusion_enabled("condition", key) then
			return true, "condition " .. key, condition_label(key)
		end

		candidates[#candidates + 1] = key
	end

	table.sort(candidates)

	return false, "none of [" .. table.concat(candidates, ",") .. "] are excluded"
end

function Filters.skip_backfill()
	if skip_backfill == nil then
		skip_backfill = mod:get("_skip_backfill") == true
	end

	return skip_backfill
end

function Filters.event_only()
	if event_only == nil then
		event_only = mod:get("_event_only") == true
	end

	return event_only
end

function Filters.set_event_only(value)
	event_only = value == true

	mod:set("_event_only", event_only, false)
end

function Filters.set_skip_backfill(value)
	skip_backfill = value == true

	mod:set("_skip_backfill", skip_backfill, false)
end

function Filters.passes(mission)
	if Filters.mission_excluded(mission) then
		return false
	end

	if not Filters.enabled("category", mission.category) then
		return false
	end

	local conditions = Filters.conditions_for_circumstance(mission.circumstance)

	if Filters.enabled("match", "any") then
		local any_ticked = false

		for i = 1, #FILTER_CONDITIONS do
			if Filters.enabled("condition", FILTER_CONDITIONS[i].key) then
				any_ticked = true
				break
			end
		end

		local matched = not any_ticked

		if conditions and not matched then
			for key in pairs(conditions) do
				if Filters.enabled("condition", key) then
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
			if not Filters.enabled("condition", key) then
				return false
			end
		end
	end

	local side = mission.side_mission or mission.sideMission

	if side and not Filters.enabled("side", side) then
		return false
	end

	if not Filters.enabled("state", "expired") and not mission_is_live(mission) then
		return false
	end

	return true
end

return Filters
