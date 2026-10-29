extends CanvasLayer
class_name PartyUI
## v0.8.0: рамки группы (имя, уровень, здоровье — для телефона и ПК) и окно «Группа / Подземелья»:
## приглашения, вступление, выход, исключение (лидер), вход в групповые подземелья (лидер ведёт группу;
## один игрок тоже может войти — здоровье врагов масштабируется под размер группы). Клавиша G.
## v0.9.1: кнопка «Группа» и G открывают вкладку «Группа» (приглашения, список игроков в сети, приглашение
## по имени, участники, выход, исключение); кнопка «Подземелья» — вкладку подземелий. Пока открыто любое окно
## (инвентарь, умения, таланты, карта, лавка, сундук, меню/настройки) кнопки и рамки скрыты.

var zone
var btn: Button           # «Группа» (G)
var dbtn: Button          # «Подземелья»
var ui_root: Control
var name_edit: LineEdit
var frames: VBoxContainer
var win: Panel
var body: VBoxContainer
var tab := "party"
var _t := 0.0
var head_bar: Panel
var _drag := false
var _drag_off := Vector2.ZERO
const LAYOUT := "user://ui_layout.cfg"

func _place_frames(p: Vector2) -> void:
	var vs := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1920, 1080)
	p = Vector2(clampf(p.x, 0, vs.x - 340), clampf(p.y, 0, vs.y - 160))
	head_bar.position = p
	frames.anchor_top = 0; frames.anchor_bottom = 0
	frames.offset_left = p.x; frames.offset_right = p.x + 330; frames.offset_top = p.y + 34; frames.offset_bottom = p.y + 34

func _head_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		_drag = ev.pressed
		_drag_off = head_bar.get_global_mouse_position() - head_bar.position
		if not ev.pressed:
			var cf := ConfigFile.new(); cf.load(LAYOUT)
			cf.set_value("party", "pos", head_bar.position); cf.save(LAYOUT)
		head_bar.accept_event()
	elif ev is InputEventMouseMotion and _drag:
		_place_frames(head_bar.get_global_mouse_position() - _drag_off)
		head_bar.accept_event()
static var preview := false   # снимки/тесты: показать рамки из Net.party без сервера

