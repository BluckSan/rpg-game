extends Node
## Игровые данные: классы, умения, враги, пути превращения, дерево талантов, добыча, расчёт характеристик.

const SKIN_COLORS := [Color(1,0.87,0.77), Color(0.96,0.78,0.62), Color(0.85,0.65,0.47), Color(0.66,0.46,0.32),
	Color(0.45,0.3,0.2), Color(0.3,0.2,0.14), Color(0.6,0.75,0.6), Color(0.7,0.72,0.85)]
const HAIR_COLORS := [Color(0.08,0.06,0.05), Color(0.35,0.2,0.1), Color(0.6,0.4,0.2), Color(0.95,0.85,0.55),
	Color(0.75,0.25,0.1), Color(0.9,0.9,0.92), Color(0.3,0.4,0.9), Color(0.8,0.3,0.6)]
const EYE_COLORS := [Color(0.3,0.2,0.1), Color(0.2,0.45,0.9), Color(0.25,0.65,0.3), Color(0.5,0.5,0.5), Color(0.85,0.65,0.1), Color(0.8,0.1,0.1)]
const HAIR_STYLES := ["Короткая", "Ёжик", "Длинная", "Хвост", "Ирокез", "Лысый"]
const FACES := ["Обычное", "Острое", "Борода", "Шрам"]

const RARITY_NAMES := ["Обычный", "Магический", "Редкий", "Уникальный"]
const RARITY_COLORS := [Color(0.9,0.9,0.9), Color(0.4,0.6,1), Color(1,0.9,0.3), Color(1,0.5,0.1)]
const SLOT_NAMES := ["Оружие", "Броня", "Шлем", "Кольцо"]
const MAX_SLOTS := 6
const INVENTORY_SIZE := 30
const ASC_LEVEL := 8
const ASC_REGION_POINTS := 6

const STAT_NAMES := {
	"hp": "к здоровью", "hp%": "% к здоровью", "mp": "к мане", "mp%": "% к мане",
	"dmg": "к урону", "dmg%": "% к урону", "spell%": "% к урону чар", "as%": "% к скорости атаки",
	"ms%": "% к скорости бега", "crit": "% шанс крит. удара", "critdmg%": "% к силе крит. удара",
	"armor": "к броне", "armor%": "% к броне", "regen": "здоровья в сек.", "mpregen": "маны в сек.",
	"leech%": "% похищения жизни", "cdr%": "% сокращения перезарядки",
}

