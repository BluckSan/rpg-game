extends StarterZoneBuilder
class_name WorldBuilder
## «Земли Эфира» — открытый мир 2×2 км с подгрузкой чанков 64×64 м.
## Чанк: ландшафт (ArrayMesh, 7 слоёв ambientCG), столкновения (HeightMapShape3D, только ближнее кольцо),
## пропсы Kenney (MultiMesh, общий материал с цветом вершин), вода в топях.
## Генерация данных чанка — в фоновых потоках (WorkerThreadPool), сборка узлов — в основном, по одному за кадр.
## LOD: ближнее кольцо 3×3 — полная сетка 2 м, столкновения, мелкие пропсы; дальше — сетка 8 м и только крупные пропсы;
## дальность видимости у пропсов (visibility_range) от пресета.

const RES_NEAR := 32
const RES_FAR := 8
const ACTIVATE_R := 120.0      # спавнеры включаются ближе этого
const DEACTIVATE_R := 165.0

## Пропсы по биомам: [ключ, штук на чанк, масштаб от, до, тип: 0 — дерево (столкновение), 1 — камень (столкновение), 2 — мелочь (только рядом)]
## [ключ, штук на чанк, масштаб от, до, тип: 0 — дерево (столкновение), 1 — крупный камень, 2 — мелочь без столкновения]
const PROPS := {
	# v0.6.0: реалистичные деревья (TreeGen), растения/камни/брёвна Poly Haven (CC0); «*» — случайный вариант
	"meadows": [["tree:oak*", 5, 0.8, 1.15, 0], ["tree:birch*", 2, 0.8, 1.1, 0], ["tree:autumn*", 1, 0.8, 1.1, 0],
		["real:shrub*", 7, 0.8, 1.4, 2], ["real:fern*", 6, 1.0, 1.6, 2], ["real:dandelion*", 14, 2.0, 3.0, 2], ["real:periwinkle*", 10, 2.0, 3.0, 2],
		["real:sorrel", 8, 2.5, 3.5, 2], ["real:rock_boulder", 1, 1.0, 2.2, 1], ["real:rock_mossb*", 4, 0.6, 1.4, 2], ["real:stump*", 1, 0.8, 1.1, 2],
		["real:grassclump*", 20, 2.0, 3.0, 2]],
	"forest": [["tree:fir*", 9, 0.8, 1.2, 0], ["tree:pine*", 6, 0.85, 1.15, 0], ["tree:oak*", 3, 0.9, 1.2, 0], ["tree:dead*", 1, 0.8, 1.0, 0],
		["real:log", 2, 0.8, 1.2, 1], ["real:stump*", 3, 0.8, 1.2, 2], ["real:roots", 1, 0.7, 1.0, 2], ["real:branches*", 6, 1.5, 2.5, 2],
		["real:fern*", 16, 1.0, 1.8, 2], ["real:nettle*", 12, 3.0, 4.5, 2], ["real:shrub*", 5, 0.8, 1.3, 2], ["real:rock_moss*", 3, 0.6, 1.3, 1],
		["real:rock_mossb*", 4, 0.5, 1.0, 2]],
	"desert": [["real:quiver", 3, 1.6, 2.6, 0], ["real:quiver_dead", 2, 1.5, 2.5, 0], ["tree:dead*", 1, 0.7, 0.9, 0],
		["real:rock_desert", 3, 1.2, 2.6, 1], ["real:rock_flat", 3, 1.0, 2.5, 1], ["real:rock_round", 2, 1.2, 2.8, 1], ["real:rock_boulder", 3, 0.6, 1.2, 2],
		["real:rooibos*", 10, 1.2, 2.0, 2], ["real:weed*", 14, 2.0, 3.5, 2], ["real:tuft*", 10, 2.0, 3.0, 2], ["real:branches*", 4, 1.5, 2.5, 2]],
	"swamp": [["tree:swamp*", 6, 0.8, 1.2, 0], ["tree:dead*", 3, 0.8, 1.1, 0], ["tree:oak*", 1, 0.8, 1.0, 0],
		["real:log", 3, 0.8, 1.2, 2], ["real:roots", 2, 0.8, 1.1, 2], ["real:stump_b", 2, 0.9, 1.2, 2],
		["real:fern*", 12, 1.0, 1.6, 2], ["real:grassclump*", 24, 2.5, 4.0, 2], ["real:nettle*", 8, 3.0, 4.0, 2],
		["nature_lily_large", 10, 3.0, 4.5, 2], ["nature_lily_small", 10, 3.0, 4.5, 2], ["real:rock_mossb*", 3, 0.6, 1.2, 2]],
	"snow": [["tree:snowfir*", 10, 0.8, 1.2, 0], ["tree:dead*", 1, 0.7, 1.0, 0], ["real:rock_round", 3, 1.2, 2.5, 1], ["real:rock_boulder", 3, 1.0, 2.2, 1],
		["real:rock_moss*", 4, 0.7, 1.4, 1], ["real:rock_mossb*", 6, 0.5, 1.0, 2], ["real:branches*", 4, 1.5, 2.2, 2], ["real:tuft*", 6, 2.0, 3.0, 2]],
	"ruins": [["tree:dead*", 3, 0.8, 1.1, 0], ["tree:oak*", 2, 0.8, 1.0, 0], ["tree:fir*", 2, 0.8, 1.0, 0],
		["nature_statue_column", 2, 4.0, 5.0, 1], ["nature_statue_columnDamaged", 3, 4.0, 5.0, 1], ["graveyard_gravestone-broken", 5, 3.0, 4.0, 2],
		["graveyard_stone-wall-damaged", 2, 4.0, 5.0, 1], ["nature_statue_block", 2, 3.0, 4.0, 1], ["real:rock_moss*", 3, 0.8, 1.4, 1],
		["real:rock_mossb*", 5, 0.5, 1.0, 2], ["real:branches*", 4, 1.5, 2.5, 2], ["real:roots", 1, 0.8, 1.0, 2], ["real:nettle*", 8, 3.0, 4.0, 2],
		["real:fern*", 6, 1.0, 1.4, 2]],
}

var chunks := {}          # Vector2i -> {lod, node, heights, res}
var _tasks := {}          # Vector2i -> {id, lod, out}
var _queue: Array = []    # [Vector2i, lod] по приоритету
var _focus := Vector3(INF, 0, INF)
var _focus_chunk := Vector2i(99999, 99999)
var terrain_mat: ShaderMaterial
var spawners: Array = []
var waypoints: Array = []     # {id, name, pos: Vector3}
var bosses: Array = []        # {biome, name, pos, spawner}
var merchant_points: Array = []
var current_biome := -1
var _spawn_check := 0.0
var _wp_check := 0.0
var built_count := 0          # для тестов
var dress: WorldDress           # атмосфера: небо, грейдинг, частицы, зверьки, жители
var map_features: Array = []    # для подробной карты: {type, pos: Vector2, size: Vector2, yaw, name}
static var _blade: ArrayMesh
static var _grass_mat: ShaderMaterial
static var _water_mat: ShaderMaterial
var max_build_ms := 0.0
static var _props := {}       # key -> Mesh
static var feature_sink = null  # массив: сюда prop() пишет постройки городов/точек — для подробной карты
static var _prop_mat: StandardMaterial3D

# ---------------- библиотека пропсов ----------------
## v0.6.0: ключи "real:"/"tree:" — реалистичные меши со своими PBR-материалами; старые ключи Kenney
## по возможности заменяются реалистичными (Real.replacement), остальные — с трипланарным PBR-материалом.
static func prop_mesh(key: String, lod := 0) -> Mesh:
	if Real.is_real(key): return Real.mesh(key, lod)
	if not _props.has(key):
		var p := "res://assets/world/props/%s.res" % key
		_props[key] = load(p) if ResourceLoader.exists(p) else null
	return _props[key]

