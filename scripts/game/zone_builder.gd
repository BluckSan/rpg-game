extends Node3D
class_name StarterZoneBuilder
## Стартовая зона «Пепельная долина» из примитивов (одиночная локация).
## Статичная геометрия объединяется в MultiMesh (по одному на тип примитива) — мало вызовов отрисовки.

const SIZE := 90.0
const GRASS := Color(0.33, 0.47, 0.24)
const GRASS_DARK := Color(0.26, 0.38, 0.2)
const DIRT := Color(0.45, 0.36, 0.25)
const STONE := Color(0.5, 0.5, 0.52)
const WOOD := Color(0.4, 0.27, 0.15)
const PATHS := [[Vector3(0,0,0), Vector3(28,0,22)], [Vector3(0,0,0), Vector3(-42,0,8)], [Vector3(0,0,0), Vector3(6,0,-46)],
	[Vector3(0,0,0), Vector3(52,0,-14)], [Vector3(0,0,0), Vector3(-4,0,60)], [Vector3(28,0,22), Vector3(66,0,56)],
	[Vector3(-4,0,44), Vector3(-25,0,54)]]

var zone
var spawn_point := Vector3(0, 0.1, -3.5)
var merchant_point := Vector3(-3.4, 0, -5.6)
var arena_point := Vector3(-4, 0.8, 64)
var portal_point := Vector3(66, 0, 56)
var dungeon_gate_point := Vector3(-27, 0, 55)
var dungeon_seal: Node3D
const POND := Vector3(-22, 0, -28)
const POND_R := 8.0
var hi_nodes: Array = []      # ПК-детализация (трава, вода, земля) — видна только при heavy/pc_detail
var detail_nodes: Array = []
var rng := RandomNumberGenerator.new()
var _batches := {}   # mesh kind -> [[Transform3D, Color], ...]
var _colliders: StaticBody3D
var enemies_root: Node3D

func build(z) -> void:
	zone = z
	rng.seed = 1337
	_colliders = StaticBody3D.new(); _colliders.name = "Colliders"; _colliders.collision_layer = 1
	add_child(_colliders)
	enemies_root = Node3D.new(); enemies_root.name = "Enemies"; add_child(enemies_root)
	_lighting()
	_ground()
	_camp(Vector3.ZERO)
	_meadow(Vector3(28, 0, 22))
	_forest(Vector3(-42, 0, 8))
	_graveyard(Vector3(6, 0, -46))
	_goblin_camp(Vector3(52, 0, -14))
	_ruins(Vector3(-4, 0, 60))
	_portal(portal_point)
	_dungeon_gate(dungeon_gate_point)
	_scatter()
	_boundary()
	_flush_batches()
	if Game.desktop and Game.is_pc_platform(): _hi_world()
	apply_graphics()
	# спавны
	Spawner.create(z, enemies_root, Vector3(28, 0, 22), "slime", 1, 2, 6, 9, 15)
	Spawner.create(z, enemies_root, Vector3(16, 0, -14), "slime", 1, 3, 4, 6, 18)
	Spawner.create(z, enemies_root, Vector3(-36, 0, 14), "wolf", 2, 4, 4, 8, 22)
	Spawner.create(z, enemies_root, Vector3(-52, 0, -4), "wolf", 3, 5, 4, 8, 22)
	Spawner.create(z, enemies_root, Vector3(6, 0, -46), "skeleton_archer", 3, 5, 4, 8, 25)
	Spawner.create(z, enemies_root, Vector3(-6, 0, -52), "skeleton", 4, 6, 3, 6, 25)
	Spawner.create(z, enemies_root, Vector3(52, 0, -14), "goblin", 5, 7, 4, 7, 30)
	Spawner.create(z, enemies_root, Vector3(-30, 0, 46), "skeleton", 6, 8, 4, 7, 30)
	var boss := Spawner.create(z, enemies_root, Vector3(-4, 0, 64), "troll", 9, 9, 1, 0.5, 120)
	boss.kill_flag = "boss_troll_killed"

func _lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1, 0.9, 0.76)
	sun.light_energy = 1.35
	sun.shadow_blur = 1.5
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_enabled = Game.shadows_enabled and Game.shadow_distance > 0
	sun.directional_shadow_max_distance = maxf(Game.shadow_distance, 10.0)
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(sun)
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.name = "Sun"
	var we := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.3, 0.48, 0.75)
	sm.sky_horizon_color = Color(0.7, 0.74, 0.78)
	sm.ground_horizon_color = Color(0.62, 0.66, 0.66)
	sm.ground_bottom_color = Color(0.22, 0.25, 0.2)
	sm.sun_angle_max = 20
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 0.75
	e.ambient_light_color = Color(0.55, 0.58, 0.62)
	e.ambient_light_energy = 1.0
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_DEPTH
	e.fog_light_color = Color(0.66, 0.72, 0.78)
	e.fog_sun_scatter = 0.25
	e.fog_density = 0.6
	e.fog_depth_begin = 38
	e.fog_depth_end = 125
	e.fog_sky_affect = 0.35
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.05
	e.tonemap_white = 6.0
	e.glow_enabled = true
	e.glow_intensity = 0.35
	e.glow_bloom = 0.04
	e.glow_hdr_threshold = 1.1
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.08
	e.adjustment_contrast = 1.04
	we.environment = e
	we.name = "Env"
	add_child(we)
	add_to_group("graphics_listeners")
	apply_graphics()