var CLASSES := {
	"warrior": {
		"name": "Воин", "weapon": "Ржавый меч", "color": Color(0.85,0.3,0.2),
		"desc": "Мастер ближнего боя. Много здоровья и брони.\nПути развития: Берсерк, Паладин, Друид.",
		"hp": 140.0, "hp_lvl": 14.0, "mp": 40.0, "mp_lvl": 3.0, "dmg": 12.0, "dmg_lvl": 2.2,
		"range": 2.6, "interval": 0.75, "ranged": false, "spell": false,
		"skills": [
			{"id": "w_attack", "name": "Удар", "kind": "melee", "mult": 1.0, "cd": 0.0, "mana": 0.0, "radius": 2.6, "range": 2.6, "color": Color.WHITE, "unlock": 1},
			{"id": "w_spin", "name": "Вихрь", "desc": "Круговой удар по всем врагам рядом", "kind": "spin", "mult": 1.6, "cd": 6.0, "mana": 15.0, "radius": 4.2, "range": 4.0, "color": Color(1,0.6,0.3), "unlock": 1},
			{"id": "w_dash", "name": "Рывок", "desc": "Рывок вперёд, ранит врагов на пути", "kind": "dash", "mult": 2.2, "cd": 8.0, "mana": 15.0, "radius": 2.0, "range": 8.0, "color": Color(1,0.85,0.4), "unlock": 3},
		]},
	"archer": {
		"name": "Лучник", "weapon": "Кривой лук", "color": Color(0.3,0.7,0.3),
		"desc": "Стреляет издалека, быстрый и ловкий. Высокий шанс крита.\nПути развития: Тень, Друид, Берсерк.",
		"hp": 100.0, "hp_lvl": 10.0, "mp": 60.0, "mp_lvl": 4.0, "dmg": 10.0, "dmg_lvl": 2.0,
		"range": 14.0, "interval": 0.6, "ranged": true, "spell": false,
		"skills": [
			{"id": "a_attack", "name": "Выстрел", "kind": "projectile", "mult": 1.0, "cd": 0.0, "mana": 0.0, "radius": 0.0, "range": 16.0, "color": Color(0.9,0.8,0.5), "unlock": 1},
			{"id": "a_volley", "name": "Залп", "desc": "Веер из пяти стрел", "kind": "volley", "mult": 0.9, "cd": 5.0, "mana": 14.0, "radius": 0.0, "range": 16.0, "color": Color(0.6,1,0.6), "unlock": 1},
			{"id": "a_rain", "name": "Град стрел", "desc": "Дождь стрел по области у цели", "kind": "arrow_rain", "mult": 2.4, "cd": 9.0, "mana": 22.0, "radius": 4.5, "range": 14.0, "color": Color(0.8,1,0.4), "unlock": 3},
		]},
	"mage": {
		"name": "Маг", "weapon": "Посох ученика", "color": Color(0.3,0.45,0.95),
		"desc": "Повелевает стихиями и тьмой. Мощные заклинания, мало здоровья.\nПути развития: Стихийник, Некромант, Паладин.",
		"hp": 85.0, "hp_lvl": 8.0, "mp": 120.0, "mp_lvl": 8.0, "dmg": 11.0, "dmg_lvl": 2.4,
		"range": 13.0, "interval": 0.8, "ranged": true, "spell": true,
		"skills": [
			{"id": "m_bolt", "name": "Искра", "kind": "projectile", "mult": 1.0, "cd": 0.0, "mana": 0.0, "radius": 0.0, "range": 15.0, "color": Color(0.5,0.7,1), "unlock": 1},
			{"id": "m_fireball", "name": "Огненный шар", "desc": "Взрывается и поджигает область", "kind": "fireball", "mult": 2.6, "cd": 5.0, "mana": 20.0, "radius": 3.2, "range": 15.0, "color": Color(1,0.45,0.1), "unlock": 1},
			{"id": "m_nova", "name": "Ледяная нова", "desc": "Замораживает и ранит врагов вокруг", "kind": "frost_nova", "mult": 1.5, "cd": 8.0, "mana": 25.0, "radius": 5.0, "range": 5.0, "color": Color(0.6,0.9,1), "unlock": 3},
		]},
}
const CLASS_ORDER := ["warrior", "archer", "mage"]

