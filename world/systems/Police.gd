class_name Police
extends Node3D
## Полиция (§13, §6.4). Хост считает всё, клиенты получают события.
## Триггер → heat (player.wanted) → при ≥ 0.5 выезд: машина приезжает, 2 мента бегут (короткая погоня, 25 с).
## Поймали: heat < 0.8 → штраф из котла (не больше, чем есть; 0 → арест); иначе арест: наручники,
## вещи из рук/карманов в комнату улик (живут в сейве), в машину → участок → решётка N сек → на выход.
## Улики вернуть: выкупить у стола (20% цены), вскрыть дверь отмычкой, взятка (купюра на стол / в руку менту).
## Soft-lock нет: срок всегда кончается, штраф ≤ котла, кореш может выкупить взяткой.

const HEAT := {
	Types.PoliceTrigger.ILLEGAL_SALE: 0.6,
	Types.PoliceTrigger.THREAT: 0.7,
	Types.PoliceTrigger.BRAWL: 0.5,
	Types.PoliceTrigger.CAR_THEFT: 0.8,
	Types.PoliceTrigger.OVERTIME: 0.4,
	Types.PoliceTrigger.BLACKLIST_ENTRY: 0.5,
	Types.PoliceTrigger.ARSON: 1.0,
	Types.PoliceTrigger.PROPERTY_THEFT: 0.55,
}
const TRIGGER_KEYS := [
	"POLICE_TRIGGER_ILLEGAL_SALE", "POLICE_TRIGGER_THREAT", "POLICE_TRIGGER_BRAWL", "POLICE_TRIGGER_CAR_THEFT",
	"POLICE_TRIGGER_OVERTIME", "POLICE_TRIGGER_BLACKLIST_ENTRY", "POLICE_TRIGGER_ARSON",
	"POLICE_TRIGGER_PROPERTY_THEFT",
]
## Сколько вариантов реплики на категорию: POLICE_COP_<CAT>_<i>.
const LINES := {
	"STOP": 3, "CHASE": 3, "GIVEUP": 2, "ARREST": 2, "RELEASE": 2,
	"BRIBE_OK": 2, "BRIBE_NO": 2, "IDLE": 2, "SHOVED": 2, "LOCKPICK": 1,
}

const DISPATCH_AT := 0.5
const ARREST_AT := 0.8
const CHASE_MAX := 25.0
const CATCH_DIST := 1.2
const CATCH_REACH_STUCK := 2.2 # упёрся в кровать/стену рядом с игроком — дотянулся рукой
const STUCK_SEC := 0.8
const CAR_APPROACH := 30.0
const CAR_PARK := 6.0
const CAR_ARRIVE_SEC := 3.0
const CAR_TO_STATION_SEC := 4.0
const FINE_UNCUFF_SEC := 3.0
const CUSTODY_BASE := 45.0
const CUSTODY_PER_WANTED := 30.0
const EVIDENCE_OPEN_SEC := 30.0
const EVIDENCE_RADIUS := 6.0
const DOOR_SLIDE := 2.5
const SHOVES_TO_ARREST := 3
const COP_POS_HZ := 5.0
const STATION_FALLBACK := Vector3(0, 0, 60)
const POLICE_CAR_SCENE := "res://world/vehicles/PoliceCar.tscn"

enum CaseState { WAIT_CAR, CHASE, FINE, TRANSPORT }


class PoliceCase extends RefCounted:
	var peer := 0
	var state := 0
	var cops: Array = []
	var car: PoliceCar = null
	var origin := Vector3.ZERO
	var chase_t := 0.0
	var retarget_t := 0.0
	var line_t := 0.0
	var timer := 0.0
	var wanted_at_catch := 0.0
	var immediate := false
	var taken: Array = [] # что было в руках на момент наручников (наручники роняют)


class Custody extends RefCounted:
	var peer := 0
	var left := 0.0
	var total := 0.0
	var wanted := 0.0
	var tick_t := 0.0


## Стол дежурного: E — выкупить улики (§6.4). Слой trigger, чтобы не мешать вещам.
class DeskCounter extends StaticBody3D:
	var police: Node

	func _init(p: Node) -> void:
		police = p
		name = "DeskCounter"
		collision_layer = Types.L_TRIGGER
		collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.8, 0.3, 0.6)
		cs.shape = bs
		add_child(cs)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.7, 0.2, 0.5)
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.85, 0.7, 0.25)
		mi.material_override = m
		add_child(mi)

	func interact(player: Player) -> void:
		police.desk_interact(player)

	func interact_hint(player: Player) -> String:
		return police.desk_hint(player)


## Замок комнаты улик: E с отмычкой в руке — попытка вскрыть.
class EvidenceLock extends StaticBody3D:
	var police: Node

	func _init(p: Node) -> void:
		police = p
		name = "EvidenceLock"
		collision_layer = Types.L_TRIGGER
		collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.6, 2.6, 0.6)
		cs.shape = bs
		add_child(cs)

	func interact(player: Player) -> void:
		police.lock_interact(player)

	func interact_hint(player: Player) -> String:
		return police.lock_hint(player)


var _cases: Dictionary = {} # peer → PoliceCase
var _custody: Dictionary = {} # peer → Custody
var _cops: Dictionary = {} # cop_id → Cop (хост: живые; клиент: прокси)
var _cars: Dictionary = {} # car_id → PoliceCar
var _evidence: Array = [] # ItemBody в комнате улик (хост)
var _desk_cop: Cop = null
var _bribe_area: Area3D = null
var _next_cop_id := 1
var _next_car_id := 1
var _jail_closed := false
var _evidence_open := false
var _evidence_left := 0.0
var _evidence_t := 0.0
var _pos_t := 0.0
var _ready_done := false


