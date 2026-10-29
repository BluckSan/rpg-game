extends Node
## v0.9.4: боссы локаций — HP ×4, фирменные приёмы с метками на земле, фазы, призыв, ярость по таймеру, сброс. Сервер (WorldSim), без сети.
var fails := 0
func check(c: bool, m: String) -> void:
	print(("  OK  " if c else "  FAIL ") + m)
	if not c: fails += 1

func _ready() -> void:
	Net.is_server = true
	await get_tree().process_frame
	var seen := {}
	for zid in ["starter", "global"]:
		var root := Node3D.new(); add_child(root)
		var nav := ServerNav.new(); nav.build(root, zid)
		Net.navs[zid] = nav
		for key in nav.spawners:
			var kind: String = nav.spawners[key].kind
			var def: Dictionary = DB.ENEMIES[kind]
			if not def.boss or kind == "warden" or def.get("raid", false) or seen.has(kind): continue
			seen[kind] = true
			_boss(zid, nav, key, kind)
	check(seen.size() >= 6, "боссов локаций проверено: %d %s" % [seen.size(), str(seen.keys())])
	for k in WorldSim.SIGNATURE: check(DB.ENEMIES.has(k), "фирменный приём у существующего босса %s" % k)
	print("=== WORLD BOSS RESULT: %s (%d fails) ===" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails else 0)

func _boss(zid: String, nav, key: String, kind: String) -> void:
	seed(99 + kind.length())
	var sim := WorldSim.new(zid, zid, nav)
	var sp = sim.ensure_spawner(key)
	var m = sim.mobs[sp.mobs[0]]
	var nm: String = DB.ENEMIES[kind].name
	var base_hp: float = float(DB.ENEMIES[kind].hp) * Combat.enemy_hp_mult(int(m.lvl))
	check(float(m.mhp) >= base_hp * WorldSim.WORLD_BOSS_HP_K * 0.99, "%s: HP ×%.0f (%.0f)" % [nm, WorldSim.WORLD_BOSS_HP_K, m.mhp])
	var lvl := int(m.lvl) + 2
	sim.set_player(1, m.pos + Vector3(3, 0, 0), 99999, lvl, "warrior", 99999)
	sim.set_player(2, m.pos + Vector3(-4, 0, 2), 99999, lvl, "mage", 99999)
	var kinds := {}; var warns := []; var tele := 0; var hurt := 0; var spawned := 0
	var steps := int(240.0 / WorldSim.TICK)
	var seen_ph := 1
	for i in steps:
		sim.tick(WorldSim.TICK)
		if i % int(1.0 / WorldSim.TICK) == 0 and m.alive and i * WorldSim.TICK < 200.0:
			# держим HP: каждые 60 с — следующая фаза
			var tgt: float = [1.0, 0.6, 0.3, 0.25][mini(3, int(i * WorldSim.TICK / 60.0))]
			if float(m.hp) / float(m.mhp) > tgt: sim.hit(1, m.nid, float(m.mhp) * 0.02)
		for e in sim.events:
			var ev: Dictionary = e[1]
			match ev.t:
				"atk": kinds[str(ev.get("a", ""))] = true
				"warn": warns.append(str(ev.s))
				"tele": tele += 1
				"hurt": hurt += 1
				"spawn": spawned += 1
		sim.events.clear()
		seen_ph = maxi(seen_ph, int(m.boss.get("ph", 1)))
	var sig: String = WorldSim.SIGNATURE.get(kind, "")
	check(sig != "" and kinds.has(sig), "%s: фирменный приём «%s» применён (приёмы: %s)" % [nm, sig, str(kinds.keys())])
	check(kinds.size() >= 4, "%s: разные приёмы, а не только погоня (%d)" % [nm, kinds.size()])
	check(tele >= 15 and hurt > 0, "%s: метки на земле %d, попаданий %d" % [nm, tele, hurt])
	check(seen_ph == 3 and spawned > 0, "%s: фазы до 3 (%d), призыв подмоги (%d)" % [nm, seen_ph, spawned])
	check(bool(m.boss.berserk) and float(m.boss.dmgm) >= 1.6, "%s: ярость после %.0f с боя" % [nm, WorldSim.WORLD_BOSS_ENRAGE])
	# сброс: все ушли — босс лечится и сбрасывает фазы/ярость
	sim.set_player(1, m.home + Vector3(90, 0, 0), 99999, lvl, "warrior", 99999)
	sim.set_player(2, m.home + Vector3(90, 0, 0), 99999, lvl, "mage", 99999)
	for i in int(60.0 / WorldSim.TICK): sim.tick(WorldSim.TICK)
	sim.events.clear()
	check(float(m.hp) >= float(m.mhp) and int(m.boss.ph) == 1 and not bool(m.boss.berserk), "%s: сброс после ухода (HP %.0f%%, фаза %d)" % [nm, 100.0 * m.hp / m.mhp, m.boss.ph])
