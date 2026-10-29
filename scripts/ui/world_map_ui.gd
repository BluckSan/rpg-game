extends Control
## Карта мира (v0.5.1): подробная запечённая карта (рельеф, вода, леса, дороги, границы зон) + векторный слой.
## Масштаб: колесо мыши, щипок двумя пальцами, кнопки «+»/«−»; перетаскивание — сдвиг; «◎» — к герою.
## Чем ближе — тем больше подробностей: малые точки, редкие враги, торговцы, сундуки, постройки городов, подписи.
## Касание значка — подсказка (у открытого камня — кнопка перемещения). Легенда сворачивается, категории отключаются.

const ZMIN := 1.0
const ZMAX := 10.0
## категория: [название, значок, цвет, с какого масштаба видна]
const CATS := {
	"player": ["Вы", "", Color(1, 0.95, 0.5), 1.0],
	"quest": ["Цель", "bullseye", Color(1, 0.85, 0.2), 1.0],
	"town": ["Города и лагеря", "village", Color(1, 0.88, 0.6), 1.0],
	"waypoint": ["Путевые камни", "", Color(0.35, 0.8, 1.0), 1.0],
	"boss": ["Боссы зон", "skull-crossed-bones", Color(1, 0.35, 0.3), 1.0],
	"dungeon": ["Входы в подземелья", "delapouite/dungeon-gate", Color(0.8, 0.6, 1.0), 1.0],
	"portal": ["Порталы", "magic-portal", Color(0.4, 0.9, 1.0), 1.0],
	"poi": ["Достопримечательности", "treasure-map", Color(0.95, 0.8, 0.55), 1.0],
	"minor": ["Малые места (лагеря, руины…)", "campfire", Color(0.9, 0.75, 0.55), 1.8],
	"rare": ["Элиты и редкие враги", "crowned-skull", Color(1, 0.55, 0.9), 2.2],
	"merchant": ["Торговцы", "two-coins", Color(1, 0.85, 0.3), 2.2],
	"stash": ["Сундуки-хранилища", "chest", Color(0.85, 0.65, 0.4), 2.2],
	"resource": ["Ресурсы (дерево, камень, грибы)", "wood-pile", Color(0.7, 0.85, 0.5), 3.0],
	"building": ["Постройки", "", Color(0.9, 0.85, 0.75), 3.0],
}
const MINOR_ICON := {"farm": "barn", "camp": "campfire", "hunters": "campfire", "cart": "caravan", "shrine": "obelisk", "woodpile": "wood-pile",
	"ruin": "castle-ruins", "shrooms": "mushroom-gills", "bones": "tombstone", "obelisk": "obelisk", "graves": "tombstone", "boat": "caravan",
	"tower": "stone-tower", "siege": "ancient-ruins"}
const RESOURCE_KINDS := ["woodpile", "shrooms", "farm"]

var zone
var data: Dictionary
var map_rect: Control
var list: VBoxContainer
var info: Label
var legend: Control
var legend_body: VBoxContainer
var tip: PanelContainer
var tip_label: RichTextLabel
var tip_btn: Button
var zoom := 1.0
var center := Vector2.ZERO          # мировые XZ в центре окна карты
var off_cats := {}                    # выключенные категории
var _tex: Texture2D
var _font: Font
var _icons := {}
var _drag := false
var _drag_moved := 0.0
var _touches := {}                  # индекс → позиция (щипок)
var _pinch_d := 0.0
var _tip_target := {}
var markers: Array = []             # последний набор значков на экране (для касаний и тестов)

