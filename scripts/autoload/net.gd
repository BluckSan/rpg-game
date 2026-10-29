extends Node
## Онлайн-режим (v0.7.0): до 10 игроков на авторитетном сервере Godot (ENet/UDP) + сервис аккаунтов (HTTPS).
## Один скрипт на клиенте и на сервере (RPC идут между узлами /root/Net).
## Клиент: вход/регистрация → герои на сервере (PostgreSQL) → подключение к миру → позиции/действия/чат.
## Сервер: проверяет токен через сервис аккаунтов, держит список игроков, принимает и проверяет движение
## (скорость, телепорты), рассылает снимки 10 раз в секунду, сохраняет героев (с проверкой скачков уровня/золота).
## Офлайн-игра этот узел не трогает: пока не выполнен вход (active = false), всё работает как раньше.

signal auth_changed
signal chars_changed
signal net_error(msg: String)
signal joined
signal chat_received(from: String, text: String)
signal roster_changed
signal party_changed

const PROTOCOL := 8   # v0.9.3: опыт считает сервер (s_wm_kill с xp); v0.9.2 — 7
const DEFAULT_HOST := "146.0.76.20"
const AUTH_PORT := 7780
const GAME_PORT := 7777
const MAX_PLAYERS := 10
const TLS_NAME := "oskolki-auth"
const SNAP_HZ := 10.0
const SEND_HZ := 12.0
const MAX_SPEED := 16.0          # м/с по горизонтали (бег + ускорения + превращения)
const SAVE_FLUSH := 15.0         # сервер пишет героя в БД не чаще, чем раз в 15 с

var host := DEFAULT_HOST
var is_server := false
var active := false              # клиент: вход выполнен, герои берутся с сервера
var token := ""
var username := ""
var chars: Array = []
var in_game := false
var busy := false
var my_id := 0
var remotes := {}                # peer_id -> {name, look, class, asc, level, zone, pos, yaw, hp, node}
var chat_log: Array = []
var _join_char := {}
var _send_t := 0.0
var _peer: ENetMultiplayerPeer
var _cert: X509Certificate
var _overlay: Node
# ---------- v0.8.0: группа и подземелья (клиент) ----------
const PARTY_MAX := 5
var party := {}                  # {id, leader, members: [{id, name, cls, lvl, hp, zone}]} — от сервера
var party_invites := {}          # party_id -> имя пригласившего
var raid_iid := 0
var raid_did := ""
var raid_client: Node

# ---------- сервер ----------
var players := {}                # peer_id -> {...}
var internal_key := ""
var internal_url := "http://127.0.0.1:7781"
var _snap_t := 0.0
var _log_t := 0.0
var parties := {}                # party_id -> {id, leader, members: [peer], invites: {peer: t}}
var instances := {}              # iid -> {sim, did, zone, members: [peer], party, log_n}
var _next_party := 1
var _next_iid := 1
var _party_t := 0.0
var _raid_snap_t := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--net-host="): host = a.substr(11)
	is_server = server_mode()
	if not is_server:
		_load_cfg()
		if FileAccess.file_exists("res://net/auth_cert.pem"):
			_cert = X509Certificate.new()
			if _cert.load("res://net/auth_cert.pem") != OK: _cert = null

static func server_mode() -> bool:
	return OS.has_feature("dedicated_server") or "--server" in OS.get_cmdline_user_args()

# =====================================================================
#                              КЛИЕНТ
# =====================================================================
func _load_cfg() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://net.cfg") == OK:
		token = str(cfg.get_value("auth", "token", ""))
		username = str(cfg.get_value("auth", "username", ""))
		host = str(cfg.get_value("net", "host", host)) if not _host_from_cmdline() else host

func _host_from_cmdline() -> bool:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--net-host="): return true
	return false

func _save_cfg() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("auth", "token", token); cfg.set_value("auth", "username", username)
	cfg.set_value("net", "host", host)
	cfg.save("user://net.cfg")

func has_saved_login() -> bool: return token != ""

## HTTPS-запрос к сервису аккаунтов (сертификат сервера закреплён в игре)
func _api(method: int, path: String, body = null) -> Dictionary:
	var rq := HTTPRequest.new()
	rq.timeout = 15.0
	add_child(rq)
	if _cert: rq.set_tls_options(TLSOptions.client(_cert, TLS_NAME))
	var headers := PackedStringArray(["Content-Type: application/json"])
	if token != "": headers.append("Authorization: Bearer " + token)
	var url := "https://%s:%d%s" % [host, AUTH_PORT, path]
	var err := rq.request(url, headers, method, JSON.stringify(body) if body != null else "")
	if err != OK:
		rq.queue_free()
		return {"_code": 0, "error": "не удалось отправить запрос (%d)" % err}
	var res: Array = await rq.request_completed
	rq.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS:
		return {"_code": 0, "error": "нет связи с сервером (%s)" % _result_text(res[0])}
	var d = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if not (d is Dictionary): d = {"error": "неверный ответ сервера"}
	d["_code"] = res[1]
	return d

func _result_text(r: int) -> String:
	match r:
		HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CANT_RESOLVE: return "сервер недоступен"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR: return "ошибка TLS"
		HTTPRequest.RESULT_TIMEOUT: return "таймаут"
	return "код %d" % r

## Вход или регистрация. Возвращает "" при успехе или текст ошибки.
func login(user: String, password: String, register := false) -> String:
	busy = true
	var d := await _api(HTTPClient.METHOD_POST, "/api/register" if register else "/api/login", {"username": user, "password": password})
	busy = false
	if d["_code"] != 200: return str(d.get("error", "ошибка %d" % d["_code"]))
	token = str(d["token"]); username = str(d["username"])
	_save_cfg()
	var e := await refresh_chars()
	if e != "": return e
	active = true
	auth_changed.emit()
	return ""

## Вход по сохранённому токену
func resume() -> String:
	if token == "": return "нужно войти"
	var e := await refresh_chars()
	if e != "": return e
	active = true
	auth_changed.emit()
	return ""

func logout() -> void:
	if token != "": _api(HTTPClient.METHOD_POST, "/api/logout")
	leave()
	token = ""; active = false; chars = []
	_save_cfg()
	auth_changed.emit()

func go_offline() -> void:
	leave()
	active = false
	auth_changed.emit()

func refresh_chars() -> String:
	var d := await _api(HTTPClient.METHOD_GET, "/api/characters")
	if d["_code"] == 401:
		token = ""; _save_cfg()
		return str(d.get("error", "нужно войти заново"))
	if d["_code"] != 200: return str(d.get("error", "ошибка %d" % d["_code"]))
	chars = []
	for c in d.get("characters", []):
		if c is Dictionary: chars.append(Game.normalize(c))
	chars_changed.emit()
	return ""

func create_char(c: Dictionary) -> void:
	var send := c.duplicate(true)
	var d := await _api(HTTPClient.METHOD_POST, "/api/characters", {"data": send})
	if d["_code"] != 200:
		Game.toast("Герой не создан: " + str(d.get("error", "")), 3.0)
	await refresh_chars()

func delete_char(id: String) -> void:
	await _api(HTTPClient.METHOD_DELETE, "/api/characters/" + id)
	await refresh_chars()

# ---------- подключение к миру ----------
func join(c: Dictionary) -> void:
	if busy or in_game: return
	busy = true
	_join_char = c
	Game.toast("Подключение к серверу…", 6.0)
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(host, GAME_PORT)
	if err != OK:
		busy = false
		Game.toast("Не удалось подключиться (%d)" % err, 3.0)
		return
	multiplayer.multiplayer_peer = _peer
	if not multiplayer.connected_to_server.is_connected(_on_connected):
		multiplayer.connected_to_server.connect(_on_connected)
		multiplayer.connection_failed.connect(_on_conn_failed)
		multiplayer.server_disconnected.connect(_on_server_lost)
	get_tree().create_timer(12.0).timeout.connect(func():
		if busy and not in_game: _fail_join("сервер не отвечает"))

func _on_connected() -> void:
	my_id = multiplayer.get_unique_id()
	c_hello.rpc_id(1, token, str(_join_char.get("id", "")), PROTOCOL, ProjectSettings.get_setting("application/config/version"))

func _on_conn_failed() -> void: _fail_join("сервер недоступен")

func _fail_join(msg: String) -> void:
	busy = false
	_close_peer()
	Game.toast("Подключение не удалось: " + msg, 3.5)
	net_error.emit(msg)

func _on_server_lost() -> void:
	var was := in_game
	_close_peer()
	if was:
		in_game = false
		Game.toast("Связь с сервером потеряна", 3.5)
		Game.to_menu()

func _close_peer() -> void:
	if _peer: _peer.close()
	_peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	for id in remotes.keys(): _drop_remote(id)
	remotes.clear()
	party = {}; party_invites.clear(); raid_iid = 0; raid_did = ""; raid_client = null
	party_changed.emit()
	if _overlay and is_instance_valid(_overlay): _overlay.queue_free()
	_overlay = null

## Выход из мира (вход в аккаунт сохраняется)
func leave() -> void:
	if not in_game and _peer == null: return
	if in_game and not Game.current.is_empty(): _send_save(Game.current)
	in_game = false; busy = false
	# дать ENet отправить последнее сохранение
	if _peer: await get_tree().create_timer(0.25).timeout
	_close_peer()

func save_character(c: Dictionary) -> void:
	if in_game: _send_save(c)

func _send_save(c: Dictionary) -> void:
	if _peer == null or _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED: return
	c_save.rpc_id(1, JSON.stringify(c))

func notify_teleport() -> void:
	if in_game and _connected(): c_teleport.rpc_id(1)

func send_action(kind: String, anim := "", speed := 1.0) -> void:
	if in_game and _connected(): c_action.rpc_id(1, kind, anim, speed)

func send_chat(text: String) -> void:
	text = text.strip_edges().left(160)
	if text != "" and in_game and _connected(): c_chat.rpc_id(1, text)

func _connected() -> bool:
	return _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func _process(delta: float) -> void:
	if is_server:
		_server_tick(delta)
		return
	if not in_game: return
	var z = get_tree().current_scene
	if z == null or not ("player" in z) or z.player == null or not is_instance_valid(z.player): return
	_send_t -= delta
	if _send_t <= 0.0 and _connected():
		_send_t = 1.0 / SEND_HZ
		var p: Node3D = z.player
		var hp := 1.0; var mpf := 1.0
		if "hp" in p and "stats" in p and p.stats:
			hp = clampf(float(p.hp) / maxf(1.0, float(p.stats.max_hp)), 0.0, 1.0)
			mpf = clampf(float(p.mp) / maxf(1.0, float(p.stats.max_mp)), 0.0, 1.0)
		c_state.rpc_id(1, str(Game.current.get("zone", "")), p.global_position, p.rotation.y, hp, mpf)
	_wm_client_tick(delta)
	# удалённые игроки — сглаживание
	for id in remotes:
		var r: Dictionary = remotes[id]
		var same: bool = r.zone == zone_key()
		if same and (r.node == null or not is_instance_valid(r.node)):
			r.node = RemotePlayer.create(z, r)
			r.node.peer_id = id
		elif not same and r.node and is_instance_valid(r.node):
			r.node.queue_free(); r.node = null
		if r.node and is_instance_valid(r.node): r.node.step(delta, r.pos, r.yaw, r.hp)
	if _overlay == null or not is_instance_valid(_overlay):
		_overlay = NetOverlay.new(); z.add_child(_overlay)

