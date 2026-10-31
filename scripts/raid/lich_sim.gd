extends RaidSim
class_name LichSim
## v0.9.5: Некрополь Пепельной Короны — Кел'Таар, Король-Лич. Своя раскладка (RaidDefs.L_*): двери по разделам,
## ауры трэша (Костяной щит, похищение маны, гнилостные облака, замедление), три мини-босса и 4 фазы лича.
## Новые события клиенту: mana (похищение маны), slow (замедление), frz/unfrz (ледяная гробница),
## gz (стойкие растущие зоны), поле status.doors и status.mc (каст мини-босса).

var doors := [true, true, true]   # 0..2 закрыты; 3-я — решётка тронного зала (gate_open базового класса)
var gzs: Array = []               # стойкие зоны: {id, pos, r, rm, g, left, f, what}
var minis := {}                   # kind -> eid
var _gz_t := 0.0
var _pit_t := 0.0
var _warn_t := {}

const MINI_K := {"rm_keeper": 60.0, "rm_sister": 55.0, "rm_colossus": 85.0}   # здоровье: dps(ур.) · K · party_k
const KEEPER_TURN := 1.25         # рад/с — Хранитель разворачивается медленно, щит держит перед собой
const FROZEN_DUR := 14.0

func _spawn_trash() -> void:
	for pi in RaidDefs.L_PACKS.size():
		var c: Vector3 = RaidDefs.L_PACKS[pi]
		var kinds: Array = RaidDefs.L_TRASH[pi]
		for i in kinds.size():
			var a := TAU * i / kinds.size()
			var e := _new_enemy(kinds[i], c + Vector3(cos(a) * 2.8, 0, sin(a) * 2.2), RaidDefs.trash_hp(level, n), "trash", pi)
			_aura_init(e)
		if pi == RaidDefs.L_PACKS.size() - 1:
			var el := _new_enemy("rl_legion", c + Vector3(0, 0, 3.5), RaidDefs.trash_hp(level, n, true), "trash", pi)
			el.frac = 0.06; el.elite = true
	for k in [["rm_keeper", RaidDefs.L_KEEPER], ["rm_sister", RaidDefs.L_SISTER], ["rm_colossus", RaidDefs.L_COLOSSUS]]:
		var m := _new_enemy(k[0], k[1], RaidDefs.dps(level) * float(MINI_K[k[0]]) * RaidDefs.party_k(n), "mini", 10 + minis.size())
		m.yaw = PI; m.frac = 0.06; m.sec = RaidDefs.l_section(k[1]); m.t1 = 6.0; m.mc = {}; m.stun = 0.0
		minis[k[0]] = m.id

func _aura_init(e: Dictionary) -> void:
	e.t1 = randf_range(2.0, 4.0)

func _reset_mech() -> void:
	super._reset_mech()
	mech.merge({"a": 5.0, "b": 11.0, "c": 18.0, "d": 4.5, "e": 6.0, "f": 10.0, "g": 3.0}, true)

func _temp_roles() -> Array: return ["add", "naiad", "half", "phyl", "tomb"]
func _gate_ready() -> bool: return false   # решётку открывает смерть Колосса (_on_kill)

func status() -> Dictionary:
	var s := super.status()
	s["doors"] = doors.duplicate()
	var mc := {}
	for k in minis:
		var m = enemies.get(minis[k])
		if m != null and m.alive and not m.mc.is_empty(): mc = {"n": str(m.mc.name), "l": float(m.mc.left), "tt": float(m.mc.total), "id": int(m.id)}
	s["mc"] = mc
	return s

func _target(e: Dictionary):
	var tn = e.get("taunt")
	if tn != null and t < float(tn[1]) and players.has(int(tn[0])) and players[int(tn[0])].alive: return int(tn[0])
	var arena_only: bool = e.role in ["boss", "add"]
	var best = null; var bt := -1.0
	for pid in _alive_players(arena_only):
		if e.role == "mini" and RaidDefs.l_section(players[pid].pos) != int(e.sec) and U.flat_dist(players[pid].pos, e.home) > 16.0: continue   # у порога секции не сбрасываем
		var th := float(e.threat.get(pid, 0.0)) + 1.0 / (1.0 + U.flat_dist(players[pid].pos, e.pos))
		if th > bt: bt = th; best = pid
	return best

