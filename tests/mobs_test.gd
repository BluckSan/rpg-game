extends Node
## v0.5.1: призывы на земле (долина/мир/склеп), боссы без сплющивания, новые семейства мобов, роли ИИ, аффиксы.
## godot --headless --path . res://tests/mobs_test.tscn ++ --ignore-lock
var is_runner := false
var errors := 0

func check(cond: bool, msg: String) -> void:
	if cond: print("  OK  ", msg)
	else:
		errors += 1
		printerr("  FAIL ", msg)

func frames(n: int) -> void:
	for i in n: await get_tree().process_frame

func secs(t: float) -> void:
	await get_tree().create_timer(t).timeout

func _ready() -> void:
	if not is_runner:
		var r = load("res://tests/mobs_test.gd").new(); r.is_runner = true
		get_tree().root.add_child.call_deferred(r); return
	print("=== MOBS TEST (v0.5.1) ===")
	get_tree().create_timer(420.0, true, false, true).timeout.connect(func():
		printerr("TIMEOUT"); get_tree().quit(2))
	for f in Game.list_characters(): Game.delete_character(f["id"])
	var c := DB.new_character("Тень", "mage", {})
	c["level"] = 14
	DB.set_zone_flag(c, "starter", "boss_troll_killed")
	# 1. призывы стоят на земле в трёх видах зон
	for zn in ["starter", "global", "dungeon"]:
		c["zone"] = zn; c["has_pos"] = false
		Game.save_character(c); Game.current = c
		get_tree().change_scene_to_file("res://scenes/zone.tscn")
		await frames(8)
		await secs(1.0)
		var z = get_tree().current_scene
		await _summon_ground(z, zn)
		if zn == "starter":
			await _model_tests(z)
			await _role_tests(z)
			await _boss_scale_tests(z)
	print("=== MOBS TEST: %s (%d errors) ===" % ["PASS" if errors == 0 else "FAIL", errors])
	get_tree().quit(0 if errors == 0 else 1)

## Независимая проверка: луч вниз по физике (столкновения земли), а не по той же функции, что ставит ноги
func _ray_floor(z, pos: Vector3) -> Variant:
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 2.5, pos + Vector3.DOWN * 6.0, 1)
	var hit: Dictionary = z.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty(): return null
	return hit.position.y

func _summon_ground(z, zn: String) -> void:
	var p: Player = z.player
	p.god_mode = true
	for e in z.enemies.duplicate():   # чтобы призывы шли за героем, а не дрались
		if is_instance_valid(e) and e.alive: e.alive = false; e.visible = false; e.process_mode = Node.PROCESS_MODE_DISABLED
	z.enemies.clear()
	var ms: Array = []
	for i in 3:
		ms.append(Minion.spawn(z, p.global_position + Vector3(1.5 * (i - 1), 3.0, 1.5), p, 0.6, 60.0))
	await frames(3)
	var init_ok := true
	for m in ms: if m.ground_error() > 0.05: init_ok = false
	check(init_ok, "[%s] призывы сразу на земле (а не в воздухе, спавн с +3 м)" % zn)
	# герой ходит кругами по рельефу (склоны/пандусы) — призывы следуют
	var start := p.global_position
	var worst := 0.0; var samples := 0; var ray_worst := 0.0
	var moved := 0.0
	var last: Vector3 = ms[0].global_position
	for step in 60:
		var a := step * 0.21
		var r := (4.0 + step * 0.12) if zn != "dungeon" else (2.5 + step * 0.05)
		var tgt := start + Vector3(cos(a) * r, 0, sin(a) * r)
		if z.builder.has_method("nav_ready") and z.builder.nav_ready():
			tgt = NavigationServer3D.map_get_closest_point(z.builder.nav_map(), tgt)
		tgt.y = z.ground_y(tgt)
		p.teleport(tgt)
		await secs(0.1)
		if not is_instance_valid(z) or z != get_tree().current_scene: break
		for m in ms:
			if not is_instance_valid(m): continue
			worst = maxf(worst, m.ground_error())
			var fy = _ray_floor(z, m.global_position)
			if fy != null:
				var dy: float = m.global_position.y - float(fy)
				# луч мог упасть на камень/пропс выше земли — это не «парение»
				if dy > -0.5:
					ray_worst = maxf(ray_worst, absf(dy)); samples += 1
		if is_instance_valid(ms[0]):
			moved += ms[0].global_position.distance_to(last); last = ms[0].global_position
	var mx := 0.0
	for m in ms: if is_instance_valid(m): mx = maxf(mx, m.max_ground_err)
	check(mx <= 0.15 and worst <= 0.15, "[%s] ноги призывов у земли всё время: макс. %.3f м" % [zn, mx])
	check(samples > 20 and ray_worst <= 0.15, "[%s] луч по физике: отклонение ≤ %.3f м (%d замеров)" % [zn, ray_worst, samples])
	check(moved > (8.0 if zn != "dungeon" else 4.0), "[%s] призывы идут за героем (%.0f м)" % [zn, moved])
	for m in ms: if is_instance_valid(m): m._die()

