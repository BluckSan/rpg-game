extends RefCounted
class_name Combat
## Боевая математика v0.5: броня врагов, стихийные сопротивления, разница уровней.
##  броня: снижение = броня / (броня + K · уровень атакующего); пробивание (pen%) снижает броню цели
##  сопротивления: % по стихиям (макс. 75%, отрицательные — уязвимость до −50%); resred вычитает пункты
##  разница уровней: враг выше вас больше чем на 2 — −15% урона за уровень (мин. 10%), его урон +12%/ур.
##  опыт/добыча с врагов сильно ниже вас — меньше.

const ARMOR_K := 8.0
const RES_CAP := 75.0
const RES_MIN := -50.0
const PEN_CAP := 40.0

const ELEM_NAMES := {"phys": "физ.", "fire": "огонь", "ice": "лёд", "lightning": "молния", "poison": "яд",
	"shadow": "тьма", "holy": "свет", "arcane": "эфир"}
const ELEM_COLORS := {"phys": Color(1, 0.98, 0.92), "fire": Color(1, 0.55, 0.2), "ice": Color(0.55, 0.85, 1.0),
	"lightning": Color(0.85, 0.85, 1.0), "poison": Color(0.55, 0.95, 0.3), "shadow": Color(0.75, 0.5, 1.0),
	"holy": Color(1, 0.92, 0.5), "arcane": Color(0.95, 0.55, 1.0)}

## Стихия умения (по виду). Базовые атаки: воин/лучник — физ., маг — эфир.
const SKILL_ELEM := {"fireball": "fire", "fire_wall": "fire", "meteor": "fire",
	"frost_nova": "ice", "ice_lance": "ice", "ice_prison": "ice", "disengage": "ice",
	"chain": "lightning", "storm": "lightning",
	"poison": "poison",
	"shadow_strike": "shadow", "knife_fan": "shadow", "bone_nova": "shadow", "curse": "shadow", "summon": "shadow",
	"holy_hammer": "holy", "consecrate": "holy"}
const CLASS_ELEM := {"warrior": "phys", "archer": "phys", "mage": "arcane"}

## Броня и сопротивления врагов по типу (броня — за уровень врага)
const ENEMY_DEF := {
	"slime": {"armor": 1.0, "res": {"poison": 50, "fire": -30}},
	"wolf": {"armor": 1.2, "res": {"ice": 30, "fire": -25}},
	"skeleton_archer": {"armor": 1.6, "res": {"poison": 75, "shadow": 40, "holy": -50}},
	"skeleton": {"armor": 2.2, "res": {"poison": 75, "shadow": 40, "holy": -50}},
	"goblin": {"armor": 2.0, "res": {"fire": 20, "poison": -20}},
	"ether_guard": {"armor": 2.5, "res": {"arcane": 50, "lightning": 30, "shadow": -25}},
	"troll": {"armor": 4.5, "res": {"poison": 40, "ice": 25, "fire": -35}},
	# v0.5.1 — семейства открытого мира
	"rat": {"armor": 0.8, "res": {"poison": 30, "fire": -20}},
	"bull": {"armor": 2.4, "res": {"ice": 20, "lightning": -25}},
	"spider": {"armor": 1.2, "res": {"poison": 60, "fire": -40}},
	"mushnub": {"armor": 0.8, "res": {"poison": 75, "fire": -50}},
	"goblin_shaman": {"armor": 1.2, "res": {"arcane": 30, "shadow": 20}},
	"bee": {"armor": 0.8, "res": {"poison": 40, "ice": -30}},
	"orc": {"armor": 2.6, "res": {"fire": 20, "shadow": -20}},
	"cactoro": {"armor": 2.0, "res": {"fire": 40, "poison": 30, "ice": -35}},
	"drake": {"armor": 1.8, "res": {"fire": 75, "ice": -40}},
	"frog": {"armor": 1.4, "res": {"poison": 60, "lightning": -35}},
	"crab": {"armor": 4.0, "res": {"ice": 30, "poison": 20, "lightning": -40}},
	"ghost": {"armor": 0.6, "res": {"shadow": 75, "poison": 75, "holy": -50}},
	"bat": {"armor": 0.8, "res": {"shadow": 30, "lightning": -30}},
	"yeti": {"armor": 2.8, "res": {"ice": 75, "fire": -40}},
	"hywirl": {"armor": 1.4, "res": {"ice": 75, "lightning": 30, "fire": -45}},
	"imp": {"armor": 1.6, "res": {"arcane": 40, "fire": 30, "holy": -30}},
	"demon": {"armor": 1.8, "res": {"fire": 50, "shadow": 40, "holy": -40}},
	"bluedemon": {"armor": 3.0, "res": {"shadow": 40, "ice": 30, "holy": -40}},
	"boss_ogron": {"armor": 4.5, "res": {"fire": 25, "poison": 25, "shadow": -30}},
	"boss_root": {"armor": 4.5, "res": {"poison": 75, "ice": 25, "fire": -40}},
	"boss_urgal": {"armor": 5.0, "res": {"fire": 75, "arcane": 25, "ice": -35}},
	"boss_gnil": {"armor": 4.5, "res": {"poison": 75, "ice": 20, "lightning": -35}},
	"boss_hyalm": {"armor": 5.0, "res": {"ice": 75, "poison": 25, "fire": -40}},
	"boss_seraph": {"armor": 5.0, "res": {"fire": 50, "shadow": 50, "arcane": 30, "holy": -35}},
	"warden": {"armor": 5.5, "res": {"arcane": 55, "shadow": 40, "lightning": 25, "holy": -30}},
}
const RANK_ARMOR := {"normal": 1.0, "elite": 1.3, "rare": 1.6, "boss": 1.0}   # боссы: высокая базовая броня в ENEMY_DEF
const RANK_RES := {"normal": 0.0, "elite": 5.0, "rare": 10.0, "boss": 10.0}
## Рекомендуемый уровень боссов (табличка, карта)
const BOSS_REC := {"troll": 8, "warden": 10}

