extends Node
## v0.9.2: серверная симуляция врагов (без сети): навмеш, агр/угроза, атаки, поводок, механики Хранителя и тролля, время шага.
var fails := 0
func check(c: bool, m: String) -> void:
	print(("  OK  " if c else "  FAIL ") + m)
	if not c: fails += 1

func _ready() -> void:
	Net.is_server = true
	await get_tree().process_frame
	var mem0 := OS.get_static_memory_usage()
	for zid in ["starter", "dungeon", "global"]:
		var t0 := Time.get_ticks_msec()
		var root := Node3D.new(); add_child(root)
		var nav := ServerNav.new(); nav.build(root, zid)
		Net.navs[zid] = nav
		print("nav %s: %d логов, %d мс, ok=%s, память +%.1f МБ" % [zid, nav.spawners.size(), Time.get_ticks_msec() - t0, nav.ok, (OS.get_static_memory_usage() - mem0) / 1048576.0])
		check(nav.spawners.size() > 0, "%s: логова собраны на сервере" % zid)
	await get_tree().physics_frame
	await get_tree().physics_frame
	# --- обычный бой в долине ---
	var nav: ServerNav = Net.navs["starter"]
	var sim := WorldSim.new("starter", "starter", nav)
	var key: String = ""
	for k in nav.spawners: if not DB.ENEMIES[nav.spawners[k].kind].boss: key = k; break
	var sp = sim.ensure_spawner(key)
	var pos: Vector3 = sp.pos + Vector3(6, 0, 0)
	sim.set_player(1, pos, 500, 5, "warrior", 500)
	sim.set_player(2, pos + Vector3(2, 0, 0), 400, 5, "mage", 400)
	var hurt := {1: 0, 2: 0}; var atk := 0
	for i in 400:
		sim.tick(WorldSim.TICK)
		for e in sim.events:
			if e[1].t == "hurt": hurt[int(e[0])] += 1
			if e[1].t == "atk": atk += 1
		sim.events.clear()
		if i == 100:   # маг бьёт — угроза у мага, воин бьёт сильнее (×2) — враги обратно к воину
			for nid in sp.mobs: sim.hit(2, nid, 5.0)
		if i == 200:
			for nid in sp.mobs: sim.hit(1, nid, 5.0)
	check(atk > 0, "враги атакуют (атак %d)" % atk)
	check(hurt[1] + hurt[2] > 0, "урон по героям от сервера: %s" % str(hurt))
	var m0 = sim.mobs[sp.mobs[0]]
	check(m0.aggro and m0.threat.size() == 2, "таблица угрозы у врага: %s" % str(m0.threat))
	check(float(m0.threat[1]) > float(m0.threat[2]), "воин держит угрозу (×2)")
	# поводок: игрок убегает далеко
	sim.set_player(1, sp.pos + Vector3(80, 0, 0), 500, 5, "warrior", 500)
	sim.set_player(2, sp.pos + Vector3(80, 0, 0), 400, 5, "mage", 400)
	for i in 600: sim.tick(WorldSim.TICK)
	sim.events.clear()
	check(U.flat_dist(m0.pos, m0.home) < 7.0 and not m0.aggro and m0.threat.is_empty() and float(m0.hp) >= float(m0.mhp), "поводок: враг вернулся домой (%.1f м)" % U.flat_dist(m0.pos, m0.home))
	# отключение одного: бой продолжается по другому
	sim.set_player(1, sp.pos + Vector3(3, 0, 0), 500, 5, "warrior", 500)
	sim.set_player(2, sp.pos + Vector3(3, 0, 1), 400, 5, "mage", 400)
	for nid in sp.mobs: sim.hit(1, nid, 1.0); sim.hit(2, nid, 1.0)
	sim.remove_player(1)
	var h2 := 0
	for i in 200:
		sim.tick(WorldSim.TICK)
		for e in sim.events: if e[1].t == "hurt" and int(e[0]) == 2: h2 += 1
		sim.events.clear()
	check(h2 > 0 and not m0.threat.has(1), "после отключения игрока 1 враги бьют игрока 2 (%d)" % h2)
	# убийство и возрождение
	var killed := [0]
	sim.kills_cb = func(_s, _sp, _m): killed[0] += 1
	sp.subs[2] = true
	for nid in sp.mobs.duplicate(): sim.hit(2, nid, 99999.0)
	check(killed[0] == int(sp.n), "смерть врагов решает сервер (%d)" % killed[0])
	sim.set_player(2, sp.pos + Vector3(60, 0, 0), 400, 5, "mage", 400)
	for i in int((float(sp.respawn) + 2.0) / WorldSim.TICK): sim.tick(WorldSim.TICK)
	var alive := 0
	for nid in sp.mobs: if sim.mobs.has(nid) and sim.mobs[nid].alive: alive += 1
	check(alive == int(sp.n), "возрождение на сервере (%d/%d)" % [alive, int(sp.n)])
	# --- Хранитель (Склеп группой) ---
	var dn: ServerNav = Net.navs["dungeon"]
	var ds := WorldSim.new("dungeon#7", "dungeon", dn)
	var wk := ""
	for k in dn.spawners: if dn.spawners[k].kind == "warden": wk = k
	var wsp = ds.ensure_spawner(wk)
	var c: Vector3 = wsp.pos
	ds.set_player(1, c + Vector3(0, 0, 10), 900, 10, "warrior", 900)
	ds.set_player(2, c + Vector3(3, 0, 10), 700, 10, "mage", 700)
	var kinds := {}; var lethal := 0; var sts := 0
	var w = ds.mobs[wsp.mobs[0]]
	for i in int(70.0 / WorldSim.TICK):
		ds.tick(WorldSim.TICK)
		if i == 300: ds.hit(1, w.nid, float(w.mhp) * 0.35)   # → фаза 2: щит и стражи
		for e in ds.events:
			var ev: Dictionary = e[1]
			if ev.t == "st": sts += 1; if ev.cn != "": kinds[ev.cn] = true
			if ev.t == "hurt" and ev.l: lethal += 1
		ds.events.clear()
		ds.set_player(1, c + Vector3(0, 0, 10), 900, 10, "warrior", 900)
		ds.set_player(2, c + Vector3(3, 0, 10), 700, 10, "mage", 700)
	print("  касты Хранителя: ", kinds.keys(), " смертельных: ", lethal, " st: ", sts)
	check(w.boss.en and kinds.size() >= 3, "механики Хранителя на сервере (%d видов)" % kinds.size())
	check(int(w.boss.ph) == 2 and w.boss.inv and ds._alive_adds(w) == 4, "фаза 2: щит и 4 стража")
	# --- тролль долины ---
	var tk := ""
	for k in nav.spawners: if nav.spawners[k].kind == "troll": tk = k
	if tk != "":
		var ts := WorldSim.new("starter", "starter", nav)
		var tsp = ts.ensure_spawner(tk)
		ts.set_player(1, tsp.pos + Vector3(5, 0, 0), 2000, 10, "warrior", 2000)
		var tr = ts.mobs[tsp.mobs[0]]
		ts.hit(1, tr.nid, float(tr.mhp) * 0.5)
		var tk_ev := {}
		for i in int(40.0 / WorldSim.TICK):
			ts.tick(WorldSim.TICK)
			for e in ts.events: tk_ev[str(e[1].t) + ":" + str(e[1].get("a", e[1].get("k", "")))] = true
			ts.events.clear()
			ts.set_player(1, tsp.pos + Vector3(5, 0, 0), 2000, 10, "warrior", 2000)
		print("  тролль: ", tk_ev.keys())
		check(int(tr.boss.ph) == 2 and (tk_ev.has("wave:") or tk_ev.has("tele:line") or tk_ev.has("spawn:")), "тролль: фаза 2 и особые атаки")
	# --- нагрузка: 40 логов рядом с 8 игроками ---
	var gs := WorldSim.new("global", "global", Net.navs["global"])
	var keys: Array = Net.navs["global"].spawners.keys().slice(0, 40)
	var pid := 1
	for k in keys:
		var s = gs.ensure_spawner(k)
		if pid <= 8: gs.set_player(pid, s.pos + Vector3(4, 0, 0), 800, 20, "warrior", 800); pid += 1
	for i in 60: await get_tree().physics_frame   # участки навмеша пекутся в фоне
	var tt := Time.get_ticks_usec()
	for i in 200: gs.tick(WorldSim.TICK); gs.events.clear()
	var per := (Time.get_ticks_usec() - tt) / 200.0 / 1000.0
	print("  нагрузка: врагов %d, шаг %.3f мс (бюджет 50 мс), путей %d, участков навмеша %d" % [gs.mobs.size(), per, gs.stats.paths, Net.nav_stats.areas])
	check(per < 5.0, "шаг симуляции укладывается (%.2f мс)" % per)
	print("память всего +%.1f МБ" % ((OS.get_static_memory_usage() - mem0) / 1048576.0))
	print("WORLDSIM %s %d" % ["OK" if fails == 0 else "FAIL", fails])
	get_tree().quit(fails)
