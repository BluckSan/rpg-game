extends RefCounted
class_name CharAssets
## Общие ресурсы персонажей: модели, анимации, материалы, палитры, пресеты лица.
## Модели и анимации — Quaternius (CC0): Universal Base Characters, Modular Character Outfits — Fantasy,
## Universal Animation Library 1/2. Сборка — tools/assets/build_chars.py и build_anims.py.

const SKIN := [Color(1.0, 0.97, 0.95), Color(1.0, 0.91, 0.84), Color(0.96, 0.82, 0.7), Color(0.87, 0.69, 0.55),
	Color(0.8, 0.66, 0.5), Color(0.64, 0.47, 0.35), Color(0.48, 0.34, 0.25), Color(0.34, 0.23, 0.17),
	Color(0.8, 0.86, 0.8), Color(0.62, 0.76, 0.96)]
const SKIN_NAMES := ["Фарфор", "Светлая", "Персик", "Загар", "Олива", "Бронза", "Смуглая", "Тёмная", "Бледная", "Лазурная"]
const HAIR := [Color(0.1, 0.085, 0.08), Color(0.26, 0.17, 0.11), Color(0.43, 0.28, 0.17), Color(0.55, 0.27, 0.13),
	Color(0.66, 0.24, 0.11), Color(0.86, 0.43, 0.18), Color(0.95, 0.78, 0.48), Color(1.0, 0.96, 0.86),
	Color(0.6, 0.6, 0.62), Color(0.98, 0.98, 1.0), Color(0.22, 0.38, 0.9), Color(0.55, 0.28, 0.8),
	Color(0.28, 0.66, 0.4), Color(0.95, 0.48, 0.68)]
const EYES := [Color(0.38, 0.22, 0.12), Color(0.5, 0.42, 0.2), Color(0.26, 0.58, 0.3), Color(0.25, 0.48, 0.9),
	Color(0.55, 0.6, 0.65), Color(0.9, 0.6, 0.15), Color(0.6, 0.3, 0.85), Color(0.85, 0.12, 0.1)]
## [подпись, имя меша]
const HAIR_STYLES := [["Без волос", ""], ["Ёжик", "Hair_Buzzed"], ["Пробор", "Hair_SimpleParted"],
	["Длинные", "Hair_Long"], ["Пучки", "Hair_Buns"], ["Короткая", "Hair_BuzzedFemale"]]
const BROW_STYLES := [["Густые", "Brows_A"], ["Тонкие", "Brows_B"], ["Без бровей", ""]]
## [ключ, подпись, группа]
const MORPHS := [
	["face_width", "Ширина лица", "Форма лица"], ["face_length", "Длина лица", "Форма лица"],
	["jaw_width", "Челюсть", "Форма лица"], ["chin", "Подбородок", "Форма лица"],
	["cheekbones", "Скулы", "Форма лица"], ["cheeks", "Щёки", "Форма лица"],
	["eye_size", "Размер глаз", "Глаза"], ["eye_spacing", "Расстояние", "Глаза"], ["eye_height", "Высота", "Глаза"],
	["nose_length", "Длина носа", "Нос"], ["nose_width", "Ширина носа", "Нос"], ["nose_bridge", "Переносица", "Нос"],
	["lips", "Полнота губ", "Рот"], ["mouth_width", "Ширина рта", "Рот"],
	["brow_height", "Высота бровей", "Брови"], ["brow_depth", "Надбровные дуги", "Брови"],
	["ears_size", "Размер ушей", "Уши"], ["ears_point", "Заострённость", "Уши"]]
