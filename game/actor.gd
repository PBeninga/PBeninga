class_name Actor
extends Node3D
## Visual stand-in for a player or creature. The simulation moves in whole
## tiles per tick; this glides between them and animates every action:
## idle, walk, run, attack (per style), hurt, gather, craft, temper, cast
## wind-ups, slams, spawn, death.

var kind := "player"
var rig: Node3D
var body: Node3D
var limbs := {}
var cape: Node3D
var points: Array = []        # world positions crossed this tick
var tick_time := 0.0
var moving := false
var walk_phase := 0.0
var facing_yaw := 0.0
var height := 1.6
var quadruped := false
var floating := false
var size := 1
var seed_phase := 0.0
var tool_node: Node3D

# One-shot actions: name -> elapsed seconds.
var actions := {}
var attack_style := "melee"
var special := ""             # warden wind-up pose while a mark is pending
var special_t := 0.0
var leap := {}                # {from, to, t, life}

const DURATIONS := {"attack": 0.42, "hurt": 0.25, "gather": 0.55, "craft": 0.5, "temper": 0.9,
	"spawn": 0.7, "slam": 0.5, "cheer": 1.0, "equip": 0.35}

func setup(model: Node3D, h: float, is_quadruped := false, is_floating := false, kind_name := "player") -> void:
	rig = model
	add_child(rig)
	body = rig.get_node("Body")
	for n in ["ArmR", "ArmL", "LegR", "LegL", "Head", "Leg5", "Leg6"]:
		var node := body.get_node_or_null(n)
		if node:
			limbs[n] = node
	cape = body.get_node_or_null("Cape")
	height = h
	quadruped = is_quadruped
	floating = is_floating
	kind = kind_name
	seed_phase = randf() * TAU

func begin_tick(world_points: Array) -> void:
	points = world_points
	tick_time = 0.0
	moving = points.size() > 1 and points[0].distance_to(points[-1]) > 0.01
	if moving:
		var d: Vector3 = points[-1] - points[0]
		facing_yaw = atan2(-d.x, -d.z)

func face(target: Vector3) -> void:
	var d := target - global_position if is_inside_tree() else target - position
	if Vector2(d.x, d.z).length() > 0.01:
		facing_yaw = atan2(-d.x, -d.z)

func snap_to(p: Vector3) -> void:
	points = [p]
	position = p

func play(action: String) -> void:
	actions[action] = 0.0

func play_attack(style: String) -> void:
	attack_style = style
	play("attack")

func play_hurt() -> void:
	play("hurt")

func play_gather() -> void:
	play("gather")

func play_death() -> void:
	actions.clear()
	special = ""
	play("death")

func set_special(pose: String) -> void:
	special = pose
	special_t = 0.0

func do_leap(to: Vector3) -> void:
	leap = {"from": position, "to": to, "t": 0.0, "life": 0.9}
	points = [to]

func revive() -> void:
	actions.erase("death")
	visible = true
	body.rotation = Vector3.ZERO
	body.position = Vector3.ZERO
	body.scale = Vector3.ONE * _base_scale()
	play("spawn")

func _base_scale() -> float:
	return 1.15 if kind == "golem" else 1.0

func update(delta: float, tick_len: float) -> void:
	tick_time += delta
	var a := clampf(tick_time / tick_len, 0.0, 1.0)
	if not leap.is_empty():
		leap.t += delta
		var t: float = clampf(leap.t / leap.life, 0, 1)
		position = (leap.from as Vector3).lerp(leap.to, t) + Vector3(0, sin(t * PI) * 3.0, 0)
		if t >= 1.0:
			leap = {}
			play("slam")
	elif points.size() >= 2:
		var seg := a * (points.size() - 1)
		var i := mini(int(floor(seg)), points.size() - 2)
		position = (points[i] as Vector3).lerp(points[i + 1], seg - i)
	elif points.size() == 1:
		position = points[0]
	rotation.y = lerp_angle(rotation.y, facing_yaw, 1.0 - exp(-delta * 14.0))
	for k in actions.keys():
		actions[k] += delta
		if k != "death" and actions[k] > DURATIONS.get(k, 0.5):
			actions.erase(k)
	if special != "":
		special_t += delta
	_animate(delta, a)

func _t(action: String) -> float:
	return clampf(actions[action] / DURATIONS.get(action, 0.5), 0, 1)

