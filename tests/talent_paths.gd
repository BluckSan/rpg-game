extends RefCounted
## v0.9.1: сборки «по пути» для balance_test: кратчайшая дорога к ветви/региону, затем сама ветвь/регион
## (жадно по роли), остаток — в общие узлы и ветви класса (без чужих регионов превращения).
const TE := preload("res://tests/talent_eval.gd")

const PATHS := {
	"warrior": [["w_weapon", "урон"], ["w_guard", "танк"], ["w_blood", "урон"], ["berserker", "урон"], ["paladin", "танк"], ["druid", "танк"], ["herald", "поддержка"]],
	"archer": [["a_aim", "урон"], ["a_volley", "урон"], ["a_track", "урон"], ["shadow", "урон"], ["druid", "танк"], ["berserker", "урон"], ["hunter", "поддержка"]],
	"mage": [["m_fire", "урон"], ["m_frost", "урон"], ["m_arcane", "танк"], ["elementalist", "урон"], ["necromancer", "урон"], ["paladin", "танк"], ["arcanist", "поддержка"]],
}

static func gear(c: Dictionary, cls: String, lvl: int, g0: int, g1: int, sd: int) -> void:
	seed(sd)
	c["equipped"].clear()
	for sl in Items.SLOT_COUNT:
		var it := Items.roll(int((g0 + g1) / 2), cls, 0.6, false, sl)
		while int(it.rarity) != 2: it = Items.roll(int((g0 + g1) / 2), cls, 0.6, false, sl)
		it["req"] = mini(int(it.req), lvl)
		c["equipped"].append(it)

static func score(e: Dictionary, role: String) -> float:
	match role:
		"танк": return pow(e.off, 0.35) * e.def
		"поддержка": return pow(e.off, 0.5) * pow(e.def, 0.8)
	return e.off * sqrt(e.def)

static func in_target(n: Dictionary, path: String) -> bool:
	return n["region"] == path or n["branch"] == path

static func build(cls: String, path: String, role: String, lvl: int, boss_lvl: int, sd := 7) -> Dictionary:
	var c := DB.new_character("Путь", cls, {})
	c["level"] = lvl; c["class_level"] = lvl
	gear(c, cls, lvl, lvl - 2, lvl, sd)
	# 1) дорога: BFS по узлам вне регионов (и сам целевой регион)
	var start := DB.start_node(cls)
	var prev := {start: -1}; var q := [start]; var goal := -1
	while not q.is_empty():
		var id: int = q.pop_front()
		if in_target(DB.tree_nodes[id], path) and DB.tree_nodes[id]["req_asc"] == "": goal = id; break
		for l in DB.tree_nodes[id]["links"]:
			var n: Dictionary = DB.tree_nodes[int(l)]
			if prev.has(int(l)): continue
			if n["region"] != "" and n["region"] != path: continue
			if n["req_asc"] != "": continue
			prev[int(l)] = id; q.append(int(l))
	var road := []
	var k := goal
	while k != -1 and k != start: road.push_front(k); k = prev[k]
	for id in road: DB.allocate(c, id)
	var road_cost := road.size()
	var is_branch := DB.get_asc(path).is_empty()
	# 2) цель, затем 3) остальное. Жадно по приросту оценки на очко; ключевые узлы и ворота —
	#    «пакетом» (дорога к ним + нужные очки в ветви), иначе жадный выбор их никогда не достаёт.
	for phase in 2:
		var guard := 0
		while DB.free_points(c) > 0 and guard < 300:
			guard += 1
			var base := score(TE.eval(c, boss_lvl), role)
			var best_plan := []; var bs := -1e9
			var cands := {}
			for id in c["talents"]:
				cands[int(id)] = true
				for l in DB.tree_nodes[int(id)]["links"]: cands[int(l)] = true
			var plans := []
			for id in cands: plans.append([id])
			if phase == 0:
				for id in DB.tree_order:
					var n: Dictionary = DB.tree_nodes[id]
					if n["type"] == "keystone" and in_target(n, path) and not c["talents"].has(id): plans.append(_plan_to(c, id, path))
			for plan in plans:
				if plan.is_empty(): continue
				var last: Dictionary = DB.tree_nodes[int(plan[-1])]
				if phase == 0 and not in_target(last, path): continue
				if phase == 1 and last["region"] != "" and last["region"] != path: continue
				if phase == 1 and is_branch and last["branch"] != "" and last["branch"] != path: continue
				var cc := c.duplicate(true)
				var ok := true
				for id in plan:
					if not DB.allocate(cc, int(id)): ok = false; break
					_try_asc(cc, path)
				if not ok: continue
				var s := (score(TE.eval(cc, boss_lvl), role) - base) / float(plan.size())
				if s > bs: bs = s; best_plan = plan
			if best_plan.is_empty(): break
			for id in best_plan:
				DB.allocate(c, int(id))
				_try_asc(c, path)
	DB.auto_build_skills(c)
	return {"c": c, "road": road_cost}

## Пакет до ключевого узла: дорога по связям (внутри цели), затем ранги в ветви до требования, затем он сам
static func _plan_to(c: Dictionary, key: int, path: String) -> Array:
	var prev := {}; var q := []
	for id in c["talents"]: prev[int(id)] = -1; q.append(int(id))
	var found := false
	while not q.is_empty():
		var id: int = q.pop_front()
		if id == key: found = true; break
		for l in DB.tree_nodes[id]["links"]:
			if prev.has(int(l)): continue
			var n: Dictionary = DB.tree_nodes[int(l)]
			if not in_target(n, path): continue
			if n["req_asc"] != "" and int(l) != key and n["region"] == path and c["ascendancy"] == "" and not n["gate"]:
				# ветви пути — только после ворот; ворота сами — gate
				pass
			prev[int(l)] = id; q.append(int(l))
	if not found: return []
	var road := []
	var k := key
	while prev[k] != -1: road.push_front(k); k = prev[k]
	var kn: Dictionary = DB.tree_nodes[key]
	var need := int(kn["req_branch"])
	var plan := road.slice(0, road.size() - 1)
	if need > 0:
		var cc := c.duplicate(true)
		for id in plan: DB.allocate(cc, int(id))
		var g := 0
		while DB.points_in_branch(cc, kn["branch"]) < need and g < 30:
			g += 1
			var added := false
			for id in cc["talents"]:
				var n: Dictionary = DB.tree_nodes[int(id)]
				if n["branch"] == kn["branch"] and n["type"] != "keystone" and DB.can_allocate(cc, int(id)):
					DB.allocate(cc, int(id)); plan.append(int(id)); added = true; break
			if not added:
				for id in DB.tree_order:
					var n: Dictionary = DB.tree_nodes[id]
					if n["branch"] == kn["branch"] and n["type"] != "keystone" and id != key and DB.can_allocate(cc, id):
						DB.allocate(cc, id); plan.append(id); added = true; break
			if not added: return []
	plan.append(key)
	return plan

static func _try_asc(c: Dictionary, path: String) -> void:
	if c["ascendancy"] != "": return
	var a := DB.get_asc(path)
	if not a.is_empty() and DB.asc_block_reason(c, a) == "": c["ascendancy"] = path
