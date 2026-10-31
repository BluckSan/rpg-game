extends PartyDungeonBuilder
class_name LichNecropolisBuilder
## v0.9.5: «Некрополь Пепельной Короны» — своя архитектура под лича, не общий шаблон подземелий:
## промёрзший склеп из кости и льда, ниши с замёрзшими телами, свечи душ, сине-зелёный некротический свет,
## стелющийся морозный туман, двери-решётки из рёбер между залами и тронный зал с костяным троном,
## четырьмя постаментами филактерий и ледяными провалами. Раскладка — RaidDefs.L_* (её же знает LichSim).
## Для телефонов: всё статичное — батчи (_add), источников света немного и без теней, туман — пара плоскостей.

const L_BONE := Color(0.82, 0.79, 0.7)
const L_BONE_D := Color(0.55, 0.52, 0.46)
const L_ICE := Color(0.62, 0.86, 0.95)
const L_ICE_D := Color(0.32, 0.5, 0.62)
const L_STONE := Color(0.3, 0.35, 0.4)
const L_STONE_D := Color(0.19, 0.22, 0.27)
const L_NECRO := Color(0.35, 1.0, 0.75)
const L_SOUL := Color(0.45, 0.9, 1.0)
const L_WALL_H := 7.5

var ldoor_bodies: Array = []
var ldoor_vis: Array = []
var ldoor_closed := [true, true, true]
var amb: AudioStreamPlayer
var _fog_planes: Array = []
var _t := 0.0

func build(z) -> void:
	zone = z
	did = "lich"
	theme = RaidDefs.DUNGEONS[did].theme
	rng.seed = 9095; vrng.seed = rng.seed
	_colliders = StaticBody3D.new(); _colliders.name = "Colliders"; _colliders.collision_layer = 1
	add_child(_colliders)
	enemies_root = Node3D.new(); enemies_root.name = "Enemies"; add_child(enemies_root)
	_lighting()
	_crypt_env()
	_lich_env()
	var cs := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = Vector3(80, 1, 240)
	cs.shape = bs; cs.position = Vector3(0, -0.5, 105); _colliders.add_child(cs)
	_add("box", Vector3(0, -0.5, 105), Vector3(80, 1, 240), Color(0.06, 0.08, 0.1), Vector3.ZERO, false)
	# зал входа и склеп легионов
	_rect(-9, 9, -4, 10, [[-6, 6]], [])
	_rect(-6, 6, 10, 53, [[-2.6, 2.6]], [[-6, 6]], true)
	_round(RaidDefs.L_KEEPER, RaidDefs.L_ROOM_R, [90.0, 270.0], 13.0, "keeper")
	_rect(-4.5, 4.5, 75, 101, [[-2.6, 2.6]], [[-2.6, 2.6]], true)
	_round(RaidDefs.L_SISTER, RaidDefs.L_ROOM_R, [90.0, 270.0], 13.0, "sister")
	_rect(-12, 12, 124, 172.5, [[-4.5, 4.5]], [[-2.6, 2.6]], false, true)
	_throne_room()
	_hall_pillars()
	_decor()
	_texit()
	_doors()
	_lgate()
	_ambience()
	_flush_batches()
	arena_center = RaidDefs.L_ARENA_C
	arena_r = RaidDefs.L_ARENA_R
	arena_point = arena_center
	portal_point = exit_portal_point
	merchant_point = Vector3.ZERO
	spawn_point = RaidDefs.L_ENTRY + Vector3(0, 0.1, 0)
	z.data["has_pos"] = false

# ---------------- атмосфера ----------------
func _lich_env() -> void:
	var e: Environment = (get_node("Env") as WorldEnvironment).environment
	e.background_color = Color(0.015, 0.03, 0.04)
	e.ambient_light_color = Color(0.3, 0.42, 0.48)
	e.ambient_light_energy = 0.4
	e.fog_enabled = true
	e.fog_light_color = Color(0.1, 0.2, 0.24)
	e.fog_density = 0.018
	e.fog_depth_begin = 12
	var sun: DirectionalLight3D = get_node("Sun")
	sun.light_color = Color(0.55, 0.8, 0.95); sun.light_energy = 0.22

