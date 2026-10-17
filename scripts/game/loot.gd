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
	spawn(z, pos + _rand(), "gold", int(round(randi_range(2, 5) * (1 + lvl * 0.5))))
	if randf() < 0.1: spawn(z, pos + _rand(), "potion", 1)
	if randf() < 0.28:
		spawn(z, pos + _rand(), "item", 1, DB.roll_item(lvl, z.data["class"], 0.0))

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
		var it := DB.roll_item(lvl + 1, d["class"], 0.5)
		if i == 0 and it.rarity < 2:
			while it.rarity < 2: it = DB.roll_item(lvl + 1, d["class"], 0.5)
		if i == 1 and first:
			while it.rarity < 3: it = DB.roll_item(lvl + 1, d["class"], 0.9)
		spawn(z, pos + _rand(2.5), "item", 1, it)
	z.last_boss_drop = {"first": first, "count": 7}

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
	if U.flat_dist(p.global_position, global_position) > 2.0: return
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
				return
			d["inventory"].append(item)
			zone.hud.pickup(item.name, DB.RARITY_COLORS[int(item.rarity)], UIK.item_icon(item, d["class"]))
	queue_free()
