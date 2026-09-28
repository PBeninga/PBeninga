extends Node3D
## Root: owns the World, advances ticks, routes input between the 3D view
## and the interface.

const SAVE_PATH := "user://thornreach.save"

var world: World
var view: WorldView
var rig: CameraRig
var ui: GameUI
var tick_accum := 0.0
var paused := false
var shot := {}

func _ready() -> void:
	_parse_args()
	var map := GameMap.load_file("res://data/frontier.txt")
	world = World.new(map, int(shot.get("seed", "0")))
	if not shot.has("fresh"):
		_load()
	_setup_environment()
	view = WorldView.new()
	add_child(view)
	view.build(world)
	rig = CameraRig.new()
	add_child(rig)
	rig.target = view.player_actor.position
	rig.snap()
	ui = GameUI.new()
	add_child(ui)
	ui.setup(self)
	if shot.has("script"):
		_run_shot_script(shot.script)

func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		shot[kv[0]] = kv[1] if kv.size() > 1 else "1"

func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("3a4a5e")
	sm.sky_horizon_color = Color("c89a78")
	sm.ground_horizon_color = Color("6a5a4a")
	sm.ground_bottom_color = Color("2a2420")
	sm.sun_angle_max = 20.0
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("7a6a62")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.92
	env.fog_enabled = true
	env.fog_light_color = Color("6a5a50")
	env.fog_density = 0.0045
	env.fog_sky_affect = 0.4
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.18
	env.adjustment_contrast = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("ffd2a0")
	sun.light_energy = 1.0
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	sun.shadow_blur = 1.5
	add_child(sun)

func _process(delta: float) -> void:
	if paused:
		return
	tick_accum += delta
	if tick_accum >= Defs.TICK_SECONDS:
		tick_accum -= Defs.TICK_SECONDS
		do_tick()
	rig.target = view.player_actor.position
	if ui:
		ui.tick_progress = tick_accum / Defs.TICK_SECONDS

func do_tick() -> void:
	world.events.clear()
	world.step()
	view.on_tick()
	for e in world.events:
		view.handle_event(e)
		ui.handle_event(e)
	ui.on_tick()
	if world.tick % 50 == 0:
		save()

func _unhandled_input(event: InputEvent) -> void:
	if rig.handle_input(event):
		return
	ui.world_input(event)

func save() -> void:
	if shot.has("fresh"):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(world.to_dict()))

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		world.from_dict(d)

func new_game() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	shot["fresh"] = "1"
	get_tree().reload_current_scene()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save()

# ---------------------------------------------------------------- screenshots

## `--script=name` runs a scripted scene from tools/shots.gd, then saves
## `--shot=path.png` and quits. Used to check the look headlessly.
func _run_shot_script(name: String) -> void:
	var s = load("res://tools/shots.gd").new()
	await s.run(self, name)
	await get_tree().process_frame
	await get_tree().process_frame
	var out: String = shot.get("shot", "/tmp/shot.png")
	var seq := int(shot.get("seq", "0"))
	var headless := DisplayServer.get_name() == "headless"
	if seq == 0 and not headless:
		get_viewport().get_texture().get_image().save_png(out)
	for i in seq:
		for f in int(shot.get("every", "6")):
			await get_tree().process_frame
		if s.has_method("each"):
			s.each(self, i)
		if not headless:
			get_viewport().get_texture().get_image().save_png(out.replace(".png", "_%02d.png" % i))
	print("SHOT DONE")
	get_tree().quit()
