class_name Interactables
extends Node3D
## Мелкие интерактивы города: автоматы, таксофоны, WC, автомат с музыкой, груша, скамейки, насос.
## Хост считает; клиенты применяют `interactable` {id, kind, ...}. Подсказка — `interact_hint`.

const JUKE_TRACKS: Array[String] = ["casino_loop", "car_rock_loop", "vendor_loop", "hub_loop"]
const JUKE_KEYS: Array[String] = ["INT_JUKE_CASINO", "INT_JUKE_ROCK", "INT_JUKE_VENDOR", "INT_JUKE_HUB"]
const JUKE_COLS: Array[Color] = [
	Color(1.0, 0.22, 0.55), Color(1.0, 0.48, 0.12), Color(0.25, 0.86, 0.38), Color(0.18, 0.78, 0.92)
]
const PHONE_COOL := 20.0
const WC_COOL := 30.0
const LOT_CLEAR := 2.5
const ROAD_PAD := 1.4

class Toy extends StaticBody3D:
	var id: String = ""
	var kind: String = ""
	var sys: Interactables
	var stuck := false
	var sitting := false
	var open := false
	var track := 0
	var cool_until := 0.0
	var door: Node3D
	var swing: Node3D
	var strip: MeshInstance3D
	var score: Label3D

	func interact(player: Node) -> void:
		if sys:
			sys.host_interact(self, player)

	func interact_hint(player: Node) -> String:
		if sys:
			return sys.hint_for(self, player)
		return ""


var toys: Dictionary = {} # id → Toy
var _mats: Dictionary = {}
var _mesh_n := 0
var _drink := ""
var _loot: Array[String] = []
var _phone_i := 0
var _lot_pts: Array[Vector3] = []
var _roads: PackedVector4Array = PackedVector4Array()
var _road_half := 5.6


func system_name() -> String:
	return "Interactables"


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if Game.world == null:
		return
	_drink = _resolve_drink()
	_loot = _resolve_loot()
	_cache_blockers()
	_build_all()
	print("[Interactables] %d props" % toys.size())


func send_full_state_to(peer: int) -> void:
	for k in toys:
		var t: Toy = toys[k] as Toy
		if t == null:
			continue
		if t.kind == "vending":
			Net.send_event(peer, "interactable", {"id": t.id, "kind": "vending", "act": "sync", "stuck": t.stuck})
		elif t.kind == "jukebox":
			Net.send_event(peer, "interactable", {"id": t.id, "kind": "jukebox", "act": "sync", "track": t.track})


func on_net_event(kind: String, data: Dictionary) -> void:
	if kind != "interactable":
		return
	var t: Toy = toys.get(str(data.get("id", "")), null) as Toy
	if t == null:
		return
	match t.kind:
		"vending":
			_fx_vending(t, data)
		"phone":
			_fx_phone(t, data)
		"wc":
			_fx_wc(t, data)
		"jukebox":
			_fx_jukebox(t, data)
		"bag":
			_fx_bag(t, data)
		"bench":
			_fx_bench(t, data)
		"pump":
			_fx_pump(t, data)


func hint_for(t: Toy, _player: Node) -> String:
	var now := _now()
	match t.kind:
		"vending":
			if t.stuck:
				return tr("INT_VEND_STUCK")
			return tr("INT_VEND_HINT")
		"phone":
			if now < t.cool_until:
				return tr("INT_PHONE_WAIT")
			return tr("INT_PHONE_HINT")
		"wc":
			if now < t.cool_until:
				return tr("INT_WC_WAIT")
			return tr("INT_WC_HINT")
		"jukebox":
			return tr("INT_JUKE_HINT")
		"bag":
			return tr("INT_BAG_HINT")
		"bench":
			return tr("INT_BENCH_STAND") if t.sitting else tr("INT_BENCH_HINT")
		"pump":
			return tr("INT_PUMP_HINT")
	return ""