## Ключ зоны для видимости других игроков: в подземельях — с номером экземпляра (разные группы не видят друг друга)
func zone_key() -> String:
	var z := str(Game.current.get("zone", ""))
	if z == "dungeon": return "dungeon#%d" % (int(party.id) if not party.is_empty() else 1000000 + my_id)   # v0.9.2: Склеп группы
	return z + ("#%d" % raid_iid if RaidDefs.is_raid_zone(z) and raid_iid > 0 else "")

func _drop_remote(id: int) -> void:
	if not remotes.has(id): return
	var n = remotes[id].node
	if n and is_instance_valid(n): n.queue_free()
	remotes.erase(id)

func online_names() -> Array:
	var out := [username + " (вы)"]
	for id in remotes: out.append(str(remotes[id].name))
	return out

# ---------- RPC: сервер → клиент ----------
@rpc("authority", "call_remote", "reliable")
func s_joined(char_json: String, roster: Array) -> void:
	var c = JSON.parse_string(char_json)
	if not (c is Dictionary): _fail_join("неверные данные героя"); return
	busy = false; in_game = true
	for e in roster: _add_remote(e)
	Game.current = Game.normalize(c)
	chat_log.clear()
	joined.emit()
	Game.play(Game.current)

@rpc("authority", "call_remote", "reliable")
func s_refused(msg: String) -> void:
	_fail_join(msg)

@rpc("authority", "call_remote", "reliable")
func s_player_joined(e: Dictionary) -> void:
	_add_remote(e)
	_chat_local("", "%s входит в мир" % e.get("name", "?"))

@rpc("authority", "call_remote", "reliable")
func s_player_left(id: int, pname: String) -> void:
	_drop_remote(id)
	roster_changed.emit()
	_chat_local("", "%s выходит" % pname)

@rpc("authority", "call_remote", "unreliable_ordered")
func s_snapshot(ids: PackedInt32Array, data: PackedFloat32Array, zones: PackedStringArray) -> void:
	# ids отдельно (id пира не помещается в float32 без потерь), data: [x, y, z, yaw, hp] * n
	var n := mini(ids.size(), data.size() / 5)
	for i in n:
		var id := ids[i]
		if not remotes.has(id): continue
		var r: Dictionary = remotes[id]
		r.pos = Vector3(data[i * 5], data[i * 5 + 1], data[i * 5 + 2])
		r.yaw = data[i * 5 + 3]; r.hp = data[i * 5 + 4]
		if i < zones.size(): r.zone = zones[i]

@rpc("authority", "call_remote", "reliable")
func s_action(id: int, kind: String, anim: String, speed: float) -> void:
	if remotes.has(id) and remotes[id].node and is_instance_valid(remotes[id].node):
		remotes[id].node.act(kind, anim, speed)

@rpc("authority", "call_remote", "reliable")
func s_chat(from: String, text: String) -> void:
	_chat_local(from, text)

@rpc("authority", "call_remote", "reliable")
func s_correct(pos: Vector3) -> void:
	var z = get_tree().current_scene
	if z and "player" in z and z.player: z.player.global_position = pos

func _chat_local(from: String, text: String) -> void:
	chat_log.append([from, text])
	if chat_log.size() > 40: chat_log.pop_front()
	chat_received.emit(from, text)
	roster_changed.emit()

func _add_remote(e: Dictionary) -> void:
	var id := int(e.get("id", 0))
	if id == 0 or id == my_id: return
	remotes[id] = {"name": str(e.get("name", "?")), "look": e.get("look", {}), "class": str(e.get("class", "warrior")),
		"asc": str(e.get("asc", "")), "level": int(e.get("level", 1)), "zone": str(e.get("zone", "")),
		"pos": e.get("pos", Vector3.ZERO), "yaw": float(e.get("yaw", 0.0)), "hp": 1.0, "node": null}
	roster_changed.emit()

# =====================================================================
#                              СЕРВЕР
# =====================================================================
func start_server(port := GAME_PORT) -> int:
	internal_key = OS.get_environment("RPG_INTERNAL_KEY")
	var iu := OS.get_environment("RPG_INTERNAL_URL")
	if iu != "": internal_url = iu
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		printerr("server: не удалось открыть порт %d (%d)" % [port, err])
		return err
	multiplayer.multiplayer_peer = _peer
	multiplayer.peer_connected.connect(_srv_connected)
	multiplayer.peer_disconnected.connect(_srv_disconnected)
	print("server: ENet UDP :%d, игроков до %d, протокол %d" % [port, MAX_PLAYERS, PROTOCOL])
	return OK

func _now() -> float: return Time.get_ticks_msec() / 1000.0

func _srv_connected(id: int) -> void:
	players[id] = {"authed": false, "t0": _now()}
	print("server: подключение %d (всего %d)" % [id, players.size()])

func _srv_disconnected(id: int) -> void:
	var p = players.get(id)
	if p != null and p.get("authed", false):
		var wzk := str(p.get("wm_zk", ""))
		if wsims.has(wzk): wsims[wzk].remove_player(id)   # v0.9.2: бой продолжается без него (угроза снята)
		_srv_raid_remove(id)
		_srv_party_remove(id, "вышел из игры")
	players.erase(id)
	if p == null: return
	if p.authed:
		pending_flush[p.char_id] = true
		await _srv_flush(p, true)
		pending_flush.erase(p.char_id)
		for oid in players:
			if players[oid].authed: s_player_left.rpc_id(oid, id, p.name)
	print("server: отключение %d (всего %d)" % [id, players.size()])

var pending_flush := {}

func _srv_http(method: int, path: String, body: Dictionary) -> Dictionary:
	var rq := HTTPRequest.new(); rq.timeout = 10.0
	add_child(rq)
	var err := rq.request(internal_url + path, PackedStringArray(["Content-Type: application/json", "X-Internal-Key: " + internal_key]), method, JSON.stringify(body))
	if err != OK: rq.queue_free(); return {"_code": 0}
	var res: Array = await rq.request_completed
	rq.queue_free()
	var d = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8()) if res[0] == HTTPRequest.RESULT_SUCCESS else null
	if not (d is Dictionary): d = {}
	d["_code"] = res[1] if res[0] == HTTPRequest.RESULT_SUCCESS else 0
	return d

func _info(id: int, p: Dictionary) -> Dictionary:
	return {"id": id, "name": p.name, "look": p.data.get("look", {}), "class": p.data.get("class", "warrior"),
		"asc": p.data.get("ascendancy", ""), "level": int(p.data.get("level", 1)), "zone": _srv_zone_key(p), "pos": p.pos, "yaw": p.yaw}

func _srv_zone_key(p: Dictionary) -> String:
	if str(p.zone) == "dungeon": return _wm_zk(p)
	return str(p.zone) + ("#%d" % int(p.get("iid", 0)) if RaidDefs.is_raid_zone(str(p.zone)) else "")

@rpc("any_peer", "call_remote", "reliable")
func c_hello(tok: String, char_id: String, proto: int, version: String) -> void:
	if not is_server: return
	var id := multiplayer.get_remote_sender_id()
	if not players.has(id) or players[id].authed: return
	if proto != PROTOCOL:
		s_refused.rpc_id(id, "версия игры устарела — обновите до %s" % ProjectSettings.get_setting("application/config/version"))
		_kick_later(id); return
	for oid in players:   # один и тот же герой дважды — нельзя
		if players[oid].authed and players[oid].char_id == char_id:
			s_refused.rpc_id(id, "этот герой уже в игре"); _kick_later(id); return
	if pending_flush.has(char_id):   # v0.9.2: прошлый выход ещё сохраняется — подождать
		for i in 100:
			await get_tree().create_timer(0.1).timeout
			if not pending_flush.has(char_id): break
		if not players.has(id): return
	var d := await _srv_http(HTTPClient.METHOD_POST, "/internal/session", {"token": tok, "char_id": char_id})
	if not players.has(id): return
	if d["_code"] != 200 or not (d.get("character") is Dictionary):
		s_refused.rpc_id(id, "вход не подтверждён — войдите заново"); _kick_later(id); return
	var c: Dictionary = d.character
	var need_mig := false   # v0.8.0: старые предметы (проценты) → плоские характеристики, сразу пишем в БД
	for lst in ["inventory", "equipped", "stash"]:
		for it in c.get(lst, []): if it is Dictionary and int(it.get("v", 0)) < Items.ITEM_V: need_mig = true
	if int(c.get("skills_v", 0)) < DB.SKILLS_V: need_mig = true   # v0.9.0: умения из набора — изучены (ранг 1)
	c = Game.normalize(c)
	DB.shop_ensure(c)   # v0.9.2: товары лавки — серверные
	var pos := Vector3.ZERO
	var cp = c.get("pos", [0, 0, 0])
	if cp is Array and cp.size() == 3: pos = Vector3(float(cp[0]), float(cp[1]), float(cp[2]))
	var p := {"authed": true, "acc": int(d.account_id), "user": str(d.username), "char_id": char_id, "name": str(c.get("name", "?")),
		"data": c, "zone": str(c.get("zone", "starter")), "pos": pos, "yaw": 0.0, "hp": 1.0, "t": _now(), "tp_until": _now() + 5.0,
		"tp_t": 0.0, "viol": 0, "budget": 24.0, "dirty": false, "save_t": _now(), "chat_t": 0.0, "chat_n": 0,
		"party": 0, "iid": 0, "inv_t": 0.0, "inv_n": 0, "peer": id}
	if RaidDefs.is_raid_zone(p.zone): p.zone = "starter"; c["zone"] = "starter"; c["has_pos"] = false
	if need_mig: p.dirty = true; print("server: герой «%s» перенесён на новый формат (предметы v0.8.0 / умения v0.9.0)" % p.name)
	players[id] = p
	var roster := []
	for oid in players:
		if oid != id and players[oid].authed: roster.append(_info(oid, players[oid]))
	s_joined.rpc_id(id, JSON.stringify(c), roster)
	for oid in players:
		if oid != id and players[oid].authed: s_player_joined.rpc_id(oid, _info(id, p))
	print("server: %s (%s) вошёл героем «%s», онлайн %d" % [p.user, id, p.name, roster.size() + 1])

func _kick_later(id: int) -> void:
	await get_tree().create_timer(0.5).timeout
	if _peer and players.has(id): _peer.disconnect_peer(id)

func _authed(id: int):
	var p = players.get(id)
	return p if p != null and p.authed else null

@rpc("any_peer", "call_remote", "unreliable_ordered")
func c_state(zone_id: String, pos: Vector3, yaw: float, hp: float, mpf: float) -> void:
	if not is_server: return
	var id := multiplayer.get_remote_sender_id()
	var p = _authed(id)
	if p == null: return
	if not DB.ZONES.has(zone_id) or not pos.is_finite() or absf(pos.x) > 5000 or absf(pos.z) > 5000 or pos.y < -200 or pos.y > 1000: return
	var now := _now()
	var dt := clampf(now - float(p.t), 0.02, 2.0)
	var d := Vector2(pos.x - p.pos.x, pos.z - p.pos.z).length()
	# «запас хода»: копится со скоростью MAX_SPEED до 24 м — рывки и прыжки проходят, постоянный спидхак — нет
	p.budget = minf(float(p.budget) + MAX_SPEED * dt, 24.0)
	var ok: bool = zone_id != p.zone or now < float(p.tp_until) or d <= float(p.budget) + 1.0
	if ok:
		if zone_id == p.zone and now >= float(p.tp_until): p.budget = maxf(0.0, float(p.budget) - d)
		p.zone = zone_id; p.pos = pos
		p.viol = maxi(0, int(p.viol) - 1)
	else:
		# слишком быстро — сервер не принимает точку и возвращает игрока
		p.viol = int(p.viol) + 1
		s_correct.rpc_id(id, p.pos)
		if int(p.viol) > 40:
			print("server: %s отключён — постоянные рывки сквозь проверку скорости" % p.name)
			_peer.disconnect_peer(id)
	p.yaw = yaw; p.hp = clampf(hp, 0.0, 1.0); p.mp = clampf(mpf, 0.0, 1.0) if is_finite(mpf) else 1.0; p.t = now