## Пресет графики → тени, дальность, свечение, туман
func apply_graphics() -> void:
	var sun: DirectionalLight3D = get_node_or_null("Sun")
	var we: WorldEnvironment = get_node_or_null("Env")
	if sun:
		sun.shadow_enabled = Game.shadows_enabled and Game.shadow_distance > 0
		sun.directional_shadow_max_distance = maxf(Game.shadow_distance, 10.0)
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if Game.quality >= 3 else DirectionalLight3D.SHADOW_ORTHOGONAL
	if we and we.environment:
		var e := we.environment
		e.glow_enabled = Game.glow
		e.fog_depth_end = Game.view_distance
		e.fog_depth_begin = Game.view_distance * 0.35
		e.adjustment_enabled = Game.quality >= 2
		_heavy_env(e, sun)
	for n in hi_nodes: if is_instance_valid(n): n.visible = Game.heavy_fx()
	for n in detail_nodes: if is_instance_valid(n): n.visible = Game.pc_detail()
	for n in get_tree().get_nodes_in_group("view_range"):
		(n as GeometryInstance3D).visibility_range_end = Game.view_distance + CELL

## ПК «Высокое» (Forward+): SSAO, мягкие тени (без PCSS — он шумит без TAA), сильнее свечение.
## «Ультра»: + SDFGI, SSR, объёмный туман (по переключателям). Окружающий свет всегда от неба/цвета —
## не зависит от GI, автоэкспозиции нет. Иначе всё выключено — телефон не нагружается.
func _heavy_env(e: Environment, sun: DirectionalLight3D) -> void:
	var on := Game.heavy_fx()
	var ult := Game.ultra()
	e.sdfgi_enabled = Game.gi_on()
	e.ssao_enabled = on
	e.ssil_enabled = false
	e.ssr_enabled = Game.ssr_on()
	e.volumetric_fog_enabled = Game.vfog_on()
	e.tonemap_exposure = 1.05
	if on:
		e.ssao_radius = 1.2; e.ssao_intensity = 1.4; e.ssao_power = 1.3
		e.ssao_light_affect = 0.0; e.ssao_ao_channel_affect = 0.0
		e.glow_intensity = 0.5; e.glow_bloom = 0.05
		e.glow_hdr_threshold = 1.0
		e.set_glow_level(1, 1.0); e.set_glow_level(3, 0.8); e.set_glow_level(5, 0.6)
	else:
		e.glow_intensity = 0.35; e.glow_bloom = 0.04
	if e.sdfgi_enabled:
		e.sdfgi_cascades = 4
		e.sdfgi_min_cell_size = 0.4
		e.sdfgi_use_occlusion = true
		e.sdfgi_read_sky_light = true
		e.sdfgi_energy = 0.8
	if e.ssr_enabled:
		e.ssr_max_steps = 48; e.ssr_fade_in = 0.15; e.ssr_fade_out = 2.0
	if e.volumetric_fog_enabled:
		e.volumetric_fog_density = 0.008 if not is_dungeon_env() else 0.014
		e.volumetric_fog_albedo = Color(0.85, 0.85, 0.9) if not is_dungeon_env() else Color(0.55, 0.5, 0.7)
		e.volumetric_fog_anisotropy = 0.55
		e.volumetric_fog_length = 70.0
		e.volumetric_fog_sky_affect = 0.2
		e.volumetric_fog_ambient_inject = 0.0
	if sun:
		sun.light_angular_distance = 0.5 if ult else 0.0
		sun.shadow_blur = 1.0 if on else 1.5
		if on: sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.light_volumetric_fog_energy = 1.0
	var sq := RenderingServer.SHADOW_QUALITY_SOFT_LOW
	if ult: sq = RenderingServer.SHADOW_QUALITY_SOFT_HIGH
	elif on: sq = RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM
	RenderingServer.directional_soft_shadow_filter_set_quality(sq)
	RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM if on else RenderingServer.SHADOW_QUALITY_SOFT_LOW)

func is_dungeon_env() -> bool: return false