func _animate(delta: float, a: float) -> void:
	var ms := Time.get_ticks_msec() * 0.001 + seed_phase
	if actions.has("death"):
		_animate_death(delta)
		return
	var walking := moving and a < 1.0 and leap.is_empty()
	var running := points.size() > 2
	if walking:
		walk_phase += delta * (13.0 if running else 9.0)
	else:
		walk_phase = lerpf(walk_phase, round(walk_phase / PI) * PI, 1.0 - exp(-delta * 10.0))
	var swing := sin(walk_phase) * (0.8 if running else 0.6) * (1.0 if walking else 0.0)
	# Idle breathing and per-creature fidgets.
	var breathe := sin(ms * 2.0) * 0.015
	var bob := absf(sin(walk_phase)) * (0.07 if running else 0.045) if walking else breathe
	var pose := {"arm_r": -swing * 0.8, "arm_l": swing * 0.8, "leg": swing, "lean": 0.12 if running and walking else 0.0,
		"body_y": bob, "body_z": 0.0, "body_roll": 0.0, "body_yaw": 0.0, "head_x": 0.0, "head_y": 0.0, "arm_r_z": 0.0, "arm_l_z": 0.0}
	if quadruped:
		pose.arm_r = swing
		pose.arm_l = -swing
	_idle_fidget(pose, ms, walking)
	if floating:
		pose.body_y = 0.25 + sin(ms * 3.0) * 0.08
		pose.leg = 0.0
	if special != "":
		_animate_special(pose, ms)
	_animate_actions(pose)
	_apply(pose, delta)

func _idle_fidget(pose: Dictionary, ms: float, walking: bool) -> void:
	match kind:
		"player":
			if not walking:
				pose.head_y = sin(ms * 0.4) * 0.25
				pose.arm_r = sin(ms * 2.0) * 0.04
				pose.arm_l = -sin(ms * 2.0) * 0.04
		"wolf":
			if not walking:
				pose.head_x = sin(ms * 1.5) * 0.12
				pose.head_y = sin(ms * 0.7) * 0.35
				pose.body_y = sin(ms * 5.0) * 0.012
		"thornling":
			pose.body_roll = sin(ms * 3.0) * 0.08
			pose.arm_r_z = 0.3 + sin(ms * 4.0) * 0.2
			pose.arm_l_z = -0.3 - sin(ms * 4.0 + 1.0) * 0.2
		"crawler":
			pose.body_y = sin(ms * 8.0) * 0.01
			if not walking:
				pose.leg = sin(ms * 6.0) * 0.12
		"golem":
			pose.body_roll = sin(ms * 0.8) * 0.03
			pose.body_y = sin(ms * 1.2) * 0.02
		"imp":
			pose.body_y = absf(sin(ms * 6.0)) * 0.12
			pose.arm_r_z = 0.6 + sin(ms * 9.0) * 0.4
			pose.arm_l_z = -0.6 - sin(ms * 9.0) * 0.4
		"revenant":
			pose.arm_r_z = 0.2 + sin(ms * 1.3) * 0.08
			pose.body_roll = sin(ms * 0.9) * 0.05
		"warden":
			pose.body_y = sin(ms * 1.4) * 0.03
			pose.head_y = sin(ms * 0.6) * 0.2

func _animate_special(pose: Dictionary, ms: float) -> void:
	var rise := clampf(special_t / 0.4, 0, 1)
	var shake := sin(ms * 40.0) * 0.03 * rise
	match special:
		"overhead":   # Hammerfall: both arms up, crouching, trembling.
			pose.arm_r = lerpf(0.0, -3.0, rise)
			pose.arm_l = lerpf(0.0, -2.8, rise)
			pose.body_y = -0.2 * rise
			pose.body_roll = shake
		"side":       # Cleave: hammer drawn back across the body.
			pose.arm_r = -1.4 * rise
			pose.arm_r_z = 1.2 * rise
			pose.body_yaw = 0.7 * rise
		"throw":      # Toss: off hand cupped, embers gathered.
			pose.arm_l = -2.6 * rise
			pose.arm_l_z = -0.4 * rise
			pose.body_yaw = -0.3 * rise
		"roar":       # Lanes: arms spread, head back.
			pose.arm_r_z = 1.3 * rise
			pose.arm_l_z = -1.3 * rise
			pose.head_x = -0.5 * rise
			pose.body_roll = shake
		"cross":      # Sundering Cross: hammer raised straight up, forward lean.
			pose.arm_r = -3.1 * rise
			pose.lean = -0.15 * rise

