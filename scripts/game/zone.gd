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
var last_boss_drop := {}
var merchant: Node3D
var merchant_point := Vector3.ZERO
var stash_point := Vector3.INF
var arena_point := Vector3.ZERO
var portal_point := Vector3.ZERO
var dungeon_gate_point := Vector3.ZERO
var builder: StarterZoneBuilder
## Точки взаимодействия (рычаги, двери): {pos, r, text, icon, cb, visible?}
var interactables: Array = []
var pillars: Array = []
var pillar_r := 1.4
var raid: RaidClient          # групповое подземелье (v0.8.0)
var party_ui: Node            # рамки группы и окно «Группа / Подземелья»
var target_ctl: Node          # v0.9.0: выбор цели (TargetCtl)
## Возвышенности для наземных врагов (у игрока — физика): диски, коробки, пандусы
var _h_discs: Array = []
var _h_boxes: Array = []
var _h_ramps: Array = []

func add_height_disc(c: Vector3, r: float, h: float) -> void: _h_discs.append([c, r, h])
func add_height_box(c: Vector3, half: Vector3, h: float) -> void: _h_boxes.append([c, half, h])
func add_height_ramp(low: Vector3, high: Vector3, half_w: float) -> void: _h_ramps.append([low, high, half_w])

## Высота земли в точке (для врагов, лута)
func ground_y(p: Vector3) -> float:
	if builder is WorldBuilder: return builder.height_at(p)
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
	if not DB.ZONES.has(data.get("zone", "")) or (data["zone"] == "dungeon" and DB.zone_lock_reason(data, "dungeon") != ""):
		data["zone"] = "starter"
	# групповое подземелье: онлайн — только внутри экземпляра сервера, офлайн — соло-забег (своя симуляция)
	if RaidDefs.is_raid_zone(data["zone"]) and (RaidDefs.by_zone(data["zone"]) == "" or (Net.in_game and Net.raid_iid == 0)):
		data["zone"] = "starter"; data["has_pos"] = false
	if RaidDefs.is_raid_zone(data["zone"]): builder = PartyDungeonBuilder.new()
	elif data["zone"] == "dungeon": builder = DungeonBuilder.new()
	elif data["zone"] == "global": builder = WorldBuilder.new()
	else: builder = StarterZoneBuilder.new()
	builder.name = "World"
	add_child(builder)
	builder.build(self)
	spawn_point = builder.spawn_point
	merchant_point = builder.merchant_point
	arena_point = builder.arena_point
	portal_point = builder.portal_point
	dungeon_gate_point = builder.dungeon_gate_point
	if builder is DungeonBuilder:
		pillars = builder.pillars; pillar_r = builder.pillar_r
	elif builder is WorldBuilder:
		DB.shop_ensure(data)
	else:
		DB.shop_ensure(data)
		_spawn_merchant()
		if "stash_point" in builder: spawn_stash(builder.stash_point)
	var arrive: String = data.get("arrive", "")
	if arrive == "dungeon" and not data.get("has_pos", false):
		data["pos"] = [dungeon_gate_point.x + 3.5, 0.1, dungeon_gate_point.z - 2.0]
		data["has_pos"] = true
	if arrive == "world" and not data.get("has_pos", false):
		data["pos"] = [portal_point.x - 3.0, 0.1, portal_point.z - 3.0]
		data["has_pos"] = true
	data.erase("arrive")

	player = Player.new()
	player.name = "Player"
	add_child(player)
	player.global_position = Vector3(data["pos"][0], float(data["pos"][1]) + 0.2, data["pos"][2]) if data.get("has_pos", false) else spawn_point
	player.setup(data)

	if builder is PartyDungeonBuilder:
		raid = RaidClient.new(); raid.name = "Raid"
		add_child(raid)
		raid.setup(self, builder.did)
	party_ui = PartyUI.new(); party_ui.zone = self
	add_child(party_ui)
	target_ctl = TargetCtl.new()
	add_child(target_ctl)
	target_ctl.setup(self)

	cam_rig = CameraRig.new()
	add_child(cam_rig)
	cam_rig.target = player
	cam_rig.global_position = player.global_position

	hud = preload("res://scripts/ui/hud.gd").new()
	add_child(hud)
	hud.setup(self)
	Game.toast(DB.ZONES[data["zone"]]["name"], 3.0)

