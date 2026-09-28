class_name GameUI
extends CanvasLayer
## Lays out the interface, turns clicks into commands, and shows what the
## World reports. Encodes no rules: every check is asked of the World.

const SETTINGS_PATH := "user://settings.cfg"

var main
var world: World
var view: WorldView
var icons: Icons
var root: Control
var side: SidePanel
var minimap: Hud.Minimap
var overlay: Hud.Overlay
var ticks: Hud.TickStrip
var boss_bar: Hud.BossBar
var hover_text: RichTextLabel
var chat: RichTextLabel
var tooltip: Windows.Tooltip
var menu: Windows.ContextMenu
var window: Control
var tick_progress := 0.0
var use_item = null
var settings := {"xp_rate": 1.0}
var _log_lines: Array = []
var _hover_target := {}
var _dirty := true

func setup(m) -> void:
	main = m
	world = m.world
	view = m.view
	_load_settings()
	world.xp_rate = float(settings.get("xp_rate", 1.0))
	icons = Icons.new()
	add_child(icons)
	icons.baked.connect(func(_k): _dirty = true)
	root = Control.new()
	root.theme = UIKit.theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	overlay = Hud.Overlay.new()
	overlay.ui = self
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(overlay)
	# Hover text, top left.
	hover_text = UIKit.rich()
	hover_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	hover_text.position = Vector2(10, 8)
	hover_text.custom_minimum_size = Vector2(600, 24)
	hover_text.add_theme_font_size_override("normal_font_size", 17)
	hover_text.add_theme_font_size_override("bold_font_size", 17)
	hover_text.add_theme_constant_override("outline_size", 4)
	hover_text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	root.add_child(hover_text)
	# Minimap and orbs, top right.
	minimap = Hud.Minimap.new()
	minimap.ui = self
	minimap.build(world.map)
	root.add_child(minimap)
	place(minimap, Vector2(1, 0), Vector2(-180, 8), Vector2(172, 172))
	var orbs := VBoxContainer.new()
	orbs.add_theme_constant_override("separation", 4)
	root.add_child(orbs)
	place(orbs, Vector2(1, 0), Vector2(-250, 8), Vector2(62, 110))
	for k in ["hp", "run", "shards"]:
		var o := Hud.Orb.new()
		o.ui = self
		o.kind = k
		orbs.add_child(o)
	# Boss bar, top centre.
	boss_bar = Hud.BossBar.new()
	boss_bar.ui = self
	boss_bar.visible = false
	root.add_child(boss_bar)
	place(boss_bar, Vector2(0.5, 0), Vector2(-220, 8), Vector2(440, 44))
	# Side panel, bottom right.
	side = SidePanel.new()
	root.add_child(side)
	side.setup(self)
	place(side, Vector2(1, 1), Vector2(-258, -386), Vector2(250, 378))
	# Chat, bottom left.
	var chat_panel := PanelContainer.new()
	chat_panel.add_theme_stylebox_override("panel", UIKit.box(Color(UIKit.BG, 0.86), UIKit.LINE, 1, 2, 8))
	chat_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(chat_panel)
	place(chat_panel, Vector2(0, 1), Vector2(8, -164), Vector2(470, 156))
	chat = RichTextLabel.new()
	chat.bbcode_enabled = true
	chat.scroll_following = true
	chat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chat.add_theme_font_size_override("normal_font_size", 14)
	chat_panel.add_child(chat)
	# Tick strip beside the chat.
	ticks = Hud.TickStrip.new()
	ticks.ui = self
	root.add_child(ticks)
	place(ticks, Vector2(0, 1), Vector2(488, -54), Vector2(296, 46))
	tooltip = Windows.Tooltip.new()
	root.add_child(tooltip)
	menu = Windows.ContextMenu.new()
	menu.ui = self
	root.add_child(menu)
	_log("Thornreach camp. Left-click to act, right-click for options.", UIKit.ASH)
	if world.tick == 0:
		_log("The forest lies west, the mine east across the bridge, the Warden's hollow south.", UIKit.ASH)
	refresh_all()

