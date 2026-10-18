class_name TreeGen
## v0.6.0: процедурные реалистичные деревья — ствол и ветви (кольца с корой ambientCG, плавный изгиб, сужение,
## корневой наплыв) + карточки листвы/хвои с альфа-срезом и «объёмными» нормалями кроны (свет ложится как на шар/конус).
## Цвет вершин: R — вес ветра (у корня 0), G — затенение внутри кроны, B — разброс оттенка.
## Виды: oak (дуб/лиственное), birch, pine (сосна), fir (ель), dead (сухое), swamp (кривое топяное), autumn.
## lod 1 — облегчённый вариант для дальних чанков (меньше граней и карточек).

static var _cache := {}
static var _mats := {}

const KINDS := {
	"oak": {"bark": "bark_oak", "card": "leaf_card", "h": [7.0, 10.0], "r": 0.32, "tint": Color(0.92, 1.0, 0.9), "tint2": Color(1.1, 1.05, 0.8)},
	"birch": {"bark": "bark_birch", "card": "leaf_card", "h": [8.0, 11.0], "r": 0.2, "tint": Color(1.05, 1.1, 0.85), "tint2": Color(1.2, 1.15, 0.75)},
	"autumn": {"bark": "bark_oak", "card": "leaf_card_autumn", "h": [6.5, 9.0], "r": 0.3, "tint": Color(1.0, 0.95, 0.9), "tint2": Color(1.15, 0.8, 0.6)},
	"pine": {"bark": "bark_pine", "card": "pine_card", "h": [12.0, 16.0], "r": 0.3, "tint": Color(1.25, 1.35, 1.1), "tint2": Color(1.4, 1.4, 1.05)},
	"fir": {"bark": "bark_pine", "card": "needle_card", "h": [9.0, 14.0], "r": 0.28, "tint": Color(1.3, 1.45, 1.25), "tint2": Color(1.4, 1.5, 1.2)},
	"snowfir": {"bark": "bark_pine", "card": "needle_card", "h": [8.0, 12.0], "r": 0.26, "tint": Color(1.2, 1.35, 1.3), "tint2": Color(1.3, 1.45, 1.35), "snow": 0.35},
	"dead": {"bark": "bark_dry", "card": "twig_card", "h": [6.0, 9.0], "r": 0.28, "tint": Color(0.9, 0.85, 0.8), "tint2": Color(0.8, 0.75, 0.7)},
	"swamp": {"bark": "bark_oak", "card": "twig_card", "h": [6.0, 8.5], "r": 0.34, "tint": Color(0.7, 0.75, 0.6), "tint2": Color(0.6, 0.62, 0.5), "moss": 0.8, "leaves": "leaf_card"},
}

static func mesh(kind: String, variant: int, lod := 0) -> ArrayMesh:
	var key := "%s_%d_%d" % [kind, variant, lod]
	if not _cache.has(key):
		_cache[key] = _build(kind, variant, lod)
	return _cache[key]

static func bark_material(kind: String) -> ShaderMaterial:
	var k: Dictionary = KINDS[kind]
	var mk := "bark_" + kind
	if not _mats.has(mk):
		var m := ShaderMaterial.new(); m.shader = load("res://assets/shaders/real_bark.gdshader")
		m.set_shader_parameter("albedo_tex", load("res://assets/real/tex/%s_d.jpg" % k.bark))
		m.set_shader_parameter("normal_tex", load("res://assets/real/tex/%s_n.jpg" % k.bark))
		m.set_shader_parameter("snow", k.get("snow", 0.0))
		m.set_shader_parameter("moss", k.get("moss", 0.0))
		m.set_shader_parameter("wind_on", 1.0 if Game.quality >= 1 else 0.0)
		_mats[mk] = m
	return _mats[mk]

