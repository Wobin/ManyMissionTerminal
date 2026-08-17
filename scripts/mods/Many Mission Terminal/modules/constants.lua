local mod = get_mod("Many Mission Terminal")

local GRID_COLS = 8
local GRID_ROWS = 3
local GRID_X0 = -84
local GRID_X1 = 831
local GRID_ROW_Y = {
	60,
	300,
	540,
}
local TILE_SCALE = 0.85
local BANNER_GAP = 13
local BADGE_TEXT_BOUNDS = {
	2000,
	2000,
}

local PLAIN_STYLES = {
	"mission_type_banner",
	"mission_type_banner_text",
	"mission_type_icon",
	"mission_type_frame",
}

local GRADIENT_STYLES = {
	"selected_frame_detail",
	"selected_frame_glow",
	"background_frame",
	"main_objective_frame",
	"main_objective_icon",
	"side_objective_icon",
}

local NOTABLE_CATEGORY = {
	event = true,
	maelstrom = true,
}

local CATEGORY_ORDER = {
	maelstrom = 1,
	event = 2,
	story = 3,
	common = 4,
}

local HORIZON_MINUTES = 180

local TILE_BOX_W = 72
local TILE_BOX_H = 82.8
local TILE_PLATE_W = 170
local TILE_PLATE_H = 204

local GRID_AREA_X0 = GRID_X0
local GRID_AREA_X1 = GRID_X1 + TILE_BOX_W * TILE_SCALE
local GRID_AREA_Y0 = GRID_ROW_Y[1]
local GRID_AREA_Y1 = GRID_ROW_Y[GRID_ROWS] + TILE_BOX_H * TILE_SCALE
local GRID_CENTRE_X = (GRID_X0 + GRID_X1) * 0.5 + TILE_BOX_W * 0.5
local GRID_CENTRE_Y = (GRID_ROW_Y[1] + GRID_ROW_Y[GRID_ROWS]) * 0.5 + TILE_BOX_H * 0.5

local GRID_SAFE_X1 = 1100

local EXPAND_SCALE = 1
local EXPAND_COLS = 4
local EXPAND_SPACING_X = 200
local EXPAND_SPACING_Y = 240
local EXPAND_SLOT_RESERVE = 12
local FADE_ALPHA = 0.15

local EXPAND_Z = 100

local BADGE = {
	size = 34,
	dx = 0,
	dy = 29,
	grow_factor = 0.25,
	z = 250,
	material = "content/ui/materials/symbols/character_level",
}

local TOOLTIP = {
	height = 32,
	pad = 18,
	gap = 10,
	card_dy = 50,
	min_y = 4,
	z = 500,
	bounds = {
		2000,
		2000,
	},
}

local SCRIM = {
	x = -160,
	y = -20,
	w = 1477,
	h = 940,
	z = 50,
	color = {
		100,
		0,
		0,
		0,
	},
}

local FILTER = {
	anchor = "corner_top_left",
	width = 330,
	top = 90,
	pad = 22,
	group_height = 34,
	row_height = 30,
	box_size = 18,
	tab_width = 42,
	tab_icon = 24,
	tab_height = 42,
	slide_rate = 9,
	z = 300,
	side_none = "none",
	tab_bar_height = 34,
	tab_pad = 14,
	row_pad = 18,
	bottom_margin = 48,
	scroll_step = 54,
	bar_width = 5,
	bar_inset = 6,
	canvas_height = 1080,
}

local FILTER_TABS = {
	{
		key = "filters",
		mod_loc = "tab_filters",
	},
	{
		key = "exclusions",
		mod_loc = "tab_exclusions",
	},
}

local EXCLUDE_MISSION_TYPES = {
	expeditions = true,
	horde = true,
}

local FILTER_CATEGORIES = {
	{
		key = "maelstrom",
		game_loc = "loc_mission_board_maelstrom_header",
	},
	{
		key = "event",
		game_loc = "loc_mission_board_mission_category_event",
	},
	{
		key = "common",
		mod_loc = "cat_common",
	},
	{
		key = "story",
		mod_loc = "cat_story",
		off_by_default = true,
	},
}

