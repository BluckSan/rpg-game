class_name UIK
## Построение интерфейса кодом.

const PANEL := Color(0.07, 0.08, 0.11, 0.93)
const BUTTON := Color(0.22, 0.25, 0.33)
const ACCENT := Color(0.85, 0.6, 0.2)
const TEXT := Color(0.95, 0.93, 0.88)
const GREEN := Color(0.25, 0.45, 0.25)
const RED := Color(0.45, 0.15, 0.15)
const GOLD := Color(0.75, 0.5, 0.15)

static func box(c: Color, radius := 10, border := 0, border_color := Color.TRANSPARENT) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(radius)
	s.content_margin_left = 14; s.content_margin_right = 14; s.content_margin_top = 8; s.content_margin_bottom = 8
	if border > 0:
		s.set_border_width_all(border); s.border_color = border_color
	return s

static func panel(parent: Node, c := PANEL, radius := 12) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", box(c, radius))
	parent.add_child(p)
	return p

## Якоря в долях родителя.
static func place(c: Control, x0: float, y0: float, x1: float, y1: float) -> Control:
	c.anchor_left = x0; c.anchor_top = 1.0 - y1; c.anchor_right = x1; c.anchor_bottom = 1.0 - y0
	c.offset_left = 0; c.offset_top = 0; c.offset_right = 0; c.offset_bottom = 0
	return c

static func full(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c

static func label(parent: Node, text: String, size := 28, color := TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

static func rich(parent: Node, bbcode: String, size := 26) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.text = bbcode
	r.fit_content = false
	r.scroll_active = false
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_color_override("default_color", TEXT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bold := FontVariation.new()
	bold.base_font = load("res://fonts/Rubik.ttf")
	bold.variation_opentype = {"wght": 700}
	r.add_theme_font_override("bold_font", bold)
	parent.add_child(r)
	return r

static func button(parent: Node, text: String, cb: Callable, c := BUTTON, size := 30) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.35))
	set_button_color(b, c)
	b.focus_mode = Control.FOCUS_NONE
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if cb.is_valid(): b.pressed.connect(cb)
	parent.add_child(b)
	return b

static func set_button_color(b: Button, c: Color) -> void:
	b.add_theme_stylebox_override("normal", box(c))
	b.add_theme_stylebox_override("hover", box(c.lightened(0.12)))
	b.add_theme_stylebox_override("pressed", box(c.darkened(0.25)))
	b.add_theme_stylebox_override("disabled", box(c.darkened(0.4)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

static func min_h(c: Control, h: float) -> Control:
	c.custom_minimum_size.y = h
	return c

## Вертикальный список с прокруткой. Возвращает VBoxContainer.
static func scroll_list(parent: Node, spacing := 10) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(sc)
	full(sc)
	sc.offset_left = 8; sc.offset_top = 8; sc.offset_right = -8; sc.offset_bottom = -8
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", spacing)
	sc.add_child(v)
	return v

static func hbox(parent: Node, h: float, spacing := 10) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", spacing)
	r.custom_minimum_size.y = h
	parent.add_child(r)
	return r

static func expand(c: Control, ratio := 1.0) -> Control:
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_stretch_ratio = ratio
	return c

static func clear(n: Node) -> void:
	for ch in n.get_children():
		ch.queue_free()

static func bar(parent: Node, fill: Color) -> ProgressBar:
	var p := ProgressBar.new()
	p.show_percentage = false
	p.add_theme_stylebox_override("background", box(Color(0, 0, 0, 0.65), 6))
	var f := box(fill, 6)
	f.content_margin_left = 0; f.content_margin_right = 0
	p.add_theme_stylebox_override("fill", f)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	var l := label(p, "", 22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	l.name = "Text"
	full(l)
	return p
