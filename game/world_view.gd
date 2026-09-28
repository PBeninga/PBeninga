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
var node_anim: Array = []      # per node: {up, shake, fall, grow, fall_dir}
var player_dead_until := 0.0
var stash_open := false
var flames: Array = []

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
		node_anim.append({"up": n.remaining > 0, "shake": -1.0, "fall": -1.0, "grow": -1.0, "fall_dir": Vector3.FORWARD, "phase": i * 1.37, "family": fam})
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
	for n in get_tree_nodes_named("Flame"):
		flames.append(n)

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
	a.setup(Models.creature(m.kind), h.get(m.kind, 1.5), m.kind in ["wolf", "crawler"], m.kind == "revenant", m.kind)
	a.size = m.size
	add_child(a)
	a.snap_to(mob_pos(m))
	a.visible = m.alive
	mob_actors[m.id] = a
	return a

# ---------------------------------------------------------------- per tick

func on_tick() -> void:
	if player_dead_until > 0.0:
		pass
	else:
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
		elif act.get("type", "") == "station" and world.player.path.is_empty():
			player_actor.face(tile_pos(world.map.stations[act.station].pos))
	for m in world.mobs:
		var a := _ensure_mob_actor(m)
		var dying: bool = a.actions.has("death")
		if m.alive and (not a.visible or dying):
			a.revive()
			a.snap_to(mob_pos(m))
		if m.alive:
			a.begin_tick([a.position, mob_pos(m)])
			if m.engaged and m.pos == m.prev_pos:
				a.face(player_actor.points[-1])
		elif not dying and a.visible:
			a.visible = false
	for i in world.nodes.size():
		var n: Dictionary = world.nodes[i]
		var up: bool = n.remaining > 0
		var st: Dictionary = node_anim[i]
		if up and not st.up:
			st.grow = 0.0          # regrowth
			node_models[i].get_node("Standing").visible = true
		elif not up and st.up:
			st.fall = 0.0          # felled or crumbled
			st.fall_dir = (tile_pos(n.pos) - player_actor.position).normalized()
			node_models[i].get_node("Stump").visible = true
		st.up = up
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
				if e.get("echo", false):
					burst(player_actor.position + Vector3(0, 1.0, 0), Color("f0d890"), 14, 2.0, 0.0, 0.4)
			else:
				var a: Actor = mob_actors[e.target]
				a.play_attack("melee")
				a.face(player_actor.points[-1])
				if e.get("ranged", false):
					_projectile(a.position + Vector3(0, 1.1, 0), player_actor.points[-1] + Vector3(0, 0.9, 0), "bolt")
		"hit":
			var a: Actor = actor_for_target(e.target)
			if a:
				a.play_hurt()
				if e.amount > 0:
					burst(a.position + Vector3(0, a.height * 0.6, 0), Color("a01810"), 6 + e.amount, 1.6, 4.0, 0.5)
		"death":
			var a: Actor = mob_actors[e.target]
			a.play_death()
			burst(a.position + Vector3(0, 0.5, 0), Color("6a625a"), 16, 1.2, 1.0, 0.9)
			if world.mobs[e.target].kind == "warden":
				burst(a.position + Vector3(0, 1.8, 0), Color("ff7a30"), 60, 3.5, -0.5, 1.8)
		"gather_swing":
			player_actor.play_gather()
			_set_tool(e.family)
			var i := world.node_at(e.pos)
			if i >= 0:
				node_anim[i].shake = 0.0
				var col := Color("4f7a34") if e.family == "log" else Color("8a8070")
				burst(tile_pos(e.pos) + Vector3(0, 0.6 if e.family == "log" else 0.35, 0), col, 5, 1.5, 3.0, 0.5)
		"gathered":
			var p := tile_pos(world.nodes[world.player.action.node].pos) if world.player.action.get("type", "") == "gather" else player_actor.position
			burst(p + Vector3(0, 0.8, 0), Defs.RARITY_COLORS[int(e.item.rarity)], 8 + 4 * int(e.item.rarity), 1.4, -0.5, 0.8)
		"strike":
			_flash(e.tiles)
			var w = world.warden_mob()
			var wa: Actor = mob_actors[w.id]
			wa.special = ""
			if e.kind != "toss":
				wa.play("slam")
			for t in e.tiles.slice(0, 40):
				if randf() < 0.35:
					burst(tile_pos(t) + Vector3(0, 0.1, 0), Color("ff8a40"), 3, 2.0, 5.0, 0.5)
		"telegraph":
			var w = world.warden_mob()
			var wa: Actor = mob_actors[w.id]
			var poses := {"cleave": "side", "toss": "throw", "hammerfall": "overhead", "lanes_even": "roar", "lanes_odd": "roar", "cross": "cross"}
			wa.set_special(poses.get(e.kind, ""))
			wa.face(player_actor.points[-1])
			if e.kind == "toss":
				# The ember lands exactly when the mark does.
				var target = player_actor.points[-1]
				var life := (int(e.land) - world.tick) * tick_len
				_projectile(wa.position + Vector3(0, 3.0, 0), target, "ember", life, 3.0)
		"equip":
			refresh_gear()
			player_actor.play("equip")
		"crafted":
			player_actor.play("craft")
			var st := _nearest_station(["anvil", "bench"])
			if st >= 0:
				var col := Color("ffb040") if world.map.stations[st].kind == "anvil" else Color("c9a66b")
				burst(tile_pos(world.map.stations[st].pos) + Vector3(0, 0.7, 0), col, 24, 2.5, 5.0, 0.6)
		"tempered":
			player_actor.play("temper")
			get_tree().create_timer(0.35).timeout.connect(func():
				burst(player_actor.position + Vector3(0, 1.9, 0), Color("ff7a30"), 30, 2.2, -0.5, 0.9))
		"level":
			player_actor.play("cheer")
			_ring(player_actor.position, Color("ffb050"))
		"heal":
			burst(player_actor.position + Vector3(0, 1.0, 0), Color("90e070"), 20, 1.2, -1.5, 1.0)
		"tell":
			burst(player_actor.position + Vector3(0, 1.4, 0), Color("ffd070"), 18, 1.8, 0.0, 0.6)
		"you_died":
			player_actor.play_death()
			player_dead_until = 1.8
		"boss":
			var w = world.warden_mob()
			var a := _ensure_mob_actor(w)
			match e.event:
				"wake":
					a.revive()
					a.snap_to(mob_pos(w))
					burst(a.position + Vector3(0, 0.3, 0), Color("ff7a30"), 40, 3.0, 2.0, 1.2)
				"phase":
					a.special = ""
					if e.phase == 2:
						a.do_leap(mob_pos(w))
						for m in world.mobs:
							if m.kind == "imp" and m.alive:
								var ia := _ensure_mob_actor(m)
								ia.revive()
								ia.snap_to(mob_pos(m))
					else:
						a.play("cheer")
						for p in Warden.rim_tiles(world.map.arena):
							burst(tile_pos(p), Color("ff6a2a"), 2, 1.5, -1.0, 1.0)
				"reset":
					a.visible = false
			if e.event == "reset":
				special_clear()
		"station":
			if e.kind == "hearth":
				burst(player_actor.position + Vector3(0, 1.0, 0), Color("ffc070"), 20, 1.0, -1.5, 1.0)

