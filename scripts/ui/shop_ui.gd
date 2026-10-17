extends Control
## Лавка торговца в лагере: покупка (зелья и снаряжение под уровень героя), продажа добычи, выкуп проданного.

var zone
var data: Dictionary
var tab := "buy"
var list: VBoxContainer
var gold_label: Label
var tab_btns := {}
var d_icon: TextureRect
var d_title: Label
var d_body: RichTextLabel
var d_price: Label
var d_btn: Button
var sel_kind := ""     # "potion", "stock", "inv", "buyback"
var sel_idx := -1
var restock_btn: Button

func setup(z) -> void:
	zone = z
	data = z.data
	DB.shop_ensure(data)
	process_mode = Node.PROCESS_MODE_ALWAYS
	UIK.full(UIK.panel(self, Color(0.02, 0.02, 0.03, 0.72), 0))
	var win := UIK.panel(self)
	UIK.place(win, 0.06, 0.05, 0.94, 0.95)
	var ic := UIK.icon_rect(win, "shop", 72, UIK.ACCENT); ic.position = Vector2(34, 26)
	var t := UIK.label(win, "Лавка Бориса", 52, UIK.ACCENT)
	t.name = "Title"
	t.autowrap_mode = TextServer.AUTOWRAP_OFF
	t.offset_left = 120; t.offset_top = 18; t.offset_right = 720; t.offset_bottom = 108
	var gb := HBoxContainer.new(); gb.add_theme_constant_override("separation", 10)
	win.add_child(gb); gb.anchor_left = 1; gb.anchor_right = 1; gb.offset_left = -560; gb.offset_right = -230; gb.offset_top = 34; gb.offset_bottom = 94
	gb.alignment = BoxContainer.ALIGNMENT_END
	UIK.icon_rect(gb, "two-coins", 44, Color(1, 0.82, 0.3))
	gold_label = UIK.label(gb, "", 36, Color(1, 0.85, 0.4))
	gold_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	var close := UIK.button(win, "Закрыть", _close, UIK.RED, 30)
	close.anchor_left = 1; close.anchor_right = 1; close.offset_left = -210; close.offset_right = -30; close.offset_top = 28; close.offset_bottom = 104

	# вкладки
	var tabs := HBoxContainer.new(); tabs.add_theme_constant_override("separation", 12)
	win.add_child(tabs); UIK.rect(tabs, Vector2(34, 120), Vector2(900, 84))
	for k in [["buy", "Купить", "swap-bag"], ["sell", "Продать", "two-coins"], ["buyback", "Выкуп", "backward-time"]]:
		var b := UIK.button(tabs, k[1], select_tab.bind(k[0]), UIK.BUTTON, 30, k[2])
		b.custom_minimum_size = Vector2(280, 80)
		tab_btns[k[0]] = b

	var lp := UIK.panel(win, Color(0.1, 0.08, 0.06, 0.9))
	lp.anchor_right = 0.56; lp.anchor_bottom = 1; lp.offset_left = 30; lp.offset_top = 216; lp.offset_bottom = -30
	list = UIK.scroll_list(lp, 8)

	# подробности (стиль подсказки)
	var dp := Panel.new(); dp.add_theme_stylebox_override("panel", UIK.frame("tooltip", Color.WHITE, 20))
	win.add_child(dp)
	dp.anchor_left = 0.57; dp.anchor_right = 1; dp.anchor_bottom = 1; dp.offset_right = -30; dp.offset_top = 216; dp.offset_bottom = -30
	d_icon = UIK.icon_rect(dp, "swap-bag", 96, UIK.ACCENT); d_icon.position = Vector2(30, 30)
	d_title = UIK.label(dp, "", 32, UIK.ACCENT)
	UIK.rect(d_title, Vector2(140, 26), Vector2(520, 110))
	d_body = UIK.rich(dp, "", 24)
	d_body.anchor_right = 1; d_body.anchor_bottom = 1; d_body.offset_left = 30; d_body.offset_right = -30; d_body.offset_top = 150; d_body.offset_bottom = -190
	d_price = UIK.label(dp, "", 30, Color(1, 0.85, 0.4))
	d_price.anchor_top = 1; d_price.anchor_bottom = 1; d_price.anchor_right = 1
	d_price.offset_left = 30; d_price.offset_right = -30; d_price.offset_top = -180; d_price.offset_bottom = -120
	d_btn = UIK.button(dp, "Купить", _on_action, UIK.GREEN, 32)
	d_btn.anchor_top = 1; d_btn.anchor_bottom = 1; d_btn.anchor_right = 1
	d_btn.offset_left = 30; d_btn.offset_right = -30; d_btn.offset_top = -110; d_btn.offset_bottom = -26
	select_tab("buy")

