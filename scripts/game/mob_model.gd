extends Node3D
class_name MobModel
## Анимированная модель монстра из glTF (Quaternius, CC0): 20+ семейств (см. DEFS).
## Материалы — общие из импорта (без копий), кроме перекраски по запросу; LOD мешей — при импорте, дальность видимости 70 м.
## Локомоция определяется по фактической скорости узла; действия — разовые анимации.

const DEFS := {
	"slime": {"scene": "mobs/slime", "scale": 0.4, "pre": "CharacterArmature|",
		"anims": {"idle": "Idle", "walk": "Walk", "run": "Walk", "attack": "Bite_Front", "hit": "HitRecieve", "death": "Death", "spawn": "Jump"}},
	"wolf": {"scene": "mobs/wolf", "scale": 0.33, "pre": "",
		"anims": {"idle": "Idle", "walk": "Walk", "run": "Gallop", "attack": "Attack", "hit": "Idle_HitReact_Left", "death": "Death", "roar": "Idle_2_HeadLow", "spawn": "Jump_ToIdle"}},
	"skeleton": {"scene": "mobs/skeleton", "scale": 0.35, "pre": "SkeletonArmature|Skeleton_",
		"anims": {"idle": "Idle", "walk": "Running", "run": "Running", "attack": "Attack", "hit": "Idle", "death": "Death", "spawn": "Spawn"}},
	# v0.9.5: Кел'Таар — временная модель (скелет + процедурные корона, мантия, посох). Если появится
	# res://assets/mobs/lich/keltaar.glb (Pigcraft, CC-BY), setup() возьмёт её — см. LICH_GLB / LICH_GLB_DEF
	"lich": {"scene": "mobs/skeleton", "scale": 0.35, "pre": "SkeletonArmature|Skeleton_", "regalia": true,
		"anims": {"idle": "Idle", "walk": "Running", "run": "Running", "attack": "Attack", "hit": "Idle", "death": "Death", "spawn": "Spawn", "cast": "Attack"}},
	# --- v0.5.1: семейства монстров (Quaternius, CC0: Ultimate Monsters, Animated Animals, Enemies) ---
	"rat": {"scene": "mobs/rat", "scale": 0.36, "pre": "RatArmature|Rat_",
		"anims": {"idle": "Idle", "walk": "Walk", "run": "Run", "attack": "Attack", "hit": "Idle", "death": "Death", "spawn": "Jump"}},
	"bull": {"scene": "mobs/bull", "scale": 0.36, "pre": "AnimalArmature|",
		"anims": {"idle": "Idle", "walk": "Walk", "run": "Gallop", "attack": "Attack_Headbutt", "attack2": "Attack_Kick", "hit": "Idle_HitReact_Left", "death": "Death", "roar": "Idle_Headlow", "charge": "Gallop", "spawn": "Jump_toIdle"}},
	"spider": {"scene": "mobs/spider", "scale": 0.3, "pre": "SpiderArmature|Spider_",
		"anims": {"idle": "Idle", "walk": "Walk", "run": "Walk", "attack": "Attack", "hit": "Idle", "death": "Death", "spawn": "Jump"}},
	"bat": {"scene": "mobs/bat", "scale": 0.17, "pre": "BatArmature|Bat_", "hover": 1.3,
		"anims": {"idle": "Flying", "walk": "Flying", "run": "Flying", "attack": "Attack", "attack2": "Attack2", "hit": "Hit", "death": "Death", "spawn": "Flying"}},
	"bee": {"scene": "mobs/bee", "scale": 0.36, "pre": "MonsterArmature|", "hover": 1.0,
		"anims": {"idle": "Flying", "walk": "Flying", "run": "Flying", "attack": "Bite_Front", "hit": "HitRecieve", "death": "Death", "spawn": "Flying"}},
	"crab": {"scene": "mobs/crab", "scale": 0.6, "pre": "MonsterArmature|",
		"anims": {"idle": "Idle", "walk": "Walk", "run": "Walk", "attack": "Bite_Front", "attack2": "Bite_InPlace", "hit": "HitRecieve", "death": "Death", "roar": "Dance", "spawn": "Jump"}},
	"goblin_q": {"scene": "mobs/goblin_q", "scale": 0.6, "pre": "EnemyArmature|EnemyArmature|EnemyArmature|",
		"anims": {"idle": "Idle", "walk": "Walk", "run": "Run", "attack": "Attack", "cast": "Jump", "hit": "HitRecieve", "death": "Death", "spawn": "Jump"}},
	# гуманоиды Ultimate Monsters (общий скелет CharacterArmature)
	"orc": {"scene": "mobs/orc", "scale": 0.57, "pre": "CharacterArmature|", "humanoid": true,
		"anims": {"idle": "Idle", "walk": "Walk", "run": "Run", "attack": "Punch", "attack2": "Weapon", "cast": "Wave", "hit": "HitReact", "death": "Death", "roar": "Yes", "slam": "Jump_Land", "throw": "Weapon", "charge": "Run", "spawn": "Jump_Land"}},
	"frog": {"scene": "mobs/frog", "scale": 0.4, "pre": "CharacterArmature|", "humanoid": true,
		"anims": {"idle": "Idle", "walk": "Walk", "run": "Run", "attack": "Punch", "attack2": "Weapon", "cast": "Wave", "hit": "HitReact", "death": "Death", "roar": "Yes", "slam": "Jump_Land", "throw": "Weapon", "charge": "Jump", "spawn": "Jump_Land"}},
	"bluedemon": {"scene": "mobs/bluedemon", "scale": 0.38, "pre": "CharacterArmature|", "humanoid": true,
		"anims": {"idle": "Idle", "walk": "Walk", "run": "Run2", "attack": "Punch", "attack2": "Weapon", "cast": "Wave", "hit": "HitReact", "death": "Death", "roar": "Yes", "slam": "Jump_Land", "throw": "Weapon", "charge": "Run2", "spawn": "Jump_Land"}},
	"mushking": {"scene": "mobs/mushking", "scale": 0.5, "pre": "CharacterArmature|", "humanoid": true,
		"anims": {"idle": "Idle", "walk": "Walk", "run": "Run", "attack": "Punch", "attack2": "Weapon", "cast": "Wave", "hit": "HitReact", "death": "Death", "roar": "Yes", "slam": "Jump_Land", "throw": "Weapon", "charge": "Run", "spawn": "Jump_Land"}},
	# «колобки» (Bite_Front)
	"mushnub": {"scene": "mobs/mushnub", "scale": 0.27, "pre": "CharacterArmature|",
		"anims": {"idle": "Idle", "walk": "Walk", "run": "Walk", "attack": "Bite_Front", "hit": "HitRecieve", "death": "Death", "roar": "Dance", "spawn": "Jump"}},
	"cactoro": {"scene": "mobs/cactoro", "scale": 0.36, "pre": "CharacterArmature|",
		"anims": {"idle": "Idle", "walk": "Walk", "run": "Walk", "attack": "Bite_Front", "cast": "Yes", "hit": "HitRecieve", "death": "Death", "roar": "Dance", "spawn": "Jump"}},
	"yeti": {"scene": "mobs/yeti", "scale": 0.9, "pre": "CharacterArmature|",
		"anims": {"idle": "Idle", "walk": "Walk", "run": "Walk", "attack": "Bite_Front", "cast": "Yes", "hit": "HitRecieve", "death": "Death", "roar": "Dance", "slam": "Jump", "throw": "Yes", "charge": "Walk", "spawn": "Jump"}},
	# летуны (Flying_Idle / Fast_Flying)
	"demon": {"scene": "mobs/demon", "scale": 0.8, "pre": "CharacterArmature|",
		"anims": {"idle": "Flying_Idle", "walk": "Flying_Idle", "run": "Fast_Flying", "attack": "Punch", "attack2": "Headbutt", "cast": "Yes", "hit": "HitReact", "death": "Death", "roar": "Yes", "slam": "Headbutt", "throw": "Punch", "charge": "Fast_Flying", "spawn": "Flying_Idle"}},
	"drake": {"scene": "mobs/drake", "scale": 0.6, "pre": "CharacterArmature|",
		"anims": {"idle": "Flying_Idle", "walk": "Flying_Idle", "run": "Fast_Flying", "attack": "Headbutt", "attack2": "Punch", "cast": "Yes", "hit": "HitReact", "death": "Death", "roar": "Yes", "slam": "Headbutt", "throw": "Punch", "charge": "Fast_Flying", "spawn": "Flying_Idle"}},
	"dragon": {"scene": "mobs/dragon", "scale": 0.6, "pre": "CharacterArmature|",
		"anims": {"idle": "Flying_Idle", "walk": "Flying_Idle", "run": "Fast_Flying", "attack": "Punch", "attack2": "Headbutt", "cast": "Yes", "hit": "HitReact", "death": "Death", "roar": "Yes", "slam": "Headbutt", "throw": "Punch", "charge": "Fast_Flying", "spawn": "Flying_Idle"}},
	"ghost": {"scene": "mobs/ghost", "scale": 0.6, "pre": "CharacterArmature|",
		"anims": {"idle": "Flying_Idle", "walk": "Flying_Idle", "run": "Fast_Flying", "attack": "Punch", "attack2": "Headbutt", "cast": "Yes", "hit": "HitReact", "death": "Death", "roar": "No", "slam": "Headbutt", "throw": "Punch", "charge": "Fast_Flying", "spawn": "Flying_Idle"}},
	"imp": {"scene": "mobs/imp", "scale": 0.65, "pre": "CharacterArmature|",
		"anims": {"idle": "Flying_Idle", "walk": "Flying_Idle", "run": "Fast_Flying", "attack": "Punch", "attack2": "Headbutt", "cast": "Yes", "hit": "HitReact", "death": "Death", "roar": "Yes", "slam": "Headbutt", "throw": "Punch", "charge": "Fast_Flying", "spawn": "Flying_Idle"}},
	"hywirl": {"scene": "mobs/hywirl", "scale": 0.7, "pre": "CharacterArmature|",
		"anims": {"idle": "Flying_Idle", "walk": "Flying_Idle", "run": "Fast_Flying", "attack": "Punch", "attack2": "Headbutt", "cast": "Yes", "hit": "HitReact", "death": "Death", "roar": "Yes", "slam": "Headbutt", "throw": "Punch", "charge": "Fast_Flying", "spawn": "Flying_Idle"}},
}