## Рекомендуемый уровень босса: из таблицы, для боссов мира — уровень босса − 2
static func boss_rec(kind: String, level: int) -> int:
	return int(BOSS_REC.get(kind, level - 2)) if level <= 10 else level - 2

static func elem_of_skill(s: Dictionary, class_id: String) -> String:
	if s.has("elem"): return s.elem
	return SKILL_ELEM.get(String(s.get("kind", "")), CLASS_ELEM.get(class_id, "phys"))

static func enemy_armor(kind: String, level: int, rank: String, is_boss: bool) -> float:
	var r := rank if rank != "normal" else ("boss" if is_boss else "normal")
	return float(ENEMY_DEF.get(kind, {}).get("armor", 1.5)) * level * float(RANK_ARMOR.get(r, 1.0))

## Сопротивление (в %) врагу; положительные получают бонус ранга, уязвимости — нет
static func enemy_resist(kind: String, elem: String, rank: String, is_boss: bool) -> float:
	if elem == "phys": return 0.0
	var r := rank if rank != "normal" else ("boss" if is_boss else "normal")
	var v := float(ENEMY_DEF.get(kind, {}).get("res", {}).get(elem, 0.0))
	if v > 0: v += float(RANK_RES.get(r, 0.0))
	return clampf(v, RES_MIN, RES_CAP)

## v0.8.0: pen_flat — плоское пробивание со снаряжения (вычитается из брони цели до процентов)
static func armor_factor(armor: float, att_level: int, pen_pct: float, pen_flat := 0.0) -> float:
	var a := maxf(0.0, armor - pen_flat) * (1.0 - clampf(pen_pct, 0, PEN_CAP) / 100.0)
	return 1.0 - a / (a + ARMOR_K * maxi(1, att_level))

static func resist_factor(res: float, res_red: float) -> float:
	var r := res - res_red if res > 0 else res
	return 1.0 - clampf(r, RES_MIN, RES_CAP) / 100.0

## v0.8.0: урон по цели выше вас: −12% за каждый уровень разницы (не ниже 10%)
static func level_factor(att_level: int, def_level: int) -> float:
	var d := def_level - att_level
	return maxf(0.1, 1.0 - 0.12 * d) if d > 0 else 1.0

## v0.8.0: урон врага по герою ниже его уровня: +10% за каждый уровень разницы
static func enemy_dmg_factor(enemy_level: int, player_level: int) -> float:
	var d := enemy_level - player_level
	return 1.0 + 0.1 * d if d > 0 else 1.0

## v0.8.0: рост здоровья и урона врагов с уровнем (слегка ускоряется — под рост снаряжения)
static func enemy_hp_mult(level: int) -> float:
	return (1.0 + (level - 1) * 0.22) * (1.0 + (level - 1) * 0.035)