func host_interact(t: Toy, player: Node) -> void:
	if not Net.is_host():
		return
	match t.kind:
		"vending":
			_host_vending(t)
		"phone":
			_host_phone(t, player)
		"wc":
			_host_wc(t)
		"jukebox":
			_host_jukebox(t)
		"bag":
			_host_bag(t)
		"bench":
			_host_bench(t, player)
		"pump":
			_host_pump(t)


# ------------------------------------------------------------------ build

func _build_all() -> void:
	# автоматы: ангар у западной стены зала (в кадре art_05), площадь скупщиков, парковка казино
	_mk_vending("Vending_0", Types.District.HANGAR, "", Vector3(-20.2, 0, -7.0), Vector3(1, 0, 0))
	_mk_vending("Vending_1", Types.District.VENDORS, "Parking", Vector3(14.0, 0, -8.0), Vector3(0, 0, 1))
	_mk_vending("Vending_2", Types.District.CASINO, "Building", Vector3(-8.0, 0, -15.0), Vector3(0, 0, 1))
	# таксофоны: двор у трейлера (в кадре art_00) и участок
	_mk_phone("Phone_0", Types.District.TRAILER_PARK, "Trailer", Vector3(-7.6, 0, 8.0), Vector3(0.7, 0, -0.7))
	_mk_phone("Phone_1", Types.District.POLICE, "Parking", Vector3(5.5, 0, -9.0), Vector3(0, 0, 1))
	_mk_wc()
	_mk_jukebox()
	_mk_bag()
	_mk_bench("Bench_0", Types.District.TRAILER_PARK, "Campfire", Vector3(3.8, 0, 3.2), Vector3(-0.8, 0, -0.4))
	_mk_bench("Bench_1", Types.District.VENDORS, "Parking", Vector3(0.0, 0, 6.5), Vector3(0, 0, -1))
	_mk_bench("Bench_2", Types.District.PORT, "Office", Vector3(6.0, 0, 4.0), Vector3(-1, 0, 0))
	_mk_bench("Bench_3", Types.District.CASINO, "Building", Vector3(8.6, 0, -14.0), Vector3(0, 0, 1))
	_mk_pump()


func _mk_vending(id: String, d: int, marker: String, off: Vector3, face: Vector3) -> void:
	var t := _toy(id, "vending", d, marker, off, face, Vector3(0.95, 1.95, 0.85), Vector3(0, 0.97, 0))
	var red := _mat(Color(0.78, 0.12, 0.14), "tex_container", Color())
	var teal := _mat(Color(0.08, 0.42, 0.46), "tex_rust_teal", Color())
	var panel := _mat(Color(0.15, 0.95, 0.82), "", Color(0.2, 1.0, 0.75), 1.8)
	var chrome := _mat(Color(0.55, 0.58, 0.62), "", Color())
	_mi(t, LowPoly.chamfer_box(Vector3(0.9, 1.9, 0.8), 0.04), Vector3(0, 0.95, 0), red)
	_mi(t, LowPoly.chamfer_box(Vector3(0.92, 0.14, 0.82), 0.02), Vector3(0, 1.88, 0), teal)
	_mi(t, LowPoly.chamfer_box(Vector3(0.7, 1.05, 0.05), 0.01), Vector3(0, 1.12, 0.42), panel)
	_mi(t, LowPoly.chamfer_box(Vector3(0.18, 0.05, 0.08), 0.008), Vector3(0.22, 0.52, 0.43), chrome)
	_mi(t, LowPoly.cylinder(0.035, 0.035, 0.03, 6), Vector3(-0.18, 0.58, 0.43), teal)
	_mi(t, LowPoly.cylinder(0.035, 0.035, 0.03, 6), Vector3(-0.18, 0.48, 0.43), red)
	var lab := _label(t, Vector3(0, 1.72, 0.44), "2$", 42, Color(1.0, 0.92, 0.2))
	lab.pixel_size = 0.006


