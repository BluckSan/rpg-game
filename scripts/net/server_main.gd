extends Node
## Точка входа выделенного сервера: godot --headless --main-pack server.pck -- --server [--port=7777]
func _ready() -> void:
	var port := Net.GAME_PORT
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--port="): port = int(a.substr(7))
	Engine.max_fps = 30
	if Net.start_server(port) != OK: get_tree().quit(1)
