class_name World
extends RefCounted
## The whole simulation. Advances only through step(); the view reads state
## and drains `events` after each tick.

class Player:
	var pos := Vector2i.ZERO
	var prev_pos := Vector2i.ZERO
	var trail: Array = []            # tiles crossed this tick, for the view
	var path: Array = []
	var action := {}                 # {} | {type: attack|gather|station, ...}
	var hp := 10
	var attack_cd := 0
	var attack_count := 0
	var last_move_tick := -99
	var last_hurt_tick := -99
	var second_wind_ready_at := 0
	var sure_strike := false         # Read the Tell
	var run := true
	var xp := {}
	var pack: Array = []
	var stash: Array = []
	var equipment := {}
	var perks := {}
	var damage_log: Array = []
	var kills := {}
	var warden_best := 0

class Mob:
	var id := 0
	var kind := ""
	var pos := Vector2i.ZERO
	var prev_pos := Vector2i.ZERO
	var spawn := Vector2i.ZERO
	var hp := 1
	var max_hp := 1
	var alive := true
	var respawn_at := 0
	var engaged := false
	var attack_cd := 0
	var size := 1
	var temporary := false
	var facing := Vector2i(0, 1)
	var last_attack_tick := -99

	func rect() -> Rect2i:
		return Rect2i(pos, Vector2i(size, size))

class Telegraph:
	var kind := ""
	var tiles := {}                  # Vector2i -> true
	var start := 0
	var land := 0
	var threatened := false          # player stood inside when it was marked

var map: GameMap
var rng := RandomNumberGenerator.new()
var tick := 0
var player := Player.new()
var mobs: Array = []
var nodes: Array = []                # {pos, res, remaining, respawn_at}
var telegraphs: Array = []
var warden := Warden.new()
var astar := AStarGrid2D.new()
var events: Array = []
var next_uid := 1
var xp_rate := 1.0
var warden_armed := true

func _init(game_map: GameMap, seed_value := 0) -> void:
	map = game_map
	rng.seed = seed_value if seed_value != 0 else int(Time.get_unix_time_from_system())
	astar.region = Rect2i(0, 0, map.width, map.height)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for y in map.height:
		for x in map.width:
			if map.is_solid(Vector2i(x, y)):
				astar.set_point_solid(Vector2i(x, y), true)
	for n in map.nodes:
		var res: Dictionary = Defs.RESOURCES[n.res]
		nodes.append({"pos": n.pos, "res": n.res, "remaining": _node_yield(n.res), "respawn_at": 0})
	for s in map.spawns:
		_spawn_mob(s.kind, s.pos, false)
	var w := _spawn_mob("warden", map.warden_spawn, false)
	w.alive = false
	warden.mob_id = w.id
	for skill in Defs.SKILLS:
		player.xp[skill] = float(Defs.xp_for_level(Defs.START_LEVELS.get(skill, 1)))
	player.pack.resize(Defs.PACK_SLOTS)
	player.pos = map.start
	player.prev_pos = map.start
	player.hp = max_hp()

func _spawn_mob(kind: String, pos: Vector2i, temporary: bool) -> Mob:
	var d: Dictionary = Defs.MOBS[kind]
	var m := Mob.new()
	m.id = mobs.size()
	m.kind = kind
	m.pos = pos
	m.prev_pos = pos
	m.spawn = pos
	m.max_hp = d.hp
	m.hp = d.hp
	m.size = d.get("size", 1)
	m.temporary = temporary
	mobs.append(m)
	return m

func _node_yield(res_id: String) -> int:
	var y: Array = Defs.RESOURCES[res_id].yield
	var n := rng.randi_range(y[0], y[1])
	if player.perks.has("deep_seam"):
		n = int(ceil(n * 1.5))
	return n

func uid() -> int:
	next_uid += 1
	return next_uid

func emit(e: Dictionary) -> void:
	events.append(e)

func log_line(text: String) -> void:
	emit({"type": "log", "text": text})

# ================================================================ skills & stats

func level(skill: String) -> int:
	return Defs.level_for_xp(player.xp[skill])

func add_xp(skill: String, amount: float) -> void:
	var before := level(skill)
	player.xp[skill] += amount * xp_rate
	emit({"type": "xp", "skill": skill, "amount": amount * xp_rate})
	var after := level(skill)
	if after > before:
		emit({"type": "level", "skill": skill, "level": after})
		log_line("%s level %d." % [Defs.SKILL_NAMES[skill], after])
		for b in Defs.BOARD_ORDER:
			if board_points(b) > _board_points_at(b, skill, before):
				log_line("%s board: perk point available." % Defs.BOARDS[b].name)

func total_level() -> int:
	var t := 0
	for s in Defs.SKILLS:
		t += level(s)
	return t

func board_level(board: String) -> int:
	return _board_level_with(board, "", 0)

