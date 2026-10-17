extends Node3D
## Главное меню: титульный экран («Играть», «Настройки», «Выход») с 3D-сценой у костра,
## выбор персонажа (6 слотов), удаление с подтверждением, создание. 3D-превью справа.

var ui: CanvasLayer
var screen: Control
var stage_pivot: Node3D
var preview: CharVisual
var yaw := 0.0
var auto_spin := 1.0
var target_x := 0.3
var cam: Camera3D
var focus := false
var _focus_t := 0.0
var _head_y := -1.0

var chars: Array = []
var selected = null
var confirm_delete := false
var list_box: VBoxContainer
var info: RichTextLabel
var play_btn: Button
var del_btn: Button
var title_root: Node3D
var title_mode := false
var confirm_box: Control
var sun: DirectionalLight3D
static var start_on_select := false   # после выхода из игры — сразу к выбору героя

func _ready() -> void:
	_build_stage()
	ui = CanvasLayer.new()
	add_child(ui)
	_build_title_scene()
	if start_on_select:
		start_on_select = false
		show_select()
	else:
		show_title()

func _build_stage() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.08, 0.07, 0.1)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.43, 0.5)
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	cam = Camera3D.new()
	cam.fov = 35
	add_child(cam)
	cam.position = Vector3(0, 1.3, 5.6)
	cam.look_at(Vector3(0, 1.0, 0))
	cam.current = true
	sun = DirectionalLight3D.new()
	sun.light_color = Color(1, 0.92, 0.82)
	sun.shadow_enabled = true
	sun.light_energy = 1.25
	sun.directional_shadow_max_distance = 12
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.6, 0.7, 1.0); fill.light_energy = 0.45
	add_child(fill)
	fill.rotation_degrees = Vector3(-15, -130, 0)
	add_child(sun)
	sun.rotation_degrees = Vector3(-35, 30, 0)
	var rim := OmniLight3D.new()
	rim.light_color = Color(1, 0.55, 0.2); rim.light_energy = 2.5; rim.omni_range = 8
	add_child(rim)
	rim.position = Vector3(-1.5, 2.5, -1.5)
	stage_pivot = Node3D.new()
	add_child(stage_pivot)
	U.prim("cylinder", stage_pivot, Vector3(0, -0.05, 0), Vector3(2.2, 0.05, 2.2), Color(0.2, 0.18, 0.2))
	U.prim("cylinder", stage_pivot, Vector3(0, -0.02, 0), Vector3(1.9, 0.05, 1.9), Color(0.6, 0.4, 0.15), 0.4, 0.3)
	preview = CharVisual.new()
	preview.speed_override = 0
	stage_pivot.add_child(preview)

func show_preview(look, class_id := "warrior", asc := "") -> void:
	preview.visible = look != null
	if look != null:
		preview.build(look, class_id, asc)

## Крупный план лица (редактор внешности)
func set_focus(v: bool) -> void:
	focus = v
	if preview: preview.set_neutral(v)
	if v:
		yaw = fposmod(yaw + PI, TAU) - PI
		auto_spin = 0

func rotate_preview(dx: float) -> void:
	yaw -= dx * 0.008
	auto_spin = 0

func _process(delta: float) -> void:
	if title_mode:
		_title_t += delta
		var a := _title_t * 0.05
		cam.position = Vector3(sin(a) * 1.0 + 1.4, 1.75, -6.6 + cos(a) * 0.4)
		cam.look_at(Vector3(-0.9, 1.05, -14.0))
		cam.fov = 45
		for sh in _shards:
			sh.position.y = sh.get_meta("y0") + sin(_title_t * 0.8 + sh.get_meta("ph")) * 0.25
			sh.rotation.y += delta * 0.5
		return
	stage_pivot.position.x = lerpf(stage_pivot.position.x, target_x, delta * 6)
	if focus:
		auto_spin = 0
		yaw = lerpf(yaw, clampf(yaw, -0.9, 0.9), delta * 2)
	else:
		auto_spin = move_toward(auto_spin, 1, delta * 0.3)
	yaw += delta * 0.2 * auto_spin
	stage_pivot.rotation.y = yaw
	_focus_t = move_toward(_focus_t, 1.0 if focus else 0.0, delta * 2.5)
	var t := smoothstep(0.0, 1.0, _focus_t)
	var hy := 1.62
	if preview and preview.skel and is_instance_valid(preview.skel):
		var hb: int = preview.skel.find_bone(preview._head_bone())
		if hb >= 0:
			var target_y: float = (preview.skel.global_transform * preview.skel.get_bone_global_pose(hb)).origin.y + 0.1
			_head_y = target_y if _head_y < 0 else lerpf(_head_y, target_y, minf(1.0, delta * 3))
			hy = _head_y
	var px := stage_pivot.position.x
	var body_pos := Vector3(0, 1.3, 5.6)
	var face_pos := Vector3(px - 0.2, hy + 0.03, 1.15)
	cam.position = body_pos.lerp(face_pos, t)
	cam.look_at(Vector3(0, 1.0, 0).lerp(Vector3(px - 0.2, hy - 0.02, 0), t))
	cam.fov = lerpf(35, 30, t)