func system_name() -> String:
	return "Police"


func _ready() -> void:
	_setup_deferred()


func _setup_deferred() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_setup_station()
	# в редакторе решётка стоит в проёме — на старте камера пустая, поднимаем сразу
	_apply_door("jail", false, true)
	if Net.is_host():
		_spawn_desk_cop()
		spawn_evidence_from_save()
	_ready_done = true
	if OS.get_cmdline_user_args().has("--police-test") and ResourceLoader.exists("res://tools/PoliceTest.gd"):
		add_child(load("res://tools/PoliceTest.gd").new())


# ------------------------------------------------------------------ участок: маркеры и интерактивы

func _station_root() -> Node3D:
	if Game.world and Game.world.has_method("district_root"):
		return Game.world.district_root(Types.District.POLICE)
	return null


func _marker(name: String) -> Node3D:
	var root := _station_root()
	if root == null:
		return null
	return root.find_child(name, true, false) as Node3D


func _station_pos(marker: String, fallback_offset: Vector3) -> Vector3:
	var m := _marker(marker)
	if m:
		return m.global_position
	var root := _station_root()
	var base := root.global_position if root else STATION_FALLBACK
	return base + fallback_offset


func _cell_pos() -> Vector3:
	return _station_pos("JailCell", Vector3.ZERO) + Vector3(0, 0.1, 0)


func _evidence_pos() -> Vector3:
	return _station_pos("EvidenceRoom", Vector3(6, 0, 0))


func _desk_pos() -> Vector3:
	return _station_pos("Desk", Vector3(-6, 0, 0))


func _car_station_pos() -> Vector3:
	return _station_pos("PoliceCarSpawn", Vector3(0, 0, -10))


func _setup_station() -> void:
	# стол: выкуп улик
	var desk := DeskCounter.new(self)
	add_child(desk)
	var desk_m := _marker("Desk")
	desk.global_position = (desk_m.global_position if desk_m else _desk_pos()) + Vector3(0, 1.15, 0)
	# замок на двери улик
	var lock := EvidenceLock.new(self)
	add_child(lock)
	var door := _marker("EvidenceDoor")
	if door:
		lock.global_transform = door.global_transform
		lock.global_position = door.global_position + Vector3(0, 1.0, 0)
	else:
		lock.global_position = _evidence_pos() + Vector3(0, 1.2, -1.5)
	# взятка на стол: Area3D-маркер или своя зона над столом
	var area := _marker("Bribe") as Area3D
	if area == null:
		area = Area3D.new()
		area.name = "BribeArea"
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.7, 0.5, 0.7)
		cs.shape = bs
		area.add_child(cs)
		add_child(area)
		area.global_position = (desk_m.global_position if desk_m else _desk_pos()) + Vector3(0, 1.25, 0)
	area.collision_mask |= Types.L_ITEM
	area.monitoring = true
	if not area.body_entered.is_connected(_on_bribe_body):
		area.body_entered.connect(_on_bribe_body)
	_bribe_area = area


func _spawn_desk_cop() -> void:
	var spot := _marker("CopSpawn0")
	var pos := spot.global_position if spot else _desk_pos() + Vector3(0, 0, -1.5)
	_desk_cop = _spawn_cop(pos, true)
	_desk_cop.face(_desk_pos() + Vector3(0, 0, 3))


# ------------------------------------------------------------------ публичный API

## Любая система: полиция узнала о косяке. culprit — игрок (или null → ближайший к pos).
func trigger(kind: int, pos: Vector3, culprit: Node = null) -> void:
	if not Net.is_host():
		return
	var p: Player = (culprit as Player) if culprit is Player else _nearest_player(pos)
	if p == null or p.dead:
		return
	if kind >= 0 and kind < TRIGGER_KEYS.size():
		_toast_all(TRIGGER_KEYS[kind])
	Game.stat_add("police_triggers")
	_add_heat(p, float(HEAT.get(kind, 0.5)), pos)


## Есть ли активная погоня/арест или кто-то сидит.
func is_active() -> bool:
	return not _cases.is_empty() or not _custody.is_empty()


func is_in_custody(peer: int) -> bool:
	return _custody.has(peer)


func custody_left(peer: int) -> float:
	var cu: Custody = _custody.get(peer)
	return cu.left if cu else 0.0


## Реплика мента по категории (см. LINES), через tr().
func cop_line(cat: String) -> String:
	var n := int(LINES.get(cat, 1))
	return tr("POLICE_COP_%s_%d" % [cat, randi() % maxi(n, 1)])


## Цена выкупа улик: 20% суммы current_value, минимум $10; 0 если улик нет.
func evidence_price() -> int:
	var total := 0
	var any := false
	for b in _evidence:
		if is_instance_valid(b):
			total += b.current_value()
			any = true
	if not any:
		return 0
	return maxi(10, int(total * 0.2))


func evidence_items() -> Array:
	var out: Array = []
	for b in _evidence:
		if is_instance_valid(b):
			out.append(b)
	return out


# ------------------------------------------------------------------ heat / выезд

func _add_heat(p: Player, amount: float, pos: Vector3) -> void:
	p.wanted = clampf(p.wanted + amount, 0.0, 1.0)
	if p.in_custody or _cases.has(p.peer_id):
		return
	if p.wanted >= DISPATCH_AT:
		_dispatch(p, pos, false)


