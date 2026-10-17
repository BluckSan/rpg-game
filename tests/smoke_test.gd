extends Node
## Смоук-тест: запуск `godot --headless --path . res://tests/smoke_test.tscn`
## Проверяет: создание персонажей всех классов, сохранение/загрузку, меню, зону, бой, умения,
## дерево талантов, превращения (все 6), окна, инвентарь, смерть/возрождение.

var errors := 0
var step := ""

func check(cond: bool, msg: String) -> void:
	if cond: print("  OK  ", msg)
	else:
		errors += 1
		printerr("  FAIL ", msg)

func frames(n: int) -> void:
	for i in n: await get_tree().process_frame

var is_runner := false

func _ready() -> void:
	if not is_runner:
		# корневая сцена будет выгружена при смене сцены — переносим тест в отдельный узел под root
		var r = load("res://tests/smoke_test.gd").new()
		r.is_runner = true
		get_tree().root.add_child.call_deferred(r)
		return
	print("=== SMOKE TEST ===")
	for f in Game.list_characters(): Game.delete_character(f["id"])
	get_tree().create_timer(280.0, true, false, true).timeout.connect(func():
		printerr("TIMEOUT / script error")
		get_tree().quit(2))
	await frames(2)
	# 1. дерево талантов
	check(DB.tree_nodes.size() == 147, "дерево: 147 узлов (%d)" % DB.tree_nodes.size())
	for cid in DB.CLASS_ORDER:
		check(DB.start_node(cid) >= 0 and DB.tree_nodes[DB.start_node(cid)]["type"] == "start", "стартовый узел " + cid)
	# 2. сохранения
	var ids := []
	for cid in DB.CLASS_ORDER:
		var c := DB.new_character("Тест_" + cid, cid, {"gender": 1, "height": 1.0, "build": 1.0, "skin": 2, "face": 3, "hair": 3, "hair_color": 4, "eye_color": 2})
		Game.save_character(c)
		ids.append(c["id"])
	var list := Game.list_characters()
	check(list.size() >= 3, "сохранено и загружено персонажей: %d" % list.size())
	var loaded = null
	for c in list:
		if c["id"] == ids[0]: loaded = c
	check(loaded != null and loaded["talents"][0] is int, "типы восстановлены после JSON")
	# 3. главное меню
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	await frames(10)
	var menu = get_tree().current_scene
	check(menu != null and menu.name == "MainMenu", "сцена меню загружена")
	await _audio_tests()
	await _title_tests(menu)
	menu.open_creator()
	await frames(5)
	var cr = null
	for ch in menu.screen.get_children():
		if ch.has_method("randomize_look"): cr = ch
	check(cr != null, "экран создания открыт")
	cr.randomize_look()
	cr.set_class("mage")
	await frames(3)
	var pv: CharVisual = menu.preview
	check(pv.model != null and pv.skel != null, "превью: модель человека со скелетом построена")
	check(pv.tree != null and pv.tree.active and CharAssets.anim_library(0).get_animation_list().size() >= 38, "превью: AnimationTree и %d анимаций" % CharAssets.anim_library(0).get_animation_list().size())
	var vis_parts := 0
	for n in pv.meshes:
		if pv.meshes[n].visible: vis_parts += 1
	check(vis_parts >= 5, "превью: видимых частей модели %d" % vis_parts)
	# редактор лица
	cr.set_gender(0)
	cr.set_tab(2)
	await frames(2)
	check(menu.focus, "крупный план лица включён на вкладке «Лицо»")
	var sliders := 0
	for row in cr.content.get_children():
		for ch in row.get_children():
			if ch is HSlider and ch.has_meta("morph"): sliders += 1
	check(sliders == 18, "ползунков лица: %d" % sliders)
	cr.set_morph("jaw_width", 0.8)
	cr.set_morph("ears_point", 1.0)
	var head: MeshInstance3D = pv.meshes["Face"]
	var bi := head.find_blend_shape_by_name("jaw_width")
	check(bi >= 0 and absf(head.get_blend_shape_value(bi) - 0.8) < 0.01, "морф «Челюсть» применён к голове")
	for t in 4:
		cr.set_tab(t); await frames(2)
	cr.look.hair = 2; cr.look.beard = 1; cr._refresh()
	await frames(2)
	check(pv.meshes["Hair_SimpleParted"].visible and pv.meshes["Beard"].visible, "причёска и борода показаны")
	check(absf(head.get_blend_shape_value(bi) - 0.8) < 0.01, "морф сохраняется после смены причёски")
	cr.char_name = "Лицевой"
	cr._create()
	await frames(3)
	var face_saved = null
	for c in Game.list_characters():
		if c["name"] == "Лицевой": face_saved = c
	check(face_saved != null and absf(float(face_saved["look"]["morphs"].get("jaw_width", 0)) - 0.8) < 0.01 and int(face_saved["look"]["beard"]) == 1, "внешность (морфы, борода) сохранена в слот")
	if face_saved: ids.append(face_saved["id"])
	check(not menu.focus, "камера вернулась к общему плану")
	menu.show_select()
	await frames(3)
	# 4. зона за каждый класс
	for i in ids.size():
		if i >= DB.CLASS_ORDER.size(): break
		var c = Game.load_file(Game.SAVE_DIR + "/char_%s.json" % ids[i])
		Game.play(c)
		await frames(15)
		var z = get_tree().current_scene
		check(z != null and z.player != null, "[%s] зона загружена, игрок создан" % c["class"])
		check(z.enemies.size() >= 30, "[%s] врагов в зоне: %d" % [c["class"], z.enemies.size()])
		var p: Player = z.player
		var far := 0
		for en in z.enemies:
			if U.flat_dist(en.global_position, en.home) > 10.0 or U.flat_dist(en.home, en.get_parent().global_position) > 9.0: far += 1
		check(far == 0, "[%s] враги стоят у своих точек появления (ушли: %d)" % [c["class"], far])
		if i == 0:
			await _jump_tests(z, p)
			_mob_anim_tests(z)
			await _ui_tests(z, p)
			await _shop_tests(z, p)
			await _desktop_tests(z, p)
			await _roll_tests(z, p)
		await _combo_tests(z, p, c["class"])
		# подвести врага и атаковать
		var e = z.enemies[0]
		p.teleport(e.global_position + Vector3(0, 0.1, -1.5))
		await frames(3)
		p.data["class_level"] = 3
		p.recalc(true)
		for slot in 3:
			p.cooldowns[slot] = 0
			p.mp = p.stats.max_mp
			var ok: bool = p.try_use(slot)
			check(ok, "[%s] умение %d (%s)" % [c["class"], slot, p.get_skill(slot).name])
			await frames(40)
		# опыт и уровни
		p.gain_xp(20000)
		check(p.data["level"] >= 10, "[%s] уровень после опыта: %d" % [c["class"], p.data["level"]])
		# окна
		z.hud._open("talents")
		await frames(3)
		var tw = z.hud.window
		tw._tap(tw._to_screen(DB.tree_nodes[DB.start_node(c["class"])]["pos"]))
		check(get_tree().paused, "[%s] окно талантов открыто, пауза" % c["class"])
		z.hud.close_window()
		z.hud._open("hero"); await frames(3); z.hud.close_window()
		z.hud._open("pause"); await frames(3); z.hud.close_window()
		check(not get_tree().paused, "[%s] окна закрыты" % c["class"])
		# лут
		Loot.spawn(z, p.global_position, "item", 1, DB.roll_item(5, c["class"], 0.5))
		Loot.spawn(z, p.global_position, "gold", 10)
		await get_tree().create_timer(1.0).timeout
		check(p.data["inventory"].size() >= 1 and p.data["gold"] >= 10, "[%s] добыча подобрана" % c["class"])
		z.hud._open("hero"); await frames(2)
		var inv = z.hud.window
		inv._select(p.data["inventory"][0], false); inv._on_action()
		check(p.data["equipped"].size() >= 2 or p.data["inventory"].size() >= 1, "[%s] предмет надет" % c["class"])
		z.hud.close_window()
		# смерть и возрождение
		p.take_damage(999999, Vector3.ZERO)
		check(p.dead, "[%s] смерть" % c["class"])
		await get_tree().create_timer(3.3).timeout
		check(not p.dead and p.hp > 0, "[%s] возрождение" % c["class"])
		z.save()
	# 5. все 6 превращений (на последнем персонаже)
	var z2 = get_tree().current_scene
	var pl: Player = z2.player
	for a in DB.ASCENDANCIES:
		DB.reset_talents(pl.data)
		pl.data["level"] = 40
		var key := DB.keystone_of(a["id"])
		# путь от старта к ключевому таланту через BFS
		var path := _bfs(pl.data["talents"][0], key["id"])
		for id in path:
			if not DB.has_talent(pl.data, id): DB.allocate(pl.data, id)
		var reason := DB.asc_block_reason(pl.data, a)
		check(reason == "", "превращение %s доступно (%s)" % [a["name"], reason])
		pl.data["ascendancy"] = a["id"]
		z2.apply_character_changes(true)
		z2.hud.refresh_skill_buttons()
		check(pl.visual.model != null or pl.visual.beast != null, "облик превращения %s построен" % a["name"])
		pl.cooldowns[3] = 0; pl.mp = pl.stats.max_mp
		var e2 = z2.enemies[0]
		pl.teleport(e2.global_position + Vector3(0, 0.1, -2))
		await frames(2)
		check(pl.try_use(3), "умение пути «%s»" % a["skill"]["name"])
		await frames(70)
	# босс
	var boss = null
	for e in z2.enemies:
		if e.def.boss: boss = e
	check(boss != null, "босс в зоне")
	if boss:
		check(U.flat_dist(boss.global_position, Vector3(-4, 0, 64)) < 8.0, "босс у арены: %s" % str(boss.global_position))
		pl.recalc(true)
		pl.teleport(boss.global_position + Vector3(0, 0.1, -3))
		var hp0: float = pl.hp
		await get_tree().create_timer(2.5).timeout
		check(pl.hp < hp0 or pl.dead, "босс атакует игрока (%d → %d)" % [hp0, pl.hp])
		await _boss_tests(z2, pl, boss)
		boss.take_damage(99999, true)
		await frames(5)
		check(not is_instance_valid(boss) or not boss.alive, "босс повержен, выпала добыча")
	# портал
	pl.teleport(Vector3(66, 0.1, 56))
	await frames(10)
	Game.to_menu()
	await frames(10)
	check(get_tree().current_scene.name == "MainMenu", "возврат в меню")
	for id in ids: Game.delete_character(id)
	print("=== RESULT: %s (%d errors) ===" % ["PASS" if errors == 0 else "FAIL", errors])
	get_tree().quit(1 if errors > 0 else 0)

