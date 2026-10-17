extends Node3D
class_name Projectile
## Снаряд. Попадание проверяется по расстоянию.

var zone
var dir := Vector3.FORWARD
var speed := 20.0
var max_dist := 15.0
var traveled := 0.0
var size := 0.25
var damage := 0.0
var from_player := true
var on_hit: Callable

static func fire(z, origin: Vector3, d: Vector3, spd: float, rng: float, c: Color, sz: float, player_owned: bool, cb: Callable, dmg := 0.0) -> Projectile:
	var p := Projectile.new()
	p.zone = z; p.dir = d.normalized(); p.speed = spd; p.max_dist = rng; p.size = sz
	p.from_player = player_owned; p.on_hit = cb; p.damage = dmg
	z.fx_root.add_child(p)
	p.global_position = origin
	var mi := U.prim("sphere", p, Vector3.ZERO, Vector3(sz, sz, sz * (3.0 if sz < 0.3 else 1.0)), c, 0.5, 2.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.rotation.y = atan2(p.dir.x, p.dir.z)
	return p

func _process(delta: float) -> void:
	var step := speed * delta
	global_position += dir * step
	traveled += step
	var pos := global_position
	if from_player:
		for e in zone.enemies:
			if e.alive and U.flat_dist(e.global_position, pos) < e.radius + size + 0.3:
				if on_hit.is_valid(): on_hit.call(e)
				queue_free()
				return
	else:
		var p = zone.player
		if p and not p.dead and U.flat_dist(p.global_position, pos) < 0.6 + size:
			p.take_damage(damage, pos)
			queue_free()
			return
		for m in zone.minions:
			if U.flat_dist(m.global_position, pos) < 0.6 + size:
				m.take_damage(damage)
				queue_free()
				return
	if traveled > max_dist: queue_free()
