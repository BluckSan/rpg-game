extends RefCounted
class_name RaidSim
## Авторитетная симуляция группового подземелья (v0.8.0). Работает на сервере (по экземпляру на группу)
## и локально в одиночной игре — одинаковый код, клиент лишь показывает результат.
## Враги, их здоровье, угроза, атаки, механики боссов и добыча считаются здесь; наружу уходят события
## (events: [pid или 0 — всем, словарь]) и снимки позиций/здоровья.

var did := ""
var d: Dictionary
var level := 1
var n := 1                      # размер группы при создании (масштаб здоровья)
var players := {}               # pid -> {name, cls, lvl, pos, hp, alive, threat_k, win_t, win_dmg, dealt}
var enemies := {}               # eid -> словарь врага
var events: Array = []
var boss_id := 0
var engaged := false
var eng_t := 0.0
var gate_open := false
var phase := 1
var cast := {}                  # {name, total, left, hint, interrupt, kind}
var mech := {}                  # таймеры механик
var tele: Array = []            # отложенные зоны урона
var enraged := false
var done := false
var shield_until := 0.0
var t := 0.0
var mlog: Array = []             # журнал для тестов: механики, прерывания, вайпы
var wipes := 0
var _next := 1
var _st_t := 0.0
var _empty_t := 0.0
var _enr_t := 0.0
var _half_dead_t := -1.0
var _boss_stun := 0.0
var _reset_until := 0.0          # после вайпа босс 12 с не вступает в бой — группа успевает собраться

const PHASES := {"ash": ["", "Пламя", "Пепел", "Пожар"], "crypt": ["", "Тишина", "Прилив", "Бездна"], "star": ["", "Свет", "Раскол", "Коллапс"]}

func setup(dungeon: String, lvl: int, party_n: int) -> void:
	did = dungeon; d = RaidDefs.DUNGEONS[dungeon]
	level = clampi(lvl, 1, 60); n = clampi(party_n, 1, 5)
	_spawn_trash()
	_spawn_boss()

# ---------------- игроки ----------------
func add_player(pid: int, info: Dictionary) -> void:
	players[pid] = {"name": str(info.get("name", "?")), "cls": str(info.get("cls", "warrior")), "lvl": int(info.get("lvl", 1)),
		"pos": RaidDefs.ENTRY, "hp": 1.0, "alive": true, "win_t": 0.0, "win_dmg": 0.0, "dealt": 0.0, "threat_k": 2.0 if str(info.get("cls", "")) == "warrior" else 1.0}
	var list := []
	for id in enemies:
		if enemies[id].alive and not enemies[id].get("hidden", false): list.append(_pub(enemies[id]))
	_emit(pid, {"t": "init", "did": did, "lvl": level, "n": n, "e": list, "gate": gate_closed(), "done": done})

func remove_player(pid: int) -> void:
	players.erase(pid)
	for id in enemies: enemies[id].threat.erase(pid)

func update_player(pid: int, pos: Vector3, hp: float) -> void:
	var p = players.get(pid)
	if p == null: return
	p.pos = Vector3(pos.x, 0, pos.z); p.hp = hp; p.alive = hp > 0.0

## Решётка: закрыта до зачистки коридора и во время боя (через 6 с после начала — успеть забежать всей группой)
func gate_closed() -> bool: return not gate_open or (engaged and eng_t > GATE_GRACE and not done)
const GATE_GRACE := 6.0

# ---------------- урон от игроков ----------------
## Удар игрока pid по врагу eid. skill — умение (прерывает касты). Возвращает принятый урон.
func hit(pid: int, eid: int, amount: float, skill: bool) -> float:
	var p = players.get(pid); var e = enemies.get(eid)
	if p == null or e == null or not e.alive or e.get("hidden", false) or not p.alive: return 0.0
	if not is_finite(amount) or amount <= 0.0: return 0.0
	if U.flat_dist(p.pos, e.pos) > 40.0: return 0.0           # слишком далеко — не засчитываем
	amount = minf(amount, RaidDefs.hit_cap(int(p.lvl)))
	if t - float(p.win_t) >= 1.0: p.win_t = t; p.win_dmg = 0.0
	var room := RaidDefs.sec_cap(int(p.lvl)) - float(p.win_dmg)
	if room <= 0.0: return 0.0
	amount = minf(amount, room)
	p.win_dmg = float(p.win_dmg) + amount
	if skill and eid == boss_id and cast.get("interrupt", false):
		_interrupt(pid)
	if e.get("invuln", false) or (eid == boss_id and t < shield_until): return 0.0
	amount *= 1.0 + _dbf(e, "mark")   # v0.9.0: метка поддержки (потолок Support.MARK_CAP)
	e.hp = maxf(0.0, float(e.hp) - amount)
	p.dealt = float(p.dealt) + amount
	e.threat[pid] = float(e.threat.get(pid, 0.0)) + amount * float(p.threat_k)
	if not e.aggro: _aggro_pack(e)
	if e.hp <= 0.0: _kill(e)
	elif eid == boss_id: _boss_hp_check()
	return amount

