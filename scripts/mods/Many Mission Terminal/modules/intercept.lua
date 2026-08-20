local mod = get_mod("Many Mission Terminal")
local JWTTicketUtils = require("scripts/multiplayer/utilities/jwt_ticket_utils")
local MissionTemplates = require("scripts/settings/mission/mission_templates")
local PartyConstants = require("scripts/settings/network/party_constants")

local DECIDE_TIMEOUT = 4
local REQUEUE_DELAY = 1.5
local REQUEUE_LIMIT = 8

local Intercept = {}

local is_excluded_fn
local has_exclusions_fn
local skip_backfill_fn
local event_only_fn
local notify_skips_fn
local installed = false
local session_id
local decision
local deadline
local reject_reason
local reject_detail
local queue_code
local queue_private
local queue_reef
local requeue_at
local requeue_count = 0
local unarmed_session
local rejected_sessions = {}

local function now()
	return Managers.time and Managers.time:time("main") or 0
end

local function party()
	return Managers.party_immaterium
end

local function current_session_id()
	local pi = party()

	return pi and pi:current_game_session_id()
end

local function is_quickplay()
	local pi = party()
	local game_state = pi and pi:party_game_state()
	local params = game_state and game_state.params
	local qp = params and params.qp

	if qp == true or qp == "true" then
		return true
	end

	local code = params and params.backend_mission_id

	return type(code) == "string" and string.sub(code, 1, 3) == "qp:"
end

local function clear_session()
	session_id = nil
	decision = nil
	deadline = nil
	reject_reason = nil
	reject_detail = nil
end

local function armed()
	if not queue_code then
		return false
	end

	if not is_quickplay() then
		return false
	end

	if skip_backfill_fn and skip_backfill_fn() then
		return true
	end

	if event_only_fn and event_only_fn() then
		return true
	end

	return is_excluded_fn ~= nil and has_exclusions_fn ~= nil and has_exclusions_fn()
end

local function mission_label(mission)
	local template = mission and mission.map and MissionTemplates[mission.map]

	if template and template.mission_name then
		return Localize(template.mission_name)
	end

	return mission and tostring(mission.map) or "?"
end

local function join_unchecked(why)
	decision = "join"

	mod:info("intercept: %s, joining unchecked", why)

	if notify_skips_fn == nil or notify_skips_fn() then
		mod:notify(mod:localize("intercept_unchecked"))
	end
end

local function decide(sid)
	if rejected_sessions[sid] then
		decision = "reject"

		return
	end

	local backend = Managers.backend
	local interfaces = backend and backend.interfaces
	local gameplay_session = interfaces and interfaces.gameplay_session

	if not gameplay_session then
		decision = "join"

		return
	end

	gameplay_session:fetch_server_details(sid):next(function (body)
		if session_id ~= sid then
			return
		end

		local ticket = body and body.ticket

		if not ticket or ticket == "" then
			join_unchecked("empty ticket")

			return
		end

		local _, payload = JWTTicketUtils.decode_jwt_ticket(ticket)
		local settings = payload and payload.sessionSettings
		local mission = settings and settings.missionJson

		if not mission then
			join_unchecked("ticket carried no missionJson")

			return
		end

		local backfill_blocked = payload.backfill == true and skip_backfill_fn ~= nil and skip_backfill_fn()
		local event_blocked = event_only_fn ~= nil and event_only_fn() and mission.category ~= "event"
		local excluded, why, label = false, "no predicate", nil

		if is_excluded_fn then
			excluded, why, label = is_excluded_fn(mission)
		end

		local verdict = "JOIN"

		if backfill_blocked then
			verdict = "SKIP"
			why = "mission already in progress (backfill)"
			label = nil
		elseif event_blocked then
			verdict = "SKIP"
			why = "category " .. tostring(mission.category) .. " is not an event"
			label = nil
		elseif excluded then
			verdict = "SKIP"
		end

		reject_detail = label

		mod:info("intercept: %s %s [%s] backfill=%s - %s", verdict, tostring(mission.map),
			tostring(mission.circumstance), tostring(payload.backfill), tostring(why))

		if backfill_blocked or event_blocked or excluded then
			rejected_sessions[sid] = mission_label(mission)
			reject_reason = backfill_blocked and "intercept_backfill"
				or event_blocked and "intercept_event_only"
				or "intercept_skipped"
			decision = "reject"
		else
			decision = "join"
			requeue_count = 0
		end
	end):catch(function (error_data)
		if session_id ~= sid then
			return
		end

		join_unchecked("fetch failed")

		mod:dump(error_data, "mmt_intercept_fetch_error", 2)
	end)
end

local function do_reject()
	local pi = party()

	if not pi then
		decision = "join"

		return false
	end

	if not queue_code then
		decision = "join"

		mod:info("intercept: no captured queue code, joining rather than stranding")

		return false
	end

	local label = rejected_sessions[session_id] or "?"

	local search_forever = event_only_fn ~= nil and event_only_fn()

	if not search_forever and requeue_count >= REQUEUE_LIMIT then
		if notify_skips_fn == nil or notify_skips_fn() then
			mod:notify(mod:localize("intercept_limit"))
		end

		decision = "join"

		return false
	end

	local quickest = get_mod("quickest_play")

	if quickest and quickest:is_enabled() and type(quickest.cancel_auto_queue) == "function" then
		quickest.cancel_auto_queue()
	end

	requeue_count = requeue_count + 1

	if notify_skips_fn == nil or notify_skips_fn() then
		local text = string.gsub(mod:localize(reject_reason or "intercept_skipped"), "{mission}", label)

		mod:notify((string.gsub(text, "{why}", reject_detail or "?")))
	end
	pi:leave_party()

	requeue_at = now() + REQUEUE_DELAY

	clear_session()

	return true
