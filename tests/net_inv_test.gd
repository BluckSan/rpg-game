extends Node
## v0.9.4.1: регрессия «вещи»: переодевание и подбор добычи. Настоящий сервер (локально) + 2 клиента.
##   python3 tests/net_local/fake_internal.py 7791 &
##   RPG_INTERNAL_URL=http://127.0.0.1:7791 RPG_INTERNAL_KEY=x godot --headless --path . res://scenes/server.tscn ++ --server
##   godot --headless --path . res://tests/net_inv_test.tscn ++ --net-host=127.0.0.1 --user=it_a --lead [--touch]
##   godot --headless --path . res://tests/net_inv_test.tscn ++ --net-host=127.0.0.1 --user=it_b [--touch]
##   godot --headless --path . res://tests/net_inv_test.tscn ++ --server --unit   (проверки сервера без сети)
var is_runner := false
var errors := 0
var checks := 0
var args := {}
const FAKE := "/tmp/fake_internal/"
const SYNC := "/tmp/it_"

func check(ok: bool, msg: String) -> void:
	checks += 1
	print(("  OK   " if ok else "  FAIL ") + "[%s] " % args.get("user", "unit") + msg)
	if not ok: errors += 1

func wait_until(cond: Callable, timeout: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < timeout * 1000.0:
		if cond.call(): return true
		await get_tree().create_timer(0.1).timeout
	return cond.call()

func _ready() -> void:
	if not is_runner:
		var r = load("res://tests/net_inv_test.gd").new(); r.is_runner = true
		get_tree().root.add_child.call_deferred(r); return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a: args[a.substr(2).get_slice("=", 0)] = a.get_slice("=", 1)
		elif a.begins_with("--"): args[a.substr(2)] = true
	get_tree().create_timer(300.0, true, false, true).timeout.connect(func(): printerr("NET INV TIMEOUT"); errors += 1; _finish())
	if args.has("unit"): _unit.call_deferred()
	else: _run.call_deferred()

func wfile(n: String, v: String) -> void:
	var f := FileAccess.open(SYNC + n, FileAccess.WRITE); f.store_string(v); f.close()
func rfile(n: String) -> String:
	return FileAccess.get_file_as_string(SYNC + n) if FileAccess.file_exists(SYNC + n) else ""

func _zone():
	var z = get_tree().current_scene
	return z if z != null and "player" in z and "fx_root" in z else null

func _process(_d: float) -> void:
	if not is_runner: return
	var z = _zone()
	if z and z.player and is_instance_valid(z.player) and not z.player.stats.is_empty(): z.player.hp = z.player.stats.max_hp

# ---------------- проверки сервера без сети ----------------
func _unit() -> void:
	var p := {"zone": "pd_crypt", "iid": 7, "party": 3, "peer": 9, "pos": Vector3.ZERO, "hp": 1.0, "data": {"inventory": []}}
	var it := Items.roll(10, "warrior")
	var d := {"zk": "pd_crypt#7", "t": "item", "n": 1, "it": it, "pos": Vector3(2, 0, 0)}
	check(Net._pick_why(p, d, 7.0) == "", "добыча босса группового подземелья (ключ «pd_crypt#7») подбирается")
	check(Net._pick_why(p, d.merged({"zk": "pd_crypt#8"}, true), 7.0) == "zone", "чужой экземпляр того же подземелья — отказ")
	check(Net._pick_why(p, d.merged({"pos": Vector3(20, 0, 0)}, true), 7.0) == "far", "далеко — отказ «far» (с сообщением)")
	check(Net._pick_why(p, d.merged({"pos": Vector3(20, 0, 0)}, true), 45.0) == "", "сбор всей добычи при выходе — в пределах 45 м")
	var full := p.duplicate(true); for i in DB.INVENTORY_SIZE: full.data.inventory.append(Items.roll(10, "warrior"))
	check(Net._pick_why(full, d, 7.0) == "full", "полный инвентарь — отказ «full» (с сообщением)")
	check(Net._pick_why(full, d.merged({"t": "gold"}, true), 7.0) == "", "золото с полным инвентарём подбирается")
	var sp := {"zone": "dungeon", "party": 3, "peer": 9, "iid": 0, "pos": Vector3.ZERO, "hp": 1.0, "data": {"inventory": []}}
	check(Net._pick_why(sp, d.merged({"zk": "dungeon#3"}, true), 7.0) == "", "Склеп группы (dungeon#3)")
	var wp := {"zone": "starter", "party": 0, "peer": 9, "iid": 0, "pos": Vector3.ZERO, "hp": 1.0, "data": {"inventory": []}}
	check(Net._pick_why(wp, d.merged({"zk": "starter"}, true), 7.0) == "", "добыча в долине (в т.ч. босса мира)")
	check(Net._pick_why(wp.merged({"hp": 0.0}, true), d.merged({"zk": "starter"}, true), 7.0) == "dead", "павший не подбирает")
	# переодевание: быстрая смена вещей сохраняет все предметы (ни копий, ни потерь)
	var c := DB.new_character("Юнит", "warrior", {})
	c["level"] = 30; c = Game.normalize(c)
	var rings := []
	while rings.size() < 4:
		var r := Items.roll(20, "warrior", 0.0, true, 0)
		if Items.equip_block(c, r) == "": rings.append(r); c.inventory.append(r)
	var before := _uids(c)
	for i in 50: InvOps.apply(c, "equip", [str(rings[i % 4].uid)])
	check(_uids(c) == before, "50 переодеваний подряд: вещи те же, без копий и потерь")
	check((c.equipped as Array).filter(func(x): return int(x.slot) == 0).size() == 1, "в ячейке ровно один предмет")
	_finish()

func _uids(c: Dictionary) -> Array:
	var out := []
	for k in ["inventory", "equipped", "stash"]: for it in c.get(k, []): out.append(str(it.uid))
	out.sort(); return out

# ---------------- два клиента ----------------
func _run() -> void:
	var user: String = args.get("user", "it_a")
	var lead := args.has("lead")
	var other := "it_b" if lead else "it_a"
	var touch := args.has("touch")
	var c := DB.new_character("Тест_" + user, "warrior" if lead else "mage", CharAssets.random_look(0, RandomNumberGenerator.new()))
	c["id"] = user; c["level"] = 4
	c["tutorial"] = {"move": true, "attack": true, "jump": true, "talents": true, "shop": true, "boss": true}
	c["zone"] = "starter"; c["has_pos"] = false
	c = Game.normalize(c)
	var cands := []
	while cands.size() < 4:
		var r := Items.roll(3, c["class"], 0.0, true, 1)
		if Items.equip_block(c, r) == "": cands.append(r)
	c.inventory.append_array(cands)
	if not lead:   # второй — с полным инвентарём (проверка отказа)
		while c.inventory.size() < DB.INVENTORY_SIZE + 1:   # +1: первая смена надевает в пустую ячейку
			c.inventory.append(Items.roll(3, c["class"]))
	DirAccess.make_dir_recursive_absolute(FAKE)
	var f := FileAccess.open(FAKE + user + ".json", FileAccess.WRITE); f.store_string(JSON.stringify(c)); f.close()
	Net.token = "tok_" + user; Net.username = user; Net.active = true; Net.chars = [c]
	Game.play(c)
	var ok := await wait_until(func(): return Net.in_game and _zone() != null and _zone().player != null, 40.0)
	check(ok, "в мире (локальный сервер)")
	if not ok: _finish(); return
	var z = _zone(); var p = z.player
	if touch: Game.desktop = false
	# ---- 1. быстрое переодевание без ожидания ответов ----
	var d0: Dictionary = p.data
	var before := _uids(d0)
	Net.inv_flicker = 0
	var reverts := [0]
	var last := [""]
	var on_res := func(_op, _r):
		var cur = Items.get_equipped(Game.current, 1)
		if cur != null and str(cur.uid) != last[0]: reverts[0] += 1
	Net.inv_result.connect(on_res)
	for i in 24:
		var it = Items.find_uid(Game.current.inventory, str(cands[i % 4].uid))
		if it == null: it = Items.find_uid(Game.current.equipped, str(cands[i % 4].uid))
		last[0] = str(cands[i % 4].uid)
		Net.inv("equip", [last[0]])
		if i % 6 == 5: await get_tree().process_frame
	await wait_until(func(): return Net.inv_pending == 0, 10.0)
	Net.inv_result.disconnect(on_res)
	var cur = Items.get_equipped(Game.current, 1)
	check(cur != null and str(cur.uid) == last[0], "после 24 быстрых смен надета последняя выбранная вещь")
	check(reverts[0] == 0, "вещи не «прыгали» назад во время смены (откатов на экране: %d, подавлено: %d)" % [reverts[0], Net.inv_flicker])
	check(_uids(Game.current) == before, "ни копий, ни потерь: %d вещей до и после" % before.size())
	# ---- 2. перегрузка (больше 30 операций в секунду) — без рассинхрона ----
	for i in 45: Net.inv("equip", [str(cands[i % 4].uid)])
	await wait_until(func(): return Net.inv_pending == 0, 10.0)
	var mine := _uids(Game.current); var eq_mine := str(Items.get_equipped(Game.current, 1).uid)
	Net.inv("shop_sync"); await wait_until(func(): return Net.inv_pending == 0, 10.0)
	check(_uids(Game.current) == mine and str(Items.get_equipped(Game.current, 1).uid) == eq_mine, "45 смен за раз: у клиента то же, что на сервере")
	check(_uids(Game.current) == before, "и после перегрузки вещи целы")
	# ---- 3. подбор с земли ----
	Loot.auto_pick = false   # первый — притягиванием после второго, второй — вручную
	ok = await wait_until(func(): return Net.remotes.values().any(func(r): return str(r.name) == "Тест_" + other), 40.0)
	check(ok, "второй игрок рядом")
	ok = await wait_until(func(): return Net.wm_nodes.size() > 0, 30.0)
	check(ok, "общие враги с сервера")
	var picks0 := Net.picks_ok
	for round in 9:
		var nid := 0
		if lead:
			var best := 1e9
			for id in Net.wm_nodes:
				var en = Net.wm_nodes[id]
				if is_instance_valid(en) and en.alive and en.global_position.distance_to(p.global_position) < best:
					best = en.global_position.distance_to(p.global_position); nid = id
			var tp: Vector3 = Net.wm_nodes[nid].global_position if Net.wm_nodes.has(nid) else p.global_position
			wfile("target", "%d|%d|%f|%f|%f" % [round, nid, tp.x, tp.y, tp.z])
		else:
			await wait_until(func(): return rfile("target").begins_with("%d|" % round), 90.0)
			nid = int(rfile("target").get_slice("|", 1))
		var en = Net.wm_nodes.get(nid)
		var tf := rfile("target").split("|")
		var at := Vector3(float(tf[2]), float(tf[3]), float(tf[4]))
		Net.notify_teleport(); await get_tree().create_timer(0.15).timeout
		p.global_position = at + Vector3(10.0 if lead else -6.0, 0.5, 0)   # подальше: притягивание не достаёт
		await get_tree().create_timer(1.5).timeout
		if lead:
			while is_instance_valid(en) and Net.wm_nodes.has(nid):
				Net.wm_hit(nid, 55.0); await get_tree().create_timer(0.15).timeout
			wfile("dead", "%d" % round)
		else:
			await wait_until(func(): return rfile("dead") == "%d" % round, 40.0)
		await wait_until(func(): return Net.net_drops.size() > 0, 5.0)
		print("    [%s] раунд %d: враг #%d, добычи видно %d, до места %.1f м" % [user, round, nid, Net.net_drops.size(), U.flat_dist(p.global_position, at)])
		await get_tree().create_timer(0.5).timeout
		if not lead:
			await _manual_round(z, p, round, touch)
			wfile("bdone", "%d" % round)
		else:
			await wait_until(func(): return rfile("bdone") == "%d" % round, 60.0)
			Loot.auto_pick = true
			# первый: идёт к оставшейся добыче — притягивание собирает
			for l in z.get_tree().get_nodes_in_group("loot"):
				if is_instance_valid(l) and not l.is_queued_for_deletion():
					Net.notify_teleport(); await get_tree().create_timer(0.1).timeout
					p.global_position = l.global_position + Vector3(0.5, 0.3, 0); await get_tree().create_timer(0.8).timeout
			await get_tree().create_timer(2.0).timeout
			Loot.auto_pick = false
			wfile("adone", "%d" % round)
		if not lead: await wait_until(func(): return rfile("adone") == "%d" % round, 60.0)
	var picks := Net.picks_ok - picks0
	if not lead: check(full_tested, "проверен отказ при полном инвентаре (выпала вещь)")
	check(picks > 0, "подобрано: %d" % picks)
	await get_tree().create_timer(2.0).timeout
	mine = _uids(Game.current)
	Net.inv("shop_sync"); await wait_until(func(): return Net.inv_pending == 0, 10.0)
	check(_uids(Game.current) == mine, "после подбора вещи клиента совпадают с сервером (%d)" % mine.size())
	wfile("res_" + user, JSON.stringify({"picks": picks}))
	_finish()

## Второй игрок: полный инвентарь → понятный отказ, вещь остаётся на земле; затем освобождает место
## и подбирает кликом/касанием и клавишей «Взаимодействие»
func _manual_round(z, p, round: int, touch: bool) -> void:
	var items := []; var other := []
	for did in Net.net_drops:
		var l = Net.net_drops[did]
		if is_instance_valid(l): (items if l.type == "item" else other).append(l)
	print("    [b] раунд %d: на земле вещей %d, прочего %d" % [round, items.size(), other.size()])
	if not full_tested and not items.is_empty():
		full_tested = true
		var l = items[0]; var did: int = l.net_id
		var n0 := int(Net.pick_fails.get("full", 0))
		Net.notify_teleport(); await get_tree().create_timer(0.1).timeout
		p.global_position = l.global_position + Vector3(1.0, 0.3, 0); await get_tree().create_timer(0.4).timeout
		Net.pick_drop(did)   # минуя проверку клиента — сервер должен отказать сам
		await wait_until(func(): return int(Net.pick_fails.get("full", 0)) > n0, 5.0)
		check(int(Net.pick_fails.get("full", 0)) > n0, "полный инвентарь: сервер отказал с причиной")
		check(Net.net_drops.has(did) and is_instance_valid(Net.net_drops[did]), "вещь осталась на земле")
		var sold := []
		for i in 6: sold.append(str(Game.current.inventory[Game.current.inventory.size() - 1 - i].uid))
		Net.inv("sell", sold); await wait_until(func(): return Net.inv_pending == 0, 5.0)
	var methods := ["key", "touch" if touch else "click"]
	var k := 0
	for l in items + other:
		if not is_instance_valid(l) or l.is_queued_for_deletion(): continue
		var m: String = methods[k % 2]; k += 1
		Net.notify_teleport(); await get_tree().create_timer(0.1).timeout
		p.global_position = l.global_position + Vector3(1.6, 0.3, 0.6)
		await get_tree().create_timer(0.5).timeout
		if not is_instance_valid(l): continue
		var n0 := Net.picks_ok
		if m == "key":
			var ev := InputEventKey.new(); ev.keycode = KEY_E; ev.physical_keycode = KEY_E; ev.pressed = true
			Input.parse_input_event(ev); await get_tree().process_frame
			ev = ev.duplicate(); ev.pressed = false; Input.parse_input_event(ev)
		else:
			var cam: Camera3D = get_viewport().get_camera_3d()
			var sp := cam.unproject_position(l.global_position + Vector3.UP * 0.4)
			if m == "touch":
				var t := InputEventScreenTouch.new(); t.index = 0; t.position = sp; t.pressed = true
				Input.parse_input_event(t); await get_tree().create_timer(0.05).timeout
				t = t.duplicate(); t.pressed = false; Input.parse_input_event(t)
			else:
				var b := InputEventMouseButton.new(); b.button_index = MOUSE_BUTTON_LEFT; b.position = sp; b.pressed = true
				Input.parse_input_event(b); await get_tree().create_timer(0.05).timeout
				b = b.duplicate(); b.pressed = false; Input.parse_input_event(b)
		var got := await wait_until(func(): return Net.picks_ok > n0, 3.0)
		check(got, "подбор: %s (%s)" % [{"key": "клавиша E", "touch": "касание", "click": "клик мышью"}[m], l.type if is_instance_valid(l) else "?"])

var full_tested := false
func _finish() -> void:
	print("=== NET INV RESULT %s: %s (%d errors, %d checks) ===" % [args.get("user", "unit"), "PASS" if errors == 0 else "FAIL", errors, checks])
	await get_tree().create_timer(1.0).timeout
	if Net.in_game: await Net.leave()
	get_tree().quit(1 if errors > 0 else 0)
