extends Node
## Снимки Некрополя Кел'Таара (v0.9.5): склеп, комната Хранителя, тронный зал, бой (фаза 1/2/3).
## xvfb-run godot --path . --resolution 1600x900 res://tests/lich_shot.tscn ++ --no-window-settings --ignore-lock --preset=2 --tag=pc_high --out=DIR
var is_runner := false
var out := "/workspace/rpg-shots/v095"
var tag := "pc_high"

func _ready() -> void:
	if not is_runner:
		var r = load("res://tests/lich_shot.gd").new(); r.is_runner = true
		get_tree().root.add_child.call_deferred(r); return
	var preset := 2
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--tag="): tag = a.substr(6)
		if a.begins_with("--preset="): preset = int(a.substr(9))
	DirAccess.make_dir_recursive_absolute(out)
	Game.apply_preset(preset)
	get_tree().create_timer(300.0, true, false, true).timeout.connect(func(): get_tree().quit(2))
	await _run()
	print("LICH SHOTS DONE")
	get_tree().quit()

func w(s: float) -> void: await get_tree().create_timer(s).timeout

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/%s_%s.png" % [out, name, tag]
	get_viewport().get_texture().get_image().save_png(path)
	print("  shot ", path)

func _run() -> void:
	for f in Game.list_characters(): if str(f.get("name", "")) == "Фотограф": Game.delete_character(f["id"])
	var c := DB.new_character("Фотограф", "mage", {})
	c["level"] = 26
	c["tutorial"] = {"move": true, "attack": true, "jump": true, "talents": true, "shop": true, "boss": true}
	c["zone"] = RaidDefs.DUNGEONS["lich"].zone; c["has_pos"] = false
	DB.auto_build_skills(c)
	Game.play(c); await w(3.0)
	var d = get_tree().current_scene
	var p: Player = d.player
	p.god_mode = true
	var sim = d.raid.sim
	p.teleport(Vector3(0, 0.1, 8)); p.face_towards(Vector3(0, 0, 30))
	await w(2.5); await shot("lich_crypt")
	for id in sim.enemies.keys():
		var e = sim.enemies[id]
		if e.alive and e.role == "trash": sim._kill(e)
	await w(1.0)
	p.teleport(Vector3(-6, 0.1, 56)); p.face_towards(Vector3(0, 0, 64))
	await w(2.5); await shot("lich_keeper_room")
	for id in sim.enemies.keys():
		var e = sim.enemies[id]
		if e.alive and e.role == "mini": sim._kill(e)
	await w(1.5)
	p.teleport(Vector3(0, 0.1, 176)); p.face_towards(RaidDefs.L_ARENA_C)
	await w(3.0); await shot("lich_throne_hall")
	p.teleport(RaidDefs.L_ARENA_C + Vector3(-4, 0.1, -10)); p.face_towards(RaidDefs.L_ARENA_C)
	await w(4.0); await shot("lich_boss_p1")
	var b = sim.enemies.get(sim.boss_id)
	b.hp = b.mhp * 0.69; sim._hp_custom(0.69)
	await w(3.0); await shot("lich_boss_p2_phylacteries")
	b.invuln = false; b.hp = b.mhp * 0.39; sim._hp_custom(0.39)
	await w(5.0); await shot("lich_boss_p3")
