extends Node3D
class_name RemotePlayer
## Другой игрок в онлайн-режиме: та же модель героя (внешность, класс, путь), имя над головой,
## плавное следование за снимками сервера; анимация шага — по скорости (CharVisual сам считает её по смещению).

var visual: CharVisual
var label: Label3D
var _init_done := false

static func create(zone_scene: Node, r: Dictionary) -> RemotePlayer:
	var n := RemotePlayer.new()
	n.name = "Remote_%s" % str(r.name).validate_node_name()
	zone_scene.add_child(n)
	n.global_position = r.pos
	n.rotation.y = r.yaw
	n.visual = CharVisual.new()
	n.add_child(n.visual)
	var look: Dictionary = (r.look as Dictionary).duplicate(true) if r.look is Dictionary else {}
	for k in ["gender", "skin", "face", "hair", "hair_color", "eye_color"]: look[k] = int(look.get(k, 0))
	n.visual.build(CharAssets.normalize_look(look), r["class"], r.asc)
	n.label = Label3D.new()
	n.label.text = "%s · %d" % [r.name, r.level]
	n.label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	n.label.no_depth_test = true
	n.label.font_size = 42; n.label.outline_size = 10
	n.label.modulate = Color(0.75, 0.9, 1.0)
	n.label.position = Vector3(0, 2.25, 0)
	n.label.pixel_size = 0.004
	n.add_child(n.label)
	n.add_to_group("remote_players")
	return n

func step(delta: float, pos: Vector3, yaw: float, hp: float) -> void:
	if global_position.distance_to(pos) > 12.0: global_position = pos   # телепорт / рывок
	else: global_position = global_position.lerp(pos, minf(1.0, delta * 10.0))
	rotation.y = lerp_angle(rotation.y, yaw, minf(1.0, delta * 12.0))
	if visual: visual.set_dead(hp <= 0.0)

func act(kind: String, anim: String, speed: float) -> void:
	if visual == null: return
	if anim != "": visual.play_anim(anim, speed, true)
	elif kind != "": visual.play_action(kind)
