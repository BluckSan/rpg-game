#!/usr/bin/env python3
"""Генератор дерева талантов v2 (ранги, ветви-специализации, пассивы, модификаторы умений).
Запуск: python3 tools/gen_talent_tree.py  -> data/talent_tree.json

Структура (от центра наружу):
  * 3 стартовых узла классов + внутреннее кольцо «Основы»;
  * у каждого класса 3 ветви-специализации (малые узлы с рангами, особый узел, модификатор умений, ключевой пассив);
  * спицы к внешнему кольцу «Перекрёстки» — через него можно пройти в любой регион превращения;
  * 6 регионов превращения (как в v1, «Путь X» — ворота превращения);
  * за воротами 3 ветви пути превращения (доступны только выбравшему этот путь), каждая с ключевым пассивом.
Поля узла: id, name, type (start|minor|notable|mod|keystone), region, classId, branch, x, y,
  max_rank, mods (за ранг), fx (за ранг: пассивы/модификаторы), req_asc, req_branch (очков в ветви для ключевого), gate, desc, links.
"""
import json, math, os, random
random.seed(42)

nodes = []
def add(name, typ, x, y, region="", mods=None, classId="", branch="", max_rank=1, fx=None, req_asc="", req_branch=0, gate=False, desc=""):
    n = {"id": len(nodes), "name": name, "type": typ, "region": region, "classId": classId, "branch": branch,
         "x": round(x, 1), "y": round(y, 1), "max_rank": max_rank,
         "mods": [{"stat": s, "value": v} for s, v in (mods or [])],
         "fx": {k: v for k, v in (fx or {}).items()}, "links": []}
    if req_asc: n["req_asc"] = req_asc
    if req_branch: n["req_branch"] = req_branch
    if gate: n["gate"] = True
    if desc: n["desc"] = desc
    nodes.append(n); return n["id"]
def link(a, b):
    if b not in nodes[a]["links"]: nodes[a]["links"].append(b)
    if a not in nodes[b]["links"]: nodes[b]["links"].append(a)
def pol(r, deg):
    a = math.radians(deg); return r * math.cos(a), -r * math.sin(a)

CLASSES = [("warrior", 30, "Воин"), ("mage", 150, "Маг"), ("archer", 270, "Лучник")]

