class_name Npc
extends CharacterBody3D
## Базовый NPC (§9, §11, §13): мультяшный капсульный чел, речь-пузырь + нейрокрик, простое перемещение.
## Хост управляет; клиенты получают позицию через события системы-владельца (грубо, NPC не носятся).

signal arrived()
signal shouted(text: String)

@export var npc_group: String = "generic" # папка голоса: res://audio/voice/<lang>/<group>
@export var body_color: Color = Color(0.6, 0.5, 0.4)
@export var height: float = 1.75
@export var fatness: float = 1.0
@export var voice_pitch: float = 1.0
@export var display_name: String = ""
@export var hat: bool = false
@export var bald: bool = false

var move_target: Vector3
var moving := false
var speed := 2.6
var _say_timer := 0.0
var _body: MeshInstance3D
var _head: MeshInstance3D
var _label: Label3D
var _say: Label3D
var _mat: StandardMaterial3D
var _paddle: Node3D
var _mouth_timer := 0.0
var ragdolled := false
var _rag: Node3D
var _push_vel := Vector3.ZERO


func _ready() -> void:
	add_to_group("npcs")
	collision_layer = Types.L_NPC
	collision_mask = Types.L_WORLD | Types.L_ITEM | Types.L_PLAYER | Types.L_NPC | Types.L_VEHICLE
	_build_visual()


## Кей-арт: гранёный коротыш, огромная голова, кепка, футболка/шорты/кеды. ~24 меша, без скелета.
var _visual: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _mouth: MeshInstance3D
## Рот — эллипсоид: меш круглый, «блин» задаётся сплющиванием по Z. Все режимы рта
## (покой / хантер / речь) домножаются на эту базу, иначе пасть снова станет шаром.
const _MOUTH_REST := Vector3(0.85, 0.42, 1.0)
const _MOUTH_REST_HUNTER := Vector3(1.0, 0.82, 1.0)
var _mouth_base_scale := Vector3(1.0, 1.0, 0.42)
var _skin_tone: Color
var _legs_h := 0.8
var _torso_h := 0.7
var _shoulder_y := 1.4
var _head_y := 1.6
var _arm_rest_l := 0.22
var _arm_rest_r := 0.22
var _fist_y := -0.28
var _eye_l: MeshInstance3D
var _eye_r: MeshInstance3D
var _pupil_l: MeshInstance3D
var _pupil_r: MeshInstance3D
var _eye_base_scale := Vector3(0.72, 1.05, 0.62)
var _pupil_rest_l := Vector3.ZERO
var _pupil_rest_r := Vector3.ZERO
var _life_t := 0.0
var _life_phase := 0.0
var _blink_cd := 3.0
var _blink_left := 0.0
var _saccade_cd := 1.5
var _saccade_off := Vector2.ZERO
var _saccade_want := Vector2.ZERO
var _hop_t := 0.0
var _rng: RandomNumberGenerator
var _body_base_scale := Vector3(1.0, 1.0, 0.88)

static var _MAT_CACHE: Dictionary = {}

const _WHITE := Color(0.97, 0.97, 0.95)
const _PUPIL := Color(0.06, 0.05, 0.07)
const _MOUTH_C := Color(0.07, 0.03, 0.04)
const _TONGUE := Color(0.90, 0.18, 0.28)
const _SHOE_W := Color(0.96, 0.95, 0.93)
const _SHOE_SOLE := Color(0.62, 0.08, 0.12)
const _SOCK := Color(0.94, 0.94, 0.92)


static func _col_mat(color: Color, rough := 0.9) -> StandardMaterial3D:
	var key := "%d_%.2f" % [color.to_rgba32(), rough]
	var cached: Variant = _MAT_CACHE.get(key)
	if cached is StandardMaterial3D:
		return cached
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = 0.0
	_MAT_CACHE[key] = m
	return m


static func _mesh(parent: Node, mesh: Mesh, color: Color, pos: Vector3, rough := 0.9) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _col_mat(color, rough)
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _capsule(r: float, h: float, seg := 8) -> ArrayMesh:
	return LowPoly.capsule(r, maxf(h, r * 2.05), seg, 3)


static func _box(size: Vector3, bevel := -1.0) -> ArrayMesh:
	var b := bevel if bevel > 0.0 else minf(minf(size.x, size.y), size.z) * 0.14
	return LowPoly.chamfer_box(size, b)


