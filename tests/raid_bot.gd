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
var lich := false
var hides := 0
var behind_frames := 0

func _init(z, pid: int, others_cb: Callable) -> void:
	zone = z; p = z.player; my_pid = pid; others = others_cb
	ranged = str(p.data["class"]) != "warrior"
	lich = z.raid != null and z.raid.did == "lich"

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
	var reach := _reach()
	for e in zone.enemies:
		if not is_instance_valid(e) or not e.alive: continue
		if lich and RaidDefs.l_section(e.global_position) > reach: continue
		var s := -U.flat_dist(e.global_position, p.global_position) * 0.2
		if e is NetEnemy:
			match e.role:
				"add", "naiad": s += 100.0
				"half": s += 80.0 + e.hp / maxf(1.0, e.max_hp) * 50.0   # бьём ту, у которой больше здоровья — умирают вместе
				"trash": s += 60.0
				"tomb": s += 150.0
				"phyl": s += 90.0
				"mini": s += 55.0
				"minion": s += 95.0
				"boss": s += 10.0 - (200.0 if e.brain and e.brain.invulnerable else 0.0)
		if s > bs: bs = s; best = e
	return best

## Некрополь: самая дальняя секция, куда можно пройти (двери закрываются до зачистки)
func _reach() -> int:
	if not lich: return 99
	if RaidDefs.in_arena(p.global_position, "lich"): return 5   # решётка закрылась за спиной — мы уже в зале
	var b = zone.builder
	if b.ldoor_closed[0]: return 0
	if b.ldoor_closed[1]: return 2
	if b.ldoor_closed[2]: return 3
	if b.gate_is_closed: return 4
	return 5

## Укрытие от рывка Колосса: точка за ближайшей колонной (колонна между героем и Колоссом)
func _hide_spot(me: Vector3):
	var col = null
	for e in zone.enemies:
		if is_instance_valid(e) and e.alive and e.kind == "rm_colossus": col = e
	if col == null: return null
	var best = null; var bd := INF
	for pl in RaidDefs.L_COL_PILLARS:
		var away: Vector3 = U.flat(pl - col.global_position).normalized()
		var spot: Vector3 = pl + away * (RaidDefs.L_COL_PILLAR_R + 1.0)
		var d := U.flat_dist(spot, me)
		if d < bd: bd = d; best = spot
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
	if lich and not urgent:
		var mc: Dictionary = zone.raid.mc
		if str(mc.get("n", "")) == "Сокрушительный рывок":
			var hs = _hide_spot(me)
			if hs != null:
				var to: Vector3 = U.flat(hs - me)
				mv = to.normalized() if to.length() > 0.5 else Vector3.ZERO
				urgent = true; hides += 1
		for id in zone.raid.gzs:   # облака гнили, «Смерть и разложение»
			var g: Dictionary = zone.raid.gzs[id]
			if not is_instance_valid(g.node): continue
			var gc := U.flat(g.node.global_position); var gr: float = g.node.scale.x
			if float(g.dur) <= 10.0 and p.hp > p.stats.max_hp * 0.5: continue   # мелкое облако гнили: терпим, иначе кайт без конца
			if U.flat_dist(gc, me) < gr + 0.8: mv += U.flat(me - gc).normalized() * 1.5; urgent = true
		for pit in RaidDefs.L_PITS:
			if U.flat_dist(pit, me) < RaidDefs.L_PIT_R + 0.8: mv += U.flat(me - pit).normalized() * 1.2; urgent = true
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
					elif t.m == "aim": pass
					elif d < t.r + 1.0 and t.fo != my_pid:
						mv += (-to_c.normalized() if d > 0.1 else Vector3.RIGHT) * 1.5; urgent = true
	if urgent: mech_moves += 1
	# 2) цель и атака
	var tgt = _pick_target()
	var b0 = _boss()
	if b0 != null and b0.brain and b0.brain.cast_name == "Песнь Бездны": tgt = b0   # все — к боссу, прервать песнь
	var bb = _boss()
	var sis_cast: bool = lich and str(zone.raid.mc.get("n", "")) == "Воскрешение мёртвых"
	if sis_cast:
		for e in zone.enemies:
			if is_instance_valid(e) and e.alive and e.kind == "rm_sister": tgt = e
	if lich and not urgent and tgt == null:
		var gt: Vector3 = zone.builder.guide_target()
		if U.flat_dist(gt, me) > 3.0: mv = U.flat(gt - me).normalized()
	elif lich and not urgent and tgt != null and tgt.kind == "rm_keeper":
		# Хранитель режет урон спереди — заходим за спину
		var fwd := Vector3(sin(tgt.rotation.y), 0, cos(tgt.rotation.y))
		var spot: Vector3 = U.flat(tgt.global_position) - fwd * (6.0 if ranged else 2.0 + tgt.radius)
		var to: Vector3 = U.flat(spot - me)
		if to.length() > 0.7:
			var rel: Vector3 = U.flat(me - tgt.global_position)
			# огибаем сбоку, а не идём сквозь него
			if rel.normalized().dot(fwd) > -0.2 and rel.length() < 5.0: to += fwd.cross(Vector3.UP).normalized() * (1.0 if rel.dot(fwd.cross(Vector3.UP)) >= 0 else -1.0) * 2.0
			mv = to.normalized()
		else: behind_frames += 1
	elif not lich and not urgent and bb != null and not RaidDefs.in_arena(me) and zone.builder.gate_open() and zone.builder.packs_left() == 0:
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
			var keep: bool = zone.raid != null and (zone.raid.did == "crypt" or (zone.raid.did == "lich" and RaidDefs.l_section(me) == 3))
			if sis_cast and tgt.kind == "rm_sister":
				for s in [2, 1]:
					if p.try_use(s): interrupts_tried += 1; break
			elif song:
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