## [ключ, множитель масштаба] — с учётом замены Kenney → реалистичная модель
static var _resolved := {}
static func resolve(key: String) -> Array:
	if Real.is_real(key): return [key, 1.0]
	if _resolved.has(key): return _resolved[key]
	var out := [key, 1.0]
	var r := Real.replacement(key)
	if not r.is_empty():
		var nm := Real.mesh(r[0])
		var om := prop_mesh(key)
		if nm != null:
			var f := 1.0
			if om != null:
				f = clampf(om.get_aabb().size.y / maxf(nm.get_aabb().size.y, 0.01), r[1], r[2])
			out = [r[0], f]
	_resolved[key] = out
	return out

static func prop_material() -> Material:
	return Real.surf_material()

## Отдельный проп (города, точки интереса): MeshInstance3D; реалистичные — со своими материалами
static func prop(parent: Node, key: String, pos: Vector3, yaw_deg: float, s: float) -> MeshInstance3D:
	var rv := resolve(key)
	var mi := MeshInstance3D.new()
	mi.mesh = prop_mesh(rv[0])
	if not Real.is_real(rv[0]): mi.material_override = Real.kenney_material(rv[0])
	parent.add_child(mi)
	mi.position = pos
	mi.rotation_degrees.y = yaw_deg
	mi.scale = Vector3.ONE * s * float(rv[1])
	if feature_sink != null and mi.is_inside_tree():
		var g := mi.global_position
		var ab := mi.get_aabb()
		feature_sink.append({"key": key, "pos": Vector2(g.x, g.z), "size": Vector2(ab.size.x, ab.size.z) * s * float(rv[1]), "yaw": mi.global_rotation.y})
	return mi

# ---------------- сборка ----------------
func build(z) -> void:
	zone = z
	WorldData.init()
	Real.prewarm()
	rng.seed = 2026
	_colliders = StaticBody3D.new(); _colliders.name = "Colliders"; _colliders.collision_layer = 1
	add_child(_colliders)
	enemies_root = Node3D.new(); enemies_root.name = "Enemies"; add_child(enemies_root)
	_lighting()
	var we: WorldEnvironment = get_node_or_null("Env")
	if we: we.environment.fog_light_color = Color(0.7, 0.75, 0.8)
	terrain_mat = ShaderMaterial.new()
	terrain_mat.shader = load("res://shaders/terrain.gdshader")
	terrain_mat.set_shader_parameter("layers", load("res://assets/terrain/layers.jpg"))
	terrain_mat.set_shader_parameter("normals", load("res://assets/terrain/normals.jpg"))
	terrain_mat.set_shader_parameter("cloud_noise", WorldDress.cloud_texture())
	_terrain_tier()
	var t0: Dictionary = WorldData.TOWNS[0]
	var tp := Vector3(t0.pos.x, 0, t0.pos.y)
	spawn_point = tp + Vector3(4, 0, 12)
	spawn_point.y = WorldData.height(spawn_point.x, spawn_point.z) + 0.2
	merchant_point = Vector3(INF, 0, INF)
	portal_point = tp + Vector3(0, 0, 26); portal_point.y = WorldData.height(portal_point.x, portal_point.z)
	arena_point = Vector3.ZERO
	dungeon_gate_point = Vector3.ZERO
	feature_sink = map_features
	for i in WorldData.TOWNS.size(): _town(i)
	for p in WorldData.POIS: _poi(p)
	feature_sink = null
	_world_spawners()
	_world_edges()
	# старт: чанки вокруг игрока — сразу, чтобы он не провалился
	var start := spawn_point
	if z.data.get("has_pos", false) and z.data.get("zone", "") == "global":
		start = Vector3(z.data["pos"][0], z.data["pos"][1], z.data["pos"][2])
	prepare(start)
	dress = WorldDress.new(); dress.name = "Dress"
	add_child(dress)
	dress.setup(z, self)
	add_to_group("graphics_listeners")
	apply_graphics()

func apply_graphics() -> void:
	super.apply_graphics()
	if terrain_mat: _terrain_tier()
	Real.apply_graphics()
	if dress: dress.apply_graphics()
	_focus_chunk = Vector2i(99999, 99999)   # пересчитать кольца под новую дальность

func is_dungeon_env() -> bool: return false

## v0.6.0: реалистичная земля на всех пресетах (PBR-текстуры, смешение по высоте, трипланарная скала).
## Пресет меняет только технику: нормали — Среднее+, второй масштаб — Высокое+, тени облаков — Среднее+.
func _terrain_tier() -> void:
	var q := Game.quality
	terrain_mat.set_shader_parameter("tex_on", true)
	terrain_mat.set_shader_parameter("normals_on", q >= 1)
	terrain_mat.set_shader_parameter("anti_tile", q >= 2)
	terrain_mat.set_shader_parameter("triplanar_rock", true)
	terrain_mat.set_shader_parameter("clouds_on", q >= 1)

## Высота земли (для врагов, лута): по сетке загруженного чанка — совпадает со столкновением; иначе — формула
func height_at(p: Vector3) -> float:
	var c := chunk_of(p)
	var ch = chunks.get(c)
	if ch != null and ch.lod == 0:
		var res: int = ch.res
		var cell := WorldData.CHUNK / res
		var lx := (p.x - c.x * WorldData.CHUNK) / cell
		var lz := (p.z - c.y * WorldData.CHUNK) / cell
		var ix := clampi(int(lx), 0, res - 1); var iz := clampi(int(lz), 0, res - 1)
		var fx := clampf(lx - ix, 0, 1); var fz := clampf(lz - iz, 0, 1)
		var hs: PackedFloat32Array = ch.heights
		var w := res + 1
		var h00 := hs[iz * w + ix]; var h10 := hs[iz * w + ix + 1]
		var h01 := hs[(iz + 1) * w + ix]; var h11 := hs[(iz + 1) * w + ix + 1]
		# как у треугольников HeightMapShape3D
		if fx + fz <= 1.0: return h00 + (h10 - h00) * fx + (h01 - h00) * fz
		return h11 + (h01 - h11) * (1.0 - fx) + (h10 - h11) * (1.0 - fz)
	return WorldData.height(p.x, p.z)

static func chunk_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / WorldData.CHUNK), floori(p.z / WorldData.CHUNK))

func near_radius() -> float:
	return maxf(Game.view_distance, 60.0) + WorldData.CHUNK * 0.5

## Синхронно построить ближние чанки (старт, быстрое перемещение, возрождение)
func prepare(p: Vector3) -> void:
	var c := chunk_of(p)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var k := c + Vector2i(dx, dz)
			if _valid(k) and (not chunks.has(k) or chunks[k].lod != 0):
				_apply(k, 0, gen_chunk(k, 0, Game.quality))
	_focus_chunk = Vector2i(99999, 99999)
	_update_stream(p)

func _valid(k: Vector2i) -> bool:
	var n := int(WorldData.HALF / WorldData.CHUNK)
	return k.x >= -n and k.x < n and k.y >= -n and k.y < n

func _process(delta: float) -> void:
	if zone == null or zone.player == null: return
	var p: Vector3 = zone.player.global_position
	_update_stream(p)
	_pump()
	_spawn_check -= delta
	if _spawn_check <= 0:
		_spawn_check = 0.5
		_update_spawners(p)
		_update_biome(p)
	_wp_check -= delta
	if _wp_check <= 0:
		_wp_check = 0.4
		_discover(p)

