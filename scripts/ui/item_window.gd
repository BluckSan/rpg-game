extends Control
## Общее окно предметов: «hero» (снаряжение + инвентарь), «shop» (лавка + инвентарь), «stash» (сундук + инвентарь).
## Сетка с рамками редкости, подсказка со сравнением с надетым, сортировка/фильтр, массовый выбор и операции.

var zone
var data: Dictionary
var mode := "hero"
var tab := "buy"                 # лавка: buy | buyback
var inv_grid: ItemGrid
var side_grid: ItemGrid          # лавка: товары/выкуп; сундук: содержимое
var equip_box: GridContainer
var stats_text: RichTextLabel
var gold_label: Label
var dust_label: Label
var inv_title: Label
var side_title: Label
var tip_icon: TextureRect
var tip: RichTextLabel
var tip_price: Label
var act_box: HBoxContainer
var mass_box: HBoxContainer
var side_mass: HBoxContainer
var tab_btns := {}
var tb := {}                     # кнопки панелей инструментов: key -> Button
var focus_item = null
var focus_src := ""              # inv | eq | stock | potion | buyback | stash
var _rarity_step := -1
var _side_rarity_step := -1
var restock_btn: Button

const SORTS := [["rarity", "редк."], ["level", "ур."], ["slot", "слот"], ["type", "тип"]]

func setup(z) -> void:
	zone = z
	data = z.data
	Items.migrate(data)
	if mode == "shop": DB.shop_ensure(data)
	process_mode = Node.PROCESS_MODE_ALWAYS
	UIK.full(UIK.panel(self, Color(0.03, 0.025, 0.02, 0.985), 0))
	_top_bar()
	var lp := UIK.panel(self)
	lp.anchor_left = 0.012; lp.anchor_right = 0.352; lp.anchor_bottom = 1; lp.offset_top = 108; lp.offset_bottom = -16
	var mp := UIK.panel(self)
	mp.anchor_left = 0.358; mp.anchor_right = 0.682; mp.anchor_bottom = 1; mp.offset_top = 108; mp.offset_bottom = -16
	var rp := Panel.new(); rp.add_theme_stylebox_override("panel", UIK.frame("tooltip", Color.WHITE, 20)); add_child(rp)
	rp.anchor_left = 0.688; rp.anchor_right = 0.988; rp.anchor_bottom = 1; rp.offset_top = 108; rp.offset_bottom = -16
	match mode:
		"hero": _build_equipment(lp)
		"shop": _build_shop(lp)
		"stash": _build_stash(lp)
	_build_inventory(mp)
	_build_detail(rp)
	refresh()

# ---------------- построение ----------------
func _top_bar() -> void:
	var titles := {"hero": ["Герой", "person"], "shop": ["Лавка Бориса", "shop"], "stash": ["Сундук", "treasure-map"]}
	var ic := UIK.icon_rect(self, titles[mode][1], 64, UIK.ACCENT); ic.position = Vector2(28, 22)
	var t := UIK.label(self, titles[mode][0], 50, UIK.ACCENT); t.name = "Title"
	t.autowrap_mode = TextServer.AUTOWRAP_OFF
	UIK.rect(t, Vector2(104, 14), Vector2(600, 84))
	var gb := HBoxContainer.new(); gb.add_theme_constant_override("separation", 10); add_child(gb)
	gb.anchor_left = 1; gb.anchor_right = 1; gb.offset_left = -820; gb.offset_right = -250; gb.offset_top = 26; gb.offset_bottom = 86
	gb.alignment = BoxContainer.ALIGNMENT_END
	UIK.icon_rect(gb, "two-coins", 40, Color(1, 0.82, 0.3))
	gold_label = UIK.label(gb, "", 34, Color(1, 0.85, 0.4)); gold_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	UIK.icon_rect(gb, "item:dust", 40)
	dust_label = UIK.label(gb, "", 34, Color(0.75, 0.6, 1.0)); dust_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	dust_label.tooltip_text = "Эфирная пыль — за разборку предметов; тратится на обновление товаров у торговца"
	var close := UIK.button(self, "Закрыть", _close, UIK.RED, 30)
	close.anchor_left = 1; close.anchor_right = 1; close.offset_left = -230; close.offset_right = -24; close.offset_top = 18; close.offset_bottom = 96

