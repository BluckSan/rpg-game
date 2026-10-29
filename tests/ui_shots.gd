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
	var portals := false
	var menu := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--pref="): pref = a.substr(7)
		if a == "--vfx": vfx = true
		if a == "--portals": portals = true
		if a == "--menu": menu = true
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
	if portals: c["zone"] = "global"; c["has_pos"] = false
	Game.play(c); await w(6.0 if portals else 3.0)
	var z = get_tree().current_scene
	z.player.god_mode = true
	if portals:   # v0.9.3: порталы подземелий на карте мира + окно группы + проверка готовности
		var pui = null
		for n in get_tree().root.find_children("*", "PartyUI", true, false): pui = n
		pui.open_dungeons(); await w(1.2); await shot("04_map_portal")
		z.hud.close_window(); await w(0.4)
		pui.open_tab("party"); await w(0.8); await shot("05_party_window"); pui.close(); await w(0.3)
		pui._on_rc_ask("ash", "Лидер", 25.0)
		pui._on_rc_state("ash", {"Лидер": true, "Арина": false, "Борис": true}, "wait")
		await w(0.8); await shot("06_ready_check")
		get_tree().quit(); return
	if vfx: await _vfx(z); get_tree().quit(); return
	if menu: await _menu(z); get_tree().quit(); return
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

var fails := 0
func ck(ok: bool, t: String) -> void:
	print(("  OK  " if ok else "  FAIL ") + t)
	if not ok: fails += 1

## v0.9.4: одна кнопка «Меню» вместо верхнего ряда и кнопок «Группа»/«Подземелья»
func _menu(z) -> void:
	var h = z.hud
	if h.hint_panel: h.hint_panel.visible = false
	await w(0.5)
	var pui = z.party_ui
	ck(not pui.btn.is_visible_in_tree() and not pui.dbtn.is_visible_in_tree(), "кнопок «Группа»/«Подземелья» на экране нет")
	var vis_top := 0
	for b in h.top_buttons: if b.is_visible_in_tree(): vis_top += 1
	ck(vis_top == 1 and h.menu_btn.is_visible_in_tree(), "верхний ряд заменён одной кнопкой «Меню» (видимых: %d)" % vis_top)
	await shot("01_hud_menu_closed")
	var c: Vector2 = h.menu_btn.get_global_rect().get_center()
	h._touch_down(-1 if Game.desktop else 0, c); h._touch_up(-1 if Game.desktop else 0)
	h.menu_btn.pressed.emit()
	await w(0.07); await shot("02_menu_opening")
	ck(h.menu_open and h.menu_panel.visible, "меню открылось по кнопке")
	await w(0.4); await shot("03_menu_open")
	ck(h.menu_panel.scale.is_equal_approx(Vector2.ONE) and is_equal_approx(h.menu_panel.modulate.a, 1.0), "анимация открытия завершилась")
	var names := []
	for k in h.menu_items: names.append(k)
	ck(names.size() >= 9 and "party" in names and "dungeons" in names and "market" in names, "в меню все окна: %s" % str(names))
	if Game.desktop: ck(h.menu_items["skills"].text.contains("[") and h.menu_items["hero"].text.contains("["), "ПК: подсказки клавиш (%s)" % h.menu_items["skills"].text)
	# клик мимо — закрыть
	var out_pt: Vector2 = h._screen() * Vector2(0.4, 0.6)
	h._touch_down(-1 if Game.desktop else 0, out_pt); h._touch_up(-1 if Game.desktop else 0)
	ck(not h.menu_open, "клик мимо меню закрывает его")
	ck(not z.player.attack_held, "клик мимо меню не превращается в атаку")
	await w(0.5)
	ck(not h.menu_panel.visible, "анимация закрытия скрыла панель (scale=%s a=%.2f ts=%.2f)" % [h.menu_panel.scale, h.menu_panel.modulate.a, Engine.time_scale])
	# Esc закрывает
	h.open_menu(); await w(0.3)
	var ev := InputEventKey.new(); ev.keycode = KEY_ESCAPE; ev.pressed = true
	h._hotkey_ev(ev)
	ck(not h.menu_open and h.window == null, "Esc закрывает меню (а не открывает паузу)")
	await w(0.3)
	# пункт меню открывает окно
	h.open_menu(); await w(0.3)
	h.menu_items["skills"].pressed.emit(); await w(0.6)
	ck(h.window != null and String(h.window.name) == "Window_skills" and not h.menu_open, "пункт «Умения» открывает окно и закрывает меню")
	await shot("04_menu_skills_window")
	h.close_window(); await w(0.3)
	h.open_menu(); await w(0.3)
	h.menu_items["dungeons"].pressed.emit(); await w(1.0)
	ck(h.window != null if z.builder is WorldBuilder else not h.menu_open, "пункт «Подземелья»: карта с порталами (в мире) / подсказка о порталах (вне мира)")
	await shot("05_menu_dungeons")
	h.close_window(); await w(0.3)
	h.open_menu(); await w(0.3)
	h.menu_items["party"].pressed.emit(); await w(0.8)
	ck(pui.win.visible, "пункт «Группа» открывает окно группы")
	await shot("06_menu_party"); pui.close(); await w(0.3)
	if Game.desktop:
		h._hotkey(KEY_K if false else Controls_key("hero")); await w(0.5)
		ck(h.window != null and String(h.window.name) == "Window_hero", "горячая клавиша героя работает напрямую")
		h.close_window(); await w(0.3)
	print("=== MENU RESULT: %s (%d fails) ===" % ["PASS" if fails == 0 else "FAIL", fails])

func Controls_key(act: String) -> int:
	for k in range(KEY_A, KEY_Z + 1):
		var ev := InputEventKey.new(); ev.keycode = k; ev.physical_keycode = k; ev.pressed = true
		if Controls.action_of(ev) == act: return k
	return KEY_C
