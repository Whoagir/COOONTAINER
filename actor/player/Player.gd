class_name Player
extends CharacterBody3D
## 1P тело (§6). Владелец двигает себя и шлёт трансформ хосту; хост считает хват/урон/смерть.

signal died(reason: String)
signal respawned()
signal said(text: String)

const SPEED := 4.6
const SPRINT_MULT := 1.55
const JUMP := 4.2
const MOUSE_SENS_DEFAULT := 0.0022
const FLAG_TALK := 1
const FLAG_DEAD := 4
const FLAG_CUFFED := 8
const FLAG_BURN := 16
const FLAG_PADDLE := 32
const FLAG_SPRINT := 64
const FLAG_PAINT := 128

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var hands: Hands = $Head/Hands
@onready var body_mesh: MeshInstance3D = $Body
@onready var head_mesh: MeshInstance3D = $Head/HeadMesh
@onready var name_plate: Label3D = $NamePlate
@onready var say_label: Label3D = $SayLabel
@onready var pockets_root: Node3D = $Pockets
@onready var wear_slot: Node3D = $Body/WearSlot
@onready var talk_icon: MeshInstance3D = $Head/TalkIcon
@onready var paddle_mount: Node3D = $Head/Hands/PaddleMount
@onready var look_ray: RayCast3D = $Head/Camera3D/LookRay
@onready var arm_r: MeshInstance3D = $Head/Hands/HandR/Arm
@onready var arm_l: MeshInstance3D = $Head/Hands/HandL/Arm

var peer_id: int = 1
var mouse_sens := MOUSE_SENS_DEFAULT
var hp := 100.0
var burning := false
var burn_time := 0.0
var drunk := 0.0
var dead := false
var cuffed := false
var encumbrance := 1.0
var slip := 0.0 # 0..1 от луж
var stuck := 0.0 # клей
var paint_color: Color = Color(0, 0, 0, 0)
var worn: ItemBody = null
var pockets: Array = [] # ItemBody
var talking := false
var voice_timeout := 0.0
var paddle_up := false
var sprinting := false
var respawn_point: Vector3 = Vector3(0, 1, 0)
var wanted := 0.0 # уровень интереса ментов
var in_vehicle: Node = null
var in_custody := false
var cinematic := false ## катсцена/трейлер: ввод и взгляд отключены, камера не наша
var cine_move := Vector3.ZERO ## трейлер: куда бежать, пока cinematic
var _death_reason := ""
var _yaw := 0.0
var _pitch := 0.0
var _remote_pos := Vector3.ZERO
var _remote_yaw := 0.0
var _remote_pitch := 0.0
var _has_remote := false
var _say_timer := 0.0
var _flags := 0
var _bob := 0.0
var _bob_y := 0.0
var _was_on_floor := true
var _land_dip := 0.0
var _shake_off := Vector3.ZERO
var _last_send := 0.0
var _slip_vel := Vector3.ZERO
var _fall_speed := 0.0
var _paddle: Node3D = null
var _body_mat: StandardMaterial3D
var _skin_mat: StandardMaterial3D
var _ragdoll: Node3D = null


func is_local() -> bool:
	return peer_id == Net.my_id()


func _ready() -> void:
	collision_layer = Types.L_PLAYER
	collision_mask = Types.L_WORLD | Types.L_ITEM | Types.L_VEHICLE | Types.L_NPC | Types.L_PLAYER
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = _color_for_peer(peer_id)
	body_mesh.material_override = _body_mat
	head_mesh.material_override = _body_mat
	arm_r.material_override = _body_mat
	arm_l.material_override = _body_mat
	_build_hand(hands.hand_r, 1.0)
	_build_hand(hands.hand_l, -1.0)
	_build_rig()
	name_plate.text = _name_for_peer()
	say_label.text = ""
	talk_icon.visible = false
	look_ray.target_position = Vector3(0, 0, -Hands.REACH)
	look_ray.collision_mask = Types.L_WORLD | Types.L_ITEM | Types.L_VEHICLE | Types.L_NPC | Types.L_TRIGGER | Types.L_PLAYER
	look_ray.collide_with_areas = true
	look_ray.add_exception(self)
	for i in pockets_root.get_child_count():
		pockets.append(null)
	if is_local():
		camera.current = true
		head_mesh.visible = false
		name_plate.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		Game.world_mode_changed.connect(func(m: int, _prev: int):
			if m != Types.WorldMode.AUCTION:
				lower_paddle())
	else:
		camera.current = false
	set_process_input(is_local())
	_life_phase = float(absi(get_instance_id()) % 10007) * 0.001837
	_p_rng = RandomNumberGenerator.new()
	_p_rng.seed = get_instance_id()
	_p_blink_cd = _p_rng.randf_range(2.5, 6.0)


## Тело от третьего лица (кооп): торс + ноги + руки на пивотах, качаются при ходьбе.
var _leg_l: Node3D
var _leg_r: Node3D
var _rig_arm_l: Node3D
var _rig_arm_r: Node3D
const BODY_Y := 0.90

static var _P_MATS: Dictionary = {}


func _pmat(color: Color, rough := 0.9) -> StandardMaterial3D:
	var key := "%d_%.2f" % [color.to_rgba32(), rough]
	var cached: Variant = _P_MATS.get(key)
	if cached is StandardMaterial3D:
		return cached
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = 0.0
	_P_MATS[key] = m
	return m


func _skin() -> StandardMaterial3D:
	if _skin_mat == null:
		_skin_mat = _pmat(Color(0.96, 0.68, 0.46), 0.88)
	return _skin_mat


