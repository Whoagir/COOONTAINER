extends Node
## Listen server, хост-авторитет (§14).
##   клиент → хост: input(транcформ игрока), grab, bid, use, voice
##   хост   → клиент: snapshot(id, xform, vel), events(break, puddle, ignite, death, hammer…)
## Клиент интерполирует; большая ошибка → телепорт + хлюп.
## Соло = тот же билд: без peer'а multiplayer.is_server() == true.

signal peer_joined(id: int)
signal peer_left(id: int)
signal connected_to_host()
signal connection_failed()
signal host_left()
signal item_spawned(body: Node)
signal item_despawned(net_id: int)
signal net_event(kind: String, data: Dictionary)
signal lobby_ready(code: String) # код/адрес для приглашения

const PORT := 27015
const MAX_PLAYERS := 4
const SNAPSHOT_EVERY_TICKS := 2 # 30 Hz физика → 15 Hz снапшоты
const TELEPORT_ERROR := 2.5

var players: Dictionary = {} # peer_id → Player
var items: Dictionary = {} # net_id → ItemBody
var _next_net_id: int = 1
var _tick: int = 0
var active := false
var using_steam := false
var lobby_id: int = 0
var local_peer_id: int = 1
var listen_port: int = PORT


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_host() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()


func my_id() -> int:
	return multiplayer.get_unique_id() if multiplayer.multiplayer_peer else 1


func peer_count() -> int:
	return players.size()


# ------------------------------------------------------------------ hosting / joining

func host() -> void:
	shutdown_peer_only()
	var made := false
	listen_port = PORT
	if SteamBoot.enabled and ClassDB.class_exists("SteamMultiplayerPeer"):
		var sp = ClassDB.instantiate("SteamMultiplayerPeer")
		if sp and sp.has_method("create_host"):
			var err: int = sp.create_host(0)
			if err == OK:
				multiplayer.multiplayer_peer = sp
				using_steam = true
				made = true
				SteamBoot.create_lobby(MAX_PLAYERS)
	if not made:
		# сначала проверяем UDP-порт — иначе create_server орёт красным ERROR в Output
		var bind_port := _first_free_enet_port()
		if bind_port < 0:
			push_warning("[Net] no free UDP port near %d — solo offline" % PORT)
			multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		else:
			var enet := ENetMultiplayerPeer.new()
			var err := enet.create_server(bind_port, MAX_PLAYERS - 1)
			if err != OK:
				push_warning("[Net] ENet server failed (%d) on %d — solo offline" % [err, bind_port])
				multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
			else:
				multiplayer.multiplayer_peer = enet
				listen_port = bind_port
				if bind_port != PORT:
					push_warning("[Net] LAN host on port %d (default %d busy)" % [bind_port, PORT])
				lobby_ready.emit(_local_ip_hint())
	active = true
	local_peer_id = 1
	_spawn_player_everywhere(1)


func _first_free_enet_port() -> int:
	## Не зовём create_server на занятый порт — Godot пишет красный ERROR в Output.
	for p in range(PORT, PORT + 8):
		var udp := PacketPeerUDP.new()
		var err := udp.bind(p)
		udp.close()
		if err == OK:
			return p
	return -1


func join(address: String) -> void:
	shutdown_peer_only()
	var ok := false
	if SteamBoot.enabled and address.is_valid_int() and ClassDB.class_exists("SteamMultiplayerPeer"):
		var sp = ClassDB.instantiate("SteamMultiplayerPeer")
		lobby_id = int(address)
		SteamBoot.join_lobby(lobby_id)
		await SteamBoot.lobby_joined
		var owner_id: int = SteamBoot.lobby_owner(lobby_id)
		if sp and sp.has_method("create_client") and sp.create_client(owner_id, 0) == OK:
			multiplayer.multiplayer_peer = sp
			using_steam = true
			ok = true
	if not ok:
		var enet := ENetMultiplayerPeer.new()
		var host_addr := address if address != "" else "127.0.0.1"
		var port := PORT
		if ":" in host_addr:
			var parts := host_addr.split(":")
			host_addr = parts[0]
			port = int(parts[1])
		var err := enet.create_client(host_addr, port)
		if err != OK:
			connection_failed.emit()
			return
		multiplayer.multiplayer_peer = enet
	active = true


