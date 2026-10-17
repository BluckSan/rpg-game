class_name WorldDress
extends Node3D
## Атмосфера открытого мира (v0.5.1): небо с облаками, грейдинг по биому (солнце, туман, насыщенность),
## частицы окружения (пыльца, светлячки, листья, пыль, снег, искры эфира), мирные зверьки и жители городов.
## Всё по пресету: Низкое — почти ничего; Среднее (телефон) — немного частиц, без света; Высокое+ — полностью.

const GRADE := {
	"meadows": {"sun": Color(1.0, 0.93, 0.80), "sun_e": 1.45, "fog": Color(0.72, 0.80, 0.88), "top": Color(0.26, 0.50, 0.86), "hor": Color(0.74, 0.82, 0.90),
		"amb": Color(0.60, 0.64, 0.68), "sat": 1.14, "con": 1.06, "bri": 1.0, "cov": 0.46, "fx": ["pollen", "butterfly"]},
	"forest": {"sun": Color(1.0, 0.90, 0.72), "sun_e": 1.2, "fog": Color(0.50, 0.62, 0.52), "top": Color(0.30, 0.48, 0.72), "hor": Color(0.60, 0.70, 0.62),
		"amb": Color(0.44, 0.54, 0.46), "sat": 1.1, "con": 1.1, "bri": 0.98, "cov": 0.55, "fx": ["leaves", "fireflies"]},
	"desert": {"sun": Color(1.0, 0.86, 0.64), "sun_e": 1.65, "fog": Color(0.88, 0.76, 0.58), "top": Color(0.34, 0.55, 0.86), "hor": Color(0.92, 0.82, 0.66),
		"amb": Color(0.70, 0.64, 0.56), "sat": 1.06, "con": 1.08, "bri": 1.03, "cov": 0.22, "fx": ["dust", ""]},
	"swamp": {"sun": Color(0.86, 0.90, 0.70), "sun_e": 1.0, "fog": Color(0.45, 0.52, 0.40), "top": Color(0.34, 0.42, 0.42), "hor": Color(0.56, 0.60, 0.50),
		"amb": Color(0.42, 0.48, 0.40), "sat": 0.92, "con": 1.06, "bri": 0.97, "cov": 0.7, "fx": ["fireflies", "spores"]},
	"snow": {"sun": Color(0.92, 0.96, 1.0), "sun_e": 1.35, "fog": Color(0.82, 0.88, 0.96), "top": Color(0.40, 0.56, 0.82), "hor": Color(0.86, 0.90, 0.97),
		"amb": Color(0.66, 0.72, 0.80), "sat": 0.96, "con": 1.06, "bri": 1.0, "cov": 0.62, "fx": ["snow", ""]},
	"ruins": {"sun": Color(0.92, 0.80, 1.0), "sun_e": 1.05, "fog": Color(0.50, 0.42, 0.60), "top": Color(0.24, 0.22, 0.44), "hor": Color(0.56, 0.46, 0.64),
		"amb": Color(0.48, 0.42, 0.56), "sat": 1.06, "con": 1.12, "bri": 0.96, "cov": 0.58, "fx": ["motes", "embers"]},
}
## Частицы: цвет, размер, скорость (вектор), разброс, турбулентность, время жизни, штук (на «Очень высоком»), свечение
const FX := {
	"pollen": [Color(1.0, 0.95, 0.7, 0.8), 0.06, Vector3(0.3, 0.05, 0.1), 0.4, 0.6, 7.0, 120, false],
	"butterfly": [Color(1.0, 0.7, 0.3, 1.0), 0.16, Vector3(0.6, 0.2, 0.3), 1.0, 1.4, 6.0, 20, false],
	"leaves": [Color(0.75, 0.55, 0.2, 1.0), 0.16, Vector3(0.4, -0.7, 0.2), 0.3, 0.9, 8.0, 70, false],
	"fireflies": [Color(0.7, 1.0, 0.4, 1.0), 0.09, Vector3(0, 0.05, 0), 0.4, 1.2, 5.0, 60, true],
	"dust": [Color(0.85, 0.72, 0.52, 0.45), 0.12, Vector3(2.2, 0.1, 0.6), 0.15, 0.8, 5.0, 140, false],
	"spores": [Color(0.75, 0.85, 0.45, 0.6), 0.07, Vector3(0.1, 0.25, 0.05), 0.5, 0.5, 7.0, 90, false],
	"snow": [Color(1, 1, 1, 0.9), 0.07, Vector3(0.5, -1.4, 0.2), 0.2, 0.6, 7.0, 260, false],
	"motes": [Color(0.75, 0.5, 1.0, 1.0), 0.08, Vector3(0, 0.45, 0), 0.4, 0.7, 6.0, 90, true],
	"embers": [Color(1.0, 0.5, 0.25, 1.0), 0.05, Vector3(0.2, 0.7, 0.1), 0.5, 1.0, 4.0, 40, true],
}
## Мирные зверьки по биомам: модель, масштаб, скорость
const CRITTERS := {
	"meadows": [["rat", 0.45, 2.6], ["bee", 0.35, 1.8]], "forest": [["rat", 0.45, 2.6], ["spider", 0.3, 2.2]],
	"desert": [["rat", 0.4, 2.8]], "swamp": [["frog", 0.35, 1.6]], "snow": [["rat", 0.42, 2.4]], "ruins": [["bat", 0.55, 3.0]],
}

