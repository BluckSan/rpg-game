extends CanvasLayer
class_name ShortcutBars
## v0.9.3: панели ярлыков в стиле Lineage 2 (только ПК). Три панели:
##  1 — клавиши 1…0 (10 ячеек), 2 — F1…F12 (12 ячеек), 3 — без клавиш (по щелчку), у каждой 5 страниц.
## В ячейку перетаскиваются умения (окно «Умения»), вещи (инвентарь: щелчок — надеть), зелье, ярлыки с других ячеек.
## Панели двигаются за ручку (если не закреплены), поворачиваются (горизонтально/вертикально), страницы — ▲▼ или «[» «]».
## Раскладка и содержимое хранятся в user://ui_<герой>.cfg. Клавиши — из настроек управления (переназначаются).

const PAGES := 5
const SIZES := [10, 12, 12]
const CELL := 62.0
const GAP := 4.0
const PATH_FMT := "user://ui_%s.cfg"

var hud
var player
var data: Dictionary
var root: Control
var panels: Array = []        # Control на панель
var slots: Array = []         # [bar] -> Array[ShortcutSlot]
var pages := [0, 0, 0]
var vertical := [false, false, true]
var shown := [true, true, false]
var pos: Array = []           # Vector2 на панель
var locked := false
var sc: Array = []            # [bar][page][slot] -> Dictionary
var _drag_bar := -1
var _drag_off := Vector2.ZERO
var _tip_t := 0.0

func setup(h) -> void:
	hud = h; player = h.player; data = h.zone.data
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new(); root.set_anchors_preset(Control.PRESET_FULL_RECT); root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	for b in 3:
		var pg := []
		for p in PAGES:
			var row := []
			for i in SIZES[b]: row.append({})
			pg.append(row)
		sc.append(pg)
	_defaults()
	load_cfg()
	for b in 3: _build(b)
	refresh_keys()
	refresh_all()

func _cfg_path() -> String:
	return PATH_FMT % str(data.get("name", "hero")).md5_text().left(12)

## По умолчанию: панель 1 стр. 1 — набор умений 1–8 и зелье на «9»
func _defaults() -> void:
	var lo: Array = data.get("loadout", [])
	for i in mini(8, lo.size()):
		if str(lo[i]) != "": sc[0][0][i] = {"k": "skill", "id": str(lo[i])}
	sc[0][0][8] = {"k": "potion"}
	var vs := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1920, 1080)
	pos = [Vector2(vs.x / 2 - _len(0) / 2, vs.y - CELL - 46), Vector2(vs.x / 2 - _len(1) / 2, vs.y - 2 * CELL - 60), Vector2(vs.x - CELL - 70, vs.y * 0.3)]

func _len(b: int) -> float: return SIZES[b] * (CELL + GAP) + 40.0

func load_cfg() -> void:
	var cf := ConfigFile.new()
	if cf.load(_cfg_path()) != OK: return
	locked = bool(cf.get_value("bars", "locked", false))
	for b in 3:
		pos[b] = cf.get_value("bars", "pos%d" % b, pos[b])
		vertical[b] = bool(cf.get_value("bars", "vert%d" % b, vertical[b]))
		shown[b] = bool(cf.get_value("bars", "shown%d" % b, shown[b]))
		pages[b] = clampi(int(cf.get_value("bars", "page%d" % b, 0)), 0, PAGES - 1)
		var saved = cf.get_value("bars", "sc%d" % b, null)
		if saved is Array and saved.size() == PAGES:
			for p in PAGES:
				if saved[p] is Array and saved[p].size() == SIZES[b]: sc[b][p] = saved[p]

func save_cfg() -> void:
	var cf := ConfigFile.new()
	cf.load(_cfg_path())
	cf.set_value("bars", "locked", locked)
	for b in 3:
		cf.set_value("bars", "pos%d" % b, pos[b]); cf.set_value("bars", "vert%d" % b, vertical[b])
		cf.set_value("bars", "shown%d" % b, shown[b]); cf.set_value("bars", "page%d" % b, pages[b])
		cf.set_value("bars", "sc%d" % b, sc[b])
	cf.save(_cfg_path())