const HAIR_MORPHS := [["hair_volume", "Объём причёски"], ["beard_length", "Длина бороды"], ["beard_volume", "Густота бороды"]]
const PRESETS := [
	["Классика", {}],
	["Благородный", {"cheekbones": 0.6, "jaw_width": 0.2, "nose_length": 0.3, "nose_width": -0.35, "chin": 0.4, "face_length": 0.3, "lips": -0.2}],
	["Суровый", {"jaw_width": 0.9, "brow_depth": 0.8, "brow_height": -0.4, "chin": 0.5, "nose_width": 0.4, "cheekbones": 0.3, "eye_size": -0.4}],
	["Мягкий", {"cheeks": 0.7, "jaw_width": -0.6, "eye_size": 0.5, "nose_length": -0.4, "lips": 0.4, "face_width": 0.2, "chin": -0.3}],
	["Эльфийский", {"ears_point": 1.0, "ears_size": 0.3, "cheekbones": 0.7, "jaw_width": -0.5, "chin": 0.3, "eye_size": 0.3, "nose_width": -0.5, "face_length": 0.2}],
	["Варвар", {"jaw_width": 1.0, "nose_width": 0.8, "nose_length": -0.2, "brow_depth": 1.0, "lips": 0.5, "mouth_width": 0.4, "chin": 0.3, "face_width": 0.3}],
	["Юный", {"eye_size": 0.6, "face_length": -0.4, "nose_length": -0.5, "cheeks": 0.4, "jaw_width": -0.4, "nose_bridge": -0.3}]]

const CLASS_OUTFIT := {
	"warrior": {"parts": ["Ranger_Body", "Ranger_Body_Belt", "Ranger_Legs", "Ranger_Feet", "Ranger_Arms", "Ranger_Acc_Pauldron"],
		"mat": "ranger", "hue": 0.61, "sat": 0.95, "val": 0.7, "metal": 0.15},
	"archer": {"parts": ["Ranger_Body", "Ranger_Body_Belt", "Ranger_Legs", "Ranger_Feet", "Ranger_Arms"],
		"mat": "ranger", "hue": 0.0, "sat": 1.0, "val": 1.0, "metal": 0.0},
	"mage": {"parts": ["Peasant_Body", "Peasant_Legs", "Peasant_Feet", "Peasant_Arms", "Ranger_Body_Belt_1"],
		"mat": "peasant", "hue": 0.53, "sat": 1.5, "val": 0.9, "metal": 0.0, "thr": 0.12},
}
## Отличия превращений: перекраска одежды, кожа, глаза, капюшон, эффекты.
const ASC_LOOK := {
	"berserker": {"hue": 0.67, "sat": 1.1, "val": 0.42, "skin_mul": Color(1.05, 0.82, 0.78), "eye": Color(1, 0.15, 0.05), "glow": 4.0, "scale": 1.1, "fx": "embers", "fx_color": Color(1, 0.35, 0.1)},
	"paladin": {"hue": 0.8, "sat": 0.55, "val": 1.35, "metal": 0.55, "rough": 0.55, "eye": Color(1, 0.85, 0.4), "glow": 1.5, "fx": "halo", "fx_color": Color(1, 0.85, 0.45)},
	"elementalist": {"hue": 0.55, "sat": 1.4, "val": 1.0, "emis": Color(0.3, 0.7, 1.0), "emis_k": 0.5, "eye": Color(0.5, 0.9, 1), "glow": 3.0, "fx": "orbs", "fx_color": Color(0.4, 0.8, 1)},
	"necromancer": {"hue": 0.27, "sat": 0.8, "val": 0.32, "skin_mul": Color(0.78, 0.86, 0.78), "eye": Color(0.45, 1, 0.5), "glow": 4.0, "hood": true, "fx": "smoke", "fx_color": Color(0.3, 0.9, 0.4)},
	"shadow": {"hue": 0.45, "sat": 0.3, "val": 0.22, "skin_mul": Color(0.62, 0.58, 0.7), "eye": Color(0.75, 0.35, 1), "glow": 4.0, "hood": true, "fx": "smoke", "fx_color": Color(0.45, 0.2, 0.7)},
}

static var _scenes := {}
static var _libs := {}
static var _mats := {}
static var _tex := {}
static var _props := {}

static func scene(gender: int) -> PackedScene:
	var k := "f" if gender == 1 else "m"
	if not _scenes.has(k): _scenes[k] = load("res://assets/characters/human_%s.gltf" % k)
	return _scenes[k]