## Яркая насыщенная футболка: сохраняем оттенок body_color, поднимаем S/V.
static func _punch(c: Color) -> Color:
	var s := c.s
	var v := c.v
	if s < 0.18:
		s = 0.74
	else:
		s = clampf(s * 1.28, 0.64, 0.96)
	v = clampf(maxf(v, 0.40) * 1.18, 0.64, 0.93)
	return Color.from_hsv(c.h, s, v)


func _build_visual() -> void:
	for c in get_children():
		if c is CollisionShape3D or c == _visual or c == _label or c == _say:
			c.queue_free()
	var cs := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.36 * fatness
	shape.height = height
	cs.shape = shape
	cs.position.y = height * 0.5
	add_child(cs)
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)

	# детерминированные вариации по цвету/имени, чтобы каждый NPC выглядел по-своему
	var seed_v := int(body_color.to_rgba32()) ^ display_name.hash() ^ int(height * 100.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var skins: Array[Color] = [
		Color(0.96, 0.70, 0.48), Color(0.93, 0.64, 0.42), Color(0.84, 0.54, 0.36),
		Color(0.66, 0.40, 0.28), Color(0.98, 0.74, 0.52)
	]
	_skin_tone = skins[0] if rng.randf() < 0.55 else skins[rng.randi() % skins.size()]
	var shirt := _punch(body_color)
	var shorts := Color.from_hsv(fmod(shirt.h + 0.36 + rng.randf() * 0.12, 1.0), 0.64, 0.40)
	var stripe_c := Color.from_hsv(fmod(shirt.h + 0.08, 1.0), 0.85, 0.78)
	var hair_set: Array[Color] = [Color(0.12, 0.08, 0.06), Color(0.38, 0.20, 0.08), Color(0.82, 0.62, 0.22), Color(0.55, 0.55, 0.58), Color(0.72, 0.22, 0.10)]
	var hair_c: Color = hair_set[rng.randi() % hair_set.size()]
	var cap_set: Array[Color] = [
		Color(0.18, 0.42, 0.96), Color(0.96, 0.22, 0.62), Color(0.96, 0.18, 0.16),
		Color(0.98, 0.84, 0.12), Color(0.16, 0.78, 0.32), Color(0.62, 0.22, 0.90)
	]
	var cap_c: Color = cap_set[rng.randi() % cap_set.size()]

	# пропорции кей-арта: голова ≈ 40% роста, диаметр ≈ ширина торса × 1.1
	_legs_h = height * 0.255
	_torso_h = height * 0.30
	var hip_y := _legs_h
	var head_r := height * 0.205
	var torso_r := (head_r / 1.1) * (0.86 + 0.14 * fatness)
	_shoulder_y = hip_y + _torso_h * 0.78
	_head_y = hip_y + _torso_h + head_r * 0.42

	_mat = _col_mat(shirt)

	# --- ноги: белые носки в полоску + огромные кеды (пивот в бедре)
	var leg_r := 0.11 * sqrt(fatness) * (height / 1.75)
	var sock_h := _legs_h * 0.82
	var shoe_s := Vector3(leg_r * 2.85, leg_r * 1.7, leg_r * 4.1)
	for side in [-1.0, 1.0]:
		var piv := Node3D.new()
		piv.name = "LegL" if side < 0.0 else "LegR"
		piv.position = Vector3(side * torso_r * 0.42, hip_y, 0.0)
		_visual.add_child(piv)
		_mesh(piv, LowPoly.cylinder(leg_r, leg_r * 1.06, sock_h, 8), _SOCK, Vector3(0, -sock_h * 0.42, 0.0))
		var band_y := -sock_h * 0.12
		_mesh(piv, LowPoly.cylinder(leg_r * 1.09, leg_r * 1.09, sock_h * 0.07, 8), stripe_c, Vector3(0, band_y, 0.0))
		_mesh(piv, LowPoly.cylinder(leg_r * 1.09, leg_r * 1.09, sock_h * 0.07, 8), stripe_c, Vector3(0, band_y - sock_h * 0.11, 0.0))
		var shoe_y := -_legs_h + shoe_s.y * 0.55
		_mesh(piv, _box(shoe_s), _SHOE_W, Vector3(0.0, shoe_y, -leg_r * 0.95), 0.85)
		_mesh(piv, _box(Vector3(shoe_s.x * 1.08, shoe_s.y * 0.32, shoe_s.z * 1.08), 0.012), _SHOE_SOLE, Vector3(0.0, shoe_y - shoe_s.y * 0.40, -leg_r * 0.95), 0.95)
		if side < 0.0:
			_leg_l = piv
		else:
			_leg_r = piv

	# --- торс: короткая жирная футболка + шорты
	_body = MeshInstance3D.new()
	_body.name = "Body"
	_body.mesh = _capsule(torso_r, _torso_h, 8)
	_body.material_override = _mat
	_body.position = Vector3(0.0, hip_y + _torso_h * 0.48, 0.0)
	_body_base_scale = Vector3(1.0, 1.0, 0.88)
	_body.scale = _body_base_scale
	_visual.add_child(_body)
	var shorts_mi := _mesh(_visual, LowPoly.cylinder(torso_r * 1.08, torso_r * 1.14, _torso_h * 0.38, 8), shorts, Vector3(0.0, hip_y + _torso_h * 0.06, 0.0))
	shorts_mi.scale = Vector3(1.0, 1.0, 0.90)

	# --- руки: короткий рукав + кулак-брус, приклеенный к рукаву
	var arm_r := 0.095 * sqrt(fatness) * (height / 1.75)
	var arm_len := _torso_h * 0.88
	_fist_y = -arm_len * 0.78
	var fist_s := Vector3(arm_r * 2.5, arm_r * 2.15, arm_r * 2.4)
	for side in [-1.0, 1.0]:
		var piv := Node3D.new()
		piv.name = "ArmL" if side < 0.0 else "ArmR"
		piv.position = Vector3(side * (torso_r * 0.95 + arm_r * 0.25), _shoulder_y, 0.04)
		_visual.add_child(piv)
		# шар-плечо в точке вращения: заполняет щель между рукавом и торсом на любом
		# повороте руки (без него в кадре видно, что руки просто висят рядом с телом)
		_mesh(piv, LowPoly.sphere(arm_r * 1.32, 8, 4), shirt, Vector3.ZERO)
		_mesh(piv, _capsule(arm_r, arm_len * 0.70, 8), shirt, Vector3(0.0, -arm_len * 0.32, 0.0))
		var fist := _mesh(piv, _box(fist_s), _skin_tone, Vector3(0.0, _fist_y, 0.0))
		fist.name = "HandL" if side < 0.0 else "HandR"
		piv.rotation.z = -side * 0.22
		piv.rotation.x = 0.22
		if side < 0.0:
			_arm_l = piv
			_arm_rest_l = 0.22
		else:
			_arm_r = piv
			_arm_rest_r = 0.22

	# хантер держит весло у правого бока (HunterPaddle на теле, не на руке) — кулак рядом с рукоятью
	if npc_group == "hunter":
		_arm_rest_r = 0.72
		if _arm_r:
			_arm_r.rotation = Vector3(0.72, -0.12, 0.42)

	# --- голова: огромный гранёный шар
	_head = MeshInstance3D.new()
	_head.name = "Head"
	_head.mesh = LowPoly.sphere(head_r, 8, 3)
	_head.material_override = _col_mat(_skin_tone, 0.88)
	_head.position.y = _head_y
	_visual.add_child(_head)

	# Лицо (§кей-арт): выпученные ГЛАЗНЫЕ ЯБЛОКИ, а не линзы. Раньше глаз строился
	# `sphere(r, 8, 3, h=0.88r)` — тянутая по Y сфера с 3 кольцами даёт острые полюса, и
	# на рендере глаз читался белым шипом, торчащим вбок сквозь козырёк. Теперь это
	# КРУГЛЫЙ шар (10 сегментов, 5 колец, без растяжки высоты), а овал даёт scale.
	# Центр шара утоплен внутрь черепа — наружу выходит только купол, как в кей-арте.
	var eye_rx := head_r * 0.30
	var eye_x := head_r * 0.34
	var eye_z := -head_r * 0.72
	var eye_y := head_r * 0.10
	_eye_base_scale = Vector3(0.80, 1.18, 0.80)
	for x in [-eye_x, eye_x]:
		var eye := _mesh(_head, LowPoly.sphere(eye_rx, 10, 5), _WHITE, Vector3(x, eye_y, eye_z), 0.70)
		eye.scale = _eye_base_scale
		# зрачок — жирная точка на передней стенке яблока (читается с 10 м, а не пиксель)
		var pupil := _mesh(_head, LowPoly.sphere(head_r * 0.13, 8, 4), _PUPIL, Vector3(x, eye_y - head_r * 0.02, eye_z - eye_rx * 0.62), 0.40)
		if x < 0.0:
			eye.name = "EyeL"
			pupil.name = "PupilL"
			_eye_l = eye
			_pupil_l = pupil
			_pupil_rest_l = pupil.position
		else:
			eye.name = "EyeR"
			pupil.name = "PupilR"
			_eye_r = eye
			_pupil_r = pupil
			_pupil_rest_r = pupil.position
	_bind_life()

	# Рот: был `chamfer_box` — плоская чёрная плита, торчавшая из лица на ~3 см (её ставили
	# по идеальному радиусу сферы, а гранёный череп лежит заметно внутри него). Теперь это
	# приплюснутый эллипсоид: спереди — круглый тёмный овал орущей пасти, без углов.
	_mouth = MeshInstance3D.new()
	_mouth.name = "Mouth"
	_mouth.mesh = LowPoly.sphere(head_r * 0.46, 10, 5, false, head_r * 0.62)
	_mouth.material_override = _col_mat(_MOUTH_C, 0.95)
	_mouth.position = Vector3(0.0, -head_r * 0.36, -head_r * 0.74)
	_head.add_child(_mouth)
	var tongue := _mesh(_mouth, _box(Vector3(head_r * 0.42, head_r * 0.14, head_r * 0.10)), _TONGUE, Vector3(0.0, -head_r * 0.16, -head_r * 0.10))
	tongue.name = "Tongue"
	# кей-арт орёт всегда; в покое рот всё ещё читается как тёмная дыра, при речи раскрывается
	_mouth.scale = _mouth_base_scale * (_MOUTH_REST_HUNTER if npc_group == "hunter" else _MOUTH_REST)

	# волосы / лысина / кепка / бини — через существующие hat/bald
	if hat:
		# приплюснутый купол + толстый козырёк-плита (не конус)
		_mesh(_head, LowPoly.sphere(head_r * 1.10, 8, 3, true, head_r * 0.72), cap_c, Vector3(0.0, head_r * 0.22, 0.04))
		_mesh(_head, _box(Vector3(head_r * 1.32, head_r * 0.14, head_r * 0.78), 0.014), cap_c, Vector3(0.0, head_r * 0.14, -head_r * 1.05))
	elif not bald:
		if rng.randf() < 0.38:
			_mesh(_head, LowPoly.sphere(head_r * 1.12, 8, 3, true, head_r * 0.70), cap_c, Vector3(0.0, head_r * 0.28, 0.02))
			_mesh(_head, LowPoly.cylinder(head_r * 1.10, head_r * 1.14, head_r * 0.18, 8), cap_c.darkened(0.15), Vector3(0.0, head_r * 0.16, 0.0))
		else:
			_mesh(_head, _box(Vector3(head_r * 1.15, head_r * 0.32, head_r * 1.05)), hair_c, Vector3(0.0, head_r * 0.62, 0.06))
			_mesh(_head, _box(Vector3(head_r * 0.48, head_r * 0.28, head_r * 0.40)), hair_c, Vector3(-head_r * 0.22, head_r * 0.70, head_r * 0.12))
	else:
		if rng.randf() < 0.40:
			_mesh(_head, _box(Vector3(head_r * 0.46, head_r * 0.07, head_r * 0.12)), hair_c, Vector3(0.0, -head_r * 0.18, -head_r * 0.88))
		if rng.randf() < 0.50:
			_mesh(_head, _box(Vector3(head_r * 0.20, head_r * 0.14, head_r * 0.18)), hair_c, Vector3(head_r * 0.58, head_r * 0.32, 0.02))

	_label = Label3D.new()
	_label.text = display_name
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 40
	_label.outline_size = 8
	_label.position.y = height + 0.35
	_label.pixel_size = 0.004
	add_child(_label)
	_say = Label3D.new()
	_say.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_say.font_size = 36
	_say.outline_size = 10
	_say.modulate = Color(1, 1, 0.75)
	_say.position.y = height + 0.6
	_say.pixel_size = 0.004
	_say.width = 600
	_say.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_say)


