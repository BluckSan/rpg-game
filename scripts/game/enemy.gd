extends CharacterBody3D
class_name Enemy
## Враг: блуждание, погоня, атака, возврат домой (поводок), смерть с наградой. Босс — удар по области с предупреждением.

var kind: String
var def: Dictionary
var level := 1
var hp := 1.0
var max_hp := 1.0
var alive := true
var radius := 0.5
var home := Vector3.ZERO
var on_death: Callable
var zone
var model: Node3D
var target: Node3D

var _wander_target := Vector3.ZERO
var _attack_timer := 0.0
var _wander_timer := 0.0
var _slow_timer := 0.0
var _slow_factor := 1.0
var _stun_timer := 0.0
var _boss_timer := 5.0
var _aggro := false
var _returning := false
var _anim := 0.0
var _lunge := 0.0
var _flash := 0.0
var _kb := Vector3.ZERO
var brain   # BossBrain для босса
var damage_mult := 1.0
var rank := "normal"   # normal | elite | rare | boss (мир)
var speed_mult := 1.0
var hits_taken := 0
var curse_timer := 0.0
var buffs := {}             # v0.9.0: ослабления от поддержки {kind: {v, t, dur, icon, col, name, good}}
var taunt_target: Node3D = null
var ai := "melee"          # melee | ranged | charger | caster | swarm | exploder | healer (DB.ENEMIES[kind].ai)
var affixes: Array = []     # аффиксы элит/редких (AFFIXES)
var armor_mult := 1.0       # «Каменнокожий»
var res_bonus := 0.0        # «Заговорённый»: + к сопротивлениям
var busy := false           # особое действие (рывок, взрыв, заклинание) — обычный ИИ ждёт
var ability_cd := 2.0
var _aura_t := 1.0
var _summoned := false
var ability_log: Array = [] # для тестов: «charge», «cast», «heal», «explode», «summon»…
var model_base_scale := Vector3.ONE   # исходный масштаб модели (ранг, размер) — восстанавливается всегда
var net_id := 0             # v0.9.1: онлайн-номер (общий враг мира — сервер; враг подземелья — RaidSim)
var net_shared := false     # общий враг мира: здоровье, смерть и добыча — на сервере
var net_owner := true       # этот клиент ведёт ИИ врага (иначе — копия по позициям сервера)
var _npos := Vector3.INF
var _nyaw := 0.0
var _squash: Tween   # проклятие: +30% получаемого урона

## Физика: тело на слое 4 (враги), сталкивается только со статикой уровня (слой 1) — стены не проходит.
## Друг друга и героя не толкают (раздвигание — мягкое, в _move_towards). В подземелье путь — по навмешу.
const LAYER_ENEMY := 4
const LIFT := 0.3          # капсула приподнята — мелкие ступеньки/пандусы не цепляют
var _path: PackedVector3Array = PackedVector3Array()
var _path_i := 0
var _path_t := 0.0
var _path_goal := Vector3(INF, 0, INF)
var wall_hits := 0

var _dots: Array = []     # [урон за тик, тиков осталось, таймер, цвет] — яд/кровотечение/поджог

## Урон со временем: total за dur секунд (тик 0.5 с)
func add_dot(total: float, dur: float, c: Color, elem := "") -> void:
	if not alive: return
	var ticks := maxi(1, int(dur / 0.5))
	if _dots.size() >= 4: _dots.pop_front()
	if elem == "": elem = "poison" if c.g > c.r else ("fire" if c.g > 0.3 else "phys")
	_dots.append([total / ticks, ticks, 0.5, c, elem])

func curse(t: float) -> void:
	curse_timer = maxf(curse_timer, t)
	if model: CombatFX.burst(zone.fx_root, global_position + Vector3.UP * 1.5, Color(0.6, 0.3, 0.9), 16, 2.0, 0.1, 0.6, Vector3.UP, 180, 0.5)