## Какие чанки нужны и с какой детализацией
func _update_stream(p: Vector3) -> void:
	var c := chunk_of(p)
	if c == _focus_chunk: return
	_focus_chunk = c
	_focus = p
	var r := near_radius()
	var n := int(ceil(r / WorldData.CHUNK)) + 1
	var want := {}
	for dz in range(-n, n + 1):
		for dx in range(-n, n + 1):
			var k := c + Vector2i(dx, dz)
			if not _valid(k): continue
			var rect := Rect2(k.x * WorldData.CHUNK, k.y * WorldData.CHUNK, WorldData.CHUNK, WorldData.CHUNK)
			var d := _rect_dist(rect, Vector2(p.x, p.z))
			if d > r: continue
			want[k] = 0 if (absi(dx) <= 1 and absi(dz) <= 1) else 1
	# выгрузка
	for k in chunks.keys():
		if not want.has(k):
			var rect := Rect2(k.x * WorldData.CHUNK, k.y * WorldData.CHUNK, WorldData.CHUNK, WorldData.CHUNK)
			if _rect_dist(rect, Vector2(p.x, p.z)) > r + 24.0:   # гистерезис
				chunks[k].node.queue_free(); chunks.erase(k)
	# очередь: сначала ближние
	_queue.clear()
	for k in want:
		var lod: int = want[k]
		if chunks.has(k) and chunks[k].lod <= lod: continue
		if _tasks.has(k) and _tasks[k].lod <= lod: continue
		_queue.append([k, lod])
	_queue.sort_custom(func(a, b): return (a[0] - c).length_squared() < (b[0] - c).length_squared())

static func _rect_dist(r: Rect2, p: Vector2) -> float:
	var dx := maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
	var dz := maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)
	return sqrt(dx * dx + dz * dz)

## Фоновые задачи: до 2 одновременно; готовые — собрать (одну за кадр)
func _pump() -> void:
	var t0 := Time.get_ticks_usec()
	var applied := false
	for k in _tasks.keys():
		var t: Dictionary = _tasks[k]
		if WorkerThreadPool.is_task_completed(t.id):
			WorkerThreadPool.wait_for_task_completion(t.id)
			_tasks.erase(k)
			if applied: continue
			if _wanted(k, t.lod):
				_apply(k, t.lod, t.out)
				applied = true
	while _tasks.size() < 2 and not _queue.is_empty():
		var q: Array = _queue.pop_front()
		var k: Vector2i = q[0]; var lod: int = q[1]
		var out := {}
		var qual := Game.quality
		var id := WorkerThreadPool.add_task(func(): out.merge(gen_chunk(k, lod, qual)), false, "chunk")
		_tasks[k] = {"id": id, "lod": lod, "out": out}
	if applied: max_build_ms = maxf(max_build_ms, (Time.get_ticks_usec() - t0) / 1000.0)

func _wanted(k: Vector2i, lod: int) -> bool:
	if chunks.has(k) and chunks[k].lod <= lod: return false
	var rect := Rect2(k.x * WorldData.CHUNK, k.y * WorldData.CHUNK, WorldData.CHUNK, WorldData.CHUNK)
	return _rect_dist(rect, Vector2(_focus.x, _focus.z)) <= near_radius() + 24.0

func _exit_tree() -> void:
	for k in _tasks: WorkerThreadPool.wait_for_task_completion(_tasks[k].id)
	_tasks.clear()