func _ready() -> void:
	layer = 41
	process_mode = Node.PROCESS_MODE_ALWAYS   # окна HUD ставят игру на паузу — скрываться нужно и тогда
	var root := Control.new(); root.set_anchors_preset(Control.PRESET_FULL_RECT); root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	ui_root = root
	btn = UIK.button(root, "Группа", open_tab.bind("party"), UIK.PURPLE, 24, "three-friends")
	btn.name = "PartyBtn"
	btn.custom_minimum_size = Vector2(0, 48)
	btn.anchor_top = 0.3; btn.anchor_bottom = 0.3
	btn.offset_left = 144 if Net.in_game else 24; btn.offset_right = btn.offset_left + 200; btn.offset_bottom = 52
	dbtn = UIK.button(root, "Подземелья", open_dungeons, UIK.PURPLE, 24, "crossed-swords")
	dbtn.name = "DungeonsBtn"
	dbtn.custom_minimum_size = Vector2(0, 48)
	dbtn.anchor_top = 0.3; dbtn.anchor_bottom = 0.3
	dbtn.offset_left = btn.offset_right + 10; dbtn.offset_right = dbtn.offset_left + 220; dbtn.offset_bottom = 52
	frames = VBoxContainer.new()
	frames.add_theme_constant_override("separation", 6)
	frames.anchor_top = 0.36; frames.anchor_bottom = 0.36
	frames.offset_left = 24; frames.offset_right = 24 + 330
	frames.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(frames)
	# v0.9.3 (ПК): окно группы как в L2 — заголовок перетаскивается, позиция сохраняется
	if Game.desktop:
		head_bar = UIK.panel(root, Color(0.06, 0.08, 0.12, 0.9), 8); head_bar.name = "PartyHead"
		head_bar.mouse_filter = Control.MOUSE_FILTER_STOP
		head_bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
		head_bar.size = Vector2(330, 30)
		var hl := UIK.label(head_bar, "Группа  ·  тяните, чтобы сдвинуть", 16, UIK.MUTED); hl.autowrap_mode = TextServer.AUTOWRAP_OFF
		hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UIK.rect(hl, Vector2(10, 3), Vector2(312, 24))
		head_bar.gui_input.connect(_head_input)
		head_bar.visible = false
		var cf := ConfigFile.new()
		var pp := Vector2(24, 400)
		if cf.load(LAYOUT) == OK: pp = cf.get_value("party", "pos", pp)
		_place_frames(pp)
	win = UIK.panel(root)
	win.anchor_left = 0.5; win.anchor_right = 0.5; win.anchor_top = 0.5; win.anchor_bottom = 0.5
	win.offset_left = -560; win.offset_right = 560; win.offset_top = -380; win.offset_bottom = 380
	var head := UIK.hbox(win, 64)
	UIK.rect(head, Vector2(24, 18), Vector2(1072, 64))
	# v0.9.3: окно только для группы; подземелья — через порталы на карте мира
	UIK.icon_rect(head, "three-friends", 48, UIK.ACCENT)
	var tl := UIK.label(head, "Группа", 34, UIK.ACCENT); tl.name = "Tab_party"; tl.autowrap_mode = TextServer.AUTOWRAP_OFF
	var sp := Control.new(); UIK.expand(sp); head.add_child(sp)
	UIK.button(head, "Закрыть", close, UIK.RED, 26)
	var holder := Control.new(); win.add_child(holder)
	UIK.rect(holder, Vector2(10, 92), Vector2(1100, 650))
	body = UIK.scroll_list(holder, 12)
	win.visible = false
	_build_rc(root)
	Net.ready_ask.connect(_on_rc_ask)
	Net.ready_check.connect(_on_rc_state)
	Net.party_changed.connect(refresh)
	Net.roster_changed.connect(refresh)
	refresh()

func toggle() -> void:
	if win.visible: close()
	else: open_tab(tab)

func close() -> void:
	win.visible = false
	if name_edit and is_instance_valid(name_edit): name_edit.release_focus()

## v0.9.3: «Подземелья» — карта мира с порталами (вход только через порталы)
func open_dungeons() -> void:
	if zone and zone.has_method("is_raid") and zone.is_raid():
		open_tab("party"); return
	if zone == null or not (zone.builder is WorldBuilder):
		Game.toast("Порталы подземелий отмечены на карте мира: у Сухого Колодца, Топкого лагеря и Заставы Инея", 4.0); return
	if zone.hud.window: return
	zone.hud._open("map")
	var m = zone.hud.window
	if m and m.has_method("focus_dungeon"):
		var pick: String = RaidDefs.ORDER[0]
		for did in RaidDefs.ORDER:
			if DB.dungeon_lock(zone.data, did) == "": pick = did
		m.call_deferred("focus_dungeon", pick)

## Открыть окно группы; повторное нажатие закрывает
func open_tab(t: String) -> void:
	if win.visible and tab == t: close(); return
	if zone and zone.hud and zone.hud.window: return   # поверх других окон не открываем
	tab = t
	win.visible = true
	refresh()
	UIK.pop_in(win)

