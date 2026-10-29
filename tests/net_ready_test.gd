extends Node
## v0.9.3: онлайн-тест проверки готовности (2 клиента). A — лидер, B — участник.
## 1) B (не лидер) пытается открыть подземелье — запроса нет; 2) A начинает проверку, B отвечает «Не готов» —
## обоим «fail»; 3) A снова, B «Готов» — обоим «go» и вход (если уровень позволяет). Синхронизация — /tmp/rc_*.
var phases := []
var asks := []
var is_runner := false
var errors := 0
var checks := 0
var args := {}
var results := []

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
		var r = load("res://tests/net_ready_test.gd").new(); r.is_runner = true
		get_tree().root.add_child.call_deferred(r); return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a: args[a.substr(2).get_slice("=", 0)] = a.get_slice("=", 1)
		elif a.begins_with("--"): args[a.substr(2)] = true
	get_tree().create_timer(200.0, true, false, true).timeout.connect(func(): printerr("READY TIMEOUT"); _finish())
	Net.ready_check.connect(func(d, st, ph): phases.append(ph))
	Net.ready_ask.connect(func(d, l, s): asks.append(d))
	_run.call_deferred()

func wfile(n: String, v: String) -> void:
	var f := FileAccess.open("/tmp/rc_" + n, FileAccess.WRITE); f.store_string(v); f.close()
func rfile(n: String) -> String:
	return FileAccess.get_file_as_string("/tmp/rc_" + n) if FileAccess.file_exists("/tmp/rc_" + n) else ""

func _run() -> void:
	var user: String = args.get("user", "wtest_a")
	var lead := args.has("lead")
	var pw := "raid-test-pass-8"
	var e := await Net.login(user, pw, false)
	check(e == "" and Net.active, "вход «%s» %s" % [user, e])
	if not Net.active: _finish(); return
	var cn := "Рейд_" + user
	var c = null
	for ch in Net.chars: if str(ch.get("name", "")) == cn: c = ch
	if c == null: check(false, "герой %s есть (сначала net_world_test)" % cn); _finish(); return
	c["zone"] = "starter"; c["has_pos"] = false
	Game.play(c)
	var ok := await wait_until(func(): return Net.in_game and get_tree().current_scene != null and "player" in get_tree().current_scene and get_tree().current_scene.player != null, 40.0)
	check(ok, "в мире")
	if not ok: _finish(); return
	await get_tree().create_timer(1.5).timeout
	if lead: await _leader()
	else: await _member()
	_finish()

func _leader() -> void:
	for f in ["inparty", "r1", "r2", "done", "b1"]: DirAccess.remove_absolute("/tmp/rc_" + f)
	if Net.in_party(): Net.party_leave(); await get_tree().create_timer(1.0).timeout
	await wait_until(func(): return rfile("ready") != "", 60.0)
	Net.party_invite("Рейд_wtest_b")
	check(await wait_until(func(): return (Net.party.get("members", []) as Array).size() == 2, 20.0), "группа из 2")
	wfile("inparty", "1")
	await wait_until(func(): return rfile("b1") != "", 30.0)
	check(phases.is_empty(), "не лидер не может начать проверку")
	Net.c_raid_enter.rpc_id(1, "ash")
	check(await wait_until(func(): return phases.has("fail"), 20.0), "раунд 1: B отказался → отмена у лидера")
	check(not phases.has("go") and Net.raid_iid == 0, "раунд 1: никто не вошёл")
	wfile("r1", "1")
	await get_tree().create_timer(1.0).timeout
	Net.c_raid_enter.rpc_id(1, "ash")
	check(await wait_until(func(): return phases.has("go"), 20.0), "раунд 2: все готовы → вход")
	await wait_until(func(): return Net.raid_iid != 0, 8.0)
	print("  leader raid_iid=%d lvl=%d" % [Net.raid_iid, int(Game.current.get("level", 1))])
	if DB.dungeon_lock(Game.current, "ash") == "": check(Net.raid_iid != 0, "лидер в подземелье")
	wfile("r2", "1")
	await wait_until(func(): return rfile("done") != "", 30.0)
	if Net.raid_iid != 0: Net.raid_leave()
	Net.party_leave()

func _member() -> void:
	if Net.in_party(): Net.party_leave(); await get_tree().create_timer(1.0).timeout
	wfile("ready", "1")
	check(await wait_until(func(): return not Net.party_invites.is_empty(), 30.0), "приглашение получено")
	if Net.party_invites.is_empty(): return
	Net.party_accept(Net.party_invites.keys()[0])
	await wait_until(func(): return rfile("inparty") != "", 20.0)
	Net.c_raid_enter.rpc_id(1, "ash")   # не лидер
	await get_tree().create_timer(2.0).timeout
	check(asks.is_empty() and phases.is_empty(), "проверку начинает только лидер")
	wfile("b1", "1")
	check(await wait_until(func(): return asks.size() == 1, 20.0), "раунд 1: запрос готовности")
	var pui = null
	for n in get_tree().root.find_children("*", "PartyUI", true, false): pui = n
	if pui: check(pui.rc_win.visible and pui.rc_yes.visible, "окно проверки готовности показано")
	if pui: pui.rc_no.pressed.emit()
	else: Net.rc_answer(false)
	check(await wait_until(func(): return phases.has("fail"), 10.0), "раунд 1: отмена")
	check(await wait_until(func(): return asks.size() == 2, 20.0), "раунд 2: запрос готовности")
	if pui: pui.rc_yes.pressed.emit()
	else: Net.rc_answer(true)
	check(await wait_until(func(): return phases.has("go"), 10.0), "раунд 2: вход")
	if pui: check(not pui.rc_win.visible, "окно закрыто")
	await wait_until(func(): return rfile("r2") != "", 20.0)
	print("  member raid_iid=%d lvl=%d" % [Net.raid_iid, int(Game.current.get("level", 1))])
	if DB.dungeon_lock(Game.current, "ash") == "": check(Net.raid_iid != 0, "участник в подземелье")
	wfile("done", "1")
	if Net.raid_iid != 0: Net.raid_leave()
	Net.party_leave()

func _finish() -> void:
	print("=== NET READY RESULT %s: %s (%d errors, %d checks) ===" % [args.get("user", "?"), "PASS" if errors == 0 else "FAIL", errors, checks])
	await get_tree().create_timer(2.0).timeout
	if Net.in_game: await Net.leave()
	get_tree().quit(1 if errors > 0 else 0)