var kind := ""
var def: Dictionary
var root: Node3D
var ap: AnimationPlayer
var skel: Skeleton3D
var speed_override := -1.0
var walk_ref := 2.0
var run_ref := 5.0
var dead := false
var _action := ""
var _last_pos := Vector3.ZERO
var _speed := 0.0
var _cur := ""

## Хук импорта модели лича: положите GLB сюда — масштаб/префикс/имена анимаций правятся в LICH_GLB_DEF
const LICH_GLB := "res://assets/mobs/lich/keltaar.glb"
## v0.9.5: модель Pigcraft «Skeletal Lich King in Bone Crown and Robes» (CC-BY 4.0) статична (без скелета) —
## прорежена до ~16k (ПК) / ~5k (телефон) треугольников с цветом в вершинах (tools/lich_lod.mjs), а оживлена
## процедурно: парение, наклон при скольжении, замах посохом, подъём при касте, вздрагивание, распад при смерти.
const LICH_GLB_LO := "res://assets/mobs/lich/keltaar_lo.glb"
const LICH_GLB_DEF := {"scene": "mobs/lich/keltaar", "scale": 1.3, "pre": "", "proc": true,
	"anims": {"idle": "idle", "walk": "walk", "run": "walk", "attack": "attack", "hit": "hit", "death": "death", "spawn": "spawn", "cast": "cast"}}
