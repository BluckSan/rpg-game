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

func setup(k: String, opts := {}) -> MobModel:
	kind = k
	def = DEFS[k]
	root = CharAssets.prop(def.scene).instantiate()
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
	_play("idle", 0.0)
	_last_pos = global_position
	return self

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
