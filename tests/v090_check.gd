extends Node
## Быстрая проверка v0.9.0 (нужен дисплей / xvfb для снимков):
## xvfb-run godot --path . --rendering-driver opengl3 --resolution 1920x1080 res://tests/v090_check.tscn
## Игра стартует, выбор цели (цикл/рамка/сброс), умения поддержки (аура, ослабление, щит), вкладка «Управление».
var is_runner := false
var out := "/workspace/rpg-shots/v090"
var errors := 0
var checks := 0

func check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok: errors += 1
	print("  ", "OK  " if ok else "FAIL", " ", msg)

func w(sec: float) -> void: await get_tree().create_timer(sec).timeout

func shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, n])
	print("  shot %s/%s.png" % [out, n])

func _ready() -> void:
	if not is_runner:
		var r = load("res://tests/v090_check.gd").new(); r.is_runner = true
		get_tree().root.add_child.call_deferred(r); return
	DirAccess.make_dir_recursive_absolute(out)
	get_tree().create_timer(120.0, true, false, true).timeout.connect(func(): print("TIMEOUT"); get_tree().quit(2))
	for f in Game.list_characters(): Game.delete_character(f["id"])
	var rng := RandomNumberGenerator.new(); rng.seed = 9
	var c := DB.new_character("Ярослава", "warrior", CharAssets.random_look(1, rng))
	c["level"] = 20; c["class_level"] = 20; c["ascendancy"] = "herald"
	DB.auto_build_skills(c, ["sp_banner", "sp_crush_roar", "sp_bulwark", "sp_taunt"])
	for t in ["sp_banner", "sp_crush_roar", "sp_bulwark", "sp_taunt"]:
		if not c["loadout"].has(t): DB.learn_skill(c, t)
	for i in 4: DB.set_loadout_slot(c, i, ["sp_banner", "sp_crush_roar", "sp_bulwark", "sp_taunt"][i])
	Game.save_character(c)
	Game.play(c); await w(2.5)
	var z = get_tree().current_scene
	check(z != null and z.player != null and z.hud != null, "игра стартует: зона, игрок и HUD созданы")
	for k in z.hud.HINTS: z.data["tutorial"][k] = true
	z.hud._hint_done()
	var p = z.player
	# --- цель ---
	var e = null
	for x in z.enemies:
		if is_instance_valid(x) and x.alive: e = x; break
	check(e != null, "в зоне есть враг")
	p.teleport(e.global_position + Vector3(3.5, 0, 0)); await w(0.4)
	var tc = z.target_ctl
	tc.cycle(); await w(0.3)
	check(tc.has_target() and tc.kind == "enemy", "Tab/цикл выбирает врага (%s)" % tc.kind)
	check(p.find_target(30.0) == tc.target, "умения бьют выбранную цель")
	check(z.hud.target_frame.visible and z.hud.tf_name.text != "", "рамка цели: «%s»" % z.hud.tf_name.text)
	check(tc.ring != null and tc.ring.visible, "кольцо под целью")
	# --- поддержка ---
	p.mp = 9999.0
	var lo: Array = c["loadout"]
	var si := func(id: String) -> int: return lo.find(id) + 1
	check(p.try_use(si.call("sp_banner")), "«Боевое знамя» применено")
	await w(0.2)
	check(not p.buffs.is_empty(), "бафф знамени на себе: %s" % str(p.buffs.keys()))
	tc.select(e)
	check(p.try_use(si.call("sp_crush_roar")), "«Сокрушающий рёв» применён")
	await w(0.2)
	check(e.buffs.has("weaken"), "ослабление на враге: %s" % str(e.buffs.keys()))
	check(p.try_use(si.call("sp_taunt")), "«Вызов» применён")
	await w(0.2)
	check(p.try_use(si.call("sp_bulwark")), "«Заслон» (без союзника — на себя)")
	await w(0.2)
	check(p.shield_hp > 0.0, "щит на себе: %.0f" % p.shield_hp)
	await w(0.6)
	await shot("01_target_frame_support")
	tc.clear(); await w(0.2)
	check(not tc.has_target() and not z.hud.target_frame.visible, "Esc/сброс снимает цель")
	# --- окна ---
	z.hud._open("skills"); await w(0.6)
	await shot("02_skills_menu")
	z.hud.close_window(); await w(0.3)
	var sp := SettingsPanel.new()
	z.hud.root.add_child(sp); sp.setup(func(): pass, z); sp._show_tab("controls"); await w(0.5)
	check(sp.tab == "controls", "вкладка «Управление» открыта")
	await shot("03_controls_tab")
	print("=== V090 CHECK: %s (%d errors, %d checks) ===" % ["PASS" if errors == 0 else "FAIL", errors, checks])
	get_tree().quit(1 if errors else 0)
