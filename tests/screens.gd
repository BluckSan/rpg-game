extends Node
## Снимки экрана для визуальной проверки (нужен дисплей / xvfb):
## godot --path . --rendering-driver opengl3 --resolution 1920x1080 res://tests/screens.tscn
## Сохраняет в /workspace/rpg-shots/ (или в user://shots, если папки нет).
var is_runner := false
var out := "/workspace/rpg-shots"
var only := ""

func shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, n])
	print("shot ", n)

func w(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func want(n: String) -> bool:
	return only == "" or only.split(",").has(n)

func _ready() -> void:
	if not is_runner:
		var r = load("res://tests/screens.gd").new(); r.is_runner = true
		get_tree().root.add_child.call_deferred(r); return
	if not DirAccess.dir_exists_absolute(out):
		out = ProjectSettings.globalize_path("user://shots"); DirAccess.make_dir_recursive_absolute(out)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="): only = a.substr(7)
	for f in Game.list_characters(): Game.delete_character(f["id"])
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	var look := CharAssets.random_look(1, rng)
	look.preset = 4; look.morphs = (CharAssets.PRESETS[4][1] as Dictionary).duplicate(); look.hair = 3; look.hair_color = 3; look.eye_color = 2
	var c := DB.new_character("Арина", "warrior", look)
	Game.save_character(c)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	await w(1.2)
	var menu = get_tree().current_scene
	if want("menu"): await shot("01_menu")
	menu.open_creator(); await w(0.3)
	var cr = null
	for ch in menu.screen.get_children():
		if ch.has_method("randomize_look"): cr = ch
	cr.look = CharAssets.random_look(0, rng); cr.look.beard = 1; cr.look.hair = 2; cr.char_name = "Торин"; cr._refresh(true)
	cr.set_class("warrior"); menu.yaw = 0.5; await w(1.2)
	if want("creator"): await shot("02_creator")
	cr.set_tab(2); menu.yaw = 0.25
	cr.apply_preset(2); await w(1.5)
	if want("face"): await shot("03_face_editor")
	cr.set_tab(2); cr.look.morphs = {"ears_point": 1.0, "eye_size": 0.6, "cheekbones": 0.8, "jaw_width": -0.6, "nose_width": -0.6}
	cr.look.beard = 0; cr.look.hair = 3; cr.look.hair_color = 7; cr._refresh(); menu.yaw = -0.35; await w(1.2)
	if want("face"): await shot("04_face_elf")
	cr.set_gender(1); cr.look.hair = 4; cr.look.hair_color = 5; cr.set_tab(3); await w(1.5)
	if want("face"): await shot("05_hair_female")
	cr.set_tab(1); cr.set_class("mage"); await w(1.3)
	if want("creator"): await shot("06_creator_mage")
	menu.set_focus(false); menu.show_select(); await w(0.3)
	Game.play(c); await w(2.5)
	var z = get_tree().current_scene
	if want("zone"): await shot("07_zone")
	# --- сцены-витрины в зоне (своя камера) ---
	var cam := Camera3D.new(); z.add_child(cam)
	var base := Vector3(-4, 0.8, 65)
	z.player.teleport(Vector3(0, 0.1, -20))
	z.hud.root.visible = false
	var boss_node = null
	for e in z.enemies.duplicate():
		if e.def.boss: boss_node = e; e.visible = false; e.set_process(false)
		elif U.flat_dist(e.global_position, base) < 25: e.queue_free(); z.enemies.erase(e)
	var stage := Node3D.new(); z.add_child(stage)
	if want("classes"):
		var i := 0
		for cls in ["warrior", "archer", "mage"]:
			var v := CharVisual.new(); stage.add_child(v)
			v.position = base + Vector3((i - 1) * 1.6, 0, 0); v.rotation.y = PI + deg_to_rad(-15 + i * 15)
			var l := CharAssets.random_look(i % 2, rng); v.build(l, cls, "")
			v.speed_override = 0
			i += 1
		_cam(cam, base + Vector3(0, 1.4, -5.2), base + Vector3(0, 0.95, 0), 40)
		await w(1.2); await shot("08_classes")
		for v in stage.get_children(): v.play_action("attack")
		await w(0.35); await shot("09_classes_attack")
		_clear(stage)
	if want("asc"):
		var i := 0
		for a in ["berserker", "paladin", "elementalist", "necromancer", "shadow", "druid"]:
			var cls := "warrior" if a in ["berserker", "paladin"] else ("mage" if a in ["elementalist", "necromancer"] else "archer")
			var v := CharVisual.new(); stage.add_child(v)
			v.position = base + Vector3((i - 2.5) * 1.5, 0, 0); v.rotation.y = PI
			v.build(CharAssets.random_look(i % 2, rng), cls, a)
			v.speed_override = 0
			i += 1
		_cam(cam, base + Vector3(0, 1.6, -7.5), base + Vector3(0, 0.9, 0), 42)
		await w(1.5); await shot("10_transformations")
		_clear(stage)
	if want("mobs"):
		var defs := [["slime", -4.2], ["wolf", -2.6], ["skeleton", -0.9], ["skeleton_archer", 0.5], ["goblin", 1.9], ["troll", 4.0]]
		for d in defs:
			var e := Enemy.spawn(z, d[0], 3, base + Vector3(d[1], 0, 0), stage)
			e.set_process(false)
			e.rotation.y = PI + deg_to_rad(-10)
			if e.model is CharVisual: e.model.speed_override = 0
			else: e.model.speed_override = 0
		_cam(cam, base + Vector3(0, 2.0, -9.5), base + Vector3(0, 1.3, 0), 42)
		await w(1.5)
		await shot("11_mobs")
		for e in stage.get_children():
			if e is Enemy: e._model_action("attack")
		await w(0.45); await shot("12_mobs_attack")
		_clear(stage)
	if boss_node: boss_node.visible = true; boss_node.set_process(true)
	z.hud.root.visible = true
	# --- арена босса ---
	if want("boss"):
		var a := Vector3(-4, 0, 64)
		_cam(cam, a + Vector3(9, 7, -26), a + Vector3(0, 0.5, -6), 50)
		await w(1.5); await shot("13_arena_ramp")
		cam.current = false
		z.player.teleport(a + Vector3(0, 1.0, -9)); z.player.face_towards(a)
		z.player.god_mode = true
		await w(2.0); await shot("14_boss")
		var boss = null
		for e in z.enemies:
			if e.def.boss: boss = e
		if boss:
			_cam(cam, boss.global_position + Vector3(4, 3.2, -6.5), boss.global_position + Vector3(0, 2.0, 0), 45)
			await w(0.4); await shot("15_boss_close")
		cam.current = false
		z.player.god_mode = false
	if want("ui"):
		z.player.teleport(Vector3(16, 0.1, 18)); await w(1.5)
		await shot("16_zone_gameplay")
	Game.delete_character(c["id"])
	get_tree().quit()

func _cam(cam: Camera3D, pos: Vector3, at: Vector3, fov: float) -> void:
	cam.global_position = pos; cam.look_at(at); cam.fov = fov; cam.current = true

func _clear(n: Node) -> void:
	for ch in n.get_children():
		if ch is Enemy: ch.zone.enemies.erase(ch)
		ch.queue_free()
