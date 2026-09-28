class_name WorldView
extends Node3D
## Draws the World: terrain, resource nodes, creatures, the player, marks on
## the floor and short-lived effects. Reads state; never changes rules.

var world: World
var terrain := Terrain.new()
var player_actor: Actor
var mob_actors := {}           # mob id -> Actor
var node_models: Array = []    # parallel to world.nodes
var station_models: Array = []
var marks: MultiMeshInstance3D
var flashes: MultiMeshInstance3D
var flash_t := 0.0
var effects: Array = []        # {node, t, life, from, to, arc}
var lights: Array = []
var tick_len := Defs.TICK_SECONDS

func build(w: World) -> void:
	world = w
	terrain.build(w.map)
	add_child(terrain)
	for i in w.nodes.size():
		var n: Dictionary = w.nodes[i]
		var fam: String = Defs.RESOURCES[n.res].family
		var m := Models.tree(n.res, i) if fam == "log" else Models.rock(n.res, i)
		m.position = tile_pos(n.pos)
		add_child(m)
		node_models.append(m)
	for s in w.map.stations:
		var m := Models.station(s.kind)
		m.position = tile_pos(s.pos)
		m.rotation.y = PI if s.kind == "stash" else 0.0
		add_child(m)
		station_models.append(m)
	var pi_ := 0
	for p in w.map.props:
		var m := Models.prop(p.kind, pi_)
		m.position = tile_pos(p.pos)
		add_child(m)
		pi_ += 1
	player_actor = Actor.new()
	player_actor.setup(Models.player(), 1.6)
	add_child(player_actor)
	player_actor.snap_to(tile_pos(w.player.pos))
	for m in w.mobs:
		_ensure_mob_actor(m)
	marks = _make_mark_layer(0.035)
	flashes = _make_mark_layer(0.05)
	add_child(marks)
	add_child(flashes)
	refresh_gear()
	for n in get_tree_nodes_named("Flicker"):
		lights.append(n)

func get_tree_nodes_named(n: String) -> Array:
	return find_children(n, "", true, false)

func tile_pos(p: Vector2i) -> Vector3:
	return Vector3(p.x + 0.5, terrain.tile_height(p), p.y + 0.5)

func mob_pos(m) -> Vector3:
	var c := Vector3(m.pos.x + m.size * 0.5, 0, m.pos.y + m.size * 0.5)
	c.y = terrain.height_at(c.x, c.z)
	return c

func _ensure_mob_actor(m) -> Actor:
	if mob_actors.has(m.id):
		return mob_actors[m.id]
	var a := Actor.new()
	var h := {"thornling": 1.0, "wolf": 1.1, "crawler": 0.8, "golem": 2.0, "revenant": 1.6, "imp": 1.0, "warden": 3.4}
	a.setup(Models.creature(m.kind), h.get(m.kind, 1.5), m.kind in ["wolf", "crawler"], m.kind == "revenant")
	a.size = m.size
	add_child(a)
	a.snap_to(mob_pos(m))
	a.visible = m.alive
	mob_actors[m.id] = a
	return a

# ---------------------------------------------------------------- per tick

func on_tick() -> void:
	var pts := []
	for t in world.player.trail:
		pts.append(tile_pos(t))
	if pts.size() == 1:
		pts = [player_actor.position, pts[0]] if player_actor.position.distance_to(pts[0]) > 0.05 else pts
	player_actor.begin_tick(pts)
	var act: Dictionary = world.player.action
	if act.get("type", "") == "attack":
		player_actor.face(mob_pos(world.mobs[act.mob]))
	elif act.get("type", "") == "gather" and world.player.path.is_empty():
		player_actor.face(tile_pos(world.nodes[act.node].pos))
	for m in world.mobs:
		var a := _ensure_mob_actor(m)
		if m.alive and not a.visible and a.dead_t < 0.0:
			a.revive()
			a.snap_to(mob_pos(m))
		elif m.alive and a.dead_t >= 0.0:
			a.revive()
			a.snap_to(mob_pos(m))
		if m.alive:
			a.begin_tick([a.position, mob_pos(m)])
			if m.engaged and m.pos == m.prev_pos:
				a.face(player_actor.points[-1])
		elif a.dead_t < 0.0 and a.visible and m.kind == "warden":
			a.visible = false
	for i in world.nodes.size():
		var n: Dictionary = world.nodes[i]
		var up: bool = n.remaining > 0
		node_models[i].get_node("Standing").visible = up
		node_models[i].get_node("Stump").visible = not up
	_update_marks()

