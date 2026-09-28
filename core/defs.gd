class_name Defs
extends RefCounted
## Static game data. Everything tunable lives here; nothing here touches nodes.

const TICK_SECONDS := 0.6
const MAX_LEVEL := 100
const PACK_SLOTS := 28

# ---------------------------------------------------------------- skills

const SKILLS := ["melee", "archery", "hitpoints", "woodcutting", "mining", "fletching", "smithing"]
const SKILL_NAMES := {
	"melee": "Melee", "archery": "Archery", "hitpoints": "Hitpoints",
	"woodcutting": "Woodcutting", "mining": "Mining",
	"fletching": "Fletching", "smithing": "Smithing",
}
const SKILL_BLURBS := {
	"melee": "Melee accuracy and max hit.",
	"archery": "Bow accuracy and max hit.",
	"hitpoints": "Health, and how hard you are to hit.",
	"woodcutting": "Chop speed, log access, rarity and tier rolls on logs.",
	"mining": "Mining speed, ore access, rarity and tier rolls on ore.",
	"fletching": "Wooden recipes and their base quality.",
	"smithing": "Metal recipes and their base quality.",
}
const START_LEVELS := {"hitpoints": 10}

## Cumulative XP needed to reach `level`.
static func xp_for_level(level: int) -> int:
	if level <= 1:
		return 0
	return int(floor(5.0 * pow(level - 1, 2.1)))

static func level_for_xp(xp: float) -> int:
	var lv := 1
	while lv < MAX_LEVEL and xp >= xp_for_level(lv + 1):
		lv += 1
	return lv

## Highest affix tier a level (or a resource's requirement) can reach.
static func tier_ceiling(level: int) -> int:
	return clampi(1 + level / 18, 1, 6)

# ---------------------------------------------------------------- rarity & modifiers

const RARITIES := ["Junk", "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic"]
const RARITY_COLORS := [
	Color("7d766a"), Color("ddd5c4"), Color("8fbf5f"), Color("5f9fd8"),
	Color("b27ad6"), Color("e8913a"), Color("e8433a"),
]
const RARITY_WEIGHTS := [34.0, 36.0, 17.0, 8.0, 3.5, 1.2, 0.3]
const TIER_NUMERALS := ["", "I", "II", "III", "IV", "V", "VI"]

## Modifier pool, shared by logs and ore.
const MODS := {
	"might":     {"name": "Might",     "stat": "power",    "per_tier": 3, "weight": 1.0},
	"precision": {"name": "Precision", "stat": "accuracy", "per_tier": 4, "weight": 1.0},
	"vigor":     {"name": "Vigor",     "stat": "max_hp",   "per_tier": 2, "weight": 1.0},
	"guard":     {"name": "Guard",     "stat": "armour",   "per_tier": 4, "weight": 1.0},
	"echo":      {"name": "Echo",      "stat": "echo",     "per_tier": 1, "weight": 0.45},
}
const MOD_ORDER := ["might", "precision", "vigor", "guard", "echo"]

## Echo: every Nth attack strikes twice. More Echo, shorter rhythm.
static func echo_interval(echo_total: int) -> int:
	if echo_total <= 0:
		return 0
	return maxi(3, 9 - echo_total)

static func mod_value_text(mod_id: String, total: int) -> String:
	if mod_id == "echo":
		return "every %s attack strikes twice" % ordinal(echo_interval(total))
	var stat_names := {"power": "Power", "accuracy": "Accuracy", "max_hp": "Hitpoints", "armour": "Armour"}
	return "+%d %s" % [total * int(MODS[mod_id].per_tier), stat_names[MODS[mod_id].stat]]

static func ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1: suffix = "st"
			2: suffix = "nd"
			3: suffix = "rd"
	return "%d%s" % [n, suffix]

# ---------------------------------------------------------------- resources

