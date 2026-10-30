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
	btn.visible = false; dbtn.visible = false   # v0.9.4: открываются из общего «Меню» HUD (и клавишей G)
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
	_build_win(root)
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
	_hide_tip()
	if inv_pan: inv_pan.visible = false
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
	if inv_pan: inv_pan.visible = false
	_layout_win()
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
	_sync_invite()
	if win.visible: _update_rows()
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

# ---------- v0.9.4.1: окно «Группа» по утверждённому макету (камень + золото) ----------
var win_k := 1.0                 # масштаб: ПК 1.0, телефон крупнее (под палец)
var title_l: Label
var head_area: Control
var list_scroll: ScrollContainer
var b_inv: Button
var b_kick: Button
var b_prom: Button
var b_leave: Button
var inv_pan: Panel
var inv_list: VBoxContainer
var ipop: Panel
var ipop_text: Label
var ipop_pid := 0
var sel_name := ""
var _tip: Control
var _wdrag := false
var _wdrag_off := Vector2.ZERO
var win_pos := Vector2(-1, -1)
const STONE := Color(0.11, 0.105, 0.1, 0.97)
const GOLD_LINE := Color(0.78, 0.6, 0.3)
const GOLD_DARK := Color(0.45, 0.33, 0.16)
const BTN_GREEN := Color(0.28, 0.6, 0.22)
const BTN_RED := Color(0.72, 0.18, 0.14)
const BTN_GOLD := Color(0.66, 0.46, 0.18)
const BTN_GREY := Color(0.42, 0.42, 0.44)
const CLASS_EMBLEM := {"warrior": "visored-helm", "mage": "ui-hood", "archer": "pocket-bow"}

