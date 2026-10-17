extends Control
## Создание персонажа в стиле современных MMORPG.
## Вкладки: Основа (имя, класс, пол, пресеты) · Тело · Лицо (18 ползунков-морфов) · Волосы и цвета.
## Превью обновляется на лету (CharVisual.apply_look), на вкладке «Лицо» камера приближается к лицу.

const MALE := ["Арвид", "Торин", "Ратибор", "Кайрон", "Эльдар", "Ярослав", "Гримм", "Святогор"]
const FEMALE := ["Лиара", "Мирослава", "Айрин", "Велена", "Сэлин", "Злата", "Иветта", "Рагна"]
const TABS := ["Основа", "Тело", "Лицо", "Волосы"]

var menu
var done: Callable
var look: Dictionary = CharAssets.default_look(0)
var char_name := ""
var class_id := "warrior"
var tab := 0
var content: VBoxContainer
var class_desc: RichTextLabel
var desc_panel: Control
var name_edit: LineEdit
var refreshers: Array[Callable] = []
var tab_buttons: Array[Button] = []
var _rng := RandomNumberGenerator.new()

func setup(m, on_done: Callable) -> void:
	menu = m
	done = on_done
	_rng.randomize()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.target_x = 0.9
	var title := UIK.label(self, "Создание персонажа", 54, UIK.ACCENT)
	UIK.place(title, 0.03, 0.91, 0.6, 0.99)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	add_child(tabs)
	UIK.place(tabs, 0.02, 0.83, 0.45, 0.905)
	for i in TABS.size():
		var b := UIK.button(tabs, TABS[i], set_tab.bind(i), UIK.BUTTON, 30)
		UIK.expand(b)
		tab_buttons.append(b)
	var p := UIK.panel(self)
	UIK.place(p, 0.02, 0.14, 0.45, 0.82)
	content = UIK.scroll_list(p, 12)
	# область вращения превью
	var drag := Control.new()
	drag.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(drag)
	UIK.place(drag, 0.47, 0.34, 1.0, 0.9)
	drag.gui_input.connect(_on_drag_input)
	var dp := UIK.panel(self, Color(0, 0, 0, 0.55))
	desc_panel = dp
	UIK.place(dp, 0.52, 0.85, 0.985, 0.99)
	class_desc = UIK.rich(dp, "", 23)
	UIK.full(class_desc); class_desc.offset_left = 18; class_desc.offset_top = 12; class_desc.offset_right = -18; class_desc.offset_bottom = -12
	UIK.place(UIK.button(self, "Назад", func(): menu.set_focus(false); done.call(null), UIK.BUTTON, 32), 0.02, 0.03, 0.14, 0.12)
	UIK.place(UIK.button(self, "Случайно", randomize_look, UIK.BUTTON, 32), 0.15, 0.03, 0.3, 0.12)
	UIK.place(UIK.button(self, "Сброс лица", reset_face, UIK.BUTTON, 28), 0.31, 0.03, 0.45, 0.12)
	UIK.place(UIK.button(self, "СОЗДАТЬ", _create, UIK.GOLD, 40), 0.74, 0.03, 0.98, 0.12)
	randomize_look()
	set_tab(0)

func _on_drag_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT):
		menu.rotate_preview(ev.relative.x)
	elif ev is InputEventScreenDrag:
		menu.rotate_preview(ev.relative.x)

func set_tab(i: int) -> void:
	tab = i
	refreshers.clear()
	UIK.clear(content)
	match i:
		0: _build_base()
		1: _build_body()
		2: _build_face()
		3: _build_hair()
	for k in tab_buttons.size():
		UIK.set_button_color(tab_buttons[k], Color(0.45, 0.35, 0.15) if k == i else UIK.BUTTON)
	menu.set_focus(i == 2 or i == 3)
	desc_panel.visible = i < 2
	_refresh(false)

func _section(t: String) -> void:
	UIK.min_h(UIK.label(content, t, 30, UIK.ACCENT), 46)