static func leaf_material(kind: String, card := "") -> ShaderMaterial:
	var k: Dictionary = KINDS[kind]
	if card == "": card = k.card
	var mk := "leaf_%s_%s" % [kind, card]
	if not _mats.has(mk):
		var m := ShaderMaterial.new(); m.shader = load("res://assets/shaders/real_foliage.gdshader")
		m.set_shader_parameter("albedo_tex", load("res://assets/real/foliage/%s.png" % card))
		var t: Color = k.tint; var t2: Color = k.tint2
		if card != k.card: t = Color(0.75, 0.85, 0.6); t2 = Color(0.85, 0.8, 0.5)
		m.set_shader_parameter("tint", Vector3(t.r, t.g, t.b))
		m.set_shader_parameter("tint_var", Vector3(t2.r, t2.g, t2.b))
		m.set_shader_parameter("snow", k.get("snow", 0.0))
		m.set_shader_parameter("wind_on", 1.0 if Game.quality >= 1 else 0.0)
		_mats[mk] = m
	return _mats[mk]

## ветер вкл/выкл (энергосбережение) — для всех материалов деревьев
static func set_wind(on: bool) -> void:
	for k in _mats: (_mats[k] as ShaderMaterial).set_shader_parameter("wind_on", 1.0 if on else 0.0)

# ---------------- построение ----------------
class Ctx:
	var bark := SurfaceTool.new()
	var leaf := SurfaceTool.new()
	var leaf2 := SurfaceTool.new()   # вторые карточки (листья на топяном дереве)
	var has_leaf2 := false
	var nleaf := 0
	var rng := RandomNumberGenerator.new()
	var sides := 8
	var card_mul := 1.0
	var crown_c := Vector3.ZERO
	var crown_r := Vector3.ONE
	var height := 8.0

static func _build(kind: String, variant: int, lod: int) -> ArrayMesh:
	var k: Dictionary = KINDS[kind]
	var c := Ctx.new()
	c.rng.seed = hash(kind) ^ (variant * 7919 + 13)
	c.bark.begin(Mesh.PRIMITIVE_TRIANGLES); c.leaf.begin(Mesh.PRIMITIVE_TRIANGLES); c.leaf2.begin(Mesh.PRIMITIVE_TRIANGLES)
	c.sides = 8 if lod == 0 else 5
	c.card_mul = 1.0 if lod == 0 else 0.5
	var h: float = c.rng.randf_range(k.h[0], k.h[1])
	c.height = h
	var r0: float = k.r * c.rng.randf_range(0.85, 1.15)
	match kind:
		"pine", "fir", "snowfir": _conifer(c, kind, h, r0)
		"dead", "swamp": _dead(c, kind, h, r0)
		_: _broadleaf(c, kind, h, r0)
	var am := ArrayMesh.new()
	c.bark.generate_tangents()
	c.bark.commit(am)
	am.surface_set_material(0, bark_material(kind))
	var si := 1
	if c.nleaf > 0:
		c.leaf.commit(am)
		am.surface_set_material(si, leaf_material(kind)); si += 1
	if c.has_leaf2:
		c.leaf2.commit(am)
		am.surface_set_material(si, leaf_material(kind, k.get("leaves", "leaf_card")))
	return am

