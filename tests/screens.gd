extends Node
## Снимки экрана для визуальной проверки (нужен дисплей / xvfb):
## godot --path . --rendering-driver opengl3 --resolution 1920x1080 res://tests/screens.tscn
## Сохраняет в /workspace/rpg-shots/ (или в user://shots, если папки нет).
var is_runner := false
var out := "/workspace/rpg-shots/v040"
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
	DirAccess.make_dir_recursive_absolute(out)
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
	if want("menu"): await shot("00_title")
	if want("menu"):
		menu.show_settings(); await w(0.5); await shot("00b_settings")
		for ch in menu.ui.get_children():
			if ch is SettingsPanel: ch.queue_free()
	menu.show_select(); await w(1.0)
	if want("menu"): await shot("01_menu")
	if want("menu"):
		menu._on_delete(); await w(0.4); await shot("01b_delete_confirm"); menu.cancel_delete(); await w(0.2)
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
	if want("v040"):
		await _v040_shots(z); return
	if want("v041"):
		await _v041_shots(z); return
	if want("v050ui"):
		await _v050_ui_shots(z); return
	if want("v050bal"):
		await _v050_bal_shots(z); return
	if want("v050world"):
		await _v050_world_shots(z); return
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
	await _v030(z, c, rng)
	Game.delete_character(c["id"])
	Engine.time_scale = 1.0
	get_tree().quit()

# ---------------- v0.3: интерфейс, бой, босс, лавка ----------------
func _v030(z, c: Dictionary, rng: RandomNumberGenerator) -> void:
	var p: Player = z.player
	p.god_mode = true
	if want("hud"):
		z.data["tutorial"] = {}
		z.hud._start_pos = z.spawn_point
		z.hud.hint_id = ""
		p.teleport(z.spawn_point + Vector3(1.5, 0, 1)); p.face_towards(z.merchant_point)
		z.cam_rig.yaw = 200.0
		await w(1.5); await shot("20_hud_tutorial_hint")
		z.hud._hint_done(); z.hud._hint_done()
		p.teleport(z.merchant_point + Vector3(1.2, 0.1, 2.2)); p.face_towards(z.merchant_point)
		z.cam_rig.yaw = 150.0
		await w(1.5); await shot("21_merchant_interact")
		for k in z.hud.HINTS: z.data["tutorial"][k] = true
		z.hud._hint_done()
	for k in z.hud.HINTS: z.data["tutorial"][k] = true
	z.hud._hint_done()
	if want("shop"):
		z.data["gold"] = 1460
		for i in 5: z.data["inventory"].append(DB.roll_item(rng.randi_range(2, 6), z.data["class"], 0.3))
		z.hud._open("shop"); await w(0.6)
		var s = z.hud.window
		s._select("stock", 1); await w(0.4)
		await shot("22_shop_buy")
		s.select_tab("sell"); s._select("inv", 0); await w(0.4)
		await shot("23_shop_sell")
		s.sell(0); s.sell(0)
		s.select_tab("buyback"); s._select("buyback", 0); await w(0.4)
		await shot("23b_shop_buyback")
		z.hud.close_window(); await w(0.3)
	if want("inv"):
		for i in 3: z.data["inventory"].append(DB.roll_item(6, z.data["class"], 0.6))
		z.hud._open("hero"); await w(0.6)
		var iv = z.hud.window
		iv._select(z.data["inventory"][z.data["inventory"].size() - 1], false); await w(0.4)
		await shot("24_hero_inventory_tooltip")
		z.hud.close_window(); await w(0.3)
	if want("talents"):
		z.data["level"] = max(int(z.data["level"]), 4)
		z.hud._open("talents"); await w(0.6)
		var tw = z.hud.window
		var nid: int = DB.tree_nodes[DB.start_node(z.data["class"])]["links"][0] if DB.tree_nodes[DB.start_node(z.data["class"])].has("links") else DB.start_node(z.data["class"])
		tw._tap(tw._to_screen(DB.tree_nodes[nid]["pos"])); await w(0.5)
		await shot("25_talent_tooltip")
		z.hud.close_window(); await w(0.3)
	# бой: стая слизней возле лагеря
	var arena := Vector3(14, 0, 6)
	if want("levelup") or want("combat"):
		p.teleport(arena + Vector3(0, 0.1, -2)); await w(0.5)
	if want("levelup"):
		p.gain_xp(DB.xp_to_next(z.data["level"]) + 5)
		z.hud.pickup("+48 золота", Color(1, 0.85, 0.35), "two-coins")
		z.hud.pickup("+1 зелье лечения", Color(1, 0.4, 0.4), "health-potion")
		var it := DB.roll_item(5, z.data["class"], 0.5)
		z.hud.pickup(it.name, DB.RARITY_COLORS[int(it.rarity)], UIK.item_icon(it, z.data["class"]))
		await w(0.6); await shot("26_levelup_loot_feed")
		await w(3.0)
	if want("combat"):
		await _combat_shots(z, "warrior", arena)
	if want("skilltip"):
		z.hud.show_skill_tooltip(1); await w(0.5)
		await shot("30_skill_tooltip")
		z.hud._hide_tooltip()
	if want("boss2"):
		await _boss_shots(z)
	if want("classes2"):
		for cls in ["archer", "mage"]:
			var c2 := DB.new_character("Тест", cls, CharAssets.random_look(1 if cls == "archer" else 0, rng))
			c2["level"] = 8; c2["class_level"] = 3; c2["tutorial"] = {"move": true, "attack": true, "jump": true, "talents": true, "shop": true, "boss": true}
			Game.save_character(c2)
			Game.play(c2); await w(2.5)
			var z2 = get_tree().current_scene
			z2.player.god_mode = true
			z2.player.teleport(arena + Vector3(0, 0.1, -2)); await w(0.5)
			await _combat_shots(z2, cls, arena)
			Game.delete_character(c2["id"])

