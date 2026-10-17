extends Node
## Снимки для отчёта v0.5.1: логотип в меню, новые монстры и боссы, карта мира (×1/×3/×7), иконки снаряжения.
## xvfb-run ... $G --path . --rendering-driver vulkan --resolution 1600x900 res://tests/shots_v051.tscn ++ --ignore-lock --no-window-settings
var is_runner := false
var out := "/workspace/rpg-shots/v051/ui"

func shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, n])
	print("shot ", n)

func w(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _cam(cam: Camera3D, pos: Vector3, at: Vector3, fov: float) -> void:
	cam.global_position = pos; cam.look_at(at); cam.fov = fov; cam.current = true

func _ready() -> void:
	if not is_runner:
		var r = load("res://tests/shots_v051.gd").new(); r.is_runner = true
		get_tree().root.add_child.call_deferred(r); return
	DirAccess.make_dir_recursive_absolute(out)
	for f in Game.list_characters(): Game.delete_character(f["id"])
	var rng := RandomNumberGenerator.new(); rng.seed = 51
	var c := DB.new_character("Арина", "warrior", CharAssets.random_look(1, rng))
	c["level"] = 22; c["gold"] = 5000
	DB.set_zone_flag(c, "starter", "boss_troll_killed")
	Game.save_character(c)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	await w(2.0)
	await shot("01_title_logo")
	# --- мир ---
	c["zone"] = "global"; c["has_pos"] = false
	Game.save_character(c); Game.current = c
	get_tree().change_scene_to_file("res://scenes/zone.tscn")
	await w(4.0)
	var z = get_tree().current_scene
	var p: Player = z.player
	p.god_mode = true
	for e in z.enemies.duplicate():
		if is_instance_valid(e): e.alive = false; e.visible = false; e.process_mode = Node.PROCESS_MODE_DISABLED
	z.enemies.clear()
	var wb: WorldBuilder = z.builder
	var spot := Vector3(30, 0, 600)
	wb.prepare(spot); await w(1.0)
	spot.y = z.ground_y(spot); p.teleport(spot + Vector3.UP * 0.1); await w(1.5)
	var base := p.global_position + Vector3(0, 0, 14)
	var cam := Camera3D.new(); z.add_child(cam)
	z.hud.root.visible = false
	var stage := Node3D.new(); z.add_child(stage)
	var lines := [["rat", "bull", "spider", "mushnub", "goblin_shaman", "bee", "orc", "cactoro", "drake"],
		["frog", "crab", "ghost", "bat", "yeti", "hywirl", "imp", "demon", "bluedemon"]]
	for li in lines.size():
		var row: Array = lines[li]
		for i in row.size():
			var pos := base + Vector3((i - 4) * 2.3, 0, 0)
			var e := Enemy.spawn(z, row[i], 15, pos, stage)
			if i % 3 == 1: e.make_rank("elite")
			e.process_mode = Node.PROCESS_MODE_DISABLED
			e.rotation.y = PI
		await w(0.2)
		var gy: float = z.ground_y(base)
		_cam(cam, Vector3(base.x, gy + 3.2, base.z - 13.0), Vector3(base.x, gy + 1.0, base.z), 50)
		await w(1.5); await shot("10_mobs_%d" % (li + 1))
		for ch in stage.get_children(): ch.queue_free()
		z.enemies.clear()
		await w(0.3)
	var bosses := ["boss_ogron", "boss_root", "boss_urgal", "boss_gnil", "boss_hyalm", "boss_seraph"]
	for bi in 2:
		for j in 3:
			var pos := base + Vector3((j - 1) * 7.5, 0, 4)
			var e := Enemy.spawn(z, bosses[bi * 3 + j], 25, pos, stage)
			e.process_mode = Node.PROCESS_MODE_DISABLED; e.rotation.y = PI
		var gy: float = z.ground_y(base)
		_cam(cam, Vector3(base.x, gy + 6.0, base.z - 15.0), Vector3(base.x, gy + 2.5, base.z + 4), 55)
		await w(1.5); await shot("11_bosses_%d" % (bi + 1))
		for ch in stage.get_children(): ch.queue_free()
		z.enemies.clear()
		await w(0.3)
	cam.current = false
	z.hud.root.visible = true
	var cross: Dictionary = WorldData.TOWNS[0]
	var cp := Vector3(cross.pos.x + 6, 0, cross.pos.y + 6); cp.y = z.ground_y(cp); p.teleport(cp + Vector3.UP * 0.1); await w(1.0)
	# --- карта мира ---
	z.hud._open("map"); await w(0.8)
	var mw = z.hud.window
	await shot("20_map_x1")
	mw.center_on_player(); mw.zoom = 3.0; mw.map_rect.queue_redraw(); await w(0.5)
	await shot("21_map_x3")
	var town: Dictionary = WorldData.TOWNS[0]
	mw.center = town.pos; mw.zoom = 7.0; mw.map_rect.queue_redraw(); await w(0.4)
	for mk in mw.markers:
		if mk.cat == "merchant": mw.show_tip(mk); break
	await w(0.3); await shot("22_map_x7_town")
	mw.center = WorldData.BIOMES[4].seed; mw.zoom = 2.2; mw.map_rect.queue_redraw(); await w(0.3)
	for mk in mw.markers:
		if mk.cat == "boss": mw.show_tip(mk); break
	await w(0.3); await shot("23_map_boss_tip")
	z.hud.close_window(); await w(0.3)
	# --- снаряжение: все типы и тиры ---
	var inv: Array = z.data["inventory"]
	inv.clear()
	var tiers := [4, 13, 24]
	var k := 0
	for t in Items.TYPES:
		for ti in 3:
			if inv.size() >= Items.INVENTORY_SIZE: break
			var it := Items.roll(tiers[ti], "warrior", 0.5, false, int(Items.TYPES[t].slot))
			it.type = t; it.cls = Items.TYPES[t].cls; it.name = Items.TYPES[t].names[ti]
			it.rarity = [0, 1, 2, 3][(k + ti) % 4]
			if k % 7 == 3: it["set"] = "wanderer"; it.rarity = Items.SET_RARITY
			inv.append(it)
		k += 1
	z.hud._open("hero"); await w(0.8)
	var iv = z.hud.window
	await shot("30_inventory_icons")
	iv._select(inv[5], false); await w(0.4)
	await shot("31_inventory_tooltip")
	z.hud.close_window(); await w(0.3)
	z.hud._open("shop"); await w(0.8)
	await shot("32_shop_icons")
	z.hud.close_window(); await w(0.3)
	z.hud._open("stash"); await w(0.8)
	await shot("33_stash_icons")
	z.hud.close_window(); await w(0.3)
	# подписи добычи
	for i in 4:
		var it2: Dictionary = inv[i * 9]
		z.hud.pickup(it2.name, DB.RARITY_COLORS[int(it2.rarity)], UIK.item_icon(it2, "warrior"))
	await w(0.5); await shot("34_loot_labels")
	Game.delete_character(c["id"])
	get_tree().quit()
