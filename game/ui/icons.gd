class_name Icons
extends Node
## Renders item meshes into small textures once, and paints flat glyphs for
## skills and tabs.

signal baked(key: String)

var _vp: SubViewport
var _mesh_i: MeshInstance3D
var _queue: Array = []
var _cache := {}
var _busy := 0
var _current := ""
var enabled := true

func _ready() -> void:
	enabled = DisplayServer.get_name() != "headless"
	_vp = SubViewport.new()
	_vp.size = Vector2i(96, 96)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.25
	cam.transform = Transform3D(Basis(), Vector3(0, 0.35, 3)).looking_at(Vector3.ZERO)
	_vp.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	sun.light_energy = 1.3
	_vp.add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c8b8a0")
	env.ambient_light_energy = 0.7
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	_mesh_i = MeshInstance3D.new()
	_vp.add_child(_mesh_i)

static func key_for(item: Dictionary) -> String:
	match item.kind:
		"component": return "comp_" + item.res
		"reagent": return "shard"
		"gear": return "gear_%s_%s" % [item.recipe, item.res]
	return ""

func icon(item: Dictionary) -> Texture2D:
	var key := key_for(item)
	if _cache.has(key):
		return _cache[key]
	if enabled and not key in _queue and key != _current:
		_queue.append(key)
		_cache_item[key] = item
	return null

var _cache_item := {}

func _process(_d: float) -> void:
	if not enabled:
		return
	if _busy > 0:
		_busy -= 1
		if _busy == 0:
			var img := _vp.get_texture().get_image()
			_cache[_current] = ImageTexture.create_from_image(img)
			_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
			var k := _current
			_current = ""
			baked.emit(k)
		return
	if _queue.is_empty():
		return
	_current = _queue.pop_front()
	var item: Dictionary = _cache_item[_current]
	_mesh_i.mesh = Models.item_mesh(item)
	_pose(item)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_busy = 3

func _pose(item: Dictionary) -> void:
	var aabb := _mesh_i.mesh.get_aabb()
	var t := Transform3D.IDENTITY
	match item.kind:
		"gear":
			match item.recipe:
				"sword", "warhammer", "shortbow", "longbow":
					t.basis = Basis(Vector3.BACK, -PI / 4) * Basis(Vector3.UP, PI / 2 if item.recipe.ends_with("bow") else 0.3)
				"buckler":
					t.basis = Basis(Vector3.RIGHT, PI / 2 - 0.35)
				"helm":
					t.basis = Basis(Vector3.RIGHT, 0.25) * Basis(Vector3.UP, 0.5)
				"cuirass":
					t.basis = Basis(Vector3.RIGHT, 0.15) * Basis(Vector3.UP, 0.4)
		"component":
			t.basis = Basis(Vector3.UP, 0.6) * Basis(Vector3.RIGHT, 0.4)
		"reagent":
			t.basis = Basis(Vector3.UP, 0.4)
	var c := t.basis * aabb.get_center()
	var extent := (t.basis * aabb.size).abs()
	var s := 1.0 / maxf(0.01, maxf(extent.x, extent.y)) * 0.95
	t.basis = t.basis.scaled(Vector3.ONE * s)
	t.origin = -c * s
	_mesh_i.transform = t

# ---------------------------------------------------------------- glyphs