func _pack(z, center: Vector3, n: int) -> Array:
	var out := []
	for i in n:
		var e := Enemy.spawn(z, ["slime", "goblin", "skeleton"][i % 3], 3, center + Vector3((i - 1) * 1.3, 0, 0.4 * (i % 2)), z.fx_root)
		e.max_hp = 9999; e.hp = 9999
		e.def = e.def.duplicate(); e.def.aggro = 0.0; e.def.dmg = 0.0
		out.append(e)
	return out

func _combat_shots(z, cls: String, arena: Vector3) -> void:
	var p: Player = z.player
	var mobs := _pack(z, arena + Vector3(0, 0, 2.2 if cls == "warrior" else 6.0), 3)
	p.teleport(arena + Vector3(0, 0.1, 0)); p.face_towards(mobs[1].global_position)
	z.cam_rig.yaw = 120.0; z.cam_rig.distance = 7.5
	await w(1.0)
	p.data["class_level"] = 3; p.recalc(true)
	z.base_time_scale = 0.3; Engine.time_scale = 0.3
	var pre: String = {"warrior": "27", "archer": "28", "mage": "29"}[cls]
	for k in 3:
		p.cooldowns[0] = 0
		p.face_towards(mobs[1].global_position)
		p.try_use(0)
		await w(0.22 if cls == "warrior" else 0.3)
		await shot("%s_combo_%s_hit%d" % [pre, cls, k + 1])
		await w(0.35)
	# умение 1
	p.cooldowns[1] = 0; p.mp = p.stats.max_mp
	p.try_use(1)
	await w(0.3); await shot("%s_skill1_%s" % [pre, cls])
	await w(0.6)
	if cls == "archer":
		# крупный план лука во время выстрела
		var cam := Camera3D.new(); z.add_child(cam)
		p.cooldowns[0] = 0; p.try_use(0)
		await w(0.12)
		var hp := p.global_position
		var side := p.forward().cross(Vector3.UP).normalized()
		cam.global_position = hp + side * 2.2 + p.forward() * 1.2 + Vector3.UP * 1.5
		cam.look_at(hp + Vector3.UP * 1.25); cam.fov = 40; cam.current = true
		await shot("28b_archer_bow_closeup")
		cam.current = false; cam.queue_free()
	Engine.time_scale = 1.0; z.base_time_scale = 1.0
	z.cam_rig.distance = 11.0
	for e in mobs:
		if is_instance_valid(e) and e.alive: e.take_damage(999999, false)
	await w(1.0)

