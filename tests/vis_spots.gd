extends Node
## Снимки одних и тех же мест (до/после визуального прохода):
## godot --path . --resolution 1600x900 res://tests/vis_spots.tscn ++ --no-window-settings --ignore-lock --preset=1 --touch --out=/dir --tag=phone_med
var is_runner := false
const SPOTS := [
	["meadows", Vector3(30, 0, 600), 2.4],
	["forest", Vector3(-520, 0, 200), 0.6],
	["desert", Vector3(600, 0, 300), -2.2],
	["swamp", Vector3(-520, 0, -420), 0.9],
	["snow", Vector3(560, 0, -440), -0.8],
	["ruins", Vector3(40, 0, -560), 3.0],
	["town", Vector3(14, 0, 590), 3.1],
	["valley", Vector3(14, 0, 16), 2.3, "starter"],
	["valley_forest", Vector3(-30, 0, 4), 1.4, "starter"],
	["dungeon", Vector3(0, 0, 44), 3.14, "dungeon"],
	["dungeon_arena", Vector3(0, 0, 90), 3.14, "dungeon"],
]

func _ready() -> void:
	if not is_runner:
		var r = load("res://tests/vis_spots.gd").new(); r.is_runner = true
		get_tree().root.add_child.call_deferred(r); return
	var out := "/workspace/rpg-shots/v051"; var tag := "x"; var preset := 2; var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--tag="): tag = a.substr(6)
		if a.begins_with("--preset="): preset = int(a.substr(9))
		if a.begins_with("--only="): only = a.substr(7)
	DirAccess.make_dir_recursive_absolute(out)
	Game.apply_preset(preset)
	for f in Game.list_characters(): Game.delete_character(f["id"])
	var c := DB.new_character("Странник", "warrior", {})
	c["level"] = 20
	for s in SPOTS:
		if only != "" and not only.split(",").has(s[0]): continue
		var p: Vector3 = s[1]
		var zid: String = s[3] if s.size() > 3 else "global"
		if zid == "global":
			WorldData.init()
			p.y = WorldData.height(p.x, p.z) + 0.3
		else: p.y = 0.3
		DB.set_zone_flag(c, "starter", "boss_troll_killed")
		c["zone"] = zid; c["has_pos"] = true; c["pos"] = [p.x, p.y, p.z]
		Game.save_character(c); Game.current = c
		get_tree().change_scene_to_file("res://scenes/zone.tscn")
		await get_tree().create_timer(0.5).timeout
		var z = get_tree().current_scene
		z.player.god_mode = true
		z.player.rotation.y = s[2]
		if z.get("cam_rig"): z.cam_rig.yaw = s[2] + PI
		if z.get("hud"): z.hud.visible = false
		for e in z.enemies: if is_instance_valid(e): e.process_mode = Node.PROCESS_MODE_DISABLED
		await get_tree().create_timer(6.0).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [out, s[0], tag])
		print("shot ", s[0], " ", tag)
	get_tree().quit()
