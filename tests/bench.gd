extends Node
## Замер нагрузки: кадр (мс), вызовы отрисовки, примитивы, объекты — в лагере и у арены.
## Запуск: godot --path . res://tests/bench.tscn ++ [--touch] [--preset=N]
var is_runner := false

func _ready() -> void:
	if not is_runner:
		var r = load("res://tests/bench.gd").new(); r.is_runner = true
		get_tree().root.add_child.call_deferred(r)
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--preset=") and Game.has_method("apply_preset"): Game.call("apply_preset", int(a.substr(9)))
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var c := DB.new_character("Bench", "mage", {"gender": 0})
	Game.save_character(c)
	Game.play(c)
	await get_tree().create_timer(3.0).timeout
	var res := []
	for spot in [["лагерь", Vector3(0, 0.1, -3.5)], ["лес", Vector3(-40, 0.1, 8)], ["арена", Vector3(-4, 0.9, 56)]]:
		var z = get_tree().current_scene
		z.player.teleport(spot[1])
		await get_tree().create_timer(1.5).timeout
		var t0 := Time.get_ticks_usec(); var n := 0
		var dc := 0.0; var prim := 0.0; var obj := 0.0
		while Time.get_ticks_usec() - t0 < 3000000:
			await get_tree().process_frame
			n += 1
			dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			prim += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
			obj += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0 / n
		res.append("%s: %.1f мс/кадр (%.0f fps), вызовов %.0f, примитивов %.0fk, объектов %.0f" % [spot[0], ms, 1000.0 / ms, dc / n, prim / n / 1000.0, obj / n])
	# подземелье
	DB.set_zone_flag(c, "starter", "boss_troll_killed")
	Game.travel("dungeon")
	await get_tree().create_timer(3.0).timeout
	for spot in [["склеп: вход", Vector3(0, 0.1, 3)], ["склеп: арена", Vector3(0, 0.1, 92)]]:
		var z = get_tree().current_scene
		z.player.teleport(spot[1])
		await get_tree().create_timer(1.5).timeout
		var t0 := Time.get_ticks_usec(); var n := 0
		var dc := 0.0; var prim := 0.0
		while Time.get_ticks_usec() - t0 < 3000000:
			await get_tree().process_frame
			n += 1
			dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			prim += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0 / n
		res.append("%s: %.1f мс/кадр (%.0f fps), вызовов %.0f, примитивов %.0fk" % [spot[0], ms, 1000.0 / ms, dc / n, prim / n / 1000.0])
	# открытый мир: город, луга, лес, руины (с подгрузкой чанков)
	c["level"] = 12
	Game.travel("global", "world")
	await get_tree().create_timer(4.0).timeout
	for spot in [["мир: Перекрёсток", Vector3(4, 0, 572)], ["мир: луга", Vector3(160, 0, 640)], ["мир: лес", Vector3(-640, 0, 300)], ["мир: руины", Vector3(60, 0, -700)]]:
		var z = get_tree().current_scene
		var q: Vector3 = spot[1]; q.y = WorldData.height(q.x, q.z) + 0.4
		z.player.teleport(q)
		await get_tree().create_timer(3.0).timeout
		var t0 := Time.get_ticks_usec(); var n := 0
		var dc := 0.0; var prim := 0.0; var worst := 0.0; var last := t0
		while Time.get_ticks_usec() - t0 < 3000000:
			await get_tree().process_frame
			var now := Time.get_ticks_usec(); worst = maxf(worst, (now - last) / 1000.0); last = now
			n += 1
			dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			prim += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0 / n
		res.append("%s: %.1f мс/кадр (%.0f fps, худший %.0f мс), вызовов %.0f, примитивов %.0fk, чанков %d" % [spot[0], ms, 1000.0 / ms, worst, dc / n, prim / n / 1000.0, get_tree().current_scene.builder.chunks.size()])
	print("BENCH desktop=%s scale=%.2f method=%s q=%d" % [str(Game.desktop), get_tree().root.scaling_3d_scale, RenderingServer.get_current_rendering_method(), Game.quality])
	for r in res: print("BENCH ", r)
	Game.delete_character(c["id"])
	get_tree().quit()