# ---------------- генерация чанка (поток) ----------------
static func gen_chunk(k: Vector2i, lod: int, quality: int) -> Dictionary:
	var res := RES_NEAR if lod == 0 else RES_FAR
	var cs := WorldData.CHUNK
	var ox := k.x * cs; var oz := k.y * cs
	var cell := cs / res
	var w := res + 1
	var rect := Rect2(ox, oz, cs, cs)
	var segs := WorldData.roads_near(rect)
	var pois := WorldData.pois_near(rect)
	var hs := PackedFloat32Array(); hs.resize(w * w)
	var bw: Array = []; bw.resize(w * w)
	for iz in w:
		for ix in w:
			var x := ox + ix * cell; var z := oz + iz * cell
			hs[iz * w + ix] = WorldData.height(x, z, segs, pois)
			bw[iz * w + ix] = WorldData.biome_weights(x, z)
	var verts := PackedVector3Array(); verts.resize(w * w)
	var norms := PackedVector3Array(); norms.resize(w * w)
	var cols := PackedColorArray(); cols.resize(w * w)
	var c0 := PackedFloat32Array(); c0.resize(w * w * 4)
	var c1 := PackedFloat32Array(); c1.resize(w * w * 4)
	var swamp := 0.0
	for iz in w:
		for ix in w:
			var i := iz * w + ix
			var x := ox + ix * cell; var z := oz + iz * cell
			var hl := hs[i - 1] if ix > 0 else WorldData.height(x - cell, z, segs, pois)
			var hr := hs[i + 1] if ix < res else WorldData.height(x + cell, z, segs, pois)
			var hd := hs[i - w] if iz > 0 else WorldData.height(x, z - cell, segs, pois)
			var hu := hs[i + w] if iz < res else WorldData.height(x, z + cell, segs, pois)
			var n := Vector3(hl - hr, 2.0 * cell, hd - hu).normalized()
			verts[i] = Vector3(ix * cell, hs[i], iz * cell)
			norms[i] = n
			var wts: PackedFloat32Array = bw[i]
			swamp = maxf(swamp, wts[3])
			var lw := WorldData.layer_weights(x, z, 1.0 - n.y, wts, segs)
			for q in 4: c0[i * 4 + q] = lw[q]
			for q in 3: c1[i * 4 + q] = lw[4 + q]
			c1[i * 4 + 3] = 0.0
			var avg := Color(0, 0, 0)
			for q in 7: avg += WorldData.LAYER_AVG[q] * lw[q]
			avg.a = lw[7]
			cols[i] = avg
	var idx := PackedInt32Array(); idx.resize(res * res * 6)
	var t := 0
	for iz in res:
		for ix in res:
			var a := iz * w + ix
			idx[t] = a; idx[t + 1] = a + 1; idx[t + 2] = a + w
			idx[t + 3] = a + 1; idx[t + 4] = a + w + 1; idx[t + 5] = a + w
			t += 6
	var out := {"res": res, "heights": hs, "verts": verts, "norms": norms, "cols": cols, "c0": c0, "c1": c1, "idx": idx,
		"water": swamp > 0.45, "props": {}, "small": {}, "solid": [], "fires": [], "grass": []}
	# малые точки интереса (лагеря, повозки, святилища…): пропсы, чей центр — в этом чанке
	var minors := WorldData.minor_near(rect)
	for m in minors:
		var mb := Basis(Vector3.UP, deg_to_rad(m.yaw))
		for it in WorldData.minor_layout(m):
			var off: Vector2 = it[1]
			var o3 := mb * Vector3(off.x, 0, off.y)
			var wx: float = m.pos.x + o3.x; var wz: float = m.pos.y + o3.z
			if not rect.has_point(Vector2(wx, wz)): continue
			var lx := wx - ox; var lz := wz - oz
			var y := WorldData.height(wx, wz, segs, pois)
			var b := Basis(Vector3.UP, deg_to_rad(m.yaw + float(it[2]))).scaled(Vector3.ONE * float(it[3]))
			if not out.props.has(it[0]): out.props[it[0]] = []
			out.props[it[0]].append(Transform3D(b, Vector3(lx, y - 0.03, lz)))
			if it[4] and lod == 0: out.solid.append([Vector3(lx, y, lz), 0.32 * float(it[3]), 1])
			if it[5]: out.fires.append(Vector3(lx, y, lz))
	# пропсы: зерно — от координат чанка (детерминированно)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(k) ^ 0x5eed
	var center_b := WorldData.biome_at(ox + cs * 0.5, oz + cs * 0.5)
	var tried := {}
	for bi in [center_b] + _neighbor_biomes(bw, w):
		if tried.has(bi): continue
		tried[bi] = true
		var table: Array = PROPS[WorldData.BIOMES[bi].id]
		for row in table:
			var kind: int = row[4]
			if kind == 2 and lod != 0: continue
			var count: int = row[1]
			if kind == 2 and quality <= 0: count = count / 3
			elif kind == 2 and quality == 1: count = count * 11 / 10
			elif kind == 2 and quality == 2: count = count * 9 / 5
			elif kind == 2 and quality >= 3: count = count * 12 / 5
			elif kind == 0 and quality >= 2: count = count * 13 / 10
			for i in count:
				var lx := rng.randf() * cs; var lz := rng.randf() * cs
				var x := ox + lx; var z := oz + lz
				if WorldData.biome_at(x, z) != bi: continue
				var ix2 := clampi(int(lx / cell), 0, res - 1); var iz2 := clampi(int(lz / cell), 0, res - 1)
				var nrm: Vector3 = norms[iz2 * w + ix2]
				if kind == 0 and nrm.y < 0.8: continue
				if WorldData.road_dist(x, z, segs) < (6.0 if kind != 2 else 3.5): continue
				if WorldData.town_dist(x, z) < WorldData.TOWN_R + (10.0 if kind != 2 else 0.0): continue
				var pd := INF
				for p in pois: pd = minf(pd, Vector2(x, z).distance_to(p.pos))
				if pd < (22.0 if kind != 2 else 12.0): continue
				var md := INF
				for m in minors: md = minf(md, Vector2(x, z).distance_to(m.pos))
				if md < (13.0 if kind != 2 else 9.0): continue
				if row[0] == "nature_lily_large" and hs[iz2 * w + ix2] > -0.2: continue
				var y := _interp_h(hs, w, cell, lx, lz)
				var s := rng.randf_range(row[2], row[3])
				var key := Real.pick(row[0], rng)
				var real := Real.is_real(key)
				# реалистичные: лёгкий наклон по склону у мелочи и камней, утопить основание
				var b := Basis(Vector3.UP, rng.randf() * TAU)
				if real and kind != 0:
					b = Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.18)) * b
				b = b.scaled(Vector3.ONE * s)
				var sink := (0.05 if not real else (0.12 * s if kind == 1 else (0.06 if kind == 0 else 0.02)))
				if not out.props.has(key): out.props[key] = []
				out.props[key].append(Transform3D(b, Vector3(lx, y - sink, lz)))
				if kind == 2: out.small[key] = true
				if kind != 2 and lod == 0:
					var rad := ((0.45 if kind == 0 else 1.1) * s / 4.0) if not real else ((0.35 * s) if kind == 0 else (0.75 * s))
					out.solid.append([Vector3(lx, y, lz), rad, kind])
	# трава-травинки (ветер) — только ближние чанки, Высокое+: плотность по весу слоя травы
	var gcount := 0
	if lod == 0: gcount = [1000, 1800, 3000, 4200, 5600][clampi(quality, 0, 4)]   # v0.6.0: трава-карточки на всех пресетах
	if gcount > 0:
		var gr := RandomNumberGenerator.new(); gr.seed = hash(k) ^ 0x6a55
		for i in gcount:
			var lx := gr.randf() * cs; var lz := gr.randf() * cs
			var ix2 := clampi(int(round(lx / cell)), 0, res); var iz2 := clampi(int(round(lz / cell)), 0, res)
			var vi := iz2 * w + ix2
			var gw: float = c0[vi * 4] + c0[vi * 4 + 1] * 0.35   # трава + лесная подстилка
			if gw < 0.35 or gr.randf() > gw: continue
			if norms[vi].y < 0.85: continue
			var x := ox + lx; var z := oz + lz
			if WorldData.road_dist(x, z, segs) < 3.0: continue
			var y := _interp_h(hs, w, cell, lx, lz)
			out.grass.append(Vector4(lx, y, lz, gr.randf()))
	# v0.6.0: буфер MultiMesh травы считается в потоке (в кадре — только присвоение)
	if not out.grass.is_empty():
		var gb := PackedFloat32Array(); gb.resize(out.grass.size() * 16)
		var o := 0
		for v: Vector4 in out.grass:
			var sc := 0.55 + v.w * 0.45
			var b := Basis(Vector3.UP, v.w * 37.0).scaled(Vector3(sc, sc * (0.75 + v.w * 0.7), sc))
			gb[o] = b.x.x; gb[o + 1] = b.y.x; gb[o + 2] = b.z.x; gb[o + 3] = v.x
			gb[o + 4] = b.x.y; gb[o + 5] = b.y.y; gb[o + 6] = b.z.y; gb[o + 7] = v.y - 0.03
			gb[o + 8] = b.x.z; gb[o + 9] = b.y.z; gb[o + 10] = b.z.z; gb[o + 11] = v.z
			gb[o + 12] = v.w; gb[o + 13] = 0.0; gb[o + 14] = 0.0; gb[o + 15] = 1.0
			o += 16
		out["grass_buf"] = gb
	return out

static func _interp_h(hs: PackedFloat32Array, w: int, cell: float, lx: float, lz: float) -> float:
	var fx := lx / cell; var fz := lz / cell
	var ix := clampi(int(fx), 0, w - 2); var iz := clampi(int(fz), 0, w - 2)
	var tx := fx - ix; var tz := fz - iz
	var h00 := hs[iz * w + ix]; var h10 := hs[iz * w + ix + 1]; var h01 := hs[(iz + 1) * w + ix]; var h11 := hs[(iz + 1) * w + ix + 1]
	# та же триангуляция, что у сетки: (a, a+1, a+w) и (a+1, a+w+1, a+w)
	if tx + tz <= 1.0: return h00 + (h10 - h00) * tx + (h01 - h00) * tz
	return h11 + (h01 - h11) * (1.0 - tx) + (h10 - h11) * (1.0 - tz)

static func _neighbor_biomes(bw: Array, w: int) -> Array:
	var out := []
	for i in [0, w - 1, w * (w - 1), w * w - 1]:
		var wts: PackedFloat32Array = bw[i]
		var best := 0
		for q in wts.size(): if wts[q] > wts[best]: best = q
		if not out.has(best): out.append(best)
	return out

