class_name Vfx
## v0.9.3: настоящие эффекты умений вместо цветных сфер. Огонь (пламя, искры, дым, подпалина),
## лёд (осколки, иней), ветвистая молния, лучи и ауры лечения/усиления, вспышки попадания, тряска камеры.
## Пресеты графики меняют только число частиц (Game.particle_mul), вид — одинаковый.

static var _smoke_mat: StandardMaterial3D
static var _scorch_tex: Texture2D
static var _shard_mesh: Mesh
static var made := {}   # для тестов: сколько эффектов какого вида создано

static func _count(k: String) -> void: made[k] = int(made.get(k, 0)) + 1

## Стихия по цвету умения: fire / ice / lightning / holy / nature / arcane / phys
static func elem_of(c: Color) -> String:
	var h := c.h; var s := c.s
	if s < 0.18: return "lightning" if c.v > 0.85 else "phys"
	if h < 0.11 or h > 0.95: return "fire"
	if h < 0.17: return "holy"
	if h < 0.42: return "nature"
	if h < 0.6: return "ice"
	if h < 0.7: return "lightning"
	return "arcane"

static func _n(n: int) -> int: return maxi(2, int(n * Game.particle_mul))

static func _parts(parent: Node, pos: Vector3, n: int, life: float, c: Color, size: float, add := true) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true; p.emitting = false; p.amount = _n(n); p.lifetime = life; p.explosiveness = 0.9
	var q := QuadMesh.new(); q.size = Vector2.ONE * size
	q.material = CombatFX._mat(c) if add else _smoke()
	p.mesh = q
	var g := Gradient.new(); g.set_color(0, Color(1, 1, 1, 1)); g.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = g
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p); p.global_position = pos
	p.finished.connect(p.queue_free)
	return p

static func _go(p: CPUParticles3D) -> void:
	p.emitting = true

static func _smoke() -> StandardMaterial3D:
	if _smoke_mat == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		m.albedo_color = Color(0.18, 0.16, 0.15, 0.55)
		m.albedo_texture = CombatFX.soft_tex()
		_smoke_mat = m
	return _smoke_mat

static func _grow() -> Curve:
	var cv := Curve.new(); cv.add_point(Vector2(0, 0.4)); cv.add_point(Vector2(1, 1.6)); return cv
static func _shrink() -> Curve:
	var cv := Curve.new(); cv.add_point(Vector2(0, 1.0)); cv.add_point(Vector2(1, 0.1)); return cv

## Огонь: языки пламени, искры, дым
static func fire(parent: Node, pos: Vector3, k := 1.0) -> void:
	_count("fire")
	var f := _parts(parent, pos, int(26 * k), 0.55, Color(1, 0.5, 0.12), 0.45 * k)
	f.direction = Vector3.UP; f.spread = 60; f.initial_velocity_min = 1.5 * k; f.initial_velocity_max = 4.0 * k
	f.gravity = Vector3(0, 3.0, 0); f.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE; f.emission_sphere_radius = 0.4 * k
	f.scale_amount_curve = _shrink(); f.color = Color(1, 0.75, 0.3)
	_go(f)
	var core := _parts(parent, pos, int(10 * k), 0.3, Color(1, 0.9, 0.55), 0.6 * k)
	core.spread = 180; core.initial_velocity_max = 1.0; core.gravity = Vector3.ZERO; core.scale_amount_curve = _shrink()
	_go(core)
	var sp := _parts(parent, pos, int(22 * k), 0.7, Color(1, 0.75, 0.3), 0.06)
	sp.direction = Vector3.UP; sp.spread = 85; sp.initial_velocity_min = 4.0 * k; sp.initial_velocity_max = 9.0 * k
	sp.gravity = Vector3(0, -9, 0)
	_go(sp)
	var sm := _parts(parent, pos + Vector3.UP * 0.3, int(10 * k), 1.6, Color.WHITE, 0.9 * k, false)
	sm.direction = Vector3.UP; sm.spread = 30; sm.initial_velocity_min = 0.6; sm.initial_velocity_max = 1.6
	sm.gravity = Vector3(0, 0.5, 0); sm.scale_amount_curve = _grow(); sm.explosiveness = 0.5
	_go(sm)
	light(parent, pos, Color(1, 0.55, 0.2), 3.0 * k, 0.4)

