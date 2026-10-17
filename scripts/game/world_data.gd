extends RefCounted
class_name WorldData
## «Земли Эфира»: описание открытого мира 2048×2048 м — биомы, уровни, города, дороги, точки интереса,
## высота рельефа и веса слоёв земли. Всё детерминировано (одинаково для мира, карты и тестов).

const HALF := 1024.0                 # мир: −1024…1024 по X и Z (2,05 × 2,05 км)
const CHUNK := 64.0
const EDGE := 960.0                  # дальше — горы-граница
const LAYER_AVG := [Color8(96, 109, 48), Color8(152, 147, 87), Color8(84, 62, 51), Color8(181, 158, 113), Color8(156, 139, 110), Color8(200, 201, 201), Color8(79, 77, 70)]
enum L { GRASS, FOREST, ROAD, SAND, MUD, SNOW, ROCK }

const BIOMES := [
	{"id": "meadows", "name": "Изумрудные луга", "lv": [5, 9], "seed": Vector2(0, 640), "amp": 6.0, "layer": L.GRASS, "bright": 1.0,
		"color": Color(0.45, 0.62, 0.3), "mobs": ["wolf", "bull", "rat", "slime"],
		"rares": [["wolf", "Клык Вожак"], ["bull", "Рогач Громобой"]], "boss": "Король холмов Огрон", "boss_kind": "boss_ogron"},
	{"id": "forest", "name": "Шепчущий лес", "lv": [8, 13], "seed": Vector2(-620, 260), "amp": 10.0, "layer": L.FOREST, "bright": 0.88,
		"color": Color(0.22, 0.42, 0.22), "mobs": ["spider", "mushnub", "goblin_shaman", "bee", "spider"],
		"rares": [["spider", "Паучиха Шелкопряд"], ["goblin_shaman", "Ворожей Шнырь"]], "boss": "Древень Мшистый Корень", "boss_kind": "boss_root"},
	{"id": "desert", "name": "Пепельные пустоши", "lv": [12, 17], "seed": Vector2(620, 260), "amp": 9.0, "layer": L.SAND, "bright": 1.0,
		"color": Color(0.78, 0.66, 0.42), "mobs": ["orc", "cactoro", "drake", "skeleton"],
		"rares": [["orc", "Вождь Карах"], ["drake", "Пламехвост"]], "boss": "Пепельный дракон Ургал", "boss_kind": "boss_urgal"},
	{"id": "swamp", "name": "Гнилые топи", "lv": [15, 20], "seed": Vector2(-600, -420), "amp": 2.5, "layer": L.MUD, "bright": 0.78,
		"color": Color(0.36, 0.4, 0.26), "mobs": ["frog", "crab", "ghost", "bat"],
		"rares": [["crab", "Старый Панцирь"], ["ghost", "Утопленник Варн"]], "boss": "Топяной великан Гнилобрюх", "boss_kind": "boss_gnil"},
	{"id": "snow", "name": "Ледяной хребет", "lv": [19, 25], "seed": Vector2(600, -440), "amp": 26.0, "layer": L.SNOW, "bright": 1.0,
		"color": Color(0.86, 0.9, 0.95), "mobs": ["yeti", "hywirl", "wolf", "imp"],
		"rares": [["yeti", "Ледобой Храг"], ["hywirl", "Вьюга Сиверь"]], "boss": "Инеистый йети Хьяльм", "boss_kind": "boss_hyalm"},
	{"id": "ruins", "name": "Руины Эфира", "lv": [24, 30], "seed": Vector2(0, -760), "amp": 11.0, "layer": L.FOREST, "bright": 0.7,
		"color": Color(0.45, 0.38, 0.52), "mobs": ["demon", "bluedemon", "skeleton", "ether_guard", "imp"],
		"rares": [["bluedemon", "Рогатый князь Аэль"], ["skeleton", "Костяной король Мор"]], "boss": "Падший серафим Эфира", "boss_kind": "boss_seraph"},
]

