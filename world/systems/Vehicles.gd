class_name Vehicles
extends Node3D
## Тачки (§10, §12, §13): реестр vid → Vehicle, спавн/деспавн, авторынок (витрина CarSlot0..2 + барыга),
## угоняемые чужие тачки у районов, ввод водителя по сети, veh_state ~10 Гц, сейв купленных.
## Хост считает; клиент просит (drive / veh_enter / veh_exit / veh_buy / veh_horn).

const STATE_SEND_SEC := 0.1
const DISPLAY_RESPAWN_SEC := 10.0
const DISPLAY_RETRY_SEC := 5.0
const THEFT_POLICE_SEC := 5.0
const DISPLAY_TYPES := ["pickup_rusty", "van_leaky", "truck_fat"]
const FALLBACK_MARKET := Vector3(22, 0, 12)
const FALLBACK_DEALER := Vector3(22, 0, 5)
const FALLBACK_NPC_CARS := [Vector3(-22, 0, 14), Vector3(-22, 0, 22), Vector3(-29, 0, 18)]
## Чужие тачки: район, смещение от корня района, тип.
const NPC_CARS := [
	[Types.District.STORAGE, Vector3(9, 0, 9), "pickup_rusty"],
	[Types.District.GARAGES, Vector3(-9, 0, 9), "van_leaky"],
	[Types.District.PORT, Vector3(10, 0, -8), "pickup_rusty"],
]

var vehicles: Dictionary = {} # vid → Vehicle
var dealer: CarDealer = null
var _next_vid := 1
var _state_t := 0.0
var _display: Dictionary = {} # slot → {"vid": int, "t": float}
var _thefts: Array = [] # {vid, peer, t}
var _host := false


func system_name() -> String:
	return "Vehicles"


func _ready() -> void:
	Net.peer_left.connect(_on_peer_left)
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree() or Game.world == null:
		return
	_spawn_dealer()
	_host = Game.pending_host and Net.is_host()
	if _host:
		_spawn_display_cars()
		_spawn_npc_cars()


# ------------------------------------------------------------------ маркеры / позиции

func _marker(d: int, name: String) -> Node3D:
	return Game.world.find_marker(d, name) if Game.world else null


func _slot_xform(i: int) -> Transform3D:
	var m := _marker(Types.District.CAR_MARKET, "CarSlot%d" % i)
	if m:
		return Transform3D(Basis(Vector3.UP, m.global_basis.get_euler().y), m.global_position + Vector3(0, 0.15, 0))
	return Transform3D(Basis(), FALLBACK_MARKET + Vector3(i * 4.5, 0.15, 0))


## Ближайшая «дорожная» точка: корень ближайшего района (+ смещение) — чтоб не soft-lock в воде.
func road_point_near(pos: Vector3) -> Vector3:
	var best := Vector3(0, 0.5, 6)
	var best_d := 1e9
	if Game.world and Game.world.city and Game.world.city.has_method("districts"):
		for d in Game.world.city.districts():
			var dd: float = d.global_position.distance_to(pos)
			if dd < best_d:
				best_d = dd
				best = d.global_position + Vector3(4, 0.5, 4)
	return best


# ------------------------------------------------------------------ спавн

func _instantiate(type: String, proxy: bool) -> Vehicle:
	var info := Vehicle.type_info(type)
	var scene: PackedScene = load(info["scene"])
	var v: Vehicle = scene.instantiate()
	v.set_proxy(proxy)
	return v


## Хост: создать тачку и разослать.
func spawn(type: String, xform: Transform3D, owner_slot := false, display := false, npc_owned := false, vid := 0) -> Vehicle:
	if not Net.is_host():
		return null
	if not Vehicle.TYPES.has(type):
		type = "pickup_rusty"
	var v := _instantiate(type, false)
	if vid == 0:
		vid = _next_vid
	_next_vid = maxi(_next_vid, vid + 1)
	v.vid = vid
	v.owner_slot = owner_slot
	v.display = display
	v.npc_owned = npc_owned
	v.price = int(Vehicle.type_info(type)["price"])
	v.sys = self
	v.name = "Veh_%d_%s" % [vid, type]
	add_child(v)
	v.global_transform = xform
	v.reset_physics_interpolation()
	vehicles[vid] = v
	Net.broadcast_event("veh_spawn", _spawn_data(v))
	return v


func _spawn_data(v: Vehicle) -> Dictionary:
	return {"vid": v.vid, "type": v.vtype, "xf": v.global_transform, "owner": v.owner_slot, "display": v.display, "npc": v.npc_owned, "price": v.price}


