extends Node
## Рендер 3D-иконок предметов (по типу) в assets/items/<type>.png — 256×256, прозрачный фон.
## xvfb-run godot --path . --rendering-driver vulkan res://tools/render_icons.tscn
## Оружие — модели Quaternius (CC0, assets/props), броня и украшения — собраны из примитивов.
const OUT := "res://assets/items/"
var vp: SubViewport
var stage: Node3D
var cam: Camera3D
var _pre_override := Vector3.INF

func _ready() -> void:
	vp = SubViewport.new(); vp.size = Vector2i(256, 256); vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_8X
	add_child(vp)
	var env := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color(0.55, 0.55, 0.6); e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e; vp.add_child(env)
	var key := DirectionalLight3D.new(); key.rotation_degrees = Vector3(-40, -35, 0); key.light_energy = 1.6; vp.add_child(key)
	var rim := DirectionalLight3D.new(); rim.rotation_degrees = Vector3(-20, 150, 0); rim.light_energy = 1.1; rim.light_color = Color(0.8, 0.85, 1.0); vp.add_child(rim)
	cam = Camera3D.new(); cam.projection = Camera3D.PROJECTION_ORTHOGONAL; cam.size = 2.2
	cam.position = Vector3(0, 1.4, 4); vp.add_child(cam); cam.look_at(Vector3.ZERO)
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var list: Array = Items.TYPES.keys() + ["potion", "dust"]
	var variants := OS.get_cmdline_user_args().has("--variants")
	if variants: list = []
	for w in ["axe", "bow"]:
		if variants:
			for v in [Vector3(0, 90, 0), Vector3(90, 90, 0), Vector3(0, 0, 90), Vector3(90, 0, 90), Vector3(-90, 0, 0), Vector3(0, 90, 90)]: list.append([w, v])
	for t0 in list:
		var t: String = t0 if t0 is String else t0[0]
		_pre_override = Vector3.INF if t0 is String else t0[1]
		if stage: stage.queue_free()
		stage = Node3D.new(); vp.add_child(stage)
		_build(t)
		_fit()
		for i in 3: await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		if t0 is String: img.save_png(ProjectSettings.globalize_path(OUT + t + ".png"))
		else: img.save_png("/tmp/var_%s_%d_%d_%d.png" % [t, t0[1].x, t0[1].y, t0[1].z])
		print("icon ", t)
	get_tree().quit()

func _fit() -> void:
	var aabb := AABB(); var first := true
	for m in stage.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (m as MeshInstance3D).global_transform * (m as MeshInstance3D).get_aabb()
		if first: aabb = b; first = false
		else: aabb = aabb.merge(b)
	if first: return
	stage.position -= aabb.get_center()
	var inv := cam.global_transform.affine_inverse()
	var mn := Vector2(INF, INF); var mx := -mn
	for i in 8:
		var q: Vector3 = inv * (aabb.get_endpoint(i) - aabb.get_center())
		mn = mn.min(Vector2(q.x, q.y)); mx = mx.max(Vector2(q.x, q.y))
	stage.position -= cam.global_transform.basis * Vector3((mn.x + mx.x) * 0.5, (mn.y + mx.y) * 0.5, 0)
	cam.size = maxf(mx.x - mn.x, mx.y - mn.y) * 1.08

