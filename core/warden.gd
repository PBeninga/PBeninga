class_name Warden
extends RefCounted
## The Cinder Warden's pattern book. Every strike is telegraphed on tiles
## before it lands; the only unmarked damage is the Slag Imps and the burning
## rim in the last phase, both visible on the floor.

const PHASES := {
	1: {"name": "The Anvil", "cadence": 5, "rotation": ["cleave", "cleave", "hammerfall"], "mobile": true},
	2: {"name": "The Bellows", "cadence": 4, "rotation": ["lanes_even", "toss", "lanes_odd", "toss"], "mobile": false},
	3: {"name": "The Collapse", "cadence": 4, "rotation": ["cleave", "cross", "cleave", "hammerfall"], "mobile": true},
}
const THRESHOLDS := {1: 0.66, 2: 0.33}
const TRANSITION_TICKS := 4
const WAKE_TICKS := 3

## lead: ticks from mark to landing. why: shown in the death recap.
const ATTACKS := {
	"cleave":     {"name": "Cleave",     "lead": 2, "dmg": [10, 14], "why": "stood on the side the Warden swung at"},
	"toss":       {"name": "Ember Toss", "lead": 2, "dmg": [8, 10],  "why": "stayed inside the thrown square"},
	"hammerfall": {"name": "Hammerfall", "lead": 3, "dmg": [16, 20], "why": "stayed within two tiles of the Warden"},
	"lanes_even": {"name": "Flame Lanes", "lead": 3, "dmg": [11, 13], "why": "stood on a marked column"},
	"lanes_odd":  {"name": "Flame Lanes", "lead": 3, "dmg": [11, 13], "why": "stood on a marked column"},
	"cross":      {"name": "Sundering Cross", "lead": 2, "dmg": [13, 15], "why": "stayed on the marked row or column"},
}

var active := false
var phase := 1
var rot_index := 0
var next_action := 0
var busy_until := 0       # rooted while winding up or changing phase
var invulnerable_until := 0
var rim_burning := false
var started_tick := 0
var mob_id := -1

func reset() -> void:
	active = false
	phase = 1
	rot_index = 0
	next_action = 0
	busy_until = 0
	invulnerable_until = 0
	rim_burning = false

func start(tick: int) -> void:
	reset()
	active = true
	started_tick = tick
	next_action = tick + WAKE_TICKS
	busy_until = tick + WAKE_TICKS
	invulnerable_until = tick + WAKE_TICKS

func phase_def() -> Dictionary:
	return PHASES[phase]

func next_attack_id() -> String:
	var rot: Array = PHASES[phase].rotation
	return rot[rot_index % rot.size()]

## Tiles an attack will strike, given the Warden's rect and player tile.
static func attack_tiles(kind: String, boss: Rect2i, player: Vector2i, arena: Rect2i) -> Array:
	var out := []
	match kind:
		"cleave":
			var band := _cleave_band(boss, player)
			for p in band:
				if arena.has_point(p):
					out.append(p)
		"toss":
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var p := player + Vector2i(dx, dy)
					if arena.has_point(p) and not boss.has_point(p):
						out.append(p)
		"hammerfall":
			var r := boss.grow(2)
			for y in range(r.position.y, r.end.y):
				for x in range(r.position.x, r.end.x):
					var p := Vector2i(x, y)
					if arena.has_point(p) and not boss.has_point(p):
						out.append(p)
		"lanes_even", "lanes_odd":
			var parity := 0 if kind == "lanes_even" else 1
			for y in range(arena.position.y, arena.end.y):
				for x in range(arena.position.x, arena.end.x):
					var p := Vector2i(x, y)
					if (x - arena.position.x) % 2 == parity and not boss.has_point(p):
						out.append(p)
		"cross":
			for x in range(arena.position.x, arena.end.x):
				var p := Vector2i(x, player.y)
				if not boss.has_point(p):
					out.append(p)
			for y in range(arena.position.y, arena.end.y):
				var p := Vector2i(player.x, y)
				if y != player.y and not boss.has_point(p):
					out.append(p)
	return out

## The row or column beside the Warden that faces the player, corners included.
static func _cleave_band(boss: Rect2i, player: Vector2i) -> Array:
	var c := Vector2(boss.position) + Vector2(boss.size) * 0.5 - Vector2(0.5, 0.5)
	var d := Vector2(player) - c
	var out := []
	if absf(d.x) >= absf(d.y):
		var x := boss.position.x - 1 if d.x < 0 else boss.end.x
		for y in range(boss.position.y - 1, boss.end.y + 1):
			out.append(Vector2i(x, y))
	else:
		var y := boss.position.y - 1 if d.y < 0 else boss.end.y
		for x in range(boss.position.x - 1, boss.end.x + 1):
			out.append(Vector2i(x, y))
	return out

static func rim_tiles(arena: Rect2i) -> Array:
	var out := []
	for y in range(arena.position.y, arena.end.y):
		for x in range(arena.position.x, arena.end.x):
			if x == arena.position.x or y == arena.position.y or x == arena.end.x - 1 or y == arena.end.y - 1:
				out.append(Vector2i(x, y))
	return out
