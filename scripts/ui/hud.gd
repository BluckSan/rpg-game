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
var skill_badge: Label
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
var boss_res: RichTextLabel
var minimap: Minimap
var objective: Label
var window: Control
var bar_pool := []
var top_buttons := []
var blockers := []          # элементы, нажатия на которые не уходят в джойстик/камеру
var target_btn: SkillButton   # v0.9.0: «Цель» — следующий враг (телефон; на ПК — Tab)
var target_frame: Panel       # рамка цели вверху: имя, уровень, здоровье, мана, баффы/ослабления
var tf_name: Label
var tf_hp: ProgressBar
var tf_mp: ProgressBar
var tf_buffs: HBoxContainer
var self_buffs: HBoxContainer # баффы своего героя (под полосой маны)
var boss_buffs: HBoxContainer # ослабления на боссе
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
	self_buffs = HBoxContainer.new(); self_buffs.name = "SelfBuffs"
	self_buffs.add_theme_constant_override("separation", 4)
	self_buffs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.add_child(self_buffs); UIK.rect(self_buffs, Vector2(300, 162), Vector2(330, 36))
	_build_target_frame()

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
	if zone.builder is WorldBuilder: objective.offset_top = 306; objective.offset_bottom = 368   # под названием зоны

	# --- v0.9.4: одна кнопка «Меню» (слева от карты) вместо ряда кнопок; панель со всеми окнами ---
	_build_menu()

	# --- боевые кнопки (координаты от правого нижнего угла) ---
	var cls: Dictionary = DB.CLASSES[zone.data["class"]]
	skill_btns.append(_skill_button(cls.skills[0].name, Vector2(-50, -50), 240, Color(0.62, 0.26, 0.16), UIK.SKILL_ICONS.get(cls.skills[0].id, "broadsword")))
	skill_btns[0].max_pips = 3
	# 8 умений набора; расположение — apply_skill_layout() (веер или ряд, настройка «Панель умений»)
	for i in range(1, DB.LOADOUT_SLOTS + 1):
		skill_btns.append(_skill_button("", Vector2(-310, -40), 140, Color.GRAY, ""))
	potion_btn = _skill_button("Зелье", Vector2(-60, -500), 116, Color(0.7, 0.12, 0.2), "health-potion")
	potion_label = UIK.label(potion_btn, "", 1)   # число показывается значком на кнопке
	potion_label.visible = false
	jump_btn = _skill_button("Прыжок", Vector2(-660, -250), 128, Color(0.22, 0.45, 0.7), "jump-across")
	roll_btn = _skill_button("Кувырок", Vector2(-670, -40), 128, Color(0.3, 0.5, 0.3), "dodging")
	target_btn = _skill_button("Цель", Vector2(-700, -400), 96, Color(0.55, 0.2, 0.2), "bullseye")
	target_btn.name = "TargetBtn"
	add_to_group("hud_listeners")
	apply_skill_layout()

	interact_btn = UIK.button(root, "Торговать", interact, UIK.GOLD, 30, "shop")
	interact_btn.anchor_left = 0.5; interact_btn.anchor_right = 0.5; interact_btn.anchor_top = 1; interact_btn.anchor_bottom = 1
	interact_btn.offset_left = -210; interact_btn.offset_right = 210; interact_btn.offset_top = -200; interact_btn.offset_bottom = -100
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
	boss_panel.offset_left = -400; boss_panel.offset_right = 400; boss_panel.offset_top = 116; boss_panel.offset_bottom = 268
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
	boss_res = RichTextLabel.new(); boss_res.bbcode_enabled = true; boss_res.scroll_active = false
	boss_res.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_res.add_theme_font_size_override("normal_font_size", 21)
	boss_panel.add_child(boss_res); UIK.rect(boss_res, Vector2(24, 114), Vector2(752, 34))
	boss_panel.visible = false
	boss_buffs = HBoxContainer.new(); boss_buffs.name = "BossBuffs"
	boss_buffs.add_theme_constant_override("separation", 4)
	boss_buffs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_panel.add_child(boss_buffs); UIK.rect(boss_buffs, Vector2(24, 152), Vector2(752, 36))
	boss_panel.offset_bottom = 306
	boss_bar.move_to_front()
	refresh_skill_buttons()
	if zone.data.has("talent_refund"):
		Game.toast("Дерево талантов обновлено: возвращено очков — %d. Распределите их заново (путь превращения сохранён)." % int(zone.data["talent_refund"]), 6.0)
		zone.data.erase("talent_refund")

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

## v0.9.4: раскрывающееся меню. Пункты: [действие окна, подпись, иконка, клавиша Controls]
const MENU_ITEMS := [["hero", "Герой", "person", "hero"], ["skills", "Умения", "book-cover", "skills"], ["talents", "Таланты", "book-cover", "talents"],
	["map", "Карта", "treasure-map", "map"], ["party", "Группа", "three-friends", "party"], ["dungeons", "Подземелья", "crossed-swords", ""],
	["market", "Рынок", "shop", ""], ["craft", "Ремесло", "thor-hammer", ""], ["pause", "Настройки", "cog", ""]]
var menu_btn: Button
var menu_panel: PanelContainer
var menu_items := {}
var menu_open := false

func _build_menu() -> void:
	menu_btn = _top_button("Меню", toggle_menu, Color(0.22, 0.2, 0.3), 0, 220, "hamburger-menu")
	menu_btn.name = "MenuBtn"
	var bg := UIK.panel(menu_btn, Color(0.85, 0.2, 0.2), 22); bg.name = "MenuBadge"
	UIK.rect(bg, Vector2(186, -14), Vector2(44, 44)); bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ml := UIK.label(bg, "!", 24, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER); UIK.full(ml)
	bg.visible = false
	menu_panel = PanelContainer.new(); menu_panel.name = "MenuPanel"
	menu_panel.add_theme_stylebox_override("panel", UIK.frame("tooltip", Color(1, 1, 1, 0.97), 16))
	root.add_child(menu_panel)
	menu_panel.anchor_left = 1; menu_panel.anchor_right = 1
	menu_panel.offset_right = menu_btn.offset_right; menu_panel.offset_left = menu_btn.offset_right - (640 if Game.desktop else 600)
	menu_panel.offset_top = 112
	menu_panel.z_index = 20   # поверх названия зоны и подсказок
	var grid := GridContainer.new(); grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10); grid.add_theme_constant_override("v_separation", 10)
	menu_panel.add_child(grid)
	for it in MENU_ITEMS:
		var b := UIK.button(grid, it[1], _menu_pick.bind(it[0]), UIK.BUTTON, 26 if Game.desktop else 30, it[2])
		b.name = "Menu_" + it[0]; b.custom_minimum_size = Vector2(300 if Game.desktop else 280, 64 if Game.desktop else 84)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		menu_items[it[0]] = b
		if it[0] in ["talents", "skills"]:
			var bb := UIK.panel(b, Color(0.85, 0.2, 0.2) if it[0] == "talents" else Color(0.25, 0.6, 0.25), 22)
			UIK.rect(bb, Vector2(b.custom_minimum_size.x - 50, 10), Vector2(40, 40)); bb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if it[0] == "skills": bb.name = "SkillBadge"
			var bl := UIK.label(bb, "", 22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER); UIK.full(bl)
			if it[0] == "talents": talent_badge = bl
			else: skill_badge = bl
	menu_panel.visible = false
	blockers.append(menu_panel)

