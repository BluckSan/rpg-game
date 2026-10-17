extends Node3D
class_name CharVisual
## Персонаж на скелете Universal Animation Library: модульная одежда по классу, редактируемое лицо (морфы),
## цвета кожи/волос/глаз, оружие, облик превращений, монстры-гуманоиды (гоблин, тролль).
## Анимации — AnimationTree: локомоция (BlendSpace1D) + прыжок + разовые действия (OneShot,
## при беге — только верх тела) + смерть.

const UPPER_ROOT := "spine_01"
## Оружие: [кость, модель, "grip" (хват в кулаке — точно по кости кисти) или смещение, поворот, масштаб]
const WEAPONS := {
	"warrior": [["hand_r", "props/sword1", "grip", Vector3.ZERO, 0.42],
		["lowerarm_l", "props/shield1", Vector3(0.0, 0.18, -0.07), Vector3(0, 0, 90), 0.25]],
	"archer": [["hand_l", "props/bow", "grip", Vector3.ZERO, 0.62],
		["spine_03", "props/arrow", Vector3(0.1, 0.05, -0.17), Vector3(10, 0, 150), 0.42],
		["spine_03", "props/arrow", Vector3(0.05, 0.05, -0.18), Vector3(12, 0, 160), 0.42]],
	"mage": [["hand_r", "props/staff", "grip", Vector3.ZERO, 0.58]],
	"goblin": [["hand_r", "props/axe", "grip", Vector3.ZERO, 0.55]],
	"troll": [["hand_r", "props/axe", "grip", Vector3.ZERO, 0.8]],
}
## Хват: точка на оси модели (y в единицах модели), где смыкается кулак, и поворот вокруг оси (°)
const GRIP := {"props/staff": [-0.134, 0.0], "props/sword1": [-0.07, 0.0], "props/axe": [-0.12, 0.0], "props/bow": [0.0, 0.0]}
## Центр кулака в системе кости кисти (измерено по костям пальцев скелета UAL: ладонь — x≈0,
## согнутые пальцы — x≈-0.05, костяшки — y≈0.11; ось кулака — Z, большой палец — +Z)
const GRIP_CENTER_R := Vector3(-0.028, 0.082, 0.0)
static func grip_center(side: float) -> Vector3:
	return Vector3(GRIP_CENTER_R.x * side, GRIP_CENTER_R.y, GRIP_CENTER_R.z)

## Трансформ оружия в кости кисти: ось модели Y идёт по оси кулака (+Z кости), кулак — на точке хвата
static func grip_transform(side: float, prop_name: String, sc: float, roll := 0.0) -> Transform3D:
	var g: Array = GRIP.get(prop_name, [0.0, 0.0])
	var b := Basis(Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0))  # X→Y, Y→Z, Z→X
	b = b * Basis(Vector3.UP, deg_to_rad(float(g[1]) + roll))
	b = b * Basis.from_scale(Vector3.ONE * sc)
	var c := grip_center(side)
	return Transform3D(b, c - b * Vector3(0, float(g[0]), 0))

