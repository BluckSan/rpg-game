extends RefCounted
class_name RaidBot
## Тестовый «игрок» группового подземелья: читает метки механик так же, как их видит человек
## (RaidClient.teles), уходит из зон, расходится/собирается, бежит в безопасные зоны, бьёт по приоритетам
## (помощники → половины → босс), прерывает касты умением, пьёт зелья. Управляет героем через force_move.

var zone
var p: Player
var others: Callable     # () -> Array[Vector3] позиции союзников
var my_pid := 1
var ranged := false
var stuck_t := 0.0
var last_pos := Vector3.ZERO
var mech_moves := 0
var interrupts_tried := 0

func _init(z, pid: int, others_cb: Callable) -> void:
	zone = z; p = z.player; my_pid = pid; others = others_cb
	ranged = str(p.data["class"]) != "warrior"

func _teles() -> Array:
	var out := []
	if zone.raid == null: return out
	for id in zone.raid.teles:
		var t: Dictionary = zone.raid.teles[id]
		if not is_instance_valid(t.node): continue
		var c: Vector3 = t.node.global_position
		out.append({"k": t.k, "c": Vector3(c.x, 0, c.z), "r": t.r, "in": t["in"], "ang": t.ang, "yaw": t.yaw, "m": t.m, "fo": t.fo, "left": t.left})
	return out

func _boss():
	for e in zone.enemies:
		if is_instance_valid(e) and e.alive and e.def.boss: return e
	return null

func _pick_target():
	var best = null; var bs := -INF
	for e in zone.enemies:
		if not is_instance_valid(e) or not e.alive: continue
		var s := -U.flat_dist(e.global_position, p.global_position) * 0.2
		if e is NetEnemy:
			match e.role:
				"add", "naiad": s += 100.0
				"half": s += 80.0 + e.hp / maxf(1.0, e.max_hp) * 50.0   # бьём ту, у которой больше здоровья — умирают вместе
				"trash": s += 60.0
				"boss": s += 10.0 - (200.0 if e.brain and e.brain.invulnerable else 0.0)
		if s > bs: bs = s; best = e
	return best

## Один шаг (каждый физический кадр). Возвращает направление движения
func step(dt: float) -> void:
	if p.dead: p.force_move = Vector3.ZERO; return
	var me := U.flat(p.global_position)
	var mv := Vector3.ZERO
	var urgent := false
	var ts := _teles()
	var allies: Array = others.call()
	# 1) безопасные зоны (прилив, Сверхновая): бежим в ближайшую
	var safe_best = null; var sd := INF
	for t in ts:
		if t.k == "safe":
			var d := U.flat_dist(me, t.c)
			if d < sd: sd = d; safe_best = t
	if safe_best != null:
		if sd > safe_best.r * 0.55: mv = U.flat(safe_best.c - me).normalized(); urgent = true
		else: mv = Vector3.ZERO; urgent = true
	if not urgent:
		for t in ts:
			var to_c: Vector3 = U.flat(t.c - me); var d: float = to_c.length()
			match t.k:
				"ring":
					if d > t["in"] - 1.5: mv += to_c.normalized() * 2.0; urgent = true
				"cone":
					var fwd := Vector3(sin(t.yaw), 0, cos(t.yaw))
					var rel: Vector3 = me - t.c
					if rel.length() < t.r + 1.0 and (rel.length() < 1.5 or rad_to_deg(fwd.angle_to(rel.normalized())) < t.ang / 2.0 + 12.0):
						var side := fwd.cross(Vector3.UP).normalized()
						mv += (side if rel.dot(side) >= 0 else -side) * 1.5 - fwd * 0.6; urgent = true
				"line":
					var fwd := Vector3(sin(t.yaw), 0, cos(t.yaw))
					var rel: Vector3 = me - t.c
					var along: float = rel.dot(fwd)
					var side := fwd.cross(Vector3.UP).normalized()
					var off: float = rel.dot(side)
					if along > -1.5 and along < t.r and absf(off) < t.ang / 2.0 + 1.6:
						mv += (side if off >= 0 else -side) * 2.0; urgent = true
				_:
					if t.m == "stack":
						if t.fo != my_pid:
							if d > t.r * 0.5: mv += to_c.normalized() * 2.0; urgent = true
						else:
							urgent = true   # стоим — к нам бегут
					elif t.m == "spread":   # метки на всех — расходимся от любого союзника
						for a in allies:
							var ad := U.flat_dist(a, me)
							if ad < t.r * 2.0 + 1.0: mv += U.flat(me - a).normalized() * 1.5; urgent = true
					elif d < t.r + 1.0 and t.fo != my_pid:
						mv += (-to_c.normalized() if d > 0.1 else Vector3.RIGHT) * 1.5; urgent = true
	if urgent: mech_moves += 1
	# 2) цель и атака
	var tgt = _pick_target()
	var b0 = _boss()
	if b0 != null and b0.brain and b0.brain.cast_name == "Песнь Бездны": tgt = b0   # все — к боссу, прервать песнь
	var bb = _boss()
	if not urgent and bb != null and not RaidDefs.in_arena(me) and zone.builder.gate_open() and zone.builder.packs_left() == 0:
		mv = U.flat(RaidDefs.ARENA_C - me).normalized()   # решётка открыта — все на арену, пока не закрылась
	elif tgt and not urgent:
		var dist := U.flat_dist(tgt.global_position, me)
		var want: float = (8.0 if ranged else 2.2 + tgt.radius)
		if dist > want: mv = U.flat(tgt.global_position - me).normalized()
		elif ranged and dist < 4.0: mv = U.flat(me - tgt.global_position).normalized() * 0.6
	if tgt:
		p.face_towards(tgt.global_position)
		var dist := U.flat_dist(tgt.global_position, me)
		if dist < (14.0 if ranged else 3.5 + tgt.radius):
			var b = _boss()
			var song: bool = b != null and b.brain and b.brain.cast_name == "Песнь Бездны"
			if song and tgt != b:
				p.face_towards(b.global_position)
				tgt = b
			# в Склепе умение 2 бережём для прерывания Песни Бездны (как сделал бы игрок)
			var keep: bool = zone.raid != null and zone.raid.did == "crypt"
			if song:
				for s in [2, 1]:
					if p.try_use(s): interrupts_tried += 1; break
			elif randf() < 0.5:
				for s in ([1] if keep else [1, 2]):
					if p.try_use(s): break
			p.try_use(0)
	# 3) зелье
	if p.hp < p.stats.max_hp * 0.4: p.use_potion()
	# застревание у стен — прыжок
	stuck_t += dt
	if stuck_t > 1.0:
		if mv != Vector3.ZERO and U.flat_dist(last_pos, p.global_position) < 0.3: p.request_jump()
		last_pos = p.global_position; stuck_t = 0.0
	if me.z < 2.5 and mv.z < 0.0: mv.z = 0.0   # не уходить в портал выхода
	p.force_move = mv.normalized() if mv.length() > 0.05 else Vector3.ZERO