func _build_rig() -> void:
	# коротыш кей-арта: жирная футболка цвета игрока, шорты, носки, кеды
	body_mesh.mesh = LowPoly.capsule(0.32, 0.48, 8, 3)
	body_mesh.position.y = BODY_Y
	body_mesh.scale = Vector3(1.0, 1.0, 0.88)
	wear_slot.position = Vector3(0, -0.20, 0) # костюм остаётся на уровне старого тела
	head_mesh.mesh = LowPoly.sphere(0.36, 8, 3)
	head_mesh.material_override = _skin()
	head_mesh.position = Vector3(0.0, _HEAD_MESH_Y, 0.02)
	var shorts_c := Color.from_hsv(fmod(_body_mat.albedo_color.h + 0.38, 1.0), 0.64, 0.40)
	var shorts := MeshInstance3D.new()
	shorts.name = "Shorts"
	shorts.mesh = LowPoly.cylinder(0.34, 0.36, 0.22, 8)
	shorts.material_override = _pmat(shorts_c)
	shorts.position = Vector3(0.0, -0.20, 0.0)
	shorts.scale = Vector3(1.0, 1.0, 0.90)
	body_mesh.add_child(shorts)
	# слоты карманов — серые кубы, в 3P выглядят как оторванные кисти
	if pockets_root:
		for vis in pockets_root.find_children("Vis", "MeshInstance3D", true, false):
			var vm: MeshInstance3D = vis as MeshInstance3D
			if vm:
				vm.visible = false
	var stripe := _pmat(Color.from_hsv(_body_mat.albedo_color.h, 0.85, 0.80))
	var sock := _pmat(Color(0.94, 0.94, 0.92))
	var shoe_w := _pmat(Color(0.96, 0.95, 0.93), 0.85)
	var sole := _pmat(Color(0.62, 0.08, 0.12), 0.95)
	var sock_h := 0.50
	var shoe_s := Vector3(0.24, 0.14, 0.34)
	for side in [-1.0, 1.0]:
		var piv := Node3D.new()
		piv.name = "LegL" if side < 0 else "LegR"
		piv.position = Vector3(side * 0.14, -0.22, 0)
		body_mesh.add_child(piv)
		var leg := MeshInstance3D.new()
		leg.mesh = LowPoly.cylinder(0.105, 0.11, sock_h, 8)
		leg.material_override = sock
		leg.position.y = -sock_h * 0.38
		piv.add_child(leg)
		var b1 := MeshInstance3D.new()
		b1.mesh = LowPoly.cylinder(0.114, 0.114, 0.03, 8)
		b1.material_override = stripe
		b1.position.y = -sock_h * 0.10
		piv.add_child(b1)
		var b2 := MeshInstance3D.new()
		b2.mesh = LowPoly.cylinder(0.114, 0.114, 0.03, 8)
		b2.material_override = stripe
		b2.position.y = -sock_h * 0.20
		piv.add_child(b2)
		var shoe := MeshInstance3D.new()
		shoe.mesh = LowPoly.chamfer_box(shoe_s, 0.02)
		shoe.material_override = shoe_w
		shoe.position = Vector3(0, -0.50, -0.09)
		piv.add_child(shoe)
		var sole_mi := MeshInstance3D.new()
		sole_mi.mesh = LowPoly.chamfer_box(Vector3(shoe_s.x * 1.08, 0.045, shoe_s.z * 1.08), 0.01)
		sole_mi.material_override = sole
		sole_mi.position = Vector3(0, -0.575, -0.09)
		piv.add_child(sole_mi)
		if side < 0:
			_leg_l = piv
		else:
			_leg_r = piv
	# руки 3P и лицо — для чужих игроков сразу; у себя — только в катсцене (см. set_third_person)
	if not is_local():
		_build_3p_extras()


var _3p_built := false
var _life_t := 0.0
var _life_phase := 0.0
var _p_eye_l: MeshInstance3D
var _p_eye_r: MeshInstance3D
var _p_eye_base := Vector3(0.70, 1.08, 0.60)
var _p_blink_cd := 3.0
var _p_blink_left := 0.0
var _p_rng: RandomNumberGenerator
const _HEAD_MESH_Y := -0.22


## Катсцена/трейлер: показать себя целиком (голова, руки, лицо), спрятать 1P-кисти. И обратно.
func set_third_person(on: bool) -> void:
	if on and not _3p_built:
		_build_3p_extras()
	head_mesh.visible = on or not is_local()
	hands.visible = not on
	if _rig_arm_l:
		_rig_arm_l.visible = on or not is_local()
	if _rig_arm_r:
		_rig_arm_r.visible = on or not is_local()
	if head_mesh.has_node("Face"):
		head_mesh.get_node("Face").visible = on or not is_local()