## ПК: шейдерная земля, трава с ветром (чанки 16 м, дальность 38 м), пруд с водой
func _hi_world() -> void:
	var nb := NoiseTexture2D.new(); nb.width = 512; nb.height = 512; nb.seamless = true
	var fn := FastNoiseLite.new(); fn.frequency = 0.008; fn.fractal_octaves = 4; nb.noise = fn
	var ns := NoiseTexture2D.new(); ns.width = 256; ns.height = 256; ns.seamless = true
	var fs := FastNoiseLite.new(); fs.frequency = 0.05; fs.fractal_octaves = 2; ns.noise = fs
	var tm := ShaderMaterial.new(); tm.shader = load("res://assets/shaders/terrain.gdshader")
	tm.set_shader_parameter("noise_big", nb); tm.set_shader_parameter("noise_small", ns)
	var ground := MeshInstance3D.new(); ground.name = "TerrainHi"
	var pm := PlaneMesh.new(); pm.size = Vector2(SIZE * 2 + 40, SIZE * 2 + 40)
	ground.mesh = pm; ground.material_override = tm
	ground.position = Vector3(0, 0.003, 0)
	add_child(ground); detail_nodes.append(ground)
	# трава
	var blade := _blade_mesh()
	var gm := ShaderMaterial.new(); gm.shader = load("res://assets/shaders/grass.gdshader")
	var CH := 16.0
	var grng := RandomNumberGenerator.new(); grng.seed = 777
	var x := -SIZE + CH / 2
	while x < SIZE:
		var zz := -SIZE + CH / 2
		while zz < SIZE:
			var xf: Array = []
			for i in 900:
				var p := Vector3(x + grng.randf_range(-CH / 2, CH / 2), 0, zz + grng.randf_range(-CH / 2, CH / 2))
				if p.length() < 13 or _dist_to_path(p) < 2.0 or p.distance_to(Vector3(-4, 0, 64)) < 17 or p.distance_to(Vector3(52, 0, -14)) < 12 \
						or (absf(p.x - 6) < 12 and absf(p.z + 46) < 10) or p.distance_to(POND) < POND_R + 0.5 or p.distance_to(dungeon_gate_point) < 6 or p.length() > SIZE - 4:
					continue
				var s := grng.randf_range(0.7, 1.3)
				xf.append(Transform3D(Basis(Vector3.UP, grng.randf() * TAU).scaled(Vector3(s, s * grng.randf_range(0.8, 1.4), s)), p))
			if xf.size() > 0:
				var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.use_colors = true
				mm.mesh = blade; mm.instance_count = xf.size()
				for i in xf.size():
					mm.set_instance_transform(i, xf[i])
					mm.set_instance_color(i, Color(grng.randf(), 0, 0))
				var mi := MultiMeshInstance3D.new(); mi.multimesh = mm; mi.material_override = gm
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.visibility_range_end = 38.0; mi.visibility_range_end_margin = 6.0
				mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
				mi.name = "Grass"
				add_child(mi); hi_nodes.append(mi)
			zz += CH
		x += CH
	# пруд
	var wn := NoiseTexture2D.new(); wn.width = 256; wn.height = 256; wn.seamless = true; wn.as_normal_map = true; wn.bump_strength = 6.0
	var wf := FastNoiseLite.new(); wf.frequency = 0.03; wn.noise = wf
	var wn2 := NoiseTexture2D.new(); wn2.width = 256; wn2.height = 256; wn2.seamless = true; wn2.as_normal_map = true; wn2.bump_strength = 4.0
	var wf2 := FastNoiseLite.new(); wf2.frequency = 0.06; wf2.seed = 9; wn2.noise = wf2
	var wm := ShaderMaterial.new(); wm.shader = load("res://assets/shaders/water.gdshader")
	wm.set_shader_parameter("wave_a", wn); wm.set_shader_parameter("wave_b", wn2); wm.set_shader_parameter("radius", POND_R)
	var water := MeshInstance3D.new(); water.name = "Pond"
	var wmesh := PlaneMesh.new(); wmesh.size = Vector2(POND_R * 2, POND_R * 2)
	water.mesh = wmesh; water.material_override = wm
	water.position = POND + Vector3(0, 0.05, 0)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water); hi_nodes.append(water)
	var shore := U.prim("cylinder", self, POND + Vector3(0, 0.008, 0), Vector3(POND_R * 2 + 2.5, 0.004, POND_R * 2 + 2.5), Color(0.42, 0.38, 0.28))
	hi_nodes.append(shore)
	for i in 10:
		var a := TAU * i / 10.0 + 0.3
		var rk := U.prim("sphere", self, POND + Vector3(cos(a), 0.15, sin(a)) * (POND_R + 0.8), Vector3(1.1, 0.5, 0.9) * (0.6 + 0.08 * (i % 4)), STONE * 0.85)
		hi_nodes.append(rk)

## Травинка: 3 скрещённые плоскости-треугольника (UV.y — высота для ветра)
func _blade_mesh() -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var b := Basis(Vector3.UP, k * PI / 3.0)
		var w := 0.045; var h := 0.36
		var p0 := b * Vector3(-w, 0, 0); var p1 := b * Vector3(w, 0, 0); var p2 := b * Vector3(0.02, h, 0.03)
		var nrm := b * Vector3(0, 0, 1)
		for v in [[p0, 0.0], [p1, 0.0], [p2, 1.0]]:
			st.set_normal(nrm); st.set_uv(Vector2(0.5, v[1])); st.add_vertex(v[0])
	return st.commit()