func _unhandled_input(e: InputEvent) -> void:
	if (e is InputEventKey or e is InputEventMouseButton) and e.pressed and not (e is InputEventKey and e.echo) and Controls.action_of(e) == "party":
		var fo = get_viewport().gui_get_focus_owner()
		if fo is LineEdit: return
		open_tab("party"); get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	# v0.9.1: только на основном экране — любое окно HUD скрывает кнопки, рамки и окно группы
	var main_view: bool = not (zone and zone.hud and zone.hud.window != null)
	ui_root.visible = main_view
	if not main_view: return
	if rc_win and rc_win.visible:
		rc_left = maxf(0.0, rc_left - delta)
		if rc_yes.visible and rc_left <= 0.0: rc_win.visible = false
	_t -= delta
	if _t > 0.0: return
	_t = 0.25
	if not _pending_blockers.is_empty() and zone and zone.hud:
		zone.hud.blockers.append_array(_pending_blockers); _pending_blockers.clear()
	_frames()
	btn.text = "Группа" + (" (%d)" % (Net.party.members.size()) if Net.in_party() else "") + (" !" if not Net.party_invites.is_empty() else "")

# ---------- рамки группы ----------
func _frames() -> void:
	var mem: Array = Net.party.get("members", []) if (Net.in_game or preview) else []
	if head_bar:
		if not head_bar.visible and not mem.is_empty() and zone and zone.hud: zone.hud.blockers.append(head_bar)
		head_bar.visible = not mem.is_empty()
	while frames.get_child_count() < mem.size(): _frame()
	for i in frames.get_child_count():
		var f: Control = frames.get_child(i)
		f.visible = i < mem.size()
		if not f.visible: continue
		var m: Dictionary = mem[i]
		var me: bool = int(m.id) == Net.my_id
		var hpf := float(m.hp)
		if me and zone and zone.player: hpf = zone.player.hp / maxf(1.0, zone.player.stats.max_hp)
		var nl: Label = f.get_node("Name")
		nl.text = "%s%s · ур. %d · %s" % ["★ " if int(m.id) == int(Net.party.leader) else "", m.name, int(m.lvl), Items.CLASS_NAMES.get(m.cls, m.cls)]
		nl.add_theme_color_override("font_color", UIK.ACCENT if me else UIK.TEXT)
		var b: ProgressBar = f.get_node("Hp")
		b.max_value = 1.0; b.value = hpf
		var mpf := float(m.get("mp", 1.0))
		if me and zone and zone.player: mpf = zone.player.mp / maxf(1.0, zone.player.stats.max_mp)
		var mb: ProgressBar = f.get_node("Mp")
		mb.max_value = 1.0; mb.value = mpf
		var zl: Label = f.get_node("Zone")
		var zk := str(m.zone)
		zl.text = "погиб" if hpf <= 0.0 else (DB.ZONES[zk].name if DB.ZONES.has(zk) else zk)
		zl.add_theme_color_override("font_color", Color(1, 0.4, 0.35) if hpf <= 0.0 else UIK.MUTED)
		# v0.9.0: баффы (свои — локально, чужие — от сервера), выделение выбранного союзника
		f.set_meta("pid", int(m.id))
		if zone and zone.hud and zone.player:
			var bl: Array = zone.hud._player_buffs() if me else zone.hud.party_buffs(m)
			zone.hud._fill_buffs(f.get_node("Buffs"), bl)
		var tc = zone.target_ctl if zone else null
		var sel: bool = tc != null and tc.has_target() and ((me and tc.target == zone.player) or (tc.target is RemotePlayer and int(tc.target.peer_id) == int(m.id)))
		f.self_modulate = Color(0.6, 1.4, 0.6) if sel else Color.WHITE

var _pending_blockers := []
func _frame_input(ev: InputEvent, f: Control) -> void:
	if not (ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed): return
	select_member(int(f.get_meta("pid", 0)))
	get_viewport().set_input_as_handled()

## Выбрать участника группы целью (рамка группы): свой герой или другой игрок в этой же зоне
func select_member(pid: int) -> bool:
	var tc = zone.target_ctl if zone else null
	if tc == null: return false
	if pid == Net.my_id or pid == 0:
		tc.select(zone.player); return true
	var r = Net.remotes.get(pid)
	if r == null or r.node == null or not is_instance_valid(r.node):
		Game.toast("Союзник не рядом — выбрать нельзя", 1.4); return false
	tc.select(r.node)
	return true