func _board_level_with(board: String, override_skill: String, override_level: int) -> int:
	var sum := 0
	var linked: Array = Defs.BOARDS[board].skills
	for entry in linked:
		var best := 0
		for s in entry.split("|"):
			var lv := override_level if s == override_skill else level(s)
			best = maxi(best, lv)
		sum += best
	return sum / linked.size()

func _board_points_at(board: String, skill: String, lv: int) -> int:
	return mini(Defs.BOARD_PERK_COUNT, _board_level_with(board, skill, lv) / Defs.LEVELS_PER_BOARD_POINT)

func board_points(board: String) -> int:
	return mini(Defs.BOARD_PERK_COUNT, board_level(board) / Defs.LEVELS_PER_BOARD_POINT)

func board_spent(board: String) -> int:
	var n := 0
	for p in Defs.PERKS[board]:
		if player.perks.has(p.id):
			n += 1
	return n

func perk_available(perk_id: String) -> bool:
	var board := Defs.perk_board(perk_id)
	if board == "" or player.perks.has(perk_id):
		return false
	if board_spent(board) >= board_points(board):
		return false
	var def := Defs.perk_def(perk_id)
	var reqs: Array = Defs.PERK_REQUIRES[def.slot]
	if reqs.is_empty():
		return true
	for p in Defs.PERKS[board]:
		if p.slot in reqs and player.perks.has(p.id):
			return true
	return false

func take_perk(perk_id: String) -> bool:
	if not perk_available(perk_id):
		return false
	player.perks[perk_id] = true
	log_line("Perk taken: %s." % Defs.perk_def(perk_id).name)
	emit({"type": "sound", "name": "perk"})
	return true

func stats() -> Dictionary:
	var s := {"accuracy": 0, "power": 0, "armour": 0, "max_hp": 0, "echo": 0}
	for slot in player.equipment:
		var g: Dictionary = Items.gear_stats(player.equipment[slot], player.perks)
		for k in s:
			s[k] += g[k]
	var w: Dictionary = player.equipment.get("weapon", {})
	s.style = w.get("style", "melee")
	s.speed = int(w.get("speed", 4))
	s.range = int(w.get("range", 1))
	var lv := level(s.style)
	s.max_hit = int(floor(0.5 + (lv + 8) * (s.power + 64) / 640.0))
	s.attack_roll = (lv + 8) * (s.accuracy + 64)
	s.defence_roll = (level("hitpoints") + 8) * (s.armour + 64)
	return s

func max_hp() -> int:
	var extra := 0
	for slot in player.equipment:
		extra += Items.gear_stats(player.equipment[slot], player.perks).max_hp
	return level("hitpoints") + extra

func combat_level() -> int:
	return int((level("hitpoints") + maxi(level("melee"), level("archery")) * 1.5) / 2.5 * 1.25)

static func hit_chance(attack: int, defence: int) -> float:
	if attack > defence:
		return 1.0 - (defence + 2.0) / (2.0 * (attack + 1.0))
	return attack / (2.0 * (defence + 1.0))

# ================================================================ commands

func cmd_walk(target: Vector2i) -> void:
	player.action = {}
	_path_to(target)

func cmd_attack(mob_id: int) -> void:
	var m: Mob = mobs[mob_id]
	if not m.alive:
		return
	player.action = {"type": "attack", "mob": mob_id}
	player.path = []

func cmd_gather(node_index: int) -> void:
	var n: Dictionary = nodes[node_index]
	var res: Dictionary = Defs.RESOURCES[n.res]
	var skill: String = Defs.FAMILY_SKILL[res.family]
	if level(skill) < res.req:
		log_line("Requires %s %d." % [Defs.SKILL_NAMES[skill], res.req])
		player.action = {}
		return
	player.action = {"type": "gather", "node": node_index}
	_path_adjacent(n.pos)

func cmd_station(index: int) -> void:
	player.action = {"type": "station", "station": index}
	_path_adjacent(map.stations[index].pos)

func node_at(p: Vector2i) -> int:
	for i in nodes.size():
		if nodes[i].pos == p:
			return i
	return -1

func station_at(p: Vector2i) -> int:
	for i in map.stations.size():
		if map.stations[i].pos == p:
			return i
	return -1

func mob_at(p: Vector2i) -> int:
	for m in mobs:
		if m.alive and m.rect().has_point(p):
			return m.id
	return -1

# ================================================================ pathing

func _path_to(target: Vector2i) -> bool:
	if not map.in_bounds(target) or astar.is_point_solid(target):
		return false
	var ids := astar.get_id_path(player.pos, target)
	if ids.is_empty():
		player.path = []
		return false
	player.path = Array(ids).slice(1)
	return true

func _path_adjacent(target: Vector2i) -> bool:
	if _cheb(player.pos, target) == 1 and _can_step_diag(player.pos, target):
		player.path = []
		return true
	var best: Array = []
	var best_len := 1 << 30
	for d in _dirs8():
		var p: Vector2i = target + d
		if not map.in_bounds(p) or astar.is_point_solid(p) or not _can_step_diag(p, target):
			continue
		if p == player.pos:
			player.path = []
			return true
		var ids := astar.get_id_path(player.pos, p)
		if ids.size() > 0 and ids.size() < best_len:
			best = Array(ids).slice(1)
			best_len = ids.size()
	player.path = best
	return not best.is_empty()