## Рывок/телепорт/возрождение: короткое окно, когда сервер принимает скачок позиции (не чаще раза в 0,4 с)
@rpc("any_peer", "call_remote", "reliable")
func c_teleport() -> void:
	if not is_server: return
	var p = _authed(multiplayer.get_remote_sender_id())
	if p == null: return
	var now := _now()
	if now - float(p.tp_t) < 0.4: return
	p.tp_t = now; p.tp_until = now + 0.6

@rpc("any_peer", "call_remote", "reliable")
func c_action(kind: String, anim: String, speed: float) -> void:
	if not is_server: return
	var id := multiplayer.get_remote_sender_id()
	var p = _authed(id)
	if p == null or kind.length() > 24 or anim.length() > 48: return
	for oid in players:
		if oid != id and players[oid].authed and _srv_zone_key(players[oid]) == _srv_zone_key(p):
			s_action.rpc_id(oid, id, kind, anim, clampf(speed, 0.1, 4.0))

@rpc("any_peer", "call_remote", "reliable")
func c_chat(text: String) -> void:
	if not is_server: return
	var p = _authed(multiplayer.get_remote_sender_id())
	if p == null: return
	var now := _now()
	if now - float(p.chat_t) > 10.0: p.chat_t = now; p.chat_n = 0
	p.chat_n = int(p.chat_n) + 1
	if int(p.chat_n) > 6: return   # не больше 6 сообщений за 10 с
	text = text.strip_edges().left(160).replace("[", "(").replace("]", ")")
	if text == "": return
	for oid in players:
		if players[oid].authed: s_chat.rpc_id(oid, p.name, text)

@rpc("any_peer", "call_remote", "reliable")
func c_save(json: String) -> void:
	if not is_server: return
	var p = _authed(multiplayer.get_remote_sender_id())
	if p == null or json.length() > 250000: return
	var c = JSON.parse_string(json)
	if not (c is Dictionary) or str(c.get("id", "")) != p.char_id: return
	if str(c.get("class", "")) != str(p.data.get("class", "")): return
	if int(c.get("level", 1)) > int(p.data.get("level", 1)) + 5: return
	c = Game.normalize(c)
	# v0.9.1: таланты сверх очков — не принимаются (остаются серверные); материалы и ремесло — только через сервер
	if DB.free_points(c) < 0:
		for k in ["talents", "ranks", "ascendancy"]: c[k] = p.data.get(k, c[k])
	# v0.9.2: вещи, золото, зелья, пыль, материалы, лавка — только серверные (клиентским не доверяем)
	var mismatch := not InvOps.same(c, p.data)
	for k in InvOps.KEYS:
		if p.data.has(k): c[k] = p.data[k]
	if p.data.has("_rev"): c["_rev"] = p.data["_rev"]
	var lvl_changed := int(c.get("level", 1)) != int(p.data.get("level", 1))
	p.data = c; p.dirty = true; p.erase("st_cache")
	if lvl_changed: DB.shop_ensure(c)
	if mismatch or lvl_changed:
		inv_stats.resync += 1
		s_inv.rpc_id(multiplayer.get_remote_sender_id(), "sync", InvOps.pub(c), {"err": ""})

func _srv_flush(p: Dictionary, force := false) -> void:
	if not force and (p.get("mkt_busy", false) or p.get("flushing", false)): return
	while p.get("mkt_busy", false) or p.get("flushing", false): await get_tree().create_timer(0.05).timeout
	if not p.dirty: return
	if not force and _now() - float(p.save_t) < SAVE_FLUSH: return
	p.dirty = false; p.save_t = _now()
	var c: Dictionary = p.data
	c["pos"] = [p.pos.x, p.pos.y, p.pos.z]
	c["_rev"] = int(c.get("_rev", 0)) + 1   # v0.9.2: номер версии — устаревшая запись не перезапишет сделку
	p["flushing"] = true
	var d := await _srv_http(HTTPClient.METHOD_PUT, "/internal/characters/" + p.char_id, {"account_id": p.acc, "data": c})
	p["flushing"] = false
	if d["_code"] != 200: print("server: сохранение «%s» отклонено: %s" % [p.name, d.get("error", d["_code"])])

func _server_tick(delta: float) -> void:
	if _peer == null: return
	var now := _now()
	# неподтверждённые подключения — не дольше 15 с
	for id in players.keys():
		if not players[id].authed and now - float(players[id].t0) > 15.0:
			_peer.disconnect_peer(id); players.erase(id)
	_snap_t -= delta
	if _snap_t <= 0.0:
		_snap_t = 1.0 / SNAP_HZ
		var data := PackedFloat32Array(); var zones := PackedStringArray()
		var ids := PackedInt32Array()
		for id in players:
			var p = players[id]
			if not p.authed: continue
			ids.append(id)
			data.append_array([p.pos.x, p.pos.y, p.pos.z, p.yaw, p.hp]); zones.append(_srv_zone_key(p))
		if ids.size() > 1:
			for id in ids: s_snapshot.rpc_id(id, ids, data, zones)
		for id in ids: _srv_flush(players[id])
	_srv_raids_tick(delta)
	_wm_server_tick(delta)
	_party_t -= delta
	if _party_t <= 0.0:
		_party_t = 0.5
		for pid in parties: _srv_party_send(pid)
		_srv_lock_check()
	_log_t -= delta
	if _log_t <= 0.0:
		_log_t = 300.0
		print("server: онлайн %d, групп %d, подземелий %d, память %.1f МБ" % [players.size(), parties.size(), instances.size(), OS.get_static_memory_usage() / 1048576.0])


# =====================================================================
# v0.8.0: группы (до 5) и групповые подземелья
# =====================================================================

# ---------- клиент: вызовы ----------
func party_invite(pname: String) -> void:
	if in_game and _connected(): c_party_invite.rpc_id(1, pname)
func party_accept(party_id: int) -> void:
	party_invites.erase(party_id)
	if in_game and _connected(): c_party_accept.rpc_id(1, party_id)
	party_changed.emit()
func party_decline(party_id: int) -> void:
	party_invites.erase(party_id); party_changed.emit()
func party_leave() -> void:
	if in_game and _connected(): c_party_leave.rpc_id(1)
func party_kick(pname: String) -> void:
	if in_game and _connected(): c_party_kick.rpc_id(1, pname)
func is_leader() -> bool: return not party.is_empty() and int(party.get("leader", 0)) == my_id
func in_party() -> bool: return not party.is_empty()

## Вход в подземелье: онлайн — через сервер (лидер ведёт всю группу), офлайн — сразу соло-забег
func raid_enter(did: String) -> void:
	if not RaidDefs.DUNGEONS.has(did): return
	var why := DB.dungeon_lock(Game.current, did)   # v0.9.2: онлайн то же проверит сервер
	if why != "": Game.toast(why, 3.0); return
	if in_game:
		if _connected(): c_raid_enter.rpc_id(1, did)
		return
	var z = get_tree().current_scene
	if z and z.has_method("save"): z.save()
	Game.travel(RaidDefs.DUNGEONS[did].zone)

func raid_ready(rc: Node) -> void:
	raid_client = rc
	if in_game and _connected(): c_raid_ready.rpc_id(1)
func raid_hit(eid: int, dmg: float, skill: bool) -> void:
	if in_game and _connected(): c_raid_hit.rpc_id(1, eid, dmg, skill)
func raid_leave() -> void:
	if in_game and _connected(): c_raid_leave.rpc_id(1)
	raid_iid = 0; raid_did = ""; raid_client = null

# ---------- RPC: сервер → клиент ----------
@rpc("authority", "call_remote", "reliable")
func s_party(st: Dictionary) -> void:
	party = st
	party_changed.emit()

@rpc("authority", "call_remote", "reliable")
func s_party_invite(from_name: String, party_id: int) -> void:
	party_invites[party_id] = from_name
	Game.toast("%s приглашает вас в группу (окно «Группа»)" % from_name, 4.0)
	_chat_local("", "%s приглашает вас в группу" % from_name)
	party_changed.emit()

@rpc("authority", "call_remote", "reliable")
func s_notice(text: String) -> void:
	Game.toast(text, 3.0)
	_chat_local("", text)

@rpc("authority", "call_remote", "reliable")
func s_raid_start(did: String, iid: int) -> void:
	if not RaidDefs.DUNGEONS.has(did): return
	raid_iid = iid; raid_did = did
	var z = get_tree().current_scene
	if z and z.has_method("save"): z.save()
	Game.travel(RaidDefs.DUNGEONS[did].zone)

@rpc("authority", "call_remote", "reliable")
func s_raid_ev(ev: Dictionary) -> void:
	if raid_client and is_instance_valid(raid_client): raid_client.handle(ev)

@rpc("authority", "call_remote", "unreliable_ordered")
func s_raid_snap(ids: PackedInt32Array, data: PackedFloat32Array) -> void:
	if raid_client and is_instance_valid(raid_client): raid_client.apply_snap(ids, data)

# ---------- сервер: группы ----------
func _srv_find(pname: String) -> int:
	var key := pname.strip_edges().to_lower()
	for oid in players:
		if players[oid].authed and str(players[oid].name).to_lower() == key: return oid
	return 0

func _srv_party_state(pid: int) -> Dictionary:
	var pt = parties.get(pid)
	if pt == null: return {}
	var mem := []
	for m in pt.members:
		var p = players.get(m)
		if p == null: continue
		mem.append({"id": m, "name": p.name, "cls": str(p.data.get("class", "warrior")), "lvl": int(p.data.get("level", 1)),
			"hp": float(p.hp), "mp": float(p.get("mp", 1.0)), "zone": str(p.zone), "iid": int(p.iid), "tg": p.get("target", ["", 0]),
			"bf": _srv_buff_pub(p)})
	return {"id": pid, "leader": pt.leader, "members": mem}

## Баффы игрока для рамок группы: [[id, иконка, цвет, осталось, длительность, бафф?]]
func _srv_buff_pub(p: Dictionary) -> Array:
	var out := []
	var now := _now()
	var bf: Dictionary = p.get("buffs", {})
	for k in bf.keys():
		var b: Dictionary = bf[k]
		if float(b.until) <= now: bf.erase(k); continue
		out.append([k, str(b.icon), (b.col as Color).to_html(false), float(b.until) - now, float(b.dur), bool(b.get("good", true)),
			str(b.get("n", k)), str(b.get("d", "")), int(b.get("st", 1)), str(b.get("src", ""))])
	return out

func _srv_party_send(pid: int) -> void:
	var st := _srv_party_state(pid)
	for m in parties[pid].members:
		if players.has(m): s_party.rpc_id(m, st)

