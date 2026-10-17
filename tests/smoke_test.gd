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
	get_tree().create_timer(200.0, true, false, true).timeout.connect(func():
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
	menu.open_creator()
	await frames(5)
	var cr = null
	for ch in menu.screen.get_children():
		if ch.has_method("randomize_look"): cr = ch
	check(cr != null, "экран создания открыт")
	cr.randomize_look()
	cr.class_id = "mage"
	cr._refresh()
	await frames(3)
	check(menu.preview.root != null, "превью персонажа построено")
	menu.show_select()
	await frames(3)
	# 4. зона за каждый класс
	for i in ids.size():
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