# ---------- построение ----------
func _build(b: int) -> void:
	var p := Panel.new(); p.name = "Bar%d" % (b + 1)
	p.add_theme_stylebox_override("panel", UIK.frame("panel_dark", Color(1, 1, 1, 0.9), 4))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(p)
	panels.append(p)
	# ручка: перетаскивание панели, номер страницы, кнопки
	var grip := Control.new(); grip.name = "Grip"; grip.mouse_filter = Control.MOUSE_FILTER_STOP
	grip.mouse_default_cursor_shape = Control.CURSOR_MOVE
	grip.gui_input.connect(_grip_input.bind(b))
	grip.draw.connect(func():
		for k in 3: grip.draw_line(Vector2(6 + k * 6, 8), Vector2(6 + k * 6, grip.size.y - 8) if not vertical[b] else Vector2(grip.size.x - 8, 6 + k * 6), Color(1, 1, 1, 0.25 if locked else 0.5), 2.0)
		if vertical[b]:
			for k in 3: pass)
	p.add_child(grip)
	var pl := UIK.label(p, "", 16, UIK.MUTED, HORIZONTAL_ALIGNMENT_CENTER); pl.name = "Page"; pl.autowrap_mode = TextServer.AUTOWRAP_OFF
	var up := _mini_btn(p, "▲", func(): page(b, -1)); up.name = "Up"
	var dn := _mini_btn(p, "▼", func(): page(b, 1)); dn.name = "Down"
	var rot := _mini_btn(p, "⟳", func(): vertical[b] = not vertical[b]; _layout(b); save_cfg()); rot.name = "Rot"
	rot.tooltip_text = "Повернуть панель (горизонтально / вертикально)"
	var lk := _mini_btn(p, "", func(): toggle_lock()); lk.name = "Lock"
	lk.tooltip_text = "Закрепить панели (нельзя сдвинуть и вытащить ярлыки)"
	var row := []
	for i in SIZES[b]:
		var s := ShortcutSlot.new(); s.bars = self; s.bar = b; s.idx = i; s.name = "S%d" % i
		s.size = Vector2(CELL, CELL)
		p.add_child(s); row.append(s)
	slots.append(row)
	_layout(b)

func _mini_btn(p: Control, t: String, cb: Callable) -> Button:
	var bt := Button.new(); bt.text = t; bt.focus_mode = Control.FOCUS_NONE
	bt.add_theme_font_size_override("font_size", 14)
	var st := UIK.box(Color(0.12, 0.14, 0.2, 0.9), 6); st.content_margin_left = 2; st.content_margin_right = 2; st.content_margin_top = 0; st.content_margin_bottom = 0
	bt.add_theme_stylebox_override("normal", st); bt.add_theme_stylebox_override("hover", UIK.box(Color(0.22, 0.26, 0.36, 0.95), 6))
	bt.add_theme_stylebox_override("pressed", UIK.box(Color(0.3, 0.24, 0.12, 0.95), 6))
	bt.pressed.connect(cb)
	p.add_child(bt)
	return bt

func _layout(b: int) -> void:
	var p: Panel = panels[b]
	var n: int = SIZES[b]
	var v: bool = vertical[b]
	var head := 34.0
	var body := n * (CELL + GAP) - GAP
	p.size = Vector2(head + body + 12, CELL + 12) if not v else Vector2(CELL + 12, head + body + 12)
	p.position = _clamp_pos(pos[b], p.size)
	var g: Control = p.get_node("Grip")
	g.position = Vector2(2, 2); g.size = Vector2(26, CELL + 8) if not v else Vector2(CELL + 8, 26)
	g.queue_redraw()
	var pl: Label = p.get_node("Page")
	pl.text = "%d" % (pages[b] + 1)
	var bw := Vector2(22, 18)
	# кнопки на ручке: ▲, номер, ▼, поворот, замок
	var items := [p.get_node("Up"), pl, p.get_node("Down"), p.get_node("Rot"), p.get_node("Lock")]
	for k in items.size():
		var c: Control = items[k]
		c.size = bw
		c.position = Vector2(5, 3 + k * 13) if not v else Vector2(3 + k * 13 + (CELL - 60) / 2, 6)
		if v: c.size = Vector2(16, 22)
		if not v: c.size = Vector2(24, 13)
		(c as Control).add_theme_font_size_override("font_size", 11)
	for i in n:
		var s: ShortcutSlot = slots[b][i]
		s.position = Vector2(6 + head + i * (CELL + GAP), 6) if not v else Vector2(6, 6 + head + i * (CELL + GAP))
		s.size = Vector2(CELL, CELL)
	p.visible = shown[b]
	(p.get_node("Lock") as Button).text = "■" if locked else "□"