var ASCENDANCIES := [
	{"id": "berserker", "name": "Берсерк", "color": Color(0.9,0.2,0.1),
	 "desc": "Багровая ярость: тело растёт, глаза горят.\n+25% урона, +10% скорости атаки.",
	 "mods": [["dmg%", 25], ["as%", 10]],
	 "skill": {"id": "asc_rage", "name": "Ярость", "desc": "8 сек: +50% урона и скорости атаки", "kind": "rage", "mult": 0.0, "cd": 20.0, "mana": 20.0, "radius": 0.0, "range": 0.0, "color": Color(1,0.2,0.1)}},
	{"id": "paladin", "name": "Паладин", "color": Color(1,0.85,0.3),
	 "desc": "Золотые латы и нимб света.\n+30% брони, +15% здоровья.",
	 "mods": [["armor%", 30], ["hp%", 15]],
	 "skill": {"id": "asc_shield", "name": "Священный щит", "desc": "Лечит 35% здоровья и снижает урон на 6 сек", "kind": "holy_shield", "mult": 0.0, "cd": 22.0, "mana": 25.0, "radius": 0.0, "range": 0.0, "color": Color(1,0.9,0.4)}},
	{"id": "elementalist", "name": "Стихийник", "color": Color(0.3,0.7,1),
	 "desc": "Вокруг кружат сферы огня, льда и молний.\n+30% урона чар, +10% сокращения перезарядки.",
	 "mods": [["spell%", 30], ["cdr%", 10], ["dmg%", 10]],
	 "skill": {"id": "asc_meteor", "name": "Метеор", "desc": "Огромный метеор по области", "kind": "meteor", "mult": 5.0, "cd": 16.0, "mana": 40.0, "radius": 6.0, "range": 15.0, "color": Color(1,0.4,0.1)}},
	{"id": "necromancer", "name": "Некромант", "color": Color(0.55,0.3,0.8),
	 "desc": "Бледная кожа, тёмная аура, парящие черепа.\n+20% урона чар, +3% похищения жизни.",
	 "mods": [["spell%", 20], ["leech%", 3], ["dmg%", 10]],
	 "skill": {"id": "asc_summon", "name": "Поднять скелетов", "desc": "Призывает 2 скелетов на 25 сек", "kind": "summon", "mult": 0.6, "cd": 25.0, "mana": 35.0, "radius": 0.0, "range": 0.0, "color": Color(0.7,0.5,1)}},
	{"id": "shadow", "name": "Тень", "color": Color(0.25,0.2,0.35),
	 "desc": "Тело окутано дымом, движения бесшумны.\n+10% крита, +50% силы крита, +10% скорости.",
	 "mods": [["crit", 10], ["critdmg%", 50], ["ms%", 10]],
	 "skill": {"id": "asc_strike", "name": "Теневой удар", "desc": "Телепорт к врагу и гарантированный крит", "kind": "shadow_strike", "mult": 4.0, "cd": 10.0, "mana": 20.0, "radius": 0.0, "range": 14.0, "color": Color(0.5,0.3,0.7)}},
	{"id": "druid", "name": "Друид-зверь", "color": Color(0.35,0.6,0.25),
	 "desc": "Облик медведя: огромное звериное тело.\n+30% здоровья, +15% урона, +3 регенерации.",
	 "mods": [["hp%", 30], ["dmg%", 15], ["regen", 3]],
	 "skill": {"id": "asc_roar", "name": "Рёв зверя", "desc": "Оглушает врагов вокруг и лечит", "kind": "beast_roar", "mult": 2.0, "cd": 14.0, "mana": 20.0, "radius": 6.0, "range": 0.0, "color": Color(0.5,0.9,0.3)}},
]

var ENEMIES := {
	"slime": {"name": "Слизень", "hp": 40.0, "dmg": 6.0, "speed": 2.2, "range": 1.6, "interval": 1.4, "aggro": 8.0, "radius": 0.6, "xp": 14.0, "ranged": false, "boss": false, "color": Color(0.4,0.85,0.3)},
	"wolf": {"name": "Серый волк", "hp": 55.0, "dmg": 9.0, "speed": 5.2, "range": 1.8, "interval": 1.0, "aggro": 11.0, "radius": 0.7, "xp": 22.0, "ranged": false, "boss": false, "color": Color(0.45,0.45,0.48)},
	"skeleton_archer": {"name": "Скелет-лучник", "hp": 50.0, "dmg": 11.0, "speed": 2.6, "range": 11.0, "interval": 1.8, "aggro": 13.0, "radius": 0.5, "xp": 28.0, "ranged": true, "boss": false, "color": Color(0.9,0.88,0.8)},
	"skeleton": {"name": "Скелет-воин", "hp": 70.0, "dmg": 12.0, "speed": 3.4, "range": 1.9, "interval": 1.2, "aggro": 11.0, "radius": 0.5, "xp": 30.0, "ranged": false, "boss": false, "color": Color(0.85,0.83,0.75)},
	"goblin": {"name": "Гоблин-громила", "hp": 120.0, "dmg": 18.0, "speed": 3.0, "range": 2.2, "interval": 1.6, "aggro": 10.0, "radius": 0.8, "xp": 45.0, "ranged": false, "boss": false, "color": Color(0.35,0.55,0.2)},
	"troll": {"name": "Древний тролль", "hp": 900.0, "dmg": 30.0, "speed": 3.2, "range": 3.2, "interval": 1.8, "aggro": 16.0, "radius": 1.6, "xp": 500.0, "ranged": false, "boss": true, "color": Color(0.4,0.5,0.45)},
}

