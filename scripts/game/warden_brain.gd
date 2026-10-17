extends RefCounted
class_name WardenBrain
## Босс подземелья «Хранитель Эфира» — рейдовые механики со смертельными ударами. У каждой —
## метка на земле, полоса каста с названием и подсказкой; от каждой можно уйти:
##  * «Рассечение» — конус 90° перед боссом (r 14): выйти из конуса за спину/вбок;
##  * «Эфирный разлом» — круг r 3 у игрока: ВСТАТЬ ВНУТРЬ (впитать), иначе взрыв по всей арене;
##  * «Взор Пустоты» — босс в центре, луч во все стороны: спрятаться за колонну (линия обзора);
##  * фаза 2 (70%): щит, 4 стража — пока они живы, босс неуязвим;
##  * фаза 3 (40%): «Сжатие» — 3 безопасных круга сжимаются, вне кругов — смерть;
##  * ярость через 5 минут боя: «Сверхновая» — гибель для всех (таймер на полосе босса).
## При гибели игрока бой сбрасывается (здоровье, фаза, помощники).

var e
var phase := 1
var busy := false
var invulnerable := false
var enraged := false
var engaged := false
var fight_time := 0.0
var special_timer := 3.0
var adds: Array = []
var log: Array = []
var cast_name := ""
var cast_hint := ""
var cast_left := 0.0
var cast_total := 0.0
var cast_mult := 1.0          # для тестов: ускорение кастов
var enrage_time := 300.0
var berserk := false          # таймер ярости истёк
var _tele: Array = []
var _seq := 0
const PHASE_NAMES := ["", "Страж", "Щит Пустоты", "Сжатие"]
const ONE_SHOT := 10.0

func setup(enemy) -> void:
	e = enemy

func zone(): return e.zone
func hp_frac() -> float: return e.hp / maxf(1.0, e.max_hp)
func center() -> Vector3: return e.home

func update(delta: float) -> void:
	if not e.alive: return
	var p = zone().player
	if p == null: return
	if p.dead:
		if engaged: reset_fight()
		return
	if not engaged:
		if U.flat_dist(p.global_position, center()) < 15.0 or e.hp < e.max_hp:
			engaged = true
			fight_time = 0.0
			Game.toast("Хранитель Эфира пробуждается! Следите за полосой заклинаний", 3.5)
		else: return
	fight_time += delta
	if cast_left > 0: cast_left = maxf(0.0, cast_left - delta)
	if fight_time >= enrage_time and not berserk and not busy:
		_enrage(); return
	if phase == 2 and invulnerable and not busy and _alive_adds() == 0:
		invulnerable = false
		log.append("shield_down")
		Game.toast("Щит Хранителя пал!", 2.5)
		_set_shield(false)
	var want := 1
	if hp_frac() <= 0.4: want = 3
	elif hp_frac() <= 0.7: want = 2
	if want > phase and not busy:
		_phase_change(want); return
	if busy: return
	special_timer -= delta
	if special_timer > 0: return
	special_timer = [0.0, 5.0, 4.5, 3.5][phase]
	_seq += 1
	var order: Array = [["cleave", "soak", "cleave", "void"], ["cleave", "void", "soak"], ["shrink", "cleave", "void", "soak"]][phase - 1]
	run(order[_seq % order.size()], p)

func _alive_adds() -> int:
	var n := 0
	for a in adds:
		if is_instance_valid(a) and a.alive: n += 1
	return n

func run(kind: String, t) -> void:
	match kind:
		"cleave": _cleave(t)
		"soak": _soak(t)
		"void": _void(t)
		"shrink": _shrink(t)
		"adds": _adds()
		"enrage": _enrage()

func _wait(sec: float) -> bool:
	await e.get_tree().create_timer(sec, false).timeout
	return is_instance_valid(e) and e.alive and engaged

func _face(p: Vector3) -> void:
	var d := U.flat(p - e.global_position)
	if d.length() > 0.1: e.rotation.y = atan2(d.x, d.z)

func _cast(nm: String, hint: String, dur: float) -> float:
	var d := dur * cast_mult
	cast_name = nm; cast_hint = hint; cast_left = d; cast_total = d
	return d

func _end_cast() -> void:
	cast_name = ""; cast_hint = ""; cast_left = 0.0; cast_total = 0.0
	for t in _tele: Tele.free_later(t)
	_tele.clear()
	busy = false

func _kill(p, what: String) -> void:
	if p == null or p.dead: return
	log.append("hit:" + what)
	p.invuln = 0.0
	p.take_damage(p.stats.max_hp * ONE_SHOT, center())
	zone().shake(0.6)

func _safe(what: String) -> void:
	log.append("safe:" + what)

## Прогресс метки во время каста
func _progress(tele: Node3D, dur: float) -> bool:
	var t := 0.0
	while t < dur:
		await e.get_tree().process_frame
		if not (is_instance_valid(e) and e.alive and engaged): return false
		t += e.get_process_delta_time()
		Tele.set_progress(tele, clampf(t / dur, 0, 1))
	return true

