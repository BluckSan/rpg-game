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
	# враги намного ниже героя: меньше золота и предметов (Combat.reward_factor)
	var rf := Combat.reward_factor(int(z.data["level"]), lvl)
	spawn(z, pos + _rand(), "gold", maxi(1, int(round(randi_range(2, 5) * (1 + lvl * 0.5) * rf))))
	if randf() > rf: return
	if randf() < 0.1: spawn(z, pos + _rand(), "potion", 1)
	# добыча для всех классов; элиты/редкие — больше и лучше, иногда комплекты
	var rank: String = e.rank if "rank" in e else "normal"
	if rank != "normal": spawn(z, pos + _rand(), "gold", int(round(randi_range(4, 8) * (1 + lvl * 0.5) * (2 if rank == "elite" else 4))))
	for it in Items.drop_items(lvl, z.data["class"], rank):
		spawn(z, pos + _rand(), "item", 1, it)

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
	if dist > 4.5: return
	if dist > 1.2:
		# притягивание добычи к герою
		var to: Vector3 = p.global_position - global_position; to.y = 0
		global_position += to.normalized() * minf(dist, delta * (4.0 + (4.5 - dist) * 3.0))
		global_position.y = lerpf(global_position.y, p.global_position.y, minf(1.0, delta * 6.0))
		return
	collect()

## Подобрать (в инвентарь/золото/зелья). false — инвентарь полон
func collect() -> bool:
	var p = zone.player
	if p == null: return false
	var d: Dictionary = p.data
	match type:
		"gold":
			d["gold"] += amount
			zone.hud.pickup("+%d золота" % amount, Color(1, 0.85, 0.35), "two-coins")
		"potion":
			d["potions"] += amount
			zone.hud.pickup("+1 зелье лечения", Color(1, 0.4, 0.4), "health-potion")
		_:
			if d["inventory"].size() >= DB.INVENTORY_SIZE:
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
	for c in z.fx_root.get_children():
		if c is Loot and not c.is_queued_for_deletion() and c.collect(): n += 1
	return n
