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
}
const ORDER := ["ash", "crypt", "star"]
## v0.9.3: порталы подземелий на карте мира — у города подходящего уровня (вход только через карту)
const PORTAL_TOWN := {"ash": "well", "crypt": "bog", "star": "frost"}
const READY_TIME := 25.0   # секунд на проверку готовности группы

static func portal_pos(did: String) -> Vector2:
	for t in WorldData.TOWNS:
		if t.id == PORTAL_TOWN.get(did, ""): return (t.pos as Vector2) + Vector2(0, -WorldData.TOWN_R - 22.0)
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

static func in_arena(p: Vector3) -> bool:
	return Vector2(p.x - ARENA_C.x, p.z - ARENA_C.z).length() < ARENA_R + 0.6 and p.z > GATE_Z + 1.0

## Проходимая область: коридор ∪ круг арены (для врагов сервера)
static func clamp_pos(p: Vector3) -> Vector3:
	if p.z <= GATE_Z + 1.5:
		return Vector3(clampf(p.x, -CORR_HALF + 0.6, CORR_HALF - 0.6), 0, clampf(p.z, 0.8, GATE_Z + 1.5))
	var d := Vector2(p.x - ARENA_C.x, p.z - ARENA_C.z)
	if d.length() > ARENA_R - 1.0: d = d.normalized() * (ARENA_R - 1.0)
	return Vector3(ARENA_C.x + d.x, 0, ARENA_C.z + d.y)
