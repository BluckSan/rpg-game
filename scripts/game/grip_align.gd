extends RefCounted
class_name GripAlign
## Доводка кисти под оружие: поворачивает кость кисти вокруг центра кулака так, чтобы ось хвата
## (ось кулака, от мизинца к большому пальцу = +Z кости кисти) смотрела вверх.
## Применяется к позе кости сразу после анимации (AnimationTree в ручном режиме), поэтому
## и кожа (меш), и BoneAttachment3D с оружием видят одну и ту же позу — кисть реально держит оружие.

var bone := -1
var side := 1.0
var center := Vector3.ZERO   # центр кулака в системе кости кисти
var target_weight := 1.0
var cur := 1.0
var blend_speed := 8.0
var _set_pos = null      # что мы записали в прошлый кадр
var _orig_pos := Vector3.ZERO

func apply(sk: Skeleton3D, delta: float) -> void:
	if sk == null or not is_instance_valid(sk) or bone < 0 or bone >= sk.get_bone_count(): return
	# если анимация не перезаписала позицию кисти — вернуть исходную (иначе смещение накопится)
	if _set_pos != null and sk.get_bone_pose_position(bone).is_equal_approx(_set_pos):
		sk.set_bone_pose_position(bone, _orig_pos)
	_orig_pos = sk.get_bone_pose_position(bone)
	_set_pos = null
	cur = move_toward(cur, target_weight, delta * blend_speed)
	if cur <= 0.001: return
	var gp: Transform3D = sk.get_bone_global_pose(bone)
	var axis := (gp.basis * Vector3(0, 0, 1)).normalized()
	var up := (sk.global_basis.inverse() * Vector3.UP).normalized()
	if axis.dot(up) > 0.9999: return
	if not axis.is_finite() or axis.length() < 0.5: return
	var q := Quaternion.IDENTITY.slerp(Quaternion(axis, up), cur)
	if not q.is_finite(): return
	var grip_c: Vector3 = gp * center
	var ng := Transform3D(Basis(q) * gp.basis, grip_c + Basis(q) * (gp.origin - grip_c))
	var par := sk.get_bone_parent(bone)
	var pg: Transform3D = sk.get_bone_global_pose(par) if par >= 0 else Transform3D.IDENTITY
	var nl: Transform3D = pg.affine_inverse() * ng
	if not nl.origin.is_finite(): return
	var sc := sk.get_bone_pose_scale(bone)
	sk.set_bone_pose_rotation(bone, nl.basis.orthonormalized().get_rotation_quaternion())
	sk.set_bone_pose_position(bone, nl.origin)
	_set_pos = nl.origin
	sk.set_bone_pose_scale(bone, sc)
