extends RefCounted
class_name Items
## Предметы v0.5: 8 слотов, типы с классовыми ограничениями, требование уровня (жёсткий запрет),
## комплекты (бонусы за 2/4/6 предметов), сундук на 100 ячеек, массовые операции, сортировка и фильтры.

const SLOT_COUNT := 8
const SLOT_NAMES := ["Оружие", "Броня", "Шлем", "Кольцо", "Перчатки", "Сапоги", "Амулет", "Пояс"]
const INVENTORY_SIZE := 40
const STASH_SIZE := 100
const SET_RARITY := 4
const CLASS_NAMES := {"warrior": "Воин", "archer": "Лучник", "mage": "Маг"}

## Типы: слот, класс ("" — для всех), названия по тирам, база (урон/броня = a + ilvl·b)
const TYPES := {
	"sword": {"slot": 0, "cls": "warrior", "names": ["Короткий меч", "Длинный меч", "Рунный клинок"], "a": 3.0, "b": 1.6},
	"axe": {"slot": 0, "cls": "warrior", "names": ["Топорик", "Секира", "Боевой топор"], "a": 3.5, "b": 1.65},
	"bow": {"slot": 0, "cls": "archer", "names": ["Короткий лук", "Длинный лук", "Составной лук"], "a": 3.0, "b": 1.6},
	"staff": {"slot": 0, "cls": "mage", "names": ["Посох ученика", "Посох мага", "Посох архимага"], "a": 3.0, "b": 1.6},
	"plate": {"slot": 1, "cls": "warrior", "names": ["Кольчуга", "Латный доспех", "Доспех витязя"], "a": 8.0, "b": 3.4},
	"leather": {"slot": 1, "cls": "archer", "names": ["Кожаная куртка", "Куртка следопыта", "Доспех охотника"], "a": 6.0, "b": 2.9},
	"robe": {"slot": 1, "cls": "mage", "names": ["Холщовая мантия", "Шёлковая мантия", "Мантия чародея"], "a": 5.0, "b": 2.5},
	"cloak": {"slot": 1, "cls": "", "names": ["Плащ", "Плащ странника", "Плащ сумерек"], "a": 5.0, "b": 2.6},
	"helm": {"slot": 2, "cls": "warrior", "names": ["Железный шлем", "Рогатый шлем", "Шлем витязя"], "a": 4.0, "b": 1.7},
	"hood": {"slot": 2, "cls": "archer", "names": ["Капюшон", "Капюшон следопыта", "Маска тени"], "a": 3.0, "b": 1.4},
	"hat": {"slot": 2, "cls": "mage", "names": ["Колпак", "Шляпа чародея", "Венец мага"], "a": 2.5, "b": 1.2},
	"circlet": {"slot": 2, "cls": "", "names": ["Обруч", "Серебряный обруч", "Венец звёзд"], "a": 2.5, "b": 1.3},
	"ring": {"slot": 3, "cls": "", "names": ["Медное кольцо", "Серебряное кольцо", "Кольцо с рубином"], "a": 0.0, "b": 0.0},
	"gloves": {"slot": 4, "cls": "", "names": ["Перчатки", "Наручи", "Латные рукавицы"], "a": 2.0, "b": 1.0},
	"boots": {"slot": 5, "cls": "", "names": ["Сапоги", "Ботфорты", "Сапоги скорохода"], "a": 2.0, "b": 1.0},
	"amulet": {"slot": 6, "cls": "", "names": ["Оберег", "Амулет", "Талисман"], "a": 0.0, "b": 0.0},
	"belt": {"slot": 7, "cls": "", "names": ["Пояс", "Ремень", "Пояс воителя"], "a": 1.0, "b": 0.8},
}
const CLASS_WEAPON := {"warrior": ["sword", "axe"], "archer": ["bow"], "mage": ["staff"]}

