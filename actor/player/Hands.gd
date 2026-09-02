class_name Hands
extends Node3D
## Руки (§6.1). Хват без инвентаря. Физику хвата считает ХОСТ для всех игроков;
## локальный клиент только выбирает цель и шлёт запрос.
## hand 0 = правая, hand 1 = левая. Мышь ведёт active_hand (по умолчанию правую);
## Q переключает. Вещь сидит В ладони, а не «висит в воздухе» перед лицом.
## Длина руки короткая — высоко/далеко не достать без лестницы.

signal held_changed()

## Дальность луча взгляда / срыва хвата (≈ длина руки + чуть-чуть).
const REACH := 1.45
## Мягкий предел ладони от плеча (визуал + куда едет вещь).
const ARM_LEN := 1.08
const FOLLOW_K := 22.0
const MAX_FOLLOW_SPEED := 12.0
const TEAM_SOLO_SPEED := 0.9
## Насколько центр вещи выше ладони (сидит «в кулаке»).
const PALM_LIFT := 0.42

@onready var player: Player = get_node("../..") as Player
@onready var hand_r: Node3D = $HandR
@onready var hand_l: Node3D = $HandL

var held: Array = [null, null] # ItemBody
var two_hands_same := false # обе руки на одном предмете
var flip_held := false # E удерживается → вещь вверх дном (вытряхнуть / вылить)
var active_hand := 0 # 0 правая (старт), 1 левая — за мышкой
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
	# сначала активная — «мышью берём той рукой, которой целимся»
	if not two_hands_same and held[active_hand] == null:
		return active_hand
	var other := 1 - active_hand
	if not two_hands_same and held[other] == null:
		return other
	return -1


func hands_empty() -> bool:
	return held[0] == null and held[1] == null


func hand_node(hand: int) -> Node3D:
	return hand_r if hand == 0 else hand_l


# ------------------------------------------------------------------ локальный ввод (владелец)

func local_swap_hand() -> void:
	active_hand = 1 - active_hand
	player.say(tr("HANDS_ACTIVE_R" if active_hand == 0 else "HANDS_ACTIVE_L"), 1.1)


func local_try_grab() -> void:
	var target = player.look_target()
	if target is ItemBody:
		var b: ItemBody = target
		if b.nested_in and not b.visible:
			return
		# не достаём через полкарты — точка луча (поверхность), не центр огромного шкафа
		if not player.can_reach_point(player._look_point()):
			player.say(tr("HANDS_TOO_FAR"), 1.4)
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
		if not player.can_reach_point(player._look_point()):
			player.say(tr("HANDS_TOO_FAR"), 1.4)
			return
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
	# отпускаем активную, если в ней что-то есть (и это не общий двухрукий хват)
	var hand := active_hand
	if two_hands_same or held[hand] == null:
		hand = 0 if held[0] != null else 1
	Net.request_release(hand, throw_force)


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
	# сразу притянуть в ладонь — иначе тяжёлое/TEAM на дистанции срывается в первый же кадр
	if not (b.arch.size_class == Types.SizeClass.TEAM and b.held_by.size() >= 2):
		var palm: Vector3
		if two_hands_same:
			palm = (hand_r.global_position + hand_l.global_position) * 0.5
		else:
			palm = hand_node(hand).global_position
		b.global_position = palm + Vector3.UP * (b.arch.dims.y * 0.5 * b.def.scale * PALM_LIFT)
		b.linear_velocity = Vector3.ZERO
		b.reset_physics_interpolation()
	if b.arch.size_class == Types.SizeClass.TEAM:
		player.encumbrance = 0.45 if b.held_by.size() < 2 else 0.7
	elif b.mass > 12.0:
		player.encumbrance = 0.7
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
	if hands_empty():
		player.encumbrance = 1.0
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
	var target: Vector3
	var team := b.arch.size_class == Types.SizeClass.TEAM
	var both := two_hands_same or team
	var half_h := b.arch.dims.y * 0.5 * b.def.scale
	if both:
		# двумя руками — вещь между ладонями, обе едут за одной мышью (позиции рук уже сведены)
		target = (hand_r.global_position + hand_l.global_position) * 0.5 + Vector3.UP * (half_h * PALM_LIFT)
	else:
		var anchor := hand_node(hand)
		# В ладони: центр вещи чуть выше кулака, без выноса вперёд «в воздух»
		target = anchor.global_position + Vector3.UP * (half_h * PALM_LIFT)
	# пассажир в кабине держит вещь «на ремне» (§10): тело кинематическое, просто едет на коленях
	if player.in_vehicle and b.freeze:
		b.global_position = target + Vector3.DOWN * 0.05
		b.global_basis = Basis.looking_at(-player.head.global_basis.z * Vector3(1, 0, 1) if (player.head.global_basis.z * Vector3(1, 0, 1)).length() > 0.01 else Vector3.FORWARD, Vector3.UP)
		return
	# TEAM: усредняем по всем держащим
	if team and b.held_by.size() >= 2:
		var sum := Vector3.ZERO
		for h in b.held_by:
			var hp: Player = h.player
			sum += (h.hand_r.global_position + h.hand_l.global_position) * 0.5
		target = sum / b.held_by.size() + Vector3.UP * (half_h * PALM_LIFT)
		if b.held_by[0] != self:
			return # считает первый держащий
	var to := target - b.global_position
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
		k = 8.0
		max_speed = 4.0
	elif two_hands_same:
		k = 26.0
	if player.drunk > 0.2:
		k *= 1.0 - player.drunk * 0.5
		to += Vector3(sin(Time.get_ticks_msec() * 0.004), 0, cos(Time.get_ticks_msec() * 0.0033)) * player.drunk * 0.15
	# дальше REACH от плеча — рвётся хват (TEAM/heavy можно волочить дальше)
	var shoulder := player.shoulder_world(hand if not both else active_hand)
	var max_sep := REACH * 1.35
	if team:
		max_sep = REACH * 2.8
	elif heavy:
		max_sep = REACH * 1.9
	if b.global_position.distance_to(shoulder) > max_sep:
		host_release_body(b)
		return
	var vel := to * k
	if vel.length() > max_speed:
		vel = vel.normalized() * max_speed
	b.linear_velocity = vel + player.velocity * 0.55
	# ориентация: лицом от игрока, стоймя
	var want_basis := Basis.looking_at(-player.head.global_basis.z * Vector3(1, 0, 1) if (player.head.global_basis.z * Vector3(1, 0, 1)).length() > 0.01 else Vector3.FORWARD, Vector3.UP)
	if flip_held and (b.def.has_facet(Types.Facet.SHAKE_OUT) or b.arch.container or b.def.is_container() or b.def.liquid_id != Types.LiquidId.NONE):
		want_basis = want_basis.rotated(want_basis.x, PI * 0.85)
	var q_cur := b.global_basis.get_rotation_quaternion()
	var q_want := want_basis.get_rotation_quaternion()
	var q_delta := q_want * q_cur.inverse()
	var angle := q_delta.get_angle()
	if angle > PI:
		angle -= TAU
	var axis := q_delta.get_axis() if absf(angle) > 0.001 else Vector3.UP
	b.angular_velocity = axis * angle * (8.0 if two_hands_same else 5.5)
	# нёс в руках и оно горит — ты тоже
	if b.lit:
		player.set_burning(true)
	# грузчик замедляется
	if team or heavy:
		player.encumbrance = 0.45 if (team and b.held_by.size() < 2) else 0.7
	else:
		player.encumbrance = 1.0