func _vbox(parent: Control, sep := 8) -> VBoxContainer:
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", sep)
	parent.add_child(v); UIK.full(v); v.offset_left = 18; v.offset_right = -18; v.offset_top = 16; v.offset_bottom = -16
	return v

func _tool(parent: Node, key: String, text: String, cb: Callable, c := UIK.BUTTON, fs := 19) -> Button:
	var b := UIK.button(parent, text, cb, c, fs)
	b.custom_minimum_size = Vector2(0, 56); b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.autowrap_mode = TextServer.AUTOWRAP_OFF; b.clip_text = true
	tb[key] = b
	return b

func _grid(parent: Node, lst: Array, n: int) -> ItemGrid:
	var g := ItemGrid.new()
	g.size_flags_vertical = Control.SIZE_EXPAND_FILL; g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(g)
	g.setup(data, lst, n)
	return g

func _build_equipment(lp: Control) -> void:
	var v := _vbox(lp, 10)
	var h := UIK.label(v, "Снаряжение", 30, UIK.ACCENT, HORIZONTAL_ALIGNMENT_CENTER); h.autowrap_mode = TextServer.AUTOWRAP_OFF
	equip_box = GridContainer.new(); equip_box.columns = 4
	equip_box.add_theme_constant_override("h_separation", 10); equip_box.add_theme_constant_override("v_separation", 6)
	v.add_child(equip_box)
	stats_text = UIK.rich(v, "", 22)
	stats_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stats_text.scroll_active = true; stats_text.mouse_filter = Control.MOUSE_FILTER_PASS

func _build_shop(lp: Control) -> void:
	var v := _vbox(lp, 8)
	var tabs := HBoxContainer.new(); tabs.add_theme_constant_override("separation", 10); v.add_child(tabs)
	for k in [["buy", "Купить", "swap-bag"], ["buyback", "Выкуп", "backward-time"]]:
		var b := UIK.button(tabs, k[1], select_tab.bind(k[0]), UIK.BUTTON, 28, k[2])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL; b.custom_minimum_size.y = 70
		tab_btns[k[0]] = b
	side_title = UIK.label(v, "", 24, UIK.MUTED); side_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	side_grid = _grid(v, data["shop"]["stock"], 0)
	side_grid.price_fn = func(it): return DB.buy_price(it) if tab == "buy" else DB.sell_price(it)
	side_grid.focused.connect(_on_side_focus)
	side_grid.hovered.connect(_on_hover)
	side_grid.activated.connect(func(_it): _primary())
	var rb := HBoxContainer.new(); rb.add_theme_constant_override("separation", 8); v.add_child(rb)
	restock_btn = _tool(rb, "restock", "", restock, UIK.BUTTON, 20)
	_tool(rb, "restock_dust", "", restock_dust, UIK.PURPLE, 20)

func _build_stash(lp: Control) -> void:
	var v := _vbox(lp, 8)
	side_title = UIK.label(v, "", 28, UIK.ACCENT); side_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	var r := HBoxContainer.new(); r.add_theme_constant_override("separation", 6); v.add_child(r)
	_tool(r, "s_sort", "", func(): _cycle_sort(side_grid))
	_tool(r, "s_mode", "Выбор", func(): side_grid.select_mode = not side_grid.select_mode; _side_toolbar())
	_tool(r, "s_rar", "Редк. ▾", func(): _side_rarity_step = _rarity_pick(side_grid, _side_rarity_step))
	_tool(r, "s_all", "Все", func(): side_grid.select_all())
	_tool(r, "s_none", "✕", func(): side_grid.clear_selection())
	side_grid = _grid(v, data["stash"], Items.STASH_SIZE)
	side_grid.focused.connect(_on_side_focus)
	side_grid.hovered.connect(_on_hover)
	side_grid.selection_changed.connect(_update_mass)
	side_grid.activated.connect(func(it): take_from_stash([str(it.uid)]))
	side_mass = HBoxContainer.new(); side_mass.add_theme_constant_override("separation", 8); v.add_child(side_mass)
	_tool(side_mass, "take", "", func(): take_from_stash(side_grid.uids()), UIK.GREEN, 22)

