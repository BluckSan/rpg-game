extends Node3D
class_name CameraRig
## Камера от третьего лица на SpringArm3D: поворот свайпом, зум щипком.

var target: Node3D
var yaw := 0.0
var pitch := 38.0
var distance := 11.0
const MIN_DIST := 5.0
const MAX_DIST := 18.0
var pitch_node: Node3D
var arm: SpringArm3D
var camera: Camera3D

func _ready() -> void:
	pitch_node = Node3D.new(); add_child(pitch_node)
	arm = SpringArm3D.new()
	arm.collision_mask = 1
	var sh := SphereShape3D.new(); sh.radius = 0.3
	arm.shape = sh
	arm.margin = 0.2
	pitch_node.add_child(arm)
	camera = Camera3D.new()
	camera.fov = 55; camera.near = 0.3; camera.far = 160
	arm.add_child(camera)
	camera.current = true
	yaw = PI  # камера за спиной персонажа (персонаж смотрит в +Z)

func rotate_by(dx: float, dy: float) -> void:
	yaw -= dx * 0.006
	pitch = clampf(pitch + dy * 0.004 * 57.0, 10, 70)

func zoom_by(k: float) -> void:
	distance = clampf(distance * k, MIN_DIST, MAX_DIST)

func _process(delta: float) -> void:
	if target == null: return
	global_position = global_position.lerp(target.global_position + Vector3.UP * 1.4, minf(1.0, delta * 14))
	rotation.y = yaw
	pitch_node.rotation_degrees.x = -pitch
	arm.spring_length = distance

func _unhandled_input(ev: InputEvent) -> void:
	# мышь — для отладки на ПК
	if ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP: zoom_by(0.9)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN: zoom_by(1.1)
	if ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_RIGHT):
		rotate_by(ev.relative.x, ev.relative.y)
