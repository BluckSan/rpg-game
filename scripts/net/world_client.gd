extends Node
class_name WorldClient
## v0.9.2: клиент общих врагов мира онлайн (долина, Земли Эфира, Склеп группы). Только показывает решения
## сервера (WorldSim): атаки, метки на земле, урон по герою, предупреждения, состояние боссов, ударные волны.

var zone
var teles := {}
var stats := {"hurt": 0, "taken": 0.0, "lethal": 0, "warns": [], "events": {}, "tele": 0, "waves": 0}
var ui: CanvasLayer
var warn_label: Label
var _warn_t := 0.0

const COLORS := {"red": Color(1.0, 0.25, 0.15), "orange": Color(1.0, 0.55, 0.15), "yellow": Color(1.0, 0.9, 0.3),
	"blue": Color(0.3, 0.75, 1.0), "violet": Color(0.8, 0.45, 1.0), "purple": Color(0.65, 0.3, 1.0), "green": Color(0.35, 1.0, 0.45),
	"cyan": Color(0.4, 0.95, 1.0)}

func setup(z) -> void:
	zone = z
	ui = CanvasLayer.new(); ui.layer = 36
	add_child(ui)
	var root := Control.new(); root.set_anchors_preset(Control.PRESET_FULL_RECT); root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	warn_label = UIK.label(root, "", 34, Color(1, 0.82, 0.5), HORIZONTAL_ALIGNMENT_CENTER)
	warn_label.add_theme_constant_override("outline_size", 10)
	warn_label.anchor_left = 0.5; warn_label.anchor_right = 0.5
	warn_label.offset_left = -640; warn_label.offset_right = 640; warn_label.offset_top = 378; warn_label.offset_bottom = 430
	warn_label.visible = false

func handle(ev: Dictionary) -> void:
	var t: String = ev.get("t", "")
	stats.events[t] = int(stats.events.get(t, 0)) + 1
	match t:
		"tele": _make_tele(ev)
		"tele_x": _free_tele(int(ev.id))
		"hurt": _hurt(ev)
		"warn": show_warn(str(ev.s))
		"wave":
			stats.waves += 1
			var w := BossBrain.Shockwave.new()
			w.zone = zone; w.center = Vector3(float(ev.x), zone.ground_y(Vector3(float(ev.x), 0, float(ev.z))), float(ev.z))
			w.speed = float(ev.sp); w.damage = float(ev.d)
			zone.fx_root.add_child(w)
		"atk":
			var e = Net.wm_nodes.get(int(ev.id))
			if e != null and is_instance_valid(e) and e.alive: e.net_attack(bool(ev.rg), _pid_pos(int(ev.p)), str(ev.get("a", "")))
		"st":
			var e = Net.wm_nodes.get(int(ev.id))
			if e != null and is_instance_valid(e) and e.brain is RaidBrain: e.brain.apply(ev, ev.get("names", ["", "", "", ""]))
		"heal":
			var e = Net.wm_nodes.get(int(ev.to))
			if e != null and is_instance_valid(e):
				zone.float_text(e.global_position + Vector3.UP * 2.4, "+%d" % int(ev.a), Color(0.4, 1, 0.5))
				CombatFX.burst(zone.fx_root, e.global_position + Vector3.UP, Color(0.4, 1, 0.5, 0.8), 10, 1.5, 0.1, 0.6, Vector3.UP, 60, 0.4)

func _pid_pos(pid: int) -> Vector3:
	if pid == Net.my_id and zone.player: return zone.player.global_position
	var r = Net.remotes.get(pid)
	if r and r.node and is_instance_valid(r.node): return r.node.global_position
	return Vector3.INF

func _make_tele(ev: Dictionary) -> void:
	stats.tele += 1
	var k: String = ev.k
	var c: Color = COLORS.get(str(ev.c), Color(1, 0.3, 0.2))
	var pos := Vector3(float(ev.x), 0, float(ev.z))
	pos.y = zone.ground_y(pos)
	var yaw := float(ev.yaw)
	var dir := Vector3(sin(yaw), 0, cos(yaw))
	var node: Node3D
	match k:
		"cone":
			node = Tele.make(zone.fx_root, "cone", pos, float(ev.r), c, dir, float(ev.ang))
		"ring": node = Tele.make(zone.fx_root, "ring", pos, float(ev.r), c, Vector3.FORWARD, 360.0, float(ev["in"]) / maxf(0.01, float(ev.r)))
		"line": node = _line_tele(pos, float(ev.r), float(ev.ang), yaw, c)
		_: node = Tele.make(zone.fx_root, "disc", pos, float(ev.r), c)
	if str(ev.m) in ["stack", "safe"]:
		var pil := U.prim("cylinder", node, Vector3(0, 2.5, 0), Vector3(0.25, 2.5, 0.25), c)
		pil.material_override = U.fx_mat(Color(c.r, c.g, c.b, 0.35))
	teles[int(ev.id)] = {"node": node, "left": float(ev.dur), "dur": float(ev.dur), "k": k, "r": float(ev.r), "r1": float(ev.get("r1", ev.r)), "m": str(ev.m)}

