extends Control
class_name Minimap
## Круглая мини-карта/компас: вращается вместе с камерой, метки цели (босс), торговца, портала и врагов.

var zone
const RANGE := 55.0
var range_m := RANGE
var big := false
var _ring: Texture2D
var _font: Font
var _icons := {}

const C_MOB := Color(1.0, 0.25, 0.2)
const C_ELITE := Color(1.0, 0.55, 0.9)
const C_PARTY := Color(0.3, 1.0, 0.4)
const C_PLAYER := Color(0.7, 0.85, 1.0)
const C_TOWN := Color(1.0, 0.88, 0.6)
const C_WP := Color(0.35, 0.8, 1.0)
const C_PORTAL := Color(0.45, 0.7, 1)
const C_GATE := Color(0.75, 0.5, 1.0)
const C_MERCH := Color(1, 0.85, 0.3)
const C_STASH := Color(0.85, 0.65, 0.4)
const LONG_PRESS := 0.45
var _terrain: Texture2D
var _press_t := -1.0
var _press_pos := Vector2.ZERO
var drawn := {}   # для тестов: что нарисовано на последнем кадре (категория -> количество)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_ring = load("res://assets/ui/compass_ring.png")
	_terrain = load("res://assets/world/minimap.png")
	_font = UIK.title_font()
	for n in ["skull-crossed-bones", "two-coins", "castle", "person", "magic-portal", "dungeon-gate", "chest", "village"]: _icons[n] = UIK.icon(n)

func _process(_d: float) -> void:
	if _press_t >= 0.0 and Time.get_ticks_msec() / 1000.0 - _press_t >= LONG_PRESS:
		_press_t = -1.0
		place_or_remove_at(_press_pos)
	queue_redraw()

## v0.9.4.2: касание/клик — карта мира; долгое нажатие или правый клик — поставить/снять метку
func _gui_input(ev: InputEvent) -> void:
	if zone == null or zone.player == null: return
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			place_or_remove_at(mb.position); accept_event(); return
		if mb.button_index != MOUSE_BUTTON_LEFT: return
		if mb.pressed:
			_press_t = Time.get_ticks_msec() / 1000.0; _press_pos = mb.position
		else:
			if _press_t >= 0.0 and zone.builder is WorldBuilder and zone.hud.window == null: zone.hud._open("map")
			_press_t = -1.0
		accept_event()
	elif ev is InputEventMouseMotion and _press_t >= 0.0 and (ev as InputEventMouseMotion).position.distance_to(_press_pos) > 18.0:
		_press_t = -1.0

## Точка мини-карты (локальные пиксели) -> мир XZ
func from_map(local: Vector2) -> Vector2:
	var m := local - size / 2
	var r := size.x / 2 * 0.78
	var pp: Vector3 = zone.player.global_position
	var cam: Camera3D = get_viewport().get_camera_3d()
	var d := m
	if cam != null:
		var f := -cam.global_basis.z; var rt := cam.global_basis.x
		var fwd := Vector2(f.x, f.z).normalized(); var right := Vector2(rt.x, rt.z).normalized()
		d = right * m.x - fwd * m.y
	return Vector2(pp.x, pp.z) + d / r * range_m

func place_or_remove_at(local: Vector2) -> bool:
	if (local - size / 2).length() > size.x / 2 * 0.86: return false
	var w := from_map(local)
	var res := MapMarks.toggle(zone.data, w, range_m * 0.12)
	queue_redraw()
	return res

## Мировая точка -> точка на карте (вверх = направление взгляда камеры)
func to_map(p: Vector3) -> Vector2:
	var r := size.x / 2 * 0.78
	var pp: Vector3 = zone.player.global_position
	var d := Vector2(p.x - pp.x, p.z - pp.z) / range_m * r
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null: return d
	var f := -cam.global_basis.z; var rt := cam.global_basis.x
	var fwd := Vector2(f.x, f.z).normalized(); var right := Vector2(rt.x, rt.z).normalized()
	return Vector2(d.dot(right), -d.dot(fwd))

func _clampv(v: Vector2, r: float) -> Vector2:
	return v.limit_length(r)

func _count(k: String) -> void: drawn[k] = int(drawn.get(k, 0)) + 1

