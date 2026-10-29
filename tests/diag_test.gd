extends Node
var is_runner := false
func w(s: float) -> void: await get_tree().create_timer(s).timeout
func _ready() -> void:
	if not is_runner:
		var r = load("res://tests/diag_test.gd").new(); r.is_runner = true
		get_tree().root.add_child.call_deferred(r); return
	process_mode = Node.PROCESS_MODE_ALWAYS
	for cls in ["warrior", "archer"]:
		for f in Game.list_characters(): Game.delete_character(f["id"])
		var c := DB.new_character("Диаг", cls, CharAssets.random_look(1, RandomNumberGenerator.new()))
		c["level"] = 18; Game.save_character(c)
		Game.play(c); await w(3.0)
		var z = get_tree().current_scene; var p = z.player; var h = z.hud
		p.god_mode = true
		if cls == "warrior":
			if h.hint_panel: h.hint_panel.visible = false
			var pt: Vector2 = h._screen() * Vector2(0.5, 0.45)
			print("DIAG top=", h._over_top_button(pt), " bars=", h.bars.over(pt) if h.bars else null, " buff=", h.buff_icon_at(pt))
			for i in h.skill_btns.size(): if h.skill_btns[i].hit(pt): print("DIAG skill_btn hit ", i, " vis=", h.skill_btns[i].visible)
			for b in [h.jump_btn, h.roll_btn, h.target_btn, h.potion_btn]: if b.hit(pt): print("DIAG btn hit ", b.name, " vis=", b.visible)
			for b in h.top_buttons + h.blockers: if b.is_visible_in_tree() and b.get_global_rect().has_point(pt): print("DIAG blocker ", b.name, " ", b.get_path())
			print("DIAG desktop=", Game.desktop, " window=", h.window, " picked=", z.target_ctl.pick(pt) if z.target_ctl else "none")
			h._touch_down(-1, pt); print("DIAG attack_held=", p.attack_held); h._touch_up(-1)
		DB.reset_skills(p.data); p.data["skill_bonus"] = 50; p.data["class_level"] = 3
		for s in DB.CLASSES[cls].skills: DB.learn_skill(p.data, s.id)
		p.recalc(true)
		var dummy := Enemy.spawn(z, "slime", 1, p.global_position + p.forward() * 3.0, z.fx_root)
		dummy.max_hp = 999999; dummy.hp = 999999
		await w(0.2)
		var prev := ""
		for s in DB.CLASSES[cls].skills:
			if s.get("passive", false): continue
			DB.set_loadout_slot(p.data, 0, s.id); p.recalc(true)
			p.cooldowns[1] = 0; p.mp = p.stats.max_mp
			var cost: float = float(s.mana) * (1.0 + float(p.fx.get("mana_cost", 0.0)) / 100.0)
			var info := "dead=%s cd=%s mp=%.0f/%.0f cost=%.0f lock='%s' skill=%s" % [p.dead, p.cooldowns[1], p.mp, p.stats.max_mp, cost, p.lock_reason(1), p.get_skill(1).id if p.get_skill(1) else "nil"]
			var ok: bool = p.try_use(1)
			print("DIAG ", cls, " after ", prev, " -> ", s.id, " ok=", ok, " ", info, " mp_after=", p.mp)
			prev = s.id
			await w(1.3)
		dummy.queue_free()
	get_tree().quit()
