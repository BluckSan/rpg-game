extends Node
## v0.9.3: проверка ПК-интерфейса в стиле L2 — панели ярлыков, переназначение клавиш, окно группы.
## xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1920x1080 res://tests/l2ui_test.tscn [++ --touch]
var is_runner := false
var out := "/workspace/rpg-shots/v093"
var errors := 0
var checks := 0

func check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok: errors += 1
	print("  ", "OK  " if ok else "FAIL", " ", msg)

func w(sec: float) -> void:
	var t0 := Time.get_ticks_msec(); var n := 0
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0) or n < 3:
		await get_tree().process_frame; n += 1

func shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, n])
	print("  shot %s/%s.png" % [out, n])

func key(z, k: int) -> void:
	var ev := InputEventKey.new(); ev.keycode = k; ev.physical_keycode = k; ev.pressed = true
	z.hud._input(ev)

func _ready() -> void:
	if not is_runner:
		var r = load("res://tests/l2ui_test.gd").new(); r.is_runner = true
		get_tree().root.add_child.call_deferred(r); return
	DirAccess.make_dir_recursive_absolute(out)
	get_tree().create_timer(200.0, true, false, true).timeout.connect(func(): print("TIMEOUT"); get_tree().quit(2))
	Controls.reset_defaults()
	for f in Game.list_characters(): Game.delete_character(f["id"])
	var rng := RandomNumberGenerator.new(); rng.seed = 5
	var c := DB.new_character("ПанелиL2", "warrior", CharAssets.random_look(1, rng))
	c["level"] = 20; c["class_level"] = 20; c["gold"] = 1000; c["potions"] = 5
	DB.auto_build_skills(c)
	var it := Items.roll(20, "warrior", 0.0, false, 0)
	c["inventory"].append(it)
	Game.save_character(c)
	# чистые настройки панелей
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ShortcutBars.PATH_FMT % str(c["name"]).md5_text().left(12)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://ui_layout.cfg"))
	Game.play(c); await w(2.5)
	var z = get_tree().current_scene
	for k in z.hud.HINTS: z.data["tutorial"][k] = true
	z.hud.hint_panel.visible = false
	if not Game.desktop:
		check(z.hud.bars == null, "телефон: панелей L2 нет (мобильный интерфейс без изменений)")
		check(z.hud.skill_btns[1].visible, "телефон: круглые кнопки умений на месте")
		await shot("l2_phone_hud")
		_done(); return
	var bars: ShortcutBars = z.hud.bars
	check(bars != null and bars.panels.size() == 3, "ПК: 3 панели ярлыков")
	check(not z.hud.skill_btns[1].visible, "ПК: старый ряд круглых кнопок скрыт")
	check(bars.slots[0][0].key_hint == "1" and bars.slots[0][9].key_hint == "0", "панель 1: клавиши 1…0")
	check(bars.slots[1][0].key_hint == "F1" and bars.slots[1][11].key_hint == "F12", "панель 2: клавиши F1…F12 (%s…%s)" % [bars.slots[1][0].key_hint, bars.slots[1][11].key_hint])
	check(Controls.key_hint("target_self") == "F", "«Цель — я» перенесена с F1 на F")
	var lo: Array = z.data["loadout"]
	check(bars.get_slot(0, 0).get("id", "") == str(lo[0]), "по умолчанию ячейка 1 = умение 1 набора")
	# клавиша 1 → умение
	z.player.cooldowns.fill(0.0)
	key(z, KEY_1); await w(0.2)
	check(z.player.cooldowns[1] > 0.0, "клавиша 1 применила умение из ячейки (перезарядка %.1f)" % z.player.cooldowns[1])
	# переназначение: ячейка 1 → Z, подсказки обновляются сразу
	Controls.rebind("skill_1", 0, KEY_Z); Controls.save()
	get_tree().call_group("hud_listeners", "refresh_key_hints")
	check(bars.slots[0][0].key_hint == "Z", "после переназначения подсказка ячейки = Z (сразу)")
	Controls.rebind("skills", 0, KEY_K + 0 if false else KEY_O)
	get_tree().call_group("hud_listeners", "refresh_key_hints")
	check(z.hud.top_buttons[2].text.contains("[O]"), "верхнее меню: подсказка «Умения [O]» обновилась (%s)" % z.hud.top_buttons[2].text)
	z.player.cooldowns.fill(0.0); await w(0.6)
	key(z, KEY_Z); await w(0.2)
	check(z.player.cooldowns[1] > 0.0, "новая клавиша Z применяет умение")
	# перетаскивание умения на F1
	var sid := str(lo[2])
	bars.drop(1, 0, {"skill": sid, "from": -1})
	check(bars.get_slot(1, 0).get("id", "") == sid, "умение перетащено в F1")
	z.player.cooldowns.fill(0.0); await w(0.6)
	key(z, KEY_F1); await w(0.2)
	check(z.player.cooldowns[3] > 0.0, "F1 применяет перетащенное умение")
	# зелье на 9
	z.player.hp = z.player.stats.max_hp * 0.4
	var pots := int(z.data["potions"])
	key(z, KEY_9); await w(0.2)
	check(int(z.data["potions"]) == pots - 1, "клавиша 9: зелье (%d → %d)" % [pots, int(z.data["potions"])])
	# вещь на панель → надеть
	bars.drop(1, 1, {"item": str(it.uid)})
	key(z, KEY_F2); await w(0.3)
	check(Items.find_uid(z.data["equipped"], str(it.uid)) != null, "F2: вещь с панели надета")
	# обмен ячеек
	bars.drop(1, 5, {"sc": [1, 0]})
	check(bars.get_slot(1, 5).get("id", "") == sid and bars.get_slot(1, 0).is_empty(), "ярлык перенесён между ячейками")
	# страницы
	key(z, KEY_BRACKETRIGHT); await w(0.1)
	check(bars.pages[0] == 1 and bars.get_slot(0, 1).is_empty(), "«]» — страница 2 панели 1 (пустая)")
	bars.drop(0, 0, {"potion": true})
	key(z, KEY_BRACKETLEFT); await w(0.1)
	check(bars.pages[0] == 0 and bars.get_slot(0, 1).get("k", "") == "skill", "«[» — назад на страницу 1")
	# перемещение, поворот, закрепление, сохранение
	bars.move_bar(1, Vector2(300, 200))
	bars.vertical[2] = false; bars.set_shown(2, true); bars._layout(2)
	bars.move_bar(2, Vector2(1200, 150))
	bars.toggle_lock()
	check(bars.locked and bars.slots[1][5]._get_drag(Vector2.ZERO) == null, "закреплено: ярлык не вытаскивается")
	bars.toggle_lock()
	bars.save_cfg()
	var b2 := ShortcutBars.new(); b2.data = z.data; b2.pos = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	for b in 3:
		var pg := []
		for p in ShortcutBars.PAGES:
			var row := []; for i in ShortcutBars.SIZES[b]: row.append({})
			pg.append(row)
		b2.sc.append(pg)
	b2.load_cfg()
	check(b2.pos[1] == Vector2(300, 200) and b2.shown[2] and b2.sc[1][0][5].get("id", "") == sid and b2.sc[0][1][0].get("k", "") == "potion", "раскладка и ярлыки сохраняются в файл")
	b2.free()
	# окно группы
	PartyUI.preview = true
	Net.party = {"id": 1, "leader": Net.my_id, "members": [
		{"id": Net.my_id, "name": "ПанелиL2", "cls": "warrior", "lvl": 20, "hp": 1.0, "mp": 1.0, "zone": z.zone_id if "zone_id" in z else "starter"},
		{"id": 777, "name": "Лекарь", "cls": "priest", "lvl": 19, "hp": 0.6, "mp": 0.35, "zone": "starter"}]}
	var pu: PartyUI = z.party_ui
	check(pu != null and pu.head_bar != null, "окно группы (ПК) с заголовком")
	if pu:
		pu._t = 0.0; await w(0.4)
		check(pu.head_bar.visible and pu.frames.get_child_count() >= 2, "рамки участников видны")
		var mp: ProgressBar = pu.frames.get_child(1).get_node("Mp")
		check(absf(mp.value - 0.35) < 0.01, "полоса маны союзника (%.2f)" % mp.value)
		var ev := InputEventMouseButton.new(); ev.button_index = MOUSE_BUTTON_LEFT; ev.pressed = true; ev.global_position = pu.head_bar.position + Vector2(5, 5); ev.position = ev.global_position
		pu._head_input(ev)
		pu._place_frames(Vector2(1400, 420))
		ev.pressed = false; pu._head_input(ev)
		var cf := ConfigFile.new(); cf.load("user://ui_layout.cfg")
		check(cf.get_value("party", "pos", Vector2.ZERO) == Vector2(1400, 420), "позиция окна группы сохранена")
		pu.select_member(Net.my_id)
		check(z.target_ctl.target == z.player, "щелчок по своей рамке — цель «я»")
	await w(0.5)
	await shot("after_pc_l2_bars")
	Controls.reset_defaults()
	PartyUI.preview = false
	_done()

func _done() -> void:
	print("L2UI: %d checks, %d errors" % [checks, errors])
	print("L2UI OK" if errors == 0 else "L2UI FAIL")
	get_tree().quit(0 if errors == 0 else 1)