func _build_3p_extras() -> void:
	if _3p_built:
		return
	_3p_built = true
	var skin: StandardMaterial3D = _skin()
	var shirt: StandardMaterial3D = _body_mat
	for side in [-1.0, 1.0]:
		var apiv := Node3D.new()
		apiv.name = "ArmL" if side < 0.0 else "ArmR"
		apiv.position = Vector3(side * 0.36, 0.16, -0.04)
		apiv.rotation.z = -side * 0.20
		apiv.rotation.x = 0.35
		body_mesh.add_child(apiv)
		var arm := MeshInstance3D.new()
		arm.mesh = LowPoly.capsule(0.09, 0.40, 8, 3)
		arm.material_override = shirt
		arm.position.y = -0.16
		apiv.add_child(arm)
		var hnd := MeshInstance3D.new()
		hnd.name = "HandL" if side < 0.0 else "HandR"
		hnd.mesh = LowPoly.chamfer_box(Vector3(0.17, 0.15, 0.16), 0.022)
		hnd.material_override = skin
		hnd.position.y = -0.38
		apiv.add_child(hnd)
		if side < 0:
			_rig_arm_l = apiv
		else:
			_rig_arm_r = apiv
	# голова — кожа, сверху кепка, огромные овалы-глаза, рот с языком (орёт как на кей-арте)
	head_mesh.material_override = skin
	head_mesh.mesh = LowPoly.sphere(0.36, 8, 3)
	var face := Node3D.new()
	face.name = "Face"
	head_mesh.add_child(face)
	var cap_c: Color = Color.from_hsv(fmod(shirt.albedo_color.h + 0.52, 1.0), 0.88, 0.94)
	var cap_mat: StandardMaterial3D = _pmat(cap_c)
	var cap := MeshInstance3D.new()
	cap.mesh = LowPoly.sphere(0.39, 8, 3, true, 0.26)
	cap.material_override = cap_mat
	cap.position = Vector3(0, 0.20, 0.04)
	face.add_child(cap)
	var visor := MeshInstance3D.new()
	visor.mesh = LowPoly.chamfer_box(Vector3(0.46, 0.048, 0.26), 0.01)
	visor.material_override = cap_mat
	visor.position = Vector3(0, 0.12, -0.38)
	face.add_child(visor)
	var eye_w: StandardMaterial3D = _pmat(Color(0.97, 0.97, 0.95), 0.70)
	var pupil_m: StandardMaterial3D = _pmat(Color(0.06, 0.05, 0.07), 0.40)
	_p_eye_base = Vector3(0.70, 1.08, 0.60)
	for x in [-0.125, 0.125]:
		var eye := MeshInstance3D.new()
		eye.mesh = LowPoly.sphere(0.13, 8, 3, false, 0.30)
		eye.material_override = eye_w
		eye.scale = _p_eye_base
		eye.position = Vector3(x, 0.05, -0.30)
		face.add_child(eye)
		var pupil := MeshInstance3D.new()
		pupil.mesh = LowPoly.sphere(0.036, 6, 3)
		pupil.material_override = pupil_m
		pupil.position = Vector3(x, 0.04, -0.36)
		face.add_child(pupil)
		if x < 0.0:
			eye.name = "EyeL"
			_p_eye_l = eye
		else:
			eye.name = "EyeR"
			_p_eye_r = eye
	var mouth := MeshInstance3D.new()
	mouth.name = "Mouth"
	mouth.mesh = LowPoly.chamfer_box(Vector3(0.30, 0.18, 0.10), 0.02)
	mouth.material_override = _pmat(Color(0.07, 0.03, 0.04), 0.95)
	mouth.position = Vector3(0, -0.13, -0.32)
	face.add_child(mouth)
	var tongue := MeshInstance3D.new()
	tongue.name = "Tongue"
	tongue.mesh = LowPoly.chamfer_box(Vector3(0.16, 0.055, 0.04), 0.008)
	tongue.material_override = _pmat(Color(0.90, 0.18, 0.28))
	tongue.position = Vector3(0, -0.05, -0.012)
	mouth.add_child(tongue)


## Мультяшная кисть кей-арта: гранёный кулак-брус + кусок предплечья, персиковая кожа.
func _build_hand(hand: Node3D, side: float) -> void:
	if hand == null or hand.has_node("Fist"):
		return
	var skin: StandardMaterial3D = _skin()
	var fist := MeshInstance3D.new()
	fist.name = "Fist"
	fist.mesh = LowPoly.chamfer_box(Vector3(0.15, 0.125, 0.14), 0.02)
	fist.material_override = skin
	fist.position = Vector3(0, 0.0, 0.0)
	fist.rotation = Vector3(deg_to_rad(-18.0), side * deg_to_rad(12.0), 0.0)
	hand.add_child(fist)
	var arm_mi: MeshInstance3D = hand.get_node_or_null("Arm") as MeshInstance3D
	if arm_mi:
		arm_mi.mesh = LowPoly.capsule(0.062, 0.30, 8, 3)
		arm_mi.material_override = skin
	var cuff := MeshInstance3D.new()
	cuff.mesh = LowPoly.cylinder(0.064, 0.068, 0.08, 8)
	cuff.material_override = _pmat(_body_mat.albedo_color)
	cuff.position = Vector3(side * 0.02, -0.05, 0.10)
	cuff.rotation.x = deg_to_rad(-60.0)
	hand.add_child(cuff)


func _color_for_peer(id: int) -> Color:
	var palette := [Color(0.9, 0.5, 0.2), Color(0.3, 0.7, 0.9), Color(0.6, 0.85, 0.3), Color(0.9, 0.35, 0.6), Color(0.85, 0.85, 0.3)]
	return palette[(id if id < 5 else id % 5) % palette.size()]


func _name_for_peer() -> String:
	if peer_id == 1 and SteamBoot.enabled and is_local():
		return SteamBoot.persona
	return "P%d" % peer_id if peer_id != 1 else "HOST"


func head_position() -> Vector3:
	return head.global_position


## Повернуть взгляд к точке (спавн лицом к двери, а не в стену).
func look_toward(target: Vector3) -> void:
	var d := target - global_position
	d.y = 0.0
	if d.length() < 0.05:
		return
	_yaw = atan2(-d.x, -d.z)
	_pitch = 0.0
	head.rotation.y = _yaw
	head.rotation.x = 0.0


# ------------------------------------------------------------------ ввод

func _input(event: InputEvent) -> void:
	if not is_local() or dead or get_tree().paused or cinematic:
		return
	if paddle_up and _paddle != null and _paddle.has_method("consume_input"):
		if _paddle.consume_input(event):
			return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m := event as InputEventMouseMotion
		var wob := 1.0 + drunk * 0.6 * sin(Time.get_ticks_msec() * 0.003)
		_yaw -= m.relative.x * mouse_sens * wob
		_pitch = clampf(_pitch - m.relative.y * mouse_sens, -1.45, 1.45)
	if in_vehicle:
		return # за рулём E/ПКМ/прыжок обрабатывает Vehicle — не дублируем хват/карман
	if event.is_action_pressed("grab"):
		if paddle_up:
			_paddle_raise()
		elif hands.holds_tag("rag") and _scrub_target():
			punch_arm()
		else:
			punch_arm()
			hands.local_try_grab()
	elif event.is_action_pressed("release"):
		hands.local_release(0.0)
	elif event.is_action_pressed("throw"):
		punch_arm()
		hands.local_release(7.5)
	elif event.is_action_pressed("second_hand"):
		hands.local_second_hand()
	elif event.is_action_pressed("use"):
		_local_use()
	elif event.is_action_pressed("alt_use"):
		_local_pocket()
	elif event.is_action_pressed("flashlight"):
		var fl := hands.holds_tag("flashlight")
		if fl:
			Net.request_use(fl.net_id, 0)
	elif event.is_action_pressed("paddle"):
		toggle_paddle()
	elif event.is_action_pressed("pin"):
		Net.request_action("pin", {"pos": _look_point()})
	elif event.is_action_pressed("jump") and is_on_floor() and stuck <= 0.0:
		velocity.y = JUMP