# ---------------- титульный экран ----------------
var _title_t := 0.0
var _shards: Array[Node3D] = []

## Фон: поляна у костра в сумерках, три героя, парящие осколки эфира (дёшево: без теней на телефоне)
func _build_title_scene() -> void:
	title_root = Node3D.new(); title_root.name = "TitleScene"
	add_child(title_root)
	title_root.position = Vector3(0, 0, -14)
	var base := U.prim("cylinder", title_root, Vector3(0, -0.1, 0), Vector3(30, 0.1, 30), Color(0.16, 0.2, 0.14))
	base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rng := RandomNumberGenerator.new(); rng.seed = 42
	for i in 26:
		var a := rng.randf() * TAU; var r := rng.randf_range(7.0, 14.0)
		var p := Vector3(cos(a) * r, 0, sin(a) * r - 2.0)
		if p.z > 3.0: continue
		var h := rng.randf_range(2.5, 4.5)
		U.prim("cylinder", title_root, p + Vector3(0, h * 0.25, 0), Vector3(0.25, h * 0.25, 0.25), Color(0.25, 0.16, 0.1)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		U.prim("cone", title_root, p + Vector3(0, h * 0.75, 0), Vector3(1.8, h, 1.8), Color(0.1, 0.22, 0.15).lerp(Color(0.12, 0.17, 0.2), rng.randf())).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in 8:
		var a := rng.randf() * TAU
		U.prim("sphere", title_root, Vector3(cos(a) * rng.randf_range(3, 6), 0.1, sin(a) * rng.randf_range(3, 6)), Vector3.ONE * rng.randf_range(0.5, 1.1), Color(0.35, 0.34, 0.36))
	# костёр
	for i in 5:
		var a := TAU * i / 5.0
		U.prim("cylinder", title_root, Vector3(cos(a) * 0.35, 0.12, sin(a) * 0.35), Vector3(0.1, 0.4, 0.1), Color(0.3, 0.18, 0.1)).rotation = Vector3(PI / 2.6, -a, 0)
	var fire := U.prim("cone", title_root, Vector3(0, 0.45, 0), Vector3(0.55, 0.9, 0.55), Color(1, 0.55, 0.15), 0.3, 4.0)
	fire.set_script(preload("res://scripts/game/flicker.gd"))
	fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fl := OmniLight3D.new(); fl.light_color = Color(1, 0.6, 0.25); fl.light_energy = 3.0; fl.omni_range = 9.0
	fl.shadow_enabled = Game.desktop and Game.quality >= 3
	fl.set_script(preload("res://scripts/game/flicker.gd"))
	title_root.add_child(fl); fl.position = Vector3(0, 1.2, 0)
	var em := CPUParticles3D.new(); em.amount = maxi(6, int(30 * Game.particle_mul)); em.lifetime = 2.2
	em.direction = Vector3.UP; em.spread = 20; em.initial_velocity_min = 0.6; em.initial_velocity_max = 1.4
	em.gravity = Vector3(0, 0.3, 0); em.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE; em.emission_sphere_radius = 0.3
	var q := QuadMesh.new(); q.size = Vector2(0.06, 0.06); q.material = U.fx_mat(Color(1, 0.6, 0.2))
	em.mesh = q
	title_root.add_child(em); em.position = Vector3(0, 0.6, 0)
	# осколки эфира
	for i in 7:
		var sh := Node3D.new(); title_root.add_child(sh)
		var c := Color(0.45, 0.8, 1.0).lerp(Color(0.75, 0.45, 1.0), rng.randf())
		var top := U.prim("cone", sh, Vector3(0, 0.3, 0), Vector3(0.35, 0.6, 0.35), c, 0.2, 3.0)
		var bot := U.prim("cone", sh, Vector3(0, -0.3, 0), Vector3(0.35, 0.6, 0.35), c, 0.2, 3.0); bot.rotation.x = PI
		top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; bot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a := -PI * 0.1 - PI * 0.8 * i / 6.0
		sh.position = Vector3(cos(a) * 5.5, rng.randf_range(2.2, 4.2), sin(a) * 4.0 - 2.5)
		sh.scale = Vector3.ONE * rng.randf_range(0.6, 1.2)
		sh.set_meta("y0", sh.position.y); sh.set_meta("ph", rng.randf() * TAU)
		_shards.append(sh)
		if i % 2 == 0:
			var l := OmniLight3D.new(); l.light_color = c; l.light_energy = 1.2; l.omni_range = 4.0; sh.add_child(l)
	# герои у костра
	var heroes := [["warrior", "paladin", 0, Vector3(-1.9, 0, 0.6), 0.5], ["mage", "", 1, Vector3(0.1, 0, 1.6), 0.0], ["archer", "", 0, Vector3(2.0, 0, 0.6), -0.5]]
	for hdef in heroes:
		var v := CharVisual.new(); title_root.add_child(v)
		v.build(CharAssets.random_look(hdef[2], rng), hdef[0], hdef[1])
		v.position = hdef[3]; v.rotation.y = hdef[4]
		v.speed_override = 0
	title_root.visible = false

func _set_title_mode(v: bool) -> void:
	title_mode = v
	title_root.visible = v
	title_root.process_mode = Node.PROCESS_MODE_INHERIT if v else Node.PROCESS_MODE_DISABLED
	stage_pivot.visible = not v
	# телефон: на титульном экране без теней и с низким пределом кадров — меню должно быть дешёвым
	sun.shadow_enabled = Game.shadows_enabled and (Game.desktop or not v)
	sun.directional_shadow_max_distance = 22.0 if v else 12.0
	sun.light_energy = 0.35 if v else 1.25
	var we: WorldEnvironment = get_child(0) as WorldEnvironment
	if we:
		var e := we.environment
		if v:
			e.background_color = Color(0.05, 0.05, 0.1)
			e.ambient_light_color = Color(0.25, 0.28, 0.42); e.ambient_light_energy = 0.7
			e.fog_enabled = true; e.fog_light_color = Color(0.08, 0.09, 0.16); e.fog_density = 0.035
			e.glow_enabled = Game.glow; e.glow_intensity = 0.6; e.glow_hdr_threshold = 1.0
		else:
			e.background_color = Color(0.08, 0.07, 0.1)
			e.ambient_light_color = Color(0.45, 0.43, 0.5); e.ambient_light_energy = 0.8
			e.fog_enabled = false; e.glow_enabled = false

func show_title() -> void:
	var s := _new_screen()
	_set_title_mode(true)
	s.name = "TitleScreen"
	var shade := ColorRect.new(); s.add_child(shade)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIK.place(shade, 0.0, 0.0, 0.42, 1.0)
	var gm := GradientTexture2D.new(); var g := Gradient.new()
	g.set_color(0, Color(0.03, 0.03, 0.06, 0.88)); g.set_color(1, Color(0.03, 0.03, 0.06, 0.0))
	gm.gradient = g; gm.fill_from = Vector2(0, 0); gm.fill_to = Vector2(1, 0)
	shade.queue_free()
	var tr := TextureRect.new(); tr.texture = gm; tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.add_child(tr); UIK.place(tr, 0.0, 0.0, 0.5, 1.0)
	var title := UIK.label(s, "ОСКОЛКИ ЭФИРА", 96, UIK.ACCENT)
	title.add_theme_font_override("font", UIK.title_font())
	title.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.02)); title.add_theme_constant_override("outline_size", 10)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	UIK.place(title, 0.05, 0.7, 0.6, 0.86)
	var sub := UIK.label(s, "Офлайн-RPG · классы, пути превращения, лут", 30, UIK.MUTED)
	sub.autowrap_mode = TextServer.AUTOWRAP_OFF
	UIK.place(sub, 0.055, 0.64, 0.6, 0.7)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 22)
	s.add_child(v); UIK.place(v, 0.055, 0.2, 0.32, 0.6)
	var bp := UIK.button(v, "Играть", show_select, UIK.GOLD, 46, "crossed-swords"); bp.name = "PlayButton"; UIK.min_h(bp, 120)
	var bs := UIK.button(v, "Настройки", show_settings, UIK.BUTTON, 38, "cog"); bs.name = "SettingsButton"; UIK.min_h(bs, 104)
	var bq := UIK.button(v, "Выход", quit_game, UIK.RED, 38); bq.name = "QuitButton"; UIK.min_h(bq, 104)
	var ver := UIK.label(s, "v%s" % ProjectSettings.get_setting("application/config/version"), 24, Color(1, 1, 1, 0.45), HORIZONTAL_ALIGNMENT_RIGHT)
	UIK.place(ver, 0.6, 0.93, 0.98, 0.99)

