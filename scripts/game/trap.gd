extends Node3D
class_name Trap
## Ловушка подземелья. «spikes» — плита с шипами, «fire» — огненная струя поперёк коридора.
## Цикл: покой → предупреждение (красное свечение, искры) → удар (урон % здоровья) → покой. Сдвиг фазы
## у соседних ловушек — всегда есть окно, чтобы пройти.

var zone
var kind := "spikes"
var half := Vector2(2.0, 2.0)   # полуразмеры по X/Z (локально)
var period := 3.2
var warn_t := 1.0
var active_t := 0.7
var phase_off := 0.0
var dmg_frac := 0.35
var hits := 0
var _t := 0.0
var _hit_this := false
var _plate: MeshInstance3D
var _glow_mat: StandardMaterial3D
var _spikes: Node3D
var _flame: Node3D
var state := "idle"

static func create(z, parent: Node, k: String, pos: Vector3, hx: float, hz: float, off: float) -> Trap:
	var t := Trap.new()
	t.zone = z; t.kind = k; t.half = Vector2(hx, hz); t.phase_off = off
	if k == "fire":
		t.period = 3.0; t.warn_t = 0.8; t.active_t = 1.0; t.dmg_frac = 0.4
	parent.add_child(t)
	t.global_position = pos
	t._build()
	return t

func _build() -> void:
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.albedo_color = Color(0.25, 0.08, 0.06)
	_glow_mat.emission_enabled = true
	_glow_mat.emission = Color(1, 0.2, 0.05)
	_glow_mat.emission_energy_multiplier = 0.0
	_plate = MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(half.x * 2, 0.06, half.y * 2)
	_plate.mesh = bm; _plate.material_override = _glow_mat
	_plate.position.y = 0.03
	_plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_plate)
	if kind == "spikes":
		_spikes = Node3D.new(); add_child(_spikes)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var cone := CylinderMesh.new(); cone.top_radius = 0.0; cone.bottom_radius = 0.09; cone.height = 0.7; cone.radial_segments = 5
		mm.mesh = cone
		var pts := []
		var x := -half.x + 0.35
		while x < half.x:
			var zz := -half.y + 0.35
			while zz < half.y:
				pts.append(Vector3(x, 0.35, zz)); zz += 0.7
			x += 0.7
		mm.instance_count = pts.size()
		for i in pts.size(): mm.set_instance_transform(i, Transform3D(Basis(), pts[i]))
		var mi := MultiMeshInstance3D.new(); mi.multimesh = mm
		mi.material_override = U.mat(Color(0.7, 0.7, 0.75), 0.4)
		_spikes.add_child(mi)
		_spikes.scale = Vector3(1, 0.01, 1)
		_spikes.position.y = -0.3
	else:
		_flame = Node3D.new(); add_child(_flame)
		var f := U.prim("box", _flame, Vector3(0, 1.0, 0), Vector3(half.x * 2, 2.0, half.y * 1.6), Color(1, 0.5, 0.1))
		f.material_override = U.fx_mat(Color(1, 0.45, 0.1, 0.55))
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_flame.visible = false
		for s in [-1, 1]:   # сопла в стенах
			U.prim("cylinder", self, Vector3(s * (half.x + 0.1), 1.0, 0), Vector3(0.5, 0.25, 0.5), Color(0.2, 0.18, 0.18)).rotation_degrees.z = 90

func inside(p: Vector3) -> bool:
	var l := to_local(p)
	return absf(l.x) <= half.x + 0.2 and absf(l.z) <= half.y + 0.2

## Опасна ли ловушка сейчас (для тестов)
func is_active() -> bool: return state == "active"

func _process(delta: float) -> void:
	_t += delta
	var c := fposmod(_t + phase_off, period)
	var idle_t := period - warn_t - active_t
	var ns := "idle"
	if c >= idle_t + warn_t: ns = "active"
	elif c >= idle_t: ns = "warn"
	if ns != state:
		state = ns
		if ns == "active": _hit_this = false
		if kind == "fire": _flame.visible = ns == "active"
		if ns == "warn": CombatFX.burst(zone.fx_root, global_position + Vector3.UP * 0.3, Color(1, 0.4, 0.1), 8, 2.0, 0.06, 0.5, Vector3.UP, 60, 0)
	match state:
		"warn": _glow_mat.emission_energy_multiplier = 1.5 + 1.5 * sin(_t * 18.0)
		"active": _glow_mat.emission_energy_multiplier = 3.0
		_: _glow_mat.emission_energy_multiplier = 0.0
	if _spikes:
		var target_y := 1.0 if state == "active" else (0.15 if state == "warn" else 0.01)
		_spikes.scale.y = move_toward(_spikes.scale.y, target_y, delta * 12.0)
		_spikes.position.y = -0.3 + 0.3 * _spikes.scale.y
	if state == "active" and not _hit_this:
		var p = zone.player
		if p and not p.dead and inside(p.global_position) and p.global_position.y < 1.6:
			_hit_this = true
			hits += 1
			p.take_damage(p.stats.max_hp * dmg_frac, global_position)
			zone.float_text(p.global_position + Vector3.UP * 2.6, "Ловушка!", Color(1, 0.5, 0.3))