## Reaching a thing diagonally needs one of the two orthogonal tiles open.
func _can_step_diag(a: Vector2i, b: Vector2i) -> bool:
	var d := b - a
	if d.x == 0 or d.y == 0:
		return true
	return not map.is_solid(Vector2i(a.x + d.x, a.y)) or not map.is_solid(Vector2i(a.x, a.y + d.y))

static func _dirs8() -> Array:
	return [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
		Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1)]

static func _cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

static func _rect_dist(p: Vector2i, r: Rect2i) -> int:
	var dx := maxi(maxi(r.position.x - p.x, 0), p.x - (r.end.x - 1))
	var dy := maxi(maxi(r.position.y - p.y, 0), p.y - (r.end.y - 1))
	return maxi(dx, dy)

# ================================================================ the tick

func step() -> void:
	tick += 1
	player.prev_pos = player.pos
	player.trail = [player.pos]
	for m in mobs:
		m.prev_pos = m.pos
	if player.attack_cd > 0:
		player.attack_cd -= 1
	_player_act()
	_player_move()
	_update_warden()
	for m in mobs:
		if m.alive and m.kind != "warden":
			_mob_act(m)
	_resolve_telegraphs()
	_regen()
	_respawns()
	if player.hp <= 0:
		_player_died()

func _player_act() -> void:
	var a := player.action
	if a.is_empty():
		return
	match a.type:
		"attack":
			var m: Mob = mobs[a.mob]
			if not m.alive:
				player.action = {}
				return
			var s := stats()
			if _rect_dist(player.pos, m.rect()) <= s.range and _rect_dist(player.pos, m.rect()) >= 1:
				player.path = []
				if player.attack_cd <= 0:
					_player_attack(m, s)
			else:
				_chase(m, s.range)
		"gather":
			var n: Dictionary = nodes[a.node]
			if n.remaining <= 0:
				player.action = {}
				return
			if _cheb(player.pos, n.pos) == 1 and player.path.is_empty():
				_gather_attempt(a.node)
			elif player.path.is_empty():
				if not _path_adjacent(n.pos):
					player.action = {}
		"station":
			var st: Dictionary = map.stations[a.station]
			if _cheb(player.pos, st.pos) == 1 and player.path.is_empty():
				player.action = {}
				_use_station(st.kind)
			elif player.path.is_empty():
				if not _path_adjacent(st.pos):
					player.action = {}

func _chase(m: Mob, attack_range: int) -> void:
	# Walk toward the nearest tile in range; re-plan every tick as it moves.
	var best: Array = []
	var best_len := 1 << 30
	var r := m.rect().grow(attack_range)
	var candidates := []
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var p := Vector2i(x, y)
			if m.rect().has_point(p) or not map.in_bounds(p) or astar.is_point_solid(p):
				continue
			candidates.append(p)
	candidates.sort_custom(func(a, b): return _cheb(a, player.pos) < _cheb(b, player.pos))
	for p in candidates.slice(0, 6):
		var ids := astar.get_id_path(player.pos, p)
		if ids.size() > 0 and ids.size() < best_len:
			best = Array(ids).slice(1)
			best_len = ids.size()
	player.path = best
	if best.is_empty():
		player.action = {}
		log_line("You can't reach that.")

func _player_move() -> void:
	var steps := 2 if player.run else 1
	for i in steps:
		if player.path.is_empty():
			break
		var next: Vector2i = player.path[0]
		if astar.is_point_solid(next):
			player.path = []
			break
		player.path.pop_front()
		player.pos = next
		player.trail.append(next)
		player.last_move_tick = tick
		# Attackers stop the moment they come into range.
		if player.action.get("type", "") == "attack":
			var m: Mob = mobs[player.action.mob]
			var d := _rect_dist(player.pos, m.rect())
			if d >= 1 and d <= stats().range:
				player.path = []
				break
	_check_arena()

# ---------------------------------------------------------------- combat

func _player_attack(m: Mob, s: Dictionary) -> void:
	var d: Dictionary = Defs.MOBS[m.kind]
	var interval := Defs.echo_interval(s.echo)
	player.attack_count += 1
	var strikes := 2 if interval > 0 and player.attack_count % interval == 0 else 1
	player.attack_cd = s.speed
	m.engaged = true
	emit({"type": "attack", "who": "player", "style": s.style, "target": m.id, "echo": strikes == 2})
	for i in strikes:
		if not m.alive:
			break
		var roll: int = s.attack_roll
		if player.perks.has("first_blood") and m.hp == m.max_hp:
			roll *= 2
		var max_hit: int = s.max_hit
		if player.perks.has("footwork") and tick - player.last_move_tick <= 2:
			max_hit += 2
		var sure := player.sure_strike
		if sure:
			max_hit += 3
			player.sure_strike = false
		var def_roll := (int(d.def) + 8) * (int(d.armour) + 64)
		var hit := sure or rng.randf() < hit_chance(roll, def_roll)
		var dmg := rng.randi_range(1, maxi(1, max_hit)) if hit else 0
		if m.kind == "warden" and tick < warden.invulnerable_until:
			dmg = 0
		_damage_mob(m, dmg, s.style)

