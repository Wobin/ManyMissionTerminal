local mod = get_mod("Many Mission Terminal")
local MissionTemplates = require("scripts/settings/mission/mission_templates")

local C = mod:io_dofile("Many Mission Terminal/scripts/mods/Many Mission Terminal/modules/constants")
local HORIZON_MINUTES = C.HORIZON_MINUTES
local ARCHIVE_URL = C.ARCHIVE_URL
local ARCHIVE_REFRESH_SECONDS = C.ARCHIVE_REFRESH_SECONDS
local ARCHIVE_RETRY_BASE = C.ARCHIVE_RETRY_BASE
local ARCHIVE_RETRY_MAX = C.ARCHIVE_RETRY_MAX

local archive_missions = {}
local archive_fetched_at = 0
local archive_pending = false
local archive_challenge
local archive_resistance
local archive_server_time
local archive_failures = 0
local archive_retry_at = 0
local archive_dirty = false
local archive_injected_into

local function archive_backoff()
	local delay = ARCHIVE_RETRY_BASE * math.pow(2, math.min(archive_failures - 1, 5))

	return math.min(delay, ARCHIVE_RETRY_MAX)
end

local function archive_page_filter(logic)
	local page = logic and logic:get_current_page()

	return page and page.filter
end

local function convert_archive_mission(raw, t, server_now_ms)
	local mission = table.clone(raw)
	local past = (server_now_ms - (tonumber(raw.expiry) or 0)) / 60000
	local remaining = math.max(HORIZON_MINUTES - past, 0)

	mission.mmt_archive = true
	mission.mmt_expiry_game_time = ((tonumber(raw.expiry) or 0) - server_now_ms) / 1000 + t

	if past > 0 then
		mission.expiry_game_time = t + remaining * 60
		mission.start_game_time = mission.expiry_game_time - HORIZON_MINUTES * 60
	else
		mission.start_game_time = t - 1
		mission.expiry_game_time = t + math.max(-past, 1) * 60
	end
	mission.start_server_time = raw.start
	mission.expiry_server_time = raw.expiry
	mission.required_level = raw.requiredLevel or 0
	mission.side_mission = raw.sideMission
	mission.mission_xp = raw.xp or 0
	mission.mission_reward = raw.credits or 0
	mission.flags = raw.flags or {}

	return mission
end

local function fetch_archive(logic)
	if archive_pending then
		return
	end

	local filter = archive_page_filter(logic)
	if not filter then
		return
	end

	local challenge = filter.challenge or 0
	local resistance = filter.resistance or 0
	local now = os.time()

	if now < archive_retry_at then
		return
	end

	local have_data = #archive_missions > 0
		and challenge == archive_challenge
		and resistance == archive_resistance

	if have_data and now - archive_fetched_at < ARCHIVE_REFRESH_SECONDS then
		return
	end

	local backend = Managers.backend
	if not backend or not backend:authenticated() then
		return
	end

	local url = string.format("%s?challenge=%d&resistance=%d&grace=%d",
		ARCHIVE_URL,
		challenge,
		resistance,
		HORIZON_MINUTES)

	archive_pending = true

	backend:url_request(url, {
		require_auth = false,
	}):next(function (data)
		archive_pending = false

		archive_fetched_at = os.time()
		archive_challenge = challenge
		archive_resistance = resistance

		local body = data and data.body
		if type(body) ~= "table" or type(body.missions) ~= "table" then
			archive_failures = archive_failures + 1
			archive_retry_at = archive_fetched_at + archive_backoff()

			return
		end

		archive_missions = body.missions
		local server_time = tonumber(body.server_time)

		archive_server_time = server_time and server_time > 1e12 and server_time or nil
		archive_failures = 0
		archive_retry_at = 0
		archive_dirty = true
	end):catch(function (error_data)
		archive_pending = false
		archive_fetched_at = os.time()
		archive_challenge = challenge
		archive_resistance = resistance
		archive_failures = archive_failures + 1
		archive_retry_at = archive_fetched_at + archive_backoff()

		mod:dump(error_data, "mmt_archive_fetch_error", 2)
	end)
end

local function inject_archive(logic, t)
	local mission_data = logic._mission_data

	if not mission_data then
		return false
	end

	if not archive_dirty and archive_injected_into == mission_data then
		return false
	end

	if #archive_missions == 0 then
		return false
	end

	archive_dirty = false
	archive_injected_into = mission_data

	local server_now_ms = archive_server_time or os.time() * 1000

	local existing = {}
	for _, mission in ipairs(logic._mission_data or {}) do
		existing[mission.id] = true
	end

	local added = 0
	for i = 1, #archive_missions do
		local raw = archive_missions[i]
		if raw.id and not existing[raw.id] and MissionTemplates[raw.map] then
			logic._mission_data[#logic._mission_data + 1] = convert_archive_mission(raw, t, server_now_ms)
			added = added + 1
		end
	end

	return added > 0
end

return {
	fetch = fetch_archive,
	inject = inject_archive,
}
