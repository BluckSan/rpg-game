extends RefCounted
class_name Support
## v0.9.0: умения поддержки (ветки «Знаменосец», «Хранитель чар», «Ловчий»).
## Описание умения: s.kind == "support", s.sup = {
##   tgt: "self" | "ally" (выбранный союзник, иначе — на себя) | "aura" (группа в радиусе, вкл. себя и призванных)
##        | "enemy" (выбранный враг / автонаведение) | "enemy_area" (враги в радиусе вокруг цели) | "self_area" (враги вокруг героя)
##   buff: {mods: [[стат, значение]], dur}   — через compute_stats, с потолками v0.8.0
##   heal / shield / hot / mana: доля макс. здоровья (маны) цели;   shield_dur
##   debuff: {kind: "mark"|"weaken"|"slow", v, dur};   taunt: секунды }
## Сила растёт с рангом умения (pow). Онлайн всё решает сервер (Net.c_support): кто в радиусе, перезарядка,
## величина по серверным характеристикам; клиент только показывает эффект и применяет присланное.

## Потолки поддержки (сверх потолков v0.8.0 на проценты)
const MARK_CAP := 0.25       # враг получает не больше +25% урона
const WEAKEN_CAP := 0.30     # враг наносит не меньше 70% урона
const SHIELD_CAP := 0.30     # щит — не больше 30% макс. здоровья
const SLOW_CAP := 0.6

## Величины с учётом ранга: {buff, heal, shield, shield_dur, hot, mana, debuff, taunt}
static func resolve(s: Dictionary) -> Dictionary:
	var sup: Dictionary = s.get("sup", {})
	var k: float = float(s.get("pow", 1.0))
	var out := {"tgt": str(sup.get("tgt", "self")), "radius": float(s.get("radius", 0.0)), "range": float(s.get("range", 0.0))}
	if sup.has("buff"):
		var mods := []
		for m in sup.buff.mods: mods.append([m[0], snappedf(float(m[1]) * k, 0.1)])
		out.buff = {"mods": mods, "dur": float(sup.buff.dur)}
	for key in ["heal", "hot", "mana"]:
		if sup.has(key): out[key] = float(sup[key]) * k
	if sup.has("shield"):
		out.shield = minf(SHIELD_CAP, float(sup.shield) * k)
		out.shield_dur = float(sup.get("shield_dur", 8.0))
	if sup.has("debuff"):
		var d: Dictionary = sup.debuff
		var cap: float = {"mark": MARK_CAP, "weaken": WEAKEN_CAP, "slow": SLOW_CAP}.get(str(d.kind), 0.3)
		out.debuff = {"kind": str(d.kind), "v": minf(cap, float(d.v) * k), "dur": float(d.dur)}
	if sup.has("taunt"): out.taunt = float(sup.taunt)
	return out

static func is_support(s) -> bool:
	return s != null and str(s.get("kind", "")) == "support"

static func targets_allies(s: Dictionary) -> bool:
	return str(s.get("sup", {}).get("tgt", "")) in ["self", "ally", "aura"]

## Запись баффа для героя/призванного (иконка, цвет, таймер)
static func make_buff(s: Dictionary, eff: Dictionary, src := "") -> Dictionary:
	var b := {"id": str(s.id), "name": str(s.name), "icon": UIK.SKILL_ICONS.get(s.id, "aura"), "col": s.color, "good": true, "src": src,
		"mods": [], "dur": 0.0, "t": 0.0}
	if eff.has("buff"): b.mods = eff.buff.mods; b.dur = float(eff.buff.dur)
	if eff.has("shield"): b.dur = maxf(b.dur, float(eff.shield_dur)); b["shield"] = true
	if eff.has("hot"): b.dur = maxf(b.dur, 6.0)
	b.t = b.dur
	b["desc"] = describe_eff(eff)
	return b

## v0.9.1: текст эффекта для подсказки по значку
static func describe_eff(eff: Dictionary) -> String:
	var parts := []
	if eff.has("buff"):
		for m in eff.buff.mods: parts.append(DB.describe_mod(m).strip_edges())
	if eff.has("shield"): parts.append("щит %d%% макс. здоровья" % roundi(float(eff.shield) * 100.0))
	if eff.has("hot"): parts.append("лечение %d%% здоровья за 6 с" % roundi(float(eff.hot) * 100.0))
	if eff.has("heal"): parts.append("мгновенно +%d%% здоровья" % roundi(float(eff.heal) * 100.0))
	if eff.has("mana"): parts.append("+%d%% маны" % roundi(float(eff.mana) * 100.0))
	return ", ".join(parts)