func _warn_once(key: String, s: String, every := 6.0) -> void:
	if t < float(_warn_t.get(key, -99.0)): return
	_warn_t[key] = t + every
	_warn(s)

# ---------------- урон по врагам ----------------
func _dmg_mult(e: Dictionary, pid: int) -> float:
	var k := 1.0
	if e.role == "trash" or e.role == "mini":   # Костяной щит: легионер рядом — −40% урона союзникам
		for id in enemies:
			var o = enemies[id]
			if o.alive and o.kind == "rl_legion" and o.id != e.id and o.aggro and U.flat_dist(o.pos, e.pos) < 8.0:
				k *= 0.6; break
	match e.kind:
		"rm_keeper":
			var fwd := Vector2(sin(e.yaw), cos(e.yaw))
			var to := Vector2(players[pid].pos.x - e.pos.x, players[pid].pos.z - e.pos.z)
			if to.length() > 0.1 and absf(rad_to_deg(fwd.angle_to(to))) < 75.0:
				k *= 0.1
				_warn_once("keeper%d" % pid, "Хранитель закрылся щитом — бейте в спину!", 8.0)
			else: mech["kb"] = float(mech.get("kb", 0.0)) + 1.0
		"rm_colossus":
			k *= 2.0 if float(e.stun) > 0.0 else 0.35
	return k

func _on_skill_hit(e: Dictionary, pid: int) -> void:
	if e.role == "mini" and not e.mc.is_empty() and e.mc.get("interrupt", false):
		_note("mini interrupt %s by %s" % [e.kind, players[pid].name])
		_warn("%s прерывает «%s»!" % [players[pid].name, e.mc.name])
		e.mc = {}; e.stun = 2.0
		_emit(0, status())

# ---------------- ИИ ----------------
func _pre_ai(e: Dictionary, dt: float) -> bool:
	match e.role:
		"mini": _mini_ai(e, dt); return true
		"phyl", "tomb":
			if e.role == "tomb" and t > float(e.until):
				_note("tomb lethal")
				_warn("Ледяная гробница поглотила %s" % players.get(int(e.victim), {"name": "?"}).name)
				_hurt(int(e.victim), 20.0, e.pos, true, "Ледяная гробница")
				_emit(0, {"t": "unfrz", "p": int(e.victim)})
				e.alive = false; _emit(0, {"t": "die", "id": e.id, "q": true})
			return true
		"trash":
			if e.aggro: _aura_tick(e, dt)
		"boss":
			if e.get("invuln", false) and phase == 2: return true   # связан с филактериями — стоит у трона и бьёт лучами
	return false

func _aura_tick(e: Dictionary, dt: float) -> void:
	e.t1 = float(e.get("t1", 1.0)) - dt
	if e.t1 > 0.0: return
	var tp = _target(e)
	if tp == null: return
	var pp: Vector3 = players[tp].pos
	match e.kind:
		"rl_ghost":
			e.t1 = 3.0
			if U.flat_dist(pp, e.pos) < 10.0:
				_emit(int(tp), {"t": "mana", "f": 0.1, "id": e.id})
		"rl_acolyte":
			e.t1 = 7.0
			_gz(pp, 2.8, 2.8, 0.0, 7.0, 0.06, "Гнилостное облако", "green")
		"rl_banshee":
			e.t1 = 4.0
			if U.flat_dist(pp, e.pos) < 11.0:
				_emit(int(tp), {"t": "slow", "k": 0.45, "dur": 2.5, "w": "Ледяной вопль"})
		_: e.t1 = 99.0

