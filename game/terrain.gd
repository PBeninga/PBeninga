class_name Terrain
extends Node3D
## Ground, cliffs, walls, water and ground clutter for the whole map.

const BASE_H := {".": 0.0, ",": 0.0, ":": -0.03, "_": 0.0, "+": 0.02, "%": -0.02, "o": 0.0, "~": -0.55, "=": -0.55, "|": 0.0, "h": 0.02, "^": 0.0}
const AMP := {".": 0.22, ",": 0.26, ":": 0.08, "_": 0.06, "+": 0.02, "%": 0.12, "o": 0.0, "~": 0.05, "=": 0.05, "|": 0.05, "h": 0.0, "^": 0.0}
const COLORS := {
	".": Color("4e6e2c"), ",": Color("30481f"), ":": Color("6e5838"), "_": Color("3e3834"),
	"+": Color("5a5046"), "%": Color("4a443e"), "o": Color("241f1d"), "~": Color("26302c"), "=": Color("26302c"),
	"|": Color("4a3e30"), "h": Color("4a4238"), "^": Color("201b19"),
}

var map: GameMap
var corner_h := PackedFloat32Array()

func build(game_map: GameMap) -> void:
	map = game_map
	_compute_heights()
	add_child(_ground())
	add_child(_water())
	add_child(_walls())
	_halls()
	_bridge()
	_gate_arch()
	_scatter()

# ---------------------------------------------------------------- heights

func _hash01(x: int, y: int, salt := 0) -> float:
	var h := hash(Vector3i(x, y, salt))
	return float(h % 10007) / 10007.0

func _is_ground(ch: String) -> bool:
	return BASE_H.has(ch)

func _compute_heights() -> void:
	corner_h.resize((map.width + 1) * (map.height + 1))
	for cy in map.height + 1:
		for cx in map.width + 1:
			var sum := 0.0
			var n := 0
			var amp := 1.0
			for d in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
				var t: Vector2i = Vector2i(cx, cy) + d
				var ch := map.ground_at(t)
				if _is_ground(ch):
					sum += BASE_H[ch]
					amp = minf(amp, AMP[ch])
					n += 1
			var h := sum / n if n > 0 else 0.0
			if n > 0:
				h += (_hash01(cx, cy) - 0.5) * amp
			corner_h[cy * (map.width + 1) + cx] = h

func corner(cx: int, cy: int) -> float:
	cx = clampi(cx, 0, map.width)
	cy = clampi(cy, 0, map.height)
	return corner_h[cy * (map.width + 1) + cx]

## Ground height under a world-space point (bilinear over the tile).
func height_at(x: float, z: float) -> float:
	var tx := int(floor(x))
	var tz := int(floor(z))
	var fx := x - tx
	var fz := z - tz
	var a := lerpf(corner(tx, tz), corner(tx + 1, tz), fx)
	var b := lerpf(corner(tx, tz + 1), corner(tx + 1, tz + 1), fx)
	var h := lerpf(a, b, fz)
	var ch := map.ground_at(Vector2i(tx, tz))
	if ch == "=":
		return 0.08
	return h

func tile_height(p: Vector2i) -> float:
	return height_at(p.x + 0.5, p.y + 0.5)

# ---------------------------------------------------------------- ground

func _tile_color(p: Vector2i, ch: String) -> Color:
	var c: Color = COLORS[ch]
	var v := _hash01(p.x, p.y, 3) - 0.5
	match ch:
		"+":
			# Flagstones: alternating shades.
			c = c.darkened(0.08) if (p.x + p.y) % 2 == 0 else c.lightened(0.03)
		".", ",":
			c = c.lerp(Color("6e7f3a") if ch == "." else Color("4a5230"), _hash01(p.x / 3, p.y / 3, 9) * 0.35)
		"o":
			if _hash01(p.x, p.y, 5) > 0.86:
				c = Color("3a2a22")
	return c.lightened(v * 0.08) if v > 0 else c.darkened(-v * 0.08)

