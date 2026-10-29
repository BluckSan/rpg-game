extends RefCounted
class_name Controls
## v0.9.0: переназначаемое управление ПК. Действия InputMap, по две привязки на действие (клавиша или кнопка мыши).
## Хранится в user://controls.cfg; конфликты (одна клавиша на двух действиях) подсвечиваются в настройках.

const PATH := "user://controls.cfg"
const MB := 1000   # коды кнопок мыши: MB + MOUSE_BUTTON_*
## [id, подпись, привязка 1, привязка 2]
const ACTIONS := [
	["move_up", "Вперёд", KEY_W, KEY_UP], ["move_down", "Назад", KEY_S, KEY_DOWN],
	["move_left", "Влево", KEY_A, KEY_LEFT], ["move_right", "Вправо", KEY_D, KEY_RIGHT],
	["attack", "Основная атака", MB + MOUSE_BUTTON_LEFT, 0],
	["skill_1", "Панель 1 · ячейка 1", KEY_1, 0], ["skill_2", "Панель 1 · ячейка 2", KEY_2, 0], ["skill_3", "Панель 1 · ячейка 3", KEY_3, 0],
	["skill_4", "Панель 1 · ячейка 4", KEY_4, 0], ["skill_5", "Панель 1 · ячейка 5", KEY_5, 0], ["skill_6", "Панель 1 · ячейка 6", KEY_6, 0],
	["skill_7", "Панель 1 · ячейка 7", KEY_7, 0], ["skill_8", "Панель 1 · ячейка 8", KEY_8, 0], ["skill_9", "Панель 1 · ячейка 9", KEY_9, 0],
	["skill_10", "Панель 1 · ячейка 10", KEY_0, 0],
	["bar2_1", "Панель 2 · ячейка 1", KEY_F1, 0], ["bar2_2", "Панель 2 · ячейка 2", KEY_F2, 0], ["bar2_3", "Панель 2 · ячейка 3", KEY_F3, 0],
	["bar2_4", "Панель 2 · ячейка 4", KEY_F4, 0], ["bar2_5", "Панель 2 · ячейка 5", KEY_F5, 0], ["bar2_6", "Панель 2 · ячейка 6", KEY_F6, 0],
	["bar2_7", "Панель 2 · ячейка 7", KEY_F7, 0], ["bar2_8", "Панель 2 · ячейка 8", KEY_F8, 0], ["bar2_9", "Панель 2 · ячейка 9", KEY_F9, 0],
	["bar2_10", "Панель 2 · ячейка 10", KEY_F10, 0], ["bar2_11", "Панель 2 · ячейка 11", KEY_F11, 0], ["bar2_12", "Панель 2 · ячейка 12", KEY_F12, 0],
	["bar_page_prev", "Панель 1: пред. страница", KEY_BRACKETLEFT, 0], ["bar_page_next", "Панель 1: след. страница", KEY_BRACKETRIGHT, 0],
	["jump", "Прыжок", KEY_SPACE, KEY_J], ["roll", "Кувырок", KEY_SHIFT, KEY_K], ["potion", "Зелье", KEY_H, KEY_Q],
	["target_next", "Следующая цель", KEY_TAB, 0], ["target_clear", "Сбросить цель", KEY_X, 0], ["target_self", "Цель — я", KEY_F, 0],
	["interact", "Взаимодействие", KEY_E, 0], ["hero", "Герой и снаряжение", KEY_I, KEY_C], ["skills", "Умения", KEY_U, KEY_P],
	["talents", "Таланты", KEY_T, KEY_N], ["map", "Карта", KEY_M, 0], ["party", "Группа", KEY_G, 0], ["chat", "Чат", KEY_ENTER, 0],
]
## Esc — всегда меню/отмена (не переназначается), чтобы нельзя было «запереть» себя в игре
static var binds := {}   # id -> [code, code]

static func defaults() -> Dictionary:
	var d := {}
	for a in ACTIONS: d[a[0]] = [int(a[2]), int(a[3])]
	return d

static func label_of(id: String) -> String:
	for a in ACTIONS: if a[0] == id: return a[1]
	return id

static func load_and_apply() -> void:
	binds = defaults()
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		for id in binds:
			var v = cf.get_value("binds", id, null)
			if v is Array and v.size() == 2: binds[id] = [int(v[0]), int(v[1])]
		# v0.9.3: F1 теперь у панели 2 — старое «Цель — я» на F1 переносим на F
		if int(binds.target_self[0]) == KEY_F1: binds.target_self[0] = KEY_F
	apply()

static func save() -> void:
	var cf := ConfigFile.new()
	for id in binds: cf.set_value("binds", id, binds[id])
	cf.save(PATH)

static func reset_defaults() -> void:
	binds = defaults(); apply(); save()

## Код кнопки мыши: MB + 1…31 (у особых клавиш — Tab, Shift, F1… — коды > 4 млн, это не мышь)
static func is_mouse(code: int) -> bool: return code >= MB and code < MB + 32

static func make_event(code: int) -> InputEvent:
	if code <= 0: return null
	if is_mouse(code):
		var m := InputEventMouseButton.new(); m.button_index = code - MB; return m
	var k := InputEventKey.new(); k.physical_keycode = code; return k

static func code_of(ev: InputEvent) -> int:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		return int(k.physical_keycode) if k.physical_keycode != 0 else int(k.keycode)
	if ev is InputEventMouseButton: return MB + int((ev as InputEventMouseButton).button_index)
	return 0

static func code_name(code: int) -> String:
	if code <= 0: return "—"
	if is_mouse(code):
		return {MOUSE_BUTTON_LEFT: "ЛКМ", MOUSE_BUTTON_RIGHT: "ПКМ", MOUSE_BUTTON_MIDDLE: "СКМ", MOUSE_BUTTON_XBUTTON1: "Мышь 4", MOUSE_BUTTON_XBUTTON2: "Мышь 5"}.get(code - MB, "Мышь %d" % (code - MB))
	var n := OS.get_keycode_string(code)
	return {"Space": "Пробел", "Shift": "Shift", "Enter": "Enter", "Tab": "Tab"}.get(n, n)

static func apply() -> void:
	for id in binds:
		if not InputMap.has_action(id): InputMap.add_action(id, 0.2)
		InputMap.action_erase_events(id)
		for code in binds[id]:
			var ev := make_event(int(code))
			if ev: InputMap.action_add_event(id, ev)

## Назначить привязку (slot 0/1); 0 — очистить
static func rebind(id: String, slot: int, code: int) -> void:
	if not binds.has(id): return
	binds[id][slot] = code
	apply(); save()

## Коды, назначенные больше чем на одно действие
static func conflicts() -> Dictionary:
	var seen := {}; var out := {}
	for id in binds:
		for code in binds[id]:
			if int(code) <= 0: continue
			if seen.has(code) and seen[code] != id: out[code] = true
			seen[code] = id
	return out

## Действие, к которому привязано событие (для горячих клавиш HUD); "" — нет
static func action_of(ev: InputEvent) -> String:
	var code := code_of(ev)
	if code <= 0: return ""
	for a in ACTIONS:
		if binds.get(a[0], []).has(code): return a[0]
	return ""

static func key_hint(id: String) -> String:
	var b: Array = binds.get(id, [0, 0])
	return code_name(int(b[0])) if int(b[0]) > 0 else code_name(int(b[1]))
