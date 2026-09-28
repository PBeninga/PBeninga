class_name CameraRig
extends Node3D
## Orbit camera in the old style: yaw with arrows or middle-drag, pitch within
## a band, scroll to zoom. Follows a target smoothly.

var yaw := deg_to_rad(20.0)
var pitch := deg_to_rad(48.0)
var distance := 13.0
var target := Vector3.ZERO
var focus := Vector3.ZERO
var cam := Camera3D.new()
var _dragging := false

const PITCH_MIN := deg_to_rad(28.0)
const PITCH_MAX := deg_to_rad(72.0)
const DIST_MIN := 6.0
const DIST_MAX := 22.0

func _ready() -> void:
	cam.fov = 42.0
	cam.near = 0.1
	cam.far = 120.0
	add_child(cam)

func snap() -> void:
	focus = target
	_apply()

func _process(delta: float) -> void:
	var turn := Input.get_axis("ui_left", "ui_right")
	var tilt := Input.get_axis("ui_down", "ui_up")
	yaw += turn * delta * 1.8
	pitch = clampf(pitch + tilt * delta * 1.2, PITCH_MIN, PITCH_MAX)
	focus = focus.lerp(target, 1.0 - exp(-delta * 10.0))
	_apply()

func _apply() -> void:
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	cam.global_position = focus + Vector3(0, 0.8, 0) + offset
	cam.look_at(focus + Vector3(0, 0.8, 0), Vector3.UP)

func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			distance = clampf(distance * 0.9, DIST_MIN, DIST_MAX)
			return true
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			distance = clampf(distance * 1.1, DIST_MIN, DIST_MAX)
			return true
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = event.pressed
			return true
	if event is InputEventMouseMotion and _dragging:
		yaw -= event.relative.x * 0.006
		pitch = clampf(pitch + event.relative.y * 0.004, PITCH_MIN, PITCH_MAX)
		return true
	return false

## Ray from the screen point onto the horizontal plane at height `h`.
func ground_point(screen: Vector2, h := 0.0) -> Vector3:
	var from := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	if absf(dir.y) < 0.0001:
		return from
	var t := (h - from.y) / dir.y
	return from + dir * t