func _mk_phone(id: String, d: int, marker: String, off: Vector3, face: Vector3) -> void:
	var t := _toy(id, "phone", d, marker, off, face, Vector3(0.32, 2.15, 0.28), Vector3(0, 1.07, 0))
	var post := _mat(Color(0.22, 0.23, 0.26), "tex_corrugated", Color())
	var box := _mat(Color(0.72, 0.62, 0.38), "tex_cardboard", Color())
	var black := _mat(Color(0.08, 0.08, 0.1), "", Color())
	_mi(t, LowPoly.cylinder(0.055, 0.06, 1.55, 8), Vector3(0, 0.78, 0), post)
	_mi(t, LowPoly.chamfer_box(Vector3(0.3, 0.48, 0.2), 0.02), Vector3(0, 1.58, 0.05), box)
	_mi(t, LowPoly.capsule(0.035, 0.2, 6, 2), Vector3(0.12, 1.55, 0.14), black, Basis(Vector3.FORWARD, 0.7))
	_mi(t, LowPoly.chamfer_box(Vector3(0.12, 0.1, 0.02), 0.004), Vector3(0, 1.5, 0.15), black)
	_label(t, Vector3(0, 1.95, 0.12), "☎", 36, Color(0.95, 0.85, 0.2))


func _mk_wc() -> void:
	var potty: Node3D = Game.world.find_marker(Types.District.TRAILER_PARK, "PortaPotty")
	var t := _toy("WC_0", "wc", Types.District.TRAILER_PARK, "PortaPotty", Vector3.ZERO, Vector3(0, 0, 1), Vector3(0.95, 2.1, 0.16), Vector3(0, 1.05, 0))
	if potty:
		t.global_basis = potty.global_basis
		t.global_position = potty.global_position + potty.global_basis * Vector3(0, 0, 0.62)
	var door := Node3D.new()
	door.name = "Door"
	door.position = Vector3(-0.4, 0, 0)
	t.add_child(door)
	t.door = door
	var blue := _mat(Color(0.18, 0.42, 0.88), "tex_container", Color())
	var dark := _mat(Color(0.12, 0.14, 0.18), "", Color())
	_mi(door, LowPoly.chamfer_box(Vector3(0.82, 1.85, 0.05), 0.015), Vector3(0.4, 1.05, 0), blue)
	_mi(door, LowPoly.chamfer_box(Vector3(0.08, 0.04, 0.08), 0.008), Vector3(0.68, 1.05, 0.04), dark)


func _mk_jukebox() -> void:
	var t := _toy("Jukebox_0", "jukebox", Types.District.CASINO, "CasinoTable", Vector3(5.1, 0, -2.4), Vector3(1, 0, 0), Vector3(0.72, 1.4, 0.5), Vector3(0, 0.7, 0))
	var wood := _mat(Color(0.28, 0.12, 0.16), "tex_planks", Color())
	var chrome := _mat(Color(0.7, 0.72, 0.78), "", Color())
	var glass := _mat(Color(0.95, 0.35, 0.7), "", Color(1.0, 0.3, 0.65), 2.2)
	_mi(t, LowPoly.chamfer_box(Vector3(0.68, 1.32, 0.46), 0.03), Vector3(0, 0.66, 0), wood)
	_mi(t, LowPoly.chamfer_box(Vector3(0.5, 0.42, 0.04), 0.01), Vector3(0, 0.95, 0.24), glass)
	t.strip = _mi(t, LowPoly.chamfer_box(Vector3(0.6, 0.07, 0.05), 0.008), Vector3(0, 1.22, 0.24), _emit(JUKE_COLS[0], 2.4))
	_mi(t, LowPoly.cylinder(0.1, 0.1, 0.04, 8), Vector3(-0.16, 0.42, 0.24), chrome)
	_mi(t, LowPoly.cylinder(0.1, 0.1, 0.04, 8), Vector3(0.16, 0.42, 0.24), chrome)
	_label(t, Vector3(0, 1.42, 0.2), "♫", 40, Color(1.0, 0.55, 0.8))


