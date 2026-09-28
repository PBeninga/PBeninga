class_name Windows
extends RefCounted
## Modal windows: stash, crafting, death recap, victory, temper choice,
## plus the tooltip and the right-click menu.


class Modal extends PanelContainer:
	var ui
	var body: VBoxContainer
	var title_label: Label

	func _init() -> void:
		add_theme_stylebox_override("panel", UIKit.box(Color(UIKit.BG, 0.98), UIKit.LINE, 1, 2, 12))
		mouse_filter = Control.MOUSE_FILTER_STOP
		body = VBoxContainer.new()
		body.add_theme_constant_override("separation", 8)
		add_child(body)
		var head := HBoxContainer.new()
		body.add_child(head)
		title_label = UIKit.heading("", 20)
		title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title_label)
		var x := UIKit.button("Close", func(): close())
		x.add_theme_font_size_override("font_size", 13)
		head.add_child(x)

	func close() -> void:
		ui.close_window(self)

	func center() -> void:
		await get_tree().process_frame
		reset_size()
		var vs := get_viewport_rect().size
		position = ((vs - size) / 2).floor() - Vector2(90, 30)
		position.x = maxf(8, position.x)
		position.y = maxf(8, position.y)

	func refresh() -> void:
		pass


# ================================================================ stash

class StashWindow extends Modal:
	var stash_grid: GridContainer
	var pack_grid: GridContainer
	var filter := "all"
	var filter_buttons := {}

	func build() -> void:
		title_label.text = "Stash"
		var filters := HBoxContainer.new()
		body.add_child(filters)
		for f in ["all", "log", "ore", "gear"]:
			var names := {"all": "All", "log": "Logs", "ore": "Ore", "gear": "Gear"}
			var b := UIKit.button(names[f], func():
				filter = f
				refresh())
			b.add_theme_font_size_override("font_size", 13)
			filters.add_child(b)
			filter_buttons[f] = b
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		filters.add_child(spacer)
		filters.add_child(UIKit.button("Deposit pack", func():
			ui.world.deposit_all()
			ui.refresh_all()))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		body.add_child(row)
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(478, 330)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		row.add_child(scroll)
		stash_grid = GridContainer.new()
		stash_grid.columns = 8
		stash_grid.add_theme_constant_override("h_separation", 3)
		stash_grid.add_theme_constant_override("v_separation", 3)
		scroll.add_child(stash_grid)
		var hint := UIKit.label("Click to move between stash and pack.", 13, UIKit.DIM)
		body.add_child(hint)

	func _sorted() -> Array:
		var items: Array = ui.world.player.stash.duplicate()
		items = items.filter(func(it):
			match filter:
				"log", "ore": return it.kind == "component" and Defs.RESOURCES[it.res].family == filter
				"gear": return it.kind == "gear"
			return true)
		items.sort_custom(func(a, b):
			if a.kind != b.kind:
				return a.kind < b.kind
			var ra := int(a.get("rarity", 9))
			var rb := int(b.get("rarity", 9))
			if ra != rb:
				return ra > rb
			return a.uid < b.uid)
		return items

	func refresh() -> void:
		for b in filter_buttons:
			filter_buttons[b].add_theme_color_override("font_color", UIKit.EMBER if b == filter else UIKit.INK)
		for c in stash_grid.get_children():
			c.queue_free()
		for it in _sorted():
			var s := ItemSlot.new()
			s.ui = ui
			s.icon_source = ui.icons
			s.set_item(it)
			s.clicked.connect(func(sl, btn):
				if btn == MOUSE_BUTTON_RIGHT:
					ui.open_item_menu(sl.item, "stash")
				else:
					ui.world.withdraw(sl.item.uid)
					ui.hide_tooltip()
					ui.refresh_all())
			stash_grid.add_child(s)
		title_label.text = "Stash · %d" % ui.world.player.stash.size()


# ================================================================ crafting