func _local_use() -> void:
	var held := hands.any_held()
	var target = look_target()
	# если смотрим на интерактив мира (стол скупщика, дверь, рулетка) — он важнее
	if target and not (target is ItemBody) and target.has_method("interact"):
		Net.request_action("interact", {"path": str(target.get_path())})
		return
	if target is ItemBody and held and (held.def.tags.has("tape") or held.def.tags.has("plank") or held.def.tags.has("lockpick") or held.def.tags.has("rag") or held.def.tags.has("lighter") or held.def.tags.has("matches")):
		# инструмент в руке применяем к тому, на что смотрим
		Net.request_action("apply_tool", {"tool": held.net_id, "target": target.net_id})
		return
	if held:
		Net.request_use(held.net_id, 0)
	elif target is ItemBody:
		Net.request_use(target.net_id, 1)
	elif target and target.has_method("interact"):
		Net.request_action("interact", {"path": str(target.get_path())})


func _local_pocket() -> void:
	var held := hands.any_held()
	if held:
		if held.arch.size_class == Types.SizeClass.POCKET or held.def.is_cash():
			Net.request_action("pocket_put", {"nid": held.net_id})
		else:
			say(tr("HANDS_NO_FIT_POCKET"))
	else:
		Net.request_action("pocket_take", {})


func _scrub_target() -> bool:
	var target = look_target()
	if target is ItemBody and target.def.has_facet(Types.Facet.DIRTYABLE):
		var rag := hands.holds_tag("rag")
		Net.request_action("scrub", {"target": target.net_id, "rag": rag.net_id})
		return true
	return false


func _look_point() -> Vector3:
	look_ray.force_raycast_update()
	if look_ray.is_colliding():
		return look_ray.get_collision_point()
	return camera.global_position - camera.global_basis.z * Hands.REACH


func look_target() -> Node:
	look_ray.force_raycast_update()
	if look_ray.is_colliding():
		var c := look_ray.get_collider()
		return c
	return null


# ------------------------------------------------------------------ движение

func _physics_process(delta: float) -> void:
	if dead or in_vehicle:
		if _ragdoll and is_local():
			camera.global_position = camera.global_position.lerp(_ragdoll.global_position + Vector3(0, 1.2, 0), delta * 3.0)
		return
	if is_local():
		_local_move(delta)
		_local_send()
	else:
		_remote_move(delta)
	_status_tick(delta)
	if is_local():
		_scrub_tick(delta)


func _local_move(delta: float) -> void:
	head.rotation.y = _yaw
	camera.rotation.x = _pitch
	var on_floor := is_on_floor()
	if not on_floor:
		velocity.y -= 9.8 * delta
		_fall_speed = velocity.y
	else:
		if not _was_on_floor:
			var land_spd := maxf(0.0, -_fall_speed)
			if land_spd > 3.0:
				_land_dip = clampf(-0.06 * (land_spd / 3.0), -0.12, 0.0)
			if land_spd > 6.0:
				AudioBus.play_at("thud", global_position, -10.0)
				shake(clampf(land_spd / 10.0, 0.5, 1.0))
			if _fall_speed < -9.0:
				take_damage((-_fall_speed - 9.0) * 6.0, "fall")
		_fall_speed = 0.0
	_was_on_floor = on_floor
	var dir := Vector3.ZERO
	# в камере ходить можно (решётка держит), в наручниках — вполсилы
	if not get_tree().paused and not cinematic:
		var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		dir = (head.global_basis * Vector3(input.x, 0, input.y)).normalized() if input.length() > 0.01 else Vector3.ZERO
	elif cinematic and cine_move.length() > 0.01:
		dir = cine_move.normalized()
		look_toward(global_position + dir)
	sprinting = Input.is_action_pressed("sprint") and dir.length() > 0.1 and stuck <= 0.0
	var spd := SPEED * encumbrance * (SPRINT_MULT if sprinting else 1.0)
	if cuffed:
		spd *= 0.5
	if stuck > 0.0:
		spd *= 0.25
	if drunk > 0.0:
		dir += Vector3(sin(Time.get_ticks_msec() * 0.0021), 0, cos(Time.get_ticks_msec() * 0.0017)) * drunk * 0.5
	var want := dir * spd
	var accel := 12.0 if slip <= 0.0 else lerpf(12.0, 1.2, slip)
	if slip > 0.3 and is_on_floor() and want.length() > 0.1:
		accel = 0.8
	velocity.x = move_toward(velocity.x, want.x, accel * delta * spd)
	velocity.z = move_toward(velocity.z, want.z, accel * delta * spd)
	move_and_slide()
	# бег с хрупким — шатает (§6.1)
	var held := hands.any_held()
	if held and sprinting and held.def.is_fragile() and randf() < 0.004:
		Net.request_release(0, 1.0)
		say(tr("HANDS_SLIPPED"))
	# толкаем вещи
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var b := col.get_collider()
		if b is RigidBody3D and Net.is_host():
			b.apply_central_impulse(-col.get_normal() * 0.6 * minf(velocity.length(), 4.0))
	# бобинг камеры — в _camera_feel, чтобы не драться с dip/shake/drunk


func _local_send() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_send < 1.0 / 20.0:
		return
	_last_send = now
	_flags = 0
	if talking: _flags |= FLAG_TALK
	if dead: _flags |= FLAG_DEAD
	if cuffed: _flags |= FLAG_CUFFED
	if burning: _flags |= FLAG_BURN
	if paddle_up: _flags |= FLAG_PADDLE
	if sprinting: _flags |= FLAG_SPRINT
	Net.send_player_state(global_position, _yaw, _pitch, _flags)


func apply_remote_state(pos: Vector3, yaw: float, pitch: float, flags: int) -> void:
	_remote_pos = pos
	_remote_yaw = yaw
	_remote_pitch = pitch
	if not _has_remote:
		global_position = pos
		_has_remote = true
	set_talking(flags & FLAG_TALK != 0)
	paddle_up = flags & FLAG_PADDLE != 0
	_update_paddle_visual()
	if Net.is_host():
		# хост: применяет состояние ввода (гость двигает себя; хост считает урон/хват)
		pass
	elif flags & FLAG_DEAD != 0 and not dead:
		dead = true
	elif flags & FLAG_DEAD == 0 and dead:
		dead = false
	cuffed = flags & FLAG_CUFFED != 0
	if not Net.is_host():
		burning = flags & FLAG_BURN != 0