# Ветви классов: (id, имя, [(стат, за ранг, имя малого)] x2, особый (имя, моды за ранг), модификатор (имя, fx, описание), ключевой (имя, моды, fx, описание))
SPECS = {
 "warrior": [
  ("w_weapon", "Оружейник", [("dmg%", 3, "Тяжёлая рука"), ("crit", 1, "Точный удар")],
     ("Мастер клинка", [("dmg%", 7), ("critdmg%", 12)]),
     ("Широкий замах", {"aoe%": 25}, "Область умений +25%"),
     ("Буря клинков", [("dmg%", 8)], {"combo_wave": 1}, "Третий удар серии выпускает ударную волну (×1.2 урона, 4 м)")),
  ("w_guard", "Страж", [("armor", 8, "Закалка"), ("hp%", 3, "Стойкость")],
     ("Стальная кожа", [("armor%", 10), ("hp", 25)]),
     ("Шипы", {"thorns": 30}, "Отражает 30% полученного урона в ближайшего врага"),
     ("Несокрушимый", [("dr%", 12), ("ms%", -8)], {}, "−12% получаемого урона, но −8% скорости")),
  ("w_blood", "Кровопийца", [("leech%", 0.4, "Жажда"), ("hp", 10, "Здоровье")],
     ("Жажда крови", [("leech%", 1.0), ("regen", 1.0)]),
     ("Кровавые раны", {"proc_bleed": 20}, "20% шанс при ударе: кровотечение (60% урона за 3 с)"),
     ("Кровавый обет", [], {"leech_x": 1, "no_regen": 1, "low_hp_dmg": 40}, "Похищение жизни ×2, нет регенерации; +40% урона при здоровье ниже 35%")),
 ],
 "mage": [
  ("m_fire", "Пиромант", [("spell%", 4, "Жар"), ("critdmg%", 5, "Вспышка")],
     ("Сердце пламени", [("spell%", 9), ("crit", 2)]),
     ("Цепная молния+", {"chain_plus": 2}, "Цепные умения: +2 отскока"),
     ("Перегрузка", [("crit", 12)], {"mana_cost": 30}, "+12% шанса крита, но умения дороже на 30% маны")),
  ("m_frost", "Криомант", [("mp", 10, "Ледяной разум"), ("cdr%", 1.5, "Стужа")],
     ("Вечная мерзлота", [("cdr%", 4), ("mp%", 8)]),
     ("Ледяное пламя", {"elem_ice": 1}, "Огненные снаряды становятся ледяными: замедляют врагов на 40%"),
     ("Ледяное сердце", [], {"aura_dmg": 30, "aura_frost": 1}, "Морозная аура: 30% урона в секунду врагам рядом (4.5 м) и замедление")),
  ("m_arcane", "Чародей", [("mpregen", 0.5, "Ток маны"), ("mp%", 3, "Глубина")],
     ("Исток", [("mpregen", 1.5), ("mp", 25)]),
     ("Искры", {"proc_bolt": 15}, "15% шанс при ударе: молния в ближайшего врага (60% урона)"),
     ("Сосуд маны", [("mp%", 15)], {"mana_guard": 40}, "40% получаемого урона снимается с маны")),
 ],
 "archer": [
  ("a_aim", "Меткость", [("crit", 1.5, "Глаз"), ("critdmg%", 6, "Слабое место")],
     ("Глаз ястреба", [("crit", 3), ("critdmg%", 12)]),
     ("Метка охотника", {"crit_mark": 1}, "Крит проклинает цель на 3 с (+30% получаемого урона)"),
     ("Снайпер", [("critdmg%", 15)], {"far_dmg": 35}, "+35% урона по целям дальше 7 м")),
  ("a_volley", "Залп", [("as%", 3, "Быстрая рука"), ("dmg%", 3, "Наконечник")],
     ("Быстрая тетива", [("as%", 7)]),
     ("Расщепление", {"extra_proj": 2}, "+2 снаряда у стрел и снарядов умений"),
     ("Град стрел", [], {"extra_proj": 2, "proj_dmg": -20}, "Ещё +2 снаряда, но снаряды наносят на 20% меньше урона")),
  ("a_track", "Следопыт", [("ms%", 2, "Лёгкий шаг"), ("regen", 0.4, "Привал")],
     ("Ветер в ногах", [("ms%", 5), ("cdr%", 3)]),
     ("Ядовитые наконечники", {"proc_poison": 25}, "25% шанс при ударе: яд (80% урона за 4 с)"),
     ("Призрачный шаг", [("ms%", 5)], {"roll_stealth": 1}, "После кувырка следующий удар — гарантированный крит")),
 ],
}

