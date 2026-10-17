extends Control
## Окно пассивного дерева талантов: перетаскивание, зум (щипок/колёсико), выбор и изучение узлов, пути превращения.

var zone
var data: Dictionary
var canvas: Control         # область рисования дерева
var side: Panel
var points_label: RichTextLabel
var info_title: Label
var info_body: RichTextLabel
var learn_btn: Button
var asc_list: VBoxContainer
var selected := -1
var zoom := 0.6
var offset := Vector2.ZERO   # смещение центра дерева относительно центра области
var font: Font
var _touches := {}
var _pinch := 0.0
var _press_pos := Vector2.ZERO
var _dragged := false

func setup(z) -> void:
	zone = z
	data = z.data
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = load("res://fonts/Rubik.ttf")
	var bg := UIK.panel(self, Color(0.03, 0.03, 0.05, 0.97), 0)
	UIK.full(bg)
	canvas = Control.new()
	canvas.clip_contents = true
	add_child(canvas)
	UIK.place(canvas, 0, 0, 0.72, 1)
	canvas.draw.connect(_draw_tree)
	canvas.gui_input.connect(_canvas_input)

	side = UIK.panel(self, UIK.PANEL, 0)
	UIK.place(side, 0.72, 0, 1, 1)
	UIK.place(UIK.label(side, "Дерево талантов", 40, UIK.ACCENT, HORIZONTAL_ALIGNMENT_CENTER), 0, 0.92, 1, 0.99)
	points_label = UIK.rich(side, "", 28)
	UIK.place(points_label, 0.04, 0.86, 0.98, 0.92)
	var info := UIK.panel(side, Color(0, 0, 0, 0.4))
	UIK.place(info, 0.04, 0.56, 0.96, 0.86)
	info_title = UIK.label(info, "Выберите узел", 32, UIK.ACCENT)
	UIK.place(info_title, 0.05, 0.76, 0.95, 0.97)
	info_body = UIK.rich(info, "Двигайте дерево пальцем, приближайте двумя пальцами.", 25)
	UIK.place(info_body, 0.05, 0.25, 0.95, 0.76)
	learn_btn = UIK.button(info, "Изучить", _learn, UIK.GREEN, 30)
	UIK.place(learn_btn, 0.05, 0.04, 0.95, 0.22)
	UIK.place(UIK.label(side, "Пути превращения", 30, UIK.ACCENT, HORIZONTAL_ALIGNMENT_CENTER), 0, 0.5, 1, 0.555)
	var ap := Control.new(); side.add_child(ap)
	UIK.place(ap, 0.02, 0.14, 0.98, 0.5)
	asc_list = UIK.scroll_list(ap, 8)
	UIK.place(UIK.button(side, "Сброс", _reset, Color(0.45, 0.18, 0.15), 28), 0.04, 0.02, 0.36, 0.12)
	UIK.place(UIK.button(side, "Закрыть", _close, UIK.BUTTON, 30), 0.4, 0.02, 0.96, 0.12)
	var start: Dictionary = DB.tree_nodes[DB.start_node(data["class"])]
	offset = -start["pos"] * zoom
	refresh()

func refresh() -> void:
	points_label.text = "[center]Свободных очков: [b]%d[/b]  (изучено %d)[/center]" % [DB.free_points(data), data["talents"].size() - 1]
	_update_info()
	_build_asc_list()
	canvas.queue_redraw()

func _to_screen(p: Vector2) -> Vector2:
	return canvas.size / 2 + offset + p * zoom

func _node_radius(n: Dictionary) -> float:
	match n["type"]:
		"keystone": return 39.0
		"notable": return 27.0
		"start": return 32.0
	return 17.0

func _region_color(region: String) -> Color:
	return DB.tree_regions[region]["color"] if DB.tree_regions.has(region) else Color(0.85, 0.78, 0.55)

