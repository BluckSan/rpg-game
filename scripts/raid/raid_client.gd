extends Node
class_name RaidClient
## Клиент группового подземелья: показывает то, что решает RaidSim (на сервере — онлайн, локально — соло-офлайн).
## Враги (NetEnemy), метки механик, урон по герою, решётка, вода/водоворот, награды и броски добычи.

var zone
var did := "ash"
var n := 1
var level := 1
var brain := RaidBrain.new()
var ents := {}            # id -> NetEnemy
var teles := {}           # id -> {node, left, dur, fo, k, len}
var sim: RaidSim          # офлайн: своя симуляция
var my_pid := 1
var done := false
var stats := {"hurt": 0, "taken": 0.0, "lethal": 0, "warns": [], "loot": [], "kills": 0, "wipes": 0, "events": {}, "src": {}}
var _snap_t := 0.0
var _pull := {}
var ui: CanvasLayer
var warn_label: Label
var roll_label: RichTextLabel
var _warn_t := 0.0
var _roll_t := 0.0

const COLORS := {"red": Color(1.0, 0.25, 0.15), "orange": Color(1.0, 0.55, 0.15), "yellow": Color(1.0, 0.9, 0.3),
	"blue": Color(0.3, 0.75, 1.0), "violet": Color(0.8, 0.45, 1.0), "green": Color(0.35, 1.0, 0.45)}

func setup(z, dungeon: String) -> void:
	zone = z; did = dungeon
	brain.PHASE_NAMES = RaidSim.PHASES[did]
	_build_ui()
	if Net.in_game:
		my_pid = Net.my_id
		Net.raid_ready(self)
	else:
		my_pid = 1
		sim = RaidSim.new()
		sim.setup(did, int(z.data.get("level", 1)), 1)
		sim.add_player(1, {"name": z.data.get("name", "?"), "cls": z.data.get("class", "warrior"), "lvl": z.data.get("level", 1)})
		_drain()

func online() -> bool: return sim == null

func send_hit(id: int, dmg: float, skill: bool) -> void:
	if sim: sim.hit(1, id, dmg, skill)
	else: Net.raid_hit(id, dmg, skill)

func leave() -> void:
	if Net.in_game: Net.raid_leave()
	zone.save()
	Game.travel("starter", "")

func _drain() -> void:
	var evs := sim.events.duplicate()
	sim.events.clear()
	for e in evs: handle(e[1])

func _process(delta: float) -> void:
	if ui: ui.visible = zone.hud == null or zone.hud.window == null   # v0.9.1: окно HUD скрывает панели рейда
	brain.step(delta)
	var p = zone.player
	if sim and p:
		var hpf := 0.0 if p.dead else clampf(p.hp / maxf(1.0, p.stats.max_hp), 0.0, 1.0)
		sim.update_player(1, p.global_position, hpf)
		sim.tick(delta)
		_drain()
		_snap_t -= delta
		if _snap_t <= 0.0:
			_snap_t = 0.1
			var s := sim.snapshot()
			apply_snap(s[0], s[1])
	_tele_tick(delta)
	if p and not p.dead:
		p.heal(p.stats.max_hp * 0.02 * delta)   # «благословение костра»: в подземельях группы нет лекаря
		if not _pull.is_empty():
			_pull.left = float(_pull.left) - delta
			var to: Vector3 = U.flat(_pull.pos - p.global_position)
			if to.length() > 0.6: p.global_position += to.normalized() * float(_pull.s) * delta
			if _pull.left <= 0.0: _pull = {}
	if _warn_t > 0.0:
		_warn_t -= delta
		warn_label.modulate.a = clampf(_warn_t, 0.0, 1.0)
		if _warn_t <= 0.0: warn_label.visible = false
	if _roll_t > 0.0:
		_roll_t -= delta
		if _roll_t <= 0.0: roll_label.get_parent().visible = false

func apply_snap(ids: PackedInt32Array, data: PackedFloat32Array) -> void:
	for i in ids.size():
		var e = ents.get(ids[i])
		if e and is_instance_valid(e) and e.alive:
			e.net_update(Vector3(data[i * 4], 0, data[i * 4 + 1]), data[i * 4 + 2], data[i * 4 + 3])

