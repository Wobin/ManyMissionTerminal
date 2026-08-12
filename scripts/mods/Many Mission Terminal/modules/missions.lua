local MissionTemplates = require("scripts/settings/mission/mission_templates")

local map_name_cache = {}
local now_ms = os.time() * 1000
local now_t = 0

local function refresh_now()
	now_ms = os.time() * 1000
	now_t = Managers.time and Managers.time:time("main") or now_t

	return now_ms
end

local function minutes_past_expiry(backend_mission)
	local expiry_game_time = backend_mission
		and (tonumber(backend_mission.mmt_expiry_game_time) or tonumber(backend_mission.expiry_game_time))

	if expiry_game_time then
		return (now_t - expiry_game_time) / 60
	end

	local expiry = backend_mission and tonumber(backend_mission.expiry)

	if not expiry then
		return nil
	end

	return (now_ms - expiry) / 60000
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

return {
	refresh_now = refresh_now,
	minutes_past_expiry = minutes_past_expiry,
	mission_is_live = mission_is_live,
	map_display_name = map_display_name,
}