func handle_event(e: Dictionary) -> void:
	match e.type:
		"attack":
			if e.who == "player":
				player_actor.play_attack(e.style)
				var m = world.mobs[e.target]
				player_actor.face(mob_pos(m))
				if e.style == "archery":
					_projectile(player_actor.position + Vector3(0, 1.1, 0), mob_pos(m) + Vector3(0, 0.7, 0), "arrow")
			else:
				var a: Actor = mob_actors[e.target]
				a.play_attack("melee")
				a.face(player_actor.points[-1])
				if e.get("ranged", false):
					_projectile(a.position + Vector3(0, 1.1, 0), player_actor.points[-1] + Vector3(0, 0.9, 0), "bolt")
		"hit":
			if e.target == -1:
				player_actor.play_hurt()
			elif mob_actors.has(e.target):
				mob_actors[e.target].play_hurt()
		"death":
			mob_actors[e.target].play_death()
		"gather_swing":
			player_actor.play_gather()
			_set_tool(e.family)
		"strike":
			_flash(e.tiles)
		"telegraph":
			var w = world.warden_mob()
			mob_actors[w.id].play_attack("melee")
		"equip":
			refresh_gear()
		"boss":
			if e.event == "wake":
				var w = world.warden_mob()
				var a := _ensure_mob_actor(w)
				a.revive()
				a.snap_to(mob_pos(w))

func _set_tool(family: String) -> void:
	var k := MeshKit.new(3)
	k.box(Vector3(0, 0.25, 0), Vector3(0.04, 0.6, 0.04), Models.LEATHER)
	if family == "log":
		k.box(Vector3(0.08, 0.5, 0), Vector3(0.16, 0.14, 0.03), Color("9a9ca0"))
	else:
		k.box(Vector3(0, 0.52, 0), Vector3(0.42, 0.05, 0.05), Color("9a9ca0"))
		k.shard(Vector3(0.21, 0.52, 0), 0.08, 0.03, Color("b0b2b6"), false, Vector3(0.08, -0.06, 0))
	player_actor.set_held("R", k.build(), Vector3.ZERO, Vector3(-PI / 2, 0, 0))
	player_actor.tool_node = player_actor
	get_tree().create_timer(1.4).timeout.connect(func():
		if world.player.action.get("type", "") != "gather":
			refresh_gear())

func refresh_gear() -> void:
	var eq: Dictionary = world.player.equipment
	var w: Dictionary = eq.get("weapon", {})
	if w.is_empty():
		player_actor.set_held("R", null)
	elif w.style == "archery":
		player_actor.set_held("R", null)
	else:
		player_actor.set_held("R", Models.gear_mesh(w), Vector3.ZERO, Vector3(-PI / 2, 0, 0))
	var left_mesh: Mesh = null
	var left_rot := Vector3.ZERO
	if not w.is_empty() and w.style == "archery":
		left_mesh = Models.gear_mesh(w)
		left_rot = Vector3(0, PI / 2, 0)
	elif eq.has("shield"):
		left_mesh = Models.gear_mesh(eq.shield)
		left_rot = Vector3(0, 0, PI / 2)
	player_actor.set_held("L", left_mesh, Vector3(-0.04, 0.05, 0), left_rot)
	var body := player_actor.body
	for n in ["HelmMesh", "CuirassMesh"]:
		var old := body.find_child(n, true, false)
		if old:
			old.free()
	if eq.has("head"):
		var hm := MeshInstance3D.new()
		hm.name = "HelmMesh"
		hm.mesh = Models.gear_mesh(eq.head)
		hm.position = Vector3(0, 0.08, 0)
		player_actor.limbs.Head.add_child(hm)
	if eq.has("body"):
		var cm := MeshInstance3D.new()
		cm.name = "CuirassMesh"
		cm.mesh = Models.gear_mesh(eq.body)
		body.add_child(cm)

# ---------------------------------------------------------------- floor marks

func _make_mark_layer(y_off: float) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2(0.92, 0.92)
	q.orientation = PlaneMesh.FACE_Y
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	q.material = mat
	mm.mesh = q
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("y_off", y_off)
	return mi