## Стелющийся морозный туман: полупрозрачные плоскости у пола (дёшево и на телефоне)
func _ground_fog(c: Vector3, sx: float, sz: float) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(sx, sz); mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.4, 0.7, 0.75, 0.035); m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mi.material_override = m; mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi); mi.position = c + Vector3.UP * 0.35
	_fog_planes.append(mi)

# ---------------- стены и залы ----------------
func _rect(x0: float, x1: float, z0: float, z1: float, gaps_n: Array, gaps_s: Array, crypts := false, hall := false) -> void:
	_add("box", Vector3((x0 + x1) / 2, 0.01, (z0 + z1) / 2), Vector3(x1 - x0, 0.02, z1 - z0), L_STONE_D, Vector3.ZERO, false)
	# плиты пола с инеем по швам
	var nz := int((z1 - z0) / 4.0)
	for i in nz:
		var zz := z0 + (i + 0.5) * (z1 - z0) / nz
		_add("box", Vector3((x0 + x1) / 2, 0.025, zz - (z1 - z0) / nz * 0.5), Vector3(x1 - x0 - 0.4, 0.01, 0.12), L_ICE_D, Vector3.ZERO, false)
	for x in [x0, x1]: _wall_x2(x, z0, z1, crypts)
	_wall_z2(z0, x0, x1, gaps_s); _wall_z2(z1, x0, x1, gaps_n)
	if hall:   # ковровая дорожка изо льда к трону
		_add("box", Vector3(0, 0.03, (z0 + z1) / 2), Vector3(3.2, 0.02, z1 - z0), L_ICE_D * 1.15, Vector3.ZERO, false)
	_ground_fog(Vector3((x0 + x1) / 2, 0, (z0 + z1) / 2), x1 - x0, z1 - z0)

func _wall_x2(x: float, z0: float, z1: float, crypts: bool) -> void:
	var s := -1.0 if x < 0 else 1.0
	_add("box", Vector3(x + s * 0.5, L_WALL_H / 2, (z0 + z1) / 2), Vector3(1.2, L_WALL_H, z1 - z0 + 1.0), L_STONE)
	_add("box", Vector3(x, 0.3, (z0 + z1) / 2), Vector3(1.0, 0.6, z1 - z0), L_BONE_D, Vector3.ZERO, false)   # костяной цоколь
	var n := maxi(1, int((z1 - z0) / 5.0))
	for i in n:
		var zz := z0 + (i + 0.5) * (z1 - z0) / n
		# рёберные арки: пара изогнутых костей на стене
		for h in [2.0, 4.0, 6.0]:
			_add("capsule", Vector3(x - s * 0.15, h, zz), Vector3(0.18, 0.9, 0.18), L_BONE, Vector3(0, 0, s * 70), false)
		_add("box", Vector3(x - s * 0.2, L_WALL_H - 0.3, zz), Vector3(0.6, 0.6, 0.9), L_BONE_D, Vector3.ZERO, false)
		_add("sphere", Vector3(x - s * 0.35, L_WALL_H - 0.35, zz), Vector3(0.38, 0.42, 0.38), L_BONE)   # череп-замковый камень
		if crypts and i % 2 == 1:
			_crypt_niche(Vector3(x - s * 0.55, 0, zz), s)
		if i % 2 == 0:
			_candles(Vector3(x - s * 0.9, 0, zz + 1.2), 3)
		if i % 3 == 0:
			_glow("sphere", Vector3(x - s * 0.5, 4.8, zz), Vector3.ONE * 0.2, L_NECRO, 4.0)
			if i % 6 == 0: _light(Vector3(x - s * 1.6, 4.0, zz), L_NECRO, 1.1, 9.0, true)
		# сосульки с карниза
		for k in 3:
			_add("cone", Vector3(x - s * 0.7, L_WALL_H - 0.9, zz + (k - 1) * 1.1), Vector3(0.1, -0.9 - 0.3 * k, 0.1), L_ICE, Vector3(180, 0, 0), false)

