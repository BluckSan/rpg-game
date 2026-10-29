extends Control
class_name ItemGrid
## Сетка предметов: ячейки с рамкой по редкости, 3D-иконкой, уровнем (красным, если не хватает),
## замком для чужого класса и галочкой выбора. Выбор: ПК — клик / Shift (диапазон) / Ctrl (переключить);
## телефон — режим «Выбор» (касание переключает). Двойной клик/касание — действие по умолчанию.

signal focused(it)               # предмет для подсказки (клик)
signal hovered(it)               # наведение мыши (null — ушли)
signal activated(it)             # двойной клик
signal selection_changed()

const CELL := 104.0
var data: Dictionary             # персонаж (для требований)
var source: Array = []           # исходный список (ссылка)
var view: Array = []             # отфильтрованный и отсортированный
var cap := 40                    # число ячеек (пустые рисуются)
var sort_by := "rarity"
var filter := "all"
var select_mode := false         # режим касаний: касание = выбрать
var selected := {}               # uid -> true
var focus_uid := ""
var extra_cells: Array = []      # особые ячейки в начале (зелье у торговца): {id, icon, color, label}
var price_fn: Callable           # подпись цены в ячейке (торговец)
var sc: ScrollContainer
var grid: GridContainer
var _anchor := -1                # начало диапазона для Shift
var _last_click := {"uid": "", "t": 0}
var cells := {}                  # uid -> Control (для тестов)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	sc = ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(sc); UIK.full(sc)
	grid = GridContainer.new()
	grid.add_theme_constant_override("h_separation", 6); grid.add_theme_constant_override("v_separation", 6)
	sc.add_child(grid)
	var ds := DragScroll.new(); ds.name = "DragScroll"
	sc.add_child(ds)
	resized.connect(_relayout)

func setup(c: Dictionary, lst: Array, n_cells: int) -> void:
	data = c; source = lst; cap = n_cells

func _relayout() -> void:
	if grid: grid.columns = maxi(3, int((size.x - 14) / (CELL + 6)))

func uids() -> Array: return selected.keys()
func count() -> int: return selected.size()
func clear_selection() -> void:
	selected.clear(); _anchor = -1; refresh(); selection_changed.emit()

func set_selection(lst: Array) -> void:
	selected.clear()
	for u in lst: selected[str(u)] = true
	refresh(); selection_changed.emit()

func select_all() -> void:
	var a := []
	for it in view: a.append(str(it.uid))
	set_selection(a)

func focused_item():
	return Items.find_uid(source, focus_uid) if focus_uid != "" else null

func refresh() -> void:
	if grid == null: return
	_relayout()
	view = []
	for it in Items.sorted(source, sort_by):
		if Items.passes(data, it, filter): view.append(it)
	# убрать выбранные, которых больше нет
	for u in selected.keys():
		if Items.find_uid(source, u) == null: selected.erase(u)
	if focus_uid != "" and Items.find_uid(source, focus_uid) == null: focus_uid = ""
	for ch in grid.get_children(): grid.remove_child(ch); ch.queue_free()
	cells.clear()
	for e in extra_cells: _extra_cell(e)
	for i in view.size(): _cell(view[i], i)
	var empty := cap - source.size() if filter == "all" else 0
	for i in maxi(0, empty): _empty_cell()