func toggle_menu() -> void:
	if menu_open: close_menu()
	else: open_menu()

func open_menu() -> void:
	if window != null: return
	menu_open = true
	refresh_key_hints()
	menu_panel.visible = true
	menu_panel.pivot_offset = Vector2(menu_panel.size.x, 0)
	menu_panel.scale = Vector2(0.85, 0.85); menu_panel.modulate.a = 0.0
	_menu_t0 = Time.get_ticks_msec()

## v0.9.4: анимация меню вручную по реальному времени (не зависит от паузы, time_scale и твинов)
var _menu_t0 := -1
func _menu_anim() -> void:
	if _menu_t0 < 0 or menu_panel == null: return
	var t := (Time.get_ticks_msec() - _menu_t0) / 1000.0
	if menu_open:
		var k := clampf(t / 0.18, 0.0, 1.0)
		var e := 1.0 + 2.70158 * pow(k - 1.0, 3) + 1.70158 * pow(k - 1.0, 2)   # back-out
		menu_panel.scale = Vector2.ONE * lerpf(0.85, 1.0, e)
		menu_panel.modulate.a = clampf(t / 0.14, 0.0, 1.0)
		if k >= 1.0: menu_panel.scale = Vector2.ONE; menu_panel.modulate.a = 1.0; _menu_t0 = -1
	else:
		var k := clampf(t / 0.12, 0.0, 1.0)
		menu_panel.scale = Vector2.ONE * lerpf(1.0, 0.9, k * k)
		menu_panel.modulate.a = 1.0 - k * k
		if k >= 1.0: menu_panel.hide(); _menu_t0 = -1

func close_menu(instant := false) -> void:
	if not menu_open: return
	menu_open = false
	if instant:
		menu_panel.visible = false; _menu_t0 = -1
		return
	_menu_t0 = Time.get_ticks_msec()

func _menu_pick(what: String) -> void:
	close_menu(true)
	var pui = zone.party_ui
	match what:
		"party": if pui: pui.open_tab("party")
		"dungeons": if pui: pui.open_dungeons()
		"map":
			if zone.builder is WorldBuilder: _open("map")
			else: minimap.toggle_big()
		_: _open(what)

func _top_button(t: String, cb: Callable, c: Color, idx: int, w: float, ic := "") -> Button:
	var b := UIK.button(root, t, cb, c, 28, ic)
	b.anchor_left = 1; b.anchor_right = 1
	var right: float = -292.0 - [0.0, 256.0, 482.0, 692.0][idx]
	b.offset_right = right; b.offset_left = right - w; b.offset_top = 20; b.offset_bottom = 104
	top_buttons.append(b)
	return b

## Расположение кнопок по центру `c` (от угла/края, к которому привязана кнопка). ax: 1 — правый край, 0.5 — центр низа
func _place(sb: Control, c: Vector2, sz: float, ax := 1.0) -> void:
	sb.anchor_left = ax; sb.anchor_right = ax; sb.anchor_top = 1; sb.anchor_bottom = 1
	sb.offset_left = c.x - sz / 2; sb.offset_right = c.x + sz / 2
	sb.offset_top = c.y - sz / 2; sb.offset_bottom = c.y + sz / 2
	sb.size = Vector2(sz, sz)
	sb.pivot_offset = Vector2(sz, sz) / 2
	sb.queue_redraw()

## Две раскладки панели умений (переключаются в настройках на телефоне и ПК, сохраняются):
## «mobile» — веер из двух дуг вокруг кнопки атаки справа внизу; «pc» — ряд 1–8 внизу по центру (работает и пальцем)
var layout := ""
func apply_skill_layout() -> void:
	layout = Game.skill_layout
	if interact_btn:
		interact_btn.offset_top = -330 if layout == "pc" else -200
		interact_btn.offset_bottom = interact_btn.offset_top + 100
	var ac := Vector2(-170, -170)          # центр кнопки атаки
	_place(skill_btns[0], ac, 240)
	if Game.desktop:
		# ПК: умения, зелье и выбор цели — на панелях ярлыков и клавишах; круглые кнопки убираем
		_place(skill_btns[0], Vector2(-110, -110), 150)
		for b in skill_btns.slice(1) + [potion_btn, target_btn]:
			b.visible = false; _place(b, Vector2(-99999, -99999), 10)
		return
	if layout == "pc":
		var sz := 104.0; var gap := 12.0
		var n := skill_btns.size() - 1
		var x0 := -((n - 1) * (sz + gap)) / 2.0
		for i in range(1, skill_btns.size()):
			_place(skill_btns[i], Vector2(x0 + (i - 1) * (sz + gap), -24 - sz / 2), sz, 0.5)
		_place(roll_btn, Vector2(-380, -90), 112)
		_place(target_btn, Vector2(x0 - (sz + gap) - 20, -24 - sz / 2), 96, 0.5)
		_place(jump_btn, Vector2(-380, -230), 112)
		_place(potion_btn, Vector2(-120, -390), 104)
	else:
		# внутренняя дуга (r 268): умения 1–4; внешняя (r 440): кувырок, прыжок, умения 5–8, зелье
		var inner := [180.0, 210.0, 240.0, 270.0]
		for k in 4:
			_place(skill_btns[k + 1], ac + Vector2.from_angle(deg_to_rad(inner[k])) * 268.0, 128)
		var outer := [180.0, 195.0, 210.0, 225.0, 240.0, 255.0, 270.0]
		var nodes: Array = [roll_btn, jump_btn, skill_btns[5], skill_btns[6], skill_btns[7], skill_btns[8], potion_btn]
		for k in outer.size():
			_place(nodes[k], ac + Vector2.from_angle(deg_to_rad(outer[k])) * 440.0, 108)
		_place(target_btn, ac + Vector2.from_angle(deg_to_rad(202.0)) * 600.0, 100)

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