func _wall_z2(zz: float, x0: float, x1: float, gaps: Array) -> void:
	var segs := [[x0, x1]]
	for g in gaps:
		var out := []
		for sg in segs:
			if g[1] <= sg[0] or g[0] >= sg[1]: out.append(sg); continue
			if g[0] > sg[0]: out.append([sg[0], g[0]])
			if g[1] < sg[1]: out.append([g[1], sg[1]])
		segs = out
	for sg in segs:
		if sg[1] - sg[0] < 0.1: continue
		_add("box", Vector3((sg[0] + sg[1]) / 2, L_WALL_H / 2, zz), Vector3(sg[1] - sg[0], L_WALL_H, 1.2), L_STONE)
		_add("box", Vector3((sg[0] + sg[1]) / 2, 0.3, zz), Vector3(sg[1] - sg[0], 0.6, 1.4), L_BONE_D, Vector3.ZERO, false)

## Круглый зал (Усыпальница Хранителя / Часовня Сестры): кольцо стен из блоков, проёмы на севере и юге
func _round(c: Vector3, r: float, gap_angles: Array, gap_deg: float, kind: String) -> void:
	_add("cylinder", c + Vector3(0, 0.015, 0), Vector3(r * 2 + 1, 0.02, r * 2 + 1), L_STONE_D, Vector3.ZERO, false)
	_add("cylinder", c + Vector3(0, 0.03, 0), Vector3(r * 1.1, 0.01, r * 1.1), L_ICE_D, Vector3.ZERO, false)
	var steps := 36
	for i in steps:
		var a := 360.0 * i / steps
		var skip := false
		for g in gap_angles:
			if absf(wrapf(a - float(g), -180.0, 180.0)) < gap_deg: skip = true
		if skip: continue
		var p := c + Vector3(cos(deg_to_rad(a)), 0, sin(deg_to_rad(a))) * (r + 0.6)
		_add("box", p + Vector3.UP * L_WALL_H / 2, Vector3(2.4, L_WALL_H, 1.2), L_STONE, Vector3(0, -a + 90, 0))
		if i % 3 == 0:
			var inward := (c - p).normalized()
			_add("capsule", p + inward * 0.5 + Vector3.UP * 3.0, Vector3(0.22, 1.6, 0.22), L_BONE, Vector3(0, -a + 90, 0), false)
			_glow("sphere", p + inward * 0.9 + Vector3.UP * 4.6, Vector3.ONE * 0.18, L_NECRO if kind == "sister" else L_SOUL, 4.0)
		if i % 4 == 2:
			_candles(p + (c - p).normalized() * 1.4, 2)
	match kind:
		"keeper":   # усыпальница: каменный саркофаг в центре, щиты павших стражей на стенах
			_add("box", c + Vector3(0, 0.45, 6.5), Vector3(2.0, 0.9, 3.6), L_STONE, Vector3.ZERO)
			_add("box", c + Vector3(0, 0.95, 6.5), Vector3(2.2, 0.15, 3.8), L_BONE_D, Vector3.ZERO, false)
			_add("sphere", c + Vector3(0, 1.1, 5.2), Vector3(0.35, 0.3, 0.35), L_BONE, Vector3.ZERO, false)
			_light(c + Vector3(0, 5, 0), L_SOUL, 1.4, 16.0)
		"sister":   # часовня: алтарь, круг рун и зелёное пламя
			_add("box", c + Vector3(0, 0.5, 8.0), Vector3(3.2, 1.0, 1.4), L_STONE, Vector3.ZERO)
			_glow("sphere", c + Vector3(0, 1.4, 8.0), Vector3(0.5, 0.7, 0.5), L_NECRO, 6.0)
			for k in 8:
				var a2 := TAU * k / 8.0
				_glow("box", c + Vector3(cos(a2) * 5.5, 0.04, sin(a2) * 5.5), Vector3(0.9, 0.01, 0.25), L_NECRO, 3.0).rotation.y = -a2
			_light(c + Vector3(0, 5, 0), L_NECRO, 1.5, 16.0, true)
	_ground_fog(c, r * 2, r * 2)

