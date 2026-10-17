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
## Пресет графики: 0 экономия батареи, 1 низкое, 2 среднее, 3 высокое, 4 ультра (только ПК)
var quality := 2
var ui_scale := 1.0
var render_scale := 1.0    # доля разрешения 3D-сцены (интерфейс всегда в полном разрешении)
var fps_cap := 60
var vsync := true          # только ПК
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]
const QUALITY_NAMES := ["Экономия батареи", "Низкое", "Среднее", "Высокое", "Ультра"]
## «Ультра» (ПК, Forward+): отдельные переключатели тяжёлых эффектов
var ultra_gi := true       # глобальное освещение SDFGI
var ultra_ssr := true      # экранные отражения
var ultra_fog := true      # объёмный туман
## Безопасный запуск: прошлая сессия не завершилась штатно, зажат Shift или --safe-graphics → «Среднее»
const SESSION_LOCK := "user://session.lock"
var safe_start := false
var safe_reason := ""
const UI_SCALES := [0.85, 1.0, 1.1]
const RENDER_SCALES := [0.5, 0.6, 0.75, 0.85, 1.0]
const FPS_MOBILE := [30, 45, 60, 90, 120]
const FPS_PC := [30, 60, 90, 120, 144, 165, 240, 300]
## Производные от пресета (заполняет apply_settings)
var view_distance := 110.0
var particle_mul := 1.0
var shadow_distance := 40.0
var glow := true
var music_volume := 0.6
var sfx_volume := 0.8
var sensitivity := 1.0     # чувствительность камеры (0.4–2.0)
var skill_layout := ""      # панель умений: "mobile" — веер у кнопки атаки, "pc" — ряд внизу по центру
var _music: AudioStreamPlayer
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_streams := {}
var _sfx_players := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	desktop = is_pc_platform() and not "--touch" in OS.get_cmdline_user_args()
	# по умолчанию: телефон — «Среднее», 3D 75%, 60 кадров (меньше нагрев); ПК — «Высокое», 100%, 144
	if desktop:
		quality = 3; render_scale = 1.0; fps_cap = 144
	else:
		quality = 2; render_scale = 0.75; fps_cap = 60
	_setup_input_map()
	_build_toast()
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		shadows_enabled = cfg.get_value("video", "shadows", true)
		fullscreen = cfg.get_value("video", "fullscreen", fullscreen)
		resolution = cfg.get_value("video", "resolution", resolution)
		quality = clampi(cfg.get_value("video", "preset", quality), 0, max_quality())
		ultra_gi = cfg.get_value("video", "ultra_gi", ultra_gi)
		ultra_ssr = cfg.get_value("video", "ultra_ssr", ultra_ssr)
		ultra_fog = cfg.get_value("video", "ultra_fog", ultra_fog)
		render_scale = clampf(cfg.get_value("video", "render_scale", render_scale), 0.5, 1.0)
		fps_cap = int(cfg.get_value("video", "fps_cap", fps_cap))
		if not fps_cap in fps_options(): fps_cap = 60
		vsync = cfg.get_value("video", "vsync", vsync)
		ui_scale = clampf(cfg.get_value("video", "ui_scale", ui_scale), 0.7, 1.5)
		music_volume = clampf(cfg.get_value("audio", "music", music_volume), 0.0, 1.0)
		sfx_volume = clampf(cfg.get_value("audio", "sfx", sfx_volume), 0.0, 1.0)
		sensitivity = clampf(cfg.get_value("input", "sensitivity", sensitivity), 0.4, 2.0)
		skill_layout = str(cfg.get_value("ui", "skill_layout", ""))
	if not skill_layout in ["mobile", "pc"]: skill_layout = default_skill_layout()
	_setup_audio()
	_check_safe_start()
	apply_settings.call_deferred()
	if desktop and is_pc_platform(): get_tree().create_timer(0.6).timeout.connect(_late_safe_key)

## «Высокое» на ПК (Forward+): SSAO, мягкие тени без PCSS, трава, вода, свечение. Освещение — небо + солнце, без GI.
func heavy_fx() -> bool:
	return desktop and is_pc_platform() and quality >= 3 and RenderingServer.get_current_rendering_method() == "forward_plus"

## «Ультра»: SDFGI / SSR / объёмный туман — по отдельным переключателям
func ultra() -> bool:
	return heavy_fx() and quality >= 4

func max_quality() -> int:
	return 4 if desktop and is_pc_platform() else 3

func gi_on() -> bool: return ultra() and ultra_gi and gi_supported()
func ssr_on() -> bool: return ultra() and ultra_ssr
func vfog_on() -> bool: return ultra() and ultra_fog