# ---------- статика ----------
func _add(kind: String, pos: Vector3, scale: Vector3, c: Color, rot := Vector3.ZERO, collide := true) -> void:
	var b := Basis.from_euler(rot * (PI / 180.0)) * Basis.from_scale(scale)
	if not _batches.has(kind): _batches[kind] = []
	_batches[kind].append([Transform3D(b, pos), c])
	if collide: _add_collider(kind, pos, scale, rot)

func _add_collider(kind: String, pos: Vector3, scale: Vector3, rot: Vector3) -> void:
	var cs := CollisionShape3D.new()
	match kind:
		"box":
			var s := BoxShape3D.new(); s.size = scale; cs.shape = s
		"sphere":
			var s := SphereShape3D.new(); s.radius = maxf(scale.x, scale.z) * 0.5; cs.shape = s
		_:
			var s := CylinderShape3D.new(); s.radius = maxf(scale.x, scale.z) * 0.5; s.height = scale.y * 2.0; cs.shape = s
	cs.position = pos
	cs.rotation_degrees = rot
	_colliders.add_child(cs)

## Статика по типу примитива и ячейке 24×24 м: каждая ячейка — свой MultiMesh, поэтому
## работает отсечение по камере и по дальности (visibility_range) — меньше вершин и вызовов.
const CELL := 24.0
func _flush_batches() -> void:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.85
	for kind in _batches:
		var cells := {}
		for it in _batches[kind]:
			var o: Vector3 = it[0].origin
			# крупное (земля, границы) — отдельно, без дальности
			var big: bool = it[0].basis.get_scale().length() > 40.0
			var key: Vector2i = Vector2i(9999, 9999) if big else Vector2i(floori(o.x / CELL), floori(o.z / CELL))
			if not cells.has(key): cells[key] = []
			cells[key].append(it)
		for key in cells:
			var list: Array = cells[key]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = U.mesh(kind)
			mm.instance_count = list.size()
			for i in list.size():
				mm.set_instance_transform(i, list[i][0])
				mm.set_instance_color(i, list[i][1])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = m
			mmi.name = "Batch_%s_%d_%d" % [kind, key.x, key.y]
			if key.x != 9999:
				mmi.visibility_range_end = Game.view_distance + CELL
				mmi.add_to_group("view_range")
			add_child(mmi)

func _glow(kind: String, pos: Vector3, scale: Vector3, c: Color, emission: float, scr: Script = null) -> Node3D:
	var w := Node3D.new()
	if scr: w.set_script(scr)
	add_child(w)
	w.position = pos
	U.prim(kind, w, Vector3.ZERO, scale, c, 0.3, emission)
	return w

func _light(pos: Vector3, c: Color, energy: float, rng_m: float, flicker := false) -> void:
	var l := OmniLight3D.new()
	l.light_color = c; l.light_energy = energy; l.omni_range = rng_m
	if flicker:
		l.set_script(preload("res://scripts/game/flicker.gd"))
	add_child(l)
	l.position = pos

func _r(a: float, b: float) -> float:
	return rng.randf_range(a, b)

func _circle(r: float) -> Vector3:
	var v := Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * r
	return Vector3(v.x, 0, v.y)

func _rand_pos(r: float) -> Vector3:
	return Vector3(_r(-r, r), 0, _r(-r, r))

func _dist_to_path(p: Vector3) -> float:
	var best := INF
	for s in PATHS:
		var a: Vector3 = s[0]; var b: Vector3 = s[1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0, 1)
		best = minf(best, p.distance_to(a + ab * t))
	return best

# ---------- части мира ----------
func _ground() -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new(); bs.size = Vector3(SIZE * 2 + 40, 1, SIZE * 2 + 40)
	cs.shape = bs; cs.position = Vector3(0, -0.5, 0)
	_colliders.add_child(cs)
	_add("box", Vector3(0, -0.5, 0), Vector3(SIZE * 2 + 40, 1, SIZE * 2 + 40), GRASS, Vector3.ZERO, false)
	for s in PATHS: _path(s[0], s[1])
	for i in 60:
		var p := _rand_pos(SIZE - 5)
		var sz := _r(4, 12)
		_add("cylinder", Vector3(p.x, 0.005, p.z), Vector3(sz, 0.005, sz * _r(0.6, 1)), GRASS_DARK if rng.randf() < 0.5 else Color(0.38, 0.52, 0.26), Vector3(0, _r(0, 360), 0), false)

func _path(a: Vector3, b: Vector3) -> void:
	var d := b - a
	var mid := (a + b) / 2
	_add("box", Vector3(mid.x, 0.012, mid.z), Vector3(3.2, 0.02, d.length()), DIRT, Vector3(0, rad_to_deg(atan2(d.x, d.z)), 0), false)

