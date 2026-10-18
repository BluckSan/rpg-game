class_name HouseGen
## v0.6.0: реалистичный дом вместо блоков Kenney — каменный цоколь, стены (штукатурка с фахверком или кладка),
## двускатная крыша со свесами (черепица/солома), фронтоны, дверь, окна со ставнями, труба.
## Поверхности по материалам (трипланарный PBR Real.surf_material), меш кэшируется по стилю. Дверь — грань +Z.
## style: 0 — фахверк + черепица, 1 — камень + черепица, 2 — штукатурка + солома
static var _cache := {}
const W := 4.3   # ширина (X)
const D := 4.3   # глубина (Z)
const WALL_H := 3.0
const BASE_H := 0.45
const RIDGE := 2.1

class Parts:
	var st := {}   # слой → SurfaceTool
	func get_st(layer: int) -> SurfaceTool:
		if not st.has(layer):
			var s := SurfaceTool.new(); s.begin(Mesh.PRIMITIVE_TRIANGLES); st[layer] = s
		return st[layer]

static func mesh(style: int) -> ArrayMesh:
	if _cache.has(style): return _cache[style]
	var p := Parts.new()
	var wall_l: int = Real.SURF.stone if style == 1 else Real.SURF.plaster
	var roof_l: int = Real.SURF.thatch if style == 2 else Real.SURF.roof
	var beam: int = Real.SURF.beam
	var top := BASE_H + WALL_H
	# цоколь (уходит в землю)
	_box(p, Real.SURF.rubble, Vector3(0, (BASE_H - 0.5) * 0.5, 0), Vector3(W + 0.3, BASE_H + 0.5, D + 0.3))
	# стены
	_box(p, wall_l, Vector3(0, BASE_H + WALL_H * 0.5, 0), Vector3(W, WALL_H, D))
	# фахверк: угловые стойки, пояса, раскосы
	if style != 1:
		for sx in [-1, 1]:
			for sz in [-1, 1]:
				_box(p, beam, Vector3(sx * (W * 0.5 - 0.06), BASE_H + WALL_H * 0.5, sz * (D * 0.5 - 0.06)), Vector3(0.26, WALL_H, 0.26))
		for y in [BASE_H + 0.1, BASE_H + WALL_H * 0.52, top - 0.1]:
			_box(p, beam, Vector3(0, y, D * 0.5 + 0.03), Vector3(W + 0.02, 0.2, 0.12))
			_box(p, beam, Vector3(0, y, -D * 0.5 - 0.03), Vector3(W + 0.02, 0.2, 0.12))
			_box(p, beam, Vector3(W * 0.5 + 0.03, y, 0), Vector3(0.12, 0.2, D + 0.02))
			_box(p, beam, Vector3(-W * 0.5 - 0.03, y, 0), Vector3(0.12, 0.2, D + 0.02))
		# раскосы на боковых стенах
		for sx in [-1, 1]:
			for sz in [-1, 1]:
				var b := Basis(Vector3.RIGHT, sz * 0.62)
				_box(p, beam, Vector3(sx * (W * 0.5 + 0.03), BASE_H + WALL_H * 0.26, sz * D * 0.25), Vector3(0.12, WALL_H * 0.58, 0.16), b)
		# средние стойки на фасаде и сзади
		for sx in [-1, 1]:
			_box(p, beam, Vector3(sx * W * 0.22, BASE_H + WALL_H * 0.5, D * 0.5 + 0.03), Vector3(0.18, WALL_H, 0.12))
			_box(p, beam, Vector3(sx * W * 0.22, BASE_H + WALL_H * 0.5, -D * 0.5 - 0.03), Vector3(0.18, WALL_H, 0.12))
	else:
		# каменный дом: угловые блоки
		for sx in [-1, 1]:
			for sz in [-1, 1]:
				_box(p, Real.SURF.rubble, Vector3(sx * (W * 0.5 - 0.1), BASE_H + WALL_H * 0.5, sz * (D * 0.5 - 0.1)), Vector3(0.42, WALL_H, 0.42))
	# дверь
	_box(p, beam, Vector3(0, BASE_H + 1.1, D * 0.5 + 0.06), Vector3(1.35, 2.3, 0.14))       # коробка
	_box(p, Real.SURF.planks, Vector3(0, BASE_H + 1.02, D * 0.5 + 0.1), Vector3(1.05, 2.05, 0.1))
	_box(p, Real.SURF.metal, Vector3(0.36, BASE_H + 1.0, D * 0.5 + 0.17), Vector3(0.1, 0.1, 0.06))
	_box(p, Real.SURF.rubble, Vector3(0, 0.1, D * 0.5 + 0.55), Vector3(1.5, 0.3, 0.7))      # ступень
	# окна (стекло — тёмный металл со ставнями)
	var wins := [[Vector3(W * 0.5 + 0.06, 0, 0), 0], [Vector3(-W * 0.5 - 0.06, 0, 0), 0], [Vector3(0, 0, -D * 0.5 - 0.06), 1], [Vector3(W * 0.3, 0, D * 0.5 + 0.06), 1], [Vector3(-W * 0.3, 0, D * 0.5 + 0.06), 1]]
	for wv in wins:
		var c: Vector3 = wv[0]; c.y = BASE_H + 1.75
		var along_x: bool = wv[1] == 1
		if absf(c.x) > 0.01 and absf(c.z) > 0.01:
			c.x = signf(c.x) * W * 0.33
		var sz := Vector3(0.75, 0.8, 0.08) if along_x else Vector3(0.08, 0.8, 0.75)
		_box(p, beam, c, sz + Vector3(0.18, 0.18, 0.0) if along_x else sz + Vector3(0.0, 0.18, 0.18))
		_box(p, Real.SURF.metal, c + (Vector3(0, 0, signf(c.z) * 0.03) if along_x else Vector3(signf(c.x) * 0.03, 0, 0)), sz * Vector3(0.82, 0.82, 1.0) if along_x else sz * Vector3(1.0, 0.82, 0.82))
		# ставни
		for s in [-1, 1]:
			var off := Vector3(s * 0.62, 0, 0) if along_x else Vector3(0, 0, s * 0.62)
			_box(p, Real.SURF.planks, c + off + (Vector3(0, 0, signf(c.z) * 0.04) if along_x else Vector3(signf(c.x) * 0.04, 0, 0)), Vector3(0.42, 0.85, 0.05) if along_x else Vector3(0.05, 0.85, 0.42))
	# крыша: конёк вдоль X, скаты к ±Z, свесы
	var ov := 0.42
	var half_d := D * 0.5 + ov
	var slope_len := sqrt(half_d * half_d + RIDGE * RIDGE)
	var ang := atan2(RIDGE, half_d)
	for sz in [-1, 1]:
		var b := Basis(Vector3.RIGHT, sz * ang)
		var c := Vector3(0, top + RIDGE * 0.5 - 0.02, sz * half_d * 0.5)
		_box(p, roof_l, c, Vector3(W + ov * 2.0, 0.16 if style != 2 else 0.32, slope_len + 0.08), b)
	_box(p, beam, Vector3(0, top + RIDGE + 0.04, 0), Vector3(W + ov * 2.0 + 0.1, 0.18, 0.22))   # конёк
	# фронтоны
	for sx in [-1, 1]:
		_gable(p, wall_l if style != 0 else Real.SURF.planks, sx * (W * 0.5), D * 0.5, top, RIDGE - 0.08, sx)
	# труба
	_box(p, Real.SURF.stone, Vector3(W * 0.28, top + RIDGE * 0.75, -D * 0.18), Vector3(0.6, RIDGE * 1.2, 0.6))
	_box(p, Real.SURF.rubble, Vector3(W * 0.28, top + RIDGE * 1.35, -D * 0.18), Vector3(0.72, 0.14, 0.72))
	var am := ArrayMesh.new()
	for layer in p.st:
		var s: SurfaceTool = p.st[layer]
		s.commit(am)
		am.surface_set_material(am.get_surface_count() - 1, Real.surf_material(layer))
	_cache[style] = am
	return am

