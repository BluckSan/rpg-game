extends RefCounted
class_name WorldSim
## v0.9.2: серверная симуляция врагов зоны (долина, открытый мир, экземпляр Склепа на группу).
## Клиенты только рисуют (интерполяция) и шлют удары/контроль; ИИ, угроза, путь по навмешу, преследование,
## поводок, атаки и умения врагов, механики боссов (метки на земле), урон по героям и возрождение — здесь.
## Шаг фиксированный — 20 Гц (Net._server_tick). Логова без игроков рядом «спят» (не считаются).

const TICK := 0.05
const WAKE_R := 110.0          # логово считается, только если игрок ближе
const AOI_R := 90.0            # позиции врагов — только игрокам ближе этого
const LEASH := 28.0
const LEASH_BOSS := 22.0
static var _next_nid := 1000001
static var _next_tele := 1

var zk := ""
var zone_id := ""
var nav: ServerNav
var spawners := {}     # key -> sp {key, def..., mobs: [nid], subs: {peer: true}}
var mobs := {}         # nid -> m
var players := {}      # peer -> {pos, hp, alive, lvl, cls, threat_k, max_hp}
var events: Array = [] # [peer (0 — всем рядом), ev, pos]
var tele: Array = []   # зоны урона
var sched: Array = []  # отложенные действия [t, Callable]
var t := 0.0
var stats := {"ticks": 0, "awake": 0, "ai_ms": 0.0, "paths": 0, "hurt": 0, "atk": 0, "tele": 0, "kills": 0}
var lv_off := 0                # v0.9.2: сдвиг уровня врагов (Склеп — по уровню группы)
var kills_cb: Callable        # (sp, m) — добыча/награды (Net)

func _init(key: String, zid: String, n: ServerNav) -> void:
	zk = key; zone_id = zid; nav = n

# ---------------- логова и враги ----------------
func ensure_spawner(key: String):
	if spawners.has(key): return spawners[key]
	var d = nav.spawners.get(key)
	if d == null: return null
	var sp: Dictionary = d.duplicate(true)
	sp["subs"] = {}; sp["mobs"] = []; sp["cleared"] = false
	spawners[key] = sp
	for i in int(sp.n): sp.mobs.append(_new_mob(sp, i).nid)
	return sp

func _new_mob(sp: Dictionary, slot: int, kind := "", lvl := -1, pos := Vector3.INF, add_of := 0) -> Dictionary:
	if kind == "": kind = str(sp.kind)
	var def: Dictionary = DB.ENEMIES[kind]
	if lvl < 0: lvl = maxi(1, randi_range(int(sp.lo), int(sp.hi)) + lv_off)
	if pos == Vector3.INF:
		var r := Vector2.from_angle(randf() * TAU) * randf() * float(sp.r)
		pos = nav.snap(sp.key, sp.pos + Vector3(r.x, 0, r.y))
	var rank := str(sp.rank) if add_of == 0 else "normal"
	if rank == "normal" and add_of == 0 and randf() < float(sp.elite): rank = "elite"
	var aff: Array = []
	if rank in ["elite", "rare"]:
		var pool: Array = Enemy.AFFIXES.keys(); pool.shuffle()
		aff = pool.slice(0, 1 if rank == "elite" else 2)
	var hp_k: float = {"elite": 2.0, "rare": 3.5}.get(rank, 1.0)
	if def.boss and kind != "warden" and not def.get("raid", false) and add_of == 0: hp_k *= WORLD_BOSS_HP_K   # v0.9.4: боссы локаций заметно крепче
	var mhp: float = float(def.hp) * Combat.enemy_hp_mult(lvl) * hp_k
	var m := {"nid": _next_nid, "sp": sp.key, "slot": slot, "kind": kind, "def": def, "lvl": lvl, "rank": rank, "name": str(sp.rname) if add_of == 0 else "",
		"aff": aff, "pos": Vector3(pos.x, 0, pos.z), "home": Vector3(pos.x, 0, pos.z), "yaw": randf() * TAU, "hp": mhp, "mhp": mhp, "alive": true,
		"respawn_at": 0.0, "parts": {}, "killer": 0, "last_hit": 0.0, "threat": {}, "aggro": false, "ret": false, "atk_t": 0.0,
		"busy": 0.0, "stun": 0.0, "slow": 1.0, "slow_t": 0.0, "taunt": [0, 0.0], "cd": randf_range(1.0, 3.0), "wander": randf_range(1.0, 5.0),
		"wto": Vector3(pos.x, 0, pos.z), "path": PackedVector3Array(), "pi": 0, "pgoal": Vector3.INF, "pt": 0.0,
		"ai": str(def.get("ai", "ranged" if def.ranged else "melee")), "spd": 1.3 if aff.has("fast") else 1.0,
		"dmgk": {"elite": 1.3, "rare": 1.5}.get(rank, 1.0), "add_of": add_of, "dash": {}, "summoned": false, "aura_t": 1.0, "boss": {}}
	if add_of != 0: m.home = mobs[add_of].home if mobs.has(add_of) else m.home
	_next_nid += 1
	mobs[m.nid] = m
	if def.boss or rank == "boss": m.boss = _boss_state(m)
	return m

func pub(m: Dictionary) -> Dictionary:
	return {"id": m.nid, "k": m.kind, "lvl": m.lvl, "rk": m.rank, "nm": m.name, "aff": m.aff, "x": m.pos.x, "y": 0.0, "z": m.pos.z,
		"yaw": m.yaw, "hp": m.hp, "mhp": m.mhp, "own": false, "add": m.add_of}

func spawner_list(sp: Dictionary) -> Array:
	var out := []
	for nid in sp.mobs:
		var m = mobs.get(nid)
		if m != null and m.alive: out.append(pub(m))
	for nid in mobs:   # помощники боссов этого логова
		var m: Dictionary = mobs[nid]
		if m.alive and int(m.add_of) != 0 and m.sp == sp.key: out.append(pub(m))
	return out