## Внешность монстров-гуманоидов
const MONSTERS := {
	"goblin": {"look": {"gender": 0, "height": 0.86, "build": 1.25, "head": 1.06, "hair": 0, "brows": 2, "beard": 0,
		"morphs": {"ears_point": 1.0, "ears_size": 1.0, "nose_length": 0.8, "nose_width": 0.6, "jaw_width": 0.7, "brow_depth": 1.0,
			"brow_height": -0.6, "chin": 0.5, "eye_size": -0.35, "mouth_width": 0.5, "lips": 0.3, "cheekbones": 0.5}},
		"skin": Color(0.5, 0.72, 0.36), "eye": Color(1, 0.75, 0.1), "glow": 1.5, "parts": ["Peasant_Legs", "Peasant_Feet"],
		"pants": {"hue": 0.0, "sat": 0.7, "val": 0.6}, "loco": ["idle", "walk", "run"], "attack": ["attack_a", "zombie_attack", "attack_b"]},
	"troll": {"look": {"gender": 0, "height": 2.25, "build": 1.38, "head": 0.94, "hair": 0, "brows": 2, "beard": 1,
		"morphs": {"jaw_width": 1.0, "nose_width": 1.0, "nose_length": 0.4, "brow_depth": 1.0, "brow_height": -0.8, "ears_size": 0.7,
			"ears_point": 0.6, "lips": 0.8, "mouth_width": 0.6, "eye_size": -0.6, "face_width": 0.6, "chin": 0.6, "cheeks": 0.4,
			"beard_length": 0.6, "beard_volume": 0.8}},
		"skin": Color(0.48, 0.56, 0.47), "hair": Color(0.2, 0.2, 0.17), "eye": Color(1, 0.25, 0.08), "glow": 3.0,
		"parts": ["Peasant_Legs"], "pants": {"hue": 0.0, "sat": 0.6, "val": 0.45},
		"loco": ["zombie_idle", "zombie_walk", "run"], "attack": ["attack_heavy", "hook", "attack_c"]},
}

var look: Dictionary = {}
var class_id := "warrior"
var asc_id := ""
var monster := ""
var model: Node3D
var skel: Skeleton3D
var tree: AnimationTree
var meshes := {}
var beast: MobModel
var fx: Node3D
var speed_override := -1.0
var in_air := false
var dead := false
var attack_speed := 1.0
var _gender := -1
var _last_pos := Vector3.ZERO
var _speed := 0.0
var _combo := 0
var _upper_paths: Array[NodePath] = []
var _act_node: AnimationNodeAnimation
var _oneshot: AnimationNodeOneShot
var _run_ref := 4.6
var _loco: AnimationNodeBlendSpace1D
var _idle_name := "idle"
var neutral_pose := false
var weapon: Node3D          # основное оружие (для следа и точки каста)
var weapon_tip := Vector3(0, 1, 0)
var trail: WeaponTrail
var _bow_ba: BoneAttachment3D
var _bow_rest: Array = []
var _bow_aiming := false
var _cur_action := ""
var _cur_kind := ""
const TRAILS := {"props/sword1": [Vector3(0, 0.5, 0), Vector3(0, 2.25, 0)], "props/staff": [Vector3(0, 0.9, 0), Vector3(0, 1.6, 0)],
	"props/axe": [Vector3(0, 0.35, 0), Vector3(0, 0.86, 0)]}

func build(l: Dictionary, cls: String, asc: String, monster_kind := "") -> void:
	class_id = cls; asc_id = asc; monster = monster_kind
	if monster != "":
		var md: Dictionary = MONSTERS[monster]
		look = CharAssets.normalize_look(md.look)
	else:
		look = CharAssets.normalize_look(l)
	for c in get_children(): c.queue_free()
	model = null; beast = null; fx = null; skel = null; tree = null; meshes = {}; weapon = null; trail = null; _bow_ba = null; grips = {}; _bow_aiming = false
	dead = false
	if asc == "druid":
		beast = MobModel.new(); add_child(beast)
		beast.setup("wolf", {"scale": 1.55, "tint": Color(0.75, 0.55, 0.38), "emission": Color(1, 0.6, 0.15)})
		beast.walk_ref = 2.4; beast.run_ref = 6.0
		_build_fx("leaves", Color(0.5, 0.9, 0.3), beast)
		return
	_gender = int(look.gender)
	model = CharAssets.scene(_gender).instantiate()
	add_child(model)
	skel = model.find_child("Skeleton3D", true, false)
	for c in skel.get_children():
		if c is MeshInstance3D:
			meshes[str(c.name)] = c
			(c as MeshInstance3D).visible = false
	_setup_tree()
	apply_look(look)
	_build_weapons()
	if ASC_FX():
		_build_fx(CharAssets.ASC_LOOK[asc_id].fx, CharAssets.ASC_LOOK[asc_id].fx_color, self)
	_last_pos = global_position

func ASC_FX() -> bool:
	return CharAssets.ASC_LOOK.has(asc_id)