# ---------------- сборка узлов чанка (основной поток) ----------------
func _apply(k: Vector2i, lod: int, d: Dictionary) -> void:
	if d.is_empty(): return
	if chunks.has(k): chunks[k].node.queue_free()
	var root := Node3D.new(); root.name = "Chunk_%d_%d" % [k.x, k.y]
	add_child(root)
	root.position = Vector3(k.x * WorldData.CHUNK, 0, k.y * WorldData.CHUNK)
	var arr := []; arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = d.verts; arr[Mesh.ARRAY_NORMAL] = d.norms; arr[Mesh.ARRAY_COLOR] = d.cols
	arr[Mesh.ARRAY_CUSTOM0] = d.c0; arr[Mesh.ARRAY_CUSTOM1] = d.c1; arr[Mesh.ARRAY_INDEX] = d.idx
	var fmt := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, fmt)
	var mi := MeshInstance3D.new(); mi.name = "Terrain"
	mi.mesh = am; mi.material_override = terrain_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	if lod == 0:
		var body := StaticBody3D.new(); body.name = "Ground"; body.collision_layer = 1
		root.add_child(body)
		var cs := CollisionShape3D.new()
		var hm := HeightMapShape3D.new()
		hm.map_width = d.res + 1; hm.map_depth = d.res + 1; hm.map_data = d.heights
		cs.shape = hm
		var cell: float = WorldData.CHUNK / d.res
		cs.scale = Vector3(cell, 1, cell)
		cs.position = Vector3(WorldData.CHUNK / 2, 0, WorldData.CHUNK / 2)
		body.add_child(cs)
		for s in d.solid:
			var sh := CollisionShape3D.new()
			var cy := CylinderShape3D.new(); cy.radius = maxf(0.3, s[1]); cy.height = 4.0
			sh.shape = cy; sh.position = s[0] + Vector3(0, 2.0, 0)
			body.add_child(sh)
	for key0 in d.props:
		var rv := resolve(key0)
		var key: String = rv[0]
		var f: float = rv[1]
		var mesh := prop_mesh(key, lod)
		if mesh == null: continue
		var list: Array = d.props[key0]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in list.size():
			var t: Transform3D = list[i]
			if f != 1.0: t.basis = t.basis.scaled(Vector3.ONE * f)
			mm.set_instance_transform(i, t)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		if not Real.is_real(key): mmi.material_override = Real.kenney_material(key)
		var small: bool = d.small.has(key0) or (not Real.is_real(key0) and _is_small(key0))
		var tree := key.begins_with("tree:") or key == "real:quiver"
		var shadow := (not small) and Game.shadows_enabled and (Game.quality >= 2 or (tree and Game.quality >= 1))
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = (55.0 if small else Game.view_distance + WorldData.CHUNK)
		mmi.visibility_range_end_margin = 6.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		if not small: mmi.add_to_group("view_range")
		root.add_child(mmi)
	if not d.grass.is_empty():
		var g: Array = d.grass
		var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.use_colors = true
		mm.mesh = Real.grass_mesh(); mm.instance_count = g.size()
		mm.buffer = d.grass_buf
		var gi := MultiMeshInstance3D.new(); gi.name = "Grass"; gi.multimesh = mm
		gi.material_override = grass_material(WorldData.biome_at(root.position.x + 32, root.position.z + 32))
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gi.visibility_range_end = [30.0, 36.0, 44.0, 52.0, 60.0][clampi(Game.quality, 0, 4)]; gi.visibility_range_end_margin = 8.0
		gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF if Game.quality >= 3 else GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		root.add_child(gi)
	for f in d.fires:
		if lod == 0: _campfire(root, f)
	if d.water:
		var wm := MeshInstance3D.new(); wm.name = "Water"
		var pm := PlaneMesh.new(); pm.size = Vector2(WorldData.CHUNK, WorldData.CHUNK)
		pm.subdivide_width = 0; pm.subdivide_depth = 0
		wm.mesh = pm
		# мелководье/берег: карта глубины чанка (33×33) → пена у кромки на всех уровнях без копии буфера глубины
		var img := Image.create(d.res + 1, d.res + 1, false, Image.FORMAT_RF)
		for iz in d.res + 1:
			for ix in d.res + 1:
				img.set_pixel(ix, iz, Color(clampf(-0.25 - d.heights[iz * (d.res + 1) + ix], -1.0, 3.0), 0, 0))
		var mat := water_material().duplicate() as ShaderMaterial
		mat.set_shader_parameter("depth_map", ImageTexture.create_from_image(img))
		wm.material_override = mat
		wm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wm.position = Vector3(WorldData.CHUNK / 2, -0.25, WorldData.CHUNK / 2)
		root.add_child(wm)
	chunks[k] = {"lod": lod, "node": root, "heights": d.heights, "res": d.res, "solid": d.solid}
	built_count += 1

static func blade_mesh() -> ArrayMesh:
	# пучок: 9 травинок разной высоты/наклона в круге 0.35 м (одна копия MultiMesh = пучок)
	if _blade == null:
		var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var r := RandomNumberGenerator.new(); r.seed = 99
		for k in 9:
			var b := Basis(Vector3.UP, r.randf() * TAU)
			var off := Vector3(r.randf_range(-0.3, 0.3), 0, r.randf_range(-0.3, 0.3))
			var w := r.randf_range(0.025, 0.04); var h := r.randf_range(0.22, 0.42)
			var lean := Vector3(r.randf_range(-0.08, 0.08), 0, r.randf_range(-0.08, 0.08))
			var p0 := off + b * Vector3(-w, 0, 0); var p1 := off + b * Vector3(w, 0, 0); var p2 := off + lean + b * Vector3(0.0, h, 0.02)
			var nrm := Vector3(0, 1, 0).lerp(b * Vector3(0, 0, 1), 0.4).normalized()
			for v in [[p0, 0.0], [p1, 0.0], [p2, 1.0]]:
				st.set_normal(nrm); st.set_uv(Vector2(0.5, v[1])); st.add_vertex(v[0])
		_blade = st.commit()
	return _blade

## Трава по биомам (цвет основания/кончиков) — один шейдер, материалы кэшируются
static var _grass_mats := {}
static func grass_material(b: int) -> ShaderMaterial:
	var id: String = WorldData.BIOMES[b].id
	if not _grass_mats.has(id):
		var gm: ShaderMaterial
		var cols := {"meadows": [Color(0.2, 0.27, 0.11), Color(0.52, 0.6, 0.3)], "forest": [Color(0.14, 0.2, 0.09), Color(0.38, 0.46, 0.22)],
			"desert": [Color(0.42, 0.36, 0.18), Color(0.78, 0.70, 0.42)], "swamp": [Color(0.16, 0.20, 0.08), Color(0.45, 0.48, 0.20)],
			"snow": [Color(0.30, 0.36, 0.30), Color(0.70, 0.75, 0.70)], "ruins": [Color(0.16, 0.18, 0.14), Color(0.42, 0.45, 0.32)]}
		var c: Array = cols.get(id, cols.meadows)
		gm = Real.grass_material(c[0], c[1])
		_grass_mats[id] = gm
	return _grass_mats[id]

static func water_material() -> ShaderMaterial:
	if _water_mat == null:
		_water_mat = ShaderMaterial.new(); _water_mat.shader = load("res://shaders/water_world.gdshader")
		var wn := NoiseTexture2D.new(); wn.width = 256; wn.height = 256; wn.seamless = true; wn.as_normal_map = true; wn.bump_strength = 5.0
		var wf := FastNoiseLite.new(); wf.frequency = 0.03; wn.noise = wf
		var fn := NoiseTexture2D.new(); fn.width = 256; fn.height = 256; fn.seamless = true
		var ff := FastNoiseLite.new(); ff.frequency = 0.05; ff.fractal_octaves = 3; ff.seed = 4; fn.noise = ff
		_water_mat.set_shader_parameter("wave", wn); _water_mat.set_shader_parameter("foam_noise", fn)
	return _water_mat

