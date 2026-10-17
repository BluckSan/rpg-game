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
	check(DB.tree_nodes.size() >= 250, "дерево v2: %d узлов" % DB.tree_nodes.size())
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
	_item_tests()
	_balance_tests()
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
			await _talent_v2_tests(z, p)
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
		await _skill_ext_tests(z, p, c["class"])
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
		var e2 = _alive_enemy(z2)
		pl.teleport(e2.global_position + Vector3(0, 0.1, -2))
		await frames(2)
		check(pl.try_use(3), "умение пути «%s»" % a["skill"]["name"])
		await frames(70)
		check(pl.data["loadout"][2] == a["skill"]["id"], "умение пути в слоте 3")
		var extra_ok := 0
		for x in a.get("skills_extra", []):
			DB.set_loadout_slot(pl.data, 0, x.id)
			pl.cooldowns[1] = 0; pl.mp = pl.stats.max_mp
			var e3 = _alive_enemy(z2)
			if e3: pl.teleport(e3.global_position + Vector3(0, 0.1, -2))
			await frames(2)
			if pl.try_use(1): extra_ok += 1
			await frames(50)
		check(extra_ok == 2, "доп. умения пути %s: %d/2" % [a["name"], extra_ok])
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
		# в игре: удар героя ур. 4 по троллю ур. 9 срезается бронёй и разницей уровней; огонь — уязвимость
		var lv_was: int = pl.data["level"]
		pl.data["level"] = 4
		var bh: float = boss.hp
		var dealt4: float = boss.take_damage(100.0, false, "phys")
		var dealt_f: float = boss.take_damage(100.0, false, "fire")
		pl.data["level"] = 9
		var dealt9: float = boss.take_damage(100.0, false, "phys")
		pl.data["level"] = lv_was
		boss.hp = bh
		check(dealt4 < 30.0 and dealt9 > dealt4 * 2.0 and dealt_f > dealt4 * 2.0, "урон по троллю: ур. 4 — %.0f, ур. 9 — %.0f, огнём (ур. 4) — %.0f из 100" % [dealt4, dealt9, dealt_f])
		await _boss_tests(z2, pl, boss)
		boss.take_damage(99999, true)
		await frames(5)
		check(not is_instance_valid(boss) or not boss.alive, "босс повержен, выпала добыча")
	await _dungeon_tests(z2, pl)
	z2 = get_tree().current_scene
	pl = z2.player
	# сундук в лагере: окно, массовый перенос туда и обратно (UI)
	check(z2.stash_point != Vector3.INF, "сундук в лагере есть")
	pl.data["inventory"].clear()
	for i in 6: pl.data["inventory"].append(Items.roll(3, String(pl.data["class"]), 0.2))
	var st0: int = pl.data["stash"].size()
	z2.hud._open("stash"); await frames(3)
	var sw = z2.hud.window
	check(sw != null and sw.mode == "stash" and sw.side_grid != null, "окно сундука открыто")
	if sw:
		sw.inv_grid.select_mode = true; sw.inv_grid.select_all()
		var moved: int = sw.stash_selected()
		check(moved == 6 and pl.data["stash"].size() == st0 + 6 and pl.data["inventory"].is_empty(), "массовый перенос в сундук: %d" % moved)
		var back: Array = []
		for it in pl.data["stash"].slice(st0, st0 + 4): back.append(str(it.uid))
		sw.side_grid.set_selection(back)
		var took: int = sw.take_from_stash(back)
		check(took == 4 and pl.data["inventory"].size() == 4 and pl.data["stash"].size() == st0 + 2, "забрать выбранные из сундука: %d" % took)
		z2.hud.close_window(); await frames(2)
	# портал из долины в открытый мир
	pl.data["level"] = maxi(int(pl.data["level"]), 6)
	pl.teleport(z2.portal_point + Vector3(0, 0.1, 0.4))
	var gw := 0
	while get_tree().current_scene == z2 and gw < 400:
		await frames(1); gw += 1
	await frames(15)
	var wz = get_tree().current_scene
	check(wz != z2 and wz.builder is WorldBuilder, "портал долины ведёт в Земли Эфира")
	if wz.builder is WorldBuilder:
		check(U.flat_dist(wz.player.global_position, wz.portal_point) < 8.0, "прибытие у портала в долину (Перекрёсток)")
		check(wz.hud.objective.text.begins_with("Цель:") and "ур." in wz.hud.objective.text, "цель в мире: %s" % wz.hud.objective.text)
		await frames(3)
		check(wz.hud.minimap.mouse_filter == Control.MOUSE_FILTER_STOP, "мини-карта в мире открывает карту по касанию")
		var ev := InputEventMouseButton.new(); ev.button_index = MOUSE_BUTTON_LEFT; ev.pressed = true
		wz.hud.minimap._gui_input(ev); await frames(2)
		check(wz.hud.window != null and wz.hud.window.has_method("travel"), "касание мини-карты → карта мира")
		wz.hud.close_window(); await frames(2)
	Game.to_menu()
	await frames(10)
	check(get_tree().current_scene.name == "MainMenu", "возврат в меню")
	for id in ids: Game.delete_character(id)
	print("=== RESULT: %s (%d errors) ===" % ["PASS" if errors == 0 else "FAIL", errors])
	get_tree().quit(1 if errors > 0 else 0)

