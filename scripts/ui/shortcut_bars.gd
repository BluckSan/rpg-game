extends CanvasLayer
class_name ShortcutBars
## v0.9.5.1: ОДНА панель ярлыков (ПК), 10 ячеек на клавишах 1…0 (переназначаются в настройках).
## В ячейку перетаскиваются умения (окно «Умения»), вещи (инвентарь), зелье и ярлыки с других ячеек.
## Панель двигается простым перетаскиванием (за рамку или пустую ячейку), если не закреплена.
## Кнопки только две: поворот (горизонтально/вертикально) и замок. Набор умений (8) синхронизирован с панелью:
## умение, выбранное в окне «Умения», сразу появляется на панели; умение, брошенное на панель, попадает в набор.
## Раскладка и содержимое — в user://ui_<герой>.cfg.

const SIZE := 10
const SIZES := [10]   # совместимость
const CELL := 62.0
const GAP := 4.0
const PATH_FMT := "user://ui_%s.cfg"

var hud
var player
var data: Dictionary
var root: Control
var panels: Array = []        # [Panel]
var slots: Array = []         # [0] -> Array[ShortcutSlot]
var vertical := false
var pos := Vector2.ZERO
var locked := false
var sc: Array = []            # [slot] -> Dictionary
var _dragging := false
var _drag_off := Vector2.ZERO
var _last_lo: Array = []

func setup(h) -> void:
	hud = h; player = h.player; data = h.zone.data
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new(); root.set_anchors_preset(Control.PRESET_FULL_RECT); root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	sc = []
	for i in SIZE: sc.append({})
	_defaults()
	load_cfg()
	_build()
	sync_loadout()
	refresh_keys()
	refresh_all()

func _cfg_path() -> String:
	return PATH_FMT % str(data.get("name", "hero")).md5_text().left(12)

## По умолчанию: умения набора 1–8 и зелье на «9»
func _defaults() -> void:
	var lo: Array = data.get("loadout", [])
	for i in mini(8, lo.size()):
		if str(lo[i]) != "": sc[i] = {"k": "skill", "id": str(lo[i])}
	sc[8] = {"k": "potion"}
	var vs := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1920, 1080)
	pos = Vector2(vs.x / 2 - _len() / 2, vs.y - CELL - 46)

func _len() -> float: return SIZE * (CELL + GAP) + 40.0

func load_cfg() -> void:
	var cf := ConfigFile.new()
	if cf.load(_cfg_path()) != OK: return
	locked = bool(cf.get_value("bars", "locked", false))
	pos = cf.get_value("bar", "pos", cf.get_value("bars", "pos0", pos))
	vertical = bool(cf.get_value("bar", "vert", cf.get_value("bars", "vert0", vertical)))
	var saved = cf.get_value("bar", "sc", null)
	if saved == null:   # миграция со старых панелей (0.9.3–0.9.5): панель 1, страница 1
		var old = cf.get_value("bars", "sc0", null)
		if old is Array and old.size() > 0 and old[0] is Array: saved = old[0]
	if saved is Array:
		for i in mini(SIZE, saved.size()):
			if saved[i] is Dictionary: sc[i] = saved[i]

func save_cfg() -> void:
	var cf := ConfigFile.new()
	cf.load(_cfg_path())
	if cf.has_section("bars"): cf.erase_section("bars")
	cf.set_value("bars", "locked", locked)
	cf.set_value("bar", "pos", pos); cf.set_value("bar", "vert", vertical)
	cf.set_value("bar", "sc", sc)
	cf.save(_cfg_path())

# ---------- построение ----------
func _build() -> void:
	var p := Panel.new(); p.name = "Bar1"
	p.add_theme_stylebox_override("panel", UIK.frame("panel_dark", Color(1, 1, 1, 0.9), 4))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.gui_input.connect(_panel_input)
	root.add_child(p)
	panels.append(p)
	var rot := _mini_btn(p, "⟳", func(): rotate_bar()); rot.name = "Rot"
	rot.tooltip_text = "Повернуть панель (горизонтально / вертикально)"
	var lk := _mini_btn(p, "", func(): toggle_lock()); lk.name = "Lock"
	lk.tooltip_text = "Закрепить панель (нельзя сдвинуть и вытащить ярлыки)"
	var row := []
	for i in SIZE:
		var s := ShortcutSlot.new(); s.bars = self; s.bar = 0; s.idx = i; s.name = "S%d" % i
		s.size = Vector2(CELL, CELL)
		p.add_child(s); row.append(s)
	slots.append(row)
	_layout()