func _mk_bag() -> void:
	var t := _toy("Bag_0", "bag", Types.District.GARAGES, "Gate", Vector3(6.8, 0, -2.2), Vector3(-1, 0, 0), Vector3(0.55, 2.0, 0.55), Vector3(0, 1.0, 0))
	var metal := _mat(Color(0.4, 0.42, 0.45), "tex_corrugated", Color())
	var red := _mat(Color(0.72, 0.16, 0.14), "tex_container", Color())
	_mi(t, LowPoly.cylinder(0.18, 0.22, 0.12, 8), Vector3(0, 0.06, 0), metal)
	_mi(t, LowPoly.cylinder(0.035, 0.035, 1.85, 6), Vector3(0, 1.0, -0.12), metal)
	var swing := Node3D.new()
	swing.name = "Swing"
	swing.position = Vector3(0, 1.55, 0)
	t.add_child(swing)
	t.swing = swing
	_mi(swing, LowPoly.sphere(0.22, 7, 4), Vector3(0, -0.35, 0.08), red)
	_mi(swing, LowPoly.cylinder(0.16, 0.18, 0.45, 7), Vector3(0, -0.55, 0.08), red)
	t.score = _label(t, Vector3(0, 2.15, 0.1), "", 28, Color(1.0, 0.9, 0.35))


func _mk_bench(id: String, d: int, marker: String, off: Vector3, face: Vector3) -> void:
	var t := _toy(id, "bench", d, marker, off, face, Vector3(1.55, 0.55, 0.5), Vector3(0, 0.28, 0))
	var wood := _mat(Color(0.55, 0.38, 0.2), "tex_planks", Color())
	var iron := _mat(Color(0.25, 0.26, 0.28), "", Color())
	_mi(t, LowPoly.chamfer_box(Vector3(1.45, 0.07, 0.4), 0.015), Vector3(0, 0.42, 0), wood)
	_mi(t, LowPoly.chamfer_box(Vector3(1.45, 0.32, 0.06), 0.012), Vector3(0, 0.62, -0.18), wood)
	_mi(t, LowPoly.cylinder(0.03, 0.03, 0.42, 6), Vector3(-0.58, 0.21, 0.12), iron)
	_mi(t, LowPoly.cylinder(0.03, 0.03, 0.42, 6), Vector3(0.58, 0.21, 0.12), iron)
	_mi(t, LowPoly.cylinder(0.03, 0.03, 0.42, 6), Vector3(-0.58, 0.21, -0.12), iron)
	_mi(t, LowPoly.cylinder(0.03, 0.03, 0.42, 6), Vector3(0.58, 0.21, -0.12), iron)


func _mk_pump() -> void:
	var t := _toy("Pump_0", "pump", Types.District.CAR_MARKET, "Kiosk", Vector3(-4.2, 0, -3.5), Vector3(0, 0, -1), Vector3(0.4, 1.25, 0.4), Vector3(0, 0.62, 0))
	var blue := _mat(Color(0.15, 0.35, 0.72), "tex_rust_teal", Color())
	var black := _mat(Color(0.1, 0.1, 0.12), "", Color())
	var chrome := _mat(Color(0.65, 0.67, 0.7), "", Color())
	_mi(t, LowPoly.cylinder(0.12, 0.14, 1.05, 8), Vector3(0, 0.55, 0), blue)
	_mi(t, LowPoly.sphere(0.08, 6, 3), Vector3(0, 1.12, 0), chrome)
	_mi(t, LowPoly.cylinder(0.025, 0.025, 0.55, 6), Vector3(0.22, 0.85, 0.1), black, Basis(Vector3.FORWARD, 1.1))
	_mi(t, LowPoly.chamfer_box(Vector3(0.08, 0.06, 0.12), 0.01), Vector3(0.38, 0.62, 0.18), chrome)
	_label(t, Vector3(0, 1.28, 0.12), "PSI", 22, Color(0.9, 0.95, 1.0))