## Подписи клавиш на кнопках и шпаргалка (после переназначения — обновляются)
func refresh_key_hints() -> void:
	if not Game.desktop: return
	skill_btns[0].key_hint = Controls.key_hint("attack")
	for i in range(1, skill_btns.size()): skill_btns[i].key_hint = Controls.key_hint("skill_%d" % i)
	potion_btn.key_hint = Controls.key_hint("potion")
	target_btn.key_hint = Controls.key_hint("target_next")
	_key_e = " [%s]" % Controls.key_hint("interact")
	for b in skill_btns + [potion_btn, target_btn]: b.queue_redraw()
	if bars != null and bars.root != null: bars.refresh_keys()
	for it in MENU_ITEMS:
		if menu_items.has(it[0]):
			menu_items[it[0]].text = it[1] + ("  [%s]" % Controls.key_hint(it[3]) if it[3] != "" else ("  [Esc]" if it[0] == "pause" else ""))
	var help = root.find_child("KeyHelp", false, false)
	if help:
		var K := func(a): return Controls.key_hint(a)
		help.text = "%s%s%s%s — ход · %s — атака · 1…0, F1…F12 — ярлыки\n%s — цель · %s — сброс цели · ПКМ — камера\n%s — прыжок · %s — кувырок · %s — зелье · %s — герой\n%s — умения · %s — таланты · %s — карта · Esc — меню" % [
			K.call("move_up"), K.call("move_left"), K.call("move_down"), K.call("move_right"), K.call("attack"), K.call("target_next"), K.call("target_clear"),
			K.call("jump"), K.call("roll"), K.call("potion"), K.call("hero"), K.call("skills"), K.call("talents"), K.call("map")]

func refresh_skill_buttons() -> void:
	if bars != null and bars.root != null: bars.refresh_all()
	for i in range(1, skill_btns.size()):
		var s = player.get_skill(i)
		skill_btns[i].text = s.name if s != null else "Пусто"
		skill_btns[i].icon = UIK.icon(UIK.SKILL_ICONS.get(s.id, "magic-swirl")) if s != null else UIK.icon("aura")
		var sc: Color = s.color if s != null else Color(0.4, 0.4, 0.4)
		skill_btns[i].color = Color(sc.r * 0.55, sc.g * 0.55, sc.b * 0.55, 1)
		skill_btns[i].queue_redraw()

# ---------------- ПК: клавиатура и мышь ----------------
## Сенсорные элементы прячем, на кнопках умений — подсказки клавиш
var bars: ShortcutBars
func _setup_desktop() -> void:
	# v0.9.3: панели ярлыков в стиле L2 вместо ряда круглых кнопок
	bars = ShortcutBars.new(); bars.name = "ShortcutBars"
	zone.add_child.call_deferred(bars)
	bars.ready.connect(func(): bars.setup(self), CONNECT_ONE_SHOT)
	joy_base.visible = false
	jump_btn.visible = false
	roll_btn.visible = false
	refresh_key_hints()
	var help := UIK.label(root, "", 17, Color(1, 1, 1, 0.6))
	help.name = "KeyHelp"
	help.autowrap_mode = TextServer.AUTOWRAP_OFF
	help.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	help.add_theme_constant_override("outline_size", 5)
	help.anchor_top = 1; help.anchor_bottom = 1
	help.offset_left = 20; help.offset_right = 480; help.offset_top = -150; help.offset_bottom = -20
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE

## Горячие клавиши (true — событие обработано). v0.9.0: по действиям Controls (переназначаются в настройках)
## Совместимость (тесты): нажатие клавиши по коду
func _hotkey(k: int) -> bool:
	var ev := InputEventKey.new(); ev.keycode = k; ev.physical_keycode = k; ev.pressed = true
	return _hotkey_ev(ev)

const WINDOW_ACTIONS := {"Window_hero": "hero", "Window_talents": "talents", "Window_skills": "skills", "Window_shop": "interact"}
func _hotkey_ev(ev: InputEvent) -> bool:
	var esc: bool = ev is InputEventKey and (ev as InputEventKey).keycode == KEY_ESCAPE
	var act := Controls.action_of(ev)
	if window != null:
		if esc or (act != "" and WINDOW_ACTIONS.get(String(window.name), "") == act):
			close_window(); return true
		return false
	if esc and menu_open:
		close_menu()
		return true
	if esc:
		if zone.target_ctl and zone.target_ctl.has_target():   # Esc сначала сбрасывает цель, затем — меню
			zone.target_ctl.clear(); return true
		_open("pause"); return true
	# v0.9.3: ПК — клавиши 1…0 и F1…F12 срабатывают по ячейкам панелей ярлыков
	if bars != null and act.begins_with("bar_page_"):
		bars.page(0, 1 if act == "bar_page_next" else -1); return true
	if bars != null and (act.begins_with("skill_") or act.begins_with("bar2_")):
		var bs := ShortcutBars.slot_of_action(act)
		bars.activate(int(bs[0]), int(bs[1]))
		return true
	if act.begins_with("skill_"):
		var i := int(act.substr(6))
		if i >= skill_btns.size(): return false
		player.try_use(i)
		skill_btns[i].set_held(true)
		get_tree().create_timer(0.12).timeout.connect(func(): if is_instance_valid(skill_btns[i]): skill_btns[i].set_held(false))
		return true
	match act:
		"jump": press_jump()
		"roll": press_roll()
		"potion": player.use_potion()
		"hero": _open("hero")
		"skills": _open("skills")
		"talents": _open("talents")
		"map":
			if zone.builder is WorldBuilder: _open("map")
			else: minimap.toggle_big()
		"interact":
			if not interact(): return false
		"target_next": if zone.target_ctl: zone.target_ctl.cycle()
		"target_clear": if zone.target_ctl: zone.target_ctl.clear()
		"target_self": if zone.target_ctl: zone.target_ctl.select(player)
		"attack":
			if ev is InputEventMouseButton: return false   # ЛКМ по миру — обычная логика (выбор цели/атака)
			player.attack_held = true
		_: return false
	return true