## Pin a control to an anchor point with a fixed offset and size.
static func place(c: Control, anchor: Vector2, offset: Vector2, sz: Vector2) -> void:
	c.anchor_left = anchor.x
	c.anchor_right = anchor.x
	c.anchor_top = anchor.y
	c.anchor_bottom = anchor.y
	c.offset_left = offset.x
	c.offset_top = offset.y
	c.offset_right = offset.x + sz.x
	c.offset_bottom = offset.y + sz.y

# ================================================================ refresh

func refresh_all() -> void:
	_dirty = false
	side.refresh()
	if window and window.has_method("refresh"):
		window.refresh()

func on_tick() -> void:
	flush_log()
	side.refresh()
	if window is Windows.StashWindow:
		pass

func flush_log() -> void:
	for e in world.events:
		if e.type == "log":
			_log(e.text, _log_color(e.text))
	# Log events are consumed once; mark them.
	for e in world.events:
		if e.type == "log":
			e.type = "logged"

func _log_color(t: String) -> Color:
	if t.contains(" level "):
		return UIKit.EMBER
	if t.contains("Cinder Shard") or t.begins_with("Crafted") or t.begins_with("Perk"):
		return UIKit.GOLD
	if t.begins_with("The Warden") or t.begins_with("The Cinder"):
		return Color("f09060")
	return UIKit.INK

func _log(text: String, col := UIKit.INK) -> void:
	_log_lines.append("[color=#%s]%s[/color]" % [UIKit.hex(col), text])
	if _log_lines.size() > 60:
		_log_lines.pop_front()
	chat.text = "\n".join(_log_lines)

func _process(_d: float) -> void:
	if _dirty:
		refresh_all()
	_update_hover()

# ================================================================ events

func handle_event(e: Dictionary) -> void:
	match e.type:
		"hit":
			overlay.add_splat(e.target, e.amount)
		"xp":
			overlay.add_drop(e.skill, e.amount)
		"station":
			_open_station(e.kind)
		"tell":
			_log("Read the Tell: next attack certain.", UIKit.EMBER)
		"you_died":
			_show_recap(e)
		"boss":
			if e.event == "defeated":
				_show_victory(e)
	_dirty = true

func _open_station(kind: String) -> void:
	match kind:
		"stash":
			var w := Windows.StashWindow.new()
			w.ui = self
			w.build()
			open_window(w)
		"anvil", "bench":
			var w := Windows.CraftWindow.new()
			w.ui = self
			w.build("smithing" if kind == "anvil" else "fletching")
			open_window(w)
		"shrine":
			side.show_tab("boards")
		"hearth":
			pass

func _show_recap(e: Dictionary) -> void:
	var lines := []
	var recap: Array = e.recap
	for i in range(recap.size() - 1, -1, -1):
		var r: Dictionary = recap[i]
		var line := "%s  %s %s" % [ItemText.c(UIKit.DIM, "Tick %d" % r.tick), r.source, ItemText.c(UIKit.BAD, str(r.amount))]
		if r.why != "":
			line += ItemText.c(UIKit.ASH, ": you %s." % r.why)
		lines.append(line)
		if i == recap.size() - 1:
			lines.append("")
	var head := ""
	if e.warden:
		head = ItemText.c(UIKit.ASH, "Phase %d, %s. The Warden resets.\n\n" % [e.phase, Warden.PHASES[e.phase].name])
	var w := Windows.NoticeWindow.new()
	w.ui = self
	w.build("You died", head + "\n".join(lines), "Wake at the hearth")
	open_window(w)

func _show_victory(e: Dictionary) -> void:
	var w := Windows.NoticeWindow.new()
	w.ui = self
	var best := "A new best." if e.best else "Best: %d ticks." % world.player.warden_best
	w.build("The Warden falls", "%d ticks. %s\n%s" % [e.ticks, best, ItemText.c(UIKit.GOLD, "3 Cinder Shards.")], "Leave the hollow")
	open_window(w)