static func enemy_dmg_mult(level: int) -> float:
	return (1.0 + (level - 1) * 0.18) * (1.0 + (level - 1) * 0.02)
## Похищение жизни: за удар не больше 1.5% здоровья (в секунду — не больше 3%)
const LEECH_HIT_CAP := 0.015
const LEECH_SEC_CAP := 0.03

## Опыт и добыча с врагов, которые намного ниже героя
static func reward_factor(player_level: int, enemy_level: int) -> float:
	var diff := player_level - enemy_level
	return maxf(0.2, 1.0 - (diff - 4) * 0.2) if diff > 4 else 1.0

## Полный множитель урона героя по врагу e
static func player_vs_enemy(e, elem: String, att_level: int, pen: float, res_red: float, pen_flat := 0.0) -> float:
	var f := level_factor(att_level, e.level)
	if elem == "phys":
		f *= armor_factor(enemy_armor(e.kind, e.level, e.rank, e.def.boss) * (float(e.armor_mult) if "armor_mult" in e else 1.0), att_level, pen, pen_flat)
	else:
		var rb: float = float(e.res_bonus) if "res_bonus" in e else 0.0
		f *= resist_factor(clampf(enemy_resist(e.kind, elem, e.rank, e.def.boss) + rb, RES_MIN, RES_CAP), res_red)
	return f

## Подпись сопротивлений: "Уязв.: огонь · Стоек: яд, лёд"
static func resist_text(kind: String, rank := "normal", is_boss := false) -> String:
	var weak := []; var strong := []
	for el in ENEMY_DEF.get(kind, {}).get("res", {}):
		var v := enemy_resist(kind, el, rank, is_boss)
		if v < 0: weak.append(ELEM_NAMES[el])
		elif v >= 20: strong.append(ELEM_NAMES[el])
	var parts := []
	if not weak.is_empty(): parts.append("Уязв.: " + ", ".join(weak))
	if not strong.is_empty(): parts.append("Стоек: " + ", ".join(strong))
	return " · ".join(parts)

## Оценка боя «герой против врага» по реальным формулам (для тестов и баланса).
## Учитывает урон, крит, скорость, умения (×1.5 к базовой атаке), броню/сопротивления/уровни,
## урон врага, броню героя, регенерацию, похищение жизни и 5 зелий (по 40%);
## уворот от телеграфов: вблизи проходит 50% урона босса, издалека — 35%.
static func sim_fight(c: Dictionary, kind: String, level: int, rank := "normal") -> Dictionary:
	var st: Dictionary = DB.compute_stats(c)
	var cls: Dictionary = DB.CLASSES[c["class"]]
	var def: Dictionary = DB.ENEMIES[kind]
	var plv := int(c["level"])
	var elem: String = CLASS_ELEM.get(c["class"], "phys")
	var hit: float = st.damage * st.dmg_mult * (st.spell_mult if cls.spell else 1.0)
	hit *= 1.0 + st.crit * (st.crit_mult - 1.0)
	var dps: float = hit / float(cls.interval) * st.attack_speed * 1.5
	var fake := {"kind": kind, "level": level, "rank": rank, "def": def}
	var f := level_factor(plv, level)
	if elem == "phys": f *= armor_factor(enemy_armor(kind, level, rank, def.boss), plv, st.get("pen", 0.0), st.get("pen_flat", 0.0))
	else: f *= resist_factor(enemy_resist(kind, elem, rank, def.boss), st.get("resred", 0.0))
	dps *= f
	var ehp: float = def.hp * enemy_hp_mult(level)
	var edmg: float = def.dmg * enemy_dmg_mult(level) * enemy_dmg_factor(level, plv) / float(def.interval)
	edmg *= (1.0 - clampf(st.dr, 0, 0.85)) * ((0.35 if cls.ranged else 0.5) if def.boss else 1.0)   # телеграфы боссов: уворот; дальний бой — больше
	var net: float = maxf(0.01, edmg - st.regen - minf(dps * st.leech, st.max_hp * LEECH_SEC_CAP))
	var survive: float = st.max_hp * (1.0 + 5 * 0.4) / net   # 5 зелий из лавки
	var ttk: float = ehp / maxf(0.01, dps)
	fake.clear()
	return {"dps": dps, "factor": f, "ttk": ttk, "ttd": survive, "win": ttk < survive, "enemy_dps": edmg}