class CraftWindow extends Modal:
	var skill := "fletching"
	var family := "log"
	var recipe := ""
	var res := ""
	var picked: Array = []
	var recipe_box: VBoxContainer
	var mat_box: HFlowContainer
	var comp_box: VBoxContainer
	var preview: RichTextLabel
	var craft_btn: Button
	var reason: Label

	func build(station_skill: String) -> void:
		skill = station_skill
		family = "log" if skill == "fletching" else "ore"
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		body.add_child(row)
		recipe_box = VBoxContainer.new()
		recipe_box.custom_minimum_size = Vector2(170, 0)
		row.add_child(recipe_box)
		var mid := VBoxContainer.new()
		mid.custom_minimum_size = Vector2(300, 0)
		row.add_child(mid)
		mid.add_child(UIKit.label("Material", 13, UIKit.ASH))
		mat_box = HFlowContainer.new()
		mat_box.add_theme_constant_override("h_separation", 4)
		mat_box.add_theme_constant_override("v_separation", 4)
		mid.add_child(mat_box)
		var hdr := HBoxContainer.new()
		mid.add_child(hdr)
		var cl := UIKit.label("Components", 13, UIKit.ASH)
		cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hdr.add_child(cl)
		var best := UIKit.button("Pick best", func():
			picked = ui.world.auto_pick(recipe, res) if res != "" else []
			refresh())
		best.add_theme_font_size_override("font_size", 12)
		hdr.add_child(best)
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(300, 250)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		mid.add_child(scroll)
		comp_box = VBoxContainer.new()
		comp_box.add_theme_constant_override("separation", 2)
		comp_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(comp_box)
		var right := VBoxContainer.new()
		right.custom_minimum_size = Vector2(290, 0)
		row.add_child(right)
		right.add_child(UIKit.label("Result", 13, UIKit.ASH))
		var pv := PanelContainer.new()
		pv.add_theme_stylebox_override("panel", UIKit.box(UIKit.BG_SOFT, UIKit.LINE_SOFT, 1, 2, 10))
		pv.custom_minimum_size = Vector2(290, 230)
		right.add_child(pv)
		preview = UIKit.rich()
		pv.add_child(preview)
		reason = UIKit.label("", 13, UIKit.BAD)
		right.add_child(reason)
		craft_btn = UIKit.button("Craft", func(): _craft())
		craft_btn.custom_minimum_size = Vector2(0, 34)
		right.add_child(craft_btn)
		for r in Defs.RECIPE_ORDER:
			if Defs.RECIPES[r].skill == skill:
				recipe = r
				break
		_pick_material()

	func _pool() -> Array:
		return ui.world.crafting_pool(family)

	func _pick_material() -> void:
		# Default to the best material the player holds and can use.
		res = ""
		var counts := {}
		for c in _pool():
			counts[c.res] = counts.get(c.res, 0) + 1
		var lv: int = ui.world.level(skill)
		for r_id in Defs.RESOURCES:
			var r: Dictionary = Defs.RESOURCES[r_id]
			if r.family != family or counts.get(r_id, 0) < int(Defs.RECIPES[recipe].count):
				continue
			if Defs.recipe_req(recipe, r_id) <= lv:
				res = r_id
		if res == "":
			for r_id in counts:
				res = r_id
				break
		picked = ui.world.auto_pick(recipe, res) if res != "" else []
		refresh()

	func refresh() -> void:
		var w: World = ui.world
		var lv := w.level(skill)
		title_label.text = "%s · level %d" % [Defs.SKILL_NAMES[skill], lv]
		for c in recipe_box.get_children():
			c.queue_free()
		recipe_box.add_child(UIKit.label("Recipe", 13, UIKit.ASH))
		for r_id in Defs.RECIPE_ORDER:
			var rec: Dictionary = Defs.RECIPES[r_id]
			if rec.skill != skill:
				continue
			var b := UIKit.button("%s  · %d" % [rec.name, rec.count], func():
				recipe = r_id
				_pick_material())
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			if r_id == recipe:
				b.add_theme_color_override("font_color", UIKit.EMBER)
			recipe_box.add_child(b)
			var slot_line = Defs.SLOT_NAMES[rec.slot]
			if rec.has("style"):
				slot_line = "%s · %d ticks · range %d" % [Defs.SKILL_NAMES[rec.style], rec.speed, rec.range]
			var l := UIKit.label(slot_line, 12, UIKit.DIM)
			recipe_box.add_child(l)
		for c in mat_box.get_children():
			c.queue_free()
		var counts := {}
		for c in _pool():
			counts[c.res] = counts.get(c.res, 0) + 1
		for r_id in Defs.RESOURCES:
			var r: Dictionary = Defs.RESOURCES[r_id]
			if r.family != family:
				continue
			var req := Defs.recipe_req(recipe, r_id)
			if req > 60 and counts.get(r_id, 0) == 0:
				continue
			var b := UIKit.button("%s %d · %d" % [r.name, req, counts.get(r_id, 0)], func():
				res = r_id
				picked = w.auto_pick(recipe, res)
				refresh())
			b.add_theme_font_size_override("font_size", 13)
			if r_id == res:
				b.add_theme_color_override("font_color", UIKit.EMBER)
			elif req > lv:
				b.add_theme_color_override("font_color", UIKit.DIM)
			b.tooltip_text = "Requires %s %d. You hold %d." % [Defs.SKILL_NAMES[skill], req, counts.get(r_id, 0)]
			mat_box.add_child(b)
		for c in comp_box.get_children():
			c.queue_free()
		var comps := _pool().filter(func(c): return c.res == res)
		comps.sort_custom(func(a, b): return Items.component_score(a) > Items.component_score(b))
		if comps.is_empty():
			comp_box.add_child(UIKit.label("None held.", 13, UIKit.DIM))
		for c in comps:
			comp_box.add_child(_comp_row(c))
		_update_preview()

	func _comp_row(c: Dictionary) -> Control:
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(290, 26)
		var idx := picked.find(c.uid)
		var mods := []
		for m in c.mods:
			mods.append("%s %s" % [Defs.MODS[m.id].name, Defs.TIER_NUMERALS[m.tier]])
		var letter = ItemText.LETTERS[idx] + "  " if idx >= 0 else "    "
		b.text = "%s%s  %s" % [letter, Defs.RARITIES[c.rarity], ", ".join(mods) if not mods.is_empty() else "-"]
		b.add_theme_color_override("font_color", UIKit.rarity_color(c.rarity))
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_font_override("font", UIKit.body_font())
		if idx >= 0:
			var sb := UIKit.box(Color("3a2618"), UIKit.EMBER, 1, 2, 6)
			b.add_theme_stylebox_override("normal", sb)
		b.pressed.connect(func():
			var i := picked.find(c.uid)
			if i >= 0:
				picked.remove_at(i)
			elif picked.size() < int(Defs.RECIPES[recipe].count):
				picked.append(c.uid)
			refresh())
		b.mouse_entered.connect(func(): ui.show_tooltip(c))
		b.mouse_exited.connect(func(): ui.hide_tooltip())
		return b

	func _update_preview() -> void:
		var w: World = ui.world
		var rec: Dictionary = Defs.RECIPES[recipe]
		var why := w.can_craft(recipe, picked)
		if res == "":
			preview.text = ItemText.c(UIKit.DIM, "No %s held." % ("logs" if family == "log" else "ore"))
		elif picked.size() == int(rec.count):
			var ings := picked.map(func(u): return w.find_item(u))
			var it := Items.craft(0, recipe, ings, w.level(skill), w.player.perks)
			preview.text = ItemText.describe(it, w)
		else:
			preview.text = ItemText.c(UIKit.ASH, "Choose %d %s. Each carries its modifiers onto the result." % [rec.count, Defs.component_name(res) + "s"])
		reason.text = why
		craft_btn.disabled = why != ""

	func _craft() -> void:
		var it = ui.world.craft(recipe, picked)
		if not it.is_empty():
			ui.flush_log()
			picked = ui.world.auto_pick(recipe, res)
			ui.refresh_all()