# ---------------- такт ----------------
func tick(dt: float) -> void:
	t += dt
	for id in enemies.keys():
		var e = enemies.get(id)
		if e != null and e.alive and not e.get("hidden", false): _enemy_ai(e, dt)
	_resolve_tele(dt)
	if not done: _boss_tick(dt)
	_st_t -= dt
	if _st_t <= 0.0:
		_st_t = 0.5
		_emit(0, status())

func status() -> Dictionary:
	var b = enemies.get(boss_id)
	var names: Array = PHASES[did]
	return {"t": "st", "ph": phase, "pn": names[clampi(phase, 0, 3)], "cn": cast.get("name", ""), "ct": float(cast.get("total", 0.0)),
		"cl": float(cast.get("left", 0.0)), "h": cast.get("hint", ""), "en": engaged, "el": maxf(0.0, float(d.enrage) - eng_t),
		"rg": enraged, "gate": gate_closed(), "inv": b != null and (b.get("invuln", false) or t < shield_until or b.get("hidden", false)), "done": done}

## Снимок: id и [x, z, поворот, здоровье] живых видимых врагов
func snapshot() -> Array:
	var ids := PackedInt32Array(); var data := PackedFloat32Array()
	for id in enemies:
		var e = enemies[id]
		if not e.alive or e.get("hidden", false): continue
		ids.append(id); data.append_array([e.pos.x, e.pos.z, e.yaw, e.hp])
	return [ids, data]

func _emit(pid: int, ev: Dictionary) -> void: events.append([pid, ev])
func _warn(s: String) -> void: _emit(0, {"t": "warn", "s": s})
func _note(s: String) -> void: mlog.append([snappedf(t, 0.1), s])

# ---------------- враги ----------------
func _new_enemy(kind: String, pos: Vector3, hp: float, role: String, pack := -1) -> Dictionary:
	var def: Dictionary = DB.ENEMIES[kind]
	var e := {"id": _next, "kind": kind, "name": str(def.name), "pos": pos, "home": pos, "yaw": PI, "hp": hp, "mhp": hp, "alive": true,
		"role": role, "pack": pack, "speed": float(def.speed), "range": maxf(1.8, float(def.range) * (0.8 if role != "boss" else 1.0)),
		"interval": float(def.interval), "atk_t": randf_range(0.5, 1.5), "ranged": float(def.range) > 5.0, "aggro": false, "threat": {},
		"frac": 0.035 if role == "boss" else (0.03 if role in ["trash", "add"] else 0.035), "boss": bool(def.boss)}
	_next += 1
	enemies[e.id] = e
	return e

func _pub(e: Dictionary) -> Dictionary:
	return {"id": e.id, "k": e.kind, "x": e.pos.x, "z": e.pos.z, "hp": e.hp, "mhp": e.mhp, "lvl": level, "r": e.role, "el": e.get("elite", false)}

func _spawn_pub(e: Dictionary) -> void: _emit(0, {"t": "spawn", "e": [_pub(e)]})

func _spawn_trash() -> void:
	var packs: Array = d.trash
	for pi in packs.size():
		var c: Vector3 = RaidDefs.PACKS[pi]
		var kinds: Array = packs[pi]
		for i in kinds.size():
			var a := TAU * i / kinds.size()
			_new_enemy(kinds[i], c + Vector3(cos(a) * 2.8, 0, sin(a) * 2.2), RaidDefs.trash_hp(level, n), "trash", pi)
		if pi == packs.size() - 1:
			var el := _new_enemy(d.elite, c + Vector3(0, 0, 3.5), RaidDefs.trash_hp(level, n, true), "trash", pi)
			el.frac = 0.06; el.elite = true

func _spawn_boss() -> void:
	var b := _new_enemy(d.boss, RaidDefs.ARENA_C + Vector3(0, 0, 6), RaidDefs.boss_hp(level, n) * float(d.get("hp_k", 1.0)), "boss")
	b.yaw = PI
	boss_id = b.id
	_reset_mech()

func _trash_left() -> int:
	var c := 0
	for id in enemies:
		if enemies[id].alive and enemies[id].role == "trash": c += 1
	return c

func _aggro_pack(e: Dictionary) -> void:
	e.aggro = true
	if e.role != "trash": return
	for id in enemies:
		var o = enemies[id]
		if o.alive and o.role == "trash" and o.pack == e.pack: o.aggro = true