func _dispatch(p: Player, pos: Vector3, immediate: bool) -> PoliceCase:
	var c := PoliceCase.new()
	c.peer = p.peer_id
	c.origin = pos
	c.immediate = immediate
	c.state = CaseState.WAIT_CAR
	var dir := _road_dir(pos)
	var from := pos + dir * CAR_APPROACH
	var park := pos + dir * CAR_PARK
	from.y = pos.y
	park.y = pos.y
	c.car = _spawn_car(from, park, CAR_ARRIVE_SEC)
	c.car.arrived.connect(func(): _on_car_arrived(c), CONNECT_ONE_SHOT)
	_cases[p.peer_id] = c
	AudioBus.play_at("siren", from, 4.0, 0.05)
	Game.stat_add("police_dispatches")
	_toast_all("POLICE_TOAST_DISPATCH", [_pname(p)])
	if immediate:
		c.taken = _held_items(p)
		p.set_cuffed(true)
	return c


func _on_car_arrived(c: PoliceCase) -> void:
	if not _cases.has(c.peer) or _cases[c.peer] != c:
		return
	var p := _player(c.peer)
	if p == null or p.dead or c.car == null or not is_instance_valid(c.car):
		_end_case(c, "lost")
		return
	var car: PoliceCar = c.car
	for side in [-1.6, 1.6]:
		var pos: Vector3 = car.global_position + car.global_basis.x * float(side)
		pos.y = maxf(car.global_position.y, 0.0) + 0.05
		var cop := _spawn_cop(pos, false)
		cop.face(p.global_position)
		c.cops.append(cop)
	c.state = CaseState.CHASE
	c.chase_t = 0.0
	c.retarget_t = 0.0
	c.line_t = 1.0
	_case_say(c, "STOP")
	if c.immediate:
		_catch(c, p)


func _chase_tick(c: PoliceCase, p: Player, delta: float) -> void:
	c.chase_t += delta
	c.retarget_t -= delta
	c.line_t -= delta
	if c.retarget_t <= 0.0:
		c.retarget_t = 0.3
		for cop in c.cops:
			if is_instance_valid(cop) and not cop.ragdolled and cop.get_meta("sidestep", 0.0) <= 0.0:
				cop.move_to(p.global_position)
	if c.line_t <= 0.0:
		c.line_t = randf_range(2.5, 4.5)
		_case_say(c, "CHASE" if randf() < 0.6 else "STOP")
	var can_catch := p.in_vehicle == null and not p.in_custody
	for cop in c.cops:
		if not is_instance_valid(cop) or cop.ragdolled:
			continue
		var d: Vector3 = cop.global_position - p.global_position
		var flat := Vector2(d.x, d.z).length()
		# застрял (нет пути — кровать, стена): рядом — дотянулся; далеко — подпрыгнуть и обойти
		var hv := Vector2(cop.velocity.x, cop.velocity.z).length()
		var stuck: float = cop.get_meta("stuck", 0.0)
		stuck = stuck + delta if (cop.moving and hv < 0.4) else 0.0
		cop.set_meta("stuck", stuck)
		cop.set_meta("sidestep", maxf(0.0, float(cop.get_meta("sidestep", 0.0)) - delta))
		var reach := CATCH_DIST if stuck < STUCK_SEC else CATCH_REACH_STUCK
		if can_catch and flat < reach and absf(d.y) < 2.0:
			_catch(c, p)
			return
		if stuck >= STUCK_SEC:
			cop.set_meta("stuck", 0.0)
			cop.set_meta("sidestep", 0.7)
			if cop.is_on_floor():
				cop.velocity.y = 4.5
			var side := Vector3(-d.z, 0.0, d.x).normalized() * (1.5 if randf() < 0.5 else -1.5)
			cop.move_to(p.global_position + side)
	if c.chase_t > CHASE_MAX:
		_case_say(c, "GIVEUP")
		_toast_all("POLICE_TOAST_ESCAPED", [_pname(p)])
		p.wanted = minf(p.wanted, 0.3)
		Game.stat_add("police_escapes")
		_end_case(c, "escaped")


func _catch(c: PoliceCase, p: Player) -> void:
	if c.state == CaseState.FINE or c.state == CaseState.TRANSPORT:
		return
	c.wanted_at_catch = p.wanted
	for b in _held_items(p):
		if not c.taken.has(b):
			c.taken.append(b)
	p.set_cuffed(true)
	p.hands.host_release_all()
	for cop in c.cops:
		if is_instance_valid(cop):
			cop.moving = false
			cop.face(p.global_position)
	_case_say(c, "ARREST")
	AudioBus.play_at("handcuffs", p.global_position, 0.0)
	_toast_all("POLICE_TOAST_CAUGHT", [_pname(p)])
	Game.stat_add("police_catches")
	if c.wanted_at_catch < ARREST_AT:
		var amount := mini(Economy.pot, 30 + int(c.wanted_at_catch * 100.0))
		if amount <= 0:
			_say_from(c, tr("POLICE_COP_NO_MONEY"), "arrest")
			_arrest(c, p)
			return
		Economy.try_spend(amount, "fine")
		Game.stat_add("fines_paid", amount)
		c.state = CaseState.FINE
		c.timer = FINE_UNCUFF_SEC
		_say_from(c, tr("POLICE_COP_FINE") % amount, "fine")
		_toast_all("POLICE_TOAST_FINE", [_pname(p), amount])
		_suggest_jobs()
	else:
		_arrest(c, p)