static func stone_box(bg := STONE, border := 3, bc := GOLD_LINE, radius := 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg; s.set_corner_radius_all(radius)
	s.set_border_width_all(border); s.border_color = bc
	s.shadow_color = Color(0, 0, 0, 0.55); s.shadow_size = 14; s.shadow_offset = Vector2(0, 6)
	s.anti_aliasing = true
	return s

## Кнопка в стиле макета: цветная плашка с золотистой кромкой, иконка + подпись
func _mk_btn(parent: Node, text: String, ic: String, col: Color, cb: Callable, tip: String) -> Button:
	var b := UIK.button(parent, text, cb, col, int(25 * win_k), ic)
	for st in ["normal", "hover", "pressed"]:
		var c: Color = col if st == "normal" else (col.lightened(0.15) if st == "hover" else col.darkened(0.25))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(c.r * 0.8, c.g * 0.8, c.b * 0.8, 0.98); sb.set_corner_radius_all(6)
		sb.set_border_width_all(2); sb.border_color = GOLD_DARK.lightened(0.25)
		sb.border_width_top = 3; sb.border_color = Color(minf(c.r * 1.4 + 0.1, 1), minf(c.g * 1.4 + 0.1, 1), minf(c.b * 1.4 + 0.1, 1))
		sb.content_margin_left = 12; sb.content_margin_right = 12
		b.add_theme_stylebox_override(st, sb)
	b.custom_minimum_size.y = 72 * win_k
	b.add_theme_constant_override("icon_max_width", int(30 * win_k))
	b.set_meta("tip", tip)
	b.mouse_entered.connect(_show_tip.bind(b))
	b.mouse_exited.connect(_hide_tip)
	return b

func _show_tip(c: Control) -> void:
	_hide_tip()
	if not c.has_meta("tip") or not c.is_visible_in_tree(): return
	var tt: Array = str(c.get_meta("tip")).split("|")
	_tip = UIK.tooltip(ui_root, tt[0], tt[1] if tt.size() > 1 else "", "", UIK.ACCENT, 460.0 * win_k)
	_tip.z_index = 20
	UIK.place_tooltip(_tip, c.get_global_rect(), get_viewport().get_visible_rect().size)

func _hide_tip() -> void:
	if _tip and is_instance_valid(_tip): _tip.queue_free()
	_tip = null

## Золотые уголки рамки
func _corners(c: Control, len := 46.0, w := 4.0) -> void:
	var o := Control.new(); o.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(o); UIK.full(o)
	o.draw.connect(func():
		var sz: Vector2 = o.size
		for cx in [0, 1]:
			for cy in [0, 1]:
				var p := Vector2(6 + cx * (sz.x - 12), 6 + cy * (sz.y - 12))
				var dx := 1.0 if cx == 0 else -1.0
				var dy := 1.0 if cy == 0 else -1.0
				o.draw_line(p, p + Vector2(len * dx, 0), GOLD_LINE, w)
				o.draw_line(p, p + Vector2(0, len * dy), GOLD_LINE, w)
				o.draw_line(p + Vector2(10 * dx, 10 * dy), p + Vector2(len * 0.6 * dx, 10 * dy), GOLD_DARK, 2)
				o.draw_line(p + Vector2(10 * dx, 10 * dy), p + Vector2(10 * dx, len * 0.6 * dy), GOLD_DARK, 2)
				var d := p + Vector2(4 * dx, 4 * dy)
				o.draw_colored_polygon(PackedVector2Array([d + Vector2(0, -7), d + Vector2(7, 0), d + Vector2(0, 7), d + Vector2(-7, 0)]), Color(0.95, 0.78, 0.4)))
	o.resized.connect(o.queue_redraw)

func _build_win(root: Control) -> void:
	win_k = 1.0 if Game.desktop else 1.3
	var k := win_k
	win = Panel.new(); win.name = "PartyWin"
	win.add_theme_stylebox_override("panel", stone_box())
	root.add_child(win)
	win.mouse_filter = Control.MOUSE_FILTER_STOP
	_corners(win)
	# заголовок: значок меню, «Группа (N/5)», золотой крестик
	head_area = Control.new(); head_area.name = "Head"; win.add_child(head_area)
	head_area.mouse_filter = Control.MOUSE_FILTER_STOP
	if Game.desktop:
		head_area.mouse_default_cursor_shape = Control.CURSOR_MOVE
		head_area.gui_input.connect(_win_head_input)
	var menu := Control.new(); menu.mouse_filter = Control.MOUSE_FILTER_IGNORE; head_area.add_child(menu)
	menu.position = Vector2(26 * k, 22 * k); menu.size = Vector2(40 * k, 36 * k)
	menu.draw.connect(func():
		for i in 3: menu.draw_rect(Rect2(0, i * 13 * k, 40 * k, 7 * k), Color(0.9, 0.72, 0.38)))
	title_l = UIK.label(head_area, "Группа", int(38 * k), Color(0.97, 0.86, 0.6), HORIZONTAL_ALIGNMENT_CENTER)
	title_l.name = "Title"; title_l.add_theme_font_override("font", UIK.title_font())
	title_l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9)); title_l.add_theme_constant_override("outline_size", 6)
	title_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var x := Button.new(); x.name = "Close"; x.focus_mode = Control.FOCUS_NONE; head_area.add_child(x)
	x.icon = UIK.icon("ui-cross"); x.expand_icon = true
	x.add_theme_color_override("icon_normal_color", Color(0.95, 0.78, 0.4)); x.add_theme_color_override("icon_hover_color", Color(1, 0.9, 0.6))
	for st in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.16, 0.13, 0.1) if st != "hover" else Color(0.24, 0.19, 0.12)
		sb.set_corner_radius_all(6); sb.set_border_width_all(2); sb.border_color = GOLD_LINE
		sb.content_margin_left = 10 * k; sb.content_margin_right = 10 * k; sb.content_margin_top = 10 * k; sb.content_margin_bottom = 10 * k
		x.add_theme_stylebox_override(st, sb)
	x.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	x.pressed.connect(close)
	x.set_meta("tip", "Закрыть|Клавиша G тоже закрывает окно")
	x.mouse_entered.connect(_show_tip.bind(x)); x.mouse_exited.connect(_hide_tip)
	var sep := ColorRect.new(); sep.name = "Sep"; sep.color = GOLD_DARK; sep.mouse_filter = Control.MOUSE_FILTER_IGNORE; win.add_child(sep)
	# список участников
	list_scroll = ScrollContainer.new(); list_scroll.name = "List"; win.add_child(list_scroll)
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body = VBoxContainer.new(); body.add_theme_constant_override("separation", int(10 * k))
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(body)
	# кнопки
	var bar := HBoxContainer.new(); bar.name = "Buttons"; bar.add_theme_constant_override("separation", int(12 * k)); win.add_child(bar)
	b_inv = _mk_btn(bar, "Пригласить", "ui-plus", BTN_GREEN, _open_invite, "Пригласить|Позвать игрока по имени или из списка игроков рядом. Приглашает лидер (или вы, если пока один).")
	b_kick = _mk_btn(bar, "Исключить", "ui-cross", BTN_RED, _kick_sel, "Исключить|Выберите участника в списке, затем нажмите. Только для лидера.")
	b_prom = _mk_btn(bar, "Передать лидерство", "ui-crown", BTN_GOLD, _promote_sel, "Передать лидерство|Выбранный участник станет лидером группы.")
	b_leave = _mk_btn(bar, "Покинуть", "ui-exit", BTN_GREY, _leave_party, "Покинуть|Выйти из группы. Если останется один человек — группа распадётся.")
	for b in [b_inv, b_kick, b_prom, b_leave]: UIK.expand(b, 1.45 if b == b_prom else 1.0)
	b_inv.name = "BtnInvite"; b_kick.name = "BtnKick"; b_prom.name = "BtnPromote"; b_leave.name = "BtnLeave"
	_build_invite_panel()
	win.visible = false
	_build_popup(root)
	if Game.desktop:
		var cf := ConfigFile.new()
		if cf.load(LAYOUT) == OK: win_pos = cf.get_value("party", "win_pos", win_pos)
	get_viewport().size_changed.connect(_layout_win)
	_layout_win()

