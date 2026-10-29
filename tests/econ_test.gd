extends Node
## v0.9.3: улучшение +1…+10, комплекты против эпиков, возврат талантов (оффлайн)
var errors := 0
var checks := 0
func check(ok: bool, msg: String) -> void:
	checks += 1
	print(("  OK   " if ok else "  FAIL ") + msg)
	if not ok: errors += 1

func _ready() -> void:
	var c := DB.new_character("Эконом", "warrior", {})
	c["level"] = 30; c["gold"] = 10_000_000; c["mats"] = {"aether_dust": 100, "ash_ember": 0}
	var it := Items.roll(25, "warrior", 3.0, false, 0)
	c["inventory"].append(it)
	var uid := str(it.uid)
	var b0 := float(it.base)
	# +1..+5: без риска и материалов
	for n in range(1, 6):
		var cost := Items.upgrade_cost(it)
		check(int(cost.fail) == 0 and int(cost.n) == 0, "+%d: без риска и материалов, %d зол." % [n, int(cost.gold)])
		var r := Items.upgrade(c, uid, 0.0)
		check(r.ok and not r.failed and int(r.up) == n, "+%d выполнено" % n)
	# неудача на +6: вещь цела, уровень прежний, плата списана
	var g := int(c.gold); var d := int(c.mats.aether_dust)
	var inv_n := (c.inventory as Array).size()
	var cost6 := Items.upgrade_cost(it)
	check(int(cost6.fail) == 10 and str(cost6.mat) == "aether_dust" and int(cost6.n) == 1, "+6: риск 10%, нужна 1 пыль эфира")
	var rf := Items.upgrade(c, uid, 5.0)
	check(rf.ok and rf.failed and int(rf.up) == 5, "неудача: уровень остался +5")
	check((c.inventory as Array).size() == inv_n and Items.find_uid(c.inventory, uid) != null, "неудача: предмет не уничтожен")
	check(int(c.gold) == g - int(cost6.gold) and int(c.mats.aether_dust) == d - 1, "неудача: списаны золото и материал")
	for n in range(6, 11):
		var r := Items.upgrade(c, uid, 99.9)
		check(r.ok and int(r.up) == n, "+%d выполнено (риск %d%%)" % [n, int(Items.UP_FAIL[n])])
	check(Items.upgrade_block(c, it).begins_with("Улучшено до предела"), "+10 — предел, дальше нельзя")
	check(not Items.upgrade(c, uid, 0.0).ok, "попытка +11 отклонена")
	check(abs(float(it.base) - round(b0 * 1.35)) <= 1.0 and str(it.name).ends_with("+10"), "база +35%% (%d → %d), имя «…+10»" % [b0, it.base])
	# нет материалов боссов — с +6 нельзя
	var s := Items.roll_set(30, "warrior", "r_ash", 0)
	c["inventory"].append(s)
	for n in 5: Items.upgrade(c, str(s.uid), 0.0)
	check(Items.upgrade_block(c, s).begins_with("Нужно: Пепельный"), "рейдовый комплект с +6 требует «Пепельный уголь»")
	c["gold"] = 0
	check(Items.upgrade_block(c, s).begins_with("Нужно") , "без золота — отказ")
	# комплект против эпика
	var e := Items.roll(30, "warrior", 3.0, false, 1)
	var sp := Items.roll_set(30, "warrior", "", 1)
	check(int(sp.rarity) == Items.SET_RARITY and str(sp.get("set", "")) != "", "предмет комплекта помечен комплектом")
	check((sp.mods as Array).size() >= 4, "комплект: 4+ характеристики (%d), эпик: %d" % [(sp.mods as Array).size(), (e.mods as Array).size()])
	var sid := str(sp.set)
	var pieces: Array = Items.SETS[sid].pieces
	var c2 := DB.new_character("Набор", "warrior", {})
	c2["equipped"] = []
	var bon := []
	for i in pieces.size():
		var p := Items.roll_set(30, "warrior", sid, i)
		c2["equipped"].append(p)
		bon.append(Items.set_bonuses(c2))
	check(Items.set_count(c2, sid) == pieces.size(), "надеты все %d части" % pieces.size())
	check((bon[0].mods as Array).is_empty(), "1 часть — бонусов нет")
	check((bon[1].mods as Array).size() > 0, "2 части — бонус 2")
	check((bon[3].mods as Array).size() > (bon[1].mods as Array).size(), "4 части — добавлен бонус 4")
	check(pieces.size() < 6 or not (bon[5].fx as Dictionary).is_empty(), "6 частей — особый эффект %s" % str(bon[mini(5, bon.size() - 1)].fx))
	# возврат талантов
	var c3 := DB.new_character("Таланты", "warrior", {})
	c3["level"] = 20
	var start := DB.start_node("warrior")
	var learned := []
	for step in 12:
		var done := false
		for id in DB.tree_nodes:
			if DB.has_talent(c3, id): continue
			if DB.allocate(c3, int(id)):
				learned.append(id); done = true; break
		if not done: break
	var fp := DB.free_points(c3)
	check(learned.size() > 0, "изучено талантов: %d" % learned.size())
	if learned.size() > 0:
		check(DB.refund_block(c3, start) != "", "стартовую точку вернуть нельзя")
		check(DB.refund(c3, learned[-1]), "последний талант возвращён")
		check(DB.free_points(c3) == fp + 1, "очко вернулось (%d → %d)" % [fp, DB.free_points(c3)])
		if learned.size() > 2: print("  узел-опора: ", DB.refund_block(c3, learned[0]))
		DB.reset_talents(c3)
		check((c3.talents as Array).size() == 1 and DB.free_points(c3) == fp + learned.size(), "полный сброс: все очки вернулись (%d)" % DB.free_points(c3))
	print("ECON %s (%d ошибок, %d проверок)" % ["OK" if errors == 0 else "FAIL", errors, checks])
	get_tree().quit(1 if errors else 0)
