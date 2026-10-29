extends Node3D
class_name Loot
## Добыча на земле, подбирается автоматически рядом с игроком.

var zone
var type := "gold"
var amount := 1
var item: Dictionary = {}
var age := 0.0
var holder: Node3D

static func drop_for(z, e) -> void:
	var pos: Vector3 = e.global_position
	var lvl: int = e.level
	var boss: bool = e.def.boss
	if boss:
		_boss_drop(z, e)
		return
	var rank: String = e.rank if "rank" in e else "normal"
	for d in roll_drops(lvl, int(z.data["level"]), str(z.data["class"]), rank):
		spawn(z, pos + _rand(), d[0], d[1], d[2])

## v0.9.1: добыча обычного врага списком [[тип, количество, предмет]] — одна формула для офлайна
## и для сервера (общие враги онлайн: сервер бросает добычу и кладёт её на землю для всех)
static func roll_drops(lvl: int, hero_lvl: int, cls: String, rank: String) -> Array:
	var out := []
	# враги намного ниже героя: меньше золота и предметов (Combat.reward_factor)
	var rf := Combat.reward_factor(hero_lvl, lvl)
	out.append(["gold", maxi(1, int(round(randi_range(2, 5) * (1 + lvl * 0.5) * rf))), {}])
	if randf() > rf: return out
	if randf() < 0.1: out.append(["potion", 1, {}])
	# добыча для всех классов; элиты/редкие — больше и лучше, иногда комплекты
	if rank != "normal": out.append(["gold", int(round(randi_range(4, 8) * (1 + lvl * 0.5) * (2 if rank == "elite" else 4))), {}])
	for it in Items.drop_items(lvl, cls, rank): out.append(["item", 1, it])
	return out

## Босс мира (тролль долины) онлайн: та же добыча, что и офлайн (без уникальных Хранителя)
static func roll_boss_drops(lvl: int, cls: String, first := false) -> Array:
	var out := [["gold", int(round(randi_range(3, 5) * (1 + lvl * 0.5) * 20)), {}], ["potion", 1, {}], ["potion", 1, {}]]
	for i in 4:
		var it := Items.roll(lvl + 1, cls, 0.5)
		if i == 0: while it.rarity < 2: it = Items.roll(lvl + 1, cls, 0.5)
		if i == 1 and first: while it.rarity < 3: it = Items.roll(lvl + 1, cls, 0.9)
		out.append(["item", 1, it])
	for it in Items.drop_items(lvl, cls, "boss"):
		if int(it.get("rarity", 0)) == Items.SET_RARITY: out.append(["item", 1, it])
	return out

## Босс: много золота, 2 зелья, 4 предмета (минимум один редкий), при первой победе — гарантированный уникальный
static func _boss_drop(z, e) -> void:
	var pos: Vector3 = e.global_position
	var lvl: int = e.level
	var d: Dictionary = z.data
	var kills: Dictionary = d.get("boss_kills", {})
	var first := int(kills.get(e.kind, 0)) == 0
	kills[e.kind] = int(kills.get(e.kind, 0)) + 1
	d["boss_kills"] = kills
	spawn(z, pos + _rand(2.5), "gold", int(round(randi_range(3, 5) * (1 + lvl * 0.5) * 20)))
	spawn(z, pos + _rand(2.5), "potion", 1)
	spawn(z, pos + _rand(2.5), "potion", 1)
	for i in 4:
		var it := Items.roll(lvl + 1, d["class"], 0.5)
		if i == 0 and it.rarity < 2:
			while it.rarity < 2: it = Items.roll(lvl + 1, d["class"], 0.5)
		if i == 1 and first:
			while it.rarity < 3: it = Items.roll(lvl + 1, d["class"], 0.9)
		spawn(z, pos + _rand(2.5), "item", 1, it)
	for it in Items.drop_items(lvl, d["class"], "dungeon" if e.kind == "warden" else "boss"):
		if int(it.get("rarity", 0)) == Items.SET_RARITY: spawn(z, pos + _rand(2.5), "item", 1, it)
	var uniq := ""
	if e.kind == "warden":
		# уникальная добыча Хранителя: оружие своего класса (первая победа — гарантированно), иногда печать
		var got: Array = d.get("warden_uniques", [])
		var key: String = d["class"]
		if first or randf() < 0.35:
			if got.has(key) and randf() < 0.5: key = "ring"
			var u := DB.warden_unique(key, lvl + 1)
			spawn(z, pos + _rand(1.5), "item", 1, u)
			uniq = u.name
			if not got.has(key): got.append(key)
			d["warden_uniques"] = got
	# v0.9.1: материалы для ремесла комплектов
	if e.kind == "warden": spawn(z, pos + _rand(2.0), "mat", 3 + lvl / 10, {"mat": "aether_dust"})
	z.last_boss_drop = {"first": first, "count": 7, "unique": uniq}

