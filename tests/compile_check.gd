extends Node
func _ready() -> void:
	var bad := 0
	var stack := ["res://scripts", "res://tests", "res://tools"]
	while stack.size() > 0:
		var d: String = stack.pop_back()
		for sub in DirAccess.get_directories_at(d): stack.append(d + "/" + sub)
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".gd"):
				var s = load(d + "/" + f)
				if s == null or not (s as GDScript).can_instantiate(): bad += 1; printerr("BAD ", d, "/", f)
	print("COMPILE ", "OK" if bad == 0 else "FAIL %d" % bad)
	get_tree().quit(bad)