func _toy(id: String, kind: String, d: int, marker: String, off: Vector3, face: Vector3, col: Vector3, col_pos: Vector3) -> Toy:
	var t := Toy.new()
	t.id = id
	t.kind = kind
	t.sys = self
	t.name = id
	t.collision_layer = Types.L_WORLD
	t.collision_mask = 0
	add_child(t)
	var pos := _spot(d, marker, off)
	if kind != "wc" and kind != "jukebox":
		pos = _safe(pos)
	t.global_position = pos
	t.global_basis = _basis_face(face)
	_box_col(t, col_pos, col)
	toys[id] = t
	return t


# ------------------------------------------------------------------ host

func _host_vending(t: Toy) -> void:
	if t.stuck:
		t.stuck = false
		_spawn_drink(t, 2)
		Net.broadcast_event("interactable", {"id": t.id, "kind": "vending", "act": "kick"})
		return
	if not Economy.try_spend(2, "vending"):
		Net.broadcast_event("interactable", {"id": t.id, "kind": "vending", "act": "broke"})
		return
	if not _playtest() and randf() < 0.15:
		t.stuck = true
		Net.broadcast_event("interactable", {"id": t.id, "kind": "vending", "act": "stuck"})
		return
	_spawn_drink(t, 1)
	Net.broadcast_event("interactable", {"id": t.id, "kind": "vending", "act": "drop"})


func _spawn_drink(t: Toy, n: int) -> void:
	if _drink == "":
		return
	for i in n:
		var local := Vector3(0.08 * float(i) - 0.04 * float(n - 1), 0.55, 0.52)
		var xf := Transform3D(Basis(), t.to_global(local))
		Net.spawn_item(_drink, xf)


func _host_phone(t: Toy, player: Node) -> void:
	var now := _now()
	if now < t.cool_until:
		return
	var text := ""
	var peer := 0
	if player is Player:
		peer = (player as Player).peer_id
	if Economy.can_afford(1) and Economy.try_spend(1, "payphone"):
		t.cool_until = now + PHONE_COOL
		text = _phone_line()
	else:
		text = tr("INT_PHONE_WRONG")
	Net.broadcast_event("interactable", {"id": t.id, "kind": "phone", "act": "call", "text": text, "peer": peer, "cool": t.cool_until})


func _phone_line() -> String:
	var i := _phone_i % 8
	_phone_i += 1
	match i:
		0, 4:
			return tr("INT_PHONE_NEXT") % _next_district_name()
		1:
			return tr("INT_PHONE_HOLD")
		2:
			return tr("INT_PHONE_GARAGE")
		3:
			return tr("INT_PHONE_CAT")
		5:
			return tr("INT_PHONE_POT")
		6:
			return tr("INT_PHONE_MUSIC")
		_:
			return tr("INT_PHONE_COP")


func _next_district_name() -> String:
	var auc: Auction = Game.world.system("Auction") as Auction if Game.world else null
	if auc:
		for s in auc.sessions:
			var sess: Auction.Session = s
			if sess == null:
				continue
			var dist: District = Game.world.city.district_root(sess.district_id) as District
			if dist:
				return tr(dist.name_key)
			if sess.preset:
				return tr("DISTRICT_HANGAR")
	return tr("DISTRICT_HANGAR")


func _host_wc(t: Toy) -> void:
	var now := _now()
	if now < t.cool_until:
		return
	t.cool_until = now + WC_COOL
	var rock := randf() < 0.1
	var gag := randi() % 3
	if rock:
		if Registry.item("cash_5"):
			Net.spawn_item("cash_5", Transform3D(Basis(), t.to_global(Vector3(0.1, 0.4, 0.45))))
		gag = 3
	elif gag == 1 and not _loot.is_empty():
		var lid: String = _loot[randi() % _loot.size()]
		Net.spawn_item(lid, Transform3D(Basis(), t.to_global(Vector3(0.05, 0.35, 0.4))))
	Net.broadcast_event("interactable", {"id": t.id, "kind": "wc", "act": "open", "gag": gag, "rock": rock, "cool": t.cool_until})