func shutdown_peer_only() -> void:
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	using_steam = false


func shutdown() -> void:
	shutdown_peer_only()
	if using_steam:
		SteamBoot.leave_lobby()
	players.clear()
	items.clear()
	_next_net_id = 1
	active = false


func _local_ip_hint() -> String:
	var port := listen_port if listen_port > 0 else PORT
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.") or ip.begins_with("10.") or ip.begins_with("172."):
			return "%s:%d" % [ip, port]
	return "127.0.0.1:%d" % port


# ------------------------------------------------------------------ peers

func _on_peer_connected(id: int) -> void:
	if not is_host():
		return
	# новому пиру — полный стейт мира
	_rpc_world_mode.rpc_id(id, Game.world_mode)
	_rpc_pot.rpc_id(id, Economy.pot, 0, "sync")
	for pid in players:
		_rpc_spawn_player.rpc_id(id, pid)
	for nid in items:
		var b = items[nid]
		if is_instance_valid(b):
			_rpc_spawn_item.rpc_id(id, nid, b.def.id, b.global_transform, b.state_dict(), b.parent_net_id())
	if Game.world and Game.world.has_method("send_full_state_to"):
		Game.world.send_full_state_to(id)
	_spawn_player_everywhere(id)
	peer_joined.emit(id)
	Game.notify.emit(tr("NOTIFY_FRIEND_JOINED"), 3.0)
	if players.size() >= 4:
		Achievements.unlock("full_party")


func _on_peer_disconnected(id: int) -> void:
	if players.has(id):
		var p = players[id]
		if is_instance_valid(p):
			p.queue_free()
		players.erase(id)
	peer_left.emit(id)


func _on_connected_to_server() -> void:
	local_peer_id = multiplayer.get_unique_id()
	connected_to_host.emit()


func _on_connection_failed() -> void:
	connection_failed.emit()
	Game.notify.emit(tr("NOTIFY_CONNECTION_FAILED"), 4.0)


func _on_server_disconnected() -> void:
	# §14: хост вылетел — ClearOut/Auction сдохли, слот мира жив у хоста.
	host_left.emit()
	Game.notify.emit(tr("NOTIFY_HOST_LEFT"), 5.0)
	await get_tree().create_timer(2.0).timeout
	Game.back_to_menu()


func _spawn_player_everywhere(id: int) -> void:
	_rpc_spawn_player.rpc(id)
	_rpc_spawn_player(id)


@rpc("authority", "call_remote", "reliable")
func _rpc_spawn_player(id: int) -> void:
	if players.has(id) or Game.world == null:
		return
	var p = Game.world.spawn_player(id)
	if p:
		players[id] = p


# ------------------------------------------------------------------ player state (client → host → all)

func send_player_state(pos: Vector3, yaw: float, pitch: float, flags: int) -> void:
	if not active or players.size() <= 1:
		return
	_rpc_player_state.rpc(my_id(), pos, yaw, pitch, flags)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_player_state(id: int, pos: Vector3, yaw: float, pitch: float, flags: int) -> void:
	var p = players.get(id)
	if p and is_instance_valid(p) and p.has_method("apply_remote_state"):
		p.apply_remote_state(pos, yaw, pitch, flags)


# ------------------------------------------------------------------ items

func register_local_item(body: Node) -> int:
	var nid := _next_net_id
	_next_net_id += 1
	items[nid] = body
	return nid


## Хост: создать вещь и разослать. Возвращает ItemBody (или null на клиенте).
func spawn_item(item_id: String, xform: Transform3D, state: Dictionary = {}, parent_net_id: int = 0) -> Node:
	if not is_host():
		return null
	var def := Registry.item(item_id)
	if def == null:
		push_warning("[Net] spawn unknown item %s" % item_id)
		return null
	var body = ItemBody.create(def)
	var nid := register_local_item(body)
	body.net_id = nid
	body.apply_state(state)
	var root := _items_root()
	if root == null:
		return null
	root.add_child(body)
	body.global_transform = xform
	if parent_net_id != 0 and items.has(parent_net_id):
		items[parent_net_id].nest_child(body)
	_rpc_spawn_item.rpc(nid, item_id, xform, state, parent_net_id)
	item_spawned.emit(body)
	return body


