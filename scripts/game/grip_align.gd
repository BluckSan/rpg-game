extends SkeletonModifier3D
class_name GripAlign
## Доводка кисти под оружие: поворачивает кость кисти так, чтобы ось хвата (ось кулака,
## от мизинца к большому пальцу = +Z кости кисти) смотрела вверх. Посох/лук держатся вертикально
## в покое и на бегу; во время ударов вес снижается, и работает исходная анимация.

var bone := -1
var side := 1.0
var target_weight := 1.0      # к чему плавно стремится влияние
var cur := 1.0
var blend_speed := 8.0

func setup(bone_name: String) -> void:
	bone = get_skeleton().find_bone(bone_name) if get_skeleton() else -1

func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null: return
	if bone < 0: return
	cur = move_toward(cur, target_weight, delta * blend_speed)
	if cur <= 0.001: return
	var gp: Transform3D = sk.get_bone_global_pose(bone)
	var axis := (gp.basis * Vector3(0, 0, 1)).normalized()
	var up := (sk.global_basis.inverse() * Vector3.UP).normalized()
	if axis.dot(up) > 0.9999: return
	var q := Quaternion(axis, up)
	q = Quaternion.IDENTITY.slerp(q, cur)
	# поворот вокруг центра хвата — кулак остаётся на месте
	var grip_c: Vector3 = gp * CharVisual.grip_center(side)
	var nb := Basis(q) * gp.basis
	var no := grip_c + Basis(q) * (gp.origin - grip_c)
	sk.set_bone_global_pose(bone, Transform3D(nb, no))
