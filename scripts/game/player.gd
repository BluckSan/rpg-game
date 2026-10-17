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
## Комбо базовой атаки: 3 удара на класс (последний — сильный, с замахом)
const COMBO_WINDOW := 1.2
const COMBOS := {
	"warrior": [
		{"anim": "attack_a", "speed": 1.5, "windup": 0.16, "mult": 1.0, "arc": 75.0, "reach": 0.0, "knock": 2.5, "stop": 0.045, "shake": 0.0, "trail": 0.32},
		{"anim": "attack_b", "speed": 1.5, "windup": 0.16, "mult": 1.15, "arc": 85.0, "reach": 0.2, "knock": 3.0, "stop": 0.05, "shake": 0.06, "trail": 0.32},
		{"anim": "attack_c", "speed": 1.2, "windup": 0.3, "mult": 1.9, "arc": 130.0, "reach": 0.7, "knock": 7.0, "stop": 0.09, "shake": 0.28, "trail": 0.5, "cd": 1.35}],
	"archer": [
		{"anim": "bow_shoot", "speed": 1.7, "windup": 0.14, "mult": 1.0, "arrows": 1, "knock": 1.5, "stop": 0.03},
		{"anim": "bow_shoot", "speed": 1.7, "windup": 0.14, "mult": 1.05, "arrows": 1, "knock": 1.5, "stop": 0.03},
		{"anim": "bow_shoot", "speed": 1.0, "windup": 0.32, "mult": 1.6, "arrows": 3, "pierce": true, "knock": 4.0, "stop": 0.06, "shake": 0.1, "cd": 1.3}],
	"mage": [
		{"anim": "cast", "speed": 1.6, "windup": 0.15, "mult": 1.0, "knock": 1.5, "stop": 0.03},
		{"anim": "cast", "speed": 1.6, "windup": 0.15, "mult": 1.05, "knock": 1.5, "stop": 0.03},
		{"anim": "cast_enter", "speed": 1.2, "windup": 0.32, "mult": 1.7, "explode": 2.6, "knock": 5.0, "stop": 0.07, "shake": 0.18, "cd": 1.3}]}
var combo_step := 0          # индекс следующего удара
var combo_timer := 0.0
var combo_count := 0         # всего выполнено ударов (для тестов)
var last_combo_index := -1
## Кувырок: рывок с неуязвимостью
const ROLL_TIME := 0.42
const ROLL_SPEED := 11.0
const ROLL_CD := 0.9
var roll_cd := 0.0
var invuln := 0.0
var _roll_time := 0.0
var _roll_dir := Vector3.FORWARD
var _last_move := Vector3.ZERO
var rolls := 0
var dodged := 0
## Прыжок: скорость, «время койота» и буфер нажатия
const JUMP_VELOCITY := 7.6
const GRAVITY := 20.0
const COYOTE_TIME := 0.14
const JUMP_BUFFER := 0.15
var _coyote := 0.0
var _jump_buffer := 0.0
var _was_on_floor := true
var jumps := 0
## Для тестов: принудительное направление движения в мировых координатах
var force_move := Vector3.ZERO
var god_mode := false

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
	data["look"] = CharAssets.normalize_look(data["look"])
	visual.build(data["look"], data["class"], data["ascendancy"])
	visual.attack_speed = 1.0

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
	if roll_cd > 0: roll_cd -= delta
	if invuln > 0: invuln -= delta
	if combo_timer > 0:
		combo_timer -= delta
		if combo_timer <= 0: combo_step = 0
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
	if force_move != Vector3.ZERO: move = Vector3(force_move.x, 0, force_move.z)
	if move.length() > 1: move = move.normalized()
	_last_move = move
	var v: Vector3
	if _roll_time > 0:
		_roll_time -= delta
		v = _roll_dir * ROLL_SPEED * clampf(0.45 + _roll_time / ROLL_TIME, 0.5, 1.2)
		rotation.y = atan2(_roll_dir.x, _roll_dir.z)
	elif _dash_time > 0:
		_dash_time -= delta
		v = _dash_vel
	else:
		v = move * stats.move_speed
		if move.length() > 0.05:
			rotation.y = lerp_angle(rotation.y, atan2(move.x, move.z), minf(1.0, delta * 12))
	velocity.x = v.x; velocity.z = v.z
	# --- гравитация и прыжок ---
	var on_floor := is_on_floor()
	if on_floor:
		_coyote = COYOTE_TIME
		if velocity.y < 0: velocity.y = -2.0
	else:
		_coyote -= delta
		velocity.y -= GRAVITY * delta
	if Input.is_key_pressed(KEY_J): request_jump()
	if Input.is_key_pressed(KEY_K): request_roll()
	if _jump_buffer > 0:
		_jump_buffer -= delta
		if _coyote > 0 and _dash_time <= 0:
			velocity.y = JUMP_VELOCITY
			_coyote = 0; _jump_buffer = 0
			jumps += 1
			visual.play_action("jump")
	move_and_slide()
	var now_floor := is_on_floor()
	if now_floor and not _was_on_floor and velocity.y <= 0.1: visual.play_action("land")
	_was_on_floor = now_floor
	visual.in_air = not now_floor and (velocity.y > 1.0 or _coyote < -0.15)
	if global_position.y < -10: teleport(zone().spawn_point)
	if attack_held or Input.is_key_pressed(KEY_SPACE): try_use(0)