func setup(z) -> void:
	zone = z
	data = z.data
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = UIK.title_font()
	_tex = load("res://assets/world/worldmap.png")
	for k in CATS:
		if CATS[k][1] != "": _icons[k] = _icon(CATS[k][1])
	for k in MINOR_ICON: _icons["m_" + k] = _icon(MINOR_ICON[k])
	UIK.full(UIK.panel(self, Color(0.03, 0.025, 0.02, 0.97), 0))
	var ic := UIK.icon_rect(self, "treasure-map", 64, UIK.ACCENT); ic.position = Vector2(28, 22)
	var t := UIK.label(self, "Земли Эфира", 50, UIK.ACCENT); t.autowrap_mode = TextServer.AUTOWRAP_OFF
	UIK.rect(t, Vector2(104, 14), Vector2(700, 84))
	var close := UIK.button(self, "Закрыть", _close, UIK.RED, 30)
	close.anchor_left = 1; close.anchor_right = 1; close.offset_left = -230; close.offset_right = -24; close.offset_top = 18; close.offset_bottom = 96
	map_rect = Control.new(); map_rect.name = "Map"
	map_rect.clip_contents = true
	map_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	map_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(map_rect)
	map_rect.anchor_right = 1; map_rect.anchor_bottom = 1
	map_rect.offset_left = 24; map_rect.offset_top = 108; map_rect.offset_bottom = -20; map_rect.offset_right = -660
	map_rect.draw.connect(_draw_map)
	map_rect.gui_input.connect(_on_map_input)
	map_rect.resized.connect(func(): map_rect.queue_redraw())
	# кнопки масштаба
	var zb := VBoxContainer.new(); zb.name = "ZoomButtons"; zb.add_theme_constant_override("separation", 10)
	map_rect.add_child(zb)
	zb.anchor_left = 1; zb.anchor_right = 1; zb.offset_left = -96; zb.offset_right = -14; zb.offset_top = 14
	for spec in [["+", func(): zoom_by(1.6)], ["−", func(): zoom_by(1.0 / 1.6)], ["◎", center_on_player]]:
		var b := UIK.button(zb, spec[0], spec[1], UIK.BUTTON, 38)
		b.name = "Zoom" + ("In" if spec[0] == "+" else ("Out" if spec[0] == "−" else "Center"))
		UIK.min_h(b, 76); b.custom_minimum_size.x = 82
	# подсказка значка
	tip = PanelContainer.new(); tip.name = "Tip"; tip.visible = false
	var tsb := StyleBoxFlat.new(); tsb.bg_color = Color(0.06, 0.05, 0.04, 0.95); tsb.border_color = UIK.ACCENT
	tsb.set_border_width_all(2); tsb.set_corner_radius_all(10); tsb.content_margin_left = 16; tsb.content_margin_right = 16
	tsb.content_margin_top = 10; tsb.content_margin_bottom = 10
	tip.add_theme_stylebox_override("panel", tsb)
	map_rect.add_child(tip)
	var tv := VBoxContainer.new(); tip.add_child(tv)
	tip_label = RichTextLabel.new(); tip_label.bbcode_enabled = true; tip_label.fit_content = true
	tip_label.custom_minimum_size = Vector2(380, 0); tip_label.scroll_active = false
	tip_label.add_theme_font_size_override("normal_font_size", 24); tip_label.add_theme_font_size_override("bold_font_size", 27)
	tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(tip_label)
	tip_btn = UIK.button(tv, "Переместиться", _tip_action, UIK.BLUE, 26, "treasure-map")
	UIK.min_h(tip_btn, 60)
	# правая панель: легенда (сворачивается) + путевые камни
	var rp := UIK.panel(self)
	rp.anchor_left = 1; rp.anchor_right = 1; rp.anchor_bottom = 1
	rp.offset_left = -620; rp.offset_right = -20; rp.offset_top = 108; rp.offset_bottom = -20
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 8); rp.add_child(v); UIK.full(v)
	v.offset_left = 18; v.offset_right = -18; v.offset_top = 14; v.offset_bottom = -14
	info = UIK.label(v, "", 22, UIK.MUTED)
	var lt := UIK.button(v, "Легенда ▾", toggle_legend, UIK.BUTTON, 26, "compass")
	lt.name = "LegendToggle"; UIK.min_h(lt, 56)
	legend = VBoxContainer.new(); legend.name = "Legend"; v.add_child(legend)
	legend_body = legend as VBoxContainer
	legend_body.add_theme_constant_override("separation", 2)
	for k in CATS: _legend_row(k)
	var lh := UIK.label(v, "Порталы и путевые камни", 28, UIK.ACCENT); lh.autowrap_mode = TextServer.AUTOWRAP_OFF
	var holder := Control.new(); holder.size_flags_vertical = Control.SIZE_EXPAND_FILL; v.add_child(holder)
	list = UIK.scroll_list(holder, 8)
	var pp: Vector3 = zone.player.global_position
	center = Vector2(pp.x, pp.z)
	zoom = 1.0
	refresh()

