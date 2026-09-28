class_name SidePanel
extends PanelContainer
## The panel at the lower right: Pack, Gear, Skills, Boards, Settings.

const TABS := ["pack", "gear", "skills", "boards", "settings"]
const TAB_NAMES := {"pack": "Pack", "gear": "Gear", "skills": "Skills", "boards": "Boards", "settings": "Settings"}

var ui
var world: World
var tab := "pack"
var tab_buttons := {}
var pages := {}
var pack_slots: Array = []
var gear_slots := {}
var gear_stats: RichTextLabel
var skill_tiles := {}
var skill_footer: Label
var board_sel := "combat"
var board_view: BoardGraph
var board_info: RichTextLabel
var board_tabs := {}

func setup(u) -> void:
	ui = u
	world = u.world
	add_theme_stylebox_override("panel", UIKit.box(Color(UIKit.BG, 0.95), UIKit.LINE, 1, 2, 6))
	var v := VBoxContainer.new()
	add_child(v)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 2)
	v.add_child(tabs)
	for t in TABS:
		var b := TabGlyph.new()
		b.kind = t
		b.tooltip_text = TAB_NAMES[t]
		b.pressed_cb = func(): show_tab(t)
		tabs.add_child(b)
		tab_buttons[t] = b
	var stack := Control.new()
	stack.custom_minimum_size = Vector2(236, 322)
	v.add_child(stack)
	pages.pack = _build_pack()
	pages.gear = _build_gear()
	pages.skills = _build_skills()
	pages.boards = _build_boards()
	pages.settings = _build_settings()
	for p in pages.values():
		p.set_anchors_preset(Control.PRESET_FULL_RECT)
		stack.add_child(p)
	show_tab("pack")

func show_tab(t: String) -> void:
	tab = t
	for k in pages:
		pages[k].visible = k == t
		tab_buttons[k].active = k == t
		tab_buttons[k].queue_redraw()
	refresh()

func refresh() -> void:
	match tab:
		"pack": _refresh_pack()
		"gear": _refresh_gear()
		"skills": _refresh_skills()
		"boards": _refresh_boards()

# ---------------------------------------------------------------- pack

func _build_pack() -> Control:
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 4)
	g.add_theme_constant_override("v_separation", 2)
	for i in Defs.PACK_SLOTS:
		var s := ItemSlot.new()
		s.ui = ui
		s.icon_source = ui.icons
		s.index = i
		s.draggable = true
		s.custom_minimum_size = Vector2(56, 44)
		s.clicked.connect(_on_pack_click)
		s.dropped_on.connect(func(a, b):
			world.swap_pack(a, b)
			_refresh_pack())
		g.add_child(s)
		pack_slots.append(s)
	return g

func _refresh_pack() -> void:
	for i in Defs.PACK_SLOTS:
		var it = world.player.pack[i]
		pack_slots[i].set_item(it)
		pack_slots[i].selected = ui.use_item != null and it != null and it.uid == ui.use_item.uid

func _on_pack_click(slot: ItemSlot, button: int) -> void:
	var it = slot.item
	if it == null:
		ui.cancel_use()
		return
	if button == MOUSE_BUTTON_RIGHT:
		ui.open_item_menu(it, "pack")
		return
	ui.item_default_action(it, "pack")

# ---------------------------------------------------------------- gear