func _win_size() -> Vector2:
	var vs := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1920, 1080)
	return Vector2(minf(1000.0 * win_k, vs.x - 40), minf(800.0 * win_k, vs.y - 40))

func _layout_win() -> void:
	if win == null: return
	var k := win_k
	var vs := get_viewport().get_visible_rect().size
	var sz := _win_size()
	win.size = sz
	var p := (vs - sz) / 2
	if Game.desktop and win_pos.x >= 0: p = win_pos
	win.position = Vector2(clampf(p.x, 0, vs.x - sz.x), clampf(p.y, 0, vs.y - sz.y))
	var hh := 80.0 * k
	head_area.position = Vector2.ZERO; head_area.size = Vector2(sz.x, hh)
	title_l.position = Vector2(80 * k, 10 * k); title_l.size = Vector2(sz.x - 160 * k, hh - 16 * k)
	var x: Control = head_area.get_node("Close")
	x.size = Vector2(58, 58) * k; x.position = Vector2(sz.x - 80 * k, 12 * k)
	var sep: Control = win.get_node("Sep"); sep.position = Vector2(24 * k, hh); sep.size = Vector2(sz.x - 48 * k, 2)
	var bh := 76.0 * k
	list_scroll.position = Vector2(24 * k, hh + 14 * k); list_scroll.size = Vector2(sz.x - 48 * k, sz.y - hh - bh - 50 * k)
	var bar: Control = win.get_node("Buttons"); bar.position = Vector2(24 * k, sz.y - bh - 22 * k); bar.size = Vector2(sz.x - 48 * k, bh)
	inv_pan.position = list_scroll.position; inv_pan.size = list_scroll.size
	var ps := Vector2(560, 270) * k
	ipop.size = ps
	ipop.position = Vector2(vs.x - ps.x - 40, clampf(vs.y * 0.3, 20, vs.y - ps.y - 20))
	if win.visible and win.size.x > 0: win.queue_redraw()

func _win_head_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		_wdrag = ev.pressed
		_wdrag_off = win.get_global_mouse_position() - win.position
		if not ev.pressed:
			win_pos = win.position
			var cf := ConfigFile.new(); cf.load(LAYOUT)
			cf.set_value("party", "win_pos", win_pos); cf.save(LAYOUT)
		head_area.accept_event()
	elif ev is InputEventMouseMotion and _wdrag:
		var vs := get_viewport().get_visible_rect().size
		var p: Vector2 = win.get_global_mouse_position() - _wdrag_off
		win.position = Vector2(clampf(p.x, 0, vs.x - win.size.x), clampf(p.y, 0, vs.y - win.size.y))
		head_area.accept_event()

