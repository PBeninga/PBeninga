extends RefCounted

var t

func new_world(s := 11) -> World:
	return World.new(GameMap.load_file("res://data/frontier.txt"), s)

func set_level(w: World, skill: String, lv: int) -> void:
	w.player.xp[skill] = float(Defs.xp_for_level(lv))

func test_map_parses() -> void:
	var m := GameMap.load_file("res://data/frontier.txt")
	t.eq(m.width, 72, "width")
	t.eq(m.height, 64, "height")
	t.ok(not m.is_solid(m.start), "start is walkable")
	t.ok(m.in_arena(m.warden_spawn), "warden inside the hollow")
	t.ok(not m.in_arena(m.gate), "gate is outside the floor")
	t.eq(m.arena.size, Vector2i(21, 9), "arena floor size")
	var kinds := {}
	for s in m.stations:
		kinds[s.kind] = true
	for k in ["stash", "anvil", "bench", "shrine", "hearth"]:
		t.ok(kinds.has(k), "station %s placed" % k)

func test_everything_reachable_from_start() -> void:
	var w := new_world()
	var targets := []
	for n in w.map.nodes:
		targets.append(n.pos)
	for s in w.map.stations:
		targets.append(s.pos)
	for s in w.map.spawns:
		targets.append(s.pos)
	targets.append(w.map.warden_spawn)
	for p in targets:
		var reach := false
		for d in World._dirs8():
			var q: Vector2i = p + d
			if w.map.in_bounds(q) and not w.astar.is_point_solid(q) and w.astar.get_id_path(w.map.start, q).size() > 0:
				reach = true
				break
		if w.map.in_bounds(p) and not w.astar.is_point_solid(p):
			reach = reach or w.astar.get_id_path(w.map.start, p).size() > 0
		t.ok(reach, "reachable: %s" % str(p))

func test_every_slice_resource_exists() -> void:
	var m := GameMap.load_file("res://data/frontier.txt")
	var have := {}
	for n in m.nodes:
		have[n.res] = true
	for r in Defs.RESOURCES:
		t.ok(have.has(r), "%s placed" % r)

func test_gathering_rolls_components_and_xp() -> void:
	var w := new_world()
	var idx := -1
	for i in w.nodes.size():
		if w.nodes[i].res == "pine":
			idx = i
			break
	w.cmd_gather(idx)
	for i in 200:
		w.step()
		if w.free_slots() < Defs.PACK_SLOTS - 2:
			break
	t.ok(w.free_slots() < Defs.PACK_SLOTS, "logs gathered")
	t.ok(w.player.xp.woodcutting > 0, "woodcutting xp")
	var found := false
	for e in w.events:
		if e.type == "gathered":
			found = true
	t.ok(found, "gathered event")

func test_gate_blocks_underlevelled() -> void:
	var w := new_world()
	for i in w.nodes.size():
		if w.nodes[i].res == "maple":
			w.cmd_gather(i)
			break
	t.ok(w.player.action.is_empty(), "no action below level")

func test_combat_kills_and_trains() -> void:
	var w := new_world(5)
	set_level(w, "melee", 20)
	var id := -1
	for m in w.mobs:
		if m.kind == "thornling":
			id = m.id
			break
	w.cmd_attack(id)
	for i in 300:
		w.step()
		if not w.mobs[id].alive:
			break
	t.ok(not w.mobs[id].alive, "thornling died")
	t.ok(w.player.xp.melee > Defs.xp_for_level(20), "melee xp")
	t.ok(w.player.xp.hitpoints > Defs.xp_for_level(10), "hitpoints xp")

func test_boards_fill_by_forty() -> void:
	var w := new_world()
	t.eq(w.board_points("gathering"), 0, "no points at start")
	set_level(w, "woodcutting", 40)
	set_level(w, "mining", 40)
	t.eq(w.board_points("gathering"), 5, "full at 40")
	t.ok(not w.perk_available("double_haul"), "needs its parent first")
	t.ok(w.take_perk("keen_eye"), "root perk")
	t.ok(w.take_perk("double_haul"), "child after parent")
	t.ok(w.take_perk("tier_sense"), "capstone via either branch")
	set_level(w, "melee", 40)
	set_level(w, "hitpoints", 40)
	t.eq(w.board_points("combat"), 5, "combat takes the better style")
	set_level(w, "melee", 1)
	set_level(w, "archery", 40)
	t.eq(w.board_points("combat"), 5, "archery counts the same")

func test_crafting_through_world() -> void:
	var w := new_world()
	var r := RandomNumberGenerator.new()
	for i in 3:
		w.add_to_pack(Items.roll_component(w.uid(), "copper", 30, {}, r))
	var uids := w.auto_pick("sword", "copper")
	t.eq(uids.size(), 3, "picked three")
	t.eq(w.can_craft("sword", uids), "", "craftable")
	var sword := w.craft("sword", uids)
	t.ok(not sword.is_empty(), "sword made")
	t.eq(w.free_slots(), Defs.PACK_SLOTS - 1, "ingredients consumed")
	t.ok(w.player.xp.smithing > 0, "smithing xp")
	t.ok(w.equip(sword.uid), "equipped")
	t.eq(w.stats().style, "melee", "melee style")

func test_temper_spends_a_shard() -> void:
	var w := new_world()
	var comp := {"uid": w.uid(), "kind": "component", "res": "iron", "rarity": 1, "ceiling": 1, "mods": [{"id": "might", "tier": 1}]}
	w.add_to_pack(comp)
	w.add_to_pack({"uid": w.uid(), "kind": "component", "res": "iron", "rarity": 0, "ceiling": 1, "mods": []})
	set_level(w, "smithing", 17)
	var helm := w.craft("helm", w.auto_pick("helm", "iron"))
	w.give_reagent(2)
	t.eq(w.reagent_count(), 2, "two shards")
	t.eq(w.temper(helm.uid), -1, "iron caps at T1")
	t.eq(w.reagent_count(), 2, "failed temper keeps the shard")

func test_save_round_trip() -> void:
	var w := new_world()
	set_level(w, "mining", 22)
	w.give_reagent(4)
	w.player.perks["keen_eye"] = true
	var json := JSON.stringify(w.to_dict())
	var w2 := new_world()
	w2.from_dict(JSON.parse_string(json))
	t.eq(w2.level("mining"), 22, "levels survive")
	t.eq(w2.reagent_count(), 4, "shards survive")
	t.ok(w2.player.perks.has("keen_eye"), "perks survive")
	t.eq(w2.player.pack.size(), Defs.PACK_SLOTS, "pack size")
	t.ok(w2.player.pack[0].qty is int, "numbers back to ints")