## Нажатие прыжка (кнопка HUD / клавиатура). Сработает в течение буфера, если персонаж на земле или только что сошёл с края.
func request_jump() -> void:
	if dead: return
	_jump_buffer = JUMP_BUFFER

## Кувырок/уклонение (кнопка HUD, клавиша K): короткая неуязвимость, уходит из-под ударов
func request_roll() -> bool:
	if dead or roll_cd > 0 or _roll_time > 0: return false
	_roll_dir = _last_move.normalized() if _last_move.length() > 0.2 else forward()
	_roll_dir.y = 0
	_roll_time = ROLL_TIME
	invuln = ROLL_TIME * 0.9
	roll_cd = ROLL_CD
	rolls += 1
	visual.play_action("roll")
	CombatFX.burst(zone().fx_root, global_position + Vector3.UP * 0.2, Color(0.8, 0.7, 0.55, 0.6), 10, 2.0, 0.18, 0.5, Vector3.UP, 80, 0.5)
	return true

## Отбрасывание игрока (таран босса)
func knockback(dir: Vector3, force: float) -> void:
	_dash_vel = U.flat(dir).normalized() * force
	_dash_time = 0.2

func is_rolling() -> bool:
	return _roll_time > 0

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
	visual.set_dead(false)
	recalc(true)

# ---------------- урон и опыт ----------------
func take_damage(dmg: float, _from: Vector3) -> void:
	if dead or god_mode: return
	if invuln > 0:
		dodged += 1
		zone().float_text(global_position + Vector3.UP * 2.2, "Уклонение!", Color(0.6, 0.9, 1.0))
		return
	var dr: float = stats.dr + (0.5 if shield_timer > 0 else 0.0)
	var final := dmg * (1.0 - clampf(dr, 0, 0.85))
	hp -= final
	zone().damage_number(global_position + Vector3.UP * 2.2, final, false, true)
	if hp <= 0:
		hp = 0; dead = true
		visual.set_dead(true)
		zone().on_player_died()
	elif final > stats.max_hp * 0.08:
		visual.play_action("hit")
		zone().shake(0.25 if final > stats.max_hp * 0.2 else 0.12)

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
		var h = zone().hud
		if h and h.has_method("level_up"): h.level_up(data["level"], DB.free_points(data))
		else: Game.toast("Новый уровень: %d! Очков талантов: %d" % [data["level"], DB.free_points(data)])
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
	visual.play_action("drink")
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