## Комплекты: класс ("" — для всех), тир (мин. уровень), 6 типов-частей, бонусы за 2/4/6
const SETS := {
	"veteran": {"name": "Ветеран", "cls": "warrior", "lvl": 5, "pieces": ["sword", "plate", "helm", "gloves", "boots", "belt"],
		"b2": [["hp", 60]], "b4": [["armor%", 15], ["dmg%", 8]], "b6": {"fx": {"combo_wave": 1, "thorns": 20}, "desc": "Третий удар серии — ударная волна; 20% урона отражается"}},
	"north": {"name": "Ярость Севера", "cls": "warrior", "lvl": 15, "pieces": ["axe", "plate", "helm", "gloves", "boots", "belt"],
		"b2": [["dmg%", 12]], "b4": [["as%", 10], ["leech%", 1.5]], "b6": {"fx": {"proc_bleed": 35, "low_hp_dmg": 40}, "desc": "35% шанс кровотечения; +40% урона при здоровье ниже 35%"}},
	"keeper": {"name": "Наследие Хранителя", "cls": "warrior", "lvl": 25, "pieces": ["sword", "plate", "helm", "gloves", "boots", "amulet"],
		"b2": [["hp%", 12]], "b4": [["dr%", 8], ["armor", 60]], "b6": {"fx": {"aura_dmg": 40, "kill_heal": 6}, "desc": "Аура: 40% урона/с врагам рядом; убийство лечит 6%"}},
	"ranger": {"name": "Следопыт", "cls": "archer", "lvl": 5, "pieces": ["bow", "leather", "hood", "gloves", "boots", "ring"],
		"b2": [["ms%", 6]], "b4": [["crit", 4], ["as%", 8]], "b6": {"fx": {"extra_proj": 2}, "desc": "+2 снаряда у стрел и снарядов умений"}},
	"wind": {"name": "Шёпот Ветра", "cls": "archer", "lvl": 15, "pieces": ["bow", "leather", "hood", "gloves", "boots", "belt"],
		"b2": [["as%", 10]], "b4": [["critdmg%", 25]], "b6": {"fx": {"proc_poison": 35, "roll_stealth": 1}, "desc": "35% шанс отравить; после кувырка — гарантированный крит"}},
	"storm": {"name": "Око Бури", "cls": "archer", "lvl": 25, "pieces": ["bow", "leather", "hood", "gloves", "boots", "amulet"],
		"b2": [["dmg%", 15]], "b4": [["crit", 6], ["critdmg%", 30]], "b6": {"fx": {"proc_bolt": 30, "chain_plus": 2, "far_dmg": 30}, "desc": "30% шанс молнии при ударе, цепи +2; +30% урона издали"}},
	"novice": {"name": "Облачение Ученика", "cls": "mage", "lvl": 5, "pieces": ["staff", "robe", "hat", "gloves", "boots", "amulet"],
		"b2": [["mp", 50]], "b4": [["spell%", 12], ["mpregen", 2]], "b6": {"fx": {"mana_guard": 30}, "desc": "30% получаемого урона снимается с маны"}},
	"eternal": {"name": "Пламя Вечности", "cls": "mage", "lvl": 15, "pieces": ["staff", "robe", "hat", "gloves", "boots", "ring"],
		"b2": [["spell%", 14]], "b4": [["crit", 5]], "b6": {"fx": {"proc_burn": 40, "kill_explode": 30}, "desc": "40% шанс поджечь; убитые враги взрываются (30%)"}},
	"ages": {"name": "Стужа Веков", "cls": "mage", "lvl": 25, "pieces": ["staff", "robe", "hat", "gloves", "boots", "belt"],
		"b2": [["cdr%", 8]], "b4": [["spell%", 20], ["mp%", 15]], "b6": {"fx": {"elem_ice": 1, "aura_frost": 1, "aura_dmg": 25}, "desc": "Огонь становится льдом; морозная аура 25% урона/с"}},
	"wanderer": {"name": "Удача Странника", "cls": "", "lvl": 5, "pieces": ["cloak", "circlet", "gloves", "boots", "ring", "amulet"],
		"b2": [["ms%", 5]], "b4": [["hp", 50], ["regen", 2]], "b6": {"fx": {"kill_heal": 5, "kill_mana": 8}, "desc": "Убийство: +5% здоровья и +8% маны"}},
	"blood": {"name": "Узы Крови", "cls": "", "lvl": 15, "pieces": ["cloak", "circlet", "gloves", "boots", "ring", "belt"],
		"b2": [["leech%", 1.0]], "b4": [["dmg%", 10], ["hp%", 8]], "b6": {"fx": {"crit_heal": 3, "leech_x": 1}, "desc": "Похищение жизни ×2; крит лечит 3%"}},
	"seals": {"name": "Печати Эфира", "cls": "", "lvl": 25, "pieces": ["cloak", "circlet", "gloves", "boots", "amulet", "belt"],
		"b2": [["dmg%", 10], ["spell%", 10]], "b4": [["cdr%", 8], ["as%", 8]], "b6": {"fx": {"proc_bolt": 25, "crit_mark": 1}, "desc": "25% шанс молнии; крит проклинает цель (+30% урона)"}},
}

