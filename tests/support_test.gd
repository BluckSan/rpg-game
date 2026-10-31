extends Node
## v0.9.0: поддержка в групповых подземельях — серверная симуляция (RaidSim, как на сервере) с группой
## «игроков»-ботов: урон по характеристикам героя (Combat), уворот от телеграфов (оракул по зонам сервера),
## получаемый урон — по событиям сервера, как у клиента (×0.75, броня, щиты). Поддержка применяет умения
## через Support.resolve и RaidSim.apply_support — тот же путь, что и сервер (Net.c_support).
## Сравнение: 3 боевых героя против 2 боевых + 1 поддержка; соло-поддержка проходит медленно.
##   godot --headless --path . res://tests/support_test.tscn ++ [--lvl=20] [--dungeon=crypt] [--verbose]
var errors := 0
var checks := 0
var verbose := false
const DPS_ASC := {"warrior": "berserker", "mage": "elementalist", "archer": "shadow"}
const SUP_ASC := {"warrior": "herald", "mage": "arcanist", "archer": "hunter"}

func check(ok: bool, msg: String) -> void:
	checks += 1
	if ok: print("  OK   ", msg)
	else: errors += 1; print("  FAIL ", msg)

func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	verbose = args.has("verbose")
	var lvl := int(args.get("lvl", "20"))
	print("=== SUPPORT TEST (ур. %d) ===" % lvl)
	_static_checks(lvl)
	var dl: Array = RaidDefs.ORDER.filter(func(x): return x != "lich") if not args.has("dungeon") else [args.dungeon]
	for did in dl:
		for sc in DB.CLASS_ORDER:
			seed(1000 + did.length() * 7 + sc.length())
			var base := _party(lvl, "")
			seed(1000 + did.length() * 7 + sc.length())
			var with := _party(lvl, sc)
			# v0.9.4: бой стохастичен — сравниваем сумму 3 прогонов с одинаковыми сидами (одиночный прогон давал «смертей 1» случайно)
			var ra := _runs(did, lvl, base, 3)
			var rb := _runs(did, lvl, with, 3)
			var tag := "%s: 3 боевых — %s; с поддержкой «%s» — %s" % [did, _fmt(ra), DB.get_asc(SUP_ASC[sc]).name, _fmt(rb)]
			var faster: bool = rb.done and (not ra.done or rb.t < ra.t * 0.97)
			var safer: bool = rb.deaths < ra.deaths or (rb.deaths <= ra.deaths and rb.wipes <= ra.wipes and rb.taken < ra.taken * 0.85)
			check(rb.done and (faster or safer) and rb.wipes <= ra.wipes, tag + (" → быстрее" if faster else "") + (" → безопаснее" if safer else ""))
			check(rb.sup_casts > 5 and rb.sup_effects > 0, "%s: поддержка «%s» применяла умения (%d раз, эффектов %d, на сервере: %s)" % [did, DB.get_asc(SUP_ASC[sc]).name, rb.sup_casts, rb.sup_effects, str(rb.log)])
	# соло: поддержка проходит подземелье, но медленнее боевого пути
	for sc in DB.CLASS_ORDER:
		seed(77 + sc.length())
		var solo_s := _run("crypt", lvl, [_member(sc, lvl, SUP_ASC[sc])])
		seed(77 + sc.length())
		var solo_d := _run("crypt", lvl, [_member(sc, lvl, DPS_ASC[sc])])
		check(solo_s.done and solo_s.t > solo_d.t, "соло %s: поддержка «%s» проходит Склеп за %.0f с (боевой путь — %.0f с) — медленнее, но проходит" % [sc, DB.get_asc(SUP_ASC[sc]).name, solo_s.t, solo_d.t])
	print("=== SUPPORT RESULT: %s (%d errors, %d checks) ===" % ["PASS" if errors == 0 else "FAIL", errors, checks])
	get_tree().quit(1 if errors else 0)