func _suggest_jobs() -> void:
	var jobs: Node = Game.world.system("Jobs") if Game.world else null
	if jobs and jobs.has_method("suggest_work"):
		jobs.suggest_work("police")
	var jan: Node = Game.world.system("Janitor") if Game.world else null
	if jan and jan.has_method("offer_job"):
		jan.offer_job()


func _finish_fine(c: PoliceCase, p: Player) -> void:
	p.set_cuffed(false)
	p.wanted = 0.0
	_end_case(c, "fine")


func _arrest(c: PoliceCase, p: Player) -> void:
	c.state = CaseState.TRANSPORT
	Achievements.unlock("arrested")
	Game.stat_add("arrests")
	var taken := _confiscate(p, c.taken)
	# посадка в машину
	if c.car == null or not is_instance_valid(c.car):
		c.car = _spawn_car(p.global_position + Vector3(2, 0, 0), p.global_position + Vector3(2, 0, 0), 0.0)
	p.enter_vehicle(c.car)
	c.car.passenger = p
	Net.broadcast_event("police_arrest", {"peer": p.peer_id, "car": c.car.car_id})
	_toast_all("POLICE_TOAST_ARRESTED", [_pname(p), taken])
	AudioBus.play_at("door_slam", c.car.global_position, 0.0)
	for cop in c.cops:
		_despawn_cop(cop)
	c.cops.clear()
	var dest := _car_station_pos()
	c.car.drive_to(dest, CAR_TO_STATION_SEC)
	Net.broadcast_event("police_car_drive", {"id": c.car.car_id, "to": dest, "dur": CAR_TO_STATION_SEC})
	c.car.arrived.connect(func(): _on_arrived_station(c), CONNECT_ONE_SHOT)
	_suggest_jobs()


func _on_arrived_station(c: PoliceCase) -> void:
	if _cases.get(c.peer) != c:
		return # дело закрыли по дороге (смерть/респавн) — не сажаем нового человека
	var p := _player(c.peer)
	if p and not p.dead:
		var cell := _cell_pos()
		p.exit_vehicle(cell)
		p.reset_physics_interpolation()
		p.in_custody = true
		if p.has_method("lower_paddle"):
			p.lower_paddle()
		var sec := CUSTODY_BASE + c.wanted_at_catch * CUSTODY_PER_WANTED
		var cu := Custody.new()
		cu.peer = c.peer
		cu.left = sec
		cu.total = sec
		cu.wanted = c.wanted_at_catch
		_custody[c.peer] = cu
		Net.broadcast_event("police_custody", {"peer": c.peer, "on": true, "pos": cell, "sec": sec})
		_set_jail_door(true)
		AudioBus.play_at("door_slam", cell, 2.0)
	if c.car and is_instance_valid(c.car):
		c.car.passenger = null
	_end_case(c, "arrest")
	_update_world_mode()


func _release(peer: int, reason: String) -> void:
	var cu: Custody = _custody.get(peer)
	if cu == null:
		return
	_custody.erase(peer)
	var p := _player(peer)
	if p:
		p.in_custody = false
		p.set_cuffed(false)
		p.wanted = 0.0
		if reason != "dead":
			if _desk_cop and is_instance_valid(_desk_cop):
				_desk_cop.say(cop_line("RELEASE"), 2.5, "release")
			_toast_all("POLICE_TOAST_RELEASED", [_pname(p)])
			_suggest_jobs()
	Net.broadcast_event("police_custody", {"peer": peer, "on": false})
	if _custody.is_empty():
		_set_jail_door(false)
	_update_world_mode()


func _end_case(c: PoliceCase, reason: String) -> void:
	if _cases.get(c.peer) == c:
		_cases.erase(c.peer)
	for cop in c.cops:
		_despawn_cop(cop)
	c.cops.clear()
	if c.car and is_instance_valid(c.car):
		var car: PoliceCar = c.car
		if car.passenger and is_instance_valid(car.passenger) and reason != "arrest":
			# уехали бы с пассажиром — высаживаем
			var pas: Player = car.passenger
			pas.exit_vehicle(car.global_position + car.global_basis.x * 1.8)
		car.passenger = null
		_cars.erase(car.car_id)
		car.leave()
		Net.broadcast_event("police_car_leave", {"id": car.car_id})
	c.car = null


## Толкнули мента (Cop.on_grab): толчок в ответ, 3 раза — арест на месте.
func on_cop_shoved(cop: Cop, player: Node) -> void:
	if not Net.is_host() or not (player is Player):
		return
	var p: Player = player
	var dir := (p.global_position - cop.global_position)
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	cop.face(p.global_position)
	cop.say(cop_line("SHOVED"), 2.0, "angry")
	Game.stat_add("cop_shoves")
	# ответный толчок (у хоста игрок сам себя двигает — пихаем скорость)
	if p.is_local():
		p.velocity += dir * 5.0 + Vector3.UP * 1.5
	if p.cuffed or p.in_custody:
		return
	var n := int(p.get_meta("cop_shoves", 0)) + 1
	p.set_meta("cop_shoves", n)
	if n >= SHOVES_TO_ARREST:
		p.set_meta("cop_shoves", 0)
		arrest_on_spot(p, cop.global_position)
	else:
		_add_heat(p, 0.2, cop.global_position)
		if n == SHOVES_TO_ARREST - 1:
			_toast_all("POLICE_TOAST_SHOVE_WARN")


## Арест без погони: наручники сразу, машина подъезжает и увозит.
func arrest_on_spot(p: Player, pos: Vector3) -> void:
	if not Net.is_host() or p.dead or p.in_custody:
		return
	p.wanted = maxf(p.wanted, ARREST_AT)
	var c: PoliceCase = _cases.get(p.peer_id)
	if c:
		if c.state == CaseState.CHASE:
			_catch(c, p)
		elif c.state == CaseState.WAIT_CAR:
			c.immediate = true
			p.set_cuffed(true)
		return
	_dispatch(p, pos, true)