## Города/лагеря: торговец, сундук, путевой камень
const TOWNS := [
	{"id": "cross", "name": "Перекрёсток", "pos": Vector2(0, 560), "biome": 0, "kind": "town"},
	{"id": "grove", "name": "Лесной приют", "pos": Vector2(-560, 230), "biome": 1, "kind": "camp"},
	{"id": "well", "name": "Сухой Колодец", "pos": Vector2(560, 230), "biome": 2, "kind": "town"},
	{"id": "bog", "name": "Топкий лагерь", "pos": Vector2(-540, -380), "biome": 3, "kind": "camp"},
	{"id": "frost", "name": "Застава Инея", "pos": Vector2(540, -400), "biome": 4, "kind": "town"},
	{"id": "bastion", "name": "Последний оплот", "pos": Vector2(0, -470), "biome": 5, "kind": "camp"},
]
const TOWN_R := 36.0

## Дороги (ломаные): индексы городов и промежуточные точки
const ROADS := [
	[Vector2(0, 560), Vector2(-180, 470), Vector2(-380, 330), Vector2(-560, 230)],
	[Vector2(0, 560), Vector2(200, 460), Vector2(400, 320), Vector2(560, 230)],
	[Vector2(-560, 230), Vector2(-610, 60), Vector2(-580, -160), Vector2(-540, -380)],
	[Vector2(560, 230), Vector2(620, 40), Vector2(590, -200), Vector2(540, -400)],
	[Vector2(-540, -380), Vector2(-360, -450), Vector2(-160, -470), Vector2(0, -470)],
	[Vector2(540, -400), Vector2(360, -460), Vector2(160, -480), Vector2(0, -470)],
	[Vector2(0, 560), Vector2(30, 330), Vector2(-20, 100), Vector2(20, -160), Vector2(0, -470)],
	[Vector2(0, 560), Vector2(0, 760), Vector2(-40, 900)],
]

## Точки интереса: тип постройки, биом определяется по месту. boss — арена босса зоны.
const POIS := [
	{"id": "mill", "name": "Старая мельница", "pos": Vector2(170, 700), "kind": "mill"},
	{"id": "circle", "name": "Каменный круг", "pos": Vector2(-230, 640), "kind": "circle"},
	{"id": "hill", "name": "Холм Огрона", "pos": Vector2(260, 860), "kind": "arena", "boss": 0},
	{"id": "bandits", "name": "Лагерь разбойников", "pos": Vector2(-760, 360), "kind": "camp_ruin"},
	{"id": "heart", "name": "Сердце леса", "pos": Vector2(-480, 50), "kind": "arena", "boss": 1},
	{"id": "oasis", "name": "Мёртвый оазис", "pos": Vector2(760, 380), "kind": "oasis"},
	{"id": "colossus", "name": "Ложе колосса", "pos": Vector2(470, 30), "kind": "arena", "boss": 2},
	{"id": "crypt", "name": "Гнилой склеп", "pos": Vector2(-760, -280), "kind": "crypt"},
	{"id": "mire", "name": "Сердце топи", "pos": Vector2(-470, -600), "kind": "arena", "boss": 3},
	{"id": "tower", "name": "Ледяная башня", "pos": Vector2(760, -560), "kind": "tower"},
	{"id": "peak", "name": "Пик Хьяльма", "pos": Vector2(420, -640), "kind": "arena", "boss": 4},
	{"id": "siege", "name": "Поле осады", "pos": Vector2(-220, -700), "kind": "siege"},
	{"id": "temple", "name": "Разрушенный храм", "pos": Vector2(0, -820), "kind": "arena", "boss": 5},
	{"id": "graves", "name": "Кладбище Эфира", "pos": Vector2(250, -720), "kind": "graves"},
]

static var _noise: FastNoiseLite
static var _warp: FastNoiseLite
static var _detail: FastNoiseLite
static var _roads: Array = []        # [[a: Vector2, b: Vector2], ...] — отрезки (сглаженные)
static var _town_h: Array = []

static func init() -> void:
	if _noise != null: return
	_noise = FastNoiseLite.new(); _noise.seed = 4242; _noise.frequency = 0.0035; _noise.fractal_octaves = 4
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_warp = FastNoiseLite.new(); _warp.seed = 99; _warp.frequency = 0.0022; _warp.fractal_octaves = 2
	_detail = FastNoiseLite.new(); _detail.seed = 7; _detail.frequency = 0.045; _detail.fractal_octaves = 2
	# дороги: подразбиваем и слегка изгибаем шумом
	for r in ROADS:
		var pts: Array = []
		for i in r.size() - 1:
			var a: Vector2 = r[i]; var b: Vector2 = r[i + 1]
			var n := maxi(1, int(a.distance_to(b) / 30.0))
			for k in n:
				var t := float(k) / n
				var p := a.lerp(b, t)
				if k > 0 or i > 0:
					var side := (b - a).normalized().orthogonal()
					p += side * _warp.get_noise_2d(p.x * 3.0, p.y * 3.0) * 22.0
				pts.append(p)
		pts.append(r[r.size() - 1])
		for i in pts.size() - 1: _roads.append([pts[i], pts[i + 1]])
	_town_h.clear()
	for t in TOWNS: _town_h.append(_raw_height(t.pos.x, t.pos.y))