func _draw() -> void:
	if zone == null or zone.player == null: return
	drawn = {}
	var c := size / 2
	var r := size.x / 2
	var inner := r * 0.8     # всё, что дальше, — скрыто (кроме цели и меток игрока)
	var world: bool = zone.builder is WorldBuilder
	_draw_ground(c, r, world)
	if zone.has_method("is_dungeon") and zone.is_dungeon() and zone.builder and zone.builder.has_method("guide_target"):
		_draw_route(c, r)
	if world:
		var wb: WorldBuilder = zone.builder
		for t in WorldData.TOWNS:
			var m := to_map(Vector3(t.pos.x, 0, t.pos.y))
			if m.length() < inner: _icon_at(c + m, "village", C_TOWN, 24.0); _count("town")
		var open: Array = wb.world_state()["wp"]
		for wp in wb.waypoints:
			var m := to_map(wp.pos)
			if m.length() < inner:
				draw_circle(c + m, 7.0, Color(0, 0, 0, 0.75))
				draw_circle(c + m, 5.0, C_WP if open.has(wp.id) else Color(0.55, 0.55, 0.55)); _count("waypoint")
		for mp in wb.merchant_points:
			var m := to_map(mp)
			if m.length() < inner: _icon_at(c + m, "two-coins", C_MERCH, 22.0); _count("merchant")
		for sp in wb.stash_points:
			var m := to_map(sp)
			if m.length() < inner: _icon_at(c + m, "chest", C_STASH, 20.0); _count("stash")
		for did in RaidDefs.ORDER:
			var pp2: Vector2 = RaidDefs.portal_pos(did)
			var m := to_map(Vector3(pp2.x, 0, pp2.y))
			if m.length() < inner: _icon_at(c + m, "dungeon-gate", C_GATE, 24.0); _count("raid_portal")
	elif zone.merchant != null:
		var m := to_map(zone.merchant_point)
		if m.length() < inner: _icon_at(c + m, "two-coins", C_MERCH, 24.0); _count("merchant")
	if zone.stash_point != Vector3.INF and not world:
		var m := to_map(zone.stash_point)
		if m.length() < inner: _icon_at(c + m, "chest", C_STASH, 20.0); _count("stash")
	# враги (только в радиусе)
	var boss_alive := false
	for e in zone.enemies:
		if not e.alive: continue
		if e.def.boss: boss_alive = true; continue
		var m := to_map(e.global_position)
		if m.length() < inner:
			var el: bool = e.rank in ["elite", "rare"]
			draw_circle(c + m, 5.5 if el else 4.2, Color(0, 0, 0, 0.7))
			draw_circle(c + m, 4.0 if el else 3.0, C_ELITE if el else C_MOB); _count("mob")
	# цель / порталы / босс
	var goal: Vector3 = zone.hud.objective_target() if zone.hud and zone.hud.has_method("objective_target") else Vector3.INF
	goal_point = goal
	if zone.portal_point != Vector3.ZERO: _marker(c, r, zone.portal_point, "magic-portal", C_PORTAL, _is_goal(zone.portal_point, goal))
	if zone.dungeon_gate_point != Vector3.ZERO: _marker(c, r, zone.dungeon_gate_point, "dungeon-gate", C_GATE, _is_goal(zone.dungeon_gate_point, goal))
	if boss_alive: _marker(c, r, zone.arena_point, "skull-crossed-bones", Color(1, 0.35, 0.3), _is_goal(zone.arena_point, goal))
	if goal != Vector3.INF and not zone.is_dungeon(): _goal_arrow(c, r, goal)
	# игроки: группа — зелёные с именем, прочие — голубые точки
	_draw_players(c, inner)
	# метки игрока — всегда (вне радиуса — у края со стрелкой)
	_draw_user_marks(c, r)
	# игрок (стрелка — направление персонажа относительно камеры)
	var fwd: Vector3 = zone.player.forward()
	var a := to_map(zone.player.global_position + fwd * 10.0)
	var dir := a.normalized() if a.length() > 0.01 else Vector2.UP
	var side := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([c + dir * 13, c - dir * 8 + side * 8, c - dir * 4, c - dir * 8 - side * 8]), Color(1, 0.95, 0.8))
	draw_polyline(PackedVector2Array([c + dir * 13, c - dir * 8 + side * 8, c - dir * 4, c - dir * 8 - side * 8, c + dir * 13]), Color(0, 0, 0, 0.8), 1.5)
	draw_texture_rect(_ring, Rect2(Vector2.ZERO, size), false)
	var n := to_map(zone.player.global_position + Vector3(0, 0, -1000)).normalized() * r * 0.93
	var t := "С"
	var fs := 26
	var w := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string_outline(_font, c + n + Vector2(-w / 2, 9), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color.BLACK)
	draw_string(_font, c + n + Vector2(-w / 2, 9), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.4, 0.3))
	if world:
		var pp: Vector3 = zone.player.global_position
		var b := WorldData.biome_at(pp.x, pp.z)
		var lv: Array = WorldData.BIOMES[b].lv
		var zt := "%s · %d–%d" % [WorldData.BIOMES[b].name, lv[0], lv[1]]
		var zfs := 20
		var zw := _font.get_string_size(zt, HORIZONTAL_ALIGNMENT_LEFT, -1, zfs).x
		var zp := Vector2(c.x - zw / 2, size.y + 18)
		draw_string_outline(_font, zp, zt, HORIZONTAL_ALIGNMENT_LEFT, -1, zfs, 6, Color.BLACK)
		draw_string(_font, zp, zt, HORIZONTAL_ALIGNMENT_LEFT, -1, zfs, Color(1, 0.9, 0.7))