func hit(e, mult: float, spell := false, force_crit := false, fb := {}) -> void:
	if e == null or not is_instance_valid(e) or not e.alive: return
	var r := roll_damage(mult, spell)
	var dmg: float = r[0]
	var crit: bool = r[1]
	if force_crit and not crit:
		dmg *= stats.crit_mult; crit = true
	var dir := U.flat(e.global_position - global_position).normalized()
	var z = zone()
	CombatFX.hit(z.fx_root, e.global_position + Vector3.UP * (2.2 if e.def.boss else 0.9), e.kind, crit, dir)
	e.take_damage(dmg, crit)
	if is_instance_valid(e):
		e.knockback(dir, float(fb.get("knock", 1.5)) * (1.4 if crit else 1.0))
	z.hit_stop(float(fb.get("stop", 0.03)) * (1.6 if crit else 1.0))
	var sh := float(fb.get("shake", 0.0)) + (0.12 if crit else 0.0)
	if sh > 0: z.shake(sh)
	if stats.leech > 0: heal(dmg * stats.leech)

func hit_area(center: Vector3, radius: float, mult: float, spell: bool, extra := Callable(), fb := {"knock": 4.0, "stop": 0.05, "shake": 0.15}) -> void:
	var fbl: Dictionary = fb.duplicate()
	for e in zone().enemies.duplicate():
		if not is_instance_valid(e) or not e.alive: continue
		if U.flat_dist(e.global_position, center) <= radius + e.radius:
			hit(e, mult, spell, false, fbl.duplicate())
			fbl["stop"] = 0.0; fbl["shake"] = 0.0
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
	var aspd: float = stats.attack_speed * (1.5 if rage_timer > 0 else 1.0)
	visual.attack_speed = aspd
	if s.kind in ["melee", "projectile"]:
		_combo_attack(s, target, aspd)
		return
	visual.play_action(s.kind)
	var origin := global_position + Vector3.UP * 1.3 + forward() * 0.6
	match s.kind:
		"spin":
			CombatFX.slash_arc(z.fx_root, global_position, forward(), s.radius, 360, s.color, 0.35, 0.9)
			await get_tree().create_timer(0.12, false).timeout
			if dead: return
			hit_area(global_position, s.radius, s.mult, false, Callable(), {"knock": 6.0, "stop": 0.07, "shake": 0.25})
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
			await get_tree().create_timer(0.15, false).timeout
			if dead: return
			var base := _dir_to(origin, target)
			for i in range(-2, 3):
				Projectile.fire(z, origin, base.rotated(Vector3.UP, deg_to_rad(i * 12)), 24.0, s.range, s.color, 0.22, true, func(e): hit(e, s.mult)).add_trail(s.color, false)
		"arrow_rain":
			var pos: Vector3 = target.global_position if target != null else global_position + forward() * 8
			z.fx("ring", pos, s.radius, s.color, 0.6)
			await get_tree().create_timer(0.4, false).timeout
			hit_area(pos, s.radius, s.mult, false)
			z.fx("burst", pos + Vector3.UP, s.radius, s.color, 0.3)
		"fireball":
			CombatFX.cast_glow(visual.tip_node(), s.color, 0.4, 0.5)
			await get_tree().create_timer(0.2, false).timeout
			if dead: return
			origin = visual.tip_position()
			var fp := Projectile.fire(z, origin, _dir_to(origin, target), 16.0, s.range, s.color, 0.5, true, func(e):
				var p: Vector3 = e.global_position
				hit_area(p, s.radius, s.mult, true)
				CombatFX.burst(z.fx_root, p + Vector3.UP, Color(1, 0.6, 0.2), 30, 8.0, 0.12, 0.6, Vector3.UP, 90, -6)
				z.shake(0.3)
				z.fx("burst", p + Vector3.UP, s.radius, s.color, 0.4))
			fp.add_trail(s.color, true)
		"frost_nova":
			CombatFX.burst(z.fx_root, global_position + Vector3.UP * 0.3, Color(0.7, 0.95, 1.0), 40, 9.0, 0.1, 0.6, Vector3.UP, 95, -2)
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

