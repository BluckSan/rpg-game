extends Node3D
class_name Enemy
## Враг: блуждание, погоня, атака, возврат домой (поводок), смерть с наградой. Босс — удар по области с предупреждением.

var kind: String
var def: Dictionary
var level := 1
var hp := 1.0
var max_hp := 1.0
var alive := true
var radius := 0.5
var home := Vector3.ZERO
var on_death: Callable
var zone
var model: Node3D
var target: Node3D

var _wander_target := Vector3.ZERO
var _attack_timer := 0.0
var _wander_timer := 0.0
var _slow_timer := 0.0
var _slow_factor := 1.0
var _stun_timer := 0.0
var _boss_timer := 5.0
var _aggro := false
var _returning := false
var _anim := 0.0
var _lunge := 0.0
var _flash := 0.0

static func spawn(z, k: String, lvl: int, pos: Vector3, parent: Node) -> Enemy:
	var e := Enemy.new()
	e.zone = z
	e.kind = k
	e.def = DB.ENEMIES[k]
	e.level = lvl
	e.radius = e.def.radius
	e.max_hp = e.def.hp * (1 + (lvl - 1) * 0.22)
	e.hp = e.max_hp
	e.home = pos
	e._wander_target = pos
	parent.add_child(e)
	e.global_position = pos
	e.rotation.y = randf() * TAU
	e._build_model()
	z.enemies.append(e)
	return e

var display_name: String:
	get: return "%s (%d)" % [def.name, level]

func _damage() -> float:
	return def.dmg * (1 + (level - 1) * 0.18)

func _eyes(y: float, z: float, size: float, col: Color, glow := 0.0) -> void:
	for s in [-1, 1]:
		U.prim("sphere", model, Vector3(s * size * 1.2, y, z), Vector3.ONE * size, col, 0.3, glow)

func _build_model() -> void:
	model = Node3D.new(); add_child(model)
	var c: Color = def.color
	match kind:
		"slime":
			U.prim("sphere", model, Vector3(0, 0.45, 0), Vector3(1.1, 0.85, 1.1), c, 0.2)
			_eyes(0.65, 0.48, 0.18, Color.BLACK)
		"wolf":
			U.prim("box", model, Vector3(0, 0.75, 0), Vector3(0.55, 0.55, 1.3), c)
			U.prim("box", model, Vector3(0, 0.95, 0.8), Vector3(0.45, 0.42, 0.5), c)
			U.prim("box", model, Vector3(0, 0.85, 1.1), Vector3(0.25, 0.2, 0.3), c * 0.8)
			for s in [-1, 1]: U.prim("box", model, Vector3(s * 0.15, 1.22, 0.75), Vector3(0.1, 0.18, 0.08), c * 0.7)
			_eyes(1.02, 1.05, 0.12, Color(1, 0.8, 0.2), 2.0)
			for x in [-0.2, 0.2]:
				for zz in [-0.45, 0.45]:
					U.prim("box", model, Vector3(x, 0.25, zz), Vector3(0.14, 0.5, 0.14), c * 0.85)
			U.prim("box", model, Vector3(0, 0.85, -0.8), Vector3(0.12, 0.12, 0.5), c)
		"skeleton", "skeleton_archer":
			U.prim("capsule", model, Vector3(0, 1.15, 0), Vector3(0.35, 0.35, 0.22), c)
			U.prim("sphere", model, Vector3(0, 1.75, 0), Vector3.ONE * 0.36, c)
			_eyes(1.78, 0.15, 0.08, Color(0.3, 0.9, 1), 3.0)
			for s in [-0.12, 0.12]: U.prim("capsule", model, Vector3(s, 0.45, 0), Vector3(0.1, 0.45, 0.1), c)
			for s in [-0.28, 0.28]: U.prim("capsule", model, Vector3(s, 1.15, 0.05), Vector3(0.08, 0.35, 0.08), c)
			if def.ranged: U.prim("cylinder", model, Vector3(-0.32, 1.1, 0.25), Vector3(0.04, 0.5, 0.04), Color(0.3, 0.2, 0.1))
			else: U.prim("box", model, Vector3(0.32, 1.0, 0.4), Vector3(0.05, 0.05, 0.8), Color(0.6, 0.6, 0.62), 0.3)
		"goblin":
			U.prim("sphere", model, Vector3(0, 1.0, 0), Vector3(1.1, 1.1, 0.9), c)
			U.prim("sphere", model, Vector3(0, 1.75, 0.15), Vector3(0.55, 0.5, 0.5), c)
			for s in [-1, 1]:
				U.prim("box", model, Vector3(s * 0.35, 1.85, 0.1), Vector3(0.35, 0.08, 0.1), c * 0.9).rotation_degrees.z = s * 20
				U.prim("capsule", model, Vector3(s * 0.28, 0.3, 0), Vector3(0.25, 0.3, 0.25), c * 0.8)
			_eyes(1.8, 0.4, 0.1, Color(1, 0.3, 0.1), 2.0)
			U.prim("cylinder", model, Vector3(0.65, 1.0, 0.3), Vector3(0.16, 0.55, 0.16), Color(0.4, 0.25, 0.1)).rotation_degrees.x = 60
		"troll":
			U.prim("sphere", model, Vector3(0, 2.2, 0), Vector3(2.4, 2.6, 2.0), c)
			U.prim("sphere", model, Vector3(0, 3.7, 0.5), Vector3(1.1, 1.0, 1.0), c * 0.95)
			for s in [-1, 1]:
				U.prim("capsule", model, Vector3(s * 1.4, 2.0, 0.2), Vector3(0.6, 1.2, 0.6), c * 0.9)
				U.prim("capsule", model, Vector3(s * 0.6, 0.7, 0), Vector3(0.7, 0.75, 0.7), c * 0.8)
				U.prim("box", model, Vector3(s * 0.25, 3.45, 0.95), Vector3(0.1, 0.3, 0.1), Color(0.95, 0.9, 0.8))
			_eyes(3.85, 0.95, 0.18, Color(1, 0.2, 0.1), 3.0)
			U.prim("box", model, Vector3(0, 1.4, 0), Vector3(2.2, 0.5, 1.9), Color(0.35, 0.22, 0.1))