func show_settings() -> void:
	var sp := SettingsPanel.new()
	ui.add_child(sp)
	sp.setup(func():
		if title_mode: _set_title_mode(true))
	UIK.pop_in(sp)

## Выход из игры (ПК и Android)
func quit_game() -> void:
	Game.save_settings()
	if "--no-quit" in OS.get_cmdline_user_args(): return
	Game.clear_lock()
	get_tree().quit()

# ---------------- экран выбора ----------------
func _new_screen() -> Control:
	if screen: screen.queue_free()
	screen = Control.new()
	UIK.full(screen)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(screen)
	return screen

func show_select() -> void:
	var s := _new_screen()
	_set_title_mode(false)
	s.name = "SelectScreen"
	target_x = 0.3
	var title := UIK.label(s, "ОСКОЛКИ ЭФИРА", 72, UIK.ACCENT)
	UIK.place(title, 0.03, 0.86, 0.6, 0.98)
	UIK.place(UIK.label(s, "Выбор персонажа", 34), 0.03, 0.8, 0.5, 0.87)
	var lp := UIK.panel(s)
	UIK.place(lp, 0.03, 0.16, 0.36, 0.79)
	list_box = UIK.scroll_list(lp, 12)
	var create := UIK.button(s, "+ Создать", open_creator, UIK.GREEN, 36)
	create.name = "CreateButton"
	UIK.place(create, 0.03, 0.04, 0.24, 0.14)
	var back := UIK.button(s, "Назад", show_title, UIK.BUTTON, 32)
	back.name = "BackButton"
	UIK.place(back, 0.25, 0.04, 0.36, 0.14)
	var ip := UIK.panel(s, Color(0, 0, 0, 0.55))
	UIK.place(ip, 0.7, 0.2, 0.98, 0.62)
	info = UIK.rich(ip, "", 30)
	UIK.full(info); info.offset_left = 24; info.offset_top = 20; info.offset_right = -24; info.offset_bottom = -20
	play_btn = UIK.button(s, "ИГРАТЬ", _on_play, UIK.GOLD, 44)
	UIK.place(play_btn, 0.7, 0.04, 0.88, 0.16)
	del_btn = UIK.button(s, "Удалить", _on_delete, UIK.RED, 28)
	UIK.place(del_btn, 0.89, 0.04, 0.97, 0.16)
	var ver := UIK.label(s, "v%s · офлайн · Godot" % ProjectSettings.get_setting("application/config/version"), 22, Color(1, 1, 1, 0.4), HORIZONTAL_ALIGNMENT_RIGHT)
	UIK.place(ver, 0.6, 0.92, 0.98, 0.99)
	var sb := UIK.button(s, "", show_settings, UIK.BUTTON, 26, "cog")
	sb.name = "SettingsButton"
	UIK.place(sb, 0.92, 0.82, 0.98, 0.92)
	refresh_list()