# ---------------- внешность ----------------
func _part_visible(n: String, parts: Array) -> bool:
	for p in parts:
		if n.begins_with(p): return true
	return false

## Быстрое обновление внешности без пересоздания модели (для редактора).
func apply_look(l: Dictionary) -> void:
	if model == null:
		return
	if int(l.get("gender", 0)) != _gender and monster == "":
		build(l, class_id, asc_id, monster)
		return
	look = CharAssets.normalize_look(l) if monster == "" else look
	var asc: Dictionary = CharAssets.ASC_LOOK.get(asc_id, {})
	var md: Dictionary = MONSTERS.get(monster, {})
	var outfit: Dictionary = CharAssets.CLASS_OUTFIT.get(class_id, CharAssets.CLASS_OUTFIT["warrior"])
	var parts: Array = md.get("parts", outfit.parts).duplicate()
	var hood: bool = asc.get("hood", false)
	if hood: parts.append("Ranger_Head_Hood")
	var hair_mesh: String = CharAssets.HAIR_STYLES[int(look.hair)][1]
	var brow_mesh: String = CharAssets.BROW_STYLES[int(look.brows)][1]
	# цвета
	var tone: Color = md.get("skin", CharAssets.SKIN[int(look.skin)])
	if asc.has("skin_mul"): tone = tone * (asc.skin_mul as Color)
	var hair_c: Color = md.get("hair", CharAssets.HAIR[int(look.hair_color)])
	var eye_c: Color = md.get("eye", asc.get("eye", CharAssets.EYES[int(look.eye_color)]))
	var glow: float = md.get("glow", asc.get("glow", 0.0))
	var o := {"hue": outfit.hue, "sat": outfit.sat, "val": outfit.val, "metal": outfit.get("metal", 0.0), "thr": outfit.get("thr", 0.22)}
	if md.has("pants"): o = md.pants.duplicate()
	for k in ["hue", "sat", "val", "metal", "rough", "emis", "emis_k"]:
		if asc.has(k): o[k] = asc[k]
	var skin_emis := Color(0.25, 0.02, 0.0) if asc_id == "berserker" else Color.BLACK
	for n in meshes:
		var mi: MeshInstance3D = meshes[n]
		var vis := false
		if n == "Face" or n == "Eyes": vis = true
		elif n == "Torso": vis = monster != ""
		elif n.begins_with("Brows_"): vis = n == brow_mesh
		elif n == "Beard": vis = int(look.beard) == 1
		elif n.begins_with("Hair_"): vis = n == hair_mesh and not hood
		else: vis = _part_visible(n, parts)
		if monster != "" and n.begins_with("Peasant_Arms"): vis = false
		mi.visible = vis
		if not vis: continue
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if not (n == "Eyes" or n.begins_with("Brows")) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			var mn: String = src.resource_name if src else ""
			var m: Material = null
			match mn:
				"skin_head": m = CharAssets.skin_mat("head_" + ("f" if _gender == 1 else "m"), tone, skin_emis)
				"skin_body": m = CharAssets.skin_mat("body_m", tone, skin_emis)
				"skin_arms": m = CharAssets.skin_mat("arms_" + ("f" if _gender == 1 else "m"), tone, skin_emis)
				"eyes": m = CharAssets.eye_mat(eye_c, glow)
				"hair1", "hair2": m = CharAssets.hair_mat(mn, hair_c)
				"ranger", "peasant": m = CharAssets.outfit_mat(mn, o)
			if m: mi.set_surface_override_material(i, m)
		# морфы
		var bc: int = mi.mesh.get_blend_shape_count() if mi.mesh is ArrayMesh else 0
		for b in bc:
			var bn := str((mi.mesh as ArrayMesh).get_blend_shape_name(b))
			mi.set_blend_shape_value(b, float(look.morphs.get(bn, 0.0)))
	# пропорции тела
	var h: float = clampf(float(look.height), 0.85, 2.5) * float(asc.get("scale", 1.0))
	model.scale = Vector3.ONE * h
	var b: float = clampf(float(look.build), 0.75, 1.45)
	_scale_bone("spine_02", Vector3(b, 1, lerpf(1.0, b, 0.7)))
	_scale_bone("neck_01", Vector3(1.0 / b, 1, 1.0 / lerpf(1.0, b, 0.7)))
	_scale_bone("thigh_l", Vector3(lerpf(1, b, 0.6), 1, lerpf(1, b, 0.6)))
	_scale_bone("thigh_r", Vector3(lerpf(1, b, 0.6), 1, lerpf(1, b, 0.6)))
	_scale_bone(_head_bone(), Vector3.ONE * clampf(float(look.head), 0.85, 1.15))