# ---------- Рассечение: фронтальный конус ----------
func in_cone(p: Vector3, dir: Vector3, r := 14.0, ang := 90.0) -> bool:
	var d := U.flat(p - e.global_position)
	if d.length() > r: return false
	if d.length() < e.radius + 0.5: return true
	return rad_to_deg(dir.angle_to(d.normalized())) <= ang / 2.0

func _cleave(t) -> void:
	busy = true
	log.append("cleave")
	_face(t.global_position)
	var dir := U.flat(e.global_basis.z).normalized()
	var dur := _cast("Рассечение", "Уйдите из конуса перед Хранителем!", 2.5)
	var tele := Tele.make(zone().fx_root, "cone", e.global_position, 14.0, Color(1, 0.2, 0.15), dir, 90.0)
	_tele.append(tele)
	e._model_action("slam")
	if not await _progress(tele, dur): _end_cast(); return
	var p = zone().player
	CombatFX.slash_arc(zone().fx_root, e.global_position, dir, 14.0, 90.0, Color(1, 0.3, 0.2), 0.4, 1.4)
	if p and not p.dead:
		if in_cone(p.global_position, dir): _kill(p, "cleave")
		else: _safe("cleave")
	_end_cast()

# ---------- Эфирный разлом: встать внутрь ----------
var soak_pos := Vector3.ZERO
func _soak(t) -> void:
	busy = true
	log.append("soak")
	soak_pos = t.global_position + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
	soak_pos = center() + U.flat(soak_pos - center()).limit_length(13.0)
	soak_pos.y = 0.0
	var dur := _cast("Эфирный разлом", "ВСТАНЬТЕ в светлый круг — впитайте разлом!", 5.0)
	var tele := Tele.make(zone().fx_root, "disc", soak_pos, 3.0, Color(0.4, 1.0, 0.6))
	_tele.append(tele)
	var warn := Tele.make(zone().fx_root, "ring", center(), 18.0, Color(1, 0.2, 0.3), Vector3.FORWARD, 360.0, 0.95)
	_tele.append(warn)
	e._model_action("roar")
	if not await _progress(tele, dur): _end_cast(); return
	var p = zone().player
	CombatFX.pillar(zone().fx_root, soak_pos, Color(0.5, 1, 0.7), 8.0, 1.0)
	if p and not p.dead:
		if U.flat_dist(p.global_position, soak_pos) <= 3.0:
			_safe("soak")
			p.take_damage(p.stats.max_hp * 0.3, soak_pos)
		else:
			CombatFX.flash(zone().fx_root, center(), Color(1, 0.3, 0.4), 18.0, 0.6)
			_kill(p, "soak")
	_end_cast()

# ---------- Взор Пустоты: за колонну ----------
func behind_pillar(p: Vector3) -> bool:
	var a := Vector2(center().x, center().z)
	var b := Vector2(p.x, p.z)
	for pl in zone().pillars:
		var c := Vector2(pl.x, pl.z)
		var ab := b - a
		var tt := clampf((c - a).dot(ab) / maxf(0.0001, ab.length_squared()), 0, 1)
		if (a + ab * tt).distance_to(c) <= float(zone().pillar_r) + 0.15 and tt > 0.05 and tt < 0.98: return true
	return false

func _void(t) -> void:
	busy = true
	log.append("void")
	e.global_position = Vector3(center().x, zone().ground_y(center()), center().z)
	var dur := _cast("Взор Пустоты", "Спрячьтесь за колонну — вне линии взгляда!", 5.0)
	var tele := Tele.make(zone().fx_root, "disc", center(), 18.0, Color(0.6, 0.2, 1.0))
	_tele.append(tele)
	# тени колонн — безопасные клинья (подсказка на земле)
	for pl in zone().pillars:
		var d := U.flat(pl - center()).normalized()
		var dist := U.flat_dist(pl, center())
		var ang := rad_to_deg(2.0 * atan2(float(zone().pillar_r), dist))
		var sh := Tele.make(zone().fx_root, "cone", center(), 18.0, Color(0.3, 1.0, 0.9), d, ang, dist / 18.0 + 0.04)
		_tele.append(sh)
	e._model_action("roar")
	if not await _progress(tele, dur): _end_cast(); return
	var p = zone().player
	CombatFX.flash(zone().fx_root, center() + Vector3.UP, Color(0.7, 0.3, 1), 18.0, 0.5)
	if p and not p.dead:
		if behind_pillar(p.global_position): _safe("void")
		else: _kill(p, "void")
	_end_cast()