func _items_root() -> Node:
	if Game.world and Game.world.has_method("items_root"):
		return Game.world.items_root()
	return Game.world


@rpc("authority", "call_remote", "reliable")
func _rpc_spawn_item(nid: int, item_id: String, xform: Transform3D, state: Dictionary, parent_net_id: int) -> void:
	if items.has(nid):
		return
	var def := Registry.item(item_id)
	if def == null:
		return
	var body = ItemBody.create(def)
	body.net_id = nid
	body.set_proxy(true)
	items[nid] = body
	var root := _items_root()
	if root == null:
		return
	root.add_child(body)
	body.global_transform = xform
	body.apply_state(state)
	if parent_net_id != 0 and items.has(parent_net_id):
		items[parent_net_id].nest_child(body)
	item_spawned.emit(body)


func despawn_item(nid: int) -> void:
	if not is_host():
		return
	_despawn_local(nid)
	_rpc_despawn_item.rpc(nid)


@rpc("authority", "call_remote", "reliable")
func _rpc_despawn_item(nid: int) -> void:
	_despawn_local(nid)


func _despawn_local(nid: int) -> void:
	var b = items.get(nid)
	items.erase(nid)
	if b and is_instance_valid(b):
		b.queue_free()
	item_despawned.emit(nid)


func sync_item_state(body: Node) -> void:
	if not is_host() or players.size() <= 1:
		return
	_rpc_item_state.rpc(body.net_id, body.state_dict())


@rpc("authority", "call_remote", "reliable")
func _rpc_item_state(nid: int, state: Dictionary) -> void:
	var b = items.get(nid)
	if b and is_instance_valid(b):
		b.apply_state(state)


func sync_item_parent(body: Node, parent_nid: int) -> void:
	if not is_host() or players.size() <= 1:
		return
	_rpc_item_parent.rpc(body.net_id, parent_nid)


@rpc("authority", "call_remote", "reliable")
func _rpc_item_parent(nid: int, parent_nid: int) -> void:
	var b = items.get(nid)
	if b == null or not is_instance_valid(b):
		return
	if parent_nid == 0:
		b.unnest()
	elif items.has(parent_nid):
		items[parent_nid].nest_child(b)


# ------------------------------------------------------------------ snapshots

func _physics_process(_delta: float) -> void:
	if not active or not is_host() or players.size() <= 1:
		return
	_tick += 1
	if _tick % SNAPSHOT_EVERY_TICKS != 0:
		return
	var buf := StreamPeerBuffer.new()
	var count := 0
	buf.put_u32(0)
	for nid in items:
		var b = items[nid]
		if not is_instance_valid(b) or b.sleeping or b.freeze or b.nested_in != null:
			continue
		var t: Transform3D = b.global_transform
		var q: Quaternion = t.basis.get_rotation_quaternion()
		var v: Vector3 = b.linear_velocity
		buf.put_u32(nid)
		buf.put_float(t.origin.x); buf.put_float(t.origin.y); buf.put_float(t.origin.z)
		buf.put_16(int(clampf(q.x, -1, 1) * 32767)); buf.put_16(int(clampf(q.y, -1, 1) * 32767))
		buf.put_16(int(clampf(q.z, -1, 1) * 32767)); buf.put_16(int(clampf(q.w, -1, 1) * 32767))
		buf.put_16(int(clampf(v.x, -300, 300) * 100)); buf.put_16(int(clampf(v.y, -300, 300) * 100))
		buf.put_16(int(clampf(v.z, -300, 300) * 100))
		count += 1
		if count >= 220:
			break
	if count == 0:
		return
	buf.seek(0)
	buf.put_u32(count)
	_rpc_snapshot.rpc(buf.data_array)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_snapshot(data: PackedByteArray) -> void:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	var count := buf.get_u32()
	for i in count:
		var nid := buf.get_u32()
		var pos := Vector3(buf.get_float(), buf.get_float(), buf.get_float())
		var q := Quaternion(buf.get_16() / 32767.0, buf.get_16() / 32767.0, buf.get_16() / 32767.0, buf.get_16() / 32767.0).normalized()
		var vel := Vector3(buf.get_16() / 100.0, buf.get_16() / 100.0, buf.get_16() / 100.0)
		var b = items.get(nid)
		if b and is_instance_valid(b):
			b.apply_snapshot(pos, q, vel)