## Костёр малой точки: огонь-частицы, на Высоком+ — мерцающий свет
func _campfire(root: Node3D, p: Vector3) -> void:
	var gp := GPUParticles3D.new()
	gp.amount = maxi(6, int(18 * Game.particle_mul)); gp.lifetime = 0.9
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE; pm.emission_sphere_radius = 0.35
	pm.direction = Vector3.UP; pm.spread = 12; pm.initial_velocity_min = 0.8; pm.initial_velocity_max = 1.6
	pm.gravity = Vector3(0, 0.6, 0); pm.scale_min = 0.6; pm.scale_max = 1.2
	var grad := Gradient.new(); grad.set_color(0, Color(1, 0.75, 0.3, 1)); grad.set_color(1, Color(0.9, 0.2, 0.05, 0))
	var gt := GradientTexture1D.new(); gt.gradient = grad; pm.color_ramp = gt
	var sc := Curve.new(); sc.add_point(Vector2(0, 1)); sc.add_point(Vector2(1, 0.2))
	var st := CurveTexture.new(); st.curve = sc; pm.scale_curve = st
	gp.process_material = pm
	var q := QuadMesh.new(); q.size = Vector2(0.45, 0.45)
	q.material = WorldDress.soft_particle_material(true)
	gp.draw_pass_1 = q
	gp.visibility_range_end = 70.0
	root.add_child(gp); gp.position = p + Vector3.UP * 0.2
	if Game.quality >= 2:
		var l := OmniLight3D.new()
		l.light_color = Color(1, 0.6, 0.3); l.light_energy = 1.6; l.omni_range = 7.0
		l.shadow_enabled = false; l.distance_fade_enabled = true; l.distance_fade_begin = 35.0; l.distance_fade_length = 10.0
		l.set_script(load("res://scripts/game/flicker.gd"))
		root.add_child(l); l.position = p + Vector3.UP * 1.0

static func _is_small(key: String) -> bool:
	for b in PROPS:
		for row in PROPS[b]:
			if row[0] == key: return int(row[4]) == 2
	return false

## Точка занята (стволы, камни) — для спавна врагов
func point_blocked(p: Vector3, r: float) -> bool:
	var k := chunk_of(p)
	var ch = chunks.get(k)
	if ch == null: return false
	var lp: Vector3 = p - (ch.node as Node3D).position
	for s in ch.solid:
		if Vector2(lp.x - s[0].x, lp.z - s[0].z).length() < r + float(s[1]): return true
	return false

# ---------------- города ----------------
func _town_center(i: int) -> Vector3:
	var t: Dictionary = WorldData.TOWNS[i]
	return Vector3(t.pos.x, WorldData.height(t.pos.x, t.pos.y), t.pos.y)

func _road_angles(c: Vector2) -> Array:
	var out := []
	for r in WorldData.ROADS:
		for j in r.size():
			if (r[j] as Vector2).distance_to(c) < 1.0:
				if j + 1 < r.size(): out.append(((r[j + 1] as Vector2) - c).angle())
				if j > 0: out.append(((r[j - 1] as Vector2) - c).angle())
	return out

func _town(i: int) -> void:
	var t: Dictionary = WorldData.TOWNS[i]
	var c := _town_center(i)
	var root := Node3D.new(); root.name = "Town_" + t.id; add_child(root)
	root.position = c
	var roads := _road_angles(t.pos)
	var free_dir := func(a: float) -> bool:
		for ra in roads:
			if absf(angle_difference(a, ra)) < 0.42: return false
		return true
	var vr := Game.view_distance + 60.0
	if t.kind == "town":
		prop(root, "town_fountain-round", Vector3.ZERO, 0, 3.2)
		_box_col(c, Vector3(5.5, 1.2, 5.5), 0)
		var n := 0
		for a_i in 12:
			var a := a_i * TAU / 12.0 + 0.13
			if not free_dir.call(a): continue
			if n >= 7: break
			var r := 22.0 + (a_i % 2) * 3.0
			var hp := Vector3(cos(a) * r, 0, sin(a) * r)
			_house(root, hp, rad_to_deg(-a) - 90.0, a_i % 3 == 0)
			_box_col(c + hp, Vector3(4.6, 4, 4.6), rad_to_deg(-a) - 90.0)
			n += 1
		for a_i in 8:
			var a := a_i * TAU / 8.0
			prop(root, "town_lantern", Vector3(cos(a) * 9.5, 0, sin(a) * 9.5), 0, 2.4)
		prop(root, "town_stall-red", Vector3(-6, 0, -9), 15, 3.2)
		prop(root, "town_stall-green", Vector3(7, 0, -8.5), -20, 3.2)
		prop(root, "town_cart", Vector3(10, 0, 6), 40, 3.0)
		prop(root, "town_banner-red", Vector3(-3, 0, 8), 0, 3.0)
		prop(root, "town_banner-green", Vector3(3, 0, 8), 0, 3.0)
		for j in 5: prop(root, "survival_barrel", Vector3(12 + (j % 2) * 1.2, 0, -3 + j * 0.9), j * 30, 3.0)
	else:
		prop(root, "survival_campfire-pit", Vector3.ZERO, 0, 5.0)
		_light(c + Vector3(0, 1.2, 0), Color(1, 0.6, 0.3), 2.0, 11, true)
		var n := 0
		for a_i in 8:
			var a := a_i * TAU / 8.0 + 0.2
			if not free_dir.call(a): continue
			if n >= 5: break
			var hp := Vector3(cos(a) * 11.0, 0, sin(a) * 11.0)
			prop(root, "nature_tent_detailedOpen" if a_i % 2 else "survival_tent-canvas", hp, rad_to_deg(-a) + 90.0, 5.5 if a_i % 2 else 7.0)
			_box_col(c + hp, Vector3(3.2, 3, 3.2), rad_to_deg(-a))
			n += 1
		for a_i in 28:
			var a := a_i * TAU / 28.0
			if not free_dir.call(a): continue
			prop(root, "survival_fence-fortified", Vector3(cos(a) * 26.0, 0, sin(a) * 26.0), rad_to_deg(-a) + 90.0, 5.0)
		prop(root, "survival_workbench", Vector3(5, 0, -6), 30, 3.5)
		for j in 4: prop(root, "survival_box-large", Vector3(-8 + j * 0.2, 0, 5 + j * 1.1), j * 20, 3.0)
	for ch in root.get_children():
		if ch is GeometryInstance3D:
			(ch as GeometryInstance3D).visibility_range_end = vr
	# торговец, сундук, путевой камень (и портал в долину у Перекрёстка)
	var mp := c + Vector3(-6.0, 0, -12.0)
	merchant_points.append(mp)
	_merchant(mp, c)
	zone.spawn_stash(c + Vector3(6.5, 0, -12.5))
	var wp := c + Vector3(0, 0, 14.0)
	_waypoint(t.id, t.name, wp, i)
	if i == 0: _valley_portal(portal_point)
	var lbl := Label3D.new()
	lbl.font = UIK.title_font(); lbl.text = t.name; lbl.font_size = 72; lbl.pixel_size = 0.008
	lbl.outline_size = 12; lbl.modulate = UIK.ACCENT; lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.visibility_range_end = 70.0
	root.add_child(lbl); lbl.position = Vector3(0, 9, 0)

func _house(root: Node3D, p: Vector3, yaw: float, stone: bool) -> void:
	## v0.6.0: реалистичный дом (HouseGen) вместо стен Kenney; стиль — от позиции (разнообразие)
	var style := 1 if stone else (absi(int(p.x * 7.0 + p.z * 3.0)) % 2) * 2
	var mi := MeshInstance3D.new(); mi.mesh = HouseGen.mesh(style)
	root.add_child(mi)
	mi.position = p; mi.rotation_degrees.y = yaw + 180.0
	if feature_sink != null and mi.is_inside_tree():
		var g := mi.global_position
		feature_sink.append({"key": "house", "pos": Vector2(g.x, g.z), "size": Vector2(HouseGen.W + 0.6, HouseGen.D + 0.6), "yaw": mi.global_rotation.y})

