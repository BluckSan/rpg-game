extends Control
class_name Minimap
## Круглая мини-карта/компас: вращается вместе с камерой, метки цели (босс), торговца, портала и врагов.

var zone
const RANGE := 55.0
var _ring: Texture2D
var _font: Font
var _icons := {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring = load("res://assets/ui/compass_ring.png")
	_font = UIK.title_font()
	for n in ["skull-crossed-bones", "two-coins", "castle", "person"]: _icons[n] = UIK.icon(n)

func _process(_d: float) -> void:
	queue_redraw()

## Мировая точка -> точка на карте (вверх = направление взгляда камеры)
func to_map(p: Vector3) -> Vector2:
	var r := size.x / 2 * 0.78
	var pp: Vector3 = zone.player.global_position
	var d := Vector2(p.x - pp.x, p.z - pp.z) / RANGE * r
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null: return d
	var f := -cam.global_basis.z; var rt := cam.global_basis.x
	var fwd := Vector2(f.x, f.z).normalized(); var right := Vector2(rt.x, rt.z).normalized()
	return Vector2(d.dot(right), -d.dot(fwd))

func _clampv(v: Vector2, r: float) -> Vector2:
	return v.limit_length(r)

func _draw() -> void:
	if zone == null or zone.player == null: return
	var c := size / 2
	var r := size.x / 2
	draw_circle(c, r * 0.86, Color(0.08, 0.1, 0.07, 0.78))
	draw_circle(c, r * 0.5, Color(1, 1, 1, 0.03))
	# враги
	for e in zone.enemies:
		if not e.alive or e.def.boss: continue
		var m := to_map(e.global_position)
		if m.length() < r * 0.78: draw_circle(c + m, 4.0, Color(0.95, 0.3, 0.25, 0.9))
	# метки
	var boss_alive := false
	for e in zone.enemies:
		if e.alive and e.def.boss: boss_alive = true
	_marker(c, r, zone.merchant_point, "two-coins", Color(1, 0.85, 0.3))
	_marker(c, r, zone.portal_point, "castle", Color(0.6, 0.75, 1))
	if boss_alive: _marker(c, r, zone.arena_point, "skull-crossed-bones", Color(1, 0.35, 0.3), true)
	# игрок (стрелка — направление персонажа относительно камеры)
	var fwd: Vector3 = zone.player.forward()
	var a := to_map(zone.player.global_position + fwd * 10.0)
	var dir := a.normalized() if a.length() > 0.01 else Vector2.UP
	var side := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([c + dir * 13, c - dir * 8 + side * 8, c - dir * 4, c - dir * 8 - side * 8]), Color(1, 0.95, 0.8))
	draw_texture_rect(_ring, Rect2(Vector2.ZERO, size), false)
	# север
	var n := to_map(zone.player.global_position + Vector3(0, 0, -1000)).normalized() * r * 0.93
	var t := "С"
	var fs := 26
	var w := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string_outline(_font, c + n + Vector2(-w / 2, 9), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color.BLACK)
	draw_string(_font, c + n + Vector2(-w / 2, 9), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.4, 0.3))

func _marker(c: Vector2, r: float, p: Vector3, ic: String, col: Color, pulse := false) -> void:
	var m := to_map(p)
	var edge := m.length() > r * 0.7
	m = _clampv(m, r * 0.7)
	var s := 30.0 if not edge else 24.0
	if pulse: s += sin(Time.get_ticks_msec() * 0.006) * 3
	draw_circle(c + m, s * 0.62, Color(0, 0, 0, 0.7))
	draw_arc(c + m, s * 0.62, 0, TAU, 20, col, 2.0)
	draw_texture_rect(_icons[ic], Rect2(c + m - Vector2(s, s) / 2, Vector2(s, s)), false, col)
