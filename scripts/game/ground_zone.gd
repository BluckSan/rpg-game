extends Node3D
class_name GroundZone
## Зона умения на земле: каждые tick секунд вызывает on_tick(центр); исчезает через duration.

var duration := 4.0
var tick := 0.5
var radius := 3.0
var on_tick: Callable
var _t := 0.0
var _acc := 0.0
var _mark: Node3D

static func spawn(z, pos: Vector3, r: float, dur: float, c: Color, cb: Callable, tick_s := 0.5, shape := "disc", dir := Vector3.FORWARD, length := 0.0) -> GroundZone:
	var g := GroundZone.new()
	g.radius = r; g.duration = dur; g.on_tick = cb; g.tick = tick_s
	z.fx_root.add_child(g)
	g.global_position = pos
	if shape == "line":
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new(); bm.size = Vector3(r * 2.0, 0.02, length)
		mi.mesh = bm
		mi.material_override = U.fx_mat(Color(c.r, c.g, c.b, 0.4))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.add_child(mi)
		mi.position = Vector3(0, 0.06, 0)
		g.rotation.y = atan2(dir.x, dir.z)
		g._mark = mi
	else:
		g._mark = Tele.make(g, "disc", pos, r, c)
		Tele.set_progress(g._mark, 1.0)
	var p := CPUParticles3D.new()
	p.amount = maxi(4, int(24 * Game.particle_mul)); p.lifetime = 0.8
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX if shape == "line" else CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_box_extents = Vector3(r, 0.1, length / 2.0)
	p.emission_sphere_radius = r * 0.8
	p.direction = Vector3.UP; p.spread = 15; p.initial_velocity_min = 0.8; p.initial_velocity_max = 2.0
	p.gravity = Vector3(0, 0.5, 0)
	var q := QuadMesh.new(); q.size = Vector2(0.18, 0.18); q.material = CombatFX._mat(c)
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(p)
	return g

func _process(delta: float) -> void:
	_t += delta; _acc += delta
	if _acc >= tick:
		_acc -= tick
		if on_tick.is_valid(): on_tick.call(global_position)
	if _t > duration - 0.4:
		scale = Vector3.ONE * maxf(0.01, (duration - _t) / 0.4)
	if _t >= duration: queue_free()
