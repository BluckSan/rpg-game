extends Node
## v0.9.2: Склеп и групповые подземелья — враги на месте, уровни, лимит прохождений, телепорт к началу.
## godot --headless --path . res://tests/dungeon_check.tscn
var is_runner := false
var errors := 0

func check(ok: bool, msg: String) -> void:
	if not ok: errors += 1
	print("  ", "OK  " if ok else "FAIL", " ", msg)

func w(sec: float) -> void:
	var t0 := Time.get_ticks_msec(); var n := 0
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0) or n < 3:
		await get_tree().process_frame; n += 1

func _ready() -> void:
	if not is_runner:
		var r = load("res://tests/dungeon_check.gd").new(); r.is_runner = true
		get_tree().root.add_child.call_deferred(r); return
	get_tree().create_timer(180.0, true, false, true).timeout.connect(func(): print("TIMEOUT"); get_tree().quit(2))
	for f in Game.list_characters(): Game.delete_character(f["id"])
	var rng := RandomNumberGenerator.new(); rng.seed = 5
	var c := DB.new_character("Склепер", "warrior", CharAssets.random_look(1, rng))
	# --- блок по уровню ---
	c["level"] = 3
	DB.set_zone_flag(c, "starter", "boss_troll_killed")
	check(DB.zone_lock_reason(c, "dungeon") != "", "ур. 3: в Склеп не пускает: " + DB.zone_lock_reason(c, "dungeon"))
	check(DB.dungeon_lock(c, "star") != "", "ур. 3: в Звёздное Святилище не пускает")
	c["level"] = 6
	check(DB.zone_lock_reason(c, "dungeon") == "", "ур. 6 (8−2): пускает")
	# --- офлайн: Склеп не пустой, враги на уровне подземелья ---
	c["level"] = 14
	Game.save_character(c)
	Game.play(c); await w(2.0)
	Game.travel("dungeon"); await w(3.0)
	var z = get_tree().current_scene
	check(z != null and z.data.zone == "dungeon", "офлайн: вошли в Склеп")
	var n := 0; var lv := []; var boss = null
	for e in z.enemies:
		if is_instance_valid(e) and e.alive:
			n += 1; lv.append(e.level)
			if e.kind == "warden": boss = e
	check(n >= 10 and boss != null, "офлайн: в Склепе %d врагов, Хранитель: %s" % [n, boss != null])
	check(boss != null and boss.level == 12, "ур. 14 → Склеп ур. 12 (потолок), Хранитель ур. %s; враги %s" % [boss.level if boss else -1, str(lv)])
	# --- офлайн: прохождение → начало долины, счётчик ---
	z.data["ret"] = {"zone": "starter", "pos": [-30.0, 0.1, 40.0]}
	boss.take_damage(1e9, false)
	await w(1.5)
	check(DB.dungeon_done(z.data, "dungeon") == 1, "победа засчитана: %d, осталось %d" % [DB.dungeon_done(z.data, "dungeon"), DB.dungeon_left(z.data, "dungeon")])
	var rp = z.builder.return_portal
	check(rp != null and rp.to_start, "портал после победы ведёт к началу")
	Game.travel_start("starter"); await w(3.0)
	z = get_tree().current_scene
	var sp: Vector3 = z.spawn_point
	check(z.data.zone == "starter" and U.flat_dist(z.player.global_position, sp) < 2.0, "после победы — в начале долины %s (не у входа)" % str(z.player.global_position))
	# --- лимит 5 ---
	var d = z.data.duplicate(true)
	for i in 4: DB.dungeon_complete(d, "dungeon")
	check(DB.dungeon_left(d, "dungeon") == 0 and DB.zone_lock_reason(d, "dungeon") != "", "5 прохождений — вход закрыт: " + DB.zone_lock_reason(d, "dungeon"))
	check(InvOps.KEYS.has("dng_done"), "счётчик прохождений — серверный (InvOps.KEYS)")
	# --- сервер: Склеп для группы ур. 8 и 12 ---
	Net.is_server = true
	for L in [8, 20]:
		var root := Node3D.new(); add_child(root)
		var nav := ServerNav.new(); nav.build(root, "dungeon")
		var sim := WorldSim.new("dungeon#1", "dungeon", nav)
		sim.lv_off = DB.dungeon_level("dungeon", L) - 10
		var cnt := 0; var bl := -1
		for k in nav.spawners:
			var s = sim.ensure_spawner(k)
			for nid in s.mobs:
				cnt += 1
				if sim.mobs[nid].kind == "warden": bl = int(sim.mobs[nid].lvl)
		check(cnt >= 10 and bl == DB.dungeon_level("dungeon", L), "сервер: группа ур. %d — врагов %d, Хранитель ур. %d, навмеш %s" % [L, cnt, bl, nav.ok])
		root.queue_free()
	Net.is_server = false
	print("DUNGEON CHECK: ", "OK" if errors == 0 else "%d FAIL" % errors)
	get_tree().quit(0 if errors == 0 else 1)
