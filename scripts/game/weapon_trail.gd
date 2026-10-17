extends MeshInstance3D
class_name WeaponTrail
## След оружия: лента между двумя точками клинка, затухающая со временем.
## Ставится ребёнком BoneAttachment3D-оружия; base/tip заданы в локальных координатах родителя.

var base_local := Vector3.ZERO
var tip_local := Vector3(0, 1, 0)
var color := Color(1, 0.95, 0.8, 0.8)
var life := 0.18
var emit_time := 0.0
var _pts: Array = []   # [base_global, tip_global, age]
var _im: ImmediateMesh
var _src: Node3D

func setup(src: Node3D, b: Vector3, t: Vector3, c: Color) -> void:
	_src = src; base_local = b; tip_local = t; color = c
	_im = ImmediateMesh.new()
	mesh = _im
	top_level = true
	global_transform = Transform3D.IDENTITY
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func emit(t: float) -> void:
	emit_time = maxf(emit_time, t)

func _process(delta: float) -> void:
	if _src == null or not is_instance_valid(_src): return
	for p in _pts: p[2] += delta
	while _pts.size() > 0 and _pts[0][2] > life: _pts.pop_front()
	if emit_time > 0:
		emit_time -= delta
		var gt := _src.global_transform
		_pts.append([gt * base_local, gt * tip_local, 0.0])
	_im.clear_surfaces()
	if _pts.size() < 2: return
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for p in _pts:
		var k: float = 1.0 - p[2] / life
		_im.surface_set_color(Color(color.r, color.g, color.b, color.a * k * 0.35))
		_im.surface_add_vertex(p[0])
		_im.surface_set_color(Color(color.r, color.g, color.b, color.a * k))
		_im.surface_add_vertex(p[1])
	_im.surface_end()
