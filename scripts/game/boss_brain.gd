extends RefCounted
class_name BossBrain
## Поведение босса «Древний тролль»: 3 фазы (100–66–33 %), особые атаки с предупреждением.
## Фаза 1: удар по земле с ударными волнами, бросок камня.
## Фаза 2: + рывок-таран, призыв гоблинов.
## Фаза 3 (ярость): быстрее и сильнее, двойные волны, град камней, призыв скелетов.
## Всё честно: у каждой атаки есть красная зона-предупреждение; волну можно перепрыгнуть, от всего — уйти кувырком.

var e            # Enemy
var phase := 1
var busy := false
var invulnerable := false
var enraged := false
var special_timer := 4.0
var summon_timer := 0.0
var adds: Array = []
var log: Array = []          # выполненные атаки (для тестов)
const PHASE_NAMES := ["", "Пробуждение", "Гнев гор", "Ярость"]

func setup(enemy) -> void:
	e = enemy

func zone(): return e.zone

func hp_frac() -> float:
	return e.hp / maxf(1.0, e.max_hp)

func update(delta: float) -> void:
	if not e.alive: return
	var want := 1
	if hp_frac() <= 0.33: want = 3
	elif hp_frac() <= 0.66: want = 2
	if want > phase and not busy:
		_phase_change(want)
		return
	if busy: return
	var t = e._choose_target()
	if t == null: return
	special_timer -= delta
	summon_timer -= delta
	if special_timer > 0: return
	special_timer = [0.0, 6.5, 5.0, 3.8][phase]
	var options := ["slam", "rock"]
	if phase >= 2: options += ["charge", "slam"]
	if phase >= 2 and summon_timer <= 0 and _alive_adds() < 3: options = ["summon"]
	run(options.pick_random(), t)

func _alive_adds() -> int:
	var n := 0
	for a in adds:
		if is_instance_valid(a) and a.alive: n += 1
	return n

func run(kind: String, t) -> void:
	match kind:
		"slam": _slam(t)
		"rock": _rock(t)
		"charge": _charge(t)
		"summon": _summon()

func _wait(sec: float) -> bool:
	await e.get_tree().create_timer(sec, false).timeout
	return is_instance_valid(e) and e.alive

func _face(p: Vector3) -> void:
	var d := U.flat(p - e.global_position)
	if d.length() > 0.1: e.rotation.y = atan2(d.x, d.z)

# ---------- смена фазы ----------
func _phase_change(p: int) -> void:
	busy = true; invulnerable = true
	phase = p
	log.append("phase%d" % p)
	var z = zone()
	e._model_action("roar")
	z.shake(0.5)
	CombatFX.burst(z.fx_root, e.global_position + Vector3.UP * 2.0, Color(1, 0.4, 0.2), 40, 9.0, 0.15, 0.8, Vector3.UP, 90, -4)
	match p:
		2: Game.toast("Тролль в гневе! Фаза 2: рывки и подмога", 3.0)
		3:
			Game.toast("ЯРОСТЬ ТРОЛЛЯ! Фаза 3: он быстрее и сильнее", 3.0)
			enraged = true
			e.speed_mult = 1.35
			e.damage_mult = 1.3
			if e.model is CharVisual:
				e.model._build_fx("embers", Color(1, 0.25, 0.05), e.model)
	# отталкивающая (безвредная) волна
	var ring := CombatFX.ground_ring(z.fx_root, e.global_position, 1.0, 0.15, Color(1, 0.5, 0.2, 0.6))
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(9, 1, 9), 0.6)
	tw.tween_property(ring.material_override, "albedo_color:a", 0.0, 0.6)
	tw.chain().tween_callback(ring.queue_free)
	if not await _wait(1.6): return
	invulnerable = false
	summon_timer = 0.0
	special_timer = 1.5
	busy = false

