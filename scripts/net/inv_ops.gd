extends RefCounted
class_name InvOps
## v0.9.2: операции с вещами и золотом. Офлайн — применяются к герою напрямую; онлайн клиент применяет их
## у себя (сразу видно) и шлёт на сервер, где та же операция выполняется над серверной копией героя.
## Сервер — владелец инвентаря: после операции присылает своё состояние (s_inv), клиент принимает его как есть.

const KEYS := ["inventory", "equipped", "stash", "buyback", "gold", "potions", "dust", "mats", "shop", "craft_n"]
const OPS := ["equip", "unequip", "sell", "dismantle", "to_stash", "from_stash", "buy", "buyback", "potion_buy", "potion_use",
	"restock", "restock_dust", "upgrade", "shop_sync"]

static func pub(c: Dictionary) -> Dictionary:
	var out := {}
	for k in KEYS: if c.has(k): out[k] = c[k]
	return out

static func _uids(args: Array) -> Array:
	var out := []
	for a in args.slice(0, 120): out.append(str(a).left(40))
	return out

static func _find(c: Dictionary, lst: String, uid: String):
	return Items.find_uid(c.get(lst, []), uid)

## Применить операцию. Возвращает {err, ...}; err == "" — успешно
static func apply(c: Dictionary, op: String, args: Array) -> Dictionary:
	if not OPS.has(op): return {"err": "неизвестная операция"}
	DB.shop_ensure(c)
	var a0 := str(args[0]).left(40) if args.size() > 0 else ""
	match op:
		"equip":
			var it = _find(c, "inventory", a0)
			if it == null: it = _find(c, "stash", a0)
			if it == null: return {"err": "нет предмета"}
			return {"err": Items.equip(c, it)}
		"unequip":
			var it = _find(c, "equipped", a0)
			if it == null: return {"err": "нет предмета"}
			if int(it.slot) == 0: return {"err": "Без оружия никак!"}
			return {"err": Items.unequip(c, it)}
		"sell": return {"err": "", "n": Items.sell_many(c, _uids(args))}
		"dismantle": return {"err": "", "n": Items.dismantle_many(c, _uids(args))}
		"to_stash": return {"err": "", "n": Items.to_stash(c, _uids(args))}
		"from_stash": return {"err": "", "n": Items.from_stash(c, _uids(args))}
		"buy":
			var stock: Array = c["shop"]["stock"]
			var it = Items.find_uid(stock, a0)
			if it == null: return {"err": "Нет товара"}
			return {"err": DB.shop_buy(c, stock.find(it))}
		"buyback":
			var bb: Array = c["buyback"]
			var it = Items.find_uid(bb, a0)
			if it == null: return {"err": "Нет предмета"}
			return {"err": DB.shop_buyback(c, bb.find(it))}
		"potion_buy": return {"err": DB.shop_buy_potion(c, clampi(int(args[0]) if args.size() > 0 else 1, 1, 20))}
		"potion_use":
			if int(c.get("potions", 0)) <= 0: return {"err": "Нет зелий"}
			c["potions"] = int(c["potions"]) - 1
			return {"err": ""}
		"restock":
			var price := DB.shop_restock_price(int(c["level"]))
			if int(c["gold"]) < price: return {"err": "Не хватает золота"}
			c["gold"] = int(c["gold"]) - price
			c["shop"]["stock"] = DB.shop_stock(int(c["level"]), c["class"])
			return {"err": ""}
		"restock_dust":
			var p := 10 + int(c["level"]) * 2
			if int(c.get("dust", 0)) < p: return {"err": "Не хватает эфирной пыли"}
			c["dust"] = int(c["dust"]) - p
			c["shop"]["stock"] = DB.shop_stock(int(c["level"]), c["class"])
			return {"err": ""}
		"upgrade":
			var r := Items.upgrade(c, a0)
			r["err"] = str(r.get("err", ""))
			return r
		"shop_sync": return {"err": ""}
	return {"err": "?"}

## Совпадают ли вещи и золото клиента с серверными (сверка при сохранении)
static func same(a: Dictionary, b: Dictionary) -> bool:
	for k in ["gold", "potions", "dust"]:
		if int(a.get(k, 0)) != int(b.get(k, 0)): return false
	for k in ["inventory", "equipped", "stash"]:
		var ua := []; var ub := []
		for it in a.get(k, []): if it is Dictionary: ua.append(str(it.get("uid", "")) + ":%d" % int(it.get("up", 0)))
		for it in b.get(k, []): if it is Dictionary: ub.append(str(it.get("uid", "")) + ":%d" % int(it.get("up", 0)))
		ua.sort(); ub.sort()
		if ua != ub: return false
	return true