func _mini_btn(p: Control, t: String, cb: Callable) -> Button:
	var bt := Button.new(); bt.text = t; bt.focus_mode = Control.FOCUS_NONE
	bt.add_theme_font_size_override("font_size", 18)
	var st := UIK.box(Color(0.12, 0.14, 0.2, 0.9), 6); st.content_margin_left = 0; st.content_margin_right = 0; st.content_margin_top = 0; st.content_margin_bottom = 0
	bt.add_theme_stylebox_override("normal", st); bt.add_theme_stylebox_override("hover", UIK.box(Color(0.22, 0.26, 0.36, 0.95), 6))
	bt.add_theme_stylebox_override("pressed", UIK.box(Color(0.3, 0.24, 0.12, 0.95), 6))
	bt.pressed.connect(cb)
	p.add_child(bt)
	return bt

func _layout(_b: int = 0) -> void:
	if panels.is_empty(): return
	var p: Panel = panels[0]
	var v := vertical
	var head := 30.0
	var body := SIZE * (CELL + GAP) - GAP
	p.size = Vector2(head + body + 14, CELL + 12) if not v else Vector2(CELL + 12, head + body + 14)
	pos = _clamp_pos(pos, p.size)
	p.position = pos
	var rot: Button = p.get_node("Rot"); var lk: Button = p.get_node("Lock")
	if not v:
		rot.position = Vector2(6, 6); rot.size = Vector2(26, (CELL - 4) / 2)
		lk.position = Vector2(6, 6 + (CELL + 4) / 2); lk.size = Vector2(26, (CELL - 4) / 2)
	else:
		rot.position = Vector2(6, 6); rot.size = Vector2((CELL - 4) / 2, 26)
		lk.position = Vector2(6 + (CELL + 4) / 2, 6); lk.size = Vector2((CELL - 4) / 2, 26)
	for i in SIZE:
		var s: ShortcutSlot = slots[0][i]
		s.position = Vector2(8 + head + i * (CELL + GAP), 6) if not v else Vector2(6, 8 + head + i * (CELL + GAP))
		s.size = Vector2(CELL, CELL)
	lk.text = "■" if locked else "□"
	p.mouse_default_cursor_shape = Control.CURSOR_ARROW if locked else Control.CURSOR_MOVE

func _clamp_pos(p: Vector2, sz: Vector2) -> Vector2:
	var vs := get_viewport().get_visible_rect().size
	return Vector2(clampf(p.x, 0, maxf(0, vs.x - sz.x)), clampf(p.y, 0, maxf(0, vs.y - sz.y)))

func rotate_bar() -> void:
	vertical = not vertical
	_layout(); save_cfg()

## Перетаскивание панели: ЛКМ по рамке или пустой ячейке (если не закреплена)
func begin_drag(at: Vector2) -> bool:
	if locked or panels.is_empty(): return false
	_dragging = true
	_drag_off = at - panels[0].position
	return true

func _panel_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
		if begin_drag(ev.global_position): panels[0].accept_event()
	else: drag_event(ev)

## Движение/отпускание мыши во время перетаскивания панели (из gui_input панели/ячейки и из _input)
func drag_event(ev: InputEvent) -> bool:
	if not _dragging: return false
	if ev is InputEventMouseMotion:
		move_bar(0, (ev as InputEventMouse).global_position - _drag_off); return true
	elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
		_dragging = false; save_cfg(); return true
	return false

func _input(ev: InputEvent) -> void:
	if not _dragging: return
	drag_event(ev)

func move_bar(_b: int, p: Vector2) -> void:
	pos = _clamp_pos(p, panels[0].size)
	panels[0].position = pos

func over(p: Vector2) -> bool:
	if root == null or not root.visible or panels.is_empty(): return false
	return panels[0].get_global_rect().has_point(p)

func toggle_lock() -> void:
	locked = not locked
	_dragging = false
	_layout()
	save_cfg()
	Game.toast("Панель закреплена" if locked else "Панель можно двигать", 1.2)

# ---------- содержимое ----------
func get_slot(_b: int, i: int) -> Dictionary: return sc[i]

func set_slot(_b: int, i: int, e: Dictionary) -> void:
	sc[i] = e
	refresh_all(); save_cfg()