func special_clear() -> void:
	for id in mob_actors:
		mob_actors[id].special = ""

func _nearest_station(kinds: Array) -> int:
	var best := -1
	var bd := 1e9
	for i in world.map.stations.size():
		var s: Dictionary = world.map.stations[i]
		if s.kind in kinds:
			var d := tile_pos(s.pos).distance_to(player_actor.position)
			if d < bd:
				bd = d
				best = i
	return best

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

func _projectile(from: Vector3, to: Vector3, kind: String, life := -1.0, arc := 0.4) -> void:
	var k := MeshKit.new(9)
	match kind:
		"arrow":
			k.box(Vector3(0, 0, 0), Vector3(0.03, 0.03, 0.5), Models.WOOD_COLORS.pine)
			k.box(Vector3(0, 0, -0.27), Vector3(0.06, 0.06, 0.06), Color("9a9ca0"))
			k.box(Vector3(0, 0, 0.22), Vector3(0.08, 0.02, 0.08), Color("c04a2a"))
		"ember":
			k.sphere(Vector3.ZERO, Vector3(0.3, 0.3, 0.3), Color("ff7a30"), 6, 4, true)
			k.sphere(Vector3.ZERO, Vector3(0.18, 0.18, 0.18), Color("ffd070"), 5, 3, true)
		_:
			k.sphere(Vector3.ZERO, Vector3(0.12, 0.12, 0.12), Color("bfe0ff"), 5, 3, true)
	var m := k.instance()
	add_child(m)
	m.position = from
	if life <= 0.0:
		life = tick_len * 0.8
	effects.append({"node": m, "t": 0.0, "life": life, "from": from, "to": to, "arc": arc, "kind": kind})