# ---------------- окна ----------------
func _open(which: String) -> void:
	if menu_btn: close_menu(true)
	if window: window.queue_free()
	_hide_tooltip()
	match which:
		"talents": window = preload("res://scripts/ui/talent_tree_ui.gd").new()
		"hero": window = preload("res://scripts/ui/inventory_ui.gd").new()
		"shop": window = preload("res://scripts/ui/shop_ui.gd").new()
		"stash": window = preload("res://scripts/ui/stash_ui.gd").new()
		"map": window = preload("res://scripts/ui/world_map_ui.gd").new()
		"skills": window = preload("res://scripts/ui/skills_ui.gd").new()
		"craft": window = preload("res://scripts/ui/craft_ui.gd").new()
		"market": window = preload("res://scripts/ui/market_ui.gd").new()
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
	_set_main_view(false)

func close_window() -> void:
	if window: UIK.pop_out(window)
	window = null
	_set_main_view(true)
	get_tree().paused = false
	refresh_skill_buttons()

## v0.9.1: рамки группы, онлайн-список, чат и панели рейда — только на основном экране
func _set_main_view(v: bool) -> void:
	if zone == null: return
	if zone.party_ui and "ui_root" in zone.party_ui and zone.party_ui.ui_root: zone.party_ui.ui_root.visible = v
	if zone.raid and zone.raid.ui: zone.raid.ui.visible = v
	if Net._overlay and is_instance_valid(Net._overlay) and Net._overlay.ui_root: Net._overlay.ui_root.visible = v
	_hide_tooltip()

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
	Game.sfx("level")
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
	var sp := DB.skill_points_free(player.data) if player != null else 0
	var sub := UIK.label(b, "Очков талантов: %d · очков умений: %d — «Таланты» и «Умения»" % [points, sp], 26, UIK.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
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
	"skills": "Есть очко умений! Откройте «Умения», изучите умение и поставьте его в любой слот.",
	"shop": "Рядом торговец: нажмите «Торговать», чтобы купить зелья и снаряжение или продать добычу.",
	"boss": "Красные зоны — предупреждение об атаке босса. Уходите из них или делайте кувырок!",
}

## v0.9.3: на ПК — текст про клавиатуру и мышь (с текущими клавишами), на телефоне — про касания
func _hint_text(id: String) -> String:
	if not Game.desktop: return HINTS[id]
	var K := func(a): return Controls.key_hint(a)
	match id:
		"move": return "%s%s%s%s — движение, правая кнопка мыши — поворот камеры, колесо — приближение." % [K.call("move_up"), K.call("move_left"), K.call("move_down"), K.call("move_right")]
		"attack": return "%s — атака: три удара подряд — комбо. Умения — клавиши 1…0 и F1…F12 на панелях внизу." % K.call("attack")
		"jump": return "%s — прыжок через ударные волны, %s — кувырок с мигом неуязвимости." % [K.call("jump"), K.call("roll")]
		"talents": return "Есть свободное очко! Откройте «Таланты» (%s) и изучите новый узел." % K.call("talents")
		"skills": return "Есть очко умений! Откройте «Умения» (%s) и перетащите умение на панель ярлыков." % K.call("skills")
		"shop": return "Рядом торговец: нажмите %s, чтобы купить зелья и снаряжение или продать добычу." % K.call("interact")
	return HINTS[id]

func _tut() -> Dictionary: return zone.data["tutorial"]

func show_hint(id: String) -> void:
	if _tut().get(id, false) or hint_id == id: return
	hint_id = id
	_hint_age = 0.0
	hint_label.text = _hint_text(id)
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
	elif hint_id == "skills" and DB.skill_points_free(zone.data) == 0: _mark_hint("skills")
	elif hint_id == "shop" and not zone.near_merchant(): hint_id = ""; hint_panel.visible = false
	elif hint_id == "boss" and _hint_age > 9: _mark_hint("boss")
	if hint_id != "": return
	if not t.get("move", false): show_hint("move")
	elif not t.get("attack", false): show_hint("attack")
	elif not t.get("jump", false): show_hint("jump")
	elif zone.near_merchant() and not t.get("shop", false): show_hint("shop")
	elif DB.skill_points_free(zone.data) > 0 and not t.get("skills", false) and t.get("jump", false): show_hint("skills")
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

# ---------------- v0.9.1: подсказки по баффам (ПК — наведение, телефон — долгое нажатие) ----------------
var buff_tip: PanelContainer
var buff_tip_text: RichTextLabel
var _tip_icon: Control = null
var _tip_touch := false
var _tip_press_t := -1.0
var _tip_press_ms := 0
var _tip_press_icon: Control = null
var _tip_mouse := Vector2(-1, -1)

func buff_icon_at(p: Vector2) -> Control:
	for ic in get_tree().get_nodes_in_group("buff_icon"):
		var c := ic as Control
		if c.is_visible_in_tree() and c.has_meta("b") and c.get_global_rect().grow(4).has_point(p): return c
	return null

func _ensure_tip() -> void:
	if buff_tip != null: return
	buff_tip = PanelContainer.new(); buff_tip.name = "BuffTip"
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.05, 0.04, 0.07, 0.95); sb.border_color = UIK.ACCENT
	sb.set_border_width_all(2); sb.set_corner_radius_all(10); sb.set_content_margin_all(12)
	buff_tip.add_theme_stylebox_override("panel", sb)
	buff_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buff_tip.z_index = 100
	buff_tip_text = RichTextLabel.new(); buff_tip_text.bbcode_enabled = true; buff_tip_text.fit_content = true
	buff_tip_text.custom_minimum_size = Vector2(440, 0); buff_tip_text.scroll_active = false
	buff_tip_text.add_theme_font_size_override("normal_font_size", 22); buff_tip_text.add_theme_font_size_override("bold_font_size", 24)
	buff_tip_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buff_tip.add_child(buff_tip_text)
	root.add_child(buff_tip)
	buff_tip.visible = false

