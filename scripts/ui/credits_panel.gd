extends Control
class_name CreditsPanel
## «Авторы и лицензии»: обязательное указание авторства (game-icons.net — CC BY 3.0) и список CC0/OFL-ассетов.
## Открывается из главного меню и из паузы.

const TEXT := """[center][b][color=#f2c46d]Осколки Эфира[/color][/b]
Код, дизайн и сборка уровней — собственные.[/center]

[b][color=#f2c46d]Иконки — CC BY 3.0 (указание авторства обязательно)[/color][/b]
game-icons.net — авторы [b]Lorc[/b], [b]Delapouite[/b], [b]Skoll[/b], [b]Sbed[/b]
Лицензия: creativecommons.org/licenses/by/3.0 · иконки перекрашены и уменьшены.

[b][color=#f2c46d]Модель босса Кел'Таар — CC BY 4.0 (указание авторства обязательно)[/color][/b]
"Skeletal Lich King in Bone Crown and Robes" by Pigcraft (@s8819296)
sketchfab.com/3d-models/skeletal-lich-king-in-bone-crown-and-robes-0fa4c6a200444b4abc108a9b0b9edae6
Лицензия: creativecommons.org/licenses/by/4.0 · изменено: модель упрощена (LOD для ПК и телефона), текстура перенесена в цвет вершин, анимация процедурная.

[b][color=#f2c46d]Фотограмметрия и реалистичные модели — CC0 1.0[/color][/b]
[b]Poly Haven[/b] (polyhaven.com): WoodenTable_01, boulder_01, dandelion_01, dead_quiver_trunk, dead_tree_trunk_02, dry_branches_medium_01, fern_02, gothic_statue, grass_medium_02, large_castle_door, modular_fort_01, namaqualand_boulder_02–05, nettle_plant, periwinkle_plant, quiver_tree_02, rock_07, rock_moss_set_01, rock_moss_set_02, root_cluster_01, shrub_02–04, shrub_sorrel_01, spinning_wheel_01, stone_fire_pit, treasure_chest, tree_stump_01–02, weed_plant_02, wicker_basket_01, wild_rooibos_bush, wine_barrel_01, wooden_axe_03, wooden_bucket_01, wooden_crate_01–02, wooden_ladder, wooden_lantern_01, wooden_stool_01.
Небо — HDRI «Kloofendal 48d Partly Cloudy (Pure Sky)» (Greg Zaal / Poly Haven, CC0). Модели упрощены (LOD), текстуры уменьшены.

[b][color=#f2c46d]PBR-материалы, кора, листва — CC0 1.0[/color][/b]
[b]ambientCG[/b] (ambientcg.com): Bricks076A, Bricks102, PavingStones131, Planks023A, Wood051, RoofingTiles006, Plaster001, ThatchedRoof001A, Fabric030, Metal032, Rock022, Ground054, Bark001, Bark006, Bark012, Bark014, Foliage001–008, LeafSet005, LeafSet024, PineNeedles001.
Из атласов листвы собраны карточки листьев, хвои и травы; деревья и дома строятся в коде.

[b][color=#f2c46d]3D-модели окружения — CC0 1.0[/color][/b]
[b]Kenney[/b] (kenney.nl): Castle Kit 2.0, Fantasy Town Kit 2.0, Graveyard Kit 5.0, Survival Kit 2.0, Nature Kit 2.1
Остались только постройки и мелочи; они покрыты PBR-материалами ambientCG.

[b][color=#f2c46d]Персонажи, монстры, анимации, оружие — CC0 1.0[/color][/b]
[b]Quaternius[/b] (quaternius.com): Universal Base Characters, Universal Animation Library 1 и 2,
Modular Character Outfits – Fantasy, Ultimate Animated Animals (в т.ч. бык), Ultimate Monsters,
модели Spider, Bat, Goblin, Bee, Crab, Rat, оружие и щиты (poly.pizza).

[b][color=#f2c46d]Иконки снаряжения — CC0 1.0[/color][/b]
[b]Idylwild[/b] (idylwild.itch.io, OpenGameArt): Armory, Arsenal, Arcanum, Inventory.
Часть иконок перекрашена под тиры; шляпы, обручи и пояса дорисованы в той же палитре.

[b][color=#f2c46d]Текстуры рельефа — CC0 1.0[/color][/b]
[b]ambientCG[/b] (ambientcg.com): Grass004, Ground037, Ground048, Ground080, Ground054, Snow006, Rock030
(цвет и карты нормалей NormalGL)

[b][color=#f2c46d]Логотип и иконка приложения[/color][/b]
Эмблема «кристалл в рунном кольце» нарисована для игры (процедурно, без сторонних изображений).

[b][color=#f2c46d]Шрифты — SIL Open Font License 1.1[/color][/b]
Rubik · Philosopher (Ярослав Захаров) · Cormorant SC (Christian Thalmann) — надпись логотипа

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
