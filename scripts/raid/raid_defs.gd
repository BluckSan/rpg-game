extends RefCounted
class_name RaidDefs
## Групповые подземелья (v0.8.0): общая раскладка (коридор с двумя группами стражей → арена босса),
## описание трёх подземелий и формулы масштабирования. Используется и сервером (RaidSim), и клиентом.

const ENTRY := Vector3(0, 0, 3)
const CORR_HALF := 6.0           # коридор: |x| ≤ 6, z 0..40
const CORR_END := 40.0
const GATE_Z := 41.0             # решётка арены: закрыта, пока живы стражи коридора и пока идёт бой
const ARENA_C := Vector3(0, 0, 63)
const ARENA_R := 20.0
const PACKS := [Vector3(0, 0, 16), Vector3(0, 0, 31)]
## Четыре опорные точки арены: островки Морвен, обелиски Аэтерона, жаровни Ворагоса
const POINTS := [Vector3(-12, 0, 55), Vector3(12, 0, 55), Vector3(-12, 0, 71), Vector3(12, 0, 71)]
const POINT_R := 3.2

const DUNGEONS := {
	"ash": {"name": "Пепельная Цитадель", "zone": "pd_ash", "boss": "rb_voragos", "enrage": 360.0, "set": "r_ash",
		"trash": [["bluedemon", "drake", "bluedemon"], ["drake", "bluedemon", "drake", "bluedemon"]], "elite": "bluedemon",
		"desc": "Ворагос, Пепельный Король. Рассечение конусом, метеоры (разойдитесь!), плита пепла (соберитесь!), щит со стражами, огненное кольцо. Ярость на 6:00.",
		"theme": {"floor": Color(0.36, 0.32, 0.3), "wall": Color(0.42, 0.36, 0.33), "light": Color(1.0, 0.55, 0.25), "fog": Color(0.25, 0.12, 0.08), "accent": Color(1.0, 0.4, 0.1)}},
	"crypt": {"name": "Затопленный Склеп", "zone": "pd_crypt", "boss": "rb_morwen", "enrage": 480.0, "hp_k": 0.85, "set": "r_tide",
		"trash": [["crab", "ghost", "crab"], ["ghost", "crab", "ghost", "crab"]], "elite": "crab",
		"desc": "Морвен, Утопленница. Песнь Бездны (прервите умением!), прилив (бегите на островки), наяды-целительницы, водоворот. Ярость на 7:00.",
		"theme": {"floor": Color(0.3, 0.36, 0.36), "wall": Color(0.34, 0.4, 0.42), "light": Color(0.45, 0.8, 1.0), "fog": Color(0.06, 0.16, 0.2), "accent": Color(0.3, 0.85, 1.0)}},
	"star": {"name": "Звёздное Святилище", "zone": "pd_star", "boss": "rb_aeteron", "enrage": 360.0, "set": "r_star",
		"trash": [["ether_guard", "demon", "ether_guard"], ["demon", "ether_guard", "demon", "ether_guard"]], "elite": "ether_guard",
		"desc": "Аэтерон, Страж Звезды. Лучи, звездопад, раскол на две половины (убейте обе за 10 с), Сверхновая на 50% и 20% (встаньте в щит обелиска — иначе гибель). Ярость на 6:00.",
		"theme": {"floor": Color(0.34, 0.33, 0.38), "wall": Color(0.4, 0.38, 0.46), "light": Color(0.75, 0.6, 1.0), "fog": Color(0.1, 0.08, 0.18), "accent": Color(0.8, 0.55, 1.0)}},
	# v0.9.5: Некрополь Пепельной Короны — своя раскладка (склепы, три мини-босса, ледяной тронный зал), см. L_*
	"lich": {"name": "Некрополь Пепельной Короны", "zone": "pd_lich", "boss": "rb_keltaar", "enrage": 1500.0, "hp_k": 4.6, "set": "r_lich",
		"trash": [], "elite": "rl_legion", "lich": true,
		"desc": "Кел'Таар, Король-Лич. Ледяные стрелы и зоны, волны скелетов; на 70% — неуязвим, пока целы 4 филактерии; на 40% — ледяная гробница (освободите союзника!) и «Смерть и разложение»; на 15% — Буря душ. Ярость на 25:00.",
		"theme": {"floor": Color(0.5, 0.56, 0.62), "wall": Color(0.46, 0.5, 0.56), "light": Color(0.45, 0.95, 0.8), "fog": Color(0.07, 0.13, 0.16), "accent": Color(0.35, 1.0, 0.75)}},
}
const ORDER := ["ash", "crypt", "star", "lich"]
## v0.9.3: порталы подземелий на карте мира — у города подходящего уровня (вход только через карту)
const PORTAL_TOWN := {"ash": "well", "crypt": "bog", "star": "frost", "lich": "frost"}
const PORTAL_OFF := {"lich": Vector2(26, -8)}   # второй портал у Заставы Инея — в стороне от Святилища
const READY_TIME := 25.0   # секунд на проверку готовности группы