func _build_inventory(mp: Control) -> void:
	var v := _vbox(mp, 8)
	inv_title = UIK.label(v, "", 28, UIK.ACCENT); inv_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	var r1 := HBoxContainer.new(); r1.add_theme_constant_override("separation", 6); v.add_child(r1)
	_tool(r1, "sort", "", func(): _cycle_sort(inv_grid))
	_tool(r1, "filter", "", _cycle_filter)
	var r2 := HBoxContainer.new(); r2.add_theme_constant_override("separation", 6); v.add_child(r2)
	_tool(r2, "mode", "Выбор", func(): inv_grid.select_mode = not inv_grid.select_mode; _toolbar())
	_tool(r2, "rar", "Редк. ▾", func(): _rarity_step = _rarity_pick(inv_grid, _rarity_step))
	_tool(r2, "junk", "Хлам", func(): inv_grid.set_selection(Items.select_junk(data, inv_grid.view)))
	_tool(r2, "all", "Все", func(): inv_grid.select_all())
	_tool(r2, "none", "✕", func(): inv_grid.clear_selection())
	inv_grid = _grid(v, data["inventory"], Items.INVENTORY_SIZE)
	inv_grid.focused.connect(func(it): _set_focus(it, "inv"))
	inv_grid.hovered.connect(_on_hover)
	inv_grid.selection_changed.connect(_update_mass)
	inv_grid.activated.connect(func(it): _set_focus(it, "inv"); _primary())
	mass_box = HBoxContainer.new(); mass_box.add_theme_constant_override("separation", 8); v.add_child(mass_box)
	match mode:
		"shop": _tool(mass_box, "m_sell", "", func(): sell_selected(), UIK.GOLD, 22)
		"stash": _tool(mass_box, "m_stash", "", func(): stash_selected(), UIK.BLUE, 22)
	_tool(mass_box, "m_dis", "", func(): dismantle_selected(), UIK.PURPLE, 22)

func _build_detail(rp: Control) -> void:
	var v := _vbox(rp, 10)
	v.offset_left = 26; v.offset_right = -26; v.offset_top = 26; v.offset_bottom = -24
	tip_icon = TextureRect.new(); tip_icon.custom_minimum_size = Vector2(0, 150)
	tip_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; tip_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	v.add_child(tip_icon)
	tip = UIK.rich(v, "", 23); tip.name = "Tooltip"
	tip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tip.scroll_active = true; tip.mouse_filter = Control.MOUSE_FILTER_PASS
	tip_price = UIK.label(v, "", 28, Color(1, 0.85, 0.4)); tip_price.autowrap_mode = TextServer.AUTOWRAP_OFF
	act_box = HBoxContainer.new(); act_box.add_theme_constant_override("separation", 8); v.add_child(act_box)
	act_box.custom_minimum_size.y = 76

# ---------------- обновление ----------------
func refresh() -> void:
	gold_label.text = str(data["gold"])
	dust_label.text = str(int(data.get("dust", 0)))
	inv_title.text = "Инвентарь  %d/%d" % [data["inventory"].size(), Items.INVENTORY_SIZE]
	inv_grid.refresh()
	match mode:
		"hero": _refresh_equipment()
		"shop": _refresh_shop()
		"stash":
			side_title.text = "Сундук  %d/%d" % [data["stash"].size(), Items.STASH_SIZE]
			side_grid.refresh()
	_toolbar(); _side_toolbar(); _update_mass(); _update_detail()

func _toolbar() -> void:
	for s in SORTS: if s[0] == inv_grid.sort_by: tb.sort.text = "Сорт: " + s[1]
	for f in Items.FILTERS: if f[0] == inv_grid.filter: tb.filter.text = "Фильтр: " + f[1]
	UIK.set_button_color(tb.mode, UIK.SELECT if inv_grid.select_mode else UIK.BUTTON)
	tb.mode.text = "Выбор ✔" if inv_grid.select_mode else "Выбор"
	tb.rar.text = ["Редк. ▾", "≤ Обычн", "≤ Магич", "≤ Редк"][_rarity_step + 1]