func _mini_ai(e: Dictionary, dt: float) -> void:
	var tp = _target(e)
	if not e.aggro:
		if tp != null and U.flat_dist(players[tp].pos, e.pos) < 12.0:
			e.aggro = true; e.t1 = 5.0
			_warn("%s вступает в бой!" % e.name)
			_note("mini engage %s" % e.kind)
			if e.kind == "rm_sister": _sister_raise(e, 3)
		return
	if tp == null:   # все ушли или погибли — мини-босс восстанавливается
		e.aggro = false; e.threat.clear(); e.hp = e.mhp; e.pos = e.home; e.mc = {}; e.stun = 0.0; e.yaw = PI
		for id in enemies.keys():
			var o = enemies[id]
			if o.role == "minion" and int(o.owner) == int(e.id):
				if o.alive: _emit(0, {"t": "die", "id": id, "q": true})
				enemies.erase(id)
		_note("mini reset %s" % e.kind)
		return
	if float(e.stun) > 0.0:
		e.stun = float(e.stun) - dt
		return
	# каст мини-босса
	if not e.mc.is_empty():
		e.mc.left = float(e.mc.left) - dt
		if e.kind == "rm_colossus" and e.mc.kind == "aim" and e.mc.left <= 0.0:
			_colossus_line(e); return
		if e.mc.left <= 0.0:
			var k: String = e.mc.kind
			e.mc = {}
			_mini_cast_done(e, k)
			_emit(0, status())
		return
	var pp: Vector3 = players[tp].pos
	var to: Vector3 = pp - e.pos
	var dist := to.length()
	var want := atan2(to.x, to.z)
	if e.kind == "rm_keeper":
		var dy := wrapf(want - float(e.yaw), -PI, PI)
		e.yaw = float(e.yaw) + clampf(dy, -KEEPER_TURN * dt, KEEPER_TURN * dt)
	elif dist > 0.05: e.yaw = want
	var facing := absf(wrapf(want - float(e.yaw), -PI, PI)) < deg_to_rad(55.0)
	var reach: float = float(e.range) + 0.9
	if e.kind == "rm_sister": reach = 10.0
	if dist > reach * 0.9 and (facing or e.kind != "rm_keeper"):
		var step: float = minf(dist - reach * 0.8, float(e.speed) * dt * (1.0 - _dbf(e, "slow")))
		var np := RaidDefs.clamp_pos(e.pos + to.normalized() * step, did)
		if RaidDefs.l_section(np) == int(e.sec): e.pos = np
	elif e.kind == "rm_sister" and dist < 5.0:
		var np2 := RaidDefs.clamp_pos(e.pos - to.normalized() * float(e.speed) * dt * 0.8, did)
		if RaidDefs.l_section(np2) == int(e.sec): e.pos = np2
	e.t1 = float(e.get("t1", 1.0)) - dt
	if e.t1 <= 0.0:
		match e.kind:
			"rm_keeper":
				e.t1 = 13.0
				e.mc = {"name": "Сотрясение склепа", "total": 2.2, "left": 2.2, "kind": "quake", "interrupt": false}
				_tele("disc", e.pos, 7.0, 2.2, 0.4, {"what": "Сотрясение склепа", "col": "orange"})
			"rm_sister":
				e.t1 = 15.0
				e.mc = {"name": "Воскрешение мёртвых", "total": 3.5, "left": 3.5, "kind": "raise", "interrupt": true}
				_tele("disc", e.pos, 3.0, 3.5, 0.0, {"what": "Воскрешение мёртвых", "col": "green"})
				_warn("Сестра Нежити читает «Воскрешение мёртвых» — прервите умением!")
			"rm_colossus":
				e.t1 = 12.0
				e.mc = {"name": "Сокрушительный рывок", "total": 2.6, "left": 2.6, "kind": "aim", "interrupt": false, "tp": tp}
				_tele("disc", pp, 1.6, 2.6, 0.0, {"follow": tp, "mode": "aim", "what": "Рывок Колосса", "col": "yellow"})
				_warn("Колосс выбрал цель — спрячьтесь за колонной!")
		_emit(0, status())
		return
	e.atk_t = float(e.atk_t) - dt
	if e.atk_t <= 0.0 and dist <= reach + 0.5 and (facing or e.kind != "rm_keeper"):
		e.atk_t = float(e.interval)
		_emit(0, {"t": "atk", "id": e.id, "p": tp, "rg": e.kind == "rm_sister"})
		_hurt(tp, float(e.frac) * (0.6 if e.kind == "rm_sister" else 1.0) * (1.0 - _dbf(e, "weaken")), e.pos, false, e.name)