## Ниша склепа: каменная полка, замёрзшее тело в ледяной глыбе
func _crypt_niche(p: Vector3, s: float) -> void:
	_add("box", p + Vector3(-s * 0.1, 0.55, 0), Vector3(1.0, 1.1, 2.6), L_STONE_D, Vector3.ZERO)
	_add("capsule", p + Vector3(-s * 0.1, 1.35, 0), Vector3(0.32, 0.9, 0.32), L_BONE_D, Vector3(90, 0, 0), false)
	_add("sphere", p + Vector3(-s * 0.1, 1.4, 1.05), Vector3(0.28, 0.28, 0.3), L_BONE, Vector3.ZERO, false)
	var ice := U.prim("box", self, p + Vector3(-s * 0.1, 1.4, 0), Vector3(0.9, 0.7, 2.5), L_ICE)
	ice.material_override = _ice_mat()
	ice.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

var _icem: StandardMaterial3D
func _ice_mat() -> StandardMaterial3D:
	if _icem == null:
		_icem = StandardMaterial3D.new()
		_icem.albedo_color = Color(0.6, 0.9, 1.0, 0.38); _icem.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_icem.roughness = 0.06; _icem.metallic = 0.1; _icem.emission_enabled = true; _icem.emission = Color(0.05, 0.16, 0.2)
		_icem.rim_enabled = true; _icem.rim = 0.6
	return _icem

## Свечи душ: восковые столбики с бирюзовым огоньком (без источников света — для телефона)
func _candles(p: Vector3, n: int) -> void:
	for i in n:
		var q := p + Vector3(_r(-0.5, 0.5), 0, _r(-0.5, 0.5))
		var h := _r(0.25, 0.6)
		_add("cylinder", q + Vector3.UP * h / 2, Vector3(0.09, h / 2, 0.09), Color(0.78, 0.8, 0.72), Vector3.ZERO, false)
		var f := _glow("sphere", q + Vector3.UP * (h + 0.08), Vector3(0.06, 0.11, 0.06), L_SOUL, 7.0)
		f.get_child(0).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

# ---------------- Костяной зал и тронный зал ----------------
func _hall_pillars() -> void:
	for pl in RaidDefs.L_COL_PILLARS:   # колонны, за которыми прячутся от рывка Колосса (с коллизией)
		_add("cylinder", pl + Vector3.UP * L_WALL_H / 2, Vector3(RaidDefs.L_COL_PILLAR_R * 2, L_WALL_H / 2, RaidDefs.L_COL_PILLAR_R * 2), L_STONE)
		_add("cylinder", pl + Vector3.UP * 0.3, Vector3(RaidDefs.L_COL_PILLAR_R * 2.4, 0.3, RaidDefs.L_COL_PILLAR_R * 2.4), L_BONE_D, Vector3.ZERO, false)
		for k in 6:   # обвивающие рёбра
			var a := TAU * k / 6.0
			_add("capsule", pl + Vector3(cos(a) * 1.35, 2.5 + (k % 2) * 2.0, sin(a) * 1.35), Vector3(0.15, 1.2, 0.15), L_BONE, Vector3(0, -rad_to_deg(a), 25), false)
		_add("sphere", pl + Vector3(0, L_WALL_H - 0.4, 0), Vector3(0.9, 0.8, 0.9), L_BONE, Vector3.ZERO, false)
		_glow("sphere", pl + Vector3(0, 3.4, 0) + (Vector3(0, 0, 196) - pl).normalized() * 1.35, Vector3.ONE * 0.2, L_NECRO, 4.0)
	_light(Vector3(0, 6, 148), L_SOUL, 1.6, 22.0)
	# груды костей по краям зала
	for i in 14:
		var p := Vector3((-1 if i % 2 == 0 else 1) * _r(8, 10.5), 0, _r(127, 170))
		_bones(p)

func _bones(p: Vector3) -> void:
	_add("sphere", p + Vector3.UP * 0.15, Vector3(_r(0.9, 1.6), 0.4, _r(0.9, 1.6)), L_BONE_D, Vector3.ZERO, false)
	for k in 4:
		_add("capsule", p + Vector3(_r(-0.6, 0.6), 0.35, _r(-0.6, 0.6)), Vector3(0.07, 0.45, 0.07), L_BONE, Vector3(90, _r(0, 180), 0), false)
	_add("sphere", p + Vector3(_r(-0.4, 0.4), 0.5, _r(-0.4, 0.4)), Vector3(0.22, 0.22, 0.24), L_BONE, Vector3.ZERO, false)