## family: "log" (Woodcutting) or "ore" (Mining). `mat` indexes base item stats.
const RESOURCES := {
	"pine":       {"name": "Pine",       "family": "log", "req": 1,  "mat": 1, "xp": 10.0,  "chance": 0.34, "yield": [3, 5], "respawn": 12, "node": "Pine tree"},
	"oak":        {"name": "Oak",        "family": "log", "req": 15, "mat": 2, "xp": 22.0,  "chance": 0.28, "yield": [4, 6], "respawn": 16, "node": "Oak tree"},
	"maple":      {"name": "Maple",      "family": "log", "req": 30, "mat": 3, "xp": 38.0,  "chance": 0.24, "yield": [4, 7], "respawn": 20, "node": "Maple tree"},
	"ironwood":   {"name": "Ironwood",   "family": "log", "req": 40, "mat": 4, "xp": 55.0,  "chance": 0.20, "yield": [5, 8], "respawn": 25, "node": "Ironwood tree"},
	"elderheart": {"name": "Elderheart", "family": "log", "req": 90, "mat": 9, "xp": 160.0, "chance": 0.12, "yield": [6, 9], "respawn": 60, "node": "Elderheart"},
	"copper":     {"name": "Copper",     "family": "ore", "req": 1,  "mat": 1, "xp": 10.0,  "chance": 0.34, "yield": [3, 5], "respawn": 12, "node": "Copper rock"},
	"iron":       {"name": "Iron",       "family": "ore", "req": 15, "mat": 2, "xp": 22.0,  "chance": 0.28, "yield": [4, 6], "respawn": 16, "node": "Iron rock"},
	"duskiron":   {"name": "Duskiron",   "family": "ore", "req": 30, "mat": 3, "xp": 38.0,  "chance": 0.24, "yield": [4, 7], "respawn": 20, "node": "Duskiron rock"},
	"emberite":   {"name": "Emberite",   "family": "ore", "req": 40, "mat": 4, "xp": 55.0,  "chance": 0.20, "yield": [5, 8], "respawn": 25, "node": "Emberite rock"},
	"sunsteel":   {"name": "Sunsteel",   "family": "ore", "req": 90, "mat": 9, "xp": 160.0, "chance": 0.12, "yield": [6, 9], "respawn": 60, "node": "Sunsteel vein"},
}
const FAMILY_SKILL := {"log": "woodcutting", "ore": "mining"}
const FAMILY_NOUN := {"log": "Log", "ore": "Ore"}

static func component_name(res_id: String) -> String:
	var r: Dictionary = RESOURCES[res_id]
	return "%s %s" % [r.name, FAMILY_NOUN[r.family]]

# ---------------------------------------------------------------- recipes

## Base stats scale with the material index `m`. `req_offset` is added to the
## material's level. Recipes consume `count` components of one resource.
const RECIPES := {
	"shortbow": {"name": "Shortbow", "skill": "fletching", "family": "log", "count": 3, "req_offset": 0,
		"slot": "weapon", "style": "archery", "speed": 4, "range": 7,
		"acc": [4, 7], "power": [1, 3], "armour": [0, 0]},
	"longbow": {"name": "Longbow", "skill": "fletching", "family": "log", "count": 4, "req_offset": 6,
		"slot": "weapon", "style": "archery", "speed": 5, "range": 9,
		"acc": [6, 8], "power": [2, 5], "armour": [0, 0]},
	"buckler": {"name": "Buckler", "skill": "fletching", "family": "log", "count": 2, "req_offset": 3,
		"slot": "shield", "armour": [3, 5], "acc": [0, 0], "power": [0, 0]},
	"sword": {"name": "Sword", "skill": "smithing", "family": "ore", "count": 3, "req_offset": 0,
		"slot": "weapon", "style": "melee", "speed": 4, "range": 1,
		"acc": [5, 7], "power": [2, 4], "armour": [0, 0]},
	"warhammer": {"name": "Warhammer", "skill": "smithing", "family": "ore", "count": 4, "req_offset": 6,
		"slot": "weapon", "style": "melee", "speed": 6, "range": 1,
		"acc": [3, 5], "power": [5, 8], "armour": [0, 0]},
	"helm": {"name": "Helm", "skill": "smithing", "family": "ore", "count": 2, "req_offset": 2,
		"slot": "head", "armour": [3, 4], "acc": [0, 0], "power": [0, 0]},
	"cuirass": {"name": "Cuirass", "skill": "smithing", "family": "ore", "count": 4, "req_offset": 8,
		"slot": "body", "armour": [6, 8], "acc": [0, 0], "power": [0, 0]},
}
const RECIPE_ORDER := ["shortbow", "longbow", "buckler", "sword", "warhammer", "helm", "cuirass"]
const SLOTS := ["weapon", "shield", "head", "body"]
const SLOT_NAMES := {"weapon": "Weapon", "shield": "Shield", "head": "Head", "body": "Body"}

static func recipe_req(recipe_id: String, res_id: String) -> int:
	return int(RESOURCES[res_id].req) + int(RECIPES[recipe_id].req_offset)

static func base_stat(pair: Array, mat: int) -> int:
	return int(pair[0]) + int(pair[1]) * (mat - 1)

# ---------------------------------------------------------------- reagent

const REAGENT_ID := "cinder_shard"
const REAGENT_NAME := "Cinder Shard"

# ---------------------------------------------------------------- creatures

