extends Node
## v0.8.0: автотест баланса «герой против босса зоны» по боевым формулам (Combat.sim_fight).
##  A) ур. 25, снаряжение ур. 10 против босса Руин Эфира (ур. 31) — должен явно проигрывать;
##  B) ур. 30, снаряжение ур. 28–30 — должен побеждать.
## Таланты — жадно под этого босса (лучший урон × живучесть), путь превращения — как только доступен.
## Снаряжение — редкое (синее/жёлтое), 8 слотов. Аргументы: --verbose, --seed=N
var errors := 0
var checks := 0
var verbose := false
const BOSS := "boss_seraph"

func check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok: errors += 1
	print("  %s %s" % ["OK  " if ok else "FAIL", msg])

func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	verbose = args.has("verbose")
	var boss_lvl := int(WorldData.BIOMES[5].lv[1]) + 1
	print("=== BALANCE TEST: босс %s ур. %d ===" % [DB.ENEMIES[BOSS].name, boss_lvl])
	for cls in DB.CLASS_ORDER:
		var worst_a := 0.0; var worst_b := 1e9
		for s in 4:
			seed(int(args.get("seed", "777")) + s * 31 + cls.length())
			var a := make_char(cls, 25, 10, 10, boss_lvl)
			var ra := Combat.sim_fight(a, BOSS, boss_lvl, "normal")
			var b := make_char(cls, 30, 28, 30, boss_lvl)
			var rb := Combat.sim_fight(b, BOSS, boss_lvl, "normal")
			worst_a = maxf(worst_a, ra.ttd / ra.ttk)   # запас A (чем больше, тем хуже для теста)
			worst_b = minf(worst_b, rb.ttd / rb.ttk)
			if verbose or s == 0:
				report("A ур.25/вещи 10", a, ra)
				report("B ур.30/вещи 28-30", b, rb)
		check(worst_a < 0.5, "%s: ур. 25 в вещах ур. 10 — явное поражение (лучший запас жизни/убийства %.2f < 0.5)" % [cls, worst_a])
		check(worst_b > 1.25, "%s: ур. 30 в вещах ур. 28–30 — победа (худший запас %.2f > 1.25)" % [cls, worst_b])
	# одно и то же 30-го уровня: вещи ур. 10 против вещей ур. 28–30 — снаряжение решает
	for cls in DB.CLASS_ORDER:
		seed(99 + cls.length())
		var old_g := Combat.sim_fight(make_char(cls, 30, 10, 10, boss_lvl), BOSS, boss_lvl)
		var new_g := Combat.sim_fight(make_char(cls, 30, 28, 30, boss_lvl), BOSS, boss_lvl)
		check(new_g.dps > old_g.dps * 1.4 and old_g.ttd / old_g.ttk < new_g.ttd / new_g.ttk * 0.6,
			"%s ур. 30: вещи ур. 28–30 дают урона ×%.2f к вещам ур. 10 (запас %.2f против %.2f)" % [cls, new_g.dps / old_g.dps, new_g.ttd / new_g.ttk, old_g.ttd / old_g.ttk])
	# снаряжение: плоские характеристики растут с уровнем предмета; проценты на вещах не растут
	seed(5)
	var lo := 0.0; var hi := 0.0; var pct_ok := true
	for i in 200:
		var a := Items.roll(10, "warrior", 0.5, false, i % 8); var b := Items.roll(30, "warrior", 0.5, false, i % 8)
		lo += item_power(a); hi += item_power(b)
		for it in [a, b]: for m in it.mods: if str(m[0]).ends_with("%") or m[0] in ["crit", "resred"]: pct_ok = false
	check(hi > lo * 2.0, "вещи ур. 30 заметно сильнее вещей ур. 10 (сумма характеристик ×%.1f)" % (hi / maxf(1, lo)))
	check(pct_ok, "на обычных вещах нет процентных бонусов — только плоские числа")
	# миграция старых сохранений (одиночная игра и сервер — Game.normalize → Items.migrate)
	var oldc := DB.new_character("Старый", "warrior", {})
	oldc["level"] = 20
	oldc["equipped"] = [{"uid": "o1", "name": "Старый меч", "slot": 0, "rarity": 2, "ilvl": 18, "base": 34.0, "type": "sword", "cls": "warrior", "req": 18,
		"mods": [["dmg%", 30.0], ["crit", 9.0], ["hp", 80.0], ["as%", 14.0]]},
		{"uid": "o2", "name": "Печать Хранителя", "slot": 3, "rarity": 3, "ilvl": 12, "base": 0.0, "unique": "warden_ring", "type": "ring", "cls": "", "req": 12,
		"mods": [["hp", 96.0], ["dmg%", 16.0], ["ms%", 9.6], ["regen", 4.8]]}]
	oldc["inventory"] = [{"uid": "o3", "name": "Плащ", "slot": 1, "rarity": 4, "set": "blood", "ilvl": 16, "base": 50.0, "type": "cloak", "cls": "", "req": 16,
		"mods": [["leech%", 2.0], ["critdmg%", 40.0], ["dmg%", 20.0]]}]
	var mc: Dictionary = Game.normalize(JSON.parse_string(JSON.stringify(oldc)))
	var all_flat := true; var n_mods := 0
	for lst in [mc["equipped"], mc["inventory"]]:
		for it in lst:
			check(int(it.get("v", 0)) == Items.ITEM_V, "миграция: «%s» → %s" % [it.name, str(it.mods)])
			for m in it.mods:
				n_mods += 1
				if str(m[0]).ends_with("%") or m[0] in ["crit", "resred"]: all_flat = false
	check(all_flat and n_mods >= 9, "миграция: процентов на вещах не осталось (%d характеристик)" % n_mods)
	var again: Dictionary = Game.normalize(JSON.parse_string(JSON.stringify(mc)))
	check(str(again["equipped"][0].mods) == str(mc["equipped"][0].mods), "миграция идемпотентна")
	var tip := Items.tooltip(mc, mc["equipped"][0], false)
	check("рейтингу" in tip or "к урону" in tip, "подсказка показывает плоские числа")
	paths_section()
	print("=== BALANCE RESULT: %s (%d errors, %d checks) ===" % ["PASS" if errors == 0 else "FAIL", errors, checks])
	get_tree().quit(1 if errors else 0)