# ================================================================ recap & victory

class NoticeWindow extends Modal:
	func build(title: String, bb: String, button_text: String) -> void:
		title_label.text = title
		var r := UIKit.rich()
		r.custom_minimum_size = Vector2(460, 0)
		r.text = bb
		body.add_child(r)
		var b := UIKit.button(button_text, func(): close())
		b.custom_minimum_size = Vector2(0, 32)
		body.add_child(b)


class ChoiceWindow extends Modal:
	func build(title: String, options: Array, cb: Callable) -> void:
		title_label.text = title
		for o in options:
			var b := UIKit.button(o.text, func():
				cb.call(o.value)
				close())
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			body.add_child(b)


# ================================================================ tooltip & menu

class Tooltip extends PanelContainer:
	var text: RichTextLabel

	func _init() -> void:
		add_theme_stylebox_override("panel", UIKit.box(Color("120f0c", 0.97), UIKit.LINE, 1, 2, 10))
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		text = UIKit.rich()
		text.custom_minimum_size = Vector2(300, 0)
		add_child(text)
		visible = false

	func show_bb(bb: String) -> void:
		text.text = bb
		visible = true
		reset_size()

	func _process(_d: float) -> void:
		if not visible:
			return
		var m := get_viewport().get_mouse_position()
		var vs := get_viewport_rect().size
		var p := m + Vector2(18, 12)
		if p.x + size.x > vs.x - 4:
			p.x = m.x - size.x - 12
		if p.y + size.y > vs.y - 4:
			p.y = vs.y - size.y - 4
		position = p.floor()


