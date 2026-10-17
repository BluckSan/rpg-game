extends Control
class_name SettingsPanel
## Настройки: графика, экран (ПК), интерфейс, звук, управление. Общие для главного меню и паузы.
## Всё применяется сразу и сохраняется в user://settings.cfg.

var on_close: Callable
var rows: VBoxContainer
var zone          # если открыто из игры — для мгновенного обновления теней

func setup(close_cb: Callable, z = null) -> void:
	on_close = close_cb; zone = z
	process_mode = Node.PROCESS_MODE_ALWAYS
	name = "SettingsPanel"
	UIK.full(self)
	UIK.full(UIK.panel(self, Color(0, 0, 0, 0.6), 0))
	var p := UIK.panel(self)
	p.anchor_left = 0.5; p.anchor_right = 0.5; p.anchor_top = 0.5; p.anchor_bottom = 0.5
	p.offset_left = -520; p.offset_right = 520; p.offset_top = -480; p.offset_bottom = 480
	UIK.place(UIK.label(p, "Настройки", 54, UIK.ACCENT, HORIZONTAL_ALIGNMENT_CENTER), 0, 0.885, 1, 0.98)
	var lp := Control.new(); p.add_child(lp)
	UIK.place(lp, 0.03, 0.15, 0.97, 0.88)
	rows = UIK.scroll_list(lp, 12)
	var done := UIK.button(p, "Готово", close, UIK.GREEN, 36)
	done.name = "Done"
	UIK.place(done, 0.3, 0.025, 0.7, 0.125)
	_build()

func close() -> void:
	Game.save_settings()
	if on_close.is_valid(): on_close.call()
	queue_free()

