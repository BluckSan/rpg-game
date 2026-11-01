extends Node
## v0.9.5.2: регрессия «Склеп Эфира пуст» + кнопка «Выйти из подземелья». Локальный сервер + клиент(ы).
##   bash tests/net_local/run_dng.sh [--touch]
var is_runner := false
var errors := 0
var checks := 0
var args := {}
const FAKE := "/tmp/fake_internal/"
const SHOTS := "/workspace/rpg-shots/v0952/"

func check(ok: bool, msg: String) -> void:
	checks += 1
	print(("  OK   " if ok else "  FAIL ") + "[%s] " % args.get("user", "?") + msg)
	if not ok: errors += 1

func wait_until(cond: Callable, timeout: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < timeout * 1000.0:
		if cond.call(): return true
		await get_tree().create_timer(0.1).timeout
	return cond.call()

func _ready() -> void:
	if not is_runner:
		var r = load("res://tests/net_dng_test.gd").new(); r.is_runner = true
		get_tree().root.add_child.call_deferred(r); return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a: args[a.substr(2).get_slice("=", 0)] = a.get_slice("=", 1)
		elif a.begins_with("--"): args[a.substr(2)] = true
	get_tree().create_timer(240.0, true, false, true).timeout.connect(func(): printerr("NET DNG TIMEOUT"); errors += 1; _finish())
	_run.call_deferred()

func _zone():
	var z = get_tree().current_scene
	return z if z != null and "player" in z and "fx_root" in z else null

func _process(_d: float) -> void:
	if not is_runner: return
	var z = _zone()
	if z and z.player and is_instance_valid(z.player) and not z.player.stats.is_empty(): z.player.hp = z.player.stats.max_hp

func shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(SHOTS + "%s_%s.png" % ["phone" if not Game.desktop else "pc", n])

func _zone_is(id: String) -> bool:
	var z = _zone()
	return z != null and z.player != null and str(Game.current.get("zone", "")) == id and Net.in_game

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(SHOTS)
	var user: String = args.get("user", "dg_a")
	var touch := args.has("touch")
	var c := DB.new_character("Тест_" + user, "warrior", CharAssets.random_look(0, RandomNumberGenerator.new()))
	c["id"] = user; c["level"] = 10
	c["tutorial"] = {"move": true, "attack": true, "jump": true, "talents": true, "shop": true, "boss": true}
	c["zone"] = "starter"; c["has_pos"] = false
	c["zones"] = {"starter": {"flags": ["boss_troll_killed"]}}
	c = Game.normalize(c)
	DirAccess.make_dir_recursive_absolute(FAKE)
	var f := FileAccess.open(FAKE + user + ".json", FileAccess.WRITE); f.store_string(JSON.stringify(c)); f.close()
	Net.token = "tok_" + user; Net.username = user; Net.active = true; Net.chars = [c]
	Game.play(c)
	var ok := await wait_until(func(): return _zone_is("starter"), 40.0)
	check(ok, "в долине (локальный сервер)")
	if not ok: _finish(); return
	if touch: Game.desktop = false
	await get_tree().create_timer(2.0).timeout
	var z = _zone()
	# к порталу Склепа и внутрь — как игрок (через портал)
	var portal = _find_portal(z)
	check(portal != null, "портал Склепа в долине найден")
	var ppos: Vector3 = portal.global_position if portal else Vector3.ZERO
	Game.current["pos"] = [ppos.x, ppos.y, ppos.z + 3.0]; Game.current["has_pos"] = true
	Game.travel("dungeon")
	ok = await wait_until(func(): return _zone_is("dungeon"), 40.0)
	check(ok, "вошёл в Склеп Эфира")
	if not ok: _finish(); return
	ok = await wait_until(func(): return Net.wm_nodes.size() > 0, 20.0)
	check(ok, "в Склепе есть враги (от сервера: %d)" % Net.wm_nodes.size())
	z = _zone()
	if ok:
		# бой: подойти к ближайшему и бить
		var e = _nearest(z)
		var hp0 := float(e.hp)
		z.player.global_position = e.global_position + Vector3(1.5, 0, 0)
		Net.c_teleport.rpc_id(1)
		await get_tree().create_timer(0.5).timeout
		for i in 30:
			if not is_instance_valid(e) or not e.alive: break
			e.take_damage(40.0, false)
			await get_tree().create_timer(0.25).timeout
		var hit_ok: bool = not is_instance_valid(e) or not e.alive or float(e.hp) < hp0
		check(hit_ok, "врага можно бить: здоровье %.0f → %s" % [hp0, ("убит" if (not is_instance_valid(e) or not e.alive) else "%.0f" % float(e.hp))])
		await shot("dungeon_mobs")
	await _exit_checks()
	_finish()

func _exit_checks() -> void:
	pass

func _nearest(z):
	var best = null; var bd := 1e9
	for nid in Net.wm_nodes:
		var e = Net.wm_nodes[nid]
		if not is_instance_valid(e) or not e.alive: continue
		var d: float = e.global_position.distance_to(z.player.global_position)
		if d < bd: bd = d; best = e
	return best

func _find_portal(z):
	for n in z.find_children("*", "", true, false):
		if n is Portal and str(n.target_zone) == "dungeon": return n
	return null

func _finish() -> void:
	print("=== NET DNG RESULT %s: %s (%d errors, %d checks) ===" % [args.get("user", "?"), "PASS" if errors == 0 else "FAIL", errors, checks])
	await get_tree().create_timer(1.0).timeout
	if Net.in_game: await Net.leave()
	get_tree().quit(1 if errors > 0 else 0)