# ---------------- игроки ----------------
func set_player(peer: int, pos: Vector3, hp: float, lvl: int, cls: String, max_hp: float) -> void:
	var p = players.get(peer)
	if p == null:
		p = {"pos": pos, "hp": hp, "alive": hp > 0.0, "lvl": lvl, "cls": cls, "threat_k": 2.0 if cls == "warrior" else 1.0, "max_hp": max_hp}
		players[peer] = p
	p.pos = Vector3(pos.x, 0, pos.z); p.hp = hp; p.alive = hp > 0.0; p.lvl = lvl; p.max_hp = max_hp

func remove_player(peer: int) -> void:
	players.erase(peer)
	for nid in mobs: mobs[nid].threat.erase(peer)
	for key in spawners: spawners[key].subs.erase(peer)

func _alive_near(pos: Vector3, r: float) -> Array:
	var out := []
	for pid in players:
		var p = players[pid]
		if p.alive and U.flat_dist(p.pos, pos) <= r: out.append(pid)
	return out

# ---------------- события ----------------
func _emit(peer: int, ev: Dictionary, pos: Vector3) -> void: events.append([peer, ev, pos])
func _warn(s: String, pos: Vector3) -> void: _emit(0, {"t": "warn", "s": s}, pos)

func _hurt(pid: int, dmg: float, src: Vector3, what := "", lethal := false, frac := 0.0, kb := 0.0) -> void:
	if not players.has(pid) or not players[pid].alive: return
	stats.hurt += 1
	_emit(pid, {"t": "hurt", "d": dmg, "f": frac, "x": src.x, "z": src.z, "l": lethal, "w": what, "kb": kb}, src)
	if lethal: players[pid].alive = false

func _dmg(m: Dictionary, pid: int) -> float:
	var pl := int(players[pid].lvl) if players.has(pid) else int(m.lvl)
	var bk: Dictionary = m.boss
	var mult: float = float(bk.get("dmgm", 1.0)) if not bk.is_empty() else 1.0
	if t < float(m.get("weak_t", 0.0)): mult *= 1.0 - float(m.weak)
	return float(m.def.dmg) * Combat.enemy_dmg_mult(int(m.lvl)) * float(m.dmgk) * mult * Combat.enemy_dmg_factor(int(m.lvl), pl)

func _later(dt: float, f: Callable) -> void: sched.append([t + dt, f])

## Метка на земле: disc | cone | ring | line; f(pid) вызывается для каждого внутри в момент удара
func _tele(kind: String, pos: Vector3, r: float, dur: float, on_hit: Callable, opts := {}) -> Dictionary:
	var z := {"id": _next_tele, "k": kind, "pos": Vector3(pos.x, 0, pos.z), "r": r, "left": dur, "dur": dur, "hit": on_hit}
	_next_tele += 1
	z.merge(opts)
	tele.append(z)
	stats.tele += 1
	_emit(0, {"t": "tele", "id": z.id, "k": kind, "x": pos.x, "z": pos.z, "r": r, "dur": dur, "yaw": float(opts.get("yaw", 0.0)),
		"ang": float(opts.get("ang", 90.0)), "in": float(opts.get("inner", 0.0)), "fo": 0, "m": str(opts.get("mode", "")),
		"c": str(opts.get("col", "red")), "r1": float(opts.get("r1", r))}, pos)
	return z

static func inside(z: Dictionary, p: Vector3) -> bool:
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
			return along >= -1.0 and along <= z.r and absf(dv.cross(fwd)) <= float(z.ang) / 2.0
		_: return dist <= float(z.get("cur_r", z.r))

func _cancel_tele_of(nid: int) -> void:
	for z in tele.duplicate():
		if int(z.get("owner", 0)) == nid:
			tele.erase(z)
			_emit(0, {"t": "tele_x", "id": z.id}, z.pos)

# ---------------- урон от игроков, контроль ----------------
## Удар игрока по врагу (сервер уже проверил дистанцию и потолки). Возвращает принятый урон.
func hit(peer: int, nid: int, dmg: float) -> float:
	var m = mobs.get(nid)
	if m == null or not m.alive: return 0.0
	if not m.boss.is_empty() and bool(m.boss.get("inv", false)): return 0.0
	m.hp = float(m.hp) - dmg
	m.parts[peer] = true; m.killer = peer; m.last_hit = t
	var k: float = float(players[peer].threat_k) if players.has(peer) else 1.0
	m.threat[peer] = float(m.threat.get(peer, 0.0)) + dmg * k
	if not m.aggro: _aggro(m)
	if aff_has(m, "summoner") and not m.summoned and m.hp < m.mhp * 0.5: _summon_aff(m)
	if float(m.hp) <= 0.0: _kill(m)
	return dmg

func aff_has(m: Dictionary, a: String) -> bool: return (m.aff as Array).has(a)

func cc(peer: int, nid: int, kind: String, v: float, dur: float, dir: Vector3) -> void:
	var m = mobs.get(nid)
	if m == null or not m.alive: return
	var boss: bool = not m.boss.is_empty()
	match kind:
		"stun": if not boss: m.stun = maxf(float(m.stun), clampf(dur, 0.0, 3.0))
		"slow":
			m.slow = clampf(v, 0.3, 1.0); m.slow_t = clampf(dur, 0.0, 6.0)
		"kb":
			if not boss and dir.length() > 0.01:
				var to: Vector3 = m.pos + Vector3(dir.x, 0, dir.z).normalized() * clampf(v * 0.25, 0.0, 3.0)
				m.pos = nav.snap(m.sp, to)
		"weaken":
			m.weak = clampf(v, 0.0, 0.5); m.weak_t = t + clampf(dur, 0.0, 8.0)
		"taunt":
			m.taunt = [peer, t + clampf(dur, 0.0, 6.0)]
			if not m.aggro: _aggro(m)

func _aggro(m: Dictionary) -> void:
	m.aggro = true
	if int(m.add_of) != 0: return
	var sp = spawners.get(m.sp)
	if sp == null: return
	for nid in sp.mobs:   # стая вступает в бой вместе
		var o = mobs.get(nid)
		if o != null and o.alive and not o.aggro and U.flat_dist(o.pos, m.pos) < 14.0:
			o.aggro = true
			for pid in m.threat: o.threat[pid] = maxf(float(o.threat.get(pid, 0.0)), 1.0)