## Цветная подложка: в мире — запечённая карта (зоны, вода, дороги, города), повёрнутая с камерой; иначе — тёмный фон
func _draw_ground(c: Vector2, r: float, world: bool) -> void:
	var rr := r * 0.86
	var pts := PackedVector2Array(); var uvs := PackedVector2Array()
	for i in 48:
		var a := i * TAU / 48.0
		var lp := c + Vector2(cos(a), sin(a)) * rr
		pts.append(lp)
		if world:
			var wp := from_map(lp)
			uvs.append((wp + Vector2.ONE * WorldData.HALF) / (WorldData.HALF * 2))
	if world and _terrain:
		draw_colored_polygon(pts, Color(0.92, 0.92, 0.92), uvs, _terrain)
		_count("terrain")
	else:
		draw_colored_polygon(pts, Color(0.1, 0.13, 0.09, 0.85))
		draw_circle(c, r * 0.5, Color(1, 1, 1, 0.03))

func _draw_players(c: Vector2, inner: float) -> void:
	if not Net.in_game: return
	var party_ids := {}
	if Net.in_party():
		for mem in Net.party.get("members", []): party_ids[int(mem.get("id", 0))] = true
	for id in Net.remotes:
		var rp: Dictionary = Net.remotes[id]
		var node = rp.get("node")
		var p: Vector3
		if node != null and is_instance_valid(node): p = node.global_position
		elif rp.get("pos") is Vector3 and rp.get("node") != null: p = rp.pos
		else: continue
		var m := to_map(p)
		var party := party_ids.has(int(id))
		if party:
			var edge := m.length() > inner
			m = m.limit_length(inner)
			draw_circle(c + m, 7.5, Color(0, 0, 0, 0.8)); draw_circle(c + m, 5.5, C_PARTY); _count("party")
			if not edge:
				var nm := str(rp.get("name", ""))
				var fw := _font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
				draw_string_outline(_font, c + m + Vector2(-fw / 2, -10), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color.BLACK)
				draw_string(_font, c + m + Vector2(-fw / 2, -10), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_PARTY)
		elif m.length() < inner:
			draw_circle(c + m, 4.0, C_PLAYER); _count("player")

func _draw_user_marks(c: Vector2, r: float) -> void:
	var lim := r * 0.74
	for mk in MapMarks.list(zone.data):
		var wp := MapMarks.pos(mk)
		var m := to_map(Vector3(wp.x, 0, wp.y))
		var col := MapMarks.color(mk)
		_count("user_mark")
		if m.length() > lim:
			var d := m.normalized(); var sd := Vector2(-d.y, d.x)
			var tip := c + d * r * 0.8
			draw_colored_polygon(PackedVector2Array([tip + d * 4, tip - d * 13 + sd * 9, tip - d * 13 - sd * 9]), Color(0, 0, 0, 0.8))
			draw_colored_polygon(PackedVector2Array([tip, tip - d * 10 + sd * 6.5, tip - d * 10 - sd * 6.5]), col)
			_count("user_mark_edge")
		else:
			_flag(c + m, col)