func _build_gear() -> Control:
	var v := VBoxContainer.new()
	var grid := Control.new()
	grid.custom_minimum_size = Vector2(236, 150)
	v.add_child(grid)
	var pos := {"head": Vector2(91, 4), "weapon": Vector2(30, 54), "body": Vector2(91, 54), "shield": Vector2(152, 54)}
	var glyphs := {"head": "gear", "weapon": "melee", "body": "pack", "shield": "boards"}
	for slot in Defs.SLOTS:
		var s := ItemSlot.new()
		s.ui = ui
		s.icon_source = ui.icons
		s.empty_glyph = glyphs[slot]
		s.position = pos[slot]
		s.size = Vector2(56, 44)
		s.clicked.connect(func(sl, btn):
			if sl.item == null:
				return
			if btn == MOUSE_BUTTON_RIGHT:
				ui.open_item_menu(sl.item, "gear")
			elif ui.use_item != null:
				ui.use_on(sl.item)
			else:
				world.unequip(slot)
				ui.refresh_all())
		grid.add_child(s)
		gear_slots[slot] = s
		var l := UIKit.label(Defs.SLOT_NAMES[slot], 11, UIKit.DIM)
		l.position = pos[slot] + Vector2(0, 45)
		l.size = Vector2(56, 14)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(l)
	gear_stats = UIKit.rich()
	gear_stats.custom_minimum_size = Vector2(236, 0)
	v.add_child(gear_stats)
	return v

func _refresh_gear() -> void:
	for slot in Defs.SLOTS:
		gear_slots[slot].set_item(world.player.equipment.get(slot))
	gear_stats.text = ItemText.stats_summary(world)

# ---------------------------------------------------------------- skills

func _build_skills() -> Control:
	var v := VBoxContainer.new()
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 4)
	g.add_theme_constant_override("v_separation", 4)
	v.add_child(g)
	for s in Defs.SKILLS:
		var t := SkillTile.new()
		t.skill = s
		t.world = world
		t.ui = ui
		g.add_child(t)
		skill_tiles[s] = t
	skill_footer = UIKit.label("", 14, UIKit.ASH)
	v.add_child(skill_footer)
	return v

func _refresh_skills() -> void:
	for s in skill_tiles:
		skill_tiles[s].queue_redraw()
	skill_footer.text = "Total level %d   Combat %d" % [world.total_level(), world.combat_level()]

# ---------------------------------------------------------------- boards

func _build_boards() -> Control:
	var v := VBoxContainer.new()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 2)
	v.add_child(h)
	for b in Defs.BOARD_ORDER:
		var btn := UIKit.button(Defs.BOARDS[b].name, func():
			board_sel = b
			_refresh_boards())
		btn.custom_minimum_size = Vector2(77, 26)
		btn.add_theme_font_size_override("font_size", 13)
		h.add_child(btn)
		board_tabs[b] = btn
	board_view = BoardGraph.new()
	board_view.ui = ui
	board_view.custom_minimum_size = Vector2(236, 170)
	v.add_child(board_view)
	board_info = UIKit.rich()
	board_info.custom_minimum_size = Vector2(236, 0)
	v.add_child(board_info)
	return v

func _refresh_boards() -> void:
	for b in board_tabs:
		var pts := world.board_points(b) - world.board_spent(b)
		board_tabs[b].text = Defs.BOARDS[b].name + (" +%d" % pts if pts > 0 else "")
		board_tabs[b].add_theme_color_override("font_color", UIKit.EMBER if b == board_sel else UIKit.INK)
	board_view.world = world
	board_view.board = board_sel
	board_view.queue_redraw()
	var lv := world.board_level(board_sel)
	var pts := world.board_points(board_sel)
	var linked := []
	for e in Defs.BOARDS[board_sel].skills:
		linked.append(" or ".join(Array(e.split("|")).map(func(x): return Defs.SKILL_NAMES[x])))
	var next := "" if pts >= Defs.BOARD_PERK_COUNT else "Next point at board level %d." % ((pts + 1) * Defs.LEVELS_PER_BOARD_POINT)
	board_info.text = "%s\n%s\n%s" % [
		ItemText.c(UIKit.ASH, "Board level %d: the average of %s." % [lv, " and ".join(linked)]),
		"Points %d of %d, %d spent." % [pts, Defs.BOARD_PERK_COUNT, world.board_spent(board_sel)],
		ItemText.c(UIKit.DIM, next)]

# ---------------------------------------------------------------- settings

