extends Node
## Проходимость «Склепа Эфира»: навмеш по коллизиям уровня + агент, который сам идёт (и прыгает при застревании)
## от входа через ловушки, рычаги (через «Взаимодействовать»), решётку, на арену и обратно к порталу выхода.
## Для каждого класса. godot --headless --path . res://tests/dungeon_nav.tscn ++ --ignore-lock
var is_runner := false
var errors := 0
var checks := 0

func check(c: bool, msg: String) -> void:
	checks += 1
	if c: print("  OK   ", msg)
	else: errors += 1; print("  FAIL ", msg)

func w(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _ready() -> void:
	if not is_runner:
		var r = load("res://tests/dungeon_nav.gd").new(); r.is_runner = true
		get_tree().root.add_child.call_deferred(r); return
	_run.call_deferred()

## Навмеш самой игры (тот же, по которому ходят враги): ждём готовности
func bake(d) -> RID:
	var b = d.builder
	var g := 0
	while b._nav_baking and g < 600: await get_tree().physics_frame; g += 1
	g = 0
	while not b.nav_ready() and g < 600: await get_tree().physics_frame; g += 1
	for i in 3: await get_tree().physics_frame
	print("    навмеш: готов=%s, полигонов %d" % [str(b.nav_ready()), b._nav_region.navigation_mesh.get_polygon_count() if b._nav_region else 0])
	return b.nav_map()

func path_to(map: RID, from: Vector3, to: Vector3) -> PackedVector3Array:
	return NavigationServer3D.map_get_path(map, from, to, true)

func reachable(map: RID, from: Vector3, to: Vector3, tol := 1.2) -> bool:
	var pth := path_to(map, from, to)
	return pth.size() > 0 and U.flat_dist(pth[pth.size() - 1], to) < tol

## Идти к цели по навмешу. false — не дошёл (застрял/нет пути/время вышло)
func walk(d, map: RID, to: Vector3, stop := 0.6, label := "") -> bool:
	var p: Player = d.player
	var pth := path_to(map, p.global_position, to)
	if pth.size() == 0: print("    нет пути: ", label); return false
	var t_end := Time.get_ticks_msec() + int((U.flat_dist(p.global_position, to) / 3.0 + 12.0) * 1000.0 / Engine.time_scale)
	var i := 1
	var last := p.global_position; var last_t := Time.get_ticks_msec(); var stuck := 0
	while Time.get_ticks_msec() < t_end:
		if not is_instance_valid(p) or get_tree().current_scene != d: return true
		if U.flat_dist(p.global_position, to) <= stop: p.force_move = Vector3.ZERO; return true
		while i < pth.size() - 1 and U.flat_dist(p.global_position, pth[i]) < 0.45: i += 1
		var wp: Vector3 = pth[mini(i, pth.size() - 1)]
		var dir := U.flat(wp - p.global_position)
		p.force_move = dir.normalized() if dir.length() > 0.01 else Vector3.ZERO
		await get_tree().physics_frame
		if Time.get_ticks_msec() - last_t > int(1200 / Engine.time_scale):
			if U.flat_dist(p.global_position, last) < 0.3:
				stuck += 1; p.request_jump()
				pth = path_to(map, p.global_position, to); i = 1
				if stuck > 5: break
			last = p.global_position; last_t = Time.get_ticks_msec()
	p.force_move = Vector3.ZERO
	print("    застрял у ", p.global_position, " → ", label)
	return false

func _run() -> void:
	Engine.time_scale = 2.0
	var classes := ["warrior", "mage", "archer"]
	if "--one" in OS.get_cmdline_user_args(): classes = ["warrior"]
	for cls in classes:
		await _class_run(cls)
	Engine.time_scale = 1.0
	print("=== NAV RESULT: %s (%d errors, %d checks) ===" % ["PASS" if errors == 0 else "FAIL", errors, checks])
	get_tree().quit(1 if errors > 0 else 0)

## Враг внутри стены? Геометрия уровня + физический запрос капсулой поменьше
func _in_wall(d, e) -> bool:
	if d.builder.point_blocked(e.global_position, -0.15): return true
	var q := PhysicsShapeQueryParameters3D.new()
	var sp := SphereShape3D.new(); sp.radius = 0.12
	q.shape = sp; q.collision_mask = 1
	q.transform = Transform3D(Basis.IDENTITY, e.global_position + Vector3.UP * 1.0)
	return not d.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()

## Симуляция боя: герой за стенами/углами от групп, враги гонятся, получают отбрасывание в стены.
## Ни один враг не должен оказаться внутри стены; точки появления — не в стенах.
func _wall_fight(d) -> void:
	var p: Player = d.player
	var b = d.builder
	await bake(d)
	var bad_spawn := 0
	for e in d.enemies: if is_instance_valid(e) and _in_wall(d, e): bad_spawn += 1
	check(bad_spawn == 0 and d.enemies.size() >= 10, "враги: %d, появились внутри стен: %d" % [d.enemies.size(), bad_spawn])
	var spots := [Vector3(-7, 0.1, 14), Vector3(0, 0.1, 30), Vector3(10.5, 0.1, 62), Vector3(-10.5, 0.1, 42), Vector3(0, 0.1, 9)]
	var inside := 0; var samples := 0; var moved := 0; var max_hits := 0
	var start := {}
	for e in d.enemies: start[e] = e.global_position
	for sp in spots:
		p.teleport(sp)
		var t_end := Time.get_ticks_msec() + int(5000 / Engine.time_scale)
		var k := 0
		while Time.get_ticks_msec() < t_end:
			await get_tree().physics_frame
			k += 1
			for e in d.enemies:
				if not is_instance_valid(e) or not e.alive: continue
				if k % 20 == 0 and U.flat_dist(e.global_position, p.global_position) < 6.0:
					e.knockback(U.flat(e.global_position - p.global_position).normalized(), 14.0)
				samples += 1
				if _in_wall(d, e):
					inside += 1
					if inside <= 3: print("    в стене: ", e.kind, " ", e.global_position)
	for e in d.enemies:
		if is_instance_valid(e) and start.has(e) and U.flat_dist(e.global_position, start[e]) > 3.0: moved += 1
		if is_instance_valid(e): max_hits = maxi(max_hits, e.wall_hits)
	check(inside == 0, "бой у стен: враг внутри стены %d раз из %d проверок" % [inside, samples])
	check(moved >= 3 and max_hits > 0, "враги двигались (%d) и упирались в стены (до %d касаний), а не проходили сквозь" % [moved, max_hits])
	# враг за стеной идёт в обход по навмешу, а не упирается напрямую
	var e0 = null
	for e in d.enemies:
		if is_instance_valid(e) and e.alive and not e.def.ranged and not e.def.boss: e0 = e; break
	if e0:
		for e in d.enemies: if e != e0 and is_instance_valid(e): e.set_process(false)
		e0.global_position = Vector3(-9, 0, 50)
		e0.home = e0.global_position
		p.teleport(Vector3(-2, 0.1, 30))   # коридор шипов: путь только через проём z=40
		e0.def = e0.def.duplicate(); e0.def.aggro = 40.0
		var t_end := Time.get_ticks_msec() + int(9000 / Engine.time_scale)
		var best := 999.0
		while Time.get_ticks_msec() < t_end:
			await get_tree().physics_frame
			best = minf(best, U.flat_dist(e0.global_position, p.global_position))
			if best < 3.0: break
		check(best < 3.5, "враг из зала рычагов обошёл стену через проём и догнал героя (мин. %.1f м)" % best)
		for e in d.enemies: if is_instance_valid(e): e.set_process(true)

## Убить Хранителя → портал возврата появляется → дойти до него по навмешу → долина у входа в склеп, добыча собрана
func _boss_return(d, cls: String, run: int) -> void:
	var b = d.builder
	var p: Player = d.player
	var boss = b.boss_enemy()
	check(boss != null and b.return_portal == null, "[%s] забег %d: Хранитель жив, портала возврата ещё нет" % [cls, run])
	if boss == null: return
	var inv0: int = p.data["inventory"].size()
	var gold0: int = int(p.data["gold"])
	p.teleport(b.arena_center + Vector3(0, 0.1, -10)); await w(0.3)
	var g := 0
	while is_instance_valid(boss) and boss.alive and g < 60:
		if boss.brain: boss.brain.invulnerable = false
		boss.take_damage(boss.max_hp * 2.0, false)
		await get_tree().physics_frame; g += 1
	await w(1.2)
	check(b.return_portal != null and is_instance_valid(b.return_portal), "[%s] забег %d: после победы на арене появился портал возврата" % [cls, run])
	if b.return_portal == null: return
	check("портал" in d.hud.objective.text.to_lower(), "[%s] подсказка на экране: %s" % [cls, d.hud.objective.text])
	var map: RID = b.nav_map()
	check(reachable(map, p.global_position, b.return_point, 1.0), "[%s] портал возврата достижим по навмешу" % cls)
	await walk(d, map, b.return_point, 0.3, "портал возврата")
	g = 0
	while get_tree().current_scene == d and g < 300:
		await get_tree().physics_frame; g += 1
	await w(1.5)
	var s = get_tree().current_scene
	var ok: bool = s != d and s.has_method("is_dungeon") and not s.is_dungeon()
	check(ok, "[%s] забег %d: портал вернул в долину" % [cls, run])
	if not ok: return
	var pl: Player = s.player
	check(U.flat_dist(pl.global_position, s.builder.dungeon_gate_point) < 8.0, "[%s] герой у входа в склеп: %s" % [cls, str(pl.global_position)])
	var saved = Game.load_file(Game.SAVE_DIR + "/char_%s.json" % pl.data["id"])
	var inv_ok: bool = pl.data["inventory"].size() > inv0 or int(pl.data["gold"]) > gold0
	check(inv_ok and saved != null and (saved["inventory"] as Array).size() == pl.data["inventory"].size(), "[%s] добыча собрана и сохранена (предметы %d → %d, золото %d → %d)" % [cls, inv0, pl.data["inventory"].size(), gold0, int(pl.data["gold"])])
	check(DB.zone_flag(pl.data, "dungeon", "boss_warden_killed"), "[%s] победа над Хранителем сохранена" % cls)

func _class_run(cls: String) -> void:
	for f in Game.list_characters(): if str(f.get("name", "")) == "Навигатор": Game.delete_character(f["id"])
	var rng := RandomNumberGenerator.new(); rng.seed = 11
	var c := DB.new_character("Навигатор", cls, CharAssets.random_look(0, rng))
	c["level"] = 12
	c["tutorial"] = {"move": true, "attack": true, "jump": true, "talents": true, "shop": true, "boss": true}
	DB.set_zone_flag(c, "starter", "boss_troll_killed")
	c["zone"] = "dungeon"; c["has_pos"] = false
	Game.save_character(c)
	Game.play(c); await w(2.0)
	var d = get_tree().current_scene
	check(d.has_method("is_dungeon") and d.is_dungeon(), "[%s] старт в склепе" % cls)
	if not d.is_dungeon(): return
	var p: Player = d.player
	p.god_mode = true
	if cls == "warrior": await _wall_fight(d)
	for e in d.enemies.duplicate():
		if is_instance_valid(e) and e.kind != "warden": e.queue_free(); d.enemies.erase(e)
	await w(0.2)
	var b = d.builder
	var map := await bake(d)
	var start: Vector3 = p.global_position
	check(reachable(map, start, Vector3(0, 0, 52)), "[%s] навмеш: от входа до зала рычагов есть путь" % cls)
	check(not reachable(map, start, b.arena_center), "[%s] навмеш: до решения рычагов арена закрыта решёткой" % cls)
	for dz in b.DOORWAYS:
		var pth := path_to(map, Vector3(0, 0, dz - 3), Vector3(0, 0, dz + 3))
		var ok := pth.size() > 0 and U.flat_dist(pth[pth.size() - 1], Vector3(0, 0, dz + 3)) < 1.0
		if dz == 64.0: ok = not ok   # решётка закрыта
		check(ok, "[%s] проём z=%d %s" % [cls, int(dz), "закрыт решёткой" if dz == 64.0 else "проходим"])
	# ширина проёмов ≥ 3 м: точки на ±1.5 м от центра проёма достижимы
	for dz in [16.0, 40.0, 86.0]:
		check(reachable(map, Vector3(-1.5, 0, dz - 2), Vector3(1.5, 0, dz + 2), 0.6) and reachable(map, Vector3(1.5, 0, dz - 2), Vector3(-1.5, 0, dz + 2), 0.6), "[%s] проём z=%d шире 3 м" % [cls, int(dz)])
	# агент: через коридор ловушек в зал рычагов
	check(await walk(d, map, Vector3(0, 0, 44), 0.8, "зал рычагов"), "[%s] агент прошёл коридор ловушек" % cls)
	for id in b.ORDER:
		var lp: Vector3 = b.levers[id].global_position
		var tgt := lp + (Vector3(0, 0, 52) - lp).normalized() * 1.4
		var ok := await walk(d, map, tgt, 0.7, "рычаг " + id)
		d.hud.interact(); await w(0.4)
		check(ok and b.levers[id].on, "[%s] агент дошёл и повернул рычаг «%s»" % [cls, b.ORDER_NAMES[id]])
	check(b.gate_open(), "[%s] рычаги решены — решётка открыта" % cls)
	await w(1.0)
	map = await bake(d)
	check(reachable(map, p.global_position, b.arena_center), "[%s] навмеш: после рычагов путь до арены" % cls)
	check(await walk(d, map, Vector3(0, 0, 88), 0.8, "огненный коридор"), "[%s] агент прошёл огненный коридор" % cls)
	check(await walk(d, map, b.arena_center + Vector3(0, 0, -5), 1.0, "арена"), "[%s] агент дошёл до центра арены" % cls)
	if cls == "archer":
		# выход через портал у входа (босс жив) — проверка обратного пути
		var boss0 = b.boss_enemy()
		if boss0: boss0.set_process(false)
		check(await walk(d, map, Vector3(0, 0, 3), 1.0, "обратно ко входу"), "[%s] агент вернулся ко входу" % cls)
		await walk(d, map, b.exit_point, 0.2, "портал выхода")
		var g := 0
		while get_tree().current_scene == d and g < 200:
			p.force_move = Vector3(0, 0, -1)
			await get_tree().physics_frame; g += 1
		await w(1.5)
		var s0 = get_tree().current_scene
		check(s0 != d and s0.has_method("is_dungeon") and not s0.is_dungeon(), "[%s] выход через портал → лагерь" % cls)
	else:
		await _boss_return(d, cls, 1)
		if cls == "warrior":
			# повторный забег: снова в склеп, босс снова жив, снова портал
			Game.travel("dungeon"); await w(2.0)
			var d2 = get_tree().current_scene
			check(d2.is_dungeon() and d2.builder.boss_enemy() != null and d2.builder.return_portal == null, "[%s] повторный забег: Хранитель снова на месте, портала нет" % cls)
			if d2.is_dungeon():
				d2.player.god_mode = true
				await bake(d2)
				d2.player.teleport(Vector3(0, 0.1, 88)); await w(0.5)
				await _boss_return(d2, cls, 2)
	Game.to_menu(); await w(1.0)
	Game.delete_character(c["id"])
