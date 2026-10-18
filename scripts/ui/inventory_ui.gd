extends "res://scripts/ui/item_window.gd"
## Окно героя: снаряжение (8 ячеек), характеристики, комплекты, инвентарь-сетка.

func _init() -> void:
	mode = "hero"

## v0.9.1: кнопка «Ремесло» (комплекты из материалов боссов подземелий)
func setup(z) -> void:
	super.setup(z)
	var cb := UIK.button(self, "Ремесло", func(): zone.hud._open("craft"), Color(0.42, 0.3, 0.18), 26, "thor-hammer")
	cb.name = "CraftBtn"
	cb.anchor_left = 1; cb.anchor_right = 1; cb.offset_left = -1080; cb.offset_right = -840; cb.offset_top = 18; cb.offset_bottom = 96
	# v0.9.2: рынок игроков (онлайн)
	var mb := UIK.button(self, "Рынок", func(): zone.hud._open("market"), Color(0.25, 0.32, 0.45), 26, "shop")
	mb.name = "MarketBtn"
	mb.anchor_left = 1; mb.anchor_right = 1; mb.offset_left = -1330; mb.offset_right = -1090; mb.offset_top = 18; mb.offset_bottom = 96
