extends Control
## Меню паузы.

var zone

func setup(z) -> void:
	zone = z
	process_mode = Node.PROCESS_MODE_ALWAYS
	UIK.full(UIK.panel(self, Color(0, 0, 0, 0.75), 0))
	var p := UIK.panel(self)
	p.anchor_left = 0.5; p.anchor_right = 0.5; p.anchor_top = 0.5; p.anchor_bottom = 0.5
	var hh := 390
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
	_btn(v, "Настройки", open_settings, UIK.BLUE)
	_btn(v, "Авторы и лицензии", open_credits, UIK.BUTTON)
	_btn(v, "В главное меню", func(): Game.to_menu(), UIK.RED)

func open_credits() -> void:
	var cp := CreditsPanel.new()
	add_child(cp)
	cp.setup()
	UIK.pop_in(cp)

## Те же настройки, что и в главном меню
func open_settings() -> void:
	var sp := SettingsPanel.new()
	add_child(sp)
	sp.setup(Callable(), zone)
	UIK.pop_in(sp)

static func _nearest(arr: Array, x: float) -> int:
	var best := 0
	for i in arr.size():
		if absf(arr[i] - x) < absf(arr[best] - x): best = i
	return best

func _btn(parent: Node, t: String, cb: Callable, c: Color) -> Button:
	var b := UIK.button(parent, t, cb, c, 34)
	UIK.min_h(b, 100)
	return b
