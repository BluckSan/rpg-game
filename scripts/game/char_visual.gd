extends Node3D
class_name CharVisual
## Модель персонажа из примитивов + процедурная анимация (ходьба, удар, превращения).

var root: Node3D
var body: Node3D
var leg_l: Node3D
var leg_r: Node3D
var arm_l: Node3D
var arm_r: Node3D
var orbit: Node3D
var beast := false
var walk_phase := 0.0
var attack_t := -1.0
var speed_override := -1.0
var _last_pos := Vector3.ZERO
var _base_scale := 1.0

func build(look: Dictionary, class_id: String, asc_id: String) -> void:
	if root: root.queue_free()
	root = Node3D.new(); root.name = "Model"
	add_child(root)
	orbit = null
	beast = asc_id == "druid"
	var cls: Dictionary = DB.CLASSES[class_id]
	var skin: Color = DB.SKIN_COLORS[clampi(int(look.get("skin", 0)), 0, 7)]
	var hair: Color = DB.HAIR_COLORS[clampi(int(look.get("hair_color", 0)), 0, 7)]
	var eye: Color = DB.EYE_COLORS[clampi(int(look.get("eye_color", 0)), 0, 5)]
	var cloth: Color = cls.color * 0.8; cloth.a = 1
	var pants := Color(0.25, 0.22, 0.2)
	var eye_glow := 0.0
	match asc_id:
		"necromancer": skin = skin.lerp(Color(0.8, 0.8, 0.85), 0.6); cloth = Color(0.2, 0.1, 0.3); eye = Color(0.6, 1, 0.6); eye_glow = 2.0
		"shadow": cloth = Color(0.1, 0.1, 0.14); pants = cloth; eye = Color(0.7, 0.3, 1); eye_glow = 2.0
		"berserker": eye = Color(1, 0.15, 0.05); eye_glow = 2.5
		"paladin": cloth = Color(0.85, 0.85, 0.9)
		"elementalist": cloth = Color(0.15, 0.3, 0.7); eye = Color(0.5, 0.9, 1); eye_glow = 1.5
	var h := clampf(float(look.get("height", 1.0)), 0.8, 1.2)
	var b := clampf(float(look.get("build", 1.0)), 0.75, 1.3)
	var female := int(look.get("gender", 0)) == 1
	var shoulder := (0.42 if female else 0.5) * b
	var hip := (0.4 if female else 0.36) * b
	_base_scale = h * (1.12 if asc_id == "berserker" else 1.0)
	root.scale = Vector3.ONE * _base_scale
	if beast:
		_build_beast(hair)
		return
	body = Node3D.new(); root.add_child(body)
	leg_l = _pivot(Vector3(-hip * 0.4, 0.9, 0)); leg_r = _pivot(Vector3(hip * 0.4, 0.9, 0))
	for leg in [leg_l, leg_r]:
		U.prim("capsule", leg, Vector3(0, -0.45, 0), Vector3(0.2 * b, 0.45, 0.2 * b), pants)
		U.prim("box", leg, Vector3(0, -0.86, 0.06), Vector3(0.2 * b, 0.1, 0.3), Color(0.3, 0.2, 0.12))
	U.prim("box", body, Vector3(0, 0.95, 0), Vector3(hip, 0.22, 0.26 * b), pants)
	U.prim("capsule", body, Vector3(0, 1.27, 0), Vector3(shoulder, 0.36, 0.28 * b), cloth)
	if female:
		U.prim("sphere", body, Vector3(0, 1.36, 0.09), Vector3(shoulder * 0.75, 0.17, 0.15), cloth)
	U.prim("box", body, Vector3(0, 1.08, 0), Vector3(shoulder * 0.95, 0.07, 0.3 * b), Color(0.35, 0.22, 0.1))
	arm_l = _pivot(Vector3(-shoulder * 0.62, 1.52, 0)); arm_r = _pivot(Vector3(shoulder * 0.62, 1.52, 0))
	for arm in [arm_l, arm_r]:
		U.prim("capsule", arm, Vector3(0, -0.3, 0), Vector3(0.15 * b, 0.32, 0.15 * b), cloth)
		U.prim("sphere", arm, Vector3(0, -0.64, 0), Vector3.ONE * 0.13, skin)
	var head := Node3D.new(); body.add_child(head); head.position = Vector3(0, 1.84, 0)
	U.prim("cylinder", body, Vector3(0, 1.66, 0), Vector3(0.13, 0.06, 0.13), skin)
	var face := int(look.get("face", 0))
	U.prim("sphere", head, Vector3.ZERO, Vector3(0.3 if face == 1 else 0.34, 0.38, 0.34), skin, 0.6)
	U.prim("sphere", head, Vector3(0, -0.02, 0.17), Vector3(0.06, 0.08, 0.06), skin * 0.95)
	for sx in [-0.075, 0.075]:
		U.prim("sphere", head, Vector3(sx, 0.04, 0.145), Vector3(0.075, 0.06, 0.04), Color.WHITE)
		U.prim("sphere", head, Vector3(sx, 0.04, 0.162), Vector3(0.04, 0.045, 0.02), eye, 0.3, eye_glow)
		U.prim("box", head, Vector3(sx, 0.11, 0.15), Vector3(0.08, 0.015, 0.02), hair)
	if face == 2 and not female:
		U.prim("sphere", head, Vector3(0, -0.13, 0.08), Vector3(0.28, 0.2, 0.24), hair)
	if face == 3:
		U.prim("box", head, Vector3(0.08, 0, 0.165), Vector3(0.015, 0.14, 0.01), Color(0.6, 0.25, 0.25))
	_build_hair(head, int(look.get("hair", 0)), hair)
	_build_weapon(class_id)
	_build_asc_extras(asc_id, head)