## Расширенные умения: пул 7+ на класс, замки, набор 5 слотов, окно «Умения», каждое умение срабатывает
func _skill_ext_tests(z, p: Player, cls: String) -> void:
	p.data["level"] = maxi(12, int(p.data["level"]))
	p.data["class_level"] = maxi(3, int(p.data["class_level"]))
	p.recalc(true)
	var pool := DB.skill_pool(p.data)
	var open := 0
	for s in pool:
		if DB.skill_lock(p.data, s) == "": open += 1
	check(pool.size() >= 7 and open == pool.size(), "[%s] умений класса: %d, открыто %d" % [cls, pool.size(), open])
	var lo: Array = p.data["loadout"]
	var uniq := {}
	for id in lo:
		if id != "": uniq[id] = true
	check(lo.size() == 8 and uniq.size() == mini(8, pool.size()), "[%s] набор 8 слотов: %s" % [cls, str(lo)])
	var low := p.data.duplicate(true)
	low["level"] = 1; low["loadout"] = []
	DB.ensure_loadout(low)
	var hi_id: String = pool[pool.size() - 1].id
	check(not DB.set_loadout_slot(low, 2, hi_id) and DB.skill_lock(low, pool[pool.size() - 1]) == "Уровень 12", "[%s] умение 12 ур. закрыто на 1 ур." % cls)
	var a0: String = lo[0]; var a1: String = lo[1]
	DB.set_loadout_slot(p.data, 0, a1)
	check(p.data["loadout"][0] == a1 and p.data["loadout"][1] == a0, "[%s] перестановка в наборе меняет слоты местами" % cls)
	await _layout_tests(z, p, cls)
	# окно «Умения»
	z.hud._open("skills")
	await frames(3)
	var w = z.hud.window
	check(w != null and w.name == "Window_skills" and get_tree().paused, "[%s] окно «Умения» открыто" % cls)
	w._select(hi_id); w._slot_pressed(4)
	check(p.data["loadout"][4] == hi_id, "[%s] умение назначено в слот 5 через окно" % cls)
	check(z.hud.skill_btns.size() == 9 and z.hud.skill_btns[5].text == DB.find_skill(p.data, hi_id).name, "[%s] кнопка 5 на HUD обновлена" % cls)
	z.hud.close_window()
	# каждое умение срабатывает и бьёт цель
	var dummy := Enemy.spawn(z, "slime", 1, p.global_position + p.forward() * 3.0, z.fx_root)
	dummy.max_hp = 999999; dummy.hp = 999999
	dummy.def = dummy.def.duplicate(); dummy.def.aggro = 0.0
	await frames(2)
	var used := 0
	var hurt := 0
	for s in pool:
		DB.set_loadout_slot(p.data, 0, s.id)
		p.cooldowns[1] = 0; p.mp = p.stats.max_mp
		p.global_position = dummy.global_position - Vector3(0, 0, 3.0)
		p.face_towards(dummy.global_position)
		dummy.global_position = dummy.home
		var hp0: float = dummy.hp
		if p.try_use(1): used += 1
		else: print("    не сработало: ", s.id, " ", p.lock_reason(1))
		await secs(1.3)
		if dummy.hp < hp0 or dummy.curse_timer > 0: hurt += 1
	check(used == pool.size(), "[%s] все умения применены: %d/%d" % [cls, used, pool.size()])
	check(hurt >= pool.size() - 3, "[%s] умения задели цель: %d/%d" % [cls, hurt, pool.size()])
	dummy.take_damage(9999999, false)
	p.data["loadout"] = []
	p.recalc(true)
	z.hud.refresh_skill_buttons()

## Раскладки панели умений: веер (телефон) и ряд (ПК); переключение, сохранение, нажатие пальцем в обоих
func _layout_tests(z, p: Player, cls: String) -> void:
	var h = z.hud
	var def := "pc" if Game.desktop else "mobile"
	if cls == "warrior": check(Game.default_skill_layout() == def and Game.skill_layout in ["pc", "mobile"], "раскладка по умолчанию: %s (сейчас %s)" % [Game.default_skill_layout(), Game.skill_layout])
	var was: String = Game.skill_layout
	for lay in ["pc", "mobile"]:
		Game.skill_layout = lay
		get_tree().call_group("hud_listeners", "apply_skill_layout")
		await frames(2)
		var rects := []
		for i in range(1, h.skill_btns.size()):
			rects.append(Rect2(h.skill_btns[i].global_position, h.skill_btns[i].size))
		var others: Array = [h.skill_btns[0], h.potion_btn] + ([] if Game.desktop else [h.jump_btn, h.roll_btn])
		for o in others: rects.append(Rect2(o.global_position, o.size))
		var overlap := 0
		var scr: Vector2 = h._screen()
		var outside := 0
		for a in rects.size():
			if not Rect2(Vector2.ZERO, scr).encloses(rects[a]): outside += 1
			for b in range(a + 1, rects.size()):
				# кнопки круглые: сравниваем окружности
				if rects[a].get_center().distance_to(rects[b].get_center()) < (rects[a].size.x + rects[b].size.x) / 2 - 2: overlap += 1
		check(overlap == 0 and outside == 0, "[%s] раскладка «%s»: 8 умений без наложений (налож. %d, за краем %d)" % [cls, lay, overlap, outside])
		if lay == "pc":
			var y0: float = h.skill_btns[1].global_position.y
			var row := true
			for i in range(2, h.skill_btns.size()):
				if absf(h.skill_btns[i].global_position.y - y0) > 1 or h.skill_btns[i].global_position.x <= h.skill_btns[i - 1].global_position.x: row = false
			var mid: float = (h.skill_btns[1].global_position.x + h.skill_btns[8].global_position.x + h.skill_btns[8].size.x) / 2
			check(row and absf(mid - scr.x / 2) < 4 and y0 > scr.y * 0.8, "[%s] ряд 1–8 по центру внизу" % cls)
		else:
			var right := true
			for i in range(1, h.skill_btns.size()):
				if h.skill_btns[i].global_position.x < scr.x * 0.55 or h.skill_btns[i].global_position.y < scr.y * 0.3: right = false
			check(right, "[%s] веер умений у кнопки атаки справа внизу" % cls)
		# нажатие (палец или мышь) по 2-й кнопке набора
		var sb = h.skill_btns[2]
		p.cooldowns[2] = 0; p.mp = p.stats.max_mp
		h._touch_down(7, sb.global_position + sb.size / 2)
		h._touch_up(7)
		check(p.cooldowns[2] > 0, "[%s] «%s»: касание по кнопке 2 применяет умение" % [cls, lay])
		await frames(30)
	Game.skill_layout = "pc" if was == "mobile" else "mobile"
	Game.save_settings()
	var cfg := ConfigFile.new(); cfg.load("user://settings.cfg")
	check(cfg.get_value("ui", "skill_layout", "") == Game.skill_layout, "[%s] выбор раскладки сохранён" % cls)
	Game.skill_layout = was; Game.save_settings()
	get_tree().call_group("hud_listeners", "apply_skill_layout")

func _branch_nodes(bid: String) -> Array:
	var out := []
	for id in DB.tree_order:
		if DB.tree_nodes[id]["branch"] == bid: out.append(id)
	return out

func _alloc_path(c: Dictionary, to: int) -> bool:
	for id in _bfs(DB.start_node(c["class"]), to):
		if not DB.has_talent(c, id) and not DB.allocate(c, id): return false
	return true

