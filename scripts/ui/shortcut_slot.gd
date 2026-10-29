extends Control
class_name ShortcutSlot
## v0.9.3: квадратная ячейка панели ярлыков (ПК, как в L2): иконка, перезарядка, клавиша, количество.
## Принимает перетаскивание умений (окно «Умения»), вещей (инвентарь) и ярлыков с других ячеек.

var bars          # ShortcutBars
var bar := 0
var idx := 0
var icon: Texture2D
var tint := Color.WHITE
var key_hint := ""
var badge := ""
var cd_frac := 0.0
var cd_text := ""
var locked := false
var empty := true
var flash := 0.0
var _font: Font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = load("res://fonts/Rubik.ttf")
	set_drag_forwarding(_get_drag, _can_drop, _drop)
	gui_input.connect(_input_ev)
	mouse_entered.connect(func(): if bars: bars.hover(self))
	mouse_exited.connect(func(): if bars: bars.hover(null))

func _input_ev(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
		bars.activate(bar, idx); accept_event()
	elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed and ev.shift_pressed:
		bars.set_slot(bar, idx, {}); accept_event()   # Shift+ПКМ — убрать ярлык

func _get_drag(_at: Vector2):
	if empty or bars.locked: return null
	var pv := TextureRect.new(); pv.texture = icon; pv.size = Vector2(64, 64); pv.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pv.modulate = tint
	set_drag_preview(pv)
	return {"sc": [bar, idx]}

func _can_drop(_at: Vector2, d) -> bool:
	return d is Dictionary and (d.has("skill") or d.has("item") or d.has("sc") or d.has("potion"))

func _drop(_at: Vector2, d) -> void:
	bars.drop(bar, idx, d)

func _process(delta: float) -> void:
	if flash > 0.0:
		flash = maxf(0.0, flash - delta * 3.0); queue_redraw()

func set_state(frac: float, rem: float, lock: bool) -> void:
	var t := str(ceili(rem)) if rem > 0.05 else ""
	if cd_frac > 0 and frac <= 0: flash = 1.0
	if frac != cd_frac or t != cd_text or lock != locked:
		cd_frac = frac; cd_text = t; locked = lock; queue_redraw()

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.07, 0.72); sb.set_corner_radius_all(9)
	sb.set_border_width_all(2); sb.border_color = Color(0.55, 0.62, 0.8, 0.35) if empty else Color(tint.r, tint.g, tint.b, 0.75)
	sb.anti_aliasing = true
	draw_style_box(sb, r)
	if icon and not empty:
		draw_texture_rect(icon, r.grow(-size.x * 0.14), false, Color(1, 1, 1, 0.35) if locked else Color(1, 0.98, 0.92))
	if cd_frac > 0.0:
		var c := size / 2
		var pts := PackedVector2Array([c])
		for i in 33:
			var a := -PI / 2 + TAU * cd_frac * float(i) / 32
			var v := Vector2(cos(a), sin(a))
			var k := 1.0 / maxf(absf(v.x), absf(v.y))   # заполняем квадрат
			pts.append(c + v * k * size.x * 0.46)
		draw_colored_polygon(pts, Color(0, 0, 0, 0.62))
		_txt(cd_text, c + Vector2(0, size.y * 0.12), int(size.y * 0.36), Color(1, 0.9, 0.6))
	if flash > 0.0: draw_rect(r.grow(-3), Color(1, 0.95, 0.7, flash * 0.4))
	if key_hint != "":
		_txt(key_hint, Vector2(size.x * 0.3, size.y * 0.24), maxi(12, int(size.y * 0.22)), Color(1, 1, 1, 0.9))
	if badge != "":
		_txt(badge, Vector2(size.x * 0.76, size.y * 0.86), maxi(12, int(size.y * 0.24)), Color(1, 0.88, 0.5))

func _txt(t: String, center: Vector2, fs: int, col: Color) -> void:
	var w := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := Vector2(center.x - w / 2, center.y + fs * 0.35)
	draw_string_outline(_font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.9))
	draw_string(_font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