## v0.9.1: сравнение путей дерева талантов (tests/talent_paths.gd + talent_eval.gd).
## Для каждого класса: 3 ветви класса, 3 боевых превращения и путь поддержки; сборка — кратчайшая дорога + путь + остаток.
##  solo = урон × √живучесть (как у жадного выбора талантов); group — плюс вклад умений поддержки в группу из 3 союзников.
func paths_section() -> void:
	var TP = load("res://tests/talent_paths.gd")
	var TE = load("res://tests/talent_eval.gd")
	for lvl in [30, 45]:
		var bl: int = lvl + 1
		var tol: Array = [0.78, 1.25] if lvl == 30 else [0.7, 1.35]
		print("--- пути талантов, ур. %d (допуск %.2f–%.2f от медианы превращений) ---" % [lvl, tol[0], tol[1]])
		for cls in DB.CLASS_ORDER:
			var rows := []
			for p in TP.PATHS[cls]:
				var b: Dictionary = TP.build(cls, p[0], p[1], lvl, bl)
				var e: Dictionary = TE.eval(b.c, bl)
				var tv: Dictionary = TE.team_value(b.c)
				rows.append({"id": p[0], "role": p[1], "e": e, "tv": tv, "solo": float(e.off) * sqrt(float(e.def)), "road": int(b.road), "over": e.st.over})
			var tr := []; var br := []; var dmg_off := 0.0; var nd := 0; var dmg_def := 0.0
			for r in rows:
				if DB.get_asc(r.id).is_empty(): br.append(r.solo)
				elif r.role != "поддержка": tr.append(r.solo)
				if r.role == "урон" and not DB.get_asc(r.id).is_empty():
					dmg_off += float(r.e.off); dmg_def += float(r.e.def); nd += 1
			tr.sort(); br.sort()
			var med: float = tr[tr.size() / 2]
			var bmean: float = (br[0] + br[1] + br[2]) / 3.0
			dmg_off /= maxf(1, nd); dmg_def /= maxf(1, nd)
			for r in rows:
				var group: float = (float(r.e.off) + float(r.tv.dmg) * 3.0 * dmg_off) * sqrt(float(r.e.def) * (1.0 + float(r.tv.surv)))
				print("  %s %-12s %-9s урон %5.0f  живуч. %4.0f  solo %6.0f  group %6.0f  дорога %d  сверх потолков %s" % [cls, r.id, r.role, r.e.off, r.e.def, r.solo, group, r.road, str(r.over)])
				var waste := 0.0
				for k in r.over: waste = maxf(waste, float(r.over[k]))
				if lvl == 30: check(waste <= 6.0, "%s/%s: проценты почти не упираются в потолки (сгорает ≤6, есть %.1f)" % [cls, r.id, waste])
				if DB.get_asc(r.id).is_empty():
					if lvl == 30: check(r.solo / bmean > 0.8 and r.solo / bmean < 1.2, "%s/%s: ветвь класса ровно с остальными (%.2f от средней)" % [cls, r.id, r.solo / bmean])
				elif r.role == "поддержка":
					check(r.solo / med > 0.45, "%s/%s: поддержка справляется одна (%.2f от медианы > 0.45)" % [cls, r.id, r.solo / med])
					check(group / med > 0.85 and group / med < 1.4, "%s/%s: в группе — наравне с боевыми путями (%.2f)" % [cls, r.id, group / med])
					check(r.road <= 8, "%s/%s: путь поддержки рядом с классом (дорога %d узлов)" % [cls, r.id, r.road])
				else:
					check(r.solo / med > tol[0] and r.solo / med < tol[1], "%s/%s: сила пути %.2f от медианы превращений" % [cls, r.id, r.solo / med])
					if r.role == "танк": check(float(r.e.def) > dmg_def * 1.5, "%s/%s: танк живучее боевых путей (%.0f против %.0f)" % [cls, r.id, r.e.def, dmg_def])
	# потолки: всё дерево сразу — пассивы в FX_CAPS, ×2 вампиризма в пределах потолка
	var c := DB.new_character("Потолки", "warrior", {})
	c["level"] = 60; c["class_level"] = 60
	for id in DB.tree_order:
		if DB.tree_nodes[id]["type"] != "start":
			c["talents"].append(id); c["ranks"][str(id)] = int(DB.tree_nodes[id]["max_rank"])
	var st := DB.compute_stats(c)
	var ok := true
	for k in st.fx:
		if DB.FX_CAPS.has(k) and float(st.fx[k]) > float(DB.FX_CAPS[k]) + 0.001: ok = false
	check(ok and st.leech <= float(DB.PCT_CAPS["leech%"]) / 100.0 + 0.0001 and st.dr <= 0.75 and st.crit <= DB.CRIT_CAP / 100.0,
		"всё дерево сразу: пассивы, вампиризм (%.1f%%), снижение урона (%.0f%%), крит (%.0f%%) — в потолках" % [st.leech * 100, st.dr * 100, st.crit * 100])
	var dead := []
	for id in DB.tree_order:
		var n: Dictionary = DB.tree_nodes[id]
		if n["type"] != "start" and n["mods"].is_empty() and n["fx"].is_empty(): dead.append(n["name"])
	check(dead.is_empty(), "пустых узлов нет %s" % str(dead))