func _remote_move(delta: float) -> void:
	if not _has_remote:
		return
	global_position = global_position.lerp(_remote_pos, minf(1.0, delta * 15.0))
	_yaw = lerp_angle(_yaw, _remote_yaw, minf(1.0, delta * 15.0))
	_pitch = lerpf(_pitch, _remote_pitch, minf(1.0, delta * 15.0))
	head.rotation.y = _yaw
	camera.rotation.x = _pitch
	velocity = (_remote_pos - global_position) / maxf(delta, 0.001) * 0.5


# ------------------------------------------------------------------ статус / тело (§6.4)

func _status_tick(delta: float) -> void:
	if _say_timer > 0.0:
		_say_timer -= delta
		if _say_timer <= 0.0:
			say_label.text = ""
	if voice_timeout > 0.0:
		voice_timeout -= delta
		if voice_timeout <= 0.0 and not is_local():
			set_talking(false)
	if drunk > 0.0:
		drunk = maxf(0.0, drunk - delta * 0.02)
	slip = maxf(0.0, slip - delta * 1.5)
	stuck = maxf(0.0, stuck - delta * 0.5)
	if Net.is_host():
		if burning:
			burn_time += delta
			take_damage(delta * 12.0, "fire")
			if burn_time > 6.0 or (slip > 0.5 and randf() < 0.05):
				set_burning(false)
		if hp < 100.0 and not burning:
			hp = minf(100.0, hp + delta * 2.0)
		wanted = maxf(0.0, wanted - delta * 0.02)
	if worn and not is_instance_valid(worn):
		worn = null


func set_burning(v: bool) -> void:
	if burning == v:
		return
	burning = v
	burn_time = 0.0
	var fx := head.get_node_or_null("BurnFx")
	if v:
		if fx == null:
			fx = FireFx.make(Vector3(0.5, 1.0, 0.5))
			fx.name = "BurnFx"
			fx.position.y = -0.8
			head.add_child(fx)
		AudioBus.play_at("ignite", global_position, 0.0)
		if Net.is_host():
			Game.stat_add("player_burns")
			Net.broadcast_event("player_burn", {"peer": peer_id, "on": true})
	else:
		if fx:
			fx.queue_free()
		if Net.is_host():
			Net.broadcast_event("player_burn", {"peer": peer_id, "on": false})


func take_damage(v: float, reason: String) -> void:
	if not Net.is_host() or dead:
		return
	hp -= v
	if is_local() and reason != "fire" and v > 1.0:
		shake(clampf(v / 20.0, 0.5, 1.0))
	if hp <= 0.0:
		die(reason)


func drink(amount: float) -> void:
	drunk = clampf(drunk + amount, 0.0, 1.0)
	Game.stat_add("drinks")
	Achievements.count("drinks", "connoisseur", 10)
	if drunk >= 0.95:
		Achievements.unlock("blackout")


func splash(liquid: int, amount: float) -> void:
	# облили (§7.3): краска красит, бензин/виски → горючий, вода тушит
	match liquid:
		Types.LiquidId.PAINT:
			paint_color = Types.liquid_color(liquid)
			paint_color.a = 1.0
			_body_mat.albedo_color = _color_for_peer(peer_id).lerp(Color(paint_color.r, paint_color.g, paint_color.b), 0.85)
			Achievements.unlock("painted_friend")
		Types.LiquidId.WATER:
			if burning:
				set_burning(false)
		Types.LiquidId.GLUE:
			stuck = 4.0
		Types.LiquidId.OIL:
			slip = 1.0
	if Net.is_host():
		Net.broadcast_event("player_splash", {"peer": peer_id, "liquid": liquid})


func on_puddle(liquid: int, slip_amount: float) -> void:
	if slip_amount > 0.0:
		slip = maxf(slip, slip_amount)
	elif slip_amount < 0.0:
		stuck = maxf(stuck, 1.5)
	if liquid == Types.LiquidId.GASOLINE and burning:
		pass


## Смерть / пуля кореша / огонь / машина: ragdoll → кровать трейлера (§6.4).
func die(reason: String) -> void:
	if dead or not Net.is_host():
		return
	dead = true
	hp = 0.0
	set_burning(false)
	hands.host_release_all()
	# карманы — на землю в месте смерти, сумка — отдельное тело где упала
	for i in pockets.size():
		var b: ItemBody = pockets[i]
		if b and is_instance_valid(b):
			_pocket_release(b, i)
	if worn:
		unwear()
	Game.stat_add("deaths")
	Achievements.count("deaths", "nine_lives", 9)
	died.emit(reason)
	_death_reason = reason
	Net.broadcast_event("player_death", {"peer": peer_id, "reason": reason, "pos": global_position, "yaw": _yaw})
	_do_death_visual(global_position, _yaw)
	if Game.world and Game.world.has_method("on_player_died"):
		Game.world.on_player_died(self, reason)
	await get_tree().create_timer(5.0).timeout
	respawn()


func _do_death_visual(pos: Vector3, yaw: float) -> void:
	dead = true
	body_mesh.visible = false
	head.visible = false
	name_plate.visible = false
	collision_layer = 0
	collision_mask = Types.L_WORLD
	_ragdoll = Ragdoll.make(_body_mat.albedo_color)
	get_parent().add_child(_ragdoll)
	_ragdoll.global_position = pos + Vector3(0, 0.9, 0)
	_ragdoll.rotation.y = yaw
	_ragdoll.kick(Vector3(randf_range(-1, 1), 1.5, randf_range(-1, 1)) * 3.0)
	AudioBus.play_at("death_wilhelm", pos, 2.0, 0.2)
	if is_local() and Game.world and Game.world.hud and Game.world.hud.has_method("show_death"):
		Game.world.hud.show_death(_death_reason, 5.0)