## Строка участника: эмблема класса в золотом кольце, имя (+корона лидера), уровень, статус, полосы HP/MP
func _member_row(m: Dictionary) -> Control:
	var k := win_k
	var lead := int(m.id) == int(Net.party.get("leader", 0))
	var me := int(m.id) == Net.my_id
	var sel := str(m.name) == sel_name
	var r := Panel.new(); r.name = "Row_" + str(m.name)
	r.custom_minimum_size = Vector2(0, 132 * k)
	r.add_theme_stylebox_override("panel", stone_box(Color(0.07, 0.065, 0.06, 0.95) if not sel else Color(0.17, 0.13, 0.07, 0.97), 2, GOLD_DARK if not sel else Color(0.98, 0.8, 0.4), 6))
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	r.gui_input.connect(_row_input.bind(str(m.name), int(m.id)))
	r.set_meta("pid", int(m.id)); r.set_meta("name", str(m.name))
	body.add_child(r)
	# эмблема
	var es := 96.0 * k
	var em := Panel.new(); em.mouse_filter = Control.MOUSE_FILTER_IGNORE; r.add_child(em)
	var eb := StyleBoxFlat.new(); eb.bg_color = Color(0.17, 0.12, 0.08); eb.set_corner_radius_all(int(es / 2))
	eb.set_border_width_all(int(4 * k)); eb.border_color = Color(0.86, 0.66, 0.3); eb.anti_aliasing = true
	eb.shadow_color = Color(0, 0, 0, 0.5); eb.shadow_size = 4
	em.add_theme_stylebox_override("panel", eb)
	em.position = Vector2(16 * k, (132 * k - es) / 2); em.size = Vector2(es, es)
	var ic := UIK.icon_rect(em, CLASS_EMBLEM.get(str(m.cls), "visored-helm"), es * 0.58, Color(0.96, 0.84, 0.58))
	ic.position = Vector2(es * 0.21, es * 0.21); ic.size = Vector2(es * 0.58, es * 0.58)
	# имя + корона
	var x0 := 16 * k + es + 20 * k
	var nl := UIK.label(r, str(m.name), int(30 * k), UIK.ACCENT if me else Color(0.97, 0.92, 0.82)); nl.name = "Name"
	nl.add_theme_font_override("font", UIK.title_font()); nl.autowrap_mode = TextServer.AUTOWRAP_OFF
	nl.position = Vector2(x0, 10 * k); nl.size = Vector2(250 * k, 42 * k)
	if lead:
		var tw := nl.get_theme_font("font").get_string_size(str(m.name), HORIZONTAL_ALIGNMENT_LEFT, -1, int(30 * k)).x
		var cr := UIK.icon_rect(r, "ui-crown", 30 * k, Color(1.0, 0.8, 0.3)); cr.name = "Crown"
		cr.position = Vector2(x0 + tw + 10 * k, 16 * k)
	var lv := UIK.label(r, "Ур. %d" % int(m.lvl), int(22 * k), Color(0.82, 0.76, 0.66)); lv.name = "Lvl"
	lv.position = Vector2(x0, 52 * k); lv.size = Vector2(200 * k, 30 * k)
	var dot := Panel.new(); dot.name = "Dot"; dot.mouse_filter = Control.MOUSE_FILTER_IGNORE; r.add_child(dot)
	dot.position = Vector2(x0 + 2 * k, 94 * k); dot.size = Vector2(16, 16) * k
	var st := UIK.label(r, "", int(21 * k), Color(0.6, 0.9, 0.5)); st.name = "Status"; st.autowrap_mode = TextServer.AUTOWRAP_OFF
	st.clip_text = true; st.position = Vector2(x0 + 26 * k, 84 * k); st.size = Vector2(240 * k, 32 * k)
	# полосы
	var bx := x0 + 270 * k
	var bw: float = maxf(180.0, _win_size().x - 48 * k - bx - 24 * k)
	var hp := _bar(r, Color(0.78, 0.13, 0.12)); hp.name = "Hp"; hp.position = Vector2(bx, 26 * k); hp.size = Vector2(bw, 36 * k)
	var mp := _bar(r, Color(0.18, 0.4, 0.85)); mp.name = "Mp"; mp.position = Vector2(bx, 72 * k); mp.size = Vector2(bw, 36 * k)
	_fill_row(r, m)
	return r