func _build() -> void:
	_section("Графика")
	_cycle("Quality", "Пресет", func(): return Game.QUALITY_NAMES[Game.quality], func():
		Game.apply_preset((Game.quality + 1) % 4)
		_refresh_all())
	_cycle("RenderScale", "Разрешение 3D", func(): return "%d%%" % roundi(Game.render_scale * 100), func():
		var i := _nearest(Game.RENDER_SCALES, Game.render_scale)
		Game.render_scale = Game.RENDER_SCALES[(i + 1) % Game.RENDER_SCALES.size()]
		Game.apply_settings())
	_cycle("FpsCap", "Ограничение кадров", func(): return "%d к/с" % Game.fps_cap, func():
		var opts := Game.fps_options()
		var i := opts.find(Game.fps_cap)
		Game.fps_cap = opts[(i + 1) % opts.size()]
		Game.apply_settings())
	_cycle("Shadows", "Тени", func(): return "вкл" if Game.shadows_enabled else "выкл", func():
		Game.shadows_enabled = not Game.shadows_enabled
		Game.apply_settings())
	if Game.desktop:
		_cycle("Vsync", "Вертикальная синхронизация", func(): return "вкл" if Game.vsync else "выкл", func():
			Game.vsync = not Game.vsync
			Game.apply_settings())
	var hint := UIK.label(rows, "В меню и на паузе кадры ограничены (%s), чтобы устройство меньше грелось." % ("до 120" if Game.desktop else "до 60"), 22, UIK.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if Game.desktop:
		_section("Экран")
		_cycle("Fullscreen", "Режим", func(): return "полный экран" if Game.fullscreen else "в окне", func():
			Game.fullscreen = not Game.fullscreen
			Game.apply_settings()
			var r2 = rows.find_child("Resolution", true, false)
			if r2: r2.disabled = Game.fullscreen)
		var rs := _cycle("Resolution", "Разрешение окна", func(): return Game.resolution_text(), func():
			var i := Game.RESOLUTIONS.find(Game.resolution)
			Game.resolution = Game.RESOLUTIONS[(i + 1) % Game.RESOLUTIONS.size()]
			Game.apply_settings())
		rs.disabled = Game.fullscreen
	_section("Интерфейс")
	_cycle("UiScale", "Масштаб интерфейса", func(): return "%d%%" % roundi(Game.ui_scale * 100), func():
		var i := _nearest(Game.UI_SCALES, Game.ui_scale)
		Game.ui_scale = Game.UI_SCALES[(i + 1) % Game.UI_SCALES.size()]
		Game.apply_settings())
	_section("Звук")
	_slider("Music", "Музыка", 0.0, 1.0, Game.music_volume, func(v):
		Game.music_volume = v
		Game.apply_audio(), true)
	_slider("Sfx", "Эффекты", 0.0, 1.0, Game.sfx_volume, func(v):
		Game.sfx_volume = v
		Game.apply_audio(), true)
	_section("Управление")
	_slider("Sensitivity", "Чувствительность камеры", 0.4, 2.0, Game.sensitivity, func(v):
		Game.sensitivity = v, false)

var _refreshers: Array[Callable] = []
func _refresh_all() -> void:
	for r in _refreshers: r.call()

func _section(t: String) -> void:
	var l := UIK.label(rows, t, 32, UIK.ACCENT)
	l.custom_minimum_size.y = 50

func _row(t: String) -> HBoxContainer:
	var r := UIK.hbox(rows, 84, 16)
	var l := UIK.label(r, t, 30)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	UIK.expand(l, 1.0)
	return r

func _cycle(id: String, t: String, val: Callable, next: Callable) -> Button:
	var r := _row(t)
	var b := UIK.button(r, str(val.call()), Callable(), UIK.BUTTON, 30)
	b.name = id
	UIK.expand(b, 0.9)
	b.pressed.connect(func():
		if DragScroll.dragging: return
		Game.sfx("click")
		next.call()
		b.text = str(val.call()))
	_refreshers.append(func(): if is_instance_valid(b): b.text = str(val.call()))
	return b

func _slider(id: String, t: String, mn: float, mx: float, v: float, cb: Callable, pct: bool) -> HSlider:
	var r := _row(t)
	var s := HSlider.new()
	s.name = id
	s.min_value = mn; s.max_value = mx; s.step = 0.05; s.value = v
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(0, 56)
	UIK.expand(s, 0.7)
	s.add_theme_stylebox_override("slider", UIK.box(Color(0.15, 0.13, 0.12), 8, 2, Color(0.4, 0.32, 0.22)))
	s.add_theme_stylebox_override("grabber_area", UIK.box(UIK.GOLD, 8))
	s.add_theme_stylebox_override("grabber_area_highlight", UIK.box(UIK.ACCENT, 8))
	var g := _knob()
	s.add_theme_icon_override("grabber", g); s.add_theme_icon_override("grabber_highlight", g)
	s.focus_mode = Control.FOCUS_NONE
	r.add_child(s)
	var vl := UIK.label(r, "", 28, UIK.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	vl.custom_minimum_size.x = 100
	vl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var upd := func(x: float): vl.text = ("%d%%" % roundi(x * 100)) if pct else ("×%.2f" % x)
	upd.call(v)
	s.value_changed.connect(func(x: float):
		cb.call(x); upd.call(x))
	s.drag_ended.connect(func(_c): if id == "Sfx": Game.sfx("pickup"))
	return s

static var _knob_tex: Texture2D
static func _knob() -> Texture2D:
	if _knob_tex: return _knob_tex
	var n := 44
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x - n / 2.0 + 0.5, y - n / 2.0 + 0.5).length()
			var a := clampf(n / 2.0 - d, 0.0, 1.0)
			var c := UIK.ACCENT.lightened(0.25) if d < n * 0.32 else Color(0.35, 0.24, 0.12)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	_knob_tex = ImageTexture.create_from_image(img)
	return _knob_tex

static func _nearest(arr: Array, x: float) -> int:
	var best := 0
	for i in arr.size():
		if absf(arr[i] - x) < absf(arr[best] - x): best = i
	return best
