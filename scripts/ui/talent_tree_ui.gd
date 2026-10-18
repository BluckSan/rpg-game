extends Control
## Окно дерева талантов: перетаскивание, зум (щипок/колёсико/кнопки), поиск и фильтры, ранги узлов (+/−),
## ветви-специализации классов и путей превращения, пассивы и модификаторы умений, сброс с подтверждением.

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
var zoom := 0.5
var offset := Vector2.ZERO   # смещение центра дерева относительно центра области
var font: Font
var _touches := {}
var _pinch := 0.0
var _press_pos := Vector2.ZERO
var _dragged := false
var refund_btn: Button
var reset_btn: Button
var search: LineEdit
var filter := "all"
var filter_btns := {}
var matches: Array = []
var _match_i := -1
var _reset_armed := 0.0
const ZOOM_MIN := 0.12
const ZOOM_MAX := 1.8
const FILTERS := [["all", "Все"], ["avail", "Можно"], ["key", "Ключевые"], ["fx", "Пассивы"], ["has", "Изучено"]]

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
	UIK.place(info, 0.04, 0.47, 0.96, 0.86)
	info_title = UIK.label(info, "Выберите узел", 32, UIK.ACCENT)
	UIK.place(info_title, 0.05, 0.76, 0.95, 0.97)
	info_body = UIK.rich(info, "Двигайте дерево пальцем, приближайте двумя пальцами.", 23)
	UIK.place(info_body, 0.05, 0.22, 0.95, 0.78)
	info_body.scroll_active = true
	info_body.mouse_filter = Control.MOUSE_FILTER_PASS
	learn_btn = UIK.button(info, "Изучить", _learn, UIK.GREEN, 28)
	learn_btn.name = "Learn"
	UIK.place(learn_btn, 0.05, 0.03, 0.62, 0.19)
	refund_btn = UIK.button(info, "−1 ранг", _refund, Color(0.45, 0.25, 0.18), 24)
	refund_btn.name = "Refund"
	UIK.place(refund_btn, 0.65, 0.03, 0.95, 0.19)
	UIK.place(UIK.label(side, "Пути превращения", 30, UIK.ACCENT, HORIZONTAL_ALIGNMENT_CENTER), 0, 0.415, 1, 0.465)
	var ap := Control.new(); side.add_child(ap)
	UIK.place(ap, 0.02, 0.135, 0.98, 0.415)
	asc_list = UIK.scroll_list(ap, 8)
	reset_btn = UIK.button(side, "Сброс", _reset, Color(0.45, 0.18, 0.15), 24)
	UIK.place(reset_btn, 0.04, 0.02, 0.36, 0.12)
	_build_tools()
	UIK.place(UIK.button(side, "Закрыть", _close, UIK.BUTTON, 30), 0.4, 0.02, 0.96, 0.12)
	var start: Dictionary = DB.tree_nodes[DB.start_node(data["class"])]
	offset = -start["pos"] * zoom
	refresh()

## Поиск, фильтры и кнопки зума поверх области дерева (удобно на телефоне)
func _build_tools() -> void:
	var bar := HBoxContainer.new(); bar.add_theme_constant_override("separation", 8)
	canvas.add_child(bar)
	UIK.place(bar, 0.01, 0.91, 0.99, 0.99)
	search = LineEdit.new()
	search.placeholder_text = "Поиск: имя или эффект…"
	search.add_theme_font_size_override("font_size", 24)
	search.custom_minimum_size = Vector2(260, 0)
	search.text_changed.connect(func(_t): _update_matches())
	search.text_submitted.connect(func(_t): find_next())
	bar.add_child(search)
	var fb := UIK.button(bar, "Найти", find_next, UIK.BUTTON, 22, "magnifying-glass")
	fb.custom_minimum_size.x = 160
	for f in FILTERS:
		var b := UIK.button(bar, f[1], set_filter.bind(f[0]), Color(0.22, 0.2, 0.26), 20)
		b.custom_minimum_size.x = 136
		filter_btns[f[0]] = b
	var zb := VBoxContainer.new(); zb.add_theme_constant_override("separation", 8)
	canvas.add_child(zb)
	UIK.place(zb, 0.01, 0.02, 0.08, 0.36)
	for z in [["+", func(): _zoom_at(1.25, canvas.size / 2)], ["−", func(): _zoom_at(0.8, canvas.size / 2)], ["⌂", center_on_start]]:
		var b := UIK.button(zb, z[0], z[1], Color(0.25, 0.23, 0.3), 34)
		b.custom_minimum_size = Vector2(80, 80)
	set_filter("all")

