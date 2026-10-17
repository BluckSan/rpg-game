extends Control
## Меню паузы.

var zone

func setup(z) -> void:
	zone = z
	process_mode = Node.PROCESS_MODE_ALWAYS
	UIK.full(UIK.panel(self, Color(0, 0, 0, 0.75), 0))
	var p := UIK.panel(self)
	p.anchor_left = 0.5; p.anchor_right = 0.5; p.anchor_top = 0.5; p.anchor_bottom = 0.5
	p.offset_left = -350; p.offset_right = 350; p.offset_top = -380; p.offset_bottom = 380
	UIK.place(UIK.label(p, "Пауза", 54, UIK.ACCENT, HORIZONTAL_ALIGNMENT_CENTER), 0, 0.85, 1, 0.97)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 22)
	p.add_child(v)
	UIK.place(v, 0.1, 0.06, 0.9, 0.8)
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
	_btn(v, "В главное меню", func(): Game.to_menu(), UIK.RED)

func _btn(parent: Node, t: String, cb: Callable, c: Color) -> Button:
	var b := UIK.button(parent, t, cb, c, 34)
	UIK.min_h(b, 110)
	return b