static func debuff_effect(kind: String, v: float) -> String:
	match kind:
		"mark": return "получает +%d%% урона" % roundi(v * 100.0)
		"weaken": return "наносит −%d%% урона" % roundi(v * 100.0)
		"slow": return "скорость −%d%%" % roundi(v * 100.0)
		"taunt": return "атакует только наложившего провокацию"
		"curse": return "получает +30% урона"
	return ""

## Подсказка по значку баффа/дебаффа: название, эффект, оставшееся время, наложения
static func describe_buff(b: Dictionary) -> String:
	var good: bool = bool(b.get("good", true))
	var nm := str(b.get("name", ""))
	var eff := str(b.get("desc", ""))
	if eff == "":
		if not good: eff = debuff_effect(str(b.get("id", "")), float(b.get("v", 0.0)))
		else:
			var mods: Array = b.get("mods", [])
			var p := []
			for m in mods: p.append(DB.describe_mod(m).strip_edges())
			if b.get("shield", false): p.append("поглощает урон")
			eff = ", ".join(p)
	if nm.contains(":") and not good: nm = nm.split(":")[0]
	if nm == "": nm = str(b.get("id", "Эффект"))
	var s := "[b][color=#%s]%s[/color][/b]  [color=#888]%s[/color]" % ["9adf7a" if good else "ff7a6a", nm, "бафф" if good else "дебафф"]
	if eff != "": s += "\n" + eff
	var t := float(b.get("t", -1.0))
	s += "\n[color=#cccccc]%s[/color]" % (("Осталось: %.1f с из %d с" % [maxf(0.0, t), roundi(float(b.get("dur", t)))]) if t >= 0.0 else "Без ограничения по времени")
	if int(b.get("st", 1)) > 1: s += "\n[color=#f2c46d]Наложений: %d[/color] [color=#888](время обновляется, действует сильнейшее)[/color]" % int(b.st)
	if str(b.get("src", "")) != "": s += "\n[color=#888]Источник: %s[/color]" % str(b.src)
	return s

static func debuff_icon(kind: String) -> String:
	return {"mark": "bullseye", "weaken": "broken-skull", "slow": "hourglass", "taunt": "shouting"}.get(kind, "cursed-star")
static func debuff_color(kind: String) -> Color:
	return {"mark": Color(1, 0.35, 0.3), "weaken": Color(0.7, 0.45, 1.0), "slow": Color(0.5, 0.8, 1.0), "taunt": Color(1, 0.7, 0.25)}.get(kind, Color.WHITE)
static func debuff_name(kind: String) -> String:
	return {"mark": "Метка: получает больше урона", "weaken": "Ослабление: наносит меньше урона", "slow": "Замедление", "taunt": "Провокация"}.get(kind, kind)

## Применить к своему герою (офлайн — сразу, онлайн — по команде сервера)
static func apply_to_player(p, s: Dictionary, eff: Dictionary, src := "") -> void:
	if p == null or p.dead: return
	var mhp: float = p.stats.max_hp
	if eff.has("heal"): p.heal(mhp * float(eff.heal))
	if eff.has("mana"): p.mp = minf(p.stats.max_mp, p.mp + p.stats.max_mp * float(eff.mana))
	if eff.has("shield"): p.shield_hp = maxf(p.shield_hp, mhp * float(eff.shield))
	if eff.has("hot"):
		p.hot_timer = 6.0; p.hot_rate = maxf(p.hot_rate if p.hot_timer > 0 else 0.0, mhp * float(eff.hot) / 6.0)
	if eff.has("buff") or eff.has("shield") or eff.has("hot"):
		p.add_buff(make_buff(s, eff, src))
	var z = p.zone()
	if z:
		CombatFX.pillar(z.fx_root, p.global_position, s.color, 2.6, 0.7)
		if eff.has("heal"): z.float_text(p.global_position + Vector3.UP * 2.6, "+%d" % roundi(mhp * float(eff.heal)), Color(0.4, 1, 0.5))

static func apply_to_minion(m, s: Dictionary, eff: Dictionary) -> void:
	if m == null or not is_instance_valid(m): return
	var mhp: float = m.max_hp
	if eff.has("heal"): m.hp = minf(mhp, m.hp + mhp * float(eff.heal))
	if eff.has("shield"): m.hp = minf(mhp * 1.3, m.hp + mhp * float(eff.shield))
	if eff.has("buff") or eff.has("shield"): m.add_buff(make_buff(s, eff))