@rpc("any_peer", "call_remote", "reliable")
func c_party_invite(pname: String) -> void:
	if not is_server: return
	var id := multiplayer.get_remote_sender_id()
	var p = _authed(id)
	if p == null: return
	var now := _now()
	# антиспам: не больше 6 приглашений за 3 с (лидер может пригласить всю группу разом)
	if now - float(p.inv_t) > 3.0:
		p.inv_t = now; p.inv_n = 0
	p.inv_n = int(p.inv_n) + 1
	if int(p.inv_n) > 6: return
	var tid := _srv_find(pname.left(40))
	if tid == 0 or tid == id: s_notice.rpc_id(id, "Игрок «%s» не в сети" % pname.left(40)); return
	if int(players[tid].party) != 0: s_notice.rpc_id(id, "%s уже в группе" % players[tid].name); return
	var pid := int(p.party)
	if pid == 0:
		pid = _next_party; _next_party += 1
		parties[pid] = {"id": pid, "leader": id, "members": [id], "invites": {}}
		p.party = pid
		_srv_party_send(pid)
	var pt: Dictionary = parties[pid]
	if pt.leader != id: s_notice.rpc_id(id, "Приглашать может только лидер группы"); return
	if pt.members.size() >= PARTY_MAX: s_notice.rpc_id(id, "В группе уже %d игроков" % PARTY_MAX); return
	pt.invites[tid] = now
	s_party_invite.rpc_id(tid, p.name, pid)
	s_notice.rpc_id(id, "Приглашение отправлено: %s" % players[tid].name)

@rpc("any_peer", "call_remote", "reliable")
func c_party_accept(party_id: int) -> void:
	if not is_server: return
	var id := multiplayer.get_remote_sender_id()
	var p = _authed(id)
	if p == null or int(p.party) != 0: return
	var pt = parties.get(party_id)
	if pt == null or not pt.invites.has(id) or _now() - float(pt.invites[id]) > 120.0:
		s_notice.rpc_id(id, "Приглашение устарело"); return
	if pt.members.size() >= PARTY_MAX: s_notice.rpc_id(id, "Группа уже полная"); return
	pt.invites.erase(id)
	pt.members.append(id); p.party = party_id
	for m in pt.members:
		if m != id: s_notice.rpc_id(m, "%s вступает в группу" % p.name)
	_srv_party_send(party_id)

@rpc("any_peer", "call_remote", "reliable")
func c_party_leave() -> void:
	if not is_server: return
	var id := multiplayer.get_remote_sender_id()
	if _authed(id) == null: return
	_srv_party_remove(id, "покидает группу")

@rpc("any_peer", "call_remote", "reliable")
func c_party_kick(pname: String) -> void:
	if not is_server: return
	var id := multiplayer.get_remote_sender_id()
	var p = _authed(id)
	if p == null or int(p.party) == 0: return
	var pt: Dictionary = parties[int(p.party)]
	if pt.leader != id: s_notice.rpc_id(id, "Исключать может только лидер"); return
	var tid := _srv_find(pname.left(40))
	if tid == 0 or tid == id or not pt.members.has(tid): return
	s_notice.rpc_id(tid, "Вас исключили из группы")
	_srv_party_remove(tid, "исключён(а) из группы")

func _srv_party_remove(id: int, why: String) -> void:
	var p = players.get(id)
	if p == null or int(p.get("party", 0)) == 0: return
	var pid := int(p.party)
	p.party = 0
	var pt = parties.get(pid)
	if _peer and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and players.has(id) and multiplayer.get_peers().has(id):
		s_party.rpc_id(id, {})
	if pt == null: return
	pt.members.erase(id)
	for m in pt.members:
		if players.has(m): s_notice.rpc_id(m, "%s %s" % [p.name, why])
	if pt.members.size() <= 1:
		for m in pt.members:
			if players.has(m):
				players[m].party = 0
				s_party.rpc_id(m, {})
				s_notice.rpc_id(m, "Группа распущена")
		parties.erase(pid)
		return
	if pt.leader == id:
		pt.leader = pt.members[0]
		s_notice.rpc_id(pt.leader, "Вы теперь лидер группы")
	_srv_party_send(pid)

# ---------- сервер: подземелья ----------
@rpc("any_peer", "call_remote", "reliable")
func c_raid_enter(did: String) -> void:
	if not is_server: return
	var id := multiplayer.get_remote_sender_id()
	var p = _authed(id)
	if p == null or not RaidDefs.DUNGEONS.has(did): return
	var members := [id]
	var pid := int(p.party)
	if pid != 0:
		var pt: Dictionary = parties[pid]
		if pt.leader != id: s_notice.rpc_id(id, "Подземелье открывает лидер группы"); return
		members = pt.members.duplicate()
		# группа уже внутри этого подземелья — догоняющие входят в тот же экземпляр
		for iid in instances:
			var inst: Dictionary = instances[iid]
			if inst.party == pid and inst.did == did and not inst.sim.done:
				for m in members:
					if players.has(m) and int(players[m].iid) != iid:
						_srv_raid_remove(m); players[m].iid = iid; s_raid_start.rpc_id(m, did, iid)
				return
	# v0.9.2: уровень и лимит прохождений — у каждого; не прошедшие проверку не входят
	var ok := []
	for m in members:
		if not players.has(m): continue
		var why := DB.dungeon_lock(players[m].data, did)
		if why == "": ok.append(m); continue
		s_notice.rpc_id(m, why)
		if m != id: s_notice.rpc_id(id, "%s: %s" % [players[m].name, why])
	if not ok.has(id): return
	members = ok
	var lvl := 1
	for m in members: lvl = maxi(lvl, int(players[m].data.get("level", 1)))
	lvl = DB.dungeon_level(did, lvl)
	var sim := RaidSim.new()
	sim.setup(did, lvl, members.size())
	var iid := _next_iid; _next_iid += 1
	instances[iid] = {"sim": sim, "did": did, "zone": RaidDefs.DUNGEONS[did].zone, "members": [], "party": pid, "log_n": 0, "t0": _now()}
	for m in members:
		if not players.has(m): continue
		_srv_raid_remove(m)
		players[m].iid = iid
		s_raid_start.rpc_id(m, did, iid)
	print("server: подземелье #%d «%s» — группа %d, ур. %d" % [iid, RaidDefs.DUNGEONS[did].name, members.size(), lvl])

@rpc("any_peer", "call_remote", "reliable")
func c_raid_ready() -> void:
	if not is_server: return
	var id := multiplayer.get_remote_sender_id()
	var p = _authed(id)
	if p == null: return
	var inst = instances.get(int(p.iid))
	if inst == null: return
	if not inst.members.has(id): inst.members.append(id)
	inst.had = true
	inst.sim.add_player(id, {"name": p.name, "cls": str(p.data.get("class", "warrior")), "lvl": int(p.data.get("level", 1))})
	p.tp_until = _now() + 3.0   # переход в зону: позиция прыгает ко входу

@rpc("any_peer", "call_remote", "reliable")
func c_raid_hit(eid: int, dmg: float, skill: bool) -> void:
	if not is_server: return
	var id := multiplayer.get_remote_sender_id()
	var p = _authed(id)
	if p == null: return
	var inst = instances.get(int(p.iid))
	if inst == null or str(p.zone) != inst.zone: return
	inst.sim.hit(id, eid, dmg, skill)

@rpc("any_peer", "call_remote", "reliable")
func c_raid_leave() -> void:
	if not is_server: return
	var id := multiplayer.get_remote_sender_id()
	if _authed(id) == null: return
	_srv_raid_remove(id)

func _srv_raid_remove(id: int) -> void:
	var p = players.get(id)
	if p == null: return
	var iid := int(p.get("iid", 0))
	p.iid = 0
	var inst = instances.get(iid)
	if inst == null: return
	inst.members.erase(id)
	inst.sim.remove_player(id)

func _srv_raids_tick(delta: float) -> void:
	_raid_snap_t -= delta
	var snap := _raid_snap_t <= 0.0
	if snap: _raid_snap_t = 1.0 / SNAP_HZ
	for iid in instances.keys():
		var inst: Dictionary = instances[iid]
		var sim: RaidSim = inst.sim
		# пустой экземпляр (никто не вошёл за 60 с или все вышли) — удаляем
		var any := false
		for pid in players:
			if int(players[pid].get("iid", 0)) == iid: any = true
		if not any and (inst.get("had", false) or _now() - float(inst.t0) > 60.0):
			print("server: подземелье #%d закрыто" % iid)
			instances.erase(iid); continue
		for m in inst.members:
			var p = players.get(m)
			if p and str(p.zone) == inst.zone: sim.update_player(m, p.pos, float(p.hp))
		sim.tick(delta)
		if sim.done and not inst.get("counted", false):   # v0.9.2: прохождение засчитано тем, кто внутри
			inst["counted"] = true
			for m in inst.members: _dng_count(m, str(inst.did))
		for e in sim.events:
			var to: int = e[0]
			if str(e[1].get("t", "")) == "drops":   # v0.9.1: добыча босса — общая, на землю (подбор — c_pick)
				var zk := "%s#%d" % [inst.zone, int(iid)]
				var out := []
				for dr in e[1].list:
					out.append(_srv_drop_new(zk, str(dr.t), int(dr.n), dr.it, Vector3(float(dr.x), 0.1, float(dr.z))))
				for m in inst.members:
					if players.has(m): s_drop_add.rpc_id(m, out)
			if to == 0:
				for m in inst.members:
					if players.has(m): s_raid_ev.rpc_id(m, e[1])
			elif inst.members.has(to): s_raid_ev.rpc_id(to, e[1])
		sim.events.clear()
		if snap and not inst.members.is_empty():
			var s := sim.snapshot()
			for m in inst.members:
				if players.has(m): s_raid_snap.rpc_id(m, s[0], s[1])
		while int(inst.log_n) < sim.mlog.size():
			var l = sim.mlog[int(inst.log_n)]
			inst.log_n = int(inst.log_n) + 1
			print("server: #%d %s [%.1f] %s" % [iid, inst.did, l[0], l[1]])


# =====================================================================
# v0.9.0: выбор цели (синхронизация) и поддержка (баффы, лечение, щиты, ослабления)
# =====================================================================
var _tg_sent := ["", 0]
func send_target(k: String, id: int) -> void:
	if not in_game or not _connected(): return
	if _tg_sent[0] == k and int(_tg_sent[1]) == id: return
	_tg_sent = [k, id]
	c_target.rpc_id(1, k, id)

@rpc("any_peer", "call_remote", "reliable")
func c_target(k: String, id: int) -> void:
	if not is_server: return
	var p = _authed(multiplayer.get_remote_sender_id())
	if p == null or not (k in ["", "p", "e"]): return
	p.target = [k, id]

## v0.9.1: захват цели на сервере — снимается, только если враг погиб или дальше LOCK_RANGE
## (атаки, умения и движение его не меняют). Сервер сам направляет по захвату поддержку и рейдовые ослабления.
func _srv_enemy_pos(p: Dictionary, eid: int) -> Vector3:
	if int(p.iid) != 0:
		var inst = instances.get(int(p.iid))
		if inst != null:
			var e = inst.sim.enemies.get(eid)
			if e != null and e.alive: return e.pos
			return Vector3.INF
	var m = _wm_by_nid(p, eid)
	if m != null and m.alive: return m.pos
	return Vector3.INF

func _srv_lock_check() -> void:
	for id in players:
		var p = players[id]
		if not p.authed: continue
		var tg: Array = p.get("target", ["", 0])
		if str(tg[0]) != "e": continue
		var ep := _srv_enemy_pos(p, int(tg[1]))
		if ep == Vector3.INF or (ep as Vector3).distance_to(p.pos) > TargetCtl.LOCK_RANGE + 4.0:
			p.target = ["", 0]
			s_target_drop.rpc_id(id, int(tg[1]))