# ================================================================ windows

func open_window(w: Control) -> void:
	if window:
		close_window(window)
	window = w
	root.add_child(w)
	if w.has_method("refresh"):
		w.refresh()
	w.center()

func close_window(w: Control) -> void:
	if w == window:
		window = null
	hide_tooltip()
	w.queue_free()

# ================================================================ tooltips

func show_tooltip(item: Dictionary) -> void:
	tooltip.show_bb(ItemText.describe(item, world))

func show_text_tooltip(bb: String) -> void:
	tooltip.show_bb(bb)

func hide_tooltip() -> void:
	tooltip.visible = false

# ================================================================ items

func item_default_action(it: Dictionary, where: String) -> void:
	hide_tooltip()
	if use_item != null:
		use_on(it)
		return
	if window is Windows.StashWindow and where == "pack":
		world.deposit(it.uid)
		refresh_all()
		return
	match it.kind:
		"gear":
			world.equip(it.uid)
		"reagent":
			use_item = it
			_log("Choose gear to temper.", UIKit.ASH)
		"component":
			show_tooltip(it)
	refresh_all()

func open_item_menu(it: Dictionary, where: String) -> void:
	hide_tooltip()
	var name := ItemText.c(UIKit.rarity_color(int(it.get("rarity", 5)) if it.kind != "reagent" else 5), Items.item_name(it))
	var opts := []
	if where == "stash":
		opts.append({"label": "Withdraw " + name, "cb": func():
			world.withdraw(it.uid)
			refresh_all()})
	if where == "pack" and window is Windows.StashWindow:
		opts.append({"label": "Deposit " + name, "cb": func():
			world.deposit(it.uid)
			refresh_all()})
	if it.kind == "gear":
		if where == "gear":
			opts.append({"label": "Remove " + name, "cb": func():
				world.unequip(it.slot)
				refresh_all()})
		elif where == "pack":
			opts.append({"label": "Equip " + name, "cb": func():
				world.equip(it.uid)
				refresh_all()})
		if world.reagent_count() > 0:
			opts.append({"label": "Temper " + name, "cb": func(): temper(it)})
		if world.player.perks.has("salvage") and where != "gear":
			opts.append({"label": "Salvage %s (%d)" % [name, Items.salvage_yield(it)], "cb": func():
				world.salvage(it.uid)
				flush_log()
				refresh_all()})
	if it.kind == "reagent":
		opts.append({"label": "Use " + name, "cb": func():
			use_item = it
			refresh_all()})
	opts.append({"label": "Examine " + name, "cb": func(): show_tooltip(it)})
	if where != "gear":
		opts.append({"label": "Drop " + name, "cb": func():
			world.drop(it.uid)
			flush_log()
			refresh_all()})
	opts.append({"label": "Cancel", "cb": func(): pass})
	menu.open(root.get_viewport().get_mouse_position(), opts)

func cancel_use() -> void:
	use_item = null
	refresh_all()

func use_on(target: Dictionary) -> void:
	var it = use_item
	use_item = null
	if it != null and it.kind == "reagent" and target.kind == "gear":
		temper(target)
	refresh_all()

func temper(it: Dictionary) -> void:
	if world.player.perks.has("guided_temper"):
		var lv := world.level(Defs.FAMILY_SKILL[it.family])
		var cands := Items.temper_candidates(it, lv)
		if cands.is_empty():
			world.temper(it.uid)
			flush_log()
			return
		var opts := []
		for i in cands:
			var m: Dictionary = it.mods[i]
			opts.append({"text": "%s %s to %s  (%s)" % [Defs.MODS[m.id].name, ItemText.tier(m.tier), ItemText.tier(int(m.tier) + 1), ItemText.LETTERS[int(m.src)]], "value": i})
		var w := Windows.ChoiceWindow.new()
		w.ui = self
		w.build("Guided Temper", opts, func(v):
			world.temper(it.uid, v)
			flush_log()
			refresh_all())
		open_window(w)
		return
	world.temper(it.uid)
	flush_log()
	refresh_all()