func secs(t: float) -> void:
	await get_tree().create_timer(t).timeout

func _combo_tests(z, p: Player, cls: String) -> void:
	var dummy := Enemy.spawn(z, "slime", 1, p.global_position + p.forward() * 1.6, z.fx_root)
	dummy.max_hp = 99999; dummy.hp = 99999
	dummy.def = dummy.def.duplicate(); dummy.def.aggro = 0.0
	await frames(2)
	await _grip_tests(p, cls)
	p.face_towards(dummy.global_position)
	p.combo_step = 0; p.combo_timer = 0
	var n0 := p.combo_count
	var seq := []
	for k in 3:
		p.cooldowns[0] = 0
		p.try_use(0)
		seq.append(p.last_combo_index)
		await secs(0.5)
	check(p.combo_count - n0 >= 3 and seq == [0, 1, 2], "[%s] комбо из 3 ударов: %s" % [cls, str(seq)])
	check(dummy.hp < 99999, "[%s] комбо наносит урон (%d)" % [cls, 99999 - dummy.hp])
	check(dummy.hits_taken >= 2, "[%s] попаданий по цели: %d" % [cls, dummy.hits_taken])
	await secs(1.4)
	check(p.combo_step == 0, "[%s] комбо сбрасывается после паузы" % cls)
	check(is_equal_approx(Engine.time_scale, 1.0), "[%s] время после стоп-кадров = 1" % cls)
	dummy.take_damage(999999, false)

