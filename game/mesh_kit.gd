class_name MeshKit
extends RefCounted
## Builds flat-shaded, vertex-coloured low-poly meshes from primitives.
## Two surfaces: "solid" (lit) and "glow" (unshaded, blooms).

var _solid := PackedVector3Array()
var _solid_col := PackedColorArray()
var _glow := PackedVector3Array()
var _glow_col := PackedColorArray()
var xf := Transform3D.IDENTITY
var jitter := 0.0
var _seed := 1

static var _mat_solid: StandardMaterial3D
static var _mat_glow: StandardMaterial3D

static func solid_material() -> StandardMaterial3D:
	if _mat_solid == null:
		_mat_solid = StandardMaterial3D.new()
		_mat_solid.vertex_color_use_as_albedo = true
		_mat_solid.vertex_color_is_srgb = true
		_mat_solid.roughness = 0.92
		_mat_solid.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return _mat_solid

static func glow_material() -> StandardMaterial3D:
	if _mat_glow == null:
		_mat_glow = StandardMaterial3D.new()
		_mat_glow.vertex_color_use_as_albedo = true
		_mat_glow.vertex_color_is_srgb = true
		_mat_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_glow.albedo_color = Color(1.6, 1.6, 1.6)
	return _mat_glow

func _init(seed_value := 1) -> void:
	_seed = seed_value

func _rand(i: int) -> float:
	# Deterministic hash noise in [-1, 1].
	var h := hash(Vector2i(_seed, i))
	return float(h % 20001) / 10000.0 - 1.0

func _j(v: Vector3) -> Vector3:
	if jitter <= 0.0:
		return v
	var k := int(round(v.x * 97.0)) * 73856093 ^ int(round(v.y * 97.0)) * 19349663 ^ int(round(v.z * 97.0)) * 83492791
	return v + Vector3(_rand(k), _rand(k + 1), _rand(k + 2)) * jitter

func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, glow := false) -> void:
	a = xf * _j(a)
	b = xf * _j(b)
	c = xf * _j(c)
	if glow:
		_glow.append_array([a, b, c])
		_glow_col.append_array([col, col, col])
	else:
		# Faces tilted toward the sky read slightly lighter.
		var n := (c - a).cross(b - a).normalized()
		var shade := col.lightened(0.06 * maxf(0.0, n.y)) if n.y > 0.0 else col
		_solid.append_array([a, b, c])
		_solid_col.append_array([shade, shade, shade])

func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, glow := false) -> void:
	tri(a, b, c, col, glow)
	tri(a, c, d, col, glow)

## Axis-aligned box centred at `c` (before the kit transform).
func box(c: Vector3, size: Vector3, col: Color, glow := false, top_col = null) -> void:
	var h := size * 0.5
	var p := [
		c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z),
		c + Vector3(h.x, -h.y, h.z), c + Vector3(-h.x, -h.y, h.z),
		c + Vector3(-h.x, h.y, -h.z), c + Vector3(h.x, h.y, -h.z),
		c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z),
	]
	var tc: Color = top_col if top_col != null else col
	quad(p[4], p[5], p[6], p[7], tc, glow)          # top
	quad(p[3], p[2], p[1], p[0], col.darkened(0.3), glow)  # bottom
	quad(p[0], p[1], p[5], p[4], col.darkened(0.08), glow)
	quad(p[2], p[3], p[7], p[6], col.darkened(0.04), glow)
	quad(p[1], p[2], p[6], p[5], col.darkened(0.14), glow)
	quad(p[3], p[0], p[4], p[7], col, glow)