func respawn() -> void:
	if not Net.is_host():
		return
	Net.broadcast_event("player_respawn", {"peer": peer_id})
	_do_respawn()


func _do_respawn() -> void:
	dead = false
	hp = 100.0
	drunk = 0.0
	cuffed = false
	in_custody = false
	if _ragdoll and is_instance_valid(_ragdoll):
		_ragdoll.queue_free()
	_ragdoll = null
	body_mesh.visible = true
	head.visible = true
	name_plate.visible = not is_local()
	collision_layer = Types.L_PLAYER
	collision_mask = Types.L_WORLD | Types.L_ITEM | Types.L_VEHICLE | Types.L_NPC | Types.L_PLAYER
	global_position = respawn_point
	velocity = Vector3.ZERO
	camera.position = Vector3.ZERO
	_land_dip = 0.0
	_shake_off = Vector3.ZERO
	_bob_y = 0.0
	if is_local() and Game.world and Game.world.hud and Game.world.hud.has_method("hide_death"):
		Game.world.hud.hide_death()
	respawned.emit()


## Клиент: событие смерти/респавна другого игрока.
func on_remote_death(pos: Vector3, yaw: float, reason: String = "") -> void:
	_death_reason = reason
	_do_death_visual(pos, yaw)


func on_remote_respawn() -> void:
	_do_respawn()


# ------------------------------------------------------------------ карманы (§6.2)

func host_pocket_put(b: ItemBody) -> void:
	if not (b.arch.size_class == Types.SizeClass.POCKET or b.def.is_cash()):
		return
	if worn and worn.def.tags.has("no_pockets"):
		say(tr("HANDS_NO_POCKETS"))
		return
	for i in pockets.size():
		if pockets[i] == null:
			for h in b.held_by.duplicate():
				h.host_release_body(b)
			pockets[i] = b
			b.freeze = true
			b.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			b.collision_layer = 0
			b.collision_mask = 0
			b.set_meta("pocket_of", peer_id)
			AudioBus.play_at("pocket", global_position, -6.0)
			Net.broadcast_event("pocket", {"peer": peer_id, "nid": b.net_id, "slot": i, "put": true})
			return
	say(tr("HANDS_POCKETS_FULL"))


func host_pocket_take() -> void:
	for i in range(pockets.size() - 1, -1, -1):
		var b: ItemBody = pockets[i]
		if b and is_instance_valid(b):
			_pocket_release(b, i)
			var hand := hands.free_hand()
			if hand != -1:
				hands.host_grab(b, hand)
			Net.broadcast_event("pocket", {"peer": peer_id, "nid": b.net_id, "slot": i, "put": false})
			return


func _pocket_release(b: ItemBody, i: int) -> void:
	pockets[i] = null
	b.freeze = b.proxy
	b.collision_layer = Types.L_ITEM
	b.collision_mask = Types.L_WORLD | Types.L_PLAYER | Types.L_ITEM | Types.L_VEHICLE | Types.L_NPC | Types.L_SHARD
	b.remove_meta("pocket_of")
	b.global_position = pockets_root.get_child(i).global_position


func apply_pocket_event(nid: int, slot: int, put: bool) -> void:
	var b = Net.items.get(nid)
	if b == null:
		return
	if put:
		pockets[slot] = b
		if b.proxy:
			b.collision_layer = 0
	else:
		pockets[slot] = null


func _process(delta: float) -> void:
	# карманные вещи едут с игроком (и на хосте, и на клиенте)
	for i in pockets.size():
		var b: ItemBody = pockets[i]
		if b and is_instance_valid(b):
			var pp := pockets_root.get_child(i) as Node3D
			b.global_transform = pp.global_transform
			b.scale = Vector3.ONE * b.def.scale
	if worn and is_instance_valid(worn):
		worn.global_transform = wear_slot.global_transform
	if talk_icon.visible:
		talk_icon.rotate_y(delta * 3.0)
	_anim_arms(delta)
	if is_local():
		if not dead and not in_vehicle:
			_camera_feel(delta)
		_flip_tick(delta)


# ------------------------------------------------------------------ процедурная анимация рук

# покой: руки опущены к нижним углам экрана, не торчат перед лицом
var _arm_base_r := Vector3(0.36, -0.42, -0.42)
var _arm_base_l := Vector3(-0.36, -0.42, -0.42)
# с вещью / у цели рука поднимается к центру, куда смотрит мышь
const _ARM_UP_R := Vector3(-0.06, 0.13, -0.04)
const _ARM_UP_L := Vector3(0.06, 0.13, -0.04)
var _arm_reach := 0.0
var _arm_swing := 0.0
var _arm_aim := 0.0
var _arm_aim_t := 0.0


