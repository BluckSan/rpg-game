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

## Пассивы игрока для снарядов (из дерева талантов): extra_proj, proj_dmg, elem_ice. Задаёт Player.recalc.
static var player_fx := {}
static var dmg_scale := 1.0   # множитель урона текущего попадания снаряда (читает Player.hit)
static var _extra := false

static func fire(z, origin: Vector3, d: Vector3, spd: float, rng: float, c: Color, sz: float, player_owned: bool, cb: Callable, dmg := 0.0) -> Projectile:
	if player_owned and not _extra and not player_fx.is_empty():
		var scale := 1.0 + float(player_fx.get("proj_dmg", 0.0)) / 100.0
		var ice := player_fx.has("elem_ice") and c.r > c.b * 1.4 and c.r > 0.6
		if ice: c = Color(0.55, 0.85, 1.0)
		var inner := cb
		if scale != 1.0 or ice:
			cb = func(e):
				dmg_scale = scale
				if inner.is_valid(): inner.call(e)
				dmg_scale = 1.0
				if ice and is_instance_valid(e) and e.alive: e.slow(0.6, 2.5)
		var n := int(player_fx.get("extra_proj", 0.0))
		if n > 0:
			_extra = true
			for i in n:
				var ang := (float(i / 2) + 1.0) * 9.0 * (1.0 if i % 2 == 0 else -1.0)
				fire(z, origin, d.rotated(Vector3.UP, deg_to_rad(ang)), spd, rng, c, sz * 0.85, true, cb, dmg)
			_extra = false
	return _make(z, origin, d, spd, rng, c, sz, player_owned, cb, dmg)

static func _make(z, origin: Vector3, d: Vector3, spd: float, rng: float, c: Color, sz: float, player_owned: bool, cb: Callable, dmg := 0.0) -> Projectile:
	var p := Projectile.new()
	p.zone = z; p.dir = d.normalized(); p.speed = spd; p.max_dist = rng; p.size = sz
	p.from_player = player_owned; p.on_hit = cb; p.damage = dmg; p.color = c
	z.fx_root.add_child(p)
	p.global_position = origin
	var mi := U.prim("sphere", p, Vector3.ZERO, Vector3(sz, sz, sz * (3.0 if sz < 0.3 else 1.0)), c, 0.5, 2.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.rotation.y = atan2(p.dir.x, p.dir.z)
	p.rotation.x = -asin(clampf(p.dir.y, -1, 1))   # наклон по направлению полёта
	p.follow_terrain = absf(p.dir.y) < 0.05
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

var wall_hit := false     # для тестов: снаряд остановлен стеной
var follow_terrain := true  # горизонтальный выстрел без цели: держится над рельефом
var hits := 0

func _process(delta: float) -> void:
	var step := speed * delta
	var prev := global_position
	var nxt := prev + dir * step
	# в мире снаряд «скользит» над рельефом (склоны не съедают выстрелы)
	if follow_terrain and zone and zone.get("builder") is WorldBuilder:
		var gy: float = zone.ground_y(nxt)
		if nxt.y < gy + 0.6: nxt.y = gy + 0.6
		elif nxt.y > gy + 2.2: nxt.y = move_toward(nxt.y, gy + 1.3, step * 0.3)
	# непрерывная проверка: луч от прошлой точки к новой — стены и статика (слой 1)
	var blocked := false
	if is_inside_tree():
		var q := PhysicsRayQueryParameters3D.create(prev, nxt + dir * size * 0.5, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		# стена — всегда; земля — только для наклонного выстрела (горизонтальный скользит над рельефом)
		if not hit.is_empty() and ((hit.normal as Vector3).y < 0.75 or not follow_terrain):
			blocked = true
			nxt = hit.position - dir * 0.05
	# цели проверяем вдоль всего отрезка (быстрые снаряды не «перепрыгивают» цель)
	var seg := prev.distance_to(nxt)
	var n := maxi(1, ceili(seg / 0.5))
	for i in n:
		var pos := prev.lerp(nxt, float(i + 1) / n)
		global_position = pos
		if _check_targets(pos): return
	traveled += step
	if blocked:
		wall_hit = true
		_impact(global_position, 0.7)
		queue_free()
		return
	var pos := global_position
	if traveled > max_dist:
		if glow: _impact(pos, 0.5)
		queue_free()

## true — снаряд израсходован
func _check_targets(pos: Vector3) -> bool:
	if from_player:
		for e in zone.enemies:
			if e.alive and not _hit_set.has(e) and U.flat_dist(e.global_position, pos) < e.radius + size + 0.3 \
					and pos.y > e.global_position.y - 0.5 and pos.y < e.global_position.y + e.body_height() + 0.5:
				_hit_set[e] = true
				hits += 1
				if on_hit.is_valid(): on_hit.call(e)
				_impact(pos)
				if not pierce:
					queue_free()
					return true
	else:
		var p = zone.player
		if p and not p.dead and U.flat_dist(p.global_position, pos) < 0.6 + size and pos.y > p.global_position.y - 0.5 and pos.y < p.global_position.y + 2.4:
			hits += 1
			p.take_damage(damage, pos)
			_impact(pos)
			queue_free()
			return true
		for m in zone.minions:
			if U.flat_dist(m.global_position, pos) < 0.6 + size:
				m.take_damage(damage)
				queue_free()
				return true
	return false

## Вспышка и искры в точке попадания
func _impact(pos: Vector3, k := 1.0) -> void:
	if zone == null: return
	if glow:
		CombatFX.burst(zone.fx_root, pos, color, int(18 * k), 5.0, 0.12, 0.4, Vector3.UP, 180, -2.0)
		CombatFX.flash(zone.fx_root, pos, color, size * 5.0 * k, 0.18)
	else:
		CombatFX.burst(zone.fx_root, pos, color.lightened(0.3), int(8 * k), 3.5, 0.05, 0.25, -dir, 60, -6.0)
