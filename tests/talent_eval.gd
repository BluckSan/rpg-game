extends RefCounted
## v0.9.1: оценка путей дерева талантов для balance_test.
## Combat.sim_fight не учитывает пассивы (fx), перезарядку, ману и группу — здесь они приближаются:
##  off — урон в секунду по боссу (одна цель) с пассивами;  aoe — урон по группе из 4 врагов;
##  def — время жизни против босса (с зельями), с щитами маны, лечением критом, отражением;
##  team — вклад в урон/живучесть группы из 3 союзников (умения поддержки пути, усреднённые по времени).
const BOSS := "boss_seraph"
const PROJ_CLASSES := ["archer", "mage"]

static func eval(c: Dictionary, boss_lvl: int) -> Dictionary:
	var r := Combat.sim_fight(c, BOSS, boss_lvl)
	var st: Dictionary = DB.compute_stats(c)
	var fx: Dictionary = st.fx
	var cls: Dictionary = DB.CLASSES[c["class"]]
	var hits := float(st.attack_speed) / float(cls.interval)          # ударов в секунду
	var crit := float(st.crit)
	var m := 1.0
	m *= 0.6 + 0.4 / maxf(0.4, 1.0 - float(st.cdr))                       # 40% урона — умения
	m += 0.24 * float(fx.get("combo_wave", 0.0))
	m += float(fx.get("low_hp_dmg", 0.0)) / 100.0 * 0.3
	if cls.ranged: m += float(fx.get("far_dmg", 0.0)) / 100.0 * 0.7
	m += float(fx.get("proc_bleed", 0.0)) / 100.0 * 0.6 + float(fx.get("proc_poison", 0.0)) / 100.0 * 0.8
	m += float(fx.get("proc_burn", 0.0)) / 100.0 * 1.0 + float(fx.get("proc_bolt", 0.0)) / 100.0 * 0.6
	if fx.has("crit_mark"): m *= 1.0 + 0.3 * (1.0 - pow(1.0 - crit * float(fx.crit_mark) / 100.0, 3.0 * hits))
	if fx.has("roll_stealth"): m += (float(st.crit_mult) - 1.0) * (1.0 - crit) / maxf(1.0, 5.0 * hits * (1.0 + crit * (float(st.crit_mult) - 1.0)))
	if c["class"] in PROJ_CLASSES:
		m *= 1.0 + float(fx.get("proj_dmg", 0.0)) / 100.0 * 0.6
		m += 0.05 * float(fx.get("extra_proj", 0.0))
	m -= float(fx.get("mana_cost", 0.0)) / 100.0 * 0.15
	var hit_raw: float = float(st.damage) * float(st.dmg_mult) * (float(st.spell_mult) if cls.spell else 1.0)
	var off: float = r.dps * m + float(fx.get("aura_dmg", 0.0)) / 100.0 * hit_raw * float(r.factor)
	off += float(fx.get("thorns", 0.0)) / 100.0 * float(r.enemy_dps)
	# группа из 4 врагов: область, снаряды, цепи, взрывы трупов
	var g := 1.0 + 0.8 * (1.0 + float(fx.get("aoe%", 0.0)) / 100.0)
	if c["class"] in PROJ_CLASSES: g += 0.35 * float(fx.get("extra_proj", 0.0))
	g += 0.3 * float(fx.get("chain_plus", 0.0)) + float(fx.get("kill_explode", 0.0)) / 100.0 * 0.8
	var aoe: float = (r.dps * m) * g + 4.0 * float(fx.get("aura_dmg", 0.0)) / 100.0 * hit_raw * float(r.factor)
	# живучесть: запас здоровья (5 зелий) / чистый входящий урон; лечение и вампиризм гасят не больше 75% урона
	var edps := float(r.enemy_dps)
	var heal_s: float = float(fx.get("crit_heal", 0.0)) / 100.0 * float(st.max_hp) * crit * hits
	var sustain: float = float(st.regen) + minf(r.dps * float(st.leech), float(st.max_hp) * Combat.LEECH_SEC_CAP) + heal_s
	var mg := clampf(float(fx.get("mana_guard", 0.0)) / 100.0, 0.0, 0.8)
	if mg > 0.0: edps *= 1.0 - mg * minf(1.0, (float(st.max_mp) + float(st.mp_regen) * 30.0) / float(st.max_hp))
	var d: float = float(st.max_hp) * 3.0 / maxf(edps * 0.25, edps - sustain)
	if fx.has("aura_frost") or fx.has("elem_ice"): d *= 1.08
	d *= 1.0 + clampf(float(st.move_speed) / 5.2 - 1.0, -0.3, 0.3) * 0.25   # скорость — уход от телеграфов
	return {"off": off, "aoe": aoe, "def": d, "st": st}

## Вклад умений поддержки пути в группу из 3 союзников (доля урона союзника, усреднённая по перезарядке)
static func team_value(c: Dictionary) -> Dictionary:
	var a := DB.get_asc(str(c.get("ascendancy", "")))
	var dmg := 0.0; var surv := 0.0
	if a.is_empty() or not a.get("support", false): return {"dmg": 0.0, "surv": 0.0}
	var skills: Array = [a.skill] + a.get("skills_extra", [])
	var st: Dictionary = DB.compute_stats(c)
	var cdr := float(st.cdr)
	for s0 in skills:
		var s := DB._sup_boost(c, (s0 as Dictionary).duplicate())
		var eff := Support.resolve(s)
		var up := 1.0
		var cd := float(s.cd) * (1.0 - cdr)
		var n_targets := 3.0 if eff.tgt in ["aura"] else (1.0 if eff.tgt == "ally" else 3.0)
		if eff.has("buff"):
			up = minf(1.0, float(eff.buff.dur) / cd)
			for mo in eff.buff.mods:
				match str(mo[0]):
					"dmg%", "spell%": dmg += float(mo[1]) / 100.0 * up * n_targets / 3.0
					"as%": dmg += float(mo[1]) / 100.0 * 0.8 * up * n_targets / 3.0
					"crit": dmg += float(mo[1]) / 100.0 * 0.7 * up * n_targets / 3.0
					"cdr%": dmg += float(mo[1]) / 100.0 * 0.4 * up * n_targets / 3.0
					"armor%", "dr%": surv += float(mo[1]) / 100.0 * (0.25 if str(mo[0]) == "armor%" else 1.0) * up * n_targets / 3.0
					"mpregen": dmg += float(mo[1]) * 0.005 * up
		if eff.has("debuff"):
			var dd: Dictionary = eff.debuff
			var u2 := minf(1.0, float(dd.dur) / cd)
			if dd.kind == "mark": dmg += float(dd.v) * u2
			elif dd.kind == "weaken": surv += float(dd.v) * u2
			elif dd.kind == "slow": surv += float(dd.v) * 0.2 * u2
		for k in ["heal", "shield"]:
			if eff.has(k): surv += float(eff[k]) * 2.0 / cd * n_targets / 3.0 * 10.0 * 0.1
		if eff.has("hot"): surv += float(eff.hot) * 2.0 / cd * 10.0 * 0.1
		if eff.has("mana"): dmg += float(eff.mana) * 0.3 / cd * 10.0 * 0.1
		if eff.has("taunt"): surv += 0.15 * minf(1.0, float(eff.taunt) / cd) * 3.0
	# умения делят время каста: из 7 умений поддержки в наборе обычно 4–5
	return {"dmg": dmg * 0.7, "surv": surv * 0.7}
