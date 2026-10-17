extends Node3D
class_name Spawner
## Область появления врагов с возрождением.

var zone
var kind: String
var min_level := 1
var max_level := 2
var count := 4
var radius := 8.0
var respawn_time := 25.0
var kill_flag := ""
var _pending: Array = []

static func create(z, parent: Node, pos: Vector3, k: String, lo: int, hi: int, n: int, r: float, respawn := 25.0) -> Spawner:
	var s := Spawner.new()
	s.zone = z; s.kind = k; s.min_level = lo; s.max_level = hi; s.count = n; s.radius = r; s.respawn_time = respawn
	s.position = pos  # родитель (Enemies) стоит в начале координат; позиция нужна до _ready
	parent.add_child(s)
	return s

func _ready() -> void:
	for i in count: _spawn_one()

func _spawn_one() -> void:
	var r := Vector2.from_angle(randf() * TAU) * randf() * radius
	var e := Enemy.spawn(zone, kind, randi_range(min_level, max_level), global_position + Vector3(r.x, 0, r.y), self)
	e.on_death = _on_death

func _on_death(e) -> void:
	_pending.append(respawn_time)
	if kill_flag != "":
		var zs: Dictionary = zone.data["zones"].get(zone.data["zone"], {"flags": []})
		if not zs["flags"].has(kill_flag):
			zs["flags"].append(kill_flag)
			Game.toast("Повержен: %s!" % e.def.name, 4.0)
		zone.data["zones"][zone.data["zone"]] = zs

func _process(delta: float) -> void:
	for i in range(_pending.size() - 1, -1, -1):
		_pending[i] -= delta
		if _pending[i] <= 0:
			var p = zone.player
			if p and U.flat_dist(p.global_position, global_position) < radius + 6:
				_pending[i] = 3.0
				continue
			_pending.remove_at(i)
			_spawn_one()
