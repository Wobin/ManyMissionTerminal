local mod = get_mod("Many Mission Terminal")
local MissionTemplates = require("scripts/settings/mission/mission_templates")
local MissionObjectiveTemplates = require("scripts/settings/mission_objective/mission_objective_templates")
local MissionGiverVoSettings = require("scripts/settings/dialogue/mission_giver_vo_settings")
local DialogueSpeakerVoiceSettings = require("scripts/settings/dialogue/dialogue_speaker_voice_settings")
local DialogueBreedSettings = require("scripts/settings/dialogue/dialogue_breed_settings")

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

local DEFAULT_GIVER = "sergeant_a"
local announcer_rows

local function giver_key(profile)
	local speaker = profile and DialogueSpeakerVoiceSettings[profile]

	return speaker and speaker.full_name
end

local function mission_giver(mission)
	local profile = mission and mission.missionGiver

	if not profile or profile == "none" then
		local template = mission and MissionTemplates[mission.map]
		local brief = template and template.mission_brief_vo

		profile = brief and brief.vo_profile
	end

	return profile or DEFAULT_GIVER
end

local function mission_giver_key(mission)
	return giver_key(mission_giver(mission))
end

local function pack_voice_keys(mission, giver, keys)
	local template = mission and MissionTemplates[mission.map]
	local brief = template and template.mission_brief_vo
	local packs = brief and brief.mission_giver_packs
	local pack = packs and packs[giver]

	if not pack then
		return keys
	end

	for i = 1, #pack do
		local settings = DialogueBreedSettings[pack[i]]
		local voices = settings and settings.wwise_voices

		if voices then
			for j = 1, #voices do
				local key = giver_key(voices[j])

				if key then
					keys[key] = true
				end
			end
		end
	end

	return keys
end

local function mission_voice_keys(mission)
	local giver = mission_giver(mission)
	local keys = {}

	return pack_voice_keys(mission, giver, keys), giver_key(giver)
end

local function board_eligible(template)
	return not template.not_available_on_mission_board
		and not C.EXCLUDE_MISSION_TYPES[template.mission_type]
end

local function announcers()
	if announcer_rows then
		return announcer_rows
	end

	announcer_rows = {}

	local seen = {}

	local function add(profile)
		local speaker = profile ~= "none" and DialogueSpeakerVoiceSettings[profile]
		local key = speaker and speaker.full_name

		if key and not seen[key] then
			seen[key] = true
			announcer_rows[#announcer_rows + 1] = {
				key = key,
				label = Localize(speaker.short_name or key),
			}
		end
	end

	for profile in pairs(MissionGiverVoSettings.overrides) do
		add(profile)
	end

	for _, template in pairs(MissionTemplates) do
		local brief = template.mission_brief_vo
		local packs = brief and brief.mission_giver_packs

		if packs and board_eligible(template) then
			for _, units in pairs(packs) do
				for i = 1, #units do
					local settings = DialogueBreedSettings[units[i]]
					local voices = settings and settings.wwise_voices

					if voices then
						for j = 1, #voices do
							add(voices[j])
						end
					end
				end
			end
		end
	end

	table.sort(announcer_rows, function (a, b)
		return a.label < b.label
	end)

	return announcer_rows
end

return {
	refresh_now = refresh_now,
	mission_giver = mission_giver,
	mission_giver_key = mission_giver_key,
	mission_voice_keys = mission_voice_keys,
	giver_key = giver_key,
	announcers = announcers,
	convert_expired_missions = convert_expired_missions,
	minutes_past_expiry = minutes_past_expiry,
	mission_is_live = mission_is_live,
	map_display_name = map_display_name,
	side_display_name = side_display_name,
	side_key = side_key,
}