func set_filter(f: String) -> void:
	filter = f
	for k in filter_btns: filter_btns[k].modulate = Color(1.3, 1.2, 0.8) if k == f else Color(1, 1, 1)
	_update_matches()

func _node_match(id: int) -> bool:
	var n: Dictionary = DB.tree_nodes[id]
	match filter:
		"avail": if not DB.can_allocate(data, id): return false
		"key": if n["type"] != "keystone": return false
		"fx": if (n["fx"] as Dictionary).is_empty(): return false
		"has": if not DB.has_talent(data, id): return false
	var q := search.text.strip_edges().to_lower() if search else ""
	if q == "": return true
	var hay: String = (str(n["name"]) + " " + str(n["desc"]) + " " + str(n["branch_name"])).to_lower()
	for m in n["mods"]: hay += " " + DB.describe_mod(m).to_lower()
	for k in n["fx"]: hay += " " + DB.describe_fx(k, float(n["fx"][k])).to_lower()
	return q in hay

func _update_matches() -> void:
	matches.clear(); _match_i = -1
	if filter == "all" and (search == null or search.text.strip_edges() == ""):
		canvas.queue_redraw(); return
	for id in DB.tree_order:
		if _node_match(id): matches.append(id)
	canvas.queue_redraw()

func _filtering() -> bool:
	return not (filter == "all" and (search == null or search.text.strip_edges() == ""))

## Следующее совпадение поиска: выбрать и показать по центру
func find_next() -> void:
	if matches.is_empty() or _match_i < 0: _update_matches()
	if matches.is_empty():
		Game.toast("Ничего не найдено", 1.2); return
	_match_i = (_match_i + 1) % matches.size()
	var id: int = matches[_match_i]
	selected = id
	offset = -DB.tree_nodes[id]["pos"] * zoom
	_clamp()
	refresh()

func center_on_start() -> void:
	offset = -DB.tree_nodes[DB.start_node(data["class"])]["pos"] * zoom
	canvas.queue_redraw()

func refresh() -> void:
	points_label.text = "[center]Свободных очков: [b]%d[/b]  (вложено %d)[/center]" % [DB.free_points(data), DB.spent_points(data)]
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
	var filt := _filtering()
	for id in DB.tree_order:
		var n: Dictionary = DB.tree_nodes[id]
		var p := _to_screen(n["pos"])
		var r := _node_radius(n) * zoom
		if p.x < -60 or p.y < -60 or p.x > canvas.size.x + 60 or p.y > canvas.size.y + 60: continue
		var has := DB.has_talent(data, id)
		var rk := DB.rank(data, id)
		var mr := int(n["max_rank"])
		var avail := DB.can_allocate(data, id)
		var rc := _region_color(n["region"])
		if n["type"] == "mod": rc = Color(0.3, 0.85, 0.8)
		var ring := Color.WHITE if id == selected else (UIK.ACCENT if has else (Color(0.6, 0.6, 0.6) if avail else Color(0.1, 0.1, 0.12)))
		var fill := rc.lerp(Color.WHITE, 0.25) if has else (rc.darkened(0.35) if avail else Color(0.18, 0.18, 0.2))
		if n["req_asc"] != "" and data["ascendancy"] != n["req_asc"]: fill = fill.darkened(0.4)
		if filt and not matches.has(id):
			ring.a = 0.2; fill.a = 0.2
		elif filt:
			canvas.draw_arc(p, r + 12 * zoom + 4, 0, TAU, 32, Color(1, 0.95, 0.4, 0.9), 3.0)
		if n["type"] == "mod":
			var d := r + 5 * zoom
			canvas.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0)]), ring)
			canvas.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)]), fill)
		else:
			canvas.draw_circle(p, r + 5 * zoom, ring)
			canvas.draw_circle(p, r, fill)
		if has and avail and mr > 1:   # можно поднять ранг
			canvas.draw_arc(p, r + 9 * zoom, 0, TAU, 24, Color(0.5, 1, 0.5, 0.8), 2.0)
		if mr > 1:
			# ранг: дуга-прогресс вокруг узла всегда; число — только если помещается внутри узла
			var dim := filt and not matches.has(id)
			canvas.draw_arc(p, r + 2.0 * zoom + 1.5, -PI / 2, -PI / 2 + TAU, 28, Color(0, 0, 0, 0.5), maxf(2.0, 3.0 * zoom))
			if rk > 0: canvas.draw_arc(p, r + 2.0 * zoom + 1.5, -PI / 2, -PI / 2 + TAU * float(rk) / mr, 28, Color(1, 0.9, 0.45, 0.25 if dim else 1.0), maxf(2.0, 3.0 * zoom))
			var rt := "%d/%d" % [rk, mr]
			var rfs := clampi(int(r * 0.78), 8, 24)
			var rw := font.get_string_size(rt, HORIZONTAL_ALIGNMENT_LEFT, -1, rfs).x
			if rw <= r * 1.8 - 2 and rfs >= 10 and not dim:
				var rp := p + Vector2(-rw / 2, rfs * 0.36)
				canvas.draw_string_outline(font, rp, rt, HORIZONTAL_ALIGNMENT_LEFT, -1, rfs, 3, Color.BLACK)
				canvas.draw_string(font, rp, rt, HORIZONTAL_ALIGNMENT_LEFT, -1, rfs, Color(1, 1, 0.85) if rk > 0 else Color(0.75, 0.75, 0.75))
	# подписи: масштабируются с зумом, раскладываются без наложений (смещение / выноска)
	for lb in layout_labels():
		if lb.leader:
			canvas.draw_line(lb.anchor, lb.rect.get_center(), Color(1, 1, 1, 0.35), 1.5, true)
		var c: Color = lb.color
		if lb.kind != "region":
			canvas.draw_string_outline(font, lb.pos, lb.text, HORIZONTAL_ALIGNMENT_LEFT, -1, lb.fs, maxi(3, lb.fs / 4), Color.BLACK)
		canvas.draw_string(font, lb.pos, lb.text, HORIZONTAL_ALIGNMENT_LEFT, -1, lb.fs, c)

