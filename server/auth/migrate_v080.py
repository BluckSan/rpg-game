#!/usr/bin/env python3
"""v0.8.0: перевод предметов всех героев в БД с процентных характеристик на плоские.
Та же формула, что Items.migrate_item_v8 (GDScript): качество старого броска сохраняется,
значение = lerp(k_lo, k_hi, q) * (ур. предмета + 4) * множитель редкости. Идемпотентно (поле "v": 8).
Перед изменением делается копия таблицы characters_bak_v080. Запуск: sudo -u rpg python3 migrate_v080.py [--dry]"""
import json, math, os, sys

ITEM_V = 8
RARITY_MULT = [1.0, 1.08, 1.18, 1.35, 1.25]
SET_RARITY = 4
NEW = {"str": (0.45, 0.8), "dex": (0.45, 0.8), "int": (0.45, 0.8), "vit": (0.35, 0.65), "dmg": (0.18, 0.36),
       "hp": (1.6, 3.0), "mp": (1.2, 2.4), "armor": (0.8, 1.6), "regen": (0.03, 0.07), "mpregen": (0.03, 0.07),
       "crit_r": (0.45, 0.85), "haste_r": (0.45, 0.85), "pen": (0.4, 0.8)}
OLD = {"hp": (10, 40), "mp": (10, 35), "dmg%": (4, 15), "as%": (3, 10), "ms%": (2, 8), "crit": (1, 5),
       "critdmg%": (8, 25), "armor": (8, 30), "regen": (0.5, 2.5), "spell%": (5, 16), "leech%": (0.3, 1.5), "cdr%": (2, 6),
       "pen%": (4, 12), "resred": (3, 10)}
MAP = {"dmg%": "dmg", "spell%": "int", "as%": "haste_r", "cdr%": "haste_r", "crit": "crit_r", "critdmg%": "dex",
       "ms%": "vit", "leech%": "hp", "pen%": "pen", "resred": "pen", "hp%": "vit", "mp%": "mp", "armor%": "armor", "dr%": "armor",
       "hp": "hp", "mp": "mp", "armor": "armor", "regen": "regen", "mpregen": "mpregen", "dmg": "dmg"}
WARDEN = {"warrior": [("str", 1.0), ("vit", 0.7), ("dmg", 0.4), ("armor", 1.6)],
          "archer": [("dex", 1.0), ("haste_r", 0.9), ("crit_r", 0.9), ("dmg", 0.4)],
          "mage": [("int", 1.0), ("mp", 2.6), ("haste_r", 0.8), ("mpregen", 0.08)],
          "ring": [("hp", 3.2), ("dmg", 0.35), ("vit", 0.6), ("regen", 0.08)]}


def gd_round(x):  # как round() в Godot: половина — от нуля
    return math.floor(x + 0.5) if x >= 0 else -math.floor(-x + 0.5)


def round_stat(v):
    return float(gd_round(v)) if abs(v) >= 5 else gd_round(v * 10) / 10.0


def migrate_item(it):
    if not isinstance(it, dict) or int(it.get("v", 0)) >= ITEM_V:
        return False
    ilvl = int(it.get("ilvl", 1)); rar = max(0, min(4, int(it.get("rarity", 0))))
    u = str(it.get("unique", ""))
    if u.startswith("warden_") and u[7:] in WARDEN:
        it["mods"] = [[k, round_stat(c * (ilvl + 4) * RARITY_MULT[3])] for k, c in WARDEN[u[7:]]]
        it["v"] = ITEM_V
        return True
    old_mult = 1.5 if rar == 3 else (1.2 if rar == SET_RARITY else 1.0)
    lvk = 1.0 + ilvl * 0.08
    out, order = {}, []
    for m in it.get("mods", []):
        if not isinstance(m, list) or len(m) < 2:
            continue
        st, v = str(m[0]), float(m[1])
        q = 0.6
        if st in OLD:
            lo, hi = OLD[st][0] * lvk * old_mult, OLD[st][1] * lvk * old_mult
            q = min(1.0, max(0.0, (v - lo) / max(0.001, hi - lo)))
        ns = MAP.get(st, st)
        if ns not in NEW:
            continue
        a, b = NEW[ns]
        nv = (a + (b - a) * q) * (ilvl + 4) * RARITY_MULT[rar]
        if ns not in out:
            order.append(ns)
        out[ns] = out.get(ns, 0.0) + nv
    it["mods"] = [[ns, round_stat(out[ns])] for ns in order]
    it["v"] = ITEM_V
    return True


def migrate_char(c):
    n = 0
    for lst in ("inventory", "equipped", "stash", "buyback"):
        for it in c.get(lst, []) or []:
            n += migrate_item(it)
    shop = c.get("shop")
    if isinstance(shop, dict):
        for it in shop.get("stock", []) or []:
            n += migrate_item(it)
    return n


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--test":
        c = json.load(sys.stdin); migrate_char(c); print(json.dumps(c, ensure_ascii=False)); return
    import psycopg2
    from psycopg2.extras import Json
    dry = "--dry" in sys.argv
    con = psycopg2.connect(os.environ.get("RPG_DSN", "dbname=rpg user=rpg host=/var/run/postgresql"))
    cur = con.cursor()
    if not dry:
        cur.execute("CREATE TABLE IF NOT EXISTS characters_bak_v080 AS SELECT * FROM characters")
    cur.execute("SELECT id, data FROM characters FOR UPDATE")
    chars = items = 0
    for cid, data in cur.fetchall():
        k = migrate_char(data)
        if k:
            chars += 1; items += k
            if not dry:
                cur.execute("UPDATE characters SET data = %s WHERE id = %s", (Json(data), cid))
    if dry:
        con.rollback()
    else:
        con.commit()
    print("migrate_v080: героев %d, предметов %d%s" % (chars, items, " (проверка, без записи)" if dry else ""))


if __name__ == "__main__":
    main()