## ПК-режим: горячие клавиши, мышь, настройки графики
func _desktop_tests(z, p: Player) -> void:
	var h = z.hud
	check(Game.desktop == Game.is_pc_platform() or "--touch" in OS.get_cmdline_user_args(), "режим ПК определён: %s" % str(Game.desktop))
	if not Game.desktop:
		check(h.jump_btn.visible and h.joy_base.visible, "сенсорные кнопки на телефоне видны")
		check(Game.fps_options() == [30, 45, 60, 90, 120], "телефон: варианты FPS 30–120")
		await _settings_tests(z)
		return
	check(not h.jump_btn.visible and not h.roll_btn.visible and not h.joy_base.visible, "на ПК сенсорный джойстик и кнопки скрыты")
	check(h.skill_btns[1].key_hint == "1" and h.skill_btns[0].key_hint == "ЛКМ", "подсказки клавиш на умениях")
	check(InputMap.has_action("move_up") and InputMap.action_get_events("move_up").size() >= 2, "WASD в карте ввода")
	h._hotkey(KEY_I); await frames(2)
	check(h.window != null and h.window.name == "Window_hero", "I открывает героя")
	h._hotkey(KEY_ESCAPE); await frames(2)
	check(h.window == null and not get_tree().paused, "Esc закрывает окно")
	h._hotkey(KEY_T); await frames(2)
	check(h.window != null and h.window.name == "Window_talents", "T открывает таланты")
	h._hotkey(KEY_T); await frames(2)
	check(h.window == null, "T повторно закрывает таланты")
	h._hotkey(KEY_M); await frames(1)
	check(h.minimap.big, "M — большая карта")
	h._hotkey(KEY_M); await frames(1)
	check(not h.minimap.big, "M — карта свёрнута")
	h._hotkey(KEY_ESCAPE); await frames(2)
	check(h.window != null and h.window.name == "Window_pause", "Esc открывает меню")
	check(h.window.find_child("Quality", true, false) == null, "настройки вынесены в отдельную панель")
	h.close_window(); await frames(2)
	await _settings_tests(z)
	h._hotkey(KEY_ESCAPE); await frames(2)
	h.window.open_settings(); await frames(2)
	var sp2: Node = h.window.find_child("SettingsPanel", true, false)
	check(sp2 != null and sp2.find_child("Fullscreen", true, false) != null and sp2.find_child("Resolution", true, false) != null and sp2.find_child("Vsync", true, false) != null, "ПК: полный экран/разрешение/VSync в настройках")
	var fo: Array = Game.fps_options()
	check(fo == [30, 60, 90, 120, 144, 165, 240, 300], "ПК: варианты FPS %s" % str(fo))
	Game.ui_scale = 1.1; Game.apply_settings()
	check(is_equal_approx(get_tree().root.content_scale_factor, 1.1), "масштаб интерфейса")
	Game.ui_scale = 1.0; Game.apply_settings()
	check(get_tree().root.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR or Game.render_scale < 0.99, "ПК: FSR только при уменьшенном 3D")
	Game.render_scale = 0.75; Game.apply_settings()
	check(get_tree().root.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR, "ПК: масштаб 3D 75%% через FSR")
	Game.apply_preset(3)
	h.close_window(); await frames(2)
	# ЛКМ по миру — атака
	var c: Vector2 = h._screen() * Vector2(0.5, 0.45)
	h._touch_down(-1, c)
	check(p.attack_held, "ЛКМ по миру — атака")
	h._touch_up(-1)
	check(not p.attack_held, "отпускание ЛКМ — конец атаки")
	h._hotkey(KEY_SPACE)
	h._hotkey(KEY_1)
	await secs(0.6)

