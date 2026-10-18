extends DungeonBuilder
class_name PartyDungeonBuilder
## Групповое подземелье (v0.8.0): зал входа с порталом выхода → коридор с двумя группами стражей →
## решётка → круглая арена босса с четырьмя опорными точками (жаровни / островки / обелиски).
## Камень — те же реалистичные PBR-материалы, что в Склепе (трипланар, Real.SURF), свет и туман — по теме.
## Враги, решётка и исход боя приходят от RaidSim (сервер или локальная симуляция) через RaidClient.

var did := "ash"
var theme: Dictionary
var gate_vis: Node3D
var gate_col: CollisionShape3D
var gate_is_closed := true
var water: MeshInstance3D
var _water_t := 0.0
var _water_dur := 0.0
var exit_portal_point := Vector3(0, 0, -2.2)
var arena_exit: Node3D
var _exit_cd := 2.0

func build(z) -> void:
	zone = z
	did = RaidDefs.by_zone(str(z.data.get("zone", "pd_ash")))
	if did == "": did = "ash"
	theme = RaidDefs.DUNGEONS[did].theme
	rng.seed = 8080 + did.hash() % 1000
	vrng.seed = rng.seed
	_colliders = StaticBody3D.new(); _colliders.name = "Colliders"; _colliders.collision_layer = 1
	add_child(_colliders)
	enemies_root = Node3D.new(); enemies_root.name = "Enemies"; add_child(enemies_root)
	_lighting()
	_crypt_env()
	_theme_env()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new(); bs.size = Vector3(90, 1, 120)
	cs.shape = bs; cs.position = Vector3(0, -0.5, 40)
	_colliders.add_child(cs)
	_add("box", Vector3(0, -0.5, 40), Vector3(90, 1, 120), Color(0.12, 0.11, 0.12), Vector3.ZERO, false)
	_troom(-8, 8, -4, 8, [[-RaidDefs.CORR_HALF + 0.5, RaidDefs.CORR_HALF - 0.5]], [])
	_troom(-RaidDefs.CORR_HALF, RaidDefs.CORR_HALF, 8, RaidDefs.GATE_Z, [[-4.2, 4.2]], [[-RaidDefs.CORR_HALF + 0.5, RaidDefs.CORR_HALF - 0.5]])
	_tarena()
	_tdecor()
	_texit()
	_tgate()
	_flush_batches()
	arena_center = RaidDefs.ARENA_C
	arena_r = RaidDefs.ARENA_R
	arena_point = arena_center
	portal_point = exit_portal_point
	merchant_point = Vector3.ZERO
	spawn_point = RaidDefs.ENTRY + Vector3(0, 0.1, 0)
	z.data["has_pos"] = false

func _theme_env() -> void:
	var we: WorldEnvironment = get_node("Env")
	var e := we.environment
	var fog: Color = theme.fog
	e.background_color = fog * 0.35
	e.ambient_light_color = (theme.light as Color).lerp(Color(0.5, 0.5, 0.55), 0.6)
	e.fog_light_color = fog
	var sun: DirectionalLight3D = get_node("Sun")
	sun.light_color = (theme.light as Color).lerp(Color.WHITE, 0.55)

func _troom(x0: float, x1: float, z0: float, z1: float, gaps_n: Array, gaps_s: Array) -> void:
	_add("box", Vector3((x0 + x1) / 2, 0.01, (z0 + z1) / 2), Vector3(x1 - x0, 0.02, z1 - z0), theme.floor, Vector3.ZERO, false)
	_twall_x(x0, z0, z1); _twall_x(x1, z0, z1)
	_twall_z(z0, x0, x1, gaps_s); _twall_z(z1, x0, x1, gaps_n)

func _twall_x(x: float, z0: float, z1: float) -> void:
	var w: Color = theme.wall
	_add("box", Vector3(x, 3.0, (z0 + z1) / 2), Vector3(1.0, 6.0, z1 - z0 + 1.0), w)
	_add("box", Vector3(x, 0.35, (z0 + z1) / 2), Vector3(1.35, 0.7, z1 - z0 + 1.2), DUNGEON_TRIM, Vector3.ZERO, false)
	_add("box", Vector3(x, 6.05, (z0 + z1) / 2), Vector3(1.4, 0.35, z1 - z0 + 1.3), DUNGEON_TRIM, Vector3.ZERO, false)
	var n := maxi(1, int((z1 - z0) / 6.0))
	for i in n:
		var zz := z0 + (i + 0.5) * (z1 - z0) / n
		_add("box", Vector3(x, 3.1, zz), Vector3(1.5, 6.2, 0.9), w * 0.85)
		if i % 2 == 0:
			var off := 0.9 if x < 0 else -0.9
			_glow("sphere", Vector3(x + off, 3.2, zz), Vector3.ONE * 0.22, theme.accent, 4.0)
			if i % 4 == 0: _light(Vector3(x + off * 1.5, 3.4, zz), theme.light, 1.5, 10.0, true)