func _host_jukebox(t: Toy) -> void:
	if not Economy.try_spend(1, "jukebox"):
		Net.broadcast_event("interactable", {"id": t.id, "kind": "jukebox", "act": "broke"})
		return
	t.track = (t.track + 1) % JUKE_TRACKS.size()
	Net.broadcast_event("interactable", {"id": t.id, "kind": "jukebox", "act": "play", "track": t.track})


func _host_bag(t: Toy) -> void:
	Game.stat_add("bag_hits")
	var key: String = ["INT_BAG_1", "INT_BAG_2", "INT_BAG_3"][randi() % 3]
	Net.broadcast_event("interactable", {"id": t.id, "kind": "bag", "act": "hit", "score": tr(key)})


func _host_bench(t: Toy, player: Node) -> void:
	t.sitting = not t.sitting
	var peer := 0
	if player is Player:
		peer = (player as Player).peer_id
	if t.sitting:
		Game.stat_add("benches_sat")
	Net.broadcast_event("interactable", {"id": t.id, "kind": "bench", "act": "sit" if t.sitting else "stand", "peer": peer})


func _host_pump(t: Toy) -> void:
	var near_car := _vehicle_near(t.global_position, 4.0)
	Game.stat_add("tires_pumped")
	var nid := _inflate_tire_near(t.global_position)
	Net.broadcast_event("interactable", {"id": t.id, "kind": "pump", "act": "hiss", "car": near_car, "nid": nid})


func _vehicle_near(pos: Vector3, r: float) -> bool:
	var vs: Vehicles = Game.world.system("Vehicles") as Vehicles if Game.world else null
	if vs == null:
		return false
	for k in vs.vehicles:
		var v: Vehicle = vs.vehicles[k] as Vehicle
		if v and is_instance_valid(v) and v.global_position.distance_to(pos) < r:
			return true
	return false


func _inflate_tire_near(pos: Vector3) -> int:
	var best: ItemBody = null
	var best_d := 5.0
	for k in Net.items:
		var b: ItemBody = Net.items[k] as ItemBody
		if b == null or not is_instance_valid(b) or b.def == null:
			continue
		if not b.def.id.begins_with("tire"):
			continue
		var d := b.global_position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = b
	return best.net_id if best else 0


# ------------------------------------------------------------------ client fx

func _fx_vending(t: Toy, data: Dictionary) -> void:
	var act := str(data.get("act", ""))
	var pos := t.global_position + Vector3(0, 1.0, 0)
	match act:
		"drop":
			t.stuck = false
			AudioBus.play_at("thud", pos)
		"stuck":
			t.stuck = true
			AudioBus.play_at("buzzer", pos, -2.0)
		"kick":
			t.stuck = false
			AudioBus.play_at("bump_boing", pos)
			_shake(t, 0.18, 0.07)
		"broke":
			AudioBus.play_at("buzzer", pos)
			Game.notify.emit(tr("INT_VEND_BROKE"), 2.5)
		"sync":
			t.stuck = bool(data.get("stuck", false))


func _fx_phone(t: Toy, data: Dictionary) -> void:
	if str(data.get("act", "")) != "call":
		return
	t.cool_until = float(data.get("cool", t.cool_until))
	AudioBus.play_at("phone_beep", t.global_position + Vector3(0, 1.5, 0))
	var text := str(data.get("text", ""))
	if text == "":
		return
	var peer := int(data.get("peer", 0))
	var pl: Player = Game.world.player_of(peer) as Player if Game.world else null
	if pl and pl.has_method("say"):
		pl.say(text, 4.0)
	if pl == null or not pl.is_local():
		Game.notify.emit(text, 4.0)