# Регионы превращений (как в v1) + 3 ветви пути за воротами
REGIONS = [
  ("berserker", 0, "Ярость", "#d9412b",
     [("dmg%", 3, "Сила удара"), ("as%", 2, "Скорость атаки"), ("leech%", 0.3, "Кровожадность"), ("hp", 8, "Здоровье")],
     [("Кровавая жатва", [("dmg%", 10), ("leech%", 1)]), ("Неистовство", [("as%", 7), ("dmg%", 5)]), ("Шрамы ветерана", [("hp", 30), ("regen", 1)])],
     ("Путь Берсерка", [("dmg%", 20), ("as%", 8), ("armor%", -10)]),
     [("Резня", ("dmg%", 4), ("Кровавый вихрь", [("aoe%", 0)], {"aoe%": 15}), ("Кровавая баня", {"kill_explode": 40}, "Убитые враги взрываются: 40% шанс, 80% урона в 3 м")),
      ("Бешенство", ("as%", 3), ("Без устали", [("as%", 6)], {}), ("Неудержимый", {"low_hp_dmg": 60}, "+60% урона при здоровье ниже 35%")),
      ("Шрамы", ("hp%", 3), ("Толстая шкура", [("armor", 25)], {}), ("Боль — сила", {"thorns": 50}, "Отражает 50% полученного урона"))]),
  ("paladin", 60, "Вера", "#e8c547",
     [("armor", 7, "Броня"), ("hp%", 2, "Стойкость"), ("regen", 0.4, "Восстановление"), ("armor%", 4, "Закалка")],
     [("Святой бастион", [("armor", 30), ("armor%", 8)]), ("Благословение", [("hp%", 7), ("regen", 1.5)]), ("Праведный гнев", [("dmg%", 7), ("hp", 25)])],
     ("Путь Паладина", [("hp%", 15), ("armor%", 20), ("regen", 3)]),
     [("Свет", ("dmg%", 3), ("Сияние", [("hp", 20)], {"aura_dmg": 10}), ("Аура возмездия", {"aura_dmg": 40}, "Святая аура: 40% урона в секунду врагам рядом")),
      ("Щит", ("armor", 10), ("Оплот", [("armor%", 10)], {}), ("Божественный щит", {"dr%": 10}, "−10% получаемого урона")),
      ("Милость", ("regen", 0.6), ("Исцеление", [("hp%", 5)], {}), ("Исцеляющий свет", {"crit_heal": 3}, "Крит лечит 3% здоровья"))]),
  ("elementalist", 120, "Стихии", "#3fa7e8",
     [("spell%", 4, "Сила магии"), ("mp", 8, "Мана"), ("cdr%", 1.5, "Перезарядка"), ("crit", 1, "Точность чар")],
     [("Повелитель огня", [("spell%", 10), ("crit", 2)]), ("Поток маны", [("mp", 30), ("mpregen", 1)]), ("Буря", [("cdr%", 5), ("spell%", 5)])],
     ("Путь Стихийника", [("spell%", 25), ("cdr%", 10)]),
     [("Огонь", ("spell%", 3), ("Тлеющие угли", [("critdmg%", 10)], {}), ("Пожар", {"proc_burn": 30}, "30% шанс поджечь (100% урона за 4 с)")),
      ("Молния", ("cdr%", 1.5), ("Разряд", [("crit", 2)], {}), ("Грозовой вестник", {"proc_bolt": 25, "chain_plus": 1}, "25% шанс молнии при ударе, цепи +1 отскок")),
      ("Лёд", ("mp", 10), ("Иней", [("mp%", 6)], {}), ("Стужа", {"elem_ice": 1, "aura_frost": 1, "aura_dmg": 15}, "Огонь становится льдом, морозная аура"))]),
  ("necromancer", 180, "Тлен", "#8b4fc9",
     [("spell%", 3, "Тёмная магия"), ("mp%", 3, "Глубины разума"), ("leech%", 0.3, "Похищение жизни"), ("mpregen", 0.4, "Ток силы")],
     [("Жатва душ", [("leech%", 1.5), ("spell%", 7)]), ("Костяной доспех", [("armor", 25), ("hp", 25)]), ("Шёпот мёртвых", [("mp%", 8), ("mpregen", 1)])],
     ("Путь Некроманта", [("spell%", 15), ("leech%", 3), ("hp%", 8)]),
     [("Кости", ("armor", 8), ("Костяной панцирь", [("hp", 30)], {}), ("Костяная броня", {"dr%": 8, "thorns": 25}, "−8% урона, отражение 25%")),
      ("Души", ("leech%", 0.4), ("Сбор душ", [("mp", 20)], {}), ("Пожиратель душ", {"kill_heal": 8, "kill_mana": 10}, "Убийство: +8% здоровья и +10% маны")),
      ("Мор", ("spell%", 3), ("Гниль", [("dmg%", 5)], {}), ("Чума", {"kill_explode": 50, "proc_poison": 20}, "Трупы взрываются (50%), яд при ударе (20%)"))]),
  ("shadow", 240, "Тени", "#3b3f58",
     [("crit", 1.5, "Шанс крита"), ("critdmg%", 6, "Сила крита"), ("ms%", 2, "Ловкость"), ("as%", 2, "Быстрые руки")],
     [("Удар в спину", [("critdmg%", 20), ("crit", 2)]), ("Неуловимость", [("ms%", 7), ("as%", 4)]), ("Яд клинка", [("dmg%", 8), ("crit", 1.5)])],
     ("Путь Тени", [("crit", 8), ("critdmg%", 40), ("ms%", 8)]),
     [("Клинок", ("crit", 1.5), ("Острие", [("critdmg%", 10)], {}), ("Убийца", {"crit_mark": 1, "critdmg%": 30}, "Крит проклинает цель, +30% силы крита")),
      ("Дым", ("ms%", 2), ("Дымка", [("as%", 5)], {}), ("Призрак", {"roll_stealth": 1}, "После кувырка — гарантированный крит")),
      ("Яд", ("dmg%", 3), ("Отрава", [("crit", 2)], {}), ("Ядовитая тень", {"proc_poison": 35}, "35% шанс отравить при ударе"))]),
  ("druid", 300, "Дикость", "#4caf50",
     [("hp%", 3, "Жизненная сила"), ("regen", 0.4, "Регенерация"), ("dmg%", 3, "Звериная мощь"), ("ms%", 2, "Бег зверя")],
     [("Шкура медведя", [("hp%", 8), ("armor", 20)]), ("Клыки", [("dmg%", 10), ("as%", 4)]), ("Зов леса", [("regen", 2), ("ms%", 4)])],
     ("Путь Друида", [("hp%", 20), ("dmg%", 12), ("regen", 2)]),
     [("Медведь", ("hp", 15), ("Мех", [("armor", 20)], {}), ("Шкура древня", {"dr%": 10, "hp%": 15}, "−10% урона, +15% здоровья")),
      ("Волк", ("as%", 3), ("Охота", [("ms%", 5)], {}), ("Стая", {"aura_dmg": 25, "ms%": 6}, "Аура когтей: 25% урона в секунду врагам рядом")),
      ("Рост", ("regen", 0.6), ("Побеги", [("hp%", 5)], {}), ("Цветение", {"regen": 6, "crit_heal": 2}, "+6 регенерации, крит лечит 2%"))]),
]