# ---------------- вкладки ----------------
func _build_base() -> void:
	_section("Имя")
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Введите имя героя"
	name_edit.max_length = 16
	name_edit.text = char_name
	name_edit.add_theme_font_size_override("font_size", 34)
	name_edit.add_theme_stylebox_override("normal", UIK.box(Color(0.12, 0.13, 0.17)))
	name_edit.add_theme_stylebox_override("focus", UIK.box(Color(0.14, 0.15, 0.2), 10, 2, UIK.ACCENT))
	name_edit.text_changed.connect(func(t): char_name = t)
	UIK.min_h(name_edit, 80)
	content.add_child(name_edit)

	_section("Класс")
	var row := UIK.hbox(content, 100)
	for cid in DB.CLASS_ORDER:
		var cls: Dictionary = DB.CLASSES[cid]
		var b := UIK.button(row, cls.name, func(): set_class(cid), UIK.BUTTON, 32)
		UIK.expand(b)
		refreshers.append(func(): UIK.set_button_color(b, (cls.color * 0.8) if class_id == cid else UIK.BUTTON))

	_section("Пол")
	var g_row := UIK.hbox(content, 80)
	var genders := ["Мужской", "Женский"]
	for gi in 2:
		var b := UIK.button(g_row, genders[gi], func(): set_gender(gi), UIK.BUTTON, 30)
		UIK.expand(b)
		refreshers.append(func(): UIK.set_button_color(b, Color(0.45, 0.35, 0.15) if int(look.gender) == gi else UIK.BUTTON))

	_section("Пресет лица")
	var grid := GridContainer.new(); grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8); grid.add_theme_constant_override("v_separation", 8)
	content.add_child(grid)
	for pi in CharAssets.PRESETS.size():
		var b := UIK.button(grid, CharAssets.PRESETS[pi][0], func(): apply_preset(pi), UIK.BUTTON, 26)
		UIK.min_h(b, 70); b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		refreshers.append(func(): UIK.set_button_color(b, Color(0.45, 0.35, 0.15) if int(look.preset) == pi else UIK.BUTTON))

func _build_body() -> void:
	_slider("Рост", "height", 0.88, 1.12)
	_slider("Телосложение", "build", 0.82, 1.3)
	_slider("Размер головы", "head", 0.9, 1.1)
	_swatches("Цвет кожи", CharAssets.SKIN, "skin")
	_name_label(func(): return "Тон: " + CharAssets.SKIN_NAMES[int(look.skin)])

func _build_face() -> void:
	var group := ""
	for md in CharAssets.MORPHS:
		if md[2] != group:
			group = md[2]
			_section(group)
		_morph_slider(md[1], md[0])

func _build_hair() -> void:
	_cycler("Причёска", CharAssets.HAIR_STYLES, "hair")
	_morph_slider("Объём причёски", "hair_volume")
	_swatches("Цвет волос", CharAssets.HAIR, "hair_color")
	_cycler("Брови", CharAssets.BROW_STYLES, "brows")
	_section("Борода")
	var row := UIK.hbox(content, 70)
	for bi in 2:
		var b := UIK.button(row, ["Нет", "Есть"][bi], func(): look.beard = bi; _refresh(), UIK.BUTTON, 28)
		UIK.expand(b)
		refreshers.append(func(): UIK.set_button_color(b, Color(0.45, 0.35, 0.15) if int(look.beard) == bi else UIK.BUTTON))
	_morph_slider("Длина бороды", "beard_length")
	_morph_slider("Густота бороды", "beard_volume")
	_swatches("Цвет глаз", CharAssets.EYES, "eye_color")

# ---------------- элементы ----------------
func _style_slider(s: HSlider) -> void:
	UIK.min_h(s, 56)
	s.add_theme_stylebox_override("slider", UIK.box(Color(0.15, 0.15, 0.2), 6))
	s.add_theme_stylebox_override("grabber_area", UIK.box(UIK.ACCENT, 6))
	s.add_theme_stylebox_override("grabber_area_highlight", UIK.box(UIK.ACCENT, 6))

func _slider(t: String, key: String, lo: float, hi: float) -> void:
	_section(t)
	var s := HSlider.new()
	s.min_value = lo; s.max_value = hi; s.step = 0.01
	s.value = look[key]
	_style_slider(s)
	s.value_changed.connect(func(v): look[key] = v; _apply())
	content.add_child(s)
	refreshers.append(func(): s.set_value_no_signal(look[key]))