static func portal_pos(did: String) -> Vector2:
	for t in WorldData.TOWNS:
		if t.id == PORTAL_TOWN.get(did, ""): return (t.pos as Vector2) + Vector2(0, -WorldData.TOWN_R - 22.0) + (PORTAL_OFF.get(did, Vector2.ZERO) as Vector2)
	return Vector2.ZERO

static func by_zone(zone_id: String) -> String:
	for k in DUNGEONS:
		if DUNGEONS[k].zone == zone_id: return k
	return ""

static func is_raid_zone(zone_id: String) -> bool: return zone_id.begins_with("pd_")

## Ожидаемый урон героя в секунду на уровне (по замерам raid_test): база для здоровья врагов и проверки урона
static func dps(lvl: int) -> float:
	return 26.0 * pow(1.0 + (lvl - 1) * 0.16, 1.35)

## Множитель группы: здоровье ×(1 + 0.85·(n−1)) — один игрок тоже может пройти (масштаб под соло)
static func party_k(n: int) -> float: return 1.0 + 0.85 * (maxi(1, n) - 1)

static func boss_hp(lvl: int, n: int) -> float: return dps(lvl) * 150.0 * party_k(n)
static func trash_hp(lvl: int, n: int, elite := false) -> float: return dps(lvl) * (14.0 if elite else 6.0) * (1.0 + 0.6 * (maxi(1, n) - 1))

## Потолок урона одного удара и урона за секунду от одного игрока (античит)
static func hit_cap(lvl: int) -> float: return dps(lvl) * 14.0 + 60.0
static func sec_cap(lvl: int) -> float: return dps(lvl) * 9.0 + 120.0

## v0.9.5: симуляция по подземелью (у Некрополя — своя, LichSim)
static func make_sim(did: String) -> RaidSim:
	return LichSim.new() if did == "lich" else RaidSim.new()

static func is_lich(did: String) -> bool: return did == "lich"
static func entry(did := "") -> Vector3: return L_ENTRY if did == "lich" else ENTRY
static func arena_c(did := "") -> Vector3: return L_ARENA_C if did == "lich" else ARENA_C
static func arena_r(did := "") -> float: return L_ARENA_R if did == "lich" else ARENA_R
static func points(did := "") -> Array: return L_POINTS if did == "lich" else POINTS
static func boss_home(did := "") -> Vector3: return L_BOSS_HOME if did == "lich" else ARENA_C + Vector3(0, 0, 6)

static func in_arena(p: Vector3, did := "") -> bool:
	if did == "lich": return p.z > L_DOORS[3] + 0.3 and (Vector2(p.x - L_ARENA_C.x, p.z - L_ARENA_C.z).length() < L_ARENA_R + 0.6 or absf(p.x) < 4.6)   # вход-ниша за решёткой тоже арена
	return Vector2(p.x - ARENA_C.x, p.z - ARENA_C.z).length() < ARENA_R + 0.6 and p.z > GATE_Z + 1.0

## Проходимая область: коридор ∪ круг арены (для врагов сервера)
static func clamp_pos(p: Vector3, did := "") -> Vector3:
	if did == "lich": return _l_clamp(p)
	if p.z <= GATE_Z + 1.5:
		return Vector3(clampf(p.x, -CORR_HALF + 0.6, CORR_HALF - 0.6), 0, clampf(p.z, 0.8, GATE_Z + 1.5))
	var d := Vector2(p.x - ARENA_C.x, p.z - ARENA_C.z)
	if d.length() > ARENA_R - 1.0: d = d.normalized() * (ARENA_R - 1.0)
	return Vector3(ARENA_C.x + d.x, 0, ARENA_C.z + d.y)

