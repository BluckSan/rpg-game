extends Node3D
class_name TargetCtl
## v0.9.0: выбор цели. Нажатие/клик по врагу или союзнику — выбрать; Tab (ПК) / кнопка «Цель» (телефон) —
## следующий враг; Esc или нажатие по пустой земле — сброс. Под целью — кольцо (красное — враг, зелёное — союзник).
## Направленные умения бьют выбранного врага (если он жив и в досягаемости), иначе — автонаведение.
## Умения поддержки — по выбранному союзнику (рамка группы или клик в мире), иначе — по себе.
## Онлайн: выбор уходит на сервер (Net.send_target) — сервер направляет поддержку и показывает его группе.

signal changed

var zone
var target: Node3D = null
var kind := ""                  # "enemy" / "ally" / ""
var ring: MeshInstance3D
var _mat: StandardMaterial3D
var _t := 0.0
const CYCLE_RANGE := 26.0
const LOCK_RANGE := 40.0        # v0.9.1: дальше — захват цели снимается
const PICK_PX := 70.0

func setup(z) -> void:
	zone = z
	name = "TargetCtl"
	ring = MeshInstance3D.new()
	var tm := TorusMesh.new(); tm.inner_radius = 0.82; tm.outer_radius = 1.0; tm.rings = 32; tm.ring_segments = 6
	ring.mesh = tm
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.no_depth_test = false
	_mat.albedo_color = Color(1, 0.25, 0.2, 0.85)
	_mat.emission_enabled = true; _mat.emission = Color(1, 0.3, 0.2); _mat.emission_energy_multiplier = 1.6
	ring.material_override = _mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.visible = false
	add_child(ring)

func has_target() -> bool:
	return _valid(target)

static func is_enemy(n) -> bool:
	return n is Enemy

static func is_ally(n) -> bool:
	return n is Player or n is RemotePlayer or n is Minion

func _valid(n) -> bool:
	if n == null or not is_instance_valid(n) or not n.is_inside_tree(): return false
	if n is Enemy: return n.alive
	return true

func select(n) -> void:
	if not _valid(n): clear(); return
	if n == target: return
	target = n
	kind = "enemy" if is_enemy(n) else "ally"
	var c := Color(1, 0.25, 0.2) if kind == "enemy" else Color(0.35, 1.0, 0.45)
	_mat.albedo_color = Color(c.r, c.g, c.b, 0.85); _mat.emission = c
	var r := 0.8
	if n is Enemy: r = clampf(float(n.radius) * 1.4, 0.8, 3.2)
	ring.scale = Vector3(r, 1.0, r)
	ring.visible = true
	_sync()
	changed.emit()

func clear() -> void:
	if target == null and not ring.visible: return
	target = null; kind = ""
	ring.visible = false
	_sync()
	changed.emit()

## Онлайн: сообщить серверу (тип и id: peer для игроков, net_id для врагов подземелья)
func _sync() -> void:
	if not Net.in_game: return
	var k := ""; var id := 0
	if target is RemotePlayer: k = "p"; id = int(target.peer_id)
	elif target is Player: k = "p"; id = Net.my_id
	elif target is Enemy and int(target.net_id) != 0: k = "e"; id = int(target.net_id)   # подземелье или общий враг мира
	Net.send_target(k, id)

## Следующий враг: ближние — первыми, по кругу
func cycle() -> void:
	var p = zone.player
	if p == null: return
	var list: Array = []
	for e in zone.enemies:
		if e.alive and p.global_position.distance_to(e.global_position) < CYCLE_RANGE: list.append(e)
	if list.is_empty():
		clear(); Game.toast("Рядом нет врагов", 1.2); return
	list.sort_custom(func(a, b): return p.global_position.distance_squared_to(a.global_position) < p.global_position.distance_squared_to(b.global_position))
	var i := list.find(target)
	select(list[(i + 1) % list.size()])

## Кандидаты под точкой экрана (враги, свой герой, другие игроки, призванные)
func pick(screen: Vector2):
	var cam := get_viewport().get_camera_3d()
	if cam == null: return null
	var best = null; var bd := INF
	var cands: Array = []
	for e in zone.enemies: if e.alive: cands.append([e, 1.2 if not e.def.boss else 2.6, float(e.radius)])
	for r in get_tree().get_nodes_in_group("remote_players"): if r.is_inside_tree() and r.visible: cands.append([r, 1.1, 0.5])
	for m in zone.minions: if is_instance_valid(m): cands.append([m, 0.9, 0.4])
	if zone.player: cands.append([zone.player, 1.1, 0.5])
	for c in cands:
		var n: Node3D = c[0]
		var wp: Vector3 = n.global_position + Vector3.UP * float(c[1])
		if cam.is_position_behind(wp): continue
		var dist := cam.global_position.distance_to(wp)
		if dist > 60.0: continue
		var sp := cam.unproject_position(wp)
		var rad: float = PICK_PX * clampf(14.0 / maxf(dist, 1.0), 0.6, 2.2) * maxf(1.0, float(c[2]))
		var d := sp.distance_to(screen)
		if d < rad and d / rad < bd:
			bd = d / rad; best = n
	return best

## Нажатие/клик по миру: выбрать то, что под пальцем, иначе — сбросить. Возвращает выбранное (или null)
func tap(screen: Vector2):
	var l := Loot.at_screen(zone, screen)   # v0.9.4.1: клик/касание по добыче — подобрать
	if l != null:
		l.manual_pick(); return null
	var n = pick(screen)
	if n == null: clear()
	else: select(n)
	return n

## Враг для направленного умения: выбранный, если жив и в досягаемости (с запасом)
func enemy_in_range(from: Vector3, rng: float):
	if kind == "enemy" and _valid(target) and from.distance_to(target.global_position) <= rng * 1.15 + float(target.radius): return target
	return null

## v0.9.1: захват цели — выбранный враг остаётся целью всех атак и умений (герой разворачивается к нему),
## пока его не сбросят (Esc, ×, касание пустой земли на телефоне, Tab/цикл), он не погибнет или не уйдёт
## дальше LOCK_RANGE. Атаки, умения, движение и автонаведение цель не меняют.
func locked_enemy():
	if kind == "enemy" and _valid(target): return target
	return null

## Союзник для умения поддержки (выбранный или null — тогда «на себя»)
func ally():
	if kind == "ally" and _valid(target): return target
	return null

func _process(delta: float) -> void:
	if target != null and not _valid(target):
		clear(); return
	if target == null: return
	var pl = zone.player
	if pl and target != pl and pl.global_position.distance_to(target.global_position) > LOCK_RANGE:
		clear(); Game.toast("Цель слишком далеко — захват снят", 1.2); return
	_t += delta
	var gp := target.global_position
	ring.global_position = Vector3(gp.x, gp.y + 0.06, gp.z)
	ring.rotation.y = _t * 0.8
	var k := 0.75 + 0.2 * sin(_t * 5.0)
	_mat.albedo_color.a = k