func _draw_tree() -> void:
	var drawn := {}
	for id in DB.tree_order:
		var n: Dictionary = DB.tree_nodes[id]
		for l in n["links"]:
			var key := Vector2i(mini(id, l), maxi(id, l))
			if drawn.has(key): continue
			drawn[key] = true
			var m: Dictionary = DB.tree_nodes[l]
			var ha := DB.has_talent(data, id)
			var hb := DB.has_talent(data, l)
			var rc := _region_color(n["region"] if n["region"] != "" else m["region"])
			var col := rc.lerp(Color.WHITE, 0.3) if (ha and hb) else (rc.darkened(0.5) if (ha or hb) else Color(0.2, 0.2, 0.24))
			canvas.draw_line(_to_screen(n["pos"]), _to_screen(m["pos"]), col, maxf(2.0, 6.0 * zoom), true)
	var labels := []
	for id in DB.tree_order:
		var n: Dictionary = DB.tree_nodes[id]
		var p := _to_screen(n["pos"])
		var r := _node_radius(n) * zoom
		if p.x < -60 or p.y < -60 or p.x > canvas.size.x + 60 or p.y > canvas.size.y + 60: continue
		var has := DB.has_talent(data, id)
		var avail := not has and DB.can_allocate(data, id)
		var rc := _region_color(n["region"])
		var ring := Color.WHITE if id == selected else (UIK.ACCENT if has else (Color(0.6, 0.6, 0.6) if avail else Color(0.1, 0.1, 0.12)))
		var fill := rc.lerp(Color.WHITE, 0.25) if has else (rc.darkened(0.35) if avail else Color(0.18, 0.18, 0.2))
		canvas.draw_circle(p, r + 5 * zoom, ring)
		canvas.draw_circle(p, r, fill)
		if n["type"] == "keystone" or n["type"] == "start":
			var t: String = DB.CLASSES[n["class"]].name if n["type"] == "start" else n["name"]
			var fs := maxi(14, int(22 * zoom / 0.6))
			var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var off := Vector2(0, r + 10 + fs)
			if n["type"] == "start":
				# стартовые узлы стоят тесно в центре — подпись выносим наружу от центра дерева
				var nd: Vector2 = (n["pos"] as Vector2).normalized()
				off = nd * (r + fs * 1.6) + Vector2(0, fs * 0.35)
			var tp := p + Vector2(-w / 2, 0) + off
			labels.append([tp, t, fs])
	# подписи рисуем поверх всех узлов
	for lb in labels:
		canvas.draw_string_outline(font, lb[0], lb[1], HORIZONTAL_ALIGNMENT_LEFT, -1, lb[2], 6, Color.BLACK)
		canvas.draw_string(font, lb[0], lb[1], HORIZONTAL_ALIGNMENT_LEFT, -1, lb[2], Color.WHITE)
	for rid in DB.tree_regions:
		var key := DB.keystone_of(rid)
		if key.is_empty(): continue
		var kp: Vector2 = key["pos"]
		var dir := kp.normalized()
		var lp := _to_screen(kp * 0.62 + Vector2(-dir.y, dir.x) * 120)
		var t: String = DB.tree_regions[rid]["name"].to_upper()
		var fs := maxi(16, int(34 * zoom / 0.6))
		var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var c: Color = DB.tree_regions[rid]["color"].lightened(0.3); c.a = 0.6
		canvas.draw_string(font, lp - Vector2(w / 2, 0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)

func _canvas_input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		if ev.pressed:
			_touches[ev.index] = ev.position
			if _touches.size() == 1:
				_press_pos = ev.position; _dragged = false
		else:
			_touches.erase(ev.index)
			_pinch = 0
			if _touches.is_empty() and not _dragged: _tap(ev.position)
	elif ev is InputEventScreenDrag:
		_touches[ev.index] = ev.position
		if _touches.size() >= 2:
			var v := _touches.values()
			var d: float = v[0].distance_to(v[1])
			if _pinch > 0: _zoom_at(d / _pinch, (v[0] + v[1]) / 2)
			_pinch = d
			_dragged = true
		else:
			offset += ev.relative
			if ev.position.distance_to(_press_pos) > 12: _dragged = true
			_clamp(); canvas.queue_redraw()
	elif ev is InputEventMouseButton and not DisplayServer.is_touchscreen_available():
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP and ev.pressed: _zoom_at(1.1, ev.position)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN and ev.pressed: _zoom_at(0.9, ev.position)
		elif ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				_press_pos = ev.position; _dragged = false
			elif not _dragged: _tap(ev.position)
	elif ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT) and not DisplayServer.is_touchscreen_available():
		offset += ev.relative
		if ev.position.distance_to(_press_pos) > 12: _dragged = true
		_clamp(); canvas.queue_redraw()

func _zoom_at(k: float, at: Vector2) -> void:
	var nz := clampf(zoom * k, 0.25, 1.8)
	var tree_pt := (at - canvas.size / 2 - offset) / zoom
	zoom = nz
	offset = at - canvas.size / 2 - tree_pt * zoom
	_clamp()
	canvas.queue_redraw()

func _clamp() -> void:
	var lim := 800 * zoom
	offset = offset.clamp(Vector2(-lim, -lim), Vector2(lim, lim))

func _tap(p: Vector2) -> void:
	var best := -1
	var best_d := INF
	for id in DB.tree_order:
		var n: Dictionary = DB.tree_nodes[id]
		var d := _to_screen(n["pos"]).distance_to(p)
		var r := maxf(_node_radius(n) * zoom + 10, 26)
		if d < r and d < best_d:
			best_d = d; best = id
	if best >= 0:
		selected = best
		refresh()
		_show_tip(best, p)
	elif tip and is_instance_valid(tip):
		tip.queue_free()