func _ground() -> MeshInstance3D:
	var k := MeshKit.new(1)
	for y in map.height:
		for x in map.width:
			var p := Vector2i(x, y)
			var ch := map.ground_at(p)
			if not _is_ground(ch):
				continue
			var c := _tile_color(p, ch)
			var a := Vector3(x, corner(x, y), y)
			var b := Vector3(x + 1, corner(x + 1, y), y)
			var cc := Vector3(x + 1, corner(x + 1, y + 1), y + 1)
			var d := Vector3(x, corner(x, y + 1), y + 1)
			if (x + y) % 2 == 0:
				k.tri(a, b, cc, c)
				k.tri(a, cc, d, c.darkened(0.03))
			else:
				k.tri(a, b, d, c)
				k.tri(b, cc, d, c.darkened(0.03))
			if ch == "o" and _hash01(x, y, 5) > 0.93:
				var h := 0.02
				k.box(Vector3(x + 0.5, h, y + 0.5), Vector3(0.5, 0.01, 0.05), Color("ff5a20"), true)
	var m := k.instance()
	m.name = "Ground"
	return m

func _water() -> MeshInstance3D:
	var st := PackedVector3Array()
	var k := MeshKit.new(2)
	for y in map.height:
		for x in map.width:
			var ch := map.ground_at(Vector2i(x, y))
			if ch == "~" or ch == "=":
				k.quad(Vector3(x, -0.22, y), Vector3(x + 1, -0.22, y), Vector3(x + 1, -0.22, y + 1), Vector3(x, -0.22, y + 1), Color("3e5a60"))
	var m := MeshInstance3D.new()
	m.mesh = k.build()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 1, 1, 0.78)
	mat.roughness = 0.15
	mat.metallic = 0.3
	m.mesh.surface_set_material(0, mat)
	m.name = "Water"
	return m

# ---------------------------------------------------------------- walls

func _walls() -> MeshInstance3D:
	var k := MeshKit.new(3)
	for y in map.height:
		for x in map.width:
			var p := Vector2i(x, y)
			var ch := map.ground_at(p)
			match ch:
				"#":
					_cliff(k, p)
				"|":
					_palisade(k, p)
				"^":
					_rim(k, p)
	var m := k.instance()
	m.name = "Walls"
	return m

func _cliff(k: MeshKit, p: Vector2i) -> void:
	var r := _hash01(p.x, p.y, 11)
	var h := 1.3 + r * 0.9
	# Neighbours that are open ground make this a face; interior cliffs stand taller.
	var open := 0
	for d in World._dirs8():
		if _is_ground(map.ground_at(p + d)):
			open += 1
	if open == 0:
		h += 0.6
	var cave := map.ground_at(p + Vector2i(1, 0)) == "_" or map.ground_at(p + Vector2i(-1, 0)) == "_" or map.ground_at(p + Vector2i(0, 1)) == "_"
	var col := Color("6a655c").lerp(Color("5a5048"), r)
	if cave:
		col = Color("4e4842")
	k.jitter = 0.12
	k.box(Vector3(p.x + 0.5, h * 0.5 - 0.4, p.y + 0.5), Vector3(1.04, h + 0.8, 1.04), col, false, col.lightened(0.08))
	if r > 0.55 and open > 0:
		k.box(Vector3(p.x + 0.5 + (r - 0.7), h + 0.05, p.y + 0.5), Vector3(0.5, 0.35, 0.55), col.darkened(0.08))
	k.jitter = 0.0
	if not cave and open == 0 and r > 0.4:
		# Moss caps on the high ground.
		k.box(Vector3(p.x + 0.5, h + 0.42, p.y + 0.5), Vector3(0.9, 0.06, 0.9), Color("4a5e30"))

func _palisade(k: MeshKit, p: Vector2i) -> void:
	for i in 3:
		var off := Vector3((i - 1) * 0.32, 0, 0)
		if map.ground_at(p + Vector2i(0, 1)) == "|" or map.ground_at(p + Vector2i(0, -1)) == "|":
			off = Vector3(0, 0, (i - 1) * 0.32)
		var h := 1.6 + _hash01(p.x, p.y, i) * 0.3
		var base := Vector3(p.x + 0.5, -0.1, p.y + 0.5) + off
		k.prism(base, h, 0.15, 0.14, 6, Color("6a4a30").lerp(Color("5a3e28"), float(i) / 3))
		k.prism(base + Vector3(0, h, 0), 0.3, 0.14, 0.0, 6, Color("7a5a3a"))
	var dir := Vector3(0, 0, 1) if map.ground_at(p + Vector2i(0, 1)) == "|" or map.ground_at(p + Vector2i(0, -1)) == "|" else Vector3(1, 0, 0)
	var c := Vector3(p.x + 0.5, 1.1, p.y + 0.5)
	k.box(c, Vector3(0.1, 0.1, 0.1) + dir * 0.95, Color("4a3422"))