local FILTER_CONDITIONS = {
	{
		key = "daemonhosts",
		mod_loc = "cond_daemonhosts",
		mutators = {
			"mutator_more_witches",
		},
	},
	{
		key = "hounds",
		mod_loc = "cond_hounds",
		mutators = {
			"mutator_chaos_hounds",
		},
	},
	{
		key = "monsters",
		mod_loc = "cond_monsters",
		mutators = {
			"mutator_monster_specials",
			"mutator_more_monsters",
		},
	},
	{
		key = "mutants",
		mod_loc = "cond_mutants",
		mutators = {
			"mutator_mutants",
		},
	},
	{
		key = "poxbursters",
		mod_loc = "cond_poxbursters",
		mutators = {
			"mutator_poxwalker_bombers",
		},
	},
	{
		key = "snipers",
		mod_loc = "cond_snipers",
		mutators = {
			"mutator_snipers",
		},
	},
	{
		key = "specials",
		mod_loc = "cond_specials",
		mutators = {
			"mutator_waves_of_specials",
		},
	},
	{
		key = "darkness",
		mod_loc = "cond_darkness",
		mutators = {
			"mutator_darkness_los",
		},
	},
	{
		key = "gas",
		mod_loc = "cond_gas",
		mutators = {
			"mutator_toxic_gas_volumes",
		},
	},
	{
		key = "purge",
		mod_loc = "cond_purge",
		mutators = {
			"mutator_ventilation_purge_los",
		},
	},
	{
		key = "resistance",
		mod_loc = "cond_resistance",
		mutators = {
			"mutator_add_resistance",
		},
	},
}

local MTABLE = {
	width = 660,
	title_height = 44,
	header_height = 28,
	row_height = 34,
	pad = 18,
	icon = 24,
	z = 400,
	max_rows = 12,
	dx = 114,
	dy = 125,
	bar_width = 76,
	bar_height = 10,
	col_bar = 0,
	col_time = 88,
	col_type = 192,
	col_cond = 252,
	col_side = 332,
	col_conds = 400,
	col_saved = 570,
	cond_slots = 5,
	cond_slot = 32,
	col_w = {
		type = 52,
		cond = 72,
		side = 52,
		saved = 32,
	},
}

local CONDITION_ICONS = {
	specials = "content/ui/materials/mission_board/circumstances/special_waves_01",
	resistance = "content/ui/materials/mission_board/circumstances/more_resistance_01",
	hounds = "content/ui/materials/mission_board/circumstances/hunting_grounds_01",
	darkness = "content/ui/materials/mission_board/circumstances/darkness_01",
	purge = "content/ui/materials/mission_board/circumstances/ventilation_purge_01",
	gas = "content/ui/materials/mission_board/circumstances/nurgle_manifestation_01",
	monsters = "content/ui/materials/icons/circumstances/havoc/havoc_mutator_final_toll",
	mutants = "content/ui/materials/icons/difficulty/difficulty_skull_auric",
	snipers = "content/ui/materials/icons/mission_types/mission_type_02",
	daemonhosts = "content/ui/materials/icons/circumstances/havoc/havoc_mutator_heinous_rituals",
	poxbursters = "content/ui/materials/icons/circumstances/havoc/havoc_mutator_nurgle",
}

local CONDITION_TAGS = {
	monsters = "MON",
	mutants = "MUT",
	snipers = "SNP",
	daemonhosts = "DMN",
	poxbursters = "POX",
}

local BOOKMARK_ICON = "content/ui/materials/icons/generic/bookmark"

local SIDE_ICONS = {
	side_mission_grimoire = "content/ui/materials/icons/pocketables/hud/small/party_grimoire",
	side_mission_tome = "content/ui/materials/icons/pocketables/hud/small/party_scripture",
}