func _anim_arms(delta: float) -> void:
	var speed := Vector3(velocity.x, 0, velocity.z).length()
	var moving := speed > 0.5 and (is_on_floor() or not is_local())
	var carried: ItemBody = hands.any_held()
	var heavy := carried != null and is_instance_valid(carried) and carried.mass > 8.0
	var swing_rate := 11.0 if sprinting else 7.5
	if heavy:
		swing_rate *= 0.55
	if moving:
		_arm_swing += delta * swing_rate
	else:
		_arm_swing = lerpf(_arm_swing, roundf(_arm_swing / PI) * PI, delta * 6.0)
	_arm_reach = maxf(0.0, _arm_reach - delta * 4.0)
	var held_r := hands.held[0] != null
	var held_l := hands.held[1] != null
	var amp := 1.4 if (sprinting and moving) else 1.0
	var sway := sin(_arm_swing) * 0.06 * clampf(speed / SPEED, 0.0, 1.5) * amp
	var bob := absf(cos(_arm_swing)) * 0.025 * clampf(speed / SPEED, 0.0, 1.5)
	var drop := 0.0
	if sprinting and moving:
		drop -= 0.02
	if heavy:
		drop -= 0.04
	var reach := Vector3(0, 0.05, -0.18) * _arm_reach
	# правая рука тянется к тому, на что смотрим (вещь в радиусе хвата) — «рука за мышкой»
	if is_local() and not held_r:
		_arm_aim_t -= delta
		if _arm_aim_t <= 0.0:
			_arm_aim_t = 0.1
			var t := look_target()
			var want_aim := (t is ItemBody) or (t != null and t.has_method("interact"))
			_arm_aim = lerpf(_arm_aim, 1.0 if want_aim else 0.0, 0.5)
	else:
		_arm_aim = 0.0
	var hold_r := _ARM_UP_R + Vector3(-0.02, 0.04, -0.01) if held_r else (_ARM_UP_R + Vector3(-0.04, 0.0, -0.12)) * _arm_aim
	var hold_l := _ARM_UP_L + Vector3(0.02, 0.04, -0.01) if held_l else Vector3.ZERO
	if paddle_up:
		hold_r = _ARM_UP_R + Vector3(-0.04, 0.08, -0.03)
	if hands.two_hands_same:
		hold_r = _ARM_UP_R + Vector3(-0.08, 0.01, -0.04)
		hold_l = _ARM_UP_L + Vector3(0.08, 0.01, -0.04)
	hands.hand_r.position = _arm_base_r + Vector3(0, bob + drop, sway if not held_r else 0.0) + reach + hold_r
	hands.hand_l.position = _arm_base_l + Vector3(0, bob + drop, -sway if not held_l else 0.0) + reach * 0.5 + hold_l
	_life_t += delta
	var breath := sin((_life_t + _life_phase) * TAU * 1.1)
	body_mesh.position.y = BODY_Y + bob * 2.0
	body_mesh.rotation.z = sway * 0.8
	body_mesh.rotation.y = head.rotation.y
	if moving:
		body_mesh.scale.y = 1.0
		head_mesh.position.y = _HEAD_MESH_Y
	else:
		body_mesh.scale.y = 1.0 + breath * 0.015
		head_mesh.position.y = _HEAD_MESH_Y + breath * 0.008
	# 3P: мигание; yaw уже на Head (_yaw/_remote_yaw), pitch слегка на голове у чужих/катсцены
	if _p_eye_l:
		_p_blink_cd -= delta
		if _p_blink_cd <= 0.0:
			_p_blink_left = 0.1
			_p_blink_cd = _p_rng.randf_range(2.5, 6.0) if _p_rng else 3.5
		var ey := 0.1 if _p_blink_left > 0.0 else _p_eye_base.y
		if _p_blink_left > 0.0:
			_p_blink_left -= delta
		_p_eye_l.scale = Vector3(_p_eye_base.x, ey, _p_eye_base.z)
		if _p_eye_r:
			_p_eye_r.scale = Vector3(_p_eye_base.x, ey, _p_eye_base.z)
	if _3p_built and (not is_local() or cinematic):
		head_mesh.rotation.x = _pitch * 0.35
	var swing := sin(_arm_swing) * clampf(speed / SPEED, 0.0, 1.3)
	if _leg_l and _leg_r:
		var leg_amp := 0.75 if moving else 0.0
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x, swing * leg_amp, delta * 14.0)
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, -swing * leg_amp, delta * 14.0)
	if _rig_arm_l and _rig_arm_r:
		var carrying := held_r or held_l
		var target_l := deg_to_rad(-70.0) if carrying else -swing * 0.6
		var target_r := deg_to_rad(-70.0) if carrying else swing * 0.6
		_rig_arm_l.rotation.x = lerpf(_rig_arm_l.rotation.x, target_l, delta * 10.0)
		_rig_arm_r.rotation.x = lerpf(_rig_arm_r.rotation.x, target_r, delta * 10.0)
	if dead:
		return
	# пьяный — руки гуляют
	if drunk > 0.1:
		hands.hand_r.position += Vector3(sin(Time.get_ticks_msec() * 0.003), cos(Time.get_ticks_msec() * 0.0021), 0) * drunk * 0.04
	# горим — машем
	if burning:
		hands.hand_r.position.y += sin(Time.get_ticks_msec() * 0.02) * 0.1
		hands.hand_l.position.y += cos(Time.get_ticks_msec() * 0.02) * 0.1


func punch_arm() -> void:
	_arm_reach = 1.0


var _use_hold := 0.0
var _flip_sent := false


func _flip_tick(delta: float) -> void:
	# удержание E с вещью в руках → перевернуть (вытряхнуть сумку / вылить бутылку / потрясти книгу)
	if Input.is_action_pressed("use") and hands.any_held() != null and not get_tree().paused:
		_use_hold += delta
		if _use_hold > 0.45 and not _flip_sent:
			_flip_sent = true
			Net.request_action("flip_held", {"on": true})
	else:
		_use_hold = 0.0
		if _flip_sent:
			_flip_sent = false
			Net.request_action("flip_held", {"on": false})


## Удар камеры: затухающий случайный поворот. Машины/взрывы зовут снаружи.
func shake(strength: float) -> void:
	var amp := deg_to_rad(1.2) * maxf(strength, 0.0)
	_shake_off = Vector3(randf_range(-amp, amp), randf_range(-amp, amp), randf_range(-amp, amp))


## Один композит: bob + приземление + shake + drunk FOV/крен. Не перетирать по отдельности.
func _camera_feel(delta: float) -> void:
	var hspeed := Vector3(velocity.x, 0.0, velocity.z).length()
	var speed_k := clampf(hspeed / SPEED, 0.0, 1.5)
	if hspeed > 0.15 and is_on_floor():
		_bob += delta * (10.0 if sprinting else 7.0) * speed_k
		_bob_y = sin(_bob) * 0.02 * speed_k
	else:
		_bob_y = lerpf(_bob_y, 0.0, delta * 6.0)
	_land_dip = lerpf(_land_dip, 0.0, minf(1.0, delta * 8.0))
	_shake_off = _shake_off.lerp(Vector3.ZERO, minf(1.0, delta * 6.0))
	camera.position.y = _bob_y + _land_dip
	var drunk_z := sin(Time.get_ticks_msec() * 0.0015) * drunk * 0.08 if drunk > 0.05 else 0.0
	camera.rotation.x = _pitch + _shake_off.x
	camera.rotation.z = drunk_z + _shake_off.z
	var fov_v: Variant = Settings.get_value("fov")
	var base_fov := 75.0
	if fov_v is float or fov_v is int:
		base_fov = clampf(float(fov_v), 65.0, 100.0)
	var sprint_add := 6.0 if (sprinting and hspeed > 0.5) else 0.0
	var drunk_add := drunk * 10.0
	var target_fov := base_fov + sprint_add + drunk_add
	camera.fov = lerpf(camera.fov, target_fov, minf(1.0, delta * 6.0))