func _throne_room() -> void:
	var c := RaidDefs.L_ARENA_C
	var r := RaidDefs.L_ARENA_R
	_add("cylinder", c + Vector3(0, 0.015, 0), Vector3(r * 2 + 2, 0.02, r * 2 + 2), L_STONE_D, Vector3.ZERO, false)
	_add("cylinder", c + Vector3(0, 0.025, 0), Vector3(r * 1.6, 0.01, r * 1.6), L_ICE_D, Vector3.ZERO, false)
	# руны-круги на полу
	for rr in [6.0, 12.0]:
		for k in 24:
			var a := TAU * k / 24.0
			if k % 2 == 0: _glow("box", c + Vector3(cos(a) * rr, 0.035, sin(a) * rr), Vector3(1.2, 0.01, 0.12), L_NECRO * 0.8, 2.0).rotation.y = -a + PI / 2
	# кольцо стен с ледяными шипами; проход на юг
	for i in 44:
		var a := i * (360.0 / 44)
		if a > 254 and a < 286: continue
		var p := c + Vector3(cos(deg_to_rad(a)), 0, sin(deg_to_rad(a))) * (r + 1.0)
		_add("box", p + Vector3.UP * (L_WALL_H + 1) / 2, Vector3(3.4, L_WALL_H + 1, 1.2), L_STONE, Vector3(0, -a + 90, 0))
		var inward := (c - p).normalized()
		if i % 2 == 0:
			_add("cone", p + inward * 0.9 + Vector3.UP * 1.0, Vector3(0.5, 2.2 + (i % 4) * 0.6, 0.5), L_ICE, Vector3(0, 0, 0), false)
		if i % 4 == 1:
			_add("capsule", p + inward * 0.4 + Vector3.UP * 4.5, Vector3(0.25, 2.0, 0.25), L_BONE, Vector3(0, -a + 90, 0), false)
			_candles(p + inward * 1.6, 2)
		if i % 6 == 0:
			_glow("sphere", p + inward * 0.9 + Vector3.UP * 5.6, Vector3.ONE * 0.28, L_SOUL, 4.0)
	for sx in [-1, 1]:   # переходник зал → тронный зал
		_add("box", Vector3(sx * 5.2, L_WALL_H / 2, 173.5), Vector3(1.2, L_WALL_H, 3.5), L_STONE)
	_add("box", Vector3(0, L_WALL_H - 0.5, 173.5), Vector3(11.0, 1.0, 3.5), L_BONE_D, Vector3.ZERO, false)
	# постаменты филактерий (сами кристаллы — враги «rl_phyl», их ставит LichSim)
	for pt in RaidDefs.L_POINTS:
		_add("cylinder", pt + Vector3.UP * 0.25, Vector3(2.6, 0.25, 2.6), L_STONE, Vector3.ZERO, false)
		_add("cylinder", pt + Vector3.UP * 0.52, Vector3(2.0, 0.02, 2.0), L_BONE_D, Vector3.ZERO, false)
		for k in 4:
			var a := TAU * k / 4.0 + PI / 4
			_add("cone", pt + Vector3(cos(a) * 1.1, 0.9, sin(a) * 1.1), Vector3(0.12, 0.8, 0.12), L_BONE, Vector3(sin(a) * 15, 0, -cos(a) * 15), false)
		_glow("cylinder", pt + Vector3.UP * 0.55, Vector3(1.6, 0.01, 1.6), L_NECRO, 2.5)
	# ледяные провалы (урон и замедление — в LichSim): тёмная бездна с ледяной кромкой
	for pit in RaidDefs.L_PITS:
		var rp := RaidDefs.L_PIT_R
		_add("cylinder", pit + Vector3.UP * 0.04, Vector3(rp * 2, 0.01, rp * 2), Color(0.02, 0.05, 0.08), Vector3.ZERO, false)
		_glow("cylinder", pit + Vector3.UP * 0.035, Vector3(rp * 2 + 0.5, 0.005, rp * 2 + 0.5), L_SOUL, 1.6)
		for k in 7:
			var a := TAU * k / 7.0 + _r(0, 0.4)
			_add("cone", pit + Vector3(cos(a) * (rp + 0.2), 0.3, sin(a) * (rp + 0.2)), Vector3(0.18, 0.6 + _r(0, 0.5), 0.18), L_ICE, Vector3(sin(a) * -25, 0, cos(a) * 25), false)
	_throne()
	_light(c + Vector3(0, 11, 0), Color(0.5, 0.85, 1.0), 1.1, 30.0)
	_light(RaidDefs.L_THRONE + Vector3(0, 4, -3), L_NECRO, 2.0, 14.0, true)
	_ground_fog(c, r * 2, r * 2)

