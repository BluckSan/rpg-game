extends Node3D
class_name Minion
## Призванный скелет некроманта.

var zone
var owner_player
var mult := 0.6
var life := 25.0
var hp := 50.0
var attack_timer := 0.0
var model: Node3D

static func spawn(z, pos: Vector3, owner_p, m: float, lifetime: float) -> Minion:
	var mn := Minion.new()
	mn.zone = z; mn.owner_player = owner_p; mn.mult = m; mn.life = lifetime
	mn.hp = owner_p.stats.max_hp * 0.5
	z.fx_root.add_child(mn)
	mn.global_position = Vector3(pos.x, 0, pos.z)
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

func take_damage(d: float) -> void:
	hp -= d
	if hp <= 0: _die()

func _die() -> void:
	if not is_inside_tree(): return
	zone.minions.erase(self)
	zone.fx("burst", global_position + Vector3.UP, 1.0, Color.WHITE, 0.3)
	queue_free()

func _process(delta: float) -> void:
	life -= delta
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
		global_position += to.normalized() * 5.0 * delta
		rotation.y = atan2(to.x, to.z)
	elif t != null and attack_timer <= 0:
		attack_timer = 1.0
		owner_player.hit(t, mult, true)
		(model as MobModel).play_action("attack", 1.3)