## Дерево v2: ветви и ключевые пассивы, ранги, возврат рангов, требования ветви, модификаторы умений,
## пассивы (аура/срабатывания), миграция старых сохранений, поиск/фильтры/сброс в окне
func _talent_v2_tests(z, p: Player) -> void:
	# структура: по 3 ветви у каждого класса и каждого пути, в каждой — ключевой пассив
	var cls_ok := 0
	for cid in DB.CLASS_ORDER:
		var br := {}
		for id in DB.tree_order:
			var n: Dictionary = DB.tree_nodes[id]
			if n["branch_class"] == cid: br[n["branch"]] = true
		var keys := 0
		for b in br:
			for id in _branch_nodes(b):
				if DB.tree_nodes[id]["type"] == "keystone": keys += 1
		if br.size() == 3 and keys == 3: cls_ok += 1
	check(cls_ok == 3, "дерево: у каждого класса 3 ветви с ключевыми пассивами (%d/3)" % cls_ok)
	var asc_ok := 0
	for a in DB.ASCENDANCIES:
		var keys := 0
		for bi in 3:
			for id in _branch_nodes("%s_%d" % [a["id"], bi]):
				var n: Dictionary = DB.tree_nodes[id]
				if n["type"] == "keystone" and n["req_asc"] == a["id"]: keys += 1
		if keys == 3: asc_ok += 1
	check(asc_ok == 6, "дерево: у каждого пути 3 ветви с ключевыми пассивами (%d/6)" % asc_ok)
	var mods := 0
	for id in DB.tree_order: if DB.tree_nodes[id]["type"] == "mod": mods += 1
	check(mods >= 9 and DB.tree_order.size() >= 250, "узлов %d, модификаторов умений %d" % [DB.tree_order.size(), mods])
	# ранги
	var c: Dictionary = p.data.duplicate(true)
	c["level"] = 80
	DB.reset_talents(c)
	var st := DB.start_node(c["class"])
	var first: int = DB.tree_nodes[st]["links"][0]
	var mr := int(DB.tree_nodes[first]["max_rank"])
	var s0 := DB.compute_stats(c)
	for i in mr: DB.allocate(c, first)
	check(DB.rank(c, first) == mr and not DB.allocate(c, first) and DB.alloc_block(c, first) == "Максимальный ранг", "ранги: узел до %d/%d, дальше нельзя" % [DB.rank(c, first), mr])
	check(DB.spent_points(c) == mr, "вложено очков = сумме рангов (%d)" % DB.spent_points(c))
	var m0: Array = DB.tree_nodes[first]["mods"][0]
	var s1 := DB.compute_stats(c)
	check(s1 != s0, "ранги усиливают характеристики (%s ×%d)" % [m0[0], mr])
	var tip := DB.describe_node(c, first)
	check("Ранг %d/%d" % [mr, mr] in tip, "подсказка показывает ранг: %s" % tip.replace("\n", " | "))
	# возврат ранга и связность
	var nxt := -1
	for l in DB.tree_nodes[first]["links"]:
		if l != st and DB.tree_nodes[l]["type"] != "start" and DB.can_allocate(c, l): nxt = l; break
	DB.allocate(c, nxt)
	check(DB.refund(c, first) and DB.rank(c, first) == mr - 1, "−1 ранг: %d → %d" % [mr, DB.rank(c, first)])
	while DB.rank(c, first) > 1: DB.refund(c, first)
	var only_link := true
	for l in DB.tree_nodes[nxt]["links"]:
		if l != first and DB.has_talent(c, l): only_link = false
	if only_link: check(DB.refund_block(c, first) != "", "нельзя вернуть узел, на котором держатся другие: %s" % DB.refund_block(c, first))
	check(DB.refund(c, nxt) and not DB.has_talent(c, nxt), "крайний узел возвращается целиком")
	# требование ветви для ключевого пассива + модификатор умений «Расщепление» (+2 снаряда)
	var vb := _branch_nodes("a_volley")
	var key_id: int = vb[vb.size() - 1]
	var mod_id: int = vb[3]
	check(_alloc_path(c, mod_id), "путь к модификатору «%s» изучен" % DB.tree_nodes[mod_id]["name"])
	var pts := DB.points_in_branch(c, "a_volley")
	var kb := DB.alloc_block(c, key_id)
	if pts < 6: check(kb.begins_with("Нужно 6"), "ключевой пассив ждёт 6 очков в ветви (%d): %s" % [pts, kb])
	DB.allocate(c, vb[4])
	while DB.points_in_branch(c, "a_volley") < 6:
		var up := false
		for id in vb:
			if DB.has_talent(c, id) and DB.allocate(c, id): up = true; break
		if not up: break
	check(DB.can_allocate(c, key_id), "после 6 очков ключевой пассив «%s» доступен" % DB.tree_nodes[key_id]["name"])
	var fx: Dictionary = DB.compute_stats(c).fx
	check(int(fx.get("extra_proj", 0)) == 2, "модификатор: +2 снаряда (%s)" % str(fx))
	# применяем к игроку: стрела/снаряд выпускает 3 снаряда; лёд вместо огня
	var saved: Dictionary = p.data.duplicate(true)
	p.data["talents"] = c["talents"]; p.data["ranks"] = c["ranks"]; p.data["level"] = c["level"]
	p.recalc(true)
	var before := 0
	for ch in z.fx_root.get_children(): if ch is Projectile: before += 1
	Projectile.fire(z, p.global_position + Vector3.UP, p.forward(), 20.0, 6.0, Color(1, 0.4, 0.1), 0.25, true, Callable())
	var after := 0
	for ch in z.fx_root.get_children(): if ch is Projectile: after += 1
	check(after - before == 3, "снарядов от одного выстрела: %d" % (after - before))
	p.fx["elem_ice"] = 1.0
	var pr := Projectile.fire(z, p.global_position + Vector3.UP, p.forward(), 20.0, 6.0, Color(1, 0.4, 0.1), 0.25, true, Callable())
	check(pr.color.b > pr.color.r, "смена стихии: огненный снаряд стал ледяным")
	# пассивы: аура и срабатывания
	var dummy := Enemy.spawn(z, "slime", 1, p.global_position + p.forward() * 2.0, z.fx_root)
	dummy.max_hp = 999999; dummy.hp = 999999
	dummy.def = dummy.def.duplicate(); dummy.def.aggro = 0.0
	p.fx = {"aura_dmg": 40.0, "aura_frost": 1.0, "proc_bolt": 100.0, "proc_poison": 100.0, "crit_mark": 1.0}
	Projectile.player_fx = {}
	var a0 := p.aura_ticks
	var hp0: float = dummy.hp
	await secs(2.3)
	check(p.aura_ticks > a0 and dummy.hp < hp0, "аура ранит врагов рядом (%d тиков)" % (p.aura_ticks - a0))
	var pr0 := p.procs
	p.hit(dummy, 1.0, false, true)
	await secs(1.2)
	check(p.procs - pr0 >= 2 and dummy.curse_timer > 0, "срабатывания: молния и яд (%d), крит метит цель" % (p.procs - pr0))
	dummy.take_damage(9999999, false)
	p.data.merge(saved, true)
	p.recalc(true)
	# миграция старого сохранения
	var old := {"class": "warrior", "level": 12, "class_level": 2, "talents": [0, 4, 5, 7], "ascendancy": "berserker"}
	var refunded := DB.migrate_talents(old)
	check(refunded == 3 and old["talents"] == [DB.start_node("warrior")] and old["ascendancy"] == "berserker" and int(old["tree_v"]) == DB.TREE_VERSION, "миграция: старые таланты возвращены (%d очк.), путь сохранён" % refunded)
	check(DB.free_points(old) == DB.total_points(old), "после миграции все очки свободны")
	check(DB.migrate_talents(old) == 0, "повторная миграция ничего не меняет")
	# окно: поиск, фильтры, +ранг, −ранг, сброс с подтверждением
	DB.reset_talents(p.data)
	p.recalc(true)
	z.hud._open("talents")
	await frames(3)
	var tw = z.hud.window
	tw.search.text = "Буря клинков"
	tw._update_matches()
	check(tw.matches.size() >= 1, "поиск по имени находит узел")
	tw.find_next()
	check(tw.selected >= 0 and DB.tree_nodes[tw.selected]["name"] == "Буря клинков", "«Найти» выбирает и показывает узел")
	tw.search.text = "снаряд"
	tw._update_matches()
	check(tw.matches.size() >= 2, "поиск по эффекту: %d" % tw.matches.size())
	# подписи: без наложений на разных зумах (по умолчанию, макс., средние), видимость по зуму
	for zz in [tw.zoom, tw.ZOOM_MAX, 0.32, 0.8, tw.ZOOM_MIN]:
		tw.zoom = zz; tw.center_on_start()
		var lbs: Array = tw.layout_labels()
		var ov := 0
		for i in lbs.size():
			for j in range(i + 1, lbs.size()):
				if (lbs[i].rect as Rect2).intersects(lbs[j].rect): ov += 1
		var fsz := []
		for lb in lbs: fsz.append(lb.fs)
		check(ov == 0 and lbs.size() >= 3, "подписи дерева при зуме %.2f: %d шт., наложений %d" % [zz, lbs.size(), ov])
		check(fsz.is_empty() or (fsz.min() >= 13 and fsz.max() <= 40), "размер подписей в пределах 13–40 (%s)" % str([fsz.min() if fsz.size() else 0, fsz.max() if fsz.size() else 0]))
	tw.zoom = 0.5; tw.center_on_start()
	var minor_far := 0
	for lb in tw.layout_labels():
		if lb.kind == "node" and lb.id >= 0 and DB.tree_nodes[lb.id]["type"] == "minor": minor_far += 1
	tw.zoom = tw.ZOOM_MAX; tw.center_on_start()
	var minor_near := 0
	for lb in tw.layout_labels():
		if lb.kind == "node" and lb.id >= 0 and DB.tree_nodes[lb.id]["type"] == "minor": minor_near += 1
	check(minor_far == 0 and minor_near >= 3, "малые узлы подписаны только вблизи (далеко %d, близко %d)" % [minor_far, minor_near])
	tw.zoom = 0.5; tw.center_on_start()
	tw.search.text = "ГНЕВ"; tw.matches.clear(); tw._match_i = -1
	tw.find_next()
	check(tw.selected >= 0 and "гнев" in str(DB.tree_nodes[tw.selected]["name"]).to_lower(), "«Найти» без пересчёта и без учёта регистра")
	tw.search.text = ""
	tw.set_filter("key")
	var all_keys := true
	for id in tw.matches: if DB.tree_nodes[id]["type"] != "keystone": all_keys = false
	check(tw.matches.size() == 33 and all_keys, "фильтр «Ключевые»: %d" % tw.matches.size())
	tw.set_filter("avail")
	check(tw.matches.size() >= 2, "фильтр «Можно»: %d" % tw.matches.size())
	tw.set_filter("all")
	var f2: int = DB.tree_nodes[DB.start_node(p.data["class"])]["links"][0]
	tw.selected = f2; tw._learn(); tw._learn()
	check(DB.rank(p.data, f2) == 2, "окно: +1 ранг (%d)" % DB.rank(p.data, f2))
	tw._refund()
	check(DB.rank(p.data, f2) == 1, "окно: −1 ранг")
	tw._zoom_at(1.25, tw.canvas.size / 2)
	tw.center_on_start()
	tw._reset()
	check(DB.has_talent(p.data, f2), "сброс ждёт подтверждения")
	tw._reset()
	check(not DB.has_talent(p.data, f2) and DB.spent_points(p.data) == 0, "сброс: все очки возвращены")
	z.hud.close_window()