func _mini_cast_done(e: Dictionary, k: String) -> void:
	match k:
		"quake": _note("keeper quake")
		"raise":
			_note("sister raise")
			_warn("Сестра Нежити подняла мёртвых!")
			var alive := 0
			for id in enemies:
				var o = enemies[id]
				if o.role == "minion" and int(o.owner) == int(e.id) and o.alive: alive += 1
			_sister_raise(e, maxi(2, 4 - alive))
			e.hp = minf(e.mhp, e.hp + e.mhp * 0.08)

func _sister_raise(e: Dictionary, cnt: int) -> void:
	for i in cnt:
		var a := randf() * TAU
		var m := _new_enemy("rl_skel", RaidDefs.clamp_pos(e.pos + Vector3(cos(a) * 3.0, 0, sin(a) * 3.0), did), RaidDefs.trash_hp(level, n) * 0.55, "minion")
		m.aggro = true; m.owner = e.id; m.frac = 0.025
		_spawn_pub(m)

## Конец прицеливания Колосса: линия к цели; если на пути колонна — линия до неё, Колосс врезается и оглушён
func _colossus_line(e: Dictionary) -> void:
	var tp = e.mc.get("tp")
	e.mc = {}
	if tp == null or not players.has(tp): return
	var dir := Vector2(players[tp].pos.x - e.pos.x, players[tp].pos.z - e.pos.z)
	if dir.length() < 0.1: dir = Vector2(0, 1)
	dir = dir.normalized()
	var length := 26.0; var hit_pillar := false
	for pl in RaidDefs.L_COL_PILLARS:
		var v := Vector2(pl.x - e.pos.x, pl.z - e.pos.z)
		var along := v.dot(dir)
		if along > 0.5 and along < length and absf(v.cross(dir)) < RaidDefs.L_COL_PILLAR_R + 1.1:
			length = along - RaidDefs.L_COL_PILLAR_R; hit_pillar = true
	var yaw := atan2(dir.x, dir.y)
	_tele("line", e.pos, length, 0.8, 0.5, {"yaw": yaw, "ang": 3.6, "what": "Сокрушительный рывок", "col": "red"})
	e.yaw = yaw
	e.pos = RaidDefs.clamp_pos(e.pos + Vector3(dir.x, 0, dir.y) * maxf(0.0, length - 1.0), did)
	if hit_pillar:
		e.stun = 6.5
		_note("colossus pillar")
		_warn("Колосс врезался в колонну! Оглушён — урон по нему удвоен")
	else:
		_note("colossus miss")
	_emit(0, status())

# ---------------- смерти и двери ----------------
func _on_kill(e: Dictionary) -> void:
	var def: Dictionary = DB.ENEMIES[e.kind]
	if e.role == "mini":
		var ids := players.keys(); var lv := []
		for pid in ids: lv.append(int(players[pid].lvl))
		var sh: Array = Xp.shares(float(def.xp), level, "elite", lv)
		for i in ids.size(): _emit(int(ids[i]), {"t": "xp", "v": maxi(1, int(round(sh[i])))})
		_note("mini dead %s t=%.1f" % [e.kind, t])
		_warn("%s повержен!" % e.name)
		for id in enemies:
			var o = enemies[id]
			if o.role == "minion" and int(o.owner) == int(e.id) and o.alive:
				o.alive = false; _emit(0, {"t": "die", "id": id, "q": true})
	if e.role == "tomb":
		_note("tomb freed")
		_emit(0, {"t": "unfrz", "p": int(e.victim)})
	if e.role == "phyl": _check_phyl()
	_update_doors()

func _alive_of(pred: Callable) -> int:
	var c := 0
	for id in enemies:
		if enemies[id].alive and pred.call(enemies[id]): c += 1
	return c

func _mini_alive(kind: String) -> bool:
	var m = enemies.get(minis.get(kind, -1))
	return m != null and m.alive

