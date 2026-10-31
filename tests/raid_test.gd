extends Node
## Групповые подземелья офлайн (соло, локальная RaidSim): вход, стражи коридора → решётка → бой с боссом,
## механики (по журналу симуляции), полное убийство босса, броски и комплектная добыча, выход в долину.
## godot --headless --path . res://tests/raid_test.tscn ++ --ignore-lock [--dungeon=ash|crypt|star] [--cls=warrior] [--lvl=12] [--god]
var is_runner := false
var errors := 0
var checks := 0
var args := {}

func check(c: bool, msg: String) -> void:
	checks += 1
	if c: print("  OK   ", msg)
	else: errors += 1; print("  FAIL ", msg)

func w(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _ready() -> void:
	if not is_runner:
		var r = load("res://tests/raid_test.gd").new(); r.is_runner = true
		get_tree().root.add_child.call_deferred(r); return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a: args[a.substr(2).get_slice("=", 0)] = a.get_slice("=", 1)
		elif a.begins_with("--"): args[a.substr(2)] = true
	_run.call_deferred()

const EXPECT := {"ash": ["meteors", "shield", "slab", "ring", "shield broken"], "crypt": ["song", "drops", "tide", "naiads", "whirlpool"],
	"lich": ["door0", "keeper", "door1", "sister", "door2", "colossus", "gate", "arrow", "ice", "wave", "phase2", "phyl", "phase3", "tomb", "dnd", "phase4"],
	"star": ["beam", "starfall", "split", "split done", "nova", "gravity"]}

func _run() -> void:
	Engine.time_scale = float(args.get("ts", "2.0"))
	var list: Array = RaidDefs.ORDER if not args.has("dungeon") else [args.dungeon]
	for did in list: await _dungeon(did)
	Engine.time_scale = 1.0
	print("=== RAID RESULT: %s (%d errors, %d checks) ===" % ["PASS" if errors == 0 else "FAIL", errors, checks])
	get_tree().quit(1 if errors > 0 else 0)

func _dungeon(did: String) -> void:
	var cls: String = args.get("cls", "warrior")
	var lvl := int(args.get("lvl", "12"))
	lvl = DB.dungeon_level(did, lvl)   # герой не ниже уровня подземелья
	print("--- %s (%s, ур. %d) ---" % [RaidDefs.DUNGEONS[did].name, cls, lvl])
	for f in Game.list_characters(): if str(f.get("name", "")) == "Рейдер": Game.delete_character(f["id"])
	var rng := RandomNumberGenerator.new(); rng.seed = 5
	var c := DB.new_character("Рейдер", cls, CharAssets.random_look(0, rng))
	c["level"] = lvl
	c["tutorial"] = {"move": true, "attack": true, "jump": true, "talents": true, "shop": true, "boss": true}
	c["potions"] = 20
	c["zone"] = RaidDefs.DUNGEONS[did].zone; c["has_pos"] = false
	DB.auto_build_skills(c)
	Game.save_character(c)
	Game.play(c); await w(2.5)
	var d = get_tree().current_scene
	check(d.has_method("is_raid") and d.is_raid() and d.raid != null and d.raid.sim != null, "[%s] вход: групповое подземелье, локальная симуляция" % did)
	if not (d.has_method("is_raid") and d.is_raid()): return
	var sim: RaidSim = d.raid.sim
	var p: Player = d.player
	if args.has("god"): p.god_mode = true
	var trash := 0
	for e in d.enemies: if e is NetEnemy and e.role == "trash": trash += 1
	if did == "lich": check(trash >= 8, "[%s] нежить Некрополя на клиенте: %d (NetEnemy)" % [did, trash])
	else: check(trash == 8, "[%s] стражи коридора на клиенте: %d (NetEnemy)" % [did, trash])
	if did == "lich":
		check(d.builder is LichNecropolisBuilder, "[lich] своя локация: LichNecropolisBuilder")
		check(d.builder.ldoor_closed == [true, true, true], "[lich] двери склепа закрыты до зачистки")
		check(sim.minis.size() == 3, "[lich] мини-боссы: %s" % str(sim.minis.keys()))
	check(d.builder.gate_is_closed, "[%s] решётка арены закрыта до зачистки" % did)
	var boss = d.builder.boss_enemy()
	check(boss != null and boss.brain is RaidBrain and absf(boss.max_hp - RaidDefs.boss_hp(sim.level, 1) * float(RaidDefs.DUNGEONS[did].get("hp_k", 1.0))) < 1.0, "[%s] босс «%s»: здоровье %d (соло-масштаб, ждём %d, мозг %s)" % [did, boss.def.name if boss else "?", boss.max_hp if boss else 0, RaidDefs.boss_hp(sim.level, 1) * float(RaidDefs.DUNGEONS[did].get("hp_k", 1.0)), boss.brain.get_script().resource_path if boss and boss.brain else "-"])
	var bot := RaidBot.new(d, 1, func(): return [])
	if args.has("skip_trash"):
		for id in sim.enemies.keys():
			if sim.enemies[id].alive and (sim.enemies[id].role == "trash" or (args.has("skip_keeper") and sim.enemies[id].kind == "rm_keeper") or (args.has("skip_sister") and sim.enemies[id].kind == "rm_sister") or (args.has("skip_col") and sim.enemies[id].kind == "rm_colossus")): sim._kill(sim.enemies[id])
	var t0 := Time.get_ticks_msec()
	var limit := float(args.get("limit", "900"))   # секунд игрового времени
	var game_t := 0.0
	var deaths := 0; var was_dead := false
	var eng_at := -1.0
	while game_t < limit and not sim.done:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		game_t += dt
		bot.step(dt)
		if p.dead and not was_dead: deaths += 1
		was_dead = p.dead
		if sim.engaged and eng_at < 0: eng_at = game_t
		if args.has("trace") and int(game_t * 2) != int((game_t - dt) * 2):
			var sp = sim.players[1]
			print("      TR t=%.1f sim=%s alive=%s in=%s cli=%s eng=%s" % [game_t, str(sp.pos), str(sp.alive), str(RaidDefs.in_arena(sp.pos, did)), str(p.global_position), str(sim.engaged)])
		if int(game_t * 10) % 300 == 0 and int((game_t - dt) * 10) % 300 != 0:
			var b = sim.enemies.get(sim.boss_id)
			print("    t=%.0f с: босс %.0f%% фаза %d, бой=%s, вайпов %d, смертей %d, урон героя %.0f" % [game_t, 100.0 * b.hp / b.mhp, sim.phase, str(sim.engaged), sim.wipes, deaths, sim.players[1].dealt])
			if did == "lich":
				var pp = d.player.global_position
				var al := []
				for o in sim.enemies.values():
					if o.alive and o.role != "boss": al.append("%s@%.0f,%.0f%s" % [o.role, o.pos.x, o.pos.z, (" hp%.0f%% yaw%.1f" % [100.0 * o.hp / o.mhp, o.yaw]) if o.role == "mini" else ""])
				print("      LOG ", sim.mlog.slice(maxi(0, sim.mlog.size() - 6)))
				print("      DBG me %.0f,%.0f reach=%d alive=%s doors=%s" % [pp.x, pp.z, bot._reach(), str(al), str(sim.doors)])
	var names := {}
	if did == "lich":
		for l in sim.mlog: names[str(l[1]).get_slice(" ", 0)] = true; names[str(l[1]).get_slice(" ", 1) if " " in str(l[1]) else str(l[1])] = true
	for l in sim.mlog: names[str(l[1]).get_slice(" ", 0) if not str(l[1]).begins_with("shield broken") and not str(l[1]).begins_with("split done") else str(l[1])] = true
	print("    журнал: ", sim.mlog.slice(0, 60) if did != "lich" else sim.mlog.filter(func(l): return not str(l[1]) in ["arrow", "ice zones", "keeper quake"]))
	print("    по герою: ударов %d, урон %.0f (%.1f× здоровья), смертельных %d, уклонений механик (кадров) %d" % [d.raid.stats.hurt, d.raid.stats.taken, d.raid.stats.taken / maxf(1.0, p.stats.max_hp), d.raid.stats.lethal, bot.mech_moves])
	print("    источники урона (доли здоровья): ", d.raid.stats.src)
	check(names.has("gate"), "[%s] стражи перебиты — решётка поднялась" % did)
	check(names.has("engage"), "[%s] бой с боссом начался" % did)
	for m in EXPECT[did]:
		check(names.has(m), "[%s] механика «%s» сработала" % [did, m])
	if did == "lich":
		var fight := game_t - eng_at
		check(eng_at > 0 and eng_at < 15.0 * 60.0, "[lich] зачистка до босса: %.1f мин (цель ≈10)" % (eng_at / 60.0))
		if sim.done: check(fight >= 20.0 * 60.0 * float(args.get("minf", "1.0")) and fight < 25.0 * 60.0, "[lich] бой с Кел'Тааром: %.1f мин (цель ≥20, бешенство в 25)" % (fight / 60.0))
		check(not sim.enraged, "[lich] бешенство не наступило")
		print("    укрытий от рывка (кадров): %d, за спиной Хранителя (кадров): %d, попыток прерывания: %d" % [bot.hides, bot.behind_frames, bot.interrupts_tried])
	if did == "crypt": check(sim.mlog.any(func(l): return str(l[1]).begins_with("interrupt")), "[%s] Песнь Бездны прервана умением" % did)
	check(sim.done, "[%s] босс убит за %.0f с боя (вайпов %d, смертей героя %d, урон %.0f, %.0f/с)" % [did, game_t - eng_at, sim.wipes, deaths, sim.players[1].dealt, sim.players[1].dealt / maxf(1.0, game_t)])
	if not sim.done: return
	await w(1.0)
	check(d.raid.stats.loot.size() == 1, "[%s] бросок добычи получен" % did)
	if d.raid.stats.loot.size() > 0:
		var ev: Dictionary = d.raid.stats.loot[0]
		var items := []
		for dr in ev.list: if str(dr.t) == "item": items.append(dr.it)
		var sets := 0
		for it in items: if str(it.get("set", "")) == RaidDefs.DUNGEONS[did].set: sets += 1
		check(sets >= 1, "[%s] добыча на земле: частей «%s»: %d, всего предметов %d" % [did, Items.SETS[RaidDefs.DUNGEONS[did].set].name, sets, items.size()])
		var req_ok := true
		for it in items: if int(it.get("req", 0)) > lvl: req_ok = false
		check(req_ok, "[%s] вся добыча надевается сразу (требование ≤ ур. героя)" % did)
	check(int(d.data.get("raid_kills", {}).get(did, 0)) == 1, "[%s] победа записана в героя" % did)
	check(d.builder.arena_exit != null, "[%s] портал выхода на арене" % did)
	# выход в долину через портал
	var ex: Vector3 = d.builder.arena_exit.global_position
	p.teleport(ex + Vector3(0, 0.1, -0.5))
	await w(2.5)
	var z2 = get_tree().current_scene
	check(z2 != d and z2.data["zone"] == "starter", "[%s] портал вернул в долину" % did)
	var inv_sets := 0
	for it in z2.data["inventory"]: if str(it.get("set", "")) == RaidDefs.DUNGEONS[did].set: inv_sets += 1
	check(inv_sets >= 1, "[%s] части комплекта в сумке после выхода: %d" % [did, inv_sets])
	print("    реальное время: %.0f с" % ((Time.get_ticks_msec() - t0) / 1000.0))
