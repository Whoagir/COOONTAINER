extends Node
## Сетевой интеграционный тест (§14): два headless-процесса на одной машине.
##   хост:   godot --headless --path . -- --nettest --smoke            (слот 3, живёт ~40 с)
##   клиент: godot --headless --path . -- --nettest --join=127.0.0.1
## Хост: ждёт пира, спавнит вещи, ломает/льёт/жжёт, шлёт события; печатает [net] и выходит.
## Клиент: ждёт мир от хоста, проверяет игроков/вещи/снапшоты/события, печатает [net] и выходит.

const HOST_LIFETIME := 40.0
const CLIENT_LIFETIME := 30.0

var _t := 0.0
var _errors: Array[String] = []
var _events := {}
var _peer_seen := false
var _stage := 0
var _spawned: Array = []


static func wanted() -> bool:
	return OS.get_cmdline_user_args().has("--nettest")


static func join_address() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--join="):
			return a.substr(7)
	return ""


func _ready() -> void:
	Net.net_event.connect(func(kind: String, _d: Dictionary): _events[kind] = int(_events.get(kind, 0)) + 1)
	Net.peer_joined.connect(func(id: int):
		_peer_seen = true
		print("[net] peer joined %d" % id))
	Net.peer_left.connect(func(id: int): print("[net] peer left %d" % id))
	Net.connection_failed.connect(func(): _fail("connection failed"))
	Net.host_left.connect(func(): print("[net] host left"))
	print("[net] start role=%s" % ("host" if Net.is_host() else "client"))


func _fail(s: String) -> void:
	_errors.append(s)
	printerr("[net] FAIL " + s)


func _ok(name: String, cond: bool, info: String = "") -> void:
	if cond:
		print("[net] PASS %s %s" % [name, info])
	else:
		_fail("%s %s" % [name, info])


func _process(delta: float) -> void:
	_t += delta
	if Net.is_host():
		_host_tick()
	else:
		_client_tick()


# ------------------------------------------------------------------ хост

func _host_tick() -> void:
	match _stage:
		0:
			if _peer_seen or _t > 25.0:
				_stage = 1
				_stage_mark = _t
				_ok("host_peer", _peer_seen, "players=%d" % Net.players.size())
				var p: Player = Game.world.local_player()
				var i := 0
				for def in Registry.all_items():
					if i >= 40:
						break
					var b = Net.spawn_item(def.id, Transform3D(Basis(), p.global_position + Vector3(-4 + (i % 8), 1.5, 3 + (i / 8))))
					if b:
						_spawned.append(b)
					i += 1
				print("[net] host spawned %d items" % _spawned.size())
		1:
			if _t > 30.0 or (_peer_seen and _stage_since() > 3.0):
				_stage = 2
				_stage_mark = _t
				var n := 0
				for b in _spawned:
					if not is_instance_valid(b):
						continue
					n += 1
					if n % 4 == 0 and b.def.is_fragile():
						b.shatter()
					elif n % 5 == 0 and b.def.liquid_id != Types.LiquidId.NONE:
						b.is_open = true
						b.spill(0.5)
					elif n % 6 == 0 and b.is_flammable():
						b.ignite()
				Game.notify.emit("net test toast", 2.0)
				Economy.add(123, "nettest")
				var p: Player = Game.world.local_player()
				if p and _spawned.size() > 0 and is_instance_valid(_spawned[0]):
					p.hands.host_grab(_spawned[0], 0)
				print("[net] host stress done")
		2:
			if _stage_since() > 4.0:
				_stage = 3
				var remote := 0
				for pid in Net.players:
					if pid != Net.my_id() and is_instance_valid(Net.players[pid]):
						remote += 1
				_ok("host_remote_players", not _peer_seen or remote >= 1, "remote=%d" % remote)
		3:
			if _t > HOST_LIFETIME:
				_finish("host")


var _stage_mark := 0.0


func _stage_since() -> float:
	return _t - _stage_mark


# ------------------------------------------------------------------ клиент

func _client_tick() -> void:
	match _stage:
		0:
			if Net.players.size() >= 2 and Game.world.local_player() != null:
				_stage = 1
				_stage_mark = _t
				_ok("client_connected", true, "my_id=%d players=%d" % [Net.my_id(), Net.players.size()])
			elif _t > 20.0:
				_fail("client never saw 2 players (players=%d, id=%d)" % [Net.players.size(), Net.my_id()])
				_finish("client")
		1:
			if _stage_since() > 12.0:
				_stage = 2
				_stage_mark = _t
				_ok("client_items", Net.items.size() >= 30, "items=%d" % Net.items.size())
				var proxies := 0
				var moving := 0
				for nid in Net.items:
					var b = Net.items[nid]
					if is_instance_valid(b):
						if b.proxy:
							proxies += 1
						if b.global_position.length() > 0.01:
							moving += 1
				_ok("client_proxies", proxies == Net.items.size(), "proxies=%d/%d placed=%d" % [proxies, Net.items.size(), moving])
				_ok("client_pot", Economy.pot >= 123, "pot=%d" % Economy.pot)
				var kinds := _events.keys()
				kinds.sort()
				print("[net] events seen: %s" % str(_events))
				_ok("client_events", _events.size() >= 2, "%d kinds" % _events.size())
				var host_p: Player = Net.players.get(1)
				_ok("client_host_player", host_p != null and is_instance_valid(host_p) and not host_p.is_local(), str(host_p.global_position.round() if host_p else "-"))
				# клиент просит хост взять вещь — должен прийти hands-ивент
				var any: ItemBody = null
				for nid in Net.items:
					var b = Net.items[nid]
					if is_instance_valid(b) and b.nested_in == null:
						any = b
						break
				if any:
					var me: Player = Game.world.local_player()
					me.global_position = any.global_position + Vector3(0, 0.2, 0.8)
					print("[net] client sends pin action (is_host=%s, id=%d)" % [str(Net.is_host()), Net.my_id()])
					Net.request_action("pin", {"pos": any.global_position})
				else:
					_fail("client found no top-level item to pin")
		2:
			if _stage_since() > 4.0 or _t > CLIENT_LIFETIME:
				_ok("client_pin_event", _events.has("pin"), str(_events.get("pin", 0)))
				_finish("client")


func _finish(role: String) -> void:
	set_process(false)
	print("[net] %s events: %s" % [role, str(_events)])
	print("[net] %s DONE errors=%d" % [role, _errors.size()])
	for e in _errors:
		printerr("[net]   " + e)
	load("res://tools/Smoke.gd").cleanup_test_slot()
	get_tree().quit(1 if _errors.size() > 0 else 0)
