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
	print("=== BALANCE RESULT: %s (%d errors, %d checks) ===" % ["PASS" if errors == 0 else "FAIL", errors, checks])
	get_tree().quit(1 if errors else 0)

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
	return c