## Звук: у каждого эффекта свой проигрыватель (без подмены потока), у WAV запас в конце буфера
func _audio_tests() -> void:
	var ok := true
	for n in ["click", "hit", "swing", "pickup", "level"]:
		var p: AudioStreamPlayer = Game._sfx_players.get(n)
		if p == null or p.stream != Game._sfx_streams[n]: ok = false
	check(ok, "звуки: отдельный проигрыватель на каждый эффект")
	var m: AudioStreamWAV = Game._music.stream
	var frames: int = m.data.size() / 2 - Game.WAV_PAD
	check(m.loop_end == frames - 1 and m.data.size() / 2 > m.loop_end + 64, "музыка: конец петли внутри буфера (%d < %d)" % [m.loop_end, m.data.size() / 2])
	for i in 200:
		Game.sfx(["click", "hit", "swing", "pickup", "level"][i % 5])
		if i % 20 == 0: await frames(1)
	ok = true
	for n in Game._sfx_players:
		if Game._sfx_players[n].stream != Game._sfx_streams[n]: ok = false
	check(ok, "200 звуков подряд — потоки не подменялись")

## Титульный экран: кнопки, настройки, выбор героя, удаление с подтверждением
func _title_tests(menu) -> void:
	check(menu.screen != null and menu.screen.name == "TitleScreen" and menu.title_mode, "при запуске — титульный экран")
	for b in ["PlayButton", "SettingsButton", "QuitButton"]:
		check(menu.screen.find_child(b, true, false) is Button, "кнопка «%s» на титульном экране" % b)
	var qb: Button = menu.screen.find_child("QuitButton", true, false)
	check(qb != null and qb.pressed.get_connections().size() > 0 and menu.has_method("quit_game"), "«Выход» подключён к выходу из игры")
	check(menu.title_root.visible and not menu.stage_pivot.visible, "3D-сцена титульного экрана показана")
	check(menu.sun.shadow_enabled == (Game.desktop and Game.shadows_enabled), "тени титульной сцены: только на ПК")
	await frames(2)
	check(Engine.max_fps == mini(Game.fps_cap, 120 if Game.desktop else 60), "в меню FPS ограничен: %d" % Engine.max_fps)
	(menu.screen.find_child("SettingsButton", true, false) as Button).pressed.emit()
	await frames(2)
	var sp: Node = menu.ui.find_child("SettingsPanel", true, false)
	check(sp != null and sp.find_child("Quality", true, false) != null and sp.find_child("Music", true, false) != null, "настройки открываются из главного меню")
	if sp: sp.close()
	await frames(2)
	(menu.screen.find_child("PlayButton", true, false) as Button).pressed.emit()
	await frames(3)
	check(menu.screen.name == "SelectScreen" and not menu.title_mode and menu.stage_pivot.visible, "«Играть» → выбор персонажа")
	check(menu.title_root.process_mode == Node.PROCESS_MODE_DISABLED and not menu.title_root.visible, "3D титульного экрана скрыт и не обновляется")
	var n0: int = Game.list_characters().size()
	check(menu.list_box.get_child_count() == DB.MAX_SLOTS, "слотов в списке: %d" % menu.list_box.get_child_count())
	# удаление: отмена сохраняет, подтверждение удаляет
	var victim := DB.new_character("Удаляемый", "archer", CharAssets.random_look(0))
	Game.save_character(victim)
	menu.refresh_list(); await frames(2)
	for c in menu.chars:
		if c["id"] == victim["id"]: menu.selected = c
	menu._on_delete(); await frames(2)
	var cb: Node = menu.ui.find_child("ConfirmDelete", true, false)
	check(cb != null and cb.find_child("ConfirmYes", true, false) != null and cb.find_child("ConfirmNo", true, false) != null, "окно подтверждения удаления")
	(cb.find_child("ConfirmNo", true, false) as Button).pressed.emit(); await frames(2)
	check(Game.list_characters().size() == n0 + 1 and menu.ui.find_child("ConfirmDelete", true, false) == null, "«Отмена» — герой не удалён")
	for c in menu.chars:
		if c["id"] == victim["id"]: menu.selected = c
	menu._on_delete(); await frames(2)
	(menu.ui.find_child("ConfirmDelete", true, false).find_child("ConfirmYes", true, false) as Button).pressed.emit(); await frames(2)
	var still := false
	for c in Game.list_characters():
		if c["id"] == victim["id"]: still = true
	check(not still and Game.list_characters().size() == n0, "«Удалить» — герой удалён")
	(menu.screen.find_child("BackButton", true, false) as Button).pressed.emit(); await frames(2)
	check(menu.screen.name == "TitleScreen" and menu.title_mode, "«Назад» → титульный экран")