func _runs(did: String, lvl: int, party: Array, n: int) -> Dictionary:
	var acc := {}
	for k in n:
		seed(4242 + k * 101 + did.length())
		var r := _run(did, lvl, party)
		if acc.is_empty(): acc = r.duplicate(); acc.t = 0.0; acc.deaths = 0; acc.wipes = 0; acc.taken = 0.0; acc.sup_casts = 0; acc.sup_effects = 0
		acc.done = acc.done and r.done if k > 0 else r.done
		acc.t += r.t / n; acc.taken += r.taken / n
		acc.deaths += r.deaths; acc.wipes += r.wipes
		acc.sup_casts += r.sup_casts; acc.sup_effects += r.sup_effects
	return acc

func _fmt(r: Dictionary) -> String:
	return "%s за %.0f с (ср.), смертей %d, вайпов %d, урона получено %.1f HP-долей" % ["убит" if r.done else "НЕ убит", r.t, r.deaths, r.wipes, r.taken]

## Потолки: баффы не пробивают потолки v0.8.0, ослабления — свои потолки
func _static_checks(lvl: int) -> void:
	var c: Dictionary = _member("warrior", lvl, "berserker").c
	var st0 := DB.compute_stats(c)
	var st1 := DB.compute_stats(c, [["dmg%", 500.0], ["cdr%", 200.0], ["as%", 300.0], ["dr%", 90.0], ["crit", 300.0]])
	check(st1.dmg_mult <= 1.0 + DB.PCT_CAPS["dmg%"] / 100.0 + 0.001 and st1.cdr <= DB.PCT_CAPS["cdr%"] / 100.0 + 0.001 and st1.crit <= DB.CRIT_CAP / 100.0 + 0.001 and st1.dr <= 0.75,
		"баффы упираются в потолки v0.8.0 (урон ×%.2f, перезарядка %.0f%%, крит %.0f%%, защита %.0f%%)" % [st1.dmg_mult, st1.cdr * 100, st1.crit * 100, st1.dr * 100])
	check(st1.damage == st0.damage, "баффы не меняют плоский урон")
	var n := 0; var all_ok := true
	for cls in SUP_ASC:
		var a := DB.get_asc(SUP_ASC[cls])
		var sk: Array = [a.skill] + a.skills_extra
		n += sk.size()
		for s in sk:
			if not Support.is_support(s): all_ok = false
			var e := Support.resolve(DB.skill_eff({"skill_ranks": {s.id: 5}, "class": cls}, s))
			if e.has("debuff") and float(e.debuff.v) > maxf(Support.MARK_CAP, maxf(Support.WEAKEN_CAP, Support.SLOW_CAP)) + 0.001: all_ok = false
			if e.has("shield") and float(e.shield) > Support.SHIELD_CAP + 0.001: all_ok = false
		check(sk.size() >= 6 and sk.size() <= 8, "%s «%s»: %d умений поддержки (6–8)" % [cls, a.name, sk.size()])
		check(DB.asc_block_reason({"ascendancy": "", "class": "warrior" if cls != "warrior" else "mage", "level": 99, "talents": [], "ranks": {}}, a).begins_with("Только"), "«%s» — только для класса %s" % [a.name, cls])
	check(all_ok and n == 21, "все %d умений — поддержка, ранг 5 не пробивает потолки (метка %.0f%%, ослабление %.0f%%, щит %.0f%%)" % [n, Support.MARK_CAP * 100, Support.WEAKEN_CAP * 100, Support.SHIELD_CAP * 100])