func _frame() -> Control:
	var p := UIK.panel(frames, Color(0.05, 0.05, 0.07, 0.78), 8)
	p.custom_minimum_size = Vector2(330, 112)
	p.mouse_filter = Control.MOUSE_FILTER_STOP   # v0.9.0: нажатие по рамке — выбрать союзника целью
	p.gui_input.connect(_frame_input.bind(p))
	if zone and zone.hud: zone.hud.blockers.append(p)
	else: _pending_blockers.append(p)
	var bx := HBoxContainer.new(); bx.name = "Buffs"; bx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bx.add_theme_constant_override("separation", 4)
	p.add_child(bx); UIK.rect(bx, Vector2(10, 72), Vector2(312, 36))
	var nl := UIK.label(p, "", 21); nl.name = "Name"; nl.autowrap_mode = TextServer.AUTOWRAP_OFF
	nl.clip_text = true
	UIK.rect(nl, Vector2(10, 2), Vector2(312, 30))
	var b := UIK.bar(p, Color(0.2, 0.75, 0.3)); b.name = "Hp"
	UIK.rect(b, Vector2(10, 34), Vector2(200, 20))
	var mpb := UIK.bar(p, Color(0.25, 0.45, 0.95)); mpb.name = "Mp"   # v0.9.3: мана участника
	UIK.rect(mpb, Vector2(10, 57), Vector2(200, 11))
	var zl := UIK.label(p, "", 17, UIK.MUTED); zl.name = "Zone"; zl.autowrap_mode = TextServer.AUTOWRAP_OFF; zl.clip_text = true
	UIK.rect(zl, Vector2(216, 34), Vector2(108, 26))
	return p

# ---------- окно ----------
func refresh() -> void:
	if body == null or not win.visible: return
	UIK.clear(body)
	if zone != null and zone.has_method("is_raid") and zone.is_raid():
		UIK.label(body, "Вы в подземелье «%s»" % DB.ZONES[zone.data.zone].name, 30, UIK.ACCENT)
		UIK.button(body, "Выйти из подземелья", func(): close(); zone.raid.leave(), UIK.RED, 26)
	_party_tab()

func _row(h := 64.0) -> HBoxContainer: return UIK.hbox(body, h, 12)