func _side_toolbar() -> void:
	if mode != "stash": return
	for s in SORTS: if s[0] == side_grid.sort_by: tb.s_sort.text = "Сорт: " + s[1]
	UIK.set_button_color(tb.s_mode, UIK.SELECT if side_grid.select_mode else UIK.BUTTON)
	tb.s_mode.text = "Выбор ✔" if side_grid.select_mode else "Выбор"
	tb.s_rar.text = ["Редк. ▾", "≤ Обычн", "≤ Магич", "≤ Редк"][_side_rarity_step + 1]

func _update_mass() -> void:
	var u := inv_grid.uids()
	var n := u.size()
	var gold := 0; var dust := 0
	for id in u:
		var it = Items.find_uid(data["inventory"], id)
		if it: gold += DB.sell_price(it); dust += Items.dust_value(it)
	if tb.has("m_sell"): tb.m_sell.text = "Продать %d  (+%d зол.)" % [n, gold]; _enable(tb.m_sell, n > 0, UIK.GOLD)
	if tb.has("m_stash"):
		tb.m_stash.text = "В сундук %d" % n
		_enable(tb.m_stash, n > 0 and data["stash"].size() < Items.STASH_SIZE, UIK.BLUE)
	tb.m_dis.text = "Разобрать %d  (+%d пыли)" % [n, dust]; _enable(tb.m_dis, n > 0, UIK.PURPLE)
	if mode == "stash":
		var k := side_grid.count()
		tb.take.text = "Забрать %d в инвентарь" % k
		_enable(tb.take, k > 0 and data["inventory"].size() < Items.INVENTORY_SIZE, UIK.GREEN)

func _enable(b: Button, on: bool, c: Color) -> void:
	b.disabled = not on
	UIK.set_button_color(b, c if on else Color(0.3, 0.3, 0.3))

func _refresh_equipment() -> void:
	UIK.clear(equip_box)
	for s in Items.SLOT_COUNT:
		var it = Items.get_equipped(data, s)
		var cell := VBoxContainer.new(); cell.add_theme_constant_override("separation", 2)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		equip_box.add_child(cell)
		var b := Button.new(); b.name = "Equip_%d" % s
		b.custom_minimum_size = Vector2(112, 112); b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var col: Color = Items.rarity_color(it) if it != null else Color(0.35, 0.3, 0.25)
		var st := StyleBoxFlat.new(); st.bg_color = Color(col.r * 0.22, col.g * 0.22, col.b * 0.22, 0.95)
		st.border_color = col.lightened(0.4) if (it != null and it == focus_item) else col
		var w := 5 if (it != null and it == focus_item) else 3
		st.border_width_left = w; st.border_width_right = w; st.border_width_top = w; st.border_width_bottom = w
		st.corner_radius_top_left = 12; st.corner_radius_top_right = 12; st.corner_radius_bottom_left = 12; st.corner_radius_bottom_right = 12
		for k in ["normal", "hover", "pressed", "disabled"]: b.add_theme_stylebox_override(k, st)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		cell.add_child(b)
		var ir := TextureRect.new(); ir.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ir.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ir.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		b.add_child(ir); UIK.full(ir); ir.offset_left = 10; ir.offset_top = 10; ir.offset_right = -10; ir.offset_bottom = -10
		if it != null:
			ir.texture = UIK.icon(UIK.item_icon(it, data["class"]))
			b.pressed.connect(func(): if not DragScroll.dragging: _set_focus(it, "eq"))
			b.mouse_entered.connect(func(): _on_hover(it)); b.mouse_exited.connect(func(): _on_hover(null))
		else:
			ir.texture = UIK.icon(UIK.SLOT_ITEM_ICONS[s]); ir.modulate = Color(1, 1, 1, 0.18)
			b.disabled = true
		var l := UIK.label(cell, Items.SLOT_NAMES[s], 18, UIK.MUTED, HORIZONTAL_ALIGNMENT_CENTER); l.autowrap_mode = TextServer.AUTOWRAP_OFF
	stats_text.text = _stats_bb()