func _build_settings() -> Control:
	var v := VBoxContainer.new()
	v.add_child(UIKit.heading("Settings", 16))
	var rate := UIKit.button("", func(): pass)
	rate.pressed.connect(func():
		world.xp_rate = 3.0 if world.xp_rate == 1.0 else 1.0
		ui.settings.xp_rate = world.xp_rate
		rate.text = "XP rate: %s" % ("Brisk x3" if world.xp_rate > 1.0 else "Standard")
		ui.save_settings())
	rate.text = "XP rate: %s" % ("Brisk x3" if world.xp_rate > 1.0 else "Standard")
	v.add_child(rate)
	var run := UIKit.button("", func(): pass)
	run.pressed.connect(func():
		world.player.run = not world.player.run
		run.text = "Movement: %s" % ("Run" if world.player.run else "Walk"))
	run.text = "Movement: %s" % ("Run" if world.player.run else "Walk")
	v.add_child(run)
	var confirm := [false]
	var reset := UIKit.button("New game", func(): pass)
	reset.pressed.connect(func():
		if confirm[0]:
			ui.main.new_game()
		else:
			confirm[0] = true
			reset.text = "Erase save and restart?")
	v.add_child(reset)
	var help := UIKit.rich()
	help.text = ItemText.c(UIKit.ASH, "Left-click acts. Right-click lists options. Arrow keys or middle-drag turn the camera; the wheel zooms. R toggles run. 1–5 switch tabs.")
	v.add_child(help)
	return v


# ================================================================ helpers

class TabGlyph extends Control:
	var kind := ""
	var active := false
	var pressed_cb: Callable
	var _hover := false

	func _init() -> void:
		custom_minimum_size = Vector2(45, 32)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func(): _hover = true; queue_redraw())
		mouse_exited.connect(func(): _hover = false; queue_redraw())

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			pressed_cb.call()
			accept_event()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color("3a2618") if active else (UIKit.SLOT_HOVER if _hover else UIKit.SLOT))
		draw_rect(r, UIKit.EMBER if active else UIKit.LINE_SOFT, false, 1.0)
		Icons.glyph(self, kind, r.grow(-6), UIKit.EMBER if active else UIKit.INK)


class SkillTile extends Control:
	var skill := ""
	var world: World
	var ui

	func _init() -> void:
		custom_minimum_size = Vector2(116, 40)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func(): ui.show_text_tooltip(_tip()))
		mouse_exited.connect(func(): ui.hide_tooltip())

	func _tip() -> String:
		var lv := world.level(skill)
		var xp: float = world.player.xp[skill]
		var lines := ["[b]%s[/b] %d" % [Defs.SKILL_NAMES[skill], lv]]
		lines.append(ItemText.c(UIKit.ASH, Defs.SKILL_BLURBS[skill]))
		lines.append("%s xp" % _num(int(xp)))
		if lv < Defs.MAX_LEVEL:
			lines.append(ItemText.c(UIKit.DIM, "%s to level %d" % [_num(Defs.xp_for_level(lv + 1) - int(xp)), lv + 1]))
		if skill in ["woodcutting", "mining"]:
			lines.append(ItemText.c(UIKit.GOLD, "Tempers up to tier %s" % Defs.TIER_NUMERALS[Defs.tier_ceiling(lv)]))
		return "\n".join(lines)

	static func _num(n: int) -> String:
		var s := str(n)
		var out := ""
		for i in s.length():
			if i > 0 and (s.length() - i) % 3 == 0:
				out += ","
			out += s[i]
		return out

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, UIKit.SLOT)
		draw_rect(r, UIKit.LINE_SOFT, false, 1.0)
		Icons.glyph(self, skill, Rect2(4, 4, 32, 32), UIKit.INK)
		var lv := world.level(skill)
		draw_string(UIKit.bold_font(), Vector2(44, 26), "%d" % lv, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UIKit.GOLD)
		# Progress to the next level along the bottom edge.
		var xp: float = world.player.xp[skill]
		var a := Defs.xp_for_level(lv)
		var b := Defs.xp_for_level(mini(lv + 1, Defs.MAX_LEVEL))
		var t := 1.0 if b <= a else clampf((xp - a) / (b - a), 0, 1)
		draw_rect(Rect2(1, r.size.y - 4, (r.size.x - 2) * t, 3), UIKit.EMBER.darkened(0.2))
		draw_string(UIKit.body_font(), Vector2(76, 26), Defs.SKILL_NAMES[skill].substr(0, 5), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIKit.DIM)


