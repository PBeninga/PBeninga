extends RefCounted
## Scripted camera setups for headless screenshots.

func run(main, name: String) -> void:
	var tree: SceneTree = main.get_tree()
	var w: World = main.world
	match name:
		"camp":
			pass
		"forest":
			w.player.pos = Vector2i(20, 30)
		"mine":
			w.player.pos = Vector2i(56, 31)
		"arena":
			w.player.xp.hitpoints = float(Defs.xp_for_level(60))
			w.player.hp = w.max_hp()
			w.player.pos = Vector2i(31, 57)
			w.player.prev_pos = w.player.pos
			for i in int(main.shot.get("ticks", "5")):
				main.do_tick()
				await tree.process_frame
			print("arena: ", w.player.pos, " warden ", w.warden.active, " hp ", w.player.hp)
		"overview":
			main.rig.distance = 22.0
			main.rig.pitch = deg_to_rad(70)
	w.player.prev_pos = w.player.pos
	main.view.player_actor.snap_to(main.view.tile_pos(w.player.pos))
	main.rig.target = main.view.player_actor.position
	main.rig.snap()
	if main.shot.has("yaw"):
		main.rig.yaw = deg_to_rad(float(main.shot.yaw))
	if main.shot.has("dist"):
		main.rig.distance = float(main.shot.dist)
	main.rig.snap()
	for i in int(main.shot.get("frames", "20")):
		await tree.process_frame
