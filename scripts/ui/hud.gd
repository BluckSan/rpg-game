extends CanvasLayer
## Игровой интерфейс: полосы, мини-карта, джойстик, кнопки умений, окна, подсказки, уведомления.
## Мультитач обрабатывается здесь.

var zone
var player: Player
var root: Control
var hp_bar: ProgressBar
var mp_bar: ProgressBar
var xp_bar: ProgressBar
var name_label: Label
var gold_label: Label
var talent_badge: Label
var skill_btns := []      # [0] атака, [1..3] умения
var potion_btn: SkillButton
var potion_label: Label
var jump_btn: SkillButton
var roll_btn: SkillButton
var interact_btn: Button
var joy_base: Control
var joy_knob: Control
var joy_default := Vector2(260, 840)
const JOY_R := 110.0
var pickup_box: VBoxContainer
var boss_panel: Control
var boss_bar: ProgressBar
var boss_name: Label
var boss_phase: Label
var minimap: Minimap
var objective: Label
var window: Control
var bar_pool := []
var top_buttons := []
var blockers := []          # элементы, нажатия на которые не уходят в джойстик/камеру
var hint_panel: Control
var hint_label: Label
var hint_id := ""
var tooltip: Control
var _hold_time := {}
var _tip_slot := -1
var _start_pos := Vector3.ZERO
var _hint_age := 0.0

# мультитач
var touches := {}   # index -> {"role": "joy"/"skill"/"cam", "slot": int, "pos": Vector2, "origin": Vector2}
var pinch_last := 0.0