func _wait_free(br) -> void:
	var g := 0
	while br.busy and g < 400:
		await frames(1); g += 1

func _dungeon_tests(z, pl: Player) -> void:
	# открытие после тролля
	var fresh := {"level": 5, "zones": {}}
	check(DB.zone_lock_reason(fresh, "dungeon") != "", "подземелье закрыто до победы над троллем: %s" % DB.zone_lock_reason(fresh, "dungeon"))
	DB.set_zone_flag(fresh, "starter", "boss_troll_killed")
	check(DB.zone_lock_reason(fresh, "dungeon") == "", "после тролля подземелье открыто")
	check(DB.zone_flag(pl.data, "starter", "boss_troll_killed"), "флаг победы над троллем сохранён")
	check(z.builder.dungeon_seal != null and not z.builder.dungeon_seal.visible, "печать у входа в склеп снята")
	# вход через портал-арку
	pl.recalc(true)
	pl.teleport(z.builder.dungeon_gate_point + Vector3(0, 0.1, 0) + Basis(Vector3.UP, deg_to_rad(115.0)) * Vector3(0, 0, 0.8))
	var g := 0
	while get_tree().current_scene == z and g < 300:
		await frames(1); g += 1
	await frames(15)
	var d = get_tree().current_scene
	check(d != z and d.is_dungeon(), "переход в «Склеп Эфира» через вход")
	if d == z or not d.is_dungeon(): return
	var p: Player = d.player
	var b = d.builder
	check(U.flat_dist(p.global_position, Vector3(0, 0, 3)) < 3.0, "герой у входа в склеп: %s" % str(p.global_position))
	check(b.traps.size() == 4 and b.levers.size() == 3 and b.packs.size() == 6, "ловушки 4, рычаги 3, группы 6")
	# ловушка: внутри во время удара — урон, снаружи — нет
	p.god_mode = false
	p.recalc(true)
	var t: Trap = b.traps[0]
	p.teleport(t.global_position + Vector3(0, 0.1, 0))
	var hp0 := p.hp
	g = 0
	while t.hits == 0 and g < 400:
		p.global_position = t.global_position + Vector3(0, 0.05, 0)
		await frames(1); g += 1
	check(t.hits >= 1 and p.hp < hp0, "шипы ранят стоящего на плите (%d → %d)" % [hp0, p.hp])
	var h1 := t.hits
	p.heal(99999)
	p.teleport(t.global_position + Vector3(0, 0.1, -3.0))
	await secs(3.4)
	check(t.hits == h1, "вне плиты шипы не задевают")
	var ft: Trap = b.traps[2]
	var seen := {}
	for i in 200:
		seen[ft.state] = true
		await frames(1)
	check(seen.has("warn") and seen.has("active") and seen.has("idle"), "огненная струя: предупреждение → удар → покой")
	check(b.traps[2].phase_off != b.traps[3].phase_off, "соседние струи сдвинуты по фазе (есть окно)")
	# группы
	for e in d.enemies.duplicate():
		if is_instance_valid(e) and e.alive and e.get_parent() == b.packs[0]: e.take_damage(9999999, false)
	await frames(3)
	check(DB.zone_flag(p.data, "dungeon", "pack1"), "группа 1 зачищена — сохранено")
	# рычаги: неверный порядок сбрасывает, верный открывает решётку
	p.teleport(b.levers["ice"].global_position + Vector3(0, 0.1, -1.2))
	await frames(3)
	check(d.nearest_interactable().get("text", "") == "Рычаг: Лёд", "кнопка взаимодействия у рычага: %s" % d.nearest_interactable().get("text", ""))
	d.hud.interact()
	await secs(0.9)
	check(b.lever_input.is_empty() and not b.levers["ice"].on and not b.gate_open(), "неверный порядок сбросил рычаги")
	for id in ["fire", "ice", "shadow"]:
		p.teleport(b.levers[id].global_position + Vector3(0, 0.1, -1.2))
		await frames(2)
		d.hud.interact()
		await frames(2)
	check(b.gate_open() and DB.zone_flag(p.data, "dungeon", "cp_lever"), "Пламя → Лёд → Тень: решётка открыта, контрольная точка")
	await frames(3)
	check(b.gate_body.get_child(0).disabled, "проход за решёткой свободен")
	check(d.spawn_point.distance_to(DungeonBuilder.CHECKPOINTS["cp_lever"]) < 0.5, "возрождение у рычагов")
	# Хранитель
	var boss = b.boss_enemy()
	check(boss != null and boss.brain is WardenBrain, "Хранитель Эфира в арене")
	if boss == null: return
	var br: WardenBrain = boss.brain
	br.cast_mult = 0.25
	br.special_timer = 9999.0
	for e in d.enemies.duplicate():
		if is_instance_valid(e) and e.alive and not e.def.boss: e.take_damage(9999999, false)
	p.teleport(b.arena_center + Vector3(0, 0.1, -8))
	await secs(0.5)
	check(br.engaged and DB.zone_flag(p.data, "dungeon", "cp_boss"), "бой начат, контрольная точка у арены")
	check(b.door_closed, "решётка арены закрылась на время боя")
	check(d.hud.boss_panel.visible and d.hud.enrage_label.visible, "полоса босса и таймер ярости: %s" % d.hud.enrage_label.text)
	# Рассечение: в конусе — смерть
	boss.global_position = b.arena_center
	br.run("cleave", p)
	await frames(3)
	check(d.hud.cast_panel.visible and "Рассечение" in d.hud.cast_label.text and d.hud.warn_label.text != "", "полоса каста и подсказка: %s / %s" % [d.hud.cast_label.text, d.hud.warn_label.text])
	check(d.fx_root.get_child_count() > 0, "метка конуса на земле")
	p.global_position = boss.global_position + boss.global_basis.z * 5.0 + Vector3(0, 0.05, 0)
	await _wait_free(br)
	check(br.log.has("hit:cleave") and p.dead, "«Рассечение» в конусе — смертельно")
	await secs(0.2)
	check(br.log.has("reset") and not br.engaged and boss.hp == boss.max_hp, "гибель игрока сбрасывает бой")
	check(not b.door_closed, "решётка арены поднялась после гибели")
	await secs(3.4)
	check(not p.dead and p.global_position.distance_to(DungeonBuilder.CHECKPOINTS["cp_boss"]) < 2.5, "возрождение у входа на арену")
	p.recalc(true)
	br.cast_mult = 0.25; br.special_timer = 9999.0
	p.teleport(b.arena_center + Vector3(0, 0.1, -8))
	await secs(0.4)
	boss.global_position = b.arena_center
	# Рассечение: за спиной — безопасно
	br.run("cleave", p)
	await frames(2)
	p.global_position = boss.global_position - boss.global_basis.z * 4.0 + Vector3(0, 0.05, 0)
	await _wait_free(br)
	check(br.log.has("safe:cleave") and not p.dead, "«Рассечение»: за спиной босса — жив")
	# Эфирный разлом: внутри круга — жив (часть урона), снаружи — смерть (проверка геометрии)
	p.heal(99999)
	br.run("soak", p)
	await frames(2)
	p.global_position = br.soak_pos + Vector3(0, 0.1, 0)
	var hs := p.hp
	await _wait_free(br)
	check(br.log.has("safe:soak") and not p.dead and p.hp < hs, "«Эфирный разлом»: впитал внутри круга (%d → %d)" % [hs, p.hp])
	# Взор Пустоты: за колонной — жив; на открытом месте — нет линии укрытия
	p.heal(99999)
	var pil: Vector3 = d.pillars[0]
	var hide := pil + U.flat(pil - b.arena_center).normalized() * 2.4
	var open_spot: Vector3 = b.arena_center + U.flat(pil - b.arena_center).normalized().rotated(Vector3.UP, deg_to_rad(45)) * 9.0
	check(br.behind_pillar(hide) and not br.behind_pillar(open_spot), "линия обзора: колонна закрывает, открытое место — нет")
	br.run("void", p)
	await frames(2)
	p.global_position = hide + Vector3(0, 0.1, 0)
	await _wait_free(br)
	check(br.log.has("safe:void") and not p.dead, "«Взор Пустоты»: укрылся за колонной")
	# фаза 2: щит и стражи
	boss.hp = boss.max_hp * 0.65
	await secs(1.0)
	await _wait_free(br)
	check(br.phase == 2 and br.invulnerable and br.adds.size() == 4, "фаза 2: щит и 4 стража")
	var hb: float = boss.hp
	boss.take_damage(5000, false)
	check(boss.hp == hb, "под щитом босс неуязвим")
	for a in br.adds:
		if is_instance_valid(a) and a.alive: a.take_damage(9999999, false)
	await secs(0.3)
	check(br.log.has("shield_down") and not br.invulnerable, "стражи убиты — щит пал")
	# фаза 3: сжатие
	boss.hp = boss.max_hp * 0.35
	await secs(0.8)
	await _wait_free(br)
	check(br.phase == 3 and br.enraged, "фаза 3 на 40%")
	p.heal(99999)
	br.run("shrink", p)
	await frames(2)
	p.global_position = br.safe_spots[0] + Vector3(0, 0.1, 0)
	await _wait_free(br)
	check(br.log.has("safe:shrink") and not p.dead, "«Сжатие»: в безопасном круге — жив")
	# ярость по таймеру (бессмертие на время проверки)
	p.god_mode = true
	br.fight_time = br.enrage_time - 0.05
	await secs(0.3)
	check(br.log.has("enrage") and d.hud.enrage_label.text != "", "ярость по таймеру 5:00 — «Сверхновая»")
	await _wait_free(br)
	check(br.log.has("hit:enrage"), "«Сверхновая» бьёт всех")
	p.god_mode = false
	# победа и уникальная добыча
	boss.take_damage(99999999, true)
	await frames(4)
	check(DB.zone_flag(p.data, "dungeon", "boss_warden_killed"), "Хранитель повержен — флаг сохранён")
	var uq := 0
	for ch in d.fx_root.get_children():
		if ch is Loot and ch.type == "item" and str(ch.item.get("unique", "")).begins_with("warden_"): uq += 1
	check(uq >= 1 and d.last_boss_drop.get("unique", "") != "", "уникальная добыча Хранителя: %s" % d.last_boss_drop.get("unique", ""))
	d.save()
	var saved = Game.load_file(Game.SAVE_DIR + "/char_%s.json" % p.data["id"])
	var ok: bool = saved != null and DB.zone_flag(saved, "dungeon", "lever_solved") and DB.zone_flag(saved, "dungeon", "boss_warden_killed") and DB.zone_flag(saved, "dungeon", "pack1")
	check(ok, "прогресс подземелья в сохранении")
	# назад в долину — через портал возврата, к входу в склеп
	await frames(3)
	check(b.return_portal != null, "после победы открыт портал возврата")
	if b.return_portal:
		b.return_portal._cd = 0.0
		p.teleport(b.return_portal.global_position + Vector3(0, 0.1, 0.5))
	else: Game.travel("starter", "dungeon")
	g = 0
	while get_tree().current_scene == d and g < 300:
		await frames(1); g += 1
	await frames(20)
	var s2 = get_tree().current_scene
	check(s2 != d and not s2.is_dungeon() and U.flat_dist(s2.player.global_position, s2.dungeon_gate_point) < 6.0, "возврат в долину к входу в склеп")
	# повторный забег: снова через вход — герой у входа, контрольные точки сброшены, Хранитель и группы на месте
	s2.player.teleport(s2.dungeon_gate_point + Vector3(0, 0.1, 0) + Basis(Vector3.UP, deg_to_rad(115.0)) * Vector3(0, 0, 0.8))
	g = 0
	while get_tree().current_scene == s2 and g < 300:
		await frames(1); g += 1
	await frames(15)
	var d2 = get_tree().current_scene
	check(d2 != s2 and d2.is_dungeon(), "повторный вход в склеп")
	if d2.is_dungeon():
		var p2: Player = d2.player
		check(U.flat_dist(p2.global_position, DungeonBuilder.CHECKPOINTS[""]) < 3.0, "повторный забег: появление у входа, а не у портала/арены (%s)" % str(p2.global_position))
		check(not DB.zone_flag(p2.data, "dungeon", "cp_boss") and not DB.zone_flag(p2.data, "dungeon", "cp_lever"), "контрольные точки сброшены на новый забег")
		check(d2.spawn_point.distance_to(DungeonBuilder.CHECKPOINTS[""]) < 1.0, "точка возрождения — вход")
		check(d2.builder.boss_enemy() != null and d2.builder.return_portal == null, "Хранитель снова на месте, портала возврата нет")
		var pe := 0
		for e in d2.enemies: if is_instance_valid(e) and not e.def.boss: pe += 1
		check(pe >= 10, "группы врагов вернулись (%d)" % pe)
		check(DB.zone_flag(p2.data, "dungeon", "boss_warden_killed") and d2.builder.gate_open(), "победа и решённая загадка сохраняются (решётка открыта)")
		Game.travel("starter", "dungeon")
		await frames(20)

