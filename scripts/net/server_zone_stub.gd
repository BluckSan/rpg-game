extends Node3D
## v0.9.2: «зона» для сервера — только чтобы построить уровень (стены, колонны, логова врагов) и снять
## с него навмеш и описания спавнеров. Ничего не рисует; после сборки удаляется.
var data := {}
var player = null
var fx_root: Node3D
var enemies: Array = []
var minions: Array = []
var interactables: Array = []
var hud = null
var merchant = null
var spawn_point := Vector3.ZERO
var merchant_point := Vector3.ZERO
var pillars: Array = []
var pillar_r := 1.4
var _h_discs: Array = []
var _h_boxes: Array = []
var _h_ramps: Array = []

func _init() -> void:
	fx_root = Node3D.new(); fx_root.name = "FX"; add_child(fx_root)

func add_height_disc(c: Vector3, r: float, h: float) -> void: _h_discs.append([c, r, h])
func add_height_box(c: Vector3, half: Vector3, h: float) -> void: _h_boxes.append([c, half, h])
func add_height_ramp(low: Vector3, high: Vector3, half_w: float) -> void: _h_ramps.append([low, high, half_w])
func ground_y(_p: Vector3) -> float: return 0.0
func fx(_k: String, _p: Vector3, _r: float, _c: Color, _d := 0.35) -> void: pass
func shake(_a: float) -> void: pass
func float_text(_p: Vector3, _t: String, _c: Color) -> void: pass
func damage_number(_p: Vector3, _a: float, _c: bool, _tp: bool, _e := "") -> void: pass
func save() -> void: pass
func spawn_stash(_p: Vector3) -> void: pass
func is_dungeon() -> bool: return false
func hit_stop(_d: float) -> void: pass
func apply_character_changes(_r: bool) -> void: pass