func set_look(color: Color, p_height: float, p_fat: float, p_hat: bool, p_bald: bool) -> void:
	body_color = color
	height = p_height
	fatness = p_fat
	hat = p_hat
	bald = p_bald
	if is_inside_tree():
		_build_visual()


## Говорит: пузырь + нейрокрик из папки группы (§3). category — префикс файлов ("bid", "angry", ...).
func say(text: String, seconds: float = 2.5, category: String = "") -> void:
	if _say:
		_say.text = text
	_say_timer = seconds
	shouted.emit(text)
	var len := AudioBus.npc_shout(npc_group, global_position + Vector3(0, height, 0), voice_pitch, category)
	_mouth_timer = maxf(len, 0.4)
	_on_spoke(text)
	if Net.is_host() and Net.peer_count() > 1:
		Net.broadcast_event("npc_say", {"path": str(get_path()), "text": text, "sec": seconds, "cat": category})


func remote_say(text: String, seconds: float, category: String) -> void:
	if _say:
		_say.text = text
	_say_timer = seconds
	var len := AudioBus.npc_shout(npc_group, global_position + Vector3(0, height, 0), voice_pitch, category)
	_mouth_timer = maxf(len, 0.4)
	_on_spoke(text)


func _on_spoke(text: String) -> void:
	if npc_group == "hunter" and text.contains("!"):
		_hop_t = 0.25