func _alive_players(arena_only := false) -> Array:
	var out := []
	for pid in players:
		var p = players[pid]
		if p.alive and (not arena_only or RaidDefs.in_arena(p.pos)): out.append(pid)
	return out

func _target(e: Dictionary):
	var tn = e.get("taunt")   # v0.9.0: провокация — враг бьёт провокатора
	if tn != null and t < float(tn[1]) and players.has(int(tn[0])) and players[int(tn[0])].alive: return int(tn[0])
	var arena_only: bool = e.role != "trash"
	var best = null; var bt := -1.0
	for pid in _alive_players(arena_only):
		var th := float(e.threat.get(pid, 0.0)) + 1.0 / (1.0 + U.flat_dist(players[pid].pos, e.pos))
		if th > bt: bt = th; best = pid
	return best

func _enemy_ai(e: Dictionary, dt: float) -> void:
	var is_boss: bool = e.id == boss_id
	if e.role == "naiad":   # наяда стоит и лечит босса
		var b = enemies.get(boss_id)
		if b and b.alive and not b.get("hidden", false): b.hp = minf(b.mhp, b.hp + b.mhp * 0.001 * dt)
	if e.role == "trash" and not e.aggro:
		for pid in _alive_players():
			if U.flat_dist(players[pid].pos, e.pos) < 11.0: _aggro_pack(e); break
		if not e.aggro: return
	if e.role == "trash":   # поводок: группа сбрасывается, если рядом никого
		var near := false
		for pid in _alive_players():
			if U.flat_dist(players[pid].pos, e.pos) < 34.0: near = true
		if not near:
			e.aggro = false; e.threat.clear(); e.hp = e.mhp; e.pos = e.home
			return
	if is_boss and (not engaged or _boss_stun > 0.0 or (not cast.is_empty() and cast.get("root", true))): 
		if _boss_stun > 0.0: _boss_stun -= dt
		return
	var tp = _target(e)
	if tp == null: return
	var to: Vector3 = players[tp].pos - e.pos
	var dist := to.length()
	if dist > 0.05: e.yaw = atan2(to.x, to.z)
	var reach: float = float(e.range) + (1.6 if is_boss else 0.6)
	if dist > reach * 0.9 and e.role != "naiad":
		var step: float = minf(dist - reach * 0.8, float(e.speed) * dt * (1.0 - _dbf(e, "slow")))
		e.pos = RaidDefs.clamp_pos(e.pos + to.normalized() * step)
	e.atk_t = float(e.atk_t) - dt
	if e.atk_t <= 0.0 and dist <= reach + 0.5:
		e.atk_t = float(e.interval) * (0.6 if enraged and is_boss else 1.0)
		_emit(0, {"t": "atk", "id": e.id, "p": tp, "rg": e.ranged})
		_hurt(tp, float(e.frac) * (2.0 if enraged and is_boss else 1.0) * (1.0 - _dbf(e, "weaken")), e.pos, false, e.name)

func _hurt(pid: int, frac: float, src: Vector3, lethal := false, what := "") -> void:
	if not players.has(pid): return
	_emit(pid, {"t": "hurt", "f": frac, "x": src.x, "z": src.z, "l": lethal, "w": what})
	# сервер сразу учитывает смертельные механики (клиент подтвердит здоровье следующим состоянием)
	if lethal: players[pid].alive = false

func _kill(e: Dictionary) -> void:
	e.alive = false; e.hp = 0.0
	_emit(0, {"t": "die", "id": e.id})
	var def: Dictionary = DB.ENEMIES[e.kind]
	if e.role == "trash":
		_emit(0, {"t": "xp", "v": int(round(float(def.xp) * (1 + (level - 1) * 0.25) * (3.0 if e.get("elite", false) else 1.6)))})
		if _trash_left() == 0 and not gate_open:
			gate_open = true
			_warn("Решётка арены поднялась!")
			_note("gate")
	if e.role == "half": _on_half_dead(e)
	if e.role == "add" and did == "ash": _check_shield_adds()
	if e.id == boss_id: _boss_dead()

# ---------------- зоны урона (телеграфы) ----------------
## kind: disc | cone | ring | line | safe. opts: yaw, ang, inner, lethal, follow (pid), mode (normal|spread|stack), base, need, group
func _tele(kind: String, pos: Vector3, r: float, dur: float, frac: float, opts := {}) -> Dictionary:
	var z := {"id": _next, "k": kind, "pos": pos, "r": r, "left": dur, "dur": dur, "f": frac}
	_next += 1
	z.merge(opts)
	tele.append(z)
	var ev := {"t": "tele", "id": z.id, "k": kind, "x": pos.x, "z": pos.z, "r": r, "dur": dur, "yaw": float(opts.get("yaw", 0.0)),
		"ang": float(opts.get("ang", 90.0)), "in": float(opts.get("inner", 0.0)), "fo": int(opts.get("follow", 0)), "m": str(opts.get("mode", "")),
		"c": str(opts.get("col", "red"))}
	_emit(0, ev)
	return z