## Кость головы (Godot переименовывает её в Head_2 при совпадении имён узлов)
func _head_bone() -> String:
	for n in ["Head", "Head_2"]:
		if skel.find_bone(n) >= 0: return n
	return "neck_01"

func _scale_bone(bone: String, s: Vector3) -> void:
	var i := skel.find_bone(bone)
	if i >= 0: skel.set_bone_pose_scale(i, s)

func set_morph(key: String, v: float) -> void:
	look.morphs[key] = v
	for n in meshes:
		var mi: MeshInstance3D = meshes[n]
		var bi := mi.find_blend_shape_by_name(key)
		if bi >= 0: mi.set_blend_shape_value(bi, v)

# ---------------- оружие ----------------
func _build_weapons() -> void:
	var list: Array = WEAPONS.get(monster if monster != "" else class_id, [])
	for w in list:
		var bi := skel.find_bone(w[0])
		if bi < 0: continue
		var ba := BoneAttachment3D.new(); ba.bone_name = w[0]
		skel.add_child(ba)
		var inst: Node3D = CharAssets.prop(w[1]).instantiate()
		ba.add_child(inst)
		if w[2] is String:
			var side := 1.0 if w[0].ends_with("_r") else -1.0
			inst.transform = grip_transform(side, w[1], float(w[4]))
			_add_grip(w[0], w[1])
		else:
			inst.position = w[2]; inst.rotation_degrees = w[3]; inst.scale = Vector3.ONE * float(w[4])
		if w[1] == "props/staff":
			_staff_orb(inst, TRAILS[w[1]][1])
		if weapon == null and TRAILS.has(w[1]):
			weapon = inst
			weapon_tip = TRAILS[w[1]][1]
			trail = WeaponTrail.new()
			add_child(trail)
			var tc := Color(1, 0.95, 0.85, 0.9)
			if CharAssets.ASC_LOOK.has(asc_id): tc = CharAssets.ASC_LOOK[asc_id].fx_color
			elif class_id == "mage": tc = Color(0.5, 0.75, 1.0, 0.9)
			elif monster != "": tc = Color(1, 0.5, 0.3, 0.7)
			trail.setup(inst, TRAILS[w[1]][0], TRAILS[w[1]][1], tc)
		elif weapon == null and w[1] == "props/bow":
			weapon = inst; weapon_tip = Vector3(0, 1.0, 0)
			_bow_ba = ba; _bow_rest = [w[0], inst.transform, float(w[4])]
		if asc_id == "paladin" or asc_id == "elementalist" or asc_id == "berserker":
			_tint_weapon(inst, CharAssets.ASC_LOOK[asc_id].fx_color)

## Доводка кисти: посох и лук в покое/на бегу стоят вертикально
var grips := {}   # кость -> GripAlign
func _add_grip(bone_name: String, prop_name: String) -> void:
	if not prop_name in ["props/staff", "props/bow", "props/sword1"]: return
	var m := GripAlign.new()
	m.name = "Grip_" + bone_name
	skel.add_child(m)
	m.side = 1.0 if bone_name.ends_with("_r") else -1.0
	m.setup(bone_name)
	grips[bone_name] = m

