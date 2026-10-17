extends Node3D
class_name MobModel
## Анимированная модель монстра из glTF (Quaternius, CC0): слизень, волк, скелет.
## Локомоция определяется по фактической скорости узла; действия — разовые анимации.

const DEFS := {
	"slime": {"scene": "mobs/slime", "scale": 0.4, "pre": "CharacterArmature|",
		"anims": {"idle": "Idle", "walk": "Walk", "run": "Walk", "attack": "Bite_Front", "hit": "HitRecieve", "death": "Death", "spawn": "Jump"}},
	"wolf": {"scene": "mobs/wolf", "scale": 0.33, "pre": "",
		"anims": {"idle": "Idle", "walk": "Walk", "run": "Gallop", "attack": "Attack", "hit": "Idle_HitReact_Left", "death": "Death", "roar": "Idle_2_HeadLow", "spawn": "Jump_ToIdle"}},
	"skeleton": {"scene": "mobs/skeleton", "scale": 0.35, "pre": "SkeletonArmature|Skeleton_",
		"anims": {"idle": "Idle", "walk": "Running", "run": "Running", "attack": "Attack", "hit": "Idle", "death": "Death", "spawn": "Spawn"}},
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
	ap = root.find_child("AnimationPlayer", true, false)
	skel = root.find_child("Skeleton3D", true, false)
	if ap:
		ap.animation_finished.connect(_on_finished)
		for a in ["idle", "walk", "run"]:
			var n := _name(a)
			if ap.has_animation(n): ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
		for a in ["attack", "hit", "death", "spawn", "roar"]:
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