var zone
var wb
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ShaderMaterial
var parts: Array = []          # 2 системы частиц
var _fx_kinds := ["", ""]
var _cur := {}                 # текущие (плавные) значения грейдинга
var _target := {}
var _sample_t := 0.0
var _sky_t := 0.0
var _sky_applied := {}
var critters: Array = []       # {node, vel, t}
var _critter_t := 1.0
var npcs: Array = []           # {node, town, home, target, t, walker}
var _npc_built := {}
static var _cloud_tex: NoiseTexture2D
static var _soft_tex: GradientTexture2D
static var _pmats := {}

static func cloud_texture() -> NoiseTexture2D:
	if _cloud_tex == null:
		_cloud_tex = NoiseTexture2D.new(); _cloud_tex.width = 256; _cloud_tex.height = 256; _cloud_tex.seamless = true
		var n := FastNoiseLite.new(); n.frequency = 0.012; n.fractal_octaves = 4; n.seed = 77
		_cloud_tex.noise = n; _cloud_tex.normalize = true
	return _cloud_tex

## Мягкая круглая частица (общая текстура-градиент); additive — для огня/светлячков
static func soft_particle_material(additive := false) -> StandardMaterial3D:
	var key := "add" if additive else "mix"
	if _pmats.has(key): return _pmats[key]
	if _soft_tex == null:
		_soft_tex = GradientTexture2D.new(); _soft_tex.width = 32; _soft_tex.height = 32
		_soft_tex.fill = GradientTexture2D.FILL_RADIAL; _soft_tex.fill_from = Vector2(0.5, 0.5); _soft_tex.fill_to = Vector2(1.0, 0.5)
		var g := Gradient.new(); g.set_color(0, Color(1, 1, 1, 1)); g.set_color(1, Color(1, 1, 1, 0))
		_soft_tex.gradient = g
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive: m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_tex
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.disable_fog = additive
	_pmats[key] = m
	return m

func setup(z, builder) -> void:
	zone = z; wb = builder
	sun = builder.get_node_or_null("Sun")
	var we: WorldEnvironment = builder.get_node_or_null("Env")
	if we: env = we.environment
	if env and env.sky:
		sky_mat = ShaderMaterial.new(); sky_mat.shader = load("res://shaders/sky_clouds.gdshader")
		env.sky.sky_material = sky_mat
	for i in 2:
		var gp := GPUParticles3D.new(); gp.name = "Ambient%d" % i
		gp.local_coords = false
		gp.visibility_aabb = AABB(Vector3(-40, -15, -40), Vector3(80, 40, 80))
		add_child(gp); parts.append(gp)
	_sample(true)
	apply_graphics()