func _update_doors() -> void:
	var names := ["Врата склепа открылись", "Двери Часовни открылись", "Путь в Костяной зал открыт"]
	var ch := false
	if doors[0] and _alive_of(func(o): return o.role == "trash" and int(o.pack) < 2) == 0: doors[0] = false; ch = true; _warn(names[0]); _note("door0")
	if doors[1] and not _mini_alive("rm_keeper") and _alive_of(func(o): return o.role == "trash" and int(o.pack) == 2) == 0: doors[1] = false; ch = true; _warn(names[1]); _note("door1")
	if doors[2] and not _mini_alive("rm_sister"): doors[2] = false; ch = true; _warn(names[2]); _note("door2")
	if not gate_open and not doors[2] and not _mini_alive("rm_colossus"):
		gate_open = true; ch = true
		_warn("Решётка тронного зала поднялась. Кел'Таар ждёт…")
		_note("gate")
	if ch: _emit(0, status())

# ---------------- стойкие зоны ----------------
func _gz(pos: Vector3, r: float, rm: float, g: float, dur: float, f: float, what: String, col: String) -> void:
	var z := {"id": _next, "pos": pos, "r": r, "rm": rm, "g": g, "left": dur, "f": f, "what": what}
	_next += 1
	gzs.append(z)
	_emit(0, {"t": "gz", "id": z.id, "x": pos.x, "z": pos.z, "r": r, "rm": rm, "g": g, "dur": dur, "c": col, "w": what})

func tick(dt: float) -> void:
	super.tick(dt)
	for z in gzs.duplicate():
		z.left = float(z.left) - dt
		z.r = minf(float(z.rm), float(z.r) + float(z.g) * dt)
		if z.left <= 0.0: gzs.erase(z)
	_gz_t -= dt
	if _gz_t <= 0.0:
		_gz_t = 0.5
		for z in gzs:
			for pid in _alive_players():
				if U.flat_dist(players[pid].pos, z.pos) <= float(z.r): _hurt(pid, float(z.f) * 0.5, z.pos, false, z.what)
	_pit_t -= dt
	if _pit_t <= 0.0:
		_pit_t = 1.0
		for pid in _alive_players(true):
			for pit in RaidDefs.L_PITS:
				if U.flat_dist(players[pid].pos, pit) <= RaidDefs.L_PIT_R:
					_hurt(pid, 0.05, pit, false, "Ледяная яма")
					_emit(pid, {"t": "slow", "k": 0.5, "dur": 1.5, "w": "Ледяная яма"})
					break

# ---------------- Кел'Таар ----------------
func _boss_custom(b: Dictionary) -> void:
	var inside := _alive_players(true)
	if inside.is_empty(): return
	if mech.a <= 0.0:   # Ледяная стрела
		mech.a = 6.5 if phase < 4 else 5.0
		var tp: int = inside.pick_random()
		var dv := U.flat(players[tp].pos - b.pos)
		_tele("line", b.pos, 34.0, 1.8, 0.4, {"yaw": atan2(dv.x, dv.z), "ang": 3.0, "what": "Ледяная стрела", "col": "blue"})
		b.yaw = atan2(dv.x, dv.z)
		_note("arrow")
	if phase != 2 and mech.b <= 0.0:   # Ледяные зоны
		mech.b = 14.0
		for pid in inside: _tele("disc", players[pid].pos, 3.4, 2.4, 0.35, {"what": "Ледяная зона", "col": "blue"})
		for i in 3:
			var a := randf() * TAU; var r := sqrt(randf()) * (RaidDefs.L_ARENA_R - 3.0)
			_tele("disc", RaidDefs.L_ARENA_C + Vector3(cos(a) * r, 0, sin(a) * r), 3.4, 2.4, 0.35, {"what": "Ледяная зона", "col": "blue"})
		_note("ice zones")
	if phase == 1 and mech.c <= 0.0:   # волна скелетов
		mech.c = 34.0
		_warn("Кел'Таар поднимает мёртвых!")
		_note("wave")
		for i in 1 + n:
			var x := -8.0 if i % 2 == 0 else 8.0
			var e := _new_enemy("rl_skel", RaidDefs.L_THRONE + Vector3(x + randf_range(-1, 1), 0, -3.0), RaidDefs.trash_hp(level, n) * 0.6, "add")
			e.aggro = true; e.frac = 0.025
			_spawn_pub(e)
	if phase == 2 and b.get("invuln", false) and mech.d <= 0.0:   # Лучи некромантии
		mech.d = 4.5
		var tp2: int = inside.pick_random()
		var dv2 := U.flat(players[tp2].pos - b.pos)
		_tele("line", b.pos, 34.0, 1.5, 0.3, {"yaw": atan2(dv2.x, dv2.z), "ang": 2.6, "what": "Луч некромантии", "col": "green"})
	if phase >= 3:
		if mech.e <= 0.0:   # Ледяная гробница
			mech.e = 26.0
			_tomb(inside)
		if mech.f <= 0.0:   # Смерть и разложение
			mech.f = 17.0
			var tp3: int = inside.pick_random()
			_gz(players[tp3].pos, 2.4, 7.0, 0.15, 40.0, 0.07, "Смерть и разложение", "green")
			_warn("Смерть и разложение расползается по залу")
			_note("dnd")
	if phase == 4 and mech.g <= 0.0:   # Буря душ
		mech.g = 3.0
		for pid in inside: _hurt(pid, 0.025, b.pos, false, "Буря душ")
		for i in 3:
			var a := randf() * TAU; var r := sqrt(randf()) * (RaidDefs.L_ARENA_R - 2.0)
			_tele("disc", RaidDefs.L_ARENA_C + Vector3(cos(a) * r, 0, sin(a) * r), 3.0, 1.6, 0.3, {"what": "Буря душ", "col": "violet"})