func _clamp_pos(p: Vector2, sz: Vector2) -> Vector2:
	var vs := get_viewport().get_visible_rect().size
	return Vector2(clampf(p.x, 0, maxf(0, vs.x - sz.x)), clampf(p.y, 0, maxf(0, vs.y - sz.y)))

func _grip_input(ev: InputEvent, b: int) -> void:
	if locked: return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed: _drag_bar = b; _drag_off = panels[b].get_global_mouse_position() - panels[b].position
		else:
			_drag_bar = -1; save_cfg()
	elif ev is InputEventMouseMotion and _drag_bar == b:
		move_bar(b, panels[b].get_global_mouse_position() - _drag_off)

func move_bar(b: int, p: Vector2) -> void:
	pos[b] = _clamp_pos(p, panels[b].size)
	panels[b].position = pos[b]

func over(p: Vector2) -> bool:
	if root == null or not root.visible: return false
	for b in 3:
		if shown[b] and panels[b].get_global_rect().has_point(p): return true
	return false

func toggle_lock() -> void:
	locked = not locked
	for b in 3: _layout(b)
	save_cfg()
	Game.toast("Панели закреплены" if locked else "Панели можно двигать", 1.2)

func page(b: int, d: int) -> void:
	pages[b] = wrapi(pages[b] + d, 0, PAGES)
	_layout(b); refresh_bar(b); save_cfg()

func set_shown(b: int, v: bool) -> void:
	shown[b] = v; _layout(b); save_cfg()

# ---------- содержимое ----------
func get_slot(b: int, i: int) -> Dictionary: return sc[b][pages[b]][i]

func set_slot(b: int, i: int, e: Dictionary) -> void:
	sc[b][pages[b]][i] = e
	refresh_bar(b); save_cfg()

## Перетаскивание в ячейку: умение, вещь, зелье или ярлык из другой ячейки (меняются местами)
func drop(b: int, i: int, d: Dictionary) -> void:
	if d.has("sc"):
		var fb := int(d.sc[0]); var fi := int(d.sc[1])
		var a: Dictionary = sc[fb][pages[fb]][fi]
		sc[fb][pages[fb]][fi] = sc[b][pages[b]][i]
		sc[b][pages[b]][i] = a
		refresh_all(); save_cfg(); return
	if d.has("skill"):
		var id := str(d.skill)
		if id == "" or DB.find_skill(data, id) == null: return
		# умение не в наборе — ставим в свободный слот набора (ограничение 8 активных умений сохраняется)
		if _loadout_index(id) < 0:
			var lo: Array = data.get("loadout", [])
			var free := lo.find("")
			if free < 0:
				Game.toast("Набор умений полон (8): освободите слот в окне «Умения»", 2.5); return
			if not DB.set_loadout_slot(data, free, id):
				Game.toast("Умение ещё не изучено", 1.6); return
			hud.refresh_skill_buttons(); hud.zone.save()
		set_slot(b, i, {"k": "skill", "id": id})
	elif d.has("item"):
		set_slot(b, i, {"k": "item", "uid": str(d.item)})
	elif d.has("potion"):
		set_slot(b, i, {"k": "potion"})

func _loadout_index(id: String) -> int:
	var lo: Array = data.get("loadout", [])
	return lo.find(id)

func _find_item(uid: String):
	var it = Items.find_uid(data.get("inventory", []), uid)
	if it == null: it = Items.find_uid(data.get("equipped", []), uid)
	return it

## Срабатывание ячейки (щелчок или клавиша)
func activate(b: int, i: int) -> bool:
	if b < 0 or b >= 3 or i < 0 or i >= SIZES[b]: return false
	var e: Dictionary = get_slot(b, i)
	var s: ShortcutSlot = slots[b][i]
	s.flash = 0.6; s.queue_redraw()
	match str(e.get("k", "")):
		"skill":
			var li := _loadout_index(str(e.id))
			if li < 0:
				Game.toast("Умение не в наборе — поставьте его в слот в окне «Умения»", 2.0); return false
			return player.try_use(li + 1)
		"potion":
			player.use_potion(); return true
		"item":
			var it = _find_item(str(e.uid))
			if it == null: Game.toast("Предмета больше нет", 1.4); return false
			if Items.find_uid(data.get("equipped", []), str(e.uid)) != null: Game.toast("Уже надето", 1.2); return true
			var err := str(Net.inv("equip", [str(e.uid)]).err)
			if err != "": Game.toast(err, 1.6); return false
			if hud.zone.has_method("apply_character_changes"): hud.zone.apply_character_changes(false)
			refresh_all()
			Game.toast("Надето", 1.0)
			return true
	return false