static func spawn(z, k: String, lvl: int, pos: Vector3, parent: Node) -> Enemy:
	var e := Enemy.new()
	e.zone = z
	e.kind = k
	e.def = DB.ENEMIES[k]
	e.level = lvl
	e.ai = String(e.def.get("ai", "ranged" if e.def.ranged else "melee"))
	e.radius = e.def.radius
	e.max_hp = e.def.hp * Combat.enemy_hp_mult(lvl)
	e.hp = e.max_hp
	e.home = pos
	e._wander_target = pos
	e.collision_layer = LAYER_ENEMY
	e.collision_mask = 1
	e.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	e.safe_margin = 0.02
	var cs := CollisionShape3D.new(); cs.name = "Body"
	var cap := CapsuleShape3D.new()
	cap.radius = clampf(e.radius * 0.8, 0.3, 1.6)
	cap.height = maxf(cap.radius * 2.0 + 0.2, 1.4 if not e.def.boss else 2.6)
	cs.shape = cap; cs.position = Vector3(0, LIFT + cap.height / 2.0, 0)
	e.add_child(cs)
	parent.add_child(e)
	e.global_position = Vector3(pos.x, z.ground_y(pos), pos.z)
	e.rotation.y = randf() * TAU
	e._build_model()
	if e.model: e.model_base_scale = e.model.scale
	if not e.def.boss: U.set_view_range(e, Game.view_distance * 0.85)
	if e.def.boss:
		e.brain = WardenBrain.new() if k == "warden" else BossBrain.new()
		e.brain.setup(e)
	z.enemies.append(e)
	return e

var display_name: String:
	get:
		var pre := ""
		if not affixes.is_empty() and rank == "elite": pre = String(AFFIXES[affixes[0]].name) + " "
		return ("★ " if rank == "elite" else ("◆ " if rank == "rare" else "")) + pre + "%s (%d)" % [def.name, level]

func affix_text() -> String:
	var a := []
	for x in affixes: a.append(AFFIXES[x].name)
	return ", ".join(a)

func add_affix(x: String) -> void:
	if affixes.has(x) or not AFFIXES.has(x): return
	affixes.append(x)
	match x:
		"fast": speed_mult *= 1.3
		"stone": armor_mult *= 2.0
		"warded": res_bonus += 25.0

## Аффиксы элит (1) и редких (2): видны в имени и на табличке
const AFFIXES := {
	"fast": {"name": "Стремительный", "desc": "быстрее на 30%"},
	"stone": {"name": "Каменнокожий", "desc": "броня ×2"},
	"vampire": {"name": "Вампирический", "desc": "лечится от своих ударов"},
	"explosive": {"name": "Взрывной", "desc": "взрывается после гибели"},
	"burning": {"name": "Пылающий", "desc": "огненная аура"},
	"summoner": {"name": "Призыватель", "desc": "зовёт подмогу на половине здоровья"},
	"warded": {"name": "Заговорённый", "desc": "+25% ко всем сопротивлениям"},
}
const RANK_COLORS := {"elite": Color(1.0, 0.8, 0.3), "rare": Color(0.75, 0.45, 1.0), "boss": Color(1.0, 0.35, 0.25)}

## Ранг в открытом мире: элита (×2 здоровья), редкий именной (×3,5), босс зоны (имя). Больше урона, опыта и добычи (Loot.drop_for).
func make_rank(r: String, title := "", fixed_aff = null) -> void:
	rank = r
	def = def.duplicate()
	var hp_k := 1.0; var dmg_k := 1.0; var xp_k := 1.0; var sc := 1.0
	match r:
		"elite": hp_k = 2.0; dmg_k = 1.3; xp_k = 2.5; sc = 1.18
		"rare": hp_k = 3.5; dmg_k = 1.5; xp_k = 5.0; sc = 1.32
		"boss": hp_k = 1.0; dmg_k = 1.0; xp_k = 1.5; sc = 1.0
	if title != "": def.name = title
	if fixed_aff is Array:   # онлайн: аффиксы выбрал сервер — одинаковые у всех игроков
		for x in fixed_aff: if AFFIXES.has(str(x)): add_affix(str(x))
	elif r in ["elite", "rare"]:
		var pool: Array = AFFIXES.keys()
		pool.shuffle()
		for i in (1 if r == "elite" else 2): add_affix(pool[i])
	def.xp = float(def.xp) * xp_k
	max_hp *= hp_k; hp = max_hp
	damage_mult *= dmg_k
	if model and sc != 1.0:
		model_base_scale *= sc
		model.scale = model_base_scale
	if r != "normal":
		var ring := MeshInstance3D.new(); ring.name = "RankRing"
		var tm := TorusMesh.new(); tm.inner_radius = radius * 1.1 * sc; tm.outer_radius = radius * 1.1 * sc + 0.12
		tm.rings = 32; tm.ring_segments = 6
		ring.mesh = tm
		var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = RANK_COLORS.get(r, Color.WHITE); m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; m.albedo_color.a = 0.8
		ring.material_override = m
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.scale = Vector3(1, 0.15, 1)
		add_child(ring); ring.position = Vector3(0, 0.08, 0)

