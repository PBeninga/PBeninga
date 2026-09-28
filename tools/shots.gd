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
		"loaded", "craft", "stash", "tooltip":
			_load_up(w)
			main.ui.refresh_all()
			if name == "craft":
				main.ui._open_station("bench")
			if name == "stash":
				main.ui._open_station("stash")
			if name == "tooltip":
				main.ui.side.show_tab("pack")
				main.ui.show_tooltip(w.player.equipment.weapon)
		"boards":
			_load_up(w)
			w.player.perks["first_blood"] = true
			w.player.perks["keen_eye"] = true
			main.ui.side.show_tab("boards")
		"overview":
			main.rig.distance = 22.0
			main.rig.pitch = deg_to_rad(70)
	w.player.prev_pos = w.player.pos
	main.view.refresh_gear()
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

func _load_up(w: World) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 3
	for s in Defs.SKILLS:
		w.player.xp[s] = float(Defs.xp_for_level(34 + (hash(s) % 9)))
	for i in 9:
		w.add_to_pack(Items.roll_component(w.uid(), ["maple", "oak", "duskiron"][i % 3], 45, {}, r))
	for i in 12:
		w.player.stash.append(Items.roll_component(w.uid(), ["maple", "iron", "pine", "emberite"][i % 4], 50, {}, r))
	w.give_reagent(4)
	var mk := func(res: String, mods: Array) -> Dictionary:
		return {"uid": w.uid(), "kind": "component", "res": res, "rarity": mods.size(), "ceiling": Defs.tier_ceiling(Defs.RESOURCES[res].req), "mods": mods}
	var bow := Items.craft(w.uid(), "longbow", [
		mk.call("maple", [{"id": "might", "tier": 2}, {"id": "echo", "tier": 1}, {"id": "precision", "tier": 1}]),
		mk.call("maple", [{"id": "might", "tier": 1}, {"id": "vigor", "tier": 2}]),
		mk.call("maple", [{"id": "echo", "tier": 2}]),
		mk.call("maple", [])], 40, {})
	var helm := Items.craft(w.uid(), "helm", [mk.call("duskiron", [{"id": "guard", "tier": 2}]), mk.call("duskiron", [{"id": "vigor", "tier": 1}, {"id": "guard", "tier": 1}])], 40, {})
	var body := Items.craft(w.uid(), "cuirass", [mk.call("emberite", [{"id": "guard", "tier": 3}]), mk.call("emberite", []), mk.call("emberite", [{"id": "vigor", "tier": 2}]), mk.call("emberite", [])], 50, {})
	w.player.equipment = {"weapon": bow, "head": helm, "body": body}
	w.add_to_pack(Items.craft(w.uid(), "sword", [mk.call("iron", [{"id": "might", "tier": 1}]), mk.call("iron", []), mk.call("iron", [{"id": "precision", "tier": 1}])], 30, {}))
	w.player.hp = w.max_hp()
	w.emit({"type": "equip"})
	w.log_line("Maple level 34.")