@rpc("authority", "call_remote", "reliable")
func s_target_drop(eid: int) -> void:
	_tg_sent = ["", 0]
	var z = get_tree().current_scene
	if z == null or not ("target_ctl" in z) or z.target_ctl == null: return
	var t = z.target_ctl.target
	if t != null and is_instance_valid(t) and "net_id" in t and int(t.net_id) == eid: z.target_ctl.clear()

## Данные участника группы по peer id (для рамки цели: мана, баффы) — {} если не в группе
func party_member(id: int) -> Dictionary:
	for m in party.get("members", []):
		if int(m.id) == id: return m
	return {}

## Клиент: применить умение поддержки (ally — peer союзника или 0; eid — враг подземелья или 0)
func support_cast(sid: String, ally: int, eid: int, pos: Vector3) -> void:
	if in_game and _connected(): c_support.rpc_id(1, sid, ally, eid, pos)

## Сервер: характеристики героя по серверным данным (кэш 5 с) — величина поддержки не от клиента
func _srv_stats(p: Dictionary) -> Dictionary:
	if not p.has("st_cache") or _now() - float(p.get("st_t", 0.0)) > 5.0:
		p.st_cache = DB.compute_stats(p.data); p.st_t = _now()
	return p.st_cache

func _srv_same_group(a: int, b: int) -> bool:
	if not players.has(a) or not players.has(b): return false
	var pa = players[a]; var pb = players[b]
	return int(pa.party) != 0 and int(pa.party) == int(pb.party) and _srv_zone_key(pa) == _srv_zone_key(pb)

var support_stats := {"casts": 0, "rejected": 0, "sent": 0}   # для тестов и журнала

@rpc("any_peer", "call_remote", "reliable")
func c_support(sid: String, ally: int, eid: int, pos: Vector3) -> void:
	if not is_server: return
	var id := multiplayer.get_remote_sender_id()
	var p = _authed(id)
	if p == null or not pos.is_finite() or float(p.hp) <= 0.0: return
	var s = DB.find_skill(p.data, sid.left(40))
	if s == null or not Support.is_support(s) or DB.skill_lock(p.data, s) != "":
		support_stats.rejected += 1; return
	var now := _now()
	if not p.has("sup_cd"): p.sup_cd = {}
	var e := DB.skill_eff(p.data, s)
	var st := _srv_stats(p)
	if now < float(p.sup_cd.get(sid, 0.0)) - 0.6:   # перезарядка на сервере (допуск на задержку сети)
		support_stats.rejected += 1; return
	p.sup_cd[sid] = now + float(e.cd) * (1.0 - float(st.get("cdr", 0.0)))
	var eff: Dictionary = Support.resolve(e)
	var tgt := str(eff.tgt)
	var tg: Array = p.get("target", ["", 0])
	if ally == 0 and str(tg[0]) == "p": ally = int(tg[1])
	if eid == 0 and str(tg[0]) == "e": eid = int(tg[1])
	var recips: Array = []
	match tgt:
		"self": recips = [id]
		"ally":
			if ally != 0 and ally != id and _srv_same_group(id, ally) and (players[ally].pos as Vector3).distance_to(p.pos) <= float(eff.range) + 6.0:
				recips = [ally]
			else: recips = [id]
		"aura":
			recips = [id]
			var pt = parties.get(int(p.party))
			if pt != null:
				for m in pt.members:
					if m != id and _srv_same_group(id, m) and (players[m].pos as Vector3).distance_to(p.pos) <= float(eff.radius) + 3.0: recips.append(m)
		_:
			if eff.has("buff") or eff.has("shield"): recips = [id]
	var ally_eff: Dictionary = eff.duplicate(); ally_eff.erase("debuff"); ally_eff.erase("taunt")
	var payload := {"id": sid, "n": str(s.name), "c": (s.color as Color).to_html(false), "eff": ally_eff, "src": str(p.name)}
	var dur := float(Support.make_buff(s, ally_eff).dur)
	for r in recips:
		if not players.has(r): continue
		if dur > 0.0:
			if not players[r].has("buffs"): players[r].buffs = {}
			var pst: int = mini(9, int(players[r].buffs[sid].get("st", 1)) + 1) if players[r].buffs.has(sid) and float(players[r].buffs[sid].until) > now else 1
			players[r].buffs[sid] = {"until": now + dur, "icon": str(UIK.SKILL_ICONS.get(sid, "aura")), "col": s.color, "dur": dur, "good": true,
				"n": str(s.name), "d": Support.describe_eff(ally_eff), "st": pst, "src": str(p.name)}
		s_support.rpc_id(r, payload)
		support_stats.sent += 1
	# враги подземелья: метка, ослабление, замедление, провокация — в серверной RaidSim
	if (eff.has("debuff") or eff.has("taunt")) and int(p.iid) != 0:
		var inst = instances.get(int(p.iid))
		if inst != null and str(p.zone) == inst.zone: inst.sim.apply_support(id, eff, eid, pos)
	support_stats.casts += 1
	if int(p.party) != 0: _srv_party_send(int(p.party))

## Клиент: сервер применил поддержку к моему герою
@rpc("authority", "call_remote", "reliable")
func s_support(payload: Dictionary) -> void:
	var z = get_tree().current_scene
	if z == null or not ("player" in z) or z.player == null: return
	var s := {"id": str(payload.id), "name": str(payload.n), "color": Color.html(str(payload.c))}
	Support.apply_to_player(z.player, s, payload.eff, str(payload.src))
	support_received += 1
	if str(payload.src) != str(Game.current.get("name", "")):
		Game.toast("%s: «%s»" % [payload.src, payload.n], 1.6)
var support_received := 0

# =====================================================================
# v0.9.1: общие враги мира и общая добыча
# =====================================================================
## Долина и Земли Эфира онлайн: враги общие для всех игроков рядом. Сервер — хозяин состояния: какие враги
## живы, их уровень, ранг, здоровье, смерть, возрождение и добыча. Движение и обычный ИИ считает один из игроков
## рядом («ведущий», ближайший к логову; сервер передаёт ведение, если он ушёл), остальные видят копию по позициям.
## Удары всех игроков идут на сервер (c_wm_hit: проверка дистанции и потолка урона), атаки врага по другим
## игрокам — через сервер (c_wm_atk). Добыча падает на землю для всех: первым подобрал — твоё (c_pick).
## Соло-склеп остаётся личным; групповые подземелья и так считает сервер (RaidSim), их добыча — тоже общая.
const WM_ZONES := ["starter", "global", "dungeon"]
const WM_RELAY_R := 140.0
const DROP_TTL := 180.0
var wsims := {}           # сервер: ключ зоны ("starter", "global", "dungeon#<группа>") -> WorldSim
var navs := {}            # сервер: зона -> ServerNav
var nav_stats := {"areas": 0, "obstacles": 0}
var _wm_acc := 0.0
var _wm_aoi_t := 0.0
var _wm_t := 0.0
var _wm_key_t := 0.0
var srv_drops := {}       # сервер: did -> {zk, t, n, it, pos, until}
var _drop_next := 1
var wm_stats := {"hits": 0, "rejected": 0, "kills": 0, "picks": 0, "pick_denied": 0, "cc": 0, "pos_sent": 0, "ev_sent": 0}
# клиент
var wm_nodes := {}        # nid -> Enemy
var wm_spawner_nodes := {} # skey -> Spawner
var net_drops := {}       # did -> Loot
var world_client: WorldClient
var _cc_n := 0
var _cc_t := 0.0

func shared_world() -> bool:
	return in_game and WM_ZONES.has(str(Game.current.get("zone", "")))

static func wm_skey(zone_id: String, pos: Vector3) -> String:
	return "%s:%d:%d" % [zone_id, roundi(pos.x), roundi(pos.z)]

# ---------- клиент: вызовы ----------
func wm_sub(sp: Node, _def := {}) -> void:
	if not (shared_world() and _connected()): return
	var key := wm_skey(str(Game.current.zone), sp.global_position)
	wm_spawner_nodes[key] = sp
	sp.set_meta("wm_key", key)
	_wm_client_ensure()
	c_wm_sub.rpc_id(1, key)

func wm_unsub(sp: Node) -> void:
	var key := str(sp.get_meta("wm_key", ""))
	if key == "": return
	wm_spawner_nodes.erase(key)
	for nid in wm_nodes.keys():
		var e = wm_nodes[nid]
		if not is_instance_valid(e) or e.get_meta("wm_key", "") == key:
			if is_instance_valid(e):
				e.zone.enemies.erase(e); e.queue_free()
			wm_nodes.erase(nid)
	if in_game and _connected(): c_wm_unsub.rpc_id(1, key)

func wm_hit(nid: int, dmg: float) -> void:
	if in_game and _connected(): c_wm_hit.rpc_id(1, nid, dmg)

## Контроль по врагу (оглушение, замедление, отбрасывание, провокация, ослабление) — решает сервер
func wm_cc(nid: int, kind: String, v: float, dur: float, dir: Vector3) -> void:
	if not (in_game and _connected()): return
	var now := _now()
	if now - _cc_t > 1.0: _cc_t = now; _cc_n = 0
	_cc_n += 1
	if _cc_n > 12: return
	c_wm_cc.rpc_id(1, nid, kind, v, dur, dir)

func pick_drop(did: int) -> void:
	if in_game and _connected(): c_pick.rpc_id(1, did)

func _wm_client_ensure() -> void:
	var z = get_tree().current_scene
	if z == null or not ("fx_root" in z): return
	if world_client != null and is_instance_valid(world_client) and world_client.get_parent() == z: return
	world_client = WorldClient.new(); world_client.name = "WorldClient"
	z.add_child(world_client)
	world_client.setup(z)

func _wm_client_tick(_delta: float) -> void: pass   # v0.9.2: клиент больше не ведёт ИИ врагов

func _wm_client_reset() -> void:
	wm_nodes.clear(); wm_spawner_nodes.clear(); net_drops.clear()

# ---------- сервер ----------
## Ключ экземпляра: долина и Земли Эфира — общие; Склеп — свой у каждой группы (или у одиночки)
func _wm_zk(p: Dictionary) -> String:
	var z := str(p.zone)
	if z == "dungeon": return "dungeon#%d" % (int(p.party) if int(p.get("party", 0)) != 0 else 1000000 + int(p.get("peer", 0)))
	return z

func _wm_sim(p: Dictionary) -> WorldSim:
	var z := str(p.zone)
	if not WM_ZONES.has(z): return null
	var zk := _wm_zk(p)
	var sim = wsims.get(zk)
	if sim != null: return sim
	var nav = navs.get(z)
	if nav == null:
		var t0 := Time.get_ticks_msec()
		var root := Node3D.new(); root.name = "Nav_" + z
		add_child(root)
		nav = ServerNav.new()
		nav.build(root, z)
		navs[z] = nav
		print("server: навмеш «%s»: логов %d, %d мс" % [z, nav.spawners.size(), Time.get_ticks_msec() - t0])
	sim = WorldSim.new(zk, z, nav)
	sim.kills_cb = _wm_on_kill
	if z == "dungeon":   # v0.9.2: уровень Склепа — по сильнейшему из группы в пределах DB.DUNGEON_LV (номинал 10)
		var lvl := int(p.data.get("level", 1))
		var pt = parties.get(int(p.get("party", 0)))
		if pt != null:
			for m in pt.members: if players.has(m): lvl = maxi(lvl, int(players[m].data.get("level", 1)))
		sim.lv_off = DB.dungeon_level("dungeon", lvl) - 10
		print("server: склеп %s — ур. %d" % [zk, 10 + sim.lv_off])
	wsims[zk] = sim
	sim.set_meta("empty_t", 0.0)
	return sim

