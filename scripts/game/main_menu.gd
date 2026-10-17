extends Node3D
## Главное меню: выбор персонажа (6 слотов), удаление, создание. 3D-превью справа.

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

func _ready() -> void:
	_build_stage()
	ui = CanvasLayer.new()
	add_child(ui)
	show_select()

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
	var sun := DirectionalLight3D.new()
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
	target_x = 0.3
	var title := UIK.label(s, "ОСКОЛКИ ЭФИРА", 72, UIK.ACCENT)
	UIK.place(title, 0.03, 0.86, 0.6, 0.98)
	UIK.place(UIK.label(s, "Выбор персонажа", 34), 0.03, 0.8, 0.5, 0.87)
	var lp := UIK.panel(s)
	UIK.place(lp, 0.03, 0.16, 0.36, 0.79)
	list_box = UIK.scroll_list(lp, 12)
	var create := UIK.button(s, "+ Создать персонажа", open_creator, UIK.GREEN, 36)
	UIK.place(create, 0.03, 0.04, 0.36, 0.14)
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
	del_btn.text = "Точно?" if confirm_delete else "Удалить"
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

func _on_delete() -> void:
	if selected == null: return
	if not confirm_delete:
		confirm_delete = true
		update_selection()
		return
	Game.delete_character(selected["id"])
	selected = null
	confirm_delete = false
	refresh_list()

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