func handle(ev: Dictionary) -> void:
	var t: String = ev.get("t", "")
	stats.events[t] = int(stats.events.get(t, 0)) + 1
	match t:
		"init":
			for id in ents: if is_instance_valid(ents[id]): ents[id].net_die(true)
			ents.clear()
			level = int(ev.lvl); n = int(ev.n)
			for e in ev.e: _spawn(e)
			zone.builder.set_gate(bool(ev.gate))
		"spawn":
			for e in ev.e: _spawn(e)
		"dbf":
			var de = ents.get(int(ev.id))
			if de and is_instance_valid(de): de.net_debuffs(ev.l)
		"die":
			var e = ents.get(int(ev.id))
			if e and is_instance_valid(e):
				e.net_die(bool(ev.get("q", false)))
				if not ev.get("q", false): stats.kills += 1
			ents.erase(int(ev.id))
		"st":
			brain.apply(ev, RaidSim.PHASES[did])
			zone.builder.set_gate(bool(ev.gate))
			if bool(ev.get("done", false)) and not done:
				done = true
				zone.builder.spawn_arena_exit()
				var k: Dictionary = zone.data.get("raid_kills", {})
				k[did] = int(k.get(did, 0)) + 1
				zone.data["raid_kills"] = k
		"tele": _make_tele(ev)
		"hurt": _hurt(ev)
		"atk":
			var e = ents.get(int(ev.id))
			if e and is_instance_valid(e): e.net_attack(bool(ev.rg), _pid_pos(int(ev.p)))
		"warn": show_warn(str(ev.s))
		"xp":
			if zone.player: zone.player.gain_xp(int(ev.v))
		"loot": _loot(ev)
		"water": zone.builder.water_rise(float(ev.dur))
		"pull": _pull = {"pos": Vector3(float(ev.x), 0, float(ev.z)), "s": float(ev.s), "left": float(ev.dur)}
		"wipe":
			stats.wipes += 1
			_pull = {}
			for id in teles.keys(): _free_tele(id)

func _spawn(e: Dictionary) -> void:
	var id := int(e.id)
	if ents.has(id) and is_instance_valid(ents[id]) and ents[id].alive: return
	ents[id] = NetEnemy.create(zone, e, zone.builder.enemies_root, self)

func _pid_pos(pid: int) -> Vector3:
	if pid == my_pid and zone.player: return zone.player.global_position
	var r = Net.remotes.get(pid)
	if r and r.node and is_instance_valid(r.node): return r.node.global_position
	return Vector3.INF

# ---------- метки механик ----------
func _make_tele(ev: Dictionary) -> void:
	var k: String = ev.k
	var c: Color = COLORS.get(str(ev.c), Color(1, 0.3, 0.2))
	var pos := Vector3(float(ev.x), 0, float(ev.z))
	var node: Node3D
	var yaw := float(ev.yaw)
	var dir := Vector3(sin(yaw), 0, cos(yaw))
	match k:
		"cone": node = Tele.make(zone.fx_root, "cone", pos, float(ev.r), c, dir, float(ev.ang))
		"ring": node = Tele.make(zone.fx_root, "ring", pos, float(ev.r), c, Vector3.FORWARD, 360.0, float(ev["in"]) / float(ev.r))
		"line": node = _line_tele(pos, float(ev.r), float(ev.ang), yaw, c)
		_: node = Tele.make(zone.fx_root, "disc", pos, float(ev.r), c)
	if k == "safe" or str(ev.m) == "stack":   # «соберитесь здесь» — яркий столб света
		var pil := U.prim("cylinder", node, Vector3(0, 2.5, 0), Vector3(0.25, 2.5, 0.25), c)
		pil.material_override = U.fx_mat(Color(c.r, c.g, c.b, 0.35))
	teles[int(ev.id)] = {"node": node, "left": float(ev.dur), "dur": float(ev.dur), "fo": int(ev.fo), "k": k, "r": float(ev.r),
		"in": float(ev["in"]), "ang": float(ev.ang), "yaw": yaw, "m": str(ev.m), "pos": pos}

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

func _tele_tick(delta: float) -> void:
	for id in teles.keys():
		var tl: Dictionary = teles[id]
		tl.left = float(tl.left) - delta
		var node: Node3D = tl.node
		if not is_instance_valid(node): teles.erase(id); continue
		if int(tl.fo) != 0:
			var fp := _pid_pos(int(tl.fo))
			if fp != Vector3.INF: node.global_position = Vector3(fp.x, 0.06, fp.z)
		var k := clampf(1.0 - float(tl.left) / maxf(0.01, float(tl.dur)), 0.0, 1.0)
		if tl.k == "line":
			var f: MeshInstance3D = node.get_node("Fill")
			f.scale.z = maxf(0.01, float(node.get_meta("len")) * k)
		else: Tele.set_progress(node, k)
		if tl.left <= 0.0:
			if tl.k != "safe": zone.fx("burst", node.global_position + Vector3.UP * 0.4, float(node.get_meta("radius", 2.0)) * 0.6, Color(1, 0.6, 0.3), 0.35)
			_free_tele(id)