func _damage_mob(m: Mob, dmg: int, style: String) -> void:
	if m.kind == "warden":
		dmg = _clamp_warden_damage(m, dmg)
	dmg = mini(dmg, m.hp)
	m.hp -= dmg
	emit({"type": "hit", "target": m.id, "amount": dmg})
	if dmg > 0:
		add_xp(style, dmg * Defs.COMBAT_XP_PER_DAMAGE)
		add_xp("hitpoints", dmg * Defs.HITPOINTS_XP_PER_DAMAGE)
	if m.hp <= 0:
		_mob_died(m)

func _mob_died(m: Mob) -> void:
	var d: Dictionary = Defs.MOBS[m.kind]
	m.alive = false
	m.engaged = false
	m.respawn_at = tick + int(d.respawn)
	player.kills[m.kind] = int(player.kills.get(m.kind, 0)) + 1
	emit({"type": "death", "target": m.id})
	if player.action.get("mob", -1) == m.id:
		player.action = {}
	if m.kind == "warden":
		_warden_defeated()
		return
	if rng.randf() < float(d.shard):
		give_reagent(1)
		log_line("%s dropped a %s." % [d.name, Defs.REAGENT_NAME])
		emit({"type": "sound", "name": "drop"})

func _mob_act(m: Mob) -> void:
	var d: Dictionary = Defs.MOBS[m.kind]
	if m.attack_cd > 0:
		m.attack_cd -= 1
	var dist_player := _rect_dist(player.pos, m.rect())
	if not m.engaged:
		var same_side := map.in_arena(player.pos) == map.in_arena(m.pos)
		if int(d.aggro) > 0 and dist_player <= int(d.aggro) and _cheb(player.pos, m.spawn) <= 10 and same_side:
			m.engaged = true
		elif m.pos != m.spawn:
			_mob_step(m, m.spawn)
			return
		else:
			return
	# Leash: give up and walk home healed.
	if (_cheb(m.pos, m.spawn) > 12 or dist_player > 15) and not m.temporary:
		m.engaged = false
		m.hp = m.max_hp
		if player.action.get("mob", -1) == m.id:
			player.action = {}
		return
	if dist_player >= 1 and dist_player <= int(d.range):
		if m.attack_cd <= 0:
			_mob_attack(m, d)
	elif dist_player == 0:
		_mob_step_away(m)
	else:
		_mob_step(m, player.pos)

func _mob_attack(m: Mob, d: Dictionary) -> void:
	m.attack_cd = int(d.speed)
	m.last_attack_tick = tick
	m.facing = (player.pos - m.pos).sign()
	emit({"type": "attack", "who": "mob", "target": m.id, "ranged": int(d.range) > 1})
	var s := stats()
	var roll := (int(d.atk) + 8) * (int(d.acc) + 64)
	var hit := rng.randf() < hit_chance(roll, s.defence_roll)
	var dmg := rng.randi_range(1, int(d.max_hit)) if hit else 0
	hurt_player(dmg, d.name, "")

func hurt_player(dmg: int, source: String, why: String) -> void:
	if dmg > 0 and player.perks.has("iron_hide"):
		dmg = maxi(0, dmg - 1)
	player.hp -= dmg
	player.last_hurt_tick = tick
	emit({"type": "hit", "target": -1, "amount": dmg})
	if dmg > 0:
		player.damage_log.append({"tick": tick, "source": source, "amount": dmg, "why": why, "hp": player.hp})
		if player.damage_log.size() > 6:
			player.damage_log.pop_front()
	var mh := max_hp()
	if player.hp > 0 and player.perks.has("second_wind") and player.hp < mh * 0.3 and tick >= player.second_wind_ready_at:
		player.hp = mini(mh, player.hp + int(ceil(mh * 0.25)))
		player.second_wind_ready_at = tick + 200
		log_line("Second Wind.")
		emit({"type": "heal", "amount": int(ceil(mh * 0.25))})

func _mob_step(m: Mob, target: Vector2i) -> void:
	# Greedy single steps, like the old games: obstacles make safe spots.
	var best := m.pos
	var best_score := _step_score(m, m.pos, target)
	for dir in _dirs8():
		var np: Vector2i = m.pos + dir
		if not _mob_can_enter(m, np, dir):
			continue
		var sc := _step_score(m, np, target)
		if sc < best_score:
			best = np
			best_score = sc
	if best != m.pos:
		m.facing = best - m.pos
		m.pos = best