func _damage() -> float:
	var pl := 1
	if zone and zone.player: pl = int(zone.player.data["level"])
	var wk: float = 1.0 - float(buffs.weaken.v) if buffs.has("weaken") else 1.0
	return def.dmg * Combat.enemy_dmg_mult(level) * damage_mult * Combat.enemy_dmg_factor(level, pl) * wk

func _build_model() -> void:
	match kind:
		"slime":
			model = MobModel.new(); add_child(model)
			model.setup("slime", {"scale": 1.0 + (level - 1) * 0.04})
			model.walk_ref = 1.2; model.run_ref = 2.5
		"wolf":
			model = MobModel.new(); add_child(model)
			model.setup("wolf", {"tint": Color(0.82, 0.78, 0.72)})
			model.walk_ref = 2.0; model.run_ref = 5.5
		"skeleton", "skeleton_archer":
			model = MobModel.new(); add_child(model)
			var archer: bool = def.ranged
			model.setup("skeleton", {"tint": Color(0.82, 0.8, 0.74) if archer else Color(0.95, 0.92, 0.85), "emission": Color(0.3, 0.9, 1.0)})
			model.walk_ref = 2.0; model.run_ref = 4.0
			if archer:
				model.attach("R.DownLeg.001", "props/bow", Vector3(0, 0.12, 0), Vector3(0, 0, 0), 0.5)
			else:
				model.attach("R.DownLeg.001", "props/sword2", Vector3(0, 0.1, 0), Vector3(180, 0, 0), 0.36)
				model.attach("L.DownLeg.001", "props/shield_round", Vector3(0, 0.1, 0), Vector3(0, 90, 0), 0.22)
		"ether_guard":
			model = MobModel.new(); add_child(model)
			model.setup("skeleton", {"tint": Color(0.55, 0.45, 0.85), "emission": Color(0.75, 0.4, 1.0), "scale": 1.15})
			model.walk_ref = 2.0; model.run_ref = 4.0
			model.attach("R.DownLeg.001", "props/sword2", Vector3(0, 0.1, 0), Vector3(180, 0, 0), 0.42)
			model.attach("L.DownLeg.001", "props/shield_round", Vector3(0, 0.1, 0), Vector3(0, 90, 0), 0.26)
		"goblin", "troll", "warden":
			model = CharVisual.new(); add_child(model)
			model.build({}, "warrior", "", kind)
			if kind == "warden": model._build_fx("embers", Color(0.7, 0.4, 1.0), model)
		_:
			model = MobModel.new(); add_child(model)
			var mk: String = def.get("model", "slime")
			var opts := {"scale": float(def.get("model_scale", 1.0))}
			if def.has("tint"): opts["tint"] = def.tint
			if def.has("emission"): opts["emission"] = def.emission
			model.setup(mk, opts)
			model.walk_ref = maxf(1.0, def.speed * 0.6); model.run_ref = maxf(2.0, def.speed * 1.3)

## Точка прицеливания (центр тела) — для снарядов героя
func aim_point() -> Vector3:
	return global_position + Vector3.UP * body_height() * 0.5

func body_height() -> float:
	return clampf(radius * 2.6 * model_base_scale.y, 0.8, 6.0) if not def.boss else clampf(radius * 2.6, 2.5, 6.0)

func _model_action(a: String) -> void:
	if model and model.has_method("play_action"): model.play_action(a)

## Урон от героя (и его призывов): броня/сопротивления/разница уровней — Combat. elem "true" — без снижения.
## Возвращает фактический урон.
func take_damage(dmg: float, crit: bool, elem := "phys") -> float:
	if not alive: return 0.0
	if brain and brain.invulnerable: 
		zone.float_text(global_position + Vector3.UP * 4.5, "Неуязвим", Color(0.8, 0.8, 0.8))
		return 0.0
	if curse_timer > 0: dmg *= 1.3
	if buffs.has("mark"): dmg *= 1.0 + float(buffs.mark.v)
	var p = zone.player if zone else null
	if elem != "true" and p != null and "stats" in p and p.stats is Dictionary and not p.stats.is_empty():
		dmg *= Combat.player_vs_enemy(self, elem, int(p.data["level"]), float(p.stats.get("pen", 0.0)), float(p.stats.get("resred", 0.0)), float(p.stats.get("pen_flat", 0.0)))
	if net_shared:
		Net.wm_hit(net_id, dmg)   # здоровье — на сервере (WorldSim); здесь — только предсказание
		hp = maxf(1.0, hp - dmg)
	else:
		hp -= dmg
	hits_taken += 1
	_flash = 0.12
	_aggro = true; _returning = false
	if model is MobModel: model.hit_react()
	elif model is CharVisual and not model.is_acting() and not def.boss: model.play_action("hit")
	zone.damage_number(global_position + Vector3.UP * (4.5 if def.boss else 2.0), dmg, crit, false, elem)
	if hp <= 0 and not net_shared: _die()
	return dmg

