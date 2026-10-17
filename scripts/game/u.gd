class_name U
## Общие помощники: материалы, примитивы, эффекты.

static var _mats := {}
static var _fx_mats := {}
static var _meshes := {}

static func mat(c: Color, rough := 0.8, emission := 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f" % [c.to_html(), rough, emission]
	if _mats.has(key): return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if emission > 0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emission
	_mats[key] = m
	return m

static func fx_mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if _fx_mats.has(key): return _fx_mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fx_mats[key] = m
	return m

## Единичные меши (размер 1), масштабируются узлом.
static func mesh(kind: String) -> Mesh:
	if _meshes.has(kind): return _meshes[kind]
	var m: Mesh
	match kind:
		"box": m = BoxMesh.new()
		"sphere":
			var s := SphereMesh.new(); s.radius = 0.5; s.height = 1.0; s.radial_segments = 12; s.rings = 6; m = s
		"capsule":
			var c := CapsuleMesh.new(); c.radius = 0.5; c.height = 2.0; c.radial_segments = 12; c.rings = 4; m = c
		"cylinder":
			var y := CylinderMesh.new(); y.top_radius = 0.5; y.bottom_radius = 0.5; y.height = 2.0; y.radial_segments = 10; y.rings = 1; m = y
		"cone":
			var k := CylinderMesh.new(); k.top_radius = 0.0; k.bottom_radius = 0.5; k.height = 1.0; k.radial_segments = 10; k.rings = 1; m = k
		_: m = BoxMesh.new()
	_meshes[kind] = m
	return m

## Примитив как в Unity: capsule/cylinder высотой 2 при scale.y = 1, sphere/box — 1.
static func prim(kind: String, parent: Node, pos: Vector3, scale: Vector3, c: Color, rough := 0.8, emission := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh(kind)
	mi.material_override = mat(c, rough, emission)
	mi.position = pos
	mi.scale = scale
	parent.add_child(mi)
	return mi

static func flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)

static func flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

# ---------- эффекты ----------
static func burst(parent: Node, pos: Vector3, radius: float, c: Color, dur := 0.35) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh("sphere")
	mi.material_override = fx_mat(Color(c.r, c.g, c.b, 0.45))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 0.2
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * radius * 2.0, dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(mi.queue_free)

static func ring(parent: Node, pos: Vector3, radius: float, c: Color, dur := 0.4) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh("cylinder")
	mi.material_override = fx_mat(Color(c.r, c.g, c.b, 0.4))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos + Vector3.UP * 0.05
	mi.scale = Vector3(0.2, 0.01, 0.2)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(radius * 2, 0.01, radius * 2), dur).set_ease(Tween.EASE_OUT)
	tw.tween_callback(mi.queue_free)

static func telegraph(parent: Node, pos: Vector3, radius: float, dur: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh("cylinder")
	mi.material_override = fx_mat(Color(1, 0.1, 0.05, 0.35))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = Vector3(pos.x, pos.y + 0.04, pos.z)
	mi.scale = Vector3(radius * 2, 0.005, radius * 2)
	mi.get_tree().create_timer(dur, false).timeout.connect(mi.queue_free)

static var _num_font: Font

## Цифры урона: по герою — красные, крит — золотые, иначе — цвет стихии (огонь, лёд, яд…)
static func damage_number(parent: Node, pos: Vector3, amount: float, crit: bool, to_player: bool, elem := "") -> void:
	var t := str(int(round(amount)))
	if crit: t += "!"
	var ec: Color = Combat.ELEM_COLORS.get(elem, Color(1, 0.98, 0.92))
	var c := Color(1, 0.3, 0.25) if to_player else (Color(1, 0.78, 0.15) if crit and elem in ["", "phys"] else (ec.lerp(Color(1, 0.85, 0.3), 0.35) if crit else ec))
	_pop_label(parent, pos, t, c, 0.0016 if crit else 0.0011, crit)

static func float_text(parent: Node, pos: Vector3, text: String, c: Color) -> void:
	_pop_label(parent, pos, text, c, 0.001, false)

static func _pop_label(parent: Node, pos: Vector3, text: String, c: Color, px: float, big: bool) -> void:
	if _num_font == null: _num_font = load("res://fonts/Philosopher-Bold.ttf")
	var l := Label3D.new()
	l.font = _num_font
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.font_size = 56
	l.outline_size = 14
	l.outline_modulate = Color(0.25, 0.08, 0.0) if big else Color(0, 0, 0)
	l.modulate = c
	l.pixel_size = px * 2.0
	parent.add_child(l)
	var side := randf_range(-0.6, 0.6)
	l.global_position = pos + Vector3(side, 0, randf_range(-0.3, 0.3))
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "pixel_size", px, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "global_position", l.global_position + Vector3(side * 0.6, 1.4, 0), 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(l, "modulate:a", 0.0, 0.45).set_delay(0.5)
	tw.chain().tween_callback(l.queue_free)


## Дальность видимости для всех мешей узла (дальние объекты не рисуются; тени — только вблизи)
static func set_view_range(n: Node, d: float) -> void:
	for g in n.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).visibility_range_end = d
		g.add_to_group("view_range_mobs")
