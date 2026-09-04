class_name Hands
extends Node3D
## Руки (§6.1). Хват без инвентаря. Физику хвата считает ХОСТ для всех игроков;
## локальный клиент только выбирает цель и шлёт запрос.
## hand 0 = правая, hand 1 = левая. Мышь ведёт active_hand (по умолчанию правую);
## Q переключает. Вещь сидит В ладони. Колесо — согнуть/разогнуть (arm_len).
## Дальность хвата короткая — высоко/далеко не достать без лестницы.

const _Feel := preload("res://core/FeelLog.gd")

signal held_changed()

## Дальность луча взгляда / срыва хвата (≈ длина руки + чуть-чуть).
const REACH := 1.45
## Полностью разогнутая рука (ладонь от плеча).
const ARM_LEN := 0.92
## Максимально согнутая — вещь у груди, не в камере.
const ARM_LEN_MIN := 0.30
## Шаг колеса «согнуть / разогнуть».
const ARM_STEP := 0.07
## Насколько центр вещи выше ладони (сидит «в кулаке»).
const PALM_LIFT := 0.42
const ANG_DEADZONE := 0.10

@onready var player: Player = get_node("../..") as Player
@onready var hand_r: Node3D = $HandR
@onready var hand_l: Node3D = $HandL

var held: Array = [null, null] # ItemBody
var two_hands_same := false # обе руки на одном предмете
var flip_held := false # E удерживается → вещь вверх дном (вытряхнуть / вылить)
var active_hand := 0 # 0 правая (старт), 1 левая — за мышкой
## Текущая длина руки от плеча (колесо): притянуть / оттянуть вещь.
var arm_len: float = ARM_LEN * 0.55
var _drop_timer := 0.0


func local_nudge_arm(dir: float) -> void:
	## dir > 0 — разогнуть (дальше), < 0 — согнуть (ближе к себе).
	if player == null or player.paddle_up or player.dead or player.cinematic:
		return
	arm_len = clampf(arm_len + dir * ARM_STEP, ARM_LEN_MIN, ARM_LEN)


func set_arm_len_norm(t: float) -> void:
	arm_len = lerpf(ARM_LEN_MIN, ARM_LEN, clampf(t, 0.0, 1.0))


func arm_len_norm() -> float:
	var span := ARM_LEN - ARM_LEN_MIN
	if span <= 0.001:
		return 1.0
	return clampf((arm_len - ARM_LEN_MIN) / span, 0.0, 1.0)


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
		var look_pt := player._look_point()
		var shoulder_d := player.shoulder_world(active_hand).distance_to(look_pt)
		var center_d := player.shoulder_world(active_hand).distance_to(b.global_position)
		var ok_reach := player.can_reach_point(look_pt)
		_Feel.grab("try", b.def.id if b.def else "?", shoulder_d, look_pt.distance_to(player.camera.global_position), REACH, arm_len, ok_reach, "center=%.2f nid=%d" % [center_d, b.net_id])
		if not ok_reach:
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
		var look_pt2 := player._look_point()
		var ok2 := player.can_reach_point(look_pt2)
		_Feel.grab("special", str(target.name), player.shoulder_world(active_hand).distance_to(look_pt2), look_pt2.distance_to(player.camera.global_position), REACH, arm_len, ok2, str(target.get_path()))
		if not ok2:
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
		_attach_held(b, 0) # переносим с одной ладони на Hands (середина)
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
		var snap_d := b.global_position.distance_to(palm)
		_Feel.grab("host", b.def.id if b.def else "?", player.shoulder_world(hand).distance_to(b.global_position), snap_d, REACH, arm_len, true, "hand=%d snap_err=%.2f mass=%.1f" % [hand, snap_d, b.mass])
		b.global_position = palm + Vector3.UP * (b.arch.dims.y * 0.5 * b.def.scale * PALM_LIFT)
		b.linear_velocity = Vector3.ZERO
		b.reset_physics_interpolation()
		_attach_held(b, hand)
	if b.arch.size_class == Types.SizeClass.TEAM:
		player.encumbrance = 0.45 if b.held_by.size() < 2 else 0.7
	elif b.mass > 12.0:
		player.encumbrance = 0.7
	AudioBus.play_at("grab", b.global_position, -8.0)
	if b.def.has_facet(Types.Facet.ALIVE):
		AudioBus.play_at("squeak", b.global_position, -2.0, 0.4)
	var yards: Node = Game.world.system("YardZones") if Game.world else null
	if yards and yards.has_method("on_host_grab"):
		yards.on_host_grab(player, b)
	_sync()


func host_release(hand: int, throw_force: float) -> void:
	var b: ItemBody = held[hand] if is_instance_valid(held[hand]) else null
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
		_detach_held(b)
		b.on_released(self)
		# после снятия exception: если вещь ещё в капсуле — чуть вперёд взгляда, без ракеты
		if throw_force <= 0.0 and b.held_by.is_empty():
			var chest := player.global_position + Vector3(0, 0.9, 0)
			if b.global_position.distance_to(chest) < 0.8:
				b.global_position += -player.head.global_basis.z * 0.28 + Vector3.UP * 0.05
				b.linear_velocity = Vector3.ZERO
				b.reset_physics_interpolation()
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


func _attach_held(b: ItemBody, hand: int) -> void:
	## Вещь — ребёнок ладони: едет с игроком без лага physics/_process.
	if b.arch.size_class == Types.SizeClass.TEAM:
		return # TEAM волочётся в мире
	var anchor: Node3D = self if two_hands_same else hand_node(hand)
	if b.get_parent() == anchor:
		return
	var gt := b.global_transform
	var old := b.get_parent()
	if old:
		old.remove_child(b)
	anchor.add_child(b)
	b.global_transform = gt
	b.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	b.set_meta("_hold_attached", true)


