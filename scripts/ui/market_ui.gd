extends Control
## v0.9.2: Рынок игроков (аукцион). Только онлайн: все сделки — на сервере, в БД одной транзакцией с героем.
## Вкладки: «Купить» (поиск, фильтры: слот, класс, уровень, редкость, комплект; сортировка), «Продать»
## (вещь из инвентаря и цена; плата за выставление 2%, налог с продажи 7%), «Мои лоты» (снять),
## «Почта» (выручка, снятые и истёкшие через 48 ч вещи — забрать).

var zone
var data: Dictionary
var tab := "buy"
var body: Control
var list_box: VBoxContainer
var status: Label
var gold_lbl: Label
var filters := {"slot": -1, "cls": "", "rarity": -1, "set_only": false, "text": "", "lvl_min": 0, "lvl_max": 0, "sort": "new"}
var results: Array = []
var mine: Array = []
var mail: Array = []
var sell_uid := ""
var price_edit: LineEdit
var waiting := false
var tab_btns := {}

func setup(z) -> void:
	zone = z
	data = z.data
	process_mode = Node.PROCESS_MODE_ALWAYS
	UIK.full(UIK.panel(self, Color(0.03, 0.03, 0.05, 0.97), 0))
	UIK.place(UIK.label(self, "Рынок", 48, UIK.ACCENT), 0.03, 0.9, 0.3, 0.98)
	gold_lbl = UIK.label(self, "", 28, Color(0.95, 0.77, 0.43)); gold_lbl.name = "Gold"
	UIK.place(gold_lbl, 0.62, 0.91, 0.86, 0.975)
	var close := UIK.button(self, "Закрыть", func(): zone.hud.close_window(), UIK.RED, 30)
	UIK.place(close, 0.87, 0.905, 0.98, 0.975)
	var x := 0.2
	for t in [["buy", "Купить"], ["sell", "Продать"], ["mine", "Мои лоты"], ["mail", "Почта"]]:
		var b := UIK.button(self, t[1], func(): select_tab(t[0]), UIK.BUTTON, 28)
		b.name = "Tab_" + t[0]; tab_btns[t[0]] = b
		UIK.place(b, x, 0.905, x + 0.1, 0.975); x += 0.105
	status = UIK.label(self, "", 24, Color(0.8, 0.8, 0.8)); status.name = "Status"
	UIK.place(status, 0.03, 0.005, 0.98, 0.045)
	body = Control.new(); add_child(body); UIK.place(body, 0.02, 0.05, 0.98, 0.89)
	if not Net.market_result.is_connected(_on_result): Net.market_result.connect(_on_result)
	if not Net.in_game:
		var l := UIK.label(body, "Рынок доступен только в сетевой игре.\nОфлайн вещи можно купить и продать у торговца.", 34, UIK.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
		UIK.place(l, 0.1, 0.4, 0.9, 0.6)
		for b in tab_btns.values(): b.disabled = true
		return
	select_tab("buy")

func _exit_tree() -> void:
	if Net.market_result.is_connected(_on_result): Net.market_result.disconnect(_on_result)

func select_tab(t: String) -> void:
	tab = t
	for k in tab_btns: tab_btns[k].modulate = Color(1.3, 1.2, 0.8) if k == t else Color.WHITE
	match t:
		"buy": search()
		"sell": _build()
		_: _ask("mine")
	_build()

func search() -> void: _ask("search", {"filters": filters.duplicate()})

func _ask(op: String, args := {}) -> void:
	waiting = true
	status.text = "Связь с рынком…"
	Net.market(op, args)

func _on_result(op: String, r: Dictionary) -> void:
	waiting = false
	status.text = "" if r.get("ok", false) else "Отказ: %s" % str(r.get("error", "?"))
	match op:
		"search": results = r.get("list", [])
		"mine":
			mine = r.get("list", []); mail = r.get("mail", [])
		"list":
			if r.get("ok", false): status.text = "Выставлено (плата %d)" % int(r.get("fee", 0)); sell_uid = ""
		"buy":
			if r.get("ok", false): status.text = "Куплено за %d" % int(r.get("price", 0)); search()
		"cancel":
			if r.get("ok", false): status.text = "Лот снят — вещь в «Почте»"; _ask("mine")
		"claim":
			if r.get("ok", false): status.text = "Получено: %d золота, вещей: %d" % [int(r.get("gold", 0)), int(r.get("items", 0))]; _ask("mine")
	if is_inside_tree(): _build()

func refresh() -> void:
	if is_inside_tree(): _build()

func _item_text(it: Dictionary) -> String:
	var col := Items.rarity_color(it)
	var cls := str(it.get("cls", ""))
	return "[color=#%s][b]%s[/b][/color]  [color=#aaaaaa]%s · ур. %d%s%s[/color]" % [col.to_html(false), str(it.get("name", "?")),
		Items.SLOT_NAMES[clampi(int(it.get("slot", 0)), 0, 7)], int(it.get("ilvl", 1)),
		(" · " + Items.CLASS_NAMES.get(cls, cls)) if cls != "" else "", " · комплект" if str(it.get("set", "")) != "" else ""]

func _row(parent: Node, text: String, btn: String, cb: Callable, on := true, tip := "") -> HBoxContainer:
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 10); parent.add_child(h)
	var r := UIK.rich(h, text, 24); r.size_flags_horizontal = Control.SIZE_EXPAND_FILL; r.custom_minimum_size.y = 64
	r.fit_content = true
	if tip != "": r.tooltip_text = tip
	if btn != "":
		var b := UIK.button(h, btn, cb, UIK.GREEN, 24); b.custom_minimum_size = Vector2(240, 60); b.disabled = not on
		b.name = "RowBtn"
	return h

