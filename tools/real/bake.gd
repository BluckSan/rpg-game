extends SceneTree
## v0.6.0: Poly Haven (CC0) glTF → облегчённые меши с PBR-материалами: assets/real/mesh/<key>.res
## Сетка упрощается (meshoptimizer через ImporterMesh.generate_lods) до целевого числа треугольников,
## к результату снова строятся LOD (дальние копии ещё легче). Текстуры — assets/real/tex (prep_tex.py).
## godot --headless --path . -s res://tools/real/bake.gd
const SRC := "/workspace/realism_src/ph/"
const OUT := "res://assets/real/mesh/"
const TEX := "res://assets/real/tex/"
## key: [id, режим ("one" — всё одной моделью, "split" — каждый узел отдельно), треугольников, вид]
const LIST := {
	"rock_boulder": ["boulder_01", "one", 1400, "rock"],
	"rock_flat": ["namaqualand_boulder_02", "one", 1200, "rock"],
	"rock_desert": ["namaqualand_boulder_03", "one", 1400, "rock"],
	"rock_round": ["namaqualand_boulder_04", "one", 1400, "rock"],
	"rock_moss": ["rock_moss_set_01", "split", 900, "rock"],
	"rock_mossb": ["rock_moss_set_02", "split", 700, "rock"],
	"fern": ["fern_02", "split", 700, "plant"],
	"shrub": ["shrub_02", "split", 1600, "plant"],
	"tuft": ["shrub_03", "split", 500, "plant"],
	"shrub_low": ["shrub_04", "one", 1500, "plant"],
	"sorrel": ["shrub_sorrel_01", "one", 900, "plant"],
	"weed": ["weed_plant_02", "split", 500, "plant"],
	"nettle": ["nettle_plant", "split", 700, "plant"],
	"rooibos": ["wild_rooibos_bush", "split", 1200, "plant"],
	"dandelion": ["dandelion_01", "split", 500, "plant"],
	"grassclump": ["grass_medium_02", "split", 400, "plant"],
	"periwinkle": ["periwinkle_plant", "split", 600, "plant"],
	"stump": ["tree_stump_01", "one", 900, "prop"],
	"stump_b": ["tree_stump_02", "one", 900, "prop"],
	"log": ["dead_tree_trunk_02", "one", 1400, "prop"],
	"quiver_dead": ["dead_quiver_trunk", "one", 700, "prop"],
	"quiver": ["quiver_tree_02", "one", 2600, "plant"],
	"branches": ["dry_branches_medium_01", "split", 400, "prop"],
	"roots": ["root_cluster_01", "one", 2000, "prop"],
	"wine_barrel": ["wine_barrel_01", "one", 900, "prop"],
	"crate": ["wooden_crate_01", "one", 700, "prop"],
	"crate_long": ["wooden_crate_02", "one", 700, "prop"],
	"bucket": ["wooden_bucket_01", "one", 500, "prop"],
	"chest": ["treasure_chest", "one", 2400, "prop"],
	"lantern": ["wooden_lantern_01", "one", 900, "prop"],
	"fire_pit": ["stone_fire_pit", "one", 900, "prop"],
	"table": ["WoodenTable_01", "one", 600, "prop"],
	"stool": ["wooden_stool_01", "one", 500, "prop"],
	"statue": ["gothic_statue", "one", 3500, "prop"],
	"ladder": ["wooden_ladder", "one", 800, "prop"],
	"castle_door": ["large_castle_door", "one", 1600, "prop"],
	"spinning_wheel": ["spinning_wheel_01", "one", 1600, "prop"],
	"basket": ["wicker_basket_01", "one", 800, "prop"],
	"axe": ["wooden_axe_03", "one", 300, "prop"],
	"fort": ["modular_fort_01", "split", 3000, "prop"],
}
var _mats := {}
var _plant_shader: Shader

func _init() -> void:
	_plant_shader = load("res://assets/shaders/real_plant.gdshader")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var only := OS.get_environment("BAKE_ONLY")
	var report := []
	for key in LIST:
		if only != "" and not (key in only.split(",")): continue
		var spec: Array = LIST[key]
		report.append_array(_bake(key, spec[0], spec[1], spec[2], spec[3]))
	for r in report: print(r)
	print("BAKE DONE ", report.size())
	quit()