## Зоны. Чтобы добавить глобальную карту: сделать сборщик мира в zone.gd для "global" и поставить available = true.
var ZONES := {
	"starter": {"name": "Пепельная долина", "scene": "res://scenes/zone.tscn", "available": true, "min_level": 1},
	"global": {"name": "Земли Эфира", "scene": "res://scenes/zone.tscn", "available": false, "min_level": 10},
}

# ---------------- Дерево талантов ----------------
var tree_nodes := {}     # id -> Dictionary
var tree_regions := {}   # id -> {name, color}
var tree_order := []

func _ready() -> void:
	_load_tree()

func _load_tree() -> void:
	var f := FileAccess.open("res://data/talent_tree.json", FileAccess.READ)
	if f == null:
		push_error("talent_tree.json не найден")
		return
	var data = JSON.parse_string(f.get_as_text())
	for r in data["regions"]:
		tree_regions[r["id"]] = {"name": r["name"], "color": Color.html(r["color"])}
	for n in data["nodes"]:
		var node := {
			"id": int(n["id"]), "name": n["name"], "type": n["type"], "region": n["region"], "class": n["classId"],
			"pos": Vector2(float(n["x"]), float(n["y"])), "mods": [], "links": []}
		for m in n["mods"]:
			node["mods"].append([m["stat"], float(m["value"])])
		for l in n["links"]:
			node["links"].append(int(l))
		tree_nodes[node["id"]] = node
		tree_order.append(node["id"])

func start_node(class_id: String) -> int:
	for id in tree_order:
		var n = tree_nodes[id]
		if n["type"] == "start" and n["class"] == class_id:
			return id
	return 0

func keystone_of(region: String) -> Dictionary:
	for id in tree_order:
		var n = tree_nodes[id]
		if n["type"] == "keystone" and n["region"] == region:
			return n
	return {}

func points_in_region(c: Dictionary, region: String) -> int:
	var k := 0
	for id in c["talents"]:
		if tree_nodes.has(int(id)) and tree_nodes[int(id)]["region"] == region:
			k += 1
	return k

func total_points(c: Dictionary) -> int:
	return (int(c["level"]) - 1) + 2 + (int(c["class_level"]) - 1) / 2

func free_points(c: Dictionary) -> int:
	return total_points(c) - max(0, c["talents"].size() - 1)

func has_talent(c: Dictionary, id: int) -> bool:
	return c["talents"].has(id)

func can_allocate(c: Dictionary, id: int) -> bool:
	if not tree_nodes.has(id): return false
	var n = tree_nodes[id]
	if n["type"] == "start" or has_talent(c, id) or free_points(c) <= 0:
		return false
	for l in n["links"]:
		if has_talent(c, l):
			return true
	return false

func allocate(c: Dictionary, id: int) -> bool:
	if not can_allocate(c, id): return false
	c["talents"].append(id)
	return true

func reset_talents(c: Dictionary) -> void:
	c["talents"] = [start_node(c["class"])]
	c["ascendancy"] = ""

func get_asc(id: String) -> Dictionary:
	for a in ASCENDANCIES:
		if a["id"] == id:
			return a
	return {}

## Возвращает "" если можно превратиться, иначе причину.
func asc_block_reason(c: Dictionary, a: Dictionary) -> String:
	if c["ascendancy"] != "": return "Путь уже выбран (сброс талантов отменит его)"
	if int(c["level"]) < ASC_LEVEL: return "Нужен %d уровень" % ASC_LEVEL
	var key := keystone_of(a["id"])
	if key.is_empty() or not has_talent(c, key["id"]): return "Изучите «%s»" % key.get("name", "?")
	var pts := points_in_region(c, a["id"])
	if pts < ASC_REGION_POINTS: return "Нужно %d очков в регионе (%d)" % [ASC_REGION_POINTS, pts]
	return ""

