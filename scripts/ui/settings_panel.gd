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
	var tabs := UIK.hbox(p, 64, 12)
	UIK.place(tabs, 0.03, 0.80, 0.97, 0.875)
	for t in [["main", "Основные"], ["controls", "Управление (ПК)"]]:
		var tb := UIK.button(tabs, t[1], _show_tab.bind(t[0]), UIK.BUTTON, 28)
		tb.name = "Tab_" + t[0]
		UIK.expand(tb, 1.0)
	var lp := Control.new(); p.add_child(lp)
	UIK.place(lp, 0.03, 0.15, 0.97, 0.79)
	rows = UIK.scroll_list(lp, 12)
	var done := UIK.button(p, "Готово", close, UIK.GREEN, 36)
	done.name = "Done"
	UIK.place(done, 0.3, 0.025, 0.7, 0.125)
	_show_tab("main")

var tab := "main"
func _show_tab(t: String) -> void:
	tab = t
	_capture = []
	_refreshers.clear()
	UIK.clear(rows)
	for b in find_children("Tab_*", "", true, false): b.modulate = Color(1.2, 1.15, 0.85) if String(b.name) == "Tab_" + t else Color(0.75, 0.75, 0.75)
	if t == "main": _build()
	else: _build_controls()

# ---------- v0.9.0: вкладка «Управление»: переназначение, конфликты, сброс ----------
var _capture: Array = []        # [id, slot, button] — ждём нажатия
var _bind_btns := {}            # "id:slot" -> Button
func _build_controls() -> void:
	_bind_btns.clear()
	var h := UIK.label(rows, "Нажмите на привязку и затем нужную клавишу или кнопку мыши. Esc — отмена, Delete — очистить. Красным — клавиша занята несколькими действиями.", 22, UIK.MUTED)
	h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var rb := UIK.button(rows, "Сбросить по умолчанию", func():
		Controls.reset_defaults(); _after_rebind(), UIK.BUTTON, 28)
	rb.name = "ResetControls"
	for a in Controls.ACTIONS:
		var r := _row(a[1])
		for slot in 2:
			var b := UIK.button(r, "", Callable(), UIK.BUTTON, 26)
			b.name = "Bind_%s_%d" % [a[0], slot]
			b.custom_minimum_size.x = 190
			var id: String = a[0]
			b.pressed.connect(func():
				if DragScroll.dragging: return
				_capture = [id, slot, b]; b.text = "Нажмите…")
			_bind_btns["%s:%d" % [a[0], slot]] = b
	_paint_binds()

func _paint_binds() -> void:
	var cf := Controls.conflicts()
	for k in _bind_btns:
		var b: Button = _bind_btns[k]
		if not is_instance_valid(b): continue
		var parts: PackedStringArray = k.split(":")
		var code := int(Controls.binds[parts[0]][int(parts[1])])
		b.text = Controls.code_name(code)
		b.modulate = Color(1.0, 0.45, 0.4) if cf.has(code) else Color.WHITE
		b.tooltip_text = "Конфликт: клавиша назначена на несколько действий" if cf.has(code) else ""

func _after_rebind() -> void:
	_paint_binds()
	get_tree().call_group("hud_listeners", "refresh_key_hints")

func _input(ev: InputEvent) -> void:
	if _capture.is_empty(): return
	var is_key: bool = ev is InputEventKey and ev.pressed and not ev.echo
	var is_mb: bool = ev is InputEventMouseButton and ev.pressed and not (ev.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN])
	if not (is_key or is_mb): return
	get_viewport().set_input_as_handled()
	var id: String = _capture[0]; var slot: int = _capture[1]
	_capture = []
	if is_key and (ev as InputEventKey).keycode == KEY_ESCAPE: _paint_binds(); return
	if is_key and (ev as InputEventKey).keycode in [KEY_DELETE, KEY_BACKSPACE]:
		Controls.rebind(id, slot, 0); _after_rebind(); return
	Controls.rebind(id, slot, Controls.code_of(ev))
	_after_rebind()

## Для тестов: назначить без ввода
func test_rebind(id: String, slot: int, code: int) -> void:
	Controls.rebind(id, slot, code); _after_rebind()

func close() -> void:
	Game.save_settings()
	if on_close.is_valid(): on_close.call()
	queue_free()

func _build() -> void:
	_section("Графика")
	_cycle("Quality", "Пресет", func(): return Game.QUALITY_NAMES[Game.quality], func():
		Game.apply_preset((Game.quality + 1) % (Game.max_quality() + 1))
		_refresh_all())
	if Game.max_quality() >= 4:
		var gi := _cycle("UltraGI", "Ультра: глоб. освещение", func(): return ("вкл" if Game.ultra_gi else "выкл") if Game.gi_supported() else "не поддерж.", func():
			Game.ultra_gi = not Game.ultra_gi
			Game.apply_settings())
		var ssr := _cycle("UltraSSR", "Ультра: отражения", func(): return "вкл" if Game.ultra_ssr else "выкл", func():
			Game.ultra_ssr = not Game.ultra_ssr
			Game.apply_settings())
		var vf := _cycle("UltraFog", "Ультра: объёмный туман", func(): return "вкл" if Game.ultra_fog else "выкл", func():
			Game.ultra_fog = not Game.ultra_fog
			Game.apply_settings())
		_refreshers.append(func():
			for b in [gi, ssr, vf]:
				if is_instance_valid(b): b.disabled = Game.quality < 4
			if is_instance_valid(gi): gi.disabled = Game.quality < 4 or not Game.gi_supported())
		var uh := UIK.label(rows, "«Ультра» — тяжёлые эффекты для мощных видеокарт. Если картинка тёмная или с артефактами — выберите «Высокое». Зажмите Shift при запуске для безопасного режима.", 22, UIK.MUTED)
		uh.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_refresh_all.call_deferred()
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
	_cycle("SkillLayout", "Панель умений", func(): return "Веер (телефон)" if Game.skill_layout == "mobile" else "Ряд (ПК)", func():
		Game.skill_layout = "pc" if Game.skill_layout == "mobile" else "mobile"
		Game.save_settings()
		get_tree().call_group("hud_listeners", "apply_skill_layout"))
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
