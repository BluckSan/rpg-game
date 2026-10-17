extends CharacterBody3D
class_name Player
## Игрок: движение, здоровье/мана, опыт и уровни, атаки и умения.
## Слоты умений: 0 — базовая атака, 1-2 — умения класса, 3 — умение пути (после превращения).

var data: Dictionary
var stats: Dictionary = {}
var hp := 1.0
var mp := 0.0
var dead := false
var visual: CharVisual
var cls: Dictionary
var cooldowns := [0.0, 0.0, 0.0, 0.0]
var rage_timer := 0.0
var shield_timer := 0.0
var move_input := Vector2.ZERO
var attack_held := false
var _dash_vel := Vector3.ZERO
var _dash_time := 0.0

func setup(d: Dictionary) -> void:
	data = d
	cls = DB.CLASSES[d["class"]]
	collision_layer = 2
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new(); cap.radius = 0.4; cap.height = 1.9
	cs.shape = cap; cs.position = Vector3(0, 0.95, 0)
	add_child(cs)
	floor_snap_length = 0.4
	visual = CharVisual.new()
	add_child(visual)
	rebuild_visual()
	recalc(true)

func rebuild_visual() -> void:
	visual.build(data["look"], data["class"], data["ascendancy"])

func recalc(fill := false) -> void:
	var hp_frac: float = hp / stats.max_hp if not stats.is_empty() else 1.0
	var mp_frac: float = mp / stats.max_mp if not stats.is_empty() else 1.0
	stats = DB.compute_stats(data)
	hp = stats.max_hp if fill else clampf(hp_frac * stats.max_hp, 1, stats.max_hp)
	mp = stats.max_mp if fill else clampf(mp_frac * stats.max_mp, 0, stats.max_mp)

func zone():
	return get_parent()

func _physics_process(delta: float) -> void:
	for i in 4:
		if cooldowns[i] > 0: cooldowns[i] -= delta
	if dead: return
	hp = minf(stats.max_hp, hp + stats.regen * delta)
	mp = minf(stats.max_mp, mp + stats.mp_regen * delta)
	if rage_timer > 0: rage_timer -= delta
	if shield_timer > 0: shield_timer -= delta
	data["play_time"] = float(data["play_time"]) + delta

	var input := move_input
	var kb := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if kb.length() > 0.1: input = Vector2(kb.x, -kb.y)
	var cam := get_viewport().get_camera_3d()
	var fwd := Vector3.FORWARD
	var right := Vector3.RIGHT
	if cam:
		fwd = -cam.global_basis.z; fwd.y = 0; fwd = fwd.normalized()
		right = cam.global_basis.x; right.y = 0; right = right.normalized()
	var move := fwd * input.y + right * input.x
	if move.length() > 1: move = move.normalized()
	var v: Vector3
	if _dash_time > 0:
		_dash_time -= delta
		v = _dash_vel
	else:
		v = move * stats.move_speed
		if move.length() > 0.05:
			rotation.y = lerp_angle(rotation.y, atan2(move.x, move.z), minf(1.0, delta * 12))
	velocity.x = v.x; velocity.z = v.z
	velocity.y = -2.0 if is_on_floor() else velocity.y - 20.0 * delta
	move_and_slide()
	if global_position.y < -10: teleport(zone().spawn_point)
	if attack_held or Input.is_key_pressed(KEY_SPACE): try_use(0)

func teleport(p: Vector3) -> void:
	global_position = p
	velocity = Vector3.ZERO

func face_towards(p: Vector3) -> void:
	var d := p - global_position
	if Vector2(d.x, d.z).length() > 0.05: rotation.y = atan2(d.x, d.z)

func forward() -> Vector3:
	return global_basis.z

func respawn(p: Vector3) -> void:
	teleport(p)
	dead = false
	recalc(true)

# ---------------- урон и опыт ----------------
func take_damage(dmg: float, _from: Vector3) -> void:
	if dead: return
	var dr: float = stats.dr + (0.5 if shield_timer > 0 else 0.0)
	var final := dmg * (1.0 - clampf(dr, 0, 0.85))
	hp -= final
	zone().damage_number(global_position + Vector3.UP * 2.2, final, false, true)
	if hp <= 0:
		hp = 0; dead = true
		zone().on_player_died()

func heal(a: float) -> void:
	if not dead: hp = minf(stats.max_hp, hp + a)