## Вес доводки в зависимости от действия
func _update_grips() -> void:
	if grips.is_empty(): return
	var acting := is_acting()
	for bn in grips:
		var g: GripAlign = grips[bn]
		var w := 1.0
		if class_id == "mage":
			# удары посохом и броски заклинаний — по анимации; стойка/бег/каст — посох вертикально
			# заклинания — посох навершием вверх; взмахи посохом (комбо) — по анимации
			if acting and not (_cur_action in ["cast", "cast_enter", "consume", "cheer", "interact", "hit"] \
					or _cur_kind in ["fireball", "frost_nova", "meteor", "summon", "drink", "hit", "pickup", "cheer"]): w = 0.0
		elif class_id == "warrior":
			# меч в стойке — клинок чуть вверх, а не вбок; в ударах — по анимации
			w = 0.0 if acting else 0.45
		else:
			w = 0.0 if _bow_aiming or (acting and _cur_action in ["roll", "dash"]) else 0.85
		if dead: w = 0.0
		g.target_weight = w

## Светящийся кристалл на навершии посоха
func _staff_orb(inst: Node3D, tip: Vector3) -> void:
	var c := Color(0.45, 0.75, 1.0)
	if CharAssets.ASC_LOOK.has(asc_id): c = CharAssets.ASC_LOOK[asc_id].fx_color
	var orb := MeshInstance3D.new()
	var sm := SphereMesh.new(); sm.radius = 0.09; sm.height = 0.18; sm.radial_segments = 12; sm.rings = 6
	orb.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = c; m.emission_enabled = true; m.emission = c; m.emission_energy_multiplier = 2.5
	orb.material_override = m
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.add_child(orb); orb.position = tip - Vector3(0, 0.12, 0)
	var halo := MeshInstance3D.new()
	var q := QuadMesh.new(); q.size = Vector2(0.55, 0.55)
	halo.mesh = q
	var hm: StandardMaterial3D = CombatFX._mat(Color(c.r, c.g, c.b, 0.45)).duplicate()
	hm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	halo.material_override = hm
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	orb.add_child(halo)
	var l := OmniLight3D.new(); l.light_color = c; l.light_energy = 0.6; l.omni_range = 2.2; l.shadow_enabled = false
	orb.add_child(l)

func _tint_weapon(n: Node, c: Color) -> void:
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			if src is StandardMaterial3D:
				var nm := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
				nm.emission_enabled = true; nm.emission = c; nm.emission_energy_multiplier = 0.35
				mi.set_surface_override_material(i, nm)

# ---------------- эффекты превращений ----------------
func _build_fx(kind: String, c: Color, parent: Node3D) -> void:
	fx = Node3D.new(); fx.name = "FX"; parent.add_child(fx)
	match kind:
		"halo":
			var ba := BoneAttachment3D.new(); ba.bone_name = _head_bone(); skel.add_child(ba)
			var t := MeshInstance3D.new(); var tm := TorusMesh.new(); tm.inner_radius = 0.13; tm.outer_radius = 0.155; tm.rings = 24; tm.ring_segments = 8
			t.mesh = tm; t.material_override = U.fx_mat(Color(c.r, c.g, c.b, 0.95)); t.position = Vector3(0, 0.3, -0.02)
			t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ba.add_child(t)
			var l := OmniLight3D.new(); l.light_color = c; l.light_energy = 0.9; l.omni_range = 3.5; l.position = Vector3(0, 2.2, 0.2); fx.add_child(l)
			_particles(fx, c, 10, 1.2, 0.04, Vector3(0, 1.0, 0), 0.5)
		"orbs":
			var spin := Node3D.new(); spin.set_script(preload("res://scripts/game/spin.gd")); fx.add_child(spin); spin.position = Vector3(0, 1.25, 0)
			var cols := [Color(1, 0.4, 0.1), Color(0.4, 0.8, 1), Color(0.8, 0.6, 1)]
			for i in 3:
				var o := U.prim("sphere", spin, Vector3(0.75, 0, 0).rotated(Vector3.UP, TAU * i / 3.0), Vector3.ONE * 0.16, cols[i], 0.2, 4.0)
				o.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var l := OmniLight3D.new(); l.light_color = c; l.light_energy = 1.0; l.omni_range = 4.0; l.position = Vector3(0, 1.4, 0); fx.add_child(l)
		"embers":
			_particles(fx, c, 22, 1.4, 0.05, Vector3(0, 0.9, 0), 0.6)
			var l := OmniLight3D.new(); l.light_color = c; l.light_energy = 0.6; l.omni_range = 3.0; l.position = Vector3(0, 1.2, 0); fx.add_child(l)
		"smoke":
			_particles(fx, c, 16, 1.6, 0.07, Vector3(0, 0.4, 0), 0.45)
			var l := OmniLight3D.new(); l.light_color = c; l.light_energy = 0.5; l.omni_range = 3.0; l.position = Vector3(0, 1.4, 0.3); fx.add_child(l)
		"leaves":
			_particles(fx, c, 14, 1.6, 0.06, Vector3(0, 0.8, 0), 0.8)

