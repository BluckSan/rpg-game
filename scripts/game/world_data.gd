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

# ---------- малые точки интереса (v0.5.1): каждые ~100–150 м ----------
## Лагеря, повозки, святилища, фермы, руины, могилы, сторожевые башни — детерминированно по сетке 125 м.
const MINOR_STEP := 125.0
const MINOR_KINDS := {
	"meadows": ["farm", "camp", "cart", "shrine", "woodpile", "ruin"],
	"forest": ["camp", "woodpile", "shrine", "shrooms", "ruin", "hunters"],
	"desert": ["cart", "ruin", "bones", "camp", "obelisk"],
	"swamp": ["ruin", "graves", "shrine", "boat", "shrooms"],
	"snow": ["camp", "tower", "cart", "shrine"],
	"ruins": ["ruin", "graves", "obelisk", "tower", "siege"],
}
const MINOR_NAMES := {
	"farm": "Заброшенная ферма", "camp": "Стоянка путников", "cart": "Разбитая повозка", "shrine": "Придорожное святилище",
	"woodpile": "Делянка лесоруба", "ruin": "Древние развалины", "shrooms": "Грибной круг", "hunters": "Охотничий лагерь",
	"bones": "Кости великана", "obelisk": "Одинокий обелиск", "graves": "Забытые могилы", "boat": "Старая пристань",
	"tower": "Сторожевая башня", "siege": "Брошенные осадные машины",
}
static var _minor: Array = []

static func minor_pois() -> Array:
	if not _minor.is_empty(): return _minor
	init()
	var rng := RandomNumberGenerator.new()
	var n := int(EDGE / MINOR_STEP)
	for gz in range(-n, n + 1):
		for gx in range(-n, n + 1):
			rng.seed = hash(Vector2i(gx, gz)) ^ 0x31337
			var p := Vector2(gx * MINOR_STEP + rng.randf_range(-38, 38), gz * MINOR_STEP + rng.randf_range(-38, 38))
			if maxf(absf(p.x), absf(p.y)) > EDGE - 40: continue
			if town_dist(p.x, p.y) < TOWN_R + 45 or poi_dist(p.x, p.y) < 60: continue
			var rd := road_dist(p.x, p.y)
			if rd < 9.0: p += (p - Vector2(gx * MINOR_STEP, gz * MINOR_STEP)).normalized() * 12.0
			if road_dist(p.x, p.y) < 8.0: continue
			var b := biome_at(p.x, p.y)
			var kinds: Array = MINOR_KINDS[BIOMES[b].id]
			var k: String = kinds[rng.randi() % kinds.size()]
			_minor.append({"id": "m%d_%d" % [gx, gz], "kind": k, "name": MINOR_NAMES[k], "pos": p, "biome": b,
				"yaw": rng.randf() * 360.0, "seed": rng.randi()})
	return _minor

static func minor_near(r: Rect2) -> Array:
	var g := r.grow(20.0)
	var out := []
	for m in minor_pois(): if g.has_point(m.pos): out.append(m)
	return out

