class_name Fire
extends Node3D
## Огонь (§7.4): контактный граф на тике 30 — горит → соседи загораются. Игрок в огне → урон/смерть.
## Пожарные: NPC с конусом воды (та же жидкость). Сгоревший лот помечается burned.

const SPREAD_CHANCE := 0.06 # за тик на соседа
const PLAYER_BURN_DIST := 0.7
const FIREFIGHTER_DELAY := 18.0

var lit_bodies: Array[ItemBody] = []
var fire_time := 0.0 # сколько подряд что-то горит
var firefighter: Npc = null
var _ff_timer := 0.0
var _ff_spray_timer := 0.0
var _burned_lot_checked := {}


func system_name() -> String:
	return "Fire"


func _ready() -> void:
	Net.item_spawned.connect(_on_item_spawned)


func _on_item_spawned(b: Node) -> void:
	if b is ItemBody:
		b.state_changed.connect(_on_item_state)


func _on_item_state(b: ItemBody) -> void:
	if b.lit and not lit_bodies.has(b):
		lit_bodies.append(b)
	elif not b.lit and lit_bodies.has(b):
		lit_bodies.erase(b)


func _physics_process(delta: float) -> void:
	if not Net.is_host():
		return
	var any := false
	# freed bodies can't be erased from a typed array by value — rebuild the list instead
	var keep: Array[ItemBody] = []
	for b in lit_bodies:
		if is_instance_valid(b) and b.lit:
			keep.append(b)
	lit_bodies = keep
	for b in lit_bodies.duplicate():
		if not is_instance_valid(b) or not b.lit:
			continue
		any = true
		b.burn_tick(delta)
		# соседи по контакту
		for other in b.get_colliding_bodies():
			if other is ItemBody and not other.lit and other.is_flammable() and randf() < SPREAD_CHANCE:
				other.ignite()
			elif other is Player and not other.burning:
				other.set_burning(true)
		# вложенные тоже горят
		for n in b.nested:
			if is_instance_valid(n) and not n.lit and n.is_flammable() and randf() < SPREAD_CHANCE * 2.0:
				n.ignite()
		# игроки рядом
		for pid in Net.players:
			var p = Net.players[pid]
			if is_instance_valid(p) and not p.dead and not p.burning and p.global_position.distance_to(b.global_position) < PLAYER_BURN_DIST:
				p.set_burning(true)
		# лужи под горящим
		var liq := _liquids()
		if liq:
			liq.ignite_at(b.global_position)
		# лот сгорел?
		if b.lot_id != "" and b.burnt:
			_check_lot_burned(b.lot_id)
	if any:
		fire_time += delta
		_ff_timer += delta
		if _ff_timer > FIREFIGHTER_DELAY and firefighter == null:
			_spawn_firefighter()
		if fire_time > 40.0:
			Achievements.unlock("arsonist")
	else:
		fire_time = 0.0
		_ff_timer = 0.0
	_firefighter_tick(delta)


func _liquids() -> Liquids:
	return Game.world.system("Liquids") if Game.world else null


func _check_lot_burned(lot_id: String) -> void:
	if _burned_lot_checked.has(lot_id) or Game.is_lot_burned(lot_id):
		return
	var total := 0
	var burnt := 0
	for nid in Net.items:
		var b = Net.items[nid]
		if is_instance_valid(b) and b.lot_id == lot_id:
			total += 1
			if b.burnt:
				burnt += 1
	if total > 0 and burnt >= maxi(3, total / 2):
		_burned_lot_checked[lot_id] = true
		Game.lot_burned(lot_id)
		Achievements.unlock("burned_garage")
		Game.notify.emit(tr("NOTIFY_LOT_BURNED"), 4.0)
		if Game.world and Game.world.has_method("on_lot_burned"):
			Game.world.on_lot_burned(lot_id)
		var police = Game.world.system("Police") if Game.world else null
		if police:
			police.trigger(Types.PoliceTrigger.ARSON, _fire_center())


func _fire_center() -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for b in lit_bodies:
		if is_instance_valid(b):
			sum += b.global_position
			n += 1
	return sum / n if n > 0 else Vector3.ZERO


# ------------------------------------------------------------------ пожарные

func _spawn_firefighter() -> void:
	var center := _fire_center()
	firefighter = Npc.new()
	firefighter.npc_group = "firefighter"
	firefighter.display_name = tr("NPC_FIREFIGHTER")
	firefighter.body_color = Color(0.85, 0.15, 0.1)
	firefighter.hat = true
	firefighter.speed = 4.5
	get_parent().add_child(firefighter)
	firefighter.global_position = center + Vector3(randf_range(-1, 1), 0.2, 1).normalized() * 14.0 + Vector3(0, 1, 0)
	firefighter.say(tr("FF_ARRIVE"), 3.0, "arrive")
	AudioBus.play_at("siren", firefighter.global_position, 4.0, 0.05)
	Game.stat_add("firefighter_calls")
	if Net.peer_count() > 1:
		Net.broadcast_event("npc_spawn", {"kind": "firefighter", "pos": firefighter.global_position, "path": str(firefighter.get_path())})


func _firefighter_tick(delta: float) -> void:
	if firefighter == null or not is_instance_valid(firefighter):
		return
	var target: ItemBody = null
	var best := 1e9
	for b in lit_bodies:
		if is_instance_valid(b):
			var d := b.global_position.distance_to(firefighter.global_position)
			if d < best:
				best = d
				target = b
	var liq := _liquids()
	var burning_puddle: Liquids.Puddle = null
	if liq:
		for p in liq.puddles:
			if p.burning:
				burning_puddle = p
				break
	var target_pos: Vector3
	if target:
		target_pos = target.global_position
	elif burning_puddle:
		target_pos = burning_puddle.global_position
	else:
		# все потушено — тушит горящих игроков, потом уезжает
		for pid in Net.players:
			var p = Net.players[pid]
			if is_instance_valid(p) and p.burning:
				target_pos = p.global_position
				target = null
				break
		if target_pos == Vector3.ZERO:
			_ff_timer -= delta
			if _ff_timer < -8.0:
				firefighter.say(tr("FF_LEAVE"), 2.0, "leave")
				if Net.peer_count() > 1:
					Net.broadcast_event("npc_despawn", {"path": str(firefighter.get_path())})
				firefighter.queue_free()
				firefighter = null
				_ff_timer = 0.0
			return
	var d := firefighter.global_position.distance_to(target_pos)
	if d > 3.5:
		firefighter.move_to(target_pos)
	else:
		firefighter.moving = false
		firefighter.face(target_pos)
		_ff_spray_timer -= delta
		if _ff_spray_timer <= 0.0 and liq:
			_ff_spray_timer = 0.3
			var from := firefighter.global_position + Vector3(0, 1.3, 0)
			var dir := (target_pos - from).normalized()
			liq.pour(Types.LiquidId.WATER, from + dir * 0.8, dir, 0.3, firefighter)
			if randf() < 0.1:
				firefighter.say(tr("FF_SPRAY"), 1.5, "spray")
			if Net.peer_count() > 1:
				Net.broadcast_event("npc_spray", {"path": str(firefighter.get_path()), "from": from + dir * 0.8, "dir": dir})


func ignite_position(pos: Vector3, radius: float) -> void:
	for nid in Net.items:
		var b = Net.items[nid]
		if is_instance_valid(b) and b.is_flammable() and b.global_position.distance_to(pos) < radius:
			b.ignite()
	var liq := _liquids()
	if liq:
		liq.ignite_at(pos)
