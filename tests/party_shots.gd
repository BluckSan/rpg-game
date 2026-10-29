extends Node
## v0.9.4.1: снимки окна «Группа» (до/после). ++ --out=<dir> --pref=<before|after> [--touch]
var is_runner := false
var out := "/workspace/rpg-shots/v0941"
var pref := "after"
var fails := 0
func ck(ok: bool, t: String) -> void:
	print(("  OK  " if ok else "  FAIL ") + t)
	if not ok: fails += 1
func shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s_%s_%s.png" % [out, pref, ("pc" if Game.desktop else "phone"), n])
	print("shot ", n)
func w(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout
func _ready() -> void:
	if not is_runner:
		var r = load("res://tests/party_shots.gd").new(); r.is_runner = true
		get_tree().root.add_child.call_deferred(r); return
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(120.0, true, false, true).timeout.connect(func(): printerr("PARTY SHOTS TIMEOUT"); get_tree().quit(2))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--pref="): pref = a.substr(7)
	DirAccess.make_dir_recursive_absolute(out)
	for f in Game.list_characters(): Game.delete_character(f["id"])
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	var c := DB.new_character("Арина", "warrior", CharAssets.random_look(1, rng))
	c["level"] = 18
	Game.save_character(c)
	Game.play(c); await w(3.0)
	var z = get_tree().current_scene
	z.player.god_mode = true
	if z.hud.hint_panel: z.hud.hint_panel.visible = false
	var pui = z.party_ui
	# имитация онлайна (без сервера): сеть не подключена, отправки RPC не происходят
	Net.in_game = true; Net.my_id = 1
	PartyUI.preview = true
	Net.remotes = {7: {"name": "Борис", "level": 15, "zone": "x", "node": null, "pos": Vector3.ZERO, "hp": 1.0}, 9: {"name": "Вера", "level": 21, "zone": "x", "node": null, "pos": Vector3.ZERO, "hp": 1.0}}
	# 1) пусто: игрок один
	Net.party = {}
	pui.open_tab("party"); await w(0.8); await shot("01_party_empty"); pui.close(); await w(0.3)
	# 2) приглашение
	Net.party_invites = {42: "Дарья"}
	if pui.has_method("_on_invite"): pui._on_invite(42, "Дарья")
	pui.open_tab("party"); await w(0.8); await shot("02_party_invite"); pui.close(); await w(0.3)
	Net.party_invites = {}
	if pui.has_method("_hide_invite"): pui._hide_invite()
	# 3) группа из трёх, я лидер
	Net.party = {"id": 5, "leader": 1, "members": [
		{"id": 1, "name": "Арина", "cls": "warrior", "lvl": 18, "hp": 1.0, "mp": 0.8, "zone": "starter"},
		{"id": 7, "name": "Борис", "cls": "mage", "lvl": 15, "hp": 0.45, "mp": 0.3, "zone": "starter"},
		{"id": 11, "name": "Глеб", "cls": "archer", "lvl": 17, "hp": 0.9, "mp": 1.0, "zone": "pd_ash"}]}
	pui.open_tab("party"); await w(0.8); await shot("03_party_leader")
	if pui.has_method("self_check"): for r in pui.self_check(): ck(r[0], r[1])
	pui.close(); await w(0.5); await shot("04_frames")
	# 4) я участник
	Net.party.leader = 7
	pui.open_tab("party"); await w(0.8); await shot("05_party_member"); pui.close(); await w(0.3)
	print("=== PARTY SHOTS RESULT: %s (%d fails) ===" % ["PASS" if fails == 0 else "FAIL", fails])
	Net.in_game = false; Net.party = {}
	get_tree().quit(1 if fails > 0 else 0)
