extends Control
## Окно героя: характеристики, снаряжение, инвентарь.

var zone
var data: Dictionary
var stats_text: RichTextLabel
var equip_grid: GridContainer
var inv_list: VBoxContainer
var detail_title: Label
var detail_icon: TextureRect
var detail_body: RichTextLabel
var action_btn: Button
var sell_btn: Button
var selected = null
var selected_equipped := false

func setup(z) -> void:
	zone = z
	data = z.data
	process_mode = Node.PROCESS_MODE_ALWAYS
	UIK.full(UIK.panel(self, Color(0.04, 0.03, 0.03, 0.94), 0))
	var tl := UIK.label(self, "Герой", 52, UIK.ACCENT)
	UIK.place(tl, 0.06, 0.9, 0.5, 0.98)
	var ti := UIK.icon_rect(self, "person", 64, UIK.ACCENT)
	UIK.place(ti, 0.015, 0.905, 0.05, 0.975)
	var sp := UIK.panel(self)
	UIK.place(sp, 0.02, 0.04, 0.3, 0.89)
	stats_text = UIK.rich(sp, "", 25)
	UIK.full(stats_text); stats_text.offset_left = 20; stats_text.offset_top = 16; stats_text.offset_right = -20; stats_text.offset_bottom = -16
	stats_text.scroll_active = true
	stats_text.mouse_filter = Control.MOUSE_FILTER_PASS

	var ep := UIK.panel(self)
	UIK.place(ep, 0.31, 0.47, 0.62, 0.89)
	UIK.place(UIK.label(ep, "Снаряжение", 30, UIK.ACCENT, HORIZONTAL_ALIGNMENT_CENTER), 0, 0.85, 1, 0.98)
	equip_grid = GridContainer.new(); equip_grid.columns = 2
	equip_grid.add_theme_constant_override("h_separation", 12); equip_grid.add_theme_constant_override("v_separation", 12)
	ep.add_child(equip_grid)
	UIK.place(equip_grid, 0.03, 0.03, 0.97, 0.84)

	var dp := Panel.new(); dp.add_theme_stylebox_override("panel", UIK.frame("tooltip", Color.WHITE, 20))
	add_child(dp)
	UIK.place(dp, 0.31, 0.04, 0.62, 0.46)
	detail_icon = UIK.icon_rect(dp, "swap-bag", 72, UIK.ACCENT)
	UIK.place(detail_icon, 0.03, 0.76, 0.16, 0.97)
	detail_title = UIK.label(dp, "Выберите предмет", 30, UIK.ACCENT)
	UIK.place(detail_title, 0.18, 0.78, 0.96, 0.96)
	detail_body = UIK.rich(dp, "", 24)
	UIK.place(detail_body, 0.04, 0.26, 0.96, 0.78)
	action_btn = UIK.button(dp, "Надеть", _on_action, UIK.GREEN, 28)
	UIK.place(action_btn, 0.04, 0.04, 0.6, 0.24)
	sell_btn = UIK.button(dp, "Продать", _on_sell, Color(0.5, 0.35, 0.1), 28)
	UIK.place(sell_btn, 0.63, 0.04, 0.96, 0.24)

	var ip := UIK.panel(self)
	UIK.place(ip, 0.63, 0.14, 0.98, 0.89)
	inv_list = UIK.scroll_list(ip, 6)
	UIK.place(UIK.button(self, "Закрыть", _close, UIK.BUTTON, 32), 0.63, 0.03, 0.98, 0.12)
	refresh()

func _close() -> void:
	zone.save()
	zone.hud.close_window()