func _inside(z: Dictionary, p: Vector3) -> bool:
	var c: Vector3 = z.pos
	var dv := Vector2(p.x - c.x, p.z - c.z)
	var dist := dv.length()
	match z.k:
		"cone":
			if dist > z.r: return false
			var fwd := Vector2(sin(z.yaw), cos(z.yaw))
			return dist < 1.2 or absf(rad_to_deg(fwd.angle_to(dv))) <= float(z.ang) / 2.0
		"ring": return dist <= z.r and dist >= float(z.get("inner", 0.0))
		"line":
			var fwd := Vector2(sin(z.yaw), cos(z.yaw))
			var along := dv.dot(fwd)
			var side := absf(dv.cross(fwd))
			return along >= -1.0 and along <= z.r and side <= float(z.ang) / 2.0
		_: return dist <= z.r

func _resolve_tele(dt: float) -> void:
	var done_z := []
	for z in tele:
		if z.has("follow") and players.has(int(z.follow)): z.pos = players[int(z.follow)].pos
		z.left = float(z.left) - dt
		if z.left <= 0.0: done_z.append(z)
	if done_z.is_empty(): return
	# группы «безопасных» зон: кто вне всех зон группы — получает урон
	var safe_groups := {}
	for z in done_z:
		tele.erase(z)
		if z.k == "safe":
			if not safe_groups.has(z.group): safe_groups[z.group] = []
			safe_groups[z.group].append(z)
			continue
		var inside := []
		for pid in _alive_players():
			if _inside(z, players[pid].pos): inside.append(pid)
		var mode: String = z.get("mode", "")
		if mode == "stack":
			var need := mini(int(z.get("need", 1)), maxi(1, _alive_players(true).size()))
			var k := maxi(1, inside.size())
			var f: float = float(z.base) * float(need) / float(k)
			for pid in inside: _hurt(pid, f, z.pos, f >= 1.15, z.get("what", ""))
			_note("stack %d/%d" % [inside.size(), need])
			if inside.size() < need: _warn("Плиту приняли не все — урон удвоен!")
		else:
			for pid in inside: _hurt(pid, float(z.f), z.pos, bool(z.get("lethal", false)), z.get("what", ""))
	for g in safe_groups:
		var zs: Array = safe_groups[g]
		var ok := 0; var bad := 0
		for pid in _alive_players():
			var safe := false
			for z in zs:
				if _inside(z, players[pid].pos): safe = true
			if safe: ok += 1
			else:
				bad += 1
				_hurt(pid, float(zs[0].f), players[pid].pos, bool(zs[0].get("lethal", false)), zs[0].get("what", ""))
		_note("safe %s ok=%d bad=%d" % [g, ok, bad])

# ---------------- босс: общее ----------------
func _reset_mech() -> void:
	mech = {"a": 6.0, "b": 12.0, "c": 20.0, "d": 30.0, "e": 999.0, "tick": 1.0}
	phase = 1; cast = {}; enraged = false; shield_until = 0.0; _enr_t = 0.0; _half_dead_t = -1.0; _boss_stun = 0.0

func _boss() -> Dictionary: return enemies.get(boss_id, {})

func _start_cast(name: String, dur: float, hint: String, kind: String, interrupt := false, root := true) -> void:
	cast = {"name": name, "total": dur, "left": dur, "hint": hint, "kind": kind, "interrupt": interrupt, "root": root}
	_emit(0, status())

func _interrupt(pid: int) -> void:
	_note("interrupt by %s" % players[pid].name)
	_warn("%s прерывает «%s»!" % [players[pid].name, cast.name])
	cast = {}
	_boss_stun = 2.0
	_emit(0, status())

func _boss_tick(dt: float) -> void:
	var b := _boss()
	if b.is_empty() or not b.alive: return
	var inside := _alive_players(true)
	if not engaged:
		if gate_open and not inside.is_empty() and t >= _reset_until:
			engaged = true; eng_t = 0.0
			_reset_mech()
			_warn("%s: «Вы пришли умереть.» Решётка закроется через 6 с!" % b.name)
			_note("engage n=%d" % inside.size())
			_emit(0, status())
		return
	eng_t += dt
	# вайп: в арене не осталось живых — босс восстанавливается
	if inside.is_empty():
		_empty_t += dt
		if _empty_t > 3.0: _wipe()
		return
	_empty_t = 0.0
	if not enraged and eng_t >= float(d.enrage):
		enraged = true
		_warn("ЯРОСТЬ! %s больше не сдерживается" % b.name)
		_note("enrage")
	if enraged:
		_enr_t -= dt
		if _enr_t <= 0.0:
			_enr_t = 4.0
			_tele("disc", b.pos, 45.0, 1.5, 0.6, {"what": "Ярость", "col": "red"})
	if not cast.is_empty():
		cast.left = float(cast.left) - dt
		if cast.left <= 0.0:
			var k: String = cast.kind
			cast = {}
			_cast_done(k)
			_emit(0, status())
		return
	for k in mech: mech[k] = float(mech[k]) - dt
	if b.get("hidden", false):
		_star_halves_tick()
		return
	match did:
		"ash": _voragos(b)
		"crypt": _morwen(b)
		"star": _aeteron(b)

