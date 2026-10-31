extends Node
## v0.9.4.2: снимки мини-карты и карты мира (до/после). ++ --pref=<before|after> [--touch]
var is_runner := false
var out := "/workspace/rpg-shots/v0942"
var pref := "after"
var fails := 0
func ck(ok: bool, t: String) -> void:
	print(("  OK  " if ok else "  FAIL ") + t)
	if not ok: fails += 1
func shot(n: String, mm = null) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var base := "%s/%s_%s_%s" % [out, pref, ("pc" if Game.desktop else "phone"), n]
	img.save_png(base + ".png")
	if mm != null:   # крупно: мини-карта
		var r: Rect2 = (mm as Control).get_global_rect().grow(30)
		var s := get_viewport().get_visible_rect().size
		var k := Vector2(img.get_width(), img.get_height()) / s
		var ri := Rect2i(Vector2i(r.position * k), Vector2i(r.size * k)).intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
		img.get_region(ri).save_png(base + "_mini.png")
	print("shot ", n)
func w(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout
func _ready() -> void:
	if not is_runner:
		var r = load("res://tests/map_shots.gd").new(); r.is_runner = true
		get_tree().root.add_child.call_deferred(r); return
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(240.0, true, false, true).timeout.connect(func(): printerr("MAP SHOTS TIMEOUT"); get_tree().quit(2))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pref="): pref = a.substr(7)
	DirAccess.make_dir_recursive_absolute(out)
	for f in Game.list_characters(): Game.delete_character(f["id"])
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	var c := DB.new_character("Арина", "warrior", CharAssets.random_look(1, rng))
	c["level"] = 18
	Game.save_character(c)
	Game.play(c); await w(7.0)
	var z = get_tree().current_scene
	z.player.god_mode = true
	Game._toast_panel.visible = false
	await shot("01_valley", z.hud.minimap)
	Game.travel("global"); await w(9.0)
	z = get_tree().current_scene
	z.player.god_mode = true
	var wb = z.builder
	for wp in wb.waypoints: wb.world_state()["wp"].append(wp.id)
	# у Сухого Колодца (город, рядом портал подземелья и враги)
	var t: Dictionary = WorldData.TOWNS[2]
	var dest := Vector3(t.pos.x + 20, 0, t.pos.y - 40); dest.y = WorldData.height(dest.x, dest.z) + 0.3
	wb.prepare(dest); z.player.teleport(dest); await w(5.0)
	Game._toast_panel.visible = false
	if z.hud.hint_panel: z.hud.hint_panel.visible = false
	if z.has_method("add_user_marker"):
		z.add_user_marker(Vector2(t.pos.x + 60, t.pos.y - 70), "Сбор")
		z.add_user_marker(Vector2(-540, -380), "Топкий")
	await shot("02_world_minimap", z.hud.minimap)
	if z.hud.minimap.has_method("self_check"): for r2 in z.hud.minimap.self_check(): ck(r2[0], r2[1])
	z.hud._open("map"); await w(1.0)
	await shot("03_worldmap")
	var wm = z.hud.window
	if wm and wm.has_method("audit"): for r3 in wm.audit(): ck(r3[0], r3[1])
	wm.zoom_by(3.0); wm.center_on_player(); await w(0.6)
	await shot("04_worldmap_zoom")
	if wm.has_method("marker_mode"):
		wm.marker_mode(true); await w(0.3)
		await shot("05_worldmap_marker_mode")
	z.hud.close_window(); await w(0.3)
	print("=== MAP SHOTS RESULT: %s (%d fails) ===" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails > 0 else 0)