func _stats_bb() -> String:
	var st: Dictionary = zone.player.stats if zone and zone.player else DB.compute_stats(data)
	var cls: Dictionary = DB.CLASSES[data["class"]]
	var asc := DB.get_asc(data["ascendancy"])
	var dmg: float = st.damage * st.dmg_mult * (st.spell_mult if cls.spell else 1.0)
	var I := func(n: String) -> String: return "[img=26x26]res://assets/icons/%s.svg[/img] " % n
	var s := "[font_size=28][b]%s[/b][/font_size]  [color=#e6c27a]%s%s · ур. %d[/color]\n" % [data["name"], cls.name, (" → " + asc["name"]) if not asc.is_empty() else "", data["level"]]
	s += I.call("heart-bottle") + "Здоровье %d   " % roundi(st.max_hp) + I.call("drop") + "Мана %d\n" % roundi(st.max_mp)
	s += I.call("sword-wound") + "Урон %d   " % roundi(dmg) + I.call("lightning-frequency") + "Скорость %d%%\n" % roundi(st.attack_speed * 100)
	s += I.call("crossed-swords") + "Крит %.1f%% (x%.2f)   " % [st.crit * 100, st.crit_mult] + I.call("checked-shield") + "Броня %d (−%d%%)\n" % [roundi(st.armor), roundi(st.dr * 100)]
	var at: Dictionary = st.get("attrs", {})
	s += "Сила %d · Ловкость %d · Интеллект %d · Выносливость %d · Пробивание %d\n" % [roundi(at.get("str", 0)), roundi(at.get("dex", 0)), roundi(at.get("int", 0)), roundi(at.get("vit", 0)), roundi(st.get("pen_flat", 0.0))]
	s += I.call("heart-beats") + "Реген %.1f/с   " % st.regen + I.call("skull-mask") + "Вампиризм %.1f%%   " % (st.leech * 100) + I.call("hourglass") + "Перезарядка −%d%%\n" % roundi(st.cdr * 100)
	var seen := {}
	for it in data["equipped"]:
		var sid: String = it.get("set", "")
		if sid == "" or seen.has(sid) or not Items.SETS.has(sid): continue
		seen[sid] = true
		var n := Items.set_count(data, sid)
		s += "\n[color=#%s][b]◆ %s[/b] %d/6[/color]  " % [DB.RARITY_COLORS[Items.SET_RARITY].to_html(false), Items.SETS[sid].name, n]
		for t in [2, 4, 6]: s += "[color=#%s](%d)[/color] " % ["66ff88" if n >= t else "666666", t]
	return s

func _refresh_shop() -> void:
	for k in tab_btns: UIK.set_button_color(tab_btns[k], UIK.SELECT if k == tab else UIK.BUTTON)
	if tab == "buy":
		side_grid.source = data["shop"]["stock"]; side_grid.cap = 0
		side_grid.extra_cells = [{"id": "potion", "icon": "item:potion", "color": Color(1, 0.45, 0.45), "label": str(DB.potion_price(data["level"]))}]
		side_title.text = "Товары под ваш уровень · зелий: %d" % data["potions"]
	else:
		side_grid.source = data["buyback"]; side_grid.cap = DB.BUYBACK_SIZE; side_grid.extra_cells = []
		side_title.text = "Проданные вещи — по цене продажи"
	side_grid.refresh()
	var dp := restock_dust_price()
	restock_btn.text = "Обновить: %d зол." % DB.shop_restock_price(data["level"])
	tb.restock_dust.text = "Обновить: %d пыли" % dp
	_enable(tb.restock_dust, int(data.get("dust", 0)) >= dp, UIK.PURPLE)

# ---------------- подсказка и действия ----------------
func _on_side_focus(it) -> void:
	if it is Dictionary and it.has("id") and it.id == "potion": _set_focus(it, "potion")
	else: _set_focus(it, {"shop": "stock" if tab == "buy" else "buyback", "stash": "stash"}.get(mode, "inv"))

