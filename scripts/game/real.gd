class_name Real
## v0.6.0: библиотека реалистичных ассетов — меши Poly Haven (assets/real/mesh, CC0), процедурные деревья (TreeGen),
## трипланарный PBR-материал для построек/подземелий (real_surface.gdshader), карточки травы.
## Ключи пропсов: "real:<имя>" — меш; "real:<префикс>*" — случайный вариант (<префикс>_a, _b…);
## "tree:<вид>" / "tree:<вид>*" — дерево (варианты 0..3); остальные ключи — модели Kenney с PBR-материалом.

const TREE_VARIANTS := 4
const SURF := {"stone": 0, "floor": 1, "planks": 2, "beam": 3, "roof": 4, "plaster": 5, "cloth": 6, "metal": 7,
	"rock": 8, "grass": 9, "thatch": 10, "rubble": 11, "dirt": 12}
static var variants := {}      # префикс → [имена]
static var _meshes := {}
static var _surf := {}
static var _grass_mesh: ArrayMesh
static var _grass_mats := {}

## список вариантов (читается один раз в основном потоке до фоновой генерации чанков)
static func init() -> void:
	if not variants.is_empty(): return
	var d := DirAccess.open("res://assets/real/mesh/")
	if d == null: return
	var names := []
	for f in d.get_files():
		var f2 := f.trim_suffix(".remap")
		if f2.ends_with(".res"): names.append(f2.get_basename())
	names.sort()
	for n in names:
		var parts: PackedStringArray = n.rsplit("_", true, 1)
		if parts.size() == 2 and parts[1].length() == 1:
			if not variants.has(parts[0]): variants[parts[0]] = []
			variants[parts[0]].append(n)

## конкретный ключ из шаблона (в фоновом потоке — только чтение variants)
static func pick(key: String, rng: RandomNumberGenerator) -> String:
	if not key.ends_with("*"): return key
	var base := key.trim_suffix("*")
	if base.begins_with("tree:"): return "%s:%d" % [base, rng.randi() % TREE_VARIANTS]
	var nm := base.substr(5)
	var list: Array = variants.get(nm, [])
	if list.is_empty(): return base
	return "real:" + str(list[rng.randi() % list.size()])

static func is_real(key: String) -> bool:
	return key.begins_with("real:") or key.begins_with("tree:")

static func mesh(key: String, lod := 0) -> Mesh:
	var ck := "%s@%d" % [key, lod]
	if _meshes.has(ck): return _meshes[ck]
	var m: Mesh = null
	if key.begins_with("tree:"):
		var p := key.split(":")
		m = TreeGen.mesh(p[1], int(p[2]) if p.size() > 2 else 0, lod)
	elif key.begins_with("real:"):
		var path := "res://assets/real/mesh/%s.res" % key.substr(5)
		if ResourceLoader.exists(path): m = load(path)
	_meshes[ck] = m
	return m

## PBR-материал построек (трипланар, слой по цвету палитры или layer ≥ 0)
static func surf_material(layer := -1, instance := false, uv_mul := 1.0, orange := -1) -> ShaderMaterial:
	var k := "%d_%s_%.2f_%d" % [layer, instance, uv_mul, orange]
	if not _surf.has(k):
		var m := ShaderMaterial.new(); m.shader = load("res://assets/shaders/real_surface.gdshader")
		m.set_shader_parameter("albedo_arr", load("res://assets/real/surf/albedo.jpg"))
		m.set_shader_parameter("normal_arr", load("res://assets/real/surf/normal.jpg"))
		m.set_shader_parameter("force_layer", layer)
		m.set_shader_parameter("use_instance", instance)
		m.set_shader_parameter("uv_mul", uv_mul)
		m.set_shader_parameter("orange_layer", orange)
		_surf[k] = m
	var mm: ShaderMaterial = _surf[k]
	mm.set_shader_parameter("normals_on", Game.quality >= 1)
	return mm

## материал для модели Kenney по ключу (палатки — ткань)
static func kenney_material(key: String) -> ShaderMaterial:
	if key.contains("tent") or key.contains("bedroll") or key.contains("structure-canvas"): return surf_material(-1, false, 1.0, SURF.cloth)
	return surf_material()

static func apply_graphics() -> void:
	for k in _surf: (_surf[k] as ShaderMaterial).set_shader_parameter("normals_on", Game.quality >= 1)
	TreeGen.set_wind(Game.quality >= 1)
	for k in _grass_mats: (_grass_mats[k] as ShaderMaterial).set_shader_parameter("wind_on", 1.0 if Game.quality >= 1 else 0.0)

## пучок травы: 3 скрещённые карточки 0.9×0.45 м с фото-травинками (CC0 ambientCG); UV.y=0 — верх
static func grass_mesh() -> ArrayMesh:
	## пучок: 5 карточек, разведённых веером и наклонённых наружу — сверху (камера) видна площадь, а не «звёздочка»
	if _grass_mesh == null:
		var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var r := RandomNumberGenerator.new(); r.seed = 4242
		for k in 5:
			var yaw := k * TAU / 5.0 + r.randf_range(-0.3, 0.3)
			var b := Basis(Vector3.UP, yaw)
			var off := b * Vector3(0, 0, r.randf_range(0.08, 0.2))
			var tilt := r.randf_range(0.45, 0.75)   # наклон наружу
			var w := r.randf_range(0.26, 0.36); var h := r.randf_range(0.34, 0.46)
			var up := (b * Vector3(0, cos(tilt), sin(tilt))).normalized()
			var side := b * Vector3(1, 0, 0)
			var c := [off - side * w, off + side * w, off + side * w + up * h, off - side * w + up * h]
			var u0 := 0.5 * float(k % 2)
			var uv := [Vector2(u0, 1), Vector2(u0 + 0.5, 1), Vector2(u0 + 0.5, 0), Vector2(u0, 0)]
			for i in [0, 1, 2, 0, 2, 3]:
				st.set_normal(Vector3.UP); st.set_uv(uv[i]); st.add_vertex(c[i])
		_grass_mesh = st.commit()
	return _grass_mesh