## SDFGI отключается на видеокартах, где он известен чёрным экраном/артефактами:
## AMD GCN (Radeon HD 7xxx, R7/R9, RX 4xx/5xx Polaris, Vega), и любом программном рендере кроме тестов.
func gi_supported() -> bool:
	if "--no-sdfgi" in OS.get_cmdline_user_args(): return false
	if "--force-sdfgi" in OS.get_cmdline_user_args(): return true
	return not gpu_gi_blocked(RenderingServer.get_video_adapter_vendor(), RenderingServer.get_video_adapter_name())

static func gpu_gi_blocked(vendor: String, adapter: String) -> bool:
	var v := vendor.to_lower(); var a := adapter.to_lower()
	var amd := v.contains("amd") or v.contains("ati") or v.contains("1002") or a.contains("radeon") or a.contains("amd")
	if not amd: return false
	for k in ["polaris", "vega", "ellesmere", "baffin", "lexa", "tonga", "fiji", "hawaii", "tahiti", "pitcairn", "bonaire", "gcn", "hd 7", "hd 8", "r5 ", "r7 ", "r9 ", "rx 4", "rx 5", "rx460", "rx470", "rx480", "rx550", "rx560", "rx570", "rx580", "rx590", "vii", "graphics (ryzen"]:
		if a.contains(k):
			# RX 5500/5600/5700 — это RDNA1, не GCN
			if k == "rx 5" and (a.contains("rx 55") or a.contains("rx 56") or a.contains("rx 57")): continue
			return true
	return false

func _check_safe_start() -> void:
	if not (desktop and is_pc_platform()): return
	var why := ""
	if "--safe-graphics" in OS.get_cmdline_user_args(): why = "запуск с --safe-graphics"
	elif FileAccess.file_exists(SESSION_LOCK) and not "--ignore-lock" in OS.get_cmdline_user_args(): why = "прошлая игра завершилась некорректно"
	elif Input.is_key_pressed(KEY_SHIFT): why = "зажат Shift"
	_write_lock()
	if why != "": _enter_safe(why)

func _late_safe_key() -> void:
	if not safe_start and Input.is_key_pressed(KEY_SHIFT) and quality > 2:
		_enter_safe("зажат Shift"); apply_settings()

func _enter_safe(why: String) -> void:
	safe_start = true; safe_reason = why
	if quality > 2:
		quality = 2; render_scale = 1.0
		save_settings()
	toast.call_deferred("Безопасный запуск (%s): графика «Среднее»" % why, 5.0)

func _write_lock() -> void:
	var f := FileAccess.open(SESSION_LOCK, FileAccess.WRITE)
	if f: f.store_string(Time.get_datetime_string_from_system()); f.close()

func clear_lock() -> void:
	if FileAccess.file_exists(SESSION_LOCK): DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_LOCK))

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE: clear_lock()

func _exit_tree() -> void:
	clear_lock()

## Детальная земля (шейдер) — ПК от «Среднего»
func pc_detail() -> bool:
	return desktop and is_pc_platform() and quality >= 2

## Панель умений по умолчанию: телефон — веер, ПК — ряд
func default_skill_layout() -> String:
	return "pc" if desktop else "mobile"

static func is_pc_platform() -> bool:
	return OS.has_feature("pc") and not OS.has_feature("mobile") and not OS.has_feature("android")

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("video", "shadows", shadows_enabled)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "resolution", resolution)
	cfg.set_value("video", "preset", quality)
	cfg.set_value("video", "ultra_gi", ultra_gi)
	cfg.set_value("video", "ultra_ssr", ultra_ssr)
	cfg.set_value("video", "ultra_fog", ultra_fog)
	cfg.set_value("video", "render_scale", render_scale)
	cfg.set_value("video", "fps_cap", fps_cap)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "ui_scale", ui_scale)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("input", "sensitivity", sensitivity)
	cfg.set_value("ui", "skill_layout", skill_layout)
	cfg.save("user://settings.cfg")

func fps_options() -> Array:
	return FPS_PC if desktop else FPS_MOBILE

## Выбор пресета: задаёт и рекомендуемые масштаб 3D/кадры/тени (их можно поменять отдельно)
func apply_preset(p: int) -> void:
	quality = clampi(p, 0, max_quality())
	match quality:
		0: render_scale = 0.6; fps_cap = 30; shadows_enabled = false
		1: render_scale = 0.7 if not desktop else 0.85; fps_cap = mini(fps_cap, 60) if not desktop else fps_cap; shadows_enabled = true
		2: render_scale = 0.75 if not desktop else 1.0; shadows_enabled = true
		3, 4: render_scale = 0.85 if not desktop else 1.0; shadows_enabled = true
	apply_settings()