func _step_score(m: Mob, p: Vector2i, target: Vector2i) -> float:
	var r := Rect2i(p, Vector2i(m.size, m.size))
	return _rect_dist(target, r) * 10.0 + (Vector2(p) + Vector2(m.size, m.size) * 0.5).distance_to(Vector2(target) + Vector2(0.5, 0.5)) * 0.1

func _mob_step_away(m: Mob) -> void:
	for dir in _dirs8():
		if _mob_can_enter(m, m.pos + dir, dir):
			m.pos += dir
			return

func _mob_can_enter(m: Mob, np: Vector2i, dir: Vector2i) -> bool:
	var r := Rect2i(np, Vector2i(m.size, m.size))
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var p := Vector2i(x, y)
			if map.is_solid(p) or p == player.pos:
				return false
			if map.in_arena(m.spawn) != map.in_arena(p):
				return false
	if dir.x != 0 and dir.y != 0:
		if map.is_solid(m.pos + Vector2i(dir.x, 0)) or map.is_solid(m.pos + Vector2i(0, dir.y)):
			return false
	for o in mobs:
		if o != m and o.alive and o.rect().intersects(r):
			return false
	return true

# ---------------------------------------------------------------- warden

func warden_mob() -> Mob:
	return mobs[warden.mob_id]

func _check_arena() -> void:
	var inside := map.in_arena(player.pos)
	if not inside:
		warden_armed = true
	if inside and warden_armed and not warden.active and not warden_mob().alive:
		warden_armed = false
		_start_warden()
	elif not inside and warden.active:
		_reset_warden()
		log_line("You left the hollow. The Warden resets.")

func _start_warden() -> void:
	var w := warden_mob()
	w.alive = true
	w.hp = w.max_hp
	w.pos = map.warden_spawn
	w.prev_pos = w.pos
	w.engaged = true
	warden.start(tick)
	_set_warden_solid(true)
	log_line("The Cinder Warden wakes.")
	emit({"type": "boss", "event": "wake"})

func _reset_warden() -> void:
	_set_warden_solid(false)
	var w := warden_mob()
	w.alive = false
	warden.reset()
	telegraphs.clear()
	for m in mobs:
		if m.temporary:
			m.alive = false
	emit({"type": "boss", "event": "reset"})

func _set_warden_solid(on: bool) -> void:
	# The Warden's footprint blocks walking, so the player paths around it.
	for y in map.arena.size.y:
		for x in map.arena.size.x:
			var p := map.arena.position + Vector2i(x, y)
			if not map.is_solid(p):
				astar.set_point_solid(p, false)
	if on:
		var r := warden_mob().rect()
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				astar.set_point_solid(Vector2i(x, y), true)

func _clamp_warden_damage(w: Mob, dmg: int) -> int:
	if warden.phase < 3:
		var floor_hp := int(ceil(w.max_hp * Warden.THRESHOLDS[warden.phase]))
		if w.hp - dmg <= floor_hp:
			dmg = w.hp - floor_hp
			_warden_next_phase()
	return dmg

func _warden_next_phase() -> void:
	warden.phase += 1
	warden.rot_index = 0
	warden.busy_until = tick + Warden.TRANSITION_TICKS
	warden.next_action = tick + Warden.TRANSITION_TICKS
	warden.invulnerable_until = tick + Warden.TRANSITION_TICKS
	telegraphs.clear()
	var w := warden_mob()
	var ph: Dictionary = warden.phase_def()
	log_line("The Warden: %s." % ph.name)
	emit({"type": "boss", "event": "phase", "phase": warden.phase})
	if warden.phase == 2:
		var center := map.arena.position + map.arena.size / 2 - Vector2i.ONE
		if player.pos.x in range(center.x, center.x + 2) and player.pos.y in range(center.y, center.y + 2):
			player.pos = center + Vector2i(-1, 0)
			player.path = []
		w.pos = center
		_set_warden_solid(true)
		for corner in [map.arena.position + Vector2i(1, 1), map.arena.end - Vector2i(2, 2)]:
			var imp := _spawn_or_reuse_imp(corner)
			imp.engaged = true
	elif warden.phase == 3:
		warden.rim_burning = true

func _spawn_or_reuse_imp(p: Vector2i) -> Mob:
	for m in mobs:
		if m.kind == "imp" and not m.alive:
			m.pos = p
			m.prev_pos = p
			m.spawn = p
			m.hp = m.max_hp
			m.alive = true
			m.attack_cd = 2
			return m
	var imp := _spawn_mob("imp", p, true)
	imp.attack_cd = 2
	return imp

