extends Node3D
## Снимок модели: godot --path . res://tests/model_shot.tscn ++ --glb=res://... --out=file.png
func _ready() -> void:
	var glb := "res://assets/mobs/lich/keltaar.glb"; var out := "/tmp/model.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--glb="): glb = a.substr(6)
		if a.begins_with("--out="): out = a.substr(6)
	var env := WorldEnvironment.new(); var e := Environment.new(); e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.15, 0.17, 0.2); e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.environment = e; add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40, 30, 0); add_child(sun)
	var mob := "--mob" in OS.get_cmdline_user_args()
	for i in 3:
		var m: Node3D
		if mob:
			m = MobModel.new(); add_child(m); m.setup("lich", {"scale": 1.0})
			if i == 1: m.play_action("attack")
			if i == 2: m.play_action("cast")
		else:
			m = load(glb).instantiate(); add_child(m)
		m.position = Vector3((i - 1) * 1.6, 0, 0); m.rotation_degrees.y = [0, 30, -30][i] if mob else [0, 90, 180][i]
	var cam := Camera3D.new(); add_child(cam); cam.position = Vector3(0, 0.9, 4.6) if mob else Vector3(0, 0.6, 3.2); cam.look_at(Vector3(0, 0.7 if mob else 0.5, 0)); cam.current = true
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out); get_tree().quit()