func move_to(p: Vector3) -> void:
	move_target = p
	moving = true


func face(p: Vector3) -> void:
	var d := p - global_position
	d.y = 0.0
	if d.length() > 0.05:
		rotation.y = atan2(-d.x, -d.z)


func _physics_process(delta: float) -> void:
	if _say_timer > 0.0:
		_say_timer -= delta
		if _say_timer <= 0.0 and _say:
			_say.text = ""
	if _mouth_timer > 0.0:
		_mouth_timer -= delta
		var m: MeshInstance3D = _mouth
		if m == null and _head:
			m = _head.get_node_or_null("Mouth") as MeshInstance3D
		if m:
			m.scale = _mouth_base_scale * Vector3(1.05, 1.05 + absf(sin(Time.get_ticks_msec() * 0.028)) * 0.22, 1.0)
	else:
		var m: MeshInstance3D = _mouth
		if m == null and _head:
			m = _head.get_node_or_null("Mouth") as MeshInstance3D
		if m:
			m.scale = _mouth_base_scale * (_MOUTH_REST_HUNTER if npc_group == "hunter" else _MOUTH_REST)
	if ragdolled:
		return
	if not Net.is_host():
		return
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = 0.0
	if moving:
		var d := move_target - global_position
		d.y = 0.0
		if d.length() < 0.25:
			moving = false
			velocity.x = 0.0
			velocity.z = 0.0
			arrived.emit()
		else:
			var v := d.normalized() * speed
			velocity.x = v.x
			velocity.z = v.z
			face(move_target)
	else:
		velocity.x = move_toward(velocity.x, 0.0, delta * 10.0)
		velocity.z = move_toward(velocity.z, 0.0, delta * 10.0)
	velocity += _push_vel
	_push_vel = _push_vel.move_toward(Vector3.ZERO, delta * 8.0)
	move_and_slide()


