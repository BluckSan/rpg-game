extends Node3D
class_name Lever
## Рычаг: столб с рукоятью и цветным кристаллом. Переключается взаимодействием (кнопка/E).

var id := ""
var color := Color.WHITE
var on := false
var _arm: Node3D
var _gem: MeshInstance3D

static func create(parent: Node, lid: String, pos: Vector3, c: Color) -> Lever:
	var l := Lever.new()
	l.id = lid; l.color = c
	parent.add_child(l)
	l.global_position = pos
	l._build()
	return l

func _build() -> void:
	U.prim("box", self, Vector3(0, 0.5, 0), Vector3(0.7, 1.0, 0.5), Color(0.35, 0.33, 0.38))
	_arm = Node3D.new(); add_child(_arm); _arm.position = Vector3(0, 1.0, 0)
	U.prim("cylinder", _arm, Vector3(0, 0.45, 0), Vector3(0.12, 0.45, 0.12), Color(0.4, 0.3, 0.2))
	_gem = U.prim("sphere", _arm, Vector3(0, 0.95, 0), Vector3.ONE * 0.32, color, 0.3, 2.0)
	_arm.rotation_degrees.x = -35
	var l := OmniLight3D.new(); l.light_color = color; l.light_energy = 0.8; l.omni_range = 4.0
	add_child(l); l.position = Vector3(0, 2.0, 0)

func set_on(v: bool) -> void:
	on = v
	var tw := create_tween()
	tw.tween_property(_arm, "rotation_degrees:x", 35.0 if v else -35.0, 0.25)