func _build() -> void:
	gold_lbl.text = "Золото: %d" % int(data.get("gold", 0))
	UIK.clear(body)
	match tab:
		"buy": _build_buy()
		"sell": _build_sell()
		"mine": _build_mine()
		"mail": _build_mail()

func _opt(parent: Node, items: Array, cur, cb: Callable) -> OptionButton:
	var o := OptionButton.new(); parent.add_child(o)
	o.add_theme_font_size_override("font_size", 22); o.custom_minimum_size = Vector2(170, 56)
	var sel := 0
	for i in items.size():
		o.add_item(str(items[i][1])); if items[i][0] == cur: sel = i
	o.select(sel)
	o.item_selected.connect(func(i): cb.call(items[i][0]))
	return o

func _build_buy() -> void:
	var top := HBoxContainer.new(); top.add_theme_constant_override("separation", 8); body.add_child(top)
	UIK.place(top, 0, 0.9, 1, 1)
	var slots := [[-1, "Любой слот"]]
	for i in Items.SLOT_NAMES.size(): slots.append([i, Items.SLOT_NAMES[i]])
	_opt(top, slots, filters.slot, func(v): filters.slot = v; search())
	_opt(top, [["", "Любой класс"], ["warrior", "Воин"], ["archer", "Лучник"], ["mage", "Маг"]], filters.cls, func(v): filters.cls = v; search())
	var rar := [[-1, "Любая редкость"]]
	for i in DB.RARITY_NAMES.size(): rar.append([i, DB.RARITY_NAMES[i]])
	_opt(top, rar, filters.rarity, func(v): filters.rarity = v; search())
	_opt(top, [[0, "Ур. от —"], [10, "от 10"], [20, "от 20"], [30, "от 30"], [40, "от 40"]], filters.lvl_min, func(v): filters.lvl_min = v; search())
	_opt(top, [[0, "до —"], [10, "до 10"], [20, "до 20"], [30, "до 30"], [45, "до 45"]], filters.lvl_max, func(v): filters.lvl_max = v; search())
	_opt(top, [["new", "Новые"], ["price", "Дешевле"], ["price_desc", "Дороже"], ["level", "Уровень"]], filters.sort, func(v): filters.sort = v; search())
	var cb := CheckBox.new(); cb.text = "Комплекты"; cb.button_pressed = filters.set_only; top.add_child(cb)
	cb.add_theme_font_size_override("font_size", 22)
	cb.toggled.connect(func(on): filters.set_only = on; search())
	var te := LineEdit.new(); te.placeholder_text = "Название…"; te.text = filters.text; top.add_child(te)
	te.size_flags_horizontal = Control.SIZE_EXPAND_FILL; te.add_theme_font_size_override("font_size", 22); te.name = "Search"
	te.text_submitted.connect(func(t): filters.text = t; search())
	var pnl := UIK.panel(body); UIK.place(pnl, 0, 0, 1, 0.88)
	list_box = UIK.scroll_list(pnl, 6)
	if results.is_empty():
		UIK.label(list_box, "Ничего не найдено" if not waiting else "Поиск…", 26, Color(0.7, 0.7, 0.7))
	for L in results:
		var it: Dictionary = L.item
		var price := int(L.price)
		var can := int(data.get("gold", 0)) >= price and str(L.get("seller", "")) != str(data.get("name", ""))
		_row(list_box, _item_text(it) + "\n[color=#f2c46d]%d золота[/color]  [color=#888888]продавец %s · до %s[/color]" % [price, str(L.get("seller", "?")), str(L.get("expires", "")).left(16).replace("T", " ")],
			"Купить", func(): buy(int(L.id)), can, Items.tooltip(data, it).replace("[b]", "").replace("[/b]", ""))