func _box_col(p: Vector3, size: Vector3, yaw: float) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new(); bs.size = size
	cs.shape = bs
	cs.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), p + Vector3(0, size.y / 2, 0))
	_colliders.add_child(cs)

func _merchant(mp: Vector3, look_at_p: Vector3) -> void:
	var m := CharVisual.new()
	m.name = "Merchant_%d" % merchant_points.size()
	add_child(m)
	m.build({"gender": merchant_points.size() % 2, "skin": 1 + merchant_points.size() % 3, "hair": 1, "hair_color": 3, "beard": 1, "height": 1.02, "build": 0.4}, "mage", "")
	m.global_position = mp
	m.rotation.y = atan2(look_at_p.x - mp.x, look_at_p.z - mp.z)
	U.set_view_range(m, 60.0)
	var l := Label3D.new()
	l.font = UIK.title_font(); l.text = "Торговец"; l.font_size = 56; l.pixel_size = 0.006
	l.outline_size = 10; l.modulate = UIK.ACCENT; l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.visibility_range_end = 45.0
	m.add_child(l); l.position = Vector3(0, 3.05, 0)
	prop(self, "town_stall-red", mp + Vector3(0, 0, 0) - (look_at_p - mp).normalized() * 1.6, rad_to_deg(atan2(look_at_p.x - mp.x, look_at_p.z - mp.z)), 3.0).visibility_range_end = 90.0
	if zone.merchant == null:
		zone.merchant = m; zone.merchant_point = mp

func _valley_portal(c: Vector3) -> void:
	for s in [-1, 1]:
		_add_world("nature_statue_column", c + Vector3(s * 2.2, 0, 0), 0, 4.6)
	var plane := U.prim("box", self, c + Vector3.UP * 2.1, Vector3(3.4, 4.1, 0.1), Color(0.3, 0.8, 1))
	plane.material_override = U.fx_mat(Color(0.3, 0.8, 1, 0.55))
	var portal := Portal.new()
	portal.zone = zone
	portal.target_zone = "starter"
	portal.arrive = "world"
	add_child(portal)
	portal.position = c
	_light(c + Vector3.UP * 2.5, Color(0.3, 0.8, 1), 2.0, 10)
	var lbl := Label3D.new()
	lbl.font = UIK.title_font(); lbl.text = "В Пепельную долину"; lbl.font_size = 56; lbl.pixel_size = 0.006
	lbl.outline_size = 10; lbl.modulate = Color(0.7, 0.9, 1.0); lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(lbl); lbl.position = c + Vector3.UP * 5.4

func _add_world(key: String, p: Vector3, yaw: float, s: float) -> MeshInstance3D:
	var mi := prop(self, key, p, yaw, s)
	mi.visibility_range_end = Game.view_distance + 40.0
	mi.add_to_group("view_range")
	return mi

# ---------------- путевые камни ----------------
func _waypoint(id: String, name: String, p: Vector3, town_i: int) -> void:
	p.y = WorldData.height(p.x, p.z)
	_add_world("nature_statue_obelisk", p, 0, 4.5)
	var g := _glow("sphere", p + Vector3(0, 4.4, 0), Vector3.ONE * 0.45, Color(0.4, 0.8, 1.0), 3.0)
	if g is GeometryInstance3D: (g as GeometryInstance3D).visibility_range_end = 120.0
	_box_col(p, Vector3(1.4, 4, 1.4), 0)
	var wp := {"id": id, "name": name, "pos": p, "town": town_i}
	waypoints.append(wp)
	zone.interactables.append({"pos": p, "r": 3.2, "text": "Путевой камень", "icon": "treasure-map",
		"cb": func(): discover_waypoint(id); zone.hud._open("map")})

func world_state() -> Dictionary:
	if not zone.data.has("world") or not zone.data["world"] is Dictionary: zone.data["world"] = {}
	var w: Dictionary = zone.data["world"]
	if not w.has("wp"): w["wp"] = []
	if not w.has("seen"): w["seen"] = []
	return w

func discover_waypoint(id: String) -> bool:
	var w := world_state()
	if (w["wp"] as Array).has(id): return false
	w["wp"].append(id)
	for wp in waypoints:
		if wp.id == id: Game.toast("Путевой камень открыт: %s" % wp.name, 2.5)
	zone.save()
	return true

func _discover(p: Vector3) -> void:
	for wp in waypoints:
		if U.flat_dist(p, wp.pos) < 12.0: discover_waypoint(wp.id)

## Быстрое перемещение к открытому камню
func travel_to(id: String) -> bool:
	if not (world_state()["wp"] as Array).has(id): return false
	for wp in waypoints:
		if wp.id == id:
			var dest: Vector3 = wp.pos + Vector3(2.5, 0, 3.0)
			dest.y = WorldData.height(dest.x, dest.z) + 0.3
			prepare(dest)
			zone.player.teleport(dest)
			_update_spawners(dest)
			zone.save()
			return true
	return false

## Возрождение у ближайшего открытого камня (или у Перекрёстка)
func respawn_point(from: Vector3) -> Vector3:
	var best: Vector3 = spawn_point; var bd := INF
	var open: Array = world_state()["wp"]
	for wp in waypoints:
		if not open.has(wp.id) and wp.town != 0: continue
		var d := U.flat_dist(from, wp.pos)
		if d < bd: bd = d; best = wp.pos + Vector3(2.5, 0, 3.0)
	best.y = WorldData.height(best.x, best.z) + 0.3
	prepare(best)
	return best