func setup(z) -> void:
	zone = z
	player = z.player
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	UIK.full(root)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	if not zone.data.has("tutorial"): zone.data["tutorial"] = {}
	_start_pos = player.global_position

	# --- статус: портрет, имя, здоровье, мана ---
	var status := UIK.panel(root, Color(0.1, 0.08, 0.06, 0.85))
	UIK.rect(status, Vector2(16, 16), Vector2(640, 200))
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var port := Panel.new(); port.add_theme_stylebox_override("panel", UIK.frame("slot", Color.WHITE, 8))
	status.add_child(port); UIK.rect(port, Vector2(18, 26), Vector2(120, 120))
	var pic := UIK.icon_rect(port, UIK.WEAPON_ICONS.get(zone.data["class"], "person"), 84, UIK.ACCENT)
	pic.position = Vector2(18, 18)
	name_label = UIK.label(status, "", 26, UIK.ACCENT)
	UIK.rect(name_label, Vector2(152, 10), Vector2(470, 46))
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.clip_text = true
	hp_bar = UIK.bar(status, Color(0.78, 0.13, 0.12)); UIK.rect(hp_bar, Vector2(152, 60), Vector2(470, 52))
	var hi := UIK.icon_rect(hp_bar, "heart-bottle", 34); hi.position = Vector2(12, 9)
	mp_bar = UIK.bar(status, Color(0.18, 0.38, 0.9)); UIK.rect(mp_bar, Vector2(152, 118), Vector2(470, 44))
	var mi := UIK.icon_rect(mp_bar, "drop", 28); mi.position = Vector2(12, 8)
	var gold_box := HBoxContainer.new(); gold_box.add_theme_constant_override("separation", 8)
	gold_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.add_child(gold_box); UIK.rect(gold_box, Vector2(152, 162), Vector2(470, 36))
	UIK.icon_rect(gold_box, "two-coins", 30, Color(1, 0.82, 0.3))
	gold_label = UIK.label(gold_box, "", 24, Color(1, 0.85, 0.4))
	gold_label.autowrap_mode = TextServer.AUTOWRAP_OFF

	xp_bar = UIK.bar(root, Color(0.85, 0.62, 0.15))
	xp_bar.anchor_left = 0.27; xp_bar.anchor_right = 0.73; xp_bar.anchor_top = 1; xp_bar.anchor_bottom = 1
	xp_bar.offset_top = -34; xp_bar.offset_bottom = -4
	xp_bar.get_node("Text").add_theme_font_size_override("font_size", 18)

	# --- мини-карта и цель ---
	minimap = Minimap.new()
	minimap.zone = zone
	minimap.anchor_left = 1; minimap.anchor_right = 1
	minimap.offset_left = -276; minimap.offset_right = -16; minimap.offset_top = 14; minimap.offset_bottom = 274
	root.add_child(minimap)
	objective = UIK.label(root, "", 22, UIK.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	objective.anchor_left = 1; objective.anchor_right = 1
	objective.offset_left = -640; objective.offset_right = -20; objective.offset_top = 278; objective.offset_bottom = 340

	# --- верхние кнопки (слева от карты) ---
	var b_tal := _top_button("Таланты", _open.bind("talents"), Color(0.42, 0.28, 0.5), 0, 240, "book-cover")
	talent_badge = UIK.label(b_tal, "", 24, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	var badge_bg := UIK.panel(b_tal, Color(0.85, 0.2, 0.2), 22)
	UIK.rect(badge_bg, Vector2(206, -14), Vector2(44, 44))
	badge_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	talent_badge.reparent(badge_bg); UIK.full(talent_badge)
	_top_button("Герой", _open.bind("hero"), UIK.BUTTON, 1, 210, "person")
	_top_button("Меню", _open.bind("pause"), Color(0.3, 0.3, 0.32), 2, 190, "cog")

	# --- боевые кнопки (координаты от правого нижнего угла) ---
	var cls: Dictionary = DB.CLASSES[zone.data["class"]]
	skill_btns.append(_skill_button(cls.skills[0].name, Vector2(-50, -50), 240, Color(0.62, 0.26, 0.16), UIK.SKILL_ICONS.get(cls.skills[0].id, "broadsword")))
	skill_btns[0].max_pips = 3
	var pos := [Vector2.ZERO, Vector2(-310, -40), Vector2(-290, -240), Vector2(-100, -320)]
	for i in range(1, 4):
		skill_btns.append(_skill_button("", pos[i], 156, Color.GRAY, ""))
	potion_btn = _skill_button("Зелье", Vector2(-60, -500), 116, Color(0.7, 0.12, 0.2), "health-potion")
	potion_label = UIK.label(potion_btn, "", 1)   # число показывается значком на кнопке
	potion_label.visible = false
	jump_btn = _skill_button("Прыжок", Vector2(-480, -250), 134, Color(0.22, 0.45, 0.7), "jump-across")
	roll_btn = _skill_button("Кувырок", Vector2(-500, -40), 134, Color(0.3, 0.5, 0.3), "dodging")

	interact_btn = UIK.button(root, "Торговать", _open.bind("shop"), UIK.GOLD, 34, "shop")
	interact_btn.anchor_left = 0.5; interact_btn.anchor_right = 0.5; interact_btn.anchor_top = 1; interact_btn.anchor_bottom = 1
	interact_btn.offset_left = -170; interact_btn.offset_right = 170; interact_btn.offset_top = -200; interact_btn.offset_bottom = -100
	interact_btn.visible = false
	blockers.append(interact_btn)

	joy_base = Control.new(); joy_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	joy_base.size = Vector2(JOY_R * 2, JOY_R * 2)
	joy_base.draw.connect(func():
		joy_base.draw_circle(Vector2(JOY_R, JOY_R), JOY_R, Color(0.05, 0.04, 0.03, 0.35))
		joy_base.draw_arc(Vector2(JOY_R, JOY_R), JOY_R - 3, 0, TAU, 48, Color(0.95, 0.74, 0.36, 0.55), 4.0))
	root.add_child(joy_base)
	joy_knob = Control.new(); joy_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	joy_knob.size = Vector2(100, 100)
	joy_knob.draw.connect(func():
		joy_knob.draw_circle(Vector2(50, 50), 48, Color(0.9, 0.8, 0.6, 0.55))
		joy_knob.draw_arc(Vector2(50, 50), 46, 0, TAU, 32, Color(1, 0.85, 0.5, 0.9), 3.0))
	joy_base.add_child(joy_knob)
	_set_joy(joy_default, Vector2.ZERO)
	if Game.desktop: _setup_desktop()

	pickup_box = VBoxContainer.new()
	pickup_box.alignment = BoxContainer.ALIGNMENT_END
	pickup_box.add_theme_constant_override("separation", 6)
	pickup_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIK.rect(pickup_box, Vector2(20, 380), Vector2(560, 300))
	root.add_child(pickup_box)

	# --- полоса босса ---
	boss_panel = UIK.panel(root, Color(0.1, 0.06, 0.05, 0.88))
	boss_panel.anchor_left = 0.5; boss_panel.anchor_right = 0.5
	boss_panel.offset_left = -400; boss_panel.offset_right = 400; boss_panel.offset_top = 116; boss_panel.offset_bottom = 236
	boss_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sk := UIK.icon_rect(boss_panel, "skull-crossed-bones", 44, Color(1, 0.4, 0.3)); sk.position = Vector2(24, 12)
	boss_name = UIK.label(boss_panel, "", 30, UIK.ACCENT)
	boss_name.autowrap_mode = TextServer.AUTOWRAP_OFF
	UIK.rect(boss_name, Vector2(80, 8), Vector2(500, 50))
	boss_phase = UIK.label(boss_panel, "", 24, Color(1, 0.6, 0.4), HORIZONTAL_ALIGNMENT_RIGHT)
	boss_phase.autowrap_mode = TextServer.AUTOWRAP_OFF
	UIK.rect(boss_phase, Vector2(420, 10), Vector2(356, 50))
	boss_name.size = Vector2(400, 50)
	boss_bar = UIK.bar(boss_panel, Color(0.7, 0.08, 0.08))
	UIK.rect(boss_bar, Vector2(24, 62), Vector2(752, 46))
	for f in [0.66, 0.33]:
		var m := ColorRect.new(); m.color = Color(1, 0.85, 0.4, 0.95)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		boss_bar.add_child(m); UIK.rect(m, Vector2(752 * f - 2, -4), Vector2(4, 54))
		m.name = "Mark%d" % int(f * 100)
	boss_panel.visible = false
	boss_bar.move_to_front()
	refresh_skill_buttons()

	# --- подсказка обучения ---
	hint_panel = Panel.new()
	hint_panel.add_theme_stylebox_override("panel", UIK.frame("tooltip", Color.WHITE, 18))
	UIK.rect(hint_panel, Vector2(16, 230), Vector2(860, 140))
	hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hint_panel)
	var hico := UIK.icon_rect(hint_panel, "treasure-map", 60, UIK.ACCENT); hico.position = Vector2(26, 40)
	hint_label = UIK.label(hint_panel, "", 25)
	UIK.rect(hint_label, Vector2(100, 14), Vector2(560, 112))
	var ok := UIK.button(hint_panel, "Понятно", _hint_done, UIK.GREEN, 26)
	UIK.rect(ok, Vector2(676, 34), Vector2(164, 72)); ok.custom_minimum_size = Vector2(164, 72)
	blockers.append(ok)
	hint_panel.visible = false

func _top_button(t: String, cb: Callable, c: Color, idx: int, w: float, ic := "") -> Button:
	var b := UIK.button(root, t, cb, c, 28, ic)
	b.anchor_left = 1; b.anchor_right = 1
	var right: float = -292.0 - [0.0, 256.0, 482.0][idx]
	b.offset_right = right; b.offset_left = right - w; b.offset_top = 20; b.offset_bottom = 104
	top_buttons.append(b)
	return b

func _skill_button(t: String, offset: Vector2, sz: float, c: Color, ic: String) -> SkillButton:
	var sb := SkillButton.new()
	sb.text = t; sb.color = c
	if ic != "": sb.icon = UIK.icon(ic)
	sb.anchor_left = 1; sb.anchor_right = 1; sb.anchor_top = 1; sb.anchor_bottom = 1
	sb.offset_left = offset.x - sz; sb.offset_right = offset.x
	sb.offset_top = offset.y - sz; sb.offset_bottom = offset.y
	sb.pivot_offset = Vector2(sz, sz) / 2
	root.add_child(sb)
	return sb

func refresh_skill_buttons() -> void:
	for i in range(1, 4):
		var s = player.get_skill(i)
		skill_btns[i].text = s.name if s != null else "Путь"
		skill_btns[i].icon = UIK.icon(UIK.SKILL_ICONS.get(s.id, "magic-swirl")) if s != null else UIK.icon("aura")
		var sc: Color = s.color if s != null else Color(0.4, 0.4, 0.4)
		skill_btns[i].color = Color(sc.r * 0.55, sc.g * 0.55, sc.b * 0.55, 1)
		skill_btns[i].queue_redraw()

# ---------------- ПК: клавиатура и мышь ----------------
## Сенсорные элементы прячем, на кнопках умений — подсказки клавиш
func _setup_desktop() -> void:
	joy_base.visible = false
	jump_btn.visible = false
	roll_btn.visible = false
	var keys := ["ЛКМ", "1", "2", "3"]
	for i in skill_btns.size(): skill_btns[i].key_hint = keys[i]
	potion_btn.key_hint = "H"
	interact_btn.text = "Торговать [E]"
	var help := UIK.label(root, "WASD — ход · ЛКМ — атака · ПКМ — камера · колесо — зум\nПробел — прыжок · Shift — кувырок · H — зелье · I — герой · T — таланты · M — карта · Esc — меню", 19, Color(1, 1, 1, 0.6))
	help.autowrap_mode = TextServer.AUTOWRAP_OFF
	help.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	help.add_theme_constant_override("outline_size", 5)
	help.anchor_top = 1; help.anchor_bottom = 1
	help.offset_left = 20; help.offset_right = 1100; help.offset_top = -112; help.offset_bottom = -44
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE

## Горячие клавиши (true — событие обработано)
func _hotkey(k: int) -> bool:
	if window != null:
		var wname := String(window.name)
		if k == KEY_ESCAPE or (k in [KEY_I, KEY_C] and wname == "Window_hero") or (k in [KEY_T, KEY_N] and wname == "Window_talents") \
				or (k == KEY_E and wname == "Window_shop"):
			close_window(); return true
		return false
	match k:
		KEY_1, KEY_2, KEY_3:
			var i := k - KEY_0
			player.try_use(i)
			skill_btns[i].set_held(true)
			get_tree().create_timer(0.12).timeout.connect(func(): if is_instance_valid(skill_btns[i]): skill_btns[i].set_held(false))
		KEY_SPACE: press_jump()
		KEY_SHIFT, KEY_K: press_roll()
		KEY_H, KEY_Q: player.use_potion()
		KEY_I, KEY_C: _open("hero")
		KEY_T, KEY_N: _open("talents")
		KEY_M: minimap.toggle_big()
		KEY_ESCAPE: _open("pause")
		KEY_E:
			if zone.near_merchant(): _open("shop")
			else: return false
		_: return false
	return true

# ---------------- окна ----------------
func _open(which: String) -> void:
	if window: window.queue_free()
	_hide_tooltip()
	match which:
		"talents": window = preload("res://scripts/ui/talent_tree_ui.gd").new()
		"hero": window = preload("res://scripts/ui/inventory_ui.gd").new()
		"shop": window = preload("res://scripts/ui/shop_ui.gd").new()
		_: window = preload("res://scripts/ui/pause_menu.gd").new()
	window.name = "Window_" + which
	UIK.full(window)
	add_child(window)
	window.setup(zone)
	UIK.pop_in(window)
	if which == "talents": _mark_hint("talents")
	if which == "shop": _mark_hint("shop")
	_release_all()
	get_tree().paused = true

func close_window() -> void:
	if window: UIK.pop_out(window)
	window = null
	get_tree().paused = false
	refresh_skill_buttons()

## Лента добычи: иконка + текст, плавно появляется и исчезает
func pickup(t: String, c: Color, ic := "") -> void:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", UIK.box(Color(0.06, 0.05, 0.04, 0.6), 10, 2, Color(c.r, c.g, c.b, 0.6)))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(h)
	if ic != "": UIK.icon_rect(h, ic, 36, c)
	var l := UIK.label(h, t, 24, c)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	pickup_box.add_child(row)
	while pickup_box.get_child_count() > 6: pickup_box.get_child(0).free()
	row.modulate.a = 0.0
	var tw := row.create_tween()
	tw.tween_property(row, "modulate:a", 1.0, 0.18)
	tw.tween_interval(3.0)
	tw.tween_property(row, "modulate:a", 0.0, 0.5)
	tw.tween_callback(row.queue_free)

## Баннер «Новый уровень»
var level_banners := 0
func level_up(level: int, points: int) -> void:
	level_banners += 1
	var b := Control.new(); b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.anchor_left = 0.5; b.anchor_right = 0.5
	b.offset_left = -450; b.offset_right = 450; b.offset_top = 150; b.offset_bottom = 330
	b.name = "LevelBanner"
	root.add_child(b)
	var bg := Panel.new(); bg.add_theme_stylebox_override("panel", UIK.frame("panel", Color(1, 1, 1, 0.95)))
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(bg); UIK.full(bg)
	var ic := UIK.icon_rect(b, "trophy", 90, UIK.ACCENT); ic.position = Vector2(40, 45)
	var t := UIK.label(b, "НОВЫЙ УРОВЕНЬ %d" % level, 56, UIK.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	t.autowrap_mode = TextServer.AUTOWRAP_OFF
	UIK.rect(t, Vector2(140, 20), Vector2(700, 80))
	var sub := UIK.label(b, "Очков талантов: %d — откройте «Таланты»" % points, 26, UIK.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	sub.autowrap_mode = TextServer.AUTOWRAP_OFF
	UIK.rect(sub, Vector2(140, 100), Vector2(700, 50))
	b.pivot_offset = Vector2(450, 90)
	b.scale = Vector2(0.6, 0.6); b.modulate.a = 0
	var tw := b.create_tween()
	tw.set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(b, "scale", Vector2.ONE, 0.35)
	tw.tween_property(b, "modulate:a", 1.0, 0.25)
	tw.chain().tween_interval(2.6)
	tw.chain().tween_property(b, "modulate:a", 0.0, 0.5)
	tw.chain().tween_callback(b.queue_free)

# ---------------- подсказки обучения ----------------
const HINTS := {
	"move": "Левый джойстик — движение. Проведите пальцем по правой части экрана, чтобы повернуть камеру.",
	"attack": "Удерживайте большую кнопку атаки: три удара подряд — это комбо, последний бьёт сильнее.",
	"jump": "«Прыжок» перепрыгивает ударные волны босса, «Кувырок» даёт миг неуязвимости.",
	"talents": "Есть свободное очко! Нажмите «Таланты» вверху и изучите новый узел.",
	"shop": "Рядом торговец: нажмите «Торговать», чтобы купить зелья и снаряжение или продать добычу.",
	"boss": "Красные зоны — предупреждение об атаке босса. Уходите из них или делайте кувырок!",
}

func _tut() -> Dictionary: return zone.data["tutorial"]

func show_hint(id: String) -> void:
	if _tut().get(id, false) or hint_id == id: return
	hint_id = id
	_hint_age = 0.0
	hint_label.text = HINTS[id]
	hint_panel.visible = true
	UIK.pop_in(hint_panel, 0.25)

func _mark_hint(id: String) -> void:
	_tut()[id] = true
	if hint_id == id: _hint_done()

func _hint_done() -> void:
	if hint_id != "": _tut()[hint_id] = true
	hint_id = ""
	hint_panel.visible = false

func _update_hints(delta: float) -> void:
	_hint_age += delta
	var t := _tut()
	# условия выполнения
	if hint_id == "move" and (player.global_position.distance_to(_start_pos) > 4.0 or _hint_age > 12): _mark_hint("move")
	elif hint_id == "attack" and (player.combo_count >= 3 or _hint_age > 15): _mark_hint("attack")
	elif hint_id == "jump" and (player.jumps > 0 or player.rolls > 0 or _hint_age > 12): _mark_hint("jump")
	elif hint_id == "talents" and DB.free_points(zone.data) == 0: _mark_hint("talents")
	elif hint_id == "shop" and not zone.near_merchant(): hint_id = ""; hint_panel.visible = false
	elif hint_id == "boss" and _hint_age > 9: _mark_hint("boss")
	if hint_id != "": return
	if not t.get("move", false): show_hint("move")
	elif not t.get("attack", false): show_hint("attack")
	elif not t.get("jump", false): show_hint("jump")
	elif zone.near_merchant() and not t.get("shop", false): show_hint("shop")
	elif DB.free_points(zone.data) > 0 and not t.get("talents", false): show_hint("talents")
	elif boss_panel.visible and not t.get("boss", false): show_hint("boss")

# ---------------- подсказки к умениям (долгое нажатие) ----------------
func show_skill_tooltip(slot: int) -> void:
	var s = player.get_skill(slot)
	if s == null: return
	var body: String = s.get("desc", "Основная атака: серия из 3 ударов")
	if float(s.get("mana", 0)) > 0: body += "\n[color=#7fb2ff]Мана: %d[/color]" % int(s.mana)
	if float(s.get("cd", 0)) > 0: body += "   [color=#e6c27a]Перезарядка: %.0f с[/color]" % float(s.cd)
	var b: Control = skill_btns[slot]
	_show_tooltip(s.name, body, UIK.SKILL_ICONS.get(s.id, "magic-swirl"), UIK.ACCENT, b.get_global_rect())

func _show_tooltip(title: String, body: String, ic: String, col: Color, near: Rect2) -> void:
	_hide_tooltip()
	tooltip = UIK.tooltip(root, title, body, ic, col)
	UIK.place_tooltip(tooltip, near, _screen())

func _hide_tooltip() -> void:
	if tooltip and is_instance_valid(tooltip): tooltip.queue_free()
	tooltip = null
	_tip_slot = -1

# ---------------- ввод ----------------
func _release_all() -> void:
	touches.clear()
	player.move_input = Vector2.ZERO
	player.attack_held = false
	for b in skill_btns: b.set_held(false)
	_set_joy(joy_default, Vector2.ZERO)

func _over_top_button(p: Vector2) -> bool:
	for b in top_buttons + blockers:
		if b.is_visible_in_tree() and b.get_global_rect().has_point(p): return true
	return false

func _input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and player != null:
		if _hotkey(ev.keycode):
			get_viewport().set_input_as_handled()
			return
	if window != null: return
	if ev is InputEventScreenTouch:
		if ev.pressed: _touch_down(ev.index, ev.position)
		else: _touch_up(ev.index)
	elif ev is InputEventScreenDrag:
		_touch_move(ev.index, ev.position, ev.relative)
	# мышь на ПК (без тача): ЛКМ по кнопкам
	elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and (Game.desktop or not DisplayServer.is_touchscreen_available()):
		if ev.pressed: _touch_down(-1, ev.position)
		else: _touch_up(-1)
	elif ev is InputEventMouseMotion and touches.has(-1) and (Game.desktop or not DisplayServer.is_touchscreen_available()):
		_touch_move(-1, ev.position, ev.relative)

func _screen() -> Vector2:
	return root.get_viewport_rect().size

func _touch_down(idx: int, p: Vector2) -> void:
	if _over_top_button(p): return
	for i in skill_btns.size():
		if skill_btns[i].hit(p):
			touches[idx] = {"role": "skill", "slot": i}
			_hold_time[i] = 0.0
			skill_btns[i].set_held(true)
			if i == 0: player.attack_held = true
			else: player.try_use(i)
			return
	if jump_btn.hit(p):
		touches[idx] = {"role": "jump"}
		jump_btn.set_held(true)
		press_jump()
		return
	if roll_btn.hit(p):
		touches[idx] = {"role": "roll"}
		roll_btn.set_held(true)
		press_roll()
		return
	if potion_btn.hit(p):
		touches[idx] = {"role": "potion"}
		potion_btn.set_held(true)
		player.use_potion()
		return
	if Game.desktop and idx == -1:
		# ЛКМ по миру — атака (удержание — серия ударов)
		if window == null and not _over_ui(p):
			touches[idx] = {"role": "skill", "slot": 0}
			_hold_time[0] = 0.0
			skill_btns[0].set_held(true)
			player.attack_held = true
		return
	var s := _screen()
	if p.x < s.x * 0.42 and p.y > s.y * 0.25 and not _has_role("joy"):
		touches[idx] = {"role": "joy", "origin": p}
		_set_joy(p, Vector2.ZERO)
		return
	touches[idx] = {"role": "cam", "pos": p}

func _over_ui(p: Vector2) -> bool:
	for c in [pickup_box, boss_panel, hint_panel, minimap]:
		if c and c.is_visible_in_tree() and c.mouse_filter != Control.MOUSE_FILTER_IGNORE and c.get_global_rect().has_point(p): return true
	return false

func _has_role(r: String) -> bool:
	for t in touches.values():
		if t["role"] == r: return true
	return false

func _touch_move(idx: int, p: Vector2, rel: Vector2) -> void:
	if not touches.has(idx): return
	var t: Dictionary = touches[idx]
	match t["role"]:
		"joy":
			var v: Vector2 = (p - t["origin"]).limit_length(JOY_R)
			_set_joy(t["origin"], v)
			player.move_input = Vector2(v.x, -v.y) / JOY_R
		"cam":
			t["pos"] = p
			var cams := []
			for k in touches:
				if touches[k]["role"] == "cam": cams.append(touches[k]["pos"])
			if cams.size() >= 2:
				var d: float = cams[0].distance_to(cams[1])
				if pinch_last > 0: zone.cam_rig.zoom_by(pinch_last / maxf(d, 1.0))
				pinch_last = d
			else:
				pinch_last = 0
				zone.cam_rig.rotate_by(rel.x, rel.y)

func _touch_up(idx: int) -> void:
	if not touches.has(idx): return
	var t: Dictionary = touches[idx]
	match t["role"]:
		"joy":
			player.move_input = Vector2.ZERO
			_set_joy(joy_default, Vector2.ZERO)
		"skill":
			skill_btns[t["slot"]].set_held(false)
			_hold_time.erase(t["slot"])
			if _tip_slot == t["slot"]: _hide_tooltip()
			if t["slot"] == 0: player.attack_held = false
		"potion":
			potion_btn.set_held(false)
		"jump":
			jump_btn.set_held(false)
		"roll":
			roll_btn.set_held(false)
	touches.erase(idx)
	pinch_last = 0

## Кнопка «Прыжок» (и для автотестов)
func press_jump() -> void:
	if player: player.request_jump()

## Кнопка «Кувырок»
func press_roll() -> void:
	if player: player.request_roll()

func _set_joy(center: Vector2, knob: Vector2) -> void:
	joy_base.position = center - Vector2(JOY_R, JOY_R)
	joy_knob.position = Vector2(JOY_R, JOY_R) + knob - Vector2(50, 50)

# ---------------- обновление ----------------
func _process(delta: float) -> void:
	if player == null or player.stats.is_empty(): return
	if window == null:
		_update_hints(delta)
		for k in _hold_time.keys():
			_hold_time[k] += delta
			if k > 0 and _hold_time[k] > 0.55 and _tip_slot != k:
				show_skill_tooltip(k); _tip_slot = k
	interact_btn.visible = window == null and zone.near_merchant()
	var d: Dictionary = zone.data
	joy_default = Vector2(260, _screen().y - 240)
	if not _has_role("joy"): _set_joy(joy_default, Vector2.ZERO)
	var asc := DB.get_asc(d["ascendancy"])
	name_label.text = "%s · ур. %d · %s" % [d["name"], d["level"], asc["name"] if not asc.is_empty() else DB.CLASSES[d["class"]].name]
	var mhp := roundi(player.stats.max_hp)
	var mmp := roundi(player.stats.max_mp)
	_set_bar(hp_bar, player.hp, player.stats.max_hp, "%d / %d" % [mini(ceili(player.hp), mhp), mhp])
	_set_bar(mp_bar, player.mp, player.stats.max_mp, "%d / %d" % [mini(floori(player.mp), mmp), mmp])
	var need := DB.xp_to_next(d["level"])
	_set_bar(xp_bar, d["xp"], need, "Опыт %d / %d" % [d["xp"], need])
	gold_label.text = "%d" % d["gold"]
	potion_btn.badge = str(d["potions"]); potion_btn.queue_redraw()
	var c0: SkillButton = skill_btns[0]
	var pip := player.combo_step if player.combo_timer > 0 else 0
	if c0.pips != pip: c0.pips = pip; c0.queue_redraw()
	roll_btn.set_state(clampf(player.roll_cd / Player.ROLL_CD, 0, 1), 0.0, "")
	objective.text = _objective()
	var free := DB.free_points(d)
	talent_badge.get_parent().visible = free > 0
	talent_badge.text = str(free)
	for i in range(1, 4):
		var lock: String = player.lock_reason(i)
		var mx := player.max_cooldown(i)
		skill_btns[i].set_state(clampf(player.cooldowns[i] / mx, 0, 1) if mx > 0 else 0.0, player.cooldowns[i], lock)
	_update_enemy_bars()

func _set_bar(b: ProgressBar, v: float, mx: float, t: String) -> void:
	b.max_value = mx; b.value = v
	b.get_node("Text").text = t

func _update_enemy_bars() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null: return
	var used := 0
	var boss = null
	var pp := player.global_position
	for e in zone.enemies:
		if not e.alive: continue
		var dist := pp.distance_to(e.global_position)
		if e.def.boss and dist < 30: boss = e
		if dist > 22: continue
		var wp: Vector3 = e.global_position + Vector3.UP * (5.2 if e.def.boss else 2.4)
		if cam.is_position_behind(wp): continue
		var sp := cam.unproject_position(wp)
		if used >= bar_pool.size():
			var bar := UIK.bar(root, Color(0.85, 0.2, 0.15))
			bar.size = Vector2(130, 16)
			bar.get_node("Text").visible = false
			var nm := UIK.label(bar, "", 20, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
			UIK.rect(nm, Vector2(-85, -38), Vector2(300, 34))
			nm.autowrap_mode = TextServer.AUTOWRAP_OFF
			nm.name = "Name"
			root.move_child(bar, 0)
			bar_pool.append(bar)
		var b: ProgressBar = bar_pool[used]
		used += 1
		b.visible = true
		b.position = sp - Vector2(65, 8)
		b.max_value = e.max_hp; b.value = e.hp
		var nl: Label = b.get_node("Name")
		nl.text = e.display_name
		var diff: int = e.level - zone.data["level"]
		nl.add_theme_color_override("font_color", Color(1, 0.35, 0.3) if diff >= 3 else (Color(0.7, 0.7, 0.7) if diff <= -3 else Color.WHITE))
	for i in range(used, bar_pool.size()): bar_pool[i].visible = false
	boss_panel.visible = boss != null
	if boss != null:
		_set_bar(boss_bar, boss.hp, boss.max_hp, "%d / %d" % [ceili(boss.hp), roundi(boss.max_hp)])
		boss_name.text = str(boss.def.name) + "  ·  ур. %d" % boss.level
		var br = boss.brain
		if br:
			boss_phase.text = "Фаза %d · %s" % [br.phase, br.PHASE_NAMES[br.phase]] + ("  · ЯРОСТЬ" if br.enraged else "")
			var fill: StyleBoxTexture = boss_bar.get_theme_stylebox("fill")
			var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
			fill.modulate_color = Color(0.95, 0.25 + 0.2 * pulse, 0.05) if br.enraged else (Color(0.85, 0.2, 0.08) if br.phase == 2 else Color(0.78, 0.1, 0.1))
			for f in [66, 33]:
				var m: ColorRect = boss_bar.get_node("Mark%d" % f)
				m.color = Color(1, 0.85, 0.4, 0.95) if boss.hp / boss.max_hp > f / 100.0 else Color(0.4, 0.35, 0.3, 0.7)

func _objective() -> String:
	var boss_alive := false
	for e in zone.enemies:
		if e.alive and e.def.boss: boss_alive = true
	if boss_alive: return "Цель: победить Древнего тролля в руинах (череп на карте)"
	return "Цель: портал в Глобальный мир (замок на карте)"
