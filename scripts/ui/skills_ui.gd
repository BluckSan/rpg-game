extends Control
## Окно «Умения»: все умения класса и пути превращения, набор из 5 слотов (+ основная атака).
## Выберите умение слева, затем нажмите слот снизу (или «В свободный слот»). Повторный выбор слота — снять.

var zone
var data: Dictionary
var list: VBoxContainer
var slots_row: HBoxContainer
var d_icon: TextureRect
var d_title: Label
var d_body: RichTextLabel
var sel_id := ""

func setup(z) -> void:
	zone = z
	data = z.data
	process_mode = Node.PROCESS_MODE_ALWAYS
	DB.ensure_loadout(data)
	UIK.full(UIK.panel(self, Color(0.04, 0.03, 0.05, 0.95), 0))
	UIK.place(UIK.label(self, "Умения", 52, UIK.ACCENT), 0.06, 0.9, 0.5, 0.98)
	UIK.place(UIK.icon_rect(self, "book-cover", 64, UIK.ACCENT), 0.015, 0.905, 0.05, 0.975)
	var hint := UIK.label(self, "Выберите умение, затем слот внизу. Умения открываются с уровнем и мастерством, у пути превращения — свои.", 22, UIK.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UIK.place(hint, 0.36, 0.9, 0.98, 0.98)
	var lp := UIK.panel(self)
	UIK.place(lp, 0.02, 0.27, 0.5, 0.89)
	list = UIK.scroll_list(lp, 8)
	var dp := Panel.new(); dp.add_theme_stylebox_override("panel", UIK.frame("tooltip", Color.WHITE, 20))
	add_child(dp)
	UIK.place(dp, 0.51, 0.27, 0.98, 0.89)
	d_icon = UIK.icon_rect(dp, "book-cover", 96, UIK.ACCENT)
	UIK.place(d_icon, 0.04, 0.8, 0.16, 0.97)
	d_title = UIK.label(dp, "Выберите умение", 34, UIK.ACCENT)
	UIK.place(d_title, 0.18, 0.84, 0.97, 0.96)
	d_body = UIK.rich(dp, "", 25)
	UIK.place(d_body, 0.05, 0.22, 0.95, 0.8)
	var auto := UIK.button(dp, "В свободный слот", _to_free, UIK.GREEN, 28)
	auto.name = "ToFree"
	UIK.place(auto, 0.05, 0.04, 0.6, 0.18)
	var sp := UIK.panel(self)
	UIK.place(sp, 0.02, 0.03, 0.86, 0.25)
	slots_row = HBoxContainer.new(); slots_row.add_theme_constant_override("separation", 8)
	sp.add_child(slots_row)
	UIK.place(slots_row, 0.02, 0.08, 0.98, 0.92)
	var close := UIK.button(self, "Закрыть", func(): zone.hud.close_window(), UIK.BUTTON, 32)
	UIK.place(close, 0.87, 0.03, 0.98, 0.25)
	refresh()

func refresh() -> void:
	UIK.clear(list)
	var lo: Array = data["loadout"]
	for s in DB.skill_pool(data):
		var lock := DB.skill_lock(data, s)
		var row := UIK.hbox(list, 96, 12)
		var b := UIK.button(row, "", _select.bind(s.id), (s.color as Color).darkened(0.45) if lock == "" else Color(0.25, 0.23, 0.22), 26, UIK.SKILL_ICONS.get(s.id, "magic-swirl"))
		b.name = "Skill_" + s.id
		UIK.expand(b, 1.0)
		var tag := ""
		var si := lo.find(s.id)
		if si >= 0: tag = "  [слот %d]" % (si + 1)
		b.text = "%s%s%s" % [s.name, tag, ("   — " + lock) if lock != "" else ""]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if s.id == sel_id: b.modulate = Color(1.15, 1.15, 0.9)
	UIK.clear(slots_row)
	var basic: Dictionary = DB.CLASSES[data["class"]].skills[0]
	_slot_tile(-1, basic)
	for i in DB.LOADOUT_SLOTS:
		_slot_tile(i, DB.find_skill(data, str(lo[i])))
	_show_detail()

func _slot_tile(i: int, s) -> void:
	var title: String = (("ЛКМ · " if Game.desktop else "") + "Атака") if i < 0 else ("%d · %s" % [i + 1, s.name if s != null else "пусто"])
	var ic: String = UIK.SKILL_ICONS.get(s.id, "magic-swirl") if s != null else "aura"
	var b := UIK.button(slots_row, title, _slot_pressed.bind(i), (s.color as Color).darkened(0.5) if s != null else Color(0.2, 0.2, 0.22), 18, ic)
	b.name = "Slot_%d" % i
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIK.expand(b, 1.0)
	if i < 0: b.disabled = true

func _select(id: String) -> void:
	sel_id = id
	refresh()

func _show_detail() -> void:
	var s = DB.find_skill(data, sel_id)
	if s == null:
		d_title.text = "Выберите умение"
		d_body.text = "Набор: до 8 умений + основная атака. Новые умения открываются на уровнях 4, 6, 8, 10, 12; у каждого пути превращения — ещё 3."
		return
	d_icon.texture = UIK.icon(UIK.SKILL_ICONS.get(s.id, "magic-swirl"))
	d_icon.modulate = s.color
	d_title.text = s.name
	var lock := DB.skill_lock(data, s)
	var t: String = s.get("desc", "")
	t += "\n\n[color=#7fb2ff]Мана: %d[/color]    [color=#e6c27a]Перезарядка: %.0f с[/color]" % [int(s.mana), float(s.cd)]
	if float(s.get("mult", 0)) > 0: t += "\n[color=#ff9a6a]Сила: ×%.1f урона[/color]" % float(s.mult)
	if lock != "": t += "\n\n[color=#ff6a5a]Закрыто: %s[/color]" % lock
	d_body.text = t

func _slot_pressed(i: int) -> void:
	if i < 0: return
	var lo: Array = data["loadout"]
	if sel_id == "" or str(lo[i]) == sel_id:
		DB.set_loadout_slot(data, i, "")   # снять
	else:
		var s = DB.find_skill(data, sel_id)
		if s != null and DB.skill_lock(data, s) != "":
			Game.toast("Умение ещё закрыто: " + DB.skill_lock(data, s), 2.0)
			return
		DB.set_loadout_slot(data, i, sel_id)
	_apply()

func _to_free() -> void:
	if sel_id == "": return
	var lo: Array = data["loadout"]
	if lo.has(sel_id): return
	var f := lo.find("")
	if f < 0:
		Game.toast("Все слоты заняты — нажмите слот, чтобы заменить", 2.0)
		return
	if not DB.set_loadout_slot(data, f, sel_id):
		Game.toast("Умение ещё закрыто", 1.5)
		return
	_apply()

func _apply() -> void:
	var p: Player = zone.player
	for i in range(1, p.cooldowns.size()): p.cooldowns[i] = maxf(p.cooldowns[i], 1.0)
	zone.hud.refresh_skill_buttons()
	zone.save()
	refresh()