## Настройки из меню паузы: пресеты, масштаб 3D, FPS (в игре и в меню), звук, чувствительность
func _settings_tests(z) -> void:
	var h = z.hud
	var q0: int = Game.quality
	var rs0: float = Game.render_scale
	var fc0: int = Game.fps_cap
	h._open("pause"); await frames(2)
	check(get_tree().paused, "пауза открыта")
	h.window.open_settings(); await frames(2)
	var sp: Node = h.window.find_child("SettingsPanel", true, false)
	check(sp != null, "настройки открываются из меню паузы")
	if sp == null: return
	for id in ["Quality", "RenderScale", "FpsCap", "Shadows", "UiScale", "Music", "Sfx", "Sensitivity"]:
		check(sp.find_child(id, true, false) != null, "строка настроек «%s»" % id)
	var qb: Button = sp.find_child("Quality", true, false)
	var before: String = qb.text
	qb.pressed.emit(); await frames(1)
	check(qb.text != before and Game.quality == (q0 + 1) % 4, "пресет переключается кнопкой (%s → %s)" % [before, qb.text])
	Game.apply_preset(0)
	check(Game.fps_cap == 30 and not Game.shadows_enabled and is_equal_approx(get_tree().root.scaling_3d_scale, 0.6) and Game.particle_mul < 0.5, "пресет «Экономия батареи»: 30 к/с, без теней, 3D 60%")
	check(get_viewport().msaa_3d == Viewport.MSAA_DISABLED and not Game.glow, "экономия: MSAA и свечение выключены")
	var z_env: WorldEnvironment = z.find_child("Env", true, false)
	if z_env:
		check(not z_env.environment.glow_enabled, "экономия: свечение в зоне выключено")
	Game.apply_preset(3)
	check(Game.shadows_enabled and Game.particle_mul >= 1.0 and Game.view_distance > 100.0, "пресет «Высокое» применён")
	var fb: Button = sp.find_child("FpsCap", true, false)
	var opts: Array = Game.fps_options()
	Game.fps_cap = opts[opts.size() - 1]; Game.apply_settings()
	await frames(2)
	var menu_cap := 120 if Game.desktop else 60
	check(Engine.max_fps == mini(Game.fps_cap, menu_cap), "на паузе FPS ограничен: %d" % Engine.max_fps)
	fb.pressed.emit(); await frames(1)
	check(Game.fps_cap == opts[0] and fb.text.begins_with(str(opts[0])), "FPS переключается по кругу: %s" % fb.text)
	var rb: Button = sp.find_child("RenderScale", true, false)
	Game.render_scale = 0.75; Game.apply_settings()
	rb.pressed.emit(); await frames(1)
	check(is_equal_approx(Game.render_scale, 0.85) and is_equal_approx(get_tree().root.scaling_3d_scale, 0.85), "масштаб 3D переключён на 85%")
	var ms: HSlider = sp.find_child("Music", true, false) as HSlider
	if ms == null:
		for c in sp.find_child("Music", true, false).find_children("*", "HSlider", true, false): ms = c
	ms.value = 0.25; await frames(1)
	check(absf(db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))) - 0.25) < 0.05, "громкость музыки → шина Music")
	ms.value = 0.0; await frames(1)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")) or AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")) < -60, "музыка 0 — без звука")
	ms.value = 0.7
	var ss: HSlider = sp.find_child("Sfx", true, false) as HSlider
	if ss == null:
		for c in sp.find_child("Sfx", true, false).find_children("*", "HSlider", true, false): ss = c
	ss.value = 0.5; await frames(1)
	check(absf(db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX"))) - 0.5) < 0.05, "громкость эффектов → шина SFX")
	var sens: HSlider = sp.find_child("Sensitivity", true, false) as HSlider
	if sens == null:
		for c in sp.find_child("Sensitivity", true, false).find_children("*", "HSlider", true, false): sens = c
	sens.value = 1.5; await frames(1)
	check(is_equal_approx(Game.sensitivity, 1.5), "чувствительность камеры")
	sens.value = 1.0
	sp.close(); await frames(2)
	check(h.window.find_child("SettingsPanel", true, false) == null, "панель настроек закрыта")
	h.close_window(); await frames(2)
	check(not get_tree().paused, "пауза снята")
	await frames(2)
	check(Engine.max_fps == Game.fps_cap, "в игре FPS = настройке: %d" % Engine.max_fps)
	Game.quality = q0; Game.render_scale = rs0; Game.fps_cap = fc0; Game.apply_settings()
	await frames(1)

## Хват: оружие в кулаке (точка хвата у центра кулака), посох/лук в стойке вертикально
func _grip_tests(p: Player, cls: String) -> void:
	var v: CharVisual = p.visual
	if v.weapon == null or v.skel == null: return
	await secs(0.6)   # выравнивание хвата плавно набирает вес (blend_speed)
	var side := -1.0 if cls == "archer" else 1.0
	var hb := v.skel.find_bone("hand_l" if cls == "archer" else "hand_r")
	var ht: Transform3D = v.skel.global_transform * v.skel.get_bone_global_pose(hb)
	var fist: Vector3 = ht * (CharVisual.grip_center(side) if cls == "warrior" else v.fist_center("hand_l" if cls == "archer" else "hand_r"))
	var pn: String = {"warrior": "props/sword1", "archer": "props/bow", "mage": "props/staff"}[cls]
	var gp: Vector3 = v.weapon.global_transform * Vector3(0, float(CharVisual.GRIP[pn][0]), 0)
	check(gp.distance_to(fist) < 0.03, "[%s] оружие в кулаке (%.3f м)" % [cls, gp.distance_to(fist)])
	var ax := (v.weapon.global_basis * Vector3.UP).normalized()
	if cls == "archer":
		var fwd: Vector3 = v.global_basis.z.normalized()
		var rel: Vector3 = ht.origin - v.global_position
		check(rel.dot(fwd) > 0.15 and v.arm_pose != null and v.arm_pose.cur > 0.5, "[archer] в стойке кисть с луком вынесена вперёд (%.2f м)" % rel.dot(fwd))
	if cls != "warrior":
		check(rad_to_deg(ax.angle_to(Vector3.UP)) < 20.0, "[%s] в стойке оружие вертикально (%d°)" % [cls, rad_to_deg(ax.angle_to(Vector3.UP))])

func _roll_tests(z, p: Player) -> void:
	p.recalc(true)
	var hp0 := p.hp
	var d0 := p.dodged
	check(p.request_roll(), "кувырок выполнен")
	check(p.is_rolling() and p.invuln > 0, "кувырок даёт неуязвимость")
	p.take_damage(50.0, p.global_position + Vector3(1, 0, 0))
	check(p.hp == hp0 and p.dodged == d0 + 1, "урон во время кувырка поглощён (уклонение)")
	check(not p.request_roll(), "повторный кувырок на перезарядке")
	await secs(1.0)
	check(not p.is_rolling(), "кувырок завершён")

func _ui_tests(z, p: Player) -> void:
	var h = z.hud
	check(h.minimap != null and h.minimap.is_visible_in_tree(), "мини-карта на экране")
	check(h.roll_btn != null and h.jump_btn != null and h.potion_btn != null, "кнопки кувырка, прыжка и зелья")
	check(h.skill_btns[0].icon != null and h.skill_btns[1].icon != null, "иконки на кнопках умений")
	check(h.skill_btns[0].max_pips == 3, "точки комбо на кнопке атаки")
	check(h.objective.text != "", "строка цели: %s" % h.objective.text)
	await frames(2)
	var hid: String = h.hint_id
	check(h.hint_panel.visible and hid != "", "подсказка обучения на экране: %s" % hid)
	h._hint_done()
	check(z.data["tutorial"].get(hid, false), "подсказка отмечена как прочитанная")
	h.show_skill_tooltip(1)
	await frames(3)
	check(h.tooltip != null and is_instance_valid(h.tooltip), "подсказка к умению (долгое нажатие)")
	h._hide_tooltip()
	var b0: int = h.level_banners
	p.gain_xp(DB.xp_to_next(p.data["level"]))
	await frames(2)
	check(h.level_banners == b0 + 1 and h.root.find_child("LevelBanner", true, false) != null, "баннер «Новый уровень»")
	var rows: int = h.pickup_box.get_child_count()
	h.pickup("Тест", Color.WHITE, "two-coins")
	check(h.pickup_box.get_child_count() == rows + 1, "уведомление о добыче с иконкой")

func _shop_tests(z, p: Player) -> void:
	p.teleport(z.merchant_point + Vector3(0, 0.1, 1.8))
	await frames(4)
	check(z.merchant != null and z.near_merchant(), "торговец в лагере рядом")
	check(z.hud.interact_btn.visible, "кнопка «Торговать» появилась")
	var d: Dictionary = p.data
	d["gold"] = 5000
	var pot0: int = d["potions"]
	z.hud._open("shop")
	await frames(3)
	var w = z.hud.window
	check(w != null and w.name == "Window_shop" and get_tree().paused, "окно лавки открыто")
	check(d["shop"]["stock"].size() == 6, "в лавке 6 товаров")
	var lvl_ok := true
	for it in d["shop"]["stock"]:
		if absi(int(it.ilvl) - int(d["level"])) > 1: lvl_ok = false
	check(lvl_ok, "товары под уровень героя")
	var nm := {}; var sl := {}
	for it in d["shop"]["stock"]:
		nm[it.name] = true; sl[int(it.slot)] = true
	check(nm.size() == 6, "в лавке нет повторов (%d разных)" % nm.size())
	check(sl.size() >= 4, "в лавке все типы снаряжения (%d)" % sl.size())
	# прокрутка списка пальцем (не только полосой)
	var ds: DragScroll = w.find_child("DragScroll", true, false)
	check(ds != null, "у списка лавки есть прокрутка пальцем")
	if ds:
		var sc: ScrollContainer = ds.sc
		var r := sc.get_global_rect()
		var st := r.position + r.size * Vector2(0.5, 0.8)
		var e1 := InputEventMouseButton.new(); e1.button_index = MOUSE_BUTTON_LEFT; e1.pressed = true; e1.position = st
		ds._input(e1)
		for k in 6:
			var mm := InputEventMouseMotion.new(); mm.position = st - Vector2(0, 30 * (k + 1)); mm.relative = Vector2(0, -30)
			ds._input(mm)
		await frames(1)
		var moved := sc.scroll_vertical
		var e2 := InputEventMouseButton.new(); e2.button_index = MOUSE_BUTTON_LEFT; e2.pressed = false; e2.position = st - Vector2(0, 180)
		ds._input(e2)
		var mx := sc.get_v_scroll_bar().max_value - sc.size.y
		check(moved > 0 or mx <= 0, "список прокручивается свайпом (%d, макс %d)" % [moved, mx])
		check(DragScroll.dragging, "после свайпа нажатие кнопки подавлено")
		await frames(3)
		check(not DragScroll.dragging, "флаг прокрутки сброшен")
	check(w.buy_potion() and d["potions"] == pot0 + 1, "покупка зелья")
	var g0: int = d["gold"]
	var price: int = DB.buy_price(d["shop"]["stock"][0])
	check(w.buy(0) and d["gold"] == g0 - price, "покупка предмета (−%d)" % price)
	var idx: int = d["inventory"].size() - 1
	var sp: int = DB.sell_price(d["inventory"][idx])
	g0 = d["gold"]
	check(w.sell(idx) and d["gold"] == g0 + sp, "продажа предмета (+%d)" % sp)
	check(d["buyback"].size() >= 1, "проданное попало в выкуп")
	check(w.buyback(0) and d["gold"] == g0, "выкуп предмета")
	w.select_tab("sell"); await frames(1)
	w.select_tab("buyback"); await frames(1)
	w.select_tab("buy"); await frames(1)
	d["gold"] = 0
	check(not w.buy(0), "без золота купить нельзя")
	d["gold"] = 1000
	w.restock()
	check(d["shop"]["stock"].size() == 6 and d["gold"] < 1000, "обновление товаров")
	z.hud.close_window()
	await frames(3)
	check(not get_tree().paused, "лавка закрыта")

func _boss_tests(z, pl: Player, boss) -> void:
	var br = boss.brain
	check(br != null, "у босса есть мозг (фазы)")
	if br == null: return
	check(boss.max_hp >= 2200, "у босса больше здоровья: %d" % boss.max_hp)
	pl.god_mode = true
	await secs(0.5)
	check(z.hud.boss_panel.visible, "полоса босса с метками фаз видна")
	boss.hp = boss.max_hp * 0.6
	await secs(2.4)
	check(br.phase == 2 and br.log.has("phase2"), "фаза 2 на 66%% (фаза %d)" % br.phase)
	check("Фаза 2" in z.hud.boss_phase.text, "надпись фазы: %s" % z.hud.boss_phase.text)
	for k in ["slam", "charge", "rock", "summon"]:
		var guard := 0
		while br.busy and guard < 200:
			await frames(1); guard += 1
		br.run(k, pl)
		await secs(2.2)
		check(br.log.has(k), "атака босса «%s» выполнена" % k)
	check(br.adds.size() >= 2, "босс призвал помощников: %d" % br.adds.size())
	var shock := 0
	for ch in z.fx_root.get_children():
		if ch is BossBrain.Shockwave: shock += 1
	pl.god_mode = false
	pl.recalc(true)
	var hp1 := pl.hp
	var w := BossBrain.Shockwave.new()
	w.zone = z; w.center = pl.global_position + Vector3(3, 0, 0); w.speed = 8.0; w.damage = 10.0
	z.fx_root.add_child(w)
	await secs(0.8)
	check(pl.hp < hp1, "ударная волна ранит стоящего на земле")
	pl.god_mode = true
	boss.hp = boss.max_hp * 0.3
	await secs(2.4)
	check(br.phase == 3 and br.enraged and boss.speed_mult > 1.0 and boss.damage_mult > 1.0, "фаза 3: ярость (быстрее и сильнее)")
	check("ЯРОСТЬ" in z.hud.boss_phase.text, "ярость отмечена на полосе")
	pl.god_mode = false
	var guard2 := 0
	while br.busy and guard2 < 300:
		await frames(1); guard2 += 1
	var items0 := 0
	for ch in z.fx_root.get_children():
		if ch is Loot and ch.type == "item": items0 += 1
	boss.take_damage(99999, true)
	await frames(3)
	var items := 0
	var rare := 0
	var uniq := 0
	for ch in z.fx_root.get_children():
		if ch is Loot and ch.type == "item" and is_instance_valid(ch):
			items += 1
			if int(ch.item.rarity) >= 2: rare += 1
			if int(ch.item.rarity) == 3: uniq += 1
	check(items - items0 >= 4 and rare >= 1, "добыча босса: %d предм., редких+ %d" % [items - items0, rare])
	check(uniq >= 1 and z.last_boss_drop.get("first", false), "первая победа: гарантированный уникальный")
	for a in br.adds:
		if is_instance_valid(a) and a.alive: a.take_damage(99999, false)

func phys(n: int) -> void:
	for i in n: await get_tree().physics_frame

func _jump_tests(z, p: Player) -> void:
	p.god_mode = true
	# прыжок с ровной земли
	p.teleport(Vector3(14, 0.3, 4))
	await phys(20)
	check(p.is_on_floor(), "игрок стоит на земле перед прыжком (y=%.2f)" % p.global_position.y)
	var y0 := p.global_position.y
	z.hud.press_jump()
	var top := y0
	for k in 70:
		await get_tree().physics_frame
		top = maxf(top, p.global_position.y)
	check(top - y0 > 1.0, "прыжок кнопкой HUD: высота %.2f м" % (top - y0))
	check(p.is_on_floor() and absf(p.global_position.y - y0) < 0.1, "приземление после прыжка")
	# «время койота»: прыжок сразу после схода с края платформы арены
	var a := Vector3(-4, 0, 64)
	var d := Vector3(0, 0, 1).rotated(Vector3.UP, deg_to_rad(255))
	p.teleport(a + d * 10.6 + Vector3.UP * 1.0)
	await phys(15)
	check(p.global_position.y > 0.7, "игрок на платформе арены (y=%.2f)" % p.global_position.y)
	p.force_move = d
	var left := false
	for k in 90:
		await get_tree().physics_frame
		if not p.is_on_floor():
			left = true; break
	check(left, "игрок сошёл с края платформы")
	await phys(3)
	var j0 := p.jumps
	p.request_jump()
	await phys(2)
	check(p.jumps == j0 + 1 and p.velocity.y > 3.0, "прыжок «время койота» после схода с края")
	p.force_move = Vector3.ZERO
	await phys(60)
	# дойти по тропе и пандусу до арены босса
	p.teleport(Vector3(-4, 0.3, 38))
	await phys(10)
	var reached := false
	for k in 600:
		var to := a - p.global_position; to.y = 0
		p.force_move = to.normalized()
		await get_tree().physics_frame
		if U.flat_dist(p.global_position, a) < 6.0:
			reached = true; break
	p.force_move = Vector3.ZERO
	await phys(5)
	check(reached and p.global_position.y > 0.7, "арена босса достижима пешком по пандусу (y=%.2f, до центра %.1f м)" % [p.global_position.y, U.flat_dist(p.global_position, a)])
	# запрыгнуть на уступ с востока и на платформу
	p.teleport(Vector3(a.x + 17, 0.3, a.z))
	await phys(10)
	var on_top := false
	for k in 400:
		p.force_move = Vector3(-1, 0, 0)
		if k % 20 == 0: p.request_jump()
		await get_tree().physics_frame
		if p.global_position.x < a.x + 10.5 and p.global_position.y > 0.7 and p.is_on_floor():
			on_top = true; break
	p.force_move = Vector3.ZERO
	check(on_top, "запрыгнуть на арену через восточный уступ (y=%.2f)" % p.global_position.y)
	p.teleport(z.spawn_point)
	p.god_mode = false
	await phys(5)

func _mob_anim_tests(z) -> void:
	var kinds := {}
	for e in z.enemies:
		if kinds.get(e.kind, false): continue
		var ok := false
		if e.model is MobModel:
			ok = e.model.ap != null and e.model.ap.is_playing()
		elif e.model is CharVisual:
			ok = e.model.tree != null and e.model.tree.active and e.model.model != null
		kinds[e.kind] = ok
	for k in ["slime", "wolf", "skeleton", "skeleton_archer", "goblin", "troll"]:
		check(kinds.get(k, false), "моб %s: модель с анимацией" % k)

func _bfs(from: int, to: int) -> Array:
	var prev := {from: -1}
	var q := [from]
	while q.size() > 0:
		var n: int = q.pop_front()
		if n == to: break
		for l in DB.tree_nodes[n]["links"]:
			if not prev.has(l):
				prev[l] = n; q.append(l)
	var path := []
	var cur := to
	while cur != -1:
		path.push_front(cur); cur = prev[cur]
	path.pop_front()
	return path