func _close() -> void:
	zone.save()
	zone.hud.close_window()

func select_tab(t: String) -> void:
	tab = t
	sel_kind = ""; sel_idx = -1
	for k in tab_btns: UIK.set_button_color(tab_btns[k], UIK.SELECT if k == t else UIK.BUTTON)
	refresh()

func _row(text: String, sub: String, ic: String, col: Color, price: String, cb: Callable, selected: bool) -> void:
	var b := UIK.button(list, "", cb, UIK.SELECT if selected else Color(0.2, 0.17, 0.14), 24)
	UIK.min_h(b, 92)
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h); UIK.full(h); h.offset_left = 14; h.offset_right = -16
	var slot := Panel.new(); slot.add_theme_stylebox_override("panel", UIK.frame("slot", col, 6))
	slot.custom_minimum_size = Vector2(72, 72); slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(slot)
	var ir := UIK.icon_rect(slot, ic, 52, col); ir.position = Vector2(10, 10)
	var v := VBoxContainer.new(); v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var l := UIK.label(v, text, 26, col); l.autowrap_mode = TextServer.AUTOWRAP_OFF; l.clip_text = true
	l.add_theme_font_override("font", UIK.title_font())
	UIK.label(v, sub, 20, UIK.MUTED).autowrap_mode = TextServer.AUTOWRAP_OFF
	var ph := HBoxContainer.new(); ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ph.add_theme_constant_override("separation", 6)
	h.add_child(ph)
	UIK.icon_rect(ph, "two-coins", 30, Color(1, 0.82, 0.3)).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UIK.label(ph, price, 26, Color(1, 0.85, 0.4)).autowrap_mode = TextServer.AUTOWRAP_OFF

func _sub(it: Dictionary) -> String:
	return "%s · %s · ур. %d" % [DB.SLOT_NAMES[int(it.slot)], DB.RARITY_NAMES[int(it.rarity)], int(it.ilvl)]

func refresh() -> void:
	gold_label.text = str(data["gold"])
	UIK.clear(list)
	match tab:
		"buy":
			_row("Зелье лечения", "Восстанавливает здоровье · у вас: %d" % data["potions"], "health-potion", Color(1, 0.45, 0.45),
				str(DB.potion_price(data["level"])), _select.bind("potion", 0), sel_kind == "potion")
			var stock: Array = data["shop"]["stock"]
			for i in stock.size():
				var it: Dictionary = stock[i]
				_row(it.name, _sub(it), UIK.item_icon(it, data["class"]), DB.RARITY_COLORS[int(it.rarity)], str(DB.buy_price(it)), _select.bind("stock", i), sel_kind == "stock" and sel_idx == i)
			restock_btn = UIK.button(list, "Обновить товары (%d зол.)" % DB.shop_restock_price(data["level"]), restock, UIK.BUTTON, 26, "backward-time")
			UIK.min_h(restock_btn, 76)
		"sell":
			var inv: Array = data["inventory"]
			if inv.is_empty(): UIK.min_h(UIK.label(list, "Инвентарь пуст — победите врагов, чтобы найти добычу.", 26, UIK.MUTED, HORIZONTAL_ALIGNMENT_CENTER), 120)
			for i in inv.size():
				var it: Dictionary = inv[i]
				_row(it.name, _sub(it), UIK.item_icon(it, data["class"]), DB.RARITY_COLORS[int(it.rarity)], "+" + str(DB.sell_price(it)), _select.bind("inv", i), sel_kind == "inv" and sel_idx == i)
		"buyback":
			var bb: Array = data["buyback"]
			if bb.is_empty(): UIK.min_h(UIK.label(list, "Здесь появятся проданные вещи — их можно вернуть по цене продажи.", 26, UIK.MUTED, HORIZONTAL_ALIGNMENT_CENTER), 120)
			for i in bb.size():
				var it: Dictionary = bb[i]
				_row(it.name, _sub(it), UIK.item_icon(it, data["class"]), DB.RARITY_COLORS[int(it.rarity)], str(DB.sell_price(it)), _select.bind("buyback", i), sel_kind == "buyback" and sel_idx == i)
	_update_detail()

func _select(kind: String, idx: int) -> void:
	sel_kind = kind; sel_idx = idx
	refresh()

func _sel_item():
	match sel_kind:
		"stock": return data["shop"]["stock"][sel_idx] if sel_idx < data["shop"]["stock"].size() else null
		"inv": return data["inventory"][sel_idx] if sel_idx < data["inventory"].size() else null
		"buyback": return data["buyback"][sel_idx] if sel_idx < data["buyback"].size() else null
	return null

