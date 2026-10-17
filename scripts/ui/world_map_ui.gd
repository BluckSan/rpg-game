extends Control
## Карта мира: зоны с уровнями, города, путевые камни (открытые — можно перенестись), боссы зон, герой.
## Касание/клик по открытому камню или кнопка в списке — быстрое перемещение (не в бою).

var zone
var data: Dictionary
var map_rect: Control
var list: VBoxContainer
var _tex: Texture2D
var _font: Font
var _icons := {}
var info: Label

func setup(z) -> void:
	zone = z
	data = z.data
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = UIK.title_font()
	_tex = load("res://assets/world/worldmap.png")
	for n in ["skull-crossed-bones", "two-coins", "castle", "treasure-map", "person"]: _icons[n] = UIK.icon(n)
	UIK.full(UIK.panel(self, Color(0.03, 0.025, 0.02, 0.97), 0))
	var ic := UIK.icon_rect(self, "treasure-map", 64, UIK.ACCENT); ic.position = Vector2(28, 22)
	var t := UIK.label(self, "Земли Эфира", 50, UIK.ACCENT); t.autowrap_mode = TextServer.AUTOWRAP_OFF
	UIK.rect(t, Vector2(104, 14), Vector2(700, 84))
	var close := UIK.button(self, "Закрыть", _close, UIK.RED, 30)
	close.anchor_left = 1; close.anchor_right = 1; close.offset_left = -230; close.offset_right = -24; close.offset_top = 18; close.offset_bottom = 96
	map_rect = Control.new(); map_rect.name = "Map"
	add_child(map_rect)
	map_rect.anchor_bottom = 1; map_rect.offset_left = 24; map_rect.offset_top = 108; map_rect.offset_bottom = -20
	map_rect.anchor_right = 0; map_rect.offset_right = 24 + 950
	map_rect.draw.connect(_draw_map)
	map_rect.gui_input.connect(_on_map_input)
	var rp := UIK.panel(self)
	rp.anchor_left = 1; rp.anchor_right = 1; rp.anchor_bottom = 1
	rp.offset_left = -900; rp.offset_right = -20; rp.offset_top = 108; rp.offset_bottom = -20
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 8); rp.add_child(v); UIK.full(v)
	v.offset_left = 20; v.offset_right = -20; v.offset_top = 16; v.offset_bottom = -16
	info = UIK.label(v, "", 24, UIK.MUTED)
	var lh := UIK.label(v, "Путевые камни", 30, UIK.ACCENT); lh.autowrap_mode = TextServer.AUTOWRAP_OFF
	var holder := Control.new(); holder.size_flags_vertical = Control.SIZE_EXPAND_FILL; v.add_child(holder)
	list = UIK.scroll_list(holder, 8)
	refresh()

func _wb() -> WorldBuilder:
	return zone.builder as WorldBuilder

func refresh() -> void:
	var wb := _wb()
	var p: Vector3 = zone.player.global_position
	var b := WorldData.biome_at(p.x, p.z)
	var lv: Array = WorldData.BIOMES[b].lv
	info.text = "Вы здесь: %s (ур. %d–%d)\nКоснитесь открытого камня на карте или выберите его в списке." % [WorldData.BIOMES[b].name, lv[0], lv[1]]
	UIK.clear(list)
	var open: Array = wb.world_state()["wp"]
	for wp in wb.waypoints:
		var known: bool = open.has(wp.id)
		var bi := WorldData.biome_at(wp.pos.x, wp.pos.z)
		var r: Array = WorldData.BIOMES[bi].lv
		var txt: String = ("%s  ·  %s %d–%d" % [wp.name, WorldData.BIOMES[bi].name, r[0], r[1]]) if known else "??? — не открыт"
		var bt := UIK.button(list, txt, travel.bind(wp.id), UIK.BLUE if known else Color(0.25, 0.25, 0.25), 24, "treasure-map")
		bt.disabled = not known
		bt.alignment = HORIZONTAL_ALIGNMENT_LEFT
		bt.name = "WP_" + str(wp.id)
		UIK.min_h(bt, 66)
	map_rect.queue_redraw()

## Мир → координаты карты (квадрат, вписанный в map_rect)
func _side() -> float: return minf(map_rect.size.x, map_rect.size.y)
func to_map(p: Vector2) -> Vector2:
	var s := _side()
	return (p + Vector2.ONE * WorldData.HALF) / (WorldData.HALF * 2) * s