static func tier_of(ilvl: int) -> int: return clampi(ilvl / 9, 0, 2)
static func req_level(ilvl: int) -> int: return clampi(ilvl, 1, 60)

## Типы для слота, доступные классу (cls_pick — класс, под который выпадает предмет)
static func types_for(slot: int, cls_pick: String) -> Array:
	var out := []
	for t in TYPES:
		var d: Dictionary = TYPES[t]
		if int(d.slot) != slot: continue
		if d.cls == "" or d.cls == cls_pick: out.append(t)
	return out

## Класс, под который выпадает предмет: 50% свой, остальное — другие классы
static func pick_class(own: String) -> String:
	if randf() < 0.5: return own
	var others := []
	for k in CLASS_NAMES: if k != own: others.append(k)
	return others.pick_random()

static func _base(t: String, ilvl: int) -> float:
	var d: Dictionary = TYPES[t]
	return round(float(d.a) + ilvl * float(d.b) + randf() * 3.0) if float(d.b) > 0 else 0.0

## Обычный предмет: mix — для всех классов (добыча), иначе — под свой класс (торговец)
static func roll(ilvl: int, own_cls: String, rarity_bonus := 0.0, mix := true, slot := -1) -> Dictionary:
	ilvl = maxi(1, ilvl)
	var cls_pick := pick_class(own_cls) if mix else own_cls
	if slot < 0:
		slot = 0 if randf() < 0.2 else randi_range(1, SLOT_COUNT - 1)
	var t: String = types_for(slot, cls_pick).pick_random()
	var d: Dictionary = TYPES[t]
	var it := {"uid": "%x%x" % [Time.get_ticks_usec(), randi()], "ilvl": ilvl, "slot": slot, "type": t, "cls": d.cls,
		"req": req_level(ilvl), "mods": []}
	var r := randf() - rarity_bonus
	it.rarity = 3 if r < 0.02 else (2 if r < 0.14 else (1 if r < 0.45 else 0))
	it.base = _base(t, ilvl)
	var n_aff := 0
	match int(it.rarity):
		0: n_aff = 1 if slot in [3, 6] else 0
		1: n_aff = randi_range(1, 2)
		2: n_aff = randi_range(3, 4)
		_: n_aff = 5
	_affixes(it, n_aff, 1.5 if it.rarity == 3 else 1.0)
	var bn: String = d.names[tier_of(ilvl)]
	if it.rarity == 3:
		it.name = DB.UNIQUES.pick_random(); it.base = round(it.base * 1.3)
	elif it.rarity >= 1:
		it.name = DB.PREFIXES.pick_random() + " " + bn.to_lower()
	else:
		it.name = bn
	return it

static func _affixes(it: Dictionary, n: int, mult: float) -> void:
	var used := []
	var scale := 1.0 + int(it.ilvl) * 0.08
	for i in n:
		var k := randi() % DB.AFFIXES.size()
		var guard := 0
		while used.has(k) and guard < 20:
			k = randi() % DB.AFFIXES.size(); guard += 1
		used.append(k)
		var a = DB.AFFIXES[k]
		var v: float = randf_range(a[1], a[2]) * scale * mult
		v = round(v) if v >= 5 else round(v * 10) / 10.0
		it.mods.append([a[0], v])

