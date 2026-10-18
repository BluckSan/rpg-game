extends CanvasLayer
class_name NetOverlay
## Онлайн-панель поверх игры: кто в мире и чат (Enter / кнопка «Чат»; на телефоне — экранная клавиатура).

var roster: Label
var log_label: RichTextLabel
var input: LineEdit
var chat_btn: Button

func _ready() -> void:
	layer = 40
	var root := Control.new(); root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	roster = Label.new()
	roster.add_theme_font_size_override("font_size", 22)
	roster.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0))
	roster.add_theme_constant_override("outline_size", 6)
	roster.add_theme_color_override("font_outline_color", Color.BLACK)
	roster.anchor_top = 0.36; roster.anchor_bottom = 0.36; roster.offset_left = 24; roster.offset_top = 0
	root.add_child(roster)
	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true; log_label.scroll_following = true
	log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_label.add_theme_font_size_override("normal_font_size", 22)
	log_label.add_theme_constant_override("outline_size", 6)
	log_label.add_theme_color_override("font_outline_color", Color.BLACK)
	log_label.anchor_top = 0.5; log_label.anchor_bottom = 0.68; log_label.anchor_right = 0.34
	log_label.offset_left = 24
	root.add_child(log_label)
	input = LineEdit.new(); input.placeholder_text = "Сообщение… (Enter — отправить)"
	input.max_length = 160
	input.anchor_top = 0.69; input.anchor_bottom = 0.69; input.anchor_right = 0.34
	input.offset_left = 24; input.offset_bottom = 54
	input.add_theme_font_size_override("font_size", 24)
	input.visible = false
	input.text_submitted.connect(_submit)
	root.add_child(input)
	chat_btn = Button.new(); chat_btn.text = "Чат"; chat_btn.focus_mode = Control.FOCUS_NONE
	chat_btn.add_theme_font_size_override("font_size", 24)
	chat_btn.anchor_top = 0.3; chat_btn.anchor_bottom = 0.3; chat_btn.offset_left = 24; chat_btn.offset_right = 134; chat_btn.offset_bottom = 48
	chat_btn.pressed.connect(open_chat)
	root.add_child(chat_btn)
	Net.roster_changed.connect(_refresh)
	Net.party_changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	if not is_instance_valid(roster): return
	roster.visible = not Net.in_party()   # в группе вместо списка — рамки группы (PartyUI)
	var names := Net.online_names()
	roster.text = "Онлайн: %d/%d\n%s" % [names.size(), Net.MAX_PLAYERS, "\n".join(names.slice(0, 10))]
	var t := ""
	for e in Net.chat_log.slice(maxi(0, Net.chat_log.size() - 8)):
		if e[0] == "": t += "[color=#9aa4b8][i]%s[/i][/color]\n" % e[1]
		else: t += "[color=#f2c46d]%s:[/color] %s\n" % [e[0], e[1]]
	log_label.text = t

func open_chat() -> void:
	input.visible = true
	input.grab_focus()

func _submit(text: String) -> void:
	Net.send_chat(text)
	input.text = ""
	input.visible = false
	input.release_focus()

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ENTER and not input.visible:
		open_chat()
		get_viewport().set_input_as_handled()
