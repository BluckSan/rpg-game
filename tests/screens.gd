extends Node
## Снимки экрана для визуальной проверки (нужен дисплей): godot --path . res://tests/screens.tscn
var is_runner := false
func shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/shot_%s.png" % n)
	print("shot ", n)
func w(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
func _ready() -> void:
	if not is_runner:
		var r = load("res://tests/screens.gd").new(); r.is_runner = true
		get_tree().root.add_child.call_deferred(r); return
	for f in Game.list_characters(): Game.delete_character(f["id"])
	var c := DB.new_character("Арина", "mage", {"gender": 1, "height": 1.0, "build": 1.0, "skin": 1, "face": 2, "hair": 3, "hair_color": 2, "eye_color": 1})
	Game.save_character(c)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	await w(1.0); r_shot("menu")
	await w(0.5)
	var menu = get_tree().current_scene
	menu.open_creator(); await w(1.0); await shot("creator")
	menu.show_select(); await w(0.3)
	Game.play(c); await w(2.0)
	var z = get_tree().current_scene
	await shot("zone")
	z.player.teleport(Vector3(-4, 0.1, 54)); await w(1.5)
	for e in z.enemies:
		if e.def.boss: print("boss ", e.global_position, " player ", z.player.global_position, " cam ", get_viewport().get_camera_3d().global_position, " vis ", e.is_visible_in_tree())
	await shot("boss")
	z.cam_rig.rotate_by(PI, 0); await w(0.5); await shot("boss2")
	z.hud._open("talents"); await w(0.7); await shot("talents")
	z.hud.close_window(); z.hud._open("hero"); await w(0.7); await shot("hero")
	z.hud.close_window()
	Game.delete_character(c["id"])
	get_tree().quit()
func r_shot(n): await shot(n)