func _frame(col: Color, sel: bool, foc: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(col.r * 0.22, col.g * 0.22, col.b * 0.22, 0.95)
	s.border_color = UIK.ACCENT.lightened(0.3) if sel else (col if not foc else col.lightened(0.45))
	var w := 5 if sel or foc else 3
	s.border_width_left = w; s.border_width_right = w; s.border_width_top = w; s.border_width_bottom = w
	s.corner_radius_top_left = 10; s.corner_radius_top_right = 10; s.corner_radius_bottom_left = 10; s.corner_radius_bottom_right = 10
	s.shadow_color = Color(col.r, col.g, col.b, 0.35 if foc else 0.0); s.shadow_size = 6 if foc else 0
	return s

func _base_cell() -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(CELL, CELL)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	grid.add_child(b)
	return b

func _set_styles(b: Button, st: StyleBox) -> void:
	for k in ["normal", "hover", "pressed", "disabled"]: b.add_theme_stylebox_override(k, st)

func _cell(it: Dictionary, idx: int) -> void:
	var b := _base_cell()
	b.name = "Cell_" + str(it.uid)
	cells[str(it.uid)] = b
	var col := Items.rarity_color(it)
	var sel := selected.has(str(it.uid))
	_set_styles(b, _frame(col, sel, str(it.uid) == focus_uid))
	var why := Items.equip_block(data, it)
	var ir := TextureRect.new()
	ir.texture = UIK.icon(UIK.item_icon(it, data["class"]))
	ir.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ir.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ir.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(ir); UIK.full(ir); ir.offset_left = 10; ir.offset_top = 8; ir.offset_right = -10; ir.offset_bottom = -14
	if why != "": ir.modulate = Color(1, 0.6, 0.6, 0.85)
	var lv := UIK.label(b, str(int(it.get("req", it.ilvl))), 20, Color(1, 0.35, 0.35) if int(it.get("req", 1)) > int(data["level"]) else UIK.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	lv.autowrap_mode = TextServer.AUTOWRAP_OFF
	lv.add_theme_color_override("font_outline_color", Color.BLACK); lv.add_theme_constant_override("outline_size", 5)
	lv.anchor_left = 0; lv.anchor_right = 1; lv.anchor_top = 1; lv.anchor_bottom = 1
	lv.offset_left = 4; lv.offset_right = -8; lv.offset_top = -30; lv.offset_bottom = -2
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if it.get("cls", "") != "" and it.cls != data["class"]:
		var lk := UIK.icon_rect(b, "cursed-star", 24, Color(1, 0.4, 0.4)); lk.position = Vector2(6, 6)
	elif it.get("set", "") != "":
		var st := UIK.label(b, "◆", 20, DB.RARITY_COLORS[Items.SET_RARITY]); st.position = Vector2(8, 2); st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if price_fn.is_valid():
		var pl := UIK.label(b, str(price_fn.call(it)), 18, Color(1, 0.85, 0.4))
		pl.autowrap_mode = TextServer.AUTOWRAP_OFF
		pl.add_theme_color_override("font_outline_color", Color.BLACK); pl.add_theme_constant_override("outline_size", 5)
		pl.position = Vector2(8, CELL - 30); pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if sel:
		var ck := UIK.label(b, "✔", 26, UIK.ACCENT.lightened(0.3), HORIZONTAL_ALIGNMENT_RIGHT)
		ck.anchor_left = 0; ck.anchor_right = 1; ck.offset_right = -6; ck.offset_top = 0
		ck.add_theme_color_override("font_outline_color", Color.BLACK); ck.add_theme_constant_override("outline_size", 6)
		ck.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.pressed.connect(_on_cell.bind(str(it.uid), idx))
	# v0.9.3 (ПК): снаряжение можно перетащить на панель ярлыков (щелчок по ярлыку — надеть)
	if Game.desktop and it.has("slot"):
		var ic: Texture2D = UIK.icon(UIK.item_icon(it, str(data.get("class", "warrior")) if data else "warrior"))
		var uid := str(it.uid)
		b.set_drag_forwarding(func(_p):
			var pv := TextureRect.new(); pv.texture = ic; pv.size = Vector2(64, 64); pv.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			b.set_drag_preview(pv)
			return {"item": uid}, Callable(), Callable())
	b.mouse_entered.connect(func(): hovered.emit(it))
	b.mouse_exited.connect(func(): hovered.emit(null))

func _extra_cell(e: Dictionary) -> void:
	var b := _base_cell()
	b.name = "Cell_" + str(e.id)
	_set_styles(b, _frame(e.color, false, focus_uid == str(e.id)))
	var ir := UIK.icon_rect(b, e.icon, CELL - 28, e.color); ir.position = Vector2(14, 8)
	if e.has("label"):
		var l := UIK.label(b, e.label, 18, Color(1, 0.85, 0.4)); l.position = Vector2(8, CELL - 30)
		l.add_theme_color_override("font_outline_color", Color.BLACK); l.add_theme_constant_override("outline_size", 5)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.pressed.connect(func():
		if DragScroll.dragging: return
		focus_uid = str(e.id); refresh(); focused.emit(e))

func _empty_cell() -> void:
	var b := _base_cell()
	b.disabled = true
	var s := StyleBoxFlat.new(); s.bg_color = Color(0.08, 0.07, 0.06, 0.7)
	s.border_color = Color(0.3, 0.26, 0.2, 0.6)
	s.border_width_left = 2; s.border_width_right = 2; s.border_width_top = 2; s.border_width_bottom = 2
	s.corner_radius_top_left = 10; s.corner_radius_top_right = 10; s.corner_radius_bottom_left = 10; s.corner_radius_bottom_right = 10
	_set_styles(b, s)

## Клик по ячейке: модификаторы ПК или режим выбора
func _on_cell(uid: String, idx: int) -> void:
	if DragScroll.dragging: return
	Game.sfx("click")
	var shift := Input.is_key_pressed(KEY_SHIFT)
	var ctrl := Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)
	click(uid, shift, ctrl)

func click(uid: String, shift := false, ctrl := false) -> void:
	var idx := -1
	for i in view.size(): if str(view[i].uid) == uid: idx = i
	if idx < 0: return
	var now := Time.get_ticks_msec()
	var dbl: bool = _last_click.uid == uid and now - int(_last_click.t) < 380 and not shift and not ctrl
	_last_click = {"uid": uid, "t": now}
	if shift and _anchor >= 0:
		for i in range(mini(_anchor, idx), maxi(_anchor, idx) + 1): selected[str(view[i].uid)] = true
		selection_changed.emit()
	elif ctrl or select_mode:
		if selected.has(uid): selected.erase(uid)
		else: selected[uid] = true
		_anchor = idx
		selection_changed.emit()
	else:
		if not selected.is_empty():
			selected.clear(); selection_changed.emit()
		_anchor = idx
	focus_uid = uid
	refresh()
	focused.emit(view[idx])
	if dbl and not select_mode: activated.emit(view[idx])