# ================================================================ world clicks

func world_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				if menu.visible:
					menu.visible = false
				elif window:
					close_window(window)
				elif use_item != null:
					cancel_use()
			KEY_R:
				world.player.run = not world.player.run
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				side.show_tab(SidePanel.TABS[event.keycode - KEY_1])
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	if menu.visible:
		menu.visible = false
		return
	var t := pick(event.position)
	var opts := options_for(t)
	if event.button_index == MOUSE_BUTTON_LEFT:
		if use_item != null:
			cancel_use()
			return
		if not opts.is_empty():
			opts[0].cb.call()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		opts.append({"label": "Cancel", "cb": func(): pass})
		menu.open(event.position, opts)

## What lies under a screen point: a creature, node, station, or ground tile.
func pick(screen: Vector2) -> Dictionary:
	var cam: Camera3D = main.rig.cam
	var best := {}
	var best_d := 30.0
	for id in view.mob_actors:
		var m = world.mobs[id]
		var a: Actor = view.mob_actors[id]
		if not m.alive or not a.visible:
			continue
		for f in [0.3, 0.6, 0.9]:
			var p := a.global_position + Vector3(0, a.height * f, 0)
			if cam.is_position_behind(p):
				continue
			var d := cam.unproject_position(p).distance_to(screen)
			var lim := 30.0 * (2.0 if m.kind == "warden" else 1.0)
			if d < lim and d < best_d * (2.0 if m.kind == "warden" else 1.0):
				best = {"kind": "mob", "id": id}
				best_d = d
	var ground: Vector3 = main.rig.ground_point(screen, 0.0)
	var tile := Vector2i(int(floor(ground.x)), int(floor(ground.z)))
	if best.is_empty():
		for i in world.nodes.size():
			var n: Dictionary = world.nodes[i]
			var fam: String = Defs.RESOURCES[n.res].family
			var hs := [0.2, 0.8, 1.5] if fam == "log" else [0.3]
			for h in hs:
				var p: Vector3 = view.tile_pos(n.pos) + Vector3(0, h, 0)
				if cam.is_position_behind(p):
					continue
				var d := cam.unproject_position(p).distance_to(screen)
				if d < best_d:
					best = {"kind": "node", "id": i}
					best_d = d
		for i in world.map.stations.size():
			var p: Vector3 = view.tile_pos(world.map.stations[i].pos) + Vector3(0, 0.5, 0)
			var d := cam.unproject_position(p).distance_to(screen)
			if d < best_d:
				best = {"kind": "station", "id": i}
				best_d = d
	if best.is_empty():
		best = {"kind": "ground", "tile": tile, "point": ground}
	return best

const STATION_VERBS := {"stash": ["Open", "Stash"], "anvil": ["Smith", "Anvil"], "bench": ["Fletch", "Fletching bench"],
	"shrine": ["Attune", "Board shrine"], "hearth": ["Rest", "Hearth"]}
const STATION_EXAMINE := {"stash": "Holds everything, shared with every station in camp.", "anvil": "Smithing: swords, warhammers, helms, cuirasses.",
	"bench": "Fletching: bows and bucklers.", "shrine": "Spend board points here or from the Boards tab.", "hearth": "Restores all health. You wake here after dying."}

func _target_name(text: String, col := UIKit.HOVER_TARGET) -> String:
	return ItemText.c(col, text)