func _cast_done(k: String) -> void:
	var b := _boss()
	match k:
		"song":
			_note("song success")
			b.hp = minf(b.mhp, b.hp + b.mhp * 0.08)
			_warn("Песнь Бездны прозвучала: Морвен исцелилась, группа ранена")
			for pid in _alive_players(): _hurt(pid, 0.45, b.pos, false, "Песнь Бездны")
		"blast":
			var left := 0
			for id in enemies:
				if enemies[id].alive and enemies[id].role == "add": left += 1
			if left > 0:
				_note("shield blast wipe")
				_warn("Пепельный взрыв! Стражи не убиты вовремя")
				for pid in _alive_players(): _hurt(pid, 9.0, b.pos, true, "Пепельный взрыв")
		"nova":
			b.invuln = false
			_note("nova done")
		_: pass

func _boss_hp_check() -> void:
	var b := _boss()
	var k: float = b.hp / b.mhp
	match did:
		"ash":
			if phase == 1 and k <= 0.65: phase = 2; _ash_shield()
			elif phase == 2 and k <= 0.30: phase = 3; _ash_shield(); mech.e = 8.0
		"crypt":
			if phase == 1 and k <= 0.70: phase = 2; mech.d = 4.0; mech.e = 10.0; _warn("Вода прибывает…")
			elif phase == 2 and k <= 0.35: phase = 3; mech["w"] = 3.0; _warn("Морвен призывает Бездну")
		"star":
			if phase == 1 and k <= 0.70: phase = 2; _star_split()
			elif phase >= 2 and not mech.has("nova50") and k <= 0.50: mech["nova50"] = 1.0; phase = 3; _star_nova()
			elif mech.has("nova50") and not mech.has("nova20") and k <= 0.20: mech["nova20"] = 1.0; _star_nova()
	_emit(0, status())

func _wipe() -> void:
	wipes += 1
	_note("wipe")
	_warn("Группа пала. %s восстанавливает силы" % _boss().name)
	engaged = false; eng_t = 0.0; _empty_t = 0.0
	_reset_until = t + 12.0
	tele.clear()
	for id in enemies.keys():
		var e = enemies[id]
		if e.role in ["add", "naiad", "half"]:
			if e.alive: _emit(0, {"t": "die", "id": id, "q": true})
			enemies.erase(id)
	var b := _boss()
	b.hp = b.mhp; b.pos = RaidDefs.ARENA_C + Vector3(0, 0, 6); b.threat.clear(); b.invuln = false
	if b.get("hidden", false):
		b.hidden = false; _spawn_pub(b)
	_reset_mech()
	_emit(0, {"t": "wipe"})
	_emit(0, status())

func _boss_dead() -> void:
	done = true; cast = {}; tele.clear()
	_note("boss dead t=%.1f" % eng_t)
	for id in enemies:
		var e = enemies[id]
		if e.alive and e.role in ["add", "naiad", "half"]:
			e.alive = false; _emit(0, {"t": "die", "id": id, "q": true})
	_warn("%s повержен!" % _boss().name)
	_loot()
	_emit(0, status())

