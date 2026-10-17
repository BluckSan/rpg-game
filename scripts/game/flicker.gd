extends Node3D
## Мерцание огня (свет или меш).
var _base_e := 1.0
var _base_s := Vector3.ONE
var _seed := 0.0

func _ready() -> void:
	_seed = randf() * 100
	_base_s = scale
	if is_class("OmniLight3D"): _base_e = get("light_energy")

func _process(_d: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	var n := 0.5 + 0.25 * sin(t * 13.0 + _seed) + 0.25 * sin(t * 7.3 + _seed * 2)
	if is_class("OmniLight3D"): set("light_energy", _base_e * (0.75 + n * 0.5))
	else: scale = _base_s * (0.85 + n * 0.3)
