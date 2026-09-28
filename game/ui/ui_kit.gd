class_name UIKit
extends RefCounted
## Palette, fonts and small widget helpers for the interface.

const BG := Color("17130f")
const BG_SOFT := Color("221c16")
const SLOT := Color("2a231b")
const SLOT_HOVER := Color("3a3024")
const LINE := Color("5c4a34")
const LINE_SOFT := Color("3a3024")
const INK := Color("e8dfcc")
const ASH := Color("9a8f7c")
const DIM := Color("6a6152")
const EMBER := Color("e8763a")
const GOLD := Color("e0b85a")
const BAD := Color("d0503a")
const GOOD := Color("8fbf5f")
const HOVER_TARGET := Color("f0c850")

static var _display: Font
static var _body: Font
static var _bold: Font
static var _theme: Theme

static func _load_font(path: String) -> Font:
	if ResourceLoader.exists(path):
		var f = load(path)
		if f is Font:
			return f
	var ff := FontFile.new()
	if ff.load_dynamic_font(ProjectSettings.globalize_path(path)) == OK:
		return ff
	return ThemeDB.fallback_font

static func display_font() -> Font:
	if _display == null:
		_display = _load_font("res://assets/fonts/Cinzel-Bold.woff2")
	return _display

static func body_font() -> Font:
	if _body == null:
		_body = _load_font("res://assets/fonts/AlegreyaSans-Medium.woff2")
	return _body

static func bold_font() -> Font:
	if _bold == null:
		_bold = _load_font("res://assets/fonts/AlegreyaSans-Bold.woff2")
	return _bold

static func box(bg: Color, border := LINE, width := 1, radius := 2, margin := 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin
	s.content_margin_bottom = margin
	return s

static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = 15
	t.set_color("font_color", "Label", INK)
	t.set_stylebox("panel", "PanelContainer", box(Color(BG, 0.96)))
	t.set_stylebox("panel", "Panel", box(Color(BG, 0.96)))
	var normal := box(BG_SOFT, LINE, 1, 2, 8)
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4
	var hover := normal.duplicate()
	hover.bg_color = SLOT_HOVER
	hover.border_color = GOLD.darkened(0.3)
	var pressed := normal.duplicate()
	pressed.bg_color = Color("3a2618")
	pressed.border_color = EMBER
	var disabled := normal.duplicate()
	disabled.bg_color = Color(BG_SOFT, 0.5)
	disabled.border_color = LINE_SOFT
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", HOVER_TARGET)
	t.set_color("font_pressed_color", "Button", EMBER)
	t.set_color("font_disabled_color", "Button", DIM)
	t.set_font("font", "Button", bold_font())
	t.set_font_size("font_size", "Button", 15)
	t.set_color("default_color", "RichTextLabel", INK)
	t.set_font("normal_font", "RichTextLabel", body_font())
	t.set_font("bold_font", "RichTextLabel", bold_font())
	t.set_font_size("normal_font_size", "RichTextLabel", 15)
	t.set_font_size("bold_font_size", "RichTextLabel", 15)
	var sb := StyleBoxFlat.new()
	sb.bg_color = LINE_SOFT
	sb.set_corner_radius_all(1)
	var grab := StyleBoxFlat.new()
	grab.bg_color = LINE
	grab.set_corner_radius_all(1)
	t.set_stylebox("scroll", "VScrollBar", sb)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab)
	t.set_constant("separation", "VBoxContainer", 4)
	t.set_constant("separation", "HBoxContainer", 6)
	_theme = t
	return t

static func label(text: String, size := 15, color := INK, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if font:
		l.add_theme_font_override("font", font)
	return l

static func heading(text: String, size := 18) -> Label:
	return label(text, size, GOLD, display_font())

static func rich() -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

static func button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b

static func hex(c: Color) -> String:
	return c.to_html(false)

static func rarity_color(r: int) -> Color:
	return Defs.RARITY_COLORS[clampi(r, 0, 6)]