## ветвь как трубка вдоль ломаной pts с радиусами rs; wind — вес ветра на концах [начало, конец]
static func _tube(c: Ctx, pts: Array, rs: Array, wind: Vector2, uv_rep: float) -> void:
	var n := c.sides
	var rings := []
	var vlen := 0.0
	for i in pts.size():
		var p: Vector3 = pts[i]
		var dir: Vector3 = ((pts[mini(i + 1, pts.size() - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)).normalized()
		var side := dir.cross(Vector3.FORWARD if absf(dir.z) < 0.9 else Vector3.RIGHT).normalized()
		var up := side.cross(dir).normalized()
		if i > 0: vlen += (p - (pts[i - 1] as Vector3)).length()
		var ring := []
		for j in n + 1:
			var a := TAU * j / n
			var off := (side * cos(a) + up * sin(a))
			ring.append([p + off * float(rs[i]), off, Vector2(float(j) / n * uv_rep, vlen / (TAU * maxf(float(rs[0]), 0.05)) * uv_rep * 0.5)])
		rings.append(ring)
	for i in pts.size() - 1:
		var t0 := float(i) / (pts.size() - 1); var t1 := float(i + 1) / (pts.size() - 1)
		for j in n:
			var q := [rings[i][j], rings[i][j + 1], rings[i + 1][j + 1], rings[i + 1][j]]
			var ts := [t0, t0, t1, t1]
			for idx in [0, 1, 2, 0, 2, 3]:
				var v: Array = q[idx]
				var w := lerpf(wind.x, wind.y, ts[idx])
				c.bark.set_color(Color(w, 0.6 + 0.4 * ts[idx], 0.0))
				c.bark.set_normal(v[1]); c.bark.set_uv(v[2]); c.bark.add_vertex(v[0])

## изогнутая линия от p0 по направлению dir длиной len (шагов seg), с отклонением и тяготением gravity
static func _path(c: Ctx, p0: Vector3, dir: Vector3, length: float, seg: int, wobble: float, gravity: float) -> Array:
	var pts := [p0]
	var d := dir.normalized()
	var p := p0
	for i in seg:
		d = (d + Vector3(c.rng.randf_range(-wobble, wobble), -gravity + c.rng.randf_range(-wobble, wobble) * 0.5, c.rng.randf_range(-wobble, wobble))).normalized()
		p += d * (length / seg)
		pts.append(p)
	return pts

## карточка: центр p, плоскость (u — ширина, v — «рост» карточки), size; нормаль — от центра кроны
static func _card(c: Ctx, st: SurfaceTool, p: Vector3, u: Vector3, v: Vector3, w: float, hgt: float, wind: float, shade: float, anchor_bottom := true) -> void:
	var hue := c.rng.randf()
	if st == c.leaf: c.nleaf += 1
	var base := p - v * (0.0 if anchor_bottom else hgt * 0.5)
	var corners := [base - u * w * 0.5, base + u * w * 0.5, base + u * w * 0.5 + v * hgt, base - u * w * 0.5 + v * hgt]
	var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	var face := u.cross(v).normalized()
	for idx in [0, 1, 2, 0, 2, 3]:
		var q: Vector3 = corners[idx]
		var rel := (q - c.crown_c) / c.crown_r
		var nrm := (rel.normalized() * 0.8 + face * 0.2 * (1.0 if face.dot(rel) >= 0 else -1.0)).normalized()
		var outer := clampf(rel.length(), 0.0, 1.2)
		st.set_color(Color(wind * (0.7 + 0.3 * float(idx >= 2)), clampf(shade * (0.55 + 0.5 * outer), 0.0, 1.0), hue))
		st.set_normal(nrm); st.set_uv(uvs[idx]); st.add_vertex(q)

static func _radii(r0: float, r1: float, n: int, flare := 0.0) -> Array:
	var out := []
	for i in n:
		var t := float(i) / (n - 1)
		out.append(lerpf(r0, r1, pow(t, 0.8)) * (1.0 + flare * pow(1.0 - t, 6.0)))
	return out

static func _rand_perp(c: Ctx, d: Vector3) -> Vector3:
	var a := d.cross(Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT).normalized()
	return a.rotated(d, c.rng.randf() * TAU)

static func _broadleaf(c: Ctx, kind: String, h: float, r0: float) -> void:
	var trunk_h := h * c.rng.randf_range(0.42, 0.55)
	var tpts := _path(c, Vector3.ZERO, Vector3.UP, h * 0.92, 9, 0.06, 0.0)
	_tube(c, tpts, _radii(r0, r0 * 0.25, tpts.size(), 0.9), Vector2(0.0, 0.25), 2.0)
	c.crown_c = Vector3(0, trunk_h + (h - trunk_h) * 0.5, 0)
	c.crown_r = Vector3(h * 0.38, (h - trunk_h) * 0.62, h * 0.38)
	var nb := c.rng.randi_range(6, 9)
	var cards := []   # [pos, dir]
	for b in nb:
		var t := c.rng.randf_range(0.45, 0.9)
		var ti := int(t * (tpts.size() - 1))
		var p0: Vector3 = tpts[ti]
		var az := b * 2.39996 + c.rng.randf_range(-0.3, 0.3)
		var tilt := c.rng.randf_range(0.6, 1.05) * (1.15 - t * 0.5)
		var dir := Vector3(cos(az) * sin(tilt), cos(tilt), sin(az) * sin(tilt))
		var bl := h * c.rng.randf_range(0.32, 0.45) * (1.2 - t * 0.5)
		var bpts := _path(c, p0, dir, bl, 4, 0.18, -0.05)
		var br := r0 * c.rng.randf_range(0.35, 0.5) * (1.1 - t * 0.5)
		_tube(c, bpts, _radii(br, br * 0.2, bpts.size()), Vector2(0.25, 0.8), 1.0)
		# побеги
		for s in c.rng.randi_range(2, 3):
			var si := c.rng.randi_range(1, bpts.size() - 2)
			var sd: Vector3 = (dir + _rand_perp(c, dir) * 0.9 + Vector3.UP * 0.3).normalized()
			var spts := _path(c, bpts[si], sd, bl * c.rng.randf_range(0.35, 0.55), 2, 0.25, -0.05)
			if c.sides > 5: _tube(c, spts, _radii(br * 0.35, br * 0.08, spts.size()), Vector2(0.6, 1.0), 1.0)
			cards.append([spts[-1], sd]); cards.append([spts[1], sd])
		cards.append([bpts[-1], dir]); cards.append([bpts[-2], dir])
	# крона: вокруг точек ветвей — по 3 пересекающиеся карточки, плюс заполнение объёма кроны
	var fill := int(18 * c.card_mul)
	for i in fill:
		var v := Vector3(c.rng.randf_range(-1, 1), c.rng.randf_range(-0.7, 1), c.rng.randf_range(-1, 1)).normalized() * c.rng.randf_range(0.35, 0.9)
		cards.append([c.crown_c + v * c.crown_r, v.normalized()])
	var n := 0
	for cd in cards:
		if c.card_mul < 1.0 and n % 2 == 1: n += 1; continue
		n += 1
		var p: Vector3 = cd[0]
		var sz := h * c.rng.randf_range(0.2, 0.28) * (1.0 / sqrt(c.card_mul))
		for q in 2:
			var vdir: Vector3 = ((cd[1] as Vector3) + Vector3(0, 0.6, 0) + _rand_perp(c, Vector3.UP) * 0.5).normalized()
			var u := vdir.cross(Vector3.UP if absf(vdir.y) < 0.95 else Vector3.RIGHT).normalized().rotated(vdir, q * PI * 0.5 + c.rng.randf_range(-0.4, 0.4))
			_card(c, c.leaf, p, u, vdir, sz, sz, 0.9, 1.0, false)

static func _conifer(c: Ctx, kind: String, h: float, r0: float) -> void:
	var tpts := _path(c, Vector3.ZERO, Vector3.UP, h, 10, 0.02, 0.0)
	_tube(c, tpts, _radii(r0, r0 * 0.08, tpts.size(), 0.7), Vector2(0.0, 0.35), 2.0)
	var fir := kind != "pine"
	var start := h * (0.18 if fir else 0.5)
	c.crown_c = Vector3(0, (start + h) * 0.5, 0)
	c.crown_r = Vector3(h * (0.28 if fir else 0.25), (h - start) * 0.6, h * (0.28 if fir else 0.25))
	var y := start
	var whorl := 0
	var step := (0.42 if fir else 0.6) / sqrt(c.card_mul)
	while y < h * 0.97:
		var t := (y - start) / (h - start)   # 0 низ кроны → 1 макушка
		var reach := h * (0.3 if fir else 0.26) * (1.0 - t) * (1.0 - t * 0.15) + 0.4
		var nbr := (7 if fir else 6) if c.card_mul >= 1.0 else (5 if fir else 4)
		for b in nbr:
			var az := b * TAU / nbr + whorl * 0.7 + c.rng.randf_range(-0.2, 0.2)
			var droop := (0.25 if fir else 0.05) - t * 0.35
			var dir := Vector3(cos(az), -droop + c.rng.randf_range(-0.08, 0.08), sin(az)).normalized()
			var p0 := Vector3(0, y, 0)
			var bpts := _path(c, p0, dir, reach, 2, 0.06, 0.06 if fir else 0.0)
			if c.sides > 5 and t < 0.75: _tube(c, bpts, _radii(r0 * 0.18 * (1.0 - t), 0.015, bpts.size()), Vector2(0.2, 0.7), 1.0)
			# лапа: карточка вдоль ветви почти горизонтально + наклонённая копия
			var along: Vector3 = ((bpts[-1] as Vector3) - p0).normalized()
			var u := along.cross(Vector3.UP).normalized()
			var flat := along
			_card(c, c.leaf, p0 + along * 0.05, u.rotated(along, c.rng.randf_range(-0.25, 0.25)), flat, reach * (0.75 if fir else 0.95), reach * 1.05, 0.8, 0.7 + 0.3 * t)
			if c.card_mul >= 1.0 and b % 2 == 0:
				_card(c, c.leaf, p0 + along * 0.05, u.rotated(along, 1.2 + c.rng.randf_range(-0.3, 0.3)), flat, reach * 0.6, reach * 0.95, 0.8, 0.5 + 0.4 * t)
		y += step * c.rng.randf_range(0.8, 1.2) * (1.0 - 0.35 * t)
		whorl += 1
	# макушка
	var top := Vector3(0, h * 0.93, 0)
	for q in 2:
		var u := Vector3.RIGHT.rotated(Vector3.UP, q * PI * 0.5)
		_card(c, c.leaf, top, u, Vector3.UP, h * 0.12, h * 0.14, 0.9, 1.0)

static func _dead(c: Ctx, kind: String, h: float, r0: float) -> void:
	var lean := Vector3(c.rng.randf_range(-0.2, 0.2), 1, c.rng.randf_range(-0.2, 0.2)).normalized()
	var tpts := _path(c, Vector3.ZERO, lean, h * 0.85, 8, 0.12 if kind == "swamp" else 0.07, 0.0)
	_tube(c, tpts, _radii(r0, r0 * 0.22, tpts.size(), 1.3 if kind == "swamp" else 0.8), Vector2(0.0, 0.2), 2.0)
	c.crown_c = tpts[-2]; c.crown_r = Vector3(h * 0.4, h * 0.3, h * 0.4)
	for b in c.rng.randi_range(5, 8):
		var t := c.rng.randf_range(0.35, 0.92)
		var p0: Vector3 = tpts[int(t * (tpts.size() - 1))]
		var az := b * 2.39996
		var tilt := c.rng.randf_range(0.7, 1.3)
		var dir := Vector3(cos(az) * sin(tilt), cos(tilt), sin(az) * sin(tilt))
		var bl := h * c.rng.randf_range(0.25, 0.4) * (1.1 - t * 0.4)
		var bpts := _path(c, p0, dir, bl, 4, 0.3, 0.08 if kind == "swamp" else -0.02)
		var br := r0 * c.rng.randf_range(0.3, 0.42)
		_tube(c, bpts, _radii(br, br * 0.15, bpts.size()), Vector2(0.15, 0.6), 1.0)
		for s in 2:
			var si := c.rng.randi_range(1, bpts.size() - 2)
			var sd: Vector3 = (dir + _rand_perp(c, dir)).normalized()
			var spts := _path(c, bpts[si], sd, bl * 0.4, 2, 0.35, 0.0)
			if c.sides > 5: _tube(c, spts, _radii(br * 0.3, br * 0.06, spts.size()), Vector2(0.5, 0.9), 1.0)
			# голые веточки
			var u := _rand_perp(c, sd)
			_card(c, c.leaf, spts[-1], u, sd, bl * 0.5, bl * 0.5, 0.8, 0.8, false)
			if kind == "swamp" and c.rng.randf() < 0.45:
				c.has_leaf2 = true
				_card(c, c.leaf2, spts[-1], u.rotated(sd, 1.3), (sd + Vector3.UP * 0.4).normalized(), bl * 0.45, bl * 0.45, 0.9, 0.7, false)
