extends Node
## Проверка яркости по пресетам (нужен дисплей / xvfb, Forward+):
## godot --path . --rendering-driver vulkan --rendering-method forward_plus --resolution 1280x720 res://tests/gfx_check.tscn ++ --no-window-settings --ignore-lock
## Для каждого пресета: снимок 3D без интерфейса, средняя яркость и доля почти чёрных пикселей.
var out := "/workspace/rpg-shots/v041"
var fails := 0
var is_runner := false

func w(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _ready() -> void:
	if not is_runner:
		var r = load("res://tests/gfx_check.gd").new(); r.is_runner = true
		get_tree().root.add_child.call_deferred(r); return
	DirAccess.make_dir_recursive_absolute(out)
	if not DirAccess.dir_exists_absolute(out):
		out = ProjectSettings.globalize_path("user://shots"); DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()

func measure(img: Image) -> Vector2:
	var sum := 0.0; var dark := 0; var n := 0
	var W := img.get_width(); var H := img.get_height()
	for y in range(int(H * 0.15), int(H * 0.85), 6):
		for x in range(int(W * 0.15), int(W * 0.85), 6):
			var c := img.get_pixel(x, y)
			var l := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			if is_nan(l): l = 0.0
			sum += l; n += 1
			if l < 0.06: dark += 1
	return Vector2(sum / maxf(1.0, n), float(dark) / maxf(1.0, n))

func _run() -> void:
	var saved_q := Game.quality
	for f in Game.list_characters(): if str(f.get("name", "")) == "Свет": Game.delete_character(f["id"])
	var rng := RandomNumberGenerator.new(); rng.seed = 3
	var c := DB.new_character("Свет", "warrior", CharAssets.random_look(0, rng))
	c["tutorial"] = {"move": true, "attack": true, "jump": true, "talents": true, "shop": true, "boss": true}
	Game.save_character(c)
	var spots := {"starter": [Vector3(-14, 0.1, -24), Vector3(4, 0.1, 6)], "dungeon": [Vector3(0, 0.1, 8), Vector3(0, 0.1, 96)]}
	DB.set_zone_flag(c, "starter", "boss_troll_killed")
	print("GFX adapter=", RenderingServer.get_video_adapter_vendor(), " / ", RenderingServer.get_video_adapter_name(), " method=", RenderingServer.get_current_rendering_method())
	for zone_id in ["starter", "dungeon"]:
		c["zone"] = zone_id; c["has_pos"] = false
		Game.play(c); await w(2.5)
		var z = get_tree().current_scene
		z.player.god_mode = true
		z.hud.root.visible = false
		for q in range(0, Game.max_quality() + 1):
			Game.apply_preset(q); await w(0.3)
			for i in (spots[zone_id] as Array).size():
				z.player.teleport(spots[zone_id][i]); z.cam_rig.yaw = 150.0; z.cam_rig.distance = 8.0
				await w(2.5 if q >= 4 else 1.2)
				await RenderingServer.frame_post_draw
				var img := get_viewport().get_texture().get_image()
				var m := measure(img)
				var nm := "%s_%d_q%d_%s" % [zone_id, i, q, Game.QUALITY_NAMES[q]]
				img.save_png("%s/%s.png" % [out, nm])
				var lo := 0.08 if zone_id == "dungeon" else 0.18
				var ok := m.x >= lo and m.x <= 0.85 and m.y < (0.45 if zone_id == "dungeon" else 0.2)
				if not ok: fails += 1
				print("GFX %s %s: яркость %.3f, тёмных %.1f%%, gi=%s ssr=%s fog=%s" % ["OK  " if ok else "FAIL", nm, m.x, m.y * 100.0, str(Game.gi_on()), str(Game.ssr_on()), str(Game.vfog_on())])
	Game.apply_preset(saved_q); Game.save_settings()
	Game.delete_character(c["id"])
	print("=== GFX RESULT: %s (%d fail) ===" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails > 0 else 0)