func _animate_actions(pose: Dictionary) -> void:
	if actions.has("spawn"):
		var t := _t("spawn")
		body.scale = Vector3.ONE * _base_scale() * ease(t, 0.4)
		pose.body_y -= (1.0 - t) * 0.6
	else:
		body.scale = Vector3.ONE * _base_scale()
	if actions.has("attack"):
		var t := _t("attack")
		if quadruped:
			pose.body_z = -sin(t * PI) * 0.35
			pose.head_x = sin(t * PI) * 0.4
		elif attack_style == "archery" or kind == "revenant":
			pose.arm_l = -PI / 2
			pose.arm_r = -PI / 2 + (0.5 * sin(clampf(t / 0.6, 0, 1) * PI) if t < 0.6 else 0.0)
			pose.body_yaw = -0.3
		elif kind == "warden":
			pose.arm_r = lerpf(-2.6, 0.6, ease(t, 0.3))
		else:
			var wind := 0.3
			pose.arm_r = lerpf(0.0, -2.6, t / wind) if t < wind else lerpf(-2.6, 0.5, ease((t - wind) / (1.0 - wind), 0.4))
			pose.body_yaw = sin(t * PI) * 0.3
			pose.lean = sin(t * PI) * 0.15
	if actions.has("slam"):
		var t := _t("slam")
		pose.arm_r = lerpf(-3.0, 0.9, ease(t * 2.5, 0.3)) if t < 0.4 else 0.9
		pose.arm_l = pose.arm_r
		pose.lean = 0.35 * sin(t * PI)
		pose.body_y = -0.25 * sin(t * PI)
	if actions.has("gather"):
		var t := _t("gather")
		pose.arm_r = lerpf(-2.4, 0.2, ease(t, 0.5))
		pose.arm_l = pose.arm_r * 0.8
		pose.lean = 0.1 * sin(t * PI)
	if actions.has("craft"):
		var t := _t("craft")
		pose.arm_r = -1.8 + absf(sin(t * TAU * 2.0)) * 1.4
		pose.lean = 0.25
		pose.head_x = 0.4
	if actions.has("temper"):
		var t := _t("temper")
		pose.arm_l = -2.9 * sin(clampf(t * 1.6, 0, 1) * PI * 0.5) * (1.0 - clampf((t - 0.7) / 0.3, 0, 1))
		pose.head_x = -0.3 * sin(t * PI)
	if actions.has("equip"):
		var t := _t("equip")
		pose.arm_r = -1.2 * sin(t * PI)
		pose.body_yaw = 0.4 * sin(t * PI)
	if actions.has("cheer"):
		var t := _t("cheer")
		pose.arm_r = -3.0 * sin(t * PI)
		pose.arm_l = -3.0 * sin(t * PI)
		pose.body_y += absf(sin(t * TAU)) * 0.15
	if actions.has("hurt"):
		var t := _t("hurt")
		pose.body_roll += sin(t * 30.0) * 0.08 * (1.0 - t)
		pose.lean -= 0.15 * sin(t * PI)

func _apply(pose: Dictionary, delta: float) -> void:
	var k := 1.0 - exp(-delta * 18.0)
	body.position.y = pose.body_y
	body.position.z = pose.body_z
	body.rotation.x = lerpf(body.rotation.x, -pose.lean, k)
	body.rotation.z = pose.body_roll
	body.rotation.y = lerpf(body.rotation.y, pose.body_yaw, k)
	for n in ["LegR", "Leg5"]:
		if limbs.has(n):
			limbs[n].rotation.x = pose.leg
	for n in ["LegL", "Leg6"]:
		if limbs.has(n):
			limbs[n].rotation.x = -pose.leg
	if limbs.has("ArmR"):
		limbs.ArmR.rotation.x = lerpf(limbs.ArmR.rotation.x, pose.arm_r, k)
		limbs.ArmR.rotation.z = lerpf(limbs.ArmR.rotation.z, pose.arm_r_z, k)
	if limbs.has("ArmL"):
		limbs.ArmL.rotation.x = lerpf(limbs.ArmL.rotation.x, pose.arm_l, k)
		limbs.ArmL.rotation.z = lerpf(limbs.ArmL.rotation.z, pose.arm_l_z, k)
	if limbs.has("Head"):
		limbs.Head.rotation.x = lerpf(limbs.Head.rotation.x, pose.head_x, k)
		limbs.Head.rotation.y = lerpf(limbs.Head.rotation.y, pose.head_y, k)
	if cape:
		# The cape trails behind movement and settles when still.
		var target := 0.35 if moving else 0.05 + sin(Time.get_ticks_msec() * 0.002 + seed_phase) * 0.03
		cape.rotation.x = lerpf(cape.rotation.x, target, 1.0 - exp(-delta * 5.0))

func _animate_death(delta: float) -> void:
	var t: float = actions.death
	var k := 1.0 - exp(-delta * 7.0)
	if quadruped:
		body.rotation.z = lerpf(body.rotation.z, PI / 2, k)
	elif kind == "warden":
		# Knees first, then forward onto the hammer.
		body.position.y = lerpf(body.position.y, -0.6 if t < 1.0 else -1.0, k * 0.6)
		body.rotation.x = lerpf(body.rotation.x, 0.0 if t < 0.9 else -1.3, k * 0.5)
		if limbs.has("ArmR"):
			limbs.ArmR.rotation.x = lerpf(limbs.ArmR.rotation.x, -0.6, k)
	else:
		body.rotation.x = lerpf(body.rotation.x, -PI / 2, k)
	if kind != "warden":
		body.position.y = lerpf(body.position.y, -0.3 if t > 0.8 else 0.0, delta * 2.0)
	var fade_start := 2.6 if kind == "warden" else 1.2
	if t > fade_start:
		body.scale = Vector3.ONE * _base_scale() * maxf(0.01, 1.0 - (t - fade_start) * 2.5)
	if t > fade_start + 0.4:
		visible = false

## Attach a mesh to a hand pivot, replacing what was there.
func set_held(hand: String, mesh: Mesh, offset := Vector3.ZERO, rot := Vector3.ZERO) -> void:
	var arm: Node3D = limbs.get("ArmR" if hand == "R" else "ArmL")
	if arm == null:
		return
	var h := arm.get_node_or_null("Hand" + hand)
	if h == null:
		return
	for c in h.get_children():
		c.queue_free()
	if mesh == null:
		return
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = offset
	m.rotation = rot
	h.add_child(m)
