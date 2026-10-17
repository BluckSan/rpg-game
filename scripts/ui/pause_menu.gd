extends Control
## Меню паузы.

var zone

func setup(z) -> void:
	zone = z
	process_mode = Node.PROCESS_MODE_ALWAYS
	UIK.full(UIK.panel(self, Color(0, 0, 0, 0.75), 0))
	var p := UIK.panel(self)
	p.anchor_left = 0.5; p.anchor_right = 0.5; p.anchor_top = 0.5; p.anchor_bottom = 0.5
	var hh := 500 if Game.desktop else 440
	p.offset_left = -360; p.offset_right = 360; p.offset_top = -hh; p.offset_bottom = hh
	UIK.place(UIK.label(p, "Пауза", 54, UIK.ACCENT, HORIZONTAL_ALIGNMENT_CENTER), 0, 0.89, 1, 0.98)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14 if Game.desktop else 20)
	p.add_child(v)
	UIK.place(v, 0.08, 0.04, 0.92, 0.87)
	_btn(v, "Продолжить", func(): zone.hud.close_window(), UIK.GREEN)
	_btn(v, "Сохранить", func():
		zone.save()
		Game.toast("Игра сохранена"), UIK.BUTTON)
	var sh := _btn(v, "", Callable(), UIK.BUTTON)
	sh.text = "Тени: вкл" if Game.shadows_enabled else "Тени: выкл"
	sh.pressed.connect(func():
		Game.shadows_enabled = not Game.shadows_enabled
		Game.save_settings()
		var sun = zone.get_node_or_null("World/Sun")
		if sun: sun.shadow_enabled = Game.shadows_enabled
		sh.text = "Тени: вкл" if Game.shadows_enabled else "Тени: выкл")
	var q := _btn(v, "", Callable(), UIK.BUTTON)
	q.name = "Quality"
	q.text = "Графика: " + Game.QUALITY_NAMES[Game.quality]
	q.pressed.connect(func():
		Game.quality = (Game.quality + 1) % 3
		_apply(); q.text = "Графика: " + Game.QUALITY_NAMES[Game.quality])
	if Game.desktop:
		var fs := _btn(v, "", Callable(), UIK.BUTTON)
		fs.name = "Fullscreen"
		fs.text = "Режим: полный экран" if Game.fullscreen else "Режим: в окне"
		var rs := _btn(v, "", Callable(), UIK.BUTTON)
		rs.name = "Resolution"
		rs.text = "Разрешение окна: " + Game.resolution_text()
		rs.disabled = Game.fullscreen
		fs.pressed.connect(func():
			Game.fullscreen = not Game.fullscreen
			_apply()
			fs.text = "Режим: полный экран" if Game.fullscreen else "Режим: в окне"
			rs.disabled = Game.fullscreen)
		rs.pressed.connect(func():
			var i := Game.RESOLUTIONS.find(Game.resolution)
			Game.resolution = Game.RESOLUTIONS[(i + 1) % Game.RESOLUTIONS.size()]
			_apply(); rs.text = "Разрешение окна: " + Game.resolution_text())
	var us := _btn(v, "", Callable(), UIK.BUTTON)
	us.name = "UiScale"
	us.text = "Масштаб интерфейса: %d%%" % roundi(Game.ui_scale * 100)
	us.pressed.connect(func():
		var i := _nearest(Game.UI_SCALES, Game.ui_scale)
		Game.ui_scale = Game.UI_SCALES[(i + 1) % Game.UI_SCALES.size()]
		_apply(); us.text = "Масштаб интерфейса: %d%%" % roundi(Game.ui_scale * 100))
	_btn(v, "В главное меню", func(): Game.to_menu(), UIK.RED)

func _apply() -> void:
	Game.apply_settings()
	Game.save_settings()

static func _nearest(arr: Array, x: float) -> int:
	var best := 0
	for i in arr.size():
		if absf(arr[i] - x) < absf(arr[best] - x): best = i
	return best

func _btn(parent: Node, t: String, cb: Callable, c: Color) -> Button:
	var b := UIK.button(parent, t, cb, c, 34)
	UIK.min_h(b, 84 if Game.desktop else 96)
	return b