var proc := false
var _pt := 0.0          # время процедурной анимации
var _pa := ""           # текущее процедурное действие
var _pa_t := 0.0
var _pa_dur := 1.0
var _body: Node3D       # узел, который качаем (внутри root)

func setup(k: String, opts := {}) -> MobModel:
	kind = k
	def = DEFS[k]
	if k == "lich" and ResourceLoader.exists(LICH_GLB): def = LICH_GLB_DEF
	var scn: String = def.scene
	if def.get("proc", false) and (Game.quality <= 1 or not Game.desktop) and ResourceLoader.exists(LICH_GLB_LO): scn = "mobs/lich/keltaar_lo"
	root = CharAssets.prop(scn).instantiate()
	add_child(root)
	var s: float = def.scale * float(opts.get("scale", 1.0))
	root.scale = Vector3.ONE * s
	if def.has("hover"): root.position.y = float(def.hover) * float(opts.get("scale", 1.0))
	ap = root.find_child("AnimationPlayer", true, false)
	skel = root.find_child("Skeleton3D", true, false)
	if ap:
		ap.animation_finished.connect(_on_finished)
		for a in ["idle", "walk", "run"]:
			var n := _name(a)
			if ap.has_animation(n): ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
		for a in ["attack", "attack2", "cast", "hit", "death", "spawn", "roar", "slam", "throw"]:
			var n := _name(a)
			if ap.has_animation(n) and not a in ["idle"]: ap.get_animation(n).loop_mode = Animation.LOOP_NONE
	if opts.has("tint") or opts.has("emission"):
		_tint(opts.get("tint", Color.WHITE), opts.get("emission", Color.BLACK), float(opts.get("metal", -1.0)))
	for m in root.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).visibility_range_end = 70.0
		(m as MeshInstance3D).visibility_range_end_margin = 6.0
	if def.get("regalia", false): _lich_regalia(float(opts.get("scale", 1.0)))
	if def.get("proc", false): _proc_setup()
	_play("idle", 0.0)
	_last_pos = global_position
	return self