var _walk_phase := 0.0
var _idle_phase := 0.0


func _bind_life() -> void:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.seed = get_instance_id()
	if _life_phase == 0.0:
		_life_phase = float(absi(get_instance_id()) % 10007) * 0.001837
	_idle_phase = _life_phase
	_blink_cd = _rng.randf_range(2.5, 6.0)
	_saccade_cd = _rng.randf_range(1.0, 3.0)


func _process(delta: float) -> void:
	if ragdolled or _visual == null or _body == null or _head == null:
		return
	_life_t += delta
	_anim_walk(delta)
	_anim_alive(delta)


## Мультяшная походка: подпрыгивание тела, качание головы; стоя — дышит.
func _anim_walk(delta: float) -> void:
	var sp := Vector3(velocity.x, 0, velocity.z).length()
	_idle_phase += delta * 2.0
	var torso_y := _legs_h + _torso_h * 0.48
	var head_y := _head_y
	var breath := sin((_life_t + _life_phase) * TAU * 1.1)
	if sp > 0.3:
		_walk_phase += delta * sp * 4.5
		var swing := sin(_walk_phase)
		var bounce := absf(swing) * 0.05
		_visual.position.y = bounce
		_body.position.y = torso_y
		_body.scale = _body_base_scale
		_body.rotation.z = swing * deg_to_rad(3.0)
		_body.rotation.y = swing * 0.08
		_head.position.y = head_y
		_head.rotation.z = -swing * 0.08
		if _leg_l and _leg_r:
			_leg_l.rotation.x = swing * 0.7
			_leg_r.rotation.x = -swing * 0.7
		if _arm_l and _arm_r:
			_arm_l.rotation.x = _arm_rest_l - swing * 0.6
			_arm_r.rotation.x = _arm_rest_r + swing * 0.6
	else:
		_visual.position.y = lerpf(_visual.position.y, 0.0, delta * 8.0)
		_body.position.y = lerpf(_body.position.y, torso_y, delta * 8.0)
		_body.scale = Vector3(_body_base_scale.x, _body_base_scale.y * (1.0 + breath * 0.015), _body_base_scale.z)
		_body.rotation.z = lerpf(_body.rotation.z, 0.0, delta * 8.0)
		_body.rotation.y = lerpf(_body.rotation.y, 0.0, delta * 8.0)
		_head.position.y = lerpf(_head.position.y, head_y + breath * 0.012, delta * 8.0)
		_head.rotation.z = lerpf(_head.rotation.z, sin(_idle_phase * 0.7) * 0.03, delta * 8.0)
		if _leg_l and _leg_r:
			_leg_l.rotation.x = lerpf(_leg_l.rotation.x, 0.0, delta * 10.0)
			_leg_r.rotation.x = lerpf(_leg_r.rotation.x, 0.0, delta * 10.0)
		if _arm_l and _arm_r:
			_arm_l.rotation.x = lerpf(_arm_l.rotation.x, _arm_rest_l + sin(_idle_phase) * 0.04, delta * 8.0)
			_arm_r.rotation.x = lerpf(_arm_r.rotation.x, _arm_rest_r - sin(_idle_phase) * 0.04, delta * 8.0)
	if _mouth_timer <= 0.0:
		_head.rotation.x = lerpf(_head.rotation.x, 0.0, delta * 8.0)