func _camp(c: Vector3) -> void:
	spawn_point = c + Vector3(0, 0.1, -3.5)
	_add("cylinder", c + Vector3(0, 0.08, 0), Vector3(1.8, 0.08, 1.8), STONE)
	for i in 4: _add("cylinder", c + Vector3(0, 0.25, 0), Vector3(0.15, 0.6, 0.15), WOOD, Vector3(70, i * 90, 0), false)
	_glow("sphere", c + Vector3(0, 0.55, 0), Vector3(0.6, 0.9, 0.6), Color(1, 0.55, 0.1), 3.0, preload("res://scripts/game/flicker.gd"))
	_light(c + Vector3(0, 1.5, 0), Color(1, 0.6, 0.25), 2.2, 12, true)
	for i in 3:
		var a := 40.0 + i * 110
		var p := c + Vector3(0, 0, 7).rotated(Vector3.UP, deg_to_rad(a))
		_add("box", p + Vector3.UP * 1.1, Vector3(2.6, 2.6, 3.4), Color(0.7, 0.6, 0.45), Vector3(0, a, 45))
		_add("box", p + Vector3.UP * 0.05, Vector3(3.8, 0.1, 3.6), DIRT, Vector3(0, a, 0), false)
	for i in 6:
		var p := c + Vector3(0, 0, _r(4, 5.5)).rotated(Vector3.UP, deg_to_rad(i * 60 + 15))
		if i % 2 == 0: _add("box", p + Vector3.UP * 0.4, Vector3.ONE * 0.8, WOOD * 1.2, Vector3(0, _r(0, 90), 0))
		else: _add("cylinder", p + Vector3.UP * 0.5, Vector3(0.7, 0.5, 0.7), WOOD)
	for i in 40:
		var a := i * 9.0
		if (a > 15 and a < 40) or (a > 105 and a < 130) or (a > 185 and a < 210) or (a > 255 and a < 280) or a > 340 or a < 3: continue
		var p := c + Vector3(0, 0, 12).rotated(Vector3.UP, deg_to_rad(a))
		_add("cylinder", p + Vector3.UP * 1.0, Vector3(0.35, 1.0, 0.35), WOOD * 0.9)
	# лавка торговца: прилавок, навес, мешки
	merchant_point = c + Vector3(-3.4, 0, -5.6)
	var mp := merchant_point
	_add("box", mp + Vector3(0, 0.5, -0.9), Vector3(2.6, 1.0, 0.7), WOOD * 1.25)
	_add("box", mp + Vector3(0, 1.03, -0.9), Vector3(2.7, 0.06, 0.8), Color(0.55, 0.3, 0.15), Vector3.ZERO, false)
	for sx in [-1.3, 1.3]:
		_add("cylinder", mp + Vector3(sx, 1.3, -1.6), Vector3(0.1, 1.3, 0.1), WOOD, Vector3.ZERO, false)
		_add("cylinder", mp + Vector3(sx, 1.3, -0.7), Vector3(0.1, 1.3, 0.1), WOOD, Vector3.ZERO, false)
	_add("box", mp + Vector3(0, 2.65, -1.25), Vector3(3.0, 0.08, 1.2), Color(0.7, 0.2, 0.15), Vector3(-10, 0, 0), false)
	_add("sphere", mp + Vector3(-0.8, 1.2, -0.9), Vector3(0.35, 0.3, 0.35), Color(0.8, 0.15, 0.2), Vector3.ZERO, false)
	_add("sphere", mp + Vector3(-0.4, 1.2, -0.9), Vector3(0.3, 0.28, 0.3), Color(0.2, 0.4, 0.85), Vector3.ZERO, false)
	_add("box", mp + Vector3(0.7, 1.2, -0.9), Vector3(0.6, 0.3, 0.4), Color(0.6, 0.45, 0.25), Vector3(0, 20, 0), false)
	_add("cylinder", mp + Vector3(1.8, 0.35, -0.2), Vector3(0.55, 0.35, 0.55), Color(0.65, 0.55, 0.35))
	var sp := c + Vector3(2.5, 0, -6)
	_add("cylinder", sp + Vector3.UP * 0.8, Vector3(0.12, 0.8, 0.12), WOOD)
	_add("box", sp + Vector3.UP * 1.5, Vector3(1.2, 0.5, 0.08), WOOD * 1.3)
	var sign_lbl := Label3D.new()
	sign_lbl.font = load("res://fonts/Rubik.ttf"); sign_lbl.text = "Лагерь"; sign_lbl.font_size = 64; sign_lbl.pixel_size = 0.005; sign_lbl.outline_size = 8
	add_child(sign_lbl)
	sign_lbl.position = sp + Vector3(0, 1.5, -0.06)
	sign_lbl.rotation_degrees.y = 180