## Комплекты, подходящие уровню предмета (самый высокий доступный тир, иногда — предыдущий)
static func sets_for_level(ilvl: int, cls := "*") -> Array:
	var best := 0
	for s in SETS: if int(SETS[s].lvl) <= ilvl: best = maxi(best, int(SETS[s].lvl))
	var out := []
	for s in SETS:
		var d: Dictionary = SETS[s]
		if int(d.lvl) > ilvl: continue
		if int(d.lvl) != best and randf() < 0.75: continue
		if cls != "*" and d.cls != "" and d.cls != cls: continue
		out.append(s)
	return out

## Часть комплекта: set_id/piece можно задать, иначе — случайно под уровень и класс
static func roll_set(ilvl: int, own_cls: String, set_id := "", piece := -1) -> Dictionary:
	ilvl = maxi(5, ilvl)
	if set_id == "":
		var cands := sets_for_level(ilvl, pick_class(own_cls))
		if cands.is_empty(): cands = sets_for_level(ilvl)
		if cands.is_empty(): return roll(ilvl, own_cls, 0.5)
		set_id = cands.pick_random()
	var sd: Dictionary = SETS[set_id]
	var pieces: Array = sd.pieces
	var t: String = pieces[piece if piece >= 0 else randi() % pieces.size()]
	var td: Dictionary = TYPES[t]
	var it := {"uid": "%x%x" % [Time.get_ticks_usec(), randi()], "ilvl": ilvl, "slot": int(td.slot), "type": t, "cls": td.cls if sd.cls != "" else "",
		"req": req_level(ilvl), "mods": [], "rarity": SET_RARITY, "set": set_id}
	it.base = round(_base(t, ilvl) * 1.15)
	_affixes(it, 2, 1.2)
	it.name = "%s «%s»" % [td.names[tier_of(ilvl)], sd.name]
	return it

## Добыча с врага: обычные, элиты, редкие, боссы. Возвращает массив предметов
static func drop_items(lvl: int, own_cls: String, rank := "normal") -> Array:
	var out := []
	match rank:
		"normal":
			if randf() < 0.28: out.append(roll(lvl, own_cls, 0.0))
		"elite":
			out.append(roll(lvl, own_cls, 0.25))
			if randf() < 0.06: out.append(roll_set(lvl, own_cls))
		"rare":
			var it := roll(lvl + 1, own_cls, 0.5)
			while int(it.rarity) < 1: it = roll(lvl + 1, own_cls, 0.5)
			out.append(it); out.append(roll(lvl + 1, own_cls, 0.3))
			if randf() < 0.18: out.append(roll_set(lvl + 1, own_cls))
		"boss":
			for i in 3: out.append(roll(lvl + 1, own_cls, 0.5))
			if randf() < 0.4: out.append(roll_set(lvl + 1, own_cls))
		"dungeon":
			if randf() < 0.35: out.append(roll_set(lvl + 1, own_cls))
	return out

# ---------- требования и экипировка ----------
## "" — можно надеть, иначе причина (требование уровня — строго)
static func equip_block(c: Dictionary, it: Dictionary) -> String:
	if int(it.get("req", 1)) > int(c["level"]): return "Нужен уровень %d" % int(it.get("req", 1))
	var cls: String = it.get("cls", "")
	if cls != "" and cls != c["class"]: return "Только для класса: %s" % CLASS_NAMES.get(cls, cls)
	return ""

static func get_equipped(c: Dictionary, slot: int):
	for it in c["equipped"]:
		if int(it["slot"]) == slot: return it
	return null

## Надеть из инвентаря (или сундука) — старый предмет уходит на его место. "" при успехе
static func equip(c: Dictionary, it: Dictionary) -> String:
	var why := equip_block(c, it)
	if why != "": return why
	var src: Array = c["inventory"] if c["inventory"].has(it) else (c.get("stash", []) as Array)
	if not src.has(it): return "Предмет не найден"
	var cur = get_equipped(c, int(it.slot))
	src.erase(it)
	if cur != null:
		c["equipped"].erase(cur)
		src.append(cur)
	c["equipped"].append(it)
	return ""