func take_damage(dmg: float, crit: bool) -> void:
	if not alive: return
	hp -= dmg
	_flash = 0.12
	_aggro = true; _returning = false
	zone.damage_number(global_position + Vector3.UP * (4.5 if def.boss else 2.0), dmg, crit, false)
	if hp <= 0: _die()

func slow(factor: float, t: float) -> void:
	_slow_factor = factor; _slow_timer = t

func stun(t: float) -> void:
	_stun_timer = t * 0.3 if def.boss else t

func _die() -> void:
	hp = 0
	alive = false
	zone.enemies.erase(self)
	var p: Player = zone.player
	if p:
		p.data["kills"] += 1
		var diff: int = p.data["level"] - level
		var mult := maxf(0.2, 1.0 - (diff - 4) * 0.2) if diff > 4 else 1.0
		p.gain_xp(maxi(1, int(round(def.xp * (1 + (level - 1) * 0.25) * mult))))
	Loot.drop_for(zone, self)
	zone.fx("burst", global_position + Vector3.UP * 0.8, radius * 2.2, def.color, 0.4)
	if on_death.is_valid(): on_death.call(self)
	queue_free()

func _choose_target() -> Node3D:
	var best: Node3D = null
	var best_d: float = def.aggro * (2.2 if _aggro else 1.0)
	var p: Player = zone.player
	if p and not p.dead:
		var d := U.flat_dist(p.global_position, global_position)
		if d < best_d:
			best_d = d; best = p
	for m in zone.minions:
		var d := U.flat_dist(m.global_position, global_position)
		if d < best_d * 0.8:
			best_d = d; best = m
	return best