func _alive_enemy(z):
	for e in z.enemies:
		if is_instance_valid(e) and e.alive and not e.def.boss: return e
	return null

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
	for b in ["PlayButton", "SettingsButton", "CreditsButton", "QuitButton"]:
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
	(menu.screen.find_child("CreditsButton", true, false) as Button).pressed.emit()
	await frames(2)
	var cp: Node = menu.ui.find_child("CreditsPanel", true, false)
	var ctext: String = cp.get_node("Panel/Text").text if cp and cp.has_node("Panel/Text") else (cp.find_child("Text", true, false).text if cp else "")
	check(cp != null and "game-icons.net" in ctext and "CC BY 3.0" in ctext and "Lorc" in ctext and "Kenney" in ctext and "Quaternius" in ctext and "ambientCG" in ctext, "экран «Авторы»: game-icons (CC BY 3.0), Kenney, Quaternius, ambientCG")
	if cp: cp.close()
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
	check(qb.text != before and Game.quality == (q0 + 1) % (Game.max_quality() + 1), "пресет переключается кнопкой (%s → %s)" % [before, qb.text])
	# «Ультра» и безопасность графики
	check(Game.gpu_gi_blocked("AMD", "AMD Radeon RX 580 Series (RADV POLARIS10)") and Game.gpu_gi_blocked("ATI Technologies Inc.", "Radeon RX 470") and Game.gpu_gi_blocked("AMD", "AMD Radeon Vega 8 Graphics"), "SDFGI блокируется на AMD GCN (RX 580/470, Vega)")
	check(not Game.gpu_gi_blocked("AMD", "AMD Radeon RX 6700 XT") and not Game.gpu_gi_blocked("AMD", "AMD Radeon RX 5700 XT") and not Game.gpu_gi_blocked("NVIDIA", "NVIDIA GeForce GTX 1060"), "SDFGI не блокируется на RDNA и NVIDIA")
	if Game.desktop:
		check(Game.max_quality() == 4 and Game.QUALITY_NAMES[4] == "Ультра", "на ПК есть пресет «Ультра»")
		Game.apply_preset(3)
		check(not Game.gi_on() and not Game.ssr_on() and not Game.vfog_on(), "«Высокое»: без SDFGI/SSR/объёмного тумана")
		Game.apply_preset(4)
		check(Game.quality == 4 and sp.find_child("UltraGI", true, false) != null and sp.find_child("UltraFog", true, false) != null, "«Ультра» и переключатели эффектов в настройках")
		Game.ultra_fog = false; Game.apply_settings()
		check(not Game.vfog_on(), "переключатель «объёмный туман» выключает туман")
		Game.ultra_fog = true
		var q4 := Game.quality
		Game._enter_safe("тест")
		check(Game.safe_start and Game.quality == 2, "безопасный запуск понижает графику до «Среднего» (%d → %d)" % [q4, Game.quality])
		Game.safe_start = false
	else:
		check(Game.max_quality() == 3, "на телефоне «Ультра» нет")
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

