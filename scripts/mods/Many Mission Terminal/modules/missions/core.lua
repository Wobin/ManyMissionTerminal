local mod = get_mod("Many Mission Terminal")
local MissionTemplates = require("scripts/settings/mission/mission_templates")
local MissionObjectiveTemplates = require("scripts/settings/mission_objective/mission_objective_templates")

local C = mod:io_dofile("Many Mission Terminal/scripts/mods/Many Mission Terminal/modules/constants")
local SIDE_NONE = C.FILTER.side_none
local HORIZON_MINUTES = C.HORIZON_MINUTES

local map_name_cache = {}
local clock = mod:persistent_table("mmt_clock")

clock.ms = clock.ms or os.time() * 1000
clock.t = clock.t or 0

local function refresh_now()
	clock.ms = os.time() * 1000
	clock.t = Managers.time and Managers.time:time("main") or clock.t

	return clock.ms
end

local function minutes_past_expiry(backend_mission)
	local expiry_game_time = backend_mission
		and (tonumber(backend_mission.mmt_expiry_game_time) or tonumber(backend_mission.expiry_game_time))

	if expiry_game_time then
		return (clock.t - expiry_game_time) / 60
	end

	local expiry = backend_mission and tonumber(backend_mission.expiry)

	if not expiry then
		return nil
	end

	return (clock.ms - expiry) / 60000
end

local function mission_is_live(mission)
	local past = minutes_past_expiry(mission)

	return not past or past <= 0
end

local function map_display_name(map)
	local cached = map_name_cache[map]
	if cached then
		return cached
	end

	local settings = MissionTemplates[map]
	local name = settings and settings.mission_name and Localize(settings.mission_name) or map
	map_name_cache[map] = name

	return name
end

local function side_key(mission)
	return mission.side_mission or mission.sideMission or SIDE_NONE
end

local function side_display_name(key)
	if key == SIDE_NONE then
		return mod:localize("side_none")
	end

	local objectives = MissionObjectiveTemplates.side_mission and MissionObjectiveTemplates.side_mission.objectives
	local objective = objectives and objectives[key]

	if objective and objective.header then
		return Localize(objective.header)
	end

	return key
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

return {
	refresh_now = refresh_now,
	convert_expired_missions = convert_expired_missions,
	minutes_past_expiry = minutes_past_expiry,
	mission_is_live = mission_is_live,
	map_display_name = map_display_name,
	side_display_name = side_display_name,
	side_key = side_key,
}