func _morph_slider(t: String, key: String) -> void:
	var row := UIK.hbox(content, 60, 12)
	var l := UIK.label(row, t, 26)
	l.custom_minimum_size.x = 220
	var s := HSlider.new()
	s.min_value = -1; s.max_value = 1; s.step = 0.02
	s.value = float(look.morphs.get(key, 0.0))
	_style_slider(s)
	UIK.expand(s, 2.0)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(func(v): set_morph(key, v))
	s.set_meta("morph", key)
	row.add_child(s)
	refreshers.append(func(): s.set_value_no_signal(float(look.morphs.get(key, 0.0))))

func _name_label(f: Callable) -> void:
	var l := UIK.label(content, "", 26, Color(1, 1, 1, 0.7))
	refreshers.append(func(): l.text = f.call())

func _swatches(t: String, colors: Array, key: String) -> void:
	_section(t)
	var grid := GridContainer.new(); grid.columns = 7
	grid.add_theme_constant_override("h_separation", 8); grid.add_theme_constant_override("v_separation", 8)
	content.add_child(grid)
	for i in colors.size():
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 64)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): look[key] = i; _refresh())
		grid.add_child(b)
		refreshers.append(func():
			var sel: bool = int(look[key]) == i
			var st := UIK.box(colors[i], 8, 5 if sel else 0, UIK.ACCENT)
			for k in ["normal", "hover", "pressed"]: b.add_theme_stylebox_override(k, st))

func _cycler(t: String, options: Array, key: String) -> void:
	_section(t)
	var row := UIK.hbox(content, 70)
	UIK.expand(UIK.button(row, "<", func(): look[key] = (int(look[key]) - 1 + options.size()) % options.size(); _refresh(), UIK.BUTTON, 34))
	var mid := PanelContainer.new()
	mid.add_theme_stylebox_override("panel", UIK.box(Color(0.12, 0.13, 0.17)))
	UIK.expand(mid, 3)
	row.add_child(mid)
	var l := UIK.label(mid, "", 30, UIK.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	UIK.expand(UIK.button(row, ">", func(): look[key] = (int(look[key]) + 1) % options.size(); _refresh(), UIK.BUTTON, 34))
	refreshers.append(func(): l.text = options[int(look[key])][0])

# ---------------- логика ----------------
func set_class(cid: String) -> void:
	class_id = cid
	_refresh(true)

func set_gender(g: int) -> void:
	if int(look.gender) == g: return
	var keep: Dictionary = look.morphs.duplicate()
	var sk: int = look.skin
	look = CharAssets.random_look(g, _rng)
	look.morphs = keep; look.skin = sk
	if g == 1: look.beard = 0
	char_name = (FEMALE if g == 1 else MALE).pick_random()
	if name_edit and is_instance_valid(name_edit): name_edit.text = char_name
	_refresh(true)

func set_morph(key: String, v: float) -> void:
	look.morphs[key] = v
	menu.preview.set_morph(key, v)

func apply_preset(i: int) -> void:
	look.preset = i
	look.morphs = (CharAssets.PRESETS[i][1] as Dictionary).duplicate()
	_refresh()

func reset_face() -> void:
	var keep := {}
	for k in ["hair_volume", "beard_length", "beard_volume"]:
		if look.morphs.has(k): keep[k] = look.morphs[k]
	look.morphs = keep
	look.preset = 0
	_refresh()

func randomize_look() -> void:
	look = CharAssets.random_look(_rng.randi() % 2, _rng)
	char_name = (FEMALE if int(look.gender) == 1 else MALE).pick_random()
	if name_edit and is_instance_valid(name_edit): name_edit.text = char_name
	_refresh(true)

func _refresh(full := false) -> void:
	for r in refreshers: r.call()
	var cls: Dictionary = DB.CLASSES[class_id]
	class_desc.text = "[b]%s[/b]\n%s" % [cls.name, cls.desc]
	if full or menu.preview.class_id != class_id or menu.preview.model == null:
		menu.show_preview(look, class_id, "")
	else:
		_apply()

func _apply() -> void:
	menu.preview.apply_look(look)

func _create() -> void:
	var n := char_name.strip_edges()
	if n.length() < 2:
		Game.toast("Имя должно быть не короче 2 букв")
		return
	for other in Game.list_characters():
		if String(other["name"]).to_lower() == n.to_lower():
			Game.toast("Персонаж с таким именем уже есть")
			return
	var c := DB.new_character(n, class_id, look.duplicate(true))
	Game.toast("Персонаж %s создан!" % n)
	menu.set_focus(false)
	done.call(c)