func _kill(m: Dictionary) -> void:
	if not m.alive: return
	m.alive = false; m.hp = 0.0
	stats.kills += 1
	_cancel_tele_of(int(m.nid))
	var sp = spawners.get(m.sp)
	m.respawn_at = t + float(sp.respawn if sp else 30.0)
	if aff_has(m, "explosive"):
		var c: Vector3 = m.pos; var dmg := _dmg(m, 0) * 1.6
		_tele("disc", c, 3.0, 1.0, func(pid): _hurt(pid, dmg, c, "Взрыв"))
	if not m.boss.is_empty(): _boss_dead(m)
	if kills_cb.is_valid(): kills_cb.call(self, sp, m)
	if int(m.add_of) != 0: mobs.erase(m.nid)

# ---------------- шаг ----------------
func tick(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	t += dt
	stats.ticks += 1
	if not sched.is_empty():
		var due := []
		for s in sched: if float(s[0]) <= t: due.append(s)
		for s in due:
			sched.erase(s)
			(s[1] as Callable).call()
	var awake := 0
	for key in spawners:
		var sp: Dictionary = spawners[key]
		var near := not _alive_near(sp.pos, WAKE_R).is_empty() or zone_id == "dungeon"
		sp["awake"] = near
		if not near: continue
		awake += 1
		for nid in sp.mobs:
			var m = mobs.get(nid)
			if m == null: continue
			if m.alive: _ai(m, dt)
			elif float(sp.respawn) > 0.0 and t >= float(m.respawn_at) and not sp.subs.is_empty():
				if not _alive_near(sp.pos, float(sp.r) + 8.0).is_empty(): continue
				var nm := _new_mob(sp, int(m.slot))
				mobs.erase(nid)
				sp.mobs[sp.mobs.find(nid)] = nm.nid
				_emit(0, {"t": "spawn", "sp": key, "e": [pub(nm)]}, sp.pos)
	for nid in mobs.keys():   # помощники боссов
		var m: Dictionary = mobs[nid]
		if int(m.add_of) != 0 and m.alive: _ai(m, dt)
	stats.awake = awake
	_resolve_tele(dt)
	stats.ai_ms = float(stats.ai_ms) * 0.95 + (Time.get_ticks_usec() - t0) / 1000.0 * 0.05

func _resolve_tele(dt: float) -> void:
	if tele.is_empty(): return
	var done := []
	for z in tele:
		z.left = float(z.left) - dt
		if z.has("r1"): z["cur_r"] = lerpf(float(z.r), float(z.r1), clampf(1.0 - float(z.left) / maxf(0.01, float(z.dur)), 0.0, 1.0))
		if float(z.left) <= 0.0: done.append(z)
	for z in done:
		tele.erase(z)
		if z.get("group_fn") is Callable:
			(z.group_fn as Callable).call(); continue
		var cb: Callable = z.hit
		if not cb.is_valid(): continue
		for pid in players.keys():
			if players.has(pid) and players[pid].alive and inside(z, players[pid].pos): cb.call(pid)

# ---------------- ИИ ----------------
func _target(m: Dictionary):
	var tn: Array = m.taunt
	if int(tn[0]) != 0 and t < float(tn[1]) and players.has(int(tn[0])) and players[int(tn[0])].alive: return int(tn[0])
	var best = null; var bt := -1.0
	var reach: float = float(m.def.aggro) * (2.4 if m.aggro else 1.0)
	for pid in players:
		var p = players[pid]
		if not p.alive: continue
		var d := U.flat_dist(p.pos, m.pos)
		if d > reach and not m.threat.has(pid): continue
		if d > LEASH + 20.0: continue
		var th := float(m.threat.get(pid, 0.0)) + 1.0 / (1.0 + d)
		if th > bt: bt = th; best = pid
	return best

func _move(m: Dictionary, goal: Vector3, speed: float, dt: float) -> void:
	goal = Vector3(goal.x, 0, goal.z)
	m.pt = float(m.pt) - dt
	if (m.path as PackedVector3Array).is_empty() or float(m.pt) <= 0.0 or U.flat_dist(m.pgoal, goal) > 1.5:
		m.path = nav.path(m.sp, m.pos, goal); m.pi = 1; m.pgoal = goal; m.pt = 0.5
		stats.paths += 1
	var next := goal
	var path: PackedVector3Array = m.path
	while int(m.pi) < path.size():
		var q: Vector3 = path[int(m.pi)]
		if U.flat_dist(q, m.pos) < 0.4: m.pi = int(m.pi) + 1
		else: next = Vector3(q.x, 0, q.z); break
	var to: Vector3 = next - m.pos; to.y = 0
	var d := to.length()
	if d < 0.01: return
	var step := minf(d, speed * dt)
	m.pos = m.pos + to / d * step
	m.yaw = atan2(to.x, to.z)

func _ai(m: Dictionary, dt: float) -> void:
	if float(m.slow_t) > 0.0:
		m.slow_t = float(m.slow_t) - dt
		if float(m.slow_t) <= 0.0: m.slow = 1.0
	if not (m.dash as Dictionary).is_empty(): _dash_step(m, dt); return
	var bs: Dictionary = m.boss
	if not bs.is_empty():
		_boss_tick(m, dt)
		if float(bs.get("busy", 0.0)) > 0.0: return
	if float(m.busy) > 0.0: m.busy = float(m.busy) - dt; return
	if float(m.stun) > 0.0: m.stun = float(m.stun) - dt; return
	m.cd = float(m.cd) - dt
	m.atk_t = float(m.atk_t) - dt
	var speed: float = float(m.def.speed) * float(m.slow) * float(m.spd) * float(bs.get("spdm", 1.0))
	var home_d := U.flat_dist(m.pos, m.home)
	if home_d > (LEASH_BOSS if not bs.is_empty() else LEASH) and not m.ret:
		m.ret = true; m.aggro = false; m.threat.clear(); m.taunt = [0, 0.0]
	if m.ret:
		_move(m, m.home, speed * 1.5, dt)
		m.hp = minf(float(m.mhp), float(m.hp) + float(m.mhp) * 0.25 * dt)
		if U.flat_dist(m.pos, m.home) < 1.5: m.ret = false; m.hp = m.mhp; m.parts = {}
		return
	if aff_has(m, "burning"):
		m.aura_t = float(m.aura_t) - dt
		if float(m.aura_t) <= 0.0:
			m.aura_t = 1.0
			for pid in _alive_near(m.pos, 3.2): _hurt(pid, _dmg(m, pid) * 0.25, m.pos, "Пламя")
	var tp = _target(m)
	if tp == null:
		if m.aggro:   # цель потеряна — назад к логову с восстановлением
			m.aggro = false; m.threat.clear()
			if U.flat_dist(m.pos, m.home) > 3.0: m.ret = true; return
		m.wander = float(m.wander) - dt
		if float(m.wander) <= 0.0:
			m.wander = randf_range(2.5, 6.0)
			var r := Vector2.from_angle(randf() * TAU) * randf() * 6.0
			m.wto = m.home + Vector3(r.x, 0, r.y)
		if U.flat_dist(m.wto, m.pos) > 0.5: _move(m, m.wto, speed * 0.4, dt)
		return
	if not m.aggro: _aggro(m)
	if not m.threat.has(tp): m.threat[tp] = 1.0
	var tpos: Vector3 = players[tp].pos
	var to: Vector3 = tpos - m.pos
	var d := to.length()
	if d > 0.05: m.yaw = atan2(to.x, to.z)
	var rng: float = float(m.def.range)
	match str(m.ai):
		"charger":
			if float(m.cd) <= 0.0 and d > 4.5 and d < 14.0 and bs.is_empty():
				_charge(m, tp, clampf(d + 3.0, 6.0, 13.0), 0.75, 13.0, 1.5, 6.0, float(m.def.radius) * 2.2 + 0.6); m.cd = 7.0; return
		"healer":
			if float(m.cd) <= 0.0 and _heal_ally(m): return
			if d < rng * 0.45: _move(m, m.pos - to.normalized() * 4.0, speed * 0.8, dt); return
		"caster", "ranged":
			if d < rng * 0.35 and bs.is_empty(): _move(m, m.pos - to.normalized() * 4.0, speed * 0.7, dt); return
	if d > rng * 0.9:
		_move(m, tpos, speed, dt)
	elif float(m.atk_t) <= 0.0:
		m.atk_t = float(m.def.interval) / float(m.spd)
		_attack(m, tp, d)

func _attack(m: Dictionary, tp: int, d: float) -> void:
	stats.atk += 1
	var ranged: bool = bool(m.def.ranged)
	_emit(0, {"t": "atk", "id": m.nid, "p": tp, "rg": ranged or m.ai == "caster", "a": "cast" if m.ai in ["caster", "healer"] else ""}, m.pos)
	var nid: int = m.nid
	match str(m.ai):
		"caster":
			var c: Vector3 = players[tp].pos
			var dm := _dmg(m, tp) * 1.3
			m.busy = 1.1
			_tele("disc", c, 2.4, 1.1, func(pid): _hurt(pid, dm, c, ""), {"owner": nid})
			return
		"exploder":
			m.busy = 1.0
			var dm := _dmg(m, tp)
			_tele("disc", m.pos, 2.8, 0.9, func(pid): _hurt(pid, dm, mobs[nid].pos if mobs.has(nid) else Vector3.ZERO, "Взрыв"), {"owner": 0})
			var _f1 := func():
				var mm = mobs.get(nid)
				if mm != null and mm.alive: mm.killer = 0; _kill(mm)
			_later(0.9, _f1)
			return
	var dm := _dmg(m, tp)
	if ranged:
		var aim: Vector3 = players[tp].pos
		var fly := d / float(m.def.get("proj_speed", 13.0))
		var _f2 := func():
			if players.has(tp) and players[tp].alive and U.flat_dist(players[tp].pos, aim) < 1.6:
				_hurt(tp, dm, aim, "")
				_vamp(nid, dm)
		_later(fly, _f2)
	else:
		var reach: float = float(m.def.range) + 0.6
		var _f3 := func():
			var mm = mobs.get(nid)
			if mm == null or not mm.alive or not players.has(tp): return
			if U.flat_dist(players[tp].pos, mm.pos) <= reach:
				_hurt(tp, dm, mm.pos, "")
				_vamp(nid, dm)
		_later(0.45 if bool(m.def.boss) else 0.25, _f3)

func _vamp(nid: int, dm: float) -> void:
	var m = mobs.get(nid)
	if m != null and m.alive and aff_has(m, "vampire"): m.hp = minf(float(m.mhp), float(m.hp) + dm * 0.5)

func _heal_ally(m: Dictionary) -> bool:
	var best = null; var bf := 0.8
	for nid in mobs:
		var o: Dictionary = mobs[nid]
		if not o.alive or not o.boss.is_empty() or U.flat_dist(o.pos, m.pos) > 12.0: continue
		var f: float = float(o.hp) / maxf(1.0, float(o.mhp))
		if f < bf: bf = f; best = o
	if best == null: return false
	m.cd = 5.0; m.busy = 0.6
	var amt: float = float(best.mhp) * 0.25
	best.hp = minf(float(best.mhp), float(best.hp) + amt)
	_emit(0, {"t": "heal", "id": m.nid, "to": best.nid, "a": amt}, m.pos)
	return true

## Таран: полоса-предупреждение, затем рывок; задетый — урон и отбрасывание
func _charge(m: Dictionary, tp: int, length: float, windup: float, spd: float, k: float, kb: float, width: float) -> void:
	var dir: Vector3 = players[tp].pos - m.pos; dir.y = 0; dir = dir.normalized()
	m.yaw = atan2(dir.x, dir.z)
	var nid: int = m.nid
	_tele("line", m.pos, length, windup, Callable(), {"yaw": m.yaw, "ang": width, "owner": nid})
	m.busy = windup + length / spd + 0.4
	_emit(0, {"t": "atk", "id": nid, "p": tp, "rg": false, "a": "roar"}, m.pos)
	var dm := _dmg(m, tp) * k
	var _f4 := func():
		var mm = mobs.get(nid)
		if mm != null and mm.alive: mm.dash = {"dir": dir, "left": length, "spd": spd, "dm": dm, "kb": kb, "hit": {}, "r": float(mm.def.radius) + 1.0}
	_later(windup, _f4)

func _dash_step(m: Dictionary, dt: float) -> void:
	var ds: Dictionary = m.dash
	var step: float = minf(float(ds.left), float(ds.spd) * dt)
	ds.left = float(ds.left) - step
	var np: Vector3 = m.pos + (ds.dir as Vector3) * step
	var sn := nav.snap(m.sp, np)
	if U.flat_dist(sn, np) > 0.5: ds.left = 0.0   # упёрся в стену
	m.pos = sn
	for pid in _alive_near(m.pos, float(ds.r)):
		if ds.hit.has(pid): continue
		ds.hit[pid] = true
		_hurt(pid, float(ds.dm), m.pos, "Таран", false, 0.0, float(ds.kb))
	if float(ds.left) <= 0.0: m.dash = {}; m.busy = 0.4

func _summon_aff(m: Dictionary) -> void:
	m.summoned = true
	for i in 2:
		var a := _new_mob(spawners[m.sp], -1, str(m.kind), maxi(1, int(m.lvl) - 1), m.pos + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)), int(m.nid))
		a.aggro = true; a.threat = m.threat.duplicate()
		_emit(0, {"t": "spawn", "sp": m.sp, "e": [pub(a)]}, m.pos)