func _throne() -> void:
	var t := RaidDefs.L_THRONE
	for k in 3:   # ступени
		_add("box", t + Vector3(0, 0.2 + k * 0.4, -3.0 + k * 0.9), Vector3(9.0 - k * 1.6, 0.4, 2.0), L_STONE if k % 2 == 0 else L_STONE_D)
	_add("box", t + Vector3(0, 1.8, 0.6), Vector3(3.2, 1.0, 2.2), L_BONE_D)
	_add("box", t + Vector3(0, 4.2, 1.6), Vector3(3.4, 4.6, 0.6), L_BONE_D)
	for sx in [-1, 1]:   # подлокотники-черепа и спинка из рёбер
		_add("box", t + Vector3(sx * 1.6, 2.6, 0.4), Vector3(0.5, 0.8, 2.0), L_BONE_D, Vector3.ZERO, false)
		_add("sphere", t + Vector3(sx * 1.6, 3.15, -0.5), Vector3(0.45, 0.45, 0.5), L_BONE, Vector3.ZERO, false)
		for k in 4:
			_add("capsule", t + Vector3(sx * (0.5 + k * 0.32), 5.0 + k * 0.45, 1.5), Vector3(0.14, 1.5 + k * 0.3, 0.14), L_BONE, Vector3(0, 0, -sx * (12 + k * 8)), false)
	for k in 7:   # корона-шипы над троном
		var x := (k - 3) * 0.55
		_add("cone", t + Vector3(x, 7.2 + (0.9 if k == 3 else 0.0), 1.6), Vector3(0.3, 1.6 + (1.2 if k == 3 else (0.5 if k % 2 == 1 else 0.0)), 0.3), L_BONE)
	_add("sphere", t + Vector3(0, 6.6, 1.35), Vector3(1.0, 1.0, 1.0), L_BONE)
	_glow("sphere", t + Vector3(0, 6.7, 0.9), Vector3(0.28, 0.28, 0.2), L_NECRO, 8.0)
	var ice := U.prim("box", self, t + Vector3(0, 3.5, 2.2), Vector3(5.5, 7.0, 0.5), L_ICE)
	ice.material_override = _ice_mat()

func _decor() -> void:
	# зал входа: статуи стражей и ледяные сталагмиты
	for sx in [-1, 1]:
		var p := Vector3(sx * 6.5, 0, 6.0)
		_add("box", p + Vector3.UP * 0.5, Vector3(1.6, 1.0, 1.6), L_STONE)
		_add("capsule", p + Vector3.UP * 2.3, Vector3(0.6, 1.4, 0.6), L_BONE_D, Vector3.ZERO, false)
		_add("sphere", p + Vector3.UP * 3.9, Vector3(0.5, 0.55, 0.5), L_BONE, Vector3.ZERO, false)
		_glow("sphere", p + Vector3(sx * -0.2, 3.95, -0.4), Vector3.ONE * 0.1, L_NECRO, 6.0)
	for i in 16:   # сталагмиты льда в коридорах (у стен, не мешают проходу)
		var zz := _r(12, 50) if i < 8 else _r(77, 99)
		var half := 6.0 if i < 8 else 4.5
		var p := Vector3((-1 if i % 2 == 0 else 1) * (half - 0.9), 0, zz)
		_add("cone", p + Vector3.UP * 0.6, Vector3(0.35, 1.2 + _r(0, 1.0), 0.35), L_ICE, Vector3.ZERO, false)
	for i in 8:
		_bones(Vector3(_r(-4, 4), 0, _r(14, 50)))
	_light(Vector3(0, 5, 2), L_SOUL, 1.4, 14.0)
	_light(Vector3(0, 5, 30), L_NECRO, 1.2, 16.0, true)
	_light(Vector3(0, 5, 88), L_SOUL, 1.2, 16.0, true)