## Раскладка малой точки: [ключ пропа, смещение XZ, поворот°, масштаб, твёрдый, огонь]
static func minor_layout(m: Dictionary) -> Array:
	var rng := RandomNumberGenerator.new(); rng.seed = int(m.seed)
	var L := []
	var ring := func(key: String, n: int, r: float, s: float, solid := true, a0 := 0.0):
		for i in n:
			var a := a0 + TAU * i / n
			L.append([key, Vector2(cos(a), sin(a)) * r, rad_to_deg(-a) + 90.0 + rng.randf_range(-8, 8), s, solid, false])
	var put := func(key: String, x: float, z: float, yaw: float, s: float, solid := true, fire := false):
		L.append([key, Vector2(x, z), yaw, s, solid, fire])
	match String(m.kind):
		"camp", "hunters":
			put.call("survival_campfire-pit", 0, 0, 0, 4.0, false, true)
			put.call("survival_tent-canvas" if m.kind == "camp" else "nature_tent_smallOpen", 4.5, -2.5, 200, 5.5)
			put.call("nature_tent_detailedOpen", -4.0, -3.0, 150, 5.0)
			put.call("survival_bedroll", 2.0, 2.5, 30, 3.0, false)
			put.call("survival_box", -3.0, 3.0, 20, 3.0); put.call("survival_barrel", -3.8, 2.2, 0, 3.0)
			put.call("nature_log", 0, 3.2, 90, 3.2, false)
			if m.kind == "hunters": put.call("survival_workbench", 5, 3, -40, 3.2); put.call("survival_resource-wood", 6, 1, 10, 3.0)
			else: put.call("survival_signpost-single", 7, 0, 90, 3.5)
		"cart":
			put.call("town_cart-high", 0, 0, rng.randf() * 360, 3.2)
			put.call("town_wheel", 2.4, 1.2, 80, 3.0, false)
			put.call("survival_box-open", -2.2, 1.6, 30, 3.0); put.call("survival_barrel-open", -1.8, -1.8, 0, 3.0)
			put.call("survival_box", 2.0, -2.2, 60, 2.8); put.call("graveyard_debris-wood", 0.5, 2.6, 15, 3.0, false)
		"farm":
			for i in 6: put.call("nature_fence_planks", -7.5 + i * 3.0, -6.0, 0, 3.0)
			for i in 4: put.call("nature_fence_planks", -9.0, -4.5 + i * 3.0, 90, 3.0)
			for ix in 4:
				for iz in 3: put.call("nature_crops_wheatStageB" if (ix + iz) % 3 else "nature_crops_cornStageD", -5.5 + ix * 3.0, -3 + iz * 3.0, 0, 3.0, false)
			put.call("graveyard_hay-bale", 5, 5, 20, 3.2); put.call("graveyard_hay-bale-bundled", 7, 3.5, 70, 3.0)
			put.call("nature_crop_pumpkin", 3, 6, 0, 3.0, false); put.call("survival_bucket", 1.5, 5.5, 0, 3.0, false)
		"shrine":
			put.call("nature_statue_obelisk" if rng.randf() < 0.5 else "nature_statue_head", 0, 0, 180, 4.2)
			ring.call("graveyard_candle-multiple", 4, 2.2, 3.0, false, 0.4)
			put.call("graveyard_altar-stone", 0, 2.4, 0, 3.0)
			ring.call("nature_flower_purpleB", 6, 3.6, 2.6, false)
		"woodpile":
			put.call("nature_log_stackLarge", 0, 0, 20, 3.4); put.call("nature_log_stack", 3.5, 1.5, 70, 3.2)
			for i in 4: put.call("nature_stump_roundDetailed", -4 + i * 2.6, -3.5 + (i % 2) * 1.6, i * 40, 3.4, false)
			put.call("survival_tool-axe", 1.2, -1.8, 30, 3.0, false); put.call("survival_resource-wood", -2.5, 2.4, 0, 3.0)
		"ruin":
			for i in 5:
				var a := TAU * i / 5.0
				put.call("graveyard_stone-wall-damaged" if i % 2 else "nature_statue_columnDamaged", cos(a) * 6.5, sin(a) * 6.5, rad_to_deg(-a) + 90, 4.4)
			put.call("graveyard_pillar-large", 0, 0, 0, 3.6); put.call("castle_rocks-small", 2.5, 2.0, 40, 3.5, false)
			put.call("graveyard_debris-wood", -2.4, 1.5, 0, 3.0, false); put.call("nature_rock_smallFlatA", 1.5, -3.0, 0, 3.0, false)
		"shrooms":
			ring.call("nature_mushroom_redTall" if m.biome != 3 else "nature_mushroom_tanTall", 9, 4.5, 3.6, false)
			put.call("nature_mushroom_redGroup", 0, 0, 0, 4.5, false); put.call("nature_stump_oldTall", 1.5, 1.0, 0, 3.6)
		"bones":
			for i in 7: put.call("graveyard_rocks-tall" if i % 2 else "nature_rock_tallE", -9 + i * 3.0, sin(i * 0.9) * 2.5, i * 30, 3.0 + (3 - absi(i - 3)) * 0.4)
			put.call("graveyard_urn-round", 3, 4, 0, 3.0, false); put.call("graveyard_coffin-old", -2, 4.5, 20, 3.0, false)
		"obelisk":
			put.call("nature_statue_obelisk", 0, 0, 0, 6.5)
			ring.call("nature_stone_smallC", 6, 3.5, 3.0, false)
			put.call("graveyard_fire-basket", 2.5, 2.5, 0, 3.0, true, true)
		"graves":
			for i in 8: put.call(["graveyard_gravestone-cross", "graveyard_gravestone-round", "graveyard_grave", "graveyard_gravestone-broken"][i % 4], -6 + (i % 4) * 4.0, -2 + (i / 4) * 4.5, rng.randf_range(-15, 15), 3.2, false)
			put.call("graveyard_lightpost-single", 7, 0, 0, 3.4); put.call("graveyard_iron-fence-damaged", 0, -5.5, 0, 3.4)
			put.call("graveyard_pine-fall-crooked", -9, 4, 0, 4.0); put.call("graveyard_crypt-small", 0, 7, 180, 3.4)
		"boat":
			for i in 4: put.call("town_planks", 0, i * 2.2, 0, 3.0, false)
			put.call("nature_canoe", 2.4, 6, 20, 3.4, false); put.call("survival_barrel", -1.8, 1.0, 0, 3.0)
			put.call("nature_lily_small", 3, 3, 0, 3.0, false); put.call("survival_campfire-stand", -3, -1.5, 0, 3.0, false, true)
		"tower":
			put.call("castle_tower-hexagon-base", 0, 0, 0, 3.4); put.call("castle_flag-banner-long", 3.5, 0, 0, 3.4)
			put.call("survival_box-large", -3.2, 2.0, 15, 3.0); put.call("graveyard_fire-basket", 2.5, 3.0, 0, 3.0, true, true)
			put.call("castle_stairs-stone", -3.0, -2.5, 90, 3.0)
		"siege":
			put.call("castle_siege-ballista-demolished", 0, 0, rng.randf() * 360, 3.6)
			put.call("castle_siege-ram-demolished", 6, 3, rng.randf() * 360, 3.6)
			put.call("castle_rocks-small", -4, 3, 0, 3.4, false); put.call("graveyard_debris-wood", 3, -3, 40, 3.2, false)
	return L