func _twall_z(zz: float, x0: float, x1: float, gaps: Array) -> void:
	var segs := [[x0, x1]]
	for g in gaps:
		var out := []
		for s in segs:
			if g[1] <= s[0] or g[0] >= s[1]: out.append(s); continue
			if g[0] > s[0]: out.append([s[0], g[0]])
			if g[1] < s[1]: out.append([g[1], s[1]])
		segs = out
	for s in segs:
		if s[1] - s[0] < 0.1: continue
		_add("box", Vector3((s[0] + s[1]) / 2, 3.0, zz), Vector3(s[1] - s[0], 6.0, 1.0), theme.wall)
		_add("box", Vector3((s[0] + s[1]) / 2, 0.35, zz), Vector3(s[1] - s[0] + 0.2, 0.7, 1.35), DUNGEON_TRIM, Vector3.ZERO, false)

func _tarena() -> void:
	var c := RaidDefs.ARENA_C
	var r := RaidDefs.ARENA_R
	_add("cylinder", c + Vector3(0, 0.02, 0), Vector3(r * 2 + 2, 0.02, r * 2 + 2), (theme.floor as Color) * 0.92, Vector3.ZERO, false)
	_add("cylinder", c + Vector3(0, 0.03, 0), Vector3(8, 0.01, 8), (theme.floor as Color) * 1.15, Vector3.ZERO, false)
	for i in 40:
		var a := i * 9.0
		if a > 256 and a < 284: continue   # проход на юг (к коридору)
		var p := c + Vector3(cos(deg_to_rad(a)), 0, sin(deg_to_rad(a))) * (r + 1.0)
		_add("box", p + Vector3.UP * 3.25, Vector3(3.6, 6.5, 1.2), theme.wall, Vector3(0, -a + 90, 0))
		_add("box", p + Vector3.UP * 0.35, Vector3(3.7, 0.7, 1.55), DUNGEON_TRIM, Vector3(0, -a + 90, 0), false)
		if i % 5 == 0:
			var inward := (c - p).normalized()
			_glow("sphere", p + inward * 1.0 + Vector3.UP * 3.6, Vector3.ONE * 0.3, theme.accent, 4.0)
	# переходник коридор → арена
	for sx in [-1, 1]:
		_add("box", Vector3(sx * (RaidDefs.CORR_HALF), 3.0, RaidDefs.GATE_Z + 1.2), Vector3(1.0, 6.0, 2.6), theme.wall)
	_light(c + Vector3(0, 9, 0), theme.light, 2.6, 30.0)
	for k in 4:
		var pt: Vector3 = RaidDefs.POINTS[k]
		match did:
			"ash":   # жаровни у опорных точек
				var bp := pt + (pt - c).normalized() * 4.4
				_add("cylinder", bp + Vector3.UP * 0.6, Vector3(1.6, 0.6, 1.6), theme.wall * 0.8)
				_glow("sphere", bp + Vector3.UP * 1.5, Vector3(1.1, 0.6, 1.1), Color(1.0, 0.45, 0.1), 6.0)
				_light(bp + Vector3.UP * 2.2, Color(1.0, 0.5, 0.2), 1.8, 9.0, true)
			"crypt": # каменные островки (безопасны при приливе)
				_add("cylinder", pt + Vector3.UP * 0.15, Vector3(RaidDefs.POINT_R * 2, 0.15, RaidDefs.POINT_R * 2), (theme.wall as Color) * 1.1, Vector3.ZERO, false)
				_add("cylinder", pt + Vector3.UP * 0.31, Vector3(RaidDefs.POINT_R * 2 - 0.4, 0.01, RaidDefs.POINT_R * 2 - 0.4), (theme.floor as Color) * 1.2, Vector3.ZERO, false)
				_glow("sphere", pt + Vector3.UP * 0.4 + (pt - c).normalized() * RaidDefs.POINT_R, Vector3.ONE * 0.25, theme.accent, 3.0)
			"star":  # обелиски (их щит спасает от Сверхновой)
				var op := pt + (pt - c).normalized() * (RaidDefs.POINT_R + 1.6)
				_add("box", op + Vector3.UP * 2.6, Vector3(1.0, 5.2, 1.0), theme.wall * 1.1, Vector3(0, 45, 0))
				_glow("box", op + Vector3.UP * 5.6, Vector3(0.5, 0.8, 0.5), theme.accent, 5.0, preload("res://scripts/game/spin.gd"))
				_light(op + Vector3.UP * 4.0, theme.light, 1.4, 10.0)
	if did == "crypt":
		water = MeshInstance3D.new()
		var pm := PlaneMesh.new(); pm.size = Vector2(r * 2 + 4, r * 2 + 4)
		water.mesh = pm
		var wm := StandardMaterial3D.new()
		wm.albedo_color = Color(0.12, 0.32, 0.38, 0.72); wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		wm.metallic = 0.2; wm.roughness = 0.08; wm.emission_enabled = true; wm.emission = Color(0.04, 0.14, 0.18)
		water.material_override = wm
		water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(water); water.position = c + Vector3(0, -0.4, 0)
		water.visible = false