func item_power(it: Dictionary) -> float:
	var p := float(it.get("base", 0.0))
	for m in it.mods: p += absf(float(m[1]))
	return p

func report(tag: String, c: Dictionary, r: Dictionary) -> void:
	var st := DB.compute_stats(c)
	print("  [%s] %s: урон %.0f ×%.2f ×чары %.2f, скор. %.2f, крит %.0f%% ×%.2f, пробив. %.0f | hp %.0f, броня %.0f (−%.0f%%) | dps по боссу %.0f (множ. %.2f) — убийство %.0f с, гибель %.0f с → %s" % [
		c["class"], tag, st.damage, st.dmg_mult, st.spell_mult, st.attack_speed, st.crit * 100, st.crit_mult, st.pen,
		st.max_hp, st.armor, st.dr * 100, r.dps, r.factor, r.ttk, r.ttd, "ПОБЕДА" if r.win else "поражение"])

## Персонаж: уровень, мастерство = уровень, жадные таланты, редкие вещи ilvl в [g0, g1]
func make_char(cls: String, lvl: int, g0: int, g1: int, boss_lvl: int) -> Dictionary:
	var c := DB.new_character("Баланс", cls, {})
	c["level"] = lvl; c["class_level"] = lvl
	c["equipped"].clear()
	for sl in Items.SLOT_COUNT:
		var best = null; var bp := -1.0
		for k in 3:
			var it := Items.roll(randi_range(g0, g1), cls, 0.6, false, sl)
			while int(it.rarity) < 2: it = Items.roll(randi_range(g0, g1), cls, 0.6, false, sl)
			if item_power(it) > bp: bp = item_power(it); best = it
		best["req"] = mini(int(best.req), lvl)
		c["equipped"].append(best)
	var guard := 0
	while DB.free_points(c) > 0 and guard < 200:
		guard += 1
		var best_id := -1; var best_s := -1.0
		var cands := {}
		for id in c["talents"]:
			cands[int(id)] = true
			for l in DB.tree_nodes[int(id)]["links"]: cands[int(l)] = true
		for id in cands:
			if not DB.can_allocate(c, id): continue
			var cc := c.duplicate(true)
			DB.allocate(cc, id)
			var r := Combat.sim_fight(cc, BOSS, boss_lvl)
			var sc: float = r.dps * sqrt(r.ttd)
			if sc > best_s: best_s = sc; best_id = id
		if best_id < 0: break
		DB.allocate(c, best_id)
		if c["ascendancy"] == "":
			for a in DB.ASCENDANCIES:
				if DB.asc_block_reason(c, a) == "" and (a.get("cls", cls) == cls): c["ascendancy"] = a.id; break
	DB.auto_build_skills(c)
	return c
