extends Node
## Онлайн-тест с настоящим сервером: два процесса с разными логинами видят друг друга, чат, проверка скорости,
## сохранение героя на сервере. Запуск (оба одновременно):
##   godot --headless --path . res://tests/net_test.tscn ++ --user=a --other=b [--net-host=146.0.76.20]
var is_runner := false
var errors := 0

func check(ok: bool, msg: String) -> void:
	print(("  OK  " if ok else "  FAIL ") + msg)
	if not ok: errors += 1

func wait_until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call(): return true
		await get_tree().create_timer(0.25).timeout
		t += 0.25
	return cond.call()

func _ready() -> void:
	if not is_runner:
		var r = load("res://tests/net_test.gd").new(); r.is_runner = true
		get_tree().root.add_child.call_deferred(r); return
	var user := "t_%d" % (randi() % 100000); var other := ""; var pw := "test-pass-123"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--user="): user = a.substr(7)
		if a.begins_with("--other="): other = a.substr(8)
	get_tree().create_timer(240.0, true, false, true).timeout.connect(func():
		printerr("NET TIMEOUT"); get_tree().quit(2))
	print("=== NET TEST %s → %s ===" % [user, Net.host])
	# 1. аккаунт
	var e := await Net.login(user, pw, true)
	if e.contains("занят"): e = await Net.login(user, pw, false)
	check(e == "" and Net.active and Net.token != "", "вход/регистрация «%s» (%s)" % [user, e])
	var e2 := await Net.login(user, "wrong-password", false)
	check(e2 != "", "неверный пароль отклонён (%s)" % e2)
	e = await Net.login(user, pw, false)
	check(e == "", "повторный вход")
	# 2. герой на сервере
	if Net.chars.is_empty():
		Game.save_character(DB.new_character("Герой_" + user, "warrior", {}))
		await wait_until(func(): return not Net.chars.is_empty(), 15.0)
	check(not Net.chars.is_empty() and str(Net.chars[0]["id"]).begins_with("n"), "герой создан на сервере (%d)" % Net.chars.size())
	var cheat := DB.new_character("Читер", "warrior", {}); cheat["level"] = 60
	var before := Net.chars.size()
	await Net.create_char(cheat)
	check(Net.chars.size() == before, "герой 60 ур. при создании отклонён")
	var c: Dictionary = Net.chars[0]
	var kills0 := int(c.get("kills", 0))
	# 3. вход в мир
	Game.play(c)
	var ok := await wait_until(func(): return Net.in_game and get_tree().current_scene != null and "player" in get_tree().current_scene and get_tree().current_scene.player != null, 30.0)
	check(ok, "подключение к игровому серверу и загрузка зоны")
	if not ok: _finish(); return
	await get_tree().create_timer(2.0).timeout
	var z = get_tree().current_scene
	var p: Node3D = z.player
	# 4. второй игрок
	if other != "":
		ok = await wait_until(func(): return Net.remotes.values().any(func(r): return str(r.name) == "Герой_" + other), 60.0)
		check(ok, "виден другой игрок «Герой_%s» (всего удалённых %d)" % [other, Net.remotes.size()])
		ok = await wait_until(func(): return get_tree().get_nodes_in_group("remote_players").size() > 0, 10.0)
		check(ok, "модель другого игрока в сцене")
		# шаги — другой процесс должен увидеть смещение
		var rid = Net.remotes.keys()[0]
		var rp0: Vector3 = Net.remotes[rid].pos
		var start := p.global_position
		for i in 30:
			p.global_position = start + Vector3(0.15 * i, 0, 0)
			await get_tree().create_timer(0.1).timeout
		await get_tree().create_timer(2.5).timeout
		var rp1: Vector3 = Net.remotes[rid].pos
		check(rp0.distance_to(rp1) > 1.0, "позиция другого игрока обновляется (%.1f м)" % rp0.distance_to(rp1))
		Net.send_chat("привет от " + user)
		ok = await wait_until(func(): return Net.chat_log.any(func(m): return str(m[1]) == "привет от " + other), 20.0)
		check(ok, "чат: сообщение от «%s» получено" % other)
	# 5. проверка скорости: скачок на 300 м без рывка — сервер возвращает
	var home := p.global_position
	p.global_position = home + Vector3(300, 0, 0)
	ok = await wait_until(func(): return p.global_position.distance_to(home) < 30.0, 5.0)
	check(ok, "сервер вернул героя после скачка на 300 м (%.0f м)" % p.global_position.distance_to(home))
	# 6. сохранение на сервере
	Game.current["kills"] = kills0 + 1
	Game.save_character(Game.current)
	await get_tree().create_timer(1.0).timeout
	if other != "": await get_tree().create_timer(6.0).timeout   # дать второму процессу закончить проверки
	Game.to_menu()
	await get_tree().create_timer(3.0).timeout
	await Net.refresh_chars()
	var saved := 0
	for cc in Net.chars:
		if cc["id"] == c["id"]: saved = int(cc.get("kills", 0))
	check(saved == kills0 + 1, "сервер сохранил героя (убийств %d → %d)" % [kills0, saved])
	_finish()

func _finish() -> void:
	print("=== NET RESULT: %s (%d errors) ===" % ["PASS" if errors == 0 else "FAIL", errors])
	Net.go_offline()
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(errors)