# ---------------- боссы ----------------
const WORLD_BOSS_HP_K := 4.0     # v0.9.4: HP боссов локаций ×4
const WORLD_BOSS_ENRAGE := 210.0 # с этого момента боя — ярость (урон ×1.6, частые приёмы)
## v0.9.4: фирменный приём каждого босса локации (кроме общих slam/rock/charge/…)
const SIGNATURE := {"troll": "quake", "boss_ogron": "quake", "boss_root": "roots", "boss_urgal": "firerain",
	"boss_gnil": "bog", "boss_hyalm": "blizzard", "boss_seraph": "judgment"}
func _boss_state(m: Dictionary) -> Dictionary:
	var warden: bool = m.kind == "warden"
	return {"warden": warden, "ph": 1, "busy": 0.0, "inv": false, "rg": false, "en": false, "spec": 3.0 if warden else 4.0, "summ": 0.0,
		"ft": 0.0, "seq": 0, "cn": "", "h": "", "cl": 0.0, "ct": 0.0, "berserk": false, "st_t": 0.0, "dmgm": 1.0, "spdm": 1.0, "empty_t": 0.0,
		"names": WardenBrain.PHASE_NAMES if warden else BossBrain.PHASE_NAMES}

func _st(m: Dictionary) -> void:
	var b: Dictionary = m.boss
	b.st_t = 1.0
	_emit(0, {"t": "st", "id": m.nid, "ph": b.ph, "rg": b.rg, "en": b.en, "inv": b.inv, "cn": b.cn, "ct": b.ct, "cl": b.cl, "h": b.h,
		"el": maxf(0.0, 300.0 - float(b.ft)) if b.warden else 0.0, "names": b.names}, m.pos)