static func _rand(rad := 1.2) -> Vector3:
	var r := Vector2.from_angle(randf() * TAU) * (0.5 + randf()) * rad * 0.7
	return Vector3(r.x, 0, r.y)

static func spawn(z, pos: Vector3, t: String, n: int, it := {}) -> Loot:
	var l := Loot.new()
	l.zone = z; l.type = t; l.amount = n; l.item = it
	z.fx_root.add_child(l)
	l.global_position = Vector3(pos.x, z.ground_y(pos), pos.z)
	l.holder = Node3D.new(); l.add_child(l.holder); l.holder.position = Vector3.UP * 0.4
	match t:
		"gold":
			U.prim("cylinder", l.holder, Vector3.ZERO, Vector3(0.35, 0.02, 0.35), Color(1, 0.82, 0.2), 0.3, 0.6).rotation_degrees.x = 90
		"potion":
			U.prim("sphere", l.holder, Vector3.ZERO, Vector3.ONE * 0.35, Color(0.9, 0.15, 0.25), 0.2, 1.0)
			U.prim("cylinder", l.holder, Vector3(0, 0.22, 0), Vector3(0.1, 0.04, 0.1), Color(0.6, 0.4, 0.2))
		"mat":
			var mc: Color = Items.MATS.get(str(it.get("mat", "")), {"col": Color.WHITE}).col
			U.prim("sphere", l.holder, Vector3.ZERO, Vector3.ONE * 0.32, mc, 0.5, 1.5)
			var mb := U.prim("cylinder", l, Vector3.UP * 2.0, Vector3(0.1, 2.0, 0.1), mc)
			mb.material_override = U.fx_mat(Color(mc.r, mc.g, mc.b, 0.35))
			mb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_:
			var c: Color = DB.RARITY_COLORS[int(it.rarity)]
			U.prim("box", l.holder, Vector3.ZERO, Vector3.ONE * 0.45, c, 0.4, 1.2 if int(it.rarity) > 0 else 0.2).rotation_degrees = Vector3(45, 0, 45)
			if int(it.rarity) > 0:
				var beam := U.prim("cylinder", l, Vector3.UP * 2.5, Vector3(0.12, 2.5, 0.12), c)
				beam.material_override = U.fx_mat(Color(c.r, c.g, c.b, 0.35))
				beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return l

func _process(delta: float) -> void:
	age += delta
	holder.rotation.y += delta * 2.0
	holder.position.y = 0.4 + sin(age * 2.0) * 0.1
	var p = zone.player
	if p == null or p.dead or age < 0.4: return
	var dist := U.flat_dist(p.global_position, global_position)
	if dist > 4.5 or not auto_pick: return
	if dist > 1.2:
		# притягивание добычи к герою
		var to: Vector3 = p.global_position - global_position; to.y = 0
		global_position += to.normalized() * minf(dist, delta * (4.0 + (4.5 - dist) * 3.0))
		global_position.y = lerpf(global_position.y, p.global_position.y, minf(1.0, delta * 6.0))
		return
	collect()

## Подобрать (в инвентарь/золото/зелья). false — инвентарь полон.
## v0.9.1: общая добыча онлайн (net_id ≠ 0) — сначала запрос серверу: кто первым подобрал, тому и достаётся
var net_id := 0
var _ask_t := -10.0
## тест/настройка: false — без притягивания, только вручную (клик, касание, клавиша)
static var auto_pick := true
const MANUAL_R := 3.2   # подбор вручную: на таком расстоянии от героя

func _ready() -> void: add_to_group("loot")