func _spawn_proxy(d: Dictionary) -> void:
	var vid := int(d.get("vid", 0))
	if vid == 0 or vehicles.has(vid):
		return
	var v := _instantiate(str(d.get("type", "pickup_rusty")), true)
	v.vid = vid
	v.owner_slot = bool(d.get("owner", false))
	v.display = bool(d.get("display", false))
	v.npc_owned = bool(d.get("npc", false))
	v.price = int(d.get("price", 0))
	v.sys = self
	v.name = "Veh_%d_%s" % [vid, v.vtype]
	add_child(v)
	v.global_transform = d.get("xf", Transform3D())
	v.reset_physics_interpolation()
	vehicles[vid] = v


func despawn(vid: int) -> void:
	if not Net.is_host():
		return
	_despawn_local(vid)
	Net.broadcast_event("veh_despawn", {"vid": vid})


func _despawn_local(vid: int) -> void:
	var v: Vehicle = vehicles.get(vid)
	vehicles.erase(vid)
	if v and is_instance_valid(v):
		for seat in 2:
			var peer := v.seat_peer(seat)
			if peer != 0:
				var p: Player = Net.players.get(peer)
				if p and is_instance_valid(p) and p.in_vehicle == v:
					v.release_player(p, v.exit_position(seat))
		v.queue_free()


func vehicle(vid: int) -> Vehicle:
	var v: Vehicle = vehicles.get(vid)
	return v if v and is_instance_valid(v) else null


func vehicle_of(player: Player) -> Vehicle:
	return player.in_vehicle if player and player.in_vehicle is Vehicle else null


# ------------------------------------------------------------------ авторынок

func _spawn_dealer() -> void:
	if Game.world == null or Game.world.npcs_root == null:
		return
	if Game.world.npcs_root.get_node_or_null("CarDealer"):
		return
	dealer = CarDealer.new()
	dealer.name = "CarDealer"
	Game.world.npcs_root.add_child(dealer)
	var spot := _marker(Types.District.CAR_MARKET, "DealerSpot")
	dealer.global_position = spot.global_position if spot else FALLBACK_DEALER
	dealer.face(_slot_xform(1).origin)


func _spawn_display_cars() -> void:
	for i in DISPLAY_TYPES.size():
		var v := spawn(DISPLAY_TYPES[i], _slot_xform(i), false, true, false)
		_display[i] = {"vid": v.vid if v else 0, "t": 0.0}


func _spawn_npc_cars() -> void:
	var i := 0
	for entry in NPC_CARS:
		var root: Node3D = Game.world.district_root(int(entry[0]))
		var pos: Vector3
		var yaw := 0.0
		if root:
			pos = root.global_position + entry[1]
			yaw = randf() * TAU
		else:
			pos = FALLBACK_NPC_CARS[i % FALLBACK_NPC_CARS.size()]
			yaw = PI * 0.5 * i
		spawn(str(entry[2]), Transform3D(Basis(Vector3.UP, yaw), pos + Vector3(0, 0.15, 0)), false, false, true)
		i += 1


func _slot_clear(i: int) -> bool:
	var pos := _slot_xform(i).origin
	for v in vehicles.values():
		if is_instance_valid(v) and v.global_position.distance_to(pos) < 3.5:
			return false
	return true


func display_vehicle(slot: int) -> Vehicle:
	var d: Dictionary = _display.get(slot, {})
	return vehicle(int(d.get("vid", 0)))


# ------------------------------------------------------------------ хост: посадка / покупка

func host_enter(p: Player, v: Vehicle, seat: int) -> void:
	if not Net.is_host() or p == null or v == null or not is_instance_valid(v):
		return
	if p.dead or p.cuffed or p.in_custody:
		return
	if v.display:
		host_buy(p, v)
		return
	if p.in_vehicle:
		host_exit(p)
	if seat == -1 or v.seat_peer(seat) != 0:
		seat = Vehicle.SEAT_DRIVER if v.driver_peer == 0 else (Vehicle.SEAT_PASSENGER if v.passenger_peer == 0 else -1)
	if seat == -1:
		p.say(tr("VEH_FULL"))
		return
	# водитель бросает всё; пассажир может везти одну не-TEAM вещь на коленях («ремень», §10)
	var lap: ItemBody = null
	if seat == Vehicle.SEAT_PASSENGER:
		var h: ItemBody = p.hands.any_held()
		if h and h.arch.size_class != Types.SizeClass.TEAM and h.arch.size_class != Types.SizeClass.VEHICLE:
			lap = h
	for i in 2:
		var b: ItemBody = p.hands.held[i] if is_instance_valid(p.hands.held[i]) else null
		if b and b != lap:
			p.hands.host_release_body(b)
	if lap:
		lap.freeze = true
		lap.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		lap.set_meta("lap_of", p.peer_id)
	v.set_seat(seat, p.peer_id)
	v.seat_player(p, seat)
	Net.broadcast_event("veh_seat", {"vid": v.vid, "peer": p.peer_id, "seat": seat, "on": true})
	AudioBus.play_at("door_slam", v.global_position, -2.0)
	if seat == Vehicle.SEAT_DRIVER and v.npc_owned and not v.stolen:
		_on_theft(p, v)