func _anim_alive(delta: float) -> void:
	if _hop_t > 0.0:
		_hop_t = maxf(0.0, _hop_t - delta)
		_visual.position.y += 0.06 * sin(PI * (1.0 - _hop_t / 0.25))
	_blink_cd -= delta
	if _blink_cd <= 0.0:
		_blink_left = 0.1
		if _rng:
			_blink_cd = _rng.randf_range(2.5, 6.0)
		else:
			_blink_cd = 3.5
	var eye_y := 0.1 if _blink_left > 0.0 else _eye_base_scale.y
	if _blink_left > 0.0:
		_blink_left -= delta
	if _eye_l:
		_eye_l.scale = Vector3(_eye_base_scale.x, eye_y, _eye_base_scale.z)
	if _eye_r:
		_eye_r.scale = Vector3(_eye_base_scale.x, eye_y, _eye_base_scale.z)
	var idle := Vector3(velocity.x, 0.0, velocity.z).length() <= 0.3 and not moving
	var look_off := _saccade_want
	var want_yaw := 0.0
	var pl := _front_player() if idle else null
	if pl:
		look_off = _pupil_toward(pl)
		var to: Vector3 = pl.global_position - global_position
		to.y = 0.0
		if to.length_squared() > 0.01:
			var world_yaw := atan2(-to.x, -to.z)
			want_yaw = clampf(wrapf(world_yaw - rotation.y, -PI, PI), -deg_to_rad(35.0), deg_to_rad(35.0))
	else:
		_saccade_cd -= delta
		if _saccade_cd <= 0.0:
			if _rng:
				_saccade_want = Vector2(_rng.randf_range(-0.02, 0.02), _rng.randf_range(-0.02, 0.02))
				_saccade_cd = _rng.randf_range(1.0, 3.0)
			else:
				_saccade_cd = 2.0
		look_off = _saccade_want
	_saccade_off = _saccade_off.lerp(look_off, minf(1.0, delta * 8.0))
	if _pupil_l:
		_pupil_l.position = _pupil_rest_l + Vector3(_saccade_off.x, _saccade_off.y, 0.0)
	if _pupil_r:
		_pupil_r.position = _pupil_rest_r + Vector3(_saccade_off.x, _saccade_off.y, 0.0)
	_head.rotation.y = lerp_angle(_head.rotation.y, want_yaw, minf(1.0, delta * 4.0))
	if _mouth_timer > 0.0 or _say_timer > 0.0:
		_head.rotation.x = sin(_life_t * TAU * 3.0) * deg_to_rad(6.0)
		if _arm_r and not _paddle_raised():
			_arm_r.rotation.x = _arm_rest_r + sin(_life_t * TAU * 2.4) * deg_to_rad(25.0)