func to_world(m: Vector2) -> Vector2:
	return m / _side() * WorldData.HALF * 2 - Vector2.ONE * WorldData.HALF

func _draw_map() -> void:
	var s := _side()
	var wb := _wb()
	map_rect.draw_texture_rect(_tex, Rect2(Vector2.ZERO, Vector2(s, s)), false)
	# дороги
	for r in WorldData.ROADS:
		var pts := PackedVector2Array()
		for q in r: pts.append(to_map(q))
		map_rect.draw_polyline(pts, Color(0.45, 0.33, 0.22, 0.9), 4.0, true)
	# подписи зон
	for i in WorldData.BIOMES.size():
		var b: Dictionary = WorldData.BIOMES[i]
		var c := to_map(b.seed)
		var t := "%s\nур. %d–%d" % [b.name, b.lv[0], b.lv[1]]
		var lines := t.split("\n")
		for li in lines.size():
			var fs := 26 if li == 0 else 22
			var w := _font.get_string_size(lines[li], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var pos := c + Vector2(-w / 2, li * 28 - 40)
			map_rect.draw_string_outline(_font, pos, lines[li], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.85))
			map_rect.draw_string(_font, pos, lines[li], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.92, 0.75) if li == 0 else Color(0.85, 0.85, 0.85))
	# точки интереса и боссы
	var killed: Array = wb.world_state().get("bosses", [])
	for bs in wb.bosses:
		var m := to_map(Vector2(bs.pos.x, bs.pos.z))
		var dead := killed.has("boss_" + WorldData.BIOMES[bs.biome].id)
		map_rect.draw_texture_rect(_icons["skull-crossed-bones"], Rect2(m - Vector2(14, 14), Vector2(28, 28)), false, Color(0.6, 0.6, 0.6) if dead else Color(1, 0.35, 0.3))
	# города и камни
	var open: Array = wb.world_state()["wp"]
	for wp in wb.waypoints:
		var m := to_map(Vector2(wp.pos.x, wp.pos.z))
		var known: bool = open.has(wp.id)
		map_rect.draw_circle(m, 11.0, Color(0.1, 0.1, 0.12, 0.85))
		map_rect.draw_circle(m, 8.0, Color(0.35, 0.8, 1.0) if known else Color(0.4, 0.4, 0.4))
		if known or wp.town >= 0:
			var fs := 20
			var w := _font.get_string_size(wp.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			map_rect.draw_string_outline(_font, m + Vector2(-w / 2, 30), wp.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color.BLACK)
			map_rect.draw_string(_font, m + Vector2(-w / 2, 30), wp.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE if known else Color(0.7, 0.7, 0.7))
	# герой
	var pp: Vector3 = zone.player.global_position
	var pm := to_map(Vector2(pp.x, pp.z))
	var f: Vector3 = zone.player.forward()
	var dir := Vector2(f.x, f.z).normalized()
	if dir == Vector2.ZERO: dir = Vector2.UP
	var side := Vector2(-dir.y, dir.x)
	map_rect.draw_colored_polygon(PackedVector2Array([pm + dir * 16, pm - dir * 10 + side * 10, pm - dir * 5, pm - dir * 10 - side * 10]), Color(1, 0.95, 0.5))
	map_rect.draw_arc(pm, 20, 0, TAU, 24, Color(1, 0.95, 0.5, 0.6), 2.0)
	map_rect.draw_rect(Rect2(Vector2.ZERO, Vector2(s, s)), Color(0.6, 0.48, 0.3), false, 3.0)

func _on_map_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var wb := _wb()
		var open: Array = wb.world_state()["wp"]
		for wp in wb.waypoints:
			if open.has(wp.id) and to_map(Vector2(wp.pos.x, wp.pos.z)).distance_to(ev.position) < 22.0:
				travel(wp.id); return

## Быстрое перемещение (не во время боя)
func travel(id: String) -> bool:
	var p: Player = zone.player
	for e in zone.enemies:
		if e.alive and e._aggro and U.flat_dist(e.global_position, p.global_position) < 25.0:
			Game.toast("Нельзя переместиться во время боя", 2.0)
			return false
	var ok := _wb().travel_to(id)
	if ok:
		zone.hud.close_window()
		Game.toast("Перемещение: %s" % _name_of(id), 2.0)
	return ok

func _name_of(id: String) -> String:
	for wp in _wb().waypoints: if wp.id == id: return wp.name
	return id

func _close() -> void:
	zone.hud.close_window()
