class_name Hud
extends RefCounted
## Small always-on widgets: minimap, orbs, tick strip, boss bar, overlay.


class Minimap extends Control:
	var ui
	var tex: ImageTexture
	const SCALE := 4.0

	func _init() -> void:
		custom_minimum_size = Vector2(172, 172)
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_STOP

	func build(map: GameMap) -> void:
		var img := Image.create(map.width, map.height, false, Image.FORMAT_RGBA8)
		var cols := {".": Color("4a6630"), ",": Color("2e4420"), ":": Color("7a6444"), "_": Color("3e3834"),
			"+": Color("6a5a48"), "%": Color("4e4640"), "o": Color("2a2220"), "~": Color("3a5a66"), "=": Color("7a5a3a"),
			"#": Color("1e1b18"), "|": Color("5a3e28"), "^": Color("3a1e14"), "h": Color("8a5a40")}
		for y in map.height:
			for x in map.width:
				var p := Vector2i(x, y)
				var c: Color = cols.get(map.ground_at(p), Color("333"))
				img.set_pixel(x, y, c)
		for n in map.nodes:
			var fam: String = Defs.RESOURCES[n.res].family
			img.set_pixel(n.pos.x, n.pos.y, Color("2a5a28") if fam == "log" else Color("8a8070"))
		tex = ImageTexture.create_from_image(img)

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			# Walk to the clicked point, like the old compass map.
			var c := size / 2
			var d: Vector2 = (e.position - c) / SCALE
			var yaw: float = ui.main.rig.yaw
			var w := d.rotated(-yaw)
			var pp: Vector3 = ui.view.player_actor.position
			var tile := Vector2i(int(floor(pp.x + w.x)), int(floor(pp.z + w.y)))
			ui.world.cmd_walk(tile)
			ui.set_click_marker_tile(tile, false)
			accept_event()

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var c := size / 2
		draw_rect(Rect2(Vector2.ZERO, size), Color("0e0c0a"))
		if tex == null:
			return
		var pp: Vector3 = ui.view.player_actor.position
		var yaw: float = ui.main.rig.yaw
		draw_set_transform(c, yaw, Vector2(SCALE, SCALE))
		draw_texture(tex, Vector2(-pp.x, -pp.z))
		for m in ui.world.mobs:
			if m.alive:
				var a: Actor = ui.view.mob_actors.get(m.id)
				if a:
					var q := Vector2(a.position.x - pp.x, a.position.z - pp.z)
					draw_rect(Rect2(q - Vector2(0.5, 0.5), Vector2(1, 1)), Color("f0d040") if m.kind != "warden" else UIKit.EMBER)
		for s in ui.world.map.stations:
			var q := Vector2(s.pos.x + 0.5 - pp.x, s.pos.y + 0.5 - pp.z)
			draw_circle(q, 0.8, Color("e8dfcc"))
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		draw_rect(Rect2(c - Vector2(2, 2), Vector2(4, 4)), Color.WHITE)
		# North marker rotates with the view.
		var n := Vector2(0, -1).rotated(yaw) * (size.x / 2 - 10) + c
		draw_string(UIKit.bold_font(), n + Vector2(-4, 5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIKit.BAD)
		draw_rect(Rect2(Vector2.ZERO, size), UIKit.LINE, false, 1.0)


class Orb extends Control:
	var ui
	var kind := "hp"
	var _hover := false

	func _init() -> void:
		custom_minimum_size = Vector2(62, 34)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func(): _hover = true)
		mouse_exited.connect(func(): _hover = false)

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and kind == "run":
			ui.world.player.run = not ui.world.player.run
			accept_event()

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var w: World = ui.world
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(UIKit.BG, 0.92))
		draw_rect(r, UIKit.LINE, false, 1.0)
		var circle_c := Vector2(17, 17)
		var frac := 1.0
		var col := UIKit.BAD
		var text := ""
		var glyph := ""
		match kind:
			"hp":
				var mh := w.max_hp()
				frac = clampf(float(w.player.hp) / mh, 0, 1)
				text = str(maxi(0, w.player.hp))
				glyph = "hitpoints"
				col = Color("b8342a")
			"run":
				frac = 1.0 if w.player.run else 0.0
				text = "Run" if w.player.run else "Walk"
				glyph = "run"
				col = Color("c8a040")
			"shards":
				frac = 1.0
				text = str(w.reagent_count())
				glyph = "shard"
				col = Color("a0401e")
		draw_circle(circle_c, 13, Color("0e0c0a"))
		if frac > 0:
			# Fill from the bottom as a chord of the circle.
			var pts := PackedVector2Array()
			var level := 13.0 - 26.0 * frac
			for i in 33:
				var a := TAU * i / 32.0
				var p := Vector2(cos(a), sin(a)) * 13.0
				if p.y >= level:
					pts.append(circle_c + p)
				else:
					pts.append(circle_c + Vector2(p.x, level))
			draw_colored_polygon(pts, col.darkened(0.15))
		draw_arc(circle_c, 13, 0, TAU, 24, UIKit.LINE, 1.0)
		Icons.glyph(self, glyph, Rect2(circle_c - Vector2(8, 8), Vector2(16, 16)), UIKit.INK)
		var f := UIKit.bold_font()
		var tc := UIKit.INK
		if kind == "hp" and frac < 0.35:
			tc = UIKit.BAD.lightened(0.3)
		draw_string(f, Vector2(34, 23), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, tc)