# --- центр ---
starts = {}
for cid, ang, nm in CLASSES:
    x, y = pol(70, ang)
    starts[cid] = add(f"Начало: {nm}", "start", x, y, "", [], cid)
ring = {}
for i in range(12):
    ang = i * 30
    x, y = pol(140, ang)
    ring[ang] = add("Основы", "minor", x, y, "", [random.choice([("hp", 6), ("mp", 6), ("dmg%", 2), ("armor", 4)])], max_rank=3)
for i in range(12):
    link(ring[i * 30], ring[((i + 1) % 12) * 30])
for cid, ang, nm in CLASSES:
    link(starts[cid], ring[ang]); link(starts[cid], ring[(ang - 30) % 360]); link(starts[cid], ring[(ang + 30) % 360])

# --- ветви классов ---
for cid, ang, nm in CLASSES:
    for bi, (bid, bname, pool, notable, mod, key) in enumerate(SPECS[cid]):
        a = ang + (bi - 1) * 15
        prev = ring[ang]
        chain_def = [
            ("minor", pool[0][2], [(pool[0][0], pool[0][1])], {}, 3, ""),
            ("minor", pool[1][2], [(pool[1][0], pool[1][1])], {}, 3, ""),
            ("notable", notable[0], notable[1], {}, 2, ""),
            ("mod", mod[0], [], mod[1], 1, mod[2]),
            ("minor", pool[0][2] + " II", [(pool[0][0], pool[0][1])], {}, 3, ""),
            ("keystone", key[0], key[1], key[2], 1, key[3]),
        ]
        for k, (typ, name, mods, fx, mr, desc) in enumerate(chain_def):
            x, y = pol(205 + k * 55, a)
            nid = add(name, typ, x, y, "", mods, cid if k == 0 else "", bid, mr, fx, "", 6 if typ == "keystone" else 0, False, desc)
            link(prev, nid); prev = nid
        # подпись ветви хранится на первом узле
        nodes[prev - 5]["branch_name"] = bname
        nodes[prev - 5]["branch_class"] = cid

# --- спицы и внешнее кольцо ---
OUT_R = 560
outer = {}
for i in range(12):
    ang = i * 30
    x, y = pol(OUT_R, ang)
    outer[ang] = add("Перекрёсток", "minor", x, y, "", [random.choice([("hp", 8), ("dmg%", 3), ("mp", 8), ("ms%", 2), ("armor", 6)])], max_rank=2)
for i in range(12):
    link(outer[i * 30], outer[((i + 1) % 12) * 30])
