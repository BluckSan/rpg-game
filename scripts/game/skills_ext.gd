class_name SkillsExt
## Расширенные умения классов и путей (v0.4.0). Вызывается из Player._execute.
## Возвращает true, если умение обработано здесь.

static func _cone_hit(p, radius: float, angle: float, mult: float, extra := Callable(), fb := {"knock": 5.0, "stop": 0.06, "shake": 0.2}) -> int:
	var n := 0
	var f: Vector3 = p.forward()
	var fbl: Dictionary = fb.duplicate()
	for e in p.zone().enemies.duplicate():
		if not is_instance_valid(e) or not e.alive: continue
		var d := U.flat(e.global_position - p.global_position)
		if d.length() > radius + e.radius: continue
		if d.length() > 0.5 and rad_to_deg(f.angle_to(d.normalized())) > angle / 2.0: continue
		p.hit(e, mult, false, false, fbl.duplicate())
		fbl["stop"] = 0.0; fbl["shake"] = 0.0
		n += 1
		if extra.is_valid() and is_instance_valid(e) and e.alive: extra.call(e)
	return n

static func _wait(p, t: float) -> bool:
	await p.get_tree().create_timer(t, false).timeout
	return is_instance_valid(p) and not p.dead

static func execute(p, s: Dictionary, target) -> bool:
	var z = p.zone()
	var pos: Vector3 = p.global_position
	var origin: Vector3 = pos + Vector3.UP * 1.3 + p.forward() * 0.6
	var c: Color = s.color
	match s.kind:
		# ---------- воин ----------
		"ground_slam":
			p.visual.play_action("slam")
			var t := Tele.make(z.fx_root, "cone", pos, s.radius, c, p.forward(), 70.0)
			if not await _wait(p, 0.25): Tele.free_later(t); return true
			Tele.free_later(t, 0.15)
			CombatFX.burst(z.fx_root, pos + p.forward() * 2.5, Color(0.6, 0.5, 0.4), 30, 6.0, 0.16, 0.6, Vector3.UP, 60, -12)
			z.shake(0.3)
			_cone_hit(p, s.radius, 70.0, s.mult, func(e): e.stun(1.5))
		"warcry":
			p.visual.play_action("roar")
			p.cry_timer = 8.0
			CombatFX.pillar(z.fx_root, pos, c, 3.5, 0.8)
			z.fx("ring", pos, s.radius, c, 0.5)
			for e in z.enemies:
				if e.alive and U.flat_dist(e.global_position, pos) < s.radius: e.slow(0.5, 4.0)
			Game.toast("Боевой клич!", 1.0)
		"leap":
			var to: Vector3 = target.global_position if target != null else pos + p.forward() * s.range * 0.7
			if U.flat_dist(to, pos) > s.range: to = pos + U.flat(to - pos).normalized() * s.range
			to = p.safe_destination(to)   # не через стены и не под землю
			var tele := Tele.make(z.fx_root, "disc", to, s.radius, c)
			p.face_towards(to)
			p.invuln = 0.5
			p.visual.play_action("jump")
			var from := pos
			Net.notify_teleport()
			var steps := 14
			for i in steps:
				await p.get_tree().process_frame
				if not is_instance_valid(p) or p.dead: Tele.free_later(tele); return true
				var k := float(i + 1) / steps
				var np := from.lerp(to, k)
				np.y = lerpf(from.y, to.y, k) + sin(k * PI) * 2.5
				p.global_position = np
				Tele.set_progress(tele, k)
			p.teleport(to)
			Tele.free_later(tele)
			z.shake(0.35)
			CombatFX.burst(z.fx_root, to + Vector3.UP * 0.3, c, 30, 7.0, 0.14, 0.6, Vector3.UP, 80, -10)
			z.fx("ring", to, s.radius, c, 0.4)
			p.hit_area(to, s.radius, s.mult, false, Callable(), {"knock": 7.0, "stop": 0.08, "shake": 0.2})
		"iron_skin":
			p.shield_timer = 5.0
			p.heal(p.stats.max_hp * 0.1)
			CombatFX.flash(z.fx_root, pos + Vector3.UP, c, 1.4, 0.5)
			CombatFX.burst(z.fx_root, pos + Vector3.UP, c, 24, 3.0, 0.1, 0.6, Vector3.UP, 180, 0)
		"execute":
			if target == null or U.flat_dist(target.global_position, pos) > s.range + 1.5:
				Game.toast("Нет цели рядом", 1.0); return true
			p.visual.play_action("slam")
			if not await _wait(p, 0.3): return true
			if not is_instance_valid(target) or not target.alive: return true
			var low: bool = target.hp / maxf(1.0, target.max_hp) < 0.3
			CombatFX.slash_arc(z.fx_root, pos, p.forward(), 3.0, 120, c, 0.3, 1.4)
			p.hit(target, s.mult * (3.0 if low else 1.0), false, low, {"knock": 6.0, "stop": 0.12, "shake": 0.35})
			if low: z.float_text(target.global_position + Vector3.UP * 3, "КАЗНЬ!", Color(1, 0.3, 0.2))
		# ---------- лучник ----------
		"pierce":
			p.visual.play_action("attack")
			if not await _wait(p, 0.15): return true
			var pr := Projectile.fire(z, origin, p._dir_to(origin, target), 30.0, s.range, c, 0.26, true, func(e): p.hit(e, s.mult, false, false, {"knock": 3.0}))
			pr.pierce = true
			pr.add_trail(c, true)
		"disengage":
			var back: Vector3 = -p.forward()
			if target != null: back = U.flat(pos - target.global_position).normalized()
			CombatFX.burst(z.fx_root, pos + Vector3.UP * 0.3, Color(0.7, 0.95, 1), 36, 7.0, 0.1, 0.6, Vector3.UP, 95, -2)
			z.fx("ring", pos, s.radius, c, 0.45)
			p.hit_area(pos, s.radius, s.mult, false, func(e): e.slow(0.35, 3.0))
			p.visual.play_action("roll")
			p.invuln = 0.35
			p._dash_vel = back * s.range / 0.25; p._dash_time = 0.25
		"trap":
			var tp: Vector3 = pos + p.forward() * 1.5
			var mark := Tele.make(z.fx_root, "disc", tp, s.radius, c)
			U.prim("cylinder", mark, Vector3(0, 0.05, 0), Vector3(0.6, 0.05, 0.6), Color(0.4, 0.35, 0.3), 0.4, 0.5)
			var armed := 0.0
			while armed < 8.0:
				await p.get_tree().create_timer(0.1, false).timeout
				armed += 0.1
				if not is_instance_valid(mark): return true
				Tele.set_progress(mark, minf(1.0, armed / 0.6))
				if armed < 0.6: continue
				var trig := false
				for e in z.enemies:
					if e.alive and U.flat_dist(e.global_position, tp) < s.radius * 0.8: trig = true
				if trig: break
			Tele.free_later(mark)
			if not is_instance_valid(p): return true
			CombatFX.burst(z.fx_root, tp + Vector3.UP * 0.4, c, 30, 6.0, 0.12, 0.5, Vector3.UP, 80, -8)
			z.fx("burst", tp + Vector3.UP * 0.5, s.radius, c, 0.3)
			p.hit_area(tp, s.radius, s.mult, false, func(e): e.stun(2.0))
		"snipe":
			p.visual.play_action("attack")
			CombatFX.cast_glow(p.visual, c, 0.5, 0.35)
			var aim = target
			if not await _wait(p, 0.5): return true
			var pr := Projectile.fire(z, origin, p._dir_to(origin, aim), 40.0, s.range, c, 0.3, true, func(e): p.hit(e, s.mult, false, true, {"knock": 5.0, "stop": 0.1, "shake": 0.25}))
			pr.add_trail(c, true)
		"poison":
			p.visual.play_action("attack")
			if not await _wait(p, 0.15): return true
			var pr := Projectile.fire(z, origin, p._dir_to(origin, target), 24.0, s.range, c, 0.24, true, func(e):
				var at: Vector3 = e.global_position
				GroundZone.spawn(z, Vector3(at.x, z.ground_y(at), at.z), s.radius, 6.0, c, func(cp):
					p.hit_area(cp, s.radius, s.mult, false, Callable(), {"knock": 0.0, "stop": 0.0, "shake": 0.0}), 1.0))
			pr.add_trail(c, true)
		# ---------- маг ----------
		"chain":
			CombatFX.cast_glow(p.visual.tip_node(), c, 0.3, 0.4)
			var from_p: Vector3 = p.visual.tip_position()
			var cur = target
			var hit_list := []
			for i in 5 + int(p.fx.get("chain_plus", 0.0)):
				if cur == null: break
				var to_p: Vector3 = cur.global_position + Vector3.UP * (2.0 if cur.def.boss else 0.9)
				Tele.bolt(z.fx_root, from_p, to_p, c)
				p.hit(cur, s.mult * pow(0.85, i), true, false, {"knock": 1.0, "stop": 0.02})
				hit_list.append(cur)
				from_p = to_p
				var nxt = null; var bd: float = s.radius
				for e in z.enemies:
					if not e.alive or hit_list.has(e): continue
					var d: float = U.flat_dist(e.global_position, Vector3(from_p.x, 0, from_p.z))
					if d < bd: bd = d; nxt = e
				cur = nxt
				if not await _wait(p, 0.06): return true
			if target == null: Game.toast("Нет цели", 1.0)
		"blink":
			var dir: Vector3 = p._last_move if p._last_move.length() > 0.1 else p.forward()
			dir = U.flat(dir).normalized()
			var to: Vector3 = pos + dir * s.range
			CombatFX.burst(z.fx_root, pos + Vector3.UP, c, 26, 4.0, 0.1, 0.4, Vector3.UP, 180, 0)
			to = p.blink_to(to)   # капсула по пути + пол под точкой (v0.5.1)
			p.invuln = 0.25
			CombatFX.burst(z.fx_root, to + Vector3.UP, c, 26, 4.0, 0.1, 0.4, Vector3.UP, 180, 0)
		"fire_wall":
			p.visual.play_action("cast")
			var f: Vector3 = p.forward()
			var center: Vector3 = pos + f * (s.range / 2.0 + 1.0)
			center.y = z.ground_y(center)
			GroundZone.spawn(z, center, s.radius, 4.0, c, func(cp):
				for e in z.enemies.duplicate():
					if not is_instance_valid(e) or not e.alive: continue
					var rel := U.flat(e.global_position - cp)
					if absf(rel.dot(f)) < s.range / 2.0 and absf(rel.dot(f.cross(Vector3.UP))) < s.radius + e.radius:
						p.hit(e, s.mult, true, false, {"knock": 0.0, "stop": 0.0}), 0.5, "line", f, s.range)
		"mana_shield":
			p.shield_timer = 6.0
			p.mp = minf(p.stats.max_mp, p.mp + p.stats.max_mp * 0.25)
			CombatFX.flash(z.fx_root, pos + Vector3.UP, c, 1.6, 0.6)
		"ice_lance":
			p.visual.play_action("cast")
			if not await _wait(p, 0.2): return true
			var o2: Vector3 = p.visual.tip_position()
			var pr := Projectile.fire(z, o2, p._dir_to(o2, target), 26.0, s.range, c, 0.35, true, func(e):
				p.hit(e, s.mult, true, false, {"knock": 2.5})
				if is_instance_valid(e) and e.alive: e.slow(0.3, 4.0))
			pr.pierce = true
			pr.add_trail(c, true)
		# ---------- пути превращения ----------
		"blood_spin":
			p.visual.play_action("spin")
			CombatFX.slash_arc(z.fx_root, pos, p.forward(), s.radius, 360, c, 0.4, 1.0)
			if not await _wait(p, 0.12): return true
			var n := 0
			for e in z.enemies.duplicate():
				if e.alive and U.flat_dist(e.global_position, pos) <= s.radius + e.radius:
					p.hit(e, s.mult, false, false, {"knock": 6.0, "stop": 0.04}); n += 1
			p.heal(p.stats.max_hp * 0.03 * n)
			CombatFX.burst(z.fx_root, pos + Vector3.UP, c, 30, 5.0, 0.1, 0.5, Vector3.UP, 180, -6)
		"quake":
			p.visual.play_action("slam")
			for i in 3:
				var r2: float = s.radius * (0.5 + 0.25 * i)
				var t := Tele.make(z.fx_root, "disc", pos, r2, c)
				if not await _wait(p, 0.35): Tele.free_later(t); return true
				Tele.free_later(t)
				z.shake(0.3)
				z.fx("ring", pos, r2, c, 0.35)
				p.hit_area(pos, r2, s.mult, false, Callable(), {"knock": 4.0, "stop": 0.03, "shake": 0.0})
		"holy_hammer":
			var pr := Projectile.fire(z, origin, p._dir_to(origin, target), 18.0, s.range, c, 0.45, true, func(e):
				var at: Vector3 = e.global_position
				CombatFX.pillar(z.fx_root, at, c, 4.0, 0.6)
				p.hit_area(at, s.radius, s.mult, true, func(e2): e2.stun(1.5)))
			pr.add_trail(c, true)
		"consecrate":
			var at: Vector3 = pos
			GroundZone.spawn(z, at, s.radius, 6.0, c, func(cp):
				p.hit_area(cp, s.radius, s.mult, true, Callable(), {"knock": 0.0, "stop": 0.0, "shake": 0.0})
				if is_instance_valid(p) and U.flat_dist(p.global_position, cp) < s.radius: p.heal(p.stats.max_hp * 0.03), 0.5)
		"storm":
			var foes := []
			for e in z.enemies:
				if e.alive and U.flat_dist(e.global_position, pos) < s.radius: foes.append(e)
			for i in 8:
				var at: Vector3
				if foes.size() > 0:
					var e = foes[i % foes.size()]
					if not is_instance_valid(e) or not e.alive: continue
					at = e.global_position
				else:
					at = pos + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
				Tele.bolt(z.fx_root, at + Vector3.UP * 12.0, at + Vector3.UP * 0.2, c, 0.3, 0.14)
				p.hit_area(at, 1.8, s.mult, true, Callable(), {"knock": 1.0, "stop": 0.0, "shake": 0.05})
				if not await _wait(p, 0.12): return true
		"ice_prison":
			var at: Vector3 = target.global_position if target != null else pos + p.forward() * 6
			z.fx("ring", at, s.radius, c, 0.5)
			CombatFX.burst(z.fx_root, at + Vector3.UP * 0.5, c, 40, 5.0, 0.14, 0.7, Vector3.UP, 90, -3)
			p.hit_area(at, s.radius, s.mult, true, func(e): e.stun(3.0))
		"bone_nova":
			for i in 12:
				var d := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 12.0)
				Projectile.fire(z, pos + Vector3.UP * 1.0, d, 18.0, s.range, c, 0.22, true, func(e): p.hit(e, s.mult, true)).add_trail(c, false)
		"curse":
			var at: Vector3 = target.global_position if target != null else pos + p.forward() * 6
			var t := Tele.make(z.fx_root, "disc", at, s.radius, c)
			Tele.set_progress(t, 1.0); Tele.free_later(t, 0.6)
			for e in z.enemies:
				if e.alive and U.flat_dist(e.global_position, at) < s.radius + e.radius:
					e.curse(8.0); e.slow(0.6, 8.0)
		"knife_fan":
			for i in 8:
				var d: Vector3 = p.forward().rotated(Vector3.UP, TAU * i / 8.0)
				Projectile.fire(z, origin, d, 26.0, s.range, c, 0.18, true, func(e): p.hit(e, s.mult)).add_trail(c, false)
		"vanish":
			p.invuln = 1.5
			p.haste_timer = 4.0
			CombatFX.burst(z.fx_root, pos + Vector3.UP, Color(0.2, 0.15, 0.3, 0.8), 40, 3.0, 0.2, 0.8, Vector3.UP, 180, 0.5)
			p.visual.visible = false
			await p.get_tree().create_timer(1.5, false).timeout
			if is_instance_valid(p): p.visual.visible = true
		"maul":
			p.visual.play_action("slam")
			if not await _wait(p, 0.2): return true
			CombatFX.slash_arc(z.fx_root, pos, p.forward(), s.radius, 140, c, 0.3, 1.0)
			_cone_hit(p, s.radius, 140.0, s.mult, Callable(), {"knock": 8.0, "stop": 0.08, "shake": 0.3})
		"regrowth":
			p.hot_timer = 6.0
			p.hot_rate = p.stats.max_hp * 0.4 / 6.0
			CombatFX.pillar(z.fx_root, pos, c, 3.0, 1.0)
		_:
			return false
	return true