func show_buff_tip(ic: Control) -> void:
	_ensure_tip()
	_tip_icon = ic
	buff_tip.visible = ic != null
	_update_buff_tip()

func _update_buff_tip() -> void:
	if buff_tip == null or not buff_tip.visible: return
	if _tip_icon == null or not is_instance_valid(_tip_icon) or not _tip_icon.is_visible_in_tree() or not _tip_icon.has_meta("b"):
		buff_tip.visible = false; _tip_icon = null; return
	buff_tip_text.text = Support.describe_buff(_tip_icon.get_meta("b"))
	buff_tip.reset_size()
	var r := _tip_icon.get_global_rect()
	var s := _screen()
	var pos := Vector2(r.position.x, r.end.y + 8)
	if pos.y + buff_tip.size.y > s.y - 10: pos.y = r.position.y - buff_tip.size.y - 8
	pos.x = clampf(pos.x, 10, s.x - buff_tip.size.x - 10)
	buff_tip.global_position = pos

## каждый кадр: долгое нажатие (0.35 с) или наведение мыши
func _tick_buff_tip(delta: float) -> void:
	if _tip_press_icon != null:
		_tip_press_t = (Time.get_ticks_msec() - _tip_press_ms) / 1000.0   # реальное время (не зависит от замедлений)
		if _tip_press_t >= 0.35 and _tip_icon != _tip_press_icon: show_buff_tip(_tip_press_icon)
	elif not _tip_touch and (Game.desktop or not DisplayServer.is_touchscreen_available()):
		var mp := get_viewport().get_mouse_position()
		if mp != _tip_mouse:   # наведение — только когда мышь двигалась (не гасит показанную нажатием подсказку)
			_tip_mouse = mp
			var ic := buff_icon_at(mp)
			if ic != _tip_icon: show_buff_tip(ic)
	_update_buff_tip()

func _over_top_button(p: Vector2) -> bool:
	if menu_open and not (menu_panel.get_global_rect().has_point(p) or menu_btn.get_global_rect().has_point(p)):
		close_menu()
		return true   # клик мимо открытого меню — закрыть (клик поглощается)
	for b in top_buttons + blockers:
		if b.is_visible_in_tree() and b.get_global_rect().has_point(p): return true
	return false

func _input(ev: InputEvent) -> void:
	if player != null and ev is InputEventKey and not ev.pressed and Controls.action_of(ev) == "attack":
		player.attack_held = false
	var extra_mb: bool = ev is InputEventMouseButton and ev.pressed and (ev.button_index == MOUSE_BUTTON_MIDDLE or ev.button_index >= MOUSE_BUTTON_XBUTTON1)
	if player != null and ((ev is InputEventKey and ev.pressed and not ev.echo) or extra_mb):
		if _hotkey_ev(ev):
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
	if bars != null and bars.over(p): return
	var bic := buff_icon_at(p)
	if bic != null:
		touches[idx] = {"role": "buff"}
		_tip_touch = idx != -1
		_tip_press_icon = bic; _tip_press_t = 0.0; _tip_press_ms = Time.get_ticks_msec()
		if idx == -1: show_buff_tip(bic)
		return
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
	if target_btn.visible and target_btn.hit(p):
		touches[idx] = {"role": "target"}
		target_btn.set_held(true)
		if zone.target_ctl: zone.target_ctl.cycle()
		return
	if potion_btn.hit(p):
		touches[idx] = {"role": "potion"}
		potion_btn.set_held(true)
		player.use_potion()
		return
	# v0.9.4.1: клик/касание по добыче на земле — подобрать (вместо атаки, джойстика или камеры)
	if window == null and not _over_ui(p):
		var lt := Loot.at_screen(zone, p)
		if lt != null:
			touches[idx] = {"role": "loot"}
			lt.manual_pick(); return
	if Game.desktop and idx == -1:
		# ЛКМ по миру — атака (удержание — серия ударов)
		if window == null and not _over_ui(p):
			# v0.9.0: клик по врагу/союзнику — выбор цели; по пустой земле — сброс цели (и обычная атака)
			# v0.9.1: ЛКМ на ПК — это атака: клик по пустой земле захват цели НЕ снимает (Esc / × / Tab)
			var picked = zone.target_ctl.pick(p) if zone.target_ctl else null
			if picked == player: picked = null   # v0.9.4: свой герой под курсором (камера за спиной) — не «союзник», это атака
			if picked != null: zone.target_ctl.select(picked)
			if picked != null and not (picked is Enemy): return   # союзник выбран — без атаки
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
	touches[idx] = {"role": "cam", "pos": p, "start": p, "t0": Time.get_ticks_msec(), "moved": false}

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
		"buff":
			pass   # палец на значке — подсказка остаётся до отпускания
		"joy":
			var v: Vector2 = (p - t["origin"]).limit_length(JOY_R)
			_set_joy(t["origin"], v)
			player.move_input = Vector2(v.x, -v.y) / JOY_R
		"cam":
			t["pos"] = p
			if p.distance_to(t.get("start", p)) > 18.0: t["moved"] = true
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
		"buff":
			_tip_press_icon = null; _tip_press_t = -1.0
			if _tip_touch: show_buff_tip(null)
			_tip_touch = false
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
		"target":
			target_btn.set_held(false)
		"cam":
			# короткое касание без сдвига — выбор цели (или сброс по пустой земле)
			if not t.get("moved", true) and Time.get_ticks_msec() - int(t.get("t0", 0)) < 450 and zone.target_ctl and touches.size() == 1:
				zone.target_ctl.tap(t["pos"])
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
	_menu_anim()
	if player == null or player.stats.is_empty(): return
	if window == null: _tick_buff_tip(delta)
	elif buff_tip != null and buff_tip.visible: show_buff_tip(null)
	if window == null:
		_update_hints(delta)
		for k in _hold_time.keys():
			_hold_time[k] += delta
			if k > 0 and _hold_time[k] > 0.55 and _tip_slot != k:
				show_skill_tooltip(k); _tip_slot = k
	var it: Dictionary = zone.nearest_interactable()
	var near_loot: bool = it.is_empty() and not zone.near_merchant() and Loot.nearest(zone) != null
	interact_btn.visible = window == null and (zone.near_merchant() or not it.is_empty() or near_loot)
	if interact_btn.visible:
		interact_btn.text = ("Торговать" if zone.near_merchant() else ("Подобрать" if near_loot else str(it["text"]))) + _key_e
		interact_btn.icon = UIK.icon("shop" if zone.near_merchant() else ("chest" if near_loot else str(it.get("icon", "cog"))))
	_update_cast()
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
	_update_goal_beacon()
	var free := DB.free_points(d)
	talent_badge.get_parent().visible = free > 0
	talent_badge.text = str(free)
	var sfree := DB.skill_points_free(d)
	skill_badge.get_parent().visible = sfree > 0
	skill_badge.text = str(sfree)
	if menu_btn: menu_btn.get_node("MenuBadge").visible = free > 0 or sfree > 0
	for i in range(1, skill_btns.size()):
		var lock: String = player.lock_reason(i)
		var mx := player.max_cooldown(i)
		skill_btns[i].set_state(clampf(player.cooldowns[i] / mx, 0, 1) if mx > 0 else 0.0, player.cooldowns[i], lock)
	_update_enemy_bars()
	_update_target_frame()
	_fill_buffs(self_buffs, _player_buffs())

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
			var rs := UIK.label(bar, "", 16, Color(0.85, 0.85, 0.85), HORIZONTAL_ALIGNMENT_CENTER)
			UIK.rect(rs, Vector2(-85, 16), Vector2(300, 24))
			rs.autowrap_mode = TextServer.AUTOWRAP_OFF
			rs.name = "Res"
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
		var nc := Color(1, 0.35, 0.3) if diff >= 3 else (Color(0.7, 0.7, 0.7) if diff <= -3 else Color.WHITE)
		if e.rank in ["elite", "rare"]: nc = Enemy.RANK_COLORS[e.rank]
		nl.add_theme_color_override("font_color", nc)
		# сопротивления/уязвимости — у элит, редких, боссов и у ближних врагов
		var rl: Label = b.get_node("Res")
		rl.text = Combat.resist_text(e.kind, e.rank, e.def.boss) if (e.rank != "normal" or e.def.boss or dist < 9.0) else ""
		if not e.affixes.is_empty(): rl.text = "[" + e.affix_text() + "]" + ("\n" + rl.text if rl.text != "" else "")
	for i in range(used, bar_pool.size()): bar_pool[i].visible = false
	boss_panel.visible = boss != null
	if boss != null:
		_fill_buffs(boss_buffs, boss.buffs.values())
		_set_bar(boss_bar, boss.hp, boss.max_hp, "%d / %d" % [ceili(boss.hp), roundi(boss.max_hp)])
		var rec := Combat.boss_rec(boss.kind, boss.level)
		var rec_c := "ff6655" if int(zone.data["level"]) < rec else "bbffaa"
		boss_name.text = str(boss.def.name) + "  ·  ур. %d" % boss.level
		boss_name.add_theme_font_size_override("font_size", 30 if boss_name.text.length() <= 24 else 23)   # длинные имена боссов мира не наезжают на фазу
		if boss_res: boss_res.text = "[center][color=#%s]Рекомендуемый уровень: %d+[/color]   %s[/center]" % [rec_c, rec, Combat.resist_text(boss.kind, boss.rank, true)]
		var br = boss.brain
		if br:
			boss_phase.text = "Фаза %d · %s" % [br.phase, br.PHASE_NAMES[br.phase]] + ("  · ЯРОСТЬ" if br.enraged else "")
			var fill: StyleBoxFlat = boss_bar.get_theme_stylebox("fill")
			var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
			fill.bg_color = Color(0.95, 0.25 + 0.2 * pulse, 0.05) if br.enraged else (Color(0.85, 0.2, 0.08) if br.phase == 2 else Color(0.78, 0.1, 0.1))
			for f in [66, 33]:
				var m: ColorRect = boss_bar.get_node("Mark%d" % f)
				m.color = Color(1, 0.85, 0.4, 0.95) if boss.hp / boss.max_hp > f / 100.0 else Color(0.4, 0.35, 0.3, 0.7)