func mat(c: Color, metal := 0.0, rough := 0.6, em := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_color = c; m.metallic = metal; m.roughness = rough
	if em > 0: m.emission_enabled = true; m.emission = c; m.emission_energy_multiplier = em
	return m

func prim(mesh: Mesh, pos: Vector3, rot: Vector3, scl: Vector3, m: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); mi.mesh = mesh; mi.material_override = m
	mi.position = pos; mi.rotation_degrees = rot; mi.scale = scl
	(parent if parent else stage).add_child(mi); return mi

func sph() -> SphereMesh: return SphereMesh.new()
func box() -> BoxMesh: return BoxMesh.new()
func cyl(top := 0.5, bot := 0.5) -> CylinderMesh:
	var c := CylinderMesh.new(); c.top_radius = top; c.bottom_radius = bot; return c
func tor(inner := 0.35, outer := 0.5) -> TorusMesh:
	var t := TorusMesh.new(); t.inner_radius = inner; t.outer_radius = outer; t.rings = 48; t.ring_segments = 16; return t

func glb(path: String, rot: Vector3, pre := Vector3.ZERO) -> void:
	var s: PackedScene = load(path)
	var n := s.instantiate() as Node3D
	var piv := Node3D.new(); piv.rotation_degrees = rot
	n.rotation_degrees = pre if _pre_override == Vector3.INF else _pre_override
	piv.add_child(n); stage.add_child(piv)

func _build(t: String) -> void:
	var steel := mat(Color(0.72, 0.74, 0.8), 0.85, 0.3)
	var gold := mat(Color(0.95, 0.75, 0.3), 0.9, 0.3)
	var leather := mat(Color(0.45, 0.28, 0.16), 0.0, 0.8)
	var cloth := mat(Color(0.35, 0.22, 0.55), 0.0, 0.9)
	var gem := mat(Color(0.9, 0.15, 0.25), 0.2, 0.1, 0.6)
	match t:
		"sword": glb("res://assets/props/sword1.glb", Vector3(0, 0, -45))
		"axe": glb("res://assets/props/axe.glb", Vector3(0, 0, -35), Vector3(-90, 0, 0))
		"bow": glb("res://assets/props/bow.glb", Vector3(0, 90, -45), Vector3(0, 90, 0))
		"staff": glb("res://assets/props/staff.glb", Vector3(0, 0, -40))
		"plate", "leather", "robe":
			var m := steel if t == "plate" else (leather if t == "leather" else cloth)
			if t == "robe": prim(cyl(0.45, 0.8), Vector3(0, -0.2, 0), Vector3.ZERO, Vector3(1, 1.6, 0.6), m)
			else: prim(box(), Vector3(0, 0, 0), Vector3.ZERO, Vector3(1.0, 1.1, 0.5), m)
			for sx in [-1, 1]: prim(sph(), Vector3(sx * 0.6, 0.45, 0), Vector3.ZERO, Vector3(0.5, 0.4, 0.5), m if t != "plate" else gold)
			prim(box(), Vector3(0, -0.45, 0.27), Vector3.ZERO, Vector3(1.02, 0.12, 0.05), gold if t != "leather" else mat(Color(0.25, 0.15, 0.08)))
			if t == "plate": prim(box(), Vector3(0, 0.1, 0.26), Vector3.ZERO, Vector3(0.1, 0.8, 0.04), gold)
		"cloak":
			var c := mat(Color(0.18, 0.4, 0.3), 0.0, 0.85)
			prim(cyl(0.35, 0.75), Vector3(0, -0.1, 0), Vector3(8, 0, 0), Vector3(1, 1.8, 0.35), c)
			prim(tor(0.25, 0.36), Vector3(0, 0.85, 0.05), Vector3(90, 0, 0), Vector3(1, 1, 0.6), gold)
		"helm":
			prim(sph(), Vector3(0, 0.1, 0), Vector3.ZERO, Vector3(1, 0.95, 1), steel)
			prim(box(), Vector3(0, -0.05, 0.47), Vector3.ZERO, Vector3(0.7, 0.12, 0.06), mat(Color(0.1, 0.1, 0.12)))
			prim(cyl(0.02, 0.09), Vector3(0, 0.62, 0), Vector3.ZERO, Vector3(1, 0.4, 1), gold)
			for sx in [-1, 1]: prim(cyl(0.01, 0.1), Vector3(sx * 0.55, 0.45, 0), Vector3(0, 0, -sx * 50), Vector3(1, 0.5, 1), mat(Color(0.9, 0.85, 0.75)))
		"hood":
			prim(sph(), Vector3(0, 0, 0), Vector3.ZERO, Vector3(1, 1, 1), leather)
			prim(cyl(0.0, 0.32), Vector3(0, 0.5, -0.25), Vector3(-35, 0, 0), Vector3(1, 0.6, 1), leather)
			prim(sph(), Vector3(0, -0.05, 0.3), Vector3.ZERO, Vector3(0.6, 0.65, 0.5), mat(Color(0.05, 0.04, 0.04)))
		"hat":
			prim(cyl(0.0, 0.42), Vector3(0, 0.45, 0), Vector3(0, 0, 8), Vector3(1, 1.2, 1), cloth)
			prim(cyl(0.95, 0.95), Vector3(0, -0.15, 0), Vector3.ZERO, Vector3(1, 0.04, 1), cloth)
			prim(cyl(0.44, 0.44), Vector3(0, -0.08, 0), Vector3.ZERO, Vector3(1, 0.08, 1), gold)
			prim(sph(), Vector3(0.1, 1.05, 0), Vector3.ZERO, Vector3.ONE * 0.18, mat(Color(1, 0.9, 0.4), 0.3, 0.2, 1.2))
		"circlet":
			prim(tor(0.42, 0.5), Vector3.ZERO, Vector3(10, 0, 0), Vector3.ONE, gold)
			prim(sph(), Vector3(0, 0.12, 0.47), Vector3.ZERO, Vector3.ONE * 0.2, mat(Color(0.3, 0.6, 1.0), 0.2, 0.1, 0.8))
		"ring":
			prim(tor(0.3, 0.42), Vector3.ZERO, Vector3(65, 0, 0), Vector3.ONE, gold)
			prim(sph(), Vector3(0, 0.42, 0.12), Vector3.ZERO, Vector3.ONE * 0.24, gem)
		"amulet":
			prim(tor(0.48, 0.52), Vector3(0, 0.35, 0), Vector3(90, 0, 0), Vector3(1, 1, 1.3), gold)
			prim(cyl(0.2, 0.2), Vector3(0, -0.3, 0), Vector3(90, 0, 0), Vector3(1, 0.08, 1), gold)
			prim(sph(), Vector3(0, -0.3, 0.05), Vector3.ZERO, Vector3(0.28, 0.28, 0.12), mat(Color(0.3, 0.9, 0.6), 0.2, 0.1, 0.8))
		"gloves":
			prim(box(), Vector3(0, 0, 0), Vector3(0, 0, -10), Vector3(0.6, 0.7, 0.3), leather)
			for i in 4: prim(cyl(0.07, 0.08), Vector3(-0.22 + i * 0.15, 0.48, 0), Vector3(0, 0, -10), Vector3(1, 0.3, 1), leather)
			prim(cyl(0.07, 0.08), Vector3(0.38, 0.05, 0), Vector3(0, 0, -60), Vector3(1, 0.25, 1), leather)
			prim(cyl(0.36, 0.36), Vector3(0, -0.45, 0), Vector3.ZERO, Vector3(1, 0.12, 0.5), steel)
		"boots":
			prim(cyl(0.22, 0.25), Vector3(0, 0.3, 0), Vector3.ZERO, Vector3(1, 0.7, 1), leather)
			prim(box(), Vector3(0.18, -0.2, 0), Vector3.ZERO, Vector3(0.75, 0.25, 0.42), leather)
			prim(cyl(0.27, 0.27), Vector3(0, 0.65, 0), Vector3.ZERO, Vector3(1, 0.08, 1), mat(Color(0.3, 0.18, 0.1)))
		"belt":
			prim(tor(0.48, 0.58), Vector3.ZERO, Vector3(10, 0, 0), Vector3(1, 1, 1), leather)
			prim(box(), Vector3(0, 0.0, 0.56), Vector3.ZERO, Vector3(0.3, 0.26, 0.06), gold)
		"potion":
			prim(sph(), Vector3.ZERO, Vector3.ZERO, Vector3.ONE * 0.8, mat(Color(0.9, 0.15, 0.25), 0.1, 0.1, 0.5))
			prim(cyl(0.12, 0.14), Vector3(0, 0.5, 0), Vector3.ZERO, Vector3(1, 0.3, 1), mat(Color(0.8, 0.85, 0.9), 0.0, 0.1))
			prim(cyl(0.09, 0.09), Vector3(0, 0.72, 0), Vector3.ZERO, Vector3(1, 0.12, 1), mat(Color(0.5, 0.3, 0.15)))
		"dust":
			for i in 7:
				var a := i * TAU / 7.0
				prim(sph(), Vector3(cos(a) * 0.35, sin(a * 2.0) * 0.15 + (0.25 if i % 2 else -0.1), sin(a) * 0.1), Vector3.ZERO, Vector3.ONE * (0.22 + 0.04 * (i % 3)), mat(Color(0.6, 0.4, 1.0), 0.3, 0.2, 1.4))
