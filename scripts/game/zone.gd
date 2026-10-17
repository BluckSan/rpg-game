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