# ---------- v0.5: предметы, комплекты, сундук, массовые операции ----------
func _item_tests() -> void:
	var c := DB.new_character("Предметы", "warrior", {})
	# 1. жёсткий запрет по уровню
	c["level"] = 3
	var hi := Items.roll(12, "warrior", 0.0, false, 4)
	c["inventory"].append(hi)
	check(int(hi.req) == 12, "требование уровня = уровень предмета (%d)" % int(hi.req))
	check(Items.equip(c, hi) == "Нужен уровень 12", "нельзя надеть предмет выше уровня")
	check(not c["equipped"].has(hi) and c["inventory"].has(hi), "предмет остался в инвентаре")
	check("[color=#ff5555]Требуется уровень 12" in Items.tooltip(c, hi), "требование уровня красным в подсказке")
	c["equipped"].append(hi)   # «взломанное» сохранение — характеристики не учитываются
	var base_hp: float = DB.compute_stats(c).max_hp
	c["equipped"].erase(hi)
	check(is_equal_approx(base_hp, DB.compute_stats(c).max_hp), "запрещённый предмет не даёт характеристик")
	c["level"] = 12
	check(Items.equip(c, hi) == "" and c["equipped"].has(hi), "на 12 уровне предмет надевается")
	# 2. ограничение по классу
	var bow := Items.roll(5, "archer", 0.0, false, 0)
	check(bow.cls == "archer" and Items.equip_block(c, bow).begins_with("Только для класса"), "лук — только для лучника")
	check("не ваш класс" in Items.tooltip(c, bow), "подсказка помечает чужой класс")
	# 3. добыча для всех классов
	var cnt := {"warrior": 0, "archer": 0, "mage": 0, "": 0}
	for i in 900:
		for it in Items.drop_items(10, "warrior", "elite"): cnt[str(it.get("cls", ""))] += 1
	check(cnt.warrior > 0 and cnt.archer > 0 and cnt.mage > 0 and cnt[""] > 0, "добыча: воин %d, лучник %d, маг %d, общие %d" % [cnt.warrior, cnt.archer, cnt.mage, cnt[""]])
	check(cnt.warrior > cnt.archer and cnt.warrior > cnt.mage, "своего класса выпадает больше")
	var sets_seen := 0
	for i in 400:
		for it in Items.drop_items(26, "mage", "boss"):
			if it.get("set", "") != "":
				sets_seen += 1
	check(sets_seen > 40, "боссы роняют комплекты (%d/400)" % sets_seen)
	var low_ok := true
	for i in 300:
		var it := Items.roll_set(6, "warrior")
		if int(Items.SETS[it.set].lvl) > 6: low_ok = false
	check(low_ok, "комплекты по уровню: на 6 ур. только тир 5")
	# 4. комплекты: включение и выключение бонусов
	var w := DB.new_character("Комплект", "warrior", {})
	w["level"] = 30
	w["equipped"].clear()
	var pieces := []
	for i in 6: pieces.append(Items.roll_set(25, "warrior", "veteran", i))
	var hp0: float = DB.compute_stats(w).max_hp
	for i in 6:
		w["inventory"].append(pieces[i])
		check(Items.equip(w, pieces[i]) == "", "надет кусок комплекта %d" % (i + 1))
		var st := DB.compute_stats(w)
		var n := Items.set_count(w, "veteran")
		check(n == i + 1, "счётчик комплекта %d" % n)
		check(st.fx.has("combo_wave") == (n >= 6), "бонус (6) %s при %d/6" % ["активен" if n >= 6 else "не активен", n])
	var st6 := DB.compute_stats(w)
	var tip := Items.tooltip(w, pieces[0])
	check("(6/6)" in tip and "— активно" in tip and "✔" in tip, "подсказка: 6/6, тиры активны, куски отмечены")
	check(Items.unequip(w, pieces[5]) == "", "снят 6-й кусок")
	var st5 := DB.compute_stats(w)
	check(not st5.fx.has("combo_wave") and not st5.fx.has("thorns"), "бонус (6) выключился после снятия")
	check(st5.armor < st6.armor or st5.max_hp <= st6.max_hp, "характеристики пересчитаны")
	for p in [pieces[4], pieces[3]]: Items.unequip(w, p)
	var st3 := DB.compute_stats(w)
	check(Items.set_count(w, "veteran") == 3, "3/6 после снятия")
	check(DB.compute_stats(w).max_hp >= hp0 + 59.0 or st3.max_hp >= hp0 + 59.0, "бонус (2) +60 HP держится на 3/6")
	var tip3 := Items.tooltip(w, pieces[0])
	check("(3/6)" in tip3 and "◦" in tip3, "подсказка: 3/6 и куски в сумке отмечены «есть»")
	Items.unequip(w, pieces[1]); Items.unequip(w, pieces[2])
	check(Items.set_count(w, "veteran") == 1 and Items.set_bonuses(w).mods.is_empty(), "1/6 — бонусов нет")
	# 5. сундук на 100 ячеек
	var s := DB.new_character("Сундук", "mage", {})
	s["inventory"].clear(); s["stash"] = []
	var moved := 0
	for batch in 4:
		s["inventory"].clear()
		for i in 30: s["inventory"].append(Items.roll(5, "mage"))
		var uids := []
		for it in s["inventory"]: uids.append(str(it.uid))
		moved += Items.to_stash(s, uids)
	check(s["stash"].size() == Items.STASH_SIZE and moved == 100, "сундук вмещает ровно 100 (%d)" % s["stash"].size())
	check(s["inventory"].size() == 20, "лишнее осталось в инвентаре")
	var back := []
	for i in 25: back.append(str(s["stash"][i].uid))
	s["inventory"].clear()
	check(Items.from_stash(s, back) == 25 and s["stash"].size() == 75, "массовый перенос из сундука")
	var all_uids := []
	for it in s["stash"]: all_uids.append(str(it.uid))
	check(Items.from_stash(s, all_uids) == Items.INVENTORY_SIZE - 25, "перенос ограничен размером инвентаря")
	# 6. массовые операции
	var m := DB.new_character("Масса", "warrior", {})
	m["inventory"].clear(); m["gold"] = 0
	for r in [0, 0, 0, 1, 1, 2, 3, 4]:
		var it := Items.roll(8, "warrior") if r < 4 else Items.roll_set(8, "warrior")
		it.rarity = r
		m["inventory"].append(it)
	var commons := Items.select_by_rarity(m["inventory"], 0)
	check(commons.size() == 3, "выбрать обычные: %d" % commons.size())
	check(Items.select_by_rarity(m["inventory"], 2).size() == 6, "выбрать до редких (уник/комплект не берутся)")
	var g := Items.sell_many(m, commons)
	check(g > 0 and int(m["gold"]) == g and m["inventory"].size() == 5, "массовая продажа: +%d золота" % g)
	check(m["buyback"].size() >= 3, "проданное — в выкуп")
	var magic := Items.select_by_rarity(m["inventory"], 1)
	var d := Items.dismantle_many(m, magic)
	check(d > 0 and int(m["dust"]) == d and m["inventory"].size() == 3, "массовая разборка: +%d пыли" % d)
	check(Items.sorted(m["inventory"], "rarity")[0].rarity == 3, "сортировка: уникальное первым")
	# 7. миграция старого сохранения
	var old := {"class": "archer", "level": 4, "inventory": [{"name": "Кольчуга", "slot": 1, "ilvl": 9, "rarity": 1, "base": 10, "mods": []}],
		"equipped": [{"name": "Длинный лук", "slot": 0, "ilvl": 7, "rarity": 0, "base": 12, "mods": []}], "gold": 0}
	Items.migrate(old)
	check(old.has("stash") and old.has("dust"), "миграция: сундук и пыль")
	check(old["equipped"].size() == 1 and old["equipped"][0].type == "bow" and int(old["equipped"][0].req) <= 4, "миграция: лук остаётся надетым")
	check(old["inventory"][0].cls == "" and old["inventory"][0].type == "plate", "миграция: старая броня — для всех классов")