func _fx_wc(t: Toy, data: Dictionary) -> void:
	t.cool_until = float(data.get("cool", t.cool_until))
	t.open = true
	if t.door:
		var tw := t.create_tween()
		tw.tween_property(t.door, "rotation:y", deg_to_rad(100.0), 0.35).set_trans(Tween.TRANS_BACK)
		tw.tween_interval(2.2)
		tw.tween_property(t.door, "rotation:y", 0.0, 0.3)
		tw.finished.connect(func() -> void: t.open = false)
	var gag := int(data.get("gag", 0))
	var pos := t.global_position + Vector3(0, 1.0, 0)
	if bool(data.get("rock", false)):
		_shake(t, 0.35, 0.1)
		AudioBus.play_at("thud_heavy", pos, -1.0)
	match gag:
		0:
			AudioBus.npc_shout("hunter", pos)
			Game.notify.emit(tr("INT_WC_BUSY"), 2.2)
		1:
			AudioBus.play_at("thud", pos)
			Game.notify.emit(tr("INT_WC_FIND"), 2.2)
		2:
			AudioBus.play_at("hiss", pos)
		3:
			AudioBus.play_at("coin", pos)


func _fx_jukebox(t: Toy, data: Dictionary) -> void:
	var act := str(data.get("act", ""))
	if act == "broke":
		AudioBus.play_at("buzzer", t.global_position + Vector3(0, 0.8, 0))
		Game.notify.emit(tr("INT_JUKE_BROKE"), 2.2)
		return
	t.track = int(data.get("track", t.track)) % JUKE_TRACKS.size()
	AudioBus.play_music(JUKE_TRACKS[t.track])
	if t.strip:
		t.strip.material_override = _emit(JUKE_COLS[t.track], 2.4)
	if act != "sync":
		AudioBus.play_at("coin", t.global_position + Vector3(0, 0.8, 0))
		Game.notify.emit(tr(JUKE_KEYS[t.track]), 2.8)


func _fx_bag(t: Toy, data: Dictionary) -> void:
	AudioBus.play_at("thud_heavy", t.global_position + Vector3(0, 1.0, 0))
	if t.score:
		t.score.text = str(data.get("score", ""))
	if t.swing:
		var tw := t.create_tween()
		tw.tween_property(t.swing, "rotation:x", 0.55, 0.12).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(t.swing, "rotation:x", -0.25, 0.18)
		tw.tween_property(t.swing, "rotation:x", 0.0, 0.22).set_trans(Tween.TRANS_SINE)


func _fx_bench(t: Toy, data: Dictionary) -> void:
	t.sitting = str(data.get("act", "")) == "sit"
	var peer := int(data.get("peer", 0))
	var pl: Player = Game.world.player_of(peer) as Player if Game.world else null
	if t.sitting and pl and pl.has_method("say"):
		pl.say(tr("INT_BENCH_SIT"), 3.0)
	elif (not t.sitting) and pl and pl.has_method("say"):
		pl.say(tr("INT_BENCH_UP"), 2.0)


func _fx_pump(t: Toy, data: Dictionary) -> void:
	AudioBus.play_at("hiss", t.global_position + Vector3(0, 0.6, 0))
	Game.notify.emit(tr("INT_PUMP_OK"), 2.4)
	var nid := int(data.get("nid", 0))
	if nid != 0 and Net.items.has(nid):
		var b: ItemBody = Net.items[nid] as ItemBody
		if b and is_instance_valid(b):
			var tw := b.create_tween()
			tw.tween_property(b, "scale", Vector3.ONE * 1.15, 0.2)
			tw.tween_property(b, "scale", Vector3.ONE, 0.35)


func _shake(n: Node3D, sec: float, amp: float) -> void:
	var origin := n.position
	var tw := n.create_tween()
	for i in 5:
		tw.tween_property(n, "position", origin + Vector3(randf_range(-amp, amp), 0, randf_range(-amp, amp)), sec / 5.0)
	tw.tween_property(n, "position", origin, 0.06)


# ------------------------------------------------------------------ place / mesh

func _spot(d: int, marker: String, off: Vector3) -> Vector3:
	var w: World = Game.world
	if w == null:
		return off
	if marker != "":
		var m: Node3D = w.find_marker(d, marker)
		if m:
			return m.global_position + m.global_basis * off
	var root: Node3D = w.district_root(d)
	if root:
		return root.global_position + off
	return off