func _party_tab() -> void:
	if not Net.in_game:
		UIK.label(body, "Группа", 30, UIK.ACCENT)
		UIK.label(body, "Группы доступны в онлайн-режиме: войдите в аккаунт в главном меню («Онлайн»), чтобы приглашать игроков, видеть участников и ходить в подземелья вместе. Подземелья — через порталы на карте мира.", 24, UIK.MUTED)
		return
	for pid in Net.party_invites:
		var r := _row()
		UIK.expand(UIK.label(r, "Приглашение от %s" % Net.party_invites[pid], 26, UIK.ACCENT))
		UIK.button(r, "Принять", Net.party_accept.bind(pid), UIK.GREEN, 26)
		UIK.button(r, "Отклонить", Net.party_decline.bind(pid), UIK.RED, 26)
	var mem: Array = Net.party.get("members", [])
	UIK.label(body, "Ваша группа: %d / %d" % [maxi(1, mem.size()), Net.PARTY_MAX] + ("  ·  вы лидер" if Net.is_leader() else ""), 30, UIK.ACCENT)
	var in_party := {}
	for m in mem:
		in_party[str(m.name)] = true
		var r := _row()
		var lead := int(m.id) == int(Net.party.leader)
		UIK.expand(UIK.label(r, "%s%s — ур. %d, %s, здоровье %d%%" % ["★ " if lead else "", m.name, int(m.lvl), Items.CLASS_NAMES.get(m.cls, m.cls), roundi(float(m.hp) * 100)], 25))
		if Net.is_leader() and int(m.id) != Net.my_id:
			UIK.button(r, "Исключить", Net.party_kick.bind(str(m.name)), UIK.RED, 24)
	if mem.is_empty():
		UIK.label(body, "Вы играете один. Пригласите игроков ниже (до %d в группе)." % Net.PARTY_MAX, 24, UIK.MUTED)
	else:
		UIK.button(body, "Покинуть группу", Net.party_leave, UIK.RED, 26)
	# приглашение по имени
	var can_inv: bool = (not Net.in_party() or Net.is_leader()) and mem.size() < Net.PARTY_MAX
	var ir := _row(70)
	name_edit = LineEdit.new(); name_edit.name = "InviteName"
	name_edit.placeholder_text = "Имя героя или логин…"; name_edit.max_length = 40
	name_edit.add_theme_font_size_override("font_size", 24)
	UIK.expand(name_edit); ir.add_child(name_edit)
	name_edit.text_submitted.connect(func(_t): _invite_typed())
	var ib := UIK.button(ir, "Пригласить по имени", _invite_typed, UIK.GREEN, 24)
	ib.disabled = not can_inv; name_edit.editable = can_inv
	if not can_inv: UIK.label(body, "Приглашать может только лидер группы" if mem.size() < Net.PARTY_MAX else "Группа полная", 22, UIK.MUTED)
	UIK.label(body, "Игроки в сети: %d" % (Net.remotes.size() + 1), 30, UIK.ACCENT)
	var any := false
	for id in Net.remotes:
		var nm := str(Net.remotes[id].name)
		if in_party.has(nm): continue
		any = true
		var r := _row()
		UIK.expand(UIK.label(r, "%s — ур. %d" % [nm, int(Net.remotes[id].get("level", 1))], 25))
		var b := UIK.button(r, "Пригласить", Net.party_invite.bind(nm), UIK.GREEN, 24)
		b.disabled = Net.in_party() and not Net.is_leader() or mem.size() >= Net.PARTY_MAX
	if not any: UIK.label(body, "Больше никого нет в сети", 24, UIK.MUTED)

func _invite_typed() -> void:
	if name_edit == null: return
	var n := name_edit.text.strip_edges()
	if n == "": Game.toast("Введите имя игрока", 1.5); return
	Net.party_invite(n)
	name_edit.text = ""
	name_edit.release_focus()

# ---------- v0.9.3: проверка готовности ----------
var rc_win: Panel
var rc_title: Label
var rc_list: Label
var rc_yes: Button
var rc_no: Button
var rc_left := 0.0

func _build_rc(root: Control) -> void:
	rc_win = UIK.panel(root, Color(0.05, 0.05, 0.09, 0.94), 12); rc_win.name = "ReadyCheck"
	rc_win.anchor_left = 0.5; rc_win.anchor_right = 0.5; rc_win.anchor_top = 0.22; rc_win.anchor_bottom = 0.22
	rc_win.offset_left = -330; rc_win.offset_right = 330; rc_win.offset_bottom = 300
	rc_title = UIK.label(rc_win, "", 28, UIK.ACCENT); UIK.rect(rc_title, Vector2(20, 12), Vector2(620, 80))
	rc_list = UIK.label(rc_win, "", 22); UIK.rect(rc_list, Vector2(20, 96), Vector2(620, 110))
	rc_yes = UIK.button(rc_win, "Готов", func(): Net.rc_answer(true); rc_yes.disabled = true; rc_no.disabled = true, UIK.GREEN, 26); rc_yes.name = "RcYes"
	UIK.rect(rc_yes, Vector2(20, 214), Vector2(300, 70))
	rc_no = UIK.button(rc_win, "Не готов", func(): Net.rc_answer(false); rc_win.visible = false, UIK.RED, 26); rc_no.name = "RcNo"
	UIK.rect(rc_no, Vector2(340, 214), Vector2(300, 70))
	rc_win.visible = false
	if zone and zone.hud: zone.hud.blockers.append(rc_win)
	else: _pending_blockers.append(rc_win)

