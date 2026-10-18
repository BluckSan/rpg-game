extends Node3D
## Просмотр реалистичных ассетов v0.6.0: деревья TreeGen и запечённые меши Poly Haven на земле, снимок в LAB_OUT.
## LAB_SET=trees|rocks|plants|props; LAB_CAM="x,y,z,tx,ty,tz"
func _ready() -> void:
	var set := OS.get_environment("LAB_SET")
	if set == "": set = "trees"
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40, -50, 0); sun.shadow_enabled = true; sun.light_energy = 1.3
	sun.light_color = Color(1, 0.94, 0.85)
	add_child(sun)
	var we := WorldEnvironment.new(); var e := Environment.new()
	var sky := Sky.new(); var sm := ProceduralSkyMaterial.new(); sky.sky_material = sm
	e.background_mode = Environment.BG_SKY; e.sky = sky; e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_ACES; e.tonemap_white = 6.0
	we.environment = e; add_child(we)
	var g := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(200, 200); g.mesh = pm
	var gm := StandardMaterial3D.new(); gm.albedo_color = Color(0.25, 0.3, 0.18); g.material_override = gm; add_child(g)
	var items := []
	match set:
		"trees":
			for k in ["oak", "birch", "autumn", "pine", "fir", "snowfir", "dead", "swamp"]:
				items.append(TreeGen.mesh(k, 0)); 
		"trees_lod":
			for k in ["oak", "pine", "fir", "dead"]:
				items.append(TreeGen.mesh(k, 1, 0)); items.append(TreeGen.mesh(k, 1, 1))
		_:
			var d := DirAccess.open("res://assets/real/mesh/")
			var names := []
			for f in d.get_files():
				if f.ends_with(".res"): names.append(f.get_basename())
			names.sort()
			var pref: Array = {"rocks": ["rock_"], "plants": ["fern", "shrub", "tuft", "sorrel", "weed", "nettle", "rooibos", "dandelion", "grassclump", "periwinkle", "quiver"],
				"props": ["stump", "log", "branches", "roots", "barrel", "wine", "crate", "bucket", "chest", "lantern", "fire_pit", "table", "stool", "statue", "ladder", "castle", "spinning", "basket", "axe", "fort"]}[set]
			for n in names:
				for pr in pref:
					if n.begins_with(pr): items.append(load("res://assets/real/mesh/%s.res" % n)); break
	var cols := int(ceil(sqrt(items.size())))
	var sp := 9.0 if set.begins_with("trees") else (3.5 if set == "rocks" else (1.2 if set == "plants" else 2.5))
	for i in items.size():
		var mi := MeshInstance3D.new(); mi.mesh = items[i]; add_child(mi)
		mi.position = Vector3((i % cols) * sp - cols * sp * 0.5, 0, (i / cols) * sp)
	var cam := Camera3D.new(); add_child(cam)
	var cs := OS.get_environment("LAB_CAM")
	var w := cols * sp
	if cs != "":
		var v := cs.split(","); cam.position = Vector3(float(v[0]), float(v[1]), float(v[2])); cam.look_at(Vector3(float(v[3]), float(v[4]), float(v[5])))
	else:
		cam.position = Vector3(0, w * 0.35, -w * 0.55); cam.look_at(Vector3(0, w * 0.04, w * 0.3))
	cam.current = true; cam.fov = 55
	for i in 20: await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_environment("LAB_OUT"))
	print("LAB SAVED")
	get_tree().quit()
