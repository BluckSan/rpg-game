#!/usr/bin/env python3
"""Генератор пассивного дерева талантов (PoE-стиль).
Запуск: python3 tools/gen_talent_tree.py  -> data/talent_tree.json
Файл JSON можно править вручную: узлы, связи, статы.
"""
import json, math, os, random
random.seed(42)

REGIONS = [
  # id, angle, name, color, minor stat pool, notables, keystone
  ("berserker", 0,   "Ярость",     "#d9412b",
     [("dmg%",6,"Сила удара"),("as%",4,"Скорость атаки"),("leech%",0.6,"Кровожадность"),("hp",12,"Здоровье")],
     [("Кровавая жатва",[("dmg%",14),("leech%",1.5)]),("Неистовство",[("as%",10),("dmg%",8)]),("Шрамы ветерана",[("hp",40),("regen",1.5)])],
     ("Путь Берсерка",[("dmg%",20),("as%",8),("armor%",-10)])),
  ("paladin", 60,    "Вера",       "#e8c547",
     [("armor",10,"Броня"),("hp%",4,"Стойкость"),("regen",0.6,"Восстановление"),("armor%",6,"Закалка")],
     [("Святой бастион",[("armor",40),("armor%",12)]),("Благословение",[("hp%",10),("regen",2)]),("Праведный гнев",[("dmg%",10),("hp",30)])],
     ("Путь Паладина",[("hp%",15),("armor%",20),("regen",3)])),
  ("elementalist", 120, "Стихии",   "#3fa7e8",
     [("spell%",6,"Сила магии"),("mp",12,"Мана"),("cdr%",3,"Перезарядка"),("crit",1.5,"Точность чар")],
     [("Повелитель огня",[("spell%",15),("crit",3)]),("Поток маны",[("mp",40),("mpregen",1.5)]),("Буря",[("cdr%",8),("spell%",8)])],
     ("Путь Стихийника",[("spell%",25),("cdr%",10)])),
  ("necromancer", 180, "Тлен",      "#8b4fc9",
     [("spell%",5,"Тёмная магия"),("mp%",5,"Глубины разума"),("leech%",0.5,"Похищение жизни"),("mpregen",0.5,"Ток силы")],
     [("Жатва душ",[("leech%",2),("spell%",10)]),("Костяной доспех",[("armor",30),("hp",30)]),("Шёпот мёртвых",[("mp%",12),("mpregen",1.5)])],
     ("Путь Некроманта",[("spell%",15),("leech%",3),("hp%",8)])),
  ("shadow", 240,    "Тени",       "#3b3f58",
     [("crit",2,"Шанс крита"),("critdmg%",10,"Сила крита"),("ms%",3,"Ловкость"),("as%",4,"Быстрые руки")],
     [("Удар в спину",[("critdmg%",30),("crit",3)]),("Неуловимость",[("ms%",10),("as%",6)]),("Яд клинка",[("dmg%",12),("crit",2)])],
     ("Путь Тени",[("crit",8),("critdmg%",40),("ms%",8)])),
  ("druid", 300,     "Дикость",    "#4caf50",
     [("hp%",4,"Жизненная сила"),("regen",0.6,"Регенерация"),("dmg%",5,"Звериная мощь"),("ms%",3,"Бег зверя")],
     [("Шкура медведя",[("hp%",12),("armor",25)]),("Клыки",[("dmg%",14),("as%",5)]),("Зов леса",[("regen",3),("ms%",6)])],
     ("Путь Друида",[("hp%",20),("dmg%",12),("regen",2)])),
]
CLASSES = [("warrior",30,"Воин"),("mage",150,"Маг"),("archer",270,"Лучник")]

nodes = []
def add(name, typ, x, y, region="", mods=None, classId=""):
    n = {"id": len(nodes), "name": name, "type": typ, "region": region, "classId": classId,
         "x": round(x,1), "y": round(y,1), "mods": [{"stat":s,"value":v} for s,v in (mods or [])], "links": []}
    nodes.append(n); return n["id"]
def link(a,b):
    if b not in nodes[a]["links"]: nodes[a]["links"].append(b)
    if a not in nodes[b]["links"]: nodes[b]["links"].append(a)
def pol(r, deg):
    a = math.radians(deg); return r*math.cos(a), -r*math.sin(a)

starts = {}
for cid, ang, nm in CLASSES:
    x,y = pol(70, ang)
    starts[cid] = add(f"Начало: {nm}", "start", x, y, "", [], cid)
ring = {}
for i in range(12):
    ang = i*30
    x,y = pol(140, ang)
    ring[ang] = add("Основы", "minor", x, y, "", [random.choice([("hp",8),("mp",8),("dmg%",4),("armor",6)])])
for i in range(12):
    link(ring[i*30], ring[((i+1)%12)*30])
for cid, ang, nm in CLASSES:
    link(starts[cid], ring[ang]); link(starts[cid], ring[(ang-30)%360]); link(starts[cid], ring[(ang+30)%360])

chains = {}
for rid, ang, rname, color, pool, notables, key in REGIONS:
    chain = []
    radii = [200,255,310,365,420,475,530,585,640]
    for i,r in enumerate(radii):
        x,y = pol(r, ang)
        if i in (3,6):
            nm, mods = notables[0 if i==3 else 1]
            nid = add(nm, "notable", x, y, rid, mods)
        else:
            s,v,nm = pool[i % len(pool)]
            nid = add(nm, "minor", x, y, rid, [(s,v)])
        if chain: link(chain[-1], nid)
        chain.append(nid)
    link(ring[ang], chain[0])
    # боковые ветки
    for base_i, side_r in ((2,310),(5,475)):
        for side in (-1,1):
            prev = chain[base_i]
            for k in range(1,3):
                x,y = pol(side_r, ang + side*k*8)
                s,v,nm = pool[(k+base_i+side) % len(pool)]
                nid = add(nm, "minor", x, y, rid, [(s,v)])
                link(prev, nid); prev = nid
            if base_i==5 and side==1:
                x,y = pol(side_r+45, ang + side*20)
                nm, mods = notables[2]
                nid = add(nm, "notable", x, y, rid, mods); link(prev, nid)
            if base_i==2 and side==-1:
                x,y = pol(side_r+45, ang + side*20)
                s,v,nm = pool[0]
                nid = add(nm+" II", "minor", x, y, rid, [(s,v*1.5)]); link(prev, nid)
    x,y = pol(700, ang)
    kid = add(key[0], "keystone", x, y, rid, key[1]); link(chain[-1], kid)
    chains[rid] = chain

# мосты между соседними регионами
names = [r[0] for r in REGIONS]
for i, rid in enumerate(names):
    nxt = names[(i+1)%len(names)]
    a = REGIONS[i][1]; mid = a + 30
    for idx, r in ((4,410),(7,590)):
        x,y = pol(r*0.97, mid)
        nid = add("Перекрёсток", "minor", x, y, "", [random.choice([("hp",10),("dmg%",4),("mp",10),("ms%",2),("armor",8)])])
        link(chains[rid][idx], nid); link(chains[nxt][idx], nid)

regions = [{"id":r[0],"name":r[2],"color":r[3]} for r in REGIONS]
out = {"version": 1, "regions": regions, "nodes": nodes}
p = os.path.join(os.path.dirname(__file__), "..", "data", "talent_tree.json")
with open(p, "w", encoding="utf-8") as f: json.dump(out, f, ensure_ascii=False, indent=1)
print("nodes:", len(nodes))