var _key_e := ""
## Взаимодействие: торговец или ближайший рычаг/механизм. true — что-то сделано
func interact() -> bool:
	if zone.near_merchant():
		_open("shop"); return true
	var it: Dictionary = zone.nearest_interactable()
	if it.is_empty():
		var l := Loot.nearest(zone)   # v0.9.4.1: «Взаимодействие» рядом с добычей — подобрать
		if l == null: return false
		l.manual_pick(); return true
	it["cb"].call()
	return true

# ---- полоса заклинаний босса и предупреждение ----
var cast_panel: Panel
var cast_bar: ProgressBar
var cast_label: Label
var warn_label: Label
var enrage_label: Label
func _build_cast_ui() -> void:
	cast_panel = UIK.panel(root, Color(0.08, 0.04, 0.1, 0.9))
	cast_panel.anchor_left = 0.5; cast_panel.anchor_right = 0.5
	cast_panel.offset_left = -330; cast_panel.offset_right = 330; cast_panel.offset_top = 244; cast_panel.offset_bottom = 300
	cast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cast_bar = UIK.bar(cast_panel, Color(0.7, 0.35, 1.0))
	UIK.rect(cast_bar, Vector2(10, 8), Vector2(640, 40))
	cast_label = UIK.label(cast_bar, "", 24, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	cast_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	UIK.full(cast_label)
	cast_label.add_theme_color_override("font_outline_color", Color.BLACK)
	cast_label.add_theme_constant_override("outline_size", 6)
	cast_panel.visible = false
	warn_label = UIK.label(root, "", 40, Color(1, 0.45, 0.35), HORIZONTAL_ALIGNMENT_CENTER)
	warn_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	warn_label.add_theme_color_override("font_outline_color", Color.BLACK)
	warn_label.add_theme_constant_override("outline_size", 10)
	warn_label.anchor_left = 0.5; warn_label.anchor_right = 0.5
	warn_label.offset_left = -600; warn_label.offset_right = 600; warn_label.offset_top = 310; warn_label.offset_bottom = 370
	warn_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	warn_label.visible = false
	enrage_label = UIK.label(boss_panel, "", 20, Color(1, 0.75, 0.5), HORIZONTAL_ALIGNMENT_RIGHT)
	enrage_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	UIK.rect(enrage_label, Vector2(420, 104), Vector2(356, 26))

func _update_cast() -> void:
	if cast_panel == null: _build_cast_ui()
	var boss = null
	for e in zone.enemies:
		if is_instance_valid(e) and e.alive and e.def.boss and (e.brain is WardenBrain or e.brain is RaidBrain): boss = e
	var br = boss.brain if boss else null
	var on: bool = br != null and br.cast_name != "" and br.cast_total > 0
	cast_panel.visible = on
	warn_label.visible = on
	if on:
		_set_bar(cast_bar, br.cast_total - br.cast_left, br.cast_total, "")
		cast_label.text = "%s  ·  %.1f с" % [br.cast_name, br.cast_left]
		warn_label.text = br.cast_hint
		var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.012)
		warn_label.modulate.a = pulse
	enrage_label.visible = br != null and br.engaged
	if br and br.engaged:
		var left: float = br.enrage_left()
		enrage_label.text = "Ярость через %d:%02d" % [int(left) / 60, int(left) % 60] if left > 0 else "ЯРОСТЬ!"

