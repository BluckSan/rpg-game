extends RefCounted
class_name ArmPose
## Поза руки поверх анимации: поворачивает плечо и предплечье так, чтобы они смотрели в заданных
## направлениях (в системе персонажа: x — влево от персонажа, y — вверх, z — вперёд).
## Нужна лучнику в стойке: кисть с луком вынесена вперёд-влево, лук не задевает ноги.

var upper := -1
var lower := -1
var hand := -1
var upper_dir := Vector3(0.3, -1.0, 0.45)
var lower_dir := Vector3(0.15, -0.12, 1.0)
var target_weight := 0.0
var cur := 0.0
var blend_speed := 5.0

func setup(sk: Skeleton3D, upper_name: String, lower_name: String, hand_name: String) -> void:
	upper = sk.find_bone(upper_name); lower = sk.find_bone(lower_name); hand = sk.find_bone(hand_name)

func apply(sk: Skeleton3D, owner_basis: Basis, delta: float) -> void:
	cur = move_toward(cur, target_weight, delta * blend_speed)
	if cur <= 0.001 or sk == null or not is_instance_valid(sk): return
	var n := sk.get_bone_count()
	if upper < 0 or lower < 0 or hand < 0 or upper >= n or lower >= n or hand >= n: return
	var to_sk := sk.global_basis.inverse() * owner_basis   # оси персонажа -> пространство скелета
	_aim(sk, upper, lower, (to_sk * upper_dir).normalized())
	_aim(sk, lower, hand, (to_sk * lower_dir).normalized())

func _aim(sk: Skeleton3D, b: int, child: int, want: Vector3) -> void:
	var gp: Transform3D = sk.get_bone_global_pose(b)
	var cp: Transform3D = sk.get_bone_global_pose(child)
	var d := cp.origin - gp.origin
	if d.length() < 0.0001 or not want.is_finite() or want.length() < 0.5: return
	d = d.normalized()
	if d.dot(want) > 0.99999: return
	var q := Quaternion.IDENTITY.slerp(Quaternion(d, want), cur)
	if not q.is_finite(): return
	var nb := Basis(q) * gp.basis
	var par := sk.get_bone_parent(b)
	var pg: Transform3D = sk.get_bone_global_pose(par) if par >= 0 else Transform3D.IDENTITY
	var lb := pg.basis.orthonormalized().inverse() * nb.orthonormalized()
	var lq := lb.get_rotation_quaternion()
	if lq.is_finite(): sk.set_bone_pose_rotation(b, lq.normalized())