static func unequip(c: Dictionary, it: Dictionary) -> String:
	if not c["equipped"].has(it): return "Не надето"
	if c["inventory"].size() >= INVENTORY_SIZE: return "Инвентарь полон"
	c["equipped"].erase(it)
	c["inventory"].append(it)
	return ""

# ---------- комплекты ----------
static func set_count(c: Dictionary, set_id: String) -> int:
	var slots := {}
	for it in c["equipped"]:
		if it.get("set", "") == set_id: slots[int(it.slot)] = true
	return slots.size()

## Активные бонусы комплектов: {mods: [[stat, v]...], fx: {}}
static func set_bonuses(c: Dictionary) -> Dictionary:
	var mods := []; var fx := {}
	var seen := {}
	for it in c["equipped"]:
		var sid: String = it.get("set", "")
		if sid == "" or seen.has(sid) or not SETS.has(sid): continue
		seen[sid] = true
		var n := set_count(c, sid)
		var sd: Dictionary = SETS[sid]
		if n >= 2: mods.append_array(sd.b2)
		if n >= 4: mods.append_array(sd.b4)
		if n >= 6:
			for k in sd.b6.fx: fx[k] = float(fx.get(k, 0.0)) + float(sd.b6.fx[k])
	return {"mods": mods, "fx": fx}

static func _owned_types(c: Dictionary, set_id: String) -> Dictionary:
	var own := {}
	for lst in [c["inventory"], c.get("stash", [])]:
		for it in lst:
			if it.get("set", "") == set_id: own[it.type] = true
	return own

# ---------- описание (BBCode) ----------
static func _c(col: Color) -> String: return col.to_html(false)

static func rarity_color(it: Dictionary) -> Color:
	return DB.RARITY_COLORS[clampi(int(it.rarity), 0, DB.RARITY_COLORS.size() - 1)]

## Подсказка: тип, требования (красным, если нельзя), характеристики, комплект, сравнение с надетым
static func tooltip(c: Dictionary, it: Dictionary, compare := true) -> String:
	var col := rarity_color(it)
	var s := "[color=#%s][b]%s[/b][/color]\n" % [_c(col), it.name]
	var t: String = it.get("type", "")
	s += "[color=#aaaaaa]%s · %s · ур. предмета %d[/color]\n" % [SLOT_NAMES[int(it.slot)], DB.RARITY_NAMES[clampi(int(it.rarity), 0, 4)], int(it.ilvl)]
	var req := int(it.get("req", 1))
	s += "[color=#%s]Требуется уровень %d[/color]\n" % ["ff5555" if req > int(c["level"]) else "cccccc", req]
	var cls: String = it.get("cls", "")
	if cls != "":
		s += "[color=#%s]Класс: %s%s[/color]\n" % ["ff5555" if cls != c["class"] else "cccccc", CLASS_NAMES.get(cls, cls), "" if cls == c["class"] else " (не ваш класс)"]
	else:
		s += "[color=#88cc88]Для всех классов[/color]\n"
	var cur = get_equipped(c, int(it.slot)) if compare else null
	if cur == it: cur = null
	if int(it.slot) == 0: s += "Урон: +%d%s\n" % [int(it.base), _delta(float(it.base), float(cur.base) if cur else 0.0, cur != null)]
	elif float(it.base) > 0 or (cur and float(cur.base) > 0): s += "Броня: +%d%s\n" % [int(it.base), _delta(float(it.base), float(cur.base) if cur else 0.0, cur != null)]
	var cur_mods := {}
	if cur: for m in cur.mods: cur_mods[m[0]] = float(cur_mods.get(m[0], 0.0)) + float(m[1])
	var mine := {}
	for m in it.mods:
		mine[m[0]] = true
		s += DB.describe_mod(m) + (_delta(float(m[1]), float(cur_mods.get(m[0], 0.0)), cur != null) if cur else "") + "\n"
	if cur:
		for k in cur_mods:
			if not mine.has(k): s += "[color=#ff6666]%s (пропадёт)[/color]\n" % DB.describe_mod([k, cur_mods[k]])
		s += "[color=#888888]Сравнение с надетым: %s[/color]\n" % cur.name
	var sid: String = it.get("set", "")
	if sid != "" and SETS.has(sid):
		var sd: Dictionary = SETS[sid]
		var n := set_count(c, sid)
		var own := _owned_types(c, sid)
		var eq := {}
		for e in c["equipped"]: if e.get("set", "") == sid: eq[e.type] = true
		s += "\n[color=#%s][b]Комплект «%s»[/b] (%d/6)[/color]\n" % [_c(DB.RARITY_COLORS[SET_RARITY]), sd.name, n]
		for pt in sd.pieces:
			var nm: String = TYPES[pt].names[tier_of(int(it.ilvl))]
			if eq.has(pt): s += "  [color=#66ff88]✔ %s (надето)[/color]\n" % nm
			elif own.has(pt): s += "  [color=#e6d36a]◦ %s (есть)[/color]\n" % nm
			else: s += "  [color=#777777]· %s[/color]\n" % nm
		for tier in [2, 4, 6]:
			var on: bool = n >= int(tier)
			var txt := ""
			if tier < 6:
				var parts := []
				for m in sd["b%d" % tier]: parts.append(DB.describe_mod(m))
				txt = ", ".join(parts)
			else: txt = sd.b6.desc
			s += "[color=#%s](%d) %s%s[/color]\n" % ["66ff88" if on else "777777", tier, txt, " — активно" if on else ""]
	return s.strip_edges()

