class_name GameMap
extends RefCounted
## Parses data/frontier.txt into ground, walls, and placed things.

const GROUND_CHARS := ".,:=_+%o~#|^h"
const WALKABLE_GROUND := ".,:=_+%o"
const NODE_CHARS := {
	"P": "pine", "O": "oak", "M": "maple", "I": "ironwood", "E": "elderheart",
	"c": "copper", "i": "iron", "d": "duskiron", "e": "emberite", "s": "sunsteel",
}
const STATION_CHARS := {"B": "stash", "A": "anvil", "F": "bench", "R": "shrine", "H": "hearth"}
const MOB_CHARS := {"1": "thornling", "2": "wolf", "3": "crawler", "4": "golem", "5": "revenant"}
const PROP_CHARS := {"r": "boulder", "b": "brazier", "l": "lantern"}

var width := 0
var height := 0
var ground: PackedStringArray = []   # one char per tile, walls included
var solid: PackedByteArray = []
var nodes: Array = []      # {pos, res}
var stations: Array = []   # {pos, kind}
var props: Array = []      # {pos, kind}
var spawns: Array = []     # {pos, kind}
var start := Vector2i.ZERO
var warden_spawn := Vector2i.ZERO
var gate := Vector2i.ZERO
var arena := Rect2i()      # floor tiles of the Warden's hollow

static func load_file(path: String) -> GameMap:
	var f := FileAccess.open(path, FileAccess.READ)
	var text := f.get_as_text()
	var m := GameMap.new()
	m.parse(text)
	return m

func parse(text: String) -> void:
	var rows := text.strip_edges(false, true).split("\n")
	height = rows.size()
	width = rows[0].length()
	ground.resize(width * height)
	solid.resize(width * height)
	var arena_min := Vector2i(9999, 9999)
	var arena_max := Vector2i(-1, -1)
	for y in height:
		for x in width:
			var ch := rows[y][x] if x < rows[y].length() else "#"
			var p := Vector2i(x, y)
			var i := y * width + x
			ground[i] = ch
			solid[i] = 0
			if NODE_CHARS.has(ch):
				nodes.append({"pos": p, "res": NODE_CHARS[ch]})
				solid[i] = 1
			elif STATION_CHARS.has(ch):
				stations.append({"pos": p, "kind": STATION_CHARS[ch]})
				solid[i] = 1
			elif PROP_CHARS.has(ch):
				props.append({"pos": p, "kind": PROP_CHARS[ch]})
				solid[i] = 1
			elif MOB_CHARS.has(ch):
				spawns.append({"pos": p, "kind": MOB_CHARS[ch]})
			elif ch == "@":
				start = p
			elif ch == "W":
				warden_spawn = p
			elif ch == "G":
				gate = p
			elif not WALKABLE_GROUND.contains(ch):
				solid[i] = 1
			if ch == "o" or ch == "W":
				arena_min = Vector2i(mini(arena_min.x, x), mini(arena_min.y, y))
				arena_max = Vector2i(maxi(arena_max.x, x), maxi(arena_max.y, y))
	arena = Rect2i(arena_min, arena_max - arena_min + Vector2i.ONE)
	# Things standing on a tile take the ground of their neighbours.
	for y in height:
		for x in width:
			var i := y * width + x
			if not GROUND_CHARS.contains(ground[i]):
				ground[i] = _neighbour_ground(rows, x, y)

func _neighbour_ground(rows: PackedStringArray, x: int, y: int) -> String:
	var counts := {}
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
		var nx: int = x + d.x
		var ny: int = y + d.y
		if ny < 0 or ny >= rows.size() or nx < 0 or nx >= rows[ny].length():
			continue
		var c := rows[ny][nx]
		if WALKABLE_GROUND.contains(c):
			counts[c] = counts.get(c, 0) + 1
	var best := "."
	var best_n := 0
	for c in counts:
		if counts[c] > best_n:
			best = c
			best_n = counts[c]
	return best

func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < width and p.y < height

func ground_at(p: Vector2i) -> String:
	return ground[p.y * width + p.x] if in_bounds(p) else "#"

func is_solid(p: Vector2i) -> bool:
	return not in_bounds(p) or solid[p.y * width + p.x] == 1

func in_arena(p: Vector2i) -> bool:
	return arena.has_point(p)
