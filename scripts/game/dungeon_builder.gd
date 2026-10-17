extends StarterZoneBuilder
class_name DungeonBuilder
## «Склеп Эфира» — подземелье после Древнего тролля. Открытый сверху склеп вдоль +Z:
##   зал входа (z 0–16, портал назад) → коридор шипов (16–40, группа 1) → зал рычагов (40–64, группа 2,
##   загадка: «Пламя → Лёд → Тень», неверный порядок сбрасывает) → огненный коридор (64–86, группа 3)
##   → арена Хранителя (центр z 104, r 18, 4 колонны для укрытия). Прогресс (группы, рычаги, контрольные
##   точки, победа) хранится в data.zones.dungeon.flags.

const FLOOR := Color(0.28, 0.26, 0.3)
const WALL := Color(0.36, 0.34, 0.4)
const ORDER := ["fire", "ice", "shadow"]
const ORDER_NAMES := {"fire": "Пламя", "ice": "Лёд", "shadow": "Тень"}
var arena_center := Vector3(0, 0, 104)
var arena_r := 18.0
var pillars: Array = []
var pillar_r := 1.4
var traps: Array = []
var levers := {}
var lever_input: Array = []
var gate_body: StaticBody3D
var gate_bars: Node3D
var door_body: StaticBody3D
var door_vis: Node3D
var door_closed := false
var packs: Array = []
var boss_spawner: Spawner
var exit_point := Vector3(0, 0, -2.2)
const CHECKPOINTS := {"": Vector3(0, 0.1, 3), "cp_lever": Vector3(0, 0.1, 62), "cp_boss": Vector3(0, 0.1, 84)}

func build(z) -> void:
	zone = z
	rng.seed = 4242
	_colliders = StaticBody3D.new(); _colliders.name = "Colliders"; _colliders.collision_layer = 1
	add_child(_colliders)
	enemies_root = Node3D.new(); enemies_root.name = "Enemies"; add_child(enemies_root)
	_lighting()
	_crypt_env()
	# пол
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new(); bs.size = Vector3(80, 1, 160)
	cs.shape = bs; cs.position = Vector3(0, -0.5, 60)
	_colliders.add_child(cs)
	_add("box", Vector3(0, -0.5, 60), Vector3(80, 1, 160), Color(0.12, 0.11, 0.14), Vector3.ZERO, false)
	_room(-8, 8, -4, 16, [[-4, 4]], [])          # зал входа (выход — в коридор)
	_room(-4, 4, 16, 40, [], [])                   # коридор шипов
	_room(-12, 12, 40, 64, [[-4, 4]], [[-4, 4]])   # зал рычагов
	_room(-4, 4, 64, 86, [], [])                   # огненный коридор
	_arena()
	_decor()
	_exit_portal()
	# ловушки
	traps.append(Trap.create(z, self, "spikes", Vector3(0, 0, 20.5), 3.8, 1.6, 0.0))
	traps.append(Trap.create(z, self, "spikes", Vector3(0, 0, 25.0), 3.8, 1.6, 1.6))
	traps.append(Trap.create(z, self, "fire", Vector3(0, 0, 69.0), 3.8, 0.9, 0.0))
	traps.append(Trap.create(z, self, "fire", Vector3(0, 0, 74.0), 3.8, 0.9, 1.5))
	_lever_hall()
	_flush_batches()
	# группы врагов (после зачистки не возвращаются)
	packs.append(_pack(Vector3(0, 0, 33), "skeleton", 9, 10, 3, 2.5, "pack1"))
	packs.append(_pack(Vector3(0, 0, 36), "ether_guard", 9, 9, 1, 1.0, "pack1b"))
	packs.append(_pack(Vector3(0, 0, 53), "ether_guard", 9, 10, 2, 3.0, "pack2"))
	packs.append(_pack(Vector3(-8, 0, 46), "skeleton_archer", 9, 10, 2, 2.0, "pack2b"))
	packs.append(_pack(Vector3(0, 0, 80), "skeleton", 10, 10, 3, 2.0, "pack3"))
	packs.append(_pack(Vector3(0, 0, 82), "ether_guard", 10, 10, 1, 1.0, "pack3b"))
	boss_spawner = Spawner.create(z, enemies_root, arena_center, "warden", 10, 10, 1, 0.3, -1.0)
	boss_spawner.kill_flag = "boss_warden_killed"
	arena_point = arena_center
	portal_point = exit_point
	merchant_point = Vector3.ZERO
	spawn_point = checkpoint()
	if flag("lever_solved"): _open_gate(true)

