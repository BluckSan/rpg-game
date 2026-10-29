extends Node
## v0.9.3: онлайн-тест рынка (2 клиента, настоящий сервер) и защита от дублирования.
##   godot --headless --path . res://tests/net_market_test.tscn ++ --user=wtest_a --lead   (продавец)
##   godot --headless --path . res://tests/net_market_test.tscn ++ --user=wtest_b          (покупатель)
## A выставляет вещь за 1 золото; B дважды подряд жмёт «купить» — вещь приходит ровно одна; A пытается
## снять уже проданный лот и выставить ту же вещь повторно — отказ; A забирает выручку. Затем B продаёт
## вещь обратно (A получает её назад). Синхронизация — файлы /tmp/mt_*.
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
		var r = load("res://tests/net_market_test.gd").new(); r.is_runner = true
		get_tree().root.add_child.call_deferred(r); return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a: args[a.substr(2).get_slice("=", 0)] = a.get_slice("=", 1)
		elif a.begins_with("--"): args[a.substr(2)] = true
	get_tree().create_timer(200.0, true, false, true).timeout.connect(func(): printerr("MARKET TIMEOUT"); _finish())
	Net.market_result.connect(func(op, r): results.append([op, r]))
	_run.call_deferred()

func wfile(n: String, v: String) -> void:
	var f := FileAccess.open("/tmp/mt_" + n, FileAccess.WRITE); f.store_string(v); f.close()
func rfile(n: String) -> String:
	return FileAccess.get_file_as_string("/tmp/mt_" + n) if FileAccess.file_exists("/tmp/mt_" + n) else ""

## Отправить операцию и дождаться ответа
func mkt(op: String, a: Dictionary) -> Dictionary:
	var n := results.size()
	Net.market(op, a)
	await wait_until(func(): return results.size() > n, 20.0)
	return results[n][1] if results.size() > n else {"ok": false, "error": "нет ответа"}

func inv_count(uid: String) -> int:
	var n := 0
	for k in ["inventory", "equipped", "stash"]:
		for it in Game.current.get(k, []): if str(it.uid) == uid: n += 1
	return n

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
	if lead: await _seller()
	else: await _buyer()
	_finish()

func _seller() -> void:
	for f in ["listed", "bought", "back", "done"]: DirAccess.remove_absolute("/tmp/mt_" + f)
	var cd: Dictionary = Game.current
	if (cd.inventory as Array).is_empty():
		# нет вещи — купить самую дешёвую у торговца (золото с добычи прошлых тестов)
		var best = null
		for it in cd.get("shop", {}).get("stock", []):
			if best == null or DB.buy_price(it) < DB.buy_price(best): best = it
		if best != null and int(cd.gold) >= DB.buy_price(best) + 10:
			Net.inv("buy", [str(best.uid)])
			await get_tree().create_timer(1.5).timeout
	if (cd.inventory as Array).is_empty(): check(false, "у продавца есть вещь для продажи (золото %d)" % int(cd.gold)); wfile("listed", "-1"); return
	var it: Dictionary = cd.inventory[0]
	var uid := str(it.uid)
	var g0 := int(cd.gold)
	var r := await mkt("list", {"uid": "нет-такой", "price": 1})
	check(not r.get("ok", false), "чужую/несуществующую вещь выставить нельзя: %s" % r.get("error", ""))
	# две заявки подряд на одну вещь: пройти может только одна
	var n0 := results.size()
	Net.market("list", {"uid": uid, "price": 1})
	Net.market("list", {"uid": uid, "price": 1})
	await wait_until(func(): return results.size() >= n0 + 2, 20.0)
	var oks := 0; var lid := 0
	for k in range(n0, results.size()):
		if results[k][1].get("ok", false): oks += 1; lid = int(results[k][1].get("id", 0))
	check(oks == 1 and lid > 0, "двойное выставление одной вещи: прошла 1 заявка из 2 (лот %d)" % lid)
	await get_tree().create_timer(0.8).timeout
	check(inv_count(uid) == 0, "вещь ушла из инвентаря продавца")
	check(int(cd.gold) == g0 - Net.market_fee(1), "списана плата %d (золото %d → %d)" % [Net.market_fee(1), g0, int(cd.gold)])
	wfile("listed", "%d|%s" % [lid, uid])
	check(await wait_until(func(): return rfile("bought") != "", 90.0), "покупатель закончил")
	r = await mkt("cancel", {"id": lid})
	check(not r.get("ok", false), "проданный лот снять нельзя: %s" % r.get("error", ""))
	var g1 := int(cd.gold)
	r = await mkt("claim", {})
	check(r.get("ok", false) and int(r.get("gold", 0)) >= 1, "выручка забрана: +%d" % int(r.get("gold", 0)))
	await get_tree().create_timer(0.8).timeout
	check(int(cd.gold) >= g1 + 1, "золото продавца выросло (%d → %d)" % [g1, int(cd.gold)])
	r = await mkt("claim", {})
	check(not r.get("ok", false), "повторно забрать ту же выручку нельзя: %s" % r.get("error", ""))
	# вернуть вещь: B выставил её обратно
	check(await wait_until(func(): return rfile("back") != "", 90.0), "покупатель выставил вещь обратно")
	var back := int(rfile("back"))
	r = await mkt("buy", {"id": back})
	check(r.get("ok", false), "вещь выкуплена обратно %s" % r.get("error", ""))
	await get_tree().create_timer(0.8).timeout
	check(inv_count(uid) == 1, "у продавца ровно 1 экземпляр вещи")
	wfile("done", "1")

