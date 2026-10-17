extends CanvasLayer
## Игровой интерфейс: полосы, джойстик, кнопки умений, окна. Мультитач обрабатывается здесь.

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
var joy_base: Control
var joy_knob: Control
var joy_default := Vector2(260, 840)
const JOY_R := 110.0
var pickup_box: VBoxContainer
var boss_bar: ProgressBar
var window: Control
var bar_pool := []
var top_buttons := []

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

	var status := UIK.panel(root, Color(0, 0, 0, 0.45))
	status.position = Vector2(20, 20); status.size = Vector2(580, 175)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label = UIK.label(status, "", 26)
	name_label.position = Vector2(16, 6); name_label.size = Vector2(550, 50)
	hp_bar = UIK.bar(status, Color(0.8, 0.15, 0.15)); hp_bar.position = Vector2(16, 62); hp_bar.size = Vector2(548, 46)
	mp_bar = UIK.bar(status, Color(0.2, 0.4, 0.9)); mp_bar.position = Vector2(16, 116); mp_bar.size = Vector2(548, 46)
	gold_label = UIK.label(root, "", 26, Color(1, 0.85, 0.35))
	gold_label.position = Vector2(28, 200); gold_label.size = Vector2(500, 40)

	xp_bar = UIK.bar(root, Color(0.85, 0.65, 0.15))
	xp_bar.anchor_left = 0.25; xp_bar.anchor_right = 0.75; xp_bar.anchor_top = 1; xp_bar.anchor_bottom = 1
	xp_bar.offset_top = -28; xp_bar.offset_bottom = 0
	xp_bar.get_node("Text").add_theme_font_size_override("font_size", 18)

	var b_tal := _top_button("Таланты", _open.bind("talents"), Color(0.35, 0.25, 0.45), 0, 200)
	talent_badge = UIK.label(b_tal, "", 24, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	var badge_bg := UIK.panel(b_tal, Color(0.85, 0.2, 0.2), 22)
	badge_bg.position = Vector2(170, -14); badge_bg.size = Vector2(44, 44)
	badge_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	talent_badge.reparent(badge_bg); UIK.full(talent_badge)
	_top_button("Герой", _open.bind("hero"), UIK.BUTTON, 1, 170)
	_top_button("Меню", _open.bind("pause"), UIK.BUTTON, 2, 150)

	# боевые кнопки (координаты от правого нижнего угла)
	var cls: Dictionary = DB.CLASSES[zone.data["class"]]
	skill_btns.append(_skill_button(cls.skills[0].name, Vector2(-60, -60), 230, Color(0.75, 0.3, 0.2)))
	var pos := [Vector2.ZERO, Vector2(-320, -60), Vector2(-280, -250), Vector2(-110, -320)]
	for i in range(1, 4):
		skill_btns.append(_skill_button("", pos[i], 150, Color.GRAY))
	potion_btn = _skill_button("Зелье", Vector2(-470, -40), 110, Color(0.8, 0.15, 0.25))
	potion_label = UIK.label(potion_btn, "", 26, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	potion_label.position = Vector2(0, 70); potion_label.size = Vector2(110, 40)

	joy_base = Control.new(); joy_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	joy_base.size = Vector2(JOY_R * 2, JOY_R * 2)
	joy_base.draw.connect(func(): joy_base.draw_circle(Vector2(JOY_R, JOY_R), JOY_R, Color(1, 1, 1, 0.18)))
	root.add_child(joy_base)
	joy_knob = Control.new(); joy_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	joy_knob.size = Vector2(100, 100)
	joy_knob.draw.connect(func(): joy_knob.draw_circle(Vector2(50, 50), 50, Color(1, 1, 1, 0.55)))
	joy_base.add_child(joy_knob)
	_set_joy(joy_default, Vector2.ZERO)

	pickup_box = VBoxContainer.new()
	pickup_box.alignment = BoxContainer.ALIGNMENT_END
	pickup_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pickup_box.position = Vector2(24, 300); pickup_box.size = Vector2(600, 300)
	root.add_child(pickup_box)

	boss_bar = UIK.bar(root, Color(0.7, 0.1, 0.1))
	boss_bar.anchor_left = 0.5; boss_bar.anchor_right = 0.5
	boss_bar.offset_left = -400; boss_bar.offset_right = 400; boss_bar.offset_top = 30; boss_bar.offset_bottom = 76
	boss_bar.visible = false
	refresh_skill_buttons()

func _top_button(t: String, cb: Callable, c: Color, idx: int, w: float) -> Button:
	var b := UIK.button(root, t, cb, c, 28)
	b.anchor_left = 1; b.anchor_right = 1
	var right: float = -20.0 - [0.0, 220.0, 410.0][idx]
	b.offset_right = right; b.offset_left = right - w; b.offset_top = 20; b.offset_bottom = 100
	top_buttons.append(b)
	return b

func _skill_button(t: String, offset: Vector2, sz: float, c: Color) -> SkillButton:
	var sb := SkillButton.new()
	sb.text = t; sb.color = c
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
		skill_btns[i].color = (s.color * 0.8 + Color(0, 0, 0, 1)) if s != null else Color(0.3, 0.3, 0.3)
		skill_btns[i].queue_redraw()

# ---------------- окна ----------------
func _open(which: String) -> void:
	if window: window.queue_free()
	match which:
		"talents": window = preload("res://scripts/ui/talent_tree_ui.gd").new()
		"hero": window = preload("res://scripts/ui/inventory_ui.gd").new()
		_: window = preload("res://scripts/ui/pause_menu.gd").new()
	UIK.full(window)
	add_child(window)
	window.setup(zone)
	_release_all()
	get_tree().paused = true

func close_window() -> void:
	if window: window.queue_free()
	window = null
	get_tree().paused = false
	refresh_skill_buttons()

func pickup(t: String, c: Color) -> void:
	var l := UIK.label(pickup_box, t, 26, c)
	get_tree().create_timer(3.0).timeout.connect(l.queue_free)

# ---------------- ввод ----------------
func _release_all() -> void:
	touches.clear()
	player.move_input = Vector2.ZERO
	player.attack_held = false
	for b in skill_btns: b.set_held(false)
	_set_joy(joy_default, Vector2.ZERO)

func _over_top_button(p: Vector2) -> bool:
	for b in top_buttons:
		if b.get_global_rect().has_point(p): return true
	return false

func _input(ev: InputEvent) -> void:
	if window != null: return
	if ev is InputEventScreenTouch:
		if ev.pressed: _touch_down(ev.index, ev.position)
		else: _touch_up(ev.index)
	elif ev is InputEventScreenDrag:
		_touch_move(ev.index, ev.position, ev.relative)
	# мышь на ПК (без тача): ЛКМ по кнопкам
	elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not DisplayServer.is_touchscreen_available():
		if ev.pressed: _touch_down(-1, ev.position)
		else: _touch_up(-1)
	elif ev is InputEventMouseMotion and touches.has(-1) and not DisplayServer.is_touchscreen_available():
		_touch_move(-1, ev.position, ev.relative)

func _screen() -> Vector2:
	return root.get_viewport_rect().size

func _touch_down(idx: int, p: Vector2) -> void:
	if _over_top_button(p): return
	for i in skill_btns.size():
		if skill_btns[i].hit(p):
			touches[idx] = {"role": "skill", "slot": i}
			skill_btns[i].set_held(true)
			if i == 0: player.attack_held = true
			else: player.try_use(i)
			return
	if potion_btn.hit(p):
		touches[idx] = {"role": "potion"}
		potion_btn.set_held(true)
		player.use_potion()
		return
	var s := _screen()
	if p.x < s.x * 0.42 and p.y > s.y * 0.25 and not _has_role("joy"):
		touches[idx] = {"role": "joy", "origin": p}
		_set_joy(p, Vector2.ZERO)
		return
	touches[idx] = {"role": "cam", "pos": p}

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
			if t["slot"] == 0: player.attack_held = false
		"potion":
			potion_btn.set_held(false)
	touches.erase(idx)
	pinch_last = 0

func _set_joy(center: Vector2, knob: Vector2) -> void:
	joy_base.position = center - Vector2(JOY_R, JOY_R)
	joy_knob.position = Vector2(JOY_R, JOY_R) + knob - Vector2(50, 50)

# ---------------- обновление ----------------
func _process(_delta: float) -> void:
	if player == null or player.stats.is_empty(): return
	var d: Dictionary = zone.data
	joy_default = Vector2(260, _screen().y - 240)
	if not _has_role("joy"): _set_joy(joy_default, Vector2.ZERO)
	var asc := DB.get_asc(d["ascendancy"])
	name_label.text = "%s  ур. %d  ·  %s (мастерство %d)" % [d["name"], d["level"], asc["name"] if not asc.is_empty() else DB.CLASSES[d["class"]].name, d["class_level"]]
	_set_bar(hp_bar, player.hp, player.stats.max_hp, "%d / %d" % [ceili(player.hp), roundi(player.stats.max_hp)])
	_set_bar(mp_bar, player.mp, player.stats.max_mp, "%d / %d" % [floori(player.mp), roundi(player.stats.max_mp)])
	var need := DB.xp_to_next(d["level"])
	_set_bar(xp_bar, d["xp"], need, "Опыт %d / %d" % [d["xp"], need])
	gold_label.text = "Золото: %d" % d["gold"]
	potion_label.text = "x%d " % d["potions"]
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
			nm.position = Vector2(-85, -38); nm.size = Vector2(300, 34)
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
	boss_bar.visible = boss != null
	if boss != null:
		_set_bar(boss_bar, boss.hp, boss.max_hp, boss.display_name)