# ---------- Сжатие: безопасные круги сужаются ----------
var safe_spots: Array = []
var safe_r := 0.0
func _shrink(_t) -> void:
	busy = true
	log.append("shrink")
	safe_spots.clear()
	var base := randf() * TAU
	for i in 3:
		var a := base + i * TAU / 3.0
		safe_spots.append(center() + Vector3(cos(a), 0, sin(a)) * 9.5 * (0.6 if i == 0 else 1.0))
	var dur := _cast("Сжатие", "Бегите в светлый круг — он сужается!", 6.0)
	var rings := []
	for s in safe_spots:
		var r := Tele.make(zone().fx_root, "disc", s, 5.0, Color(0.5, 0.9, 1.0))
		_tele.append(r); rings.append(r)
	var danger := Tele.make(zone().fx_root, "disc", center(), 18.0, Color(1, 0.15, 0.1))
	_tele.append(danger)
	var t := 0.0
	while t < dur:
		await e.get_tree().process_frame
		if not (is_instance_valid(e) and e.alive and engaged): _end_cast(); return
		t += e.get_process_delta_time()
		safe_r = lerpf(5.0, 2.0, clampf(t / dur, 0, 1))
		for r in rings:
			if is_instance_valid(r):
				r.get_node("Base").scale = Vector3(safe_r, 1, safe_r)
				r.get_node("Edge").scale = Vector3(safe_r, 1, safe_r)
		Tele.set_progress(danger, clampf(t / dur, 0, 1))
	var p = zone().player
	CombatFX.flash(zone().fx_root, center(), Color(1, 0.3, 0.2), 18.0, 0.5)
	if p and not p.dead:
		var ok := false
		for s in safe_spots:
			if U.flat_dist(p.global_position, s) <= safe_r + 0.2: ok = true
		if ok: _safe("shrink")
		else: _kill(p, "shrink")
	_end_cast()

# ---------- фазы ----------
func _phase_change(p: int) -> void:
	busy = true
	phase = p
	log.append("phase%d" % p)
	var z = zone()
	e._model_action("roar")
	z.shake(0.5)
	CombatFX.burst(z.fx_root, e.global_position + Vector3.UP * 2.0, Color(0.7, 0.4, 1), 40, 9.0, 0.15, 0.8, Vector3.UP, 90, -4)
	match p:
		2:
			Game.toast("Фаза 2: Щит Пустоты! Убейте 4 стражей — тогда щит падёт", 3.5)
			invulnerable = true
			_set_shield(true)
			_adds()
		3:
			Game.toast("Фаза 3: Сжатие! Хранитель в ярости", 3.0)
			enraged = true
			e.speed_mult = 1.2
			e.damage_mult = 1.3
	if not await _wait(1.6 * cast_mult): busy = false; return
	special_timer = 1.5
	busy = false

func _adds() -> void:
	log.append("adds")
	for i in 4:
		var a := i * TAU / 4.0 + PI / 4.0
		var pos := center() + Vector3(cos(a), 0, sin(a)) * 13.0
		var g := Enemy.spawn(zone(), "ether_guard", e.level - 2, pos, zone().fx_root)
		g.home = center()
		g.def = g.def.duplicate(); g.def.aggro = 40.0
		adds.append(g)
		CombatFX.pillar(zone().fx_root, pos, Color(0.6, 0.4, 1), 5.0, 0.8)

func _set_shield(on: bool) -> void:
	var sh = e.get_node_or_null("WardenShield")
	if on and sh == null:
		var m := U.prim("sphere", e, Vector3.UP * 2.2, Vector3.ONE * 5.2, Color(0.6, 0.4, 1))
		m.name = "WardenShield"
		m.material_override = U.fx_mat(Color(0.55, 0.35, 1.0, 0.22))
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	elif not on and sh: sh.queue_free()

func _enrage() -> void:
	busy = true
	enraged = true
	berserk = true
	log.append("enrage")
	var dur := _cast("СВЕРХНОВАЯ", "Время вышло — Хранитель уничтожает всё!", 4.0)
	var tele := Tele.make(zone().fx_root, "disc", center(), 20.0, Color(1, 0.1, 0.05))
	_tele.append(tele)
	if not await _progress(tele, dur): _end_cast(); return
	CombatFX.flash(zone().fx_root, center() + Vector3.UP, Color(1, 0.5, 0.2), 22.0, 0.8)
	_kill(zone().player, "enrage")
	_end_cast()

func enrage_left() -> float:
	return maxf(0.0, enrage_time - fight_time)

## Гибель игрока — бой сбрасывается
func reset_fight() -> void:
	engaged = false
	log.append("reset")
	phase = 1; enraged = false; berserk = false; invulnerable = false; fight_time = 0.0; _seq = 0
	e.hp = e.max_hp
	e.speed_mult = 1.0; e.damage_mult = 1.0
	_set_shield(false)
	for a in adds:
		if is_instance_valid(a) and a.alive: a.take_damage(999999.0, false)
	adds.clear()
	_end_cast()
	special_timer = 3.0
	e.global_position = Vector3(center().x, zone().ground_y(center()), center().z)