func _tdecor() -> void:
	for i in 12:
		var p := Vector3(_r(-5, 5), 0, _r(10, 38))
		if absf(p.x) < 2.6: continue
		_add("box", p + Vector3.UP * 0.25, Vector3(_r(0.4, 1.0), 0.5, _r(0.4, 1.0)), theme.wall * 0.7, Vector3(0, _r(0, 90), 0), false)
	match did:
		"ash":
			for i in 10:   # раскалённые трещины
				var p := Vector3(_r(-4, 4), 0.035, _r(10, 38)) if i < 5 else RaidDefs.ARENA_C + Vector3(_r(-14, 14), 0.035, _r(-14, 14))
				var g := _glow("box", p, Vector3(_r(1.5, 3.5), 0.01, 0.12), Color(1.0, 0.4, 0.05), 5.0)
				g.rotation_degrees.y = _r(0, 180)
		"crypt":
			for i in 8:    # лужи
				var p := Vector3(_r(-4, 4), 0.03, _r(10, 38))
				var w := U.prim("cylinder", self, p, Vector3(_r(1.2, 2.4), 0.005, _r(1.2, 2.4)), Color(0.1, 0.25, 0.3))
				var m := StandardMaterial3D.new(); m.albedo_color = Color(0.08, 0.2, 0.24, 0.8); m.roughness = 0.05; m.metallic = 0.3
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				w.material_override = m
		"star":
			for i in 10:   # кристаллы эфира
				var p := Vector3(_r(-4.8, 4.8), 0.4, _r(10, 38)) if i < 5 else RaidDefs.ARENA_C + Vector3(_r(-16, 16), 0.4, _r(-16, 16))
				if absf(p.x) < 2.6 and p.z < 40: continue
				_glow("box", p, Vector3(0.3, 0.8, 0.3), theme.accent, 3.0, preload("res://scripts/game/spin.gd"))

func _texit() -> void:
	var c := exit_portal_point
	for s in [-1, 1]:
		_add("box", c + Vector3(s * 2.0, 2.2, 0), Vector3(0.9, 4.4, 0.9), theme.wall * 1.1)
	_add("box", c + Vector3(0, 4.7, 0), Vector3(5.2, 0.8, 1.0), theme.wall)
	var plane := U.prim("box", self, c + Vector3.UP * 2.1, Vector3(3.1, 4.1, 0.1), Color(0.3, 0.8, 1))
	plane.material_override = U.fx_mat(Color(0.3, 0.8, 1, 0.55))
	_light(c + Vector3(0, 2.5, 1.0), Color(0.3, 0.8, 1), 2.0, 9)

func _tgate() -> void:
	var body := StaticBody3D.new(); body.name = "RaidGate"; add_child(body)
	gate_col = CollisionShape3D.new(); var b := BoxShape3D.new(); b.size = Vector3(RaidDefs.CORR_HALF * 2, 6, 0.6)
	gate_col.shape = b; gate_col.position = Vector3(0, 3, RaidDefs.GATE_Z + 0.6)
	body.add_child(gate_col)
	gate_vis = Node3D.new(); add_child(gate_vis)
	for x in range(-5, 6):
		U.prim("box", gate_vis, Vector3(x * 1.0, 3.0, RaidDefs.GATE_Z + 0.6), Vector3(0.16, 6.0, 0.16), (theme.accent as Color), 0.4, 1.6)
	U.prim("box", gate_vis, Vector3(0, 5.6, RaidDefs.GATE_Z + 0.6), Vector3(RaidDefs.CORR_HALF * 2, 0.25, 0.25), theme.accent, 0.4, 1.2)