## Подпалина на земле (декаль), гаснет за ~6 с
static func scorch(parent: Node, pos: Vector3, radius := 1.5) -> void:
	_count("scorch")
	if _scorch_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(0.05, 0.03, 0.02, 0.85)); g.set_color(1, Color(0, 0, 0, 0))
		g.add_point(0.55, Color(0.08, 0.05, 0.03, 0.6))
		var t := GradientTexture2D.new(); t.gradient = g; t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5); t.fill_to = Vector2(1, 0.5); t.width = 128; t.height = 128
		_scorch_tex = t
	var d := Decal.new()
	d.texture_albedo = _scorch_tex
	d.size = Vector3(radius * 2, 2.0, radius * 2)
	d.rotation.y = randf() * TAU
	parent.add_child(d); d.global_position = pos
	var tw := d.create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(d, "albedo_mix", 0.0, 2.0)
	tw.tween_callback(d.queue_free)

## Лёд: разлетающиеся осколки, морозная дымка, иней-кольцо
static func ice(parent: Node, pos: Vector3, k := 1.0) -> void:
	_count("ice")
	if _shard_mesh == null:
		var pm := PrismMesh.new(); pm.size = Vector3(0.12, 0.45, 0.12)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.75, 0.92, 1.0, 0.85); m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.emission_enabled = true; m.emission = Color(0.4, 0.75, 1.0); m.emission_energy_multiplier = 1.4
		m.metallic_specular = 1.0; m.roughness = 0.1
		pm.material = m
		_shard_mesh = pm
	var s := CPUParticles3D.new()
	s.one_shot = true; s.amount = _n(int(16 * k)); s.lifetime = 0.9; s.explosiveness = 1.0
	s.mesh = _shard_mesh
	s.direction = Vector3.UP; s.spread = 80; s.initial_velocity_min = 3.0 * k; s.initial_velocity_max = 7.0 * k
	s.gravity = Vector3(0, -12, 0); s.angular_velocity_min = -360; s.angular_velocity_max = 360
	s.particle_flag_rotate_y = true; s.scale_amount_min = 0.6 * k; s.scale_amount_max = 1.4 * k
	s.scale_amount_curve = _shrink()
	parent.add_child(s); s.global_position = pos
	s.finished.connect(s.queue_free); s.emitting = true
	var mist := _parts(parent, pos, int(18 * k), 0.9, Color(0.7, 0.9, 1.0, 0.7), 0.7 * k)
	mist.spread = 180; mist.initial_velocity_max = 2.0 * k; mist.gravity = Vector3(0, -0.5, 0); mist.scale_amount_curve = _grow()
	_go(mist)
	var gl := _parts(parent, pos, int(20 * k), 0.8, Color(0.85, 0.97, 1.0), 0.07)
	gl.spread = 180; gl.initial_velocity_min = 2.0; gl.initial_velocity_max = 5.0; gl.gravity = Vector3(0, -2, 0)
	_go(gl)
	light(parent, pos, Color(0.55, 0.8, 1.0), 2.5 * k, 0.35)

## Ветвистая молния a → b: основной разряд, 2–4 ответвления, свет и искры в точке удара
static func lightning(parent: Node, a: Vector3, b: Vector3, c: Color, dur := 0.25) -> void:
	_count("lightning")
	var pts := _zig(a, b, 10, 0.45)
	_strip(parent, pts, Color(c.r * 1.6, c.g * 1.6, c.b * 1.8), 0.1, dur)
	_strip(parent, pts, Color(1, 1, 1), 0.035, dur * 0.8)
	for i in randi_range(2, 4):
		var from: Vector3 = pts[randi_range(2, pts.size() - 3)]
		var d := (b - a).normalized()
		var side := Vector3(randf_range(-1, 1), randf_range(-0.6, 0.3), randf_range(-1, 1)).normalized()
		var to := from + (d * 0.6 + side).normalized() * a.distance_to(b) * randf_range(0.12, 0.3)
		_strip(parent, _zig(from, to, 5, 0.25), Color(c.r * 1.3, c.g * 1.3, c.b * 1.6), 0.045, dur * 0.7)
	light(parent, b, c.lightened(0.3), 4.0, dur + 0.1)
	var sp := _parts(parent, b, 14, 0.4, Color(0.85, 0.9, 1.0), 0.06)
	sp.spread = 180; sp.initial_velocity_min = 3.0; sp.initial_velocity_max = 8.0; sp.gravity = Vector3(0, -9, 0)
	_go(sp)