## One-shot spray of small glowing cubes.
func burst(at: Vector3, col: Color, amount: int, speed: float, gravity: float, life: float) -> void:
	var p := CPUParticles3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 0.06
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.vertex_color_use_as_albedo = true
	bm.material = mat
	p.mesh = bm
	p.amount = maxi(1, amount)
	p.one_shot = true
	p.explosiveness = 0.9
	p.lifetime = life
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -gravity, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	p.position = at
	add_child(p)
	p.emitting = true
	get_tree().create_timer(life + 0.2).timeout.connect(p.queue_free)

## A ring of embers rising around a point (level up).
func _ring(at: Vector3, col: Color) -> void:
	for i in 16:
		var a := TAU * i / 16.0
		burst(at + Vector3(cos(a) * 0.6, 0.1, sin(a) * 0.6), col, 3, 1.5, -2.0, 1.2)

func _process(delta: float) -> void:
	if world == null:
		return
	var ms := Time.get_ticks_msec() * 0.001
	if player_dead_until > 0.0:
		player_dead_until -= delta
		if player_dead_until <= 0.0:
			player_dead_until = 0.0
			player_actor.revive()
			player_actor.snap_to(tile_pos(world.player.pos))
			refresh_gear()
	player_actor.update(delta, tick_len)
	for id in mob_actors:
		mob_actors[id].update(delta, tick_len)
	_animate_nodes(delta, ms)
	if flash_t > 0.0:
		flash_t -= delta
		var mm := flashes.multimesh
		var fa := clampf(flash_t / 0.35, 0.0, 1.0)
		for i in mm.instance_count:
			mm.set_instance_color(i, Color(1.0, 0.8, 0.45, fa * 0.9))
		if flash_t <= 0.0:
			mm.instance_count = 0
	var pulse := 0.85 + 0.15 * sin(ms * 12.0)
	marks.transparency = 1.0 - pulse
	for e in effects.duplicate():
		e.t += delta
		var t: float = e.t / e.life
		if t >= 1.0:
			if e.kind == "ember":
				burst(e.to + Vector3(0, 0.2, 0), Color("ff8a40"), 20, 3.0, 6.0, 0.6)
			e.node.queue_free()
			effects.erase(e)
			continue
		var p: Vector3 = (e.from as Vector3).lerp(e.to, t)
		p.y += sin(t * PI) * e.arc
		# Point along the flight path.
		var nt := minf(1.0, t + 0.05)
		var q: Vector3 = (e.from as Vector3).lerp(e.to, nt)
		q.y += sin(nt * PI) * e.arc
		e.node.position = p
		if q.distance_to(p) > 0.001:
			e.node.look_at(q, Vector3.UP)
		if e.kind == "ember":
			e.node.rotate_object_local(Vector3.RIGHT, delta * 10.0)
	for i in lights.size():
		var l: OmniLight3D = lights[i]
		if not l.has_meta("base"):
			l.set_meta("base", l.light_energy)
		l.light_energy = float(l.get_meta("base")) * (0.85 + 0.15 * sin(ms * 11.0 + i * 1.7) * sin(ms * 7.0 + i))
	for i in flames.size():
		var f: Node3D = flames[i]
		f.scale = Vector3(1.0 + sin(ms * 13.0 + i) * 0.08, 1.0 + sin(ms * 9.0 + i * 2.1) * 0.18, 1.0 + cos(ms * 11.0 + i) * 0.08)
		f.rotation.y = ms * 1.5 + i
	for s in station_models:
		var spin: Node3D = s.get_node_or_null("Spin")
		if spin:
			spin.rotation.y += delta * 0.8
			spin.position.y = 1.25 + sin(ms * 2.0) * 0.06
		var lid: Node3D = s.get_node_or_null("Lid")
		if lid:
			lid.rotation.x = lerpf(lid.rotation.x, -1.6 if stash_open else 0.0, 1.0 - exp(-delta * 8.0))
	_animate_water(ms)