func _spawn(z, kind: String, lvl: int, off: Vector3) -> Enemy:
	var p: Player = z.player
	var pos: Vector3 = p.global_position + off
	pos.y = z.ground_y(pos)
	var e := Enemy.spawn(z, kind, lvl, pos, z.builder.enemies_root if "enemies_root" in z.builder else z)
	return e

func _model_tests(z) -> void:
	var fam := {}
	for k in DB.ENEMIES:
		var d: Dictionary = DB.ENEMIES[k]
		if not d.has("model"): continue
		var e := _spawn(z, k, 10, Vector3(30, 0, 30))
		await frames(2)
		var mm = e.model
		var ok: bool = mm is MobModel and mm.ap != null
		if ok:
			for a in ["attack", "death", "idle", "walk"]:
				if not mm.ap.has_animation(mm._name(a)): ok = false
		check(ok, "%s («%s»): своя модель «%s» с анимациями атаки/смерти" % [k, d.name, d.model])
		fam[d.model] = true
		e.queue_free(); z.enemies.erase(e)
	check(fam.size() >= 18, "разных моделей монстров: %d" % fam.size())
	# у каждого биома — свои семейства, у каждой зоны — свой босс
	var seen := {}; var bosses := {}
	for b in WorldData.BIOMES:
		var models := {}
		for k in b.mobs: models[DB.ENEMIES[k].get("model", k)] = true
		check(models.size() >= 3, "«%s»: %d семейства" % [b.name, models.size()])
		bosses[b.boss_kind] = DB.ENEMIES[b.boss_kind].model
	check(bosses.size() == 6 and _uniq(bosses.values()) == 6, "6 боссов мира — 6 разных моделей")
	var roles := {}
	for k in DB.ENEMIES: roles[DB.ENEMIES[k].get("ai", "ranged" if DB.ENEMIES[k].ranged else "melee")] = true
	for r in ["melee", "ranged", "charger", "caster", "swarm", "exploder", "healer"]:
		check(roles.has(r), "роль «%s» есть" % r)

func _uniq(a: Array) -> int:
	var d := {}
	for x in a: d[x] = true
	return d.size()