func collect(manual := false) -> bool:
	var p = zone.player
	if p == null: return false
	if net_id != 0:
		if type == "item" and p.data["inventory"].size() >= DB.INVENTORY_SIZE:
			Game.toast("Инвентарь полон! Продайте или разберите вещи", 1.8); age = -2.0; return false
		if Time.get_ticks_msec() / 1000.0 - _ask_t < (0.4 if manual else 1.5): return false
		_ask_t = Time.get_ticks_msec() / 1000.0
		Net.pick_drop(net_id)
		return false
	return grant()

## Выдать герою (офлайн — сразу, онлайн — по подтверждению сервера)
func grant(from_server := false) -> bool:
	var p = zone.player
	if p == null: return false
	var d: Dictionary = p.data
	match type:
		"mat":
			var mid := str(item.get("mat", "aether_dust"))
			if not d.has("mats") or not (d["mats"] is Dictionary): d["mats"] = {}
			d["mats"][mid] = int(d["mats"].get(mid, 0)) + amount
			var md: Dictionary = Items.MATS.get(mid, {"name": mid, "col": Color.WHITE, "icon": "magic-swirl"})
			zone.hud.pickup("+%d %s" % [amount, md.name], md.col, md.icon)
		"gold":
			d["gold"] += amount
			zone.hud.pickup("+%d золота" % amount, Color(1, 0.85, 0.35), "two-coins")
		"potion":
			d["potions"] += amount
			zone.hud.pickup("+1 зелье лечения", Color(1, 0.4, 0.4), "health-potion")
		_:
			# подтверждение сервера — предмет уже у героя на сервере: не терять его и у себя
			if d["inventory"].size() >= DB.INVENTORY_SIZE and not from_server:
				Game.toast("Инвентарь полон!", 1.5)
				age = -2.0
				return false
			d["inventory"].append(item)
			zone.hud.pickup(item.name, DB.RARITY_COLORS[int(item.rarity)], UIK.item_icon(item, d["class"]))
	Game.sfx("pickup")
	queue_free()
	return true

## Собрать всю лежащую добычу зоны (портал возврата — ничего не теряется). Возвращает число подобранного
static func collect_all(z) -> int:
	var n := 0
	var net := false
	for c in z.fx_root.get_children():
		if not (c is Loot) or c.is_queued_for_deletion(): continue
		if c.net_id != 0: net = true; n += 1; continue
		if c.collect(): n += 1
	if net: Net.pick_all()   # v0.9.4.1: общую добычу собирает сервер (раньше отказ по расстоянию — терялась)
	return n

## Отказ сервера: понятное сообщение вместо бесконечных молчаливых попыток
func denied(why: String) -> void:
	match why:
		"full": Game.toast("Инвентарь полон! Продайте или разберите вещи", 1.8); age = -2.0
		"far": Game.toast("Подойдите ближе", 1.0); _ask_t = -10.0
		"dead": pass
		_: queue_free()   # чужая зона/экземпляр — это не наша добыча

## Подбор вручную (клик/касание по добыче или клавиша «Взаимодействие»)
func manual_pick() -> bool:
	var p = zone.player
	if p == null or p.dead: return false
	if U.flat_dist(p.global_position, global_position) > MANUAL_R:
		Game.toast("Подойдите ближе", 1.0); return false
	age = maxf(age, 0.4)
	return collect(true) or net_id != 0

## Ближайшая добыча рядом с героем (или null)
static func nearest(z, r := MANUAL_R) -> Loot:
	if z == null or z.player == null: return null
	var best: Loot = null; var bd := r
	for l in z.get_tree().get_nodes_in_group("loot"):
		if l.is_queued_for_deletion() or l.zone != z: continue
		var d: float = U.flat_dist(z.player.global_position, l.global_position)
		if d <= bd: bd = d; best = l
	return best

## Добыча под точкой экрана (клик мышью или касание)
static func at_screen(z, screen: Vector2, px := 70.0) -> Loot:
	var cam: Camera3D = z.get_viewport().get_camera_3d()
	if cam == null: return null
	var best: Loot = null; var bd := INF
	for l in z.get_tree().get_nodes_in_group("loot"):
		if l.is_queued_for_deletion() or l.zone != z: continue
		var wp: Vector3 = l.global_position + Vector3.UP * 0.4
		if cam.is_position_behind(wp) or cam.global_position.distance_to(wp) > 40.0: continue
		var d: float = cam.unproject_position(wp).distance_to(screen)
		if d < px and d < bd: bd = d; best = l
	return best
