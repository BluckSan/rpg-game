extends Node
## Сессия: текущий персонаж, сохранения (user://saves), переходы между сценами, всплывающие сообщения.

const SAVE_DIR := "user://saves"
var current: Dictionary = {}
var _toast_layer: CanvasLayer
var _toast_label: Label
var _toast_panel: PanelContainer
var _toast_time := 0.0
var shadows_enabled := true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	_build_toast()
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		shadows_enabled = cfg.get_value("video", "shadows", true)

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("video", "shadows", shadows_enabled)
	cfg.save("user://settings.cfg")

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