# ------------------------------------------------------------------ requests (client → host)

func request_grab(nid: int, hand: int) -> void:
	if is_host():
		_rpc_request_grab(my_id(), nid, hand)
	else:
		_rpc_request_grab.rpc_id(1, my_id(), nid, hand)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_grab(peer: int, nid: int, hand: int) -> void:
	if not is_host():
		return
	var p = players.get(peer)
	var b = items.get(nid)
	if p and b and is_instance_valid(b):
		p.hands.host_grab(b, hand)


func request_release(hand: int, throw_force: float) -> void:
	if is_host():
		_rpc_request_release(my_id(), hand, throw_force)
	else:
		_rpc_request_release.rpc_id(1, my_id(), hand, throw_force)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_release(peer: int, hand: int, throw_force: float) -> void:
	if not is_host():
		return
	var p = players.get(peer)
	if p:
		p.hands.host_release(hand, throw_force)


func request_use(nid: int, mode: int = 0) -> void:
	if is_host():
		_rpc_request_use(my_id(), nid, mode)
	else:
		_rpc_request_use.rpc_id(1, my_id(), nid, mode)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_use(peer: int, nid: int, mode: int) -> void:
	if not is_host():
		return
	var p = players.get(peer)
	var b = items.get(nid)
	if p and b and is_instance_valid(b):
		b.host_use(p, mode)


## Универсальный запрос игрока к миру: "bid", "paddle", "interact", "haggle", "casino_bet", "buy_car", ...
func request_action(kind: String, data: Dictionary = {}) -> void:
	if is_host():
		_rpc_request_action(my_id(), kind, data)
	else:
		_rpc_request_action.rpc_id(1, my_id(), kind, data)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_action(peer: int, kind: String, data: Dictionary) -> void:
	if not is_host():
		return
	if Game.world and Game.world.has_method("handle_action"):
		Game.world.handle_action(peer, kind, data)


# ------------------------------------------------------------------ broadcasts (host → all)

func broadcast_event(kind: String, data: Dictionary = {}) -> void:
	if not is_host():
		return
	_rpc_event(kind, data)
	if players.size() > 1:
		_rpc_event.rpc(kind, data)


## Событие одному пиру. Себе (хост в одиночке или хост-игрок) — напрямую:
## rpc_id на собственный id при call_remote — ошибка ERR_INVALID_PARAMETER.
func send_event(peer: int, kind: String, data: Dictionary = {}) -> void:
	if not is_host():
		return
	if peer == my_id() or players.size() <= 1:
		_rpc_event(kind, data)
	else:
		_rpc_event.rpc_id(peer, kind, data)


@rpc("authority", "call_remote", "reliable")
func _rpc_event(kind: String, data: Dictionary) -> void:
	net_event.emit(kind, data)
	if Game.world and Game.world.has_method("on_net_event"):
		Game.world.on_net_event(kind, data)


func broadcast_pot(v: int, delta: int, reason: String) -> void:
	if players.size() > 1:
		_rpc_pot.rpc(v, delta, reason)


@rpc("authority", "call_remote", "reliable")
func _rpc_pot(v: int, delta: int, reason: String) -> void:
	Economy.set_pot(v, reason)


func broadcast_world_mode(m: int) -> void:
	if players.size() > 1:
		_rpc_world_mode.rpc(m)


@rpc("authority", "call_remote", "reliable")
func _rpc_world_mode(m: int) -> void:
	Game.set_world_mode(m)


## Голос (§14): сырые семплы, unreliable, мимо физики. Steam Voice — в Voice.gd, тут транспорт-фоллбек.
func send_voice(data: PackedByteArray) -> void:
	if players.size() <= 1:
		return
	_rpc_voice.rpc(my_id(), data)


@rpc("any_peer", "call_remote", "unreliable")
func _rpc_voice(peer: int, data: PackedByteArray) -> void:
	Voice.receive(peer, data)
