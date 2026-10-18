extends Node
## Снимки онлайн-режима: экран входа и мир с другим игроком (партнёр — второй процесс net_test).
var is_runner := false
func _ready() -> void:
	if not is_runner:
		var r = load("res://tests/net_shot.gd").new(); r.is_runner = true
		get_tree().root.add_child.call_deferred(r); return
	var out := "/workspace/rpg-shots/v070"; var user := "shooter"; var other := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--user="): user = a.substr(7)
		if a.begins_with("--other="): other = a.substr(8)
	DirAccess.make_dir_recursive_absolute(out)
	get_tree().create_timer(200.0, true, false, true).timeout.connect(func(): get_tree().quit(2))
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	await get_tree().create_timer(2.0).timeout
	var mm = get_tree().current_scene
	Net.token = ""   # показать форму входа, а не автовход
	mm.show_online()
	await get_tree().create_timer(1.0).timeout
	mm._user_edit.text = user; mm._pass_edit.text = "test-pass-123"
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/online_login.png")
	var e := await Net.login(user, "test-pass-123", true)
	if e.contains("занят"): e = await Net.login(user, "test-pass-123", false)
	if Net.chars.is_empty():
		Game.save_character(DB.new_character("Герой_" + user, "archer", {"gender": 1}))
		for i in 40:
			if not Net.chars.is_empty(): break
			await get_tree().create_timer(0.25).timeout
	mm.show_select()
	await get_tree().create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/online_select.png")
	Game.play(Net.chars[0])
	for i in 200:
		if Net.in_game and "player" in get_tree().current_scene and get_tree().current_scene.player != null and get_tree().get_nodes_in_group("remote_players").size() > 0: break
		await get_tree().create_timer(0.25).timeout
	await get_tree().create_timer(2.0).timeout
	var z = get_tree().current_scene
	var rp = get_tree().get_nodes_in_group("remote_players")
	if rp.size() > 0:
		z.player.global_position = rp[0].global_position + Vector3(2.2, 0, 2.2)
		Net.notify_teleport()
		if z.get("cam_rig"): z.cam_rig.yaw = 0.8
	Net.send_chat("Привет! Идём в лес?")
	await get_tree().create_timer(4.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/online_world.png")
	print("NET SHOTS DONE remotes=%d" % rp.size())
	Game.to_menu()
	await get_tree().create_timer(1.5).timeout
	get_tree().quit()