func gain_xp(amount: int) -> void:
	data["xp"] += amount
	data["class_xp"] += amount
	var lvl := false
	var clvl := false
	while data["xp"] >= DB.xp_to_next(data["level"]):
		data["xp"] -= DB.xp_to_next(data["level"]); data["level"] += 1; lvl = true
	while data["class_xp"] >= DB.class_xp_to_next(data["class_level"]):
		data["class_xp"] -= DB.class_xp_to_next(data["class_level"]); data["class_level"] += 1; clvl = true
	if lvl:
		recalc(true)
		zone().fx("burst", global_position + Vector3.UP, 2.5, Color(1, 0.85, 0.3), 0.8)
		Game.toast("Новый уровень: %d! Очков талантов: %d" % [data["level"], DB.free_points(data)])
		zone().save()
	if clvl:
		recalc()
		var extra := ""
		for s in cls.skills:
			if int(s.unlock) == data["class_level"]: extra = " Открыто умение «%s»!" % s.name
		Game.toast("Мастерство класса «%s»: %d.%s" % [cls.name, data["class_level"], extra], 3.5)

# ---------------- умения ----------------
func get_skill(slot: int):
	if slot < 3: return cls.skills[slot]
	var a := DB.get_asc(data["ascendancy"])
	return null if a.is_empty() else a.skill

## "" если доступно, иначе короткая причина для кнопки.
func lock_reason(slot: int) -> String:
	if slot < 3:
		var need := int(cls.skills[slot].unlock)
		return "" if data["class_level"] >= need else "мастер.\n%d" % need
	return "" if get_skill(3) != null else "ур. %d+" % DB.ASC_LEVEL

func max_cooldown(slot: int) -> float:
	var s = get_skill(slot)
	if s == null: return 0.0
	if slot == 0: return cls.interval / (stats.attack_speed * (1.5 if rage_timer > 0 else 1.0))
	return s.cd * (1.0 - stats.cdr)

func use_potion() -> void:
	if dead: return
	if data["potions"] <= 0:
		Game.toast("Нет зелий")
		return
	if hp >= stats.max_hp - 1:
		Game.toast("Здоровье полное")
		return
	data["potions"] -= 1
	heal(stats.max_hp * 0.45)
	zone().fx("burst", global_position + Vector3.UP, 1.5, Color(1, 0.2, 0.3), 0.5)

func try_use(slot: int) -> bool:
	if dead or cooldowns[slot] > 0: return false
	if lock_reason(slot) != "":
		if slot > 0:
			Game.toast("Умение пути откроется после превращения (дерево талантов)" if slot == 3 else "Нужно мастерство класса %d" % int(cls.skills[slot].unlock))
		return false
	var s = get_skill(slot)
	if mp < s.mana:
		Game.toast("Не хватает маны", 1.0)
		return false
	mp -= s.mana
	cooldowns[slot] = max_cooldown(slot)
	_execute(s)
	return true

func find_target(rng: float):
	var best = null
	var best_score := INF
	var f := forward()
	for e in zone().enemies:
		if not e.alive: continue
		var d: Vector3 = U.flat(e.global_position - global_position)
		var dist := d.length()
		if dist > rng: continue
		var score := dist * (1.5 - f.dot(d.normalized()) * 0.5)
		if score < best_score:
			best_score = score; best = e
	return best

func roll_damage(mult: float, spell: bool) -> Array:
	var dmg: float = stats.damage * stats.dmg_mult * mult * (1.5 if rage_timer > 0 else 1.0) * randf_range(0.9, 1.1)
	if spell or cls.spell: dmg *= stats.spell_mult
	var crit: bool = randf() < stats.crit
	if crit: dmg *= stats.crit_mult
	return [dmg, crit]

func hit(e, mult: float, spell := false, force_crit := false) -> void:
	if e == null or not is_instance_valid(e) or not e.alive: return
	var r := roll_damage(mult, spell)
	var dmg: float = r[0]
	var crit: bool = r[1]
	if force_crit and not crit:
		dmg *= stats.crit_mult; crit = true
	e.take_damage(dmg, crit)
	if stats.leech > 0: heal(dmg * stats.leech)

func hit_area(center: Vector3, radius: float, mult: float, spell: bool, extra := Callable()) -> void:
	for e in zone().enemies.duplicate():
		if not is_instance_valid(e) or not e.alive: continue
		if U.flat_dist(e.global_position, center) <= radius + e.radius:
			hit(e, mult, spell)
			if extra.is_valid() and is_instance_valid(e) and e.alive: extra.call(e)

func _dir_to(origin: Vector3, t) -> Vector3:
	if t == null: return forward()
	var d: Vector3 = t.global_position + Vector3.UP * 0.8 - origin
	d.y = 0
	return d.normalized()