func _animate_nodes(delta: float, ms: float) -> void:
	for i in node_models.size():
		var st: Dictionary = node_anim[i]
		var standing: Node3D = node_models[i].get_node("Standing")
		var stump: Node3D = node_models[i].get_node("Stump")
		var sway := Vector3.ZERO
		if st.family == "log":
			# Wind: a slow lean and a quicker flutter, out of phase per tree.
			sway = Vector3(sin(ms * 0.9 + st.phase) * 0.025, 0, sin(ms * 1.3 + st.phase * 2.0) * 0.03)
		var offset := Vector3.ZERO
		var sc := 1.0
		if st.shake >= 0.0:
			st.shake += delta
			var k := maxf(0.0, 1.0 - st.shake / 0.3)
			sway += Vector3(sin(st.shake * 60.0) * 0.06 * k, 0, cos(st.shake * 50.0) * 0.05 * k)
			if st.family == "ore":
				offset = Vector3(sin(st.shake * 80.0) * 0.03 * k, 0, 0)
			if st.shake > 0.3:
				st.shake = -1.0
		if st.fall >= 0.0:
			st.fall += delta
			var t: float = clampf(st.fall / 0.9, 0, 1)
			if st.family == "log":
				# Topple away from the axe, then sink out.
				var dir: Vector3 = st.fall_dir
				var local = standing.get_parent().global_transform.basis.inverse() * Vector3(dir.x, 0, dir.z)
				sway = Vector3(local.z, 0, -local.x) * (ease(t, 2.4) * 1.5)
				offset.y = -maxf(0.0, st.fall - 0.9) * 1.5
				if st.fall > 1.1 and st.fall < 1.2:
					burst(node_models[i].position + dir * 1.5, Color("6a5a3a"), 20, 1.5, 3.0, 0.7)
				if st.fall > 1.6:
					standing.visible = false
					st.fall = -1.0
			else:
				sc = 1.0 - ease(t, 2.0)
				if st.fall < delta * 1.5:
					burst(node_models[i].position + Vector3(0, 0.4, 0), Color("7b766c"), 24, 2.5, 5.0, 0.8)
				if t >= 1.0:
					standing.visible = false
					st.fall = -1.0
		elif st.grow >= 0.0:
			st.grow += delta
			var t: float = clampf(st.grow / 0.8, 0, 1)
			sc = ease(t, 0.35)
			stump.visible = t < 0.5
			if t >= 1.0:
				st.grow = -1.0
		elif not st.up:
			standing.visible = false
		standing.rotation = sway
		standing.position = offset
		standing.scale = Vector3.ONE * maxf(0.01, sc)
		if st.up and st.fall < 0.0 and st.grow < 0.0:
			stump.visible = false

var _water_mat: ShaderMaterial

func _animate_water(ms: float) -> void:
	if _water_mat == null:
		var w := terrain.get_node_or_null("Water") as MeshInstance3D
		if w == null:
			return
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode blend_mix, cull_disabled, specular_schlick_ggx;
uniform float time;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(wpos.x * 1.7 + time * 1.6) * 0.03 + cos(wpos.z * 2.3 + time * 1.2) * 0.03;
}
void fragment() {
	float r = sin(wpos.x * 3.0 + wpos.z * 2.0 + time * 2.0) * 0.5 + 0.5;
	float s = sin(wpos.z * 4.0 - time * 2.6 + sin(wpos.x * 1.3)) * 0.5 + 0.5;
	vec3 deep = vec3(0.10, 0.17, 0.19);
	vec3 shallow = vec3(0.20, 0.30, 0.30);
	ALBEDO = mix(deep, shallow, r * 0.5 + s * 0.3);
	ALBEDO += vec3(0.9, 0.75, 0.55) * smoothstep(0.92, 1.0, r * s) * 0.35;
	ROUGHNESS = 0.12;
	METALLIC = 0.2;
	ALPHA = 0.82;
}
"""
		_water_mat = ShaderMaterial.new()
		_water_mat.shader = sh
		w.material_override = _water_mat
	_water_mat.set_shader_parameter("time", ms)

## Screen-space anchor above an actor, for splats and names.
func actor_for_target(target: int) -> Actor:
	if target == -1:
		return player_actor
	return mob_actors.get(target)