func refresh() -> void:
	var st: Dictionary = zone.player.stats
	var cls: Dictionary = DB.CLASSES[data["class"]]
	var asc := DB.get_asc(data["ascendancy"])
	var dmg: float = st.damage * st.dmg_mult * (st.spell_mult if cls.spell else 1.0)
	var I := func(n: String) -> String: return "[img=30x30]res://assets/icons/%s.svg[/img] " % n
	stats_text.text = "[font_size=34][b]%s[/b][/font_size]\n[color=#e6c27a]%s%s[/color]\nУровень %d · мастерство %d\nОпыт класса: %d/%d\n\n" % [
		data["name"], cls.name, (" → " + asc["name"]) if not asc.is_empty() else "", data["level"], data["class_level"],
		data["class_xp"], DB.class_xp_to_next(data["class_level"])]
	stats_text.text += I.call("heart-bottle") + "Здоровье: %d\n" % roundi(st.max_hp)
	stats_text.text += I.call("drop") + "Мана: %d\n" % roundi(st.max_mp)
	stats_text.text += I.call("sword-wound") + "Урон: %d\n" % roundi(dmg)
	stats_text.text += I.call("lightning-frequency") + "Скорость атаки: %d%%\n" % roundi(st.attack_speed * 100)
	stats_text.text += I.call("crossed-swords") + "Крит: %.1f%% (x%.2f)\n" % [st.crit * 100, st.crit_mult]
	stats_text.text += I.call("checked-shield") + "Броня: %d (−%d%% урона)\n" % [roundi(st.armor), roundi(st.dr * 100)]
	stats_text.text += I.call("heart-beats") + "Регенерация: %.1f/с · мана %.1f/с\n" % [st.regen, st.mp_regen]
	stats_text.text += I.call("skull-mask") + "Похищение жизни: %.1f%%\n" % (st.leech * 100)
	stats_text.text += I.call("sprint") + "Скорость бега: %.1f\n" % st.move_speed
	stats_text.text += I.call("hourglass") + "Сокр. перезарядки: %d%%\n\n" % roundi(st.cdr * 100)
	stats_text.text += I.call("two-coins") + "Золото: %d   " % data["gold"] + I.call("health-potion") + "Зелья: %d\n" % data["potions"]
	stats_text.text += I.call("broken-skull") + "Убито врагов: %d" % data["kills"]

	UIK.clear(equip_grid)
	for s in 4:
		var it = DB.get_equipped(data, s)
		var t: String = DB.SLOT_NAMES[s] + "\n" + (it.name if it != null else "пусто")
		var b := UIK.button(equip_grid, t, _select.bind(it, true) if it != null else Callable(), UIK.SELECT if (it != null and it == selected) else Color(0.22, 0.18, 0.14), 24,
			UIK.item_icon(it, data["class"]) if it != null else UIK.SLOT_ICONS[s])
		b.add_theme_constant_override("icon_max_width", 56)
		if it != null: b.add_theme_color_override("icon_normal_color", DB.RARITY_COLORS[int(it.rarity)])
		else: b.add_theme_color_override("icon_normal_color", Color(1, 1, 1, 0.3))
		b.custom_minimum_size = Vector2(270, 140)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		if it != null: b.add_theme_color_override("font_color", DB.RARITY_COLORS[int(it.rarity)])

	UIK.clear(inv_list)
	UIK.min_h(UIK.label(inv_list, "Инвентарь (%d/%d)" % [data["inventory"].size(), DB.INVENTORY_SIZE], 28, UIK.ACCENT, HORIZONTAL_ALIGNMENT_CENTER), 50)
	for it in data["inventory"]:
		var b := UIK.button(inv_list, "%s  (%s, ур. %d)" % [it.name, DB.SLOT_NAMES[int(it.slot)], int(it.ilvl)], _select.bind(it, false),
			UIK.SELECT if it == selected else Color(0.22, 0.18, 0.14), 24, UIK.item_icon(it, data["class"]))
		b.add_theme_constant_override("icon_max_width", 44)
		b.add_theme_color_override("icon_normal_color", DB.RARITY_COLORS[int(it.rarity)])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_color_override("font_color", DB.RARITY_COLORS[int(it.rarity)])
		UIK.min_h(b, 70)
	_update_detail()

func _select(it, equipped: bool) -> void:
	selected = it
	selected_equipped = equipped
	refresh()

func _update_detail() -> void:
	var has: bool = selected != null
	action_btn.visible = has
	sell_btn.visible = has and not selected_equipped
	if not has:
		detail_icon.texture = UIK.icon("swap-bag"); detail_icon.modulate = UIK.ACCENT
		detail_title.text = "Выберите предмет"
		detail_body.text = "Нажмите на предмет в инвентаре или снаряжении."
		return
	detail_title.text = selected.name
	detail_title.add_theme_color_override("font_color", DB.RARITY_COLORS[int(selected.rarity)])
	detail_icon.texture = UIK.icon(UIK.item_icon(selected, data["class"])); detail_icon.modulate = DB.RARITY_COLORS[int(selected.rarity)]
	var body := DB.describe_item(selected)
	if not selected_equipped:
		var cur = DB.get_equipped(data, int(selected.slot))
		if cur != null:
			var diff := int(selected.base) - int(cur.base)
			body += "\n\n[color=#aaa][font_size=21]Надето: %s (%s %d)[/font_size][/color] [color=%s]%s%d[/color]" % [cur.name, "урон" if int(cur.slot) == 0 else "броня", int(cur.base), "#7fd87f" if diff > 0 else ("#e07070" if diff < 0 else "#bbbbbb"), "+" if diff >= 0 else "", diff]
	detail_body.text = body
	action_btn.text = "Снять" if selected_equipped else "Надеть"
	sell_btn.text = "Продать (%d)" % DB.sell_price(selected)

func _on_action() -> void:
	if selected == null: return
	if selected_equipped:
		if int(selected.slot) == 0:
			Game.toast("Без оружия никак!")
			return
		if data["inventory"].size() >= DB.INVENTORY_SIZE:
			Game.toast("Инвентарь полон")
			return
		data["equipped"].erase(selected)
		data["inventory"].append(selected)
	else:
		var cur = DB.get_equipped(data, int(selected.slot))
		if cur != null:
			data["equipped"].erase(cur)
			data["inventory"].append(cur)
		data["inventory"].erase(selected)
		data["equipped"].append(selected)
	selected = null
	zone.apply_character_changes(false)
	refresh()

func _on_sell() -> void:
	if selected == null or selected_equipped: return
	data["gold"] += DB.sell_price(selected)
	data["inventory"].erase(selected)
	selected = null
	refresh()
