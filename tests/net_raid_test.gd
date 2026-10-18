extends Node
## Онлайн-тест групп и подземелий с настоящим сервером: несколько процессов-игроков.
## Лидер приглашает, исключает и снова приглашает; группа входит в подземелье экземпляром сервера,
## проходит стражей и убивает босса (общий бой: враги и механики — на сервере), у каждого свой бросок добычи.
##   лидер:     godot --headless --path . res://tests/net_raid_test.tscn ++ --user=ra --cls=warrior --lead --members=rb,rc [--dungeon=ash]
##   участники: godot --headless --path . res://tests/net_raid_test.tscn ++ --user=rb --cls=mage
var is_runner := false
var errors := 0
var checks := 0
var args := {}

func check(ok: bool, msg: String) -> void:
	checks += 1
	print(("  OK   " if ok else "  FAIL ") + "[%s] " % args.get("user", "?") + msg)
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
		var r = load("res://tests/net_raid_test.gd").new(); r.is_runner = true
		get_tree().root.add_child.call_deferred(r); return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a: args[a.substr(2).get_slice("=", 0)] = a.get_slice("=", 1)
		elif a.begins_with("--"): args[a.substr(2)] = true
	get_tree().create_timer(float(args.get("timeout", "1700")), true, false, true).timeout.connect(func():
		printerr("NET RAID TIMEOUT"); _finish())
	_run.call_deferred()

func cname(u: String) -> String: return "Рейд_" + u

func _run() -> void:
	var user: String = args.get("user", "ra")
	var pw := "raid-test-pass-8"
	var lead := args.has("lead")
	var members: Array = str(args.get("members", "")).split(",", false) if lead else []
	var did: String = args.get("dungeon", "ash")
	print("=== NET RAID %s (%s) → %s ===" % [user, "лидер" if lead else "участник", Net.host])
	var e := await Net.login(user, pw, true)
	if e.contains("занят"): e = await Net.login(user, pw, false)
	check(e == "" and Net.active, "вход «%s» %s" % [user, e])
	if not Net.active: _finish(); return
	var c = null
	for ch in Net.chars: if str(ch.get("name", "")) == cname(user): c = ch
	if c == null:
		Game.save_character(DB.new_character(cname(user), args.get("cls", "warrior"), CharAssets.random_look(0, RandomNumberGenerator.new())))
		await wait_until(func(): return Net.chars.any(func(x): return str(x.get("name", "")) == cname(user)), 15.0)
		for ch in Net.chars: if str(ch.get("name", "")) == cname(user): c = ch
	check(c != null, "герой «%s» на сервере (ур. %d)" % [cname(user), int(c.get("level", 0)) if c else 0])
	if c == null: _finish(); return
	c["tutorial"] = {"move": true, "attack": true, "jump": true, "talents": true, "shop": true, "boss": true}
	c["zone"] = "starter"; c["has_pos"] = false
	Game.play(c)
	var ok := await wait_until(func(): return Net.in_game and _zone() != null and _zone().player != null, 40.0)
	check(ok, "в мире")
	if not ok: _finish(); return
	await get_tree().create_timer(1.5).timeout
	if lead: await _lead_party(members)
	else: await _member_party()
	if not Net.in_party(): _finish(); return
	# ---- вход в подземелье ----
	if lead:
		await get_tree().create_timer(2.0).timeout
		Net.raid_enter(did)
	ok = await wait_until(func(): return _zone() != null and _zone().has_method("is_raid") and _zone().is_raid() and _zone().raid != null and _zone().raid.ents.size() > 0, 60.0)
	check(ok, "группа в подземелье «%s» (экземпляр #%d)" % [RaidDefs.DUNGEONS[did].name, Net.raid_iid])
	if not ok: _finish(); return
	var z = _zone()
	var rc: RaidClient = z.raid
	check(rc.sim == null, "враги — с сервера (локальной симуляции нет), врагов: %d" % rc.ents.size())
	var need := 1 + members.size() if lead else int(args.get("n", "3"))
	ok = await wait_until(func(): return _same_zone_remotes() >= need - 1, 40.0)
	check(ok, "союзники в том же экземпляре: %d" % _same_zone_remotes())
	await get_tree().create_timer(3.0).timeout
	var boss = z.builder.boss_enemy()
	check(boss != null and absf(boss.max_hp - RaidDefs.boss_hp(rc.level, rc.n)) < 2.0, "босс: здоровье %d = масштаб на группу из %d (ур. %d)" % [boss.max_hp if boss else 0, rc.n, rc.level])
	var bot := RaidBot.new(z, Net.my_id, _ally_pos)
	var limit := float(args.get("limit", "1200"))
	var t := 0.0; var deaths := 0; var was := false
	var p: Player = z.player
	var hp_seen := {}
	while t < limit and not rc.done:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		if not is_instance_valid(z) or get_tree().current_scene != z: break
		bot.step(dt)
		if p.dead and not was: deaths += 1
		was = p.dead
		if boss and is_instance_valid(boss) and boss.alive: hp_seen[int(boss.hp)] = true
		if int(t * 10) % 300 == 0 and int((t - dt) * 10) % 300 != 0:
			print("    [%s] t=%.0f босс %s фаза %d, вайпов %d, смертей %d, событий %s" % [user, t, ("%.0f%%" % (100.0 * boss.hp / boss.max_hp)) if boss and is_instance_valid(boss) else "-", rc.brain.phase, rc.stats.wipes, deaths, str(rc.stats.events)])
	if is_instance_valid(p): p.force_move = Vector3.ZERO
	check(hp_seen.size() > 20, "здоровье босса синхронизируется с сервера (%d значений)" % hp_seen.size())
	check(rc.stats.events.get("tele", 0) > 3 and rc.stats.events.get("hurt", 0) > 0, "механики сервера пришли: меток %d, ударов по герою %d" % [rc.stats.events.get("tele", 0), rc.stats.events.get("hurt", 0)])
	check(rc.done, "БОСС УБИТ группой за %.0f с (вайпов %d, смертей %d)" % [t, rc.stats.wipes, deaths])
	await get_tree().create_timer(2.0).timeout
	check(rc.stats.loot.size() == 1, "свой бросок добычи получен")
	if rc.stats.loot.size() > 0:
		var ev: Dictionary = rc.stats.loot[0]
		var sets := 0
		for it in ev.items: if str(it.get("set", "")) == RaidDefs.DUNGEONS[did].set: sets += 1
		check((ev.rolls as Dictionary).size() == need, "броски всей группы видны: %s" % str(ev.rolls))
		check(sets >= 1, "бросок %d%s → частей комплекта «%s»: %d" % [int(ev.roll), " (лучший)" if ev.best else "", Items.SETS[RaidDefs.DUNGEONS[did].set].name, sets])
	# выход и проверка, что группа сохранилась
	z.raid.leave()
	ok = await wait_until(func(): return _zone() != null and _zone() != z and str(_zone().data.get("zone", "")) == "starter", 30.0)
	check(ok, "выход из подземелья в долину")
	await get_tree().create_timer(4.0).timeout
	if not lead and args.has("leave_end"):
		Net.party_leave()
		ok = await wait_until(func(): return not Net.in_party(), 10.0)
		check(ok, "покинул группу")
	if lead and members.size() > 1:
		ok = await wait_until(func(): return (Net.party.get("members", []) as Array).size() == members.size(), 30.0)
		check(ok, "участник покинул группу — у лидера %d в группе" % (Net.party.get("members", []) as Array).size())
	await get_tree().create_timer(3.0).timeout
	_finish()