func buy(lid: int) -> void:
	if waiting: return
	_ask("buy", {"id": lid})

func _build_sell() -> void:
	var lp := UIK.panel(body); UIK.place(lp, 0, 0, 0.6, 1)
	var v := UIK.scroll_list(lp, 6)
	var inv: Array = data.get("inventory", [])
	if inv.is_empty(): UIK.label(v, "Инвентарь пуст", 26, Color(0.7, 0.7, 0.7))
	for it in inv:
		var u := str(it.uid)
		_row(v, ("▶ " if u == sell_uid else "") + _item_text(it), "Выбрать", func(): sell_uid = u; _build(), true)
	var rp := UIK.panel(body, Color(0.07, 0.06, 0.09, 0.9)); UIK.place(rp, 0.62, 0, 1, 1)
	var it = Items.find_uid(inv, sell_uid)
	var info := UIK.rich(rp, "", 24); UIK.place(info, 0.05, 0.42, 0.95, 0.97)
	if it == null:
		info.text = "[b]Выберите вещь слева[/b]\n\nПлата за выставление — 2% цены (от 5 до 5000), не возвращается.\nНалог с продажи — 7%.\nЛот висит 48 часов; не продан — вещь вернётся в «Почту»."
		return
	info.text = Items.tooltip(data, it, false) + "\n\n[color=#aaaaaa]Торговец дал бы: %d[/color]" % DB.sell_price(it)
	price_edit = LineEdit.new(); rp.add_child(price_edit); price_edit.name = "Price"
	price_edit.placeholder_text = "Цена, золото"; price_edit.add_theme_font_size_override("font_size", 28)
	price_edit.text = str(DB.buy_price(it))
	UIK.place(price_edit, 0.05, 0.28, 0.95, 0.38)
	var fee_l := UIK.label(rp, "", 22, Color(0.9, 0.8, 0.6)); UIK.place(fee_l, 0.05, 0.2, 0.95, 0.27)
	var upd := func(_t = ""):
		var pr := int(price_edit.text)
		fee_l.text = "Плата: %d · вы получите: %d" % [Net.market_fee(maxi(1, pr)), pr - int(round(pr * Net.MARKET_TAX))]
	price_edit.text_changed.connect(upd); upd.call()
	var b := UIK.button(rp, "Выставить", func(): list_item(sell_uid, int(price_edit.text)), UIK.GREEN, 30)
	b.name = "ListBtn"; UIK.place(b, 0.15, 0.04, 0.85, 0.17)

func list_item(uid: String, price: int) -> void:
	if waiting: return
	if price < 1: status.text = "Укажите цену"; return
	_ask("list", {"uid": uid, "price": price})

func _build_mine() -> void:
	var pnl := UIK.panel(body); UIK.place(pnl, 0, 0, 1, 1)
	var v := UIK.scroll_list(pnl, 6)
	if mine.is_empty(): UIK.label(v, "Нет выставленных лотов" if not waiting else "Загрузка…", 26, Color(0.7, 0.7, 0.7))
	for L in mine:
		_row(v, _item_text(L.item) + "\n[color=#f2c46d]%d золота[/color]  [color=#888888]до %s[/color]" % [int(L.price), str(L.get("expires", "")).left(16).replace("T", " ")],
			"Снять", func(): if not waiting: _ask("cancel", {"id": int(L.id)}), true)

func _build_mail() -> void:
	var pnl := UIK.panel(body); UIK.place(pnl, 0, 0.12, 1, 1)
	var v := UIK.scroll_list(pnl, 6)
	var gold := 0
	for m in mail:
		gold += int(m.get("gold", 0))
		_row(v, ("[color=#f2c46d]+%d золота[/color]  " % int(m.gold) if int(m.get("gold", 0)) > 0 else "") + (_item_text(m.item) + "  " if m.get("item") is Dictionary else "") + "[color=#aaaaaa]%s[/color]" % str(m.get("note", "")), "", Callable())
	if mail.is_empty(): UIK.label(v, "Почта пуста" if not waiting else "Загрузка…", 26, Color(0.7, 0.7, 0.7))
	var b := UIK.button(body, "Забрать всё (%d золота, вещей: %d)" % [gold, mail.filter(func(m): return m.get("item") is Dictionary).size()], func(): if not waiting: _ask("claim"), UIK.GREEN, 28)
	b.name = "ClaimBtn"; b.disabled = mail.is_empty()
	UIK.place(b, 0.3, 0.0, 0.7, 0.1)