func _update_warden() -> void:
	if not warden.active:
		return
	var w := warden_mob()
	if not w.alive:
		return
	var ph: Dictionary = warden.phase_def()
	# Move toward the player when free and mobile.
	if ph.mobile and tick >= warden.busy_until and _rect_dist(player.pos, w.rect()) > 1:
		_set_warden_solid(false)
		_mob_step(w, player.pos)
		_set_warden_solid(true)
	if tick >= warden.next_action:
		var kind := warden.next_attack_id()
		warden.rot_index += 1
		if kind == "cleave" and _rect_dist(player.pos, w.rect()) > 1:
			kind = "toss"
		var atk: Dictionary = Warden.ATTACKS[kind]
		var tg := Telegraph.new()
		tg.kind = kind
		tg.start = tick
		tg.land = tick + int(atk.lead)
		for p in Warden.attack_tiles(kind, w.rect(), player.pos, map.arena):
			tg.tiles[p] = true
		tg.threatened = tg.tiles.has(player.pos)
		telegraphs.append(tg)
		w.facing = (player.pos - w.pos).sign()
		warden.busy_until = tg.land
		warden.next_action = tick + int(ph.cadence)
		emit({"type": "telegraph", "kind": kind, "land": tg.land})

func _resolve_telegraphs() -> void:
	var keep := []
	for tg in telegraphs:
		if tg.land > tick:
			keep.append(tg)
			continue
		var atk: Dictionary = Warden.ATTACKS[tg.kind]
		emit({"type": "strike", "kind": tg.kind, "tiles": tg.tiles.keys()})
		if tg.tiles.has(player.pos):
			hurt_player(rng.randi_range(atk.dmg[0], atk.dmg[1]), atk.name, atk.why)
		elif tg.threatened and player.perks.has("read_the_tell"):
			if not player.sure_strike:
				emit({"type": "tell"})
			player.sure_strike = true
	telegraphs = keep
	if warden.rim_burning and warden.active:
		var r := map.arena
		var p := player.pos
		if r.has_point(p) and (p.x == r.position.x or p.y == r.position.y or p.x == r.end.x - 1 or p.y == r.end.y - 1):
			hurt_player(2, "Burning rim", "stood on the burning rim")

func _warden_defeated() -> void:
	var ticks := tick - warden.started_tick
	warden.active = false
	telegraphs.clear()
	_set_warden_solid(false)
	for m in mobs:
		if m.temporary:
			m.alive = false
	give_reagent(3)
	var best := player.warden_best == 0 or ticks < player.warden_best
	if best:
		player.warden_best = ticks
	log_line("The Cinder Warden falls in %d ticks. 3 Cinder Shards." % ticks)
	emit({"type": "boss", "event": "defeated", "ticks": ticks, "best": best})

# ---------------------------------------------------------------- upkeep

func _regen() -> void:
	var mh := max_hp()
	if player.hp >= mh:
		player.hp = mini(player.hp, mh)
		return
	var calm := tick - player.last_hurt_tick > 12 and not warden.active
	if tick % (3 if calm else 10) == 0:
		player.hp += 1

func _respawns() -> void:
	for n in nodes:
		if n.remaining <= 0 and tick >= n.respawn_at:
			n.remaining = _node_yield(n.res)
			emit({"type": "node", "pos": n.pos, "depleted": false})
	for m in mobs:
		if not m.alive and not m.temporary and m.kind != "warden" and tick >= m.respawn_at:
			m.alive = true
			m.hp = m.max_hp
			m.pos = m.spawn
			m.prev_pos = m.spawn
			m.engaged = false

func _player_died() -> void:
	var recap := player.damage_log.duplicate()
	var in_fight := warden.active
	emit({"type": "you_died", "recap": recap, "warden": in_fight, "phase": warden.phase})
	if in_fight:
		_reset_warden()
	for m in mobs:
		m.engaged = false
	var hearth := map.start
	for st in map.stations:
		if st.kind == "hearth":
			hearth = st.pos + Vector2i(1, 0)
	player.pos = hearth
	player.prev_pos = hearth
	player.path = []
	player.action = {}
	player.hp = max_hp()
	player.damage_log.clear()
	log_line("You wake at the hearth.")

# ================================================================ gathering

func _gather_attempt(idx: int) -> void:
	var n: Dictionary = nodes[idx]
	var res: Dictionary = Defs.RESOURCES[n.res]
	var skill: String = Defs.FAMILY_SKILL[res.family]
	if free_slots() == 0:
		log_line("Your pack is full.")
		player.action = {}
		return
	var lv := level(skill)
	emit({"type": "gather_swing", "family": res.family, "pos": n.pos})
	var chance := float(res.chance) * (1.0 + (lv - int(res.req)) / 40.0)
	if player.perks.has("swift_hands"):
		chance *= 1.15
	if rng.randf() >= minf(chance, 0.95):
		return
	var count := 2 if player.perks.has("double_haul") and rng.randf() < 0.12 else 1
	for i in count:
		if free_slots() == 0:
			break
		var c := Items.roll_component(uid(), n.res, lv, player.perks, rng)
		add_to_pack(c)
		emit({"type": "gathered", "item": c})
	add_xp(skill, float(res.xp) * count)
	n.remaining -= 1
	if n.remaining <= 0:
		n.respawn_at = tick + int(res.respawn)
		player.action = {}
		emit({"type": "node", "pos": n.pos, "depleted": true})

