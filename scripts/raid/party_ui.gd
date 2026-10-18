extends CanvasLayer
class_name PartyUI
## v0.8.0: рамки группы (имя, уровень, здоровье — для телефона и ПК) и окно «Группа / Подземелья»:
## приглашения, вступление, выход, исключение (лидер), вход в групповые подземелья (лидер ведёт группу;
## один игрок тоже может войти — здоровье врагов масштабируется под размер группы). Клавиша G.

var zone
var btn: Button
var frames: VBoxContainer
var win: Panel
var body: VBoxContainer
var tab := "dungeons"
var _t := 0.0
static var preview := false   # снимки/тесты: показать рамки из Net.party без сервера

func _ready() -> void:
	layer = 41
	var root := Control.new(); root.set_anchors_preset(Control.PRESET_FULL_RECT); root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	btn = UIK.button(root, "Группа" if Net.in_game else "Подземелья", toggle, UIK.PURPLE, 24, "crossed-swords")
	btn.custom_minimum_size = Vector2(0, 48)
	btn.anchor_top = 0.3; btn.anchor_bottom = 0.3
	btn.offset_left = 144 if Net.in_game else 24; btn.offset_right = btn.offset_left + 210; btn.offset_bottom = 52
	frames = VBoxContainer.new()
	frames.add_theme_constant_override("separation", 6)
	frames.anchor_top = 0.36; frames.anchor_bottom = 0.36
	frames.offset_left = 24; frames.offset_right = 24 + 330
	frames.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(frames)
	win = UIK.panel(root)
	win.anchor_left = 0.5; win.anchor_right = 0.5; win.anchor_top = 0.5; win.anchor_bottom = 0.5
	win.offset_left = -560; win.offset_right = 560; win.offset_top = -380; win.offset_bottom = 380
	var head := UIK.hbox(win, 64)
	UIK.rect(head, Vector2(24, 18), Vector2(1072, 64))
	if Net.in_game: UIK.button(head, "Группа", func(): tab = "party"; refresh(), UIK.BUTTON, 26, "three-friends")
	UIK.button(head, "Подземелья", func(): tab = "dungeons"; refresh(), UIK.BUTTON, 26, "dungeon-gate")
	var sp := Control.new(); UIK.expand(sp); head.add_child(sp)
	UIK.button(head, "Закрыть", toggle, UIK.RED, 26)
	var holder := Control.new(); win.add_child(holder)
	UIK.rect(holder, Vector2(10, 92), Vector2(1100, 650))
	body = UIK.scroll_list(holder, 12)
	win.visible = false
	Net.party_changed.connect(refresh)
	Net.roster_changed.connect(refresh)
	refresh()

func toggle() -> void:
	win.visible = not win.visible
	if win.visible:
		if Net.in_game and (not Net.party_invites.is_empty() or tab == ""): tab = "party"
		refresh()
		UIK.pop_in(win)

func _unhandled_input(e: InputEvent) -> void:
	if (e is InputEventKey or e is InputEventMouseButton) and e.pressed and not (e is InputEventKey and e.echo) and Controls.action_of(e) == "party":
		var fo = get_viewport().gui_get_focus_owner()
		if fo is LineEdit: return
		toggle(); get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0: return
	_t = 0.25
	_frames()
	if Net.in_game:
		btn.text = "Группа" + (" (%d)" % (Net.party.members.size()) if Net.in_party() else "") + (" !" if not Net.party_invites.is_empty() else "")

# ---------- рамки группы ----------
func _frames() -> void:
	var mem: Array = Net.party.get("members", []) if (Net.in_game or preview) else []
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
		var zl: Label = f.get_node("Zone")
		var zk := str(m.zone)
		zl.text = "погиб" if hpf <= 0.0 else (DB.ZONES[zk].name if DB.ZONES.has(zk) else zk)
		zl.add_theme_color_override("font_color", Color(1, 0.4, 0.35) if hpf <= 0.0 else UIK.MUTED)

func _frame() -> Control:
	var p := UIK.panel(frames, Color(0.05, 0.05, 0.07, 0.78), 8)
	p.custom_minimum_size = Vector2(330, 70)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nl := UIK.label(p, "", 21); nl.name = "Name"; nl.autowrap_mode = TextServer.AUTOWRAP_OFF
	nl.clip_text = true
	UIK.rect(nl, Vector2(10, 2), Vector2(312, 30))
	var b := UIK.bar(p, Color(0.2, 0.75, 0.3)); b.name = "Hp"
	UIK.rect(b, Vector2(10, 34), Vector2(200, 26))
	var zl := UIK.label(p, "", 17, UIK.MUTED); zl.name = "Zone"; zl.autowrap_mode = TextServer.AUTOWRAP_OFF; zl.clip_text = true
	UIK.rect(zl, Vector2(216, 34), Vector2(108, 26))
	return p

# ---------- окно ----------
func refresh() -> void:
	if body == null or not win.visible: return
	UIK.clear(body)
	if tab == "party" and Net.in_game: _party_tab()
	else: _dungeon_tab()

func _row(h := 64.0) -> HBoxContainer: return UIK.hbox(body, h, 12)

func _party_tab() -> void:
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
	UIK.label(body, "Игроки в сети", 30, UIK.ACCENT)
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

func _dungeon_tab() -> void:
	var in_raid: bool = zone != null and zone.is_raid()
	if in_raid:
		UIK.label(body, "Вы в подземелье «%s»" % DB.ZONES[zone.data.zone].name, 30, UIK.ACCENT)
		UIK.button(body, "Выйти в долину", func(): toggle(); zone.raid.leave(), UIK.RED, 26)
		return
	var n := maxi(1, (Net.party.get("members", []) as Array).size()) if Net.in_game else 1
	UIK.label(body, "Групповые подземелья: босс со сложными механиками, комплекты рейда. Здоровье врагов — ×%.2f под группу из %d." % [RaidDefs.party_k(n), n], 24, UIK.MUTED)
	var kills: Dictionary = zone.data.get("raid_kills", {}) if zone else {}
	for did in RaidDefs.ORDER:
		var d: Dictionary = RaidDefs.DUNGEONS[did]
		var p := UIK.panel(body, Color(0.1, 0.08, 0.12, 0.85), 10)
		p.custom_minimum_size = Vector2(0, 200)
		var t := UIK.label(p, "%s   [побед: %d]" % [d.name, int(kills.get(did, 0))], 30, UIK.ACCENT)
		UIK.rect(t, Vector2(20, 8), Vector2(800, 44))
		var ds := UIK.label(p, String(d.desc), 22)
		UIK.rect(ds, Vector2(20, 54), Vector2(820, 136))
		var set_name: String = Items.SETS[d.set].name
		var sl := UIK.label(p, "Добыча: «%s»" % set_name, 21, Color(0.6, 1.0, 0.6))
		UIK.rect(sl, Vector2(20, 160), Vector2(820, 32))
		var can := not Net.in_game or not Net.in_party() or Net.is_leader()
		var b := UIK.button(p, ("Войти группой" if Net.in_party() else "Войти соло") if can else "Ведёт лидер", _enter.bind(did), UIK.GREEN, 26)
		UIK.rect(b, Vector2(856, 60), Vector2(210, 80))
		b.disabled = not can

func _enter(did: String) -> void:
	win.visible = false
	Net.raid_enter(did)
