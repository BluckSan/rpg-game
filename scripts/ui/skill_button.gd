extends Control
class_name SkillButton
## Круглая кнопка умения: иконка, золотое кольцо, радиальная перезарядка, подпись, точки комбо.
## Нажатия обрабатывает HUD (мультитач).

var color := Color.WHITE
var text := ""
var icon: Texture2D
var cd_frac := 0.0
var cd_text := ""
var locked_text := ""
var held := false
var pips := 0          # заполненные точки комбо
var max_pips := 0
var badge := ""        # число в углу (например, зелья)
var flash := 0.0       # вспышка «готово»
var key_hint := ""     # клавиша на ПК
var font: Font
var title: Font
static var _ring: Texture2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = load("res://fonts/Rubik.ttf")
	title = load("res://fonts/Philosopher-Bold.ttf")
	if _ring == null: _ring = load("res://assets/ui/skill_ring.png")

func hit(p: Vector2) -> bool:
	var c := global_position + size * scale / 2
	return p.distance_to(c) <= size.x * 0.56  # зона нажатия чуть больше кнопки

func _process(delta: float) -> void:
	if flash > 0:
		flash = maxf(0, flash - delta * 2.5)
		queue_redraw()

func _draw() -> void:
	var r := size.x / 2
	var c := size / 2
	draw_circle(c + Vector2(0, 4), r, Color(0, 0, 0, 0.35))
	var base := color.darkened(0.3) if held else color
	draw_circle(c, r * 0.9, base.darkened(0.45))
	draw_circle(c - Vector2(0, r * 0.08), r * 0.8, base)
	draw_circle(c - Vector2(0, r * 0.3), r * 0.45, Color(1, 1, 1, 0.08))
	if icon:
		var isz := r * 1.05
		draw_texture_rect(icon, Rect2(c - Vector2(isz, isz) / 2 - Vector2(0, r * 0.08 if text != "" else 0), Vector2(isz, isz)), false,
			Color(1, 1, 1, 0.35) if locked_text != "" else Color(1, 0.97, 0.9))
	if locked_text != "":
		draw_circle(c, r * 0.88, Color(0, 0, 0, 0.55))
	elif cd_frac > 0:
		var pts := PackedVector2Array([c])
		var steps := 40
		for i in steps + 1:
			var a := -PI / 2 + TAU * cd_frac * float(i) / steps
			pts.append(c + Vector2(cos(a), sin(a)) * (r * 0.88))
		draw_colored_polygon(pts, Color(0.02, 0.02, 0.05, 0.68))
		draw_arc(c, r * 0.88, -PI / 2, -PI / 2 + TAU * cd_frac, 48, Color(1, 0.85, 0.4, 0.9), 4.0)
	if flash > 0:
		draw_circle(c, r * 0.9, Color(1, 0.95, 0.7, flash * 0.45))
	draw_texture_rect(_ring, Rect2(Vector2.ZERO, size), false)
	if text != "" and (icon == null):
		_text_centered(text, c + Vector2(0, -2 if cd_text == "" else -r * 0.35), int(r * 0.34), title)
	elif text != "":
		# подпись на тёмной плашке, шрифт ужимается под ширину кнопки
		var fs := maxi(16, int(r * 0.24))
		while fs > 13 and title.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > r * 1.9: fs -= 1
		var tw := title.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pc := c + Vector2(0, r * 0.74)
		draw_rect(Rect2(pc - Vector2(tw / 2 + 8, fs * 0.62), Vector2(tw + 16, fs * 1.24)), Color(0.05, 0.03, 0.02, 0.72))
		_text_centered(text, pc, fs, title)
	if locked_text != "":
		_text_centered(locked_text, c + Vector2(0, r * 0.1), int(r * 0.26), font)
	elif cd_text != "":
		_text_centered(cd_text, c, int(r * 0.5), title)
	if key_hint != "":
		var kf := maxi(18, int(r * 0.22))
		var kw := maxf(kf * 1.3, font.get_string_size(key_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, kf).x + 14)
		var kp := Vector2(c.x + r * 0.78 - kw, c.y - r * 0.98)
		draw_rect(Rect2(kp, Vector2(kw, kf * 1.35)), Color(0.08, 0.06, 0.04, 0.9))
		draw_rect(Rect2(kp, Vector2(kw, kf * 1.35)), Color(0.95, 0.75, 0.4, 0.9), false, 2.0)
		_text_centered(key_hint, kp + Vector2(kw, kf * 1.35) / 2, kf, font)
	if max_pips > 0:
		for i in max_pips:
			var a := PI * 1.25 + (i - (max_pips - 1) / 2.0) * 0.32
			var p := c + Vector2(cos(a), sin(a)) * (r * 1.02)
			draw_circle(p, r * 0.08 + 2, Color(0, 0, 0, 0.7))
			draw_circle(p, r * 0.08, Color(1, 0.8, 0.3) if i < pips else Color(0.3, 0.25, 0.2))
	if badge != "":
		var bp := c + Vector2(r * 0.68, r * 0.68)
		draw_circle(bp, r * 0.28, Color(0.1, 0.07, 0.05))
		draw_arc(bp, r * 0.28, 0, TAU, 24, Color(0.9, 0.7, 0.3), 2.0)
		_text_centered(badge, bp, int(r * 0.28), title)

func _text_centered(t: String, center: Vector2, fs: int, f: Font) -> void:
	var lines := t.split("\n")
	var lh := fs * 1.1
	var y0 := center.y - lh * (lines.size() - 1) / 2.0
	for i in lines.size():
		var w := f.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos := Vector2(center.x - w / 2, y0 + i * lh + fs * 0.35)
		draw_string_outline(f, pos, lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.85))
		draw_string(f, pos, lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)

func set_state(frac: float, remaining: float, locked: String) -> void:
	var t := str(ceili(remaining)) if remaining > 0.05 and locked == "" else ""
	if cd_frac > 0 and frac <= 0 and locked == "": flash = 1.0
	if frac != cd_frac or t != cd_text or locked != locked_text:
		cd_frac = frac; cd_text = t; locked_text = locked
		queue_redraw()

func set_held(h: bool) -> void:
	if h != held:
		held = h
		pivot_offset = size / 2
		scale = Vector2.ONE * (0.9 if h else 1.0)
		queue_redraw()
