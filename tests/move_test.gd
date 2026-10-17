extends Node
## v0.5.1: рывки/телепорты не сквозь стены и не под карту, снаряды не пролетают стены, прицел в 3D на склонах.
## godot --headless --path . res://tests/move_test.tscn ++ --ignore-lock
var is_runner := false
var errors := 0

func check(cond: bool, msg: String) -> void:
	if cond: print("  OK  ", msg)
	else:
		errors += 1
		printerr("  FAIL ", msg)

func frames(n: int) -> void:
	for i in n: await get_tree().physics_frame

func secs(t: float) -> void:
	await get_tree().create_timer(t).timeout

func _ready() -> void:
	if not is_runner:
		var r = load("res://tests/move_test.gd").new(); r.is_runner = true
		get_tree().root.add_child.call_deferred(r); return
	print("=== MOVE TEST (v0.5.1) ===")
	get_tree().create_timer(400.0, true, false, true).timeout.connect(func():
		printerr("TIMEOUT"); get_tree().quit(2))
	for f in Game.list_characters(): Game.delete_character(f["id"])
	var c := DB.new_character("Прыгун", "mage", {})
	c["level"] = 14
	DB.set_zone_flag(c, "starter", "boss_troll_killed")
	var zones := ["starter", "global", "dungeon"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--zones="): zones = Array(a.substr(8).split(","))
	for zn in zones:
		c["zone"] = zn; c["has_pos"] = false
		Game.save_character(c); Game.current = c
		get_tree().change_scene_to_file("res://scenes/zone.tscn")
		await frames(10)
		await secs(1.0)
		var z = get_tree().current_scene
		z.player.god_mode = true
		for e in z.enemies.duplicate():
			if is_instance_valid(e): e.alive = false; e.process_mode = Node.PROCESS_MODE_DISABLED
		z.enemies.clear()
		# порталы выключаем, чтобы случайный рывок не сменил сцену
		for n in z.find_children("*", "", true, false):
			if n is Portal: n.process_mode = Node.PROCESS_MODE_DISABLED
		if zn == "starter": await _wall_and_cliff(z)
		await _random_blinks(z, zn)
		if zn == "global": await _slope_shots(z)
	print("=== MOVE TEST: %s (%d errors) ===" % ["PASS" if errors == 0 else "FAIL", errors])
	get_tree().quit(0 if errors == 0 else 1)

func _box(z, pos: Vector3, size: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new(); b.collision_layer = 1
	var cs := CollisionShape3D.new(); var sh := BoxShape3D.new(); sh.size = size; cs.shape = sh
	b.add_child(cs)
	var mi := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = size; mi.mesh = bm; b.add_child(mi)
	z.add_child(b); b.global_position = pos
	return b

func _wall_and_cliff(z) -> void:
	var p: Player = z.player
	var o := Vector3(40, 0, -30)
	o.y = z.ground_y(o)
	p.teleport(o + Vector3.UP * 0.05)
	await frames(4)
	var start := p.global_position
	# стена в 4 м перед героем, толщина 0.5 м
	var wall := _box(z, start + Vector3(0, 2.0, 4.0), Vector3(6, 4, 0.5))
	await frames(2)
	var d := p.blink_to(start + Vector3(0, 0, 9.0))
	check(d.z < start.z + 4.0 - 0.25 - 0.3, "рывок в стену: остановка перед ней (z %.2f, стена с %.2f)" % [d.z - start.z, 3.75])
	await frames(3)
	check(p.global_position.z < start.z + 3.75, "после рывка герой по эту сторону стены")
	# прыжок (leap) — тоже упирается
	var ld := p.safe_destination(start + Vector3(0, 0, 9.0))
	check(ld.z < start.z + 3.75, "прыжок через стену не проходит (%.2f)" % (ld.z - start.z))
	# снаряд в стену: не долетает до дальней стороны
	var pr := Projectile.fire(z, start + Vector3.UP * 1.2, Vector3(0, 0, 1), 30.0, 20.0, Color.WHITE, 0.25, true, Callable())
	var max_z := -INF
	for i in 40:
		await frames(1)
		if not is_instance_valid(pr): break
		max_z = maxf(max_z, pr.global_position.z)
	check(not is_instance_valid(pr) and max_z < start.z + 4.25, "снаряд разбился о стену (дальше %.2f м не пролетел)" % (max_z - start.z))
	# снаряд на высокой скорости (тонкая стена, большой шаг кадра)
	var fast := Projectile.fire(z, start + Vector3.UP * 1.2, Vector3(0, 0, 1), 400.0, 30.0, Color.WHITE, 0.2, true, Callable())
	var fz := -INF
	for i in 10:
		await frames(1)
		if not is_instance_valid(fast): break
		fz = maxf(fz, fast.global_position.z)
	check(fz < start.z + 4.25, "быстрый снаряд (400 м/с) тоже не проходит стену")
	wall.queue_free()
	# обрыв: герой на площадке 5 м, рывок за край — приземление на землю, не в воздух и не под неё
	var plat := _box(z, start + Vector3(0, 2.5, 0), Vector3(3, 5, 3))
	await frames(2)
	p.teleport(start + Vector3(0, 5.05, 0))
	await frames(3)
	var cd := p.blink_to(start + Vector3(8, 5.0, 0))
	var gy: float = z.ground_y(cd)
	check(absf(cd.y - gy) < 0.3, "рывок с обрыва: на земле (y %.2f, земля %.2f)" % [cd.y, gy])
	plat.queue_free()
	await frames(2)

func _random_blinks(z, zn: String) -> void:
	var p: Player = z.player
	var rng := RandomNumberGenerator.new(); rng.seed = 4242
	var bad := 0; var worst := 0.0
	var home := p.global_position
	for i in 60:
		var a := rng.randf() * TAU
		var to := p.global_position + Vector3(cos(a), 0, sin(a)) * rng.randf_range(4, 14)
		if i % 3 == 0: to = p.safe_destination(to)
		var d := p.blink_to(to)
		if OS.get_cmdline_user_args().has("--verbose"): print("   blink ", i, " ", to, " -> ", d)
		await frames(2)
		var gy: float = z.ground_y(d)
		var fy = p.floor_at(d, d.y + 2.0)
		var under := (fy == null) or d.y < float(fy) - 0.3 or (z.builder is WorldBuilder and d.y < gy - 0.3)
		if under: bad += 1
		worst = maxf(worst, (gy - d.y) if z.builder is WorldBuilder else 0.0)
		if p.global_position.distance_to(home) > 60: p.teleport(home)
	await frames(10)
	var gy2: float = z.ground_y(p.global_position)
	check(bad == 0, "[%s] 60 случайных рывков: ни одного под картой/без пола" % zn)
	check(p.global_position.y > gy2 - 0.5, "[%s] герой на поверхности после серии" % zn)
	# страховка: принудительно под землю — возвращает на последнюю безопасную точку
	var r0 := p.rescues
	p.teleport(p.global_position + Vector3.DOWN * 6.0)
	await frames(4)
	check(p.rescues > r0 and p.global_position.y > z.ground_y(p.global_position) - 0.5, "[%s] из-под карты — назад на безопасную точку" % zn)

## Склон: цель выше/ниже стрелка — снаряд с прицелом в 3D попадает
func _slope_shots(z) -> void:
	var p: Player = z.player
	var wb: WorldBuilder = z.builder
	# ищем склон: перепад ≥ 3 м на 10 м у героя
	var base := p.global_position
	var found := false; var lo := Vector3.ZERO; var hi := Vector3.ZERO
	# сетка по миру, ближайший к герою склон 3–6 м на 14 м с ровным уклоном (без гребня между точками)
	var best_d := INF
	for gx in range(-780, 780, 20):
		for gz in range(-780, 780, 20):
			var c := Vector3(gx, 0, gz)
			var h1: float = WorldData.height(c.x, c.z)
			for dv in [Vector3(14, 0, 0), Vector3(0, 0, 14), Vector3(10, 0, 10), Vector3(10, 0, -10)]:
				var c2: Vector3 = c + dv
				var h2: float = WorldData.height(c2.x, c2.z)
				var hm: float = WorldData.height((c.x + c2.x) * 0.5, (c.z + c2.z) * 0.5)
				var dh := absf(h1 - h2)
				if dh < 3.0 or dh > 6.0: continue
				if hm > maxf(h1, h2) - 0.3 or hm < minf(h1, h2) + 0.3: continue
				var dist := Vector2(c.x - base.x, c.z - base.z).length()
				if dist < best_d:
					best_d = dist; found = true
					lo = Vector3(c.x, h1, c.z) if h1 < h2 else Vector3(c2.x, h2, c2.z)
					hi = Vector3(c2.x, h2, c2.z) if h1 < h2 else Vector3(c.x, h1, c.z)
	if not found:
		# запасной вариант: искусственный уступ 4 м
		lo = base; lo.y = z.ground_y(base)
		hi = base + Vector3(10, 0, 0); hi.y = z.ground_y(hi)
		_box(z, hi + Vector3(0, 2.0, 0), Vector3(4, 4, 4)); hi.y += 4.0
		await frames(3)
	print("  склон: перепад %.1f м (%s)" % [hi.y - lo.y, "рельеф" if found else "уступ"])
	wb.prepare(lo); await frames(5)
	for pair in [[lo, hi, "вверх"], [hi, lo, "вниз"]]:
		var from: Vector3 = pair[0]; var to: Vector3 = pair[1]
		p.teleport(from + Vector3.UP * 0.1)
		await frames(3)
		var e = Enemy.spawn(z, "wolf", 10, to, wb.enemies_root)
		e.process_mode = Node.PROCESS_MODE_DISABLED
		e.global_position = to
		await frames(2)
		var origin := p.global_position + Vector3.UP * 1.3
		var pr = Projectile.fire(z, origin, p._dir_to(origin, e), 26.0, 20.0, Color.WHITE, 0.25, true, func(x): x.take_damage(1.0, false, "true"))
		var hit := false
		for i in 60:
			await frames(1)
			if not is_instance_valid(pr):
				break
			if pr.hits > 0: hit = true
		check(hit or e.hp < e.max_hp, "выстрел %s по склону попал (Δh %.1f м)" % [pair[2], to.y - from.y])
		# ответный выстрел врага (лучник) — тоже в 3D
		var ar = Enemy.spawn(z, "skeleton_archer", 10, to + Vector3(1.5, 0, 0), wb.enemies_root)
		ar.target = p
		ar.global_position = to + Vector3(1.5, 0, 0); ar.global_position.y = WorldData.height(to.x + 1.5, to.z)
		var dd: Vector3 = p.global_position - ar.global_position; ar.rotation.y = atan2(dd.x, dd.z)
		ar.process_mode = Node.PROCESS_MODE_DISABLED
		p.god_mode = false; p.stats.max_hp = 1.0e6; p.hp = 1.0e6
		var hp0: float = p.hp
		ar._attack()
		for i in 90:
			await frames(1)
			if p.hp < hp0: break
		check(p.hp < hp0, "лучник %s по склону попал в героя" % ("сверху" if pair[2] == "вверх" else "снизу"))
		p.god_mode = true
		e.queue_free(); ar.queue_free(); z.enemies.erase(e); z.enemies.erase(ar)
		await frames(2)
