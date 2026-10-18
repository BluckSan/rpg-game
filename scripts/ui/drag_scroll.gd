extends Node
class_name DragScroll
## Прокрутка списка простым движением пальца/мыши по любому месту списка (не только по полосе).
## Короткое касание остаётся нажатием кнопки; если палец сдвинулся — это прокрутка, и кнопка не срабатывает.

static var dragging := false   # кнопки игнорируют отпускание во время прокрутки
var sc: ScrollContainer
var _down := false
var _start := Vector2.ZERO
var _moved := false
var _vel := 0.0
const THRESHOLD := 14.0

func _ready() -> void:
	sc = get_parent()
	process_mode = Node.PROCESS_MODE_ALWAYS

func _input(ev: InputEvent) -> void:
	if not sc.is_visible_in_tree(): return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			var hv := sc.get_viewport().gui_get_hovered_control()
			if hv is Slider: return   # ползунок тянут вбок — это не прокрутка
			if sc.get_global_rect().has_point(ev.position):
				_down = true; _moved = false; _start = ev.position; _vel = 0.0
		elif _down:
			_down = false
			if _moved:
				dragging = true
				_clear.call_deferred()
	elif ev is InputEventMouseMotion and _down:
		if sc.get_viewport().gui_is_dragging():   # перетаскивание умения в слот — не прокрутка
			_down = false; _vel = 0.0; return
		if not _moved and ev.position.distance_to(_start) > THRESHOLD: _moved = true
		if _moved:
			sc.scroll_vertical -= int(ev.relative.y)
			_vel = -ev.relative.y / maxf(get_process_delta_time(), 0.008)

func _clear() -> void:
	await get_tree().process_frame
	dragging = false

func _process(delta: float) -> void:
	if not _down and absf(_vel) > 30:
		sc.scroll_vertical += int(_vel * delta)
		_vel = lerpf(_vel, 0.0, minf(1.0, delta * 5.0))
	elif not _down:
		_vel = 0.0