func _set_focus(it, src: String) -> void:
	focus_item = it; focus_src = src
	if src != "inv": inv_grid.focus_uid = ""
	if side_grid and src in ["inv", "eq"]: side_grid.focus_uid = ""
	if mode == "hero": _refresh_equipment()
	if src in ["inv", "eq"] or not side_grid: inv_grid.refresh()
	if side_grid and src not in ["inv", "eq"]: side_grid.refresh()
	_update_detail()

func _on_hover(it) -> void:
	if not Game.desktop: return
	if it == null: _update_detail()
	elif it is Dictionary and it.has("uid"): _show_tip(it, focus_src if it == focus_item else "")

func _show_tip(it: Dictionary, src: String) -> void:
	tip_icon.texture = UIK.icon(UIK.item_icon(it, data["class"]))
	tip.text = Items.tooltip(data, it, src != "eq")

func _update_detail() -> void:
	UIK.clear(act_box)
	tip_price.text = ""
	if focus_item != null and focus_src == "potion":
		tip_icon.texture = UIK.icon("item:potion")
		tip.text = "[color=#ff8080][b]Зелье лечения[/b][/color]\nМгновенно восстанавливает 45%% здоровья.\nКнопка «Зелье» в бою.\n\nУ вас: %d" % data["potions"]
		tip_price.text = "Цена: %d" % DB.potion_price(data["level"])
		_act("Купить", buy_potion, int(data["gold"]) >= DB.potion_price(data["level"]))
		return
	if focus_item == null or not _still_there():
		focus_item = null; focus_src = ""
		tip_icon.texture = UIK.icon({"hero": "item:sword", "shop": "item:potion", "stash": "item:belt"}[mode])
		tip.text = {"hero": "[b]Выберите предмет[/b]\n\nКлик — подсказка и сравнение с надетым, двойной клик — надеть.\n[color=#aaaaaa]ПК: Shift — выбрать диапазон, Ctrl — добавить к выбору.\nТелефон: включите «Выбор» и касайтесь предметов.[/color]\n\n[color=#ff6666]Красный уровень[/color] — предмет пока нельзя надеть.\n[color=#4df273]◆[/color] — часть комплекта.",
			"shop": "[b]Борис[/b]\n\nСвежие товары под ваш уровень. Выберите несколько вещей в инвентаре и продайте разом. Ошиблись — верните во вкладке «Выкуп».\n\nРазобранные вещи дают эфирную пыль — ей можно оплатить обновление товаров.",
			"stash": "[b]Сундук лагеря[/b]\n\nДо %d предметов, общий для всех лагерей. Выберите вещи и перенесите разом; двойной клик — перенести одну." % Items.STASH_SIZE}[mode]
		return
	var it: Dictionary = focus_item
	_show_tip(it, focus_src)
	var why := Items.equip_block(data, it)
	match focus_src:
		"inv":
			_act(why if why != "" else "Надеть", _primary, why == "", UIK.GREEN)
			match mode:
				"shop":
					tip_price.text = "Продажа: +%d" % DB.sell_price(it)
					_act("Продать", func(): sell_selected([str(it.uid)]), true, UIK.GOLD)
				"stash": _act("В сундук", func(): stash_selected([str(it.uid)]), data["stash"].size() < Items.STASH_SIZE, UIK.BLUE)
				_:
					_act("Разобрать +%d" % Items.dust_value(it), func(): dismantle_selected([str(it.uid)]), true, UIK.PURPLE)
					_upgrade_btn(it)
		"eq":
			_act("Снять", _primary, int(it.slot) != 0, UIK.BUTTON)
			_upgrade_btn(it)
		"stock":
			tip_price.text = "Цена: %d" % DB.buy_price(it)
			_act("Купить", _primary, int(data["gold"]) >= DB.buy_price(it))
		"buyback":
			tip_price.text = "Выкуп: %d" % DB.sell_price(it)
			_act("Выкупить", _primary, int(data["gold"]) >= DB.sell_price(it))
		"stash":
			_act("Забрать", func(): take_from_stash([str(it.uid)]), data["inventory"].size() < Items.INVENTORY_SIZE, UIK.GREEN)
			_act(why if why != "" else "Надеть", func(): _equip(it), why == "", UIK.BUTTON)