func host_exit(p: Player) -> void:
	if not Net.is_host() or p == null:
		return
	var v := vehicle_of(p)
	if v == null:
		p.in_vehicle = null
		return
	var seat := v.seat_of(p.peer_id)
	if seat == -1:
		seat = Vehicle.SEAT_DRIVER
	var pos := v.exit_position(seat)
	v.set_seat(seat, 0)
	v.release_player(p, pos)
	# вещь с коленей снова физическая и остаётся в руках
	for i in 2:
		var b: ItemBody = p.hands.held[i] if is_instance_valid(p.hands.held[i]) else null
		if b and b.get_meta("lap_of", 0) == p.peer_id:
			b.remove_meta("lap_of")
			b.freeze = false
			b.global_position = pos + Vector3(0, 1.2, 0)
	Net.broadcast_event("veh_seat", {"vid": v.vid, "peer": p.peer_id, "seat": seat, "on": false, "pos": pos})
	AudioBus.play_at("door_slam", v.global_position, -2.0)


## Освободить сиденье без игрока (пир вышел / тело пропало).
func host_vacate(v: Vehicle, seat: int) -> void:
	if not Net.is_host() or v == null:
		return
	var peer := v.seat_peer(seat)
	if peer == 0:
		return
	v.set_seat(seat, 0)
	Net.broadcast_event("veh_seat", {"vid": v.vid, "peer": peer, "seat": seat, "on": false, "pos": v.exit_position(seat)})


func host_buy(p: Player, v: Vehicle) -> bool:
	if not Net.is_host() or p == null or v == null or not v.display:
		return false
	if not Economy.try_spend(v.price, "car"):
		AudioBus.play_at("buzzer", v.global_position, 0.0)
		p.say(tr("VEH_TOO_POOR") % (v.price - Economy.pot))
		if dealer:
			dealer.say_poor()
		return false
	v.set_bought()
	Net.broadcast_event("veh_bought", {"vid": v.vid})
	AudioBus.play_at("cash_register", v.global_position, 2.0)
	p.say(tr("VEH_BOUGHT"))
	Game.stat_add("cars_bought")
	Achievements.unlock("first_car")
	if dealer:
		dealer.say_sell()
	for slot in _display:
		if int(_display[slot]["vid"]) == v.vid:
			_display[slot] = {"vid": 0, "t": DISPLAY_RESPAWN_SEC}
	return true


func _on_theft(p: Player, v: Vehicle) -> void:
	v.stolen = true
	Game.stat_add("cars_stolen")
	Achievements.unlock("car_thief")
	p.say(tr("VEH_STOLEN_NOTIFY"))
	if dealer and dealer.global_position.distance_to(v.global_position) < 40.0:
		dealer.say_theft()
	_thefts.append({"vid": v.vid, "peer": p.peer_id, "t": THEFT_POLICE_SEC})


# ------------------------------------------------------------------ действия / события

func handle_action(peer: int, kind: String, data: Dictionary) -> bool:
	match kind:
		"drive":
			var v := vehicle(int(data.get("vid", 0)))
			if v and v.driver_peer == peer:
				v.apply_input(float(data.get("steer", 0.0)), float(data.get("throttle", 0.0)), float(data.get("brake", 0.0)), bool(data.get("hb", false)))
			return true
		"veh_enter":
			var v := vehicle(int(data.get("vid", 0)))
			var p: Player = Net.players.get(peer)
			if v and p and v.global_position.distance_to(p.global_position) < 6.0:
				host_enter(p, v, int(data.get("seat", -1)))
			return true
		"veh_exit":
			var p: Player = Net.players.get(peer)
			if p:
				host_exit(p)
			return true
		"veh_buy":
			var v := vehicle(int(data.get("vid", 0)))
			var p: Player = Net.players.get(peer)
			if v and p and v.global_position.distance_to(p.global_position) < 6.0:
				host_buy(p, v)
			return true
		"veh_horn":
			var v := vehicle(int(data.get("vid", 0)))
			if v and v.driver_peer == peer:
				Net.broadcast_event("veh_horn", {"vid": v.vid, "pos": v.global_position})
			return true
	return false