static func _zig(a: Vector3, b: Vector3, n: int, amp: float) -> Array:
	var pts := [a]
	var d := b - a
	var side := d.cross(Vector3.UP).normalized()
	if side.length() < 0.1: side = Vector3.RIGHT
	var up := d.cross(side).normalized()
	for i in range(1, n):
		var k := float(i) / n
		var j := amp * sin(k * PI) * 1.4
		pts.append(a + d * k + side * randf_range(-j, j) + up * randf_range(-j, j))
	pts.append(b)
	return pts

static func _strip(parent: Node, pts: Array, c: Color, width: float, dur: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in pts.size() - 1:
		var p0: Vector3 = pts[i]; var p1: Vector3 = pts[i + 1]
		var d := (p1 - p0).normalized()
		var s1 := d.cross(Vector3.UP).normalized() * width
		if s1.length() < 0.001: s1 = Vector3.RIGHT * width
		var s2 := d.cross(s1).normalized() * width
		for w in [s1, s2]:
			st.add_vertex(p0 - w); st.add_vertex(p0 + w); st.add_vertex(p1 + w)
			st.add_vertex(p0 - w); st.add_vertex(p1 + w); st.add_vertex(p1 - w)
	var mi := MeshInstance3D.new(); mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD; m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = c
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	var tw := mi.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, dur).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)

## Луч (лечение/благословение сверху или от заклинателя к союзнику)
static func beam(parent: Node, a: Vector3, b: Vector3, c: Color, dur := 0.6) -> void:
	_count("beam")
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new(); cm.top_radius = 0.25; cm.bottom_radius = 0.35; cm.height = 1.0
	cm.cap_top = false; cm.cap_bottom = false; cm.radial_segments = 16
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD; m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(c.r, c.g, c.b, 0.6)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	var len := a.distance_to(b)
	mi.global_position = (a + b) / 2
	if len > 0.01:
		var d := (b - a) / len
		var ax := Vector3.UP.cross(d)
		if ax.length() > 0.001: mi.global_basis = Basis(ax.normalized(), Vector3.UP.angle_to(d))
	mi.scale = Vector3(0.2, len, 0.2)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(1.0, len, 1.0), dur * 0.25)
	tw.tween_property(m, "albedo_color:a", 0.0, dur).set_delay(dur * 0.3)
	tw.chain().tween_callback(mi.queue_free)
	var sp := _parts(parent, b, 18, 0.9, c.lightened(0.3), 0.12)
	sp.direction = Vector3.UP; sp.spread = 20; sp.initial_velocity_min = 1.5; sp.initial_velocity_max = 3.5
	sp.gravity = Vector3.ZERO; sp.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	sp.emission_ring_radius = 0.7; sp.emission_ring_inner_radius = 0.5; sp.emission_ring_height = 0.1; sp.emission_ring_axis = Vector3.UP
	_go(sp)