func apply_graphics() -> void:
	if env:
		env.adjustment_enabled = Game.quality >= 1
	if sky_mat: sky_mat.set_shader_parameter("clouds_on", Game.quality >= 1)
	_fx_kinds = ["", ""]   # пересобрать частицы под новый множитель
	_sample(true)
	if Game.quality <= 0: _clear_critters()

## Смесь грейдинга по весам биомов в точке героя
func _sample(force := false) -> void:
	if zone == null or zone.player == null: return
	var p: Vector3 = zone.player.global_position
	var w := WorldData.biome_weights(p.x, p.z)
	var t := {}
	var best := 0
	for i in w.size():
		if w[i] > w[best]: best = i
		var g: Dictionary = GRADE[WorldData.BIOMES[i].id]
		for k in g:
			if k == "fx": continue
			if not t.has(k): t[k] = (g[k] * 0.0) if (g[k] is Color or g[k] is float) else g[k]
			t[k] += g[k] * w[i]
	_target = t
	if force or _cur.is_empty(): _cur = t.duplicate()
	var fx: Array = GRADE[WorldData.BIOMES[best].id].fx
	for i in 2:
		if fx[i] != _fx_kinds[i]: _set_fx(i, fx[i])

func _set_fx(i: int, kind: String) -> void:
	_fx_kinds[i] = kind
	var gp: GPUParticles3D = parts[i]
	if kind == "" or Game.quality <= 0:
		gp.emitting = false; gp.visible = false; return
	var f: Array = FX[kind]
	var n := int(float(f[6]) * Game.particle_mul * (0.6 if not Game.desktop else 1.0))
	if n < 4:
		gp.emitting = false; gp.visible = false; return
	gp.visible = true
	gp.amount = n
	gp.lifetime = f[5]
	gp.preprocess = f[5]
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(24, 5 if kind != "snow" and kind != "leaves" else 3, 24)
	var v: Vector3 = f[2]
	pm.direction = v.normalized() if v.length() > 0.01 else Vector3.UP
	pm.spread = 180.0 * float(f[3])
	pm.initial_velocity_min = v.length() * 0.6; pm.initial_velocity_max = v.length() * 1.3 + 0.1
	pm.gravity = Vector3.ZERO
	pm.turbulence_enabled = float(f[4]) > 0.0 and Game.quality >= 2
	pm.turbulence_noise_strength = float(f[4]); pm.turbulence_noise_scale = 4.0
	pm.scale_min = 0.6; pm.scale_max = 1.4
	if kind in ["leaves", "butterfly"]:
		pm.angle_min = -180; pm.angle_max = 180; pm.angular_velocity_min = -120; pm.angular_velocity_max = 120
	var c: Color = f[0]
	var grad := Gradient.new()
	grad.set_color(0, Color(c, 0.0)); grad.add_point(0.2, c); grad.add_point(0.8, c); grad.set_color(grad.get_point_count() - 1, Color(c, 0.0))
	var gt := GradientTexture1D.new(); gt.gradient = grad
	pm.color_ramp = gt
	if kind == "leaves":
		pm.color_initial_ramp = _ramp([Color(0.85, 0.55, 0.15), Color(0.55, 0.65, 0.2), Color(0.7, 0.3, 0.1)])
	elif kind == "butterfly":
		pm.color_initial_ramp = _ramp([Color(1, 0.6, 0.2), Color(0.5, 0.7, 1.0), Color(1, 1, 0.6), Color(0.9, 0.4, 0.8)])
	gp.process_material = pm
	var q := QuadMesh.new()
	var sz: float = f[1]
	q.size = Vector2(sz, sz * (0.6 if kind in ["leaves", "butterfly"] else 1.0)) * 2.0
	q.material = soft_particle_material(bool(f[7]))
	gp.draw_pass_1 = q
	gp.emitting = true
	gp.restart()

