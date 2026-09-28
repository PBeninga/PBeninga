class_name ItemSlot
extends Control
## One inventory cell. Draws the baked icon, a rarity rule and modifier pips.

signal clicked(slot: ItemSlot, button: int)
signal dropped_on(from_index: int, to_index: int)

var item = null
var ui          # GameUI
var index := -1
var empty_glyph := ""
var selected := false
var dim := false
var draggable := false
var _hover := false

func _init() -> void:
	custom_minimum_size = Vector2(54, 44)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func():
		_hover = true
		queue_redraw()
		if ui and item != null:
			ui.show_tooltip(item))
	mouse_exited.connect(func():
		_hover = false
		queue_redraw()
		if ui:
			ui.hide_tooltip())

func set_item(it) -> void:
	item = it
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			clicked.emit(self, event.button_index)
			accept_event()

func _get_drag_data(_pos: Vector2):
	if not draggable or item == null:
		return null
	var p := ItemSlot.new()
	p.ui = null
	p.item = item
	p.icon_source = icon_source
	p.modulate.a = 0.8
	set_drag_preview(p)
	return {"slot_index": index}

func _can_drop_data(_pos: Vector2, data) -> bool:
	return draggable and data is Dictionary and data.has("slot_index")

func _drop_data(_pos: Vector2, data) -> void:
	dropped_on.emit(int(data.slot_index), index)

var icon_source: Icons

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var bg := UIKit.SLOT_HOVER if _hover else UIKit.SLOT
	if selected:
		bg = Color("3a2618")
	draw_rect(r, bg)
	draw_rect(r, UIKit.EMBER if selected else UIKit.LINE_SOFT, false, 1.0)
	if item == null:
		if empty_glyph != "":
			Icons.glyph(self, empty_glyph, r.grow(-10), Color(UIKit.DIM, 0.5))
		return
	var tex: Texture2D = icon_source.icon(item) if icon_source else null
	var a := 0.4 if dim else 1.0
	if tex:
		var s := minf(r.size.x, r.size.y) - 2
		draw_texture_rect(tex, Rect2(r.get_center() - Vector2(s, s) / 2, Vector2(s, s)), false, Color(1, 1, 1, a))
	else:
		var f := UIKit.bold_font()
		var n := Items.item_name(item)
		draw_string(f, Vector2(4, r.size.y / 2 + 5), n.substr(0, 6), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(UIKit.INK, a))
	if item.kind == "reagent":
		draw_string(UIKit.bold_font(), Vector2(3, 13), str(int(item.qty)), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("f0d040"))
		return
	var rc := UIKit.rarity_color(int(item.get("rarity", 1)))
	draw_rect(Rect2(1, r.size.y - 3, r.size.x - 2, 2), Color(rc, a))
	# One pip per modifier instance; brighter pips are higher tiers.
	var mods: Array = item.mods
	for i in mods.size():
		var t := int(mods[i].tier)
		var col := UIKit.GOLD.lerp(UIKit.EMBER, clampf((t - 1) / 3.0, 0, 1))
		if int(mods[i].get("tempered", 0)) > 0:
			col = UIKit.EMBER.lightened(0.2)
		var x := r.size.x - 6 - (i % 6) * 5
		var y := 5 + (i / 6) * 5
		draw_rect(Rect2(x, y, 3, 3), Color(col, a))