## v0.9.1: общая добыча на земле — без бросков: вся добыча падает у босса, кто первым подберёт, тому и достанется
## (онлайн подбор подтверждает сервер). Части комплекта: по одной на игрока (+1 за группу), классы — по составу
## группы; обычные предметы, золото, материалы ремесла (материал этого босса и Пыль Эфира). Опыт — каждому.
var drops: Array = []   # для тестов: последняя добыча
func _loot() -> void:
	var ilvl := level + 3
	var bxp := int(round(1800.0 * (1 + (level - 1) * 0.25)))
	var classes: Array = []
	for pid in players: classes.append(str(players[pid].cls))
	if classes.is_empty(): classes = ["warrior"]
	var n := players.size()
	var list: Array = []
	for i in n + 1:
		var it := Items.roll_set(ilvl, classes[i % classes.size()], d.set)
		Items._affixes(it, 1, 1.4); it.base = round(float(it.base) * 1.15)   # рейдовые части сильнее обычных
		it.req = mini(int(it.req), level)
		list.append(["item", 1, it])
	if randf() < 0.5:
		var it2 := Items.roll_set(ilvl, classes.pick_random(), d.set)
		Items._affixes(it2, 1, 1.4); it2.base = round(float(it2.base) * 1.15); it2.req = mini(int(it2.req), level)
		list.append(["item", 1, it2])
	for i in n:
		var ex := Items.roll(ilvl, classes[i % classes.size()], 0.8); ex.req = mini(int(ex.req), level)
		list.append(["item", 1, ex])
		list.append(["gold", int(round(randi_range(4, 6) * (1 + level * 0.5) * 30)), {}])
	var mat: String = Items.BOSS_MAT.get(str(d.boss), "aether_dust")
	for i in n + 1: list.append(["mat", 2 + level / 12, {"mat": mat}])
	for i in n: list.append(["mat", 2 + level / 10, {"mat": "aether_dust"}])
	var c: Vector3 = _boss().pos
	drops.clear()
	for k in list.size():
		var a := TAU * k / list.size() + randf() * 0.3
		var pos := c + Vector3(cos(a), 0, sin(a)) * randf_range(2.0, 4.5)
		drops.append({"id": k + 1, "t": list[k][0], "n": int(list[k][1]), "it": list[k][2], "x": pos.x, "z": pos.z})
	_emit(0, {"t": "drops", "list": drops})
	for pid in players: _emit(pid, {"t": "reward", "xp": bxp})
	_note("drops %d" % drops.size())

# ---------------- Ворагос, Пепельный Король ----------------
func _voragos(b: Dictionary) -> void:
	var inside := _alive_players(true)
	var tp = _target(b)
	if mech.a <= 0.0 and tp != null:      # рассечение конусом в сторону цели
		mech.a = 8.0 if phase < 3 else 6.5
		var to: Vector3 = players[tp].pos - b.pos
		b.yaw = atan2(to.x, to.z)
		_tele("cone", b.pos, 9.0, 1.7, 0.55, {"yaw": b.yaw, "ang": 120.0, "what": "Рассечение", "col": "orange"})
		_start_cast("Рассечение", 1.7, "Уйдите из конуса перед боссом", "cleave")
		return
	if mech.b <= 0.0:                     # метеоры: метка на каждом — разойдитесь
		mech.b = 22.0 if phase < 3 else 16.0
		for pid in inside: _tele("disc", players[pid].pos, 4.0, 5.0, 0.25, {"follow": pid, "mode": "spread", "what": "Метеор", "col": "orange"})
		_warn("Метеоры! Разойдитесь друг от друга")
		_note("meteors")
		return
	if phase >= 2 and mech.c <= 0.0 and not inside.is_empty():   # плита: соберитесь под меткой
		mech.c = 26.0
		var pid = inside.pick_random()
		_tele("disc", players[pid].pos, 3.6, 5.5, 0.0, {"follow": pid, "mode": "stack", "base": 0.4, "need": 3, "what": "Плита пепла", "col": "yellow"})
		_warn("Плита пепла на %s — встаньте вместе!" % players[pid].name)
		_note("slab")
		return
	if phase >= 3 and mech.e <= 0.0:      # огненное кольцо: держитесь ближе к боссу
		mech.e = 18.0
		_tele("ring", b.pos, RaidDefs.ARENA_R + 4.0, 3.2, 0.8, {"inner": 6.0, "what": "Огненное кольцо", "col": "red"})
		_start_cast("Огненное кольцо", 3.2, "Встаньте вплотную к боссу!", "ring")
		_note("ring")

func _ash_shield() -> void:
	var b := _boss()
	shield_until = t + 40.0
	var cnt := 1 + n
	var pts: Array = RaidDefs.POINTS.duplicate(); pts.shuffle()
	for i in cnt:
		var e := _new_enemy("ra_ashguard", pts[i % 4] + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)), RaidDefs.trash_hp(level, n, true) * 0.45, "add")
		e.aggro = true; e.frac = 0.05
		for pid in players: e.threat[pid] = randf()
		_spawn_pub(e)
	_start_cast("Пепельный щит", 40.0, "Убейте стражей до конца каста — иначе взрыв уничтожит группу", "blast", false, false)
	_warn("Ворагос неуязвим! Убейте пепельных стражей")
	_note("shield adds=%d" % cnt)
	b.invuln = true

func _check_shield_adds() -> void:
	for id in enemies:
		if enemies[id].alive and enemies[id].role == "add": return
	var b := _boss()
	b.invuln = false; shield_until = 0.0
	if cast.get("kind", "") == "blast": cast = {}
	_warn("Щит Ворагоса рухнул!")
	_note("shield broken")
	_emit(0, status())

