extends Node3D
class_name Portal
## Переход в другую зону (глобальная карта — в следующих версиях).

var zone
var target_zone := "global"
var arrive := ""
var _cd := 0.0

func _process(delta: float) -> void:
	if _cd > 0:
		_cd -= delta
		return
	var p = zone.player
	if p == null or U.flat_dist(p.global_position, global_position) > 2.5: return
	_cd = 4.0
	var z: Dictionary = DB.ZONES.get(target_zone, {})
	if z.is_empty(): return
	if not z["available"]:
		Game.toast("Путь в «%s» откроется в следующих версиях (от %d ур.)" % [z["name"], z["min_level"]], 3.5)
		return
	var why := DB.zone_lock_reason(p.data, target_zone)
	if why != "":
		Game.toast(why, 3.0)
		return
	zone.save()
	Game.travel(target_zone, arrive)