func _tree(p: Vector3, s: float, pine: bool) -> void:
	_add("cylinder", p + Vector3.UP * 1.2 * s, Vector3(0.35 * s, 1.2 * s, 0.35 * s), WOOD)
	if pine:
		var col := Color(0.16, 0.32, 0.18) * _r(0.85, 1.15); col.a = 1
		for i in 3:
			_add("cone", p + Vector3.UP * (2.6 + i * 1.0) * s, Vector3((3.0 - i * 0.7) * s, 1.8 * s, (3.0 - i * 0.7) * s), col, Vector3.ZERO, false)
	else:
		var col := Color(0.25, 0.45, 0.2) * _r(0.85, 1.15); col.a = 1
		_add("sphere", p + Vector3.UP * 3.0 * s, Vector3(2.8, 2.4, 2.8) * s, col, Vector3.ZERO, false)
		_add("sphere", p + Vector3(0.6, 3.6, 0.3) * s, Vector3(1.8, 1.6, 1.8) * s, col * 1.1, Vector3.ZERO, false)

func _rock(p: Vector3, s: float) -> void:
	var c := STONE * _r(0.8, 1.1); c.a = 1
	_add("sphere", p + Vector3.UP * 0.3 * s, Vector3(1.4, 0.9, 1.2) * s, c, Vector3(_r(-10, 10), _r(0, 360), _r(-10, 10)))

func _meadow(c: Vector3) -> void:
	var cols := [Color(1, 0.85, 0.2), Color(0.9, 0.3, 0.4), Color(0.6, 0.5, 1), Color.WHITE]
	for i in 40:
		var p := c + _circle(14)
		_add("sphere", p + Vector3.UP * 0.25, Vector3.ONE * 0.22, cols[rng.randi() % 4], Vector3.ZERO, false)
		_add("cylinder", p + Vector3.UP * 0.12, Vector3(0.04, 0.12, 0.04), GRASS_DARK, Vector3.ZERO, false)
	for i in 5: _rock(c + _circle(15), _r(0.6, 1.2))

func _forest(c: Vector3) -> void:
	for i in 70:
		var p := c + _circle(26)
		if p.distance_to(Vector3(-36, 0, 14)) < 5 or p.distance_to(Vector3(-52, 0, -4)) < 5 or _dist_to_path(p) < 3: continue
		_tree(p, _r(0.8, 1.4), rng.randf() < 0.6)
	for i in 10: _rock(c + _circle(22), _r(0.5, 1.4))

func _graveyard(c: Vector3) -> void:
	_add("box", c + Vector3(0, 0.015, 0), Vector3(22, 0.02, 18), Color(0.3, 0.32, 0.25), Vector3.ZERO, false)
	for x in range(-3, 4):
		for zz in range(-2, 3):
			if rng.randf() < 0.3: continue
			var p := c + Vector3(x * 3.0 + _r(-0.4, 0.4), 0, zz * 3.2 + _r(-0.4, 0.4))
			_add("box", p + Vector3.UP * 0.6, Vector3(0.9, 1.2, 0.25), STONE * 0.85, Vector3(_r(-8, 8), _r(-15, 15), _r(-8, 8)))
	for i in range(-5, 6):
		_add("box", c + Vector3(i * 2.2, 0.6, 9.5), Vector3(0.2, 1.2, 0.2), Color(0.2, 0.2, 0.22))
		if i != 0: _add("box", c + Vector3(i * 2.2, 0.6, -9.5), Vector3(0.2, 1.2, 0.2), Color(0.2, 0.2, 0.22))
	_add("box", c + Vector3(0, 1.5, -6.5), Vector3(5, 3, 3), STONE * 0.7)
	_add("box", c + Vector3(0, 3.3, -6.5), Vector3(5.6, 0.6, 3.6), STONE * 0.6)
	for i in 6:
		var v := Vector2.from_angle(rng.randf() * TAU) * _r(12, 16)
		_tree(c + Vector3(v.x, 0, v.y), _r(0.8, 1.1), false)

func _goblin_camp(c: Vector3) -> void:
	for i in 3:
		var p := c + Vector3(0, 0, 6).rotated(Vector3.UP, deg_to_rad(i * 120 + 20))
		_add("cylinder", p + Vector3.UP * 1.2, Vector3(3, 1.2, 3), Color(0.45, 0.35, 0.25))
		_add("sphere", p + Vector3.UP * 2.4, Vector3(3.2, 1.8, 3.2), Color(0.5, 0.4, 0.2), Vector3.ZERO, false)
	for i in 24:
		var a := i * 15.0
		if a > 230 and a < 280: continue
		var p := c + Vector3(0, 0, 11).rotated(Vector3.UP, deg_to_rad(a))
		_add("cylinder", p + Vector3.UP * 1.3, Vector3(0.4, 1.3, 0.4), WOOD * 0.8)
	_add("cylinder", c + Vector3.UP * 0.1, Vector3(1.5, 0.1, 1.5), Color(0.2, 0.18, 0.15))
	for i in 4: _add("box", c + _circle(4) + Vector3.UP * 0.25, Vector3(0.6, 0.5, 0.4), Color(0.85, 0.8, 0.7), Vector3(0, _r(0, 360), 0), false)