# ---------------- группа ----------------
func _member(cls: String, lvl: int, asc: String) -> Dictionary:
	var c := DB.new_character("Бот", cls, {})
	c["level"] = lvl; c["class_level"] = lvl
	c["equipped"].clear()
	for sl in Items.SLOT_COUNT:
		var it := Items.roll(randi_range(lvl - 2, lvl), cls, 0.6, false, sl)
		while int(it.rarity) < 2: it = Items.roll(randi_range(lvl - 2, lvl), cls, 0.6, false, sl)
		it["req"] = mini(int(it.req), lvl)
		c["equipped"].append(it)
	c["ascendancy"] = asc
	var a := DB.get_asc(asc)
	var prefer: Array = [a.skill.id]
	for x in a.skills_extra: prefer.append(x.id)
	DB.auto_build_skills(c, prefer)
	var sup: Array = []
	for id in c["loadout"]:
		var s = DB.find_skill(c, str(id))
		if s != null and Support.is_support(s): sup.append(DB.skill_eff(c, s))
	return {"c": c, "cls": cls, "asc": asc, "sup": sup, "support": a.get("support", false)}

func _party(lvl: int, sup_cls: String) -> Array:
	var out := []
	for cls in DB.CLASS_ORDER:
		out.append(_member(cls, lvl, SUP_ASC[cls] if cls == sup_cls else DPS_ASC[cls]))
	return out

## Прогон подземелья: серверная RaidSim + боты. Возвращает {done, t, deaths, wipes, taken, sup_casts, sup_effects, log}
func _run(did: String, lvl: int, party: Array) -> Dictionary:
	var sim := RaidSim.new()
	sim.setup(did, lvl, party.size())
	var P := {}
	for i in party.size():
		var pid := i + 1
		var m: Dictionary = party[i]
		sim.add_player(pid, {"name": "Бот%d" % pid, "cls": m.cls, "lvl": lvl})
		P[pid] = {"m": m, "hp": 1.0, "dead_t": 0.0, "alive": true, "pos": RaidDefs.ENTRY + Vector3(i * 1.5 - 1.5, 0, 0), "buffs": {}, "shield": 0.0,
			"hot": 0.0, "hot_t": 0.0, "pots": 5, "cd": {}, "hit_t": randf(), "skill_t": randf() * 3.0, "st": DB.compute_stats(m.c), "st_t": 0.0,
			"ranged": m.cls != "warrior"}
	var r := {"done": false, "t": 0.0, "deaths": 0, "wipes": 0, "taken": 0.0, "sup_casts": 0, "sup_effects": 0, "log": {}}
	var dt := 0.1
	var limit := 900.0
	var t := 0.0
	while t < limit and not sim.done:
		t += dt
		for pid in P: _bot(sim, P, pid, dt, r)
		for pid in P:
			var b: Dictionary = P[pid]
			sim.update_player(pid, b.pos, b.hp if b.alive else 0.0)
		sim.tick(dt)
		for ev in sim.events:
			var to: int = ev[0]; var e: Dictionary = ev[1]
			if str(e.get("t", "")) != "hurt": continue
			for pid in ([to] if to != 0 else P.keys()):
				if P.has(pid): _hurt(P[pid], e, r)
		sim.events.clear()
	r.done = sim.done and sim._boss().get("alive", true) == false
	r.t = t; r.wipes = sim.wipes
	r.log = sim.support_log
	if verbose: print("    ", did, " ", party.map(func(x): return x.asc), " ", _fmt(r))
	return r

func _hurt(b: Dictionary, e: Dictionary, r: Dictionary) -> void:
	if not b.alive: return
	var f: float = float(e.f) * 0.75
	if bool(e.l): f = 99.0
	else:
		f *= 1.0 - clampf(float(b.st.dr), 0.0, 0.85)
		var ab := minf(b.shield, f); b.shield -= ab; f -= ab
	r.taken += minf(f, 1.0)
	b.hp -= f
	if b.hp < 0.35 and b.pots > 0 and not bool(e.l): b.pots -= 1; b.hp = minf(1.0, b.hp + 0.45)
	if b.hp <= 0.0:
		b.hp = 0.0; b.alive = false; b.dead_t = 8.0; r.deaths += 1

func _buff_mods(b: Dictionary, t: float) -> Array:
	var out := []
	for k in b.buffs.keys():
		if float(b.buffs[k].until) <= t: b.buffs.erase(k); continue
		out.append_array(b.buffs[k].mods)
	return out