func _wm_by_nid(p: Dictionary, nid: int):
	var sim = wsims.get(_wm_zk(p))
	if sim == null: return null
	return sim.mobs.get(nid)

@rpc("any_peer", "call_remote", "reliable")
func c_wm_sub(key: String) -> void:
	if not is_server: return
	var id := multiplayer.get_remote_sender_id()
	var p = _authed(id)
	if p == null or not WM_ZONES.has(str(p.zone)) or not key.begins_with(str(p.zone) + ":") or key.length() > 64: return
	if str(p.zone) == "dungeon" and str(p.get("wm_zk", "")) != _wm_zk(p):
		var old := str(p.get("wm_zk", ""))
		if wsims.has(old): wsims[old].remove_player(id)
		p["wm_zk"] = _wm_zk(p)
		if not _dng_admit(id, p): return
	var sim := _wm_sim(p)
	if sim == null: return
	var sp = sim.ensure_spawner(key)   # описание логова — только серверное (ServerNav), клиентскому не верим
	if sp == null or U.flat_dist(p.pos, sp.pos) > 260.0: return
	sp.subs[id] = true
	s_wm_spawn.rpc_id(id, key, sim.spawner_list(sp))
	for nid in sp.mobs:   # состояние босса — сразу
		var m = sim.mobs.get(nid)
		if m != null and m.alive and not m.boss.is_empty(): sim._st(m)
	var near := []
	for did in srv_drops:
		var d: Dictionary = srv_drops[did]
		if d.zk == sim.zk and (d.pos as Vector3).distance_to(sp.pos) < 60.0: near.append(_drop_pub(int(did), d))
	if not near.is_empty(): s_drop_add.rpc_id(id, near)

@rpc("any_peer", "call_remote", "reliable")
func c_wm_unsub(key: String) -> void:
	if not is_server: return
	var id := multiplayer.get_remote_sender_id()
	var p = _authed(id)
	if p == null: return
	var sim = wsims.get(_wm_zk(p))
	if sim != null and sim.spawners.has(key): sim.spawners[key].subs.erase(id)

@rpc("any_peer", "call_remote", "reliable")
func c_wm_hit(nid: int, dmg: float) -> void:
	if not is_server: return
	var id := multiplayer.get_remote_sender_id()
	var p = _authed(id)
	if p == null or not is_finite(dmg) or dmg <= 0.0 or float(p.hp) <= 0.0: return
	var sim = wsims.get(_wm_zk(p))
	if sim == null: return
	var m = sim.mobs.get(nid)
	if m == null or not m.alive: return
	var st := _srv_stats(p)
	var cap: float = maxf(60.0, float(st.get("damage", 10.0)) * float(st.get("dmg_mult", 1.0)) * float(st.get("spell_mult", 1.0)) * float(st.get("crit_mult", 2.0)) * 14.0)
	# окно в 1 с: суммарный урон игрока по врагам мира не больше 4 потолков удара
	var now := _now()
	if now - float(p.get("wm_win_t", 0.0)) > 1.0: p["wm_win_t"] = now; p["wm_win"] = 0.0
	if U.flat_dist(p.pos, m.pos) > 45.0 or dmg > cap or float(p.get("wm_win", 0.0)) + dmg > cap * 4.0:
		wm_stats.rejected += 1; return
	p["wm_win"] = float(p.get("wm_win", 0.0)) + dmg
	wm_stats.hits += 1
	sim.hit(id, nid, dmg)

@rpc("any_peer", "call_remote", "reliable")
func c_wm_cc(nid: int, kind: String, v: float, dur: float, dir: Vector3) -> void:
	if not is_server: return
	var id := multiplayer.get_remote_sender_id()
	var p = _authed(id)
	if p == null or not (kind in ["stun", "slow", "kb", "taunt", "weaken"]) or not is_finite(v) or not is_finite(dur) or not dir.is_finite(): return
	var now := _now()
	if now - float(p.get("cc_t", 0.0)) > 1.0: p["cc_t"] = now; p["cc_n"] = 0
	p["cc_n"] = int(p.get("cc_n", 0)) + 1
	if int(p.cc_n) > 15: return
	var sim = wsims.get(_wm_zk(p))
	if sim == null: return
	var m = sim.mobs.get(nid)
	if m == null or U.flat_dist(p.pos, m.pos) > 40.0: return
	wm_stats.cc += 1
	sim.cc(id, nid, kind, v, dur, dir)

## Враг погиб (решение WorldSim): участникам — опыт и флаги, добыча — на землю для всех
func _wm_on_kill(sim: WorldSim, sp, m: Dictionary) -> void:
	wm_stats.kills += 1
	if sim.zone_id == "dungeon" and str(m.kind) == "warden" and int(m.add_of) == 0:
		for pid in sim.players: _dng_count(pid, "dungeon")
	var subs: Dictionary = sp.subs if sp != null else {}
	var xpm := wm_xp(sim, m)
	for s in sim.players:
		if players.has(s) and (subs.has(s) or m.parts.has(s) or xpm.has(s)): s_wm_kill.rpc_id(s, int(m.nid), m.parts.has(s) or xpm.has(s), int(xpm.get(s, 0)))
	if int(m.killer) == 0 and m.parts.is_empty(): return   # взорвался сам — без добычи
	var kp = players.get(int(m.killer))
	var cls := str(kp.data.get("class", "warrior")) if kp != null else "warrior"
	var hl := int(kp.data.get("level", 1)) if kp != null else int(m.lvl)
	var boss: bool = bool(m.def.boss) or str(m.rank) == "boss"
	var list: Array = Loot.roll_boss_drops(int(m.lvl), cls) if boss else Loot.roll_drops(int(m.lvl), hl, cls, str(m.rank))
	var out := []
	for dr in list:
		var r := Vector2.from_angle(randf() * TAU) * randf_range(0.4, 1.6) * (2.0 if boss else 1.0)
		out.append(_srv_drop_new(sim.zk, str(dr[0]), int(dr[1]), dr[2], m.pos + Vector3(r.x, 0, r.y)))
	_srv_drop_send(sim.zk, out, m.pos)

func _srv_drop_new(zk: String, t: String, n: int, it: Dictionary, pos: Vector3) -> Dictionary:
	var did := _drop_next; _drop_next += 1
	srv_drops[did] = {"zk": zk, "t": t, "n": n, "it": it, "pos": pos, "until": _now() + DROP_TTL}
	return _drop_pub(did, srv_drops[did])

func _drop_pub(did: int, d: Dictionary) -> Dictionary:
	return {"id": did, "t": d.t, "n": d.n, "it": d.it, "x": d.pos.x, "y": d.pos.y, "z": d.pos.z}

func _srv_drop_send(zk: String, list: Array, at: Vector3) -> void:
	if list.is_empty(): return
	for s in players:
		var q = players[s]
		if q.authed and _wm_zk(q) == zk and (q.pos as Vector3).distance_to(at) < WM_RELAY_R: s_drop_add.rpc_id(s, list)

@rpc("any_peer", "call_remote", "reliable")
func c_pick(did: int) -> void:
	if not is_server: return
	var id := multiplayer.get_remote_sender_id()
	var p = _authed(id)
	if p == null: return
	var d = srv_drops.get(did)
	if d == null:
		wm_stats.pick_denied += 1; s_drop_gone.rpc_id(id, did); return
	if d.zk != _wm_zk(p) or U.flat_dist(p.pos, d.pos) > 7.0 or float(p.hp) <= 0.0:
		wm_stats.pick_denied += 1; return
	if d.t == "item" and (p.data.get("inventory", []) as Array).size() >= DB.INVENTORY_SIZE: return
	srv_drops.erase(did)
	wm_stats.picks += 1
	# серверная копия героя: сразу с добычей (ремесло проверяет материалы и золото по ней)
	match str(d.t):
		"gold": p.data["gold"] = int(p.data.get("gold", 0)) + int(d.n)
		"potion": p.data["potions"] = int(p.data.get("potions", 0)) + int(d.n)
		"mat":
			var mats: Dictionary = p.data.get("mats", {})
			var mid := str((d.it as Dictionary).get("mat", "aether_dust"))
			mats[mid] = int(mats.get(mid, 0)) + int(d.n); p.data["mats"] = mats
		_: p.data["inventory"].append(d.it)
	p.dirty = true
	s_pick_ok.rpc_id(id, did, str(d.t), int(d.n), d.it)
	for s in players:
		if s != id and players[s].authed and _wm_zk(players[s]) == d.zk: s_drop_gone.rpc_id(s, did)

## Шаг серверной симуляции мира: фиксированные 20 Гц; события — пачкой каждому игроку; позиции врагов —
## 10 Гц и только тем, кто ближе AOI_R (и только сдвинувшиеся / с изменившимся здоровьем, раз в 1 с — все)
func _wm_server_tick(delta: float) -> void:
	_wm_acc = minf(_wm_acc + delta, 0.25)
	while _wm_acc >= WorldSim.TICK:
		_wm_acc -= WorldSim.TICK
		_wm_feed()
		for zk in wsims: wsims[zk].tick(WorldSim.TICK)
		_wm_flush_events()
	_wm_aoi_t -= delta
	if _wm_aoi_t <= 0.0:
		_wm_aoi_t = 0.1
		_wm_key_t -= 0.1
		var key := _wm_key_t <= 0.0
		if key: _wm_key_t = 1.0
		for zk in wsims: _wm_send_pos(wsims[zk], key)
	_wm_t -= delta
	if _wm_t > 0.0: return
	_wm_t = 0.5
	var now := _now()
	for zk in wsims.keys():
		var sim: WorldSim = wsims[zk]
		for key in sim.spawners:
			var sp: Dictionary = sim.spawners[key]
			for s in sp.subs.keys():
				if not players.has(s) or not players[s].get("authed", false) or _wm_zk(players[s]) != zk: sp.subs.erase(s)
		# пустой экземпляр Склепа — закрыть через 2 минуты
		if sim.zone_id == "dungeon":
			if sim.players.is_empty():
				sim.set_meta("empty_t", float(sim.get_meta("empty_t", 0.0)) + 0.5)
				if float(sim.get_meta("empty_t")) > 120.0:
					print("server: склеп %s закрыт" % zk)
					wsims.erase(zk)
			else: sim.set_meta("empty_t", 0.0)
	for did in srv_drops.keys():
		if now > float(srv_drops[did].until):
			var d: Dictionary = srv_drops[did]
			srv_drops.erase(did)
			for s in players: if players[s].authed and _wm_zk(players[s]) == d.zk: s_drop_gone.rpc_id(s, did)

