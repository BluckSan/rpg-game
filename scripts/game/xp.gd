class_name Xp
## v0.9.3: опыт за убийство. Считает сервер (WorldSim/подземелья), клиент только применяет число.
##  база      = xp_вида × (1 + 0.25·(ур_моба − 1))
##  уровень   = моб выше/равен: +10 % за уровень (до +50 %); ниже на 1–2 — ×1; на 3–5 — ×0.85/0.70/0.55;
##              «серые» (ниже на 6+) — резкий спад ×0.30/0.15/0.08, дальше ×0.02
##  ранг      = обычный ×1, элитный ×2.5, чемпион (rare) ×4, босс ×1 (у боссов своя большая база)
##  группа    = общий опыт × (1 + 0.1·(N−1)), N ≤ 6, делится пропорционально уровням участников
##  бонусы    = первое убийство вида за сутки +50 %; серия (убийства с паузой ≤ 15 с) +3 % за убийство, до +30 %

const RANK := {"normal": 1.0, "elite": 2.5, "rare": 4.0, "champion": 4.0, "boss": 1.0}
const STREAK_GAP := 15.0

static func base(def_xp: float, mob_lvl: int) -> float:
	return def_xp * (1.0 + (mob_lvl - 1) * 0.25)

static func level_mult(player_lvl: int, mob_lvl: int) -> float:
	var d := mob_lvl - player_lvl
	if d >= 0: return 1.0 + minf(d, 5) * 0.1
	var g := -d
	if g <= 2: return 1.0
	if g <= 5: return [0.85, 0.7, 0.55][g - 3]
	if g <= 8: return [0.3, 0.15, 0.08][g - 6]
	return 0.02

static func is_grey(player_lvl: int, mob_lvl: int) -> bool: return player_lvl - mob_lvl >= 6

static func group_bonus(n: int) -> float: return 1.0 + 0.1 * (clampi(n, 1, 6) - 1)

## Доли группы: lvls — уровни N участников; возвращает массив опыта (до личных бонусов)
static func shares(def_xp: float, mob_lvl: int, rank: String, lvls: Array) -> Array:
	var n := maxi(1, lvls.size())
	var total := base(def_xp, mob_lvl) * float(RANK.get(rank, 1.0)) * group_bonus(n)
	var sum := 0.0
	for l in lvls: sum += float(l)
	var out := []
	for l in lvls:
		var w := float(l) / sum if sum > 0.0 else 1.0 / n
		out.append(total * w * level_mult(int(l), mob_lvl))
	return out

## Личные бонусы; st — словарь состояния игрока на сервере {day, seen{}, streak, last_t}
static func personal(amount: float, st: Dictionary, kind: String, now: float, day: int) -> int:
	if int(st.get("day", -1)) != day: st["day"] = day; st["seen"] = {}
	var k := 1.0
	if not st.seen.has(kind):
		st.seen[kind] = true; k += 0.5
	if now - float(st.get("last_t", -100.0)) <= STREAK_GAP: st["streak"] = int(st.get("streak", 0)) + 1
	else: st["streak"] = 0
	st["last_t"] = now
	k += minf(0.3, 0.03 * int(st.streak))
	return maxi(1, int(round(amount * k)))

## Кривая уровней: ровный темп — ~7 убийств равного обычного моба на 1-м уровне, ~20 на 10-м, ~34 на 20-м, ~48 на 30-м
static func to_next(level: int) -> int:
	return int(round(base(30.0, level) * (6.0 + 1.4 * level) / 10.0) * 10)

static func today() -> int: return int(Time.get_unix_time_from_system() / 86400.0)
