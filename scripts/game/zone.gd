extends Node3D
## Игровая зона: строит мир, создаёт игрока, камеру, HUD; автосохранение, смерть и возрождение.

static var instance: Node3D

var data: Dictionary
var player: Player
var cam_rig: CameraRig
var hud
var spawn_point := Vector3(0, 0.1, -3.5)
var enemies: Array = []   # живые враги
var minions: Array = []
var fx_root: Node3D
var _autosave := 30.0
## Возвышенности для наземных врагов (у игрока — физика): диски, коробки, пандусы
var _h_discs: Array = []
var _h_boxes: Array = []
var _h_ramps: Array = []

func add_height_disc(c: Vector3, r: float, h: float) -> void: _h_discs.append([c, r, h])
func add_height_box(c: Vector3, half: Vector3, h: float) -> void: _h_boxes.append([c, half, h])
func add_height_ramp(low: Vector3, high: Vector3, half_w: float) -> void: _h_ramps.append([low, high, half_w])

## Высота земли в точке (для врагов, лута)
func ground_y(p: Vector3) -> float:
	var y := 0.0
	for d in _h_discs:
		if Vector2(p.x - d[0].x, p.z - d[0].z).length() <= d[1]: y = maxf(y, d[2])
	for b in _h_boxes:
		if absf(p.x - b[0].x) <= b[1].x and absf(p.z - b[0].z) <= b[1].z: y = maxf(y, b[2])
	for r in _h_ramps:
		var a: Vector3 = r[0]; var bb: Vector3 = r[1]
		var ab := Vector2(bb.x - a.x, bb.z - a.z)
		var ap := Vector2(p.x - a.x, p.z - a.z)
		var t := ap.dot(ab) / ab.length_squared()
		if t < 0 or t > 1: continue
		if absf(ap.cross(ab.normalized())) > r[2]: continue
		y = maxf(y, lerpf(a.y, bb.y, t))
	return y

func _ready() -> void:
	instance = self
	if Game.current.is_empty():
		var list := Game.list_characters()
		Game.current = list[0] if list.size() > 0 else DB.new_character("Тестовый герой", "warrior", {})
	data = Game.current
	fx_root = Node3D.new(); fx_root.name = "FX"; add_child(fx_root)
	var builder := StarterZoneBuilder.new()
	builder.name = "World"
	add_child(builder)
	builder.build(self)
	spawn_point = builder.spawn_point

	player = Player.new()
	player.name = "Player"
	add_child(player)
	player.global_position = Vector3(data["pos"][0], float(data["pos"][1]) + 0.2, data["pos"][2]) if data.get("has_pos", false) else spawn_point
	player.setup(data)

	cam_rig = CameraRig.new()
	add_child(cam_rig)
	cam_rig.target = player
	cam_rig.global_position = player.global_position

	hud = preload("res://scripts/ui/hud.gd").new()
	add_child(hud)
	hud.setup(self)
	Game.toast(DB.ZONES[data["zone"]]["name"], 3.0)

func _process(delta: float) -> void:
	_autosave -= delta
	if _autosave <= 0:
		_autosave = 30.0
		save()

func save() -> void:
	if player and not player.dead:
		var p := player.global_position
		data["pos"] = [p.x, p.y, p.z]
		data["has_pos"] = true
	Game.save_character(data)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if data: save()

func on_player_died() -> void:
	Game.toast("Вы погибли... Возрождение у костра", 3.0)
	data["xp"] = int(data["xp"] * 0.9)
	player.visual.rotation_degrees.x = -90
	await get_tree().create_timer(3.0, false).timeout
	player.visual.rotation_degrees.x = 0
	player.respawn(spawn_point)
	save()

func apply_character_changes(rebuild_visual: bool) -> void:
	player.recalc()
	if rebuild_visual: player.rebuild_visual()
	save()

func fx(kind: String, pos: Vector3, radius: float, c: Color, dur := 0.35) -> void:
	match kind:
		"burst": U.burst(fx_root, pos, radius, c, dur)
		"ring": U.ring(fx_root, pos, radius, c, dur)
		"telegraph": U.telegraph(fx_root, pos, radius, dur)

func damage_number(pos: Vector3, amount: float, crit: bool, to_player: bool) -> void:
	U.damage_number(fx_root, pos, amount, crit, to_player)