func _particles(parent: Node3D, c: Color, n: int, life: float, size: float, at: Vector3, spread: float) -> void:
	var p := CPUParticles3D.new()
	p.amount = n; p.lifetime = life; p.position = at
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE; p.emission_sphere_radius = spread
	p.direction = Vector3.UP; p.spread = 25; p.gravity = Vector3(0, 0.6, 0)
	p.initial_velocity_min = 0.2; p.initial_velocity_max = 0.6
	p.scale_amount_min = 0.6; p.scale_amount_max = 1.2
	var m := SphereMesh.new(); m.radius = size; m.height = size * 2; m.radial_segments = 6; m.rings = 3
	m.material = U.fx_mat(Color(c.r, c.g, c.b, 0.7))
	p.mesh = m
	var g := Gradient.new(); g.set_color(0, Color(1, 1, 1, 0.9)); g.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = g
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)

# ---------------- анимации ----------------
func _setup_tree() -> void:
	var lib := CharAssets.anim_library(_gender)
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	model.add_child(tree)
	tree.add_animation_library("h", lib)
	tree.root_node = NodePath("..")
	var loco_names: Array = MONSTERS[monster].loco if monster != "" else ["idle_sword" if class_id == "warrior" else "idle", "walk", "run"]
	var bt := AnimationNodeBlendTree.new()
	var loco := AnimationNodeBlendSpace1D.new()
	loco.min_space = 0.0; loco.max_space = 8.0
	var pts := [[loco_names[0], 0.0], [loco_names[1], 1.6], [loco_names[2], 4.6], ["sprint", 7.5]]
	for pt in pts:
		var a := AnimationNodeAnimation.new(); a.animation = "h/" + pt[0]
		loco.add_blend_point(a, pt[1], -1, StringName(pt[0]))
	bt.add_node("loco", loco)
	_loco = loco; _idle_name = loco_names[0]
	if neutral_pose: (loco.get_blend_point_node(0) as AnimationNodeAnimation).animation = "h/idle"
	var loco_ts := AnimationNodeTimeScale.new(); bt.add_node("loco_ts", loco_ts)
	bt.connect_node("loco_ts", 0, "loco")
	var air_a := AnimationNodeAnimation.new(); air_a.animation = "h/jump_air"; bt.add_node("air_anim", air_a)
	var air := AnimationNodeBlend2.new(); bt.add_node("air", air)
	bt.connect_node("air", 0, "loco_ts"); bt.connect_node("air", 1, "air_anim")
	_act_node = AnimationNodeAnimation.new(); _act_node.animation = "h/attack_a"; bt.add_node("act_anim", _act_node)
	var ts := AnimationNodeTimeScale.new(); bt.add_node("act_ts", ts)
	bt.connect_node("act_ts", 0, "act_anim")
	_oneshot = AnimationNodeOneShot.new(); _oneshot.fadein_time = 0.08; _oneshot.fadeout_time = 0.22
	bt.add_node("act", _oneshot)
	bt.connect_node("act", 0, "air"); bt.connect_node("act", 1, "act_ts")
	var death_a := AnimationNodeAnimation.new(); death_a.animation = "h/death"; bt.add_node("death_anim", death_a)
	var seek := AnimationNodeTimeSeek.new(); bt.add_node("death_seek", seek)
	bt.connect_node("death_seek", 0, "death_anim")
	var dead_b := AnimationNodeBlend2.new(); bt.add_node("dead", dead_b)
	bt.connect_node("dead", 0, "act"); bt.connect_node("dead", 1, "death_seek")
	bt.connect_node("output", 0, "dead")
	tree.tree_root = bt
	# фильтр «верх тела» для действий на бегу
	_upper_paths.clear()
	var ui := skel.find_bone(UPPER_ROOT)
	for i in skel.get_bone_count():
		var j := i
		while j >= 0 and j != ui: j = skel.get_bone_parent(j)
		if j == ui:
			var path := NodePath(str(model.get_path_to(skel)) + ":" + skel.get_bone_name(i))
			_upper_paths.append(path)
			_oneshot.set_filter_path(path, true)
	tree.active = true
	tree.set("parameters/act_ts/scale", 1.0)
	tree.set("parameters/loco_ts/scale", 1.0)