func _pivot(p: Vector3) -> Node3D:
	var t := Node3D.new(); body.add_child(t); t.position = p
	return t

func _build_hair(head: Node3D, style: int, c: Color) -> void:
	match style:
		0: U.prim("sphere", head, Vector3(0, 0.07, -0.02), Vector3(0.37, 0.3, 0.37), c)
		1: U.prim("sphere", head, Vector3(0, 0.1, -0.01), Vector3(0.35, 0.24, 0.35), c)
		2:
			U.prim("sphere", head, Vector3(0, 0.07, -0.02), Vector3(0.38, 0.31, 0.38), c)
			U.prim("box", head, Vector3(0, -0.2, -0.12), Vector3(0.36, 0.5, 0.14), c)
		3:
			U.prim("sphere", head, Vector3(0, 0.07, -0.02), Vector3(0.37, 0.3, 0.37), c)
			U.prim("capsule", head, Vector3(0, -0.12, -0.22), Vector3(0.1, 0.22, 0.1), c)
		4: U.prim("box", head, Vector3(0, 0.2, -0.02), Vector3(0.07, 0.18, 0.36), c)

func _build_weapon(class_id: String) -> void:
	var hand := Node3D.new()
	match class_id:
		"archer":
			arm_l.add_child(hand); hand.position = Vector3(0, -0.66, 0.05)
			U.prim("cylinder", hand, Vector3(0, 0, 0.05), Vector3(0.04, 0.5, 0.04), Color(0.45, 0.28, 0.12))
			U.prim("cylinder", hand, Vector3(0, 0, -0.05), Vector3(0.008, 0.48, 0.008), Color.WHITE)
		"mage":
			arm_r.add_child(hand); hand.position = Vector3(0, -0.66, 0.05)
			U.prim("cylinder", hand, Vector3(0, 0.25, 0.05), Vector3(0.05, 0.75, 0.05), Color(0.35, 0.22, 0.1))
			U.prim("sphere", hand, Vector3(0, 1.02, 0.05), Vector3.ONE * 0.16, Color(0.4, 0.7, 1), 0.2, 2.0)
		_:
			arm_r.add_child(hand); hand.position = Vector3(0, -0.66, 0.05)
			U.prim("box", hand, Vector3(0, 0, 0.42), Vector3(0.06, 0.03, 0.8), Color(0.75, 0.77, 0.8), 0.3)
			U.prim("box", hand, Vector3(0, 0, 0.02), Vector3(0.22, 0.05, 0.05), Color(0.5, 0.35, 0.1))

