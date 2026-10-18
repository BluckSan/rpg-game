extends RefCounted
class_name RaidBrain
## «Мозг» босса группового подземелья на клиенте: только отображение состояния, присланного RaidSim
## (фаза, каст, ярость, неуязвимость). Поля совпадают с BossBrain/WardenBrain — HUD показывает их так же.

var phase := 1
var PHASE_NAMES: Array = ["", "", "", ""]
var enraged := false
var engaged := false
var invulnerable := false
var busy := false
var cast_name := ""
var cast_total := 0.0
var cast_left := 0.0
var cast_hint := ""
var _enr_left := 0.0

func setup(_e) -> void: pass
func update(_dt: float) -> void: pass
func enrage_left() -> float: return _enr_left

func apply(st: Dictionary, names: Array) -> void:
	PHASE_NAMES = names
	phase = int(st.get("ph", 1)); enraged = bool(st.get("rg", false)); engaged = bool(st.get("en", false))
	invulnerable = bool(st.get("inv", false))
	cast_name = str(st.get("cn", "")); cast_total = float(st.get("ct", 0.0)); cast_left = float(st.get("cl", 0.0))
	cast_hint = str(st.get("h", "")); _enr_left = float(st.get("el", 0.0))

func step(dt: float) -> void:
	if cast_left > 0.0: cast_left = maxf(0.0, cast_left - dt)
	if engaged and _enr_left > 0.0: _enr_left = maxf(0.0, _enr_left - dt)