## v0.9.2: общий враг мира онлайн — ИИ целиком на сервере (WorldSim), клиент только показывает
func set_net(nid: int, _own := false) -> void:
	net_id = nid; net_shared = true
	net_owner = false
	busy = false
	if def.boss and not (self is NetEnemy): brain = RaidBrain.new()   # фаза/каст/ярость — от сервера (событие st)
	_npos = global_position; _nyaw = rotation.y
	_nbuf.clear()

const INTERP_DELAY := 0.12   # показ с задержкой между двумя снимками сервера (10 Гц)
var _nbuf: Array = []        # [время, позиция, поворот]

func net_pos(p: Vector3, yaw: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	p.y = zone.ground_y(p) if zone else p.y
	_nbuf.append([now, p, yaw])
	if _nbuf.size() > 6: _nbuf.pop_front()
	_npos = p; _nyaw = yaw

## Копия врага сервера: интерполяция по буферу снимков, высота — по рельефу зоны
func _puppet(delta: float) -> void:
	if _npos == Vector3.INF: return
	var rt := Time.get_ticks_msec() / 1000.0 - INTERP_DELAY
	var goal := _npos; var gyaw := _nyaw
	if _nbuf.size() >= 2:
		var i := _nbuf.size() - 1
		while i > 0 and float(_nbuf[i - 1][0]) > rt: i -= 1
		if i > 0:
			var a: Array = _nbuf[i - 1]; var b: Array = _nbuf[i]
			var k := clampf((rt - float(a[0])) / maxf(0.001, float(b[0]) - float(a[0])), 0.0, 1.0)
			goal = (a[1] as Vector3).lerp(b[1], k); gyaw = lerp_angle(float(a[2]), float(b[2]), k)
		else:
			goal = _nbuf[0][1]; gyaw = float(_nbuf[0][2])
	if goal.distance_to(global_position) > 25.0: global_position = goal
	else: global_position = global_position.lerp(goal, minf(1.0, delta * 15.0))
	rotation.y = lerp_angle(rotation.y, gyaw, minf(1.0, delta * 12.0))

## Атака по команде сервера: только анимация и снаряд для вида (урон решает сервер)
func net_attack(ranged: bool, target_pos: Vector3, a := "") -> void:
	if not alive: return
	_lunge = 0.25
	match a:
		"slam", "charge", "rock", "summon", "breath", "spores", "nova", "roar": _model_action("attack2" if a != "rock" else "throw")
		"cast": _model_action("attack")
		_: _model_action("attack" if randf() < 0.7 else "attack2")
	if ranged and def.has("proj") and target_pos != Vector3.INF:
		var origin := global_position + Vector3.UP * float(def.get("shot_h", 1.3))
		Tele.bolt(zone.fx_root, origin, target_pos + Vector3.UP, def.get("proj", Color(0.6, 0.9, 1)), 0.22, 0.07)

## Смерть по решению сервера: опыт и счётчики — участникам; добычу сервер кладёт на землю сам
func net_die(participant: bool, xp := -1) -> void:
	if not alive: return
	hp = 0
	alive = false
	zone.enemies.erase(self)
	var p: Player = zone.player
	if p and participant:
		p.data["kills"] += 1
		if xp >= 0: p.gain_xp(xp)   # v0.9.3: число опыта решает сервер
		if on_death.is_valid(): on_death.call(self)
	CombatFX.burst(zone.fx_root, global_position + Vector3.UP * (2.0 if def.boss else 0.8), Color(0.85, 0.85, 1.0, 0.7), 16 if not def.boss else 40, 2.5, 0.16, 0.9, Vector3.UP, 50, 1.5)
	if model and model.has_method("set_dead"): model.set_dead(true)
	var tw := create_tween()
	tw.tween_interval(2.4 if def.boss else 1.8)
	tw.tween_property(self, "position:y", -1.2 if not def.boss else -3.0, 1.2)
	tw.tween_callback(queue_free)

## Отбрасывание при попадании (босс почти не сдвигается) + «упругий» отклик модели
func knockback(dir: Vector3, force: float) -> void:
	if not alive: return
	if net_shared: Net.wm_cc(net_id, "kb", force, 0.0, dir)
	var k := 0.08 if def.boss else (0.5 if kind in ["troll", "goblin"] else 1.0)
	_kb += U.flat(dir).normalized() * force * k
	# «упругий» отклик — только у обычных врагов и всегда от исходного масштаба (раньше масштаб брался
	# посреди прошлого отклика и при частых ударах босс сплющивался). Боссы не деформируются вовсе.
	if model and not def.boss:
		if _squash and _squash.is_valid(): _squash.kill()
		var base := model_base_scale
		model.scale = base
		_squash = create_tween()
		_squash.tween_property(model, "scale", Vector3(base.x * 1.06, base.y * 0.95, base.z * 1.06), 0.05)
		_squash.tween_property(model, "scale", base, 0.12)

## v0.9.0: метка (+получаемый урон), ослабление (−наносимый урон), замедление, провокация
func add_debuff(k: String, v: float, dur: float) -> void:
	var cur: Dictionary = buffs.get(k, {})
	var nv := maxf(v, float(cur.get("v", 0.0)))
	buffs[k] = {"id": k, "v": nv, "t": maxf(dur, float(cur.get("t", 0.0))), "dur": dur, "icon": Support.debuff_icon(k), "col": Support.debuff_color(k),
		"name": Support.debuff_name(k), "good": false, "st": mini(9, int(cur.get("st", 0)) + 1)}
	if k == "slow": slow(1.0 - nv, dur)
	if k == "weaken" and net_shared: Net.wm_cc(net_id, "weaken", nv, dur, Vector3.ZERO)
	if k == "taunt":
		_aggro = true
		if net_shared: Net.wm_cc(net_id, "taunt", 1.0, dur, Vector3.ZERO)

func _tick_debuffs(delta: float) -> void:
	for k in buffs.keys():
		buffs[k].t = float(buffs[k].t) - delta
		if buffs[k].t <= 0.0:
			buffs.erase(k)
			if k == "taunt": taunt_target = null

func slow(factor: float, t: float) -> void:
	_slow_factor = factor; _slow_timer = t
	if net_shared: Net.wm_cc(net_id, "slow", factor, t, Vector3.ZERO)

func stun(t: float) -> void:
	_stun_timer = t * 0.3 if def.boss else t
	if net_shared: Net.wm_cc(net_id, "stun", 0.0, t, Vector3.ZERO)

func _die() -> void:
	if net_shared: return   # общий враг погибает только по решению сервера (net_die)
	hp = 0
	alive = false
	zone.enemies.erase(self)
	var p: Player = zone.player
	if p:
		p.data["kills"] += 1
		var rk := "boss" if def.boss else str(rank)
		var sh: Array = Xp.shares(float(def.xp), level, rk, [int(p.data["level"])])
		p.gain_xp(Xp.personal(sh[0], p.get_meta("xp_st", {}) if p.has_meta("xp_st") else _xp_st(p), kind, Time.get_ticks_msec() / 1000.0, Xp.today()))
	Loot.drop_for(zone, self)
	# дымка/искры души при гибели
	CombatFX.burst(zone.fx_root, global_position + Vector3.UP * (2.0 if def.boss else 0.8), Color(0.85, 0.85, 1.0, 0.7), 16 if not def.boss else 40, 2.5, 0.16, 0.9, Vector3.UP, 50, 1.5)
	if on_death.is_valid(): on_death.call(self)
	if affixes.has("explosive"): _death_blast(global_position, _damage() * 1.6)
	if model and model.has_method("set_dead"): model.set_dead(true)
	# тело остаётся на земле, затем уходит под землю
	var tw := create_tween()
	tw.tween_interval(2.4 if def.boss else 1.8)
	tw.tween_property(self, "position:y", -1.2 if not def.boss else -3.0, 1.2)
	tw.tween_callback(queue_free)

func _choose_target() -> Node3D:
	if buffs.has("taunt") and taunt_target != null and is_instance_valid(taunt_target) and not ("dead" in taunt_target and taunt_target.dead): return taunt_target
	var best: Node3D = null
	var best_d: float = def.aggro * (2.2 if _aggro else 1.0)
	var p: Player = zone.player
	if p and not p.dead:
		var d := U.flat_dist(p.global_position, global_position)
		if d < best_d:
			best_d = d; best = p
	for m in zone.minions:
		var d := U.flat_dist(m.global_position, global_position)
		if d < best_d * 0.8:
			best_d = d; best = m
	return best

func _process(delta: float) -> void:
	if not alive: return
	if net_shared:
		if not buffs.is_empty(): _tick_debuffs(delta)
		if brain is RaidBrain: brain.step(delta)
		_puppet(delta)
		_animate(delta)
		return
	if _attack_timer > 0: _attack_timer -= delta
	if curse_timer > 0: curse_timer -= delta
	if not buffs.is_empty(): _tick_debuffs(delta)
	if not _dots.is_empty():
		for d in _dots.duplicate():
			d[2] -= delta
			if d[2] <= 0:
				d[2] = 0.5; d[1] -= 1
				if model: CombatFX.burst(zone.fx_root, global_position + Vector3.UP * 1.2, d[3], 5, 1.5, 0.08, 0.4, Vector3.UP, 120, 0.3)
				take_damage(d[0], false, d[4] if d.size() > 4 else "phys")
				if not alive: return
				if d[1] <= 0: _dots.erase(d)
	if _slow_timer > 0:
		_slow_timer -= delta
		if _slow_timer <= 0: _slow_factor = 1.0
	_animate(delta)
	if _kb.length_squared() > 0.01:
		slide_move(_kb * delta)
		_kb = _kb * exp(-delta * 9.0)
	if brain:
		brain.update(delta)
		if brain.busy: return
	if _stun_timer > 0:
		_stun_timer -= delta
		return
	if busy: return
	if ability_cd > 0: ability_cd -= delta
	if not affixes.is_empty(): _affix_tick(delta)
	var speed: float = def.speed * _slow_factor * speed_mult
	var home_dist := U.flat_dist(global_position, home)
	if home_dist > (22.0 if def.boss else 28.0):
		_returning = true; _aggro = false
	if _returning:
		_move_towards(home, speed * 1.5, delta)
		hp = minf(max_hp, hp + max_hp * 0.25 * delta)
		if home_dist < 1.5: _returning = false
		return
	target = _choose_target()
	if target:
		_aggro = true
		var to := U.flat(target.global_position - global_position)
		_face(to, delta)
		if _role_tick(to, speed, delta): return
		if to.length() > def.range * 0.9:
			_move_towards(target.global_position, speed, delta)
		elif _attack_timer <= 0:
			_attack_timer = def.interval / speed_mult
			_attack()
	else:
		_aggro = false
		_wander_timer -= delta
		if _wander_timer <= 0:
			_wander_timer = randf_range(2.5, 6.0)
			var r := Vector2.from_angle(randf() * TAU) * randf() * 6.0
			_wander_target = home + Vector3(r.x, 0, r.y)
		if U.flat_dist(_wander_target, global_position) > 0.5:
			_move_towards(_wander_target, speed * 0.4, delta)

func _attack() -> void:
	_anim = 0; _lunge = 0.25
	if ai == "caster":
		_cast_aoe(target); return
	if ai == "exploder":
		_fuse(); return
	_model_action("attack" if randf() < 0.7 else "attack2")
	if def.ranged:
		var origin := global_position + Vector3.UP * float(def.get("shot_h", 1.3)) + global_basis.z * 0.4
		# в 3D — в центр цели (герой на склоне выше/ниже)
		var tp: Vector3 = target.global_position + Vector3.UP * 1.0
		var dir := (tp - origin).normalized()
		if Vector2(dir.x, dir.z).length() < 0.2: dir = U.flat(tp - origin).normalized()
		Projectile.fire(zone, origin, dir, float(def.get("proj_speed", 13.0)), def.range + 4, def.get("proj", Color(0.6, 0.9, 1)), 0.25, false, Callable(), _damage())
	else:
		var t := target
		await get_tree().create_timer(0.25 if not def.boss else 0.45, false).timeout
		if not alive or t == null or not is_instance_valid(t): return
		if U.flat_dist(t.global_position, global_position) <= def.range + 0.6:
			_deal_to(t, _damage())

func _deal_to(t: Node3D, dmg: float) -> void:
	if t == null or not is_instance_valid(t): return
	if affixes.has("vampire") and alive:
		hp = minf(max_hp, hp + dmg * 0.5)
	if t is Player: t.take_damage(dmg, global_position)
	elif t.has_method("take_damage"): t.take_damage(dmg)

## Движение со столкновениями: скольжение вдоль стен (две итерации), высота — по рельефу зоны
func slide_move(motion: Vector3) -> void:
	motion.y = 0
	for i in 3:
		if motion.length_squared() < 0.000001: break
		var col := move_and_collide(motion)
		if col == null: break
		wall_hits += 1
		var n := col.get_normal(); n.y = 0
		if n.length_squared() < 0.0001: break
		motion = col.get_remainder().slide(n.normalized())
		motion.y = 0
	global_position.y = zone.ground_y(global_position)

## Следующая точка пути: в подземелье — по навмешу (обход стен), иначе — напрямую
func _steer_point(p: Vector3, delta: float) -> Vector3:
	var b = zone.builder if zone else null
	if b == null or not b.has_method("nav_ready") or not b.nav_ready(): return p
	_path_t -= delta
	if _path_t <= 0.0 or U.flat_dist(p, _path_goal) > 1.0 or _path_i >= _path.size():
		_path_t = 0.45
		_path_goal = p
		_path = NavigationServer3D.map_get_path(b.nav_map(), global_position, p, true)
		_path_i = 1
	while _path_i < _path.size() - 1 and U.flat_dist(global_position, _path[_path_i]) < 0.5: _path_i += 1
	if _path.size() < 2: return p
	return _path[mini(_path_i, _path.size() - 1)]

func _move_towards(p: Vector3, speed: float, delta: float) -> void:
	var d := U.flat(p - global_position)
	if d.length_squared() < 0.01: return
	var face := d
	d = U.flat(_steer_point(p, delta) - global_position)
	if d.length_squared() < 0.0001: d = face
	var step := d.normalized() * speed * delta
	for o in zone.enemies:
		if o == self: continue
		var away := U.flat(global_position - o.global_position)
		var mn: float = radius + o.radius
		if away.length_squared() < mn * mn and away.length_squared() > 0.0001:
			step += away.normalized() * delta * 2.0
	slide_move(step)
	_face(d if d.length_squared() > 0.01 else face, delta)

func _face(d: Vector3, delta: float) -> void:
	if d.length_squared() < 0.001: return
	rotation.y = lerp_angle(rotation.y, atan2(d.x, d.z), minf(1.0, delta * 8))

func _animate(delta: float) -> void:
	if _lunge > 0: _lunge -= delta
	if _flash > 0: _flash -= delta
	if model:
		model.rotation.z = sin(Time.get_ticks_msec() * 0.02) * 0.14 if _stun_timer > 0 else 0.0

# ================= роли врагов (v0.5.1) =================
## Особое поведение по роли; true — кадр занят (обычная атака/движение пропускаются)
func _role_tick(to: Vector3, speed: float, delta: float) -> bool:
	var d := to.length()
	match ai:
		"charger":
			if ability_cd <= 0 and d > 4.5 and d < 14.0:
				_charge(target); return true
		"healer":
			if ability_cd <= 0 and _heal_ally(): return true
			if d < def.range * 0.45:   # держит дистанцию
				_move_towards(global_position - to.normalized() * 4.0, speed * 0.8, delta); return true
		"caster", "ranged":
			if d < def.range * 0.35 and not def.boss:
				_move_towards(global_position - to.normalized() * 4.0, speed * 0.7, delta); return true
	return false

## Таран: красная полоса-предупреждение, разгон, удар с отбрасыванием (как у тролля, но короче)
func _charge(t) -> void:
	busy = true; ability_cd = 7.0
	ability_log.append("charge")
	var start := global_position
	var dir := U.flat(t.global_position - start).normalized()
	var length := clampf(U.flat_dist(t.global_position, start) + 3.0, 6.0, 13.0)
	var tele := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(radius * 2.2 + 0.6, 0.02, length)
	tele.mesh = bm
	tele.material_override = U.fx_mat(Color(1, 0.1, 0.05, 0.35))
	tele.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	zone.fx_root.add_child(tele)
	tele.global_position = start + dir * length / 2 + Vector3.UP * 0.06
	tele.rotation.y = atan2(dir.x, dir.z)
	rotation.y = atan2(dir.x, dir.z)
	_model_action("roar")
	await get_tree().create_timer(0.75, false).timeout
	tele.queue_free()
	if not alive: return
	_model_action("charge")
	var traveled := 0.0; var hit := false
	while traveled < length and alive:
		var dt := get_process_delta_time()
		await get_tree().process_frame
		if not is_instance_valid(self) or not alive: return
		var step := 13.0 * maxf(dt, 0.001)
		traveled += step
		slide_move(dir * step)
		var p = zone.player
		if not hit and p and not p.dead and U.flat_dist(p.global_position, global_position) < radius + 1.0:
			hit = true
			p.take_damage(_damage() * 1.5, global_position)
			if p.invuln <= 0: p.knockback(dir, 6.0)
	busy = false

## Заклинание по площади у цели: круг-предупреждение 1.1 с, затем удар стихией
func _cast_aoe(t) -> void:
	if t == null or not is_instance_valid(t): return
	busy = true
	ability_log.append("cast")
	_model_action("cast")
	var c: Vector3 = t.global_position
	c.y = zone.ground_y(c)
	var r := 2.4
	var col: Color = def.get("proj", Color(0.8, 0.4, 1.0))
	zone.fx("telegraph", c, r, Color.RED, 1.1)
	await get_tree().create_timer(1.1, false).timeout
	if not is_instance_valid(self): return
	busy = false
	if not alive: return
	zone.fx("burst", c + Vector3.UP * 0.4, r, col, 0.4)
	zone.fx("ring", c, r, col, 0.3)
	var p = zone.player
	if p and not p.dead and U.flat_dist(p.global_position, c) < r and U.los(self, c, p.global_position): p.take_damage(_damage() * 1.3, c)
	for m in zone.minions.duplicate():
		if is_instance_valid(m) and U.flat_dist(m.global_position, c) < r: m.take_damage(_damage() * 1.3)

## Взрывун: подбегает, шипит 0.9 с (круг) и взрывается, погибая
func _fuse() -> void:
	busy = true
	ability_log.append("explode")
	_model_action("roar")
	zone.fx("telegraph", global_position, 2.8, Color.RED, 0.9)
	await get_tree().create_timer(0.9, false).timeout
	if not is_instance_valid(self) or not alive: return
	_death_blast(global_position, _damage(), 2.8, false)
	busy = false
	hp = 0; _die()

func _death_blast(c: Vector3, dmg: float, r := 3.0, delayed := true) -> void:
	var z = zone
	if delayed:
		z.fx("telegraph", c, r, Color.RED, 1.0)
		await z.get_tree().create_timer(1.0, false).timeout
	z.fx("burst", c + Vector3.UP * 0.6, r, Color(1, 0.55, 0.2), 0.45)
	z.shake(0.25)
	var p = z.player
	if p and not p.dead and U.flat_dist(p.global_position, c) < r and U.los(z.player, c, p.global_position): p.take_damage(dmg, c)

## Шаман: лечит самого раненого союзника рядом (25% здоровья); true — лечение было
func _heal_ally() -> bool:
	var best = null; var bf := 0.8
	for o in zone.enemies:
		if not is_instance_valid(o) or not o.alive or o.def.boss: continue
		if U.flat_dist(o.global_position, global_position) > 12.0: continue
		var f: float = o.hp / maxf(1.0, o.max_hp)
		if f < bf: bf = f; best = o
	if best == null: return false
	ability_cd = 5.0
	ability_log.append("heal")
	_model_action("cast")
	var amt: float = best.max_hp * 0.25
	best.hp = minf(best.max_hp, best.hp + amt)
	Tele.bolt(zone.fx_root, global_position + Vector3.UP * 1.4, best.global_position + Vector3.UP * 1.0, Color(0.4, 1.0, 0.5), 0.3, 0.06)
	zone.float_text(best.global_position + Vector3.UP * 2.2, "+%d" % int(amt), Color(0.4, 1.0, 0.5))
	return true

func _affix_tick(delta: float) -> void:
	if affixes.has("burning"):
		_aura_t -= delta
		if _aura_t <= 0:
			_aura_t = 1.0
			var p = zone.player
			if p and not p.dead and U.flat_dist(p.global_position, global_position) < 3.2:
				p.take_damage(_damage() * 0.3, global_position)
			CombatFX.burst(zone.fx_root, global_position + Vector3.UP * 0.6, Color(1, 0.45, 0.1), 8, 2.5, 0.12, 0.5, Vector3.UP, 120, 0.5)
	if affixes.has("summoner") and not _summoned and hp < max_hp * 0.5:
		_summoned = true
		ability_log.append("summon")
		var mk: String = def.get("minion", kind)
		for i in 2:
			var pos := global_position + Vector3(-2.0 if i == 0 else 2.0, 0, randf_range(-1, 1))
			var a := Enemy.spawn(zone, mk, maxi(1, level - 2), pos, get_parent())
			a._aggro = true; a.home = home
			zone.fx("burst", pos + Vector3.UP * 0.5, 1.2, Color(0.6, 0.3, 0.9), 0.4)


func _xp_st(p: Node) -> Dictionary:
	var st := {}
	p.set_meta("xp_st", st)
	return st