func _tomb(inside: Array) -> void:
	var cand := []
	for pid in inside:
		var frozen := false
		for id in enemies:
			if enemies[id].alive and enemies[id].role == "tomb" and int(enemies[id].victim) == pid: frozen = true
		if not frozen: cand.append(pid)
	if cand.is_empty(): return
	var pid: int = cand.pick_random()
	var e := _new_enemy("rl_tomb", players[pid].pos, RaidDefs.dps(level) * 7.0 * (1.0 + 0.4 * (n - 1)), "tomb")
	e.aggro = true; e.victim = pid; e.until = t + FROZEN_DUR
	_spawn_pub(e)
	_emit(0, {"t": "frz", "p": pid, "id": e.id, "dur": FROZEN_DUR})
	_warn("Ледяная гробница сковала %s — разбейте лёд!" % players[pid].name)
	_note("tomb")

func _hp_custom(k: float) -> void:
	var b := _boss()
	if phase == 1 and k <= 0.70:
		phase = 2
		b.invuln = true; b.pos = RaidDefs.L_BOSS_HOME
		_warn("Кел'Таар связан с филактериями — разбейте все четыре!")
		_note("phase2 link")
		for i in 4:
			var e := _new_enemy("rl_phyl", RaidDefs.L_POINTS[i], RaidDefs.dps(level) * 11.0 * (1.0 + 0.6 * (n - 1)), "phyl")
			e.aggro = true
			_spawn_pub(e)
		mech.d = 3.0
	elif phase == 2 and not b.get("invuln", false) and k <= 0.40:
		phase = 3; mech.e = 4.0; mech.f = 8.0
		_warn("Кел'Таар: «Лёд станет вашей могилой!»")
		_note("phase3")
	elif phase == 3 and k <= 0.15:
		phase = 4; mech.g = 1.0
		_warn("Буря душ! Кел'Таар вытягивает души из зала")
		_note("phase4")

func _check_phyl() -> void:
	if _alive_of(func(o): return o.role == "phyl") > 0: return
	var b := _boss()
	b.invuln = false
	_warn("Филактерии разбиты — Кел'Таар уязвим!")
	_note("phyl broken")
	_emit(0, status())

func _wipe() -> void:
	for id in enemies:
		var e = enemies[id]
		if e.role == "tomb" and e.alive: _emit(0, {"t": "unfrz", "p": int(e.victim)})
	gzs.clear()
	_emit(0, {"t": "gzclr"})
	super._wipe()

func _boss_dead() -> void:
	gzs.clear()
	_emit(0, {"t": "gzclr"})
	for id in enemies:
		var e = enemies[id]
		if e.role == "tomb" and e.alive: _emit(0, {"t": "unfrz", "p": int(e.victim)})
	super._boss_dead()

func _extra_loot(list: Array, ilvl: int) -> void:
	var st := DB.lich_staff(ilvl)
	st.req = mini(int(st.req), level)
	list.append(["item", 1, st])