func _boss_shots(z) -> void:
	var p: Player = z.player
	var boss = null
	for e in z.enemies:
		if e.def.boss: boss = e
	if boss == null: return
	var a: Vector3 = z.arena_point
	p.teleport(a + Vector3(0, 0.3, -7)); p.face_towards(boss.global_position)
	z.cam_rig.yaw = 0.0; z.cam_rig.distance = 13.0
	await w(2.0)
	var br = boss.brain
	br.special_timer = 99.0
	boss.hp = boss.max_hp * 0.6
	await w(0.5)
	await shot("31_boss_phase2_banner")
	await w(1.8)
	br.special_timer = 99.0
	while br.busy: await w(0.1)
	br.special_timer = 99.0
	br.run("slam", p)
	await w(0.6); await shot("32_boss_slam_telegraph")
	await w(0.85); await shot("33_boss_shockwave")
	while br.busy: await w(0.1)
	br.special_timer = 99.0
	br.run("charge", p)
	await w(0.5); await shot("34_boss_charge_telegraph")
	while br.busy: await w(0.1)
	br.special_timer = 99.0
	br.run("rock", p)
	await w(0.9); await shot("35_boss_rock_throw")
	while br.busy: await w(0.1)
	boss.hp = boss.max_hp * 0.3
	await w(0.7); await shot("36_boss_phase3_enrage")
	await w(2.0)
	br.special_timer = 99.0
	while br.busy: await w(0.1)
	br.summon_timer = 0
	br.run("summon", p)
	await w(1.6); await shot("37_boss_summon_adds")
	p.god_mode = false

func _cam(cam: Camera3D, pos: Vector3, at: Vector3, fov: float) -> void:
	cam.global_position = pos; cam.look_at(at); cam.fov = fov; cam.current = true

func _clear(n: Node) -> void:
	for ch in n.get_children():
		if ch is Enemy: ch.zone.enemies.erase(ch)
		ch.queue_free()


func _v040_shots(z) -> void:
	var p: Player = z.player
	p.god_mode = true
	z.data["level"] = 12; z.data["class_level"] = 3; p.recalc(true)
	z.cam_rig.yaw = 150.0; z.cam_rig.distance = 8.0
	p.teleport(Vector3(-14, 0.1, -24)); await w(2.0)
	await shot("40_world_%s" % ("hi" if Game.heavy_fx() else "std"))
	p.teleport(Vector3(-24, 0.1, 50)); z.cam_rig.yaw = 200.0; await w(1.5)
	await shot("41_dungeon_gate")
	p.teleport(Vector3(4, 0.1, 6)); await w(0.8)
	Game.skill_layout = "mobile"; z.hud.apply_skill_layout(); await w(0.4)
	await shot("42_layout_mobile")
	Game.skill_layout = "pc"; z.hud.apply_skill_layout(); await w(0.4)
	await shot("43_layout_pc")
	Game.skill_layout = Game.default_skill_layout(); z.hud.apply_skill_layout()
	z.hud._open("skills"); await w(0.6)
	await shot("44_skills_window")
	z.hud.close_window(); await w(0.3)
	z.hud._open("talents"); await w(0.6)
	var tw = z.hud.window
	tw.search.text = "огн"; tw.find_next(); await w(0.5)
	await shot("45_talents_search")
	tw.set_filter("key"); await w(0.4)
	await shot("46_talents_keystones")
	z.hud.close_window(); await w(0.3)
	DB.set_zone_flag(z.data, "starter", "boss_troll_killed")
	Game.travel("dungeon"); await w(3.0)
	var d = get_tree().current_scene
	d.player.god_mode = true
	d.cam_rig.yaw = 180.0; d.cam_rig.distance = 8.0
	d.player.teleport(Vector3(0, 0.1, 8)); await w(1.2)
	await shot("47_crypt_hall")
	d.player.teleport(Vector3(0, 0.1, 50)); await w(1.0)
	await shot("48_lever_hall")
	var b = d.builder.boss_enemy()
	d.player.teleport(Vector3(0, 0.1, 96)); await w(4.0)
	await shot("49_warden_fight")
	if b and b.brain:
		var t0 := Time.get_ticks_msec()
		while b.brain.cast_name == "" and Time.get_ticks_msec() - t0 < 12000: await w(0.2)
		await w(0.8)
		await shot("50_warden_telegraph")