func _cast(m: Dictionary, nm: String, hint: String, dur: float) -> void:
	var b: Dictionary = m.boss
	b.cn = nm; b.h = hint; b.cl = dur; b.ct = dur; b.busy = dur + 0.2
	_st(m)

func _end_cast(m: Dictionary) -> void:
	var b: Dictionary = m.boss
	b.cn = ""; b.h = ""; b.cl = 0.0; b.ct = 0.0
	_st(m)

func _boss_tick(m: Dictionary, dt: float) -> void:
	var b: Dictionary = m.boss
	b.st_t = float(b.st_t) - dt
	if float(b.cl) > 0.0: b.cl = maxf(0.0, float(b.cl) - dt)
	if float(b.busy) > 0.0: b.busy = float(b.busy) - dt
	if b.warden: _warden(m, dt)
	else: _troll(m, dt)
	if float(b.st_t) <= 0.0: _st(m)

func _troll(m: Dictionary, dt: float) -> void:
	var b: Dictionary = m.boss
	var tp = _target(m)
	if tp == null:
		if b.en and float(m.hp) < float(m.mhp) and not m.ret:   # все ушли/погибли — домой и лечиться
			m.ret = true; m.aggro = false; m.threat.clear()
		if float(m.hp) >= float(m.mhp) and b.en:
			m.boss = _boss_state(m); _st(m)   # v0.9.4: сброс боя — фазы, ярость и таймер с нуля
		return
	if not b.en: b.en = true; _st(m)
	var f: float = float(m.hp) / maxf(1.0, float(m.mhp))
	var want := 3 if f <= 0.33 else (2 if f <= 0.66 else 1)
	if want > int(b.ph) and float(b.busy) <= 0.0:
		b.ph = want; b.busy = 1.6; b.inv = true
		var nm := str(m.def.name)
		if want == 3: b.rg = true; b.spdm = 1.35; b.dmgm = 1.3
		_warn(("Тролль в гневе! Фаза 2: рывки и подмога" if m.kind == "troll" else "%s в гневе! Фаза 2" % nm) if want == 2 else
			("ЯРОСТЬ ТРОЛЛЯ! Фаза 3: он быстрее и сильнее" if m.kind == "troll" else "%s в ярости! Фаза 3" % nm), m.pos)
		var nid: int = m.nid
		_later(1.6, func(): if mobs.has(nid): mobs[nid].boss.inv = false; mobs[nid].boss.spec = 1.5; mobs[nid].boss.summ = 0.0; _st(mobs[nid]))
		_st(m)
		return
	b.ft = float(b.ft) + dt
	if float(b.ft) >= WORLD_BOSS_ENRAGE and not b.berserk:
		b.berserk = true; b.rg = true; b.dmgm = float(b.dmgm) * 1.6; b.spdm = maxf(float(b.spdm), 1.35)
		_warn("%s впадает в неистовство! Урон резко вырос" % str(m.def.name), m.pos); _st(m)
	if float(b.busy) > 0.0: return
	b.spec = float(b.spec) - dt; b.summ = float(b.summ) - dt; b.sig = float(b.get("sig", 8.0)) - dt
	if float(b.spec) > 0.0: return
	b.spec = [0.0, 6.5, 5.0, 3.8][int(b.ph)] * (0.7 if b.berserk else 1.0)
	var moves: Array = m.def.get("moves", ["slam", "rock", "charge"])
	var options: Array = moves.slice(0, 2)
	if int(b.ph) >= 2: options = moves.duplicate() + [moves[0]]
	if SIGNATURE.has(m.kind) and float(b.sig) <= 0.0:
		b.sig = [0.0, 16.0, 12.0, 9.0][int(b.ph)]
		options = [SIGNATURE[m.kind]]
	if int(b.ph) >= 2 and float(b.summ) <= 0.0 and _alive_adds(m) < 3: options = ["summon"]
	_boss_move(m, options.pick_random(), tp)