## Базовая атака: цепочка из трёх ударов. Замах (windup) — урон наносится не сразу, а в момент удара в анимации.
func _combo_attack(s: Dictionary, target, aspd: float) -> void:
	var z = zone()
	var list: Array = COMBOS.get(data["class"], COMBOS["warrior"])
	var idx := combo_step
	var c: Dictionary = list[idx]
	last_combo_index = idx
	combo_step = (idx + 1) % list.size()
	combo_timer = COMBO_WINDOW / maxf(0.5, aspd) + float(c.windup)
	combo_count += 1
	cooldowns[0] = max_cooldown(0) * float(c.get("cd", 1.0))
	var spd: float = float(c.speed) * clampf(aspd, 0.7, 1.8)
	visual.play_anim(c.anim, spd, true, float(c.get("trail", 0.0)) / spd)
	if data["class"] == "mage":
		CombatFX.cast_glow(visual.tip_node(), s.color, float(c.windup) / aspd + 0.1, 0.35 if idx < 2 else 0.6)
	var fb := {"knock": c.get("knock", 1.5), "stop": c.get("stop", 0.03), "shake": c.get("shake", 0.0)}
	await get_tree().create_timer(float(c.windup) / clampf(aspd, 0.7, 1.8), false).timeout
	if dead or not is_inside_tree(): return
	if target != null and is_instance_valid(target) and target.alive: face_towards(target.global_position)
	var origin := global_position + Vector3.UP * 1.3 + forward() * 0.6
	match data["class"]:
		"warrior":
			var reach: float = cls.range + float(c.reach)
			var any := false
			for e in z.enemies.duplicate():
				if not is_instance_valid(e) or not e.alive: continue
				var d: Vector3 = U.flat(e.global_position - global_position)
				if d.length() <= reach + e.radius and rad_to_deg(forward().angle_to(d)) < float(c.arc) * 0.5 + 15:
					hit(e, float(c.mult), false, false, fb.duplicate())
					fb["stop"] = 0.0; fb["shake"] = 0.0
					any = true
			CombatFX.slash_arc(z.fx_root, global_position, forward(), reach + 0.3, float(c.arc), Color(1, 0.95, 0.8) if idx < 2 else Color(1, 0.7, 0.35), 0.2 if idx < 2 else 0.3)
			if idx == 2:
				z.fx("ring", global_position + forward() * 1.2, 1.6, Color(1, 0.8, 0.5), 0.3)
				if not any: z.shake(0.1)
		"archer":
			origin = visual.tip_position() if visual.weapon else origin
			var base := _dir_to(origin, target)
			var n := int(c.get("arrows", 1))
			for i in n:
				var ang := (i - (n - 1) / 2.0) * 7.0
				var pr := Projectile.fire(z, origin, base.rotated(Vector3.UP, deg_to_rad(ang)), 26.0 if idx < 2 else 30.0, s.range + 2, s.color if idx < 2 else Color(1, 0.85, 0.4), 0.22, true,
					func(e): hit(e, float(c.mult), false, false, fb.duplicate()))
				pr.pierce = bool(c.get("pierce", false))
				pr.add_trail(Color(1, 0.95, 0.75) if idx < 2 else Color(1, 0.75, 0.3), false)
			if idx == 2: z.shake(float(c.get("shake", 0.0)))
		_:
			origin = visual.tip_position()
			var ex := float(c.get("explode", 0.0))
			var col: Color = s.color if idx < 2 else Color(0.75, 0.55, 1.0)
			var pr := Projectile.fire(z, origin, _dir_to(origin, target), 20.0, s.range, col, 0.28 if idx < 2 else 0.45, true, func(e):
				if ex > 0:
					var p: Vector3 = e.global_position
					hit_area(p, ex, float(c.mult), true, Callable(), fb.duplicate())
					CombatFX.burst(z.fx_root, p + Vector3.UP, col, 26, 6.0, 0.1, 0.5, Vector3.UP, 90, -3)
					z.fx("burst", p + Vector3.UP, ex, col, 0.35)
				else:
					hit(e, float(c.mult), true, false, fb.duplicate()))
			pr.add_trail(col, true)

static func _dist_to_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	p.y = 0; a.y = 0; b.y = 0
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0, 1)
	return p.distance_to(a + ab * t)