# ---------------- Морвен, Утопленница ----------------
func _morwen(b: Dictionary) -> void:
	var inside := _alive_players(true)
	if mech.a <= 0.0:                     # Песнь Бездны — прерываемая
		mech.a = 22.0 if phase < 3 else 16.0
		_start_cast("Песнь Бездны", 4.0, "ПРЕРВИТЕ умением (не обычной атакой)!", "song", true)
		_note("song")
		return
	if mech.b <= 0.0:                     # капли: разойдитесь
		mech.b = 18.0
		for pid in inside: _tele("disc", players[pid].pos, 3.6, 5.0, 0.22, {"follow": pid, "mode": "spread", "what": "Слеза Бездны", "col": "blue"})
		_warn("Слёзы Бездны! Разойдитесь")
		_note("drops")
		return
	if phase >= 2 and mech.d <= 0.0:      # прилив: на островки
		mech.d = 30.0
		for i in 4: _tele("safe", RaidDefs.POINTS[i], RaidDefs.POINT_R, 6.0, 0.75, {"group": "tide%d" % int(t), "what": "Прилив", "col": "green"})
		_emit(0, {"t": "water", "dur": 6.0})
		_warn("Прилив! Бегите на каменные островки")
		_note("tide")
		return
	if phase >= 2 and mech.e <= 0.0:      # наяды-целительницы
		mech.e = 40.0
		var pts: Array = RaidDefs.POINTS.duplicate(); pts.shuffle()
		for i in (1 if n <= 1 else 2):   # соло — одна наяда
			var e := _new_enemy("ra_naiad", pts[i], RaidDefs.trash_hp(level, n) * (0.8 if n <= 1 else 1.2), "naiad")
			e.aggro = true; e.frac = 0.02
			_spawn_pub(e)
		_warn("Наяды исцеляют Морвен — убейте их!")
		_note("naiads")
		return
	if phase >= 3 and mech.has("w") and float(mech.w) <= 0.0:   # водоворот: тянет к центру
		mech.w = 25.0
		_emit(0, {"t": "pull", "x": b.pos.x, "z": b.pos.z, "s": 3.2, "dur": 7.0})
		for i in 7: _tele("disc", b.pos, 5.0, 1.0 + i, 0.18, {"what": "Водоворот", "col": "blue"})
		_warn("Водоворот! Бегите от центра")
		_note("whirlpool")

# ---------------- Аэтерон, Страж Звезды ----------------
func _aeteron(b: Dictionary) -> void:
	var inside := _alive_players(true)
	if inside.is_empty(): return
	if mech.a <= 0.0:                     # лучи на случайных игроков
		mech.a = 8.0 if phase < 3 else 6.0
		var targets: Array = inside.duplicate(); targets.shuffle()
		for i in mini(1 if phase == 1 else 2, targets.size()):
			var to: Vector3 = players[targets[i]].pos - b.pos
			_tele("line", b.pos, 34.0, 1.9, 0.45, {"yaw": atan2(to.x, to.z), "ang": 3.6, "what": "Луч звезды", "col": "violet"})
		_start_cast("Луч звезды", 1.9, "Сойдите с линии луча", "beam")
		_note("beam")
		return
	if mech.b <= 0.0:                     # звездопад
		mech.b = 20.0
		for i in 6 + 2 * n:
			var a := randf() * TAU; var r := sqrt(randf()) * (RaidDefs.ARENA_R - 2.0)
			_tele("disc", RaidDefs.ARENA_C + Vector3(cos(a) * r, 0, sin(a) * r), 3.0, 2.4 + randf() * 1.2, 0.35, {"what": "Звездопад", "col": "violet"})
		for pid in inside: _tele("disc", players[pid].pos, 3.0, 2.6, 0.35, {"what": "Звездопад", "col": "violet"})
		_warn("Звездопад!")
		_note("starfall")
		return
	if phase >= 2 and mech.c <= 0.0:      # гравитация: соберитесь
		mech.c = 26.0
		var pid = inside.pick_random()
		_tele("disc", players[pid].pos, 3.6, 5.5, 0.0, {"follow": pid, "mode": "stack", "base": 0.4, "need": 3, "what": "Гравитация", "col": "yellow"})
		_warn("Гравитация на %s — соберитесь!" % players[pid].name)
		_note("gravity")

func _star_split() -> void:
	var b := _boss()
	b.hidden = true
	_emit(0, {"t": "die", "id": b.id, "q": true, "hide": true})
	cast = {}
	for s in [-1, 1]:
		var e := _new_enemy("rb_aeteron_l" if s < 0 else "rb_aeteron_r", b.pos + Vector3(6 * s, 0, 0), b.mhp * 0.11, "half")
		e.aggro = true; e.frac = 0.04
		for pid in players: e.threat[pid] = float(b.threat.get(pid, 0.0))
		_spawn_pub(e)
	_half_dead_t = -1.0
	_warn("Аэтерон раскололся! Убейте обе половины с разницей не больше 10 с")
	_note("split")

