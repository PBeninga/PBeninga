extends RefCounted
## The Warden must be beatable by reading its marks, and must kill a player
## who ignores them.

var t

func geared_world(s: int, style: String) -> World:
	var w := World.new(GameMap.load_file("res://data/frontier.txt"), s)
	for skill in ["melee", "archery", "hitpoints", "woodcutting", "mining", "fletching", "smithing"]:
		w.player.xp[skill] = float(Defs.xp_for_level(40))
	var mk := func(res: String) -> Dictionary:
		return {"uid": w.uid(), "kind": "component", "res": res, "rarity": 2, "ceiling": Defs.tier_ceiling(Defs.RESOURCES[res].req),
			"mods": [{"id": "might", "tier": 2}, {"id": "vigor", "tier": 2}]}
	var weapon := "sword" if style == "melee" else "shortbow"
	var res := "emberite" if style == "melee" else "ironwood"
	var wpn := Items.craft(w.uid(), weapon, [mk.call(res), mk.call(res), mk.call(res)], 40, {})
	var body := Items.craft(w.uid(), "helm", [mk.call("emberite"), mk.call("emberite")], 40, {})
	w.player.equipment = {"weapon": wpn, "head": body}
	w.player.hp = w.max_hp()
	return w

func enter_arena(w: World) -> void:
	w.player.pos = w.map.gate + Vector2i(0, 1)
	w.player.prev_pos = w.player.pos
	w.step()

## Tiles that will be struck soonest, with the tick they land.
func danger(w: World) -> Dictionary:
	var out := {}
	for tg in w.telegraphs:
		for p in tg.tiles:
			out[p] = mini(out.get(p, 1 << 20), tg.land)
	if w.warden.rim_burning:
		for p in Warden.rim_tiles(w.map.arena):
			out[p] = w.tick + 1
	return out

func dodge_bot_tick(w: World) -> void:
	var d := danger(w)
	var me := w.player.pos
	var boss := w.warden_mob()
	if d.has(me):
		# Nearest safe floor tile, preferring ones that keep us in range.
		var best := me
		var best_score := 1e9
		var rng: int = w.stats().range
		for y in range(-3, 4):
			for x in range(-3, 4):
				var p := me + Vector2i(x, y)
				if not w.map.in_arena(p) or w.astar.is_point_solid(p) or d.has(p):
					continue
				var path := w.astar.get_id_path(me, p)
				if path.is_empty() or path.size() - 1 > 4:
					continue
				var dist := World._rect_dist(p, boss.rect())
				var score := (path.size() - 1) * 2.0 + (0.0 if dist >= 1 and dist <= rng else 3.0)
				if score < best_score:
					best = p
					best_score = score
		if best != me:
			w.cmd_walk(best)
			return
	if not boss.alive:
		return
	var rng: int = w.stats().range
	var dist := World._rect_dist(me, boss.rect())
	var in_range := dist >= 1 and dist <= rng
	if in_range:
		if w.player.action.is_empty():
			w.cmd_attack(boss.id)
		return
	# Out of range: walk to the closest safe tile that is in range.
	var best := me
	var best_len := 1 << 20
	var r := boss.rect().grow(rng)
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var p := Vector2i(x, y)
			if not w.map.in_arena(p) or w.astar.is_point_solid(p) or d.has(p):
				continue
			var path := w.astar.get_id_path(me, p)
			if path.is_empty():
				continue
			var bad := false
			for q in path:
				if d.has(q) and d[q] <= w.tick + 2:
					bad = true
			if not bad and path.size() < best_len:
				best = p
				best_len = path.size()
	if best != me:
		w.cmd_walk(best)

func run_fight(w: World, bot: bool, max_ticks := 1500) -> Dictionary:
	enter_arena(w)
	t.ok(w.warden.active, "fight starts on entering")
	var hits := 0
	var died := false
	var won := false
	for i in max_ticks:
		if bot:
			dodge_bot_tick(w)
		elif w.player.action.is_empty():
			w.cmd_attack(w.warden_mob().id)
		w.events.clear()
		w.step()
		for e in w.events:
			if e.type == "you_died":
				died = true
				print("    died: ", e.recap)
			if e.type == "boss" and e.event == "defeated":
				won = true
			if e.type == "hit" and e.target == -1 and e.amount >= 8:
				hits += 1
		if died or won:
			break
	return {"died": died, "won": won, "hits": hits, "ticks": w.tick}

func test_attack_shapes() -> void:
	var arena := Rect2i(24, 52, 21, 9)
	var boss := Rect2i(33, 55, 2, 2)
	t.eq(Warden.attack_tiles("cleave", boss, Vector2i(32, 55), arena).size(), 4, "cleave covers one side")
	t.ok(Vector2i(32, 54) in Warden.attack_tiles("cleave", boss, Vector2i(32, 55), arena), "cleave includes the corner")
	t.eq(Warden.attack_tiles("toss", boss, Vector2i(28, 55), arena).size(), 9, "toss is 3x3")
	t.eq(Warden.attack_tiles("hammerfall", boss, Vector2i(28, 55), arena).size(), 32, "hammerfall is a 6x6 ring")
	var lanes_even := Warden.attack_tiles("lanes_even", boss, Vector2i(28, 55), arena)
	var lanes_odd := Warden.attack_tiles("lanes_odd", boss, Vector2i(28, 55), arena)
	for p in lanes_even:
		t.ok(not (p in lanes_odd), "lanes alternate")
	var cross := Warden.attack_tiles("cross", boss, Vector2i(28, 55), arena)
	t.ok(not (Vector2i(29, 56) in cross), "diagonal step escapes the cross")

func test_standing_still_dies() -> void:
	var w := geared_world(21, "melee")
	var r := run_fight(w, false)
	t.ok(r.died, "ignoring marks is fatal")

func test_reading_marks_wins_melee() -> void:
	var wins := 0
	for s in [1, 2, 3]:
		var r := run_fight(geared_world(s, "melee"), true)
		if r.won:
			wins += 1
		print("  melee seed %d: %s" % [s, str(r)])
	t.ok(wins >= 2, "a mark-reading player wins in melee (%d/3)" % wins)

func test_reading_marks_wins_archery() -> void:
	var wins := 0
	for s in [4, 5, 6]:
		var r := run_fight(geared_world(s, "archery"), true)
		if r.won:
			wins += 1
		print("  archery seed %d: %s" % [s, str(r)])
	t.ok(wins >= 2, "a mark-reading player wins at range (%d/3)" % wins)