func _rim(k: MeshKit, p: Vector2i) -> void:
	var r := _hash01(p.x, p.y, 13)
	var h := 1.0 + r * 1.2
	k.jitter = 0.08
	k.box(Vector3(p.x + 0.5, h * 0.5 - 0.2, p.y + 0.5), Vector3(1.0, h + 0.4, 1.0), Color("221c1a"), false, Color("2e2624"))
	k.jitter = 0.0
	if r > 0.5:
		k.shard(Vector3(p.x + 0.5, h - 0.1, p.y + 0.5), 0.6 + r * 0.6, 0.18, Color("1a1614"))
	if r > 0.7:
		k.box(Vector3(p.x + 0.5, h * 0.4, p.y + 0.5), Vector3(1.02, 0.05, 0.3), Color("ff5a20"), true)

# ---------------------------------------------------------------- structures

func _halls() -> void:
	var seen := {}
	for y in map.height:
		for x in map.width:
			var p := Vector2i(x, y)
			if map.ground_at(p) != "h" or seen.has(p):
				continue
			var x1 := x
			while map.ground_at(Vector2i(x1 + 1, y)) == "h":
				x1 += 1
			var y1 := y
			while map.ground_at(Vector2i(x, y1 + 1)) == "h":
				y1 += 1
			for yy in range(y, y1 + 1):
				for xx in range(x, x1 + 1):
					seen[Vector2i(xx, yy)] = true
			var w := x1 - x + 1
			var d := y1 - y + 1
			var hall := Models.hall(w, d, x * 31 + y)
			hall.position = Vector3(x + w * 0.5, 0.0, y + d * 0.5)
			add_child(hall)

func _bridge() -> void:
	var k := MeshKit.new(4)
	for y in map.height:
		for x in map.width:
			if map.ground_at(Vector2i(x, y)) != "=":
				continue
			for i in 4:
				var c := Color("7a5a3a").lerp(Color("6a4a2e"), _hash01(x, y, i))
				k.box(Vector3(x + 0.5, 0.05, y + 0.125 + i * 0.25), Vector3(1.02, 0.08, 0.22), c)
			for side in [0, 1]:
				var yy: int = y + side
				if map.ground_at(Vector2i(x, y + (1 if side == 1 else -1))) != "=":
					k.prism(Vector3(x + 0.5, -0.5, yy - 0.5 + side * 0.0 + (0.05 if side == 0 else -0.05) + 0.5 * 0), 1.3, 0.06, 0.06, 5, Color("4a3422"))
					k.box(Vector3(x + 0.5, 0.55, y + (0.05 if side == 0 else 0.95)), Vector3(1.0, 0.07, 0.07), Color("5a3e28"))
	add_child(k.instance())

func _gate_arch() -> void:
	var g := map.gate
	var k := MeshKit.new(5)
	for side in [-1, 1]:
		k.box(Vector3(g.x + 0.5 + side * 1.0, 1.3, g.y + 0.5), Vector3(0.6, 2.6, 0.7), Color("241e1c"))
		k.box(Vector3(g.x + 0.5 + side * 1.0, 1.6, g.y + 0.14), Vector3(0.1, 1.2, 0.02), Color("ff6a2a"), true)
	k.box(Vector3(g.x + 0.5, 2.8, g.y + 0.5), Vector3(3.0, 0.45, 0.8), Color("2a2220"))
	k.shard(Vector3(g.x + 0.5, 3.0, g.y + 0.5), 0.6, 0.2, Color("1a1614"))
	k.box(Vector3(g.x + 0.5, 2.8, g.y + 0.09), Vector3(0.3, 0.2, 0.02), Color("ffcf7a"), true)
	add_child(k.instance())