func refresh_list() -> void:
	chars = Game.list_characters()
	UIK.clear(list_box)
	if selected != null:
		var sid = selected["id"]
		selected = null
		for c in chars:
			if c["id"] == sid: selected = c
	if selected == null and chars.size() > 0:
		selected = chars[-1]
	for c in chars:
		var cls: Dictionary = DB.CLASSES[c["class"]]
		var asc := DB.get_asc(c["ascendancy"])
		var txt := "%s\n%s · ур. %d · мастерство %d" % [c["name"], asc["name"] if not asc.is_empty() else cls.name, c["level"], c["class_level"]]
		var b := UIK.button(list_box, txt, _select.bind(c), UIK.BUTTON, 30)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		UIK.min_h(b, 120)
		b.set_meta("char_id", c["id"])
	for i in range(chars.size(), DB.MAX_SLOTS):
		var b := UIK.button(list_box, "Пустой слот", open_creator, Color(0.13, 0.14, 0.18), 28)
		b.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		UIK.min_h(b, 90)
	update_selection()

func _select(c) -> void:
	selected = c
	confirm_delete = false
	update_selection()

func update_selection() -> void:
	for b in list_box.get_children():
		if b.has_meta("char_id"):
			UIK.set_button_color(b, Color(0.45, 0.35, 0.15) if selected != null and b.get_meta("char_id") == selected["id"] else UIK.BUTTON)
	play_btn.disabled = selected == null
	del_btn.disabled = selected == null
	del_btn.text = "Удалить"
	if selected == null:
		info.text = "Нет персонажей.\nСоздайте своего первого героя!"
		show_preview(null)
		return
	var c: Dictionary = selected
	var cls: Dictionary = DB.CLASSES[c["class"]]
	var asc := DB.get_asc(c["ascendancy"])
	var t := int(c["play_time"])
	info.text = "[font_size=44][b]%s[/b][/font_size]\nКласс: %s (мастерство %d)\nПуть: %s\nУровень: %d\nЛокация: %s\nУбито врагов: %d\nВ игре: %d ч %d мин" % [
		c["name"], cls.name, c["class_level"], asc["name"] if not asc.is_empty() else "не выбран", c["level"],
		DB.ZONES[c["zone"]]["name"], c["kills"], t / 3600, (t / 60) % 60]
	show_preview(c["look"], c["class"], c["ascendancy"])