## v0.9.2: улучшение +1…+10 (онлайн бросок и списание — на сервере)
func _upgrade_btn(it: Dictionary) -> void:
	if Items.up_level(it) >= Items.UP_MAX: return
	var cost := Items.upgrade_cost(it)
	var why := Items.upgrade_block(data, it)
	var txt := "+%d: %d зол." % [int(cost.to), int(cost.gold)]
	if int(cost.n) > 0: txt += " · %s ×%d" % [Items.MATS[cost.mat].name, int(cost.n)]
	if int(cost.fail) > 0: txt += " · риск %d%%" % int(cost.fail)
	var b := _act(txt, func(): upgrade_item(str(it.uid)), why == "", UIK.GOLD)
	b.name = "UpgradeBtn"; b.tooltip_text = why if why != "" else "Улучшить: характеристики +%d%%" % int(round(Items.UP_STEP * 100))

var _up_wait := false
func upgrade_item(uid: String) -> void:
	if _up_wait: return
	if Net.in_game:
		_up_wait = true
		Net.inv("upgrade", [uid], false)
		var res: Array = ["", {}]
		for i in 20:
			res = await Net.inv_result
			if res[0] == "upgrade": break
		_up_wait = false
		_up_result(res[1] if res.size() > 1 else {})
	else:
		_up_result(Net.inv("upgrade", [uid]))

func _up_result(r: Dictionary) -> void:
	if str(r.get("err", "")) != "": Game.toast(str(r.err), 1.6)
	elif r.get("failed", false): Game.toast("Улучшение не удалось — предмет цел, цена списана", 2.0)
	else: Game.toast("Улучшено до +%d!" % int(r.get("up", 0)), 1.6); _coin_fx(); _changed()
	if is_inside_tree(): refresh()

func _still_there() -> bool:
	match focus_src:
		"inv": return data["inventory"].has(focus_item)
		"eq": return data["equipped"].has(focus_item)
		"stock": return data["shop"]["stock"].has(focus_item)
		"buyback": return data["buyback"].has(focus_item)
		"stash": return data["stash"].has(focus_item)
	return false

func _act(text: String, cb: Callable, on := true, c := UIK.GREEN) -> Button:
	var b := UIK.button(act_box, text, cb, c, 26)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL; b.custom_minimum_size.y = 76
	b.autowrap_mode = TextServer.AUTOWRAP_OFF; b.clip_text = true
	if not on:
		b.disabled = true
		if text.begins_with("Нужен") or text.begins_with("Только"):
			b.add_theme_color_override("font_disabled_color", Color(1, 0.4, 0.4))
	return b

## Главное действие для выбранного предмета
func _primary() -> void:
	if focus_item == null: return
	var err := ""
	match focus_src:
		"inv": err = _equip(focus_item, false)
		"eq":
			if int(focus_item.slot) == 0: err = "Без оружия никак!"
			else:
				err = str(Net.inv("unequip", [str(focus_item.uid)]).err)
				if err == "": _changed(); focus_item = null
		"stock":
			err = str(Net.inv("buy", [str(focus_item.uid)]).err)
			if err == "": focus_item = null; _coin_fx()
		"buyback":
			err = str(Net.inv("buyback", [str(focus_item.uid)]).err)
			if err == "": focus_item = null; _coin_fx()
	if err != "": Game.toast(err, 1.6)
	refresh()

func _equip(it: Dictionary, do_refresh := true) -> String:
	var err := str(Net.inv("equip", [str(it.uid)]).err)
	if err == "":
		focus_item = null
		_changed()
	elif do_refresh: Game.toast(err, 1.6)
	if do_refresh: refresh()
	return err

func _changed() -> void:
	if zone and zone.has_method("apply_character_changes"): zone.apply_character_changes(false)

# ---------------- массовые операции ----------------
func _uids_or_sel(uids) -> Array:
	return uids if uids is Array else inv_grid.uids()

func sell_selected(uids = null) -> int:
	var g := int(Net.inv("sell", _uids_or_sel(uids)).get("n", 0))
	if g > 0: _coin_fx()
	inv_grid.selected.clear(); refresh()
	return g