static func anim_library(gender: int) -> AnimationLibrary:
	var k := "f" if gender == 1 else "m"
	if not _libs.has(k):
		var n: Node = load("res://assets/characters/anims_%s.gltf" % k).instantiate()
		var ap: AnimationPlayer = n.find_child("AnimationPlayer", true, false)
		var lib: AnimationLibrary = ap.get_animation_library("").duplicate(true)
		for a in ["idle", "idle_sword", "idle_shield", "idle_spell", "idle_fold", "walk", "run", "sprint", "jump_air", "dance", "zombie_walk", "zombie_idle"]:
			if lib.has_animation(a): lib.get_animation(a).loop_mode = Animation.LOOP_LINEAR
		for a in lib.get_animation_list():
			if not a in ["idle", "idle_sword", "idle_shield", "idle_spell", "idle_fold", "walk", "run", "sprint", "jump_air", "dance", "zombie_walk", "zombie_idle"]:
				lib.get_animation(a).loop_mode = Animation.LOOP_NONE
		n.free()
		_libs[k] = lib
	return _libs[k]

static func prop(name: String) -> PackedScene:
	if not _props.has(name): _props[name] = load("res://assets/%s.glb" % name)
	return _props[name]

static func tex(path: String) -> Texture2D:
	if not _tex.has(path): _tex[path] = load("res://assets/characters/tex/%s.png" % path) if ResourceLoader.exists("res://assets/characters/tex/%s.png" % path) else null
	return _tex[path]

static func _cached(key: String, maker: Callable) -> Material:
	if not _mats.has(key): _mats[key] = maker.call()
	return _mats[key]

static func skin_mat(part: String, tone: Color, emis := Color.BLACK) -> Material:
	return _cached("skin|%s|%s|%s" % [part, tone.to_html(), emis.to_html()], func():
		var m := ShaderMaterial.new(); m.shader = preload("res://assets/shaders/skin.gdshader")
		m.set_shader_parameter("albedo_tex", tex(part + "_albedo")); m.set_shader_parameter("normal_tex", tex(part + "_normal"))
		m.set_shader_parameter("skin_tone", tone); m.set_shader_parameter("emission_color", emis)
		return m)

static func hair_mat(which: String, c: Color, emis := Color.BLACK) -> Material:
	return _cached("hair|%s|%s|%s" % [which, c.to_html(), emis.to_html()], func():
		var m := ShaderMaterial.new(); m.shader = preload("res://assets/shaders/hair.gdshader")
		m.set_shader_parameter("albedo_tex", tex(which + "_albedo")); m.set_shader_parameter("normal_tex", tex(which + "_normal"))
		m.set_shader_parameter("hair_color", c); m.set_shader_parameter("emission_color", emis)
		return m)

static func eye_mat(c: Color, glow: float) -> Material:
	return _cached("eye|%s|%.2f" % [c.to_html(), glow], func():
		var m := ShaderMaterial.new(); m.shader = preload("res://assets/shaders/eyes.gdshader")
		m.set_shader_parameter("albedo_tex", tex("eyes_albedo")); m.set_shader_parameter("iris_color", c)
		m.set_shader_parameter("glow", glow)
		return m)

static func outfit_mat(kind: String, o: Dictionary) -> Material:
	var key := "outfit|%s|%s" % [kind, str(o)]
	return _cached(key, func():
		var m := ShaderMaterial.new(); m.shader = preload("res://assets/shaders/outfit.gdshader")
		m.set_shader_parameter("albedo_tex", tex(kind + "_albedo")); m.set_shader_parameter("normal_tex", tex(kind + "_normal"))
		m.set_shader_parameter("orm_tex", tex(kind + "_orm"))
		m.set_shader_parameter("hue_shift", float(o.get("hue", 0.0))); m.set_shader_parameter("sat_mul", float(o.get("sat", 1.0)))
		m.set_shader_parameter("val_mul", float(o.get("val", 1.0))); m.set_shader_parameter("metal_add", float(o.get("metal", 0.0)))
		m.set_shader_parameter("rough_mul", float(o.get("rough", 1.0))); m.set_shader_parameter("sat_threshold", float(o.get("thr", 0.22)))
		m.set_shader_parameter("tint", o.get("tint", Color.WHITE))
		m.set_shader_parameter("band_center", float(o.get("band", 0.33 if kind == "ranger" else -1.0)))
		m.set_shader_parameter("emission_color", o.get("emis", Color.BLACK)); m.set_shader_parameter("emission_strength", float(o.get("emis_k", 0.0)))
		return m)