func _paddle_raised() -> bool:
	if npc_group != "hunter":
		return false
	var v: Variant = get("_raising")
	return v is bool and bool(v)


func _front_player() -> Node3D:
	var best: Node3D = null
	var best_d := 36.0
	if Net.players.is_empty():
		return null
	for pid in Net.players:
		var pl: Variant = Net.players[pid]
		if not (pl is Player):
			continue
		var pp: Player = pl as Player
		if not is_instance_valid(pp) or pp.dead:
			continue
		var off: Vector3 = pp.global_position - global_position
		off.y = 0.0
		var d2 := off.length_squared()
		if d2 > best_d or d2 < 0.04:
			continue
		var fwd := -global_transform.basis.z
		fwd.y = 0.0
		if fwd.length_squared() < 0.01 or off.normalized().dot(fwd.normalized()) < 0.15:
			continue
		best = pp
		best_d = d2
	return best


func _pupil_toward(pl: Node3D) -> Vector2:
	if _head == null:
		return Vector2.ZERO
	var local: Vector3 = _head.to_local(pl.global_position + Vector3(0.0, 1.4, 0.0))
	var look := Vector2(local.x, local.y)
	if look.length_squared() > 0.0001:
		look = look.normalized() * 0.02
	return Vector2(clampf(look.x, -0.02, 0.02), clampf(look.y, -0.02, 0.02))


## Толчок/удар (§9 потасовка): импульс, при сильном — ragdoll на пару секунд.
func shove(impulse: Vector3) -> void:
	_push_vel += impulse
	if impulse.length() > 6.0 and not ragdolled:
		ragdoll_for(3.5)
	say(_pick_angry(), 2.0, "angry")


func ragdoll_for(seconds: float) -> void:
	if ragdolled:
		return
	ragdolled = true
	if _visual:
		_visual.visible = false
	for c in get_children():
		if c is MeshInstance3D:
			c.visible = false
	_rag = Ragdoll.make(body_color)
	get_parent().add_child(_rag)
	_rag.global_position = global_position + Vector3(0, 0.9, 0)
	_rag.kick(Vector3(randf_range(-1, 1), 1.0, randf_range(-1, 1)) * 2.0)
	AudioBus.play_at("oof", global_position, 0.0, 0.3)
	if Net.is_host():
		Net.broadcast_event("npc_ragdoll", {"path": str(get_path()), "sec": seconds})
	await get_tree().create_timer(seconds).timeout
	if is_instance_valid(_rag):
		global_position = _rag.global_position - Vector3(0, 0.5, 0)
		global_position.y = maxf(global_position.y, 0.0)
		_rag.queue_free()
	ragdolled = false
	if _visual:
		_visual.visible = true
	for c in get_children():
		if c is MeshInstance3D:
			c.visible = true


func _pick_angry() -> String:
	var ru := ["Э!", "Ты чё?!", "Руки убрал!", "Охрана!", "Я тебя запомнил"]
	var en := ["Hey!", "What the hell?!", "Hands off!", "Security!", "I'll remember you"]
	var arr := ru if TranslationServer.get_locale().begins_with("ru") else en
	return arr[randi() % arr.size()]


func on_grab(_player: Node) -> void:
	# схватили за шкирку — толчок
	shove((global_position - _player.global_position).normalized() * 3.0 + Vector3.UP)