func _bot(sim: RaidSim, P: Dictionary, pid: int, dt: float, r: Dictionary) -> void:
	var b: Dictionary = P[pid]
	var t: float = sim.t
	if not b.alive:
		b.dead_t -= dt
		if b.dead_t <= 0.0:   # возрождение у входа
			b.alive = true; b.hp = 1.0; b.pos = RaidDefs.ENTRY; b.shield = 0.0; b.buffs.clear()
		return
	# характеристики с баффами (раз в 0.5 с)
	b.st_t -= dt
	if b.st_t <= 0.0:
		b.st_t = 0.5
		b.st = DB.compute_stats(b.m.c, _buff_mods(b, t))
	b.hp = minf(1.0, b.hp + float(b.st.regen) / float(b.st.max_hp) * dt)
	if b.hot_t > t: b.hp = minf(1.0, b.hp + b.hot * dt)
	# 1) уворот: оракул по зонам сервера (как бот видит метки на земле)
	var me: Vector3 = b.pos
	var moved := false
	for z in sim.tele:
		if float(z.left) > 1.2: continue
		var mode := str(z.get("mode", ""))
		if z.k == "safe":
			var best = null; var bd := INF
			for z2 in sim.tele:
				if z2.k == "safe" and z2.get("group") == z.get("group") and U.flat_dist(z2.pos, me) < bd: bd = U.flat_dist(z2.pos, me); best = z2
			if best != null and not sim._inside(best, me): b.pos = best.pos; moved = true
			break
		if mode == "stack":
			if not sim._inside(z, me): b.pos = z.pos + Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5)); moved = true
			continue
		if z.k == "ring" and sim._inside(z, me):
			b.pos = z.pos; moved = true; continue
		if sim._inside(z, me):
			var dir := U.flat(me - z.pos)
			if dir.length() < 0.2: dir = Vector3.RIGHT.rotated(Vector3.UP, randf() * TAU)
			if z.k in ["line", "cone"]:
				var fwd := Vector3(sin(z.yaw), 0, cos(z.yaw)); dir = fwd.cross(Vector3.UP)
				if dir.dot(me - z.pos) < 0: dir = -dir
				b.pos = RaidDefs.clamp_pos(me + dir.normalized() * (float(z.get("ang", 4.0)) / 2.0 + 2.5))
			else:
				b.pos = RaidDefs.clamp_pos(z.pos + dir.normalized() * (float(z.r) + 1.5))
			moved = true
	# во время боя уворот не выводит за решётку арены (как игрок у стены)
	if moved and sim.engaged and RaidDefs.in_arena(me) and not RaidDefs.in_arena(b.pos):
		var dv := U.flat(b.pos - RaidDefs.ARENA_C)
		b.pos = RaidDefs.ARENA_C + dv.normalized() * minf(dv.length(), RaidDefs.ARENA_R - 3.0)
		if not RaidDefs.in_arena(b.pos): b.pos = me
	# 2) цель: помощники/половины → стражи → босс
	var tgt = null; var ts := -INF
	for id in sim.enemies:
		var e = sim.enemies[id]
		if not e.alive or e.get("hidden", false): continue
		var s := -U.flat_dist(e.pos, me) * 0.2
		match str(e.role):
			"add", "naiad": s += 100.0
			"half": s += 80.0 + float(e.hp) / maxf(1.0, float(e.mhp)) * 50.0
			"trash": s += 60.0
			"boss": s += 10.0 - (200.0 if e.get("invuln", false) else 0.0)
		if s > ts: ts = s; tgt = e
	var boss: Dictionary = sim._boss()
	if not sim.cast.is_empty() and sim.cast.get("interrupt", false) and boss.get("alive", false): tgt = boss
	if tgt == null: return
	if sim.gate_open and sim._trash_left() == 0 and not RaidDefs.in_arena(me) and not moved:
		b.pos = RaidDefs.clamp_pos(me + U.flat(RaidDefs.ARENA_C - me).normalized() * minf(6.0 * dt, me.distance_to(RaidDefs.ARENA_C)))
		return
	var want: float = 8.0 if b.ranged else 2.2
	var dist := U.flat_dist(tgt.pos, me)
	if not moved and dist > want:
		b.pos = RaidDefs.clamp_pos(me + U.flat(tgt.pos - me).normalized() * minf(5.6 * dt, dist - want + 0.1))
	# 3) поддержка: умения по перезарядке
	if b.m.support: _support_ai(sim, P, pid, b, tgt, r)
	# 4) урон (раз в 0.5 с), умение — каждые ~3 с (прерывание кастов)
	b.hit_t -= dt
	if b.hit_t <= 0.0 and dist < (14.0 if b.ranged else 3.5):
		b.hit_t = 0.5
		var dps: float = Combat.sim_fight(b.m.c, str(boss.get("kind", "rb_voragos")), sim.level, "normal", _buff_mods(b, t)).dps
		b.skill_t -= 0.5
		var sk: bool = b.skill_t <= 0.0
		if sk: b.skill_t = 3.0
		sim.hit(pid, int(tgt.id), dps * 0.5, sk)

