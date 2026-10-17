class_name CombatFX
## Боевые эффекты: искры/брызги при попадании, дуга удара, свечение каста, ударные волны, камни.

static var _spark_mesh: Mesh
static var _mats := {}
static var _soft: Texture2D

## Мягкое круглое пятно для частиц (вместо квадратов)
static func soft_tex() -> Texture2D:
	if _soft == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1)); g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.35, Color(1, 1, 1, 0.8))
		var t := GradientTexture2D.new()
		t.gradient = g; t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5); t.fill_to = Vector2(1.0, 0.5)
		t.width = 64; t.height = 64
		_soft = t
	return _soft

static func _mat(c: Color, add := true) -> StandardMaterial3D:
	var key := c.to_html() + str(add)
	if _mats.has(key): return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if add: m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = c
	m.albedo_texture = soft_tex()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES if add else BaseMaterial3D.BILLBOARD_DISABLED
	_mats[key] = m
	return m

## Разовый выброс частиц: искры (металл, кости), «кровь» (живые), магия
static func burst(parent: Node, pos: Vector3, c: Color, n := 14, speed := 5.0, size := 0.06, life := 0.45, dir := Vector3.UP, spread := 70.0, gravity := -9.0) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true; p.emitting = false
	p.amount = n; p.lifetime = life; p.explosiveness = 0.95
	p.direction = dir; p.spread = spread
	p.initial_velocity_min = speed * 0.5; p.initial_velocity_max = speed
	p.gravity = Vector3(0, gravity, 0)
	p.scale_amount_min = 0.6; p.scale_amount_max = 1.4
	var q := QuadMesh.new(); q.size = Vector2(size, size * (2.5 if gravity < -3 else 1.0))
	q.material = _mat(c)
	p.mesh = q
	var g := Gradient.new(); g.set_color(0, Color(1, 1, 1, 1)); g.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = g
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)

## Попадание по врагу
static func hit(parent: Node, pos: Vector3, kind: String, crit: bool, from_dir: Vector3) -> void:
	var d := (from_dir.normalized() + Vector3.UP * 0.6).normalized()
	match kind:
		"skeleton", "skeleton_archer":
			burst(parent, pos, Color(1, 0.9, 0.6), 16 if crit else 10, 6.0, 0.05, 0.35, d, 55)
			burst(parent, pos, Color(0.95, 0.92, 0.85, 0.9), 6, 3.0, 0.09, 0.6, d, 60, -12)
		"slime":
			burst(parent, pos, Color(0.4, 1.0, 0.3), 14 if crit else 9, 4.5, 0.09, 0.55, d, 70, -12)
		_:
			burst(parent, pos, Color(0.85, 0.08, 0.05), 16 if crit else 10, 5.0, 0.07, 0.5, d, 60, -14)
			burst(parent, pos, Color(1, 0.85, 0.5), 8 if crit else 4, 7.0, 0.04, 0.25, d, 40)
	if crit:
		flash(parent, pos, Color(1, 0.9, 0.5), 0.9, 0.12)

## Короткая вспышка-сфера
static func flash(parent: Node, pos: Vector3, c: Color, radius: float, dur: float) -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new(); s.radius = 0.5; s.height = 1.0; s.radial_segments = 12; s.rings = 6
	mi.mesh = s
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = c
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * radius * 0.4
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * radius * 2.0, dur)
	tw.tween_property(m, "albedo_color:a", 0.0, dur)
	tw.chain().tween_callback(mi.queue_free)

## Дуга-«взмах» (для кругового удара и тяжёлых атак)
static func slash_arc(parent: Node, center: Vector3, fwd: Vector3, radius: float, arc_deg: float, c: Color, dur := 0.22, height := 1.1) -> void:
	var mesh := ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = center + Vector3.UP * height
	var base_ang := atan2(fwd.x, fwd.z)
	var seg := 20
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in seg + 1:
		var t := float(i) / seg
		var a := base_ang + deg_to_rad(arc_deg) * (t - 0.5)
		var dir := Vector3(sin(a), 0, cos(a))
		var alpha := sin(t * PI) * (0.35 + 0.65 * t)
		mesh.surface_set_color(Color(c.r, c.g, c.b, alpha))
		mesh.surface_add_vertex(dir * radius * 0.35 + Vector3.UP * 0.05 * t)
		mesh.surface_set_color(Color(c.r, c.g, c.b, alpha * 0.2))
		mesh.surface_add_vertex(dir * radius - Vector3.UP * 0.05 * t)
	mesh.surface_end()
	mi.scale = Vector3.ONE * 0.85
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * 1.08, dur)
	tw.tween_property(mi, "rotation:y", deg_to_rad(arc_deg * 0.15), dur)
	tw.tween_property(m, "albedo_color:a", 0.0, dur).set_delay(dur * 0.3)
	tw.chain().tween_callback(mi.queue_free)

## Свечение в руке/на посохе при касте
static func cast_glow(parent: Node3D, c: Color, dur := 0.35, radius := 0.25) -> void:
	var holder := Node3D.new()
	parent.add_child(holder)
	var l := OmniLight3D.new(); l.light_color = c; l.light_energy = 1.6; l.omni_range = 3.0
	holder.add_child(l)
	flash(holder, holder.global_position, c, radius, dur)
	burst(holder, holder.global_position, c, 12, 1.5, 0.06, dur, Vector3.UP, 180, 0.5)
	var tw := holder.create_tween()
	tw.tween_property(l, "light_energy", 0.0, dur)
	tw.tween_callback(holder.queue_free)

## Ударная волна по земле (кольцо). Через неё можно перепрыгнуть или прокатиться.
static func ground_ring(parent: Node, pos: Vector3, radius: float, width: float, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new(); t.inner_radius = 1.0 - width; t.outer_radius = 1.0; t.rings = 48; t.ring_segments = 4
	mi.mesh = t
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	m.emission_enabled = true; m.emission = c; m.emission_energy_multiplier = 1.5
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos + Vector3.UP * 0.15
	mi.scale = Vector3(radius, 1.4, radius)
	return mi