func _alive_adds(m: Dictionary) -> int:
	var n := 0
	for nid in mobs: if mobs[nid].alive and int(mobs[nid].add_of) == int(m.nid): n += 1
	return n

func _boss_move(m: Dictionary, kind: String, tp: int) -> void:
	var b: Dictionary = m.boss
	var ph := int(b.ph)
	var tpos: Vector3 = players[tp].pos
	var fwd := Vector3(sin(m.yaw), 0, cos(m.yaw))
	var to: Vector3 = (tpos - m.pos); to.y = 0
	if to.length() > 0.1: fwd = to.normalized(); m.yaw = atan2(fwd.x, fwd.z)
	var nid: int = m.nid
	var base := _dmg(m, tp)
	_emit(0, {"t": "atk", "id": nid, "p": tp, "rg": false, "a": kind}, m.pos)
	match kind:
		"slam":
			var c: Vector3 = m.pos + fwd * 2.0
			var tl := 1.1 if ph < 3 else 0.85
			b.busy = tl + 0.6 + (0.55 if ph >= 3 else 0.0)
			_tele("disc", c, 3.2, tl, func(pid): _hurt(pid, base * 1.7, c, "Удар"), {"owner": nid})
			_later(tl, func(): _emit(0, {"t": "wave", "x": c.x, "z": c.z, "sp": 7.5, "d": base * 0.9}, c))
			if ph >= 3: _later(tl + 0.55, func(): _emit(0, {"t": "wave", "x": c.x, "z": c.z, "sp": 9.0, "d": base * 0.9}, c))
		"rock":
			var n := 1 if ph < 3 else 3
			b.busy = 1.25
			for i in n:
				var c: Vector3 = tpos + (Vector3.ZERO if i == 0 else Vector3(randf_range(-4, 4), 0, randf_range(-4, 4)))
				_tele("disc", c, 2.2, 1.75, func(pid): _hurt(pid, base * 1.3, c, "Камень"), {"owner": nid, "col": "orange"})
		"charge":
			_charge(m, tp, clampf(to.length() + 4.0, 6.0, 16.0), 1.0 if ph < 3 else 0.8, 17.0, 1.5, 9.0, 2.8)
			b.busy = float(m.busy); m.busy = 0.0
		"summon":
			b.busy = 1.7; b.summ = 22.0
			var ad: Array = m.def.get("adds", ["goblin", "skeleton"])
			var kd: String = ad[0] if ph < 3 else ad[mini(1, ad.size() - 1)]
			_warn("Тролль призывает подмогу!" if m.kind == "troll" else "%s призывает подмогу!" % str(m.def.name), m.pos)
			var _f5 := func():
				var mm = mobs.get(nid)
				if mm == null or not mm.alive: return
				var list := []
				for i in 2:
					var a := _new_mob(spawners[mm.sp], -1, kd, maxi(3, int(mm.lvl) - 3), mm.pos + Vector3(-3.5 if i == 0 else 3.5, 0, randf_range(-1.5, 1.5)), nid)
					a.aggro = true; a.threat = mm.threat.duplicate()
					list.append(pub(a))
				_emit(0, {"t": "spawn", "sp": mm.sp, "e": list}, mm.pos)
			_later(0.9, _f5)
		"breath":
			var tl := 1.2 if ph < 3 else 0.95
			b.busy = tl + 0.6
			_tele("cone", m.pos, 9.0, tl, func(pid): _hurt(pid, base * 1.8, mobs[nid].pos if mobs.has(nid) else tpos, "Пламя"), {"owner": nid, "yaw": m.yaw, "ang": 76.0, "col": "orange"})
		"spores":
			var n := 3 if ph < 3 else 5
			b.busy = 1.8
			for i in n:
				var c: Vector3 = tpos + (Vector3.ZERO if i == 0 else Vector3(randf_range(-5, 5), 0, randf_range(-5, 5)))
				_tele("disc", c, 2.4, 1.3, func(pid): _hurt(pid, base * 1.2, c, "Споры"), {"owner": nid, "col": "green"})
		"quake":   # разлом: цепочка ударов по линии к цели, затем ударная волна
			var n := 5 if ph < 3 else 7
			b.busy = 0.9 + n * 0.28
			_warn("%s раскалывает землю! Уходите с линии разлома" % str(m.def.name), m.pos)
			for i in n:
				var c: Vector3 = m.pos + fwd * (3.0 + i * 2.4)
				_tele("disc", c, 2.3, 1.0 + i * 0.28, func(pid): _hurt(pid, base * 1.5, c, "Разлом", false, 0.0, 6.0), {"owner": nid, "col": "orange"})
		"roots":   # корни под каждым игроком рядом + исцеление, если хоть кто-то попался
			b.busy = 1.9
			_warn("%s пускает корни — отойдите с отметки!" % str(m.def.name), m.pos)
			for pid in _alive_near(m.pos, 20.0):
				var c: Vector3 = players[pid].pos
				_tele("disc", c, 2.6, 1.6, func(q):
					_hurt(q, base * 1.4, c, "Корни")
					var mm = mobs.get(nid)
					if mm != null and mm.alive: mm.hp = minf(float(mm.mhp), float(mm.hp) + float(mm.mhp) * 0.02), {"owner": nid, "col": "green"})
		"firerain":   # огненный дождь вокруг босса + дыхание в цель
			var n := 8 if ph < 3 else 12
			b.busy = 2.4
			_warn("%s обрушивает огненный дождь!" % str(m.def.name), m.pos)
			for i in n:
				var ang := randf() * TAU; var rr := randf_range(3.0, 11.0)
				var c: Vector3 = m.pos + Vector3(cos(ang) * rr, 0, sin(ang) * rr)
				_tele("disc", c, 2.4, 1.4 + randf() * 0.9, func(pid): _hurt(pid, base * 1.3, c, "Огненный дождь"), {"owner": nid, "col": "orange"})
		"bog":   # трясина: кольцо вокруг (безопасно — вплотную к боссу), затем общий выброс яда
			b.busy = 2.6
			var c: Vector3 = m.pos
			_warn("%s извергает трясину — держитесь вплотную!" % str(m.def.name), m.pos)
			_tele("ring", c, 12.0, 1.9, func(pid): _hurt(pid, base * 2.0, c, "Трясина"), {"owner": nid, "inner": 3.5, "col": "green"})
		"blizzard":   # буран: три волны колец от центра наружу — нужно перешагивать
			b.busy = 3.0
			var c: Vector3 = m.pos
			_warn("%s поднимает буран!" % str(m.def.name), m.pos)
			for i in 3:
				var r_in := 2.0 + i * 4.0
				_tele("ring", c, r_in + 3.0, 1.2 + i * 0.7, func(pid): _hurt(pid, base * 1.3, c, "Буран", false, 0.0, 4.0), {"owner": nid, "inner": r_in, "col": "blue"})
		"judgment":   # приговор: крест из лучей + метка под каждым игроком
			b.busy = 2.2
			_warn("%s выносит приговор! Уходите с лучей" % str(m.def.name), m.pos)
			for k in 4:
				var yw: float = m.yaw + k * PI / 2.0 + (PI / 4.0 if ph >= 3 else 0.0)
				_tele("line", m.pos, 18.0, 1.5, func(pid): _hurt(pid, base * 1.6, m.pos, "Приговор"), {"owner": nid, "yaw": yw, "ang": 3.0, "col": "purple"})
			for pid in _alive_near(m.pos, 22.0):
				var c: Vector3 = players[pid].pos
				_tele("disc", c, 2.2, 1.8, func(q): _hurt(q, base * 1.2, c, "Кара"), {"owner": nid, "col": "purple"})
		"nova":
			var tl := 1.3 if ph < 3 else 1.05
			b.busy = tl + 0.5
			var c: Vector3 = m.pos
			_tele("ring", c, 9.0, tl, func(pid): _hurt(pid, base * 1.6, c, "Кольцо"), {"owner": nid, "inner": 3.0, "col": "blue"})