# ---------- биомы ----------
static func _warped(x: float, z: float) -> Vector2:
	return Vector2(x + _warp.get_noise_2d(x, z) * 140.0, z + _warp.get_noise_2d(z + 500.0, x - 300.0) * 140.0)

## Индекс биома в точке (ближайшее «зерно» с искажением границ)
static func biome_at(x: float, z: float) -> int:
	init()
	var p := _warped(x, z)
	var best := 0; var bd := INF
	for i in BIOMES.size():
		var d := p.distance_squared_to(BIOMES[i].seed)
		if d < bd: bd = d; best = i
	return best

## Мягкие веса биомов (сумма 1) — для плавных переходов рельефа и земли
static func biome_weights(x: float, z: float) -> PackedFloat32Array:
	init()
	var p := _warped(x, z)
	var w := PackedFloat32Array(); w.resize(BIOMES.size())
	var dmin := INF
	var ds := []
	for i in BIOMES.size():
		var d := p.distance_to(BIOMES[i].seed); ds.append(d); dmin = minf(dmin, d)
	var tot := 0.0
	for i in BIOMES.size():
		var v := exp(-(float(ds[i]) - dmin) / 38.0)
		w[i] = v; tot += v
	for i in BIOMES.size(): w[i] /= tot
	return w

static func biome_name(i: int) -> String: return BIOMES[i].name
static func level_range(i: int) -> Array: return BIOMES[i].lv

## Уровень мобов в точке: от нижней границы у города зоны к верхней на краю
static func level_at(x: float, z: float) -> int:
	var b := biome_at(x, z)
	var lv: Array = BIOMES[b].lv
	var tp: Vector2 = TOWNS[b].pos
	var t := clampf(Vector2(x, z).distance_to(tp) / 420.0, 0.0, 1.0)
	return clampi(int(round(lerpf(float(lv[0]), float(lv[1]), t))), int(lv[0]), int(lv[1]))

# ---------- дороги, города ----------
## Отрезки дорог рядом с прямоугольником (для быстрого расчёта чанка)
static func roads_near(r: Rect2) -> Array:
	init()
	var g := r.grow(40.0)
	var out := []
	for s in _roads:
		var a: Vector2 = s[0]; var b: Vector2 = s[1]
		if Rect2(a, Vector2.ZERO).expand(b).intersects(g): out.append(s)
	return out

static func pois_near(r: Rect2) -> Array:
	var g := r.grow(45.0)
	var out := []
	for p in POIS: if g.has_point(p.pos): out.append(p)
	return out

static func road_dist(x: float, z: float, segs = null) -> float:
	init()
	var p := Vector2(x, z)
	var best := INF
	for s in (segs if segs != null else _roads):
		var a: Vector2 = s[0]; var b: Vector2 = s[1]
		# быстрый отсев по рамке
		if p.x < minf(a.x, b.x) - 40 or p.x > maxf(a.x, b.x) + 40 or p.y < minf(a.y, b.y) - 40 or p.y > maxf(a.y, b.y) + 40: continue
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best

static func nearest_town(x: float, z: float) -> int:
	var best := 0; var bd := INF
	for i in TOWNS.size():
		var d := Vector2(x, z).distance_squared_to(TOWNS[i].pos)
		if d < bd: bd = d; best = i
	return best

static func town_dist(x: float, z: float) -> float:
	return Vector2(x, z).distance_to(TOWNS[nearest_town(x, z)].pos)

static func poi_dist(x: float, z: float) -> float:
	var best := INF
	for p in POIS: best = minf(best, Vector2(x, z).distance_to(p.pos))
	return best