func _execute(s: Dictionary) -> void:
	var z = zone()
	var target = find_target(maxf(s.range, cls.range) + 2)
	if target != null and s.kind != "dash": face_towards(target.global_position)
	visual.play_attack()
	var origin := global_position + Vector3.UP * 1.3 + forward() * 0.6
	match s.kind:
		"melee":
			for e in z.enemies.duplicate():
				if not e.alive: continue
				var d: Vector3 = U.flat(e.global_position - global_position)
				if d.length() <= cls.range + e.radius and rad_to_deg(forward().angle_to(d)) < 70:
					hit(e, 1.0)
			z.fx("burst", global_position + forward() * 1.2 + Vector3.UP, 1.3, Color.WHITE, 0.15)
		"projectile":
			Projectile.fire(z, origin, _dir_to(origin, target), 22.0, s.range, s.color, 0.25, true, func(e): hit(e, 1.0))
		"spin":
			hit_area(global_position, s.radius, s.mult, false)
			z.fx("ring", global_position, s.radius, s.color, 0.35)
		"dash":
			var dir: Vector3 = U.flat(target.global_position - global_position) if target != null else forward()
			dir = dir.normalized()
			face_towards(global_position + dir)
			_dash_vel = dir * s.range / 0.22; _dash_time = 0.22
			var a := global_position
			var b: Vector3 = a + dir * s.range
			for e in z.enemies.duplicate():
				if e.alive and _dist_to_segment(e.global_position, a, b) < s.radius + e.radius: hit(e, s.mult)
			z.fx("burst", b + Vector3.UP, 2.0, s.color, 0.3)
		"volley":
			var base := _dir_to(origin, target)
			for i in range(-2, 3):
				Projectile.fire(z, origin, base.rotated(Vector3.UP, deg_to_rad(i * 12)), 22.0, s.range, s.color, 0.22, true, func(e): hit(e, s.mult))
		"arrow_rain":
			var pos: Vector3 = target.global_position if target != null else global_position + forward() * 8
			z.fx("ring", pos, s.radius, s.color, 0.6)
			await get_tree().create_timer(0.4, false).timeout
			hit_area(pos, s.radius, s.mult, false)
			z.fx("burst", pos + Vector3.UP, s.radius, s.color, 0.3)
		"fireball":
			Projectile.fire(z, origin, _dir_to(origin, target), 16.0, s.range, s.color, 0.5, true, func(e):
				var p: Vector3 = e.global_position
				hit_area(p, s.radius, s.mult, true)
				z.fx("burst", p + Vector3.UP, s.radius, s.color, 0.4))
		"frost_nova":
			hit_area(global_position, s.radius, s.mult, true, func(e): e.slow(0.4, 3.0))
			z.fx("ring", global_position, s.radius, s.color, 0.45)
		"rage":
			rage_timer = 8.0
			z.fx("burst", global_position + Vector3.UP, 3.0, s.color, 0.6)
			Game.toast("ЯРОСТЬ!", 1.2)
		"holy_shield":
			shield_timer = 6.0
			heal(stats.max_hp * 0.35)
			z.fx("burst", global_position + Vector3.UP, 2.5, s.color, 0.8)
		"shadow_strike":
			if target == null:
				Game.toast("Нет цели", 1.0); cooldowns[3] = 0.5; mp += s.mana
				return
			var behind: Vector3 = target.global_position - target.global_basis.z * 1.3
			behind.y = global_position.y
			z.fx("burst", global_position + Vector3.UP, 1.5, s.color, 0.3)
			teleport(behind)
			face_towards(target.global_position)
			hit(target, s.mult, false, true)
			z.fx("burst", behind + Vector3.UP, 1.5, s.color, 0.3)
		"meteor":
			var pos: Vector3 = target.global_position if target != null else global_position + forward() * 8
			z.fx("telegraph", pos, s.radius, Color.RED, 0.9)
			await get_tree().create_timer(0.9, false).timeout
			hit_area(pos, s.radius, s.mult, true)
			z.fx("burst", pos + Vector3.UP, s.radius, s.color, 0.6)
		"summon":
			for i in 2:
				Minion.spawn(z, global_position + global_basis.x * (-1.5 if i == 0 else 1.5), self, s.mult, 25.0)
		"beast_roar":
			hit_area(global_position, s.radius, s.mult, false, func(e): e.stun(2.0))
			heal(stats.max_hp * 0.15)
			z.fx("ring", global_position, s.radius, s.color, 0.5)

static func _dist_to_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	p.y = 0; a.y = 0; b.y = 0
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0, 1)
	return p.distance_to(a + ab * t)