## Офлайн/локально: враги мира (у каждого клиента свои) и офлайн-подземелье (локальная RaidSim)
static func apply_to_enemy(e, eff: Dictionary, caster) -> void:
	if e == null or not e.alive: return
	if e is NetEnemy:
		return   # врагами подземелья управляет RaidSim (сервер или локальная) — см. cast()
	if eff.has("debuff"):
		var d: Dictionary = eff.debuff
		e.add_debuff(str(d.kind), float(d.v), float(d.dur))
	if eff.has("taunt"):
		e.add_debuff("taunt", 1.0, float(eff.taunt))
		e.taunt_target = caster

## Применение умения героем p. target — враг (find_target) или null. true — умение сработало.
static func cast(p, s: Dictionary, target) -> bool:
	var z = p.zone()
	var eff: Dictionary = resolve(s)
	var tgt: String = eff.tgt
	var pos: Vector3 = p.global_position
	var tc = z.target_ctl if "target_ctl" in z else null
	var col: Color = s.color
	p.visual.play_action("cast" if p.data["class"] == "mage" else ("roar" if p.data["class"] == "warrior" else "cast"))
	match tgt:
		"self", "ally", "aura":
			var ally = tc.ally() if tc != null and tgt == "ally" else null
			if ally != null and ally != p and pos.distance_to(ally.global_position) > float(s.range) + 1.0:
				Game.toast("Союзник слишком далеко — на себя", 1.2); ally = null
			if tgt == "aura":
				z.fx("ring", pos, float(s.radius), col, 0.6)
				CombatFX.flash(z.fx_root, pos + Vector3.UP, col, float(s.radius) * 0.5, 0.5)
			elif ally != null and ally != p:
				CombatFX.burst(z.fx_root, ally.global_position + Vector3.UP, col, 22, 3.0, 0.08, 0.5)
			if Net.in_game:
				var aid := 0
				if ally is RemotePlayer: aid = int(ally.peer_id)
				Net.support_cast(s.id, aid, 0, pos)
				# свои призванные — на клиенте (их нет на сервере)
				for m in z.minions.duplicate():
					if tgt == "aura" and is_instance_valid(m) and U.flat_dist(m.global_position, pos) < float(s.radius): apply_to_minion(m, s, eff)
					elif tgt == "ally" and m == ally: apply_to_minion(m, s, eff)
				return true
			if tgt == "aura":
				apply_to_player(p, s, eff)
				for m in z.minions.duplicate():
					if is_instance_valid(m) and U.flat_dist(m.global_position, pos) < float(s.radius): apply_to_minion(m, s, eff)
			elif ally is Minion: apply_to_minion(ally, s, eff)
			else: apply_to_player(p, s, eff)
		"enemy", "enemy_area", "self_area":
			var center: Vector3 = pos
			if tgt != "self_area":
				if target == null and tgt == "enemy": tgt = "enemy_area"   # без цели — по области перед героем
				center = target.global_position if target != null else pos + p.forward() * minf(8.0, float(s.range))
			var r: float = (float(s.radius) if float(s.radius) > 0.0 else 3.0) if tgt != "enemy" else 0.0
			var t := Tele.make(z.fx_root, "disc", center, maxf(1.2, r), col)
			Tele.set_progress(t, 1.0); Tele.free_later(t, 0.5)
			var hit: Array = []
			var eff2: Dictionary = eff.duplicate(); eff2.tgt = tgt; eff2.radius = r
			eff = eff2
			if tgt == "enemy": hit = [target]
			else:
				for e in z.enemies:
					if e.alive and U.flat_dist(e.global_position, center) < r + float(e.radius): hit.append(e)
			for e in hit:
				CombatFX.burst(z.fx_root, e.global_position + Vector3.UP * 1.4, debuff_color(eff.get("debuff", {}).get("kind", "taunt")), 14, 3.0, 0.07, 0.4)
				apply_to_enemy(e, eff, p)
			# враги подземелья — в RaidSim: онлайн через сервер, офлайн — локальная симуляция
			var eid := int(target.net_id) if target is NetEnemy and tgt == "enemy" else 0
			if z.raid != null and not Net.in_game and z.raid.sim: z.raid.sim.apply_support(1, eff, eid, center)
			if Net.in_game: Net.support_cast(s.id, 0, eid, center)   # сервер: враги подземелья и бафф себе
			elif eff.has("buff") or eff.has("shield"): apply_to_player(p, s, eff)
	return true