for ang in range(0, 360, 60):
    prev = ring[ang]
    for r in (240, 340, 450):
        x, y = pol(r, ang)
        nid = add("Тропа", "minor", x, y, "", [random.choice([("hp", 6), ("dmg%", 2), ("mp", 6), ("armor", 5)])], max_rank=2)
        link(prev, nid); prev = nid
    link(prev, outer[ang])

# --- регионы превращения ---
OFF = 400
chains = {}
for rid, ang, rname, color, pool, notables, key, asc_branches in REGIONS:
    chain = []
    radii = [200, 255, 310, 365, 420, 475, 530, 585, 640]
    for i, r in enumerate(radii):
        x, y = pol(r + OFF, ang)
        if i in (3, 6):
            nm, mods = notables[0 if i == 3 else 1]
            nid = add(nm, "notable", x, y, rid, mods, max_rank=2)
        else:
            s, v, nm = pool[i % len(pool)]
            nid = add(nm, "minor", x, y, rid, [(s, v)], max_rank=3)
        if chain: link(chain[-1], nid)
        chain.append(nid)
    link(outer[ang], chain[0])
    for base_i, side_r in ((2, 310), (5, 475)):
        for side in (-1, 1):
            prev = chain[base_i]
            for k in range(1, 3):
                x, y = pol(side_r + OFF, ang + side * k * 7)
                s, v, nm = pool[(k + base_i + side) % len(pool)]
                nid = add(nm, "minor", x, y, rid, [(s, v)], max_rank=3)
                link(prev, nid); prev = nid
            if base_i == 5 and side == 1:
                x, y = pol(side_r + OFF + 45, ang + side * 17)
                nm, mods = notables[2]
                nid = add(nm, "notable", x, y, rid, mods, max_rank=2); link(prev, nid)
    x, y = pol(700 + OFF, ang)
    gate = add(key[0], "keystone", x, y, rid, key[1], gate=True, desc="Ворота превращения: открывает путь «%s»" % rname)
    link(chain[-1], gate)
    chains[rid] = chain
    # ветви пути (только для выбравших это превращение)
    for bi, (bname, minor, notable, keyst) in enumerate(asc_branches):
        a = ang + (bi - 1) * 8
        prev = gate
        bid = f"{rid}_{bi}"
        x, y = pol(1170, a)
        n1 = add(bname, "minor", x, y, rid, [minor], "", bid, 3, {}, rid)
        nodes[n1]["branch_name"] = bname
        x, y = pol(1235, a)
        nm_mods = [m for m in notable[1] if m[1] != 0]
        n2 = add(notable[0], "notable", x, y, rid, nm_mods, "", bid, 2, notable[2], rid, desc="")
        stat_mods = [(k, v) for k, v in keyst[1].items() if k in ("critdmg%", "hp%", "ms%", "regen", "dr%")]
        fx = {k: v for k, v in keyst[1].items() if k not in ("critdmg%", "hp%", "ms%", "regen", "dr%")}
        x, y = pol(1305, a)
        n3 = add(keyst[0], "keystone", x, y, rid, stat_mods, "", bid, 1, fx, rid, 4, desc=keyst[2])
        link(gate, n1); link(n1, n2); link(n2, n3)

# мосты между соседними регионами
names = [r[0] for r in REGIONS]
for i, rid in enumerate(names):
    nxt = names[(i + 1) % len(names)]
    a = REGIONS[i][1]; mid = a + 30
    for idx, r in ((4, 410), (7, 590)):
        x, y = pol((r + OFF) * 0.97, mid)
        nid = add("Перекрёсток", "minor", x, y, "", [random.choice([("hp", 8), ("dmg%", 3), ("mp", 8), ("ms%", 2), ("armor", 6)])], max_rank=2)
        link(chains[rid][idx], nid); link(chains[nxt][idx], nid)

regions = [{"id": r[0], "name": r[2], "color": r[3]} for r in REGIONS]
out = {"version": 2, "regions": regions, "nodes": nodes}
p = os.path.join(os.path.dirname(__file__), "..", "data", "talent_tree.json")
with open(p, "w", encoding="utf-8") as f: json.dump(out, f, ensure_ascii=False, indent=1)
import collections
print("nodes:", len(nodes), collections.Counter(n["type"] for n in nodes))