func _ramp(cols: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, cols[0]); g.set_color(1, cols[cols.size() - 1])
	for i in range(1, cols.size() - 1): g.add_point(float(i) / (cols.size() - 1), cols[i])
	var t := GradientTexture1D.new(); t.gradient = g
	return t

func _process(delta: float) -> void:
	if zone == null or zone.player == null: return
	var p: Vector3 = zone.player.global_position
	for gp in parts: gp.global_position = p + Vector3.UP * 3.0
	_sample_t -= delta
	if _sample_t <= 0:
		_sample_t = 0.5
		_sample()
	# плавно к целевым значениям
	var k := minf(1.0, delta * 0.8)
	for key in _target:
		_cur[key] = _cur[key].lerp(_target[key], k) if _cur[key] is Color else lerpf(_cur[key], _target[key], k)
	_apply_grade(delta)
	if Game.quality >= 1: _critters_tick(delta, p)
	_npcs_tick(delta, p)

func _apply_grade(delta: float) -> void:
	if _cur.is_empty(): return
	if sun:
		sun.light_color = _cur.sun; sun.light_energy = _cur.sun_e
	if env:
		env.fog_light_color = _cur.fog
		env.ambient_light_color = _cur.amb
		if env.adjustment_enabled:
			env.adjustment_saturation = _cur.sat; env.adjustment_contrast = _cur.con; env.adjustment_brightness = _cur.bri
	# небо: редко и только при заметной разнице (пересчёт отражений)
	_sky_t -= delta
	if sky_mat and _sky_t <= 0:
		_sky_t = 1.0
		var top: Color = _cur.top
		if _sky_applied.is_empty() or (top - (_sky_applied.top as Color)).get_luminance() > 0.01 or absf(top.r - _sky_applied.top.r) + absf(top.g - _sky_applied.top.g) + absf(top.b - _sky_applied.top.b) > 0.02:
			_sky_applied = {"top": top}
			sky_mat.set_shader_parameter("top_col", top)
			sky_mat.set_shader_parameter("hor_col", _cur.hor)
			sky_mat.set_shader_parameter("ground_col", (_cur.fog as Color).darkened(0.5))
			sky_mat.set_shader_parameter("coverage", _cur.cov)
			sky_mat.set_shader_parameter("cloud_shadow", (_cur.hor as Color).darkened(0.25))

# ---------------- зверьки ----------------
func _clear_critters() -> void:
	for c in critters: if is_instance_valid(c.node): c.node.queue_free()
	critters.clear()

func _critters_tick(delta: float, p: Vector3) -> void:
	var cap := 3 if Game.quality == 1 else (5 if Game.quality == 2 else 7)
	_critter_t -= delta
	if _critter_t <= 0:
		_critter_t = 1.5
		for c in critters.duplicate():
			if not is_instance_valid(c.node) or U.flat_dist(c.node.global_position, p) > 55.0:
				if is_instance_valid(c.node): c.node.queue_free()
				critters.erase(c)
		if critters.size() < cap:
			var a := randf() * TAU
			var sp := p + Vector3(cos(a), 0, sin(a)) * randf_range(16, 32)
			if WorldData.town_dist(sp.x, sp.z) > WorldData.TOWN_R and WorldData.road_dist(sp.x, sp.z) > 3.0:
				var b := WorldData.biome_at(sp.x, sp.z)
				var opts: Array = CRITTERS[WorldData.BIOMES[b].id]
				var o: Array = opts[randi() % opts.size()]
				var mm := MobModel.new(); mm.name = "Critter"
				add_child(mm)
				mm.setup(o[0], {"scale": float(o[1])})
				sp.y = zone.ground_y(sp)
				mm.global_position = sp
				U.set_view_range(mm, 45.0)
				critters.append({"node": mm, "vel": Vector3.ZERO, "t": 0.0, "speed": float(o[2]), "kind": o[0]})
	for c in critters:
		var n: Node3D = c.node
		if not is_instance_valid(n): continue
		c.t -= delta
		var away := U.flat(n.global_position - p)
		var spd := 0.0
		if away.length() < 6.0:   # пугается героя
			c.vel = away.normalized() * c.speed * 1.8; spd = c.speed * 1.8
		elif c.t <= 0:
			c.t = randf_range(1.5, 4.0)
			c.vel = Vector3.ZERO if randf() < 0.45 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * c.speed * 0.5
		var v: Vector3 = c.vel
		if v.length_squared() > 0.01:
			var np := n.global_position + v * delta
			np.y = zone.ground_y(np)
			n.global_position = np
			n.rotation.y = lerp_angle(n.rotation.y, atan2(v.x, v.z), minf(1.0, delta * 8))