func _buyer() -> void:
	check(await wait_until(func(): return rfile("listed") != "", 90.0), "лот выставлен")
	var parts := rfile("listed").split("|")
	if int(parts[0]) <= 0: wfile("bought", "x"); return
	var lid := int(parts[0]); var uid := parts[1]
	var cd: Dictionary = Game.current
	var s := await mkt("search", {"filters": {}})
	check(s.get("ok", false) and (s.get("list", []) as Array).any(func(L): return int(L.get("id", 0)) == lid), "лот виден в поиске")
	var g0 := int(cd.gold)
	var n0 := results.size()
	Net.market("buy", {"id": lid}); Net.market("buy", {"id": lid})
	await wait_until(func(): return results.size() >= n0 + 2, 20.0)
	var oks := 0
	for k in range(n0, results.size()): if results[k][1].get("ok", false): oks += 1
	check(oks == 1, "двойная покупка: успешна ровно 1 из 2")
	await get_tree().create_timer(0.8).timeout
	check(inv_count(uid) == 1, "вещь пришла ровно одна")
	check(int(cd.gold) == g0 - 1, "списано 1 золото (%d → %d)" % [g0, int(cd.gold)])
	var r := await mkt("buy", {"id": lid})
	check(not r.get("ok", false), "повторная покупка проданного лота: отказ (%s)" % r.get("error", ""))
	wfile("bought", "1")
	await get_tree().create_timer(1.0).timeout
	r = await mkt("list", {"uid": uid, "price": 1})
	check(r.get("ok", false), "вещь выставлена обратно %s" % r.get("error", ""))
	wfile("back", str(int(r.get("id", 0))))
	check(await wait_until(func(): return rfile("done") != "", 90.0), "продавец выкупил")
	r = await mkt("claim", {})
	check(r.get("ok", false), "выручка за обратную продажу забрана")
	await get_tree().create_timer(0.8).timeout
	check(inv_count(uid) == 0, "у покупателя вещи больше нет (не размножилась)")

func _finish() -> void:
	print("=== NET MARKET RESULT %s: %s (%d errors, %d checks) ===" % [args.get("user", "?"), "PASS" if errors == 0 else "FAIL", errors, checks])
	await get_tree().create_timer(2.0).timeout
	if Net.in_game: await Net.leave()
	get_tree().quit(1 if errors > 0 else 0)
