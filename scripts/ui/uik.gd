class_name UIK
## Построение интерфейса кодом. Фэнтези-тема: кожаные панели в золотой рамке, тонируемые кнопки,
## глянцевые полосы, шрифт Philosopher для заголовков и Rubik для текста, иконки game-icons.net.

const PANEL := Color(0.07, 0.08, 0.11, 0.93)
const BUTTON := Color(0.42, 0.34, 0.26)
const ACCENT := Color(0.95, 0.74, 0.36)
const TEXT := Color(0.96, 0.92, 0.84)
const MUTED := Color(0.72, 0.66, 0.58)
const GREEN := Color(0.33, 0.55, 0.28)
const RED := Color(0.62, 0.2, 0.17)
const GOLD := Color(0.9, 0.64, 0.24)
const BLUE := Color(0.27, 0.42, 0.7)
const PURPLE := Color(0.48, 0.32, 0.6)
const SELECT := Color(0.85, 0.62, 0.25)

static var _tex := {}
static var _title_font: Font
static var _body_font: Font

static func tex(path: String) -> Texture2D:
	if not _tex.has(path): _tex[path] = load(path)
	return _tex[path]

static func icon(name: String) -> Texture2D:
	var p := "res://assets/icons/%s.svg" % name
	if not ResourceLoader.exists(p): return null
	return tex(p)

static func title_font() -> Font:
	if _title_font == null: _title_font = load("res://fonts/Philosopher-Bold.ttf")
	return _title_font

static func body_font() -> Font:
	if _body_font == null: _body_font = load("res://fonts/Rubik.ttf")
	return _body_font

static func box(c: Color, radius := 10, border := 0, border_color := Color.TRANSPARENT) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(radius)
	s.content_margin_left = 14; s.content_margin_right = 14; s.content_margin_top = 8; s.content_margin_bottom = 8
	if border > 0:
		s.set_border_width_all(border); s.border_color = border_color
	return s

## Орнаментальная панель (кожа + золотая рамка)
static func frame(kind := "panel", tint := Color.WHITE, margin := 22) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = tex("res://assets/ui/%s.png" % kind)
	var m := 24 if kind.begins_with("panel") else (14 if kind == "slot" else 20)
	s.texture_margin_left = m; s.texture_margin_right = m; s.texture_margin_top = m; s.texture_margin_bottom = m
	s.content_margin_left = margin; s.content_margin_right = margin; s.content_margin_top = margin * 0.7; s.content_margin_bottom = margin * 0.7
	s.modulate_color = tint
	return s

static func panel(parent: Node, c := PANEL, radius := 12) -> Panel:
	var p := Panel.new()
	if c == PANEL: p.add_theme_stylebox_override("panel", frame("panel"))
	elif c.a < 0.62 or radius == 0: p.add_theme_stylebox_override("panel", box(c, radius))
	else: p.add_theme_stylebox_override("panel", frame("panel_dark", Color(1, 1, 1, c.a)))
	parent.add_child(p)
	return p

## Якоря в долях родителя (y от низа).
static func place(c: Control, x0: float, y0: float, x1: float, y1: float) -> Control:
	c.anchor_left = x0; c.anchor_top = 1.0 - y1; c.anchor_right = x1; c.anchor_bottom = 1.0 - y0
	c.offset_left = 0; c.offset_top = 0; c.offset_right = 0; c.offset_bottom = 0
	return c

## Позиция и размер (размер дважды: у переносимых надписей минимальная высота пересчитывается после смены ширины)
static func rect(c: Control, pos: Vector2, sz: Vector2) -> Control:
	c.offset_left = pos.x; c.offset_top = pos.y; c.offset_right = pos.x + sz.x; c.offset_bottom = pos.y + sz.y
	return c

static func full(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c

static func label(parent: Node, text: String, size := 28, color := TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02, 0.9))
	l.add_theme_constant_override("outline_size", 5 if size >= 40 else 4)
	if size >= 40 or color == ACCENT:
		l.add_theme_font_override("font", title_font())
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
		l.add_theme_constant_override("shadow_offset_y", 3)
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
	r.add_theme_font_override("bold_font", title_font())
	parent.add_child(r)
	return r

static func button(parent: Node, text: String, cb: Callable, c := BUTTON, size := 30, icon_name := "") -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_font_override("font", title_font())
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.35))
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	b.add_theme_constant_override("outline_size", 4)
	set_button_color(b, c)
	b.focus_mode = Control.FOCUS_NONE
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size.y = maxf(b.custom_minimum_size.y, 64)
	if icon_name != "":
		b.icon = icon(icon_name)
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", int(size * 1.4))
		b.add_theme_constant_override("h_separation", 10)
	if cb.is_valid(): b.pressed.connect(cb)
	b.button_down.connect(func(): b.pivot_offset = b.size / 2; b.scale = Vector2.ONE * 0.97)
	b.button_up.connect(func(): b.scale = Vector2.ONE)
	parent.add_child(b)
	return b

static func _btn_style(c: Color) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = tex("res://assets/ui/button.png")
	s.texture_margin_left = 14; s.texture_margin_right = 14; s.texture_margin_top = 14; s.texture_margin_bottom = 14
	s.content_margin_left = 16; s.content_margin_right = 16; s.content_margin_top = 8; s.content_margin_bottom = 8
	var k := 1.35
	s.modulate_color = Color(minf(c.r * k, 1), minf(c.g * k, 1), minf(c.b * k, 1), c.a)
	return s

