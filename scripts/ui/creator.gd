extends Control
## Создание персонажа в стиле MMORPG: имя, класс, пол, рост, телосложение, кожа, лицо, причёска, цвета.

const MALE := ["Арвид", "Торин", "Ратибор", "Кайрон", "Эльдар", "Ярослав", "Гримм", "Святогор"]
const FEMALE := ["Лиара", "Мирослава", "Айрин", "Велена", "Сэлин", "Злата", "Иветта", "Рагна"]

var menu
var done: Callable
var look := {"gender": 0, "height": 1.0, "build": 1.0, "skin": 1, "face": 0, "hair": 0, "hair_color": 1, "eye_color": 0}
var char_name := ""
var class_id := "warrior"
var content: VBoxContainer
var class_desc: RichTextLabel
var name_edit: LineEdit
var refreshers: Array[Callable] = []
var dragging := false

func setup(m, on_done: Callable) -> void:
	menu = m
	done = on_done
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.target_x = 1.0
	var title := UIK.label(self, "Создание персонажа", 54, UIK.ACCENT)
	UIK.place(title, 0.03, 0.9, 0.6, 0.98)
	var p := UIK.panel(self)
	UIK.place(p, 0.02, 0.14, 0.45, 0.89)
	content = UIK.scroll_list(p, 12)
	# область вращения превью
	var drag := Control.new()
	drag.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(drag)
	UIK.place(drag, 0.47, 0.34, 1.0, 0.9)
	drag.gui_input.connect(_on_drag_input)
	var dp := UIK.panel(self, Color(0, 0, 0, 0.55))
	UIK.place(dp, 0.6, 0.14, 0.98, 0.33)
	class_desc = UIK.rich(dp, "", 26)
	UIK.full(class_desc); class_desc.offset_left = 18; class_desc.offset_top = 12; class_desc.offset_right = -18; class_desc.offset_bottom = -12
	UIK.place(UIK.button(self, "Назад", func(): done.call(null), UIK.BUTTON, 32), 0.02, 0.03, 0.14, 0.12)
	UIK.place(UIK.button(self, "Случайно", randomize_look, UIK.BUTTON, 32), 0.15, 0.03, 0.3, 0.12)
	UIK.place(UIK.button(self, "СОЗДАТЬ", _create, UIK.GOLD, 40), 0.74, 0.03, 0.98, 0.12)
	_build_options()
	randomize_look()

func _on_drag_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT):
		menu.rotate_preview(ev.relative.x)
	elif ev is InputEventScreenDrag:
		menu.rotate_preview(ev.relative.x)

func _section(t: String) -> void:
	UIK.min_h(UIK.label(content, t, 30, UIK.ACCENT), 46)

func _build_options() -> void:
	_section("Имя")
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Введите имя героя"
	name_edit.max_length = 16
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
		var b := UIK.button(row, cls.name, func(): class_id = cid; _refresh(), UIK.BUTTON, 32)
		UIK.expand(b)
		refreshers.append(func(): UIK.set_button_color(b, (cls.color * 0.8) if class_id == cid else UIK.BUTTON))

	_section("Пол")
	var g_row := UIK.hbox(content, 80)
	var genders := ["Мужской", "Женский"]
	for gi in 2:
		var b := UIK.button(g_row, genders[gi], func():
			look.gender = gi
			if gi == 1 and look.face == 2: look.face = 0
			_refresh(), UIK.BUTTON, 30)
		UIK.expand(b)
		refreshers.append(func(): UIK.set_button_color(b, Color(0.45, 0.35, 0.15) if look.gender == gi else UIK.BUTTON))

	_slider("Рост", "height", 0.85, 1.15)
	_slider("Телосложение", "build", 0.8, 1.25)
	_swatches("Цвет кожи", DB.SKIN_COLORS, "skin")
	_cycler("Лицо", DB.FACES, "face")
	_cycler("Причёска", DB.HAIR_STYLES, "hair")
	_swatches("Цвет волос", DB.HAIR_COLORS, "hair_color")
	_swatches("Цвет глаз", DB.EYE_COLORS, "eye_color")

func _slider(t: String, key: String, lo: float, hi: float) -> void:
	_section(t)
	var s := HSlider.new()
	s.min_value = lo; s.max_value = hi; s.step = 0.01
	s.value = look[key]
	UIK.min_h(s, 60)
	s.add_theme_stylebox_override("slider", UIK.box(Color(0.15, 0.15, 0.2), 6))
	s.add_theme_stylebox_override("grabber_area", UIK.box(UIK.ACCENT, 6))
	s.add_theme_stylebox_override("grabber_area_highlight", UIK.box(UIK.ACCENT, 6))
	s.value_changed.connect(func(v): look[key] = v; _rebuild())
	content.add_child(s)
	refreshers.append(func(): s.set_value_no_signal(look[key]))

func _swatches(t: String, colors: Array, key: String) -> void:
	_section(t)
	var row := UIK.hbox(content, 70, 8)
	for i in colors.size():
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		UIK.expand(b)
		b.pressed.connect(func(): look[key] = i; _refresh())
		row.add_child(b)
		refreshers.append(func():
			var sel: bool = look[key] == i
			var st := UIK.box(colors[i], 8, 5 if sel else 0, UIK.ACCENT)
			for k in ["normal", "hover", "pressed"]: b.add_theme_stylebox_override(k, st))

func _cycler(t: String, options: Array, key: String) -> void:
	_section(t)
	var row := UIK.hbox(content, 70)
	UIK.expand(UIK.button(row, "<", func(): look[key] = (look[key] - 1 + options.size()) % options.size(); _refresh(), UIK.BUTTON, 34))
	var mid := PanelContainer.new()
	mid.add_theme_stylebox_override("panel", UIK.box(Color(0.12, 0.13, 0.17)))
	UIK.expand(mid, 3)
	row.add_child(mid)
	var l := UIK.label(mid, "", 30, UIK.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	UIK.expand(UIK.button(row, ">", func(): look[key] = (look[key] + 1) % options.size(); _refresh(), UIK.BUTTON, 34))
	refreshers.append(func(): l.text = options[look[key]])

func _refresh() -> void:
	for r in refreshers: r.call()
	var cls: Dictionary = DB.CLASSES[class_id]
	class_desc.text = "[b]%s[/b]\n%s" % [cls.name, cls.desc]
	_rebuild()

func _rebuild() -> void:
	menu.show_preview(look, class_id, "")

func randomize_look() -> void:
	look.gender = randi() % 2
	look.height = randf_range(0.92, 1.08)
	look.build = randf_range(0.9, 1.12)
	look.skin = randi() % 6
	look.face = randi() % 2 if look.gender == 1 else randi() % 4
	look.hair = ([2, 3].pick_random()) if look.gender == 1 else randi() % 6
	look.hair_color = randi() % DB.HAIR_COLORS.size()
	look.eye_color = randi() % DB.EYE_COLORS.size()
	char_name = (FEMALE if look.gender == 1 else MALE).pick_random()
	name_edit.text = char_name
	_refresh()

func _create() -> void:
	var n := char_name.strip_edges()
	if n.length() < 2:
		Game.toast("Имя должно быть не короче 2 букв")
		return
	for other in Game.list_characters():
		if String(other["name"]).to_lower() == n.to_lower():
			Game.toast("Персонаж с таким именем уже есть")
			return
	var c := DB.new_character(n, class_id, look.duplicate())
	Game.toast("Персонаж %s создан!" % n)
	done.call(c)