func _on_rc_ask(did: String, leader: String, secs: float) -> void:
	rc_left = secs
	rc_title.text = "%s ведёт группу в «%s». Вы готовы?" % [leader, RaidDefs.DUNGEONS[did].name if RaidDefs.DUNGEONS.has(did) else did]
	rc_yes.visible = true; rc_no.visible = true; rc_yes.disabled = false; rc_no.disabled = false
	rc_win.visible = true; UIK.pop_in(rc_win)

func _on_rc_state(did: String, st: Dictionary, phase: String) -> void:
	var nm: String = RaidDefs.DUNGEONS[did].name if RaidDefs.DUNGEONS.has(did) else did
	var lines := []
	for n in st: lines.append(("✔ " if st[n] else "… ") + str(n))
	rc_list.text = "  ".join(lines)
	if phase == "wait":
		if not rc_win.visible:   # лидер: ждём остальных
			rc_title.text = "Проверка готовности: «%s»" % nm
			rc_yes.visible = false; rc_no.visible = false
			rc_left = RaidDefs.READY_TIME
			rc_win.visible = true
	else:
		rc_win.visible = false
		Game.toast("Группа готова — вход в «%s»" % nm if phase == "go" else "Вход в «%s» отменён" % nm, 2.5)

func _dungeon_tab_unused() -> void:
	var in_raid: bool = zone != null and zone.is_raid()
	if in_raid:
		UIK.label(body, "Вы в подземелье «%s»" % DB.ZONES[zone.data.zone].name, 30, UIK.ACCENT)
		UIK.button(body, "Выйти из подземелья", func(): close(); zone.raid.leave(), UIK.RED, 26)
		return
	var n := maxi(1, (Net.party.get("members", []) as Array).size()) if Net.in_game else 1
	UIK.label(body, "Групповые подземелья: босс со сложными механиками, комплекты рейда. Здоровье врагов — ×%.2f под группу из %d." % [RaidDefs.party_k(n), n], 24, UIK.MUTED)
	var kills: Dictionary = zone.data.get("raid_kills", {}) if zone else {}
	for did in RaidDefs.ORDER:
		var d: Dictionary = RaidDefs.DUNGEONS[did]
		var p := UIK.panel(body, Color(0.1, 0.08, 0.12, 0.85), 10)
		p.custom_minimum_size = Vector2(0, 200)
		var t := UIK.label(p, "%s   [побед: %d]" % [d.name, int(kills.get(did, 0))], 30, UIK.ACCENT)
		var cd: Dictionary = zone.data if zone else Game.current
		var lk := DB.dungeon_lock(cd, did)
		var inf := UIK.label(p, DB.dungeon_info(cd, did) if lk == "" else lk, 21, UIK.GOLD if lk == "" else UIK.RED)   # v0.9.2
		UIK.rect(inf, Vector2(560, 14), Vector2(500, 32))
		UIK.rect(t, Vector2(20, 8), Vector2(800, 44))
		var ds := UIK.label(p, String(d.desc), 22)
		UIK.rect(ds, Vector2(20, 54), Vector2(820, 136))
		var set_name: String = Items.SETS[d.set].name
		var sl := UIK.label(p, "Добыча: «%s»" % set_name, 21, Color(0.6, 1.0, 0.6))
		UIK.rect(sl, Vector2(20, 160), Vector2(820, 32))
		var can := not Net.in_game or not Net.in_party() or Net.is_leader()
		var b := UIK.button(p, ("Войти группой" if Net.in_party() else "Войти соло") if can else "Ведёт лидер", _enter.bind(did), UIK.GREEN, 26)
		UIK.rect(b, Vector2(856, 60), Vector2(210, 80))
		b.disabled = not can or lk != ""

func _enter(did: String) -> void:
	close()
	Net.raid_enter(did)