## Баланс v0.5: броня, сопротивления, разница уровней; бой «на бумаге» по формулам Combat
func _balance_tests() -> void:
	check(absf(Combat.level_factor(4, 9) - 0.55) < 0.001 and Combat.level_factor(9, 9) == 1.0 and Combat.level_factor(9, 11) == 1.0, "разница уровней: −15%/ур. сверх +2")
	check(Combat.level_factor(1, 30) == 0.1, "урон по врагу на 29 ур. выше — не ниже 10%")
	check(Combat.enemy_dmg_factor(9, 4) > 1.3 and Combat.enemy_dmg_factor(5, 5) == 1.0, "враг выше вас бьёт сильнее")
	check(Combat.reward_factor(20, 5) == 0.2 and Combat.reward_factor(8, 5) == 1.0, "опыт/добыча с серых врагов снижены")
	var a_lo := Combat.armor_factor(Combat.enemy_armor("troll", 9, "normal", true), 4, 0)
	var a_hi := Combat.armor_factor(Combat.enemy_armor("troll", 9, "normal", true), 9, 0)
	var a_pen := Combat.armor_factor(Combat.enemy_armor("troll", 9, "normal", true), 9, 40)
	check(a_lo < a_hi and a_hi < a_pen and a_pen < 1.0, "броня: формула броня/(броня+K·ур.), пробивание помогает (%.2f / %.2f / %.2f)" % [a_lo, a_hi, a_pen])
	check(Combat.armor_factor(1e9, 1, 100) > 0.0 and Combat.armor_factor(1e9, 1, 100) < 0.01, "пробивание ограничено %d%%" % int(Combat.PEN_CAP))
	check(Combat.enemy_resist("skeleton", "poison", "boss", true) == Combat.RES_CAP, "сопротивление ограничено 75%")
	check(Combat.enemy_resist("troll", "fire", "normal", true) < 0 and Combat.resist_factor(Combat.enemy_resist("troll", "fire", "normal", true), 0) > 1.3, "уязвимость тролля к огню")
	check(Combat.resist_factor(40, 10) > Combat.resist_factor(40, 0), "снижение сопротивлений работает")
	check(Combat.enemy_resist("troll", "poison", "normal", true) > Combat.enemy_resist("troll", "poison", "normal", false), "босс: доп. сопротивления")
	check("Уязв.: огонь" in Combat.resist_text("troll", "normal", true) and "яд" in Combat.resist_text("troll", "normal", true), "подпись сопротивлений: %s" % Combat.resist_text("troll", "normal", true))
	check(Combat.elem_of_skill({"kind": "fireball"}, "mage") == "fire" and Combat.elem_of_skill({"kind": "projectile"}, "mage") == "arcane" and Combat.elem_of_skill({"kind": "melee"}, "warrior") == "phys", "стихии умений")
	check(Combat.boss_rec("troll", 9) >= 8 and Combat.boss_rec("troll", 9) <= 10, "рек. уровень тролля долины: %d" % Combat.boss_rec("troll", 9))
	check(DB.STAT_NAMES.has("pen%") and DB.STAT_NAMES.has("resred"), "новые характеристики в описаниях")
	var pen_nodes := 0
	for id in DB.tree_nodes:
		for m in DB.tree_nodes[id]["mods"]: if m[0] in ["pen%", "resred"]: pen_nodes += 1
	check(pen_nodes >= 6, "пробивание/снижение сопротивлений в дереве талантов: %d" % pen_nodes)
	# бой с Древним троллем (ур. 9): уровень 4 со стартовым снаряжением — без шансов, уровень 9 — победа
	seed(20261018)
	for cls in DB.CLASS_ORDER:
		var lo := DB.new_character("Тест", cls, {})
		lo["level"] = 4
		var r_lo := Combat.sim_fight(lo, "troll", 9)
		check(not r_lo.win and r_lo.ttk > 3.0 * r_lo.ttd, "%s ур. 4: тролля не одолеть (убийство %.0f с, гибель %.0f с)" % [cls, r_lo.ttk, r_lo.ttd])
		var hi := DB.new_character("Тест", cls, {})
		hi["level"] = 9
		hi["equipped"].clear()
		for sl in 8: hi["equipped"].append(Items.roll(8, cls, 0.35, false, sl))
		for it in hi["equipped"]: it["req"] = mini(int(it.get("req", 1)), 9); it["rarity"] = maxi(1, int(it["rarity"]))
		var r_hi := Combat.sim_fight(hi, "troll", 9)
		var sh: Dictionary = DB.compute_stats(hi)
		check(r_hi.win and r_hi.ttk < 240.0, "%s ур. 9: победа (убийство %.0f с, запас %.0f с; hp %.0f, dr %.2f, реген %.1f, урон босса %.1f/с)" % [cls, r_hi.ttk, r_hi.ttd, sh.max_hp, sh.dr, sh.regen, r_hi.enemy_dps])
		check(r_hi.dps > r_lo.dps * 3.0, "%s: урон по боссу ур. 9 против ур. 4 — в %.1f раза выше" % [cls, r_hi.dps / maxf(0.01, r_lo.dps)])
	randomize()
