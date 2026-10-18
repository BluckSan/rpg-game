extends Node
## v0.9.1: короткий онлайн-тест общих врагов и добычи (2 клиента, настоящий сервер).
##   godot --headless --path . res://tests/net_world_test.tscn ++ --user=wtest_a --lead   (бьёт врага)
##   godot --headless --path . res://tests/net_world_test.tscn ++ --user=wtest_b          (смотрит и подбирает)
## Синхронизация между процессами — файлы /tmp/wt_*.
var is_runner := false
var errors := 0
var checks := 0
var args := {}
var seen_drops := {}
var gone := {}

func check(ok: bool, msg: String) -> void:
	checks += 1
	print(("  OK   " if ok else "  FAIL ") + "[%s] " % args.get("user", "?") + msg)
	if not ok: errors += 1

func wait_until(cond: Callable, timeout: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < timeout * 1000.0:
		if cond.call(): return true
		await get_tree().create_timer(0.2).timeout
	return cond.call()

func _ready() -> void:
	if not is_runner:
		var r = load("res://tests/net_world_test.gd").new(); r.is_runner = true
		get_tree().root.add_child.call_deferred(r); return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a: args[a.substr(2).get_slice("=", 0)] = a.get_slice("=", 1)
		elif a.begins_with("--"): args[a.substr(2)] = true
	get_tree().create_timer(240.0, true, false, true).timeout.connect(func(): printerr("NET WORLD TIMEOUT"); _finish())
	_run.call_deferred()

func _zone():
	var z = get_tree().current_scene
	return z if z != null and "player" in z else null

func wfile(n: String, v: String) -> void:
	var f := FileAccess.open("/tmp/wt_" + n, FileAccess.WRITE); f.store_string(v); f.close()
func rfile(n: String) -> String:
	return FileAccess.get_file_as_string("/tmp/wt_" + n) if FileAccess.file_exists("/tmp/wt_" + n) else ""

func _process(_d: float) -> void:
	if not is_runner: return
	for did in Net.net_drops: seen_drops[did] = true
	for did in seen_drops: if not Net.net_drops.has(did): gone[did] = true
	var z = _zone()
	if z and z.player and is_instance_valid(z.player) and not z.player.stats.is_empty(): z.player.hp = z.player.stats.max_hp   # тест: герой не погибает

func _run() -> void:
	var user: String = args.get("user", "wtest_a")
	var lead := args.has("lead")
	var other := "wtest_b" if lead else "wtest_a"
	var pw := "raid-test-pass-8"
	var e := await Net.login(user, pw, true)
	if e.contains("занят"): e = await Net.login(user, pw, false)
	check(e == "" and Net.active, "вход «%s» %s" % [user, e])
	if not Net.active: _finish(); return
	var cn := "Рейд_" + user
	var c = null
	for ch in Net.chars: if str(ch.get("name", "")) == cn: c = ch
	if c == null:
		Game.save_character(DB.new_character(cn, "warrior" if lead else "mage", CharAssets.random_look(0, RandomNumberGenerator.new())))
		await wait_until(func(): return Net.chars.any(func(x): return str(x.get("name", "")) == cn), 15.0)
		for ch in Net.chars: if str(ch.get("name", "")) == cn: c = ch
	if c == null: check(false, "герой"); _finish(); return
	c["tutorial"] = {"move": true, "attack": true, "jump": true, "talents": true, "shop": true, "boss": true}
	c["zone"] = "starter"; c["has_pos"] = false
	Game.play(c)
	var ok := await wait_until(func(): return Net.in_game and _zone() != null and _zone().player != null, 40.0)
	check(ok, "в мире")
	if not ok: _finish(); return
	ok = await wait_until(func(): return Net.remotes.values().any(func(r): return str(r.name) == "Рейд_" + other and str(r.zone) == Net.zone_key()), 60.0)
	check(ok, "второй игрок в той же зоне")
	ok = await wait_until(func(): return Net.wm_nodes.size() > 0, 30.0)
	check(ok, "общие враги пришли с сервера: %d" % Net.wm_nodes.size())
	var z = _zone(); var p = z.player
	var gold0 := int(p.data.get("gold", 0)); var inv0: int = p.data["inventory"].size()
	var picks0 := Net.picks_ok
	var kills := 0
	for round in 6:
		var nid := 0
		if lead:
			var best := 1e9
			for id in Net.wm_nodes:
				var en = Net.wm_nodes[id]
				if is_instance_valid(en) and en.alive:
					var dd: float = en.global_position.distance_to(p.global_position)
					if dd < best: best = dd; nid = id
			wfile("target", "%d|%d" % [round, nid])
		else:
			await wait_until(func(): return rfile("target").begins_with("%d|" % round), 60.0)
			nid = int(rfile("target").get_slice("|", 1))
		var en = Net.wm_nodes.get(nid)
		if round == 0: check(en != null and is_instance_valid(en), "у обоих один и тот же враг #%d (%s)" % [nid, en.kind if en else "-"])
		if en == null or not is_instance_valid(en): break
		# оба героя встают рядом с врагом (короткий «телепорт» разрешён сервером)
		Net.notify_teleport(); await get_tree().create_timer(0.15).timeout
		p.global_position = en.global_position + Vector3(3.0 if lead else -3.0, 0.5, 0)
		await get_tree().create_timer(1.5).timeout
		if lead:
			var hp0: float = en.hp
			Net.wm_hit(nid, 5.0)
			await get_tree().create_timer(1.0).timeout
			wfile("hit", "%d" % round)
			while is_instance_valid(en) and Net.wm_nodes.has(nid):
				Net.wm_hit(nid, 55.0); await get_tree().create_timer(0.15).timeout
			if round == 0: check(hp0 > 0, "удар засчитан сервером")
		else:
			await wait_until(func(): return rfile("hit") == "%d" % round, 30.0)
			if round == 0: check(is_instance_valid(en) and en.hp < en.max_hp, "здоровье врага от чужого удара: %.0f / %.0f" % [en.hp if is_instance_valid(en) else 0.0, en.max_hp if is_instance_valid(en) else 0.0])
		ok = await wait_until(func(): return not Net.wm_nodes.has(nid), 30.0)
		if round == 0: check(ok, "смерть общего врага видна обоим")
		if ok: kills += 1
		await get_tree().create_timer(4.0).timeout   # подбор добычи (у кого быстрее — тому и досталась)
		wfile("seen_" + user, JSON.stringify(seen_drops.keys()))
		if seen_drops.size() >= 3 and round >= 1: break
	await get_tree().create_timer(3.0).timeout
	var picks := Net.picks_ok - picks0
	wfile("res_" + user, JSON.stringify({"seen": seen_drops.keys(), "picks": picks, "left": Net.net_drops.size()}))
	check(kills >= 1, "убито общих врагов: %d" % kills)
	check(seen_drops.size() > 0, "добыча на земле видна: %d предметов" % seen_drops.size())
	check(Net.net_drops.is_empty(), "вся добыча подобрана или исчезла (осталось %d)" % Net.net_drops.size())
	# повторный подбор уже взятого — сервер отказывает
	var before := Net.picks_ok
	for did in seen_drops: Net.pick_drop(did)
	await get_tree().create_timer(2.0).timeout
	check(Net.picks_ok == before, "повторный подбор уже взятой добычи отклонён")
	ok = await wait_until(func(): return rfile("res_" + other) != "", 40.0)
	if ok:
		var o: Dictionary = JSON.parse_string(rfile("res_" + other))
		var mine := {}; for d in seen_drops: mine[int(d)] = true
		var theirs := {}; for d in o.seen: theirs[int(d)] = true
		var common := 0; for d in mine: if theirs.has(d): common += 1
		check(common > 0 and common == mine.size(), "одни и те же предметы у обоих: общих %d, у меня %d, у другого %d" % [common, mine.size(), theirs.size()])
		check(picks + int(o.picks) == common, "каждый предмет достался ровно одному: я %d + другой %d = %d" % [picks, int(o.picks), common])
	print("    [%s] золото %d→%d, вещей %d→%d, подобрал %d" % [user, gold0, int(p.data.get("gold", 0)), inv0, p.data["inventory"].size(), picks])
	_finish()

func _finish() -> void:
	print("=== NET WORLD RESULT %s: %s (%d errors, %d checks) ===" % [args.get("user", "?"), "PASS" if errors == 0 else "FAIL", errors, checks])
	await get_tree().create_timer(3.0).timeout
	if Net.in_game: await Net.leave()
	get_tree().quit(1 if errors > 0 else 0)