func _bar(parent: Control, col: Color) -> ProgressBar:
	var b := UIK.bar(parent, col)
	var bg := StyleBoxFlat.new(); bg.bg_color = Color(0.03, 0.03, 0.03, 0.9); bg.set_corner_radius_all(4)
	bg.set_border_width_all(2); bg.border_color = Color(0.32, 0.26, 0.18)
	b.add_theme_stylebox_override("background", bg)
	var f := StyleBoxFlat.new(); f.bg_color = col; f.set_corner_radius_all(3)
	f.border_width_top = 3; f.border_color = col.lightened(0.35)
	f.expand_margin_left = -2; f.expand_margin_right = -2; f.expand_margin_top = -2; f.expand_margin_bottom = -2
	b.add_theme_stylebox_override("fill", f)
	var l: Label = b.get_node("Text"); l.add_theme_font_size_override("font_size", int(21 * win_k))
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95)); l.add_theme_constant_override("outline_size", 5)
	b.max_value = 1.0
	return b

func _fill_row(r: Control, m: Dictionary) -> void:
	var me := int(m.id) == Net.my_id
	var hpf := float(m.get("hp", 1.0)); var mpf := float(m.get("mp", 1.0))
	var hpm := float(m.get("hpm", 0)); var mpm := float(m.get("mpm", 0))
	if me and zone and zone.player and not preview:
		hpm = float(zone.player.stats.max_hp); mpm = float(zone.player.stats.max_mp)
		hpf = zone.player.hp / maxf(1.0, hpm); mpf = zone.player.mp / maxf(1.0, mpm)
	var hb: ProgressBar = r.get_node("Hp"); hb.value = hpf
	var mb: ProgressBar = r.get_node("Mp"); mb.value = mpf
	(hb.get_node("Text") as Label).text = "%d / %d" % [roundi(hpf * hpm), roundi(hpm)] if hpm > 0 else "%d%%" % roundi(hpf * 100)
	(mb.get_node("Text") as Label).text = "%d / %d" % [roundi(mpf * mpm), roundi(mpm)] if mpm > 0 else "%d%%" % roundi(mpf * 100)
	var zk := str(m.get("zone", ""))
	var txt := "В сети"; var col := Color(0.35, 0.85, 0.3)
	if hpf <= 0.0: txt = "Погиб"; col = Color(0.9, 0.3, 0.25)
	elif zk == "dungeon" or zk.begins_with("pd_") or (DB.ZONES.has(zk) and RaidDefs.DUNGEONS.has(zk)):
		txt = "В подземелье"; col = Color(0.7, 0.45, 0.95)
	elif zone and zone.data and zk != "" and zk != str(zone.data.get("zone", "")) and DB.ZONES.has(zk):
		txt = "В сети · " + str(DB.ZONES[zk].name)
	var st: Label = r.get_node("Status"); st.text = txt; st.add_theme_color_override("font_color", col.lightened(0.15))
	var d: Panel = r.get_node("Dot")
	var db := StyleBoxFlat.new(); db.bg_color = col; db.set_corner_radius_all(10); db.anti_aliasing = true
	db.shadow_color = Color(col.r, col.g, col.b, 0.6); db.shadow_size = 4
	d.add_theme_stylebox_override("panel", db)

func _update_rows() -> void:
	if inv_pan and inv_pan.visible: return
	var mem: Array = Net.party.get("members", [])
	var byname := {}
	for m in mem: byname[str(m.name)] = m
	for r in body.get_children():
		if r.has_meta("name") and byname.has(str(r.get_meta("name"))): _fill_row(r, byname[str(r.get_meta("name"))])

func _row_input(ev: InputEvent, nm: String, pid: int) -> void:
	if not (ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed): return
	if DragScroll.dragging: return
	sel_name = "" if sel_name == nm or pid == Net.my_id else nm
	Game.sfx("click")
	refresh()

