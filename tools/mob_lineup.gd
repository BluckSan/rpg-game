extends Node3D
## Ряд всех моделей монстров с шестом 1.8 м — проверка масштаба/ориентации (xvfb):
## godot --path . --rendering-driver vulkan res://tools/mob_lineup.tscn ++ out=/tmp/lineup.png [kinds=a,b]
func _ready() -> void:
	var out := "/tmp/lineup.png"; var kinds: Array = MobModel.DEFS.keys()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
		if a.begins_with("kinds="): kinds = Array(a.substr(6).split(","))
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.5, 0.6, 0.7)
	env.environment.ambient_light_color = Color.WHITE; env.environment.ambient_light_energy = 0.6
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, 30, 0); add_child(sun)
	var g := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(200, 40); g.mesh = pm; add_child(g)
	var i := 0
	var cols := mini(8, kinds.size())
	for k in kinds:
		var x := float(i % cols) * 3.2 - cols * 1.6; var z := float(i / cols) * -5.0
		var m := MobModel.new(); add_child(m); m.position = Vector3(x, 0, z); m.setup(k); m.rotation_degrees.y = 35
		var pole := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(0.08, 1.8, 0.08); pole.mesh = bm
		add_child(pole); pole.position = Vector3(x + 1.3, 0.9, z)
		var l := Label3D.new(); l.text = k; l.font_size = 64; l.pixel_size = 0.006; add_child(l); l.position = Vector3(x, 0.15, z + 1.2)
		l.rotation_degrees.x = -30
		i += 1
	var cam := Camera3D.new(); add_child(cam)
	var rows := ceili(kinds.size() / float(cols))
	cam.position = Vector3(0, 2.0 + rows * 2.0, 7.5 + rows * 2.0); cam.look_at(Vector3(0, 0.9, -(rows - 1) * 2.5))
	cam.fov = 50
	cam.current = true
	for f in 30: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