## Применить окно/качество/масштаб интерфейса
func apply_settings() -> void:
	var vp := get_tree().root
	vp.content_scale_factor = ui_scale
	vp.scaling_3d_scale = render_scale
	# на ПК при уменьшенном 3D — FSR (чётче), на телефоне — дешёвый билинейный
	# FSR — только на ПК-платформах; на Android всегда билинейное масштабирование (Mali/Vulkan Mobile)
	var fsr_ok := desktop and is_pc_platform() and OS.get_name() != "Android"
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if fsr_ok and render_scale < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	match quality:
		0:
			vp.msaa_3d = Viewport.MSAA_DISABLED
			view_distance = 60.0; particle_mul = 0.35; shadow_distance = 0.0; glow = false
			RenderingServer.directional_shadow_atlas_set_size(1024, true)
		1:
			vp.msaa_3d = Viewport.MSAA_DISABLED
			view_distance = 75.0; particle_mul = 0.55; shadow_distance = 25.0; glow = false
			RenderingServer.directional_shadow_atlas_set_size(1024, true)
		2:
			vp.msaa_3d = Viewport.MSAA_2X
			view_distance = 95.0; particle_mul = 0.8; shadow_distance = 35.0; glow = desktop
			RenderingServer.directional_shadow_atlas_set_size(2048, true)
		_:
			vp.msaa_3d = Viewport.MSAA_4X if desktop else Viewport.MSAA_2X
			view_distance = 125.0 if desktop else 105.0; particle_mul = 1.0; shadow_distance = 60.0 if desktop else 40.0; glow = true
			RenderingServer.directional_shadow_atlas_set_size(4096 if desktop else 2048, true)
	if desktop and DisplayServer.get_name() != "headless" and not "--bench-uncapped" in OS.get_cmdline_user_args():
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	_fps_now = -1
	update_fps()
	get_tree().call_group("graphics_listeners", "apply_graphics")
	if desktop and DisplayServer.get_name() != "headless" and not "--no-window-settings" in OS.get_cmdline_user_args():
		if fullscreen:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var scr := DisplayServer.screen_get_size()
			var sz := Vector2i(mini(resolution.x, scr.x), mini(resolution.y, scr.y))
			DisplayServer.window_set_size(sz)
			DisplayServer.window_set_position(DisplayServer.screen_get_position() + (scr - sz) / 2)

# ---------- звук ----------
## Шины Music/SFX, фоновая музыка и короткие звуки (синтезируются в коде — без внешних файлов)
func _setup_audio() -> void:
	for b in ["Music", "SFX"]:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")
	apply_audio()
	_music = AudioStreamPlayer.new(); _music.bus = "Music"; _music.volume_db = -6.0
	_music.stream = _make_music()
	add_child(_music)
	_music.play()
	# у каждого звука свой проигрыватель с полифонией: поток никогда не подменяется на лету
	# (подмена потока во время микширования на Android — риск гонки с аудиопотоком)
	for n in ["click", "hit", "swing", "pickup", "level"]:
		_sfx_streams[n] = _make_sfx(n)
		var p := AudioStreamPlayer.new(); p.bus = "SFX"; p.stream = _sfx_streams[n]
		p.max_polyphony = 3; p.name = "Sfx_" + n
		add_child(p); _sfx_players[n] = p

func apply_audio() -> void:
	var mi := AudioServer.get_bus_index("Music"); var si := AudioServer.get_bus_index("SFX")
	if mi >= 0:
		AudioServer.set_bus_volume_db(mi, linear_to_db(maxf(music_volume, 0.0001)))
		AudioServer.set_bus_mute(mi, music_volume <= 0.001)
	if si >= 0:
		AudioServer.set_bus_volume_db(si, linear_to_db(maxf(sfx_volume, 0.0001)))
		AudioServer.set_bus_mute(si, sfx_volume <= 0.001)

## Короткий звук: click, hit, swing, pickup, level
func sfx(n: String, pitch := 1.0) -> void:
	if not _sfx_players.has(n) or sfx_volume <= 0.001: return
	var p: AudioStreamPlayer = _sfx_players[n]
	p.pitch_scale = pitch * randf_range(0.95, 1.05)
	p.play()