## Marks brighten as they near landing: 3+ ticks dim, 2 ticks warm, 1 tick hot.
func _update_marks() -> void:
	var tiles := {}
	for tg in world.telegraphs:
		for p in tg.tiles:
			tiles[p] = mini(tiles.get(p, 99), tg.land - world.tick)
	if world.warden.rim_burning and world.warden.active:
		for p in Warden.rim_tiles(world.map.arena):
			if not tiles.has(p):
				tiles[p] = 100
	var mm := marks.multimesh
	mm.instance_count = tiles.size()
	var i := 0
	for p in tiles:
		var left: int = tiles[p]
		var c: Color
		if left >= 100:
			c = Color(0.9, 0.3, 0.1, 0.35)
		elif left <= 1:
			c = Color(1.0, 0.45, 0.12, 0.8)
		elif left == 2:
			c = Color(0.95, 0.35, 0.1, 0.5)
		else:
			c = Color(0.85, 0.3, 0.1, 0.28)
		mm.set_instance_transform(i, Transform3D(Basis(), tile_pos(p) + Vector3(0, 0.035, 0)))
		mm.set_instance_color(i, c)
		i += 1

func _flash(tiles: Array) -> void:
	var mm := flashes.multimesh
	mm.instance_count = tiles.size()
	for i in tiles.size():
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(1.05, 1, 1.05)), tile_pos(tiles[i]) + Vector3(0, 0.05, 0)))
		mm.set_instance_color(i, Color(1.0, 0.85, 0.5, 0.9))
	flash_t = 0.35

# ---------------------------------------------------------------- effects

func _projectile(from: Vector3, to: Vector3, kind: String) -> void:
	var k := MeshKit.new(9)
	if kind == "arrow":
		k.box(Vector3(0, 0, 0), Vector3(0.03, 0.03, 0.5), Models.WOOD_COLORS.pine)
		k.shard(Vector3(0, 0, -0.25), 0.0, 0.0, Color.WHITE)
		k.box(Vector3(0, 0, -0.27), Vector3(0.06, 0.06, 0.06), Color("9a9ca0"))
	else:
		k.sphere(Vector3.ZERO, Vector3(0.12, 0.12, 0.12), Color("bfe0ff"), 5, 3, true)
	var m := k.instance()
	add_child(m)
	m.position = from
	m.look_at_from_position(from, to, Vector3.UP)
	effects.append({"node": m, "t": 0.0, "life": tick_len * 0.8, "from": from, "to": to, "arc": 0.4})

func _process(delta: float) -> void:
	if world == null:
		return
	player_actor.update(delta, tick_len)
	for id in mob_actors:
		mob_actors[id].update(delta, tick_len)
	if flash_t > 0.0:
		flash_t -= delta
		var mm := flashes.multimesh
		var a := clampf(flash_t / 0.35, 0.0, 1.0)
		for i in mm.instance_count:
			mm.set_instance_color(i, Color(1.0, 0.8, 0.45, a * 0.9))
		if flash_t <= 0.0:
			mm.instance_count = 0
	var pulse := 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.012)
	marks.transparency = 1.0 - pulse
	for e in effects.duplicate():
		e.t += delta
		var t: float = e.t / e.life
		if t >= 1.0:
			e.node.queue_free()
			effects.erase(e)
			continue
		var p: Vector3 = (e.from as Vector3).lerp(e.to, t)
		p.y += sin(t * PI) * e.arc
		e.node.position = p
	var ms := Time.get_ticks_msec()
	for i in lights.size():
		var l: OmniLight3D = lights[i]
		l.light_energy = l.get_meta("base", l.light_energy) if l.has_meta("base") else l.light_energy
		if not l.has_meta("base"):
			l.set_meta("base", l.light_energy)
		l.light_energy = float(l.get_meta("base")) * (0.85 + 0.15 * sin(ms * 0.011 + i * 1.7) * sin(ms * 0.007 + i))
	for s in station_models:
		var spin: Node3D = s.get_node_or_null("Spin")
		if spin:
			spin.rotation.y += delta * 0.8
			spin.position.y = 1.25 + sin(ms * 0.002) * 0.06

## Screen-space anchor above an actor, for splats and names.
func actor_for_target(target: int) -> Actor:
	if target == -1:
		return player_actor
	return mob_actors.get(target)