func _tex(stem: String, suf: String) -> Texture2D:
	var p := TEX + stem + "_" + suf + ".jpg"
	if not ResourceLoader.exists(p): p = TEX + stem + "_" + suf + ".png"
	return load(p) if ResourceLoader.exists(p) else null

## материал по имени исходного файла цветовой текстуры
func _material(stem: String, kind: String, gl_mat: Dictionary) -> Material:
	var mk := stem + "|" + kind
	if _mats.has(mk): return _mats[mk]
	var m: Material
	var blend: bool = gl_mat.get("alphaMode", "") == "BLEND" and stem.ends_with("glass")
	if kind == "plant":
		var sm := ShaderMaterial.new(); sm.shader = _plant_shader
		sm.set_shader_parameter("albedo_tex", _tex(stem, "d"))
		sm.set_shader_parameter("normal_tex", _tex(stem, "n"))
		sm.set_shader_parameter("orm_tex", _tex(stem, "orm"))
		m = sm
	else:
		var om := ORMMaterial3D.new()
		om.albedo_texture = _tex(stem, "d")
		om.normal_enabled = true; om.normal_texture = _tex(stem, "n")
		om.orm_texture = _tex(stem, "orm")
		om.cull_mode = BaseMaterial3D.CULL_BACK if not gl_mat.get("doubleSided", false) or kind == "rock" else BaseMaterial3D.CULL_DISABLED
		if blend:
			om.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			om.albedo_color = Color(1, 0.9, 0.7, 0.35)
			om.emission_enabled = true; om.emission = Color(1.0, 0.7, 0.35); om.emission_energy_multiplier = 0.6
		m = om
	m.resource_name = stem
	_mats[mk] = m
	return m