func _pack(pos: Vector3, k: String, lo: int, hi: int, n: int, r: float, f: String) -> Spawner:
	var s := Spawner.create(zone, enemies_root, pos, k, lo, hi, n, r, -1.0)
	s.clear_flag = f
	return s

func flag(f: String) -> bool: return DB.zone_flag(zone.data, "dungeon", f)
func set_flag(f: String) -> void: DB.set_zone_flag(zone.data, "dungeon", f)

## Лучшая открытая контрольная точка (возрождение)
func checkpoint() -> Vector3:
	if flag("cp_boss"): return CHECKPOINTS["cp_boss"]
	if flag("cp_lever"): return CHECKPOINTS["cp_lever"]
	return CHECKPOINTS[""]

func _crypt_env() -> void:
	var we: WorldEnvironment = get_node("Env")
	var e := we.environment
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.025, 0.05)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.42, 0.36, 0.55)
	e.ambient_light_energy = 0.9
	e.fog_light_color = Color(0.12, 0.09, 0.18)
	e.fog_depth_begin = 20
	var sun: DirectionalLight3D = get_node("Sun")
	sun.light_color = Color(0.7, 0.68, 0.95)
	sun.light_energy = 0.55
	sun.rotation_degrees = Vector3(-62, -20, 0)

func is_dungeon_env() -> bool: return true

func apply_graphics() -> void:
	super.apply_graphics()
	var we: WorldEnvironment = get_node_or_null("Env")
	if we and we.environment: we.environment.fog_depth_end = minf(Game.view_distance, 70.0)

## Комната: стены по периметру; gaps_n / gaps_s — проёмы в северной (z1) и южной (z0) стенах [x0, x1]
func _room(x0: float, x1: float, z0: float, z1: float, gaps_n: Array, gaps_s: Array) -> void:
	_add("box", Vector3((x0 + x1) / 2, 0.01, (z0 + z1) / 2), Vector3(x1 - x0, 0.02, z1 - z0), FLOOR, Vector3.ZERO, false)
	_wall_x(x0, z0, z1); _wall_x(x1, z0, z1)
	_wall_z(z0, x0, x1, gaps_s); _wall_z(z1, x0, x1, gaps_n)

func _wall_x(x: float, z0: float, z1: float) -> void:
	_add("box", Vector3(x, 2.5, (z0 + z1) / 2), Vector3(1.0, 5.0, z1 - z0 + 1.0), WALL)
	var n := int((z1 - z0) / 6.0)
	for i in n:   # пилястры и факелы
		var zz := z0 + (i + 0.5) * (z1 - z0) / n
		_add("box", Vector3(x, 2.6, zz), Vector3(1.5, 5.2, 0.9), WALL * 0.85)
		if i % 2 == 0:
			var off := 0.9 if x < 0 else -0.9
			_glow("sphere", Vector3(x + off, 3.0, zz), Vector3.ONE * 0.22, Color(0.7, 0.45, 1.0), 4.0)
			if i % 4 == 0: _light(Vector3(x + off * 1.5, 3.2, zz), Color(0.65, 0.45, 1.0), 1.4, 9.0, true)

func _wall_z(z: float, x0: float, x1: float, gaps: Array) -> void:
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
		_add("box", Vector3((s[0] + s[1]) / 2, 2.5, z), Vector3(s[1] - s[0], 5.0, 1.0), WALL)