func _process(delta: float) -> void:
	if not alive: return
	if _attack_timer > 0: _attack_timer -= delta
	if _slow_timer > 0:
		_slow_timer -= delta
		if _slow_timer <= 0: _slow_factor = 1.0
	_animate(delta)
	if _stun_timer > 0:
		_stun_timer -= delta
		return
	var speed: float = def.speed * _slow_factor
	var home_dist := U.flat_dist(global_position, home)
	if home_dist > (22.0 if def.boss else 28.0):
		_returning = true; _aggro = false
	if _returning:
		_move_towards(home, speed * 1.5, delta)
		hp = minf(max_hp, hp + max_hp * 0.25 * delta)
		if home_dist < 1.5: _returning = false
		return
	target = _choose_target()
	if target:
		_aggro = true
		var to := U.flat(target.global_position - global_position)
		_face(to, delta)
		if def.boss: _boss_logic(delta)
		if to.length() > def.range * 0.9:
			_move_towards(target.global_position, speed, delta)
		elif _attack_timer <= 0:
			_attack_timer = def.interval
			_attack()
	else:
		_aggro = false
		_wander_timer -= delta
		if _wander_timer <= 0:
			_wander_timer = randf_range(2.5, 6.0)
			var r := Vector2.from_angle(randf() * TAU) * randf() * 6.0
			_wander_target = home + Vector3(r.x, 0, r.y)
		if U.flat_dist(_wander_target, global_position) > 0.5:
			_move_towards(_wander_target, speed * 0.4, delta)

func _attack() -> void:
	_anim = 0; _lunge = 0.25
	if def.ranged:
		var origin := global_position + Vector3.UP * 1.3 + global_basis.z * 0.4
		var dir := U.flat(target.global_position - global_position).normalized()
		Projectile.fire(zone, origin, dir, 13.0, def.range + 4, Color(0.6, 0.9, 1), 0.25, false, Callable(), _damage())
	else:
		_deal_to(target, _damage())

func _deal_to(t: Node3D, dmg: float) -> void:
	if t == null or not is_instance_valid(t): return
	if t is Player: t.take_damage(dmg, global_position)
	elif t.has_method("take_damage"): t.take_damage(dmg)

func _boss_logic(delta: float) -> void:
	_boss_timer -= delta
	if _boss_timer > 0 or target == null: return
	_boss_timer = randf_range(5.0, 7.5)
	var pos := target.global_position
	var r := 4.5
	zone.fx("telegraph", pos, r, Color.RED, 1.3)
	await get_tree().create_timer(1.3, false).timeout
	if not alive or not is_instance_valid(self): return
	zone.fx("ring", pos, r, Color(0.6, 0.4, 0.2), 0.4)
	var p: Player = zone.player
	if p and U.flat_dist(p.global_position, pos) < r: p.take_damage(_damage() * 1.8, pos)
	for m in zone.minions.duplicate():
		if is_instance_valid(m) and U.flat_dist(m.global_position, pos) < r: m.take_damage(_damage() * 1.8)

func _move_towards(p: Vector3, speed: float, delta: float) -> void:
	var d := U.flat(p - global_position)
	if d.length_squared() < 0.01: return
	var step := d.normalized() * speed * delta
	for o in zone.enemies:
		if o == self: continue
		var away := U.flat(global_position - o.global_position)
		var mn: float = radius + o.radius
		if away.length_squared() < mn * mn and away.length_squared() > 0.0001:
			step += away.normalized() * delta * 2.0
	var np := global_position + step
	np.y = 0
	global_position = np
	_face(d, delta)

func _face(d: Vector3, delta: float) -> void:
	if d.length_squared() < 0.001: return
	rotation.y = lerp_angle(rotation.y, atan2(d.x, d.z), minf(1.0, delta * 8))

func _animate(delta: float) -> void:
	_anim += delta * 8
	var sq := sin(_anim) * 0.12 if kind == "slime" else 0.0
	var bob := absf(sin(_anim)) * 0.06 if kind != "slime" else 0.0
	if _lunge > 0: _lunge -= delta
	var fwd := sin(_lunge / 0.25 * PI) * 0.5 if _lunge > 0 else 0.0
	var fl := 1.12 if _flash > 0 else 1.0
	if _flash > 0: _flash -= delta
	model.scale = Vector3((1 + sq) * fl, (1 - sq) * fl, (1 + sq) * fl)
	model.position = Vector3(0, bob, fwd)
	model.rotation.z = sin(Time.get_ticks_msec() * 0.02) * 0.14 if _stun_timer > 0 else 0.0
