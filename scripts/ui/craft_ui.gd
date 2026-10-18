extends Control
## v0.9.1: ремесло комплектов. Материалы — с боссов подземелий (Хранитель Эфира, Ворагос, Морвен, Аэтерон).
## Выберите комплект (своего класса/общий; обычные — до вашего уровня, рейдовые — всегда) и слот-часть;
## цена: материал комплекта (2 + ур/8, рейдовые 3 + ур/8) и золото (30·ур, рейдовые 60·ур).
## Онлайн изготовление проверяет и выполняет сервер (Net.craft → s_craft_ok); офлайн — сразу.

var zone
var data: Dictionary
var sets_box: VBoxContainer
var pieces_box: HBoxContainer
var info: RichTextLabel
var mats_lbl: RichTextLabel
var make_btn: Button
var sel_set := ""
var sel_piece := 0
var waiting := false
var last_item: Dictionary = {}

func setup(z) -> void:
	zone = z
	data = z.data
	process_mode = Node.PROCESS_MODE_ALWAYS
	UIK.full(UIK.panel(self, Color(0.04, 0.03, 0.05, 0.96), 0))
	UIK.place(UIK.label(self, "Ремесло комплектов", 48, UIK.ACCENT), 0.03, 0.9, 0.5, 0.98)
	mats_lbl = UIK.rich(self, "", 24)
	mats_lbl.name = "Mats"
	UIK.place(mats_lbl, 0.4, 0.88, 0.86, 0.985)
	var close := UIK.button(self, "Закрыть", func(): zone.hud.close_window(), UIK.RED, 30)
	UIK.place(close, 0.87, 0.905, 0.98, 0.975)
	var lp := UIK.panel(self)
	UIK.place(lp, 0.02, 0.03, 0.36, 0.88)
	sets_box = UIK.scroll_list(lp, 8)
	var rp := UIK.panel(self, Color(0.07, 0.06, 0.09, 0.9))
	UIK.place(rp, 0.37, 0.03, 0.98, 0.88)
	info = UIK.rich(rp, "", 25)
	UIK.place(info, 0.03, 0.42, 0.97, 0.97)
	var pb := Control.new(); rp.add_child(pb)
	UIK.place(pb, 0.03, 0.22, 0.97, 0.4)
	pieces_box = HBoxContainer.new(); pieces_box.add_theme_constant_override("separation", 8)
	pb.add_child(pieces_box); UIK.full(pieces_box)
	make_btn = UIK.button(rp, "Создать", _make, UIK.GREEN, 30, "thor-hammer")
	make_btn.name = "Make"
	UIK.place(make_btn, 0.3, 0.03, 0.7, 0.18)
	if not Net.crafted.is_connected(_on_crafted): Net.crafted.connect(_on_crafted)
	var cs := Items.craftable_sets(data)
	if not cs.is_empty(): sel_set = cs[0]
	refresh()

func _exit_tree() -> void:
	if Net.crafted.is_connected(_on_crafted): Net.crafted.disconnect(_on_crafted)

func refresh() -> void:
	var mats: Dictionary = data.get("mats", {})
	var mt := "[right]"
	for mid in Items.MATS:
		mt += "[color=#%s]%s: %d[/color]   " % [(Items.MATS[mid].col as Color).to_html(false), Items.MATS[mid].name, int(mats.get(mid, 0))]
	mats_lbl.text = mt + "\n[color=#f2c46d]Золото: %d[/color][/right]" % int(data.get("gold", 0))
	UIK.clear(sets_box)
	for sid in Items.craftable_sets(data):
		var sd: Dictionary = Items.SETS[sid]
		var b := UIK.button(sets_box, "%s%s" % [sd.name, "  (рейд)" if sd.get("raid", false) else "  (ур. %d)" % int(sd.lvl)], select_set.bind(sid),
			Color(0.3, 0.22, 0.4) if sid == sel_set else UIK.BUTTON, 24)
		b.name = "Set_" + sid
		b.custom_minimum_size.y = 64
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	UIK.clear(pieces_box)
	if sel_set == "":
		info.text = "Нет доступных комплектов"; make_btn.disabled = true; return
	var sd2: Dictionary = Items.SETS[sel_set]
	for i in (sd2.pieces as Array).size():
		var t: String = sd2.pieces[i]
		var td: Dictionary = Items.TYPES[t]
		var pbt := UIK.button(pieces_box, "%s\n%s" % [Items.SLOT_NAMES[int(td.slot)], td.names[0]], select_piece.bind(i), Color(0.25, 0.4, 0.3) if i == sel_piece else UIK.BUTTON, 20)
		pbt.name = "Piece_%d" % i
		UIK.expand(pbt, 1.0)
	var cost := Items.craft_cost(sel_set, int(data.level))
	var why := Items.craft_block(data, sel_set, sel_piece)
	var t2 := "[b]%s[/b]\n" % sd2.name
	t2 += "2 части: %s\n4 части: %s\n6 частей: %s\n\n" % [_mods(sd2.b2), _mods(sd2.b4), str(sd2.b6.desc)]
	t2 += "Цена: [color=#%s]%s ×%d[/color] (есть %d) и [color=#f2c46d]%d золота[/color]\n" % [(Items.MATS[cost.mat].col as Color).to_html(false), Items.MATS[cost.mat].name, int(cost.n), int((data.get("mats", {}) as Dictionary).get(cost.mat, 0)), int(cost.gold)]
	t2 += "[color=#999]%s[/color]\n" % Items.MATS[cost.mat].desc
	if why != "": t2 += "\n[color=#ff7a6a]%s[/color]" % why
	if not last_item.is_empty(): t2 += "\n\n[color=#9adf7a]Создано: %s[/color]" % str(last_item.get("name", ""))
	info.text = t2
	make_btn.disabled = why != "" or waiting
	make_btn.text = "Ждём сервер…" if waiting else "Создать"

func _mods(list: Array) -> String:
	var out := []
	for m in list: out.append(DB.describe_mod(m).strip_edges())
	return ", ".join(out)

func select_set(sid: String) -> void:
	sel_set = sid; sel_piece = 0; last_item = {}; refresh()

func select_piece(i: int) -> void:
	sel_piece = i; refresh()

func _make() -> void:
	if Items.craft_block(data, sel_set, sel_piece) != "" or waiting: return
	if Net.in_game:
		waiting = true
		Net.craft(sel_set, sel_piece)
		refresh()
		get_tree().create_timer(5.0, true, false, true).timeout.connect(func(): if is_instance_valid(self) and waiting: waiting = false; refresh())
		return
	var it := Items.craft(data, sel_set, sel_piece)
	if not it.is_empty(): _on_crafted(it)

func _on_crafted(it: Dictionary) -> void:
	waiting = false
	last_item = it
	Game.sfx("level")
	Game.toast("Создано: %s" % str(it.get("name", "")), 2.5)
	zone.save()
	refresh()