# ---------------- Персонаж ----------------
static func xp_to_next(level: int) -> int:
	return int(60.0 * pow(level, 1.6))

static func class_xp_to_next(cl: int) -> int:
	return int(100.0 * pow(cl, 1.5))

func new_character(char_name: String, class_id: String, look: Dictionary) -> Dictionary:
	return {
		"version": 1, "id": "%x%x" % [Time.get_ticks_usec(), randi()], "name": char_name, "class": class_id, "look": look,
		"level": 1, "xp": 0, "class_level": 1, "class_xp": 0,
		"talents": [start_node(class_id)], "ascendancy": "",
		"gold": 0, "potions": 3, "inventory": [], "equipped": [starter_weapon(class_id)],
		"zone": "starter", "has_pos": false, "pos": [0, 0, 0], "zones": {},
		"created": Time.get_unix_time_from_system(), "play_time": 0.0, "kills": 0,
	}

func get_equipped(c: Dictionary, slot: int):
	for it in c["equipped"]:
		if int(it["slot"]) == slot:
			return it
	return null

func describe_mod(m: Array) -> String:
	var stat: String = m[0]
	var v: float = m[1]
	var vs := str(int(round(v))) if absf(v - round(v)) < 0.01 else ("%.1f" % v)
	return ("+" if v >= 0 else "") + vs + " " + STAT_NAMES.get(stat, stat)

## Итоговые характеристики: класс + уровень + таланты + путь + снаряжение.
func compute_stats(c: Dictionary) -> Dictionary:
	var raw := {}
	var add := func(mods):
		for m in mods:
			raw[m[0]] = raw.get(m[0], 0.0) + float(m[1])
	for id in c["talents"]:
		if tree_nodes.has(int(id)):
			add.call(tree_nodes[int(id)]["mods"])
	var asc := get_asc(c["ascendancy"])
	if not asc.is_empty():
		add.call(asc["mods"])
	var weapon_dmg := 0.0
	var item_armor := 0.0
	for it in c["equipped"]:
		add.call(it["mods"])
		if int(it["slot"]) == 0: weapon_dmg += float(it["base"])
		else: item_armor += float(it["base"])
	raw["dmg%"] = raw.get("dmg%", 0.0) + (int(c["class_level"]) - 1) * 3.0
	var g := func(k): return raw.get(k, 0.0)
	var cls: Dictionary = CLASSES[c["class"]]
	var L := int(c["level"]) - 1
	var s := {}
	s.max_hp = (cls.hp + cls.hp_lvl * L + g.call("hp")) * (1 + g.call("hp%") / 100.0)
	s.max_mp = (cls.mp + cls.mp_lvl * L + g.call("mp")) * (1 + g.call("mp%") / 100.0)
	s.damage = cls.dmg + cls.dmg_lvl * L + weapon_dmg + g.call("dmg")
	s.dmg_mult = 1 + g.call("dmg%") / 100.0
	s.spell_mult = 1 + g.call("spell%") / 100.0
	s.attack_speed = maxf(0.3, 1 + g.call("as%") / 100.0)
	s.move_speed = 5.2 * clampf(1 + g.call("ms%") / 100.0, 0.5, 2.0)
	s.crit = clampf(5 + g.call("crit"), 0, 80) / 100.0
	s.crit_mult = 1.5 + g.call("critdmg%") / 100.0
	s.armor = maxf(0, (5 + item_armor + g.call("armor")) * (1 + g.call("armor%") / 100.0))
	s.regen = 0.5 + g.call("regen")
	s.mp_regen = 2.0 + g.call("mpregen")
	s.leech = g.call("leech%") / 100.0
	s.cdr = clampf(g.call("cdr%"), 0, 50) / 100.0
	s.dr = s.armor / (s.armor + 120.0) * 0.8
	return s

