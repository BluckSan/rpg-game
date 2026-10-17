extends SceneTree
## Запекание моделей Kenney (CC0) в одноповерхностные меши с цветом вершин → assets/world/props/<key>.res
## Цвет = albedo материала × цвет палитры (colormap) в UV вершины. Один общий материал на все пропсы →
## одна отрисовка на тип в MultiMesh; на телефоне не нужно распаковывать текстуры.
## godot --headless --path . -s res://tools/bake_props.gd
const SRC := "res://assets/kenney/"
const OUT := "res://assets/world/props/"
const LIST := [
	# луга
	"nature/tree_oak", "nature/tree_default", "nature/tree_fat", "nature/tree_detailed", "nature/plant_bushLarge", "nature/plant_bush",
	"nature/flower_redA", "nature/flower_yellowA", "nature/flower_purpleA", "nature/grass_large", "nature/grass_leafsLarge",
	"nature/rock_smallA", "nature/rock_smallC", "nature/rock_largeA", "nature/stump_round",
	# лес
	"nature/tree_pineTallA_detailed", "nature/tree_pineDefaultA", "nature/tree_pineRoundC", "nature/tree_detailed_dark", "nature/tree_tall_dark",
	"nature/log_large", "nature/stump_old", "nature/mushroom_redGroup", "nature/mushroom_redTall", "nature/plant_bushDetailed", "nature/rock_tallA",
	# пустоши
	"nature/cactus_tall", "nature/cactus_short", "nature/tree_palmTall", "nature/tree_palmBend", "nature/rock_largeB", "nature/rock_tallB",
	"nature/stone_tallC", "nature/stone_largeD", "survival/rock-sand-a", "survival/rock-sand-b",
	# топи
	"nature/tree_thin_dark", "nature/tree_fat_darkh", "nature/log", "nature/lily_large", "nature/mushroom_tanTall", "nature/mushroom_tanGroup",
	"nature/stump_oldTall", "nature/plant_flatTall",
	# хребет
	"nature/tree_pineSmallA", "nature/tree_pineRoundA", "nature/tree_cone", "nature/rock_largeC", "nature/stone_tallA", "nature/stone_largeA",
	# руины
	"nature/tree_blocks_dark", "nature/statue_column", "nature/statue_columnDamaged", "nature/statue_obelisk", "nature/statue_head", "nature/statue_ring",
	"graveyard/stone-wall-damaged", "graveyard/pillar-large", "graveyard/gravestone-broken", "graveyard/gravestone-cross", "graveyard/crypt",
	"graveyard/rocks-tall", "graveyard/pine-crooked", "graveyard/lantern-candle", "graveyard/altar-stone",
	"castle/tower-base", "castle/tower-square-mid", "castle/tower-square-top", "castle/wall-half", "castle/siege-catapult-demolished",
	"castle/siege-tower-demolished", "castle/flag", "castle/rocks-large",
	# города и лагеря
	"town/wall-wood", "town/wall-wood-door", "town/wall-wood-window-shutters", "town/wall", "town/wall-door", "town/wall-window-stone",
	"town/roof-point", "town/roof-high-point", "town/stall-red", "town/stall-green", "town/stall-bench", "town/fountain-round", "town/lantern",
	"town/cart", "town/fence", "town/banner-red", "town/banner-green", "town/windmill", "town/tree-high-round", "town/hedge",
	"survival/tent-canvas", "survival/tent", "survival/campfire-pit", "survival/chest", "survival/barrel", "survival/box-large",
	"survival/signpost", "survival/workbench", "survival/bedroll", "survival/fence-fortified",
	"nature/campfire_stones", "nature/tent_detailedOpen", "nature/sign", "nature/fence_simple", "nature/bridge_wood",
]

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var n := 0
	for key in LIST:
		var path: String = SRC + key + ".glb"
		if not ResourceLoader.exists(path):
			print("MISSING ", key); continue
		var mesh := bake(path, key.begins_with("nature/"))
		var name: String = key.replace("/", "_")
		ResourceSaver.save(mesh, OUT + name + ".res", ResourceSaver.FLAG_COMPRESS)
		n += 1
	print("baked ", n)
	quit()

static func _tex_img(m: BaseMaterial3D) -> Image:
	if m == null or m.albedo_texture == null: return null
	var img := m.albedo_texture.get_image()
	if img == null: return null
	if img.is_compressed(): img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img

## Палитра Nature Kit бирюзовая — приводим листву к зелёной, кору — к коричневой (под текстуры ambientCG)
static func _nature_fix(c: Color) -> Color:
	var h := c.h; var sat := c.s; var v := c.v
	if h > 0.38 and h < 0.58 and sat > 0.25: return Color.from_hsv(0.27 + (h - 0.45) * 0.3, clampf(sat * 0.85, 0, 1), v * 0.62)
	if (h < 0.1 or h > 0.95) and sat > 0.2 and sat < 0.7 and v > 0.5: return Color.from_hsv(0.065, clampf(sat * 1.2, 0, 0.75), v * 0.55)
	return c

static func bake(path: String, nature := false) -> ArrayMesh:
	var root: Node3D = (load(path) as PackedScene).instantiate()
	var verts := PackedVector3Array(); var norms := PackedVector3Array(); var cols := PackedColorArray(); var idx := PackedInt32Array()
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var it: Array = stack.pop_back()
		var node: Node = it[0]; var xf: Transform3D = it[1]
		if node is Node3D: xf = xf * (node as Node3D).transform
		for ch in node.get_children(): stack.append([ch, xf])
		if not node is MeshInstance3D: continue
		var mi := node as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var mat = mi.get_surface_override_material(s) if mi.get_surface_override_material(s) else mi.mesh.surface_get_material(s)
			var base := Color.WHITE
			var img: Image = null
			if mat is BaseMaterial3D:
				base = (mat as BaseMaterial3D).albedo_color
				img = _tex_img(mat)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var uv = arr[Mesh.ARRAY_TEX_UV]
			var vc = arr[Mesh.ARRAY_COLOR]
			var ind = arr[Mesh.ARRAY_INDEX]
			var off := verts.size()
			var nb := xf.basis.inverse().transposed()
			for i in v.size():
				verts.append(xf * v[i])
				norms.append((nb * nm[i]).normalized() if i < nm.size() else Vector3.UP)
				var c := base
				if img != null and uv != null and i < (uv as PackedVector2Array).size():
					var t: Vector2 = uv[i]
					var px := clampi(int(fposmod(t.x, 1.0) * img.get_width()), 0, img.get_width() - 1)
					var py := clampi(int(fposmod(t.y, 1.0) * img.get_height()), 0, img.get_height() - 1)
					c = c * img.get_pixel(px, py)
				if vc != null and i < (vc as PackedColorArray).size(): c = c * vc[i]
				if nature: c = _nature_fix(c)
				c.a = 1.0
				cols.append(c)
			if ind != null and (ind as PackedInt32Array).size() > 0:
				for k in ind: idx.append(off + int(k))
			else:
				for k in v.size(): idx.append(off + k)
	root.free()
	var a := []; a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = verts; a[Mesh.ARRAY_NORMAL] = norms; a[Mesh.ARRAY_COLOR] = cols; a[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return m