## Аура на герое: светящееся кольцо у ног и поднимающиеся искры, следует за целью
static func aura(parent: Node, who: Node3D, c: Color, dur := 1.2) -> void:
	_count("aura")
	if not is_instance_valid(who): return
	var holder := Node3D.new()
	who.add_child(holder)
	var ring := MeshInstance3D.new()
	var t := TorusMesh.new(); t.inner_radius = 0.75; t.outer_radius = 0.95; t.rings = 32; t.ring_segments = 4
	ring.mesh = t
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD; m.albedo_color = Color(c.r, c.g, c.b, 0.8)
	ring.material_override = m; ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(ring); ring.position = Vector3.UP * 0.08; ring.scale = Vector3(1, 0.3, 1)
	var p := CPUParticles3D.new()
	p.amount = _n(24); p.lifetime = 1.0; p.local_coords = false
	var q := QuadMesh.new(); q.size = Vector2.ONE * 0.12; q.material = CombatFX._mat(c.lightened(0.25)); p.mesh = q
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING; p.emission_ring_radius = 0.85; p.emission_ring_inner_radius = 0.6
	p.emission_ring_height = 0.1; p.emission_ring_axis = Vector3.UP
	p.direction = Vector3.UP; p.spread = 10; p.initial_velocity_min = 1.0; p.initial_velocity_max = 2.4; p.gravity = Vector3.ZERO
	var g := Gradient.new(); g.set_color(0, Color(1, 1, 1, 1)); g.set_color(1, Color(1, 1, 1, 0)); p.color_ramp = g
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(p)
	var tw := holder.create_tween().set_parallel(true)
	tw.tween_property(ring, "rotation:y", TAU, dur)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.4).set_delay(maxf(0.0, dur - 0.4))
	tw.chain().tween_callback(func(): p.emitting = false)
	tw.chain().tween_interval(1.0)
	tw.chain().tween_callback(holder.queue_free)

## Вспышка попадания: плоское свечение (билборд) + короткий свет, без сфер
static func hit_flash(parent: Node, pos: Vector3, c: Color, radius := 0.8, dur := 0.15) -> void:
	_count("flash")
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new(); q.size = Vector2.ONE
	mi.mesh = q
	var m: StandardMaterial3D = CombatFX._mat(c).duplicate()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = false
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi); mi.global_position = pos
	mi.scale = Vector3.ONE * radius * 0.6
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * radius * 2.4, dur)
	tw.tween_property(m, "albedo_color:a", 0.0, dur)
	tw.chain().tween_callback(mi.queue_free)
	light(parent, pos, c, 2.0 + radius, dur)

static func light(parent: Node, pos: Vector3, c: Color, rng: float, dur: float) -> void:
	if Game.particle_mul < 0.4: return   # самый низкий пресет: без динамического света (частицы те же)
	var l := OmniLight3D.new(); l.light_color = c; l.light_energy = 2.5; l.omni_range = rng
	l.shadow_enabled = false
	parent.add_child(l); l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, dur)
	tw.tween_callback(l.queue_free)

## Попадание/взрыв по стихии
static func impact(parent: Node, pos: Vector3, elem: String, k := 1.0, c := Color.WHITE) -> void:
	match elem:
		"fire": fire(parent, pos, k)
		"ice": ice(parent, pos, k)
		"lightning":
			lightning(parent, pos + Vector3(randf_range(-0.5, 0.5), 2.5 * k, randf_range(-0.5, 0.5)), pos, Color(0.65, 0.75, 1.0), 0.2)
			hit_flash(parent, pos, Color(0.8, 0.85, 1.0), 0.7 * k, 0.12)
		"holy", "nature":
			var col := Color(1, 0.88, 0.45) if elem == "holy" else Color(0.45, 1.0, 0.5)
			hit_flash(parent, pos, col, 0.9 * k, 0.25)
			var sp := _parts(parent, pos, int(20 * k), 0.8, col, 0.1)
			sp.direction = Vector3.UP; sp.spread = 50; sp.initial_velocity_min = 1.5; sp.initial_velocity_max = 4.0; sp.gravity = Vector3(0, 1.0, 0)
			_go(sp)
		_:
			hit_flash(parent, pos, c if elem == "arcane" else Color(1, 0.92, 0.75), 0.8 * k, 0.15)
			var sp2 := _parts(parent, pos, int(14 * k), 0.4, c.lightened(0.3), 0.08)
			sp2.spread = 180; sp2.initial_velocity_min = 2.0; sp2.initial_velocity_max = 5.0; sp2.gravity = Vector3(0, -4, 0)
			_go(sp2)

## Лёгкая тряска камеры текущей зоны (сильные удары)
static func shake(amount: float) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null: return
	var z = tree.current_scene
	if z and z.has_method("shake"): z.shake(amount)