# ---------------- двери, решётка, выход ----------------
func _doors() -> void:
	for i in 3:
		var zz: float = RaidDefs.L_DOORS[i]
		var body := StaticBody3D.new(); body.name = "LichDoor%d" % i; add_child(body)
		var col := CollisionShape3D.new(); var b := BoxShape3D.new(); b.size = Vector3(5.6, 6, 0.6)
		col.shape = b; col.position = Vector3(0, 3, zz); body.add_child(col)
		ldoor_bodies.append(col)
		var vis := Node3D.new(); add_child(vis)
		for x in range(-2, 3):   # прутья-рёбра
			U.prim("capsule", vis, Vector3(x * 0.55, 2.8, zz), Vector3(0.12, 2.8, 0.12), L_BONE, 0.6)
		U.prim("box", vis, Vector3(0, 5.4, zz), Vector3(3.2, 0.3, 0.3), L_BONE_D, 0.6)
		U.prim("sphere", vis, Vector3(0, 5.6, zz - 0.1), Vector3(0.45, 0.45, 0.45), L_BONE, 0.6)
		U.prim("sphere", vis, Vector3(0, 5.6, zz - 0.4), Vector3(0.12, 0.12, 0.12), L_NECRO, 0.2, 6.0)
		ldoor_vis.append(vis)
		for sx in [-1, 1]:   # косяки
			_add("box", Vector3(sx * 3.0, L_WALL_H / 2, zz), Vector3(0.9, L_WALL_H, 1.4), L_STONE)
		_add("box", Vector3(0, 6.6, zz), Vector3(6.8, 1.0, 1.4), L_BONE_D, Vector3.ZERO, false)

func set_doors(closed: Array) -> void:
	for i in mini(3, closed.size()):
		var c := bool(closed[i])
		if c == ldoor_closed[i]: continue
		ldoor_closed[i] = c
		ldoor_bodies[i].set_deferred("disabled", not c)
		var tw := create_tween()
		tw.tween_property(ldoor_vis[i], "position:y", 0.0 if c else 5.6, 0.8)

func _lgate() -> void:
	var gz: float = RaidDefs.L_DOORS[3]
	var body := StaticBody3D.new(); body.name = "RaidGate"; add_child(body)
	gate_col = CollisionShape3D.new(); var b := BoxShape3D.new(); b.size = Vector3(10, 7, 0.6)
	gate_col.shape = b; gate_col.position = Vector3(0, 3.5, gz + 0.8)
	body.add_child(gate_col)
	gate_vis = Node3D.new(); add_child(gate_vis)
	for x in range(-4, 5):
		U.prim("box", gate_vis, Vector3(x * 1.05, 3.2, gz + 0.8), Vector3(0.18, 6.4, 0.18), L_ICE, 0.2, 1.6)
	U.prim("box", gate_vis, Vector3(0, 6.2, gz + 0.8), Vector3(9.6, 0.3, 0.3), L_BONE, 0.6)

func spawn_arena_exit() -> void:
	if arena_exit != null: return
	var c := RaidDefs.L_ARENA_C + Vector3(0, 0, -12)
	arena_exit = Node3D.new(); add_child(arena_exit); arena_exit.position = c
	for sx in [-1, 1]:
		U.prim("box", arena_exit, Vector3(sx * 1.9, 2.1, 0), Vector3(0.7, 4.2, 0.7), L_BONE_D, 0.6)
	U.prim("box", arena_exit, Vector3(0, 4.4, 0), Vector3(4.6, 0.6, 0.8), L_BONE_D, 0.6)
	var plane := U.prim("box", arena_exit, Vector3(0, 2.0, 0), Vector3(3.0, 3.9, 0.08), L_SOUL)
	plane.material_override = U.fx_mat(Color(0.5, 0.95, 1.0, 0.6))
	_light(c + Vector3(0, 2.5, 1.2), L_SOUL, 2.5, 12.0)
	arena_exit.scale = Vector3(1, 0.05, 1)
	arena_exit.create_tween().tween_property(arena_exit, "scale", Vector3.ONE, 0.9).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Game.toast("Открылся портал к Заставе Инея — добыча будет собрана автоматически", 4.0)
	if amb: amb.create_tween().tween_property(amb, "volume_db", -30.0, 4.0)