func _wm_feed() -> void:
	for id in players:
		var p = players[id]
		if not p.get("authed", false): continue
		var zk := _wm_zk(p) if WM_ZONES.has(str(p.zone)) else ""
		var old := str(p.get("wm_zk", ""))
		if old != zk:
			if wsims.has(old): wsims[old].remove_player(id)
			p["wm_zk"] = zk
			if str(p.zone) == "dungeon" and not _dng_admit(id, p): continue
		if zk == "" or not wsims.has(zk): continue
		var st := _srv_stats(p)
		var mhp := float(st.get("max_hp", 100.0))
		wsims[zk].set_player(id, p.pos, float(p.hp) * mhp, int(p.data.get("level", 1)), str(p.data.get("class", "warrior")), mhp)
	for zk in wsims:
		var sim: WorldSim = wsims[zk]
		for pid in sim.players.keys():
			if not players.has(pid) or str(players[pid].get("wm_zk", "")) != zk: sim.remove_player(pid)

func _wm_flush_events() -> void:
	for zk in wsims:
		var sim: WorldSim = wsims[zk]
		if sim.events.is_empty(): continue
		var out := {}
		for e in sim.events:
			var to := int(e[0])
			if to != 0:
				if sim.players.has(to): (out.get_or_add(to, []) as Array).append(e[1])
				continue
			var pos: Vector3 = e[2]
			for pid in sim.players:
				if sim.zone_id == "dungeon" or U.flat_dist(sim.players[pid].pos, pos) < WM_RELAY_R:
					(out.get_or_add(pid, []) as Array).append(e[1])
		sim.events.clear()
		for pid in out:
			if players.has(pid):
				s_wm_ev.rpc_id(pid, out[pid])
				wm_stats.ev_sent += (out[pid] as Array).size()

func _wm_send_pos(sim: WorldSim, key: bool) -> void:
	if sim.players.is_empty(): return
	var moved := []
	for nid in sim.mobs:
		var m: Dictionary = sim.mobs[nid]
		if not m.alive: continue
		var lp = m.get("lp")
		if key or lp == null or (lp[0] as Vector3).distance_squared_to(m.pos) > 0.0004 or absf(float(lp[1]) - float(m.yaw)) > 0.02 or absf(float(lp[2]) - float(m.hp)) > 0.01:
			m["lp"] = [m.pos, m.yaw, m.hp]
			moved.append(m)
	if moved.is_empty(): return
	for pid in sim.players:
		if not players.has(pid): continue
		var pp: Vector3 = sim.players[pid].pos
		var ids := PackedInt32Array(); var data := PackedFloat32Array()
		for m in moved:
			if U.flat_dist(m.pos, pp) > WorldSim.AOI_R: continue
			ids.append(int(m.nid)); data.append_array([m.pos.x, m.pos.z, m.yaw, m.hp])
		if not ids.is_empty():
			s_wm_pos.rpc_id(pid, ids, data)
			wm_stats.pos_sent += ids.size()

# ---------- RPC: сервер → клиент ----------
func _wm_make(key: String, list: Array) -> void:
	var z = get_tree().current_scene
	var sp = wm_spawner_nodes.get(key)
	if z == null or sp == null or not is_instance_valid(sp): return
	_wm_client_ensure()
	for m in list:
		var nid := int(m.id)
		if wm_nodes.has(nid) and is_instance_valid(wm_nodes[nid]): continue
		var e := Enemy.spawn(z, str(m.k), int(m.lvl), Vector3(float(m.x), 0.0, float(m.z)), sp)
		if str(m.rk) != "normal": e.make_rank(str(m.rk), str(m.nm), m.aff)
		e.max_hp = float(m.mhp); e.hp = float(m.hp)
		e.rotation.y = float(m.yaw)
		e.set_net(nid)
		e.set_meta("wm_key", key)
		if int(m.get("add", 0)) == 0:
			if sp.has_method("_net_died"): e.on_death = sp._net_died
			sp.alive += 1
		else: e.set_meta("wm_add", true)
		wm_nodes[nid] = e

@rpc("authority", "call_remote", "reliable")
func s_wm_spawn(key: String, list: Array) -> void:
	_wm_make(key, list)

@rpc("authority", "call_remote", "reliable")
func s_wm_ev(list: Array) -> void:
	for ev in list:
		if not (ev is Dictionary): continue
		match str(ev.get("t", "")):
			"spawn": _wm_make(str(ev.sp), ev.e)
			"gone":
				var e = wm_nodes.get(int(ev.id))
				wm_nodes.erase(int(ev.id))
				if e != null and is_instance_valid(e) and e.alive: e.alive = false; e.zone.enemies.erase(e); e.queue_free()
			_:
				_wm_client_ensure()
				if world_client != null and is_instance_valid(world_client): world_client.handle(ev)

@rpc("authority", "call_remote", "unreliable_ordered")
func s_wm_pos(ids: PackedInt32Array, data: PackedFloat32Array) -> void:
	for i in mini(ids.size(), data.size() / 4):
		var e = wm_nodes.get(int(ids[i]))
		if e != null and is_instance_valid(e) and e.alive:
			e.net_pos(Vector3(data[i * 4], 0.0, data[i * 4 + 1]), data[i * 4 + 2])
			e.hp = minf(data[i * 4 + 3], e.max_hp)

## v0.9.3: опыт за убийство (сервер): участники + их согруппники рядом (≤ 50 м), доли по уровням, бонус группы
func wm_xp(sim, m: Dictionary) -> Dictionary:
	var elig := {}
	for s in m.parts:
		if not players.has(s): continue
		elig[s] = true
		var pid := int(players[s].get("party", 0))
		if pid != 0 and parties.has(pid):
			for o in parties[pid].members:
				if players.has(o) and sim.players.has(o) and U.flat_dist(players[o].pos, m.pos) <= 50.0: elig[o] = true
	if elig.is_empty(): return {}
	var ids := elig.keys()
	var lv := []
	for s in ids: lv.append(int(players[s].data.get("level", 1)))
	var rk := "boss" if bool(m.def.boss) or str(m.rank) == "boss" else str(m.rank)
	var sh: Array = Xp.shares(float(m.def.xp), int(m.lvl), rk, lv)
	var out := {}
	var now := _now()
	for i in ids.size():
		var p = players[ids[i]]
		if not p.has("xp_st"): p["xp_st"] = {}
		out[ids[i]] = Xp.personal(sh[i], p.xp_st, str(m.kind), now, Xp.today())
	return out

@rpc("authority", "call_remote", "reliable")
func s_wm_kill(nid: int, participant: bool, xp := -1) -> void:
	var e = wm_nodes.get(nid)
	wm_nodes.erase(nid)
	if e != null and is_instance_valid(e) and e.alive:
		var sp = wm_spawner_nodes.get(str(e.get_meta("wm_key", "")))
		if e.has_meta("wm_add"): e.on_death = Callable()
		elif not participant and sp != null and is_instance_valid(sp): sp.alive = maxi(0, sp.alive - 1)
		e.net_die(participant, xp)


@rpc("authority", "call_remote", "reliable")
func s_drop_add(list: Array) -> void:
	var z = get_tree().current_scene
	if z == null or not ("fx_root" in z) or z.fx_root == null: return
	for d in list:
		var did := int(d.id)
		if net_drops.has(did) and is_instance_valid(net_drops[did]): continue
		var l := Loot.spawn(z, Vector3(float(d.x), float(d.y), float(d.z)), str(d.t), int(d.n), d.it)
		l.net_id = did
		net_drops[did] = l

@rpc("authority", "call_remote", "reliable")
func s_drop_gone(did: int) -> void:
	var l = net_drops.get(did)
	net_drops.erase(did)
	if l != null and is_instance_valid(l): l.queue_free()

@rpc("authority", "call_remote", "reliable")
func s_pick_ok(did: int, t: String, n: int, it: Dictionary) -> void:
	var l = net_drops.get(did)
	net_drops.erase(did)
	picks_ok += 1
	if l != null and is_instance_valid(l):
		l.grant(); return
	var z = get_tree().current_scene
	if z == null or not ("fx_root" in z): return
	var tmp := Loot.spawn(z, z.player.global_position, t, n, it)
	tmp.grant()
var picks_ok := 0

# ---------- v0.9.1: таланты, умения и ремесло — с проверкой на сервере ----------
## Клиент уже применил операцию у себя; сервер повторяет её на своей копии героя. Отказ — сервер
## присылает свои таланты/умения/материалы (s_char_fix), и клиент откатывается к ним.
func char_op(op: String, arg: String) -> void:
	if in_game and _connected(): c_char_op.rpc_id(1, op.left(20), arg.left(40))
func craft(set_id: String, piece: int) -> void:
	if in_game and _connected(): c_craft.rpc_id(1, set_id.left(20), piece)
var char_ops := {"ok": 0, "rejected": 0}

func _srv_fix_pub(c: Dictionary) -> Dictionary:
	return {"talents": c.get("talents", []), "ranks": c.get("ranks", {}), "ascendancy": c.get("ascendancy", ""), "skill_ranks": c.get("skill_ranks", {}),
		"loadout": c.get("loadout", []), "mats": c.get("mats", {}), "gold": int(c.get("gold", 0)), "inventory": c.get("inventory", [])}

@rpc("any_peer", "call_remote", "reliable")
func c_char_op(op: String, arg: String) -> void:
	if not is_server: return
	var id := multiplayer.get_remote_sender_id()
	var p = _authed(id)
	if p == null: return
	var why := DB.char_op(p.data, op, arg)
	if why != "":
		char_ops.rejected += 1
		s_notice.rpc_id(id, "Сервер отклонил: %s" % why)
		s_char_fix.rpc_id(id, _srv_fix_pub(p.data))
		return
	char_ops.ok += 1
	p.dirty = true; p.erase("st_cache")

@rpc("any_peer", "call_remote", "reliable")
func c_craft(set_id: String, piece: int) -> void:
	if not is_server: return
	var id := multiplayer.get_remote_sender_id()
	var p = _authed(id)
	if p == null: return
	var why := Items.craft_block(p.data, set_id, piece)
	if why != "":
		s_notice.rpc_id(id, "Ремесло: %s" % why)
		s_char_fix.rpc_id(id, _srv_fix_pub(p.data))
		return
	var it := Items.craft(p.data, set_id, piece)
	p.data["craft_n"] = int(p.data.get("craft_n", 0)) + 1
	p.dirty = true
	s_craft_ok.rpc_id(id, it, p.data["mats"], int(p.data["gold"]), int(p.data.craft_n))

@rpc("authority", "call_remote", "reliable")
func s_char_fix(d: Dictionary) -> void:
	var c: Dictionary = Game.current
	for k in d: c[k] = d[k]
	Game.normalize(c)
	char_fixes += 1
	var z = get_tree().current_scene
	if z and z.has_method("apply_character_changes"): z.apply_character_changes(false)
	if z and "hud" in z and z.hud and z.hud.window and z.hud.window.has_method("refresh"): z.hud.window.refresh()
var char_fixes := 0

signal crafted(item: Dictionary)
@rpc("authority", "call_remote", "reliable")
func s_craft_ok(it: Dictionary, mats: Dictionary, gold: int, n: int) -> void:
	var c: Dictionary = Game.current
	c["mats"] = mats; c["gold"] = gold; c["craft_n"] = n
	c["inventory"].append(it)
	Game.normalize(c)
	var z = get_tree().current_scene
	if z and z.has_method("save"): z.save()
	crafted.emit(it)

# ---------- v0.9.2: инвентарь и золото — на сервере ----------
signal inv_result(op: String, r: Dictionary)
var inv_stats := {"ok": 0, "rejected": 0, "resync": 0}
var inv_syncs := 0