## Flat glyph for a skill or tab, drawn into `ci` within `r`.
static func glyph(ci: CanvasItem, kind: String, r: Rect2, col: Color) -> void:
	var c := r.get_center()
	var s := minf(r.size.x, r.size.y) / 24.0
	var P := func(x: float, y: float) -> Vector2: return c + Vector2(x, y) * s
	var dark := Color(0.08, 0.06, 0.05)
	match kind:
		"melee":
			ci.draw_colored_polygon(PackedVector2Array([P.call(-1.2, 6), P.call(1.2, 6), P.call(1.2, -8), P.call(0, -10.5), P.call(-1.2, -8)]), col)
			ci.draw_rect(Rect2(P.call(-5, 5.5), Vector2(10, 2) * s), col.darkened(0.2))
			ci.draw_rect(Rect2(P.call(-1, 7.5), Vector2(2, 4) * s), col.darkened(0.4))
		"archery":
			var pts := PackedVector2Array()
			for i in 13:
				var a := lerpf(-1.2, 1.2, i / 12.0)
				pts.append(P.call(-6 + cos(a) * 8 - 8 + 8, sin(a) * 10))
			ci.draw_polyline(pts, col, 2.2 * s)
			ci.draw_line(pts[0], pts[12], col.darkened(0.3), 1.0 * s)
			ci.draw_line(P.call(-4, 0), P.call(9, 0), col, 1.4 * s)
			ci.draw_colored_polygon(PackedVector2Array([P.call(9, -2.5), P.call(12, 0), P.call(9, 2.5)]), col)
		"hitpoints":
			var pts := PackedVector2Array()
			for i in 24:
				var t := TAU * i / 24.0
				var x := 16 * pow(sin(t), 3)
				var y := -(13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t))
				pts.append(P.call(x * 0.55, y * 0.55 - 0.5))
			ci.draw_colored_polygon(pts, col)
		"woodcutting":
			ci.draw_line(P.call(-6, 10), P.call(5, -8), col.darkened(0.35), 2.2 * s)
			ci.draw_colored_polygon(PackedVector2Array([P.call(1, -9), P.call(9, -8), P.call(10, -1), P.call(4, -3)]), col)
		"mining":
			ci.draw_line(P.call(-6, 10), P.call(4, -5), col.darkened(0.35), 2.2 * s)
			var arc := PackedVector2Array()
			for i in 9:
				var a := lerpf(PI + 0.5, TAU - 0.2, i / 8.0)
				arc.append(P.call(4, 2) + Vector2(cos(a), sin(a)) * 10 * s - c + c)
			ci.draw_polyline(arc, col, 2.6 * s)
		"fletching":
			ci.draw_line(P.call(-9, 9), P.call(9, -9), col, 1.6 * s)
			ci.draw_colored_polygon(PackedVector2Array([P.call(9, -9), P.call(4, -8), P.call(8, -4)]), col)
			ci.draw_colored_polygon(PackedVector2Array([P.call(-9, 9), P.call(-9, 3), P.call(-6, 6)]), col.darkened(0.2))
			ci.draw_colored_polygon(PackedVector2Array([P.call(-9, 9), P.call(-3, 9), P.call(-6, 6)]), col.darkened(0.2))
		"smithing":
			ci.draw_colored_polygon(PackedVector2Array([P.call(-10, -2), P.call(8, -2), P.call(10, -4), P.call(10, 1), P.call(4, 3), P.call(4, 6), P.call(7, 9), P.call(-7, 9), P.call(-4, 6), P.call(-4, 3), P.call(-10, 1)]), col)
		"pack":
			ci.draw_colored_polygon(PackedVector2Array([P.call(-8, -3), P.call(8, -3), P.call(9, 9), P.call(-9, 9)]), col)
			ci.draw_arc(P.call(0, -3), 5 * s, PI, TAU, 10, col, 2 * s)
			ci.draw_rect(Rect2(P.call(-2, 1), Vector2(4, 3) * s), dark)
		"gear":
			ci.draw_colored_polygon(PackedVector2Array([P.call(-8, 2), P.call(-8, -4), P.call(-4, -9), P.call(4, -9), P.call(8, -4), P.call(8, 2), P.call(5, 10), P.call(1.5, 10), P.call(1.5, 0), P.call(-1.5, 0), P.call(-1.5, 10), P.call(-5, 10)]), col)
			ci.draw_rect(Rect2(P.call(-6, -3), Vector2(12, 2) * s), dark)
		"skills":
			for i in 3:
				ci.draw_rect(Rect2(P.call(-9 + i * 7, 9 - (i + 1) * 6), Vector2(4.5, (i + 1) * 6) * s), col)
		"boards":
			for p in [Vector2(0, -8), Vector2(-7, -1), Vector2(7, -1), Vector2(-4, 8), Vector2(4, 8)]:
				ci.draw_circle(P.call(p.x, p.y), 2.6 * s, col)
			ci.draw_line(P.call(0, -8), P.call(-7, -1), col, 1.2 * s)
			ci.draw_line(P.call(0, -8), P.call(7, -1), col, 1.2 * s)
			ci.draw_line(P.call(-7, -1), P.call(-4, 8), col, 1.2 * s)
			ci.draw_line(P.call(7, -1), P.call(4, 8), col, 1.2 * s)
		"settings":
			ci.draw_arc(c, 6 * s, 0, TAU, 16, col, 3 * s)
			for i in 8:
				var a := TAU * i / 8.0
				ci.draw_line(c + Vector2(cos(a), sin(a)) * 7 * s, c + Vector2(cos(a), sin(a)) * 10 * s, col, 3 * s)
		"run":
			ci.draw_colored_polygon(PackedVector2Array([P.call(-4, -9), P.call(3, -9), P.call(0, -2), P.call(6, -2), P.call(-3, 10), P.call(-1, 1), P.call(-6, 1)]), col)
		"shard":
			ci.draw_colored_polygon(PackedVector2Array([P.call(0, -10), P.call(5, -1), P.call(1, 10), P.call(-5, 1)]), col)
			ci.draw_colored_polygon(PackedVector2Array([P.call(0, -10), P.call(1, 10), P.call(-5, 1)]), col.darkened(0.25))