# ---------------- Добыча ----------------
const ARMOR_BASES := ["Кожаная куртка", "Кольчуга", "Латный доспех"]
const HELM_BASES := ["Капюшон", "Железный шлем", "Рогатый шлем"]
const RING_BASES := ["Медное кольцо", "Серебряное кольцо", "Кольцо с рубином"]
const PREFIXES := ["Острый", "Крепкий", "Быстрый", "Древний", "Пылающий", "Ледяной", "Кровавый", "Святой", "Теневой"]
const UNIQUES := ["Клык Тролля", "Сердце долины", "Пепельный венец", "Шёпот бури"]
const AFFIXES := [["hp",10,40],["mp",10,35],["dmg%",4,15],["as%",3,10],["ms%",2,8],["crit",1,5],
	["critdmg%",8,25],["armor",8,30],["regen",0.5,2.5],["spell%",5,16],["leech%",0.3,1.5],["cdr%",2,6]]

func weapon_base(class_id: String, tier: int) -> String:
	match class_id:
		"archer": return ["Короткий лук", "Длинный лук", "Составной лук"][tier]
		"mage": return ["Посох", "Жезл чародея", "Посох архимага"][tier]
	return ["Меч", "Боевой топор", "Двуручный клинок"][tier]

func starter_weapon(class_id: String) -> Dictionary:
	return {"uid": str(randi()), "name": CLASSES[class_id].weapon, "slot": 0, "rarity": 0, "ilvl": 1, "base": 3.0, "mods": []}

func roll_item(ilvl: int, class_id: String, rarity_bonus := 0.0) -> Dictionary:
	var it := {"uid": str(randi()), "ilvl": ilvl, "slot": randi() % 4, "mods": []}
	var r := randf() - rarity_bonus
	it.rarity = 3 if r < 0.02 else (2 if r < 0.14 else (1 if r < 0.45 else 0))
	var tier := clampi(ilvl / 4, 0, 2)
	var base_name := ""
	match it.slot:
		0: base_name = weapon_base(class_id, tier); it.base = 3 + ilvl * 1.6 + randf() * 3
		1: base_name = ARMOR_BASES[tier]; it.base = 6 + ilvl * 3.0 + randf() * 5
		2: base_name = HELM_BASES[tier]; it.base = 3 + ilvl * 1.5 + randf() * 3
		_: base_name = RING_BASES[tier]; it.base = 0.0
	it.base = round(it.base)
	var n_aff := 0
	match it.rarity:
		0: n_aff = 1 if it.slot == 3 else 0
		1: n_aff = randi_range(1, 2)
		2: n_aff = randi_range(3, 4)
		_: n_aff = 5
	var used := []
	var scale := 1.0 + ilvl * 0.08
	for i in n_aff:
		var k := randi() % AFFIXES.size()
		var guard := 0
		while used.has(k) and guard < 20:
			k = randi() % AFFIXES.size(); guard += 1
		used.append(k)
		var a = AFFIXES[k]
		var v: float = randf_range(a[1], a[2]) * scale * (1.5 if it.rarity == 3 else 1.0)
		v = round(v) if v >= 5 else round(v * 10) / 10.0
		it.mods.append([a[0], v])
	if it.rarity == 3:
		it.name = UNIQUES.pick_random(); it.base = round(it.base * 1.3)
	elif it.rarity >= 1:
		it.name = PREFIXES.pick_random() + " " + base_name.to_lower()
	else:
		it.name = base_name
	return it

func describe_item(it: Dictionary) -> String:
	var s := "%s · %s · ур. %d\n" % [SLOT_NAMES[int(it.slot)], RARITY_NAMES[int(it.rarity)], int(it.ilvl)]
	if int(it.slot) == 0: s += "Урон: +%d\n" % int(it.base)
	elif float(it.base) > 0: s += "Броня: +%d\n" % int(it.base)
	for m in it.mods:
		s += describe_mod(m) + "\n"
	return s.strip_edges()

func sell_price(it: Dictionary) -> int:
	return 5 + int(it.ilvl) * 3 * (int(it.rarity) + 1)