func _line_tele(pos: Vector3, length: float, width: float, yaw: float, c: Color) -> Node3D:
	var root := Node3D.new()
	zone.fx_root.add_child(root)
	root.global_position = pos + Vector3.UP * 0.06
	root.rotation.y = yaw
	for nm in ["Base", "Fill"]:
		var mi := MeshInstance3D.new(); mi.name = nm
		var pm := PlaneMesh.new(); pm.size = Vector2(width, 1.0); pm.center_offset = Vector3(0, 0, 0.5)
		mi.mesh = pm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(c.r, c.g, c.b, 0.3 if nm == "Base" else 0.45)
		if nm == "Fill": m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.scale = Vector3(1, 1, length if nm == "Base" else 0.01)
		mi.position.y = 0.0 if nm == "Base" else 0.01
		root.add_child(mi)
	root.set_meta("len", length)
	return root

func _process(delta: float) -> void:
	if zone == null: return
	if ui: ui.visible = zone.hud == null or zone.hud.window == null
	for id in teles.keys():
		var tl: Dictionary = teles[id]
		tl.left = float(tl.left) - delta
		var node: Node3D = tl.node
		if not is_instance_valid(node): teles.erase(id); continue
		var k := clampf(1.0 - float(tl.left) / maxf(0.01, float(tl.dur)), 0.0, 1.0)
		if tl.k == "line":
			var f: MeshInstance3D = node.get_node("Fill")
			f.scale.z = maxf(0.01, float(node.get_meta("len")) * k)
		else:
			Tele.set_progress(node, k)
			if float(tl.r1) != float(tl.r):   # сужающийся безопасный круг
				var s := lerpf(1.0, float(tl.r1) / maxf(0.01, float(tl.r)), k)
				node.scale = Vector3(s, 1, s)
		if tl.left <= 0.0:
			if tl.m != "safe": zone.fx("burst", node.global_position + Vector3.UP * 0.4, float(node.get_meta("radius", 2.0)) * 0.6, Color(1, 0.6, 0.3), 0.35)
			_free_tele(id)
	if _warn_t > 0.0:
		_warn_t -= delta
		warn_label.modulate.a = clampf(_warn_t, 0.0, 1.0)
		if _warn_t <= 0.0: warn_label.visible = false

func _free_tele(id) -> void:
	var tl = teles.get(id)
	if tl and is_instance_valid(tl.node): tl.node.queue_free()
	teles.erase(id)

func _hurt(ev: Dictionary) -> void:
	var p = zone.player
	if p == null or p.dead: return
	var src := Vector3(float(ev.x), 0, float(ev.z))
	src.y = zone.ground_y(src)
	var dmg: float = float(ev.d)
	if float(ev.get("f", 0.0)) > 0.0: dmg = float(ev.f) * float(p.stats.max_hp)
	if bool(ev.l):
		p.invuln = 0.0
		dmg = float(p.stats.max_hp) * 20.0
		stats.lethal += 1
	stats.hurt += 1; stats.taken += dmg
	p.take_damage(dmg, src)
	if float(ev.get("kb", 0.0)) > 0.0 and not p.dead:
		var dir := U.flat(p.global_position - src)
		if dir.length() < 0.1: dir = Vector3.FORWARD
		p.knockback(dir.normalized(), float(ev.kb))
	if str(ev.w) != "" and (bool(ev.l) or float(ev.get("f", 0.0)) >= 0.2):
		zone.float_text(p.global_position + Vector3.UP * 2.8, str(ev.w), Color(1, 0.6, 0.4))

func show_warn(s: String) -> void:
	stats.warns.append(s)
	warn_label.text = s
	warn_label.visible = true
	warn_label.modulate.a = 1.0
	_warn_t = 4.0