## Клиент: операция с вещами. Офлайн/не в сети — применяется сразу; онлайн — ещё и на сервере (сервер прав).
## local=false — не применять у себя (улучшение: бросок делает сервер, ответ — inv_result)
func inv(op: String, args: Array = [], local := true) -> Dictionary:
	var r := {"err": ""}
	if local or not (in_game and _connected()): r = InvOps.apply(Game.current, op, args)
	if in_game and _connected(): c_inv.rpc_id(1, op.left(20), args.slice(0, 120))
	return r

@rpc("any_peer", "call_remote", "reliable")
func c_inv(op: String, args: Array) -> void:
	if not is_server: return
	var id := multiplayer.get_remote_sender_id()
	var p = _authed(id)
	if p == null: return
	var now := _now()
	if now - float(p.get("invop_t", 0.0)) > 1.0: p["invop_t"] = now; p["invop_n"] = 0
	p["invop_n"] = int(p.get("invop_n", 0)) + 1
	if int(p.invop_n) > 30: return   # не больше 30 операций в секунду
	if p.get("mkt_busy", false):
		s_inv.rpc_id(id, op, InvOps.pub(p.data), {"err": "Подождите: идёт сделка на рынке"}); return
	var r := InvOps.apply(p.data, op, args)
	if str(r.get("err", "")) == "": inv_stats.ok += 1
	else: inv_stats.rejected += 1
	p.dirty = true; p.erase("st_cache")
	s_inv.rpc_id(id, op, InvOps.pub(p.data), r)

@rpc("authority", "call_remote", "reliable")
func s_inv(op: String, state: Dictionary, r: Dictionary) -> void:
	var c: Dictionary = Game.current
	if c.is_empty(): return
	for k in state: c[k] = state[k]
	Game.normalize(c)
	inv_syncs += 1
	var z = get_tree().current_scene
	if z and z.has_method("apply_character_changes"): z.apply_character_changes(false)
	if z and "hud" in z and z.hud and z.hud.window and z.hud.window.has_method("refresh"): z.hud.window.refresh()
	inv_result.emit(op, r)

# ---------- v0.9.2: рынок (аукцион) — сделки в БД одной транзакцией вместе с героем ----------
signal market_result(op: String, r: Dictionary)
const MARKET_TAX := 0.07
static func market_fee(price: int) -> int: return clampi(int(round(price * 0.02)), 5, 5000)
var mkt_stats := {"list": 0, "buy": 0, "cancel": 0, "claim": 0, "denied": 0}

func market(op: String, args: Dictionary = {}) -> void:
	if in_game and _connected(): c_mkt.rpc_id(1, op.left(12), args)

@rpc("any_peer", "call_remote", "reliable")
func c_mkt(op: String, args: Dictionary) -> void:
	if not is_server: return
	var id := multiplayer.get_remote_sender_id()
	var p = _authed(id)
	if p == null: return
	if p.get("mkt_busy", false):
		s_mkt.rpc_id(id, op, {"ok": false, "error": "Подождите: предыдущая сделка ещё идёт"}); return
	p["mkt_busy"] = true
	var r: Dictionary = {}
	r = await _mkt_do(p, op, args)
	p["mkt_busy"] = false
	if not r.get("ok", false): mkt_stats.denied += 1
	if players.has(id):
		s_mkt.rpc_id(id, op, r)
		if op in ["list", "buy", "claim"]: s_inv.rpc_id(id, "market", InvOps.pub(p.data), {"err": ""})

## Перед сделкой — записать героя (в БД должна быть текущая версия), затем кандидат с номером версии +1
func _mkt_prep(p: Dictionary) -> void:
	while p.get("flushing", false): await get_tree().create_timer(0.05).timeout
	p.dirty = true
	p["mkt_busy"] = false
	await _srv_flush(p, true)
	p["mkt_busy"] = true

func _mkt_cand(p: Dictionary) -> Dictionary:
	var c: Dictionary = p.data.duplicate(true)
	c["pos"] = [p.pos.x, p.pos.y, p.pos.z]
	c["_rev"] = int(p.data.get("_rev", 0)) + 1
	return c

func _mkt_do(p: Dictionary, op: String, a: Dictionary) -> Dictionary:
	var base := {"account_id": p.acc, "char_id": p.char_id}
	match op:
		"search":
			var f: Dictionary = a.get("filters", {}) if a.get("filters") is Dictionary else {}
			var d := await _srv_http(HTTPClient.METHOD_POST, "/internal/market/search", {"filters": f, "char_id": p.char_id})
			return {"ok": d["_code"] == 200, "list": d.get("list", []), "error": d.get("error", "")}
		"mine":
			var d := await _srv_http(HTTPClient.METHOD_POST, "/internal/market/mine", base)
			return {"ok": d["_code"] == 200, "list": d.get("list", []), "mail": d.get("mail", []), "error": d.get("error", "")}
		"list":
			var uid := str(a.get("uid", "")).left(40)
			var price := int(a.get("price", 0))
			if price < 1 or price > 50000000: return {"ok": false, "error": "Цена: от 1 до 50 000 000"}
			var it = Items.find_uid(p.data.get("inventory", []), uid)
			if it == null: return {"ok": false, "error": "Выставить можно вещь из инвентаря"}
			var fee := market_fee(price)
			if int(p.data.get("gold", 0)) < fee: return {"ok": false, "error": "Плата за выставление: %d золота" % fee}
			await _mkt_prep(p)
			it = Items.find_uid(p.data.get("inventory", []), uid)
			if it == null: return {"ok": false, "error": "Предмет пропал"}
			var cand := _mkt_cand(p)
			cand.inventory.erase(Items.find_uid(cand.inventory, uid)); cand["gold"] = int(cand.gold) - fee
			var body := base.duplicate(); body["data"] = cand; body["item"] = it; body["price"] = price
			var d := await _srv_http(HTTPClient.METHOD_POST, "/internal/market/list", body)
			if d["_code"] != 200: return {"ok": false, "error": str(d.get("error", "нет связи с базой"))}
			var cur = Items.find_uid(p.data.inventory, uid)
			if cur != null: p.data.inventory.erase(cur)
			p.data["gold"] = int(p.data.gold) - fee; p.data["_rev"] = cand._rev
			mkt_stats.list += 1
			return {"ok": true, "id": int(d.get("id", 0)), "fee": fee}
		"buy":
			var lid := int(a.get("id", 0))
			var g := await _srv_http(HTTPClient.METHOD_POST, "/internal/market/get", {"id": lid})
			if g["_code"] != 200 or not (g.get("listing") is Dictionary) or str(g.listing.get("status", "")) != "active": return {"ok": false, "error": "Лот уже продан или снят"}
			var L: Dictionary = g.listing
			if str(L.get("seller_char", "")) == p.char_id: return {"ok": false, "error": "Это ваш лот"}
			if int(p.data.get("gold", 0)) < int(L.price): return {"ok": false, "error": "Не хватает золота"}
			if (p.data.inventory as Array).size() >= DB.INVENTORY_SIZE: return {"ok": false, "error": "Инвентарь полон"}
			await _mkt_prep(p)
			var cand := _mkt_cand(p)
			cand.inventory.append(L.item); cand["gold"] = int(cand.gold) - int(L.price)
			if int(cand.gold) < 0: return {"ok": false, "error": "Не хватает золота"}
			var body := base.duplicate(); body["data"] = cand; body["id"] = lid
			var d := await _srv_http(HTTPClient.METHOD_POST, "/internal/market/buy", body)
			if d["_code"] != 200: return {"ok": false, "error": str(d.get("error", "нет связи с базой"))}
			var item: Dictionary = L.item
			_mkt_int(item)
			p.data.inventory.append(item); p.data["gold"] = int(p.data.gold) - int(L.price); p.data["_rev"] = cand._rev
			mkt_stats.buy += 1
			return {"ok": true, "item": item, "price": int(L.price)}
		"cancel":
			var d := await _srv_http(HTTPClient.METHOD_POST, "/internal/market/cancel", {"char_id": p.char_id, "id": int(a.get("id", 0))})
			if d["_code"] != 200: return {"ok": false, "error": str(d.get("error", "нет связи с базой"))}
			mkt_stats.cancel += 1
			return {"ok": true}
		"claim":
			var m := await _srv_http(HTTPClient.METHOD_POST, "/internal/market/mine", base)
			if m["_code"] != 200: return {"ok": false, "error": "нет связи с базой"}
			var free: int = DB.INVENTORY_SIZE - (p.data.inventory as Array).size()
			var ids := []; var gold := 0; var items := []
			for ml in m.get("mail", []):
				if ml.get("item") is Dictionary:
					if free <= 0: continue
					free -= 1; items.append(ml.item)
				gold += int(ml.get("gold", 0)); ids.append(int(ml.id))
			if ids.is_empty(): return {"ok": false, "error": "Почта пуста" if (m.get("mail", []) as Array).is_empty() else "Инвентарь полон"}
			await _mkt_prep(p)
			var cand := _mkt_cand(p)
			for it in items: cand.inventory.append(it)
			cand["gold"] = int(cand.gold) + gold
			var body := base.duplicate(); body["data"] = cand; body["ids"] = ids
			var d := await _srv_http(HTTPClient.METHOD_POST, "/internal/market/claim", body)
			if d["_code"] != 200: return {"ok": false, "error": str(d.get("error", "нет связи с базой"))}
			for it in items: _mkt_int(it); p.data.inventory.append(it)
			p.data["gold"] = int(p.data.gold) + gold; p.data["_rev"] = cand._rev
			mkt_stats.claim += 1
			return {"ok": true, "gold": gold, "items": items.size()}
	return {"ok": false, "error": "неизвестная операция"}

func _mkt_int(it: Dictionary) -> void:
	for k in ["slot", "rarity", "ilvl", "req", "up", "v"]: if it.has(k): it[k] = int(it[k])

@rpc("authority", "call_remote", "reliable")
func s_mkt(op: String, r: Dictionary) -> void:
	market_result.emit(op, r)



# ---------- v0.9.2: прохождения подземелий (не больше DB.DUNGEON_RUNS) — считает только сервер ----------
func _dng_count(pid: int, did: String) -> void:
	var p = players.get(pid)
	if p == null or not p.get("authed", false): return
	var left := DB.dungeon_complete(p.data, did)
	p.dirty = true
	s_inv.rpc_id(pid, "sync", InvOps.pub(p.data), {"err": ""})
	s_notice.rpc_id(pid, "«%s» пройдено! Осталось прохождений: %d из %d" % [DB.dungeon_name(did), left, DB.DUNGEON_RUNS])
	print("server: %s прошёл «%s» (осталось %d)" % [p.name, did, left])

## Сервер не впустил в Склеп — клиент возвращается в долину к началу
@rpc("authority", "call_remote", "reliable")
func s_dng_kick(why: String) -> void:
	Game.toast(why, 4.0)
	if str(Game.current.get("zone", "")) == "dungeon": Game.travel_start("starter")

## Вход в экземпляр Склепа (p.wm_zk уже выставлен): проверка уровня и лимита; новый забег — свежий экземпляр
func _dng_admit(id: int, p: Dictionary) -> bool:
	var zk := str(p.wm_zk)
	var why := DB.dungeon_lock(p.data, "dungeon")
	if why != "":
		p["wm_zk"] = ""
		if _now() > float(p.get("dng_kick_t", 0.0)):
			p["dng_kick_t"] = _now() + 3.0
			s_dng_kick.rpc_id(id, why)
		return false
	if wsims.has(zk) and wsims[zk].players.is_empty():
		wsims.erase(zk); print("server: склеп %s — новый забег" % zk)
	return true
