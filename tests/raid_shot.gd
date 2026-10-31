extends Node
## Снимки групповых подземелий (телефон/ПК): коридор, бой с метками механик, прилив, Сверхновая, рамки группы, окно подземелий.
## xvfb-run godot --path . --resolution 1600x900 res://tests/raid_shot.tscn ++ --no-window-settings --ignore-lock --preset=1 --touch --tag=phone_med --out=DIR
var is_runner := false
var out := "/workspace/rpg-shots/v080"
var tag := "pc_high"

func _ready() -> void:
	if not is_runner:
		var r = load("res://tests/raid_shot.gd").new(); r.is_runner = true
		get_tree().root.add_child.call_deferred(r); return
	var preset := 2
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="): only = a.substr(7)
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--tag="): tag = a.substr(6)
		if a.begins_with("--preset="): preset = int(a.substr(9))
	DirAccess.make_dir_recursive_absolute(out)
	Game.apply_preset(preset)
	get_tree().create_timer(600.0, true, false, true).timeout.connect(func(): get_tree().quit(2))
	for did in RaidDefs.ORDER:
		if did == "lich" or (only != "" and did != only): continue   # Некрополь — tests/lich_shot
		await _dungeon(did)
	print("RAID SHOTS DONE")
	get_tree().quit()

func w(s: float) -> void: await get_tree().create_timer(s).timeout

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/%s_%s.png" % [out, name, tag]
	get_viewport().get_texture().get_image().save_png(path)
	print("  shot ", path)

func _dungeon(did: String) -> void:
	for f in Game.list_characters(): if str(f.get("name", "")) == "Фотограф": Game.delete_character(f["id"])
	var c := DB.new_character("Фотограф", "warrior", {})
	c["level"] = 20
	c["tutorial"] = {"move": true, "attack": true, "jump": true, "talents": true, "shop": true, "boss": true}
	c["zone"] = RaidDefs.DUNGEONS[did].zone; c["has_pos"] = false
	DB.auto_build_skills(c)
	Game.play(c); await w(3.0)
	var d = get_tree().current_scene
	var p: Player = d.player
	p.god_mode = true
	var sim: RaidSim = d.raid.sim
	p.teleport(Vector3(0, 0.1, 9)); p.face_towards(Vector3(0, 0, 30))
	await w(2.0)
	await shot(did + "_corridor")
	for id in sim.enemies.keys():
		var e = sim.enemies[id]
		if e.alive and e.role == "trash": sim._kill(e)
	await w(1.0)
	p.teleport(RaidDefs.ARENA_C + Vector3(-3, 0.1, -9)); p.face_towards(RaidDefs.ARENA_C)
	await w(2.5)
	sim.mech.b = 0.0   # метеоры / капли / звездопад — метки на земле
	await w(2.0)
	await shot(did + "_boss")
	match did:
		"ash":
			sim.phase = 2; sim._ash_shield()
			await w(2.0); await shot(did + "_shield")
		"crypt":
			sim.phase = 2; sim.mech.d = 0.0
			await w(2.5); await shot(did + "_tide")
		"star":
			sim._star_nova()
			await w(2.5); await shot(did + "_nova")
	if did == "ash":
		PartyUI.preview = true
		Net.party = {"id": 1, "leader": 0, "members": [
			{"id": 0, "name": "Фотограф", "cls": "warrior", "lvl": 20, "hp": 1.0, "zone": "pd_ash"},
			{"id": 11, "name": "Мирослава", "cls": "mage", "lvl": 19, "hp": 0.62, "zone": "pd_ash"},
			{"id": 12, "name": "Ратибор", "cls": "archer", "lvl": 21, "hp": 0.35, "zone": "pd_ash"},
			{"id": 13, "name": "Злата", "cls": "mage", "lvl": 18, "hp": 0.0, "zone": "pd_ash"},
			{"id": 14, "name": "Всеслав", "cls": "warrior", "lvl": 20, "hp": 0.9, "zone": "pd_ash"}]}
		await w(1.0); await shot("party_frames")
		PartyUI.preview = false; Net.party = {}
	await w(0.5)
	Game.travel("starter")
	if did == "star":
		await w(3.0)
		var z = get_tree().current_scene
		z.party_ui.toggle()
		await w(1.0); await shot("dungeon_panel")
		z.party_ui.toggle()
	else:
		await w(2.0)