func _icon(n: String) -> Texture2D:
	var name := n.get_file()
	return UIK.icon(name)

func _legend_row(k: String) -> void:
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 10)
	legend_body.add_child(h)
	var cb := CheckBox.new(); cb.name = "Cat_" + k; cb.button_pressed = true
	cb.add_theme_font_size_override("font_size", 22)
	cb.toggled.connect(func(on): set_category(k, on))
	h.add_child(cb)
	var sw := Control.new(); sw.custom_minimum_size = Vector2(30, 30)
	sw.draw.connect(func(): _draw_symbol(sw, k, Vector2(15, 15), ""))
	h.add_child(sw)
	var l := UIK.label(h, CATS[k][0] + ("" if CATS[k][3] <= 1.0 else "  (×%.1f+)" % CATS[k][3]), 21, UIK.TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF

func toggle_legend() -> void:
	legend.visible = not legend.visible

func set_category(k: String, on: bool) -> void:
	if on: off_cats.erase(k)
	else: off_cats[k] = true
	map_rect.queue_redraw()

func _wb() -> WorldBuilder:
	return zone.builder as WorldBuilder

func refresh() -> void:
	var wb := _wb()
	var p: Vector3 = zone.player.global_position
	var b := WorldData.biome_at(p.x, p.z)
	var lv: Array = WorldData.BIOMES[b].lv
	info.text = "Вы здесь: %s (ур. %d–%d)\nКолесо/щипок/«+ −» — масштаб, перетаскивание — сдвиг, касание значка — подсказка." % [WorldData.BIOMES[b].name, lv[0], lv[1]]
	UIK.clear(list)
	if wb == null: return   # v0.9.3: вне открытого мира (город/подземелье) — без точек телепорта
	for did in RaidDefs.ORDER:
		var lk := DB.dungeon_lock(data, did)
		var r2: Array = DB.DUNGEON_LV[did]
		var db := UIK.button(list, "Портал: %s  ·  ур. %d–%d" % [RaidDefs.DUNGEONS[did].name, r2[0], r2[1]], focus_dungeon.bind(did), UIK.PURPLE if lk == "" else Color(0.25, 0.22, 0.28), 22, "magic-portal")
		db.alignment = HORIZONTAL_ALIGNMENT_LEFT; db.name = "Portal_" + did
		UIK.min_h(db, 60)
	var open: Array = wb.world_state()["wp"]
	for wp in wb.waypoints:
		var known: bool = open.has(wp.id)
		var bi := WorldData.biome_at(wp.pos.x, wp.pos.z)
		var r: Array = WorldData.BIOMES[bi].lv
		var txt: String = ("%s  ·  %s %d–%d" % [wp.name, WorldData.BIOMES[bi].name, r[0], r[1]]) if known else "??? — не открыт"
		var bt := UIK.button(list, txt, travel.bind(wp.id), UIK.BLUE if known else Color(0.25, 0.25, 0.25), 22, "treasure-map")
		bt.disabled = not known
		bt.alignment = HORIZONTAL_ALIGNMENT_LEFT
		bt.name = "WP_" + str(wp.id)
		UIK.min_h(bt, 60)
	map_rect.queue_redraw()

# ---------------- преобразования ----------------
func _base() -> float: return minf(map_rect.size.x, map_rect.size.y) / (WorldData.HALF * 2)
func scale_px() -> float: return _base() * zoom
func to_map(p: Vector2) -> Vector2:
	return (p - center) * scale_px() + map_rect.size * 0.5
func to_world(m: Vector2) -> Vector2:
	return (m - map_rect.size * 0.5) / scale_px() + center

func _clamp_center() -> void:
	var half_view := map_rect.size * 0.5 / scale_px()
	var lim := Vector2.ONE * WorldData.HALF - half_view
	center.x = clampf(center.x, -maxf(lim.x, 0.0), maxf(lim.x, 0.0))
	center.y = clampf(center.y, -maxf(lim.y, 0.0), maxf(lim.y, 0.0))

## Масштаб вокруг точки экрана (колесо — под курсором, кнопки — центр)
func zoom_by(f: float, at = null) -> void:
	var pivot: Vector2 = at if at != null else map_rect.size * 0.5
	var wp := to_world(pivot)
	zoom = clampf(zoom * f, ZMIN, ZMAX)
	center = wp - (pivot - map_rect.size * 0.5) / scale_px()
	_clamp_center()
	tip.visible = false
	map_rect.queue_redraw()

func pan_px(d: Vector2) -> void:
	center -= d / scale_px()
	_clamp_center()
	map_rect.queue_redraw()

func center_on_player() -> void:
	var pp: Vector3 = zone.player.global_position
	center = Vector2(pp.x, pp.z)
	if zoom < 2.5: zoom = 3.0
	_clamp_center()
	map_rect.queue_redraw()

# ---------------- значки ----------------
## Все значки: {cat, pos (мир), name, text, sub, wp?, icon?}
func collect_markers() -> Array:
	var wb := _wb()
	var out := []
	if wb == null: return out
	var open: Array = wb.world_state()["wp"]
	var killed: Array = wb.world_state().get("bosses", [])
	for i in WorldData.TOWNS.size():
		var t: Dictionary = WorldData.TOWNS[i]
		var b: Dictionary = WorldData.BIOMES[t.biome]
		out.append({"cat": "town", "pos": t.pos, "name": t.name, "text": "%s · %s, ур. %d–%d\nТорговец, сундук-хранилище, путевой камень" % ["Город" if t.kind == "town" else "Лагерь", b.name, b.lv[0], b.lv[1]], "label": true})
	for wp in wb.waypoints:
		var known: bool = open.has(wp.id)
		var nt := false
		for t2 in WorldData.TOWNS: if (t2.pos as Vector2).distance_to(Vector2(wp.pos.x, wp.pos.z)) < 45.0: nt = true
		out.append({"cat": "waypoint", "near_town": nt, "pos": Vector2(wp.pos.x, wp.pos.z), "name": wp.name if known else "Неизвестный камень",
			"text": "Путевой камень открыт — можно переместиться" if known else "Подойдите, чтобы открыть", "wp": wp.id if known else "", "known": known})
	for bs in wb.bosses:
		var dead := killed.has("boss_" + WorldData.BIOMES[bs.biome].id)
		var blv: int = int(WorldData.BIOMES[bs.biome].lv[1]) + 1
		var kind := String(WorldData.BIOMES[bs.biome].get("boss_kind", "troll"))
		out.append({"cat": "boss", "pos": Vector2(bs.pos.x, bs.pos.z), "name": bs.name, "dead": dead,
			"text": "%s\nБосс зоны · ур. %d · рек. %d+\n%s" % [bs.poi, blv, Combat.boss_rec(kind, blv), "Повержен" if dead else Combat.resist_text(kind, "boss", true)], "sub": "рек. %d+" % Combat.boss_rec(kind, blv)})
	for p in WorldData.POIS:
		if p.has("boss"): continue
		var cat := "dungeon" if p.kind == "crypt" else "poi"
		out.append({"cat": cat, "pos": p.pos, "name": p.name, "text": ("Вход в склеп (подземелье)" if cat == "dungeon" else "Достопримечательность") + " · " + WorldData.BIOMES[WorldData.biome_at(p.pos.x, p.pos.y)].name, "label": true})
	if wb.portal_point != Vector3.ZERO:
		out.append({"cat": "portal", "pos": Vector2(wb.portal_point.x, wb.portal_point.z), "name": "Портал в Пепельную долину", "text": "Долина: Древний тролль, вход в Склеп Эфира"})
		out.append({"cat": "dungeon", "pos": Vector2(wb.portal_point.x, wb.portal_point.z) + Vector2(14, 0), "name": "Склеп Эфира (через долину)", "text": "Подземелье с Хранителем — вход в Пепельной долине"})
	for m in WorldData.minor_pois():
		var res := RESOURCE_KINDS.has(m.kind)
		out.append({"cat": "resource" if res else "minor", "pos": m.pos, "name": m.name, "kind": m.kind,
			"text": "%s · %s" % [m.name, WorldData.BIOMES[m.biome].name] + ("\nМожно добыть припасы" if res else "")})
	for s in wb.spawners:
		if s.rank == "rare":
			var d: Dictionary = DB.ENEMIES.get(s.kind, {})
			out.append({"cat": "rare", "pos": Vector2(s.global_position.x, s.global_position.z), "name": s.rare_name,
				"text": "Редкий враг: %s (%s)\nур. %d · %s" % [s.rare_name, d.get("name", s.kind), s.max_level, Combat.resist_text(s.kind, "rare")]})
	for e in zone.enemies:   # элиты, встреченные рядом (случайные)
		if is_instance_valid(e) and e.alive and e.rank == "elite":
			out.append({"cat": "rare", "pos": Vector2(e.global_position.x, e.global_position.z), "name": e.display_name,
				"text": "Элита: %s\n%s" % [e.display_name, e.affix_text()]})
	for mp in wb.merchant_points:
		out.append({"cat": "merchant", "pos": Vector2(mp.x, mp.z), "name": "Торговец", "text": "Покупка и продажа снаряжения, зелья"})
		out.append({"cat": "stash", "pos": Vector2(mp.x, mp.z) + Vector2(12.5, -0.5), "name": "Сундук-хранилище", "text": "Общий склад всех героев"})
	for did in RaidDefs.ORDER:   # v0.9.3: порталы групповых подземелий
		var d: Dictionary = RaidDefs.DUNGEONS[did]
		var lk := DB.dungeon_lock(data, did)
		out.append({"cat": "dungeon", "did": did, "pos": RaidDefs.portal_pos(did), "name": "Портал: " + String(d.name), "label": true,
			"text": "%s\n%s\nДобыча: «%s»" % [String(d.desc), DB.dungeon_info(data, did) if lk == "" else lk, Items.SETS[d.set].name]})
	var q := _quest_marker()
	if not q.is_empty(): out.append(q)
	return out

## Цель: босс зоны по уровню героя (ещё не побеждённый)
func _quest_marker() -> Dictionary:
	var wb := _wb()
	if wb == null: return {}
	var lvl := int(data.get("level", 1))
	var killed: Array = wb.world_state().get("bosses", [])
	for bs in wb.bosses:
		var b: Dictionary = WorldData.BIOMES[bs.biome]
		if killed.has("boss_" + b.id): continue
		if lvl <= int(b.lv[1]) + 2:
			return {"cat": "quest", "pos": Vector2(bs.pos.x, bs.pos.z) + Vector2(0, -26), "name": "Цель: " + bs.name, "text": "Рекомендуемая цель для вашего уровня: победить босса зоны «%s»" % b.name}
	return {}

func _draw_symbol(ci: CanvasItem, cat: String, at: Vector2, mk) -> void:
	var col: Color = CATS[cat][2]
	match cat:
		"player":
			ci.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -12), at + Vector2(9, 9), at + Vector2(0, 4), at + Vector2(-9, 9)]), col)
		"waypoint":
			var known: bool = mk is Dictionary and mk.get("known", true) or not (mk is Dictionary)
			ci.draw_circle(at, 11.0, Color(0.1, 0.1, 0.12, 0.85))
			ci.draw_circle(at, 8.0, col if known else Color(0.4, 0.4, 0.4))
		"building":
			ci.draw_rect(Rect2(at - Vector2(9, 7), Vector2(18, 14)), col.darkened(0.3))
			ci.draw_rect(Rect2(at - Vector2(9, 7), Vector2(18, 14)), Color(0.2, 0.15, 0.1), false, 2.0)
		_:
			var key: String = cat
			if cat in ["minor", "resource"] and mk is Dictionary and mk.has("kind"): key = "m_" + String(mk.kind)
			var tex: Texture2D = _icons.get(key, _icons.get(cat))
			var sz := 28.0 if cat in ["boss", "town", "quest"] else 24.0
			ci.draw_circle(at, sz * 0.62, Color(0.05, 0.04, 0.03, 0.8))
			if tex: ci.draw_texture_rect(tex, Rect2(at - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false, Color(0.6, 0.6, 0.6) if (mk is Dictionary and mk.get("dead", false)) else col)

func _text(pos: Vector2, s: String, fs: int, col: Color, center_x := true) -> void:
	var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := pos - Vector2(w / 2 if center_x else 0.0, 0)
	map_rect.draw_string_outline(_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.85))
	map_rect.draw_string(_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

func _draw_map() -> void:
	_clamp_center()
	var sp := scale_px()
	var wb := _wb()
	var tl := to_map(-Vector2.ONE * WorldData.HALF)
	map_rect.draw_rect(Rect2(Vector2.ZERO, map_rect.size), Color(0.08, 0.07, 0.06))
	map_rect.draw_texture_rect(_tex, Rect2(tl, Vector2.ONE * WorldData.HALF * 2 * sp), false)
	map_rect.draw_rect(Rect2(tl, Vector2.ONE * WorldData.HALF * 2 * sp), Color(0.6, 0.48, 0.3), false, 3.0)
	var view := Rect2(Vector2.ZERO, map_rect.size).grow(40)
	# постройки городов и точек (контуры) — при приближении
	if wb != null and zoom >= CATS.building[3] and not off_cats.has("building"):
		for f in wb.map_features:
			var c := to_map(f.pos)
			if not view.has_point(c): continue
			var sz: Vector2 = f.size * sp
			if sz.x < 3.0 and sz.y < 3.0: continue
			var key: String = f.key
			var col := Color(0.82, 0.74, 0.6, 0.9)
			if key.contains("wall") or key.contains("tower"): col = Color(0.62, 0.6, 0.58, 0.95)
			elif key.contains("tent") or key.contains("stall"): col = Color(0.85, 0.55, 0.4, 0.9)
			elif key.contains("fence") or key.contains("hedge"): col = Color(0.5, 0.4, 0.28, 0.9)
			var xf := Transform2D(-f.yaw, c)
			map_rect.draw_set_transform_matrix(xf)
			map_rect.draw_rect(Rect2(-sz * 0.5, sz), col)
			map_rect.draw_rect(Rect2(-sz * 0.5, sz), Color(0.15, 0.1, 0.07), false, 1.5)
			map_rect.draw_set_transform_matrix(Transform2D.IDENTITY)
	# названия зон с уровнями
	for i in WorldData.BIOMES.size():
		var b: Dictionary = WorldData.BIOMES[i]
		var c := to_map(b.seed)
		var fs := clampi(int(24 + zoom * 2), 24, 36)
		_text(c + Vector2(0, -40), b.name, fs, Color(1, 0.92, 0.75))
		_text(c + Vector2(0, -40 + fs + 2), "ур. %d–%d" % [b.lv[0], b.lv[1]], fs - 4, Color(0.85, 0.85, 0.85))
	# значки
	markers.clear()
	var all := collect_markers()
	for mk in all:
		var cat: String = mk.cat
		if off_cats.has(cat) or zoom < float(CATS[cat][3]): continue
		var m := to_map(mk.pos)
		if not view.has_point(m): continue
		_draw_symbol(map_rect, cat, m, mk)
		mk["screen"] = m
		markers.append(mk)
		var show_name: bool = mk.get("label", false) or (cat == "waypoint" and (mk.get("known", false) or zoom >= 2.0)) or zoom >= 3.2
		if cat == "waypoint" and mk.get("near_town", false): show_name = false   # камень в городе — подпись города уже есть
		if cat == "boss" and mk.has("sub"):
			_text(m + Vector2(0, 32), mk.sub, 16, Color(0.6, 0.6, 0.6) if mk.get("dead", false) else Color(1, 0.6, 0.5))
			if zoom >= 2.0: _text(m + Vector2(0, 52), mk.name, 18, Color(1, 0.8, 0.75))
		elif show_name and cat != "player":
			_text(m + Vector2(0, 32), mk.name, 18 if cat != "town" else 22, Color.WHITE if cat != "minor" else Color(0.92, 0.88, 0.8))
	# герой
	if not off_cats.has("player"):
		var pp: Vector3 = zone.player.global_position
		var pm := to_map(Vector2(pp.x, pp.z))
		var f: Vector3 = zone.player.forward()
		var dir := Vector2(f.x, f.z).normalized()
		if dir == Vector2.ZERO: dir = Vector2.UP
		var side := Vector2(-dir.y, dir.x)
		map_rect.draw_colored_polygon(PackedVector2Array([pm + dir * 16, pm - dir * 10 + side * 10, pm - dir * 5, pm - dir * 10 - side * 10]), CATS.player[2])
		map_rect.draw_arc(pm, 20, 0, TAU, 24, Color(1, 0.95, 0.5, 0.6), 2.0)
		markers.append({"cat": "player", "pos": Vector2(pp.x, pp.z), "screen": pm, "name": "Вы", "text": "%s, ур. %d" % [data.get("name", ""), int(data.get("level", 1))]})
	# масштабная линейка
	var meters := 100.0 if zoom >= 2.5 else (250.0 if zoom >= 1.4 else 500.0)
	var bar := meters * sp
	var bp := Vector2(24, map_rect.size.y - 28)
	map_rect.draw_line(bp, bp + Vector2(bar, 0), Color.WHITE, 3.0)
	map_rect.draw_line(bp, bp + Vector2(0, -8), Color.WHITE, 3.0); map_rect.draw_line(bp + Vector2(bar, 0), bp + Vector2(bar, -8), Color.WHITE, 3.0)
	_text(bp + Vector2(bar + 12, 6), "%d м · ×%.1f" % [int(meters), zoom], 18, Color.WHITE, false)

# ---------------- ввод ----------------
func _on_map_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP: zoom_by(1.2, mb.position); return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN: zoom_by(1.0 / 1.2, mb.position); return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag = true; _drag_moved = 0.0
			else:
				_drag = false
				if _drag_moved < 10.0 and _touches.size() <= 1: tap(mb.position)
	elif ev is InputEventMouseMotion and _drag and _touches.size() <= 1:
		var mm := ev as InputEventMouseMotion
		_drag_moved += mm.relative.length()
		pan_px(mm.relative)
	elif ev is InputEventMagnifyGesture:
		zoom_by((ev as InputEventMagnifyGesture).factor, (ev as InputEventMagnifyGesture).position)
	elif ev is InputEventPanGesture:
		pan_px(-(ev as InputEventPanGesture).delta * 8.0)
	elif ev is InputEventScreenTouch:
		var st := ev as InputEventScreenTouch
		if st.pressed: _touches[st.index] = st.position
		else: _touches.erase(st.index)
		_pinch_d = _pinch_dist()
	elif ev is InputEventScreenDrag:
		var sd := ev as InputEventScreenDrag
		_touches[sd.index] = sd.position
		if _touches.size() >= 2:
			var d := _pinch_dist()
			if _pinch_d > 10.0 and d > 10.0: zoom_by(d / _pinch_d, _pinch_mid())
			_pinch_d = d
			_drag_moved = 99.0

func _pinch_dist() -> float:
	if _touches.size() < 2: return 0.0
	var v: Array = _touches.values()
	return (v[0] as Vector2).distance_to(v[1])

func _pinch_mid() -> Vector2:
	var v: Array = _touches.values()
	return ((v[0] as Vector2) + (v[1] as Vector2)) * 0.5

## Касание: ближайший значок в 26 px → подсказка (для открытого камня — кнопка перемещения)
func tap(pos: Vector2) -> bool:
	var best = null; var bd := 26.0
	for mk in markers:
		var d: float = (mk.screen as Vector2).distance_to(pos)
		if mk.get("wp", "") != "": d -= 10.0   # камни перемещения важнее соседних построек
		if d < bd: bd = d; best = mk
	if best == null:
		tip.visible = false
		return false
	show_tip(best)
	return true

func show_tip(mk: Dictionary) -> void:
	_tip_target = mk
	tip_label.text = "[b][color=#%s]%s[/color][/b]\n%s" % [(CATS[mk.cat][2] as Color).to_html(false), mk.name, mk.get("text", "")]
	tip_btn.visible = mk.get("wp", "") != "" or mk.has("did")
	tip_btn.disabled = false
	if mk.has("did"):
		var lk := DB.dungeon_lock(data, mk.did)
		var can := not Net.in_game or not Net.in_party() or Net.is_leader()
		tip_btn.text = ("Проверка готовности" if Net.in_game and Net.in_party() else "Войти в портал") if can else "Ведёт лидер"
		tip_btn.disabled = lk != "" or not can or (zone.has_method("is_raid") and zone.is_raid())
	else: tip_btn.text = "Переместиться"
	tip.visible = true
	tip.reset_size()
	var p: Vector2 = mk.get("screen", map_rect.size * 0.5) + Vector2(24, -20)
	tip.position = Vector2(clampf(p.x, 8, map_rect.size.x - tip.size.x - 8), clampf(p.y, 8, map_rect.size.y - tip.size.y - 8))

func _tip_action() -> void:
	if _tip_target.has("did"): enter_portal(str(_tip_target.did))
	elif _tip_target.get("wp", "") != "": travel(_tip_target.wp)

## v0.9.3: вход в подземелье через портал на карте (в группе — сначала проверка готовности)
func enter_portal(did: String) -> bool:
	var p: Player = zone.player
	for e in zone.enemies:
		if e.alive and e._aggro and U.flat_dist(e.global_position, p.global_position) < 25.0:
			Game.toast("Нельзя войти в портал во время боя", 2.0)
			return false
	var lk := DB.dungeon_lock(data, did)
	if lk != "": Game.toast(lk, 2.5); return false
	zone.hud.close_window()
	Net.raid_enter(did)
	return true

## Сдвинуть карту к порталу подземелья (кнопка «Подземелья»)
func focus_dungeon(did: String) -> void:
	center = RaidDefs.portal_pos(did); zoom = maxf(zoom, 2.0); _clamp_center(); map_rect.queue_redraw()
	for mk in collect_markers():
		if mk.get("did", "") == did:
			mk["screen"] = map_rect.size * 0.5
			show_tip(mk); return

## Быстрое перемещение (не во время боя)
func travel(id: String) -> bool:
	var p: Player = zone.player
	for e in zone.enemies:
		if e.alive and e._aggro and U.flat_dist(e.global_position, p.global_position) < 25.0:
			Game.toast("Нельзя переместиться во время боя", 2.0)
			return false
	var ok := _wb() != null and _wb().travel_to(id)
	if ok:
		zone.hud.close_window()
		Game.toast("Перемещение: %s" % _name_of(id), 2.0)
	return ok

func _name_of(id: String) -> String:
	for wp in _wb().waypoints: if wp.id == id: return wp.name
	return id

func _close() -> void:
	zone.hud.close_window()