## Хранитель Эфира: рассечение, разлом (впитать), Взор Пустоты (за колонну), щит со стражами, сжатие, сверхновая
func _arena_players(m: Dictionary) -> Array: return _alive_near(m.home, 24.0)

func _warden(m: Dictionary, dt: float) -> void:
	var b: Dictionary = m.boss
	var c: Vector3 = m.home
	var inside_p := _arena_players(m)
	if not b.en:
		if not _alive_near(c, 15.0).is_empty() or float(m.hp) < float(m.mhp):
			b.en = true; b.ft = 0.0
			_warn("Хранитель Эфира пробуждается! Следите за полосой заклинаний", c)
			_st(m)
		else:
			b.busy = 1.0   # ждёт
			return
	if inside_p.is_empty():
		b.empty_t = float(b.empty_t) + dt
		if float(b.empty_t) > 3.0: _warden_reset(m)
		return
	b.empty_t = 0.0
	b.ft = float(b.ft) + dt
	if float(b.ft) >= 300.0 and not b.berserk and float(b.busy) <= 0.0:
		b.berserk = true; b.rg = true
		_cast(m, "СВЕРХНОВАЯ", "Время вышло — Хранитель уничтожает всё!", 4.0)
		var nid: int = m.nid
		_tele("disc", c, 20.0, 4.0, func(pid): _hurt(pid, 0.0, c, "Сверхновая", true), {"owner": nid})
		_later(4.0, func(): if mobs.has(nid): _end_cast(mobs[nid]))
		return
	if int(b.ph) == 2 and b.inv and float(b.busy) <= 0.0 and _alive_adds(m) == 0:
		b.inv = false
		_warn("Щит Хранителя пал!", c); _st(m)
	var f: float = float(m.hp) / maxf(1.0, float(m.mhp))
	var want := 3 if f <= 0.4 else (2 if f <= 0.7 else 1)
	if want > int(b.ph) and float(b.busy) <= 0.0:
		b.ph = want; b.busy = 1.6
		if want == 2:
			_warn("Фаза 2: Щит Пустоты! Убейте 4 стражей — тогда щит падёт", c)
			b.inv = true
			var list := []
			for i in 4:
				var a := i * TAU / 4.0 + PI / 4.0
				var g := _new_mob(spawners[m.sp], -1, "ether_guard", int(m.lvl) - 2, c + Vector3(cos(a), 0, sin(a)) * 13.0, int(m.nid))
				g.def = g.def.duplicate(); g.def.aggro = 40.0; g.aggro = true
				list.append(pub(g))
			_emit(0, {"t": "spawn", "sp": m.sp, "e": list}, c)
		else:
			_warn("Фаза 3: Сжатие! Хранитель в ярости", c)
			b.rg = true; b.spdm = 1.2; b.dmgm = 1.3
		b.spec = 1.5 + 1.6
		_st(m)
		return
	if float(b.busy) > 0.0: return
	b.spec = float(b.spec) - dt
	if float(b.spec) > 0.0: return
	b.spec = [0.0, 5.0, 4.5, 3.5][int(b.ph)] + 0.0
	b.seq = int(b.seq) + 1
	var order: Array = [["cleave", "soak", "cleave", "void"], ["cleave", "void", "soak"], ["shrink", "cleave", "void", "soak"]][int(b.ph) - 1]
	var tp = _target(m)
	if tp == null: tp = inside_p[0]
	var kind: String = order[int(b.seq) % order.size()]
	var nid: int = m.nid
	match kind:
		"cleave":
			var to: Vector3 = players[tp].pos - m.pos
			m.yaw = atan2(to.x, to.z)
			_cast(m, "Рассечение", "Уйдите из конуса перед Хранителем!", 2.5)
			_tele("cone", m.pos, 14.0, 2.5, func(pid): _hurt(pid, 0.0, c, "Рассечение", true), {"owner": nid, "yaw": m.yaw, "ang": 90.0})
			b.spec = float(b.spec) + 2.5
		"soak":
			var sp: Vector3 = players[tp].pos + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
			sp = c + U.flat(sp - c).limit_length(13.0); sp.y = 0
			_cast(m, "Эфирный разлом", "ВСТАНЬТЕ в светлый круг — впитайте разлом!", 5.0)
			var z := _tele("disc", sp, 3.0, 5.0, Callable(), {"owner": nid, "col": "green", "mode": "stack"})
			_tele("ring", c, 18.0, 5.0, Callable(), {"owner": nid, "inner": 17.1})
			z["group_fn"] = func():
				var ins := []
				for pid in _arena_players(m): if U.flat_dist(players[pid].pos, sp) <= 3.0: ins.append(pid)
				if ins.is_empty():
					for pid in _arena_players(m): _hurt(pid, 0.0, sp, "Разлом", true)
				else:
					for pid in ins: _hurt(pid, 0.0, sp, "Разлом", false, 0.3)
			b.spec = float(b.spec) + 5.0
		"void":
			m.pos = c
			_cast(m, "Взор Пустоты", "Спрячьтесь за колонну — вне линии взгляда!", 5.0)
			var z := _tele("disc", c, WardenBrain.VOID_R, 5.0, Callable(), {"owner": nid, "col": "purple"})
			for pl in nav.pillars:
				var dd := U.flat(pl - c)
				var wg := WardenBrain.shadow_wedge(dd.length(), nav.pillar_r)
				_tele("cone", c, WardenBrain.VOID_R, 5.0, Callable(), {"owner": nid, "yaw": atan2(dd.x, dd.z), "ang": float(wg.angle), "inner": float(wg.inner) * WardenBrain.VOID_R, "col": "cyan", "mode": "safe"})
			z["group_fn"] = func():
				for pid in _arena_players(m):
					if not _behind_pillar(c, players[pid].pos): _hurt(pid, 0.0, c, "Взор Пустоты", true)
			b.spec = float(b.spec) + 5.0
		"shrink":
			var spots := []
			var base := randf() * TAU
			for i in 3:
				var a := base + i * TAU / 3.0
				spots.append(c + Vector3(cos(a), 0, sin(a)) * 9.5 * (0.6 if i == 0 else 1.0))
			_cast(m, "Сжатие", "Бегите в светлый круг — он сужается!", 6.0)
			for s in spots: _tele("disc", s, 5.0, 6.0, Callable(), {"owner": nid, "col": "cyan", "r1": 2.0, "mode": "safe"})
			var z := _tele("disc", c, 18.0, 6.0, Callable(), {"owner": nid})
			z["group_fn"] = func():
				for pid in _arena_players(m):
					var ok := false
					for s in spots: if U.flat_dist(players[pid].pos, s) <= 2.2: ok = true
					if not ok: _hurt(pid, 0.0, c, "Сжатие", true)
			b.spec = float(b.spec) + 6.0
	_later(float(b.busy) - 0.2, func(): if mobs.has(nid) and mobs[nid].alive: _end_cast(mobs[nid]))