# ------------------------------------------------------------------ конфискация / улики

func _held_items(p: Player) -> Array:
	var out: Array = []
	for h in p.hands.held:
		if h and is_instance_valid(h) and not out.has(h):
			out.append(h)
	return out


## Изъять: что было в руках (was_held — до наручников) + карманы → комната улик.
func _confiscate(p: Player, was_held: Array) -> int:
	var bodies: Array = []
	for h in was_held + _held_items(p):
		if h and is_instance_valid(h) and not bodies.has(h) and h.nested_in == null:
			bodies.append(h)
	p.hands.host_release_all()
	for i in p.pockets.size():
		var b: ItemBody = p.pockets[i] if is_instance_valid(p.pockets[i]) else null
		if b:
			p._pocket_release(b, i)
			Net.broadcast_event("pocket", {"peer": p.peer_id, "nid": b.net_id, "slot": i, "put": false})
			bodies.append(b)
	for b in bodies:
		_put_in_evidence(b)
	if not bodies.is_empty():
		Game.stat_add("items_confiscated", bodies.size())
		_write_evidence_save()
		Game.write_slot()
	return bodies.size()


func _evidence_slot(i: int) -> Vector3:
	return _evidence_pos() + Vector3(-1.2 + 0.4 * (i % 7), 0.35 + 0.5 * ((i / 7) % 3), -0.3 + 0.6 * (i / 21))


func _put_in_evidence(b: ItemBody) -> void:
	if b.nested_in:
		b.unnest()
	b.freeze = false
	b.sleeping = false
	b.linear_velocity = Vector3.ZERO
	b.angular_velocity = Vector3.ZERO
	b.global_transform = Transform3D(Basis(Vector3.UP, randf() * TAU), _evidence_slot(_evidence.size()))
	b.set_meta("evidence", true)
	if not _evidence.has(b):
		_evidence.append(b)


func _write_evidence_save() -> void:
	var arr: Array = []
	for b in _evidence:
		if is_instance_valid(b):
			arr.append({"item_id": b.def.id, "state": b.state_dict()})
	Game.save["evidence"] = arr


## Улики из сейва — обратно в комнату улик (§6.4: изъятое живёт между сессиями).
func spawn_evidence_from_save() -> void:
	if not Net.is_host():
		return
	var list: Array = Game.save.get("evidence", [])
	var i := 0
	for e in list:
		var id := ""
		var state := {}
		if e is Dictionary:
			id = str(e.get("item_id", ""))
			state = e.get("state", {})
		else:
			id = str(e)
		if Registry.item(id) == null:
			continue
		var b = Net.spawn_item(id, Transform3D(Basis(Vector3.UP, randf() * TAU), _evidence_slot(i)), state)
		if b:
			b.set_meta("evidence", true)
			_evidence.append(b)
			i += 1


func _evidence_tick() -> void:
	var room := _evidence_pos()
	var changed := false
	for b in _evidence.duplicate():
		if not is_instance_valid(b):
			_evidence.erase(b)
			changed = true
		elif b.global_position.distance_to(room) > EVIDENCE_RADIUS:
			b.remove_meta("evidence")
			_evidence.erase(b)
			changed = true
			Game.stat_add("evidence_recovered")
	if changed:
		_write_evidence_save()


## Стол: выкупить улики за 20% (min $10) → дверь открыта 30 с.
func desk_interact(player: Player) -> void:
	if not Net.is_host() or player == null:
		return
	var n := evidence_price()
	if n <= 0:
		player.say(tr("POLICE_HINT_DESK_EMPTY"))
		return
	if _evidence_open:
		player.say(tr("POLICE_DESK_OPEN"))
		return
	if Economy.try_spend(n, "evidence"):
		AudioBus.play_at("cash_register", player.global_position, 0.0)
		Game.stat_add("evidence_bought", n)
		_set_evidence_door(true, EVIDENCE_OPEN_SEC)
		_toast_all("POLICE_TOAST_EVIDENCE_BOUGHT", [n])
		if _desk_cop and is_instance_valid(_desk_cop):
			_desk_cop.say(cop_line("BRIBE_OK"), 2.0, "ok")
	else:
		player.say(tr("POLICE_DESK_POOR"))


func desk_hint(_player: Player) -> String:
	var n := evidence_price()
	if n <= 0:
		return tr("POLICE_HINT_DESK_EMPTY")
	return tr("POLICE_HINT_DESK") % n


## Дверь улик: отмычкой — 35% открыть, иначе 20% сломать; мент рядом злится.
func lock_interact(player: Player) -> void:
	if not Net.is_host() or player == null:
		return
	if _evidence_open:
		player.say(tr("POLICE_HINT_EVIDENCE_OPEN"))
		return
	var pick: ItemBody = player.hands.holds_tag("lockpick")
	var pos: Vector3 = player.global_position
	if pick == null:
		AudioBus.play_at("locked_rattle", pos, 0.0)
		player.say(tr("POLICE_EVIDENCE_LOCKED"))
		return
	if randf() < 0.35:
		AudioBus.play_at("unlock", pos, 0.0)
		Achievements.unlock("picked_lock")
		Game.stat_add("unlocked")
		_set_evidence_door(true, EVIDENCE_OPEN_SEC)
		_toast_all("POLICE_TOAST_EVIDENCE_OPEN")
	else:
		AudioBus.play_at("locked_rattle", pos, 0.0)
		if randf() < 0.2:
			pick.consume_use(player)
			player.say(tr("ITEM_LOCKPICK_BROKE"))
		var cop := _cop_near(pos, 12.0)
		if cop:
			cop.face(pos)
			cop.say(cop_line("LOCKPICK"), 2.0, "angry")
			_add_heat(player, 0.3, pos)