# ---------------- точки интереса ----------------
func _poi(p: Dictionary) -> void:
	var c := Vector3(p.pos.x, WorldData.height(p.pos.x, p.pos.y), p.pos.y)
	var r := Node3D.new(); r.name = "POI_" + p.id; add_child(r); r.position = c
	var rr := RandomNumberGenerator.new(); rr.seed = hash(p.id)
	match p.kind:
		"mill":
			prop(r, "town_windmill", Vector3.ZERO, 30, 5.0); _box_col(c, Vector3(5, 8, 5), 30)
			for j in 6: prop(r, "town_fence", Vector3(-9 + j * 3.4, 0, 8), 0, 3.4)
		"circle", "arena":
			var n := 9 if p.kind == "circle" else 12
			for j in n:
				var a := j * TAU / n
				var key := "nature_statue_column" if j % 3 else "nature_statue_columnDamaged"
				if p.kind == "arena" and WorldData.biome_at(p.pos.x, p.pos.y) == 4: key = "nature_stone_tallA"
				prop(r, key, Vector3(cos(a), 0, sin(a)) * (13.0 if p.kind == "arena" else 8.0), rr.randf() * 360, 4.6)
				_box_col(c + Vector3(cos(a), 0, sin(a)) * (13.0 if p.kind == "arena" else 8.0), Vector3(1.2, 4, 1.2), 0)
			if p.kind == "circle": prop(r, "nature_statue_ring", Vector3.ZERO, 0, 4.0)
			else: prop(r, "graveyard_altar-stone", Vector3(0, 0, -16), 0, 4.0)
		"camp_ruin":
			for j in 5: prop(r, "survival_tent", Vector3(cos(j * 1.3) * 9, 0, sin(j * 1.3) * 9), j * 70, 6.0)
			prop(r, "nature_campfire_stones", Vector3.ZERO, 0, 4.0)
			for j in 6: prop(r, "survival_barrel", Vector3(rr.randf_range(-6, 6), 0, rr.randf_range(-6, 6)), j * 40, 3.0)
		"oasis":
			for j in 7: prop(r, "nature_tree_palmBend", Vector3(cos(j) * 10, 0, sin(j) * 10), j * 50, 5.5)
			for j in 5: prop(r, "nature_statue_columnDamaged", Vector3(cos(j * 1.7) * 5, 0, sin(j * 1.7) * 5), j * 33, 4.0)
		"crypt":
			prop(r, "graveyard_crypt", Vector3.ZERO, 0, 7.0); _box_col(c, Vector3(5, 5, 7.8), 0)
			for j in 10: prop(r, "graveyard_gravestone-cross", Vector3(rr.randf_range(-14, 14), 0, rr.randf_range(6, 16)), rr.randf() * 40 - 20, 3.6)
			for j in 4: prop(r, "graveyard_lantern-candle", Vector3(-5 + j * 3.3, 0, 5), 0, 3.0)
		"tower":
			prop(r, "castle_tower-base", Vector3.ZERO, 0, 6.0); prop(r, "castle_tower-square-mid", Vector3(0, 7.8, 0), 0, 6.0)
			prop(r, "castle_tower-square-top", Vector3(0, 13.8, 0), 0, 6.0); prop(r, "castle_flag", Vector3(0, 19.0, 0), 0, 4.0)
			_box_col(c, Vector3(6, 20, 6), 0)
		"siege":
			prop(r, "castle_siege-catapult-demolished", Vector3(-8, 0, 0), 20, 5.0)
			prop(r, "castle_siege-tower-demolished", Vector3(8, 0, 3), -30, 5.0)
			for j in 6: prop(r, "castle_wall-half", Vector3(-14 + j * 5.0, 0, -10), 0, 5.0)
		"graves":
			for j in 18: prop(r, "graveyard_gravestone-broken" if j % 2 else "graveyard_gravestone-cross", Vector3(rr.randf_range(-15, 15), 0, rr.randf_range(-12, 12)), rr.randf() * 360, 3.6)
			prop(r, "graveyard_crypt", Vector3(0, 0, -14), 180, 6.0)
	for ch in r.get_children():
		if ch is GeometryInstance3D: (ch as GeometryInstance3D).visibility_range_end = Game.view_distance + 60.0
	var lbl := Label3D.new()
	lbl.font = UIK.title_font(); lbl.text = p.name; lbl.font_size = 56; lbl.pixel_size = 0.007
	lbl.outline_size = 10; lbl.modulate = Color(0.9, 0.85, 0.7); lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.visibility_range_end = 55.0
	r.add_child(lbl); lbl.position = Vector3(0, 7, 0)
	if p.kind in ["mill", "camp_ruin", "oasis", "crypt", "tower", "siege"]:
		_waypoint(p.id, p.name, c + Vector3(0, 0, 18) if p.kind != "tower" else c + Vector3(10, 0, 10), -1)

# ---------------- враги ----------------
func _world_spawners() -> void:
	var rr := RandomNumberGenerator.new(); rr.seed = 777
	var placed: Array = []
	for bi in WorldData.BIOMES.size():
		var b: Dictionary = WorldData.BIOMES[bi]
		var n := 0; var guard := 0
		var bs: Vector2 = b.seed
		while n < 30 and guard < 6000:
			guard += 1
			var p := bs + Vector2(rr.randf_range(-430, 430), rr.randf_range(-430, 430))
			if absf(p.x) > 920 or absf(p.y) > 920: continue
			if WorldData.biome_at(p.x, p.y) != bi: continue
			if WorldData.town_dist(p.x, p.y) < 75.0 or WorldData.poi_dist(p.x, p.y) < 40.0: continue
			var ok := true
			for q in placed: if (q as Vector2).distance_to(p) < 55.0: ok = false; break
			if not ok or WorldData.road_dist(p.x, p.y) < 12.0: continue
			placed.append(p)
			var lv := WorldData.level_at(p.x, p.y)
			var kind: String = (b.mobs as Array)[n % (b.mobs as Array).size()]
			var s := WorldSpawner.make(zone, enemies_root, Vector3(p.x, 0, p.y), kind, maxi(int(b.lv[0]), lv - 1), mini(int(b.lv[1]), lv + 1), rr.randi_range(3, 5) * (2 if DB.ENEMIES[kind].get("ai", "") == "swarm" else 1), 9.0, 45.0)
			s.sid = "%s_%d" % [b.id, n]; s.biome = bi; s.elite_chance = 0.12
			spawners.append(s)
			n += 1
		# именные редкие — у двух самых дальних от города лагерей
		var mine := spawners.filter(func(sp): return sp.biome == bi)
		mine.sort_custom(func(a, c): return a.global_position.distance_to(_town_center(bi)) > c.global_position.distance_to(_town_center(bi)))
		for ri in 2:
			if ri >= mine.size(): break
			var rare: Array = b.rares[ri]
			var hp: Vector3 = mine[ri].global_position + Vector3(14, 0, -10)
			var rs := WorldSpawner.make(zone, enemies_root, hp, rare[0], int(b.lv[1]), int(b.lv[1]), 1, 2.0, 240.0)
			rs.sid = "%s_rare%d" % [b.id, ri]; rs.biome = bi; rs.rank = "rare"; rs.rare_name = rare[1]
			spawners.append(rs)
	# боссы зон — на аренах
	for p in WorldData.POIS:
		if not p.has("boss"): continue
		var bi: int = p.boss
		var b: Dictionary = WorldData.BIOMES[bi]
		var bp := Vector3(p.pos.x, 0, p.pos.y)
		var bsp := WorldSpawner.make(zone, enemies_root, bp, String(b.get("boss_kind", "troll")), int(b.lv[1]) + 1, int(b.lv[1]) + 1, 1, 1.0, 600.0)
		bsp.sid = "%s_boss" % b.id; bsp.biome = bi; bsp.rank = "boss"; bsp.rare_name = b.boss
		bsp.kill_flag = "boss_" + b.id
		spawners.append(bsp)
		bosses.append({"biome": bi, "name": b.boss, "pos": bp, "spawner": bsp, "poi": p.name})

func _update_spawners(p: Vector3) -> void:
	var nearest_boss := Vector3.ZERO; var nb := INF
	for s in spawners:
		var d := U.flat_dist(p, s.global_position)
		if not s.active and d < ACTIVATE_R: s.set_active(true)
		elif s.active and d > DEACTIVATE_R: s.set_active(false)
		if s.rank == "boss" and s.alive > 0 and d < nb: nb = d; nearest_boss = s.global_position
	arena_point = nearest_boss if nb < 140.0 else Vector3.ZERO

func active_spawners() -> int:
	var n := 0
	for s in spawners: if s.active: n += 1
	return n

func _update_biome(p: Vector3) -> void:
	var b := WorldData.biome_at(p.x, p.z)
	if b == current_biome: return
	var first := current_biome < 0
	current_biome = b
	var lv: Array = WorldData.BIOMES[b].lv
	Game.toast("%s · ур. %d–%d" % [WorldData.BIOMES[b].name, lv[0], lv[1]], 1.8 if first else 3.0)
	var seen: Array = world_state()["seen"]
	if not seen.has(WorldData.BIOMES[b].id): seen.append(WorldData.BIOMES[b].id)

# ---------------- граница ----------------
func _world_edges() -> void:
	for i in 4:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new(); bs.size = Vector3(WorldData.HALF * 2, 200, 2)
		cs.shape = bs
		var b := Basis(Vector3.UP, deg_to_rad(i * 90))
		cs.transform = Transform3D(b, b * Vector3(0, 50, WorldData.EDGE + 30.0))
		_colliders.add_child(cs)