func refresh_all() -> void:
	for b in 3: refresh_bar(b)

func refresh_bar(b: int) -> void:
	if b >= slots.size(): return
	(panels[b].get_node("Page") as Label).text = "%d" % (pages[b] + 1)
	for i in SIZES[b]:
		var s: ShortcutSlot = slots[b][i]
		var e: Dictionary = get_slot(b, i)
		s.empty = e.is_empty(); s.badge = ""
		match str(e.get("k", "")):
			"skill":
				var sk = DB.find_skill(data, str(e.id))
				s.icon = UIK.icon(UIK.SKILL_ICONS.get(str(e.id), "magic-swirl")); s.tint = sk.color if sk != null else Color.GRAY
			"potion":
				s.icon = UIK.icon("health-potion"); s.tint = Color(1, 0.35, 0.4); s.badge = str(int(data.get("potions", 0)))
			"item":
				var it = _find_item(str(e.uid))
				if it == null: s.empty = true; sc[b][pages[b]][i] = {}
				else: s.icon = UIK.icon(UIK.item_icon(it, data["class"])); s.tint = Items.rarity_color(it)
		s.queue_redraw()

func refresh_keys() -> void:
	for b in 3:
		for i in SIZES[b]:
			var s: ShortcutSlot = slots[b][i]
			s.key_hint = Controls.key_hint(action_for(b, i)) if action_for(b, i) != "" else ""
			s.queue_redraw()

static func action_for(b: int, i: int) -> String:
	if b == 0: return "skill_%d" % (i + 1)
	if b == 1: return "bar2_%d" % (i + 1)
	return ""

## Действие клавиши → [панель, ячейка] или []
static func slot_of_action(act: String) -> Array:
	if act.begins_with("skill_"): return [0, int(act.substr(6)) - 1]
	if act.begins_with("bar2_"): return [1, int(act.substr(5)) - 1]
	return []

var _hover: ShortcutSlot
func hover(s) -> void:
	_hover = s
	if s == null: hud._hide_tooltip(); return
	var e: Dictionary = get_slot(s.bar, s.idx)
	if str(e.get("k", "")) == "skill":
		var sk = DB.find_skill(data, str(e.id))
		if sk != null: hud._show_tooltip(sk.name, str(sk.get("desc", "")), UIK.SKILL_ICONS.get(str(e.id), "magic-swirl"), sk.color, s.get_global_rect())
	elif str(e.get("k", "")) == "item":
		var it = _find_item(str(e.uid))
		if it != null: hud._show_tooltip(str(it.get("name", "Предмет")), "Щелчок или клавиша — надеть", UIK.item_icon(it, data["class"]), Items.rarity_color(it), s.get_global_rect())

func _process(_dt: float) -> void:
	if hud == null or player == null: return
	# поверх открытых окон панели видны только во время перетаскивания (чтобы бросить ярлык в ячейку)
	var dragging := get_viewport().gui_is_dragging()
	root.visible = hud.window == null or dragging
	if not root.visible: return
	for b in 3:
		if not shown[b]: continue
		for i in SIZES[b]:
			var s: ShortcutSlot = slots[b][i]
			var e: Dictionary = get_slot(b, i)
			if str(e.get("k", "")) == "skill":
				var li := _loadout_index(str(e.id))
				if li < 0: s.set_state(0, 0, true); continue
				var mx: float = player.max_cooldown(li + 1)
				s.set_state(clampf(player.cooldowns[li + 1] / mx, 0, 1) if mx > 0 else 0.0, player.cooldowns[li + 1], player.lock_reason(li + 1) != "")
			elif str(e.get("k", "")) == "potion":
				var bd := str(int(data.get("potions", 0)))
				if s.badge != bd: s.badge = bd; s.queue_redraw()