static func _delta(v: float, old: float, show: bool) -> String:
	if not show: return ""
	var d := v - old
	if absf(d) < 0.05: return " [color=#999999](=)[/color]"
	return " [color=#%s](%s%s)[/color]" % ["66ff66" if d > 0 else "ff6666", "+" if d > 0 else "", str(int(d)) if absf(d) >= 5 else str(snappedf(d, 0.1))]

# ---------- сундук, массовые операции ----------
static func find_uid(lst: Array, uid: String):
	for it in lst:
		if str(it.uid) == uid: return it
	return null

## Переложить предметы (по uid) из одного списка в другой с лимитом. Возвращает число перемещённых
static func move_many(src: Array, dst: Array, uids: Array, cap: int) -> int:
	var n := 0
	for u in uids:
		if dst.size() >= cap: break
		var it = find_uid(src, str(u))
		if it == null: continue
		src.erase(it); dst.append(it); n += 1
	return n

static func to_stash(c: Dictionary, uids: Array) -> int:
	if not c.has("stash"): c["stash"] = []
	return move_many(c["inventory"], c["stash"], uids, STASH_SIZE)

static func from_stash(c: Dictionary, uids: Array) -> int:
	if not c.has("stash"): c["stash"] = []
	return move_many(c["stash"], c["inventory"], uids, INVENTORY_SIZE)

## Продать несколько: золото получено, предметы — в выкуп
static func sell_many(c: Dictionary, uids: Array) -> int:
	var gold := 0
	for u in uids:
		var it = find_uid(c["inventory"], str(u))
		if it == null: continue
		c["inventory"].erase(it)
		gold += DB.sell_price(it)
		var bb: Array = c.get("buyback", [])
		bb.push_front(it)
		while bb.size() > DB.BUYBACK_SIZE: bb.pop_back()
		c["buyback"] = bb
	c["gold"] = int(c["gold"]) + gold
	return gold

static func dust_value(it: Dictionary) -> int:
	return (1 + int(it.ilvl) / 3) * [1, 2, 4, 8, 6][clampi(int(it.rarity), 0, 4)]

## Разобрать на эфирную пыль (используется у торговца для обновления товаров)
static func dismantle_many(c: Dictionary, uids: Array) -> int:
	var dust := 0
	for u in uids:
		var it = find_uid(c["inventory"], str(u))
		if it == null: continue
		c["inventory"].erase(it)
		dust += dust_value(it)
	c["dust"] = int(c.get("dust", 0)) + dust
	return dust

## Выбрать по редкости (до max_rarity включительно); junk — обычные, хуже надетого или не своего класса
static func select_by_rarity(lst: Array, max_rarity: int) -> Array:
	var out := []
	for it in lst: if int(it.rarity) <= max_rarity and int(it.rarity) != 3 and int(it.rarity) != SET_RARITY: out.append(str(it.uid))
	return out