const RATE := 22050
## WAV из сэмплов. В конце — запас тишины, а конец петли — последний кадр включительно (frames-1):
## микшер WAV в Godot при loop_end == frames читает кадр за концом буфера, на Android 16 с проверкой
## тегов памяти (MTE) это приводило к падению SIGSEGV в libgodot_android.so (v0.3.2).
const WAV_PAD := 512
static func _wav(data: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var frames := data.size()
	var b := PackedByteArray(); b.resize((frames + WAV_PAD) * 2)
	b.fill(0)
	for i in frames: b.encode_s16(i * 2, int(clampf(data[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS; w.mix_rate = RATE; w.stereo = false; w.data = b
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD; w.loop_begin = 0; w.loop_end = frames - 1
	return w

func _make_sfx(n: String) -> AudioStreamWAV:
	var len := {"click": 0.06, "hit": 0.16, "swing": 0.22, "pickup": 0.25, "level": 0.9}[n] as float
	var cnt := int(RATE * len)
	var d := PackedFloat32Array(); d.resize(cnt)
	var rng := RandomNumberGenerator.new(); rng.seed = n.hash()
	var lp := 0.0
	for i in cnt:
		var t := float(i) / RATE; var k := t / len
		var v := 0.0
		match n:
			"click": v = sin(TAU * 1400.0 * t) * (1.0 - k) * 0.35
			"hit":
				lp = lerpf(lp, rng.randf_range(-1, 1), 0.25)
				v = (lp * 0.8 + sin(TAU * (160.0 - 90.0 * k) * t) * 0.6) * pow(1.0 - k, 2.0) * 0.7
			"swing":
				lp = lerpf(lp, rng.randf_range(-1, 1), 0.08 + 0.2 * sin(PI * k))
				v = lp * sin(PI * k) * 0.9
			"pickup": v = sin(TAU * (880.0 if k < 0.45 else 1320.0) * t) * (1.0 - k) * 0.3
			"level":
				var f: float = [523.25, 659.25, 783.99, 1046.5][mini(3, int(k * 4.0))]
				v = (sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.0 * t)) * (1.0 - k) * 0.28
		d[i] = v
	return _wav(d)

## Спокойная фоновая тема: мягкие аккорды (ля-минор — фа — до — соль), 16 с, по кругу
func _make_music() -> AudioStreamWAV:
	var chords := [[220.0, 261.63, 329.63], [174.61, 220.0, 261.63], [130.81, 196.0, 261.63], [196.0, 246.94, 293.66]]
	var seg := 4.0
	var cnt := int(RATE * seg * chords.size())
	var d := PackedFloat32Array(); d.resize(cnt)
	for i in cnt:
		var t := float(i) / RATE
		var ci := int(t / seg) % chords.size(); var lt := fmod(t, seg)
		var env := minf(1.0, lt / 1.2) * minf(1.0, (seg - lt) / 1.0)
		var v := 0.0
		for f in chords[ci]:
			v += sin(TAU * f * t) * 0.16 + sin(TAU * f * 0.5 * t) * 0.08
		# переливы арпеджио
		var nf: float = chords[ci][int(lt * 2.0) % 3] * 2.0
		var nt := fmod(lt, 0.5)
		v += sin(TAU * nf * t) * exp(-nt * 6.0) * 0.07
		d[i] = v * env * 0.5
	return _wav(d, true)

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
	var rk := {}
	for k in c.get("ranks", {}): rk[str(k)] = int(c["ranks"][k])
	if c.has("ranks"): c["ranks"] = rk
	DB.migrate_talents(c)
	for list_name in ["inventory", "equipped", "stash", "buyback"]:
		for it in c.get(list_name, []):
			it["slot"] = int(it["slot"]); it["rarity"] = int(it["rarity"]); it["ilvl"] = int(it["ilvl"])
			if it.has("req"): it["req"] = int(it["req"])
	c["dust"] = int(c.get("dust", 0))
	Items.migrate(c)
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

func travel(zone_id: String, arrive := "") -> void:
	var z = DB.ZONES.get(zone_id)
	if z == null or not z["available"]: return
	current["zone"] = zone_id
	current["has_pos"] = false
	if arrive != "": current["arrive"] = arrive
	save_character(current)
	get_tree().change_scene_to_file(z["scene"])

func to_menu() -> void:
	save_character(current)
	var mm = load("res://scripts/game/main_menu.gd")
	mm.start_on_select = true
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

## Ограничение кадров: в игре — настройка игрока; в меню и на паузе — не выше 120 на ПК и 60 на телефоне
var _fps_now := -1
func update_fps() -> void:
	var scene := get_tree().current_scene
	var in_game := scene != null and scene.has_method("near_merchant") and not get_tree().paused
	var cap := fps_cap if in_game else mini(fps_cap, 120 if desktop else 60)
	if "--bench-uncapped" in OS.get_cmdline_user_args(): cap = 0
	if cap != _fps_now:
		_fps_now = cap
		Engine.max_fps = cap

func _process(delta: float) -> void:
	update_fps()
	if _toast_time > 0:
		_toast_time -= delta
		_toast_panel.modulate.a = clampf(_toast_time * 2, 0, 1)
		_place_toast()
		if _toast_time <= 0: _toast_panel.visible = false

func _place_toast() -> void:
	var vs := get_viewport().get_visible_rect().size
	_toast_panel.position = Vector2((vs.x - _toast_panel.size.x) / 2, vs.y * 0.24)
