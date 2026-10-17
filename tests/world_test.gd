extends Node
## Тест открытого мира: подгрузка чанков, уровни зон, спавнеры, города, путевые камни, быстрое перемещение.
## godot --headless --path . res://tests/world_test.tscn ++ --ignore-lock
var is_runner := false
var errors := 0

func check(cond: bool, msg: String) -> void:
	if cond: print("  OK  ", msg)
	else:
		errors += 1
		printerr("  FAIL ", msg)

func frames(n: int) -> void:
	for i in n: await get_tree().process_frame

func _ready() -> void:
	if not is_runner:
		var r = load("res://tests/world_test.gd").new(); r.is_runner = true
		get_tree().root.add_child.call_deferred(r); return
	print("=== WORLD TEST ===")
	get_tree().create_timer(240.0, true, false, true).timeout.connect(func():
		printerr("TIMEOUT"); get_tree().quit(2))
	# 1. данные мира (без сцены)
	WorldData.init()
	check(WorldData.HALF * 2 >= 2000, "мир %d×%d м" % [WorldData.HALF * 2, WorldData.HALF * 2])
	check(WorldData.BIOMES.size() >= 4 and WorldData.BIOMES.size() <= 6, "биомов: %d" % WorldData.BIOMES.size())
	for i in WorldData.BIOMES.size():
		var b: Dictionary = WorldData.BIOMES[i]
		check(WorldData.biome_at(b.seed.x, b.seed.y) == i, "центр зоны «%s» в своём биоме" % b.name)
		var t: Dictionary = WorldData.TOWNS[i]
		check(WorldData.biome_at(t.pos.x, t.pos.y) == i, "город «%s» в зоне «%s»" % [t.name, b.name])
	# уровни по зонам: монотонно растут, каждый уровень мобов в диапазоне своей зоны
	var prev := 0
	for i in WorldData.BIOMES.size():
		var lv: Array = WorldData.BIOMES[i].lv
		check(int(lv[0]) >= prev - 4 and int(lv[1]) > int(lv[0]), "диапазон уровней %s: %d–%d" % [WorldData.BIOMES[i].id, lv[0], lv[1]])
		prev = int(lv[0])
	var rng := RandomNumberGenerator.new(); rng.seed = 5
	var lv_ok := true
	for i in 400:
		var x := rng.randf_range(-900, 900); var z := rng.randf_range(-900, 900)
		var b := WorldData.biome_at(x, z); var l := WorldData.level_at(x, z)
		var r: Array = WorldData.BIOMES[b].lv
		if l < int(r[0]) or l > int(r[1]): lv_ok = false
	check(lv_ok, "уровень мобов в точке всегда в диапазоне её зоны (400 точек)")
	# дороги соединяют города
	for t in WorldData.TOWNS:
		check(WorldData.road_dist(t.pos.x, t.pos.y) < 2.0, "к городу «%s» ведёт дорога" % t.name)
	var t0 := Time.get_ticks_usec()
	var d := WorldBuilder.gen_chunk(Vector2i(0, 8), 0, 2)
	var gen_ms := (Time.get_ticks_usec() - t0) / 1000.0
	check(d.heights.size() == 33 * 33, "чанк: сетка 33×33 (%.0f мс генерации)" % gen_ms)
	var dfar := WorldBuilder.gen_chunk(Vector2i(0, 8), 1, 2)
	check(dfar.heights.size() == 9 * 9 and dfar.solid.is_empty(), "дальний LOD: сетка 9×9, без столкновений")
	var np := 0; var npf := 0
	for k in d.props: np += d.props[k].size()
	for k in dfar.props: npf += dfar.props[k].size()
	check(np > npf and npf > 0, "дальний LOD без мелких пропсов (%d → %d)" % [np, npf])
	# 2. сцена мира
	for f in Game.list_characters(): Game.delete_character(f["id"])
	var c := DB.new_character("Странник", "archer", {})
	c["level"] = 12; c["zone"] = "global"
	Game.save_character(c)
	Game.current = c
	check(DB.zone_lock_reason(c, "global") == "", "мир доступен с 5 уровня")
	var tl := Time.get_ticks_msec()
	get_tree().change_scene_to_file("res://scenes/zone.tscn")
	await frames(6)
	var z = get_tree().current_scene
	var load_ms := Time.get_ticks_msec() - tl
	check(z != null and z.builder is WorldBuilder, "сцена мира загружена (%d мс)" % load_ms)
	var wb: WorldBuilder = z.builder
	var p: Player = z.player
	p.god_mode = true
	check(wb.chunks.size() >= 9, "стартовые чанки построены: %d" % wb.chunks.size())
	var pc := WorldBuilder.chunk_of(p.global_position)
	check(wb.chunks.has(pc) and wb.chunks[pc].lod == 0, "чанк под игроком — полная детализация")
	await get_tree().create_timer(1.5).timeout
	check(p.is_on_floor() or absf(p.global_position.y - z.ground_y(p.global_position)) < 0.6, "герой стоит на земле (y %.2f, земля %.2f)" % [p.global_position.y, z.ground_y(p.global_position)])
	check(wb.waypoints.size() >= 10, "путевых камней: %d" % wb.waypoints.size())
	check(wb.merchant_points.size() == WorldData.TOWNS.size(), "торговцы во всех городах")
	check(wb.bosses.size() == WorldData.BIOMES.size(), "боссы во всех зонах: %d" % wb.bosses.size())
	var rares := wb.spawners.filter(func(s): return s.rank == "rare")
	check(rares.size() >= WorldData.BIOMES.size() * 2, "именных редких: %d" % rares.size())
	check(wb.spawners.size() >= 80, "спавнеров в мире: %d" % wb.spawners.size())
	# спавнеры: уровни в диапазоне зоны
	var sp_ok := true
	for s in wb.spawners:
		var r: Array = WorldData.BIOMES[s.biome].lv
		if s.rank != "boss" and (s.min_level < int(r[0]) or s.max_level > int(r[1])): sp_ok = false
	check(sp_ok, "уровни всех спавнеров — в диапазоне своей зоны")
	# 3. подгрузка при движении
	var act0 := wb.active_spawners()
	check(act0 < wb.spawners.size() / 4, "активны только ближние спавнеры (%d из %d)" % [act0, wb.spawners.size()])
	var path := [Vector3(0, 0, 420), Vector3(-200, 0, 400), Vector3(-450, 0, 250), Vector3(-560, 0, 0)]
	var max_chunks := 0
	var fps_min := 999.0
	for target in path:
		var start: Vector3 = p.global_position
		for s in 30:
			var q: Vector3 = start.lerp(target, (s + 1) / 30.0)
			q.y = WorldData.height(q.x, q.z) + 0.4
			p.teleport(q)
			await frames(3)
			max_chunks = maxi(max_chunks, wb.chunks.size())
			fps_min = minf(fps_min, Engine.get_frames_per_second())
	await get_tree().create_timer(1.0).timeout
	pc = WorldBuilder.chunk_of(p.global_position)
	check(wb.chunks.has(pc) and wb.chunks[pc].lod == 0, "после пути чанк под героем подгружен")
	var far_loaded := 0
	for k in wb.chunks:
		if (k - pc).length() > 6: far_loaded += 1
	check(far_loaded == 0, "дальние чанки выгружены (лишних: %d)" % far_loaded)
	check(max_chunks <= 60, "одновременно чанков не больше 60 (макс. %d)" % max_chunks)
	check(wb.max_build_ms < 60.0, "сборка чанка в кадре < 60 мс (макс. %.1f)" % wb.max_build_ms)
	check(wb.built_count > 20, "построено чанков за путь: %d" % wb.built_count)
	# враги вокруг: уровень соответствует зоне, есть элиты при большом числе
	await get_tree().create_timer(1.0).timeout
	var lv_bad := 0
	for e in z.enemies:
		var b := WorldData.biome_at(e.global_position.x, e.global_position.z)
		var r: Array = WorldData.BIOMES[b].lv
		if e.rank != "boss" and (e.level < int(r[0]) - 1 or e.level > int(r[1]) + 1): lv_bad += 1
	check(z.enemies.size() > 0, "рядом есть враги: %d" % z.enemies.size())
	check(lv_bad == 0, "уровни врагов соответствуют зоне")
	var e_ok := true
	for e in z.enemies:
		if absf(e.global_position.y - z.ground_y(e.global_position)) > 0.8: e_ok = false
	check(e_ok, "враги стоят на рельефе")
	# ранги
	var el := Enemy.spawn(z, "wolf", 10, p.global_position + Vector3(6, 0, 0), wb.enemies_root)
	var base_hp := el.max_hp
	el.make_rank("elite")
	check(el.max_hp > base_hp * 1.9 and el.display_name.begins_with("★"), "элита: ×2 здоровья, отметка в имени")
	var rr := Enemy.spawn(z, "goblin", 10, p.global_position + Vector3(-6, 0, 0), wb.enemies_root)
	rr.make_rank("rare", "Тестовый Грох")
	check(rr.def.name == "Тестовый Грох" and rr.max_hp > 3.0 * DB.ENEMIES.goblin.hp, "редкий именной враг")
	check(DB.ENEMIES.goblin.name == "Гоблин-громила", "общий шаблон врага не изменён")
	var drops_r := 0
	for i in 50: drops_r += Items.drop_items(10, "archer", "rare").size()
	check(drops_r >= 100, "редкие враги щедрее на добычу (%d за 50)" % drops_r)
	for e2 in [el, rr]: z.enemies.erase(e2); e2.queue_free()
	# респаун у спавнера (абсолютное время, работает и выключенным)
	var ws: WorldSpawner = null
	for s in wb.spawners: if s.active and s.rank == "normal" and s.alive > 0: ws = s; break
	if ws == null:   # рядом никого — идём к ближайшему обычному спавнеру
		var bd := INF
		for s in wb.spawners:
			var sd := U.flat_dist(p.global_position, s.global_position)
			if s.rank == "normal" and sd < bd: bd = sd; ws = s
		var q: Vector3 = ws.global_position + Vector3(20, 0, 0)
		q.y = WorldData.height(q.x, q.z) + 0.4
		p.teleport(q)
		await get_tree().create_timer(1.0).timeout
		if not (ws.active and ws.alive > 0): ws = null
	check(ws != null, "есть активный спавнер рядом")
	if ws:
		var n0: int = ws.alive
		var victim = ws.mine[0]
		victim.take_damage(1e9, false)
		await frames(2)
		check(ws.alive == n0 - 1 and ws._respawn_at.size() == 1, "смерть врага → таймер возрождения")
		ws._respawn_at[0] = WorldSpawner.now() - 1.0
		ws.set_active(false)
		check(ws.mine.is_empty() and ws.alive == 0, "выключенный спавнер убирает врагов")
		ws.set_active(true)
		check(ws.alive == ws.count, "после возвращения — снова %d врагов (таймер истёк)" % ws.count)
	# 4. путевые камни и быстрое перемещение
	var wst := wb.world_state()
	check(not (wst["wp"] as Array).has("bog"), "дальний камень ещё не открыт")
	check(not wb.travel_to("bog"), "нельзя перенестись к неоткрытому камню")
	wb.discover_waypoint("bog")
	check(wb.travel_to("bog"), "перемещение к открытому камню")
	await frames(3)
	var bog: Dictionary = WorldData.TOWNS[3]
	check(Vector2(p.global_position.x, p.global_position.z).distance_to(bog.pos) < 30.0, "герой у Топкого лагеря")
	pc = WorldBuilder.chunk_of(p.global_position)
	check(wb.chunks.has(pc) and wb.chunks[pc].lod == 0, "чанки на месте прибытия построены сразу")
	await get_tree().create_timer(1.0).timeout
	check(absf(p.global_position.y - z.ground_y(p.global_position)) < 1.0, "после перемещения герой не провалился")
	wb._update_biome(p.global_position)
	check(wb.current_biome == 3, "текущая зона — Гнилые топи")
	# 5. окно карты
	z.hud._open("map"); await frames(3)
	check(z.hud.window != null and z.hud.window.name == "Window_map", "окно карты мира открыто")
	var mw = z.hud.window
	check(mw.has_method("travel") and mw.travel("cross"), "быстрое перемещение из окна карты")
	await frames(3)
	check(z.hud.window == null, "после перемещения карта закрыта")
	check(Vector2(p.global_position.x, p.global_position.z).distance_to(WorldData.TOWNS[0].pos) < 30.0, "герой у Перекрёстка")
	# 6. возрождение у ближайшего открытого камня
	var rp := wb.respawn_point(Vector3(-520, 0, -360))
	check(Vector2(rp.x, rp.z).distance_to(bog.pos) < 30.0, "возрождение у ближайшего открытого камня")
	# 7. сохранение позиции в мире
	z.save()
	var saved = Game.load_character(c["id"]) if Game.has_method("load_character") else Game.current
	check(saved["zone"] == "global" and saved.get("has_pos", false), "позиция в мире сохранена")
	print("=== RESULT: %s (%d errors) ===" % ["PASS" if errors == 0 else "FAIL", errors])
	get_tree().quit(0 if errors == 0 else 1)