func options_for(t: Dictionary) -> Array:
	var opts := []
	match t.kind:
		"mob":
			var m = world.mobs[t.id]
			var d: Dictionary = Defs.MOBS[m.kind]
			var lvl_col := UIKit.GOOD if d.combat <= world.combat_level() else UIKit.BAD
			var n := "%s %s" % [_target_name(d.name), ItemText.c(lvl_col, "(level %d)" % d.combat)]
			opts.append({"label": "Attack " + n, "cb": func():
				world.cmd_attack(t.id)
				set_click_marker(view.mob_pos(m), true)})
			var ex := "Combat %d. %s" % [d.combat, "Attacks on sight." if int(d.aggro) > 0 else "Fights back."]
			if int(d.range) > 1:
				ex += " Shoots from %d tiles." % d.range
			opts.append({"label": "Examine " + n, "cb": func(): _log(ex, UIKit.ASH)})
		"node":
			var node: Dictionary = world.nodes[t.id]
			var r: Dictionary = Defs.RESOURCES[node.res]
			var verb := "Chop down" if r.family == "log" else "Mine"
			var skill: String = Defs.FAMILY_SKILL[r.family]
			var n := _target_name(r.node, UIKit.HOVER_TARGET if world.level(skill) >= r.req else UIKit.DIM)
			if node.remaining > 0:
				opts.append({"label": "%s %s" % [verb, n], "cb": func():
					world.cmd_gather(t.id)
					flush_log()
					set_click_marker(view.tile_pos(node.pos), true)})
			var ex := "Requires %s %d. Rolls tiers up to %s." % [Defs.SKILL_NAMES[skill], r.req, Defs.TIER_NUMERALS[Defs.tier_ceiling(r.req)]]
			if node.remaining <= 0:
				ex = "Depleted. " + ex
			opts.append({"label": "Examine " + n, "cb": func(): _log(ex, UIKit.ASH)})
		"station":
			var st: Dictionary = world.map.stations[t.id]
			var v: Array = STATION_VERBS[st.kind]
			opts.append({"label": "%s %s" % [v[0], _target_name(v[1])], "cb": func():
				world.cmd_station(t.id)
				set_click_marker(view.tile_pos(st.pos), true)})
			opts.append({"label": "Examine " + _target_name(v[1]), "cb": func(): _log(STATION_EXAMINE[st.kind], UIKit.ASH)})
	if t.kind == "ground" or true:
		var tile: Vector2i = t.get("tile", Vector2i(-1, -1))
		if t.kind != "ground":
			var g: Vector3 = main.rig.ground_point(root.get_viewport().get_mouse_position(), 0.0)
			tile = Vector2i(int(floor(g.x)), int(floor(g.z)))
		opts.append({"label": "Walk here", "cb": func():
			world.cmd_walk(tile)
			set_click_marker_tile(tile, false)})
	return opts

func set_click_marker(p: Vector3, red: bool) -> void:
	overlay.marker = {"pos": p + Vector3(0, 0.05, 0), "t": overlay.clock, "red": red}

func set_click_marker_tile(tile: Vector2i, red: bool) -> void:
	if world.map.in_bounds(tile):
		set_click_marker(view.tile_pos(tile), red)

func _update_hover() -> void:
	if menu.visible or window and window.get_global_rect().has_point(root.get_viewport().get_mouse_position()):
		hover_text.text = ""
		return
	var mp := root.get_viewport().get_mouse_position()
	var gui := root.get_viewport().gui_get_hovered_control()
	if gui != null and gui != overlay and gui != root:
		if use_item != null:
			hover_text.text = "Use %s ->" % ItemText.c(UIKit.EMBER, Defs.REAGENT_NAME)
		else:
			hover_text.text = ""
		return
	var t := pick(mp)
	var opts := options_for(t)
	if use_item != null:
		hover_text.text = "Use %s -> choose gear" % ItemText.c(UIKit.EMBER, Defs.REAGENT_NAME)
	elif opts.is_empty():
		hover_text.text = ""
	else:
		var extra := opts.size() - 1
		hover_text.text = opts[0].label + (ItemText.c(UIKit.ASH, "  / %d more option%s" % [extra, "s" if extra > 1 else ""]) if extra > 0 else "")

# ================================================================ settings

func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		for k in cf.get_section_keys("game"):
			settings[k] = cf.get_value("game", k)

func save_settings() -> void:
	var cf := ConfigFile.new()
	for k in settings:
		cf.set_value("game", k, settings[k])
	cf.save(SETTINGS_PATH)