## The tick metronome: the current tick on the left, the next eleven to the
## right, with the player's next swing and every pending strike marked.
class TickStrip extends Control:
	var ui
	const CELLS := 12

	func _init() -> void:
		custom_minimum_size = Vector2(12 * 24 + 8, 46)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var w: World = ui.world
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(UIKit.BG, 0.9))
		draw_rect(r, UIKit.LINE, false, 1.0)
		var f := UIKit.bold_font()
		var prog: float = ui.tick_progress
		var cw := 24.0
		var y0 := 16.0
		var strikes := {}
		for tg in w.telegraphs:
			var d: int = tg.land - w.tick
			strikes[d] = true
		var s := w.stats()
		var in_fight := w.player.action.get("type", "") == "attack" or w.warden.active
		var interval := Defs.echo_interval(s.echo)
		for i in CELLS:
			var x := 4.0 + i * cw
			var cell := Rect2(x, y0, cw - 2, 24)
			var col := UIKit.SLOT
			if i == 0:
				col = UIKit.SLOT_HOVER.lerp(UIKit.GOLD.darkened(0.6), 1.0 - prog)
			draw_rect(cell, col)
			if strikes.has(i + 1):
				draw_rect(cell, Color(UIKit.EMBER, 0.85 if i == 0 else 0.55))
			# Player swing lands when the cooldown reaches zero.
			if in_fight and i == maxi(1, w.player.attack_cd) - 1:
				var cc := cell.get_center()
				var echo := interval > 0 and (w.player.attack_count + 1) % interval == 0
				var pts := PackedVector2Array([cc + Vector2(0, -7), cc + Vector2(6, 0), cc + Vector2(0, 7), cc + Vector2(-6, 0)])
				draw_colored_polygon(pts, UIKit.GOLD if not echo else UIKit.INK)
				if echo:
					draw_arc(cc, 9, 0, TAU, 12, UIKit.GOLD, 1.5)
		draw_string(f, Vector2(6, 13), "Tick %d" % w.tick, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIKit.ASH)
		var legend := ""
		if w.warden.active:
			var nxt := w.warden.next_attack_id()
			legend = "Next: %s in %d" % [Warden.ATTACKS[nxt].name if nxt != "cleave" or World._rect_dist(w.player.pos, w.warden_mob().rect()) <= 1 else "Ember Toss", maxi(0, w.warden.next_action - w.tick)]
		draw_string(f, Vector2(size.x - 6 - f.get_string_size(legend, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x, 13), legend, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIKit.EMBER)


class BossBar extends Control:
	var ui

	func _init() -> void:
		custom_minimum_size = Vector2(440, 44)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_d: float) -> void:
		visible = ui.world.warden.active
		if visible:
			queue_redraw()

	func _draw() -> void:
		var w: World = ui.world
		var m = w.warden_mob()
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(UIKit.BG, 0.9))
		draw_rect(r, UIKit.LINE, false, 1.0)
		var f := UIKit.display_font()
		draw_string(f, Vector2(10, 17), "Cinder Warden", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UIKit.GOLD)
		var ph: String = Warden.PHASES[w.warden.phase].name
		var bf := UIKit.body_font()
		draw_string(bf, Vector2(size.x - 10 - bf.get_string_size(ph, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, 17), ph, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIKit.ASH)
		var bar := Rect2(10, 24, size.x - 20, 12)
		draw_rect(bar, Color("2a0e0a"))
		var t := float(m.hp) / m.max_hp
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * t, bar.size.y)), Color("b8342a"))
		for th in [0.66, 0.33]:
			var x: float = bar.position.x + bar.size.x * th
			draw_line(Vector2(x, bar.position.y - 2), Vector2(x, bar.end.y + 2), UIKit.INK, 1.0)
		draw_rect(bar, UIKit.LINE, false, 1.0)