func _safe(p: Vector3) -> Vector3:
	var pos := Vector3(p.x, 0.0, p.z)
	for i in 14:
		if not _blocked(pos):
			return Vector3(pos.x, 0.0, pos.z)
		var a := float(i) * 2.399763
		var r := 1.1 + float(i) * 0.65
		pos = Vector3(p.x + cos(a) * r, 0.0, p.z + sin(a) * r)
	return Vector3(p.x, 0.0, p.z)


func _blocked(p: Vector3) -> bool:
	var flat := Vector3(p.x, 0.0, p.z)
	for c in _lot_pts:
		if Vector3(c.x, 0.0, c.z).distance_to(flat) < LOT_CLEAR:
			return true
	for seg in _roads:
		var s: Vector4 = seg
		var a := Vector2(s.x, s.y)
		var b := Vector2(s.z, s.w)
		if _dist_seg(Vector2(p.x, p.z), a, b) < _road_half:
			return true
	return false


func _dist_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _cache_blockers() -> void:
	_lot_pts.clear()
	for a in get_tree().get_nodes_in_group("lot_anchors"):
		if a is Node3D:
			var n: Node3D = a
			if n.has_method("cell_center"):
				_lot_pts.append(n.cell_center())
			else:
				_lot_pts.append(n.global_position)
	var city: City = Game.world.city as City if Game.world else null
	if city and city.roads():
		var r: Roads = city.roads() as Roads
		if r:
			_roads = r.segments
			_road_half = r.width * 0.5 + r.sidewalk + ROAD_PAD


func _basis_face(face: Vector3) -> Basis:
	var f := Vector3(face.x, 0.0, face.z)
	if f.length_squared() < 0.0001:
		f = Vector3.FORWARD
	return Basis.looking_at(-f.normalized(), Vector3.UP)


func _mat(albedo: Color, tex_name: String, emit: Color, emit_e := 1.4) -> StandardMaterial3D:
	var key := "%s|%s|%s|%.2f" % [albedo.to_html(false), tex_name, emit.to_html(false), emit_e]
	if _mats.has(key):
		return _mats[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = 0.82
	if tex_name != "":
		var tex: Texture2D = CityDress.tex(tex_name)
		if tex:
			m.albedo_texture = tex
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_scale = Vector3(0.45, 0.45, 0.45)
	if emit.v > 0.04:
		m.emission_enabled = true
		m.emission = emit
		m.emission_energy_multiplier = emit_e
	_mats[key] = m
	return m


func _emit(c: Color, e: float) -> StandardMaterial3D:
	return _mat(c.lightened(0.15), "", c, e)


func _mi(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material, basis := Basis()) -> MeshInstance3D:
	if _mesh_n >= 120 or mesh == null:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = Transform3D(basis, pos)
	parent.add_child(mi)
	_mesh_n += 1
	return mi


func _box_col(body: StaticBody3D, pos: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = pos
	body.add_child(cs)


func _label(parent: Node3D, pos: Vector3, text: String, size: int, col: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.outline_size = 6
	l.pixel_size = 0.007
	l.modulate = col
	l.outline_modulate = Color(0.05, 0.05, 0.06)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = pos
	parent.add_child(l)
	return l


func _resolve_drink() -> String:
	for id in Registry.items:
		var s := str(id).to_lower()
		if s.contains("soda") or s.contains("cola") or s.contains("beer") or s.contains("can"):
			return str(id)
	for def in Registry.all_items():
		var d: ItemDef = def
		if d and d.liquid_id != Types.LiquidId.NONE and d.archetype_id == "bottle":
			return d.id
	if Registry.item("water_bottle"):
		return "water_bottle"
	if Registry.item("whiskey_cheap"):
		return "whiskey_cheap"
	return ""


func _resolve_loot() -> Array[String]:
	var out: Array[String] = []
	for id in ["tape_scotch", "tape_colored", "tool_tape", "book_romance", "book_cookbook", "book_diary"]:
		if Registry.item(id):
			out.append(id)
	return out


func _now() -> float:
	return Time.get_ticks_msec() * 0.001


func _playtest() -> bool:
	return OS.get_cmdline_user_args().has("--playtest")
