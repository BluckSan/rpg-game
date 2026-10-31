extends RefCounted
class_name MapMarks
## v0.9.4.2: метки игрока на карте. Хранятся в данных героя: data["map_marks"] = {зона: [{x, z, n}]}.
## Ставятся/снимаются на карте мира и на мини-карте; на мини-карте видны всегда (вне радиуса — стрелка у края).

const MAX := 24
const COLORS := [Color(0.3, 1.0, 0.55), Color(1.0, 0.45, 0.85), Color(0.35, 0.75, 1.0), Color(1.0, 0.65, 0.2)]

static func _zid(data: Dictionary) -> String: return str(data.get("zone", "starter"))

static func list(data: Dictionary, zid := "") -> Array:
	if zid == "": zid = _zid(data)
	var all = data.get("map_marks", {})
	if not (all is Dictionary): return []
	var l = all.get(zid, [])
	return l if l is Array else []

static func add(data: Dictionary, p: Vector2, name := "", zid := "") -> bool:
	if zid == "": zid = _zid(data)
	if not (data.get("map_marks") is Dictionary): data["map_marks"] = {}
	var all: Dictionary = data["map_marks"]
	if not (all.get(zid) is Array): all[zid] = []
	var l: Array = all[zid]
	if l.size() >= MAX:
		Game.toast("Не больше %d меток — снимите лишние" % MAX, 2.0)
		return false
	if name == "": name = "Метка %d" % (l.size() + 1)
	l.append({"x": snappedf(p.x, 0.1), "z": snappedf(p.y, 0.1), "n": name.left(24), "c": l.size() % COLORS.size()})
	_save(data)
	return true

## Индекс ближайшей метки в радиусе r (мировые метры) или -1
static func nearest(data: Dictionary, p: Vector2, r: float, zid := "") -> int:
	var best := -1; var bd := r
	var l := list(data, zid)
	for i in l.size():
		var d := pos(l[i]).distance_to(p)
		if d < bd: bd = d; best = i
	return best

static func remove(data: Dictionary, i: int, zid := "") -> bool:
	var l := list(data, zid)
	if i < 0 or i >= l.size(): return false
	l.remove_at(i)
	_save(data)
	return true

## Снять метку рядом, иначе поставить новую. true — поставлена, false — снята/не удалось
static func toggle(data: Dictionary, p: Vector2, r: float, zid := "") -> bool:
	var i := nearest(data, p, r, zid)
	if i >= 0:
		remove(data, i, zid); Game.toast("Метка снята", 1.2)
		return false
	var ok := add(data, p, "", zid)
	if ok: Game.toast("Метка поставлена", 1.2)
	return ok

static func pos(m) -> Vector2: return Vector2(float(m.get("x", 0)), float(m.get("z", 0)))
static func color(m) -> Color: return COLORS[int(m.get("c", 0)) % COLORS.size()]

static func _save(data: Dictionary) -> void:
	if is_same(data, Game.current) and not data.is_empty(): Game.save_character(data)