# ---------------- музыка и эмбиент ----------------
## Процедурный эмбиент склепа: низкий гул в миноре, вой ветра (фильтрованный шум) и редкий колокол.
## Основная музыка игры приглушается, пока герой в Некрополе.
func _ambience() -> void:
	amb = AudioStreamPlayer.new(); amb.bus = "Music"; amb.volume_db = -8.0; amb.name = "LichAmbience"
	amb.stream = _make_amb()
	add_child(amb)
	if Game.music_volume > 0.001 and DisplayServer.get_name() != "headless": amb.play()
	if Game.get("_music") and Game._music: Game._music.stream_paused = true

func _exit_tree() -> void:
	if Game.get("_music") and Game._music: Game._music.stream_paused = false

static func _make_amb() -> AudioStreamWAV:
	var rate := Game.RATE
	var seg := 6.0
	var roots := [110.0, 103.83, 98.0, 87.31]   # A — G# — G — F: нисходящий гул
	var cnt := int(rate * seg * roots.size())
	var d := PackedFloat32Array(); d.resize(cnt)
	var r := RandomNumberGenerator.new(); r.seed = 95
	var lp := 0.0; var lp2 := 0.0
	for i in cnt:
		var t := float(i) / rate
		var ci := int(t / seg) % roots.size(); var lt := fmod(t, seg)
		var env := minf(1.0, lt / 2.0) * minf(1.0, (seg - lt) / 2.0)
		var f: float = roots[ci]
		var v := (sin(TAU * f * 0.5 * t) * 0.22 + sin(TAU * f * t) * 0.12 + sin(TAU * f * 1.189 * t) * 0.07 + sin(TAU * f * 1.498 * t) * 0.05) * env
		# ветер: дважды сглаженный шум с медленной волной громкости
		var nz := r.randf_range(-1.0, 1.0)
		lp += (nz - lp) * 0.02; lp2 += (lp - lp2) * 0.05
		v += lp2 * (1.4 + sin(t * 0.37) * 0.8)
		# колокол раз в сегмент
		if lt < 3.0 and ci % 2 == 0:
			v += sin(TAU * f * 4.0 * t) * exp(-lt * 1.3) * 0.08 + sin(TAU * f * 5.4 * t) * exp(-lt * 2.0) * 0.04
		d[i] = v * 0.55
	return Game._wav(d, true)

func _process(delta: float) -> void:
	_t += delta
	for i in _fog_planes.size():
		var f: MeshInstance3D = _fog_planes[i]
		f.position.y = 0.35 + sin(_t * 0.4 + i) * 0.08
	super._process(delta)

# --- HUD / мини-карта ---
func checkpoint() -> Vector3: return RaidDefs.L_ENTRY + Vector3(0, 0.1, 0)
func guide_target() -> Vector3:
	var p: Vector3 = zone.player.global_position
	var sec := RaidDefs.l_section(p)
	if ldoor_closed[0]: return RaidDefs.L_PACKS[0] if p.z < RaidDefs.L_PACKS[0].z - 2 else RaidDefs.L_PACKS[1]
	if ldoor_closed[1]: return RaidDefs.L_KEEPER if sec <= 1 else RaidDefs.L_PACKS[2]
	if ldoor_closed[2]: return RaidDefs.L_SISTER
	if gate_is_closed and _colossus_alive(): return RaidDefs.L_COLOSSUS
	return RaidDefs.L_ARENA_C
func _colossus_alive() -> bool:
	for e in zone.enemies:
		if is_instance_valid(e) and e.alive and e.kind == "rm_colossus": return true
	return false
func objective() -> String:
	if arena_exit != null: return "Некрополь пройден! Портал в тронном зале вернёт к Заставе Инея"
	if ldoor_closed[0]: return "Цель: перебить легионы склепа (%d)" % packs_left()
	if ldoor_closed[1]: return "Цель: Хранитель склепа (бейте в спину) и стража галереи"
	if ldoor_closed[2]: return "Цель: Сестра Нежити — прерывайте «Воскрешение мёртвых»"
	if gate_is_closed and _colossus_alive(): return "Цель: Костяной Колосс — заманите его рывок в колонну"
	return "Цель: Кел'Таар, Король-Лич"
