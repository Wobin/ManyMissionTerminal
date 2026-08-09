local MissionTemplates = require("scripts/settings/mission/mission_templates")

local map_name_cache = {}
local now_ms = os.time() * 1000

local function refresh_now()
	now_ms = os.time() * 1000

	return now_ms
end

local function minutes_past_expiry(backend_mission)
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
