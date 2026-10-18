class_name Tele
## Наземные метки: зоны предупреждения (круг, конус, кольцо), зоны умений, молнии.
## Все меши — плоские, без теней, аддитивные/прозрачные (дёшево и на телефоне).

static var _disc_mesh: Mesh

static func _flat_mat(c: Color, add := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if add: m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = c
	m.no_depth_test = false
	m.render_priority = 1
	return m

## Сектор круга (веер треугольников) радиуса 1 в плоскости XZ, ось — +Z
static func fan_mesh(angle_deg: float, inner := 0.0, segs := 32) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a0 := -deg_to_rad(angle_deg) / 2.0
	var step := deg_to_rad(angle_deg) / segs
	for i in segs:
		var a := a0 + step * i; var b := a + step
		var pa := Vector3(sin(a), 0, cos(a)); var pb := Vector3(sin(b), 0, cos(b))
		if inner <= 0.0:
			st.add_vertex(Vector3.ZERO); st.add_vertex(pa); st.add_vertex(pb)
		else:
			st.add_vertex(pa * inner); st.add_vertex(pa); st.add_vertex(pb)
			st.add_vertex(pa * inner); st.add_vertex(pb); st.add_vertex(pb * inner)
	return st.commit()

static func disc_mesh() -> Mesh:
	if _disc_mesh == null: _disc_mesh = fan_mesh(360.0, 0.0, 48)
	return _disc_mesh

## Метка на земле. kind: disc | cone | ring. Возвращает узел; fill (дочерний) растёт по мере каста.
static func make(parent: Node, kind: String, pos: Vector3, radius: float, c: Color, dir := Vector3.FORWARD, angle := 90.0, inner := 0.0) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos + Vector3.UP * 0.06
	if dir.length() > 0.01: root.rotation.y = atan2(dir.x, dir.z)
	var m: Mesh
	match kind:
		"cone": m = fan_mesh(angle, inner)   # v0.9.1: inner > 0 — усечённый сектор (тень за колонной)
		"ring": m = fan_mesh(360.0, inner, 48)
		_: m = disc_mesh()
	var base := MeshInstance3D.new(); base.mesh = m; base.name = "Base"
	base.material_override = _flat_mat(Color(c.r, c.g, c.b, 0.28))
	base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	base.scale = Vector3(radius, 1, radius)
	root.add_child(base)
	var edge := MeshInstance3D.new(); edge.name = "Edge"
	edge.mesh = fan_mesh(angle if kind == "cone" else 360.0, 0.96, 48)
	edge.material_override = _flat_mat(Color(c.r, c.g, c.b, 0.9), true)
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	edge.scale = Vector3(radius, 1, radius)
	edge.position.y = 0.01
	root.add_child(edge)
	var fill := MeshInstance3D.new(); fill.mesh = m; fill.name = "Fill"
	fill.material_override = _flat_mat(Color(c.r, c.g, c.b, 0.35), true)
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fill.scale = Vector3(0.01, 1, 0.01)
	fill.position.y = 0.02
	root.add_child(fill)
	root.set_meta("radius", radius)
	return root

## Заполнение метки 0..1 (сколько осталось до удара)
static func set_progress(t: Node3D, k: float) -> void:
	if t == null or not is_instance_valid(t): return
	var r: float = t.get_meta("radius", 1.0)
	var f: MeshInstance3D = t.get_node_or_null("Fill")
	if f: f.scale = Vector3(maxf(0.01, r * k), 1, maxf(0.01, r * k))

static func free_later(t: Node3D, delay := 0.0) -> void:
	if t == null or not is_instance_valid(t): return
	if delay <= 0.0: t.queue_free(); return
	var tw := t.create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(t.queue_free)

## Ломаная молния между двумя точками
static func bolt(parent: Node, a: Vector3, b: Vector3, c: Color, dur := 0.25, width := 0.09) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 8
	var pts: Array[Vector3] = [a]
	var d := b - a
	var side := d.cross(Vector3.UP).normalized()
	if side.length() < 0.1: side = Vector3.RIGHT
	for i in range(1, n):
		var k := float(i) / n
		pts.append(a + d * k + side * randf_range(-0.35, 0.35) + Vector3.UP * randf_range(-0.25, 0.25))
	pts.append(b)
	for i in n:
		var p0 := pts[i]; var p1 := pts[i + 1]
		var w0 := side * width; var w1 := Vector3.UP * width
		for w in [w0, w1]:
			st.add_vertex(p0 - w); st.add_vertex(p0 + w); st.add_vertex(p1 + w)
			st.add_vertex(p0 - w); st.add_vertex(p1 + w); st.add_vertex(p1 - w)
	var mi := MeshInstance3D.new(); mi.mesh = st.commit()
	var m := _flat_mat(Color(c.r, c.g, c.b, 1.0), true)
	m.albedo_color = Color(c.r * 1.5, c.g * 1.5, c.b * 1.5, 1)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	var tw := mi.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, dur)
	tw.tween_callback(mi.queue_free)
