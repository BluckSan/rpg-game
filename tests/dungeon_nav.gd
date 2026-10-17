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

var nav_region: NavigationRegion3D
func bake(d) -> RID:
	if nav_region and is_instance_valid(nav_region): nav_region.queue_free()
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5; nm.agent_height = 2.0; nm.agent_max_climb = 0.25; nm.agent_max_slope = 40.0
	nm.cell_size = 0.25; nm.cell_height = 0.25
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, d.builder)
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	print("    навмеш: полигонов ", nm.get_polygon_count(), ", вершин ", nm.get_vertices().size(), ", вершин источника ", src.get_vertices().size())
	nav_region = NavigationRegion3D.new(); nav_region.navigation_mesh = nm
	d.add_child(nav_region)
	var map: RID = d.get_world_3d().navigation_map
	var it0 := NavigationServer3D.map_get_iteration_id(map)
	for i in 120:
		await get_tree().physics_frame
		if NavigationServer3D.map_get_iteration_id(map) != it0 and NavigationServer3D.map_get_closest_point(map, Vector3(0, 0, 3)) != Vector3.ZERO: break
	print("    карта: регионов ", NavigationServer3D.map_get_regions(map).size(), ", ближайшая точка к (0,0,3): ", NavigationServer3D.map_get_closest_point(map, Vector3(0, 0, 3)))
	return map

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
	for e in d.enemies.duplicate(): if is_instance_valid(e): e.queue_free()
	d.enemies.clear()
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
	await w(0.8)
	map = await bake(d)
	check(reachable(map, p.global_position, b.arena_center), "[%s] навмеш: после рычагов путь до арены" % cls)
	check(await walk(d, map, Vector3(0, 0, 88), 0.8, "огненный коридор"), "[%s] агент прошёл огненный коридор" % cls)
	check(await walk(d, map, b.arena_center + Vector3(0, 0, -5), 1.0, "арена"), "[%s] агент дошёл до центра арены" % cls)
	check(await walk(d, map, Vector3(0, 0, 3), 1.0, "обратно ко входу"), "[%s] агент вернулся ко входу" % cls)
	await walk(d, map, b.exit_point, 0.2, "портал выхода")
	var g := 0
	while get_tree().current_scene == d and g < 200:
		p.force_move = Vector3(0, 0, -1)
		await get_tree().physics_frame; g += 1
	await w(1.5)
	var s = get_tree().current_scene
	check(s != d and s.has_method("is_dungeon") and not s.is_dungeon(), "[%s] выход через портал → лагерь" % cls)
	Game.to_menu(); await w(1.0)
	Game.delete_character(c["id"])