## Hitsplats, health bars, XP drops and the click cross, all in screen space.
class Overlay extends Control:
	var ui
	var splats: Array = []     # {target, amount, t, offset}
	var bars := {}             # target id -> expiry time
	var drops: Array = []      # {text, t, skill}
	var marker := {}           # {pos: Vector3, t, red}
	var clock := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func add_splat(target: int, amount: int) -> void:
		var n := 0
		for s in splats:
			if s.target == target and clock - s.t < 0.9:
				n += 1
		splats.append({"target": target, "amount": amount, "t": clock, "slot": n % 4})
		bars[target] = clock + 5.0

	func add_drop(skill: String, amount: float) -> void:
		for d in drops:
			if d.skill == skill and clock - d.t < 0.3:
				d.amount += amount
				return
		drops.append({"skill": skill, "amount": amount, "t": clock})

	func _process(delta: float) -> void:
		clock += delta
		splats = splats.filter(func(s): return clock - s.t < 1.1)
		drops = drops.filter(func(d): return clock - d.t < 1.8)
		queue_redraw()

	func _head(target: int) -> Variant:
		var a: Actor = ui.view.actor_for_target(target)
		if a == null or not a.visible:
			return null
		var cam: Camera3D = ui.main.rig.cam
		var p := a.global_position + Vector3(0, a.height + 0.1, 0)
		if cam.is_position_behind(p):
			return null
		return cam.unproject_position(p)

	func _draw() -> void:
		var f := UIKit.bold_font()
		var w: World = ui.world
		# Health bars over anything hurt recently.
		for target in bars.keys():
			if clock > bars[target]:
				bars.erase(target)
				continue
			var hp := 0
			var mh := 1
			if target == -1:
				hp = w.player.hp
				mh = w.max_hp()
			else:
				var m = w.mobs[target]
				if not m.alive or m.kind == "warden":
					continue
				hp = m.hp
				mh = m.max_hp
			var p = _head(target)
			if p == null:
				continue
			var bw := 36.0
			var rr := Rect2(p + Vector2(-bw / 2, -8), Vector2(bw, 5))
			draw_rect(rr, Color("a0201a"))
			draw_rect(Rect2(rr.position, Vector2(bw * clampf(float(hp) / mh, 0, 1), 5)), Color("30b030"))
		for s in splats:
			var p = _head(s.target)
			if p == null:
				continue
			var offs := [Vector2(0, 14), Vector2(-14, 26), Vector2(14, 26), Vector2(0, 38)]
			var c: Vector2 = p + offs[s.slot]
			var age: float = clock - s.t
			var col := Color("9a1c14") if s.amount > 0 else Color("2c4a8a")
			var pts := PackedVector2Array()
			for i in 10:
				var a := TAU * i / 10.0
				var rad := 11.0 + (2.0 if i % 2 == 0 else 0.0)
				pts.append(c + Vector2(cos(a), sin(a)) * rad)
			var alpha := 1.0 if age < 0.8 else 1.0 - (age - 0.8) / 0.3
			draw_colored_polygon(pts, Color(col, alpha))
			var txt := str(s.amount)
			var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			draw_string(f, c + Vector2(-tw / 2 + 1, 6), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0, 0, 0, alpha))
			draw_string(f, c + Vector2(-tw / 2, 5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, alpha))
		# XP drops rise beside the minimap.
		var base := Vector2(size.x - 262, 200)
		for i in drops.size():
			var d: Dictionary = drops[i]
			var age: float = clock - d.t
			var y := base.y - age * 60.0 + i * 0.0
			var txt := "+%d" % int(round(d.amount))
			var alpha := clampf(1.8 - age, 0, 1)
			Icons.glyph(self, d.skill, Rect2(base.x - 20, y - 14, 18, 18), Color(UIKit.INK, alpha))
			draw_string(f, Vector2(base.x + 1, y + 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0, 0, 0, alpha))
			draw_string(f, Vector2(base.x, y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(UIKit.INK, alpha))
		# Click cross.
		if not marker.is_empty():
			var age: float = clock - marker.t
			if age > 0.45:
				marker = {}
			else:
				var cam: Camera3D = ui.main.rig.cam
				var sp := cam.unproject_position(marker.pos)
				var col := Color("e8c030") if not marker.red else Color("e03a2a")
				var s := 7.0 * (1.0 - age / 0.45 * 0.5)
				draw_line(sp + Vector2(-s, -s), sp + Vector2(s, s), col, 2.5)
				draw_line(sp + Vector2(-s, s), sp + Vector2(s, -s), col, 2.5)