static func set_button_color(b: Button, c: Color) -> void:
	b.add_theme_stylebox_override("normal", _btn_style(c))
	b.add_theme_stylebox_override("hover", _btn_style(c.lightened(0.12)))
	b.add_theme_stylebox_override("pressed", _btn_style(c.darkened(0.25)))
	b.add_theme_stylebox_override("disabled", _btn_style(Color(c.v, c.v, c.v).darkened(0.45)))
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
	sc.offset_left = 16; sc.offset_top = 16; sc.offset_right = -16; sc.offset_bottom = -16
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
	var bg := StyleBoxTexture.new(); bg.texture = tex("res://assets/ui/bar_bg.png")
	bg.texture_margin_left = 10; bg.texture_margin_right = 10; bg.texture_margin_top = 10; bg.texture_margin_bottom = 10
	p.add_theme_stylebox_override("background", bg)
	var f := StyleBoxTexture.new(); f.texture = tex("res://assets/ui/bar_fill.png")
	f.texture_margin_left = 4; f.texture_margin_right = 4; f.texture_margin_top = 4; f.texture_margin_bottom = 4
	f.expand_margin_left = -3; f.expand_margin_right = -3; f.expand_margin_top = -3; f.expand_margin_bottom = -3
	f.modulate_color = fill.lightened(0.1)
	p.add_theme_stylebox_override("fill", f)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	var l := label(p, "", 22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	l.name = "Text"
	full(l)
	return p

static func icon_rect(parent: Node, name: String, sz: float, tint := Color.WHITE) -> TextureRect:
	var t := TextureRect.new()
	t.texture = icon(name)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(sz, sz)
	t.size = Vector2(sz, sz)
	t.modulate = tint
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(t)
	return t

## Всплывающая подсказка (предмет/умение/талант)
static func tooltip(parent: Node, title: String, body: String, ic := "", col := ACCENT, width := 520.0) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", frame("tooltip", Color.WHITE, 22))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.name = "Tooltip"
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(h)
	if ic != "": icon_rect(h, ic, 52, col)
	var t := label(h, title, 30, col)
	t.add_theme_font_override("font", title_font())
	t.custom_minimum_size.x = width - 100
	var r := rich(v, body, 23)
	r.fit_content = true
	r.custom_minimum_size = Vector2(width - 44, 0)
	parent.add_child(p)
	p.reset_size()
	return p

## Ставит подсказку над прямоугольником (или сбоку), не вылезая за экран
static func place_tooltip(t: Control, near: Rect2, vs: Vector2) -> void:
	t.modulate.a = 0.0
	var f := func():
		if not is_instance_valid(t): return
		t.reset_size()
		var sz: Vector2 = t.size
		var p := Vector2(near.position.x + near.size.x / 2 - sz.x / 2, near.position.y - sz.y - 14)
		if p.y < 10: p = Vector2(near.position.x - sz.x - 14, near.position.y)
		t.position = Vector2(clampf(p.x, 10, vs.x - sz.x - 10), clampf(p.y, 10, vs.y - sz.y - 10))
		t.pivot_offset = sz / 2
		t.create_tween().tween_property(t, "modulate:a", 1.0, 0.15)
	f.call_deferred()

## Плавное появление окна
static func pop_in(c: Control, dur := 0.2) -> void:
	c.modulate.a = 0.0
	c.pivot_offset = c.get_viewport_rect().size / 2 if c.size == Vector2.ZERO else c.size / 2
	c.scale = Vector2.ONE * 0.94
	var tw := c.create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, dur * 0.8)
	tw.tween_property(c, "scale", Vector2.ONE, dur)

## Плавное закрытие и удаление
static func pop_out(c: Control, dur := 0.14) -> void:
	if not is_instance_valid(c): return
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.pivot_offset = c.size / 2
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "modulate:a", 0.0, dur)
	tw.tween_property(c, "scale", Vector2.ONE * 0.95, dur)
	tw.chain().tween_callback(c.queue_free)

## Иконки предметов/умений/характеристик
const SKILL_ICONS := {"w_attack": "broadsword", "w_spin": "spinning-sword", "w_dash": "sprint",
	"a_attack": "high-shot", "a_volley": "arrow-cluster", "a_rain": "arrow-flights",
	"m_bolt": "magic-swirl", "m_fireball": "fireball", "m_nova": "frozen-orb",
	"asc_rage": "burning-passion", "asc_shield": "shield-reflect", "asc_meteor": "meteor-impact",
	"asc_summon": "raise-skeleton", "asc_strike": "backstab", "asc_roar": "wolf-howl"}
const WEAPON_ICONS := {"warrior": "broadsword", "archer": "pocket-bow", "mage": "wizard-staff"}
const SLOT_ICONS := ["broadsword", "breastplate", "visored-helm", "ring"]
const STAT_ICONS := {"max_hp": "heart-bottle", "max_mp": "drop", "damage": "sword-wound", "attack_speed": "lightning-frequency",
	"crit": "crossed-swords", "armor": "checked-shield", "regen": "heart-beats", "leech": "skull-mask", "move_speed": "sprint", "cdr": "hourglass"}

static func item_icon(it: Dictionary, class_id := "warrior") -> String:
	var s := int(it.get("slot", 0))
	return WEAPON_ICONS.get(class_id, "broadsword") if s == 0 else SLOT_ICONS[s]