func lock_hint(player: Player) -> String:
	if _evidence_open:
		return tr("POLICE_HINT_EVIDENCE_OPEN")
	if player and player.hands and player.hands.holds_tag("lockpick"):
		return tr("POLICE_HINT_EVIDENCE_PICK")
	return tr("POLICE_HINT_EVIDENCE_LOCKED")


# ------------------------------------------------------------------ взятка (§6.3: только бумажка)

func _on_bribe_body(b: Node) -> void:
	if not Net.is_host() or not (b is ItemBody):
		return
	var bill: ItemBody = b
	if not bill.def.is_cash() or bill.get_meta("bribe_done", false):
		return
	bill.set_meta("bribe_done", true)
	_try_bribe(bill, _nearest_player(bill.global_position), _desk_cop)


## Купюра в руку менту (Cop.interact).
func bribe_in_hand(bill: ItemBody, player: Player, cop: Cop) -> void:
	if not Net.is_host() or not is_instance_valid(bill) or player == null:
		return
	if cop.global_position.distance_to(player.global_position) > 3.0:
		return
	cop.face(player.global_position)
	_try_bribe(bill, player, cop)


func _bribe_threshold(target: Player) -> int:
	var w := 0.0
	if target:
		var cu: Custody = _custody.get(target.peer_id)
		w = cu.wanted if cu else target.wanted
	return 20 + int(w * 80.0)


## Кому помогает взятка: сидящему → бегущему → самому плательщику (дверь улик).
func _bribe_beneficiary(payer: Player) -> Player:
	if payer and _custody.has(payer.peer_id):
		return payer
	if payer and _cases.has(payer.peer_id):
		return payer
	for peer in _custody:
		var p := _player(peer)
		if p:
			return p
	for peer in _cases:
		var p := _player(peer)
		if p:
			return p
	return payer


func _try_bribe(bill: ItemBody, payer: Player, cop: Cop) -> bool:
	var target := _bribe_beneficiary(payer)
	var threshold := _bribe_threshold(target)
	var value := bill.def.cash_value()
	var pos := bill.global_position
	for h in bill.held_by.duplicate():
		h.host_release_body(bill)
	Net.despawn_item(bill.net_id)
	AudioBus.play_at("coin", pos, -4.0)
	if cop == null or not is_instance_valid(cop):
		cop = _cop_near(pos, 30.0)
	if value >= threshold:
		Achievements.unlock("bribe")
		Game.stat_add("bribes", value)
		if target and _custody.has(target.peer_id):
			_release(target.peer_id, "bribe")
		elif target and _cases.has(target.peer_id):
			var c: PoliceCase = _cases[target.peer_id]
			target.set_cuffed(false)
			target.wanted = 0.0
			if c.state == CaseState.TRANSPORT and c.car and is_instance_valid(c.car):
				target.exit_vehicle(c.car.global_position + c.car.global_basis.x * 1.8)
			_end_case(c, "bribe")
		else:
			_set_evidence_door(true, EVIDENCE_OPEN_SEC)
		if cop:
			cop.say(cop_line("BRIBE_OK"), 2.5, "ok")
		_toast_all("POLICE_TOAST_BRIBE_OK")
		return true
	if cop:
		cop.say(cop_line("BRIBE_NO"), 2.5, "angry")
	_toast_all("POLICE_TOAST_BRIBE_NO")
	if payer:
		_add_heat(payer, 0.2, pos)
	return false


# ------------------------------------------------------------------ двери

func _set_jail_door(closed: bool) -> void:
	if _jail_closed == closed:
		return
	_jail_closed = closed
	_apply_door("jail", closed)
	Net.broadcast_event("police_door", {"which": "jail", "active": closed})


func _set_evidence_door(open: bool, seconds: float = 0.0) -> void:
	if open:
		_evidence_left = maxf(_evidence_left, seconds)
	if _evidence_open == open:
		return
	_evidence_open = open
	_apply_door("evidence", open)
	Net.broadcast_event("police_door", {"which": "evidence", "active": open})