local ARCHIVE_URL = "https://darktide.dpdns.org/v1/live"
local ARCHIVE_REFRESH_SECONDS = 600
local ARCHIVE_RETRY_BASE = 15
local ARCHIVE_RETRY_MAX = 300
local LIVE_BAR_COLOR = {
	255,
	101,
	145,
	102,
}

local EXPIRED_BAR_COLOR = {
	255,
	232,
	138,
	46,
}

local FADE_COLOR_KEYS = {
	"color",
	"default_color",
	"text_color",
}

local INCOMPATIBLE_MODS = {
	"MissionGrid",
	"StoryReplay",
	"sorted_mission_grid",
}

return {
	MTABLE = MTABLE,
	CONDITION_ICONS = CONDITION_ICONS,
	CONDITION_TAGS = CONDITION_TAGS,
	SIDE_ICONS = SIDE_ICONS,
	BOOKMARK_ICON = BOOKMARK_ICON,
	GRID_COLS = GRID_COLS,
	GRID_ROWS = GRID_ROWS,
	GRID_X0 = GRID_X0,
	GRID_X1 = GRID_X1,
	GRID_ROW_Y = GRID_ROW_Y,
	TILE_SCALE = TILE_SCALE,
	BANNER_GAP = BANNER_GAP,
	BADGE_TEXT_BOUNDS = BADGE_TEXT_BOUNDS,
	PLAIN_STYLES = PLAIN_STYLES,
	GRADIENT_STYLES = GRADIENT_STYLES,
	NOTABLE_CATEGORY = NOTABLE_CATEGORY,
	CATEGORY_ORDER = CATEGORY_ORDER,
	HORIZON_MINUTES = HORIZON_MINUTES,
	TILE_BOX_W = TILE_BOX_W,
	TILE_BOX_H = TILE_BOX_H,
	TILE_PLATE_W = TILE_PLATE_W,
	TILE_PLATE_H = TILE_PLATE_H,
	GRID_AREA_X0 = GRID_AREA_X0,
	GRID_AREA_X1 = GRID_AREA_X1,
	GRID_AREA_Y0 = GRID_AREA_Y0,
	GRID_AREA_Y1 = GRID_AREA_Y1,
	GRID_SAFE_X1 = GRID_SAFE_X1,
	GRID_CENTRE_X = GRID_CENTRE_X,
	GRID_CENTRE_Y = GRID_CENTRE_Y,
	EXPAND_SCALE = EXPAND_SCALE,
	EXPAND_COLS = EXPAND_COLS,
	EXPAND_SPACING_X = EXPAND_SPACING_X,
	EXPAND_SPACING_Y = EXPAND_SPACING_Y,
	EXPAND_SLOT_RESERVE = EXPAND_SLOT_RESERVE,
	FADE_ALPHA = FADE_ALPHA,
	EXPAND_Z = EXPAND_Z,
	BADGE = BADGE,
	TOOLTIP = TOOLTIP,
	SCRIM = SCRIM,
	FILTER = FILTER,
	FILTER_CATEGORIES = FILTER_CATEGORIES,
	FILTER_CONDITIONS = FILTER_CONDITIONS,
	FILTER_TABS = FILTER_TABS,
	EXCLUDE_MISSION_TYPES = EXCLUDE_MISSION_TYPES,
	ARCHIVE_URL = ARCHIVE_URL,
	ARCHIVE_REFRESH_SECONDS = ARCHIVE_REFRESH_SECONDS,
	ARCHIVE_RETRY_BASE = ARCHIVE_RETRY_BASE,
	ARCHIVE_RETRY_MAX = ARCHIVE_RETRY_MAX,
	LIVE_BAR_COLOR = LIVE_BAR_COLOR,
	EXPIRED_BAR_COLOR = EXPIRED_BAR_COLOR,
	FADE_COLOR_KEYS = FADE_COLOR_KEYS,
	INCOMPATIBLE_MODS = INCOMPATIBLE_MODS,
}