# ---------------- v0.9.5: Некрополь Пепельной Короны (Кел'Таар) ----------------
## Зал входа → Склеп легионов (2 группы) → Усыпальница Хранителя (круг) → Галерея банши (группа) →
## Часовня Сестры Нежити (круг) → Костяной зал Колосса (4 колонны) → Ледяной тронный зал Кел'Таара.
## Двери (z): 0 — после двух групп склепа, 1 — Хранитель и группа галереи, 2 — Сестра, 3 — Колосс (решётка тронного зала)
const L_ENTRY := Vector3(0, 0, 3)
const L_DOORS := [52.0, 100.0, 124.0, 172.0]
const L_PACKS := [Vector3(0, 0, 22), Vector3(0, 0, 40), Vector3(0, 0, 88)]
const L_TRASH := [["rl_legion", "rl_ghost", "rl_legion"], ["rl_acolyte", "rl_banshee", "rl_acolyte", "rl_ghost"], ["rl_legion", "rl_banshee", "rl_acolyte", "rl_ghost"]]
const L_KEEPER := Vector3(0, 0, 64)
const L_SISTER := Vector3(0, 0, 112)
const L_COLOSSUS := Vector3(0, 0, 150)
const L_ROOM_R := 12.0
const L_HALL := [-12.0, 12.0, 124.0, 172.0]        # Костяной зал: x0, x1, z0, z1
const L_COL_PILLARS := [Vector3(-6, 0, 138), Vector3(6, 0, 138), Vector3(-6, 0, 158), Vector3(6, 0, 158)]
const L_COL_PILLAR_R := 1.3
const L_ARENA_C := Vector3(0, 0, 196)
const L_ARENA_R := 22.0
const L_BOSS_HOME := Vector3(0, 0, 206)
const L_THRONE := Vector3(0, 0, 216)
## Филактерии — 4 столпа тронного зала; ледяные ямы — провалы во льду (замедляют и морозят)
const L_POINTS := [Vector3(-13, 0, 187), Vector3(13, 0, 187), Vector3(-13, 0, 205), Vector3(13, 0, 205)]
const L_PITS := [Vector3(-17, 0, 196), Vector3(17, 0, 196), Vector3(-10, 0, 184), Vector3(-7, 0, 211), Vector3(7, 0, 211)]
const L_PIT_R := 2.4
## Проходимые фигуры: прямоугольники [x0, x1, z0, z1] и круги [центр, r]
const L_RECTS := [[-9.0, 9.0, -4.0, 10.0], [-6.0, 6.0, 10.0, 53.0], [-4.5, 4.5, 75.0, 101.0], [-4.5, 4.5, 123.0, 125.0], [-12.0, 12.0, 124.0, 172.5], [-4.5, 4.5, 171.0, 177.0]]
const L_CIRCLES := [[Vector3(0, 0, 64), 12.0], [Vector3(0, 0, 112), 12.0], [Vector3(0, 0, 196), 22.0]]

static func _l_clamp(p: Vector3) -> Vector3:
	var best := p; var bd := INF
	for r in L_RECTS:
		var q := Vector3(clampf(p.x, r[0] + 0.6, r[1] - 0.6), 0, clampf(p.z, r[2] + 0.2, r[3] - 0.2))
		var dd := Vector2(q.x - p.x, q.z - p.z).length()
		if dd < 0.001: return Vector3(p.x, 0, p.z)
		if dd < bd: bd = dd; best = q
	for c in L_CIRCLES:
		var cc: Vector3 = c[0]
		var v := Vector2(p.x - cc.x, p.z - cc.z)
		var lim: float = float(c[1]) - 1.0
		if v.length() <= lim: return Vector3(p.x, 0, p.z)
		var q := cc + Vector3(v.normalized().x, 0, v.normalized().y) * lim
		var dd := Vector2(q.x - p.x, q.z - p.z).length()
		if dd < bd: bd = dd; best = q
	return best

## В какой части Некрополя точка: 0 склеп, 1 Хранитель, 2 галерея, 3 Сестра, 4 Костяной зал, 5 тронный зал
static func l_section(p: Vector3) -> int:
	if p.z < L_DOORS[0]: return 0
	if p.z < 76.0: return 1
	if p.z < L_DOORS[1]: return 2
	if p.z < L_DOORS[2]: return 3
	if p.z < L_DOORS[3]: return 4
	return 5
