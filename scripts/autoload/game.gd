extends Node
## Сессия: текущий персонаж, сохранения (user://saves), переходы между сценами, всплывающие сообщения.

const SAVE_DIR := "user://saves"
var current: Dictionary = {}
var _toast_layer: CanvasLayer
var _toast_label: Label
var _toast_panel: PanelContainer
var _toast_time := 0.0
var shadows_enabled := true
## ПК-режим: клавиатура и мышь, без сенсорных кнопок. На Android всегда false.
var desktop := false
var fullscreen := true
var resolution := Vector2i(1920, 1080)
var quality := 1          # 0 низкое, 1 среднее, 2 высокое
var ui_scale := 1.0
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]
const QUALITY_NAMES := ["Низкое", "Среднее", "Высокое"]
const UI_SCALES := [0.85, 1.0, 1.1]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	desktop = is_pc_platform() and not "--touch" in OS.get_cmdline_user_args()
	if desktop: quality = 2
	_setup_input_map()
	_build_toast()
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		shadows_enabled = cfg.get_value("video", "shadows", true)
		fullscreen = cfg.get_value("video", "fullscreen", fullscreen)
		resolution = cfg.get_value("video", "resolution", resolution)
		quality = clampi(cfg.get_value("video", "quality", quality), 0, 2)
		ui_scale = clampf(cfg.get_value("video", "ui_scale", ui_scale), 0.7, 1.5)
	if not "--no-window-settings" in OS.get_cmdline_user_args():
		apply_settings.call_deferred()

static func is_pc_platform() -> bool:
	return OS.has_feature("pc") and not OS.has_feature("mobile") and not OS.has_feature("android")

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("video", "shadows", shadows_enabled)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "resolution", resolution)
	cfg.set_value("video", "quality", quality)
	cfg.set_value("video", "ui_scale", ui_scale)
	cfg.save("user://settings.cfg")

## Применить окно/качество/масштаб интерфейса
func apply_settings() -> void:
	var vp := get_tree().root
	vp.content_scale_factor = ui_scale
	match quality:
		0:
			vp.msaa_3d = Viewport.MSAA_DISABLED; vp.scaling_3d_scale = 0.75
			RenderingServer.directional_shadow_atlas_set_size(1024, true)
		1:
			vp.msaa_3d = Viewport.MSAA_2X; vp.scaling_3d_scale = 1.0
			RenderingServer.directional_shadow_atlas_set_size(2048, true)
		_:
			vp.msaa_3d = Viewport.MSAA_4X; vp.scaling_3d_scale = 1.0
			RenderingServer.directional_shadow_atlas_set_size(4096, true)
	if desktop and DisplayServer.get_name() != "headless":
		if fullscreen:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var scr := DisplayServer.screen_get_size()
			var sz := Vector2i(mini(resolution.x, scr.x), mini(resolution.y, scr.y))
			DisplayServer.window_set_size(sz)
			DisplayServer.window_set_position(DisplayServer.screen_get_position() + (scr - sz) / 2)

func resolution_text() -> String:
	return "%d×%d" % [resolution.x, resolution.y]

## Клавиши ПК: WASD + стрелки
func _setup_input_map() -> void:
	var map := {"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT], "move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN]}
	for a in map:
		if not InputMap.has_action(a): InputMap.add_action(a, 0.2)
		for k in map[a]:
			var ev := InputEventKey.new(); ev.physical_keycode = k
			InputMap.action_add_event(a, ev)

# ---------- сохранения ----------
func list_characters() -> Array:
	var out := []
	var d := DirAccess.open(SAVE_DIR)
	if d == null: return out
	for f in d.get_files():
		if f.begins_with("char_") and f.ends_with(".json"):
			var c = load_file(SAVE_DIR + "/" + f)
			if c is Dictionary and c.has("id"):
				out.append(c)
	out.sort_custom(func(a, b): return float(a["created"]) < float(b["created"]))
	return out

func load_file(path: String):
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null: return null
	var data = JSON.parse_string(fa.get_as_text())
	if not (data is Dictionary): 
		push_warning("Повреждённое сохранение: " + path)
		return null
	return normalize(data)

## JSON превращает целые в float — возвращаем типы.
func normalize(c: Dictionary) -> Dictionary:
	for k in ["level", "xp", "class_level", "class_xp", "gold", "potions", "kills"]:
		c[k] = int(c.get(k, 0))
	var t := []
	for id in c.get("talents", []): t.append(int(id))
	c["talents"] = t
	for list_name in ["inventory", "equipped"]:
		for it in c.get(list_name, []):
			it["slot"] = int(it["slot"]); it["rarity"] = int(it["rarity"]); it["ilvl"] = int(it["ilvl"])
	if not c.has("zones") or not (c["zones"] is Dictionary): c["zones"] = {}
	var look: Dictionary = c.get("look", {})
	for k in ["gender", "skin", "face", "hair", "hair_color", "eye_color"]:
		look[k] = int(look.get(k, 0))
	c["look"] = look
	return c

func save_character(c: Dictionary) -> void:
	if c.is_empty(): return
	var path := SAVE_DIR + "/char_%s.json" % c["id"]
	var tmp := path + ".tmp"
	var fa := FileAccess.open(tmp, FileAccess.WRITE)
	if fa == null:
		push_error("Не удалось сохранить: " + str(FileAccess.get_open_error()))
		return
	fa.store_string(JSON.stringify(c))
	fa.close()
	DirAccess.rename_absolute(tmp, path)

func delete_character(id: String) -> void:
	DirAccess.remove_absolute(SAVE_DIR + "/char_%s.json" % id)

# ---------- сцены ----------
func play(c: Dictionary) -> void:
	current = c
	var z: Dictionary = DB.ZONES.get(c["zone"], DB.ZONES["starter"])
	if not z["available"]:
		c["zone"] = "starter"; z = DB.ZONES["starter"]
	get_tree().paused = false
	get_tree().change_scene_to_file(z["scene"])

func travel(zone_id: String) -> void:
	var z = DB.ZONES.get(zone_id)
	if z == null or not z["available"]: return
	current["zone"] = zone_id
	current["has_pos"] = false
	save_character(current)
	get_tree().change_scene_to_file(z["scene"])

func to_menu() -> void:
	save_character(current)
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

# ---------- сообщения ----------
func _build_toast() -> void:
	_toast_layer = CanvasLayer.new()
	_toast_layer.layer = 100
	add_child(_toast_layer)
	_toast_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.75)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 30; sb.content_margin_right = 30; sb.content_margin_top = 14; sb.content_margin_bottom = 14
	_toast_panel.add_theme_stylebox_override("panel", sb)
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_layer.add_child(_toast_panel)
	_toast_label = Label.new()
	_toast_label.add_theme_font_size_override("font_size", 32)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_panel.add_child(_toast_label)
	_toast_panel.visible = false

func toast(msg: String, seconds := 2.5) -> void:
	_toast_label.text = msg
	_toast_panel.visible = true
	_toast_panel.modulate.a = 1.0
	_toast_panel.reset_size()
	_place_toast()
	_toast_time = seconds

func _process(delta: float) -> void:
	if _toast_time > 0:
		_toast_time -= delta
		_toast_panel.modulate.a = clampf(_toast_time * 2, 0, 1)
		_place_toast()
		if _toast_time <= 0: _toast_panel.visible = false

func _place_toast() -> void:
	var vs := get_viewport().get_visible_rect().size
	_toast_panel.position = Vector2((vs.x - _toast_panel.size.x) / 2, vs.y * 0.24)