## Список: [анимация, скорость, только верх тела на бегу]
func _action_anim(kind: String) -> Array:
	if monster != "":
		var at: Array = MONSTERS[monster].attack
		match kind:
			"attack":
				_combo = (_combo + 1) % at.size()
				return [at[_combo], 1.25 if monster == "goblin" else 1.0, true]
			"slam": return ["attack_heavy", 1.4, false]
			"hit": return ["hit", 1.3, true]
			"roar": return ["cheer", 1.0, false]
			"throw": return ["throw", 0.9, false]
			"charge": return ["attack_heavy", 0.8, false]
			"stomp": return ["attack_heavy", 1.1, false]
	match kind:
		"attack":
			match class_id:
				"warrior":
					_combo = (_combo + 1) % 3
					return [["attack_a", "attack_b", "attack_c"][_combo], 1.35 * attack_speed, true]
				"archer": return ["bow_shoot", 1.6 * attack_speed, true]
				_:
					_combo = (_combo + 1) % 2
					return [["attack_a", "attack_b"][_combo], 1.4 * attack_speed, true]
		"spin": return ["attack_combo", 1.9, false]
		"dash": return ["dash", 1.4, false]
		"volley": return ["bow_shoot", 1.3, true]
		"arrow_rain": return ["throw", 1.5, true]
		"fireball": return ["sword_attack", 1.4, true]
		"frost_nova": return ["attack_heavy", 1.25, false]
		"rage": return ["punch_b", 1.0, false]
		"holy_shield": return ["block", 1.0, true]
		"meteor": return ["attack_c", 1.0, true]
		"summon": return ["cast_enter", 1.0, true]
		"shadow_strike": return ["attack_heavy", 2.4, false]
		"jump": return ["jump_start", 1.6, false]
		"land": return ["jump_land", 1.6, false]
		"hit": return ["hit", 1.4, true]
		"drink": return ["consume", 1.6, true]
		"cheer": return ["cheer", 1.0, false]
		"pickup": return ["interact", 1.5, true]
		"roll": return ["roll", 1.5, false]
		"beast_roar": return ["cheer", 1.3, false]
	return ["attack_a", 1.2, true]