# ---------------- жители городов ----------------
func _npcs_tick(delta: float, p: Vector3) -> void:
	# строим жителей, когда герой подходит к городу (до 120 м), и прячем дальних
	for i in WorldData.TOWNS.size():
		var tp: Vector2 = WorldData.TOWNS[i].pos
		var d := Vector2(p.x, p.z).distance_to(tp)
		if d < 120.0 and not _npc_built.has(i): _build_npcs(i)
	for n in npcs:
		var node: Node3D = n.node
		if not is_instance_valid(node): continue
		var near := U.flat_dist(node.global_position, p) < 70.0
		node.visible = near
		node.process_mode = Node.PROCESS_MODE_INHERIT if near else Node.PROCESS_MODE_DISABLED
		if not near: continue
		n.t -= delta
		if n.walker:
			var to := U.flat(n.target - node.global_position)
			if to.length() < 0.4:
				n.target = n.home + Vector3(randf_range(-9, 9), 0, randf_range(-9, 9))
				n.t = randf_range(2.0, 5.0)
			elif n.t <= 0:
				var step := to.normalized() * 1.3 * delta
				var np: Vector3 = node.global_position + step
				np.y = zone.ground_y(np)
				node.global_position = np
				node.rotation.y = lerp_angle(node.rotation.y, atan2(to.x, to.z), minf(1.0, delta * 6))
		elif n.t <= 0:
			n.t = randf_range(5.0, 11.0)
			node.play_anim(["interact", "cheer", "idle_fold", "consume", "dance"][randi() % 5] if randf() < 0.8 else "idle_fold", 1.0, false)

func _build_npcs(i: int) -> void:
	_npc_built[i] = true
	var t: Dictionary = WorldData.TOWNS[i]
	var c := Vector3(t.pos.x, 0, t.pos.y)
	var count := 6 if t.kind == "town" else 4
	if Game.quality <= 0: count = 2
	elif Game.quality == 1: count = mini(count, 4)
	var rr := RandomNumberGenerator.new(); rr.seed = hash(t.id)
	var jobs := ["Горожанин", "Стражник", "Путник", "Травница", "Кузнец", "Охотник"]
	for j in count:
		var a := rr.randf() * TAU
		var r := rr.randf_range(7.0, 16.0)
		var pos := c + Vector3(cos(a) * r, 0, sin(a) * r)
		pos.y = zone.ground_y(pos)
		var cv := CharVisual.new(); cv.name = "Townsfolk_%d_%d" % [i, j]
		add_child(cv)
		var look := CharAssets.random_look(rr.randi() % 2, rr)
		cv.build(look, ["warrior", "archer", "mage"][j % 3], "")
		cv.global_position = pos
		cv.rotation.y = rr.randf() * TAU
		U.set_view_range(cv, 60.0)
		var lbl := Label3D.new()
		lbl.font = UIK.title_font(); lbl.text = jobs[j % jobs.size()]; lbl.font_size = 40; lbl.pixel_size = 0.006
		lbl.outline_size = 8; lbl.modulate = Color(0.85, 0.9, 1.0); lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.visibility_range_end = 22.0
		cv.add_child(lbl); lbl.position = Vector3(0, 2.4, 0)
		var walker := j % 2 == 1
		npcs.append({"node": cv, "town": i, "home": pos, "target": pos, "t": rr.randf_range(0.5, 4.0), "walker": walker})
