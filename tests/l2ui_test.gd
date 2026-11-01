extends Node
## v0.9.3: проверка ПК-интерфейса в стиле L2 — панели ярлыков, переназначение клавиш, окно группы.
## xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1920x1080 res://tests/l2ui_test.tscn [++ --touch]
var is_runner := false
var out := "/workspace/rpg-shots/v0951"
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

func mouse_drag(a: Vector2, b: Vector2) -> void:
	var vp := get_viewport()
	var mm := InputEventMouseMotion.new(); mm.position = a; mm.global_position = a; vp.push_input(mm); await w(0.05)
	var e := InputEventMouseButton.new(); e.button_index = MOUSE_BUTTON_LEFT; e.pressed = true; e.position = a; e.global_position = a
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	vp.push_input(e); await w(0.1)
	for k in range(1, 21):
		var m := InputEventMouseMotion.new(); m.position = a.lerp(b, k / 20.0); m.global_position = m.position
		m.button_mask = MOUSE_BUTTON_MASK_LEFT; m.relative = (b - a) / 20.0
		vp.push_input(m); await get_tree().process_frame
	await w(0.1)
	var r := InputEventMouseButton.new(); r.button_index = MOUSE_BUTTON_LEFT; r.pressed = false; r.position = b; r.global_position = b
	vp.push_input(r); await w(0.2)

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
	check(bars != null and bars.panels.size() == 1 and bars.root.get_child_count() == 1, "ПК: ровно одна панель умений")
	var btns := []
	for ch in bars.panels[0].get_children(): if ch is Button: btns.append(String(ch.name))
	check(btns.size() == 2 and "Rot" in btns and "Lock" in btns, "на панели только 2 кнопки: поворот и замок (%s)" % [btns])
	check(not z.hud.skill_btns[1].visible, "ПК: старый ряд круглых кнопок скрыт")
	check(bars.slots[0].size() == 10 and bars.slots[0][0].key_hint == "1" and bars.slots[0][9].key_hint == "0", "панель: 10 ячеек, клавиши 1…0")
	check(Controls.key_hint("target_self") == "F", "«Цель — я» на F")
	var lo: Array = z.data["loadout"]
	var all8 := true
	for i in 8: all8 = all8 and bars.get_slot(0, i).get("id", "") == str(lo[i])
	check(all8 and bars.get_slot(0, 8).get("k", "") == "potion", "по умолчанию: 8 умений набора на 1…8, зелье на 9")
	z.player.cooldowns.fill(0.0)
	key(z, KEY_1); await w(0.2)
	check(z.player.cooldowns[1] > 0.0, "клавиша 1 применила умение из ячейки (перезарядка %.1f)" % z.player.cooldowns[1])
	Controls.rebind("skill_1", 0, KEY_Z); Controls.save()
	get_tree().call_group("hud_listeners", "refresh_key_hints")
	check(bars.slots[0][0].key_hint == "Z", "после переназначения подсказка ячейки = Z (сразу)")
	Controls.rebind("skills", 0, KEY_O)
	get_tree().call_group("hud_listeners", "refresh_key_hints")
	check(z.hud.menu_items["skills"].text.contains("[O]"), "меню: подсказка «Умения [O]» обновилась (%s)" % z.hud.menu_items["skills"].text)
	z.player.cooldowns.fill(0.0); await w(0.6)
	key(z, KEY_Z); await w(0.2)
	check(z.player.cooldowns[1] > 0.0, "новая клавиша Z применяет умение")
	Controls.reset_defaults(); get_tree().call_group("hud_listeners", "refresh_key_hints")
	# --- баг 0.9.5: выбранное умение не ставилось на панель ---
	# 1) умение, которого нет в наборе (набор полон), бросаем на ячейку 0 → попадает и на панель, и в набор
	var spare := ""
	for s in DB.CLASSES[z.data["class"]].skills.slice(1):
		if DB.skill_lock(z.data, s) == "" and lo.find(s.id) < 0: spare = s.id; break
	if spare == "":   # все изучены и в наборе — освободим одно умение
		var kk := 7
		while kk > 0 and str(lo[kk]) == "": kk -= 1
		spare = str(lo[kk]); DB.set_loadout_slot(z.data, kk, ""); await w(0.2)
		check(not bars._on_bar(spare), "снятое с набора умение ушло с панели")
	check(spare != "", "есть изученное умение вне набора (%s)" % spare)
	bars.drop(0, 0, {"skill": spare, "from": -1})
	check(bars.get_slot(0, 0).get("id", "") == spare and lo.find(spare) >= 0, "умение вне набора поставлено на ячейку 1 (и попало в набор)")
	z.player.cooldowns.fill(0.0); await w(0.6)
	key(z, KEY_1); await w(0.2)
	check(z.player.cooldowns[lo.find(spare) + 1] > 0.0, "клавиша 1 применяет поставленное умение")
	# 2) выбор в окне «Умения» (слот набора) сразу отражается на панели
	var other := str(lo[1])
	z.hud._open("skills"); await w(0.4)
	var sw = z.hud.window
	var sl := lo.find(spare)
	DB.set_loadout_slot(z.data, sl, "")
	sw.drop_on_slot(other if false else spare, sl)
	z.hud.close_window(); await w(0.3)
	check(bars._on_bar(spare), "выбранное в окне «Умения» умение стоит на панели")
	# 3) настоящая мышь: тянем умение из списка окна «Умения» на ячейку 10
	var mv := str(lo[3])
	bars.set_slot(0, 9, {}); for ci in 10: if bars.get_slot(0, ci).get("id", "") == mv: bars.set_slot(0, ci, {})
	z.hud._open("skills"); await w(0.5)
	sw = z.hud.window
	var src: Control = sw.find_child("Skill_" + mv, true, false)
	if src == null:
		for n in sw.find_children("*", "Button", true, false):
			if (n as Button).text.begins_with(DB.find_skill(z.data, mv).name): src = n; break
	check(src != null, "кнопка умения в окне найдена")
	if src:
		var a0: Vector2 = src.get_global_rect().get_center()
		var dst: Vector2 = bars.slots[0][9].get_global_rect().get_center()
		await mouse_drag(a0, dst)
		check(bars.get_slot(0, 9).get("id", "") == mv, "мышью: умение перетащено из окна «Умения» на ячейку 0 (%s)" % [bars.get_slot(0, 9)])
		await shot("after_pc_skills_drag")
	z.hud.close_window(); await w(0.3)
	# зелье на 9
	z.player.hp = z.player.stats.max_hp * 0.4
	var pots := int(z.data["potions"])
	key(z, KEY_9); await w(0.2)
	check(int(z.data["potions"]) == pots - 1, "клавиша 9: зелье (%d → %d)" % [pots, int(z.data["potions"])])
	# вещь на панель → надеть
	bars.drop(0, 9, {"item": str(it.uid)})
	key(z, KEY_0); await w(0.3)
	check(Items.find_uid(z.data["equipped"], str(it.uid)) != null, "клавиша 0: вещь с панели надета")
	# обмен ячеек
	var e1 := bars.get_slot(0, 1)
	bars.drop(0, 5, {"sc": [0, 1]})
	check(bars.get_slot(0, 5) == e1, "ярлык перенесён между ячейками")
	# перемещение мышью за пустую ячейку / рамку, поворот, закрепление, сохранение
	bars.set_slot(0, 9, {})
	var p0: Vector2 = bars.panels[0].position
	await mouse_drag(bars.slots[0][9].get_global_rect().get_center(), bars.slots[0][9].get_global_rect().get_center() + Vector2(-300, -400))
	check(bars.panels[0].position.distance_to(p0 + Vector2(-300, -400)) < 4, "панель перетащена мышью (%s → %s)" % [p0, bars.panels[0].position])
	bars.rotate_bar()
	check(bars.vertical and bars.panels[0].size.y > bars.panels[0].size.x, "поворот: вертикально")
	bars.move_bar(0, Vector2(1700, 150))
	await shot("after_pc_bar_vertical")
	bars.toggle_lock()
	var pl: Vector2 = bars.panels[0].position
	await mouse_drag(bars.panels[0].get_global_rect().position + Vector2(4, 4), Vector2(400, 600))
	check(bars.locked and bars.panels[0].position == pl and bars.slots[0][5]._get_drag(Vector2.ZERO) == null, "закреплено: панель не двигается, ярлык не вытаскивается")
	bars.toggle_lock()
	bars.save_cfg()
	var b2 := ShortcutBars.new(); b2.data = z.data
	for i in 10: b2.sc.append({})
	b2.load_cfg()
	check(b2.pos == bars.pos and b2.vertical and b2.sc[5] == e1, "положение, поворот и ярлыки сохраняются в файл")
	b2.free()
	bars.rotate_bar(); bars.move_bar(0, Vector2(560, 960)); bars.save_cfg()
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