func _arena() -> void:
	var c := arena_center
	_add("cylinder", c + Vector3(0, 0.02, 0), Vector3(arena_r * 2, 0.02, arena_r * 2), Color(0.24, 0.22, 0.28), Vector3.ZERO, false)
	_add("cylinder", c + Vector3(0, 0.03, 0), Vector3(7, 0.01, 7), Color(0.35, 0.25, 0.5), Vector3.ZERO, false)
	# кольцо стен с проходом на юг
	for i in 36:
		var a := i * 10.0
		if a > 255 and a < 285: continue   # проход (−Z)
		var p := c + Vector3(cos(deg_to_rad(a)), 0, sin(deg_to_rad(a))) * (arena_r + 1.0)
		_add("box", p + Vector3.UP * 2.75, Vector3(3.6, 5.5, 1.2), WALL, Vector3(0, -a + 90, 0))
	# переходник коридор → арена
	_add("box", Vector3(-4.5, 2.5, 86.5), Vector3(1.0, 5.0, 2.0), WALL)
	_add("box", Vector3(4.5, 2.5, 86.5), Vector3(1.0, 5.0, 2.0), WALL)
	# колонны для укрытия от «Взора Пустоты»
	for k in 4:
		var a := deg_to_rad(45.0 + k * 90.0)
		var p := c + Vector3(cos(a), 0, sin(a)) * 9.0
		pillars.append(p)
		_add("cylinder", p + Vector3.UP * 3.0, Vector3(pillar_r * 2, 3.0, pillar_r * 2), WALL * 1.1)
		_add("box", p + Vector3.UP * 0.2, Vector3(3.4, 0.4, 3.4), WALL * 0.8)
		_glow("sphere", p + Vector3.UP * 6.3, Vector3.ONE * 0.5, Color(0.6, 0.4, 1.0), 3.0)
	_light(c + Vector3(0, 7, 0), Color(0.6, 0.45, 1.0), 2.5, 26.0)
	# дверь арены (закрывается во время боя)
	door_body = StaticBody3D.new(); add_child(door_body)
	var dcs := CollisionShape3D.new(); var dbs := BoxShape3D.new(); dbs.size = Vector3(8, 5, 0.6)
	dcs.shape = dbs; dcs.position = Vector3(0, 2.5, 86.6); dcs.disabled = true
	door_body.add_child(dcs)
	door_vis = Node3D.new(); add_child(door_vis)
	for x in range(-3, 4):
		U.prim("box", door_vis, Vector3(x * 1.1, 2.5, 86.6), Vector3(0.18, 5.0, 0.18), Color(0.5, 0.35, 0.9), 0.4, 1.5)
	door_vis.visible = false

func set_door(closed: bool) -> void:
	if closed == door_closed: return
	door_closed = closed
	door_body.get_child(0).set_deferred("disabled", not closed)
	door_vis.visible = closed
	if closed: Game.toast("Решётка опустилась! Бой с Хранителем", 2.5)

func _decor() -> void:
	for i in 14:
		var p := Vector3(_r(-6, 6), 0, _r(1, 14))
		if p.distance_to(Vector3(0, 0, 3)) < 3.5 or absf(p.x) < 2.0: continue
		_add("box", p + Vector3.UP * 0.25, Vector3(_r(0.4, 1.0), 0.5, _r(0.4, 1.0)), WALL * 0.7, Vector3(0, _r(0, 90), 0), false)
	for z in [10.0, 46.0, 58.0]:
		for sx in [-1, 1]:
			_add("box", Vector3(sx * 6.5, 0.6, z), Vector3(2.2, 1.2, 1.0), Color(0.3, 0.27, 0.3))   # саркофаги
			_add("box", Vector3(sx * 6.5, 1.25, z), Vector3(2.4, 0.15, 1.15), Color(0.4, 0.36, 0.42), Vector3.ZERO, false)
	for i in 8:
		_glow("box", Vector3(_r(-10, 10), 0.3, _r(42, 62)), Vector3(0.25, 0.6, 0.25), Color(0.6, 0.4, 1.0), 2.5, preload("res://scripts/game/spin.gd"))

func _exit_portal() -> void:
	var c := exit_point
	for s in [-1, 1]:
		_add("box", c + Vector3(s * 2.0, 2.2, 0), Vector3(0.9, 4.4, 0.9), WALL * 1.1)
	_add("box", c + Vector3(0, 4.7, 0), Vector3(5.2, 0.8, 1.0), WALL)
	var plane := U.prim("box", self, c + Vector3.UP * 2.1, Vector3(3.1, 4.1, 0.1), Color(0.3, 0.8, 1))
	plane.material_override = U.fx_mat(Color(0.3, 0.8, 1, 0.55))
	var portal := Portal.new()
	portal.zone = zone
	portal.target_zone = "starter"
	portal.arrive = "dungeon"
	add_child(portal)
	portal.position = c
	_light(c + Vector3(0, 2.5, 1.0), Color(0.3, 0.8, 1), 2.0, 9)

