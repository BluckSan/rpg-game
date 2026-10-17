extends SceneTree
## Размеры моделей монстров (AABB мешей в мировых координатах, scale 1) — для подбора масштаба в MobModel.DEFS
var nodes := {}
var frame := 0
func _initialize() -> void:
	for f in DirAccess.get_files_at("res://assets/mobs"):
		if not f.ends_with(".glb"): continue
		var n: Node3D = (load("res://assets/mobs/" + f) as PackedScene).instantiate()
		root.add_child(n); nodes[f] = n
func _process(_d: float) -> bool:
	frame += 1
	if frame < 3: return false
	for f in nodes:
		var n: Node3D = nodes[f]
		var ab := AABB(); var first := true
		for m in n.find_children("*", "MeshInstance3D", true, false):
			var mi := m as MeshInstance3D
			var a: AABB = mi.global_transform * mi.get_aabb()
			if first: ab = a; first = false
			else: ab = ab.merge(a)
		var sk := n.find_child("Skeleton3D", true, false) as Skeleton3D
		var lo := Vector3(INF, INF, INF); var hi := -lo
		if sk:
			for b in sk.get_bone_count():
				var p: Vector3 = sk.global_transform * sk.get_bone_global_pose(b).origin
				lo = lo.min(p); hi = hi.max(p)
		print("%s mesh h=%.2f w=%.2f d=%.2f y0=%.2f | bones h=%.2f y0=%.2f" % [f, ab.size.y, ab.size.x, ab.size.z, ab.position.y, hi.y - lo.y, lo.y])
	return true