static func select_junk(c: Dictionary, lst: Array) -> Array:
	var out := []
	for it in lst:
		if int(it.rarity) == 0 or (int(it.rarity) <= 1 and it.get("cls", "") != "" and it.cls != c["class"]): out.append(str(it.uid))
	return out

## Сортировка: слот / редкость / уровень / тип
static func sorted(lst: Array, by := "rarity") -> Array:
	var a := lst.duplicate()
	match by:
		"rarity": a.sort_custom(func(x, y): return _rk(x) > _rk(y) or (_rk(x) == _rk(y) and int(x.ilvl) > int(y.ilvl)))
		"level": a.sort_custom(func(x, y): return int(x.ilvl) > int(y.ilvl) or (int(x.ilvl) == int(y.ilvl) and _rk(x) > _rk(y)))
		"slot": a.sort_custom(func(x, y): return int(x.slot) < int(y.slot) or (int(x.slot) == int(y.slot) and _rk(x) > _rk(y)))
		"type": a.sort_custom(func(x, y): return str(x.get("type", "")) < str(y.get("type", "")) or (str(x.get("type", "")) == str(y.get("type", "")) and int(x.ilvl) > int(y.ilvl)))
	return a

static func _rk(it) -> int:
	var r := int(it.rarity)
	return 5 if r == 3 else (4 if r == SET_RARITY else r)

const FILTERS := [["all", "Все"], ["weapon", "Оружие"], ["armor", "Броня"], ["jewel", "Украшения"], ["usable", "Подходит"], ["set", "Комплекты"]]
static func passes(c: Dictionary, it: Dictionary, f: String) -> bool:
	match f:
		"weapon": return int(it.slot) == 0
		"armor": return int(it.slot) in [1, 2, 4, 5, 7]
		"jewel": return int(it.slot) in [3, 6]
		"usable": return equip_block(c, it) == ""
		"set": return it.get("set", "") != ""
	return true

# ---------- миграция старых сохранений ----------
## Старые предметы: тип/класс/требование; оружие — класса персонажа, прочее — для всех.
## Надетое выше уровня снимается (жёсткий запрет); если места нет — в сундук.
static func migrate(c: Dictionary) -> void:
	if not c.has("stash"): c["stash"] = []
	if not c.has("dust"): c["dust"] = 0
	for lname in ["inventory", "equipped", "stash", "buyback"]:
		for it in c.get(lname, []): _fix(it, c["class"], int(c["level"]))
	if c.has("shop"): for it in c["shop"].get("stock", []): _fix(it, c["class"], 99)
	for it in (c["equipped"] as Array).duplicate():
		if int(it.get("req", 1)) > int(c["level"]) or (it.get("cls", "") != "" and it.cls != c["class"]):
			c["equipped"].erase(it)
			if c["inventory"].size() < INVENTORY_SIZE: c["inventory"].append(it)
			else: c["stash"].append(it)

## old_cap: старым вещам требование не выше текущего уровня — никто не теряет экипировку при обновлении
static func _fix(it: Dictionary, cls: String, old_cap := 99) -> void:
	if not it.has("uid"): it["uid"] = "%x%x" % [Time.get_ticks_usec(), randi()]
	if not it.has("req"): it["req"] = mini(req_level(int(it.get("ilvl", 1))), maxi(1, old_cap))
	if not it.has("type"):
		var nm := str(it.get("name", "")).to_lower()
		match int(it.get("slot", 0)):
			0:
				it["type"] = {"warrior": "axe" if ("топор" in nm or "секира" in nm) else "sword", "archer": "bow", "mage": "staff"}.get(cls, "sword")
				it["cls"] = cls
			1: it["type"] = "leather" if "кож" in nm else "plate"; it["cls"] = ""
			2: it["type"] = "hood" if "капюш" in nm else "helm"; it["cls"] = ""
			_: it["type"] = "ring"; it["cls"] = ""
	if not it.has("cls"): it["cls"] = ""