## atk/def are levels, acc/armour are bonuses. `aggro` 0 means passive.
const MOBS := {
	"thornling": {"name": "Thornling", "combat": 3, "hp": 8, "atk": 2, "def": 2, "acc": 0, "armour": 0,
		"max_hit": 1, "speed": 5, "range": 1, "aggro": 0, "shard": 0.03, "respawn": 20},
	"wolf": {"name": "Dire Wolf", "combat": 14, "hp": 20, "atk": 12, "def": 10, "acc": 8, "armour": 6,
		"max_hit": 3, "speed": 4, "range": 1, "aggro": 4, "shard": 0.05, "respawn": 25},
	"crawler": {"name": "Cave Crawler", "combat": 11, "hp": 16, "atk": 8, "def": 14, "acc": 4, "armour": 22,
		"max_hit": 2, "speed": 4, "range": 1, "aggro": 0, "shard": 0.05, "respawn": 25},
	"golem": {"name": "Slag Golem", "combat": 28, "hp": 45, "atk": 24, "def": 22, "acc": 12, "armour": 30,
		"max_hit": 6, "speed": 6, "range": 1, "aggro": 3, "shard": 0.10, "respawn": 35},
	"revenant": {"name": "Ashen Revenant", "combat": 36, "hp": 50, "atk": 32, "def": 28, "acc": 20, "armour": 18,
		"max_hit": 7, "speed": 5, "range": 6, "aggro": 5, "shard": 0.12, "respawn": 40},
	"imp": {"name": "Slag Imp", "combat": 18, "hp": 10, "atk": 22, "def": 6, "acc": 10, "armour": 0,
		"max_hit": 2, "speed": 4, "range": 1, "aggro": 12, "shard": 0.0, "respawn": 0},
	"warden": {"name": "Cinder Warden", "combat": 64, "hp": 240, "atk": 48, "def": 34, "acc": 30, "armour": 30,
		"max_hit": 0, "speed": 5, "range": 1, "aggro": 0, "shard": 1.0, "respawn": 0, "size": 2},
}

const COMBAT_XP_PER_DAMAGE := 8.0
const HITPOINTS_XP_PER_DAMAGE := 6.0

# ---------------------------------------------------------------- boards

const BOARDS := {
	"combat": {"name": "Combat", "skills": ["melee|archery", "hitpoints"]},
	"gathering": {"name": "Gathering", "skills": ["woodcutting", "mining"]},
	"production": {"name": "Production", "skills": ["fletching", "smithing"]},
}
const BOARD_ORDER := ["combat", "gathering", "production"]
const LEVELS_PER_BOARD_POINT := 8
const BOARD_PERK_COUNT := 5

## Graph per board: a and b open from the root; c needs a, d needs b; e needs c or d.
const PERKS := {
	"combat": [
		{"id": "first_blood", "slot": "a", "name": "First Blood", "desc": "Your first swing at an unhurt target has double accuracy."},
		{"id": "footwork", "slot": "b", "name": "Footwork", "desc": "Attacking within 2 ticks of a step adds 2 to max hit."},
		{"id": "iron_hide", "slot": "c", "name": "Iron Hide", "desc": "Every hit you take deals 1 less damage."},
		{"id": "second_wind", "slot": "d", "name": "Second Wind", "desc": "Falling below 30% health restores 25% of it. Once per 200 ticks."},
		{"id": "read_the_tell", "slot": "e", "name": "Read the Tell", "desc": "Dodging a telegraphed strike makes your next attack certain to hit, with 3 more max hit."},
	],
	"gathering": [
		{"id": "keen_eye", "slot": "a", "name": "Keen Eye", "desc": "Rarity rolls count as 10 levels higher."},
		{"id": "swift_hands", "slot": "b", "name": "Swift Hands", "desc": "15% more gathering successes."},
		{"id": "double_haul", "slot": "c", "name": "Double Haul", "desc": "12% chance to gather a second component."},
		{"id": "deep_seam", "slot": "d", "name": "Deep Seam", "desc": "Trees and rocks yield half again before depleting."},
		{"id": "tier_sense", "slot": "e", "name": "Tier Sense", "desc": "Tier rolls lean toward the resource's ceiling."},
	],
	"production": [
		{"id": "thrift", "slot": "a", "name": "Thrift", "desc": "10% chance a craft returns its weakest ingredient."},
		{"id": "masterwork", "slot": "b", "name": "Masterwork", "desc": "Crafts gain 1 quality."},
		{"id": "guided_temper", "slot": "c", "name": "Guided Temper", "desc": "You choose which modifier a Cinder Shard upgrades."},
		{"id": "salvage", "slot": "d", "name": "Salvage", "desc": "Break crafted gear into Cinder Shards: one per three modifiers."},
		{"id": "resonance", "slot": "e", "name": "Resonance", "desc": "A modifier present three or more times gains one tier's worth of value."},
	],
}
const PERK_REQUIRES := {"a": [], "b": [], "c": ["a"], "d": ["b"], "e": ["c", "d"]}

static func perk_def(perk_id: String) -> Dictionary:
	for board in PERKS:
		for p in PERKS[board]:
			if p.id == perk_id:
				return p
	return {}

static func perk_board(perk_id: String) -> String:
	for board in PERKS:
		for p in PERKS[board]:
			if p.id == perk_id:
				return board
	return ""