func _free_tele(id) -> void:
	var tl = teles.get(id)
	if tl and is_instance_valid(tl.node): tl.node.queue_free()
	teles.erase(id)

# ---------- урон по герою ----------
func _hurt(ev: Dictionary) -> void:
	var p = zone.player
	if p == null or p.dead: return
	var src := Vector3(float(ev.x), 0, float(ev.z))
	# v0.8.0: броня героя после перехода на плоские характеристики режет меньше — механики ×0.75 (смертельные — без изменений)
	var dmg: float = float(ev.f) * float(p.stats.max_hp) * 0.75
	if bool(ev.l):
		p.invuln = 0.0
		dmg = float(p.stats.max_hp) * 20.0
		stats.lethal += 1
	stats.hurt += 1; stats.taken += dmg
	var src_n := str(ev.w)
	stats.src[src_n] = float(stats.src.get(src_n, 0.0)) + float(ev.f)
	p.take_damage(dmg, src)
	if str(ev.w) != "" and float(ev.f) >= 0.2:
		zone.float_text(p.global_position + Vector3.UP * 2.8, str(ev.w), Color(1, 0.6, 0.4))

# ---------- награды ----------
func _loot(ev: Dictionary) -> void:
	stats.loot.append(ev)
	var p = zone.player
	if p == null: return
	var pos: Vector3 = p.global_position
	for it in ev.items: Loot.spawn(zone, pos + Vector3(randf_range(-2, 2), 0, randf_range(1, 3)), "item", 1, it)
	Loot.spawn(zone, pos + Vector3(0, 0, 1.5), "gold", int(ev.gold))
	p.gain_xp(int(ev.get("xp", 0)))
	var t := "[center][b]Броски добычи[/b][/center]\n"
	var rolls: Dictionary = ev.rolls
	var names := rolls.keys()
	names.sort_custom(func(a, b): return int(rolls[a]) > int(rolls[b]))
	for nm in names:
		t += "%s — [color=#f2c46d]%d[/color]%s\n" % [nm, int(rolls[nm]), "  ★ лучший" if nm == names[0] and names.size() > 1 else ""]
	t += "\nВаш бросок: [b]%d[/b] → предметов комплекта: %d" % [int(ev.roll), _set_count(ev.items)]
	roll_label.text = t
	roll_label.get_parent().visible = true
	_roll_t = 12.0
	zone.save()

func _set_count(items: Array) -> int:
	var c := 0
	for it in items: if str(it.get("set", "")) != "": c += 1
	return c

# ---------- интерфейс ----------
func _build_ui() -> void:
	ui = CanvasLayer.new(); ui.layer = 36
	add_child(ui)
	var root := Control.new(); root.set_anchors_preset(Control.PRESET_FULL_RECT); root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	warn_label = UIK.label(root, "", 34, Color(1, 0.82, 0.5), HORIZONTAL_ALIGNMENT_CENTER)
	warn_label.add_theme_constant_override("outline_size", 10)
	warn_label.anchor_left = 0.5; warn_label.anchor_right = 0.5
	warn_label.offset_left = -640; warn_label.offset_right = 640; warn_label.offset_top = 378; warn_label.offset_bottom = 430
	warn_label.visible = false
	var pn := UIK.panel(root, Color(0.06, 0.05, 0.08, 0.88))
	pn.anchor_left = 0.68; pn.anchor_right = 0.98; pn.anchor_top = 0.3; pn.anchor_bottom = 0.62
	pn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	roll_label = UIK.rich(pn, "", 24)
	UIK.full(roll_label); roll_label.offset_left = 18; roll_label.offset_top = 14; roll_label.offset_right = -18; roll_label.offset_bottom = -14
	pn.visible = false

func show_warn(s: String) -> void:
	stats.warns.append(s)
	warn_label.text = s
	warn_label.visible = true
	warn_label.modulate.a = 1.0
	_warn_t = 3.5