# ================================================================ stations

func _use_station(kind: String) -> void:
	if kind == "hearth":
		player.hp = max_hp()
		log_line("Rested at the hearth.")
	emit({"type": "station", "kind": kind})

# ================================================================ inventory

func free_slots() -> int:
	var n := 0
	for s in player.pack:
		if s == null:
			n += 1
	return n

func add_to_pack(item: Dictionary) -> bool:
	for i in player.pack.size():
		if player.pack[i] == null:
			player.pack[i] = item
			return true
	player.stash.append(item)
	log_line("Pack full. Sent to the stash.")
	return false

func give_reagent(n: int) -> void:
	for s in player.pack:
		if s != null and s.kind == "reagent":
			s.qty += n
			return
	for s in player.stash:
		if s.kind == "reagent":
			s.qty += n
			return
	add_to_pack({"uid": uid(), "kind": "reagent", "qty": n})

func reagent_count() -> int:
	var n := 0
	for s in player.pack + player.stash:
		if s != null and s.kind == "reagent":
			n += int(s.qty)
	return n

func _spend_reagent(n: int) -> bool:
	if reagent_count() < n:
		return false
	for list in [player.pack, player.stash]:
		for i in list.size():
			var s = list[i]
			if s != null and s.kind == "reagent" and n > 0:
				var take := mini(n, int(s.qty))
				s.qty -= take
				n -= take
				if s.qty <= 0:
					list[i] = null
	player.stash = player.stash.filter(func(x): return x != null)
	return true

func find_item(item_uid: int) -> Dictionary:
	for s in player.pack:
		if s != null and s.uid == item_uid:
			return s
	for s in player.stash:
		if s.uid == item_uid:
			return s
	for slot in player.equipment:
		if player.equipment[slot].uid == item_uid:
			return player.equipment[slot]
	return {}

func _remove_item(item_uid: int) -> Dictionary:
	for i in player.pack.size():
		if player.pack[i] != null and player.pack[i].uid == item_uid:
			var it: Dictionary = player.pack[i]
			player.pack[i] = null
			return it
	for i in player.stash.size():
		if player.stash[i].uid == item_uid:
			return player.stash.pop_at(i)
	return {}

func pack_index(item_uid: int) -> int:
	for i in player.pack.size():
		if player.pack[i] != null and player.pack[i].uid == item_uid:
			return i
	return -1

func swap_pack(a: int, b: int) -> void:
	var t = player.pack[a]
	player.pack[a] = player.pack[b]
	player.pack[b] = t

func equip(item_uid: int) -> bool:
	var i := pack_index(item_uid)
	if i < 0:
		return false
	var it: Dictionary = player.pack[i]
	if it.kind != "gear":
		return false
	var old = player.equipment.get(it.slot)
	player.equipment[it.slot] = it
	player.pack[i] = old
	if it.has("style") and player.action.get("type", "") == "attack":
		player.attack_cd = maxi(player.attack_cd, 1)
	player.hp = mini(player.hp, max_hp())
	emit({"type": "equip"})
	emit({"type": "sound", "name": "equip"})
	return true

func unequip(slot: String) -> bool:
	if not player.equipment.has(slot) or free_slots() == 0:
		return false
	add_to_pack(player.equipment[slot])
	player.equipment.erase(slot)
	player.hp = mini(player.hp, max_hp())
	emit({"type": "equip"})
	return true

func drop(item_uid: int) -> void:
	var it := _remove_item(item_uid)
	if not it.is_empty():
		log_line("Dropped %s." % Items.item_name(it))

func deposit(item_uid: int) -> void:
	var i := pack_index(item_uid)
	if i < 0:
		return
	var it: Dictionary = player.pack[i]
	player.pack[i] = null
	if it.kind == "reagent":
		for s in player.stash:
			if s.kind == "reagent":
				s.qty += it.qty
				return
	player.stash.append(it)

func deposit_all() -> void:
	for s in player.pack.duplicate():
		if s != null:
			deposit(s.uid)

func withdraw(item_uid: int) -> bool:
	if free_slots() == 0:
		return false
	for i in player.stash.size():
		if player.stash[i].uid == item_uid:
			add_to_pack(player.stash.pop_at(i))
			return true
	return false

# ================================================================ crafting

func crafting_pool(family: String) -> Array:
	var out := []
	for s in player.pack + player.stash:
		if s != null and s.kind == "component" and Defs.RESOURCES[s.res].family == family:
			out.append(s)
	return out

## Best `count` components of one resource, by score.
func auto_pick(recipe_id: String, res_id: String) -> Array:
	var rec: Dictionary = Defs.RECIPES[recipe_id]
	var pool := crafting_pool(rec.family).filter(func(c): return c.res == res_id)
	pool.sort_custom(func(a, b): return Items.component_score(a) > Items.component_score(b))
	return pool.slice(0, rec.count).map(func(c): return c.uid)