func _behind_pillar(c: Vector3, p: Vector3) -> bool:
	var a := Vector2(c.x, c.z); var bb := Vector2(p.x, p.z)
	for pl in nav.pillars:
		var cc := Vector2(pl.x, pl.z)
		var ab := bb - a
		var tt := clampf((cc - a).dot(ab) / maxf(0.0001, ab.length_squared()), 0, 1)
		if (a + ab * tt).distance_to(cc) <= nav.pillar_r + WardenBrain.COVER_PAD and tt > 0.05 and tt < WardenBrain.COVER_TT: return true
	return false

func _warden_reset(m: Dictionary) -> void:
	var b: Dictionary = m.boss
	var keep_names: Array = b.names
	m.boss = _boss_state(m); m.boss.names = keep_names
	m.hp = m.mhp; m.pos = m.home; m.threat.clear(); m.aggro = false; m.parts = {}
	_cancel_tele_of(int(m.nid))
	for nid in mobs.keys():
		var a: Dictionary = mobs[nid]
		if int(a.add_of) == int(m.nid) and a.alive:
			a.alive = false
			_emit(0, {"t": "gone", "id": nid}, a.pos)
			mobs.erase(nid)
	_warn("Хранитель восстановился — бой сброшен", m.home)
	_st(m)

func _boss_dead(m: Dictionary) -> void:
	_cancel_tele_of(int(m.nid))
	m.boss.en = false; m.boss.cn = ""; m.boss.cl = 0.0
	for nid in mobs.keys():
		var a: Dictionary = mobs[nid]
		if int(a.add_of) == int(m.nid) and a.alive:
			a.alive = false
			_emit(0, {"t": "gone", "id": nid}, a.pos)
			mobs.erase(nid)