func _spawn_merchant() -> void:
	var m := CharVisual.new()
	m.name = "Merchant"
	add_child(m)
	m.build({"gender": 0, "skin": 1, "hair": 1, "hair_color": 3, "beard": 1, "height": 1.04, "build": 0.4}, "mage", "")
	m.global_position = merchant_point
	m.rotation.y = atan2(spawn_point.x - merchant_point.x, spawn_point.z - merchant_point.z)
	merchant = m
	var l := Label3D.new()
	l.font = UIK.title_font(); l.text = "Торговец Борис"; l.font_size = 56; l.pixel_size = 0.006
	l.outline_size = 10; l.modulate = UIK.ACCENT; l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 10; l.outline_render_priority = 9
	m.add_child(l); l.position = Vector3(0, 3.05, 0.6)
	var ic := Sprite3D.new()
	ic.texture = UIK.icon("two-coins"); ic.pixel_size = 0.0035; ic.modulate = Color(1, 0.85, 0.3)
	ic.billboard = BaseMaterial3D.BILLBOARD_ENABLED; ic.no_depth_test = true
	ic.render_priority = 10
	m.add_child(ic); ic.position = Vector3(0, 3.6, 0.6)

## Сундук лагеря (общий, 100 ячеек): модель Kenney Survival Kit (CC0) + точка взаимодействия
func spawn_stash(p: Vector3) -> void:
	stash_point = p
	var ch := WorldBuilder.prop(self, "survival_chest", p, 0, 4.2)
	ch.name = "Stash"
	ch.rotation.y = atan2(spawn_point.x - p.x, spawn_point.z - p.z)
	var l := Label3D.new()
	l.font = UIK.title_font(); l.text = "Сундук"; l.font_size = 48; l.pixel_size = 0.006
	l.outline_size = 10; l.modulate = Color(0.75, 0.85, 1.0); l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true; l.render_priority = 10; l.outline_render_priority = 9
	add_child(l); l.global_position = p + Vector3(0, 1.6, 0)
	l.visibility_range_end = 40.0
	interactables.append({"pos": p, "r": 2.4, "text": "Сундук", "icon": "treasure-map", "cb": func(): hud._open("stash")})

func near_stash() -> bool:
	return stash_point != Vector3.INF and player != null and U.flat_dist(player.global_position, stash_point) < 2.4

func is_dungeon() -> bool:
	return builder is DungeonBuilder

func is_raid() -> bool: return builder is PartyDungeonBuilder

## Ближайшая доступная точка взаимодействия рядом с игроком (или пустой словарь)
func nearest_interactable() -> Dictionary:
	if player == null: return {}
	var best := {}
	var bd := INF
	for it in interactables:
		if it.has("visible") and not it["visible"].call(): continue
		var d := U.flat_dist(player.global_position, it["pos"])
		if d < float(it["r"]) and d < bd: bd = d; best = it
	return best

func near_merchant() -> bool:
	if player == null: return false
	if builder is WorldBuilder:
		for mp in builder.merchant_points:
			if U.flat_dist(player.global_position, mp) < 3.2: return true
		return false
	return merchant != null and U.flat_dist(player.global_position, merchant_point) < 3.2

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
	if builder is WorldBuilder: spawn_point = builder.respawn_point(player.global_position)
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

## «Стоп-кадр» при попадании: на долю секунды почти останавливаем время
var _stop_active := false
var base_time_scale := 1.0   # для замедленных снимков
var hit_stops := 0
func hit_stop(dur: float) -> void:
	if dur <= 0.0 or _stop_active or not is_inside_tree(): return
	_stop_active = true
	hit_stops += 1
	Engine.time_scale = 0.05 * base_time_scale
	await get_tree().create_timer(dur, true, false, true).timeout
	Engine.time_scale = base_time_scale
	_stop_active = false

func _exit_tree() -> void:
	Engine.time_scale = 1.0

func shake(amount: float) -> void:
	if cam_rig: cam_rig.shake(amount)

func float_text(pos: Vector3, text: String, c: Color) -> void:
	U.float_text(fx_root, pos, text, c)

func damage_number(pos: Vector3, amount: float, crit: bool, to_player: bool, elem := "") -> void:
	U.damage_number(fx_root, pos, amount, crit, to_player, elem)
