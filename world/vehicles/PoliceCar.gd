class_name PoliceCar
extends Node3D
## Косметическая ментовская машина (§13): коробка с мигалкой. Приезжает по прямой, паркуется,
## везёт арестованного в участок, уезжает. Не водится. Одинаково крутится у хоста и у клиентов (твины).

signal arrived()

const BODY_COLOR := Color(0.12, 0.16, 0.36)
const TRIM_COLOR := Color(0.92, 0.92, 0.95)
const SIREN_EVERY := 2.2

var car_id := 0
var passenger: Node = null
var lights_on := true
var driving := false

var _red: OmniLight3D
var _blue: OmniLight3D
var _red_mat: StandardMaterial3D
var _blue_mat: StandardMaterial3D
var _flash_t := 0.0
var _siren_t := 0.0
var _tween: Tween
var _leaving := false


func _ready() -> void:
	_build()


func _box(size: Vector3, pos: Vector3, color: Color, emissive := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if emissive:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 2.0
	mi.material_override = m
	mi.position = pos
	add_child(mi)
	return mi


func _build() -> void:
	_box(Vector3(1.9, 0.7, 4.2), Vector3(0, 0.65, 0), BODY_COLOR)
	_box(Vector3(1.9, 0.22, 4.2), Vector3(0, 0.55, 0), TRIM_COLOR)
	_box(Vector3(1.7, 0.55, 2.0), Vector3(0, 1.25, -0.2), BODY_COLOR)
	var glass := _box(Vector3(1.72, 0.4, 2.02), Vector3(0, 1.3, -0.2), Color(0.25, 0.3, 0.4, 0.6))
	var glass_mat := glass.material_override as StandardMaterial3D
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_box(Vector3(1.2, 0.14, 0.3), Vector3(0, 1.6, -0.3), Color(0.1, 0.1, 0.1))
	_red_mat = _box(Vector3(0.5, 0.16, 0.28), Vector3(-0.32, 1.72, -0.3), Color(1, 0.15, 0.1), true).material_override as StandardMaterial3D
	_blue_mat = _box(Vector3(0.5, 0.16, 0.28), Vector3(0.32, 1.72, -0.3), Color(0.2, 0.4, 1), true).material_override as StandardMaterial3D
	for x in [-0.95, 0.95]:
		for z in [-1.35, 1.35]:
			var w := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.36
			cm.bottom_radius = 0.36
			cm.height = 0.28
			cm.radial_segments = 10
			w.mesh = cm
			var wm := StandardMaterial3D.new()
			wm.albedo_color = Color(0.08, 0.08, 0.08)
			w.material_override = wm
			w.position = Vector3(x, 0.36, z)
			w.rotation.z = PI * 0.5
			add_child(w)
	for i in 2:
		var lbl := Label3D.new()
		lbl.text = "POLICE"
		lbl.font_size = 64
		lbl.pixel_size = 0.006
		lbl.outline_size = 6
		lbl.modulate = TRIM_COLOR
		lbl.position = Vector3(0.96 if i == 0 else -0.96, 0.75, 0.3)
		lbl.rotation.y = PI * 0.5 if i == 0 else -PI * 0.5
		add_child(lbl)
	_red = OmniLight3D.new()
	_red.light_color = Color(1, 0.2, 0.1)
	_red.light_energy = 3.0
	_red.omni_range = 9.0
	_red.shadow_enabled = false
	_red.position = Vector3(-0.35, 1.9, -0.3)
	add_child(_red)
	_blue = OmniLight3D.new()
	_blue.light_color = Color(0.25, 0.4, 1)
	_blue.light_energy = 3.0
	_blue.omni_range = 9.0
	_blue.shadow_enabled = false
	_blue.position = Vector3(0.35, 1.9, -0.3)
	add_child(_blue)
	# коллизия: в машину нельзя пройти, но она косметика (слой vehicle)
	var body := AnimatableBody3D.new()
	body.name = "Collider"
	body.sync_to_physics = true
	body.collision_layer = Types.L_VEHICLE
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.9, 1.6, 4.2)
	cs.shape = bs
	cs.position = Vector3(0, 0.85, 0)
	body.add_child(cs)
	add_child(body)


func _process(delta: float) -> void:
	if lights_on:
		_flash_t += delta
		var phase := fmod(_flash_t * 4.0, 2.0)
		var red_on := phase < 1.0
		_red.visible = red_on
		_blue.visible = not red_on
		_red_mat.emission_energy_multiplier = 3.0 if red_on else 0.3
		_blue_mat.emission_energy_multiplier = 0.3 if red_on else 3.0
	else:
		_red.visible = false
		_blue.visible = false
	if driving:
		_siren_t -= delta
		if _siren_t <= 0.0:
			_siren_t = SIREN_EVERY
			AudioBus.play_at("siren", global_position, -2.0, 0.05)


func _physics_process(_delta: float) -> void:
	# арестованный едет внутри (у него самого движение выключено, пока in_vehicle)
	if passenger and is_instance_valid(passenger) and passenger.get("in_vehicle") == self:
		passenger.global_position = global_position + Vector3(0, 0.45, 0.2)
		passenger.reset_physics_interpolation()


## Приехать: появиться в from, доехать до to за dur секунд.
func arrive(from: Vector3, to: Vector3, dur: float) -> void:
	global_position = from
	_face(to)
	_drive(to, dur, Tween.EASE_OUT)


func drive_to(to: Vector3, dur: float) -> void:
	_face(to)
	_drive(to, dur, Tween.EASE_IN_OUT)


## Уехать по прямой и исчезнуть.
func leave(dur: float = 3.0) -> void:
	if _leaving:
		return
	_leaving = true
	passenger = null
	var to := global_position + (-global_basis.z) * 45.0
	_drive(to, dur, Tween.EASE_IN)
	arrived.connect(queue_free, CONNECT_ONE_SHOT)


func _drive(to: Vector3, dur: float, p_ease: Tween.EaseType) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	driving = true
	_siren_t = 0.0
	if dur <= 0.0 or not is_inside_tree():
		global_position = to
		driving = false
		call_deferred("emit_signal", "arrived")
		return
	_tween = create_tween()
	_tween.tween_property(self, "global_position", to, dur).set_trans(Tween.TRANS_SINE).set_ease(p_ease)
	_tween.finished.connect(func():
		driving = false
		arrived.emit())


func _face(to: Vector3) -> void:
	var d := to - global_position
	d.y = 0.0
	if d.length() > 0.05:
		rotation.y = atan2(-d.x, -d.z)