## Перетаскивание в ячейку: умение, вещь, зелье или ярлык из другой ячейки (меняются местами)
func drop(_b: int, i: int, d: Dictionary) -> void:
	if i < 0 or i >= SIZE: return
	if d.has("sc"):
		var fi := int(d.sc[1])
		var a: Dictionary = sc[fi]
		sc[fi] = sc[i]
		sc[i] = a
		refresh_all(); save_cfg(); return
	if d.has("skill"):
		var id := str(d.skill)
		var s = DB.find_skill(data, id) if id != "" else null
		if s == null: return
		if DB.skill_lock(data, s) != "":
			Game.toast("Умение ещё не изучено", 1.6); return
		if _loadout_index(id) < 0 and not _put_in_loadout(id, i): return
		# это умение уже на панели — переносим, а не дублируем
		for k in SIZE:
			if k != i and str(sc[k].get("k", "")) == "skill" and str(sc[k].get("id", "")) == id: sc[k] = {}
		sc[i] = {"k": "skill", "id": id}
		_last_lo = (data.get("loadout", []) as Array).duplicate()
		refresh_all(); save_cfg()
	elif d.has("item"):
		set_slot(0, i, {"k": "item", "uid": str(d.item)})
	elif d.has("potion"):
		set_slot(0, i, {"k": "potion"})

## Умение не в наборе (8 активных): свободный слот набора, иначе заменяем умение из этой ячейки,
## иначе — умение набора, которого нет на панели. Возвращает успех.
func _put_in_loadout(id: String, cell: int) -> bool:
	var lo: Array = data.get("loadout", [])
	var slot := lo.find("")
	if slot < 0 and str(sc[cell].get("k", "")) == "skill": slot = lo.find(str(sc[cell].get("id", "")))
	if slot < 0:
		for k in lo.size():
			if not _on_bar(str(lo[k])): slot = k; break
	if slot < 0:
		Game.toast("Набор умений полон (8): перетащите умение на ячейку с другим умением", 2.5); return false
	if not DB.set_loadout_slot(data, slot, id):
		Game.toast("Умение ещё не изучено", 1.6); return false
	hud.refresh_skill_buttons(); hud.zone.save()
	return true

func _on_bar(id: String) -> bool:
	for e in sc:
		if str(e.get("k", "")) == "skill" and str(e.get("id", "")) == id: return true
	return false

## Набор изменили в окне «Умения» (или изучили/разучили): умение, заменённое в наборе, заменяется и на панели;
## новое умение набора, которого нет на панели, ставится в первую пустую ячейку.
func sync_loadout() -> void:
	var lo: Array = (data.get("loadout", []) as Array).duplicate()
	if lo == _last_lo: return
	var old := _last_lo
	_last_lo = lo
	for k in lo.size():
		var nid := str(lo[k])
		var oid := str(old[k]) if k < old.size() else ""
		if oid != "" and oid != nid and lo.find(oid) < 0:
			for c in SIZE:
				if str(sc[c].get("k", "")) == "skill" and str(sc[c].get("id", "")) == oid:
					sc[c] = {"k": "skill", "id": nid} if nid != "" and not _on_bar(nid) else {}
	for k in lo.size():
		var nid := str(lo[k])
		if nid == "" or _on_bar(nid): continue
		var free := -1
		if k < SIZE and sc[k].is_empty(): free = k
		if free < 0:
			for c in SIZE:
				if sc[c].is_empty(): free = c; break
		if free >= 0: sc[free] = {"k": "skill", "id": nid}
	save_cfg()

func _loadout_index(id: String) -> int:
	var lo: Array = data.get("loadout", [])
	return lo.find(id)

func _find_item(uid: String):
	var it = Items.find_uid(data.get("inventory", []), uid)
	if it == null: it = Items.find_uid(data.get("equipped", []), uid)
	return it

## Срабатывание ячейки (щелчок или клавиша)
func activate(b: int, i: int) -> bool:
	if b != 0 or i < 0 or i >= SIZE: return false
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
	refresh_bar(0)

func refresh_bar(b: int = 0) -> void:
	if b != 0 or slots.is_empty(): return
	for i in SIZE:
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
				if it == null: s.empty = true; sc[i] = {}
				else: s.icon = UIK.icon(UIK.item_icon(it, data["class"])); s.tint = Items.rarity_color(it)
		s.queue_redraw()

func refresh_keys() -> void:
	for i in SIZE:
		var s: ShortcutSlot = slots[0][i]
		s.key_hint = Controls.key_hint(action_for(0, i))
		s.queue_redraw()

static func action_for(b: int, i: int) -> String:
	if b == 0: return "skill_%d" % (i + 1)
	return ""

## Действие клавиши → [панель, ячейка] или []
static func slot_of_action(act: String) -> Array:
	if act.begins_with("skill_"): return [0, int(act.substr(6)) - 1]
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
	if lo_changed(): sync_loadout(); refresh_all()
	for b in 1:
		for i in SIZE:
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

func lo_changed() -> bool:
	return data.get("loadout", []) != _last_lo