func _build_asc_extras(asc_id: String, head: Node3D) -> void:
	match asc_id:
		"berserker":
			for s in [-1, 1]:
				var sp := U.prim("box", body, Vector3(s * 0.3, 1.62, 0), Vector3(0.08, 0.25, 0.08), Color(0.4, 0.05, 0.05))
				sp.rotation_degrees = Vector3(0, 0, -s * 30)
		"paladin":
			for s in [-1, 1]:
				U.prim("sphere", body, Vector3(s * 0.3, 1.55, 0), Vector3(0.28, 0.16, 0.3), Color(1, 0.8, 0.25), 0.3)
			U.prim("cylinder", head, Vector3(0, 0.33, 0), Vector3(0.36, 0.01, 0.36), Color(1, 0.9, 0.4), 0.2, 3.0)
		"elementalist", "necromancer", "shadow":
			orbit = Node3D.new(); root.add_child(orbit); orbit.position = Vector3(0, 1.4, 0)
			var cols: Array
			if asc_id == "elementalist": cols = [Color(1, 0.4, 0.1), Color(0.4, 0.8, 1), Color(1, 1, 0.4)]
			elif asc_id == "necromancer": cols = [Color(0.9, 0.9, 0.8), Color(0.9, 0.9, 0.8)]
			else: cols = [Color.BLACK, Color.BLACK, Color.BLACK, Color.BLACK]
			for i in cols.size():
				var ang := i * TAU / cols.size()
				var shadow := asc_id == "shadow"
				var r := 0.35 if shadow else 0.75
				var o := U.prim("sphere", orbit, Vector3(cos(ang) * r, (-0.8 + i * 0.4) if shadow else 0.3, sin(ang) * r),
					Vector3.ONE * (0.5 if shadow else 0.18), cols[i], 0.5, 0.0 if shadow else 2.0)
				if shadow:
					o.material_override = U.fx_mat(Color(0.1, 0.05, 0.15, 0.45))

func _build_beast(fur: Color) -> void:
	fur = fur.lerp(Color(0.35, 0.22, 0.12), 0.6)
	body = Node3D.new(); root.add_child(body)
	_base_scale *= 1.25
	root.scale = Vector3.ONE * _base_scale
	U.prim("capsule", body, Vector3(0, 0.95, 0), Vector3(0.85, 0.75, 0.85), fur).rotation_degrees = Vector3(90, 0, 0)
	var head := Node3D.new(); body.add_child(head); head.position = Vector3(0, 1.25, 0.8)
	U.prim("sphere", head, Vector3.ZERO, Vector3(0.55, 0.5, 0.55), fur)
	U.prim("sphere", head, Vector3(0, -0.08, 0.25), Vector3(0.28, 0.22, 0.3), fur * 1.3)
	U.prim("sphere", head, Vector3(0, -0.02, 0.4), Vector3.ONE * 0.08, Color.BLACK)
	for s in [-1, 1]:
		U.prim("sphere", head, Vector3(s * 0.2, 0.25, -0.05), Vector3(0.15, 0.15, 0.08), fur)
		U.prim("sphere", head, Vector3(s * 0.12, 0.08, 0.24), Vector3.ONE * 0.06, Color(0.9, 0.9, 0.3), 0.3, 2.0)
	leg_l = _pivot(Vector3(-0.3, 0.7, 0.45)); leg_r = _pivot(Vector3(0.3, 0.7, 0.45))
	arm_l = _pivot(Vector3(-0.3, 0.7, -0.45)); arm_r = _pivot(Vector3(0.3, 0.7, -0.45))
	for l in [leg_l, leg_r, arm_l, arm_r]:
		U.prim("capsule", l, Vector3(0, -0.35, 0), Vector3(0.28, 0.38, 0.28), fur * 0.9)

func play_attack() -> void:
	attack_t = 0.0

func _process(delta: float) -> void:
	if root == null or body == null: return
	var p := global_position
	var spd := speed_override if speed_override >= 0 else U.flat_dist(p, _last_pos) / maxf(delta, 0.0001)
	_last_pos = p
	var moving := clampf(spd / 4.0, 0, 1)
	walk_phase += delta * (4.0 + spd * 1.6)
	var swing := sin(walk_phase) * 38.0 * moving
	leg_l.rotation_degrees = Vector3(swing, 0, 0)
	leg_r.rotation_degrees = Vector3(-swing, 0, 0)
	if beast:
		arm_l.rotation_degrees = Vector3(-swing, 0, 0)
		arm_r.rotation_degrees = Vector3(swing, 0, 0)
	else:
		arm_l.rotation_degrees = Vector3(-swing * 0.7, 0, -6)
		if attack_t >= 0:
			attack_t += delta / 0.3
			var k := attack_t / 0.4 if attack_t < 0.4 else 1.0 - (attack_t - 0.4) / 0.6
			arm_r.rotation_degrees = Vector3(-150.0 * clampf(k, 0, 1), 0, 6)
			if attack_t >= 1: attack_t = -1
		else:
			arm_r.rotation_degrees = Vector3(swing * 0.7, 0, 6)
	body.position = Vector3(0, absf(sin(walk_phase)) * 0.05 * moving + sin(Time.get_ticks_msec() * 0.002) * 0.01, 0)
	if orbit:
		orbit.rotation.y += delta * PI / 2
