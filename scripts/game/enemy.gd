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
var _kb := Vector3.ZERO
var brain   # BossBrain для босса
var damage_mult := 1.0
var speed_mult := 1.0
var hits_taken := 0

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
	e.global_position = Vector3(pos.x, z.ground_y(pos), pos.z)
	e.rotation.y = randf() * TAU
	e._build_model()
	if not e.def.boss: U.set_view_range(e, Game.view_distance * 0.85)
	if e.def.boss:
		e.brain = BossBrain.new()
		e.brain.setup(e)
	z.enemies.append(e)
	return e

var display_name: String:
	get: return "%s (%d)" % [def.name, level]

func _damage() -> float:
	return def.dmg * (1 + (level - 1) * 0.18) * damage_mult

func _build_model() -> void:
	match kind:
		"slime":
			model = MobModel.new(); add_child(model)
			model.setup("slime", {"scale": 1.0 + (level - 1) * 0.04})
			model.walk_ref = 1.2; model.run_ref = 2.5
		"wolf":
			model = MobModel.new(); add_child(model)
			model.setup("wolf", {"tint": Color(0.82, 0.78, 0.72)})
			model.walk_ref = 2.0; model.run_ref = 5.5
		"skeleton", "skeleton_archer":
			model = MobModel.new(); add_child(model)
			var archer: bool = def.ranged
			model.setup("skeleton", {"tint": Color(0.82, 0.8, 0.74) if archer else Color(0.95, 0.92, 0.85), "emission": Color(0.3, 0.9, 1.0)})
			model.walk_ref = 2.0; model.run_ref = 4.0
			if archer:
				model.attach("R.DownLeg.001", "props/bow", Vector3(0, 0.12, 0), Vector3(0, 0, 0), 0.5)
			else:
				model.attach("R.DownLeg.001", "props/sword2", Vector3(0, 0.1, 0), Vector3(180, 0, 0), 0.36)
				model.attach("L.DownLeg.001", "props/shield_round", Vector3(0, 0.1, 0), Vector3(0, 90, 0), 0.22)
		"goblin", "troll":
			model = CharVisual.new(); add_child(model)
			model.build({}, "warrior", "", kind)
		_:
			model = MobModel.new(); add_child(model)
			model.setup("slime")

func _model_action(a: String) -> void:
	if model and model.has_method("play_action"): model.play_action(a)

func take_damage(dmg: float, crit: bool) -> void:
	if not alive: return
	if brain and brain.invulnerable: 
		zone.float_text(global_position + Vector3.UP * 4.5, "Неуязвим", Color(0.8, 0.8, 0.8))
		return
	hp -= dmg
	hits_taken += 1
	_flash = 0.12
	_aggro = true; _returning = false
	if model is MobModel: model.hit_react()
	elif model is CharVisual and not model.is_acting() and not def.boss: model.play_action("hit")
	zone.damage_number(global_position + Vector3.UP * (4.5 if def.boss else 2.0), dmg, crit, false)
	if hp <= 0: _die()

## Отбрасывание при попадании (босс почти не сдвигается) + «упругий» отклик модели
func knockback(dir: Vector3, force: float) -> void:
	if not alive: return
	var k := 0.08 if def.boss else (0.5 if kind in ["troll", "goblin"] else 1.0)
	_kb += U.flat(dir).normalized() * force * k
	if model:
		var base := model.scale
		var tw := create_tween()
		tw.tween_property(model, "scale", Vector3(base.x * 1.08, base.y * 0.92, base.z * 1.08), 0.05)
		tw.tween_property(model, "scale", base, 0.12)

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
	# дымка/искры души при гибели
	CombatFX.burst(zone.fx_root, global_position + Vector3.UP * (2.0 if def.boss else 0.8), Color(0.85, 0.85, 1.0, 0.7), 16 if not def.boss else 40, 2.5, 0.16, 0.9, Vector3.UP, 50, 1.5)
	if on_death.is_valid(): on_death.call(self)
	if model and model.has_method("set_dead"): model.set_dead(true)
	# тело остаётся на земле, затем уходит под землю
	var tw := create_tween()
	tw.tween_interval(2.4 if def.boss else 1.8)
	tw.tween_property(self, "position:y", -1.2 if not def.boss else -3.0, 1.2)
	tw.tween_callback(queue_free)

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
	if _kb.length_squared() > 0.01:
		var np := global_position + _kb * delta
		np.y = zone.ground_y(np)
		global_position = np
		_kb = _kb * exp(-delta * 9.0)
	if brain:
		brain.update(delta)
		if brain.busy: return
	if _stun_timer > 0:
		_stun_timer -= delta
		return
	var speed: float = def.speed * _slow_factor * speed_mult
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
		if to.length() > def.range * 0.9:
			_move_towards(target.global_position, speed, delta)
		elif _attack_timer <= 0:
			_attack_timer = def.interval / speed_mult
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
	_model_action("attack")
	if def.ranged:
		var origin := global_position + Vector3.UP * 1.3 + global_basis.z * 0.4
		var dir := U.flat(target.global_position - global_position).normalized()
		Projectile.fire(zone, origin, dir, 13.0, def.range + 4, Color(0.6, 0.9, 1), 0.25, false, Callable(), _damage())
	else:
		var t := target
		await get_tree().create_timer(0.25 if not def.boss else 0.45, false).timeout
		if not alive or t == null or not is_instance_valid(t): return
		if U.flat_dist(t.global_position, global_position) <= def.range + 0.6:
			_deal_to(t, _damage())

func _deal_to(t: Node3D, dmg: float) -> void:
	if t == null or not is_instance_valid(t): return
	if t is Player: t.take_damage(dmg, global_position)
	elif t.has_method("take_damage"): t.take_damage(dmg)

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
	np.y = zone.ground_y(np)
	global_position = np
	_face(d, delta)

func _face(d: Vector3, delta: float) -> void:
	if d.length_squared() < 0.001: return
	rotation.y = lerp_angle(rotation.y, atan2(d.x, d.z), minf(1.0, delta * 8))

func _animate(delta: float) -> void:
	if _lunge > 0: _lunge -= delta
	if _flash > 0: _flash -= delta
	if model:
		model.rotation.z = sin(Time.get_ticks_msec() * 0.02) * 0.14 if _stun_timer > 0 else 0.0