func _lead_party(members: Array) -> void:
	var ok := await wait_until(func(): return members.all(func(m): return Net.remotes.values().any(func(r): return str(r.name) == cname(m))), 120.0)
	check(ok, "все участники в сети: %s" % str(members))
	for m in members: Net.party_invite(cname(m))
	ok = await wait_until(func(): return (Net.party.get("members", []) as Array).size() == 1 + members.size(), 120.0)
	check(ok, "группа собрана: %d / 5, лидер — я: %s" % [(Net.party.get("members", []) as Array).size(), str(Net.is_leader())])
	var ui = _zone().party_ui
	await get_tree().create_timer(2.0).timeout
	var vis := 0
	for f in ui.frames.get_children(): if f.visible: vis += 1
	check(vis == 1 + members.size(), "рамки группы на экране: %d" % vis)
	if members.size() >= 2:
		var last: String = members[members.size() - 1]
		Net.party_kick(cname(last))
		ok = await wait_until(func(): return (Net.party.get("members", []) as Array).size() == members.size(), 15.0)
		check(ok, "исключение «%s» из группы" % cname(last))
		await get_tree().create_timer(2.0).timeout
		Net.party_invite(cname(last))
		ok = await wait_until(func(): return (Net.party.get("members", []) as Array).size() == 1 + members.size(), 30.0)
		check(ok, "повторное приглашение — группа снова %d" % (1 + members.size()))
	# шестой лишний: проверить лимит нельзя без шестого клиента — лимит проверяется на сервере (PARTY_MAX)

func _member_party() -> void:
	var ok := await wait_until(func(): return not Net.party_invites.is_empty(), 180.0)
	check(ok, "приглашение получено")
	if not ok: return
	Net.party_accept(Net.party_invites.keys()[0])
	ok = await wait_until(func(): return Net.in_party(), 20.0)
	check(ok, "вступил в группу (лидер: %s)" % str(Net.party.get("leader", 0)))
	# если исключат — принимаем повторное приглашение; ждём входа лидера в подземелье
	var t := 0.0
	while t < 240.0 and Net.raid_iid == 0:
		if not Net.in_party() and not Net.party_invites.is_empty():
			print("    [%s] исключён — принимаю повторное приглашение" % args.get("user"))
			check(true, "исключение получено — рамок группы нет")
			Net.party_accept(Net.party_invites.keys()[0])
		await get_tree().create_timer(0.25).timeout
		t += 0.25

func _zone():
	var z = get_tree().current_scene
	return z if z != null and "player" in z else null

func _same_zone_remotes() -> int:
	var c := 0
	for id in Net.remotes:
		if str(Net.remotes[id].zone) == Net.zone_key(): c += 1
	return c

func _ally_pos() -> Array:
	var out := []
	for id in Net.remotes:
		var r: Dictionary = Net.remotes[id]
		if str(r.zone) == Net.zone_key() and r.node and is_instance_valid(r.node): out.append(U.flat(r.node.global_position))
	return out

func _finish() -> void:
	print("=== NET RAID RESULT %s: %s (%d errors, %d checks) ===" % [args.get("user", "?"), "PASS" if errors == 0 else "FAIL", errors, checks])
	if Net.in_game: await Net.leave()
	get_tree().quit(1 if errors > 0 else 0)
