extends Spawner
class_name WorldSpawner
## Спавнер открытого мира: враги существуют, только пока игрок рядом (включает WorldBuilder по расстоянию).
## Таймеры возрождения идут по абсолютному времени — и когда спавнер выключен. Элиты — случайно, редкие и боссы — именные.

var sid := ""
var biome := 0
var active := false
var rank := "normal"          # normal (с шансом элиты) | rare | boss
var rare_name := ""
var elite_chance := 0.0
var mine: Array = []
var _respawn_at: Array = []   # секунды (Time.get_ticks_msec / 1000)

static func make(z, parent: Node, pos: Vector3, k: String, lo: int, hi: int, n: int, r: float, respawn: float) -> WorldSpawner:
	var s := WorldSpawner.new()
	s.zone = z; s.kind = k; s.min_level = lo; s.max_level = hi; s.count = n; s.radius = r; s.respawn_time = respawn
	s.position = pos
	parent.add_child(s)
	return s

func _ready() -> void:
	pass   # без игрока рядом никого не создаём

static func now() -> float: return Time.get_ticks_msec() / 1000.0

func set_active(on: bool) -> void:
	if on == active: return
	active = on
	if on:
		var t := now()
		_respawn_at = _respawn_at.filter(func(x): return x > t)
		for i in maxi(0, count - _respawn_at.size()): _spawn_one()
	else:
		for e in mine:
			if is_instance_valid(e):
				zone.enemies.erase(e)
				e.queue_free()
		mine.clear()
		alive = 0

func _spawn_one() -> void:
	var p := free_point()
	var e := Enemy.spawn(zone, kind, randi_range(min_level, max_level), p, self)
	match rank:
		"rare": e.make_rank("rare", rare_name)
		"boss": e.make_rank("boss", rare_name)
		_: if randf() < elite_chance: e.make_rank("elite")
	e.on_death = _on_death
	mine.append(e)
	alive += 1

func _on_death(e) -> void:
	alive -= 1
	mine.erase(e)
	if respawn_time > 0: _respawn_at.append(now() + respawn_time)
	if kill_flag != "":
		var w: Dictionary = zone.data.get("world", {})
		if not w.has("bosses"): w["bosses"] = []
		if not (w["bosses"] as Array).has(kill_flag): w["bosses"].append(kill_flag)
		zone.data["world"] = w
		Game.toast("Повержен босс зоны: %s!" % e.def.name, 4.0)
		zone.save()

func _process(_delta: float) -> void:
	if not active or _respawn_at.is_empty(): return
	var t := now()
	for i in range(_respawn_at.size() - 1, -1, -1):
		if _respawn_at[i] > t: continue
		var p = zone.player
		if p and U.flat_dist(p.global_position, global_position) < radius + 8:
			_respawn_at[i] = t + 3.0
			continue
		_respawn_at.remove_at(i)
		_spawn_one()