func _v041_shots(z) -> void:
	out = "/workspace/rpg-shots/v041"
	var p: Player = z.player
	p.god_mode = true
	z.data["level"] = 14; z.data["class_level"] = 3; p.recalc(true)
	z.hud._open("talents"); await w(0.6)
	var tw = z.hud.window
	tw.zoom = 0.5; tw.center_on_start(); await w(0.4)
	await shot("t1_talents_default")
	tw.zoom = 1.0; tw.center_on_start(); await w(0.4)
	await shot("t2_talents_zoom1")
	tw.zoom = tw.ZOOM_MAX; tw.center_on_start(); await w(0.4)
	await shot("t3_talents_zoom_max")
	tw.zoom = 0.2; tw.center_on_start(); await w(0.4)
	await shot("t4_talents_far")
	z.hud.close_window(); await w(0.3)
	z.hud._open("pause"); await w(0.4)
	z.hud.window.open_settings(); await w(0.5)
	Game.apply_preset(4); await w(0.2)
	var sp = z.hud.window.find_child("SettingsPanel", true, false)
	if sp: sp._refresh_all()
	await w(0.3)
	await shot("t5_settings_ultra")
	Game.apply_preset(3)
	z.hud.close_window(); await w(0.3)
	get_tree().paused = false
	DB.set_zone_flag(z.data, "starter", "boss_troll_killed")
	Game.travel("dungeon"); await w(3.0)
	var d = get_tree().current_scene
	d.player.god_mode = true
	d.cam_rig.yaw = 180.0; d.cam_rig.distance = 9.0
	d.player.teleport(Vector3(0, 0.1, 10)); await w(1.2)
	await shot("t6_crypt_doorway_guides")
	d.player.teleport(Vector3(0, 0.1, 58)); await w(1.0)
	await shot("t7_lever_hall_gate")
	for e in d.enemies.duplicate():
		if is_instance_valid(e) and e.kind != "warden": e.queue_free(); d.enemies.erase(e)
	DB.set_zone_flag(d.data, "dungeon", "lever_solved")
	d.builder._open_gate(true)
	d.player.teleport(Vector3(0, 0.1, 100)); await w(1.0)
	var b = d.builder.boss_enemy()
	var g := 0
	while b and is_instance_valid(b) and b.alive and g < 60:
		if b.brain: b.brain.invulnerable = false
		b.take_damage(b.max_hp * 2.0, false); await w(0.05); g += 1
	await w(1.6)
	d.player.teleport(Vector3(0, 0.1, 104)); d.cam_rig.yaw = 0.0; await w(1.0)
	await shot("t8_return_portal")