func _detach_held(b: ItemBody) -> void:
	if not is_instance_valid(b):
		return
	if not b.has_meta("_hold_attached") and b.get_parent() != hand_r and b.get_parent() != hand_l and b.get_parent() != self:
		return
	var gt := b.global_transform
	var old := b.get_parent()
	var root: Node = null
	if Game.world and Game.world.has_method("items_root"):
		root = Game.world.items_root()
	if root == null:
		root = Game.world
	if old:
		old.remove_child(b)
	if root:
		root.add_child(b)
	b.global_transform = gt
	b.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	if b.has_meta("_hold_attached"):
		b.remove_meta("_hold_attached")
	b.reset_physics_interpolation()


func _process(delta: float) -> void:
	# после Player._anim_arms (родитель раньше детей) — кинематика в ладони без лага physics
	if not Net.is_host() or not is_inside_tree():
		return
	_follow_held(delta)


func _physics_process(delta: float) -> void:
	if not Net.is_host():
		return
	_drop_timer -= delta
	# пьяный роняет (§6.4)
	if player.drunk > 0.4 and _drop_timer <= 0.0:
		_drop_timer = randf_range(2.0, 6.0)
		if randf() < player.drunk * 0.5:
			var b := any_held()
			if b:
				host_release_body(b)
				player.say(tr("HANDS_SLIPPED"))


func _follow_held(delta: float) -> void:
	var processed: Array = []
	for i in 2:
		# валидность проверяем ДО типизированного присваивания: снесённая вещь (разбилась,
		# сгорела) даёт "assign invalid previously freed instance" каждый кадр
		if not is_instance_valid(held[i]):
			held[i] = null
			continue
		var b: ItemBody = held[i]
		if b.nested_in != null:
			held[i] = null
			continue
		if processed.has(b):
			continue
		processed.append(b)
		_follow(b, i, delta)


func _follow(b: ItemBody, hand: int, delta: float) -> void:
	var target: Vector3
	var team := b.arch.size_class == Types.SizeClass.TEAM
	var both := two_hands_same or team
	var half_h := b.arch.dims.y * 0.5 * b.def.scale
	if both:
		target = (hand_r.global_position + hand_l.global_position) * 0.5 + Vector3.UP * (half_h * PALM_LIFT)
	else:
		target = hand_node(hand).global_position + Vector3.UP * (half_h * PALM_LIFT)
	if player.in_vehicle:
		b.global_position = target + Vector3.DOWN * 0.05
		var vf := -player.head.global_basis.z
		vf.y = 0.0
		b.global_basis = Basis.looking_at(vf.normalized() if vf.length_squared() > 0.0001 else Vector3.FORWARD, Vector3.UP)
		b.reset_physics_interpolation()
		return
	if team and b.held_by.size() >= 2:
		var sum := Vector3.ZERO
		for h in b.held_by:
			sum += (h.hand_r.global_position + h.hand_l.global_position) * 0.5
		target = sum / b.held_by.size() + Vector3.UP * (half_h * PALM_LIFT)
		if b.held_by[0] != self:
			return
	var flat_fwd := -player.head.global_basis.z
	flat_fwd.y = 0.0
	if flat_fwd.length_squared() < 0.0001:
		flat_fwd = Vector3.FORWARD
	else:
		flat_fwd = flat_fwd.normalized()
	var bulk := maxf(b.arch.dims.x, b.arch.dims.z) * 0.5 * b.def.scale
	target += flat_fwd * (0.06 + bulk * 0.45)
	if player.drunk > 0.2:
		target += Vector3(sin(Time.get_ticks_msec() * 0.004), 0, cos(Time.get_ticks_msec() * 0.0033)) * player.drunk * 0.08
	var shoulder := player.shoulder_world(hand if not both else active_hand)
	var max_sep := REACH * 1.35
	var heavy := b.mass > 12.0
	if team:
		max_sep = REACH * 2.8
	elif heavy:
		max_sep = REACH * 1.9
	if target.distance_to(shoulder) > max_sep:
		host_release_body(b)
		return
	var want_basis := Basis.looking_at(flat_fwd, Vector3.UP)
	if flip_held and (b.def.has_facet(Types.Facet.SHAKE_OUT) or b.arch.container or b.def.is_container() or b.def.liquid_id != Types.LiquidId.NONE):
		want_basis = want_basis.rotated(want_basis.x, PI * 0.85)
	# обычный хват — жёсткий snap (lerp давал err 0.3–0.7 на бегу). TEAM соло — медленно.
	var soft := team and b.held_by.size() < 2
	if soft:
		var blend := 1.0 - exp(-4.0 * delta)
		b.global_position = b.global_position.lerp(target, blend)
		var q_cur := b.global_basis.get_rotation_quaternion()
		b.global_basis = Basis(q_cur.slerp(want_basis.get_rotation_quaternion(), blend))
	else:
		b.global_position = target
		b.global_basis = want_basis
	b.linear_velocity = player.velocity
	b.angular_velocity = Vector3.ZERO
	b.reset_physics_interpolation()
	var err := b.global_position.distance_to(target)
	_Feel.hold(
		b.def.id if b.def else "?",
		err,
		0.0,
		0.0,
		b.global_position.distance_to(shoulder),
		max_sep,
		player.velocity.length()
	)
	if b.lit:
		player.set_burning(true)
	if team or heavy:
		player.encumbrance = 0.45 if (team and b.held_by.size() < 2) else 0.7
	else:
		player.encumbrance = 1.0