func set_gate(closed: bool) -> void:
	if closed == gate_is_closed: return
	gate_is_closed = closed
	gate_col.set_deferred("disabled", not closed)
	var tw := create_tween()
	tw.tween_property(gate_vis, "position:y", 0.0 if closed else 5.8, 0.6)

func water_rise(dur: float) -> void:
	if water == null: return
	water.visible = true
	_water_t = 0.0; _water_dur = dur

func spawn_arena_exit() -> void:
	if arena_exit != null: return
	var c := RaidDefs.ARENA_C + Vector3(0, 0, 13)
	arena_exit = Node3D.new(); add_child(arena_exit); arena_exit.position = c
	for sx in [-1, 1]:
		U.prim("box", arena_exit, Vector3(sx * 1.9, 2.1, 0), Vector3(0.7, 4.2, 0.7), theme.wall * 1.2, 0.6)
	U.prim("box", arena_exit, Vector3(0, 4.4, 0), Vector3(4.6, 0.6, 0.8), theme.wall * 1.2, 0.6)
	var plane := U.prim("box", arena_exit, Vector3(0, 2.0, 0), Vector3(3.0, 3.9, 0.08), Color(1.0, 0.85, 0.4))
	plane.material_override = U.fx_mat(Color(1.0, 0.8, 0.35, 0.6))
	_light(c + Vector3(0, 2.5, 1.2), Color(1.0, 0.8, 0.45), 2.5, 12.0)
	arena_exit.scale = Vector3(1, 0.05, 1)
	arena_exit.create_tween().tween_property(arena_exit, "scale", Vector3.ONE, 0.9).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Game.toast("Открылся портал в долину — добыча будет собрана автоматически", 4.0)

func _process(delta: float) -> void:
	if water and water.visible:
		_water_t += delta
		var k := clampf(_water_t / 1.2, 0.0, 1.0) if _water_t < _water_dur else clampf(1.0 - (_water_t - _water_dur) / 1.5, 0.0, 1.0)
		water.position.y = lerpf(-0.4, 0.24, k)
		if _water_t > _water_dur + 1.5: water.visible = false
	var p = zone.player
	if p == null or zone.get("raid") == null: return
	if _exit_cd > 0.0: _exit_cd -= delta; return
	var near_exit := U.flat_dist(p.global_position, exit_portal_point) < 1.7
	if arena_exit and U.flat_dist(p.global_position, arena_exit.global_position) < 2.4: near_exit = true
	if near_exit:
		_exit_cd = 4.0
		if arena_exit:
			var n := Loot.collect_all(zone)
			if n > 0: Game.toast("Добыча собрана: %d" % n, 2.0)
		zone.raid.leave()

# --- то, что спрашивают HUD/мини-карта у подземелий ---
func checkpoint() -> Vector3: return RaidDefs.ENTRY + Vector3(0, 0.1, 0)
func boss_enemy():
	for e in zone.enemies:
		if is_instance_valid(e) and e.alive and e.def.boss: return e
	return null
func gate_open() -> bool: return not gate_is_closed
func packs_left() -> int:
	var c := 0
	for e in zone.enemies:
		if is_instance_valid(e) and e.alive and e is NetEnemy and e.role == "trash": c += 1
	return c
func guide_target() -> Vector3:
	var p: Vector3 = zone.player.global_position
	if packs_left() > 0: return RaidDefs.PACKS[0] if p.z < RaidDefs.PACKS[0].z - 2 else RaidDefs.PACKS[1]
	return RaidDefs.ARENA_C
func objective() -> String:
	var dd: Dictionary = RaidDefs.DUNGEONS[did]
	if arena_exit != null: return "%s пройдена! Портал на арене вернёт в долину" % dd.name
	if packs_left() > 0: return "Цель: перебить стражей коридора (%d) — решётка арены откроется" % packs_left()
	return "Цель: %s — %s" % [dd.name, String(dd.desc).get_slice(".", 0)]
func bake_nav() -> void: pass
func nav_ready() -> bool: return false