func play_action(kind: String) -> void:
	if beast:
		var ba := {"attack": "attack", "beast_roar": "roar", "hit": "hit", "jump": "spawn"}
		if ba.has(kind) or kind in ["spin", "dash", "rage"]: beast.play_action(ba.get(kind, "attack"), 1.4)
		return
	if tree == null or dead: return
	var a := _action_anim(kind)
	var lib := CharAssets.anim_library(_gender)
	if not lib.has_animation(a[0]): return
	_act_node.animation = "h/" + a[0]
	_cur_action = a[0]
	_cur_kind = kind
	_oneshot.filter_enabled = bool(a[2]) and _speed > 0.6
	tree.set("parameters/act_ts/scale", a[1])
	tree.set("parameters/act/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	if kind in ["spin", "dash", "shadow_strike", "slam", "charge", "stomp"] or (kind == "attack" and monster != ""): swing(0.5)

## Спокойная стойка (для редактора лица): голова прямо, без боевой позы
func set_neutral(v: bool) -> void:
	neutral_pose = v
	if _loco and _loco.get_blend_point_count() > 0:
		(_loco.get_blend_point_node(0) as AnimationNodeAnimation).animation = "h/" + ("idle" if v else _idle_name)

## Произвольная анимация из библиотеки (для комбо и особых атак)
func play_anim(anim: String, speed := 1.0, upper := true, trail_time := 0.0) -> void:
	if beast:
		beast.play_action("attack", speed)
		return
	if tree == null or dead: return
	if not CharAssets.anim_library(_gender).has_animation(anim): return
	_act_node.animation = "h/" + anim
	_cur_action = anim
	_cur_kind = ""
	_oneshot.filter_enabled = upper and _speed > 0.6
	tree.set("parameters/act_ts/scale", speed)
	tree.set("parameters/act/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	if trail_time > 0: swing(trail_time)

## След оружия на время взмаха
func swing(t: float) -> void:
	if trail: trail.emit(t)

## Мировая позиция кончика оружия (точка каста)
func tip_position() -> Vector3:
	if weapon and is_instance_valid(weapon): return weapon.global_transform * weapon_tip
	return global_position + Vector3.UP * 1.4 + global_basis.z * 0.5

## Узел у кончика оружия (для свечения каста)
func tip_node() -> Node3D:
	var n := Node3D.new()
	if weapon and is_instance_valid(weapon):
		weapon.add_child(n); n.position = weapon_tip
	else:
		add_child(n); n.position = Vector3(0, 1.4, 0.5)
	n.top_level = false
	get_tree().create_timer(1.0).timeout.connect(n.queue_free)
	return n

func play_attack() -> void:
	play_action("attack")

func is_acting() -> bool:
	return tree != null and bool(tree.get("parameters/act/active"))

func set_dead(v: bool) -> void:
	if beast:
		beast.set_dead(v)
		return
	dead = v
	if tree:
		if v:
			tree.set("parameters/act/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
			tree.set("parameters/death_seek/seek_request", 0.0)
		tree.set("parameters/dead/blend_amount", 1.0 if v else 0.0)

## Лук: в покое — в левой руке; при выстреле — перед грудью в правой руке, тетивой к себе
func _update_bow() -> void:
	if _bow_ba == null or not is_instance_valid(_bow_ba): return
	var aim := is_acting() and _cur_action in ["bow_shoot", "bow_aim", "throw"]
	if aim == _bow_aiming: return
	_bow_aiming = aim
	var w: Node3D = _bow_ba.get_child(0)
	if aim:
		_bow_ba.bone_name = "hand_r"
		w.transform = grip_transform(1.0, "props/bow", _bow_rest[2], 180.0)
	else:
		_bow_ba.bone_name = _bow_rest[0]
		w.transform = _bow_rest[1]

func _process(delta: float) -> void:
	var p := global_position
	var v := Vector2(p.x - _last_pos.x, p.z - _last_pos.z).length() / maxf(delta, 0.0001)
	_last_pos = p
	if v > 30: v = 0.0  # телепорт
	var target := v if speed_override < 0 else speed_override
	_speed = lerpf(_speed, target, minf(1.0, delta * 10))
	if beast:
		beast.speed_override = _speed
		return
	if tree == null: return
	_update_bow()
	_update_grips()
	var s := _speed / maxf(0.5, model.scale.x if monster != "" else 1.0)
	tree.set("parameters/loco/blend_position", clampf(s, 0, 8))
	tree.set("parameters/loco_ts/scale", 1.0 if s < 5.5 else clampf(s / 5.5, 1.0, 1.4))
	var air_now: float = tree.get("parameters/air/blend_amount")
	tree.set("parameters/air/blend_amount", move_toward(air_now, 1.0 if in_air else 0.0, delta * 6))