func _on_half_dead(e: Dictionary) -> void:
	var other = null
	for id in enemies:
		if enemies[id].role == "half" and id != e.id: other = enemies[id]
	if other == null: return
	if other.alive:
		_half_dead_t = t
		e.dead_at = t
		_warn("Половина пала — у вас 10 секунд на вторую!")
		return
	# обе мертвы — Аэтерон снова целый
	var b := _boss()
	b.hidden = false
	b.hp = maxf(b.mhp * 0.52, b.hp - b.mhp * 0.1)
	b.pos = RaidDefs.ARENA_C
	_spawn_pub(b)
	_half_dead_t = -1.0
	for id in enemies.keys():
		if enemies[id].role == "half": enemies.erase(id)
	_warn("Аэтерон собран заново")
	_note("split done")
	_emit(0, status())

func _star_halves_tick() -> void:
	if _half_dead_t < 0.0 or t - _half_dead_t < 10.0: return
	for id in enemies:
		var e = enemies[id]
		if e.role == "half" and not e.alive:
			e.alive = true; e.hp = e.mhp * 0.6
			_spawn_pub(e)
	_half_dead_t = -1.0
	_warn("Половина возродилась — убивайте их одновременно!")
	_note("half revived")

func _star_nova() -> void:
	var b := _boss()
	b.invuln = true
	var pt: Vector3 = RaidDefs.POINTS.pick_random()
	_tele("safe", pt, 4.2, 8.0, 9.0, {"group": "nova%d" % int(t), "lethal": true, "what": "Сверхновая", "col": "green"})
	_start_cast("Сверхновая", 8.0, "Все в щит обелиска (зелёный круг)!", "nova", false)
	_warn("СВЕРХНОВАЯ! Встаньте в щит обелиска")
	_note("nova")


# ---------------- v0.9.0: поддержка — ослабления врагов и провокация (решает сервер) ----------------
var support_log := {"mark": 0, "weaken": 0, "slow": 0, "taunt": 0}   # для тестов
var mark_bonus_dealt := 0.0

func _dbf(e: Dictionary, k: String) -> float:
	var d = e.get("dbf", {}).get(k)
	if d == null or t >= float(d[1]): return 0.0
	return float(d[0])

## eff — Support.resolve(умение); eid — выбранный враг (0 — по области center/radius)
func apply_support(pid: int, eff: Dictionary, eid: int, center: Vector3) -> int:
	if not players.has(pid) or not players[pid].alive: return 0
	var list: Array = []
	var tgt := str(eff.get("tgt", ""))
	if tgt == "enemy":
		var e = enemies.get(eid)
		if e == null:   # без выбранной цели — ближайший к точке
			var bd := 6.0
			for id in enemies:
				var o = enemies[id]
				if o.alive and not o.get("hidden", false) and U.flat_dist(o.pos, center) < bd: bd = U.flat_dist(o.pos, center); e = o
		if e != null: list.append(e)
	else:
		var c: Vector3 = players[pid].pos if tgt == "self_area" else Vector3(center.x, 0, center.z)
		if U.flat_dist(c, players[pid].pos) > 30.0: return 0
		for id in enemies:
			var o = enemies[id]
			if o.alive and not o.get("hidden", false) and U.flat_dist(o.pos, c) < float(eff.get("radius", 4.0)) + 1.0: list.append(o)
	for e in list:
		if U.flat_dist(e.pos, players[pid].pos) > 34.0: continue
		if not e.has("dbf"): e.dbf = {}
		if eff.has("debuff"):
			var d: Dictionary = eff.debuff
			var cur = e.dbf.get(d.kind)
			var v: float = maxf(float(d.v), float(cur[0]) if cur != null and t < float(cur[1]) else 0.0)
			e.dbf[d.kind] = [v, t + float(d.dur), float(d.dur)]
			support_log[d.kind] = int(support_log[d.kind]) + 1
		if eff.has("taunt"):
			e.taunt = [pid, t + float(eff.taunt)]
			e.dbf["taunt"] = [1.0, t + float(eff.taunt), float(eff.taunt)]
			e.aggro = true
			support_log.taunt = int(support_log.taunt) + 1
		_emit(0, {"t": "dbf", "id": e.id, "l": _dbf_pub(e)})
	return list.size()

func _dbf_pub(e: Dictionary) -> Dictionary:
	var out := {}
	for k in e.get("dbf", {}):
		var d: Array = e.dbf[k]
		if t < float(d[1]): out[k] = [float(d[0]), float(d[1]) - t, float(d[2])]
	return out