func dismantle_selected(uids = null) -> int:
	var d := int(Net.inv("dismantle", _uids_or_sel(uids)).get("n", 0))
	if d > 0: Game.toast("Разобрано: +%d эфирной пыли" % d, 1.4)
	inv_grid.selected.clear(); refresh()
	return d

func stash_selected(uids = null) -> int:
	var lst := _uids_or_sel(uids)
	var n := int(Net.inv("to_stash", lst).get("n", 0))
	if n < lst.size(): Game.toast("Сундук полон (%d/%d)" % [data["stash"].size(), Items.STASH_SIZE], 1.6)
	inv_grid.selected.clear(); refresh()
	return n

func take_from_stash(uids: Array) -> int:
	var n := int(Net.inv("from_stash", uids).get("n", 0))
	if n < uids.size(): Game.toast("Инвентарь полон", 1.6)
	if side_grid: side_grid.selected.clear()
	refresh()
	return n

func _rarity_pick(g: ItemGrid, step: int) -> int:
	step += 1
	if step > 2:
		g.clear_selection(); return -1
	g.set_selection(Items.select_by_rarity(g.view, step))
	return step

func _cycle_sort(g: ItemGrid) -> void:
	var i := 0
	for k in SORTS.size(): if SORTS[k][0] == g.sort_by: i = k
	g.sort_by = SORTS[(i + 1) % SORTS.size()][0]
	refresh()

func _cycle_filter() -> void:
	var i := 0
	for k in Items.FILTERS.size(): if Items.FILTERS[k][0] == inv_grid.filter: i = k
	inv_grid.filter = Items.FILTERS[(i + 1) % Items.FILTERS.size()][0]
	refresh()

# ---------------- лавка ----------------
func select_tab(t: String) -> void:
	tab = t
	focus_item = null; focus_src = ""
	if side_grid: side_grid.focus_uid = ""; side_grid.selected.clear()
	refresh()

func restock_dust_price() -> int: return 10 + int(data["level"]) * 2

func restock() -> void:
	var price := DB.shop_restock_price(data["level"])
	if int(data["gold"]) < price:
		Game.toast("Не хватает золота", 1.5); return
	Net.inv("restock")
	focus_item = null
	refresh()

func restock_dust() -> void:
	var p := restock_dust_price()
	if int(data.get("dust", 0)) < p:
		Game.toast("Не хватает эфирной пыли", 1.5); return
	Net.inv("restock_dust")
	focus_item = null
	refresh()

func _coin_fx() -> void:
	gold_label.pivot_offset = gold_label.size / 2
	var tw := gold_label.create_tween()
	tw.tween_property(gold_label, "scale", Vector2.ONE * 1.25, 0.08)
	tw.tween_property(gold_label, "scale", Vector2.ONE, 0.15)

func _close() -> void:
	zone.save()
	zone.hud.close_window()

# ---------------- для автотестов (совместимо со старыми окнами) ----------------
func _select(it, equipped: bool) -> void:
	_set_focus(it, "eq" if equipped else "inv")

func _on_action() -> void:
	_primary()

func buy_potion() -> bool:
	var g: int = data["gold"]
	var err := str(Net.inv("potion_buy", [1]).err)
	if err != "": Game.toast(err, 1.5)
	else: _coin_fx()
	refresh()
	return int(data["gold"]) < g

func buy(i: int) -> bool:
	if tab != "buy": select_tab("buy")
	if i >= data["shop"]["stock"].size(): return false
	_set_focus(data["shop"]["stock"][i], "stock")
	var n: int = data["inventory"].size()
	_primary()
	return data["inventory"].size() > n

func sell(i: int) -> bool:
	if i >= data["inventory"].size(): return false
	return sell_selected([str(data["inventory"][i].uid)]) > 0

func buyback(i: int) -> bool:
	if tab != "buyback": select_tab("buyback")
	if i >= data["buyback"].size(): return false
	_set_focus(data["buyback"][i], "buyback")
	var n: int = data["inventory"].size()
	_primary()
	return data["inventory"].size() > n
