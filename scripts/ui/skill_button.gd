extends Control
class_name SkillButton
## Круглая кнопка умения с затемнением перезарядки. Нажатия обрабатывает HUD (мультитач).

var color := Color.WHITE
var text := ""
var cd_frac := 0.0
var cd_text := ""
var locked_text := ""
var held := false
var font: Font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = load("res://fonts/Rubik.ttf")

func hit(p: Vector2) -> bool:
	var c := global_position + size / 2
	return p.distance_to(c) <= size.x / 2

func _draw() -> void:
	var r := size.x / 2
	var c := size / 2
	draw_circle(c, r, Color(0, 0, 0, 0.45))
	draw_circle(c, r - 8, color.darkened(0.25) if held else color)
	if locked_text != "":
		draw_circle(c, r - 8, Color(0, 0, 0, 0.65))
	elif cd_frac > 0:
		var pts := PackedVector2Array([c])
		var steps := 32
		for i in steps + 1:
			var a := -PI / 2 + TAU * cd_frac * float(i) / steps
			pts.append(c + Vector2(cos(a), sin(a)) * (r - 8))
		draw_colored_polygon(pts, Color(0, 0, 0, 0.65))
	var fs := int(r * 0.34)
	_text_centered(text, c + Vector2(0, -2 if cd_text == "" else -r * 0.35), fs)
	if locked_text != "":
		_text_centered(locked_text, c + Vector2(0, r * 0.38), int(r * 0.24))
	elif cd_text != "":
		_text_centered(cd_text, c + Vector2(0, r * 0.25), int(r * 0.45))

func _text_centered(t: String, center: Vector2, fs: int) -> void:
	var lines := t.split("\n")
	var lh := fs * 1.1
	var y0 := center.y - lh * (lines.size() - 1) / 2.0
	for i in lines.size():
		var w := font.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos := Vector2(center.x - w / 2, y0 + i * lh + fs * 0.35)
		draw_string_outline(font, pos, lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.8))
		draw_string(font, pos, lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)

func set_state(frac: float, remaining: float, locked: String) -> void:
	var t := str(ceili(remaining)) if remaining > 0.05 and locked == "" else ""
	if frac != cd_frac or t != cd_text or locked != locked_text:
		cd_frac = frac; cd_text = t; locked_text = locked
		queue_redraw()

func set_held(h: bool) -> void:
	if h != held:
		held = h
		scale = Vector2.ONE * (0.92 if h else 1.0)
		queue_redraw()