static func _box(p: Parts, layer: int, c: Vector3, size: Vector3, b := Basis.IDENTITY) -> void:
	var st := p.get_st(layer)
	var h := size * 0.5
	var faces := [[Vector3.RIGHT, Vector3.BACK, Vector3.UP], [Vector3.LEFT, Vector3.FORWARD, Vector3.UP], [Vector3.UP, Vector3.RIGHT, Vector3.BACK],
		[Vector3.DOWN, Vector3.RIGHT, Vector3.FORWARD], [Vector3.BACK, Vector3.LEFT, Vector3.UP], [Vector3.FORWARD, Vector3.RIGHT, Vector3.UP]]
	for f in faces:
		var n: Vector3 = f[0]; var u: Vector3 = f[1]; var v: Vector3 = f[2]
		if n.cross(u).dot(v) < 0: u = -u
		var center := n * h
		var hu := u * h; var hv := v * h
		var q := [center - hu - hv, center + hu - hv, center + hu + hv, center - hu + hv]
		var wn := (b * n).normalized()
		for i in [0, 2, 1, 0, 3, 2]:
			st.set_color(Color(0.8, 0.8, 0.8)); st.set_normal(wn); st.add_vertex(c + b * (q[i] as Vector3))

static func _gable(p: Parts, layer: int, x: float, hd: float, y0: float, rh: float, side: int) -> void:
	var st := p.get_st(layer)
	var a := Vector3(x, y0, -hd); var b := Vector3(x, y0, hd); var t := Vector3(x, y0 + rh, 0)
	var n := Vector3(side, 0, 0)
	var tri := [a, b, t] if side > 0 else [a, t, b]
	for v in tri:
		st.set_color(Color(0.8, 0.8, 0.8)); st.set_normal(n); st.add_vertex(v)