# ---------------- внешность ----------------
static func default_look(gender := 0) -> Dictionary:
	return {"gender": gender, "height": 1.0, "build": 1.0, "head": 1.0, "skin": 2, "hair": 2 if gender == 0 else 3,
		"hair_color": 2, "eye_color": 0, "brows": 0 if gender == 0 else 1, "beard": 0, "preset": 0, "morphs": {}}

## Приводит внешность к актуальному формату (старые сохранения v0.1 тоже).
static func normalize_look(l: Dictionary) -> Dictionary:
	var d := default_look(int(l.get("gender", 0)))
	for k in d:
		if l.has(k): d[k] = l[k]
	d["gender"] = clampi(int(d["gender"]), 0, 1)
	d["skin"] = clampi(int(d["skin"]), 0, SKIN.size() - 1)
	d["hair"] = posmod(int(d["hair"]), HAIR_STYLES.size())
	d["hair_color"] = clampi(int(d["hair_color"]), 0, HAIR.size() - 1)
	d["eye_color"] = clampi(int(d["eye_color"]), 0, EYES.size() - 1)
	d["brows"] = posmod(int(d["brows"]), BROW_STYLES.size())
	d["beard"] = clampi(int(d["beard"]), 0, 1)
	d["preset"] = clampi(int(d["preset"]), 0, PRESETS.size() - 1)
	for k in ["height", "build", "head"]: d[k] = float(d[k])
	var m := {}
	var src: Dictionary = d["morphs"] if d["morphs"] is Dictionary else {}
	for mk in src: m[str(mk)] = clampf(float(src[mk]), -1.0, 1.0)
	d["morphs"] = m
	# старый формат v0.1: face 2 — борода у мужчин
	if l.has("face") and not l.has("morphs") and int(l.get("face", 0)) == 2 and d["gender"] == 0: d["beard"] = 1
	return d

static func random_look(gender: int, rng: RandomNumberGenerator = null) -> Dictionary:
	if rng == null:
		rng = RandomNumberGenerator.new(); rng.randomize()
	var l := default_look(gender)
	l["height"] = rng.randf_range(0.94, 1.06)
	l["build"] = rng.randf_range(0.88, 1.15)
	l["head"] = rng.randf_range(0.97, 1.03)
	l["skin"] = rng.randi_range(0, 7)
	l["hair"] = rng.randi_range(0, HAIR_STYLES.size() - 1) if gender == 0 else [3, 4, 5, 2][rng.randi_range(0, 3)]
	l["hair_color"] = rng.randi_range(0, 9)
	l["eye_color"] = rng.randi_range(0, 5)
	l["brows"] = rng.randi_range(0, 1)
	l["beard"] = 1 if gender == 0 and rng.randf() < 0.45 else 0
	l["preset"] = rng.randi_range(0, PRESETS.size() - 1)
	var m: Dictionary = (PRESETS[l["preset"]][1] as Dictionary).duplicate()
	for md in MORPHS:
		m[md[0]] = clampf(float(m.get(md[0], 0.0)) + rng.randf_range(-0.3, 0.3), -1, 1)
	m["beard_length"] = rng.randf_range(-0.5, 0.8); m["beard_volume"] = rng.randf_range(-0.4, 0.6)
	m["hair_volume"] = rng.randf_range(-0.3, 0.4)
	l["morphs"] = m
	return l