## v0.5: окна предметов (герой, лавка, сундук), подсказка комплекта, массовый выбор
func _v050_ui_shots(z) -> void:
	out = "/workspace/rpg-shots/v050"; DirAccess.make_dir_recursive_absolute(out)
	var p: Player = z.player
	p.god_mode = true
	var d: Dictionary = z.data
	d["level"] = 16; d["gold"] = 4820; d["dust"] = 37; p.recalc(true)
	d["inventory"].clear()
	d["equipped"].clear()
	d["equipped"].append(Items.roll(15, "warrior", 0.3, false, 0))
	for i in [0, 1, 2, 3]:
		var it := Items.roll_set(15, "warrior", "north", i)
		var cur = Items.get_equipped(d, int(it.slot))
		if cur: d["equipped"].erase(cur)
		d["equipped"].append(it)
	d["equipped"].append(Items.roll(14, "warrior", 0.4, false, 3))
	d["equipped"].append(Items.roll(15, "warrior", 0.4, false, 6))
	d["inventory"].append(Items.roll_set(15, "warrior", "north", 4))
	d["inventory"].append(Items.roll_set(15, "", "blood", 2))
	d["inventory"].append(Items.roll(22, "warrior", 0.5, false, 1))
	d["inventory"].append(Items.roll(9, "archer", 0.3, false, 0))
	d["inventory"].append(Items.roll(12, "mage", 0.3, false, 2))
	for i in 17: d["inventory"].append(Items.roll(randi_range(8, 17), "warrior", 0.15))
	p.recalc(true)
	z.hud._open("hero"); await w(0.6)
	var win = z.hud.window
	win._select(d["inventory"][0], false); await w(0.3)
	await shot("u1_hero_set_tooltip")
	win._select(d["inventory"][2], false); await w(0.3)
	await shot("u2_hero_level_lock")
	win.inv_grid.select_mode = true
	win.inv_grid.set_selection(Items.select_junk(d, win.inv_grid.view)); win.refresh(); await w(0.3)
	await shot("u3_mass_select_junk")
	z.hud.close_window(); await w(0.3)
	z.hud._open("shop"); await w(0.6)
	win = z.hud.window
	win.inv_grid.set_selection(Items.select_by_rarity(win.inv_grid.view, 1)); win.refresh()
	win._set_focus(d["shop"]["stock"][1], "stock"); await w(0.3)
	await shot("u4_shop_grid")
	z.hud.close_window(); await w(0.3)
	for i in 60: d["stash"].append(Items.roll(randi_range(5, 18), "warrior", 0.2))
	z.hud._open("stash"); await w(0.6)
	win = z.hud.window
	win.side_grid.set_selection([str(d["stash"][0].uid), str(d["stash"][1].uid), str(d["stash"][2].uid)]); win.refresh(); await w(0.3)
	await shot("u5_stash_100")
	z.hud.close_window(); await w(0.3)
	get_tree().paused = false
	p.teleport(z.stash_point + Vector3(1.5, 0.1, 2.5)); z.cam_rig.yaw = 200.0; await w(1.0)
	await shot("u6_camp_stash_chest")
	get_tree().quit()

func _v050_world_shots(z) -> void:
	out = "/workspace/rpg-shots/v050"; DirAccess.make_dir_recursive_absolute(out)
	Game.current["level"] = 22
	Game.travel("global", "world"); await w(5.0)
	z = get_tree().current_scene
	var p: Player = z.player
	p.god_mode = true; p.recalc(true)
	var wb: WorldBuilder = z.builder
	z.cam_rig.yaw = 160.0; z.cam_rig.distance = 15.0; await w(2.0)
	await shot("w1_cross_town")
	for t in WorldData.TOWNS:
		if t.id == "cross": continue
		wb.discover_waypoint(t.id); wb.travel_to(t.id); await w(3.0)
		z.cam_rig.yaw = 200.0
		await w(1.0)
		await shot("w2_town_%s" % t.id)
	var done_b := {}
	for s in wb.spawners:
		var key := "%d_%s" % [s.biome, s.rank]
		if done_b.has(key) or (s.rank == "normal" and s.biome % 2 == 1): continue
		done_b[key] = true
		var q: Vector3 = s.global_position + Vector3(9, 0, 9)
		q.y = WorldData.height(q.x, q.z) + 0.4
		p.teleport(q); z.cam_rig.yaw = 45.0; z.cam_rig.distance = 13.0
		await w(3.0)
		await shot("w3_%s_%s" % [WorldData.BIOMES[s.biome].id, s.rank])
	z.hud._open("map"); await w(0.8)
	await shot("w6_world_map")
	z.hud.close_window(); await w(0.3)
	get_tree().paused = false
	get_tree().quit()


func _v050_bal_shots(z) -> void:
	out = "/workspace/rpg-shots/v050"; DirAccess.make_dir_recursive_absolute(out)
	var p: Player = z.player
	p.god_mode = true
	z.data["level"] = 4; p.recalc(true)
	var boss = null
	for e in z.enemies: if e.def.boss: boss = e
	p.teleport(boss.global_position + Vector3(0, 0.1, -7)); z.cam_rig.yaw = 0.0
	await w(1.5)
	for i in 6:
		if is_instance_valid(boss) and boss.alive:
			p.hit(boss, 1.0, false, false, {"elem": ["phys", "fire", "ice", "poison"][i % 4]})
		await w(0.12)
	await shot("b1_troll_lvl4_resists")
	z.hud._open("pause"); await w(0.5)
	z.hud.window.open_credits(); await w(0.6)
	await shot("b2_credits")
	z.hud.close_window(); await w(0.3)
	get_tree().paused = false
	get_tree().quit()
