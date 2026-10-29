extends Node
## v0.9.3: снимки интерфейса и эффектов. ++ --out=<dir> --pref=<before|after> [--touch] [--vfx]
var is_runner := false
var out := "/workspace/rpg-shots/v093"
var pref := "after"
func shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s_%s_%s.png" % [out, pref, ("pc" if Game.desktop else "phone"), n])
	print("shot ", n)
func w(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout
func _ready() -> void:
	if not is_runner:
		var r = load("res://tests/ui_shots.gd").new(); r.is_runner = true
		get_tree().root.add_child.call_deferred(r); return
	process_mode = Node.PROCESS_MODE_ALWAYS
	var vfx := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--pref="): pref = a.substr(7)
		if a == "--vfx": vfx = true
	DirAccess.make_dir_recursive_absolute(out)
	for f in Game.list_characters(): Game.delete_character(f["id"])
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	var cls := "mage" if vfx else "warrior"
	var c := DB.new_character("Арина", cls, CharAssets.random_look(1, rng))
	c["level"] = 18
	Game.save_character(c)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	await w(1.5)
	if not vfx: await shot("00_menu")
	Game.play(c); await w(3.0)
	var z = get_tree().current_scene
	z.player.god_mode = true
	if vfx: await _vfx(z); get_tree().quit(); return
	await shot("01_hud")
	for wn in ["hero", "skills", "talents", "map", "pause"]:
		z.hud._open(wn); await w(0.8); await shot("02_" + wn); z.hud.close_window(); await w(0.3)
	if z.hud.has_method("toggle_menu"):
		z.hud.toggle_menu(); await w(0.5); await shot("03_menu_button"); z.hud.toggle_menu(); await w(0.3)
	get_tree().quit()

func _vfx(z) -> void:
	var p: Player = z.player
	var at: Vector3 = p.global_position + p.forward() * 6.0
	var cam := Camera3D.new(); z.add_child(cam)
	cam.global_position = p.global_position + Vector3(4.5, 3.2, -1.5) + p.forward() * 1.0
	cam.look_at(at + Vector3.UP * 0.8); cam.current = true
	var fx = z.fx_root
	var names := ["fire", "ice", "lightning", "heal", "slash", "hit"]
	for n in names:
		await w(0.6)
		match n:
			"fire": Vfx.impact(fx, at + Vector3.UP, "fire", 1.6); Vfx.scorch(fx, at, 2.0)
			"ice": Vfx.impact(fx, at + Vector3.UP, "ice", 1.6)
			"lightning": Vfx.lightning(fx, at + Vector3.UP * 10, at + Vector3.UP * 0.2, Color(0.7, 0.8, 1.0), 0.6)
			"heal": Vfx.aura(fx, p, Color(0.5, 1.0, 0.5), 1.5); Vfx.beam(fx, p.global_position + Vector3.UP * 8, p.global_position, Color(1, 0.9, 0.5), 1.0)
			"slash": CombatFX.slash_arc(fx, at, Vector3.FORWARD, 3.0, 160, Color(1, 0.85, 0.6), 0.6)
			"hit": CombatFX.hit(fx, at + Vector3.UP, "beast", true, Vector3.BACK)
		await w(0.12); await shot("vfx_" + n)
		await w(0.3); await shot("vfx_" + n + "_b")