## Временные регалии Короля-Лича на скелете: корона из костяных шипов, мантия, посох с филактерией, глаза
func _lich_regalia(sc: float) -> void:
	if skel == null: return
	var k: float = skel.global_basis.get_scale().x / maxf(0.0001, global_basis.get_scale().x)
	if k <= 0.0001: k = def.scale * sc
	var bone := Color(0.86, 0.84, 0.76); var ice := Color(0.45, 1.0, 0.85); var cloth := Color(0.1, 0.13, 0.17)
	var head := _bone_node("Head", k)
	if head:
		var crown := Node3D.new(); head.add_child(crown); crown.position = Vector3(0, 0.3, 0) * sc / k
		U.prim("cylinder", crown, Vector3.ZERO, Vector3(0.34, 0.035, 0.34) * sc / k, bone, 0.6)
		for i in 7:
			var a := TAU * i / 7.0
			var sp := U.prim("cone", crown, Vector3(cos(a) * 0.15, 0.1, sin(a) * 0.15) * sc / k, Vector3(0.06, 0.24 if i % 2 == 0 else 0.15, 0.06) * sc / k, bone, 0.6)
			sp.rotation = Vector3(sin(a) * 0.25, 0, -cos(a) * 0.25)
		U.prim("sphere", crown, Vector3(0, 0.05, 0.17) * sc / k, Vector3.ONE * 0.06 * sc / k, ice, 0.2, 3.0)
		for x in [-0.055, 0.055]:
			U.prim("sphere", head, Vector3(x, 0.14, 0.12) * sc / k, Vector3.ONE * 0.045 * sc / k, ice, 0.2, 4.0)
	var hips := _bone_node("Torso", k)
	if hips:
		var robe := U.prim("cylinder", hips, Vector3(0, -0.28, 0) * sc / k, Vector3(0.62, 0.5, 0.5) * sc / k, cloth, 0.9)
		var rm := StandardMaterial3D.new(); rm.albedo_color = cloth; rm.roughness = 0.95
		robe.mesh = _robe_mesh(); robe.material_override = rm
		robe.scale = Vector3.ONE * sc / k
		var trim := U.prim("cylinder", hips, Vector3(0, -0.02, 0) * sc / k, Vector3(0.36, 0.02, 0.3) * sc / k, ice, 0.3, 1.5)
		trim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for x in [-0.2, 0.2]:   # наплечники
			var pd := U.prim("sphere", hips, Vector3(x, 0.32, 0) * sc / k, Vector3(0.2, 0.12, 0.2) * sc / k, bone, 0.6)
			U.prim("cone", pd, Vector3(0, 0.6, 0), Vector3(0.35, 1.2, 0.35), bone, 0.6)
	var hand := _bone_node("R.DownLeg.001", k)
	if hand:
		var st := Node3D.new(); hand.add_child(st); st.position = Vector3(0, 0.1, 0) * sc / k
		st.scale = Vector3.ONE * sc / k
		U.prim("cylinder", st, Vector3(0, 0.1, 0), Vector3(0.035, 0.75, 0.035), Color(0.25, 0.3, 0.33), 0.5)
		U.prim("sphere", st, Vector3(0, 0.9, 0), Vector3(0.09, 0.14, 0.09), ice, 0.1, 4.0)
		for i in 3:
			var a := TAU * i / 3.0
			var cl := U.prim("cone", st, Vector3(cos(a) * 0.07, 0.86, sin(a) * 0.07), Vector3(0.035, 0.22, 0.035), bone, 0.6)
			cl.rotation = Vector3(sin(a) * -0.4, 0, cos(a) * 0.4)

