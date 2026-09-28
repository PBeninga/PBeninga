class_name Actor
extends Node3D
## Visual stand-in for a player or creature. The simulation moves in whole
## tiles per tick; this glides between them and animates the limbs.

var rig: Node3D
var body: Node3D
var limbs := {}
var points: Array = []        # world positions crossed this tick
var tick_time := 0.0
var moving := false
var walk_phase := 0.0
var attack_t := -1.0
var attack_style := "melee"
var hurt_t := -1.0
var dead_t := -1.0
var gather_t := -1.0
var facing_yaw := 0.0
var height := 1.6
var quadruped := false
var floating := false
var size := 1
var tool_node: Node3D

func setup(model: Node3D, h: float, is_quadruped := false, is_floating := false) -> void:
	rig = model
	add_child(rig)
	body = rig.get_node("Body")
	for n in ["ArmR", "ArmL", "LegR", "LegL", "Head", "Leg5", "Leg6"]:
		var node := body.get_node_or_null(n)
		if node:
			limbs[n] = node
	height = h
	quadruped = is_quadruped
	floating = is_floating

func begin_tick(world_points: Array) -> void:
	points = world_points
	tick_time = 0.0
	moving = points.size() > 1 and points[0].distance_to(points[-1]) > 0.01
	if moving:
		var d: Vector3 = points[-1] - points[0]
		facing_yaw = atan2(-d.x, -d.z)

func face(target: Vector3) -> void:
	var d := target - global_position
	if Vector2(d.x, d.z).length() > 0.01:
		facing_yaw = atan2(-d.x, -d.z)

func snap_to(p: Vector3) -> void:
	points = [p]
	position = p

func play_attack(style: String) -> void:
	attack_t = 0.0
	attack_style = style

func play_hurt() -> void:
	hurt_t = 0.0

func play_gather() -> void:
	gather_t = 0.0

func play_death() -> void:
	dead_t = 0.0

func revive() -> void:
	dead_t = -1.0
	visible = true
	body.rotation = Vector3.ZERO
	body.position = Vector3.ZERO

func update(delta: float, tick_len: float) -> void:
	tick_time += delta
	var a := clampf(tick_time / tick_len, 0.0, 1.0)
	if points.size() >= 2:
		var seg := a * (points.size() - 1)
		var i := mini(int(floor(seg)), points.size() - 2)
		position = (points[i] as Vector3).lerp(points[i + 1], seg - i)
	elif points.size() == 1:
		position = points[0]
	rotation.y = lerp_angle(rotation.y, facing_yaw, 1.0 - exp(-delta * 14.0))
	_animate(delta, a)

func _animate(delta: float, a: float) -> void:
	if dead_t >= 0.0:
		dead_t += delta
		body.rotation.x = lerpf(body.rotation.x, -PI / 2 if not quadruped else 0.0, 1.0 - exp(-delta * 8.0))
		body.rotation.z = lerpf(body.rotation.z, PI / 2 if quadruped else 0.0, 1.0 - exp(-delta * 8.0))
		body.position.y = lerpf(body.position.y, -0.35 if dead_t > 0.8 else 0.0, delta * 2.0)
		if dead_t > 1.6:
			visible = false
		return
	var walking := moving and a < 1.0
	if walking:
		walk_phase += delta * (13.0 if points.size() > 2 else 9.0)
	else:
		walk_phase = lerpf(walk_phase, round(walk_phase / PI) * PI, 1.0 - exp(-delta * 10.0))
	var swing := sin(walk_phase) * (0.7 if walking else 0.0)
	var bob := absf(sin(walk_phase)) * 0.05 if walking else sin(Time.get_ticks_msec() * 0.002) * 0.012
	body.position.y = bob + (0.25 + sin(Time.get_ticks_msec() * 0.003) * 0.08 if floating else 0.0)
	if limbs.has("LegR"):
		limbs.LegR.rotation.x = swing
	if limbs.has("LegL"):
		limbs.LegL.rotation.x = -swing
	if limbs.has("Leg5"):
		limbs.Leg5.rotation.x = swing
	if limbs.has("Leg6"):
		limbs.Leg6.rotation.x = -swing
	var arm_r := -swing * 0.8 if not quadruped else swing
	var arm_l := swing * 0.8 if not quadruped else -swing
	# Attacks override the arms.
	if attack_t >= 0.0:
		attack_t += delta
		var t := attack_t / 0.42
		if t >= 1.0:
			attack_t = -1.0
		elif quadruped:
			body.position.z = -sin(t * PI) * 0.35
		elif attack_style == "archery":
			arm_l = -PI / 2
			arm_r = -PI / 2 + (0.0 if t > 0.6 else 0.4 * sin(t / 0.6 * PI))
		else:
			var wind := 0.3
			arm_r = lerpf(-2.6, 0.5, ease(clampf((t - wind) / (1.0 - wind), 0, 1), 0.4)) if t > wind else lerpf(0.0, -2.6, t / wind)
			body.rotation.y = sin(t * PI) * 0.25
	elif gather_t >= 0.0:
		gather_t += delta
		var t := gather_t / 0.55
		if t >= 1.0:
			gather_t = -1.0
		else:
			arm_r = lerpf(-2.4, 0.2, ease(t, 0.5))
			arm_l = arm_r * 0.8
	else:
		body.rotation.y = lerpf(body.rotation.y, 0.0, delta * 8.0)
	if limbs.has("ArmR"):
		limbs.ArmR.rotation.x = arm_r
	if limbs.has("ArmL"):
		limbs.ArmL.rotation.x = arm_l
	if hurt_t >= 0.0:
		hurt_t += delta
		if hurt_t > 0.25:
			hurt_t = -1.0
			body.rotation.z = 0.0
		else:
			body.rotation.z = sin(hurt_t * 60.0) * 0.06

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