func _objective() -> String:
	var o := _objective0()
	var did := DB.dungeon_of_zone(str(zone.data.get("zone", "")))   # v0.9.2: уровень и остаток прохождений
	if did != "": o += "\n" + DB.dungeon_info(zone.data, did)
	elif zone.builder is StarterZoneBuilder and DB.zone_flag(zone.data, "starter", "boss_troll_killed"):
		var lk := DB.dungeon_lock(zone.data, "dungeon")
		o += "\nСклеп Эфира: " + (DB.dungeon_info(zone.data, "dungeon") if lk == "" else lk)
	return o

func _objective0() -> String:
	if zone.builder is PartyDungeonBuilder: return zone.builder.objective()
	if zone.builder is WorldBuilder:
		var lv := int(zone.data["level"])
		var best := 0
		for i in WorldData.BIOMES.size():
			if int(WorldData.BIOMES[i].lv[0]) <= lv + 1: best = i
		var bz: Dictionary = WorldData.BIOMES[best]
		return "Цель: %s (ур. %d–%d) — путевые камни на карте (M / касание мини-карты)" % [bz.name, bz.lv[0], bz.lv[1]]
	if zone.is_dungeon():
		var b = zone.builder
		if b.boss_enemy() == null and b.return_portal != null:
			return "Хранитель повержен! Войдите в золотой портал на арене — он вернёт к началу долины"
		if not b.gate_open():
			if b.packs_left() > 0 and zone.player.global_position.z < 40: return "Цель: пройти коридор ловушек (шипы — по таймингу или прыжком)"
			return "Цель: рычаги в порядке с таблички у решётки (Пламя → Лёд → Тень)"
		if zone.player.global_position.z < 86: return "Цель: огненный коридор — проходите между струями"
		return "Цель: победить Хранителя Эфира (прячьтесь за колоннами, впитывайте разлом)"
	if DB.zone_lock_reason(zone.data, "dungeon") == "" and not DB.zone_flag(zone.data, "dungeon", "boss_warden_killed"):
		var troll := false
		for e in zone.enemies:
			if e.alive and e.def.boss: troll = true
		if not troll: return "Цель: Склеп Эфира открыт — вход к западу от руин"
	var boss_alive := false
	for e in zone.enemies:
		if e.alive and e.def.boss: boss_alive = true
	if boss_alive: return "Цель: победить Древнего тролля в руинах (рек. ур. %d+, череп на карте)" % Combat.boss_rec("troll", 9)
	return "Цель: портал в Земли Эфира — выход в мир (синий портал, отмечен на мини-карте)"

## v0.9.1: точка текущей цели (для мини-карты, стрелки к цели и маяка в мире); Vector3.INF — нет точки.
## В долине цель «выйти в мир» ведёт к порталу в Земли Эфира, а не ко входу в Склеп.
func objective_target() -> Vector3:
	if zone == null or zone.builder == null or zone.player == null: return Vector3.INF
	if zone.builder is PartyDungeonBuilder or zone.builder is WorldBuilder: return Vector3.INF
	if zone.is_dungeon():
		return zone.builder.guide_target() if zone.builder.has_method("guide_target") else Vector3.INF
	for e in zone.enemies:
		if e.alive and e.def.boss: return zone.arena_point
	if DB.zone_lock_reason(zone.data, "dungeon") == "" and not DB.zone_flag(zone.data, "dungeon", "boss_warden_killed") and zone.dungeon_gate_point != Vector3.ZERO:
		return zone.dungeon_gate_point
	return zone.portal_point if zone.portal_point != Vector3.ZERO else Vector3.INF

var goal_beacon: Node3D
func _update_goal_beacon() -> void:
	var t := objective_target()
	if goal_beacon == null or not is_instance_valid(goal_beacon):
		goal_beacon = Node3D.new(); goal_beacon.name = "GoalBeacon"
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new(); cm.top_radius = 0.35; cm.bottom_radius = 0.9; cm.height = 14.0
		mi.mesh = cm; mi.position.y = 7.0
		var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(1.0, 0.82, 0.35, 0.22); m.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = m; mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		goal_beacon.add_child(mi)
		zone.add_child(goal_beacon)
	goal_beacon.visible = t != Vector3.INF and not zone.is_dungeon() and U.flat_dist(t, player.global_position) > 6.0
	if t != Vector3.INF: goal_beacon.global_position = Vector3(t.x, zone.ground_y(t) if zone.has_method("ground_y") else t.y, t.z)


# ---------------- v0.9.0: рамка цели и значки баффов ----------------
func _build_target_frame() -> void:
	target_frame = UIK.panel(root, Color(0.06, 0.05, 0.08, 0.88))
	target_frame.name = "TargetFrame"
	target_frame.anchor_left = 0.5; target_frame.anchor_right = 0.5
	target_frame.offset_left = -330; target_frame.offset_right = 330; target_frame.offset_top = 124; target_frame.offset_bottom = 226
	target_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tf_name = UIK.label(target_frame, "", 24, UIK.ACCENT)
	tf_name.autowrap_mode = TextServer.AUTOWRAP_OFF; tf_name.clip_text = true
	UIK.rect(tf_name, Vector2(16, 2), Vector2(560, 32))
	tf_hp = UIK.bar(target_frame, Color(0.75, 0.15, 0.12)); UIK.rect(tf_hp, Vector2(16, 36), Vector2(400, 28))
	tf_hp.get_node("Text").add_theme_font_size_override("font_size", 17)
	tf_mp = UIK.bar(target_frame, Color(0.2, 0.4, 0.95)); UIK.rect(tf_mp, Vector2(16, 68), Vector2(400, 14))
	tf_mp.get_node("Text").visible = false
	tf_buffs = HBoxContainer.new(); tf_buffs.name = "Buffs"
	tf_buffs.add_theme_constant_override("separation", 4)
	tf_buffs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target_frame.add_child(tf_buffs); UIK.rect(tf_buffs, Vector2(426, 36), Vector2(224, 40))
	var x := UIK.button(target_frame, "×", func(): if zone.target_ctl: zone.target_ctl.clear(), Color(0.35, 0.2, 0.2), 24)
	x.name = "Clear"
	x.custom_minimum_size = Vector2(56, 40); UIK.rect(x, Vector2(596, 2), Vector2(56, 40))
	blockers.append(x)
	target_frame.visible = false

