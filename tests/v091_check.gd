extends Node
## Быстрая проверка v0.9.1 (по пунктам списка ошибок; снимки — нужен xvfb):
## xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1920x1080 res://tests/v091_check.tscn
var is_runner := false
var out := "/workspace/rpg-shots/v091"
var errors := 0
var checks := 0

func check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok: errors += 1
	print("  ", "OK  " if ok else "FAIL", " ", msg)

## ожидание по реальному времени и не меньше 3 кадров (после снимка кадр длинный — таймер срабатывал за 1 кадр)
func w(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	var n := 0
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0) or n < 3:
		await get_tree().process_frame
		n += 1

func shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, n])
	print("  shot %s/%s.png" % [out, n])

func key(z, k: int) -> void:
	var ev := InputEventKey.new(); ev.keycode = k; ev.physical_keycode = k; ev.pressed = true
	z.hud._input(ev)

func _ready() -> void:
	if not is_runner:
		var r = load("res://tests/v091_check.gd").new(); r.is_runner = true
		get_tree().root.add_child.call_deferred(r); return
	DirAccess.make_dir_recursive_absolute(out)
	get_tree().create_timer(240.0, true, false, true).timeout.connect(func(): print("TIMEOUT"); get_tree().quit(2))
	for f in Game.list_characters(): Game.delete_character(f["id"])
	var rng := RandomNumberGenerator.new(); rng.seed = 11
	var c := DB.new_character("Проверка", "warrior", CharAssets.random_look(1, rng))
	c["level"] = 20; c["class_level"] = 20; c["ascendancy"] = "herald"; c["gold"] = 50000
	for t in ["sp_banner", "sp_crush_roar", "w_spin"]: DB.learn_skill(c, t)
	for i in 3: DB.set_loadout_slot(c, i, ["sp_banner", "sp_crush_roar", "w_spin"][i])
	var req: Array = DB.ZONES["dungeon"].get("requires", [])
	if req.size() == 2: DB.set_zone_flag(c, req[0], req[1])
	Game.save_character(c)
	Game.play(c); await w(2.5)
	var z = get_tree().current_scene
	check(z != null and z.player != null, "игра стартует")
	for k in z.hud.HINTS: z.data["tutorial"][k] = true
	z.hud._hint_done()
	var p = z.player
	var pu = z.party_ui
	# ---- 1. Группа ----
	var gk := InputEventKey.new(); gk.keycode = KEY_G; gk.physical_keycode = KEY_G; gk.pressed = true
	pu._unhandled_input(gk); await w(0.3)
	check(pu.win.visible and pu.tab == "party", "1. G открывает вкладку «Группа» (не «Подземелья»): %s" % pu.tab)
	pu.close(); await w(0.1)
	pu.btn.pressed.emit(); await w(0.3)
	check(pu.win.visible and pu.tab == "party", "1. кнопка «Группа» открывает вкладку «Группа»")
	await shot("01_party_tab")
	pu.close()
	# ---- 3. рамки/чат скрыты в окнах, «Подземелья» не налезает на «Умения» ----
	check(pu.ui_root.visible, "3. на главном экране рамки группы видны")
	for wn in ["hero", "skills", "talents"]:
		z.hud._open(wn); await w(0.25)
		check(not pu.ui_root.is_visible_in_tree() and not pu.dbtn.is_visible_in_tree(), "3. окно «%s»: рамки группы, список онлайн и кнопка «Подземелья» скрыты" % wn)
		if wn == "skills": await shot("03_skills_no_overlap")
		z.hud.close_window(); await w(0.2)
	check(pu.ui_root.visible, "3. после закрытия окна рамки снова видны")
	# ---- 9. захват цели ----
	var e = null
	for x in z.enemies:
		if is_instance_valid(x) and x.alive and not x.def.boss: e = x; break
	p.teleport(e.global_position + Vector3(3.0, 0, 0)); await w(0.3)
	var tc = z.target_ctl
	e.max_hp = 1e7; e.hp = 1e7
	tc.select(e); await w(0.1)
	var other = null
	for x in z.enemies:
		if is_instance_valid(x) and x.alive and x != e: other = x; break
	p.attack_held = true; await w(0.6); p.attack_held = false
	p.move_input = Vector2(1, 0); await w(0.4); p.move_input = Vector2.ZERO
	check(tc.target == e, "9. атака и движение не сбрасывают и не меняют захваченную цель")
	check(p.find_target(30.0) == e, "9. умения и автонаведение бьют захваченную цель")
	if other: p.teleport(other.global_position + Vector3(1.0, 0, 0)); await w(0.2)
	check(p.find_target(30.0) == e or not is_instance_valid(e), "9. рядом другой враг — цель та же")
	p.teleport(e.global_position + Vector3(45.0, 0, 0)); await w(0.5)
	check(not tc.has_target(), "9. дальше 40 м — захват снят")
	# ---- 4. подсказки баффов ----
	p.teleport(e.global_position + Vector3(3.0, 0, 0)); await w(0.3)
	p.mp = 9999.0
	var lo: Array = c["loadout"]
	p.try_use(lo.find("sp_banner") + 1); await w(0.3)
	p.try_use(lo.find("sp_crush_roar") + 1); await w(0.3)
	p.try_use(lo.find("sp_banner") + 1); await w(0.2)
	var ic = null
	for x in z.hud.self_buffs.get_children():
		if x.visible and x.has_meta("b"): ic = x; break
	check(ic != null and ic.mouse_filter == Control.MOUSE_FILTER_STOP, "4. значок баффа на себе принимает наведение/нажатие")
	if ic:
		z.hud.show_buff_tip(ic); await w(0.2)
		var tt: String = z.hud.buff_tip_text.text
		check(z.hud.buff_tip.visible and "Боевое знамя" in tt and "Осталось" in tt and "урон" in tt, "4. подсказка: название, эффект, время — %s" % tt.replace("\n", " | ").left(160))
		await shot("04_buff_tooltip_self")
		# долгое нажатие на телефоне
		z.hud.show_buff_tip(null)
		var r: Rect2 = ic.get_global_rect()
		z.hud._touch_down(5, r.get_center())
		await w(0.5)
		check(z.hud.buff_tip.visible, "4. долгое нажатие показывает подсказку")
		z.hud._touch_up(5); await w(0.1)
		check(not z.hud.buff_tip.visible, "4. отпустили — подсказка скрыта")
	tc.select(e); await w(0.3)
	var eic = null
	for x in z.hud.tf_buffs.get_children():
		if x.visible and x.has_meta("b"): eic = x; break
	check(eic != null, "4. дебафф на враге в рамке цели")
	if eic:
		z.hud.show_buff_tip(eic); await w(0.2)
		check("Ослабление" in z.hud.buff_tip_text.text and "дебафф" in z.hud.buff_tip_text.text, "4. подсказка дебаффа врага: %s" % z.hud.buff_tip_text.text.replace("\n", " | ").left(140))
		await shot("04_buff_tooltip_enemy")
		z.hud.show_buff_tip(null)
	var pb: Array = z.hud.party_buffs({"bf": [["sp_banner", "aura", "ff6633", 7.5, 10.0, true, "Боевое знамя", "+15% к урону", 2, "Друг"]]})
	check(pb.size() == 1 and int(pb[0].st) == 2 and "Друг" in Support.describe_buff(pb[0]) and "Наложений: 2" in Support.describe_buff(pb[0]), "4. баффы союзника (с сервера): эффект, наложения и источник")
	# ---- 5. ремесло ----
	z.data["mats"] = {"aether_dust": 20, "ash_ember": 10}
	var inv0: int = (z.data["inventory"] as Array).size()
	z.hud._open("hero"); await w(0.3)
	var cb = z.hud.window.find_child("CraftBtn", true, false)
	check(cb != null, "5. в окне героя есть кнопка «Ремесло»")
	if cb: cb.pressed.emit()
	await w(0.4)
	var cw = z.hud.window
	check(cw != null and cw.get_script() == load("res://scripts/ui/craft_ui.gd"), "5. окно «Ремесло» открылось")
	if cw:
		var sid: String = Items.craftable_sets(z.data)[0]
		cw.select_set(sid); cw.select_piece(1); await w(0.2)
		var cost := Items.craft_cost(sid, int(z.data["level"]))
		await shot("05_craft_window")
		var mk = cw.find_child("Make", true, false)
		mk.pressed.emit(); await w(0.3)
		var inv: Array = z.data["inventory"]
		var it: Dictionary = inv[-1] if inv.size() > inv0 else {}
		check(inv.size() == inv0 + 1 and it.get("crafted", false) and str(it.get("set", "")) == sid, "5. создана часть комплекта «%s»: %s" % [sid, str(it.get("name", "—"))])
		check(int(z.data["mats"][cost.mat]) == (20 if cost.mat == "aether_dust" else 10) - int(cost.n), "5. списано %s ×%d и %d золота" % [cost.mat, int(cost.n), int(cost.gold)])
		await shot("05_craft_done")
		z.hud.close_window(); await w(0.2)
	var raid_ok := Items.craft_block({"level": 30, "class": "warrior", "mats": {}, "gold": 99999, "inventory": []}, "voragos_raid" if Items.SETS.has("voragos_raid") else Items.craftable_sets({"level": 30, "class": "warrior"})[-1], 0)
	check(raid_ok.begins_with("Нужно"), "5. без материалов — отказ: %s" % raid_ok)
	check(Items.craft_cost(Items.craftable_sets(z.data)[0], 40).n > Items.craft_cost(Items.craftable_sets(z.data)[0], 8).n, "5. цена растёт с уровнем")
	# ---- 11. возврат талантов и умений ----
	var cc: Dictionary = z.data
	DB.reset_talents(cc)
	var start := DB.start_node("warrior")
	var n1: int = DB.tree_nodes[start]["links"][0]
	var n2 := -1
	for l in DB.tree_nodes[n1]["links"]:
		if int(l) != start and DB.tree_nodes[int(l)]["type"] != "start" and not DB.tree_nodes[int(l)]["links"].has(start): n2 = int(l); break
	var free0 := DB.free_points(cc)
	check(DB.char_op(cc, "t_alloc", str(n1)) == "" and DB.char_op(cc, "t_alloc", str(n1)) == "" and DB.char_op(cc, "t_alloc", str(n2)) == "", "11. изучено: «%s» ×2 и «%s»" % [DB.tree_nodes[n1].name, DB.tree_nodes[n2].name])
	var why := DB.char_op(cc, "t_refund_node", str(n1))
	check(why != "" and DB.tree_nodes[n2].name in why, "11. узел с зависимыми не снимается, причина называет их: %s" % why)
	check(DB.char_op(cc, "t_refund", str(n1)) == "" and DB.rank(cc, n1) == 1, "11. −1 ранг у узла с зависимыми (связь сохраняется)")
	check(DB.char_op(cc, "t_refund_node", str(n2)) == "" and not DB.has_talent(cc, n2), "11. лист снимается целиком")
	check(DB.char_op(cc, "t_refund_node", str(n1)) == "" and DB.free_points(cc) == free0, "11. все очки вернулись (%d)" % DB.free_points(cc))
	check(DB.char_op(cc, "t_refund", "99999") != "" and DB.char_op(cc, "t_alloc", "-5") != "" and DB.char_op(cc, "bogus", "1") != "", "11. сервер отклоняет неверные операции")
	DB.char_op(cc, "t_alloc", str(n1))
	check(DB.char_op(cc, "t_reset", "") == "" and DB.spent_points(cc) == 0 and cc["ascendancy"] == "" and int(cc["skill_ranks"].get("sp_banner", 0)) == 0 and not (cc["loadout"] as Array).has("sp_banner"),
		"11. полный сброс бесплатный: очки возвращены, путь снят, умения пути разучены и сняты с панели")
	# UI: окно талантов — кнопки
	cc["ascendancy"] = ""
	DB.allocate(cc, n1); DB.allocate(cc, n1)
	z.hud._open("talents"); await w(0.4)
	var tw = z.hud.window
	tw.selected = n1; tw._refund(); await w(0.1)
	check(DB.rank(cc, n1) == 1, "11. кнопка «Вернуть очко» в окне талантов работает")
	tw.selected = n1; tw._refund_node(); await w(0.1)
	check(not DB.has_talent(cc, n1), "11. кнопка «Вернуть узел» работает")
	await shot("11_talent_tree")
	z.hud.close_window(); await w(0.2)
	# умения
	cc["skill_ranks"] = {}; DB.learn_skill(cc, "w_spin"); DB.learn_skill(cc, "w_spin"); DB.set_loadout_slot(cc, 0, "w_spin")
	var sp0 := DB.skill_points_free(cc)
	z.hud._open("skills"); await w(0.4)
	var sw = z.hud.window
	sw._refund_id("w_spin"); await w(0.1)
	check(DB.skill_rank(cc, "w_spin") == 1 and DB.skill_points_free(cc) == sp0 + 1, "11. «−» в меню умений возвращает ранг и очко")
	sw._refund_id("w_spin"); await w(0.1)
	check(DB.skill_rank(cc, "w_spin") == 0 and not (cc["loadout"] as Array).has("w_spin"), "11. последний ранг: умение разучено и снято с панели")
	DB.learn_skill(cc, "w_spin"); DB.learn_skill(cc, "w_dash")
	var rb = sw.find_child("ResetSkills", true, false)
	if rb == null:
		for b in sw.find_children("*", "Button", true, false):
			if "Сбросить" in (b as Button).text: rb = b; break
	check(rb != null, "11. кнопка «Сбросить все» в меню умений")
	if rb:
		rb.pressed.emit(); await w(0.1); rb.pressed.emit(); await w(0.2)
		check(DB.skill_points_spent(cc) == 0, "11. «Сбросить все» (с подтверждением) возвращает все очки умений")
	await shot("11_skills_refund")
	z.hud.close_window(); await w(0.2)
	# ---- 8. тень колонны ⊆ зона укрытия ----
	var bad := 0; var tot := 0
	var WB = load("res://scripts/game/warden_brain.gd")
	for dist in [5.0, 8.0, 11.0, 14.0]:
		var wg: Dictionary = WB.shadow_wedge(dist, 1.4)
		var half := deg_to_rad(float(wg.angle)) / 2.0
		for i in 9:
			for j in 6:
				var ang := -half + half * 2.0 * i / 8.0
				var rr: float = lerpf(float(wg.inner) * WB.VOID_R, WB.VOID_R, j / 5.0)
				var pt := Vector2(cos(ang), sin(ang)) * rr
				var pl := Vector2(dist, 0)
				var ab := pt
				var t := clampf(pl.dot(ab) / maxf(0.0001, ab.length_squared()), 0, 1)
				var covered: bool = (ab * t).distance_to(pl) <= 1.4 + WB.COVER_PAD and t > 0.05 and t < WB.COVER_TT
				tot += 1
				if not covered: bad += 1
	check(bad == 0, "8. подсвеченная тень за колонной целиком внутри зоны укрытия (%d точек, вне — %d)" % [tot, bad])
	# ---- 10. цель «выйти в мир» → портал ----
	DB.set_zone_flag(z.data, "dungeon", "boss_warden_killed")
	for x in z.enemies:
		if is_instance_valid(x) and x.alive and x.def.boss: x.alive = false
	await w(0.6)
	var ot: Vector3 = z.hud.objective_target()
	check(ot.distance_to(z.portal_point) < 0.5, "10. цель указывает на портал в мир, не на вход в Склеп")
	check(z.hud.minimap.goal_point.distance_to(z.portal_point) < 0.5, "10. мини-карта: цель — портал")
	await shot("10_portal_goal")
	# ---- 2. выход из подземелья — туда, откуда вошли ----
	var here: Vector3 = p.global_position + Vector3(6, 0, -4)
	p.teleport(here); await w(0.3)
	z.save()
	Game.travel("dungeon"); await w(3.0)
	var dz = get_tree().current_scene
	check(dz != null and str(Game.current["zone"]) == "dungeon", "2. вошли в Склеп")
	Game.travel_back("starter"); await w(3.0)
	var bz = get_tree().current_scene
	var d2: float = U.flat_dist(bz.player.global_position, here) if bz and bz.player else 999.0
	check(d2 < 2.0, "2. вышли туда же, где вошли (расхождение %.1f м)" % d2)
	print("=== V091 CHECK: %s (%d errors, %d checks) ===" % ["PASS" if errors == 0 else "FAIL", errors, checks])
	get_tree().quit(1 if errors else 0)