# ---------- зал рычагов ----------
func _lever_hall() -> void:
	var defs := {"fire": [Vector3(-10, 0, 50), Color(1, 0.35, 0.1)], "ice": [Vector3(10, 0, 50), Color(0.4, 0.8, 1.0)], "shadow": [Vector3(0, 0, 43), Color(0.65, 0.3, 1.0)]}
	for id in defs:
		var l := Lever.create(self, id, defs[id][0], defs[id][1])
		levers[id] = l
		var lid: String = id
		zone.interactables.append({"pos": l.global_position, "r": 2.4, "text": "Рычаг: " + ORDER_NAMES[id], "icon": "cog", "cb": func(): pull_lever(lid), "visible": func(): return not flag("lever_solved")})
	# табличка с подсказкой
	_add("box", Vector3(0, 1.2, 62.6), Vector3(3.6, 1.6, 0.25), Color(0.25, 0.22, 0.2))
	var lbl := Label3D.new()
	lbl.font = UIK.title_font(); lbl.text = "«Пламя рождает Лёд,\nЛёд хранит Тень»\nПламя → Лёд → Тень"
	lbl.font_size = 48; lbl.pixel_size = 0.0052; lbl.outline_size = 8; lbl.modulate = Color(1, 0.9, 0.7)
	add_child(lbl)
	lbl.position = Vector3(0, 1.25, 62.45); lbl.rotation_degrees.y = 180
	# решётка
	gate_body = StaticBody3D.new(); add_child(gate_body)
	var gcs := CollisionShape3D.new(); var gbs := BoxShape3D.new(); gbs.size = Vector3(8, 5, 0.6)
	gcs.shape = gbs; gcs.position = Vector3(0, 2.5, 64)
	gate_body.add_child(gcs)
	gate_bars = Node3D.new(); add_child(gate_bars)
	for x in range(-3, 4):
		U.prim("box", gate_bars, Vector3(x * 1.1, 2.5, 64), Vector3(0.2, 5.0, 0.2), Color(0.35, 0.33, 0.36), 0.4)
	U.prim("box", gate_bars, Vector3(0, 4.6, 64), Vector3(8, 0.3, 0.3), Color(0.3, 0.28, 0.3), 0.4)

func pull_lever(id: String) -> void:
	if flag("lever_solved") or not levers.has(id): return
	var l: Lever = levers[id]
	if l.on: return
	l.set_on(true)
	lever_input.append(id)
	var k := lever_input.size() - 1
	if ORDER[k] != id:
		Game.toast("Неверный порядок — механизм сбросился. Подсказка у решётки", 3.0)
		zone.fx("burst", l.global_position + Vector3.UP * 1.6, 1.5, Color(1, 0.3, 0.2), 0.4)
		lever_input.clear()
		await get_tree().create_timer(0.6, false).timeout
		for x in levers.values(): x.set_on(false)
		return
	zone.fx("ring", l.global_position + Vector3.UP * 0.1, 1.5, l.color, 0.4)
	if lever_input.size() == ORDER.size():
		set_flag("lever_solved")
		set_flag("cp_lever")
		zone.spawn_point = checkpoint()
		_open_gate(false)
		Game.toast("Решётка поднимается! Контрольная точка сохранена", 3.0)
		zone.save()
	else:
		Game.toast("Рычаг «%s» — верно (%d/3)" % [ORDER_NAMES[id], lever_input.size()], 1.8)

func _open_gate(instant: bool) -> void:
	gate_body.get_child(0).set_deferred("disabled", true)
	for x in levers.values(): x.set_on(true)
	if instant: gate_bars.position.y = -5.2
	else:
		var tw := gate_bars.create_tween()
		tw.tween_property(gate_bars, "position:y", -5.2, 1.2)

func gate_open() -> bool:
	return flag("lever_solved")

func _process(_d: float) -> void:
	var p = zone.player
	if p == null: return
	if p.global_position.z > 83.0 and not flag("cp_boss"):
		set_flag("cp_boss")
		zone.spawn_point = checkpoint()
		Game.toast("Контрольная точка: вход на арену", 2.0)
		zone.save()
	var boss = boss_enemy()
	var fighting: bool = boss != null and boss.brain and boss.brain.engaged and not p.dead
	set_door(fighting and p.global_position.z > 88.0)

func boss_enemy():
	for e in zone.enemies:
		if is_instance_valid(e) and e.alive and e.kind == "warden": return e
	return null

## Сколько групп осталось
func packs_left() -> int:
	var n := 0
	for s in packs:
		if s.clear_flag != "" and not flag(s.clear_flag): n += 1
	return n