## Руины с ареной босса: каменная платформа высотой ARENA_H, пологий пандус от тропы (юг)
## и ступень-уступ с востока, на которую нужно запрыгнуть.
const ARENA_H := 0.8
const ARENA_R := 12.0

func _ruins(c: Vector3) -> void:
	var a := c + Vector3(0, 0, 4)
	_add("cylinder", a + Vector3(0, ARENA_H / 2, 0), Vector3(ARENA_R * 2, ARENA_H / 2, ARENA_R * 2), STONE * 0.72)
	_add("cylinder", a + Vector3(0, ARENA_H + 0.01, 0), Vector3(ARENA_R * 1.6, 0.01, ARENA_R * 1.6), STONE * 0.62, Vector3.ZERO, false)
	_add("cylinder", a + Vector3(0, ARENA_H + 0.02, 0), Vector3(5, 0.01, 5), Color(0.35, 0.25, 0.45), Vector3.ZERO, false)
	# пандус: от земли (юг) до края платформы
	var low := Vector3(a.x, 0, a.z - ARENA_R - 5.4)
	var high := Vector3(a.x, ARENA_H, a.z - ARENA_R + 0.6)
	_ramp(low, high, 4.6)
	for sx in [-1, 1]:
		_add("box", Vector3(a.x + sx * 2.6, 0.55, (low.z + high.z) / 2 + 0.6), Vector3(0.5, 1.1, 4.0), STONE * 0.85)
	zone.add_height_ramp(low, high, 2.3)
	zone.add_height_disc(a, ARENA_R, ARENA_H)
	# уступ с востока: ступень 0.45 м, дальше прыжок на платформу
	var step := Vector3(a.x + ARENA_R + 0.7, 0.225, a.z)
	_add("box", step, Vector3(2.4, 0.45, 3.4), STONE * 0.8)
	zone.add_height_box(step, Vector3(1.2, 0, 1.7), 0.45)
	for i in 12:
		if i == 6 or i == 3: continue  # проходы: юг (пандус) и восток (уступ)
		var p := a + Vector3(0, 0, 11).rotated(Vector3.UP, deg_to_rad(i * 30))
		var h := _r(1, 2.5) if i % 3 == 0 else _r(4, 6)
		_add("cylinder", p + Vector3.UP * (ARENA_H + h / 2), Vector3(1.2, h / 2, 1.2), STONE * 0.9)
		_add("box", p + Vector3.UP * (ARENA_H + 0.12), Vector3(1.6, 0.24, 1.6), STONE * 0.8)
		if i % 3 == 0: _rock(p + Vector3(1.5, ARENA_H, 1), 0.8)
	_add("box", c + Vector3(0, ARENA_H + 1.5, 14), Vector3(8, 3, 1.5), STONE * 0.8)
	_glow("box", c + Vector3(0, ARENA_H + 3.8, 14), Vector3(1, 1.6, 1), Color(0.5, 0.3, 0.9), 2.5, preload("res://scripts/game/spin.gd"))
	_light(c + Vector3(0, ARENA_H + 4.5, 12), Color(0.6, 0.4, 1), 1.8, 14)
	for sx in [-1, 1]:
		_light(Vector3(a.x + sx * 3.2, 1.9, low.z + 1.0), Color(1, 0.6, 0.25), 1.2, 7, true)
		_glow("sphere", Vector3(a.x + sx * 3.2, 1.25, low.z + 1.0), Vector3.ONE * 0.25, Color(1, 0.55, 0.2), 4.0)
		_add("cylinder", Vector3(a.x + sx * 3.2, 0.55, low.z + 1.0), Vector3(0.3, 0.55, 0.3), STONE * 0.7)

## Наклонная плита: верхняя грань идёт от low до high (по оси Z), ширина w.
func _ramp(low: Vector3, high: Vector3, w: float) -> void:
	var d := high - low
	var length := d.length()
	var ang := atan2(d.y, Vector2(d.x, d.z).length())
	var yaw := atan2(d.x, d.z)
	var thick := 1.2
	var basis := Basis.from_euler(Vector3(-ang, yaw, 0))
	var top_mid := (low + high) / 2
	var center := top_mid - basis.y * thick / 2
	_add("box", center, Vector3(w, thick, length), STONE * 0.78, Vector3(rad_to_deg(-ang), rad_to_deg(yaw), 0))

func _portal(c: Vector3) -> void:
	var rot := -135.0
	var rb := Basis(Vector3.UP, deg_to_rad(rot))
	for s in [-1, 1]:
		_add("box", c + rb * Vector3(s * 2.0, 2.2, 0), Vector3(0.9, 4.4, 0.9), STONE * 0.8, Vector3(0, rot, 0))
	_add("box", c + rb * Vector3(0, 4.7, 0), Vector3(5.2, 0.8, 1.0), STONE * 0.75, Vector3(0, rot, 0))
	var plane := U.prim("box", self, c + Vector3.UP * 2.1, Vector3(3.1, 4.1, 0.1), Color(0.3, 0.8, 1))
	plane.rotation_degrees.y = rot
	plane.material_override = U.fx_mat(Color(0.3, 0.8, 1, 0.55))
	var portal := Portal.new()
	portal.zone = zone
	portal.target_zone = "global"
	add_child(portal)
	portal.position = c
	_light(c + Vector3.UP * 2.5, Color(0.3, 0.8, 1), 2.0, 10)