func _update_detail() -> void:
	d_btn.visible = sel_kind != ""
	d_price.text = ""
	if sel_kind == "":
		d_icon.texture = UIK.icon("swap-bag"); d_icon.modulate = UIK.ACCENT
		d_title.text = "Борис"
		d_title.add_theme_color_override("font_color", UIK.ACCENT)
		d_body.text = {"buy": "Свежие товары под ваш уровень! Чем выше редкость, тем дороже.\nВыберите товар слева.",
			"sell": "Продавайте лишнюю добычу. Ошиблись — верните её во вкладке «Выкуп».",
			"buyback": "Последние %d проданных вещей можно выкупить по той же цене." % DB.BUYBACK_SIZE}[tab]
		return
	if sel_kind == "potion":
		d_icon.texture = UIK.icon("health-potion"); d_icon.modulate = Color(1, 0.45, 0.45)
		d_title.text = "Зелье лечения"
		d_title.add_theme_color_override("font_color", Color(1, 0.5, 0.5))
		d_body.text = "Мгновенно восстанавливает 45%% здоровья.\nКнопка «Зелье» в бою.\n\nУ вас: %d" % data["potions"]
		d_price.text = "Цена: %d" % DB.potion_price(data["level"])
		d_btn.text = "Купить"
		_btn_state(int(data["gold"]) >= DB.potion_price(data["level"]))
		return
	var it = _sel_item()
	if it == null:
		sel_kind = ""; _update_detail(); return
	var col: Color = DB.RARITY_COLORS[int(it.rarity)]
	d_icon.texture = UIK.icon(UIK.item_icon(it, data["class"])); d_icon.modulate = col
	d_title.text = it.name
	d_title.add_theme_color_override("font_color", col)
	var body := DB.describe_item(it)
	var cur = DB.get_equipped(data, int(it.slot))
	if cur != null:
		var diff := int(it.base) - int(cur.base)
		var dc := "#7fd87f" if diff > 0 else ("#e07070" if diff < 0 else "#bbbbbb")
		body += "\n\n[color=#aaa]Надето: %s (%s %d)[/color]  [color=%s]%s%d[/color]" % [cur.name, "урон" if int(cur.slot) == 0 else "броня", int(cur.base), dc, "+" if diff >= 0 else "", diff]
	d_body.text = body
	match sel_kind:
		"stock":
			d_price.text = "Цена: %d" % DB.buy_price(it); d_btn.text = "Купить"
			_btn_state(int(data["gold"]) >= DB.buy_price(it))
		"inv":
			d_price.text = "Вы получите: %d" % DB.sell_price(it); d_btn.text = "Продать"
			_btn_state(true)
		"buyback":
			d_price.text = "Цена выкупа: %d" % DB.sell_price(it); d_btn.text = "Выкупить"
			_btn_state(int(data["gold"]) >= DB.sell_price(it))

func _btn_state(ok: bool) -> void:
	d_btn.disabled = not ok
	UIK.set_button_color(d_btn, UIK.GREEN if ok else Color(0.3, 0.3, 0.3))

func _on_action() -> void:
	var err := ""
	match sel_kind:
		"potion": err = DB.shop_buy_potion(data)
		"stock": err = DB.shop_buy(data, sel_idx)
		"inv": err = DB.shop_sell(data, sel_idx)
		"buyback": err = DB.shop_buyback(data, sel_idx)
	if err == "" and sel_kind != "potion": sel_kind = ""
	if err != "": Game.toast(err, 1.5)
	else: _coin_fx()
	refresh()

func _coin_fx() -> void:
	gold_label.pivot_offset = gold_label.size / 2
	var tw := gold_label.create_tween()
	tw.tween_property(gold_label, "scale", Vector2.ONE * 1.25, 0.08)
	tw.tween_property(gold_label, "scale", Vector2.ONE, 0.15)

func restock() -> void:
	var price := DB.shop_restock_price(data["level"])
	if int(data["gold"]) < price:
		Game.toast("Не хватает золота", 1.5); return
	data["gold"] = int(data["gold"]) - price
	data["shop"]["stock"] = DB.shop_stock(int(data["level"]), data["class"])
	sel_kind = ""
	refresh()

# --- для автотестов ---
func buy_potion() -> bool:
	_select("potion", 0)
	var g: int = data["gold"]
	_on_action()
	return int(data["gold"]) < g

func buy(i: int) -> bool:
	tab = "buy"
	_select("stock", i)
	var n: int = data["inventory"].size()
	_on_action()
	return data["inventory"].size() > n

func sell(i: int) -> bool:
	tab = "sell"
	_select("inv", i)
	var g: int = data["gold"]
	_on_action()
	return int(data["gold"]) > g

func buyback(i: int) -> bool:
	tab = "buyback"
	_select("buyback", i)
	var n: int = data["inventory"].size()
	_on_action()
	return data["inventory"].size() > n