class ContextMenu extends PanelContainer:
	var box: VBoxContainer
	var ui

	func _init() -> void:
		add_theme_stylebox_override("panel", UIKit.box(Color("120f0c", 0.98), UIKit.LINE, 1, 2, 4))
		mouse_filter = Control.MOUSE_FILTER_STOP
		box = VBoxContainer.new()
		box.add_theme_constant_override("separation", 0)
		add_child(box)
		visible = false

	## options: [{label: bbcode, cb: Callable}]
	func open(at: Vector2, options: Array) -> void:
		for c in box.get_children():
			c.queue_free()
		var head := UIKit.label("Choose option", 13, UIKit.ASH)
		box.add_child(head)
		for o in options:
			var b := Button.new()
			b.flat = true
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.add_theme_stylebox_override("normal", UIKit.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 4))
			b.add_theme_stylebox_override("hover", UIKit.box(UIKit.SLOT_HOVER, Color(0, 0, 0, 0), 0, 0, 4))
			b.add_theme_stylebox_override("pressed", UIKit.box(UIKit.SLOT_HOVER, Color(0, 0, 0, 0), 0, 0, 4))
			var r := UIKit.rich()
			r.autowrap_mode = TextServer.AUTOWRAP_OFF
			r.text = o.label
			r.position = Vector2(4, 3)
			b.add_child(r)
			b.custom_minimum_size = Vector2(maxf(160, UIKit.body_font().get_string_size(_strip(o.label), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 16), 24)
			b.pressed.connect(func():
				visible = false
				o.cb.call())
			box.add_child(b)
		visible = true
		reset_size()
		var vs := get_viewport_rect().size
		await get_tree().process_frame
		reset_size()
		position = Vector2(clampf(at.x - size.x / 2, 4, vs.x - size.x - 4), clampf(at.y - 8, 4, vs.y - size.y - 4))

	static func _strip(bb: String) -> String:
		var re := RegEx.new()
		re.compile("\\[[^\\]]*\\]")
		return re.sub(bb, "", true)