## Вход в «Склеп Эфира»: каменный склеп с аркой; до победы над троллем — печать (красный барьер)
func _dungeon_gate(c: Vector3) -> void:
	var rot := 115.0   # арка смотрит на тропу от руин
	var rb := Basis(Vector3.UP, deg_to_rad(rot))
	_add("box", c + rb * Vector3(0, 2.0, -2.2), Vector3(7.0, 4.0, 4.0), STONE * 0.6, Vector3(0, rot, 0))
	_add("box", c + rb * Vector3(0, 4.3, -2.2), Vector3(7.6, 0.6, 4.6), STONE * 0.5, Vector3(0, rot, 0))
	for s in [-1, 1]:
		_add("box", c + rb * Vector3(s * 2.0, 2.0, 0.1), Vector3(0.9, 4.0, 0.9), STONE * 0.75, Vector3(0, rot, 0))
		_glow("sphere", c + rb * Vector3(s * 2.0, 4.3, 0.4), Vector3.ONE * 0.3, Color(0.7, 0.45, 1.0), 3.0)
	_add("box", c + rb * Vector3(0, 4.25, 0.1), Vector3(5.0, 0.7, 1.0), STONE * 0.7, Vector3(0, rot, 0))
	var plane := U.prim("box", self, c + Vector3.UP * 1.9, Vector3(3.1, 3.6, 0.1), Color(0.5, 0.3, 1))
	plane.rotation_degrees.y = rot
	plane.material_override = U.fx_mat(Color(0.55, 0.3, 1.0, 0.6))
	var lbl := Label3D.new()
	lbl.font = UIK.title_font(); lbl.text = "Склеп Эфира"; lbl.font_size = 64; lbl.pixel_size = 0.006
	lbl.outline_size = 10; lbl.modulate = Color(0.85, 0.7, 1.0); lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(lbl); lbl.position = c + Vector3.UP * 5.6
	var portal := Portal.new()
	portal.zone = zone
	portal.target_zone = "dungeon"
	add_child(portal)
	portal.position = c + rb * Vector3(0, 0, 0.8)
	_light(c + Vector3.UP * 2.5 + rb * Vector3(0, 0, 1.5), Color(0.6, 0.4, 1.0), 2.0, 9)
	# печать: пока тролль жив
	dungeon_seal = Node3D.new(); add_child(dungeon_seal)
	var seal := U.prim("box", dungeon_seal, c + Vector3.UP * 1.9 + rb * Vector3(0, 0, 0.5), Vector3(3.4, 3.8, 0.15), Color(1, 0.2, 0.15))
	seal.rotation_degrees.y = rot
	seal.material_override = U.fx_mat(Color(1, 0.15, 0.1, 0.45))
	dungeon_seal.visible = DB.zone_lock_reason(zone.data, "dungeon") != ""

func update_seal() -> void:
	if dungeon_seal: dungeon_seal.visible = DB.zone_lock_reason(zone.data, "dungeon") != ""

func _scatter() -> void:
	for i in 90:
		var p := _rand_pos(SIZE - 6)
		if p.length() < 16 or _dist_to_path(p) < 3: continue
		if p.distance_to(POND) < POND_R + 3 or p.distance_to(dungeon_gate_point) < 8 or p.distance_to(Vector3(-4, 0, 64)) < 16 or p.distance_to(Vector3(52, 0, -14)) < 13 or p.distance_to(Vector3(6, 0, -46)) < 13 or p.distance_to(Vector3(66, 0, 56)) < 6: continue
		if rng.randf() < 0.65: _tree(p, _r(0.7, 1.3), rng.randf() < 0.4)
		else: _rock(p, _r(0.5, 1.6))

func _boundary() -> void:
	for i in 72:
		var p := Vector3(0, 0, SIZE + _r(0, 6)).rotated(Vector3.UP, deg_to_rad(i * 5))
		var s := _r(8, 16)
		var c := STONE * _r(0.6, 0.85); c.a = 1
		_add("sphere", p + Vector3.UP * s * 0.2, Vector3(s, s * _r(0.8, 1.3), s), c, Vector3(0, _r(0, 360), 0))
	for i in 4:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new(); bs.size = Vector3(SIZE * 2, 10, 1)
		cs.shape = bs
		var b := Basis(Vector3.UP, deg_to_rad(i * 90))
		cs.transform = Transform3D(b, b * Vector3(0, 5, SIZE - 4))
		_colliders.add_child(cs)