func _role_tests(z) -> void:
	var p: Player = z.player
	p.god_mode = false
	p.hp = 1.0e6
	p.stats.max_hp = 1.0e6
	# таран
	var bull := _spawn(z, "bull", 10, Vector3(9, 0, 0))
	bull.ability_cd = 0.0; bull._aggro = true
	var sp := bull.global_position
	await secs(2.6)
	check(bull.ability_log.has("charge"), "тур: таран с предупреждением")
	check(U.flat_dist(sp, bull.global_position) > 4.0, "тур: рывок %.1f м" % U.flat_dist(sp, bull.global_position))
	_clear(z, bull)
	# заклинатель
	var hp0 := p.hp
	var dr := _spawn(z, "drake", 10, Vector3(7, 0, 0))
	dr._aggro = true; dr._attack_timer = 0.0
	await secs(3.0)
	check(dr.ability_log.has("cast"), "дракончик: заклинание по площади")
	_clear(z, dr)
	# взрывун
	hp0 = p.hp
	var mn := _spawn(z, "mushnub", 10, Vector3(5, 0, 0))
	mn._aggro = true
	await secs(4.0)
	check(mn.ability_log.has("explode") and not mn.alive, "спорыш: подбежал и взорвался")
	check(p.hp < hp0, "взрыв ранит героя (%.0f)" % (hp0 - p.hp))
	print("    player dead=%s hp=%.0f" % [p.dead, p.hp])
	p.god_mode = true
	# шаман лечит (герой рядом — взрывы/таран могли его отбросить)
	p.teleport(Vector3(p.global_position.x, z.ground_y(p.global_position), p.global_position.z))
	var w := _spawn(z, "wolf", 10, Vector3(7, 0, 3))
	w.hp = w.max_hp * 0.3
	w.process_mode = Node.PROCESS_MODE_DISABLED
	var sh := _spawn(z, "goblin_shaman", 10, Vector3(7, 0, 6))
	sh._aggro = true; sh.ability_cd = 0.0
	await secs(1.5)
	print("    shaman: pdead=%s target=%s cd=%.1f ret=%s busy=%s alive=%s d=%.1f" % [p.dead, sh.target, sh.ability_cd, sh._returning, sh.busy, sh.alive, U.flat_dist(sh.global_position, p.global_position)])
	check(sh.ability_log.has("heal") and w.hp > w.max_hp * 0.3, "шаман лечит раненого волка (%.0f%%)" % (w.hp / w.max_hp * 100))
	_clear(z, w); _clear(z, sh)
	# аффиксы
	var r := _spawn(z, "orc", 10, Vector3(20, 0, 20))
	var base_def_name: String = r.def.name
	r.make_rank("rare", "Тестовый")
	check(r.affixes.size() == 2, "редкий: 2 аффикса (%s)" % r.affix_text())
	var el := _spawn(z, "orc", 10, Vector3(22, 0, 20))
	el.make_rank("elite")
	check(el.affixes.size() == 1 and el.display_name.contains(Enemy.AFFIXES[el.affixes[0]].name), "элита: аффикс в имени — %s" % el.display_name)
	_clear(z, r); _clear(z, el)
	var st := _spawn(z, "orc", 10, Vector3(24, 0, 20))
	var f0 := Combat.player_vs_enemy(st, "phys", 10, 0, 0)
	var r0 := Combat.player_vs_enemy(st, "fire", 10, 0, 0)
	st.add_affix("stone"); st.add_affix("warded"); st.add_affix("fast")
	check(Combat.player_vs_enemy(st, "phys", 10, 0, 0) < f0, "«Каменнокожий»: физ. урон %.2f → %.2f" % [f0, Combat.player_vs_enemy(st, "phys", 10, 0, 0)])
	check(Combat.player_vs_enemy(st, "fire", 10, 0, 0) < r0, "«Заговорённый»: огонь %.2f → %.2f" % [r0, Combat.player_vs_enemy(st, "fire", 10, 0, 0)])
	check(st.speed_mult > 1.25, "«Стремительный»: скорость ×%.2f" % st.speed_mult)
	_clear(z, st)
	var sm := _spawn(z, "spider", 10, Vector3(26, 0, 20))
	sm.add_affix("summoner")
	var n0: int = z.enemies.size()
	sm.hp = sm.max_hp * 0.4
	sm._affix_tick(0.1)
	await frames(2)
	check(z.enemies.size() == n0 + 2, "«Призыватель»: 2 помощника на половине здоровья")
	p.god_mode = true
	for e in z.enemies.duplicate(): _clear(z, e)

func _clear(z, e) -> void:
	if not is_instance_valid(e): return
	z.enemies.erase(e)
	e.alive = false
	e.queue_free()

func _uniform(v: Vector3) -> bool:
	return absf(v.x - v.y) < 0.001 and absf(v.y - v.z) < 0.001

## Боссы: масштаб модели равномерный и равен исходному после каждой фазы (и после ударов в неуязвимости)
func _boss_scale_tests(z) -> void:
	var p: Player = z.player
	p.god_mode = true
	var kinds := ["troll", "warden"]
	for b in WorldData.BIOMES: kinds.append(b.boss_kind)
	for k in kinds:
		var e := _spawn(z, k, 12, Vector3(0, 0, 14))
		e._aggro = true
		await frames(3)
		var base: Vector3 = e.model.scale
		var ok := _uniform(base)
		var phases := []
		for target in [0.6, 0.3]:
			var dmg: float = e.hp - e.max_hp * target + 1.0
			e.take_damage(dmg, false, "true")
			for i in 12:     # удары во время смены фазы (неуязвимость) и сразу после
				e.knockback(Vector3(1, 0, 0), 8.0)
				e.take_damage(5.0, false, "true")
				await secs(0.12)
				if not _uniform(e.model.scale) or not _uniform(e.scale): ok = false
			await secs(1.0)
			phases.append(e.brain.phase if e.brain else 0)
			if not e.model.scale.is_equal_approx(base) or not e.scale.is_equal_approx(Vector3.ONE): ok = false
			# скелетные меши — без неравномерного масштаба по всей цепочке
			for mi in e.model.find_children("*", "MeshInstance3D", true, false):
				if (mi as MeshInstance3D).skin != null or (mi as MeshInstance3D).skeleton != NodePath(""):
					var s: Vector3 = (mi as Node3D).global_basis.get_scale()
					if absf(s.x - s.y) > 0.01 * s.x or absf(s.y - s.z) > 0.01 * s.x: ok = false
		var reached: bool = e.brain == null or (phases.size() == 2 and phases[1] >= 3) or k == "warden"
		check(ok and reached, "босс %s: масштаб равномерный и прежний после фаз %s (%.2f)" % [k, str(phases), base.x])
		_clear(z, e)
		await frames(2)
