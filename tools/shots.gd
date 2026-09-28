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
		"fight", "chop":
			_load_up(w)
			w.player.xp.hitpoints = float(Defs.xp_for_level(70))
			w.player.hp = w.max_hp()
			if name == "fight":
				w.player.pos = Vector2i(31, 57)
				w.player.prev_pos = w.player.pos
				main.do_tick()
				main.world.cmd_attack(w.warden.mob_id)
			else:
				w.player.pos = Vector2i(21, 26)
				for i in w.nodes.size():
					if w.nodes[i].pos == Vector2i(22, 26):
						w.nodes[i].remaining = 2
						w.cmd_gather(i)
		"smoke":
			await _smoke(main, w, tree)
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

func each(main, i: int) -> void:
	main.rig.target = main.view.player_actor.position

## Drives every screen and action once so runtime errors surface headlessly.
func _smoke(main, w: World, tree: SceneTree) -> void:
	var ui = main.ui
	_load_up(w)
	for t in ["pack", "gear", "skills", "boards", "settings"]:
		ui.side.show_tab(t)
		await tree.process_frame
	for k in ["stash", "anvil", "bench", "shrine", "hearth"]:
		ui._open_station(k)
		await tree.process_frame
	ui.close_window(ui.window) if ui.window else null
	# Craft at the bench with whatever maple is held.
	var cw := Windows.CraftWindow.new()
	cw.ui = ui
	cw.build("fletching")
	ui.open_window(cw)
	await tree.process_frame
	cw._craft()
	await tree.process_frame
	# Temper, salvage and equip through the UI paths.
	w.player.perks["salvage"] = true
	w.player.perks["guided_temper"] = true
	var gear = w.player.equipment.weapon
	ui.temper(gear)
	await tree.process_frame
	if ui.window:
		ui.close_window(ui.window)
	for it in w.player.pack:
		if it != null and it.kind == "gear":
			ui.open_item_menu(it, "pack")
			await tree.process_frame
			ui.menu.visible = false
			w.equip(it.uid)
			break
	ui.pick(Vector2(640, 360))
	ui.options_for(ui.pick(Vector2(640, 360)))
	# Gather, fight, die, and fight the Warden for a while.
	w.player.pos = Vector2i(21, 26)
	for i in w.nodes.size():
		if w.nodes[i].res == "pine":
			w.cmd_gather(i)
			break
	for i in 30:
		main.do_tick()
		await tree.process_frame
	for m in w.mobs:
		if m.kind == "thornling" and m.alive:
			w.cmd_attack(m.id)
			break
	for i in 30:
		main.do_tick()
		await tree.process_frame
	w.player.pos = Vector2i(31, 57)
	for i in 400:
		if w.warden.active and w.player.action.is_empty():
			w.cmd_attack(w.warden.mob_id)
		main.do_tick()
		await tree.process_frame
		if not w.warden.active and i > 5:
			w.player.pos = Vector2i(31, 57)
			w.player.hp = w.max_hp()
	main.save()
	print("SMOKE ticks=%d kills=%s" % [w.tick, str(w.player.kills)])