func on_net_event(kind: String, data: Dictionary) -> void:
	match kind:
		"veh_spawn":
			if not Net.is_host():
				_spawn_proxy(data)
		"veh_despawn":
			if not Net.is_host():
				_despawn_local(int(data.get("vid", 0)))
		"veh_state":
			if not Net.is_host():
				var v := vehicle(int(data.get("vid", 0)))
				if v:
					v.apply_state(data.get("xf", Transform3D()), data.get("lv", Vector3.ZERO), data.get("av", Vector3.ZERO), float(data.get("st", 0.0)))
		"veh_seat":
			if not Net.is_host():
				var v := vehicle(int(data.get("vid", 0)))
				var p: Player = Net.players.get(int(data.get("peer", 0)))
				if v == null:
					return
				var seat := int(data.get("seat", 0))
				if bool(data.get("on", false)):
					v.set_seat(seat, int(data.get("peer", 0)))
					if p:
						v.seat_player(p, seat)
				else:
					v.set_seat(seat, 0)
					if p:
						v.release_player(p, data.get("pos", v.exit_position(seat)))
		"veh_bought":
			if not Net.is_host():
				var v := vehicle(int(data.get("vid", 0)))
				if v:
					v.set_bought()
		"veh_horn":
			AudioBus.play_at("car_horn", data.get("pos", Vector3.ZERO), 4.0, 0.05)
		"veh_flip":
			AudioBus.play_at("bump_boing", data.get("pos", Vector3.ZERO), 2.0, 0.2)
		"veh_bump":
			AudioBus.play_at("bump_boing", data.get("pos", Vector3.ZERO), 2.0, 0.2)


func send_full_state_to(peer: int) -> void:
	for v in vehicles.values():
		if not is_instance_valid(v):
			continue
		Net.send_event(peer, "veh_spawn", _spawn_data(v))
		for seat in 2:
			var sp: int = v.seat_peer(seat)
			if sp != 0:
				Net.send_event(peer, "veh_seat", {"vid": v.vid, "peer": sp, "seat": seat, "on": true})


func _on_peer_left(id: int) -> void:
	if not Net.is_host():
		return
	for v in vehicles.values():
		if not is_instance_valid(v):
			continue
		for seat in 2:
			if v.seat_peer(seat) == id:
				host_vacate(v, seat)


# ------------------------------------------------------------------ тик хоста

func _physics_process(delta: float) -> void:
	if not _host:
		return
	_state_t += delta
	if _state_t >= STATE_SEND_SEC:
		_state_t = 0.0
		if Net.peer_count() > 1:
			for v in vehicles.values():
				if is_instance_valid(v) and v.wants_state():
					Net.broadcast_event("veh_state", v.state_data())
	for i in range(_thefts.size() - 1, -1, -1):
		var th: Dictionary = _thefts[i]
		th["t"] = float(th["t"]) - delta
		if float(th["t"]) <= 0.0:
			_thefts.remove_at(i)
			var v := vehicle(int(th["vid"]))
			var p: Player = Net.players.get(int(th["peer"]))
			var police: Node = Game.world.system("Police") if Game.world else null
			if v and police and police.has_method("trigger"):
				police.trigger(Types.PoliceTrigger.CAR_THEFT, v.global_position, p)
	for slot in _display:
		var d: Dictionary = _display[slot]
		if float(d["t"]) > 0.0:
			d["t"] = float(d["t"]) - delta
			if float(d["t"]) <= 0.0:
				if _slot_clear(int(slot)):
					var v := spawn(DISPLAY_TYPES[int(slot) % DISPLAY_TYPES.size()], _slot_xform(int(slot)), false, true, false)
					d["vid"] = v.vid if v else 0
					d["t"] = 0.0
				else:
					d["t"] = DISPLAY_RETRY_SEC


# ------------------------------------------------------------------ сейв (§15: тачки в слоте)

func collect_save() -> Array:
	var out: Array = []
	for v in vehicles.values():
		if not is_instance_valid(v) or not v.owner_slot or v.display:
			continue
		var p: Vector3 = v.global_position
		out.append({"type": v.vtype, "pos": [p.x, p.y, p.z], "yaw": v.global_basis.orthonormalized().get_euler().y, "vid": v.vid})
	return out


func spawn_from_save(list: Array) -> void:
	if not Net.is_host():
		return
	var junk := _marker(Types.District.TRAILER_PARK, "JunkYard")
	var base: Vector3 = junk.global_position if junk else Vector3(0, 0, 4)
	var i := 0
	for e in list:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = e
		var type := str(d.get("type", "pickup_rusty"))
		var arr: Array = d.get("pos", [])
		var pos := Vector3.ZERO
		var valid := arr.size() == 3
		if valid:
			pos = Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
			valid = pos.is_finite() and pos.y > -0.5 and pos.y < 100.0 and pos.length() < 1500.0
		if not valid:
			pos = base + Vector3(5.0 + i * 3.5, 0.0, 3.0)
		var yaw := float(d.get("yaw", 0.0))
		spawn(type, Transform3D(Basis(Vector3.UP, yaw), pos + Vector3(0, 0.15, 0)), true, false, false, int(d.get("vid", 0)))
		i += 1
