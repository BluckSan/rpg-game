extends Control
## v0.9.0 — окно «Умения».
## 1) Умение открывается уровнем/мастерством/путём превращения, но само в набор НЕ встаёт.
## 2) Его нужно изучить за очко умений (ранг 1) и при желании улучшать (до ранга 5).
## 3) Изученное умение ставится в ЛЮБОЙ из 8 слотов вручную: на ПК — перетащить карточку на слот,
##    на телефоне — выбрать умение и нажать слот. Слот на слот — обмен; повторное нажатие — снять.

var zone
var data: Dictionary
var list: VBoxContainer
var slots_row: HBoxContainer
var d_icon: TextureRect
var d_title: Label
var d_body: RichTextLabel
var pts_lbl: Label
var learn_btn: Button
var place_btn: Button
var remove_btn: Button
var sel_id := ""
var placing := false     # режим «нажмите слот»
var _pulse := 0.0

func setup(z) -> void:
	zone = z
	data = z.data
	process_mode = Node.PROCESS_MODE_ALWAYS
	DB.ensure_loadout(data)
	UIK.full(UIK.panel(self, Color(0.04, 0.03, 0.05, 0.95), 0))
	UIK.place(UIK.label(self, "Умения", 52, UIK.ACCENT), 0.06, 0.9, 0.3, 0.98)
	UIK.place(UIK.icon_rect(self, "book-cover", 64, UIK.ACCENT), 0.015, 0.905, 0.05, 0.975)
	pts_lbl = UIK.label(self, "", 30, UIK.GREEN)
	pts_lbl.name = "Points"
	UIK.place(pts_lbl, 0.24, 0.91, 0.52, 0.97)
	var hint := UIK.label(self, ("Изучите умение за очко, затем перетащите его на любой слот внизу." if Game.desktop else "Изучите умение за очко, затем нажмите «В слот» и выберите любой слот внизу.") + " Новые умения сами в набор не встают.", 21, UIK.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UIK.place(hint, 0.53, 0.9, 0.86, 0.98)
	var rs := UIK.button(self, "Сбросить", _reset, UIK.BUTTON, 24)
	rs.name = "ResetSkills"
	UIK.place(rs, 0.87, 0.905, 0.98, 0.975)
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
	d_body = UIK.rich(dp, "", 24)
	UIK.place(d_body, 0.05, 0.22, 0.95, 0.8)
	learn_btn = UIK.button(dp, "Изучить", _learn, UIK.GREEN, 26)
	learn_btn.name = "Learn"
	UIK.place(learn_btn, 0.04, 0.04, 0.36, 0.18)
	place_btn = UIK.button(dp, "В слот", _start_place, UIK.BUTTON, 26)
	place_btn.name = "Place"
	UIK.place(place_btn, 0.38, 0.04, 0.66, 0.18)
	remove_btn = UIK.button(dp, "Снять", _remove_sel, UIK.BUTTON, 26)
	remove_btn.name = "Remove"
	UIK.place(remove_btn, 0.68, 0.04, 0.96, 0.18)
	var sp := UIK.panel(self)
	UIK.place(sp, 0.02, 0.03, 0.86, 0.25)
	slots_row = HBoxContainer.new(); slots_row.add_theme_constant_override("separation", 8)
	sp.add_child(slots_row)
	UIK.place(slots_row, 0.02, 0.08, 0.98, 0.92)
	var close := UIK.button(self, "Закрыть", func(): zone.hud.close_window(), UIK.BUTTON, 32)
	UIK.place(close, 0.87, 0.03, 0.98, 0.25)
	# сброс на пустое место окна (вне слотов) — снять умение со слота
	set_drag_forwarding(Callable(), _can_drop_bg, _drop_bg)
	refresh()

func _process(dt: float) -> void:
	_pulse += dt
	if not placing: return
	var k := 0.85 + 0.25 * absf(sin(_pulse * 4.0))
	for i in DB.LOADOUT_SLOTS:
		var b := slots_row.get_node_or_null("Slot_%d" % i)
		if b: b.modulate = Color(k, k * 1.05, 0.7 + 0.3 * k)

func _state(s: Dictionary) -> String:
	var u := DB.skill_unlock_block(data, s)
	if u != "": return "locked"
	if DB.skill_rank(data, s.id) == 0: return "learnable" if DB.skill_points_free(data) > 0 else "unlearned"
	return "learned"

func refresh() -> void:
	DB.ensure_loadout(data)
	var free := DB.skill_points_free(data)
	pts_lbl.text = "Очки умений: %d" % free
	pts_lbl.add_theme_color_override("font_color", UIK.GREEN if free > 0 else UIK.MUTED)
	UIK.clear(list)
	var lo: Array = data["loadout"]
	var cls_n: int = DB.CLASSES[data["class"]].skills.size() - 1
	var idx := 0
	for s in DB.skill_pool(data):
		if idx == 0 or idx == cls_n:
			var hdr := UIK.label(list, "Умения класса" if idx == 0 else "Путь «%s»" % DB.get_asc(data.get("ascendancy", "")).get("name", ""), 24, UIK.ACCENT)
			hdr.name = "Hdr_%d" % idx
		idx += 1
		var st := _state(s)
		var r := DB.skill_rank(data, s.id)
		var row := UIK.hbox(list, 96, 12)
		var col: Color = (s.color as Color).darkened(0.45) if st == "learned" else (Color(0.18, 0.32, 0.18) if st == "learnable" else Color(0.25, 0.23, 0.22))
		var b := UIK.button(row, "", _select.bind(s.id), col, 25, UIK.SKILL_ICONS.get(s.id, "magic-swirl"))
		b.name = "Skill_" + s.id
		UIK.expand(b, 1.0)
		var stars := ""
		for k in DB.SKILL_MAX_RANK: stars += "●" if k < r else "○"
		var tag := ""
		match st:
			"locked": tag = "   — " + DB.skill_unlock_block(data, s)
			"learnable": tag = "   — можно изучить"
			"unlearned": tag = "   — не изучено"
			_:
				var si := lo.find(s.id)
				tag = ("   [слот %d]" % (si + 1)) if si >= 0 else "   — не в наборе"
		b.text = "%s  %s%s" % [s.name, stars, tag]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if st == "locked": b.modulate = Color(0.7, 0.7, 0.7)
		if s.id == sel_id: b.modulate = Color(1.2, 1.2, 0.9)
		if st == "learned" and Game.desktop:
			b.set_drag_forwarding(_drag_skill.bind(s.id), Callable(), Callable())
		var up := UIK.button(row, "+", _learn_id.bind(s.id), UIK.GREEN, 30)
		up.name = "Up_" + s.id
		up.custom_minimum_size.x = 80
		up.disabled = DB.skill_learn_block(data, s) != ""
		up.tooltip_text = "Изучить" if r == 0 else "Улучшить до ранга %d" % (r + 1)
	UIK.clear(slots_row)
	var basic: Dictionary = DB.CLASSES[data["class"]].skills[0]
	_slot_tile(-1, basic)
	for i in DB.LOADOUT_SLOTS:
		_slot_tile(i, DB.find_skill(data, str(lo[i])))
	_show_detail()

func _slot_tile(i: int, s) -> void:
	var key := ""
	if Game.desktop: key = (Controls.key_hint("attack") if i < 0 else Controls.key_hint("skill_%d" % (i + 1)))
	var nm: String = ("Атака" if i < 0 else (s.name if s != null else "пусто"))
	var title := ("%s · %s" % [key, nm]) if key != "" else (("%d · " % (i + 1)) if i >= 0 else "") + nm
	var ic: String = UIK.SKILL_ICONS.get(s.id, "magic-swirl") if s != null else "aura"
	var b := UIK.button(slots_row, title, _slot_pressed.bind(i), (s.color as Color).darkened(0.5) if s != null else Color(0.2, 0.2, 0.22), 18, ic)
	b.name = "Slot_%d" % i
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIK.expand(b, 1.0)
	if i < 0:
		b.disabled = true
		return
	if s != null and str(data["loadout"][i]) == sel_id: b.modulate = Color(1.2, 1.2, 0.9)
	if Game.desktop:
		b.set_drag_forwarding(_drag_slot.bind(i), _can_drop_slot.bind(i), _drop_slot.bind(i))

# ---------- перетаскивание (ПК) ----------
func _drag_preview(id: String) -> Control:
	var s = DB.find_skill(data, id)
	var pv := TextureRect.new()
	pv.texture = UIK.icon(UIK.SKILL_ICONS.get(id, "magic-swirl"))
	pv.custom_minimum_size = Vector2(90, 90); pv.size = Vector2(90, 90)
	pv.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	if s != null: pv.modulate = s.color
	return pv

func _drag_skill(_at: Vector2, id: String):
	if DB.skill_lock(data, DB.find_skill(data, id)) != "": return null
	set_drag_preview(_drag_preview(id))
	return {"skill": id, "from": -1}

func _drag_slot(_at: Vector2, i: int):
	var id := str(data["loadout"][i])
	if id == "": return null
	set_drag_preview(_drag_preview(id))
	return {"skill": id, "from": i}

func _can_drop_slot(_at: Vector2, d, _i: int) -> bool:
	return d is Dictionary and d.has("skill")

func _drop_slot(_at: Vector2, d, i: int) -> void:
	drop_on_slot(str(d.skill), i)

func _can_drop_bg(_at: Vector2, d) -> bool:
	return d is Dictionary and int(d.get("from", -1)) >= 0

func _drop_bg(_at: Vector2, d) -> void:
	DB.set_loadout_slot(data, int(d.from), "")
	_apply()

## Поставить умение в слот (общая логика перетаскивания и выбора-нажатия). Возвращает успех.
func drop_on_slot(id: String, i: int) -> bool:
	var s = DB.find_skill(data, id)
	if s == null: return false
	var why := DB.skill_lock(data, s)
	if why != "":
		Game.toast("«%s»: %s — сначала изучите" % [s.name, why] if why == "Не изучено" else "«%s»: %s" % [s.name, why], 2.0)
		return false
	DB.set_loadout_slot(data, i, id)
	placing = false
	sel_id = id
	_apply()
	return true

# ---------- выбор и нажатия ----------
func _select(id: String) -> void:
	if DragScroll.dragging: return
	sel_id = id
	placing = false
	refresh()

func _slot_pressed(i: int) -> void:
	if i < 0: return
	var lo: Array = data["loadout"]
	var cur := str(lo[i])
	if sel_id != "" and cur == sel_id and not placing:
		DB.set_loadout_slot(data, i, "")   # повторное нажатие — снять
		_apply(); return
	if sel_id != "" and cur != sel_id:
		var s = DB.find_skill(data, sel_id)
		if s != null and DB.skill_lock(data, s) == "":
			drop_on_slot(sel_id, i); return
	if cur != "":                         # ничего (подходящего) не выбрано — показать умение из слота
		sel_id = cur; placing = false; refresh(); return
	if sel_id != "":
		drop_on_slot(sel_id, i)

func _start_place() -> void:
	var s = DB.find_skill(data, sel_id)
	if s == null: return
	if DB.skill_lock(data, s) != "":
		Game.toast("Сначала изучите умение", 1.6); return
	placing = true
	Game.toast("Нажмите любой слот внизу", 1.6)

func _remove_sel() -> void:
	var lo: Array = data["loadout"]
	var i := lo.find(sel_id)
	if i < 0: return
	DB.set_loadout_slot(data, i, "")
	_apply()

func _learn() -> void:
	_learn_id(sel_id)

func _learn_id(id: String) -> void:
	if DragScroll.dragging or id == "": return
	var r0 := DB.skill_rank(data, id)
	var why := DB.learn_skill(data, id)
	if why != "":
		Game.toast(why, 1.8); return
	sel_id = id
	var s = DB.find_skill(data, id)
	Game.sfx("level")
	Game.toast(("Изучено «%s» — поставьте его в слот" % s.name) if r0 == 0 else "«%s»: ранг %d" % [s.name, r0 + 1], 2.2)
	if r0 == 0 and not Game.desktop: placing = true
	zone.player.recalc()
	_apply()

func _reset() -> void:
	DB.reset_skills(data)
	sel_id = ""; placing = false
	Game.toast("Умения сброшены, очки возвращены", 2.0)
	zone.player.recalc()
	_apply()

func _show_detail() -> void:
	var s = DB.find_skill(data, sel_id)
	learn_btn.visible = s != null
	place_btn.visible = s != null
	remove_btn.visible = s != null and (data["loadout"] as Array).has(sel_id)
	if s == null:
		d_title.text = "Выберите умение"
		d_body.text = "Очки умений: +1 за уровень героя и +1 за каждые 3 уровня мастерства.\nИзучите умение (ранг 1), улучшайте до ранга 5: +12% силы и −4% перезарядки за ранг.\nНабор: 8 слотов + основная атака. Любое изученное умение — в любой слот."
		return
	d_icon.texture = UIK.icon(UIK.SKILL_ICONS.get(s.id, "magic-swirl"))
	d_icon.modulate = s.color
	var r := DB.skill_rank(data, s.id)
	d_title.text = "%s — ранг %d/%d" % [s.name, r, DB.SKILL_MAX_RANK]
	var e := DB.skill_eff(data, s)
	var t: String = s.get("desc", "")
	t += "\n\n[color=#7fb2ff]Мана: %d[/color]    [color=#e6c27a]Перезарядка: %.1f с[/color]" % [int(e.mana), float(e.cd)]
	if float(s.get("mult", 0)) > 0: t += "\n[color=#ff9a6a]Сила: ×%.2f урона[/color]" % float(e.mult)
	if r < DB.SKILL_MAX_RANK and r > 0:
		var nx: Dictionary = s.duplicate(); var tmp: Dictionary = data.duplicate(); tmp["skill_ranks"] = (data.get("skill_ranks", {}) as Dictionary).duplicate(); tmp["skill_ranks"][s.id] = r + 1
		var e2 := DB.skill_eff(tmp, nx)
		t += "\n[color=#9adf7a]Ранг %d: перезарядка %.1f с%s (нужен %d ур.)[/color]" % [r + 1, float(e2.cd), (", ×%.2f" % float(e2.mult)) if float(s.get("mult", 0)) > 0 else "", DB.skill_rank_level(s, r + 1)]
	var ub := DB.skill_unlock_block(data, s)
	if ub != "": t += "\n\n[color=#ff6a5a]Закрыто: %s[/color]" % ub
	elif r == 0: t += "\n\n[color=#ffd36a]Не изучено. Изучите за 1 очко, затем поставьте в слот.[/color]"
	d_body.text = t
	var lb := DB.skill_learn_block(data, s)
	learn_btn.text = ("Изучить (1 очко)" if r == 0 else "Улучшить (1 очко)") if lb == "" else (lb if r < DB.SKILL_MAX_RANK else "Ранг 5 — максимум")
	learn_btn.disabled = lb != ""
	place_btn.disabled = DB.skill_lock(data, s) != ""
	place_btn.text = "Перетащите на слот" if Game.desktop and not place_btn.disabled else "В слот"

func _apply() -> void:
	var p: Player = zone.player
	for i in range(1, p.cooldowns.size()): p.cooldowns[i] = maxf(p.cooldowns[i], 1.0)
	zone.hud.refresh_skill_buttons()
	zone.save()
	refresh()
