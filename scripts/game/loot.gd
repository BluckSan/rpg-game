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
	spawn(z, pos + _rand(), "gold", int(round(randi_range(2, 5) * (1 + lvl * 0.5) * (10 if boss else 1))))
	if randf() < (1.0 if boss else 0.1): spawn(z, pos + _rand(), "potion", 1)
	var n := 3 if boss else (1 if randf() < 0.28 else 0)
	for i in n:
		spawn(z, pos + _rand(), "item", 1, DB.roll_item(lvl, z.data["class"], 0.3 if boss else 0.0))

static func _rand() -> Vector3:
	var r := Vector2.from_angle(randf() * TAU) * randf() * 1.2
	return Vector3(r.x, 0, r.y)

static func spawn(z, pos: Vector3, t: String, n: int, it := {}) -> Loot:
	var l := Loot.new()
	l.zone = z; l.type = t; l.amount = n; l.item = it
	z.fx_root.add_child(l)
	l.global_position = Vector3(pos.x, 0, pos.z)
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
			zone.hud.pickup("+%d золота" % amount, Color(1, 0.85, 0.35))
		"potion":
			d["potions"] += amount
			zone.hud.pickup("+1 зелье лечения", Color(1, 0.4, 0.4))
		_:
			if d["inventory"].size() >= DB.INVENTORY_SIZE:
				Game.toast("Инвентарь полон!", 1.5)
				age = -2.0
				return
			d["inventory"].append(item)
			zone.hud.pickup(item.name, DB.RARITY_COLORS[int(item.rarity)])
	queue_free()