func _bone_node(bone: String, _k: float) -> Node3D:
	if skel.find_bone(bone) < 0: return null
	var ba := BoneAttachment3D.new(); ba.bone_name = bone
	skel.add_child(ba)
	return ba

static var _robe: ArrayMesh
## Мантия: расширяющийся книзу рваный конус (единичный, ~1.1 м)
static func _robe_mesh() -> ArrayMesh:
	if _robe: return _robe
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 14
	for i in n:
		var a0 := TAU * i / n; var a1 := TAU * (i + 1) / n
		var r0 := 0.18; var r1 := 0.42
		var j0 := 1.0 + (0.12 if i % 2 == 0 else -0.05); var j1 := 1.0 + (0.12 if (i + 1) % 2 == 0 else -0.05)
		var t0 := Vector3(cos(a0) * r0, 0.15, sin(a0) * r0); var t1 := Vector3(cos(a1) * r0, 0.15, sin(a1) * r0)
		var b0 := Vector3(cos(a0) * r1, -0.95 * j0, sin(a0) * r1); var b1 := Vector3(cos(a1) * r1, -0.95 * j1, sin(a1) * r1)
		for v in [t0, b0, b1, t0, b1, t1]: st.add_vertex(v)
		for v in [t0, b1, b0, t0, t1, b1]: st.add_vertex(v)   # изнанка
	st.generate_normals()
	_robe = st.commit()
	return _robe

func _name(a: String) -> String:
	return def.pre + def.anims.get(a, "Idle")

func _tint(c: Color, emis: Color, metal: float) -> void:
	for m in root.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			if src is StandardMaterial3D:
				var nm := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
				# глаза и чёрные детали не трогаем
				var lum := nm.albedo_color.get_luminance()
				var is_eye := "Eye" in src.resource_name
				if not is_eye:
					nm.albedo_color = nm.albedo_color * c
					if emis != Color.BLACK:
						nm.emission_enabled = true; nm.emission = emis; nm.emission_energy_multiplier = 0.06
					if metal >= 0: nm.metallic = metal
				elif emis != Color.BLACK and lum < 0.5:
					nm.emission_enabled = true; nm.emission = emis; nm.emission_energy_multiplier = 3.0
				nm.roughness = minf(nm.roughness, 0.75)
				mi.set_surface_override_material(i, nm)

func attach(bone: String, scene_name: String, pos: Vector3, rot: Vector3, sc: float) -> Node3D:
	if skel == null: return null
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	skel.add_child(ba)
	var w: Node3D = CharAssets.prop(scene_name).instantiate()
	ba.add_child(w)
	# pos и sc заданы в метрах мира: компенсируем масштаб скелета (у некоторых моделей он 100x)
	var k: float = skel.global_basis.get_scale().x / maxf(0.0001, global_basis.get_scale().x)
	w.position = pos / k; w.rotation_degrees = rot
	w.scale = Vector3.ONE * sc / k
	return w

func _play(a: String, blend := 0.18, speed := 1.0) -> void:
	if proc:
		_cur = a
		if a in ["attack", "cast", "hit", "death", "spawn"]:
			_pa = a; _pa_t = 0.0
			_pa_dur = {"attack": 0.9, "cast": 1.4, "hit": 0.35, "death": 2.2, "spawn": 1.6}[a] / maxf(0.1, speed)
		elif _pa != "death": _pa = ""
		return
	if ap == null: return
	var n := _name(a)
	if not ap.has_animation(n): return
	_cur = a
	ap.play(n, blend, speed)

func play_action(a: String, speed := 1.0) -> void:
	if dead: return
	if not def.anims.has(a): a = "attack"
	if a == "charge":   # бег-таран — зацикленная локомоция, не разовое действие
		_action = ""; speed_override = run_ref * 1.5
		get_tree().create_timer(1.2, false).timeout.connect(func(): speed_override = -1.0)
		return
	_action = a
	if ap: ap.speed_scale = 1.0
	_play(a, 0.1, speed)

func hit_react() -> void:
	if dead or _action != "": return
	if def.anims.has("hit") and def.anims.hit != def.anims.idle: play_action("hit", 1.4)