func _bake(key: String, id: String, mode: String, target: int, kind: String) -> Array:
	var path := SRC + id + "/" + id + ".gltf"
	var js: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	# материал glTF → основа имени текстур
	var mat_stem := {}
	for gm in js.materials:
		var bi: int = gm.get("pbrMetallicRoughness", {}).get("baseColorTexture", {}).get("index", -1)
		var uri: String = js.images[js.textures[bi].source].uri if bi >= 0 else ""
		mat_stem[gm.name] = [uri.get_file().replace("_diff_1k.jpg", "").replace("_diff_1k.png", ""), gm]
	var doc := GLTFDocument.new(); var st := GLTFState.new()
	var err := doc.append_from_file(path, st, 0, SRC + id)
	if err != OK: return ["%s: ошибка glTF %d" % [key, err]]
	var nodes := st.get_nodes()
	var gmeshes := st.get_meshes()
	# глобальные трансформы узлов
	var glob := {}
	for ni in nodes.size(): glob[ni] = _global(nodes, ni)
	var groups := []   # [[node_idx...]]
	var mesh_nodes := []
	for ni in nodes.size():
		if nodes[ni].mesh >= 0: mesh_nodes.append(ni)
	if mode == "split":
		for ni in mesh_nodes: groups.append([ni])
	else:
		groups.append(mesh_nodes)
	var out := []
	var letters := "abcdefghijklmnop"
	for gi in groups.size():
		# собрать поверхности по материалам
		var by_mat := {}   # stem -> {v, n, t, uv, idx}
		var tris_src := 0
		for ni in groups[gi]:
			var im: ImporterMesh = (gmeshes[nodes[ni].mesh] as GLTFMesh).mesh
			var xf: Transform3D = glob[ni]
			for si in im.get_surface_count():
				var arr := im.get_surface_arrays(si)
				var mname := im.get_surface_material(si).resource_name if im.get_surface_material(si) else ""
				var ms: Array = mat_stem.get(mname, [id, {}])
				var stem: String = ms[0]
				if not by_mat.has(stem): by_mat[stem] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "t": PackedFloat32Array(), "uv": PackedVector2Array(), "i": PackedInt32Array(), "gm": ms[1]}
				var b: Dictionary = by_mat[stem]
				var base: int = b.v.size()
				var vv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				var tt = arr[Mesh.ARRAY_TANGENT]
				var uu: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
				var ii: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
				var nb := xf.basis.inverse().transposed()
				for k in vv.size():
					b.v.append(xf * vv[k])
					b.n.append((nb * nn[k]).normalized())
					b.uv.append(uu[k] if k < uu.size() else Vector2.ZERO)
					if tt != null and tt.size() >= (k + 1) * 4:
						var tv := (xf.basis * Vector3(tt[k * 4], tt[k * 4 + 1], tt[k * 4 + 2])).normalized()
						b.t.append_array([tv.x, tv.y, tv.z, tt[k * 4 + 3]])
				for k in ii.size(): b.i.append(base + ii[k])
				tris_src += ii.size() / 3
		# опора: центр по XZ, низ на y=0
		var aabb := AABB()
		var first := true
		for stem in by_mat:
			for p in by_mat[stem].v:
				if first: aabb = AABB(p, Vector3.ZERO); first = false
				else: aabb = aabb.expand(p)
		var shift := Vector3(-aabb.get_center().x, -aabb.position.y, -aabb.get_center().z)
		# упрощение: первая LOD-ступень, где треугольников ≤ цели (пропорционально по поверхностям)
		var imesh := ImporterMesh.new()
		for stem in by_mat:
			var b: Dictionary = by_mat[stem]
			for k in b.v.size(): b.v[k] += shift
			var a := []; a.resize(Mesh.ARRAY_MAX)
			a[Mesh.ARRAY_VERTEX] = b.v; a[Mesh.ARRAY_NORMAL] = b.n; a[Mesh.ARRAY_TEX_UV] = b.uv; a[Mesh.ARRAY_INDEX] = b.i
			if b.t.size() == b.v.size() * 4: a[Mesh.ARRAY_TANGENT] = b.t
			imesh.add_surface(Mesh.PRIMITIVE_TRIANGLES, a, [], {}, _material(stem, kind, b.gm), stem)
		var ratio := clampf(float(target) / maxf(tris_src, 1.0), 0.0, 1.0)
		var final_mesh := ImporterMesh.new()
		if ratio < 0.95:
			imesh.generate_lods(25.0, 60.0, [])
		for si in imesh.get_surface_count():
			var arr := imesh.get_surface_arrays(si)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var want := int(idx.size() / 3 * ratio)
			var best := idx
			if ratio < 0.95:
				for li in imesh.get_surface_lod_count(si):
					var li_idx := imesh.get_surface_lod_indices(si, li)
					if li_idx.size() / 3 < want / 2 and li_idx.size() < best.size(): break   # слишком грубо — оставить предыдущую ступень
					best = li_idx
					if li_idx.size() / 3 <= want: break
			arr = _compact(arr, best)
			if arr.is_empty(): continue
			final_mesh.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, imesh.get_surface_material(si), imesh.get_surface_name(si))
		final_mesh.generate_lods(25.0, 60.0, [])
		var am := final_mesh.get_mesh()
		var nm := key if groups.size() == 1 else "%s_%s" % [key, letters[gi]]
		am.resource_name = nm
		var tris := 0
		for si in am.get_surface_count(): tris += am.surface_get_array_index_len(si) / 3
		ResourceSaver.save(am, OUT + nm + ".res", ResourceSaver.FLAG_COMPRESS)
		out.append("%s: %d → %d тр., размер %s" % [nm, tris_src, tris, str(aabb.size.snapped(Vector3.ONE * 0.01))])
	return out

func _global(nodes: Array, ni: int) -> Transform3D:
	var t: Transform3D = nodes[ni].xform
	var p: int = nodes[ni].parent
	while p >= 0:
		t = nodes[p].xform * t
		p = nodes[p].parent
	return t

## оставить только вершины, на которые ссылаются индексы
func _compact(arr: Array, idx: PackedInt32Array) -> Array:
	if idx.is_empty(): return []
	var remap := {}
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var t = arr[Mesh.ARRAY_TANGENT]
	var has_t: bool = t != null and (t as PackedFloat32Array).size() == v.size() * 4
	var nv := PackedVector3Array(); var nn := PackedVector3Array(); var nuv := PackedVector2Array(); var nt := PackedFloat32Array()
	var ni := PackedInt32Array(); ni.resize(idx.size())
	for k in idx.size():
		var o := idx[k]
		if not remap.has(o):
			remap[o] = nv.size()
			nv.append(v[o]); nn.append(n[o]); nuv.append(uv[o])
			if has_t: nt.append_array([t[o * 4], t[o * 4 + 1], t[o * 4 + 2], t[o * 4 + 3]])
		ni[k] = remap[o]
	var a := []; a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = nv; a[Mesh.ARRAY_NORMAL] = nn; a[Mesh.ARRAY_TEX_UV] = nuv; a[Mesh.ARRAY_INDEX] = ni
	if has_t: a[Mesh.ARRAY_TANGENT] = nt
	return a