# ---------- высота ----------
static func _raw_height(x: float, z: float) -> float:
	var w := biome_weights(x, z)
	var n := _noise.get_noise_2d(x, z)
	var h := 0.0
	for i in BIOMES.size():
		if w[i] < 0.002: continue
		var amp: float = BIOMES[i].amp
		var hb := 0.0
		match BIOMES[i].id:
			"snow": hb = (1.0 - absf(n)) * amp - amp * 0.35 + _noise.get_noise_2d(x * 2.3, z * 2.3) * 6.0
			"desert": hb = n * amp + sin(x * 0.03 + _warp.get_noise_2d(x, z) * 4.0) * 2.0
			"swamp": hb = n * amp - 0.5
			_: hb = n * amp
		h += hb * w[i]
	return h + _detail.get_noise_2d(x, z) * 0.35

static func height(x: float, z: float, segs = null, pois = null) -> float:
	init()
	var h := _raw_height(x, z)
	# дороги сглажены
	var rd := road_dist(x, z, segs if segs != null else roads_near(Rect2(x, z, 0, 0)))
	if rd < 16.0:
		var k := 1.0 - smoothstep(5.0, 16.0, rd)
		h = lerpf(h, _noise.get_noise_2d(x, z) * 2.0 + h * 0.35, k * 0.75)
	# города — ровные площадки
	var ti := nearest_town(x, z)
	var td := Vector2(x, z).distance_to(TOWNS[ti].pos)
	if td < TOWN_R + 34.0:
		h = lerpf(h, _town_h[ti], 1.0 - smoothstep(TOWN_R, TOWN_R + 34.0, td))
	# точки интереса тоже сглажены (арены, постройки)
	for p in (pois if pois != null else POIS):
		var pd := Vector2(x, z).distance_to(p.pos)
		if pd < 40.0:
			var ph := _raw_height(p.pos.x, p.pos.y)
			h = lerpf(h, ph, 1.0 - smoothstep(18.0, 40.0, pd))
	# граница мира — горы
	var e := maxf(absf(x), absf(z))
	if e > EDGE: h += smoothstep(EDGE, HALF, e) * 55.0 * (0.8 + 0.4 * _noise.get_noise_2d(x * 3.0, z * 3.0))
	return h

## Веса 7 слоёв земли (+ яркость в .a): трава/лесная подстилка/дорога/песок/грязь/снег/скала
static func layer_weights(x: float, z: float, slope: float, w: PackedFloat32Array, segs = null) -> PackedFloat32Array:
	var out := PackedFloat32Array(); out.resize(8)
	var bright := 0.0
	var dn := _detail.get_noise_2d(x * 0.6, z * 0.6)
	for i in BIOMES.size():
		if w[i] < 0.002: continue
		var b: Dictionary = BIOMES[i]
		bright += float(b.bright) * w[i]
		match b.id:
			"meadows":
				out[L.GRASS] += w[i] * (0.8 + 0.2 * dn); out[L.FOREST] += w[i] * clampf(0.2 - 0.2 * dn, 0, 1)
			"forest":
				out[L.FOREST] += w[i] * 0.7; out[L.GRASS] += w[i] * 0.3
			"desert":
				out[L.SAND] += w[i] * (0.85 + 0.15 * dn); out[L.ROCK] += w[i] * clampf(-dn * 0.4, 0, 0.3)
			"swamp":
				out[L.MUD] += w[i] * (0.65 + 0.3 * dn); out[L.GRASS] += w[i] * clampf(0.35 - 0.3 * dn, 0, 1)
			"snow":
				out[L.SNOW] += w[i]
			"ruins":
				out[L.FOREST] += w[i] * 0.55; out[L.ROCK] += w[i] * 0.3; out[L.MUD] += w[i] * 0.15
	# склоны — скала (на хребте снег держится дольше)
	var rock := smoothstep(0.42, 0.7, slope)
	if rock > 0.0:
		for k in 7: out[k] *= (1.0 - rock)
		out[L.ROCK] += rock
	# дороги и площади городов
	var rd := road_dist(x, z, segs if segs != null else roads_near(Rect2(x, z, 0, 0)))
	var road := 1.0 - smoothstep(3.2, 5.5, rd + dn * 1.2)
	var td := town_dist(x, z)
	road = maxf(road, (1.0 - smoothstep(TOWN_R - 14.0, TOWN_R, td)) * (0.55 + 0.4 * dn))
	if road > 0.0:
		for k in 7: out[k] *= (1.0 - road)
		out[L.ROAD] += road
	out[7] = bright
	return out
