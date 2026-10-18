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

const PROTOCOL := 2
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

# ---------- сервер ----------
var players := {}                # peer_id -> {...}
var internal_key := ""
var internal_url := "http://127.0.0.1:7781"
var _snap_t := 0.0
var _log_t := 0.0

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
		var hp := 1.0
		if "hp" in p and "stats" in p and p.stats: hp = clampf(float(p.hp) / maxf(1.0, float(p.stats.max_hp)), 0.0, 1.0)
		c_state.rpc_id(1, str(Game.current.get("zone", "")), p.global_position, p.rotation.y, hp)
	# удалённые игроки — сглаживание
	for id in remotes:
		var r: Dictionary = remotes[id]
		var same: bool = r.zone == str(Game.current.get("zone", ""))
		if same and (r.node == null or not is_instance_valid(r.node)):
			r.node = RemotePlayer.create(z, r)
		elif not same and r.node and is_instance_valid(r.node):
			r.node.queue_free(); r.node = null
		if r.node and is_instance_valid(r.node): r.node.step(delta, r.pos, r.yaw, r.hp)
	if _overlay == null or not is_instance_valid(_overlay):
		_overlay = NetOverlay.new(); z.add_child(_overlay)

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
	players.erase(id)
	if p == null: return
	if p.authed:
		await _srv_flush(p, true)
		for oid in players:
			if players[oid].authed: s_player_left.rpc_id(oid, id, p.name)
	print("server: отключение %d (всего %d)" % [id, players.size()])

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
		"asc": p.data.get("ascendancy", ""), "level": int(p.data.get("level", 1)), "zone": p.zone, "pos": p.pos, "yaw": p.yaw}

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
	var d := await _srv_http(HTTPClient.METHOD_POST, "/internal/session", {"token": tok, "char_id": char_id})
	if not players.has(id): return
	if d["_code"] != 200 or not (d.get("character") is Dictionary):
		s_refused.rpc_id(id, "вход не подтверждён — войдите заново"); _kick_later(id); return
	var c: Dictionary = d.character
	var pos := Vector3.ZERO
	var cp = c.get("pos", [0, 0, 0])
	if cp is Array and cp.size() == 3: pos = Vector3(float(cp[0]), float(cp[1]), float(cp[2]))
	var p := {"authed": true, "acc": int(d.account_id), "user": str(d.username), "char_id": char_id, "name": str(c.get("name", "?")),
		"data": c, "zone": str(c.get("zone", "starter")), "pos": pos, "yaw": 0.0, "hp": 1.0, "t": _now(), "tp_until": _now() + 5.0,
		"tp_t": 0.0, "viol": 0, "budget": 24.0, "dirty": false, "save_t": _now(), "chat_t": 0.0, "chat_n": 0}
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
func c_state(zone_id: String, pos: Vector3, yaw: float, hp: float) -> void:
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
	p.yaw = yaw; p.hp = clampf(hp, 0.0, 1.0); p.t = now

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
		if oid != id and players[oid].authed and players[oid].zone == p.zone:
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
	p.data = c; p.dirty = true

func _srv_flush(p: Dictionary, force := false) -> void:
	if not p.dirty: return
	if not force and _now() - float(p.save_t) < SAVE_FLUSH: return
	p.dirty = false; p.save_t = _now()
	var c: Dictionary = p.data
	c["pos"] = [p.pos.x, p.pos.y, p.pos.z]
	var d := await _srv_http(HTTPClient.METHOD_PUT, "/internal/characters/" + p.char_id, {"account_id": p.acc, "data": c})
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
			data.append_array([p.pos.x, p.pos.y, p.pos.z, p.yaw, p.hp]); zones.append(p.zone)
		if ids.size() > 1:
			for id in ids: s_snapshot.rpc_id(id, ids, data, zones)
		for id in ids: _srv_flush(players[id])
	_log_t -= delta
	if _log_t <= 0.0:
		_log_t = 300.0
		print("server: онлайн %d, память %.1f МБ" % [players.size(), OS.get_static_memory_usage() / 1048576.0])