func refresh() -> void:
	if body == null: return
	_sync_invite()
	if not win.visible: return
	var mem: Array = Net.party.get("members", []) if Net.in_game else []
	title_l.text = "Группа (%d/%d)" % [maxi(1, mem.size()), Net.PARTY_MAX]
	var names := []
	for m in mem: names.append(str(m.name))
	if not names.has(sel_name): sel_name = ""
	UIK.clear(body)
	var k := win_k
	if zone != null and zone.has_method("is_raid") and zone.is_raid():
		var rr := HBoxContainer.new(); rr.add_theme_constant_override("separation", int(12 * k)); body.add_child(rr)
		UIK.expand(UIK.label(rr, "Вы в подземелье «%s»" % DB.ZONES[zone.data.zone].name, int(26 * k), UIK.ACCENT))
		var lb := _mk_btn(rr, "Выйти", "ui-exit", BTN_RED, func(): close(); zone.raid.leave(), "Выйти из подземелья|Вернуться в мир")
		lb.custom_minimum_size = Vector2(200 * k, 60 * k)
	if not Net.in_game:
		_empty_state("Группы доступны в онлайн-режиме", "Войдите в аккаунт в главном меню («Онлайн»), чтобы приглашать игроков, видеть участников и ходить в подземелья вместе.")
	elif mem.is_empty():
		_empty_state("Вы пока играете один", "Нажмите «Пригласить» внизу: введите имя героя или выберите игрока рядом. В группе до %d человек — общий опыт, рамки союзников и вход в подземелья вместе." % Net.PARTY_MAX)
	else:
		for m in mem: _member_row(m)
		if Net.is_leader() and mem.size() > 1 and sel_name == "":
			UIK.label(body, "Нажмите на участника, чтобы исключить его или передать лидерство", int(20 * k), UIK.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	var lead := Net.is_leader()
	var can_inv: bool = Net.in_game and (not Net.in_party() or lead) and mem.size() < Net.PARTY_MAX
	_set_on(b_inv, can_inv)
	_set_on(b_kick, lead and sel_name != "")
	_set_on(b_prom, lead and sel_name != "")
	_set_on(b_leave, Net.in_party())

## Неактивная кнопка остаётся нажимаемой — по нажатию объясняет, почему сейчас нельзя
func _set_on(b: Button, on: bool) -> void:
	b.set_meta("on", on)
	b.modulate = Color.WHITE if on else Color(0.62, 0.62, 0.62, 0.85)

func _why_off(b: Button) -> bool:
	if bool(b.get_meta("on", true)): return false
	var why := ""
	if not Net.in_game: why = "Группы доступны только в онлайн-режиме"
	elif b == b_inv: why = "Группа полная" if (Net.party.get("members", []) as Array).size() >= Net.PARTY_MAX else "Приглашать может только лидер группы"
	elif b == b_leave: why = "Вы не в группе"
	elif not Net.is_leader(): why = "Это может только лидер группы"
	else: why = "Сначала выберите участника в списке"
	Game.toast(why, 1.8)
	return true

func _empty_state(t: String, hint: String) -> void:
	var k := win_k
	var p := Panel.new(); p.name = "Empty"; p.custom_minimum_size = Vector2(0, 300 * k)
	p.add_theme_stylebox_override("panel", stone_box(Color(0.07, 0.065, 0.06, 0.9), 2, GOLD_DARK, 6))
	body.add_child(p)
	var em := UIK.icon_rect(p, "three-friends", 110 * k, Color(0.86, 0.66, 0.3, 0.9))
	em.position = Vector2((_win_size().x - 48 * k) / 2 - 55 * k, 24 * k)
	var tl := UIK.label(p, t, int(30 * k), UIK.ACCENT, HORIZONTAL_ALIGNMENT_CENTER); tl.add_theme_font_override("font", UIK.title_font())
	tl.position = Vector2(20, 140 * k); tl.size = Vector2(_win_size().x - 48 * k - 40, 44 * k)
	var hl := UIK.label(p, hint, int(22 * k), Color(0.82, 0.76, 0.66), HORIZONTAL_ALIGNMENT_CENTER); hl.name = "Hint"
	hl.position = Vector2(40, 188 * k); hl.size = Vector2(_win_size().x - 48 * k - 80, 100 * k)

func _kick_sel() -> void:
	if _why_off(b_kick): return
	Net.party_kick(sel_name); sel_name = ""

func _promote_sel() -> void:
	if _why_off(b_prom): return
	Net.party_promote(sel_name); sel_name = ""

func _leave_party() -> void:
	if _why_off(b_leave): return
	Net.party_leave()

# ----- панель приглашения: по имени + игроки рядом -----
func _build_invite_panel() -> void:
	var k := win_k
	inv_pan = Panel.new(); inv_pan.name = "InvitePanel"
	inv_pan.add_theme_stylebox_override("panel", stone_box(Color(0.08, 0.075, 0.07, 0.99), 2, GOLD_LINE, 6))
	win.add_child(inv_pan); inv_pan.visible = false
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", int(12 * k)); inv_pan.add_child(v)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 20 * k; v.offset_right = -20 * k; v.offset_top = 16 * k; v.offset_bottom = -16 * k
	var hl := UIK.label(v, "Пригласить в группу", int(28 * k), UIK.ACCENT); hl.add_theme_font_override("font", UIK.title_font())
	var ir := HBoxContainer.new(); ir.add_theme_constant_override("separation", int(10 * k)); v.add_child(ir)
	name_edit = LineEdit.new(); name_edit.name = "InviteName"
	name_edit.placeholder_text = "Имя героя или логин…"; name_edit.max_length = 40
	name_edit.add_theme_font_size_override("font_size", int(24 * k))
	name_edit.custom_minimum_size.y = 64 * k
	UIK.expand(name_edit); ir.add_child(name_edit)
	name_edit.text_submitted.connect(func(_t): _invite_typed())
	var sb := _mk_btn(ir, "Отправить", "ui-check", BTN_GREEN, _invite_typed, "Отправить|Приглашение придёт игроку, если он в сети")
	sb.custom_minimum_size = Vector2(230 * k, 64 * k)
	UIK.label(v, "Игроки рядом", int(24 * k), Color(0.86, 0.66, 0.3))
	var sc := ScrollContainer.new(); sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL; v.add_child(sc)
	inv_list = VBoxContainer.new(); inv_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv_list.add_theme_constant_override("separation", int(8 * k)); sc.add_child(inv_list)
	var back := _mk_btn(v, "Назад к группе", "", BTN_GREY, func(): inv_pan.visible = false; refresh(), "Назад|Вернуться к списку участников")
	back.custom_minimum_size.y = 60 * k

func _open_invite() -> void:
	if _why_off(b_inv): return
	inv_pan.visible = not inv_pan.visible
	if inv_pan.visible: _fill_nearby()

func _fill_nearby() -> void:
	UIK.clear(inv_list)
	var k := win_k
	var in_p := {}
	for m in Net.party.get("members", []): in_p[str(m.name)] = true
	var ids := Net.remotes.keys()
	var mypos: Vector3 = zone.player.global_position if zone and zone.player else Vector3.ZERO
	ids.sort_custom(func(a, b): return (Net.remotes[a].get("pos", Vector3.ZERO) as Vector3).distance_to(mypos) < (Net.remotes[b].get("pos", Vector3.ZERO) as Vector3).distance_to(mypos))
	var any := false
	for id in ids:
		var nm := str(Net.remotes[id].name)
		if in_p.has(nm): continue
		any = true
		var r := HBoxContainer.new(); r.add_theme_constant_override("separation", int(10 * k)); inv_list.add_child(r)
		r.custom_minimum_size.y = 64 * k
		UIK.icon_rect(r, "person", 40 * k, Color(0.86, 0.66, 0.3))
		UIK.expand(UIK.label(r, "%s — ур. %d" % [nm, int(Net.remotes[id].get("level", 1))], int(24 * k)))
		var b := _mk_btn(r, "Пригласить", "ui-plus", BTN_GREEN, func(): Net.party_invite(nm); Game.toast("Приглашение отправлено: " + nm, 1.6), "Пригласить|" + nm)
		b.custom_minimum_size = Vector2(220 * k, 60 * k)
	if not any: UIK.label(inv_list, "Рядом никого нет — введите имя героя выше", int(22 * k), UIK.MUTED)

func _invite_typed() -> void:
	if name_edit == null: return
	var n := name_edit.text.strip_edges()
	if n == "": Game.toast("Введите имя игрока", 1.5); return
	Net.party_invite(n)
	Game.toast("Приглашение отправлено: " + n, 1.6)
	name_edit.text = ""
	name_edit.release_focus()

# ----- всплывающее приглашение: Принять / Отклонить -----
func _build_popup(root: Control) -> void:
	var k := win_k
	ipop = Panel.new(); ipop.name = "InvitePopup"
	ipop.add_theme_stylebox_override("panel", stone_box())
	root.add_child(ipop); ipop.mouse_filter = Control.MOUSE_FILTER_STOP
	_corners(ipop, 30.0, 3.0)
	var t := UIK.label(ipop, "Приглашение в группу", int(26 * k), Color(0.86, 0.66, 0.3), HORIZONTAL_ALIGNMENT_CENTER)
	t.add_theme_font_override("font", UIK.title_font()); t.position = Vector2(20, 18 * k); t.size = Vector2(520 * k, 36 * k)
	ipop_text = UIK.label(ipop, "", int(28 * k), Color(0.97, 0.92, 0.82), HORIZONTAL_ALIGNMENT_CENTER); ipop_text.name = "Text"
	ipop_text.position = Vector2(20, 62 * k); ipop_text.size = Vector2(520 * k, 90 * k)
	var a := _mk_btn(ipop, "Принять", "ui-check", BTN_GREEN, func(): Net.party_accept(ipop_pid); _hide_invite(), "Принять|Вступить в группу")
	a.name = "Accept"; a.position = Vector2(24 * k, 166 * k); a.size = Vector2(246 * k, 76 * k)
	var d := _mk_btn(ipop, "Отклонить", "ui-cross", BTN_RED, func(): Net.party_decline(ipop_pid); _hide_invite(), "Отклонить|Отказаться от приглашения")
	d.name = "Decline"; d.position = Vector2(290 * k, 166 * k); d.size = Vector2(246 * k, 76 * k)
	ipop.visible = false
	if zone and zone.hud: zone.hud.blockers.append(ipop)
	else: _pending_blockers.append(ipop)

func _on_invite(pid: int, from_name: String) -> void:
	ipop_pid = pid
	ipop_text.text = "%s приглашает вас в группу" % from_name
	if not ipop.visible:
		ipop.visible = true; UIK.pop_in(ipop)

func _hide_invite() -> void:
	ipop_pid = 0
	if ipop: ipop.visible = false

func _sync_invite() -> void:
	if ipop == null: return
	if Net.party_invites.is_empty():
		if ipop.visible: _hide_invite()
	elif not Net.party_invites.has(ipop_pid) or not ipop.visible:
		var pid: int = int(Net.party_invites.keys()[0])
		_on_invite(pid, str(Net.party_invites[pid]))

## Проверки для снимков/тестов: [[ok, текст]]
func self_check() -> Array:
	var out := []
	var vs := get_viewport().get_visible_rect().size
	out.append([Rect2(Vector2.ZERO, vs).encloses(win.get_global_rect()), "окно целиком на экране"])
	out.append([title_l.text.begins_with("Группа ("), "заголовок «%s»" % title_l.text])
	var rows := 0
	for r in body.get_children(): if r.has_meta("name"): rows += 1
	out.append([rows == (Net.party.get("members", []) as Array).size(), "строк участников: %d" % rows])
	for b in [b_inv, b_kick, b_prom, b_leave]:
		out.append([b.size.y >= (72.0 * win_k) - 1 and b.get_global_rect().end.x <= win.get_global_rect().end.x + 1, "кнопка «%s» %dx%d" % [b.text, b.size.x, b.size.y]])
	var crowns := 0
	for r in body.get_children(): if r.has_node("Crown"): crowns += 1
	out.append([crowns == (1 if Net.in_party() else 0), "корона лидера: %d" % crowns])
	for r in body.get_children():
		if r.has_node("Hp"):
			var tl := str((r.get_node("Hp/Text") as Label).text)
			out.append([tl != "", "HP «%s»" % tl])
			break
	return out

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