## Frustum/cylinder/cone along +Y from `base`. r1 at the bottom, r2 at the top.
func prism(base: Vector3, height: float, r1: float, r2: float, sides: int, col: Color, glow := false, cap := true, twist := 0.0) -> void:
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var b0 := base + Vector3(cos(a0), 0, sin(a0)) * r1
		var b1 := base + Vector3(cos(a1), 0, sin(a1)) * r1
		var t0 := base + Vector3(cos(a0 + twist), 0, sin(a0 + twist)) * r2 + Vector3(0, height, 0)
		var t1 := base + Vector3(cos(a1 + twist), 0, sin(a1 + twist)) * r2 + Vector3(0, height, 0)
		var shade := col.darkened(0.12 * (0.5 + 0.5 * sin(a0 + 0.8)))
		if r2 <= 0.001:
			tri(b0, base + Vector3(0, height, 0), b1, shade, glow)
		else:
			quad(b0, t0, t1, b1, shade, glow)
			if cap:
				tri(base + Vector3(0, height, 0), t1, t0, col.lightened(0.05), glow)
		if cap:
			tri(base, b0, b1, col.darkened(0.3), glow)

## Low-poly sphere (lat/long), `rings` >= 2.
func sphere(c: Vector3, r: Vector3, col: Color, sides := 6, rings := 4, glow := false) -> void:
	for j in rings:
		var v0 := PI * j / rings - PI / 2
		var v1 := PI * (j + 1) / rings - PI / 2
		for i in sides:
			var u0 := TAU * i / sides
			var u1 := TAU * (i + 1) / sides
			var p00 := c + Vector3(cos(v0) * cos(u0) * r.x, sin(v0) * r.y, cos(v0) * sin(u0) * r.z)
			var p01 := c + Vector3(cos(v0) * cos(u1) * r.x, sin(v0) * r.y, cos(v0) * sin(u1) * r.z)
			var p10 := c + Vector3(cos(v1) * cos(u0) * r.x, sin(v1) * r.y, cos(v1) * sin(u0) * r.z)
			var p11 := c + Vector3(cos(v1) * cos(u1) * r.x, sin(v1) * r.y, cos(v1) * sin(u1) * r.z)
			var shade := col.darkened(0.1 * (1.0 - float(j) / rings))
			if j == 0:
				tri(p00, p11, p10, shade, glow)
			elif j == rings - 1:
				tri(p00, p01, p10, shade, glow)
			else:
				quad(p00, p01, p11, p10, shade, glow)

## A pointed shard: square base, apex along +Y.
func shard(base: Vector3, height: float, w: float, col: Color, glow := false, lean := Vector3.ZERO) -> void:
	var tip := base + Vector3(0, height, 0) + lean
	var mid := base + Vector3(0, height * 0.7, 0) + lean * 0.7
	var ps := [base + Vector3(w, 0, 0), base + Vector3(0, 0, w), base + Vector3(-w, 0, 0), base + Vector3(0, 0, -w)]
	for i in 4:
		var a: Vector3 = ps[i]
		var b: Vector3 = ps[(i + 1) % 4]
		var am := a + (mid - base) * 1.0 + (a - base) * 0.1
		var bm := b + (mid - base) * 1.0 + (b - base) * 0.1
		quad(a, am, bm, b, col.darkened(0.1 * i), glow)
		tri(am, tip, bm, col.lightened(0.08 * (i % 2)), glow)

## Run `f` with the kit transform temporarily multiplied by `t`.
func with(t: Transform3D, f: Callable) -> void:
	var saved := xf
	xf = xf * t
	f.call()
	xf = saved

func is_empty() -> bool:
	return _solid.is_empty() and _glow.is_empty()

func build() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if not _solid.is_empty():
		_add_surface(mesh, _solid, _solid_col, solid_material())
	if not _glow.is_empty():
		_add_surface(mesh, _glow, _glow_col, glow_material())
	return mesh

static func _add_surface(mesh: ArrayMesh, verts: PackedVector3Array, cols: PackedColorArray, mat: Material) -> void:
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for i in range(0, verts.size(), 3):
		var n := (verts[i + 2] - verts[i]).cross(verts[i + 1] - verts[i]).normalized()
		normals[i] = n
		normals[i + 1] = n
		normals[i + 2] = n
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_COLOR] = cols
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(mesh.get_surface_count() - 1, mat)

func instance() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = build()
	return mi
