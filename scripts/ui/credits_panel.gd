extends Control
class_name CreditsPanel
## «Авторы и лицензии»: обязательное указание авторства (game-icons.net — CC BY 3.0) и список CC0/OFL-ассетов.
## Открывается из главного меню и из паузы.

const TEXT := """[center][b][color=#f2c46d]Осколки Эфира[/color][/b]
Код, дизайн и сборка уровней — собственные.[/center]

[b][color=#f2c46d]Иконки — CC BY 3.0 (указание авторства обязательно)[/color][/b]
game-icons.net — авторы [b]Lorc[/b], [b]Delapouite[/b], [b]Skoll[/b], [b]Sbed[/b]
Лицензия: creativecommons.org/licenses/by/3.0 · иконки перекрашены и уменьшены.

[b][color=#f2c46d]3D-модели окружения — CC0 1.0[/color][/b]
[b]Kenney[/b] (kenney.nl): Castle Kit 2.0, Fantasy Town Kit 2.0, Graveyard Kit 5.0, Survival Kit 2.0, Nature Kit 2.1
Модели перекрашены и запечены в вершинные цвета.

[b][color=#f2c46d]Персонажи, монстры, анимации, оружие — CC0 1.0[/color][/b]
[b]Quaternius[/b] (quaternius.com): Universal Base Characters, Universal Animation Library 1 и 2,
Modular Character Outfits – Fantasy, Ultimate Animated Animals, Ultimate Monsters, оружие и щиты (poly.pizza).
Предметы в иконках инвентаря отрисованы из этих моделей.

[b][color=#f2c46d]Текстуры рельефа — CC0 1.0[/color][/b]
[b]ambientCG[/b] (ambientcg.com): Grass004, Ground037, Ground048, Ground080, Ground054, Snow006, Rock030

[b][color=#f2c46d]Шрифты — SIL Open Font License 1.1[/color][/b]
Rubik · Philosopher (Ярослав Захаров)

[b][color=#f2c46d]Движок[/color][/b]
Godot Engine (godotengine.org) — лицензия MIT, © Juan Linietsky, Ariel Manzur и сообщество Godot.
"""

var on_close: Callable

func setup(close_cb := Callable()) -> void:
	on_close = close_cb
	process_mode = Node.PROCESS_MODE_ALWAYS
	name = "CreditsPanel"
	UIK.full(self)
	UIK.full(UIK.panel(self, Color(0, 0, 0, 0.6), 0))
	var p := UIK.panel(self)
	p.anchor_left = 0.5; p.anchor_right = 0.5; p.anchor_top = 0.5; p.anchor_bottom = 0.5
	p.offset_left = -620; p.offset_right = 620; p.offset_top = -480; p.offset_bottom = 480
	UIK.place(UIK.label(p, "Авторы и лицензии", 50, UIK.ACCENT, HORIZONTAL_ALIGNMENT_CENTER), 0, 0.885, 1, 0.98)
	var rt := RichTextLabel.new()
	rt.name = "Text"
	rt.bbcode_enabled = true
	rt.scroll_active = true
	rt.add_theme_font_size_override("normal_font_size", 25)
	rt.add_theme_font_size_override("bold_font_size", 26)
	rt.text = TEXT
	p.add_child(rt)
	UIK.place(rt, 0.04, 0.15, 0.96, 0.87)
	var done := UIK.button(p, "Закрыть", close, UIK.GREEN, 36)
	done.name = "Done"
	UIK.place(done, 0.3, 0.025, 0.7, 0.125)

func close() -> void:
	if on_close.is_valid(): on_close.call()
	queue_free()