# ---------- удар по земле + ударные волны ----------
func _slam(t) -> void:
	busy = true
	log.append("slam")
	var z = zone()
	_face(t.global_position)
	var c: Vector3 = e.global_position + e.global_basis.z * 2.0
	c.y = z.ground_y(c)
	var tele := 1.1 if phase < 3 else 0.85
	z.fx("telegraph", c, 3.2, Color.RED, tele)
	e._model_action("slam")
	if not await _wait(tele): return
	z.shake(0.45)
	CombatFX.burst(z.fx_root, c + Vector3.UP * 0.3, Color(0.55, 0.45, 0.35), 34, 7.0, 0.2, 0.7, Vector3.UP, 70, -12)
	z.fx("ring", c, 3.2, Color(0.7, 0.5, 0.3), 0.35)
	var p = z.player
	if p and not p.dead and U.flat_dist(p.global_position, c) < 3.2: p.take_damage(e._damage() * 1.7, c)
	for m in z.minions.duplicate():
		if is_instance_valid(m) and U.flat_dist(m.global_position, c) < 3.2: m.take_damage(e._damage() * 1.7)
	_wave(c, 7.5)
	if phase >= 3:
		if not await _wait(0.55): return
		_wave(c, 9.0)
	if not await _wait(0.6): return
	busy = false

func _wave(c: Vector3, speed: float) -> void:
	var w := Shockwave.new()
	w.zone = zone(); w.center = c; w.speed = speed; w.damage = e._damage() * 0.9
	zone().fx_root.add_child(w)

# ---------- бросок камня ----------
func _rock(t) -> void:
	busy = true
	log.append("rock")
	var z = zone()
	_face(t.global_position)
	e._model_action("throw")
	var n := 1 if phase < 3 else 3
	if not await _wait(0.45): return
	for i in n:
		var target: Vector3 = t.global_position
		if i > 0: target += Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
		target.y = z.ground_y(target)
		var r := Rock.new()
		r.zone = z; r.from = e.global_position + Vector3.UP * 3.6 + e.global_basis.z * 0.8; r.to = target
		r.damage = e._damage() * 1.3; r.flight = 1.3
		z.fx_root.add_child(r)
		z.fx("telegraph", target, Rock.RADIUS, Color.RED, r.flight)
	if not await _wait(0.8): return
	busy = false

# ---------- рывок-таран ----------
func _charge(t) -> void:
	busy = true
	log.append("charge")
	var z = zone()
	_face(t.global_position)
	var start: Vector3 = e.global_position
	var dir := U.flat(t.global_position - start).normalized()
	var length := clampf(U.flat_dist(t.global_position, start) + 4.0, 6.0, 16.0)
	# предупреждение: красная полоса
	var tele := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(2.8, 0.02, length)
	tele.mesh = bm
	tele.material_override = U.fx_mat(Color(1, 0.1, 0.05, 0.35))
	tele.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	z.fx_root.add_child(tele)
	tele.global_position = start + dir * length / 2 + Vector3.UP * 0.06
	tele.rotation.y = atan2(dir.x, dir.z)
	e._model_action("roar")
	var windup := 1.0 if phase < 3 else 0.8
	if not await _wait(windup):
		tele.queue_free(); return
	tele.queue_free()
	e._model_action("charge")
	var speed := 17.0
	var traveled := 0.0
	var hit := false
	while traveled < length:
		var dt: float = e.get_process_delta_time()
		await e.get_tree().process_frame
		if not is_instance_valid(e) or not e.alive: return
		var step := speed * dt
		traveled += step
		var np: Vector3 = e.global_position + dir * step
		np.y = z.ground_y(np)
		e.global_position = np
		if fmod(traveled, 1.5) < step: CombatFX.burst(z.fx_root, np + Vector3.UP * 0.2, Color(0.6, 0.5, 0.4, 0.7), 6, 2.0, 0.2, 0.5, Vector3.UP, 60, -2)
		var p = z.player
		if not hit and p and not p.dead and U.flat_dist(p.global_position, np) < 1.7:
			hit = true
			p.take_damage(e._damage() * 1.5, np)
			if p.invuln <= 0: p.knockback(dir, 9.0)
			z.shake(0.4)
	z.shake(0.3)
	if not await _wait(0.7): return
	busy = false