## Размер шрифта подписи: растёт с зумом, но в читаемых пределах
func label_fs(base: float) -> int:
	return clampi(int(base * zoom), 13, 34)

## Какие подписи видны на этом зуме: далеко — регионы и классы, ближе — ключевые и ветви, ещё ближе — особые и модификаторы, вплотную — все
func _label_tier(n: Dictionary) -> int:
	match n["type"]:
		"start": return 0
		"keystone": return 1
		"notable", "mod": return 2
	return 3

func _tier_visible(t: int) -> bool:
	match t:
		0: return true
		1: return zoom >= 0.32
		2: return zoom >= 0.62
	return zoom >= 1.15

## Раскладка подписей: кандидаты по приоритету; для каждой — позиции вокруг узла (снизу, сверху, справа, слева,
## наружу по радиусу, затем дальше с выноской). Подпись не ставится поверх уже поставленной; если места нет — скрыта.
func layout_labels() -> Array:
	var out: Array = []
	var placed: Array[Rect2] = []
	var view := Rect2(Vector2.ZERO, canvas.size).grow(40)
	var filt := _filtering()
	# 1) названия регионов — крупно, на своих местах
	for rid in DB.tree_regions:
		var key := DB.keystone_of(rid)
		if key.is_empty(): continue
		var kp: Vector2 = key["pos"]
		var dir := kp.normalized()
		var t: String = DB.tree_regions[rid]["name"].to_upper()
		var fs := clampi(int(54 * zoom), 16, 40)
		var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var c: Color = DB.tree_regions[rid]["color"].lightened(0.3); c.a = 0.6
		var ctr := _to_screen(kp * 0.6 + Vector2(-dir.y, dir.x) * 230)
		var rect := Rect2(ctr - Vector2(w / 2, fs * 0.8), Vector2(w, fs))
		if not view.intersects(rect): continue
		if _free(rect, placed):
			placed.append(rect.grow(4))
			out.append({"text": t, "fs": fs, "pos": Vector2(rect.position.x, rect.position.y + fs * 0.8), "rect": rect, "color": c, "kind": "region", "leader": false, "anchor": ctr, "id": -1})
	# 2) узлы
	var cands: Array = []
	for id in DB.tree_order:
		var n: Dictionary = DB.tree_nodes[id]
		var t := _label_tier(n)
		var bname: String = n["branch_name"]
		var show_node: bool = _tier_visible(t) or id == selected or (filt and matches.has(id) and zoom >= 0.32)
		var show_branch: bool = bname != "" and zoom >= 0.32
		if not show_node and not show_branch: continue
		var p := _to_screen(n["pos"])
		if not view.has_point(p): continue
		if show_branch: cands.append([0.5, id, bname, label_fs(24), Color(0.95, 0.85, 0.55), "branch"])
		if show_node:
			var nm: String = DB.CLASSES[n["class"]].name if n["type"] == "start" else n["name"]
			if n["type"] == "start" or bname != nm:
				var pr := float(t)
				if id == selected: pr = -1.0
				cands.append([pr, id, nm, label_fs([32, 28, 24, 21][t]), Color.WHITE, "node"])
	cands.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	# занятые узлами круги (чтобы подпись не закрывала узлы)
	var discs: Array = []
	for id in DB.tree_order:
		var n: Dictionary = DB.tree_nodes[id]
		var p := _to_screen(n["pos"])
		if view.has_point(p): discs.append([p, _node_radius(n) * zoom + 5 * zoom + 2])
	for c in cands:
		var id: int = c[1]
		var n: Dictionary = DB.tree_nodes[id]
		var p := _to_screen(n["pos"])
		var r := _node_radius(n) * zoom + 6 * zoom + 3
		var fs: int = c[3]
		var w := font.get_string_size(c[2], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var h := float(fs)
		var radial: Vector2 = (n["pos"] as Vector2).normalized() if (n["pos"] as Vector2).length() > 1 else Vector2.DOWN
		var opts: Array = []
		if c[5] == "branch":
			# подпись ветви — по направлению к центру дерева (внутрь), чтобы не спорить с именем узла
			for k in [1.0, 1.8, 2.8]: opts.append([p - radial * (r + h * k) - Vector2(0, -h * 0.1), k > 1.0])
		else:
			opts.append([p + Vector2(0, r + h * 0.55), false])          # снизу
			opts.append([p - Vector2(0, r + h * 0.55), false])          # сверху
			opts.append([p + Vector2(r + w / 2 + 4, 0), false])         # справа
			opts.append([p - Vector2(r + w / 2 + 4, 0), false])         # слева
			for k in [1.0, 2.0, 3.2]: opts.append([p + radial * (r + h * 0.6 + w * 0.3 + k * h), k > 1.0])
		var best = null; var best_pen := INF
		for o in opts:
			var ctr: Vector2 = o[0]
			var rect := Rect2(ctr - Vector2(w / 2, h / 2), Vector2(w, h))
			if not _free(rect, placed): continue
			var pen := 0.0
			for d in discs:
				if d[0].distance_to(p) < 0.5: continue
				if _rect_hits_circle(rect, d[0], d[1]): pen += 1.0
			if o[1]: pen += 0.6
			if pen < best_pen: best_pen = pen; best = [rect, o[1]]
			if pen == 0.0: break
		if best == null: continue
		var rect: Rect2 = best[0]
		placed.append(rect.grow(2))
		out.append({"text": c[2], "fs": fs, "pos": Vector2(rect.position.x, rect.position.y + h * 0.8), "rect": rect, "color": c[4], "kind": c[5], "leader": best[1], "anchor": p, "id": id})
	return out

func _free(rect: Rect2, placed: Array[Rect2]) -> bool:
	for q in placed:
		if q.intersects(rect): return false
	return true

static func _rect_hits_circle(rect: Rect2, c: Vector2, rad: float) -> bool:
	var q := Vector2(clampf(c.x, rect.position.x, rect.end.x), clampf(c.y, rect.position.y, rect.end.y))
	return q.distance_to(c) < rad

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
	var nz := clampf(zoom * k, ZOOM_MIN, ZOOM_MAX)
	var tree_pt := (at - canvas.size / 2 - offset) / zoom
	zoom = nz
	offset = at - canvas.size / 2 - tree_pt * zoom
	_clamp()
	canvas.queue_redraw()

func _clamp() -> void:
	var lim := 2600 * zoom
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
	var t := DB.describe_node(data, id) + "\n"
	var blk := DB.alloc_block(data, id)
	var has := DB.has_talent(data, id)
	if has and blk == "Максимальный ранг": t += "[color=#7fd87f]Изучено полностью[/color]"
	elif blk == "": t += "[color=#e6c27a]%s[/color]" % ("Можно поднять ранг" if has else "Можно изучить")
	else: t += "[color=#999]%s[/color]" % blk
	var col: Color = {"keystone": Color(1, 0.6, 0.25), "notable": UIK.ACCENT, "mod": Color(0.4, 0.95, 0.9)}.get(n["type"], UIK.TEXT)
	var ic: String = {"keystone": "aura", "notable": "crystal-ball", "start": "swords-emblem", "mod": "magic-swirl"}.get(n["type"], "gem-pendant")
	tip = UIK.tooltip(self, title, t.strip_edges(), ic, col, 440)
	UIK.place_tooltip(tip, Rect2(at - Vector2(30, 30), Vector2(60, 60)), get_viewport_rect().size)

func _update_info() -> void:
	if selected < 0:
		learn_btn.visible = false
		return
	var n: Dictionary = DB.tree_nodes[selected]
	var type_name: String = {"keystone": "Ключевой пассив", "notable": "Особый талант", "start": "Стартовая точка", "mod": "Модификатор умений"}.get(n["type"], "Малый талант")
	if n["gate"]: type_name = "Ворота превращения"
	info_title.text = ("Начало: " + DB.CLASSES[n["class"]].name) if n["type"] == "start" else n["name"]
	var where := ""
	if DB.tree_regions.has(n["region"]): where = " · " + DB.tree_regions[n["region"]]["name"]
	var t := "[i]%s%s[/i]\n" % [type_name, where]
	t += DB.describe_node(data, selected) + "\n"
	if n["gate"]:
		var a := DB.get_asc(n["region"])
		if not a.is_empty(): t += "\nОткрывает путь: [b]%s[/b]" % a["name"]
	info_body.text = t
	var has := DB.has_talent(data, selected)
	var blk := DB.alloc_block(data, selected)
	learn_btn.visible = n["type"] != "start" and blk != "Максимальный ранг"
	learn_btn.disabled = blk != ""
	refund_btn.visible = has and n["type"] != "start"
	refund_btn.disabled = DB.refund_block(data, selected) != ""
	UIK.place(info_body, 0.05, 0.22 if (learn_btn.visible or refund_btn.visible) else 0.04, 0.95, 0.78)
	if blk == "": learn_btn.text = ("+1 ранг (%d/%d)" % [DB.rank(data, selected) + 1, int(n["max_rank"])]) if has else "Изучить"
	else: learn_btn.text = blk
	if refund_btn.disabled and has: info_body.text += "\n[color=#999]Вернуть: %s[/color]" % DB.refund_block(data, selected)

func _build_asc_list() -> void:
	UIK.clear(asc_list)
	var order: Array = DB.ASCENDANCIES.filter(func(x): return str(x.get("cls", data["class"])) == str(data["class"]))   # пути поддержки — только своего класса
	order.sort_custom(func(x, y): return _asc_rank(x) < _asc_rank(y))
	for a in order:
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
		var lbl := UIK.rich(h, "[b]%s[/b]%s  [font_size=20](%d очк.)[/font_size]\n[font_size=20]%s[/font_size]" % [a["name"], "  [color=#7fe07f][font_size=20]поддержка[/font_size][/color]" if a.get("support", false) else "", pts, status], 26)
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

func _asc_rank(a: Dictionary) -> int:
	if data["ascendancy"] == a["id"]: return 0
	if DB.asc_block_reason(data, a) == "": return 1
	if a.has("cls") and a["cls"] == data["class"]: return 2
	return 3 + DB.ASCENDANCIES.find(a)

func _asc_info(a: Dictionary) -> void:
	selected = -1
	info_title.text = a["name"]
	var sk := "Умение: %s — %s" % [a["skill"]["name"], a["skill"]["desc"]]
	for x in a.get("skills_extra", []): sk += "\n• %s (%d ур.) — %s" % [x.name, int(x.get("lvl", 1)), x.desc]
	info_body.text = "%s\n\n%s\nТребуется: %d ур., ключевой талант региона и %d очков в нём.\nУмения пути изучаются за очки умений и ставятся в любой слот вручную." % [
		a["desc"], sk, DB.ASC_LEVEL, DB.ASC_REGION_POINTS]
	learn_btn.visible = false
	UIK.place(info_body, 0.05, 0.04, 0.95, 0.78)
	canvas.queue_redraw()

func _ascend(a: Dictionary) -> void:
	data["ascendancy"] = a["id"]
	zone.apply_character_changes(true)
	Game.toast("Вы стали: %s! Новые умения пути — изучите их в окне «Умения»" % a["name"], 4.0)
	refresh()

func _learn() -> void:
	if DB.allocate(data, selected):
		zone.apply_character_changes(false)
	refresh()

func _refund() -> void:
	if DB.refund(data, selected):
		zone.apply_character_changes(false)
	refresh()

func _process(delta: float) -> void:
	if _reset_armed > 0:
		_reset_armed -= delta
		if _reset_armed <= 0: reset_btn.text = "Сброс"

## Полный сброс (возврат всех очков, путь превращения отменяется) — по второму нажатию
func _reset() -> void:
	if _reset_armed <= 0:
		_reset_armed = 3.0
		reset_btn.text = "Точно?"
		Game.toast("Нажмите «Сброс» ещё раз: все очки вернутся, путь превращения отменится", 3.0)
		return
	_reset_armed = 0
	reset_btn.text = "Сброс"
	var had: bool = data["ascendancy"] != ""
	DB.reset_talents(data)
	zone.apply_character_changes(had)
	Game.toast("Таланты сброшены")
	refresh()

func _close() -> void:
	zone.save()
	zone.hud.close_window()