func _flag(at: Vector2, col: Color) -> void:
	draw_line(at, at + Vector2(0, -18), Color(0, 0, 0, 0.9), 3.5)
	draw_line(at, at + Vector2(0, -18), Color.WHITE, 1.5)
	draw_colored_polygon(PackedVector2Array([at + Vector2(0, -18), at + Vector2(12, -13), at + Vector2(0, -8)]), col)
	draw_circle(at, 3.0, col)

func _icon_at(at: Vector2, ic: String, col: Color, s: float) -> void:
	draw_circle(at, s * 0.6, Color(0, 0, 0, 0.7))
	draw_arc(at, s * 0.6, 0, TAU, 16, col, 1.5)
	draw_texture_rect(_icons[ic], Rect2(at - Vector2(s, s) * 0.4, Vector2(s, s) * 0.8), false, col)

## Для тестов
func self_check() -> Array:
	return [[drawn.get("terrain", 0) == 1 or not (zone.builder is WorldBuilder), "мини-карта: цветная подложка мира"],
		[int(drawn.get("user_mark", 0)) == MapMarks.list(zone.data).size(), "мини-карта: все метки игрока видны (%d)" % MapMarks.list(zone.data).size()]]

func _draw_route(c: Vector2, r: float) -> void:
	var b = zone.builder
	var pts := PackedVector2Array()
	for p in b.ROUTE: pts.append(c + _clampv(to_map(p), r * 0.8))
	draw_polyline(pts, Color(1, 0.8, 0.4, 0.35), 5.0, true)
	var t: Vector3 = b.guide_target()
	var m := _clampv(to_map(t), r * 0.7)
	var pr := 9.0 + sin(Time.get_ticks_msec() * 0.008) * 3.0
	draw_circle(c + m, pr, Color(1, 0.8, 0.3, 0.85))
	draw_arc(c + m, pr + 4, 0, TAU, 20, Color(0, 0, 0, 0.8), 2.0)

var goal_point := Vector3.INF   # для тестов: куда указывает цель
func _is_goal(p: Vector3, goal: Vector3) -> bool: return goal != Vector3.INF and U.flat_dist(p, goal) < 1.0

## Стрелка у края мини-карты в сторону цели (если цель дальше видимой области)
func _goal_arrow(c: Vector2, r: float, goal: Vector3) -> void:
	var m := to_map(goal)
	if m.length() < r * 0.66: return
	var d := m.normalized(); var sd := Vector2(-d.y, d.x)
	var tip := c + d * r * 0.84
	var col := Color(1, 0.85, 0.35, 0.75 + sin(Time.get_ticks_msec() * 0.008) * 0.25)
	draw_colored_polygon(PackedVector2Array([tip, tip - d * 16 + sd * 10, tip - d * 16 - sd * 10]), col)

func _marker(c: Vector2, r: float, p: Vector3, ic: String, col: Color, pulse := false) -> void:
	var m := to_map(p)
	if m.length() > r * 0.8 and not pulse: return
	_count(ic)
	var edge := m.length() > r * 0.7
	m = _clampv(m, r * 0.7)
	var s := 30.0 if not edge else 24.0
	if pulse: s += sin(Time.get_ticks_msec() * 0.006) * 3
	draw_circle(c + m, s * 0.62, Color(0, 0, 0, 0.7))
	draw_arc(c + m, s * 0.62, 0, TAU, 20, col, 2.0)
	draw_texture_rect(_icons[ic], Rect2(c + m - Vector2(s, s) / 2, Vector2(s, s)), false, col)


## Большая карта (клавиша M на ПК)
func toggle_big() -> void:
	big = not big
	if big:
		anchor_left = 0.5; anchor_right = 0.5; anchor_top = 0.5; anchor_bottom = 0.5
		offset_left = -380; offset_right = 380; offset_top = -380; offset_bottom = 380
		range_m = RANGE * 2.2
	else:
		anchor_left = 1; anchor_right = 1; anchor_top = 0; anchor_bottom = 0
		offset_left = -276; offset_right = -16; offset_top = 14; offset_bottom = 274
		range_m = RANGE