func _on_play() -> void:
	if selected != null:
		Game.play(selected)

## Удаление — только после подтверждения в отдельном окне
func _on_delete() -> void:
	if selected == null: return
	_close_confirm()
	confirm_delete = true
	confirm_box = Control.new(); confirm_box.name = "ConfirmDelete"
	UIK.full(confirm_box); ui.add_child(confirm_box)
	UIK.full(UIK.panel(confirm_box, Color(0, 0, 0, 0.65), 0))
	var p := UIK.panel(confirm_box)
	p.anchor_left = 0.5; p.anchor_right = 0.5; p.anchor_top = 0.5; p.anchor_bottom = 0.5
	p.offset_left = -440; p.offset_right = 440; p.offset_top = -230; p.offset_bottom = 230
	UIK.place(UIK.label(p, "Удалить героя?", 46, UIK.ACCENT, HORIZONTAL_ALIGNMENT_CENTER), 0.05, 0.74, 0.95, 0.94)
	var body := UIK.label(p, "«%s», ур. %d, будет удалён навсегда.\nЭто действие нельзя отменить." % [selected["name"], selected["level"]], 28, UIK.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	UIK.place(body, 0.05, 0.36, 0.95, 0.72)
	var yes := UIK.button(p, "Удалить", confirm_delete_now, UIK.RED, 34); yes.name = "ConfirmYes"
	UIK.place(yes, 0.06, 0.07, 0.47, 0.3)
	var no := UIK.button(p, "Отмена", cancel_delete, UIK.BUTTON, 34); no.name = "ConfirmNo"
	UIK.place(no, 0.53, 0.07, 0.94, 0.3)
	UIK.pop_in(p)

func confirm_delete_now() -> void:
	if selected != null:
		Game.delete_character(selected["id"])
	selected = null
	confirm_delete = false
	_close_confirm()
	refresh_list()

func cancel_delete() -> void:
	confirm_delete = false
	_close_confirm()

func _close_confirm() -> void:
	if confirm_box and is_instance_valid(confirm_box): confirm_box.queue_free()
	confirm_box = null

func open_creator() -> void:
	if Game.list_characters().size() >= DB.MAX_SLOTS:
		Game.toast("Все слоты заняты. Удалите персонажа.")
		return
	var s := _new_screen()
	var cr := preload("res://scripts/ui/creator.gd").new()
	UIK.full(cr)
	s.add_child(cr)
	cr.setup(self, func(created):
		if created != null:
			Game.save_character(created)
			selected = created
		show_select())