end

function Intercept.update()
	if not requeue_at then
		return
	end

	if now() < requeue_at then
		return
	end

	local pi = party()
	local backend = Managers.backend

	if not pi or not backend or not backend:authenticated() then
		return
	end

	if pi:current_state() ~= PartyConstants.State.none then
		return
	end

	if not queue_code then
		requeue_at = nil

		return
	end

	requeue_at = nil

	pi:wanted_mission_selected(queue_code, queue_private, queue_reef)
end

function Intercept.cancel()
	requeue_at = nil
	queue_code = nil
	queue_private = nil
	queue_reef = nil
	requeue_count = 0
	unarmed_session = nil

	table.clear(rejected_sessions)
	clear_session()
end

function Intercept.debug_state()
	return {
		armed = armed(),
		quickplay = is_quickplay(),
		queue_code = queue_code,
		queue_private = queue_private,
		queue_reef = queue_reef,
		session_id = session_id,
		decision = decision,
		reject_reason = reject_reason,
		reject_detail = reject_detail,
		deadline_in = deadline and deadline - now() or nil,
		requeue_in = requeue_at and requeue_at - now() or nil,
		requeue_count = requeue_count,
		rejected_sessions = rejected_sessions,
		has_exclusions = has_exclusions_fn ~= nil and has_exclusions_fn(),
		skip_backfill = skip_backfill_fn ~= nil and skip_backfill_fn(),
		event_only = event_only_fn ~= nil and event_only_fn(),
		notify_skips = notify_skips_fn ~= nil and notify_skips_fn(),
		installed = installed,
	}
end

function Intercept.install(predicate, has_exclusions, skip_backfill, notify_skips, event_only)
	is_excluded_fn = predicate
	has_exclusions_fn = has_exclusions
	skip_backfill_fn = skip_backfill
	event_only_fn = event_only
	notify_skips_fn = notify_skips

	if installed then
		return
	end

	installed = true

	mod:hook(CLASS.PartyImmateriumManager, "wanted_mission_selected", function (func, self, backend_mission_id, private_session, reef)
		if type(backend_mission_id) == "string" and string.sub(backend_mission_id, 1, 3) == "qp:" then
			queue_code = backend_mission_id
			queue_private = private_session
			queue_reef = reef
		end

		return func(self, backend_mission_id, private_session, reef)
	end)

	mod:hook(CLASS.MechanismHub, "_retry_join", function (func, self, ...)
		if requeue_at then
			return
		end

		if not armed() then
			local skipped_sid = current_session_id()

			if skipped_sid and skipped_sid ~= unarmed_session then
				unarmed_session = skipped_sid

				mod:info("intercept: not armed for %s (qp=%s queue_code=%s exclusions=%s backfill_opt=%s)",
					tostring(skipped_sid), tostring(is_quickplay()), tostring(queue_code),
					tostring(has_exclusions_fn ~= nil and has_exclusions_fn()),
					tostring(skip_backfill_fn ~= nil and skip_backfill_fn()))
			end

			return func(self, ...)
		end

		local sid = current_session_id()

		if not sid then
			return func(self, ...)
		end

		if sid ~= session_id then
			clear_session()

			session_id = sid
			deadline = now() + DECIDE_TIMEOUT

			mod:info("intercept: evaluating session %s", tostring(sid))
			decide(sid)

			return
		end

		if decision == "join" then
			queue_code = nil
			queue_private = nil
			queue_reef = nil

			return func(self, ...)
		end
	end)

	mod:hook(CLASS.StateMainMenu, "_show_reconnect_popup", function (func, self, ...)
		if requeue_at then
			return
		end

		if not armed() then
			return func(self, ...)
		end

		local sid = current_session_id()

		if not sid then
			return func(self, ...)
		end

		if sid ~= session_id then
			clear_session()

			session_id = sid
			deadline = now() + DECIDE_TIMEOUT

			mod:info("intercept: evaluating session %s (character select)", tostring(sid))
			decide(sid)

			return
		end

		if decision == "reject" then
			if not do_reject() then
				return func(self, ...)
			end

			return
		end

		if decision == "join" or (deadline and now() > deadline) then
			decision = "join"
			queue_code = nil
			queue_private = nil
			queue_reef = nil

			if type(self._rejoin_game) == "function" then
				self._reconnect_popup_id = nil
				self._reconnect_pressed = true

				self:_rejoin_game()

				return
			end

			return func(self, ...)
		end
	end)

	mod:hook(CLASS.MechanismHub, "_show_retry_popup", function (func, self, ...)
		if requeue_at then
			return
		end

		if not armed() or session_id == nil then
			return func(self, ...)
		end

		if decision == "reject" then
			if not do_reject() then
				self:_retry_join()
			end

			return
		end

		if decision == "join" or (deadline and now() > deadline) then
			decision = "join"

			self:_retry_join()
		end
	end)
end

return Intercept
