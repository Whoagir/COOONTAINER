class_name Hands
extends Node3D
## Руки (§6.1). Хват без инвентаря. Физику хвата считает ХОСТ для всех игроков;
## локальный клиент только выбирает цель и шлёт запрос.
## hand 0 = правая (главная), hand 1 = левая (вторая рука / второй предмет).

signal held_changed()

const REACH := 2.6
const FOLLOW_K := 14.0
const MAX_FOLLOW_SPEED := 9.0
const TEAM_SOLO_SPEED := 0.9

@onready var player: Player = get_node("../..") as Player
@onready var hand_r: Node3D = $HandR
@onready var hand_l: Node3D = $HandL

var held: Array = [null, null] # ItemBody
var two_hands_same := false # обе руки на одном предмете
var flip_held := false # E удерживается → вещь вверх дном (вытряхнуть / вылить)
var _drop_timer := 0.0


func other_held(b: ItemBody) -> ItemBody:
	for h in held:
		if h != null and h != b and is_instance_valid(h):
			return h
	return null


func any_held() -> ItemBody:
	for h in held:
		if h != null and is_instance_valid(h):
			return h
	return null


func is_holding(b: ItemBody) -> bool:
	return held[0] == b or held[1] == b


func holds_tag(tag: String) -> ItemBody:
	for h in held:
		if h and is_instance_valid(h) and h.def.tags.has(tag):
			return h
	return null


func free_hand() -> int:
	if held[0] == null:
		return 0
	if held[1] == null and not two_hands_same:
		return 1
	return -1


func hands_empty() -> bool:
	return held[0] == null and held[1] == null


# ------------------------------------------------------------------ локальный ввод (владелец)

func local_try_grab() -> void:
	var target = player.look_target()
	if target is ItemBody:
		var b: ItemBody = target
		if b.nested_in and not b.visible:
			return
		var hand := free_hand()
		if b.arch.size_class == Types.SizeClass.TWO_HAND and not hands_empty():
			player.say(tr("HANDS_NEED_TWO"))
			return
		if hand == -1:
			return
		Net.request_grab(b.net_id, hand)
		return
	# хват за ручку тачки / за NPC / за дверь — делегируем миру
	if target and target.has_method("on_grab"):
		Net.request_action("grab_special", {"path": str(target.get_path())})


func local_second_hand() -> void:
	var b := any_held()
	if b == null:
		return
	if b.arch.size_class == Types.SizeClass.ONE_HAND or b.arch.size_class == Types.SizeClass.TWO_HAND or b.def.is_fragile():
		Net.request_grab(b.net_id, 1)


func local_release(throw_force: float = 0.0) -> void:
	if hands_empty():
		return
	Net.request_release(0 if held[0] != null else 1, throw_force)


# ------------------------------------------------------------------ хост

func host_grab(b: ItemBody, hand: int) -> void:
	if player.dead or player.cuffed:
		return
	if b.worn_by != null:
		return
	if b.nested_in:
		if not b.visible:
			return
		b.unnest()
	# вторая рука на том же предмете
	if is_holding(b) and hand == 1 and not two_hands_same:
		two_hands_same = true
		held[1] = b
		AudioBus.play_at("grab", b.global_position, -8.0)
		_sync()
		return
	if b.arch.size_class == Types.SizeClass.TWO_HAND:
		if not hands_empty():
			return
		held[0] = b
		held[1] = b
		two_hands_same = true
	elif b.arch.size_class == Types.SizeClass.TEAM:
		# комод: до двух игроков. Один — волочёт медленно (§6.1).
		if not hands_empty():
			return
		if b.held_by.size() >= 2:
			return
		held[0] = b
		held[1] = b
		two_hands_same = true
	elif b.arch.size_class == Types.SizeClass.VEHICLE:
		return
	else:
		if held[hand] != null:
			hand = free_hand()
			if hand == -1:
				return
		held[hand] = b
	b.on_grabbed(self)
	b.sleeping = false
	AudioBus.play_at("grab", b.global_position, -8.0)
	if b.def.has_facet(Types.Facet.ALIVE):
		AudioBus.play_at("squeak", b.global_position, -2.0, 0.4)
	_sync()


func host_release(hand: int, throw_force: float) -> void:
	var b: ItemBody = held[hand]
	if b == null:
		b = any_held()
	if b == null:
		return
	host_release_body(b, throw_force)


func host_release_body(b: ItemBody, throw_force: float = 0.0) -> void:
	if not is_holding(b):
		return
	for i in 2:
		if held[i] == b:
			held[i] = null
	two_hands_same = false
	if is_instance_valid(b):
		b.on_released(self)
		# отпустил над открытой сумкой/чемоданом/ящиком → внутрь (§6.2, §7.2 вложенность)
		if throw_force <= 0.0 and b.held_by.is_empty():
			var target = player.look_target()
			if target is ItemBody and target != b and (target.is_open or target.open_drawers > 0) and target.can_nest(b):
				target.nest_child(b)
				AudioBus.play_at("pocket", target.global_position, -6.0)
				_sync()
				return
		if throw_force > 0.0 and b.held_by.is_empty():
			var dir := -player.head.global_basis.z
			b.apply_central_impulse(dir * throw_force * b.mass + Vector3.UP * 0.5 * b.mass)
			AudioBus.play_at("whoosh", b.global_position, -6.0)
			Game.stat_add("throws")
	_sync()


func host_release_all() -> void:
	for h in held.duplicate():
		if h:
			host_release_body(h)