static func grass_material(base: Color, tip: Color) -> ShaderMaterial:
	var k := base.to_html() + tip.to_html()
	if not _grass_mats.has(k):
		var m := ShaderMaterial.new(); m.shader = load("res://assets/shaders/real_grass.gdshader")
		m.set_shader_parameter("albedo_tex", load("res://assets/real/foliage/grass_card.png"))
		m.set_shader_parameter("base_col", base); m.set_shader_parameter("tip_col", tip)
		m.set_shader_parameter("wind_on", 1.0 if Game.quality >= 1 else 0.0)
		_grass_mats[k] = m
	return _grass_mats[k]

## MultiMesh из списка трансформов (собственные материалы меша, без override)
static func batch(parent: Node, key: String, xforms: Array, lod := 0, vis_end := 0.0, shadow := false) -> MultiMeshInstance3D:
	var m := mesh(key, lod)
	if m == null or xforms.is_empty(): return null
	var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.mesh = m
	mm.instance_count = xforms.size()
	for i in xforms.size(): mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new(); mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if vis_end > 0.0: mmi.visibility_range_end = vis_end; mmi.visibility_range_end_margin = 6.0
	parent.add_child(mmi)
	return mmi

## Замена старых моделей Kenney (низкополигональных) на реалистичные: [новый ключ, мин. и макс. множитель масштаба].
## Масштаб подбирается по высоте старой модели (чтобы постройки/точки интереса не «поехали»), с ограничением.
static var _repl_cache := {}
static func replacement(k: String) -> Array:
	if _repl_cache.has(k): return _repl_cache[k]
	var r: Array = _replacement(k)
	_repl_cache[k] = r
	return r

static func _var(base: String, k: String) -> String:
	var list: Array = variants.get(base, [])
	if list.is_empty(): return "real:" + base
	return "real:" + str(list[absi(hash(k)) % list.size()])

static func _replacement(k: String) -> Array:
	var n := absi(hash(k)) % TREE_VARIANTS
	if k.contains("tree_palm"): return ["real:quiver", 0.8, 3.0]
	if k.contains("cactus"): return ["real:quiver_dead" if k.contains("tall") else _var("rooibos", k), 0.6, 3.0]
	if k.contains("pine") or k.contains("tree_cone"): return ["tree:%s:%d" % ["fir" if not k.contains("Tall") else "pine", n], 0.55, 1.3]
	if k.contains("tree_") or k.contains("_tree"):
		if k.contains("fall") or k.contains("autumn"): return ["tree:autumn:%d" % n, 0.6, 1.3]
		if k.contains("thin_dark") or k.contains("fat_darkh") or k.contains("crooked"): return ["tree:swamp:%d" % n, 0.6, 1.3]
		if k.contains("blocks") or k.contains("plateau_dark"): return ["tree:dead:%d" % n, 0.6, 1.3]
		if k.contains("_dark"): return ["tree:fir:%d" % n, 0.6, 1.3]
		return ["tree:oak:%d" % n, 0.6, 1.3]
	if k.contains("rock") or k.begins_with("nature_stone"):
		if k.contains("sand"): return ["real:rock_desert" if k.ends_with("a") else "real:rock_flat", 0.3, 4.0]
		if k.contains("tall"): return ["real:rock_round", 0.3, 4.0]
		if k.contains("large") or k.contains("wide"): return ["real:rock_boulder" if n % 2 == 0 else "real:rock_desert", 0.3, 4.0]
		return [_var("rock_mossb", k), 0.3, 4.0]
	if k.contains("stump"): return ["real:stump" if n % 2 == 0 else "real:stump_b", 0.5, 2.0]
	if k == "nature_log" or k == "nature_log_large": return ["real:log", 0.5, 2.0]
	if k.contains("plant_bush"): return [_var("shrub", k), 0.5, 2.5]
	if k.contains("plant_flat"): return [_var("fern", k), 0.6, 2.5]
	if k.contains("grass"): return [_var("grassclump", k), 1.0, 5.0]
	if k.contains("flower"): return [_var("dandelion" if k.contains("yellow") else "periwinkle", k), 1.0, 5.0]
	if k.contains("mushroom"): return [_var("nettle", k), 1.0, 5.0]
	if k.begins_with("survival_barrel"): return ["real:wine_barrel", 0.5, 2.0]
	if k == "survival_box-large": return ["real:crate_long", 0.5, 2.5]
	if k.begins_with("survival_box"): return ["real:crate", 0.5, 2.5]
	if k == "survival_chest": return ["real:chest", 0.5, 2.0]
	if k.contains("campfire-pit") or k.contains("campfire_stones"): return ["real:fire_pit", 0.5, 3.0]
	if k == "survival_bucket": return ["real:bucket", 0.5, 2.0]
	if k == "survival_tool-axe": return ["real:axe", 0.5, 2.0]
	if k == "survival_workbench": return ["real:table", 0.5, 2.0]
	if k == "graveyard_debris-wood": return [_var("branches", k), 0.8, 4.0]
	return []
