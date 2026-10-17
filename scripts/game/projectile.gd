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
var pierce := false
var _hit_set := {}
var color := Color.WHITE
var glow := false

static func fire(z, origin: Vector3, d: Vector3, spd: float, rng: float, c: Color, sz: float, player_owned: bool, cb: Callable, dmg := 0.0) -> Projectile:
	var p := Projectile.new()
	p.zone = z; p.dir = d.normalized(); p.speed = spd; p.max_dist = rng; p.size = sz
	p.from_player = player_owned; p.on_hit = cb; p.damage = dmg; p.color = c
	z.fx_root.add_child(p)
	p.global_position = origin
	var mi := U.prim("sphere", p, Vector3.ZERO, Vector3(sz, sz, sz * (3.0 if sz < 0.3 else 1.0)), c, 0.5, 2.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.rotation.y = atan2(p.dir.x, p.dir.z)
	return p

## След снаряда: частицы и (для заклинаний) свет
func add_trail(c: Color, is_glow: bool) -> Projectile:
	glow = is_glow
	color = c
	if is_glow:
		# мягкий ореол вокруг ядра
		var h := MeshInstance3D.new()
		var q2 := QuadMesh.new(); q2.size = Vector2.ONE * size * 4.0
		h.mesh = q2
		var hm: StandardMaterial3D = CombatFX._mat(Color(c.r, c.g, c.b, 0.55)).duplicate()
		h.material_override = hm
		h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(h)
	var p := CPUParticles3D.new()
	p.amount = maxi(3, int((16 if glow else 10) * Game.particle_mul))
	p.lifetime = 0.35 if glow else 0.2
	p.local_coords = false
	p.direction = Vector3.ZERO; p.spread = 180
	p.initial_velocity_min = 0.0; p.initial_velocity_max = 0.4 if glow else 0.1
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.5; p.scale_amount_max = 1.0
	var q := QuadMesh.new(); q.size = Vector2.ONE * (size * 1.4 if glow else 0.09)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = c
	m.albedo_texture = CombatFX.soft_tex()
	q.material = m
	p.mesh = q
	var g := Gradient.new(); g.set_color(0, Color(1, 1, 1, 0.9)); g.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = g
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	if glow:
		var l := OmniLight3D.new(); l.light_color = c; l.light_energy = 1.2; l.omni_range = 3.5
		add_child(l)
	return self

func _process(delta: float) -> void:
	var step := speed * delta
	global_position += dir * step
	traveled += step
	var pos := global_position
	if from_player:
		for e in zone.enemies:
			if e.alive and not _hit_set.has(e) and U.flat_dist(e.global_position, pos) < e.radius + size + 0.3:
				_hit_set[e] = true
				if on_hit.is_valid(): on_hit.call(e)
				_impact(pos)
				if not pierce:
					queue_free()
					return
	else:
		var p = zone.player
		if p and not p.dead and U.flat_dist(p.global_position, pos) < 0.6 + size:
			p.take_damage(damage, pos)
			_impact(pos)
			queue_free()
			return
		for m in zone.minions:
			if U.flat_dist(m.global_position, pos) < 0.6 + size:
				m.take_damage(damage)
				queue_free()
				return
	if traveled > max_dist:
		if glow: _impact(pos, 0.5)
		queue_free()

## Вспышка и искры в точке попадания
func _impact(pos: Vector3, k := 1.0) -> void:
	if zone == null: return
	if glow:
		CombatFX.burst(zone.fx_root, pos, color, int(18 * k), 5.0, 0.12, 0.4, Vector3.UP, 180, -2.0)
		CombatFX.flash(zone.fx_root, pos, color, size * 5.0 * k, 0.18)
	else:
		CombatFX.burst(zone.fx_root, pos, color.lightened(0.3), int(8 * k), 3.5, 0.05, 0.25, -dir, 60, -6.0)