# ---------------------------------------------------------------- clutter

func _scatter() -> void:
	var tuft := MeshKit.new(6)
	for i in 5:
		var a := i * TAU / 5
		var base := Vector3(cos(a) * 0.05, 0, sin(a) * 0.05)
		tuft.tri(base + Vector3(-0.02, 0, 0), base + Vector3(0.02, 0, 0), base + Vector3(cos(a) * 0.08, 0.2 + 0.05 * (i % 2), sin(a) * 0.08), Color("6e8a3e"))
		tuft.tri(base + Vector3(0.02, 0, 0), base + Vector3(-0.02, 0, 0), base + Vector3(cos(a) * 0.08, 0.2 + 0.05 * (i % 2), sin(a) * 0.08), Color("5a7432"))
	var fern := MeshKit.new(7)
	for i in 6:
		var a := i * TAU / 6
		var tip := Vector3(cos(a) * 0.32, 0.18, sin(a) * 0.32)
		var side := Vector3(-sin(a), 0, cos(a)) * 0.06
		fern.tri(Vector3.ZERO, tip + side, tip, Color("3e6a2e"))
		fern.tri(Vector3.ZERO, tip, tip - side, Color("355c28"))
		fern.tri(Vector3.ZERO, tip, tip + side, Color("3e6a2e"))
		fern.tri(Vector3.ZERO, tip - side, tip, Color("355c28"))
	var flower := MeshKit.new(8)
	flower.box(Vector3(0, 0.07, 0), Vector3(0.015, 0.14, 0.015), Color("4a6a2a"))
	flower.box(Vector3(0, 0.15, 0), Vector3(0.07, 0.03, 0.07), Color("e8dfb0"))
	var red_flower := MeshKit.new(9)
	red_flower.box(Vector3(0, 0.07, 0), Vector3(0.015, 0.14, 0.015), Color("4a6a2a"))
	red_flower.box(Vector3(0, 0.15, 0), Vector3(0.07, 0.03, 0.07), Color("c0402a"))
	var mushroom := MeshKit.new(10)
	mushroom.prism(Vector3.ZERO, 0.08, 0.02, 0.02, 5, Color("e0d8c0"))
	mushroom.prism(Vector3(0, 0.08, 0), 0.05, 0.07, 0.0, 6, Color("b04a2a"))
	var pebble := MeshKit.new(11)
	pebble.jitter = 0.02
	pebble.sphere(Vector3(0, 0.03, 0), Vector3(0.07, 0.05, 0.06), Color("6a645a"), 5, 2)
	var sets := {"tuft": [], "fern": [], "flower": [], "red": [], "mush": [], "pebble": []}
	for y in map.height:
		for x in map.width:
			var p := Vector2i(x, y)
			var ch := map.ground_at(p)
			if map.is_solid(p) and not _is_ground(ch):
				continue
			var n := 0
			match ch:
				".": n = 3
				",": n = 3
				"_", "%": n = 1
			for i in n:
				var r := _hash01(x, y, 20 + i)
				var q := Vector3(x + _hash01(x, y, 40 + i), 0, y + _hash01(x, y, 60 + i))
				q.y = height_at(q.x, q.z)
				var kind := ""
				if ch == ".":
					kind = "tuft" if r < 0.86 else ("flower" if r < 0.96 else "red")
				elif ch == ",":
					kind = "fern" if r < 0.4 else ("tuft" if r < 0.9 else ("mush" if r < 0.93 else ""))
				else:
					kind = "pebble" if r < 0.6 else ""
				if kind != "":
					sets[kind].append(Transform3D(Basis(Vector3.UP, r * TAU).scaled(Vector3.ONE * (0.8 + r * 0.6)), q))
	var meshes := {"tuft": tuft, "fern": fern, "flower": flower, "red": red_flower, "mush": mushroom, "pebble": pebble}
	for kind in sets:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[kind].build()
		mm.instance_count = sets[kind].size()
		for i in sets[kind].size():
			mm.set_instance_transform(i, sets[kind][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