func _player_buffs() -> Array:
	var out: Array = player.buffs.values()
	if player.shield_hp > 0.0:
		out = out.duplicate()
		out.append({"id": "_shield", "icon": "magic-shield", "col": Color(0.6, 0.85, 1.0), "t": -1.0, "dur": 0.0, "good": true, "name": "Щит", "desc": "поглощает ещё %d урона" % roundi(player.shield_hp)})
	return out

## Значки: [{icon, col, t (осталось; <0 — без таймера), good, name}]
func _fill_buffs(box: HBoxContainer, list: Array) -> void:
	if box == null: return
	while box.get_child_count() < mini(list.size(), 8):
		var ic := TextureRect.new()
		ic.custom_minimum_size = Vector2(34, 34)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.mouse_filter = Control.MOUSE_FILTER_STOP   # v0.9.1: наведение / долгое нажатие — подсказка
		ic.add_to_group("buff_icon")
		var stl := UIK.label(ic, "", 13, Color(1, 0.85, 0.4)); stl.name = "St"
		stl.autowrap_mode = TextServer.AUTOWRAP_OFF
		stl.add_theme_color_override("font_outline_color", Color.BLACK); stl.add_theme_constant_override("outline_size", 4)
		UIK.rect(stl, Vector2(1, -4), Vector2(30, 18))
		var bg := ColorRect.new(); bg.name = "Bg"; bg.show_behind_parent = true; bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ic.add_child(bg); UIK.full(bg)
		var tl := UIK.label(ic, "", 14, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT); tl.name = "T"
		tl.autowrap_mode = TextServer.AUTOWRAP_OFF
		tl.add_theme_color_override("font_outline_color", Color.BLACK); tl.add_theme_constant_override("outline_size", 4)
		UIK.rect(tl, Vector2(-6, 16), Vector2(40, 20))
		box.add_child(ic)
	for i in box.get_child_count():
		var ic: TextureRect = box.get_child(i)
		ic.visible = i < list.size()
		if not ic.visible: continue
		var b: Dictionary = list[i]
		ic.texture = UIK.icon(str(b.get("icon", "aura")))
		ic.modulate = b.get("col", Color.WHITE)
		(ic.get_node("Bg") as ColorRect).color = Color(0.1, 0.35, 0.12, 0.85) if b.get("good", true) else Color(0.45, 0.08, 0.08, 0.85)
		var tt := float(b.get("t", -1.0))
		(ic.get_node("T") as Label).text = ("%d" % ceili(tt)) if tt >= 0.0 else ""
		(ic.get_node("St") as Label).text = ("×%d" % int(b.st)) if int(b.get("st", 1)) > 1 else ""
		ic.set_meta("b", b)

## Баффы удалённого игрока — из состояния группы (сервер)
static func party_buffs(m: Dictionary) -> Array:
	var out := []
	for b in m.get("bf", []):
		var e := {"id": str(b[0]), "icon": str(b[1]), "col": Color.html(str(b[2])), "t": float(b[3]), "dur": float(b[4]), "good": bool(b[5])}
		if b.size() > 9: e.merge({"name": str(b[6]), "desc": str(b[7]), "st": int(b[8]), "src": str(b[9])})
		out.append(e)
	return out

func _update_target_frame() -> void:
	var tc = zone.target_ctl
	var t = tc.target if tc and tc.has_target() else null
	target_frame.visible = t != null
	if t == null: return
	var nm := ""; var lvl := 0; var hpv := 1.0; var hpm := 1.0; var mpf := -1.0; var bl: Array = []
	var col := UIK.ACCENT
	if t is Enemy:
		nm = t.display_name; lvl = t.level; hpv = t.hp; hpm = t.max_hp
		bl = t.buffs.values()
		if t.curse_timer > 0: bl = bl.duplicate(); bl.append({"icon": "cursed-star", "col": Color(0.6, 0.3, 0.9), "t": t.curse_timer, "dur": 8.0, "good": false, "name": "Проклятие", "id": "curse"})
		col = Color(1, 0.45, 0.4)
	elif t is Player:
		nm = str(zone.data["name"]) + " (вы)"; lvl = int(zone.data["level"]); hpv = t.hp; hpm = t.stats.max_hp
		mpf = t.mp / maxf(1.0, t.stats.max_mp); bl = _player_buffs(); col = Color(0.5, 1, 0.55)
	elif t is RemotePlayer:
		nm = t.pname; lvl = t.level; hpv = t.hp_frac; hpm = 1.0
		var m := Net.party_member(int(t.peer_id))
		if not m.is_empty(): mpf = float(m.get("mp", 1.0)); bl = party_buffs(m)
		col = Color(0.5, 0.85, 1.0)
	elif t is Minion:
		nm = "Скелет (призванный)"; lvl = int(zone.data["level"]); hpv = t.hp; hpm = t.max_hp
		bl = t.buffs.values(); col = Color(0.6, 1, 0.6)
	tf_name.text = "%s · ур. %d" % [nm, lvl]
	tf_name.add_theme_color_override("font_color", col)
	_set_bar(tf_hp, hpv, hpm, ("%d / %d" % [ceili(hpv), roundi(hpm)]) if hpm > 1.0 else "%d%%" % roundi(hpv * 100.0))
	tf_mp.visible = mpf >= 0.0
	if mpf >= 0.0: tf_mp.max_value = 1.0; tf_mp.value = mpf
	_fill_buffs(tf_buffs, bl)