func _sync() -> void:
	held_changed.emit()
	if Net.peer_count() > 1:
		var ids: Array = [held[0].net_id if held[0] else 0, held[1].net_id if held[1] else 0]
		Net.broadcast_event("hands", {"peer": player.peer_id, "h": ids, "same": two_hands_same})


## Клиентская сторона: узнали, что в руках у игрока (для UI/анимации).
func apply_remote_hands(ids: Array, same: bool) -> void:
	for i in 2:
		var b = Net.items.get(int(ids[i]))
		held[i] = b if b and is_instance_valid(b) else null
	two_hands_same = same
	held_changed.emit()


func _physics_process(delta: float) -> void:
	if not Net.is_host():
		return
	if not is_inside_tree():
		return
	_drop_timer -= delta
	var processed: Array = []
	for i in 2:
		var b: ItemBody = held[i]
		if b == null:
			continue
		if not is_instance_valid(b) or b.nested_in != null:
			held[i] = null
			continue
		if processed.has(b):
			continue
		processed.append(b)
		_follow(b, i, delta)
	# пьяный роняет (§6.4)
	if player.drunk > 0.4 and _drop_timer <= 0.0:
		_drop_timer = randf_range(2.0, 6.0)
		if randf() < player.drunk * 0.5:
			var b := any_held()
			if b:
				host_release_body(b)
				player.say(tr("HANDS_SLIPPED"))


func _follow(b: ItemBody, hand: int, delta: float) -> void:
	var anchor: Node3D
	var target: Vector3
	var team := b.arch.size_class == Types.SizeClass.TEAM
	var both := two_hands_same or team
	if both:
		target = player.head.global_position + (-player.head.global_basis.z) * (0.75 + b.arch.dims.z * 0.5 * b.def.scale) + Vector3.DOWN * 0.3
	else:
		anchor = hand_r if hand == 0 else hand_l
		target = anchor.global_position + (-player.head.global_basis.z) * (0.25 + b.arch.dims.z * 0.4 * b.def.scale)
	# пассажир в кабине держит вещь «на ремне» (§10): тело кинематическое, просто едет на коленях
	if player.in_vehicle and b.freeze:
		b.global_position = target + Vector3.DOWN * 0.15
		b.global_basis = Basis.looking_at(-player.head.global_basis.z * Vector3(1, 0, 1) if (player.head.global_basis.z * Vector3(1, 0, 1)).length() > 0.01 else Vector3.FORWARD, Vector3.UP)
		return
	# TEAM: усредняем по всем держащим
	if team and b.held_by.size() >= 2:
		var sum := Vector3.ZERO
		for h in b.held_by:
			var hp: Player = h.player
			sum += hp.head.global_position + (-hp.head.global_basis.z) * 0.9 + Vector3.DOWN * 0.3
		target = sum / b.held_by.size()
		if b.held_by[0] != self:
			return # считает первый держащий
	var origin_offset := b.global_transform.basis * Vector3(0, b.arch.dims.y * 0.5 * b.def.scale, 0)
	var to := target - (b.global_position + origin_offset)
	var k := FOLLOW_K
	var max_speed := MAX_FOLLOW_SPEED
	var heavy := b.mass > 12.0
	if team:
		if b.held_by.size() < 2:
			k = 3.0
			max_speed = TEAM_SOLO_SPEED
		else:
			k = 6.0
			max_speed = 2.5
	elif heavy:
		k = 6.0
		max_speed = 3.0
	elif two_hands_same:
		k = 18.0
	if player.drunk > 0.2:
		k *= 1.0 - player.drunk * 0.5
		to += Vector3(sin(Time.get_ticks_msec() * 0.004), 0, cos(Time.get_ticks_msec() * 0.0033)) * player.drunk * 0.15
	# дальше REACH — рвётся хват
	if to.length() > REACH * 1.4:
		host_release_body(b)
		return
	var vel := to * k
	if vel.length() > max_speed:
		vel = vel.normalized() * max_speed
	b.linear_velocity = vel + player.velocity * 0.5
	# ориентация: лицом к игроку, стоймя
	var want_basis := Basis.looking_at(-player.head.global_basis.z * Vector3(1, 0, 1) if (player.head.global_basis.z * Vector3(1, 0, 1)).length() > 0.01 else Vector3.FORWARD, Vector3.UP)
	if flip_held and (b.def.has_facet(Types.Facet.SHAKE_OUT) or b.arch.container or b.def.is_container() or b.def.liquid_id != Types.LiquidId.NONE):
		# удерживаемая E → переворачиваем: книга трясётся, сумка вытряхивается, бутылка льётся
		want_basis = want_basis.rotated(want_basis.x, PI * 0.85)
	var q_cur := b.global_basis.get_rotation_quaternion()
	var q_want := want_basis.get_rotation_quaternion()
	var q_delta := q_want * q_cur.inverse()
	var angle := q_delta.get_angle()
	if angle > PI:
		angle -= TAU
	var axis := q_delta.get_axis() if absf(angle) > 0.001 else Vector3.UP
	b.angular_velocity = axis * angle * (6.0 if two_hands_same else 4.0)
	# нёс в руках и оно горит — ты тоже
	if b.lit:
		player.set_burning(true)
	# грузчик замедляется
	if team or heavy:
		player.encumbrance = 0.45 if (team and b.held_by.size() < 2) else 0.7
	else:
		player.encumbrance = 1.0