class BoardGraph extends Control:
	var world: World
	var board := "combat"
	var ui
	var _hover_slot := ""
	const POS := {"root": Vector2(0.5, 0.1), "a": Vector2(0.24, 0.36), "b": Vector2(0.76, 0.36),
		"c": Vector2(0.24, 0.64), "d": Vector2(0.76, 0.64), "e": Vector2(0.5, 0.9)}

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _perk(slot: String) -> Dictionary:
		for p in Defs.PERKS[board]:
			if p.slot == slot:
				return p
		return {}

	func _pt(slot: String) -> Vector2:
		return POS[slot] * size

	func _slot_at(p: Vector2) -> String:
		for s in ["a", "b", "c", "d", "e"]:
			if p.distance_to(_pt(s)) < 18:
				return s
		return ""

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseMotion:
			var s := _slot_at(e.position)
			if s != _hover_slot:
				_hover_slot = s
				queue_redraw()
				if s == "":
					ui.hide_tooltip()
				else:
					var p := _perk(s)
					var state := "Taken." if world.player.perks.has(p.id) else ("Click to take." if world.perk_available(p.id) else "Locked.")
					ui.show_text_tooltip("[b]%s[/b]\n%s\n%s" % [p.name, p.desc, ItemText.c(UIKit.DIM, state)])
		elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			var s := _slot_at(e.position)
			if s != "":
				if world.take_perk(_perk(s).id):
					ui.refresh_all()
					ui.flush_log()

	func _draw() -> void:
		if world == null:
			return
		var links := [["root", "a"], ["root", "b"], ["a", "c"], ["b", "d"], ["c", "e"], ["d", "e"]]
		for l in links:
			var on: bool = (l[0] == "root" or world.player.perks.has(_perk(l[0]).id)) and world.player.perks.has(_perk(l[1]).id)
			draw_line(_pt(l[0]), _pt(l[1]), UIKit.EMBER if on else UIKit.LINE, 2.0 if on else 1.0)
		draw_circle(_pt("root"), 6, UIKit.LINE)
		var t := Time.get_ticks_msec() * 0.004
		for s in ["a", "b", "c", "d", "e"]:
			var p := _perk(s)
			var c := _pt(s)
			var taken: bool = world.player.perks.has(p.id)
			var avail := world.perk_available(p.id)
			var r := 14.0
			var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
			if taken:
				draw_colored_polygon(pts, UIKit.EMBER)
			else:
				draw_colored_polygon(pts, UIKit.SLOT)
			var edge := UIKit.GOLD.lerp(UIKit.EMBER, 0.5 + 0.5 * sin(t)) if avail else (UIKit.EMBER if taken else UIKit.LINE)
			pts.append(pts[0])
			draw_polyline(pts, edge, 2.0 if avail or s == _hover_slot else 1.0)
			var name_col := UIKit.INK if taken or avail else UIKit.DIM
			var f := UIKit.body_font()
			var w := f.get_string_size(p.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			var lx := c.x - w / 2
			var ly := c.y + r + 13
			if s == "e":
				lx = c.x + r + 6
				ly = c.y + 4
			draw_string(f, Vector2(lx, ly), p.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, name_col)
		if world.board_points(board) > world.board_spent(board):
			queue_redraw()