func _support_ai(sim: RaidSim, P: Dictionary, pid: int, b: Dictionary, tgt: Dictionary, r: Dictionary) -> void:
	var t: float = sim.t
	for s in b.m.sup:
		if float(b.cd.get(s.id, 0.0)) > t: continue
		var eff := Support.resolve(s)
		var tg := str(eff.tgt)
		var used := false
		match tg:
			"aura", "self":
				var any := tg == "self"
				for q in P:
					if P[q].alive and (tg == "aura" and U.flat_dist(P[q].pos, b.pos) <= float(eff.radius) + 3.0 or q == pid):
						if eff.has("buff") or eff.has("shield") or eff.has("heal") or eff.has("hot"): any = true
				if not any: continue
				if eff.has("heal") and not eff.has("buff"):
					var need := false
					for q in P: if P[q].alive and P[q].hp < 0.8: need = true
					if not need: continue
				for q in P:
					if P[q].alive and (q == pid or (tg == "aura" and U.flat_dist(P[q].pos, b.pos) <= float(eff.radius) + 3.0)):
						_apply_ally(P[q], s, eff, t); r.sup_effects += 1
				used = true
			"ally":
				var low = null; var lh := 2.0
				for q in P:
					if P[q].alive and P[q].hp < lh and U.flat_dist(P[q].pos, b.pos) <= float(eff.range) + 6.0: lh = P[q].hp; low = q
				if low == null or (eff.has("heal") and not eff.has("shield") and lh > 0.75) or (eff.has("shield") and P[low].shield > 0.05): continue
				_apply_ally(P[low], s, eff, t); r.sup_effects += 1
				used = true
			_:
				var n := sim.apply_support(pid, eff, int(tgt.id), tgt.pos)
				if n <= 0: continue
				r.sup_effects += n
				if eff.has("buff") or eff.has("shield"): _apply_ally(b, s, eff, t)
				used = true
		if used:
			b.cd[s.id] = t + float(s.cd) * (1.0 - float(b.st.cdr))
			r.sup_casts += 1
			return   # одно умение за такт

func _apply_ally(q: Dictionary, s: Dictionary, eff: Dictionary, t: float) -> void:
	if eff.has("heal"): q.hp = minf(1.0, q.hp + float(eff.heal))
	if eff.has("shield"): q.shield = maxf(q.shield, float(eff.shield) * 1.0)
	if eff.has("hot"): q.hot = float(eff.hot) / 6.0; q.hot_t = t + 6.0
	if eff.has("buff"): q.buffs[s.id] = {"mods": eff.buff.mods, "until": t + float(eff.buff.dur)}
	q.st_t = 0.0