func set_dead(v := true) -> void:
	dead = v
	_action = ""
	_cur = ""
	_play("death" if v else "idle", 0.1)

func _on_finished(_n: StringName) -> void:
	if dead: return
	_action = ""

func _process(delta: float) -> void:
	if proc: _proc_tick(delta)
	var p := global_position
	var v := Vector2(p.x - _last_pos.x, p.z - _last_pos.z).length() / maxf(delta, 0.0001)
	_last_pos = p
	_speed = lerpf(_speed, v if speed_override < 0 else speed_override, minf(1.0, delta * 10))
	if dead or _action != "": return
	var want := "idle"
	if _speed > (run_ref + walk_ref) * 0.5: want = "run"
	elif _speed > 0.35: want = "walk"
	if want != _cur: _play(want, 0.2)
	if ap and want != "idle":
		ap.speed_scale = clampf(_speed / (run_ref if want == "run" else walk_ref), 0.6, 1.8)
	elif ap:
		ap.speed_scale = 1.0

# ---------------- v0.9.5: процедурная анимация статичной модели (Кел'Таар) ----------------
func _proc_setup() -> void:
	proc = true
	var mesh_nodes := root.find_children("*", "MeshInstance3D", true, false)
	_body = Node3D.new(); _body.name = "Body"
	root.add_child(_body)
	for m in mesh_nodes:
		m.get_parent().remove_child(m); _body.add_child(m)
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true; mat.vertex_color_is_srgb = false
		mat.roughness = 0.78; mat.metallic = 0.05; mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.rim_enabled = true; mat.rim = 0.35; mat.rim_tint = 0.6
		(m as MeshInstance3D).material_override = mat
	var ice := Color(0.45, 1.0, 0.85)
	for x in [-0.018, 0.018]:   # светящиеся глаза
		var eye := U.prim("sphere", _body, Vector3(x, 0.875, 0.03), Vector3.ONE * 0.018, ice, 0.2, 6.0)
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var aura := OmniLight3D.new(); aura.light_color = Color(0.4, 0.95, 0.85); aura.light_energy = 1.2; aura.omni_range = 4.0
	aura.position = Vector3(0, 0.6, 0.25); _body.add_child(aura)
	var ring := U.prim("cylinder", root, Vector3(0, 0.01, 0), Vector3(0.55, 0.004, 0.55), ice, 0.2, 1.4)
	ring.material_override = U.fx_mat(Color(0.35, 1.0, 0.8, 0.28))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.name = "FrostRing"

func _proc_tick(delta: float) -> void:
	_pt += delta
	if _body == null: return
	var hover := 0.03 + sin(_pt * 1.6) * 0.018
	var pitch := 0.0; var roll := sin(_pt * 1.1) * 0.025; var yaw := 0.0; var sink := 0.0; var sc := 1.0
	var moving := _speed > 0.35 and not dead
	if moving: pitch += clampf(_speed / 6.0, 0.0, 1.0) * 0.16
	if _pa != "":
		_pa_t += delta
		var k := clampf(_pa_t / _pa_dur, 0.0, 1.0)
		match _pa:
			"attack":   # замах назад и выпад посохом вперёд
				pitch += -0.22 * sin(k * PI) if k < 0.45 else 0.32 * sin((k - 0.45) / 0.55 * PI)
				yaw = 0.25 * sin(k * PI)
			"cast":     # поднимается над землёй и откидывается назад
				hover += 0.18 * sin(k * PI); pitch -= 0.15 * sin(k * PI)
			"hit": pitch -= 0.12 * sin(k * PI); roll += 0.06 * sin(k * PI * 2.0)
			"spawn": sink = (1.0 - k) * 1.0; sc = lerpf(0.6, 1.0, k)
			"death":    # оседает, заваливается и рассыпается
				hover = 0.0; roll = 0.9 * k * k; pitch = 0.25 * k; sink = k * 0.35; sc = lerpf(1.0, 0.75, k)
		if k >= 1.0 and _pa != "death":
			_pa = ""
			if _action != "": _on_finished(&"")
	_body.position = Vector3(0, hover - sink, 0)
	_body.rotation = Vector3(pitch, yaw, roll)
	_body.scale = Vector3.ONE * sc
	var ring := root.get_node_or_null("FrostRing")
	if ring: ring.rotation.y = _pt * 0.4; ring.visible = not dead
