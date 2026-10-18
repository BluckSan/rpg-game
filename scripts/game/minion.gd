extends CharacterBody3D
class_name Minion
## Призванный скелет некроманта. Тело CharacterBody3D (слой — нет, маска 1: стены уровня):
## ноги всегда на земле — высота по рельефу зоны (долина, чанки мира, склеп) при появлении и в каждом кадре физики;
## в склепе путь — по навмешу, стены не проходит.

var zone
var owner_player
var mult := 0.6
var life := 25.0
var hp := 50.0
var max_hp := 50.0
var buffs := {}               # v0.9.0: баффы поддержки (урон, броня)
var attack_timer := 0.0
var model: Node3D
var max_ground_err := 0.0       # для тестов: наибольшее отклонение ног от земли
var _path: PackedVector3Array = PackedVector3Array()
var _path_i := 0
var _path_t := 0.0
var _path_goal := Vector3(INF, 0, INF)
const SPEED := 5.0

static func spawn(z, pos: Vector3, owner_p, m: float, lifetime: float) -> Minion:
	var mn := Minion.new()
	mn.zone = z; mn.owner_player = owner_p; mn.mult = m; mn.life = lifetime
	mn.hp = owner_p.stats.max_hp * 0.5
	mn.max_hp = mn.hp
	mn.collision_layer = 0
	mn.collision_mask = 1
	mn.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	mn.safe_margin = 0.02
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new(); cap.radius = 0.32; cap.height = 1.4
	cs.shape = cap; cs.position = Vector3(0, 0.3 + 0.7, 0)   # приподнята: ступеньки не цепляют
	mn.add_child(cs)
	z.fx_root.add_child(mn)
	mn.global_position = Vector3(pos.x, 0, pos.z)
	mn.snap_to_ground()
	var mm := MobModel.new(); mn.add_child(mm)
	mm.setup("skeleton", {"tint": Color(0.7, 0.68, 0.85), "emission": Color(0.4, 1.0, 0.5)})
	mm.walk_ref = 2.0; mm.run_ref = 4.5
	mm.attach("R.DownLeg.001", "props/sword2", Vector3(0, 0.1, 0), Vector3(180, 0, 0), 0.36)
	mm.play_action("spawn", 1.5)
	mn.model = mm
	var c := Color(0.6, 1.0, 0.6)
	z.minions.append(mn)
	z.fx("burst", mn.global_position + Vector3.UP, 1.2, c, 0.4)
	return mn

## Ноги — на земле зоны (рельеф мира — по треугольникам чанка, долина/склеп — по платформам и пандусам)
## Сначала — луч вниз по физике (настоящие столкновения пола, пандусов и чанков), иначе — высота зоны.
func floor_y() -> float:
	var gy: float = zone.ground_y(global_position)
	if is_inside_tree():
		var from := Vector3(global_position.x, maxf(global_position.y, gy) + 1.2, global_position.z)
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 6.0, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty() and hit.normal.y > 0.6 and absf(hit.position.y - gy) < 1.0: return hit.position.y
	return gy

func snap_to_ground() -> void:
	if zone == null: return
	global_position.y = floor_y()

func ground_error() -> float:
	return absf(global_position.y - floor_y())

func add_buff(b: Dictionary) -> void:
	buffs[b.id] = b.duplicate()

## Множители от баффов: урон (dmg%) и защита (armor%/dr%)
func buff_mult(stat: String) -> float:
	var v := 0.0
	for k in buffs:
		for m in buffs[k].get("mods", []):
			if m[0] == stat: v += float(m[1])
	return v / 100.0

func _tick_buffs(delta: float) -> void:
	for k in buffs.keys():
		buffs[k].t = float(buffs[k].t) - delta
		if buffs[k].t <= 0.0: buffs.erase(k)

func take_damage(d: float) -> void:
	d *= 1.0 - clampf(buff_mult("dr%") + buff_mult("armor%") * 0.3, 0.0, 0.5)
	hp -= d
	if hp <= 0: _die()

func _die() -> void:
	if not is_inside_tree(): return
	zone.minions.erase(self)
	zone.fx("burst", global_position + Vector3.UP, 1.0, Color.WHITE, 0.3)
	queue_free()

func _steer(p: Vector3, delta: float) -> Vector3:
	var b = zone.builder if zone else null
	if b == null or not b.has_method("nav_ready") or not b.nav_ready(): return p
	_path_t -= delta
	if _path_t <= 0.0 or U.flat_dist(p, _path_goal) > 1.0 or _path_i >= _path.size():
		_path_t = 0.45
		_path_goal = p
		_path = NavigationServer3D.map_get_path(b.nav_map(), global_position, p, true)
		_path_i = 1
	while _path_i < _path.size() - 1 and U.flat_dist(global_position, _path[_path_i]) < 0.5: _path_i += 1
	if _path.size() < 2: return p
	return _path[mini(_path_i, _path.size() - 1)]

func _move(motion: Vector3) -> void:
	motion.y = 0
	for i in 3:
		if motion.length_squared() < 0.000001: break
		var col := move_and_collide(motion)
		if col == null: break
		var n := col.get_normal(); n.y = 0
		if n.length_squared() < 0.0001: break
		motion = col.get_remainder().slide(n.normalized())
		motion.y = 0

func _physics_process(delta: float) -> void:
	life -= delta
	if not buffs.is_empty(): _tick_buffs(delta)
	if life <= 0 or not is_instance_valid(owner_player):
		_die()
		return
	if attack_timer > 0: attack_timer -= delta
	var t = null
	var best := 14.0
	for e in zone.enemies:
		if not e.alive: continue
		var d := U.flat_dist(e.global_position, global_position)
		if d < best:
			best = d; t = e
	var goal: Vector3 = t.global_position if t != null else owner_player.global_position + owner_player.global_basis.x * 2.0
	var to := U.flat(goal - global_position)
	var stop: float = t.radius + 1.2 if t != null else 2.0
	if to.length() > stop:
		# далеко отстал (телепорт героя, быстрое перемещение) — догоняет прыжком
		if t == null and to.length() > 30.0:
			global_position = goal
		else:
			var dir := U.flat(_steer(goal, delta) - global_position)
			if dir.length_squared() < 0.0001: dir = to
			_move(dir.normalized() * SPEED * delta)
			rotation.y = atan2(dir.x, dir.z)
	elif t != null and attack_timer <= 0:
		attack_timer = 1.0
		owner_player.hit(t, mult * (1.0 + buff_mult("dmg%")), true)
		(model as MobModel).play_action("attack", 1.3)
	snap_to_ground()
	max_ground_err = maxf(max_ground_err, ground_error())