## Обе двери в редакторе стоят в проёме (= закрыты) и уезжают ВВЕРХ на DOOR_SLIDE, когда открыты.
## Камера: active = закрыта → на месте; отпустили → решётка поднимается и выпускает.
## Улики: active = открыта → вверх.
func _apply_door(which: String, active: bool, instant := false) -> void:
	var door := _marker("JailDoor" if which == "jail" else "EvidenceDoor")
	if door == null:
		return
	var base: float = door.get_meta("base_y", door.position.y)
	door.set_meta("base_y", base)
	var open := (not active) if which == "jail" else active
	var target := base + (DOOR_SLIDE if open else 0.0)
	if instant:
		door.position.y = target
		return
	var tw := door.create_tween()
	tw.tween_property(door, "position:y", target, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var sfx := "door_slam" if (which == "jail" and active) else "door_roll"
	AudioBus.play_at(sfx, door.global_position, 2.0, 0.05)


# ------------------------------------------------------------------ тик (хост)

func _physics_process(delta: float) -> void:
	if not Net.is_host() or not _ready_done:
		return
	for peer in _cases.keys():
		var c: PoliceCase = _cases[peer]
		var p := _player(peer)
		if p == null or p.dead:
			if p:
				p.wanted = 0.0
			_end_case(c, "dead")
			continue
		match c.state:
			CaseState.CHASE:
				_chase_tick(c, p, delta)
			CaseState.FINE:
				c.timer -= delta
				if c.timer <= 0.0:
					_finish_fine(c, p)
	for peer in _custody.keys():
		var cu: Custody = _custody[peer]
		var p := _player(peer)
		if p == null or p.dead:
			_release(peer, "dead")
			continue
		if not p.in_custody:
			# кто-то снял снаружи (респавн) — закрываем дело
			_release(peer, "dead")
			continue
		cu.left -= delta
		cu.tick_t -= delta
		if cu.tick_t <= 0.0:
			cu.tick_t = 1.0
			_send_custody_state(peer, cu.left)
		if cu.left <= 0.0:
			_release(peer, "time")
	if _evidence_open:
		_evidence_left -= delta
		if _evidence_left <= 0.0:
			_set_evidence_door(false)
	_evidence_t -= delta
	if _evidence_t <= 0.0:
		_evidence_t = 1.0
		_evidence_tick()
	_pos_t -= delta
	if _pos_t <= 0.0:
		_pos_t = 1.0 / COP_POS_HZ
		_broadcast_cop_pos()


func _send_custody_state(peer: int, left: float) -> void:
	if peer == Net.my_id():
		_hud_timer(left)
	elif Net.players.size() > 1:
		Net.send_event(peer, "custody_state", {"peer": peer, "left": left})


## Режим мира глобален для пати: POLICE_CUSTODY только когда все живые сидят.
func _update_world_mode() -> void:
	var living := 0
	var jailed := 0
	for pid in Net.players:
		var p: Player = Net.players[pid]
		if p and is_instance_valid(p) and not p.dead:
			living += 1
			if p.in_custody:
				jailed += 1
	if living > 0 and jailed == living:
		Game.set_world_mode(Types.WorldMode.POLICE_CUSTODY)
	elif Game.world_mode == Types.WorldMode.POLICE_CUSTODY:
		Game.set_world_mode(Types.WorldMode.TRAVEL)


# ------------------------------------------------------------------ менты и машины (хост спавнит, клиент — прокси)

func _npcs_root() -> Node:
	if Game.world and Game.world.get("npcs_root"):
		return Game.world.npcs_root
	return self


func _spawn_cop(pos: Vector3, stationary: bool) -> Cop:
	var cop := Cop.new()
	cop.cop_id = _next_cop_id
	_next_cop_id += 1
	cop.name = "Cop_%d" % cop.cop_id
	cop.police = self
	cop.stationary = stationary
	_npcs_root().add_child(cop)
	cop.global_position = pos
	_cops[cop.cop_id] = cop
	if Net.peer_count() > 1:
		Net.broadcast_event("cop_spawn", {"id": cop.cop_id, "pos": pos, "name": cop.name})
	return cop


func _despawn_cop(cop: Node) -> void:
	if cop == null or not is_instance_valid(cop):
		return
	_cops.erase(cop.cop_id)
	if Net.peer_count() > 1:
		Net.broadcast_event("cop_despawn", {"id": cop.cop_id})
	cop.queue_free()


func _spawn_proxy_cop(id: int, pos: Vector3, name: String) -> void:
	if _cops.has(id):
		return
	var cop := Cop.new()
	cop.cop_id = id
	cop.proxy = true
	cop.police = self
	if name != "":
		cop.name = name
	_npcs_root().add_child(cop)
	cop.set_proxy_target(pos, 0.0)
	_cops[id] = cop


func _broadcast_cop_pos() -> void:
	if Net.peer_count() <= 1 or _cops.is_empty():
		return
	var arr: Array = []
	for id in _cops:
		var cop: Node3D = _cops[id]
		if is_instance_valid(cop):
			var gp := cop.global_position
			arr.append([id, gp.x, gp.y, gp.z, cop.rotation.y])
	if not arr.is_empty():
		Net.broadcast_event("cop_pos", {"c": arr})


func _make_car(id: int) -> PoliceCar:
	var car: PoliceCar = null
	if ResourceLoader.exists(POLICE_CAR_SCENE):
		var scene := load(POLICE_CAR_SCENE) as PackedScene
		if scene:
			car = scene.instantiate() as PoliceCar
	if car == null:
		car = PoliceCar.new()
	car.car_id = id
	car.name = "PoliceCar_%d" % id
	add_child(car)
	_cars[id] = car
	return car


func _spawn_car(from: Vector3, to: Vector3, dur: float) -> PoliceCar:
	var id := _next_car_id
	_next_car_id += 1
	var car := _make_car(id)
	car.arrive(from, to, dur)
	if Net.peer_count() > 1:
		Net.broadcast_event("police_car", {"id": id, "from": from, "to": to, "dur": dur})
	return car


## Направление «по дороге»: от места к центру города (дороги сходятся к нему); у центра — вдоль X.
func _road_dir(pos: Vector3) -> Vector3:
	var to_center := -Vector3(pos.x, 0.0, pos.z)
	if to_center.length() < 5.0:
		return Vector3.RIGHT
	return to_center.normalized()


func _cop_near(pos: Vector3, radius: float) -> Cop:
	var best: Cop = null
	var best_d := radius
	for id in _cops:
		var cop: Cop = _cops[id]
		if is_instance_valid(cop):
			var d := cop.global_position.distance_to(pos)
			if d < best_d:
				best_d = d
				best = cop
	return best


func _case_say(c: PoliceCase, cat: String) -> void:
	var alive: Array = []
	for cop in c.cops:
		if is_instance_valid(cop):
			alive.append(cop)
	if alive.is_empty():
		return
	var cop: Cop = alive[randi() % alive.size()]
	cop.say(cop_line(cat), 2.0, cat.to_lower())


func _say_from(c: PoliceCase, text: String, cat: String) -> void:
	for cop in c.cops:
		if is_instance_valid(cop):
			cop.say(text, 2.5, cat)
			return


# ------------------------------------------------------------------ сеть

func handle_action(_peer: int, _kind: String, _data: Dictionary) -> bool:
	return false


func on_net_event(kind: String, data: Dictionary) -> void:
	match kind:
		"police_toast":
			Game.notify.emit(_fmt(str(data.get("key", "")), data.get("args", [])), 3.5)
		"cop_spawn":
			if not Net.is_host():
				_spawn_proxy_cop(int(data["id"]), data["pos"], str(data.get("name", "")))
		"cop_pos":
			if not Net.is_host():
				for e in data.get("c", []):
					var cop: Cop = _cops.get(int(e[0]))
					if cop and is_instance_valid(cop):
						cop.set_proxy_target(Vector3(float(e[1]), float(e[2]), float(e[3])), float(e[4]))
		"cop_despawn":
			if not Net.is_host():
				var cop: Node = _cops.get(int(data["id"]))
				_cops.erase(int(data["id"]))
				if cop and is_instance_valid(cop):
					cop.queue_free()
		"police_car":
			if not Net.is_host():
				var id := int(data["id"])
				var car: PoliceCar = _cars.get(id)
				if car == null or not is_instance_valid(car):
					car = _make_car(id)
				car.arrive(data["from"], data["to"], float(data.get("dur", 0.0)))
		"police_car_drive":
			if not Net.is_host():
				var car: PoliceCar = _cars.get(int(data["id"]))
				if car and is_instance_valid(car):
					car.drive_to(data["to"], float(data.get("dur", 0.0)))
		"police_car_leave":
			if not Net.is_host():
				var car: PoliceCar = _cars.get(int(data["id"]))
				_cars.erase(int(data["id"]))
				if car and is_instance_valid(car):
					car.leave()
		"police_arrest":
			if not Net.is_host():
				var p := _player(int(data["peer"]))
				var car: PoliceCar = _cars.get(int(data.get("car", 0)))
				if p:
					p.enter_vehicle(car)
					if car and is_instance_valid(car):
						car.passenger = p
		"police_custody":
			var peer := int(data["peer"])
			var on := bool(data["on"])
			var p := _player(peer)
			if p and not Net.is_host():
				if on:
					p.exit_vehicle(data["pos"])
					p.reset_physics_interpolation()
					if p.has_method("lower_paddle"):
						p.lower_paddle()
				p.in_custody = on
			if peer == Net.my_id():
				if on:
					_hud_timer(float(data.get("sec", 0.0)))
				else:
					_hud_clear()
		"custody_state":
			if int(data.get("peer", 0)) == Net.my_id():
				_hud_timer(float(data.get("left", 0.0)))
		"police_door":
			if not Net.is_host():
				var which := str(data["which"])
				var active := bool(data["active"])
				if which == "jail":
					_jail_closed = active
				else:
					_evidence_open = active
				_apply_door(which, active)


func send_full_state_to(peer: int) -> void:
	for id in _cops:
		var cop: Node3D = _cops[id]
		if is_instance_valid(cop):
			Net.send_event(peer, "cop_spawn", {"id": id, "pos": cop.global_position, "name": cop.name})
	for id in _cars:
		var car: Node3D = _cars[id]
		if is_instance_valid(car):
			Net.send_event(peer, "police_car", {"id": id, "from": car.global_position, "to": car.global_position, "dur": 0.0})
	if _jail_closed:
		Net.send_event(peer, "police_door", {"which": "jail", "active": true})
	if _evidence_open:
		Net.send_event(peer, "police_door", {"which": "evidence", "active": true})
	for jailed in _custody:
		var cu: Custody = _custody[jailed]
		Net.send_event(peer, "police_custody", {"peer": jailed, "on": true, "pos": _cell_pos(), "sec": cu.left})


# ------------------------------------------------------------------ helpers

func _player(peer: int) -> Player:
	var p = Net.players.get(peer)
	return p if p and is_instance_valid(p) else null


func _nearest_player(pos: Vector3) -> Player:
	var best: Player = null
	var best_d := 1e9
	for pid in Net.players:
		var p: Player = Net.players[pid]
		if p and is_instance_valid(p) and not p.dead:
			var d := p.global_position.distance_to(pos)
			if d < best_d:
				best_d = d
				best = p
	return best


func _pname(p: Player) -> String:
	if p and p.name_plate:
		return p.name_plate.text
	return "P%d" % (p.peer_id if p else 0)


func _toast_all(key: String, args: Array = []) -> void:
	Net.broadcast_event("police_toast", {"key": key, "args": args})


func _fmt(key: String, args) -> String:
	var s := tr(key)
	if args is Array and not (args as Array).is_empty() and "%" in s:
		s = s % args
	return s


func _hud_timer(sec: float) -> void:
	var hud = Game.world.hud if Game.world else null
	if hud and hud.has_method("set_timer"):
		hud.set_timer(maxf(sec, 0.0), "POLICE_CUSTODY")


func _hud_clear() -> void:
	var hud = Game.world.hud if Game.world else null
	if hud and hud.has_method("clear_timer"):
		hud.clear_timer()