# ------------------------------------------------------------------ одежда (§6.2: 0 карманов, угар и меш)

func wear(b: ItemBody) -> void:
	if not Net.is_host():
		return
	if worn == b:
		unwear()
		return
	if worn:
		unwear()
	for h in b.held_by.duplicate():
		h.host_release_body(b)
	b.unnest()
	worn = b
	b.worn_by = self
	b.freeze = true
	b.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	b.collision_layer = 0
	b.collision_mask = 0
	AudioBus.play_at("cloth", global_position, -4.0)
	Game.stat_add("worn")
	if b.def.tags.has("clown"):
		Achievements.unlock("clown")
	if b.def.tags.has("unicorn"):
		Achievements.unlock("unicorn")
	Net.broadcast_event("wear", {"peer": peer_id, "nid": b.net_id, "on": true})


func unwear() -> void:
	if worn == null:
		return
	var b := worn
	worn = null
	if is_instance_valid(b):
		b.worn_by = null
		b.freeze = b.proxy
		b.collision_layer = Types.L_ITEM
		b.collision_mask = Types.L_WORLD | Types.L_PLAYER | Types.L_ITEM | Types.L_VEHICLE | Types.L_NPC | Types.L_SHARD
		b.global_position = global_position + head.global_basis.z * -0.6 + Vector3.UP
		if Net.is_host():
			Net.broadcast_event("wear", {"peer": peer_id, "nid": b.net_id, "on": false})


func apply_wear_event(nid: int, on: bool) -> void:
	var b = Net.items.get(nid)
	if on and b:
		worn = b
		b.worn_by = self
		b.collision_layer = 0
	elif not on:
		worn = null
		if b:
			b.worn_by = null


# ------------------------------------------------------------------ разное

func say(text: String, seconds: float = 2.5) -> void:
	say_label.text = text
	_say_timer = seconds
	said.emit(text)
	if is_local():
		Game.notify.emit(text, seconds)
	elif Net.is_host() and Net.peer_count() > 1:
		Net.broadcast_event("say", {"peer": peer_id, "text": text})


func set_talking(v: bool) -> void:
	talking = v
	talk_icon.visible = v and not is_local()


func read_document(b: ItemBody) -> void:
	var text := b.def.lore_ru if TranslationServer.get_locale().begins_with("ru") else b.def.lore_en
	if text == "":
		text = b.def.display_name()
	if is_local():
		Game.notify.emit("📄 " + text, 5.0)
	else:
		Net.broadcast_event("read_doc", {"peer": peer_id, "text": text})
	Game.stat_add("docs_read")


func toggle_paddle() -> void:
	if paddle_up:
		lower_paddle()
		return
	if Game.world_mode != Types.WorldMode.AUCTION or in_custody or in_vehicle:
		say(tr("PADDLE_NOT_HERE"))
		return
	# весло — только у ангара с торгами, а не где угодно по городу
	var hud = Game.world.hud if Game.world else null
	if hud and "bid_panel" in hud and hud.bid_panel and not hud.bid_panel.visible:
		say(tr("PADDLE_NOT_HERE"))
		return
	paddle_up = true
	_update_paddle_visual()
	if hud and hud.has_method("set_bid_paddle_up"):
		hud.set_bid_paddle_up(true)
	Net.request_action("paddle_show", {})


## Убрать весло (B повторно, Esc/R с веслом, конец торгов, арест, смерть).
func lower_paddle() -> void:
	if not paddle_up:
		return
	paddle_up = false
	_update_paddle_visual()
	if Game.world and Game.world.hud and Game.world.hud.has_method("set_bid_paddle_up"):
		Game.world.hud.set_bid_paddle_up(false)


func _update_paddle_visual() -> void:
	if paddle_up and _paddle == null:
		var scene := load("res://ui/paddle/Paddle.tscn") as PackedScene
		if scene:
			_paddle = scene.instantiate()
			paddle_mount.add_child(_paddle)
			if _paddle.has_method("set_owner_player"):
				_paddle.set_owner_player(self)
	elif not paddle_up and _paddle:
		_paddle.queue_free()
		_paddle = null
		if Game.world and Game.world.hud and Game.world.hud.has_method("set_my_bid"):
			Game.world.hud.set_my_bid(-1, false)


func _paddle_raise() -> void:
	if _paddle and _paddle.has_method("raise"):
		_paddle.raise()


func paddle() -> Node3D:
	return _paddle


func _scrub_tick(_delta: float) -> void:
	# тряпка в руках + зажата ЛКМ + смотрим на грязное → скребём мышью (§13)
	var rag := hands.holds_tag("rag")
	if rag == null or not Input.is_action_pressed("grab"):
		return
	var target = look_target()
	if target is ItemBody and target.def.has_facet(Types.Facet.DIRTYABLE):
		var mouse_speed := Input.get_last_mouse_velocity().length()
		if mouse_speed > 150.0 and Engine.get_physics_frames() % 4 == 0:
			Net.request_action("scrub", {"target": target.net_id, "rag": rag.net_id, "amount": clampf(mouse_speed / 3000.0, 0.02, 0.12)})


func set_cuffed(v: bool) -> void:
	cuffed = v
	if v:
		hands.host_release_all()
	if Net.is_host():
		Net.broadcast_event("cuffed", {"peer": peer_id, "on": v})


func enter_vehicle(v: Node) -> void:
	in_vehicle = v
	collision_layer = 0
	body_mesh.visible = false
	# руки решает хост в Vehicles.host_enter (водитель бросает, пассажир везёт вещь на коленях)


func exit_vehicle(pos: Vector3) -> void:
	in_vehicle = null
	collision_layer = Types.L_PLAYER
	body_mesh.visible = true
	global_position = pos
	velocity = Vector3.ZERO