func can_craft(recipe_id: String, uids: Array) -> String:
	var rec: Dictionary = Defs.RECIPES[recipe_id]
	if uids.size() != int(rec.count):
		return "Needs %d components." % rec.count
	var res_id := ""
	for u in uids:
		var c := find_item(u)
		if c.is_empty() or c.kind != "component":
			return "Missing component."
		if Defs.RESOURCES[c.res].family != rec.family:
			return "Wrong material."
		if res_id != "" and c.res != res_id:
			return "Components must match."
		res_id = c.res
	var req := Defs.recipe_req(recipe_id, res_id)
	if level(rec.skill) < req:
		return "Requires %s %d." % [Defs.SKILL_NAMES[rec.skill], req]
	return ""

func craft(recipe_id: String, uids: Array) -> Dictionary:
	if can_craft(recipe_id, uids) != "":
		return {}
	var rec: Dictionary = Defs.RECIPES[recipe_id]
	var ings := []
	for u in uids:
		ings.append(find_item(u))
	var item := Items.craft(uid(), recipe_id, ings, level(rec.skill), player.perks)
	for u in uids:
		_remove_item(u)
	var xp := 0.0
	for c in ings:
		xp += float(Defs.RESOURCES[c.res].xp) * 1.1
	add_xp(rec.skill, xp)
	if player.perks.has("thrift") and rng.randf() < 0.10:
		var worst: Dictionary = ings[0]
		for c in ings:
			if Items.component_score(c) < Items.component_score(worst):
				worst = c
		add_to_pack(worst)
		log_line("Thrift returned a %s." % Items.item_name(worst))
	add_to_pack(item)
	log_line("Crafted %s." % Items.item_name(item))
	emit({"type": "crafted", "item": item})
	emit({"type": "sound", "name": "craft"})
	return item

func temper(item_uid: int, choice := -1) -> int:
	var item := find_item(item_uid)
	if item.is_empty() or item.kind != "gear":
		return -1
	if reagent_count() < 1:
		log_line("No Cinder Shards.")
		return -1
	if not player.perks.has("guided_temper"):
		choice = -1
	var lv := level(Defs.FAMILY_SKILL[item.family])
	var idx := Items.temper(item, lv, rng, choice)
	if idx < 0:
		log_line("Nothing on it can rise further at %s %d." % [Defs.SKILL_NAMES[Defs.FAMILY_SKILL[item.family]], lv])
		return -1
	_spend_reagent(1)
	var m: Dictionary = item.mods[idx]
	log_line("%s rose to %s." % [Defs.MODS[m.id].name, Defs.TIER_NUMERALS[m.tier]])
	emit({"type": "tempered", "uid": item_uid, "index": idx})
	emit({"type": "sound", "name": "temper"})
	return idx

func salvage(item_uid: int) -> int:
	if not player.perks.has("salvage"):
		return 0
	var item := find_item(item_uid)
	if item.is_empty() or item.kind != "gear":
		return 0
	var n := Items.salvage_yield(item)
	if n <= 0:
		log_line("Too few modifiers to salvage.")
		return 0
	_remove_item(item_uid)
	give_reagent(n)
	log_line("Salvaged %s: %d %s." % [Items.item_name(item), n, Defs.REAGENT_NAME + ("s" if n > 1 else "")])
	return n

# ================================================================ saving

func to_dict() -> Dictionary:
	return {
		"version": 1, "tick": tick, "next_uid": next_uid,
		"pos": [player.pos.x, player.pos.y], "hp": player.hp, "run": player.run,
		"xp": player.xp, "pack": player.pack, "stash": player.stash,
		"equipment": player.equipment, "perks": player.perks.keys(),
		"kills": player.kills, "warden_best": player.warden_best,
	}

func from_dict(d: Dictionary) -> void:
	tick = int(d.get("tick", 0))
	next_uid = int(d.get("next_uid", 1))
	for s in d.get("xp", {}):
		player.xp[s] = float(d.xp[s])
	player.pack = _fix_ints(d.get("pack", []))
	player.pack.resize(Defs.PACK_SLOTS)
	player.stash = _fix_ints(d.get("stash", []))
	player.equipment = _fix_ints(d.get("equipment", {}))
	player.perks = {}
	for p in d.get("perks", []):
		player.perks[p] = true
	player.kills = d.get("kills", {})
	player.warden_best = int(d.get("warden_best", 0))
	player.run = bool(d.get("run", true))
	var pos: Array = d.get("pos", [map.start.x, map.start.y])
	var p := Vector2i(int(pos[0]), int(pos[1]))
	player.pos = p if not map.is_solid(p) and not map.in_arena(p) else map.start
	player.prev_pos = player.pos
	player.hp = clampi(int(d.get("hp", max_hp())), 1, max_hp())

## JSON turns every number into a float; items use ints.
static func _fix_ints(v):
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _fix_ints(v[k])
		return out
	if v is Array:
		return v.map(func(x): return _fix_ints(x))
	if v is float and v == floor(v):
		return int(v)
	return v