# ---------- призыв ----------
func _summon() -> void:
	busy = true
	log.append("summon")
	summon_timer = 22.0
	var z = zone()
	e._model_action("roar")
	z.shake(0.3)
	if not await _wait(0.9): return
	var kind := "goblin" if phase < 3 else "skeleton"
	for i in 2:
		var pos: Vector3 = e.global_position + Vector3(-3.5 if i == 0 else 3.5, 0, randf_range(-1.5, 1.5))
		CombatFX.burst(z.fx_root, pos + Vector3.UP * 0.5, Color(0.5, 0.3, 0.8), 24, 4.0, 0.12, 0.6, Vector3.UP, 60, -1)
		var a := Enemy.spawn(z, kind, maxi(3, e.level - 3), pos, e.get_parent())
		a.home = e.home
		a._aggro = true
		if a.model is MobModel: a.model.play_action("spawn", 1.2)
		adds.append(a)
	Game.toast("Тролль призывает подмогу!", 2.0)
	if not await _wait(0.8): return
	busy = false

# ======================================================================
class Shockwave extends Node3D:
	## Кольцо, расходящееся по земле. Задевает только тех, кто на земле (можно перепрыгнуть).
	var zone
	var center := Vector3.ZERO
	var speed := 7.5
	var radius := 1.0
	var max_radius := 15.0
	var width := 0.9
	var damage := 10.0
	var _hit := false
	var _mi: MeshInstance3D
	var _torus: TorusMesh
	func _ready() -> void:
		_mi = CombatFX.ground_ring(self, center, 1.0, 0.1, Color(1.0, 0.45, 0.15, 0.85))
		_torus = _mi.mesh
		_mi.scale = Vector3.ONE
	func _process(delta: float) -> void:
		radius += speed * delta
		_torus.inner_radius = maxf(0.05, radius - width / 2)
		_torus.outer_radius = radius + width / 2
		var a := clampf(1.0 - radius / max_radius, 0, 1)
		(_mi.material_override as StandardMaterial3D).albedo_color.a = 0.85 * a + 0.1
		var p = zone.player
		if not _hit and p and not p.dead:
			var d := U.flat_dist(p.global_position, center)
			var above: float = p.global_position.y - zone.ground_y(p.global_position)
			if absf(d - radius) < width / 2 + 0.35 and above < 0.45:
				_hit = true
				p.take_damage(damage, center)
		if radius > max_radius: queue_free()

class Rock extends Node3D:
	## Камень по дуге; урон по площади в точке падения.
	const RADIUS := 2.2
	var zone
	var from := Vector3.ZERO
	var to := Vector3.ZERO
	var flight := 1.3
	var damage := 10.0
	var _t := 0.0
	var _mesh: MeshInstance3D
	func _ready() -> void:
		_mesh = U.prim("sphere", self, Vector3.ZERO, Vector3(0.9, 0.75, 0.85), Color(0.42, 0.38, 0.33), 0.95)
		global_position = from
	func _process(delta: float) -> void:
		_t += delta
		var k := clampf(_t / flight, 0, 1)
		var p := from.lerp(to, k)
		p.y += sin(k * PI) * 5.0
		global_position = p
		_mesh.rotation += Vector3(delta * 5, delta * 3, 0)
		if k >= 1.0:
			CombatFX.burst(zone.fx_root, to + Vector3.UP * 0.3, Color(0.5, 0.45, 0.4), 26, 6.0, 0.18, 0.6, Vector3.UP, 70, -12)
			zone.fx("ring", to, RADIUS, Color(0.6, 0.5, 0.4), 0.3)
			zone.shake(0.2)
			var pl = zone.player
			if pl and not pl.dead and U.flat_dist(pl.global_position, to) < RADIUS: pl.take_damage(damage, to)
			for m in zone.minions.duplicate():
				if is_instance_valid(m) and U.flat_dist(m.global_position, to) < RADIUS: m.take_damage(damage)
			queue_free()