var tip: Control
## Всплывающая подсказка у выбранного узла
func _show_tip(id: int, at: Vector2) -> void:
	if tip and is_instance_valid(tip): tip.queue_free()
	var n: Dictionary = DB.tree_nodes[id]
	var title: String = ("Начало: " + DB.CLASSES[n["class"]].name) if n["type"] == "start" else n["name"]
	var t := ""
	for m in n["mods"]: t += DB.describe_mod(m) + "\n"
	var has := DB.has_talent(data, id)
	t += "[color=#7fd87f]Изучено[/color]" if has else ("[color=#e6c27a]Можно изучить[/color]" if DB.can_allocate(data, id) else "[color=#999]Нужна связь с изученным узлом[/color]")
	var col: Color = {"keystone": Color(1, 0.6, 0.25), "notable": UIK.ACCENT}.get(n["type"], UIK.TEXT)
	var ic: String = {"keystone": "aura", "notable": "crystal-ball", "start": "swords-emblem"}.get(n["type"], "gem-pendant")
	tip = UIK.tooltip(self, title, t.strip_edges(), ic, col, 440)
	UIK.place_tooltip(tip, Rect2(at - Vector2(30, 30), Vector2(60, 60)), get_viewport_rect().size)

func _update_info() -> void:
	if selected < 0:
		learn_btn.visible = false
		return
	var n: Dictionary = DB.tree_nodes[selected]
	var type_name: String = {"keystone": "Ключевой талант", "notable": "Особый талант", "start": "Стартовая точка"}.get(n["type"], "Малый талант")
	info_title.text = ("Начало: " + DB.CLASSES[n["class"]].name) if n["type"] == "start" else n["name"]
	var t := "[i]%s%s[/i]\n" % [type_name, (" · " + DB.tree_regions[n["region"]]["name"]) if DB.tree_regions.has(n["region"]) else ""]
	for m in n["mods"]: t += DB.describe_mod(m) + "\n"
	if n["type"] == "keystone":
		var a := DB.get_asc(n["region"])
		if not a.is_empty(): t += "\nОткрывает путь: [b]%s[/b]" % a["name"]
	info_body.text = t
	var has := DB.has_talent(data, selected)
	learn_btn.visible = not has and n["type"] != "start"
	learn_btn.disabled = not DB.can_allocate(data, selected)
	learn_btn.text = "Нет очков" if DB.free_points(data) <= 0 else ("Изучить" if not learn_btn.disabled else "Недоступно (нет связи)")

func _build_asc_list() -> void:
	UIK.clear(asc_list)
	for a in DB.ASCENDANCIES:
		var current: bool = data["ascendancy"] == a["id"]
		var reason := DB.asc_block_reason(data, a)
		var pts := DB.points_in_region(data, a["id"])
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UIK.box((a["color"] * 0.6 + Color(0, 0, 0, 1)) if current else Color(0.12, 0.12, 0.16), 8, 0))
		UIK.min_h(row, 110)
		asc_list.add_child(row)
		var h := HBoxContainer.new(); row.add_child(h)
		var stripe := ColorRect.new(); stripe.color = a["color"]; stripe.custom_minimum_size.x = 10; h.add_child(stripe)
		var status: String = ("Выбран. Умение: " + a["skill"]["name"]) if current else ("Доступен!" if reason == "" else reason)
		var lbl := UIK.rich(h, "[b]%s[/b]  [font_size=20](%d очк.)[/font_size]\n[font_size=20]%s[/font_size]" % [a["name"], pts, status], 26)
		lbl.fit_content = true
		UIK.expand(lbl, 2.5)
		lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var b: Button
		if reason == "" and not current:
			b = UIK.button(h, "Превратиться", _ascend.bind(a), UIK.GOLD, 22)
		else:
			b = UIK.button(h, "Инфо", _asc_info.bind(a), UIK.BUTTON, 22)
		UIK.expand(b, 1)
		b.custom_minimum_size.y = 80
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER

func _asc_info(a: Dictionary) -> void:
	selected = -1
	info_title.text = a["name"]
	info_body.text = "%s\n\nУмение: %s — %s\nТребуется: %d ур., ключевой талант региона и %d очков в нём." % [
		a["desc"], a["skill"]["name"], a["skill"]["desc"], DB.ASC_LEVEL, DB.ASC_REGION_POINTS]
	learn_btn.visible = false
	canvas.queue_redraw()

func _ascend(a: Dictionary) -> void:
	data["ascendancy"] = a["id"]
	zone.apply_character_changes(true)
	Game.toast("Вы стали: %s! Новое умение: %s" % [a["name"], a["skill"]["name"]], 4.0)
	refresh()

func _learn() -> void:
	if DB.allocate(data, selected):
		zone.apply_character_changes(false)
	refresh()

func _reset() -> void:
	var had: bool = data["ascendancy"] != ""
	DB.reset_talents(data)
	zone.apply_character_changes(had)
	Game.toast("Таланты сброшены")
	refresh()

func _close() -> void:
	zone.save()
	zone.hud.close_window()
