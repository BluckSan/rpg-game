extends Enemy
class_name NetEnemy
## Враг группового подземелья на клиенте: модель, анимации и попадания — как у обычного Enemy,
## но ИИ, здоровье и смерть — на сервере (RaidSim). Удары героя уходят на сервер (RaidClient.send_hit),
## позиция плавно следует за снимками сервера.

var srv_pos := Vector3.ZERO
var srv_yaw := 0.0
var client          # RaidClient
var role := "trash"
var _got_snap := false

static func create(z, e: Dictionary, parent: Node, rc) -> NetEnemy:
	var ne := NetEnemy.new()
	ne.zone = z; ne.client = rc
	ne.kind = str(e.k); ne.def = DB.ENEMIES[ne.kind]
	ne.level = int(e.lvl); ne.net_id = int(e.id); ne.role = str(e.get("r", "trash"))
	ne.ai = "melee"; ne.radius = float(ne.def.radius)
	ne.max_hp = float(e.mhp); ne.hp = float(e.hp)
	ne.collision_layer = LAYER_ENEMY; ne.collision_mask = 0
	var cs := CollisionShape3D.new(); cs.name = "Body"
	var cap := CapsuleShape3D.new()
	cap.radius = clampf(ne.radius * 0.8, 0.3, 1.6)
	cap.height = maxf(cap.radius * 2.0 + 0.2, 1.4 if not ne.def.boss else 2.6)
	cs.shape = cap; cs.position = Vector3(0, LIFT + cap.height / 2.0, 0)
	ne.add_child(cs)
	parent.add_child(ne)
	ne.srv_pos = Vector3(float(e.x), 0, float(e.z))
	ne.global_position = Vector3(ne.srv_pos.x, z.ground_y(ne.srv_pos), ne.srv_pos.z)
	ne.rotation.y = PI
	ne.srv_yaw = PI
	ne._build_model()
	if ne.model: ne.model_base_scale = ne.model.scale
	if bool(e.get("el", false)):
		ne.make_rank("elite")
		ne.max_hp = float(e.mhp); ne.hp = float(e.hp)
	if ne.def.boss: ne.brain = rc.brain
	z.enemies.append(ne)
	return ne

func net_update(pos: Vector3, yaw: float, hp_v: float) -> void:
	srv_pos = pos; srv_yaw = yaw; hp = hp_v
	if not _got_snap:
		_got_snap = true
		global_position = Vector3(pos.x, zone.ground_y(pos), pos.z)

func take_damage(dmg: float, crit: bool, elem := "phys") -> float:
	if not alive: return 0.0
	if brain and brain.invulnerable:
		zone.float_text(global_position + Vector3.UP * 4.5, "Неуязвим", Color(0.8, 0.8, 0.8))
		return 0.0
	if curse_timer > 0: dmg *= 1.3
	var p = zone.player if zone else null
	var skill := false
	if elem != "true" and p != null and "stats" in p and p.stats is Dictionary and not p.stats.is_empty():
		dmg *= Combat.player_vs_enemy(self, elem, int(p.data["level"]), float(p.stats.get("pen", 0.0)), float(p.stats.get("resred", 0.0)), float(p.stats.get("pen_flat", 0.0)))
	if p != null and "last_skill_t" in p: skill = Time.get_ticks_msec() / 1000.0 - float(p.last_skill_t) < 2.0
	hits_taken += 1
	_flash = 0.12
	if model is MobModel: model.hit_react()
	zone.damage_number(global_position + Vector3.UP * (4.5 if def.boss else 2.0), dmg, crit, false, elem)
	if client: client.send_hit(net_id, dmg, skill)
	hp = maxf(1.0, hp - dmg)   # предсказание; сервер поправит снимком и сам решит, когда враг погибнет
	return dmg

func knockback(_dir: Vector3, _force: float) -> void: pass
func stun(_t: float) -> void: pass
func slow(_f: float, _t: float) -> void: pass

## Смерть по команде сервера (награда приходит отдельным событием)
func net_die(quiet := false, _xp := -1) -> void:
	if not alive: return
	alive = false; hp = 0
	zone.enemies.erase(self)
	if quiet:
		queue_free(); return
	CombatFX.burst(zone.fx_root, global_position + Vector3.UP * (2.0 if def.boss else 0.8), Color(0.85, 0.85, 1.0, 0.7), 16 if not def.boss else 40, 2.5, 0.16, 0.9, Vector3.UP, 50, 1.5)
	if model and model.has_method("set_dead"): model.set_dead(true)
	var tw := create_tween()
	tw.tween_interval(2.4 if def.boss else 1.8)
	tw.tween_property(self, "position:y", -1.2 if not def.boss else -3.0, 1.2)
	tw.tween_callback(queue_free)

func net_attack(ranged: bool, target_pos: Vector3, _a := "") -> void:
	if not alive: return
	_lunge = 0.25
	_model_action("attack" if randf() < 0.7 else "attack2")
	if ranged and def.has("proj"):
		var origin := global_position + Vector3.UP * float(def.get("shot_h", 1.3))
		Tele.bolt(zone.fx_root, origin, target_pos + Vector3.UP, def.get("proj", Color(0.6, 0.9, 1)), 0.22, 0.07)

func _die() -> void: pass   # погибает только по команде сервера

## v0.9.0: ослабления от сервера (метка, ослабление, замедление, провокация): {вид: [величина, осталось]}
func net_debuffs(l: Dictionary) -> void:
	buffs.clear()
	for k in l:
		var d: Array = l[k]
		buffs[k] = {"id": k, "v": float(d[0]), "t": float(d[1]), "dur": maxf(float(d[1]), float(d[2]) if d.size() > 2 else float(d[1])),
			"icon": Support.debuff_icon(k), "col": Support.debuff_color(k), "name": Support.debuff_name(k), "good": false}
		if d.size() > 3: buffs[k]["st"] = int(d[3])

func _process(delta: float) -> void:
	if not alive: return
	if curse_timer > 0: curse_timer -= delta
	if not buffs.is_empty(): _tick_debuffs(delta)
	if not _dots.is_empty():
		for dd in _dots.duplicate():
			dd[2] -= delta
			if dd[2] <= 0:
				dd[2] = 0.5; dd[1] -= 1
				take_damage(dd[0], false, dd[4] if dd.size() > 4 else "phys")
				if not alive: return
				if dd[1] <= 0: _dots.erase(dd)
	_animate(delta)
	var cur := global_position
	var goal := Vector3(srv_pos.x, zone.ground_y(srv_pos), srv_pos.z)
	if cur.distance_to(goal) > 12.0: global_position = goal
	else: global_position = cur.lerp(goal, minf(1.0, delta * 8.0))
	rotation.y = lerp_angle(rotation.y, srv_yaw, minf(1.0, delta * 8.0))
