class_name Vehicle
extends VehicleBody3D
## Тачка (§10): аркадные колёса, скачки, дырявый кузов — физический объём, в котором вещи реально едут.
## Хост симулирует VehicleBody3D; на клиентах — kinematic-прокси с интерполяцией (как ItemBody).
## Геометрия — примитивы, строится в _ready по @export-тюнингу; варианты типов — сцены *.tscn.
## Вперёд = -Z. Сиденья: 0 водитель (слева), 1 пассажир (справа). Кузов — Area3D BedZone + твёрдые борта.

signal seat_changed(seat: int, peer: int)

const TYPES := {
	"pickup_rusty": {"scene": "res://world/vehicles/PickupRusty.tscn", "price": 400, "name_key": "VEH_PICKUP_RUSTY"},
	"van_leaky": {"scene": "res://world/vehicles/VanLeaky.tscn", "price": 1200, "name_key": "VEH_VAN_LEAKY"},
	"truck_fat": {"scene": "res://world/vehicles/TruckFat.tscn", "price": 3200, "name_key": "VEH_TRUCK_FAT"},
}
const CHASSIS_BOTTOM := 0.375
const WALL_T := 0.22
const INPUT_SEND_SEC := 0.1
const FLIP_SEC := 4.0
const WATER_Y := -1.0
const BUMP_SPIKE := 4.0
const SEAT_DRIVER := 0
const SEAT_PASSENGER := 1

@export var vtype := "pickup_rusty"
@export var body_color := Color(0.28, 0.6, 0.55)
@export_group("Drive")
@export var accel := 5.5 ## м/с² при полном газе (сила на колесо = accel * mass / 4)
@export var brake_decel := 9.0 ## м/с² при полном тормозе
@export var top_speed := 15.0
@export var reverse_speed := 5.0
@export var max_steer := 0.62 ## радианы стоя
@export var min_steer := 0.16 ## радианы на топ-скорости
@export_group("Wheels")
@export var wheel_radius := 0.36
@export var wheel_width := 0.28
@export var wheel_y := 0.5 ## точка крепления; луч подвески стартует на wheel_radius выше — держать ниже пола кузова
@export var track := 1.55
@export var axle_front := 1.5 ## |z| передней оси
@export var axle_rear := 1.2
@export var suspension_rest := 0.2
@export var suspension_travel := 0.25
## Godot: сила = stiffness * сжатие * mass; статическое сжатие = g / (4 * stiffness)
@export var suspension_stiffness := 40.0
## Демпфер тоже * mass; ζ ≈ damping / (2 * sqrt(stiffness / 4)) → 1.8 при k=40 ≈ 0.28 (прыгуче, но не мяч)
@export var damping_compression := 1.8
@export var damping_relaxation := 2.6
@export var friction_slip := 4.0
@export var roll_influence := 0.08
@export_group("Body")
@export var body_size := Vector3(1.7, 0.41, 4.0) ## шасси: низ на CHASSIS_BOTTOM, верх = пол кузова
@export var cab_size := Vector3(1.7, 1.2, 1.4) ## ширина, высота над шасси, длина
@export var cab_z := -0.9
@export var hood_length := 0.9
@export_group("Bed")
@export var bed_size := Vector3(1.4, 0.4, 1.8) ## ширина, высота бортов, длина
@export var bed_z := 0.9
@export var bed_missing_wall := 1 ## -1 нет; 0 левый борт; 1 правый; 2 задний
@export var bed_hole := Vector2.ZERO ## дыра в полу (ширина, длина), 0 = нет
@export var bed_hole_z := 0.0 ## z дыры относительно центра кузова
@export var bed_roof := false
@export var bed_roof_height := 1.5
@export var tailgate_height := -1.0 ## -1 = как борта

var vid := 0
var owner_slot := false ## куплена пати → сохраняется
var display := false ## витрина авторынка
var npc_owned := false ## чужая — угон
var stolen := false
var price := 0
var proxy := false
var driver_peer := 0
var passenger_peer := 0
var bed_items: Array = [] ## ItemBody в кузове
var sys: Node = null ## Vehicles
var test_drive := false ## headless-тест: газ без водителя

var _in_steer := 0.0
var _in_throttle := 0.0
var _in_brake := 0.0
var _in_hb := false
var _steer := 0.0
var _visual: Node3D
var _wheels: Array = []
var _front_wheels: Array = []
var _rear_wheels: Array = []
var _seats: Array = [null, null]
var _bed_zone: Area3D
var _bed_floor_y := 0.0
var _price_label: Label3D
var _engine: AudioStreamPlayer3D
var _music: AudioStreamPlayer
var _mats: Dictionary = {}
var _headlights: Array[SpotLight3D] = []
var _dust: GPUParticles3D
var _prune_t := 0.0
var _vy_hist: Array[float] = []
var _flip_t := 0.0
var _spawn_grace := 2.0
var _seat_grace := 0.0
var _skid_cd := 0.0
var _send_t := 0.0
var _last_in := [0.0, 0.0, false]
var _force_state := true
var _target_xf := Transform3D()
var _target_lv := Vector3.ZERO
var _target_av := Vector3.ZERO
var _has_target := false
var _wheel_spin := 0.0


class Door extends Area3D:
	var vehicle: Vehicle
	var seat := 0

	func interact(player: Player) -> void:
		if vehicle:
			vehicle.door_interact(player, seat)

	func interact_hint(player: Player) -> String:
		return vehicle.door_hint(player, seat) if vehicle else ""


static func type_info(t: String) -> Dictionary:
	return TYPES.get(t, TYPES["pickup_rusty"])


func set_proxy(v: bool) -> void:
	proxy = v
	if v:
		freeze = true
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC


func display_name() -> String:
	return tr(type_info(vtype)["name_key"])


func _ready() -> void:
	collision_layer = Types.L_VEHICLE
	collision_mask = Types.L_WORLD | Types.L_ITEM | Types.L_PLAYER | Types.L_NPC | Types.L_VEHICLE | Types.L_SHARD
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.3, 0)
	linear_damp = 0.05
	angular_damp = 0.6
	can_sleep = true
	var pm := PhysicsMaterial.new()
	pm.friction = 0.6
	pm.bounce = 0.1
	physics_material_override = pm
	_build()
	_build_audio()


# ------------------------------------------------------------------ геометрия

## Краска кузова: у «ржавого пикапа» — облезлая бирюза с ржавчиной (кей-арт), у остальных — плоский цвет.
func _mat(c: Color) -> StandardMaterial3D:
	var key := c.to_rgba32()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.85
		var painted := c.is_equal_approx(body_color) or c.is_equal_approx(body_color.darkened(0.15)) or c.is_equal_approx(body_color.darkened(0.3))
		if painted and vtype == "pickup_rusty" and ResourceLoader.exists("res://assets/textures/tex_rust_teal.png"):
			var t: Texture2D = load("res://assets/textures/tex_rust_teal.png")
			m.albedo_texture = t
			m.albedo_color = Color(1, 1, 1).lerp(c, 0.25).lightened(0.05) if c.is_equal_approx(body_color) else Color(0.85, 0.85, 0.85).lerp(c, 0.25)
			m.uv1_triplanar = true
			m.uv1_scale = Vector3.ONE / 1.6
			m.roughness = 0.95
		_mats[key] = m
	return _mats[key]


func _box(size: Vector3, pos: Vector3, color: Color, collide := true, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var smallest := minf(minf(size.x, size.y), size.z)
	if smallest >= 0.1:
		mi.mesh = LowPoly.chamfer_box(size, clampf(smallest * 0.18, 0.015, 0.05)) # рубленые панели, как на арте
	else:
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
	mi.material_override = _mat(color)
	mi.position = pos
	(parent if parent else _visual).add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.position = pos
		add_child(cs)
	return mi


func _build() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	# шасси = пол кузова и кабины: толстый (≈0.4 м), чтобы вещи не проскакивали сквозь него на 30 Гц
	var top := CHASSIS_BOTTOM + body_size.y
	var chassis_y := CHASSIS_BOTTOM + body_size.y * 0.5
	var dark := body_color.darkened(0.3)
	var grey := Color(0.3, 0.3, 0.32)
	if bed_hole.x <= 0.0 or bed_hole.y <= 0.0:
		_box(body_size, Vector3(0, chassis_y, 0), dark)
	else:
		# дыра в полу насквозь: шасси из 4 кусков вокруг неё — вещь меньше дыры падает на дорогу
		var z0 := -body_size.z * 0.5
		var z1 := body_size.z * 0.5
		var hz0 := bed_z + bed_hole_z - bed_hole.y * 0.5
		var hz1 := bed_z + bed_hole_z + bed_hole.y * 0.5
		if hz0 > z0:
			_box(Vector3(body_size.x, body_size.y, hz0 - z0), Vector3(0, chassis_y, (z0 + hz0) * 0.5), dark)
		if z1 > hz1:
			_box(Vector3(body_size.x, body_size.y, z1 - hz1), Vector3(0, chassis_y, (hz1 + z1) * 0.5), dark)
		var side_w := (body_size.x - bed_hole.x) * 0.5
		for sx in [-1.0, 1.0]:
			_box(Vector3(side_w, body_size.y, bed_hole.y), Vector3(sx * (bed_hole.x * 0.5 + side_w * 0.5), chassis_y, (hz0 + hz1) * 0.5), dark)
		var rust := Color(0.45, 0.2, 0.08)
		_box(Vector3(bed_hole.x + 0.1, 0.02, 0.05), Vector3(0, top + 0.01, hz0 - 0.025), rust, false)
		_box(Vector3(bed_hole.x + 0.1, 0.02, 0.05), Vector3(0, top + 0.01, hz1 + 0.025), rust, false)
	# --- кабина
	var cab_front := cab_z - cab_size.z * 0.5
	var cab_back := cab_z + cab_size.z * 0.5
	var front_end := cab_front - hood_length
	_box(Vector3(cab_size.x * 0.96, 0.4, hood_length), Vector3(0, top + 0.2, cab_front - hood_length * 0.5), body_color)
	_box(Vector3(cab_size.x, 0.36, 0.4), Vector3(0, top + 0.18, cab_front + 0.2), dark)
	for sx in [-1.0, 1.0]:
		for z in [cab_front + 0.04, cab_back - 0.04]:
			_box(Vector3(0.08, cab_size.y, 0.08), Vector3(sx * (cab_size.x * 0.5 - 0.04), top + cab_size.y * 0.5, z), body_color)
		_box(Vector3(0.05, 0.6, cab_size.z - 0.16), Vector3(sx * (cab_size.x * 0.5 - 0.025), top + 0.3, cab_z), body_color)
		_box(Vector3(0.5, 0.3, 0.5), Vector3(sx * 0.42, top + 0.15, cab_z + 0.15), Color(0.3, 0.25, 0.2), false)
		# зеркало
		_box(Vector3(0.12, 0.1, 0.04), Vector3(sx * (cab_size.x * 0.5 + 0.1), top + 0.8, cab_front + 0.1), grey, false)
	_box(Vector3(cab_size.x, 0.06, cab_size.z), Vector3(0, top + cab_size.y - 0.03, cab_z), body_color)
	_box(Vector3(cab_size.x, 0.6, 0.05), Vector3(0, top + 0.3, cab_back - 0.025), body_color)
	# руль
	var wheel := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.18
	cm.bottom_radius = 0.18
	cm.height = 0.03
	cm.radial_segments = 10
	wheel.mesh = cm
	wheel.material_override = _mat(Color(0.1, 0.1, 0.1))
	wheel.position = Vector3(-0.42, top + 0.62, cab_front + 0.5)
	wheel.rotation.x = 1.1
	_visual.add_child(wheel)
	# бамперы
	_box(Vector3(cab_size.x, 0.12, 0.1), Vector3(0, top - 0.1, front_end - 0.05), grey)
	_box(Vector3(body_size.x, 0.12, 0.1), Vector3(0, top - 0.1, body_size.z * 0.5 + 0.05), grey)
	# фары: всегда горят, слабо
	for sx in [-1.0, 1.0]:
		var hx: float = sx * (cab_size.x * 0.5 - 0.3)
		var lamp := _box(Vector3(0.25, 0.12, 0.05), Vector3(hx, top + 0.25, front_end - 0.02), Color(1, 0.95, 0.75), false)
		var lm := StandardMaterial3D.new()
		lm.albedo_color = Color(1, 0.95, 0.75)
		lm.emission_enabled = true
		lm.emission = Color(1, 0.9, 0.6)
		lm.emission_energy_multiplier = 1.5
		lamp.material_override = lm
		var sl := SpotLight3D.new()
		sl.shadow_enabled = false
		sl.light_energy = 1.2
		sl.spot_range = 16.0
		sl.spot_angle = 32.0
		sl.light_color = Color(1, 0.95, 0.8)
		sl.position = Vector3(hx, top + 0.25, front_end - 0.06)
		sl.visible = false
		_visual.add_child(sl)
		_headlights.append(sl)
	# сиденья (позиция игрока: голова на +1.6)
	for seat in 2:
		var s := Node3D.new()
		s.name = "SeatDriver" if seat == 0 else "SeatPassenger"
		s.position = Vector3(-0.42 if seat == 0 else 0.42, 0.0, cab_z + 0.15)
		add_child(s)
		_seats[seat] = s
		var door := Door.new()
		door.name = "DoorL" if seat == 0 else "DoorR"
		door.vehicle = self
		door.seat = seat
		door.collision_layer = Types.L_TRIGGER
		door.collision_mask = 0
		door.monitoring = false
		door.monitorable = true
		var dcs := CollisionShape3D.new()
		var dbs := BoxShape3D.new()
		dbs.size = Vector3(0.12, 1.0, cab_size.z - 0.2)
		dcs.shape = dbs
		door.add_child(dcs)
		door.position = Vector3((-1.0 if seat == 0 else 1.0) * (cab_size.x * 0.5 + 0.06), top + 0.6, cab_z)
		add_child(door)
	# --- кузов: борта толстые (WALL_T) и уходят вниз в шасси — без щелей-ловушек и туннелирования
	_bed_floor_y = top
	var wall_c := body_color.darkened(0.15)
	var sink := 0.2
	var hw := bed_size.x * 0.5
	var hl := bed_size.z * 0.5
	for side in 2:
		var sx := -1.0 if side == 0 else 1.0
		if bed_missing_wall == side:
			# обломок борта спереди — «оторвало»
			_box(Vector3(WALL_T, bed_size.y * 0.7 + sink, 0.3), Vector3(sx * (hw + WALL_T * 0.5), top + (bed_size.y * 0.7 - sink) * 0.5, bed_z - hl + 0.15), Color(0.5, 0.25, 0.1))
		else:
			_box(Vector3(WALL_T, bed_size.y + sink, bed_size.z + WALL_T * 2.0), Vector3(sx * (hw + WALL_T * 0.5), top + (bed_size.y - sink) * 0.5, bed_z), wall_c)
	_box(Vector3(bed_size.x + WALL_T * 2.0, bed_size.y + sink, WALL_T), Vector3(0, top + (bed_size.y - sink) * 0.5, bed_z - hl - WALL_T * 0.5), wall_c)
	var th := tailgate_height if tailgate_height > 0.0 else bed_size.y
	if bed_missing_wall != 2:
		_box(Vector3(bed_size.x + WALL_T * 2.0, th + sink, WALL_T), Vector3(0, top + (th - sink) * 0.5, bed_z + hl + WALL_T * 0.5), wall_c)
	if bed_roof:
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				_box(Vector3(0.06, bed_roof_height, 0.06), Vector3(sx * (bed_size.x * 0.5 - 0.03), _bed_floor_y + bed_roof_height * 0.5, bed_z + sz * (bed_size.z * 0.5 - 0.03)), grey)
		_box(Vector3(bed_size.x + 0.1, 0.05, bed_size.z + 0.1), Vector3(0, _bed_floor_y + bed_roof_height + 0.025, bed_z), body_color)
	# зона кузова: кто внутри — едет (ItemBody.in_vehicle_bed, ачивка bump_launch)
	_bed_zone = Area3D.new()
	_bed_zone.name = "BedZone"
	_bed_zone.collision_layer = 0
	_bed_zone.collision_mask = Types.L_ITEM
	_bed_zone.monitorable = false
	_bed_zone.monitoring = true
	var zcs := CollisionShape3D.new()
	var zbs := BoxShape3D.new()
	zbs.size = Vector3(bed_size.x, 1.4, bed_size.z)
	zcs.shape = zbs
	_bed_zone.add_child(zcs)
	_bed_zone.position = Vector3(0, _bed_floor_y + 0.7, bed_z)
	_bed_zone.body_entered.connect(_on_bed_entered)
	_bed_zone.body_exited.connect(_on_bed_exited)
	add_child(_bed_zone)
	# --- колёса
	for sx in [-1.0, 1.0]:
		var wf := _make_wheel(Vector3(sx * track * 0.5, wheel_y, -axle_front), true)
		var wr := _make_wheel(Vector3(sx * track * 0.5, wheel_y, axle_rear), false)
		_front_wheels.append(wf)
		_rear_wheels.append(wr)
		_wheels.append(wf)
		_wheels.append(wr)
	_build_dust()
	# --- ценник витрины
	_price_label = Label3D.new()
	_price_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_price_label.font_size = 72
	_price_label.outline_size = 12
	_price_label.pixel_size = 0.006
	_price_label.modulate = Color(1, 0.9, 0.3)
	_price_label.position = Vector3(0, top + cab_size.y + 0.9, cab_z)
	add_child(_price_label)
	_refresh_label()


## Пыль из-под задних колёс: город стоит на глине, без шлейфа езда выглядит стерильно.
func _build_dust() -> void:
	_dust = GPUParticles3D.new()
	_dust.name = "Dust"
	_dust.amount = 20
	_dust.lifetime = 1.1
	_dust.randomness = 0.7
	_dust.emitting = false
	_dust.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0.6)
	pm.spread = 35.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3(0, 0.4, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.0
	pm.scale_min = 0.35
	pm.scale_max = 1.0
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(track * 0.5, 0.05, 0.2)
	var g := Gradient.new()
	g.set_color(0, Color(0.5, 0.4, 0.3, 0.28)) # тёмная глина, слабая — на закате светлое читается белыми квадратами
	g.set_color(1, Color(0.5, 0.42, 0.34, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	_dust.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.5, 0.5)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL # освещённая пыль темнеет в тени, не светится
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	m.disable_receive_shadows = true
	qm.material = m
	_dust.draw_pass_1 = qm
	_dust.position = Vector3(0, 0.1, axle_rear + 0.4)
	add_child(_dust)


func _dust_tick(spd: float) -> void:
	if _dust == null:
		return
	var on := spd > 2.5 and global_position.y > WATER_Y + 0.5
	if on != _dust.emitting:
		_dust.emitting = on
	if on:
		_dust.amount_ratio = clampf(spd / top_speed, 0.25, 1.0)


func _make_wheel(pos: Vector3, front: bool) -> Node3D:
	var w: Node3D
	if proxy:
		w = Node3D.new()
		w.position = pos - Vector3(0, suspension_rest, 0)
	else:
		var vw := VehicleWheel3D.new()
		vw.use_as_steering = front
		vw.use_as_traction = true
		vw.wheel_radius = wheel_radius
		vw.wheel_rest_length = suspension_rest
		vw.suspension_travel = suspension_travel
		vw.suspension_stiffness = suspension_stiffness
		vw.suspension_max_force = 40000.0
		vw.damping_compression = damping_compression
		vw.damping_relaxation = damping_relaxation
		vw.wheel_friction_slip = friction_slip
		vw.wheel_roll_influence = roll_influence
		w = vw
		w.position = pos
	w.name = ("WheelF" if front else "WheelR") + ("L" if pos.x < 0 else "R")
	add_child(w)
	var tire := MeshInstance3D.new()
	tire.mesh = LowPoly.cylinder(wheel_radius, wheel_radius, wheel_width, 10)
	tire.rotation.z = PI * 0.5
	tire.material_override = _mat(Color(0.08, 0.08, 0.08))
	w.add_child(tire)
	var hub := MeshInstance3D.new()
	hub.mesh = LowPoly.cylinder(wheel_radius * 0.55, wheel_radius * 0.55, wheel_width + 0.02, 6)
	hub.rotation.z = PI * 0.5
	hub.material_override = _mat(Color(0.82, 0.8, 0.72)) # грязно-белый колпак, читается на любом кузове
	w.add_child(hub)
	return w


func _build_audio() -> void:
	_engine = AudioStreamPlayer3D.new()
	_engine.name = "Engine"
	_engine.bus = "SFX"
	_engine.max_distance = 45.0
	_engine.unit_size = 5.0
	_engine.volume_db = -6.0
	_engine.stream = _load_loop("res://audio/sfx/car_engine_loop")
	add_child(_engine)
	_music = AudioStreamPlayer.new()
	_music.name = "RockLoop"
	_music.bus = "Music"
	_music.volume_db = -8.0
	_music.stream = _load_loop("res://audio/music/car_rock_loop")
	add_child(_music)


static func _load_loop(base: String) -> AudioStream:
	for ext in ["wav", "ogg"]:
		var path := "%s.%s" % [base, ext]
		if ResourceLoader.exists(path):
			var s: AudioStream = ResourceLoader.load(path)
			if s is AudioStreamWAV:
				s = s.duplicate()
				s.loop_mode = AudioStreamWAV.LOOP_FORWARD
				s.loop_end = s.data.size() / (2 if s.format == AudioStreamWAV.FORMAT_16_BITS else 1) / (2 if s.stereo else 1)
			elif s is AudioStreamOggVorbis:
				s.loop = true
			return s
	return null


func _refresh_label() -> void:
	if _price_label == null:
		return
	_price_label.visible = display
	if display:
		_price_label.text = "$%d\n%s" % [price, display_name()]


# ------------------------------------------------------------------ кузов

func _on_bed_entered(b: Node) -> void:
	if b is ItemBody and not bed_items.has(b):
		bed_items.append(b)
		b.in_vehicle_bed = true


func _on_bed_exited(b: Node) -> void:
	if b is ItemBody:
		bed_items.erase(b)
		b.in_vehicle_bed = false


func bed_floor_world_y() -> float:
	return (global_transform * Vector3(0, _bed_floor_y, bed_z)).y


## Точка над полом кузова (для спавна/теста).
func bed_point(local_xz: Vector2, height := 0.3) -> Vector3:
	return global_transform * Vector3(local_xz.x, _bed_floor_y + height, bed_z + local_xz.y)


# ------------------------------------------------------------------ сиденья / интерактив (хост зовёт interact)

func seat_peer(seat: int) -> int:
	return driver_peer if seat == SEAT_DRIVER else passenger_peer


func seat_of(peer: int) -> int:
	if driver_peer == peer:
		return SEAT_DRIVER
	if passenger_peer == peer:
		return SEAT_PASSENGER
	return -1


func seat_for(player: Node3D) -> int:
	var lx := to_local(player.global_position).x
	if lx < 0.0:
		return SEAT_DRIVER if driver_peer == 0 else (SEAT_PASSENGER if passenger_peer == 0 else -1)
	return SEAT_PASSENGER if passenger_peer == 0 else (SEAT_DRIVER if driver_peer == 0 else -1)


func exit_position(seat: int) -> Vector3:
	var sx := -1.0 if seat == SEAT_DRIVER else 1.0
	var p := global_transform * Vector3(sx * (cab_size.x * 0.5 + 0.8), 0.15, cab_z)
	p.y = maxf(p.y, global_position.y + 0.15)
	return p


func _system() -> Node:
	if sys == null and Game.world and Game.world.has_method("system"):
		sys = Game.world.system("Vehicles")
	return sys


func interact(player: Player) -> void:
	door_interact(player, seat_for(player))


func interact_hint(player: Player) -> String:
	return door_hint(player, seat_for(player))


func door_interact(player: Player, seat: int) -> void:
	var s := _system()
	if s == null or not Net.is_host():
		return
	if player.in_vehicle == self:
		s.host_exit(player)
	elif display:
		s.host_buy(player, self)
	else:
		s.host_enter(player, self, seat)


func door_hint(player: Player, seat: int) -> String:
	if player.in_vehicle == self:
		return tr("VEH_EXIT_HINT")
	if display:
		return tr("VEH_BUY_HINT") % [display_name(), price]
	if seat == SEAT_DRIVER:
		return tr("VEH_ENTER_HINT") % display_name()
	if seat == SEAT_PASSENGER:
		return tr("VEH_PASSENGER_HINT")
	return tr("VEH_FULL")


## Смена владельца сиденья (хост напрямую, клиенты по событию veh_seat).
func set_seat(seat: int, peer: int) -> void:
	var prev := seat_peer(seat)
	if seat == SEAT_DRIVER:
		driver_peer = peer
	else:
		passenger_peer = peer
	if peer == 0 and seat == SEAT_DRIVER:
		_in_steer = 0.0
		_in_throttle = 0.0
		_in_brake = 0.0
		_in_hb = false
	_seat_grace = 0.6
	if prev != 0 and prev == Net.my_id() and prev != peer:
		_local_left(seat)
	if peer != 0 and peer == Net.my_id():
		_local_seated(seat)
	seat_changed.emit(seat, peer)


func seat_player(p: Player, seat: int) -> void:
	p.enter_vehicle(self)
	var s: Node3D = _seats[seat]
	if s:
		p.global_transform = Transform3D(global_basis.orthonormalized(), s.global_position)
		p.reset_physics_interpolation()


func release_player(p: Player, pos: Vector3) -> void:
	var yaw := global_basis.orthonormalized().get_euler().y
	p.exit_vehicle(pos)
	p.rotation = Vector3.ZERO
	if p.is_local():
		p.set("_yaw", float(p.get("_yaw")) + yaw)
	p.reset_physics_interpolation()


func _local_seated(seat: int) -> void:
	if seat == SEAT_DRIVER and _music.stream:
		AudioBus.stop_music()
		_music.play()


func _local_left(seat: int) -> void:
	if seat == SEAT_DRIVER:
		_music.stop()
		if Game.world and Game.world.has_method("_on_mode_changed"):
			Game.world._on_mode_changed(Game.world_mode, Game.world_mode)


func set_bought() -> void:
	owner_slot = true
	display = false
	npc_owned = false
	_refresh_label()


# ------------------------------------------------------------------ ввод

## Хост: применить ввод водителя.
func apply_input(steer: float, throttle: float, brake_in: float, hb: bool) -> void:
	_in_steer = clampf(steer, -1.0, 1.0)
	_in_throttle = clampf(throttle, -1.0, 1.0)
	_in_brake = clampf(brake_in, 0.0, 1.0)
	_in_hb = hb
	if sleeping and (absf(_in_throttle) > 0.05 or _in_hb):
		sleeping = false


func _local_input_tick(delta: float) -> void:
	var me := Net.my_id()
	var my_seat := seat_of(me)
	if my_seat == -1 or Game.world == null:
		return
	var p: Player = Game.world.local_player()
	if p == null or p.dead or p.in_vehicle != self:
		return
	_seat_grace -= delta
	if _seat_grace <= 0.0 and Input.is_action_just_pressed("use"):
		Net.request_action("veh_exit", {"vid": vid})
		return
	if my_seat != SEAT_DRIVER:
		return
	if Input.is_action_just_pressed("alt_use"):
		Net.request_action("veh_horn", {"vid": vid})
	var steer := Input.get_axis("move_right", "move_left")
	var throttle := Input.get_axis("move_back", "move_forward")
	var hb := Input.is_action_pressed("jump")
	var changed := absf(steer - float(_last_in[0])) > 0.02 or absf(throttle - float(_last_in[1])) > 0.02 or hb != bool(_last_in[2])
	_send_t += delta
	if changed or _send_t >= INPUT_SEND_SEC:
		_send_t = 0.0
		_last_in = [steer, throttle, hb]
		if Net.is_host():
			apply_input(steer, throttle, 0.0, hb)
		else:
			Net.request_action("drive", {"vid": vid, "steer": steer, "throttle": throttle, "brake": 0.0, "hb": hb})


# ------------------------------------------------------------------ симуляция

func _physics_process(delta: float) -> void:
	_spawn_grace = maxf(0.0, _spawn_grace - delta)
	if proxy:
		_proxy_tick(delta)
	else:
		_sim_tick(delta)
	_seats_tick()
	_local_input_tick(delta)
	_audio_tick(delta)


## Сбитые (§6.4 «машина: ragdoll»): игрок/NPC перед капотом на скорости → урон + отлёт. NPC → менты.
var _hit_cd: Dictionary = {} # instance_id → секунды до следующего удара


func _run_over_tick(fwd: Vector3, fwd_speed: float, delta: float) -> void:
	for k in _hit_cd.keys():
		_hit_cd[k] -= delta
		if _hit_cd[k] <= 0.0:
			_hit_cd.erase(k)
	var spd := absf(fwd_speed)
	if spd < 3.5:
		return
	var nose := fwd * signf(fwd_speed)
	var half_len := 2.4
	var victims: Array = []
	for pid in Net.players:
		var p = Net.players[pid]
		if is_instance_valid(p) and p.in_vehicle == null and not p.dead:
			victims.append(p)
	victims.append_array(get_tree().get_nodes_in_group("npcs"))
	for v in victims:
		if not is_instance_valid(v) or _hit_cd.has(v.get_instance_id()):
			continue
		var rel: Vector3 = v.global_position - global_position
		var along := rel.dot(nose)
		var side := (rel - nose * along)
		side.y = 0.0
		if along < 0.3 or along > half_len + 0.6 or side.length() > 1.25 or absf(rel.y) > 1.6:
			continue
		_hit_cd[v.get_instance_id()] = 1.5
		var kick := nose * (spd * 0.9 + 3.0) + Vector3.UP * (2.5 + spd * 0.25)
		AudioBus.play_at("thud_heavy", v.global_position, 2.0)
		if v is Player:
			v.velocity += kick
			v.take_damage(spd * 7.0, "car")
			if driver_peer != 0 and driver_peer != v.peer_id:
				Achievements.unlock("hit_and_run")
		elif v is Npc:
			if v.has_method("shove"):
				v.shove(kick)
			var pol = Game.world.system("Police") if Game.world else null
			if pol and driver_peer != 0:
				pol.trigger(Types.PoliceTrigger.THREAT, global_position, Game.world.player_of(driver_peer))
		Game.stat_add("run_overs")


func _sim_tick(delta: float) -> void:
	var fwd := -global_basis.z
	var fwd_speed := fwd.dot(linear_velocity)
	var parked := driver_peer == 0 and not test_drive
	var steer_lim := lerpf(max_steer, min_steer, clampf(absf(fwd_speed) / top_speed, 0.0, 1.0))
	_steer = move_toward(_steer, _in_steer * steer_lim, delta * 3.2)
	steering = _steer
	var force_per_wheel := accel * mass * 0.25
	var eng := 0.0
	var brk := 0.0
	if _in_throttle > 0.05:
		if fwd_speed < -0.6:
			brk = 1.0
		elif fwd_speed < top_speed:
			eng = _in_throttle * force_per_wheel
	elif _in_throttle < -0.05:
		if fwd_speed > 0.6:
			brk = 1.0
		elif fwd_speed > -reverse_speed:
			eng = _in_throttle * force_per_wheel * 0.7
	brk = maxf(brk, _in_brake)
	if parked:
		brk = maxf(brk, 0.35)
	if _in_hb:
		brk = 1.0
		eng = 0.0
	# VehicleBody3D толкает вдоль +Z при положительной силе; наш нос — -Z
	engine_force = -eng
	# тормоз в VehicleBody3D — импульс за шаг: decel * m / 4 колеса * dt
	brake = brk * brake_decel * mass * 0.25 * delta
	for w in _rear_wheels:
		w.wheel_friction_slip = friction_slip * (0.35 if _in_hb else 1.0)
	# лёгкая аэродинамика: держит топ-скорость
	if absf(fwd_speed) > top_speed * 1.05:
		apply_central_force(-fwd * signf(fwd_speed) * mass * 2.0)
	_run_over_tick(fwd, fwd_speed, delta)
	# кочка → кузов взлетел (скачок vy за ~0.33 с)
	var vy := linear_velocity.y
	_vy_hist.append(vy)
	if _vy_hist.size() > 10:
		_vy_hist.pop_front()
	_prune_t -= delta
	if _prune_t <= 0.0:
		_prune_t = 1.0
		bed_items = bed_items.filter(func(b): return is_instance_valid(b))
	if _spawn_grace <= 0.0 and not parked and not bed_items.is_empty():
		var mn := vy
		for h in _vy_hist:
			mn = minf(mn, h)
		if vy - mn > BUMP_SPIKE:
			_vy_hist.clear()
			_on_bump()
	# перевернулась с водителем → через 4 с ставим на колёса
	if global_basis.y.y < -0.2:
		_flip_t += delta
		if _flip_t > FLIP_SEC and driver_peer != 0:
			_flip_t = 0.0
			right_up(tr("VEH_FLIPPED"))
	else:
		_flip_t = 0.0
	# утонула / провалилась → на дорогу
	if global_position.y < WATER_Y or global_position.y < -40.0:
		var s := _system()
		var pos: Vector3 = s.road_point_near(global_position) if s and s.has_method("road_point_near") else Vector3(0, 0.5, 6)
		global_position = pos + Vector3(0, 1.0, 0)
		right_up(tr("VEH_SOAKED"))


func _on_bump() -> void:
	Achievements.unlock("bump_launch")
	Game.stat_add("bump_launches")
	if Net.is_host():
		Net.broadcast_event("veh_bump", {"vid": vid, "pos": global_position})


## Поставить на колёса на месте (хост).
func right_up(msg: String = "") -> void:
	var f := -global_basis.z
	f.y = 0.0
	if f.length() < 0.1:
		f = Vector3.FORWARD
	global_transform = Transform3D(Basis.looking_at(f.normalized(), Vector3.UP), global_position + Vector3(0, 0.6, 0))
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_vy_hist.clear()
	_spawn_grace = 1.0
	_force_state = true
	reset_physics_interpolation()
	if Net.is_host():
		Net.broadcast_event("veh_flip", {"vid": vid, "pos": global_position})
		if msg != "" and driver_peer != 0:
			var p: Player = Net.players.get(driver_peer)
			if p:
				p.say(msg)


func _seats_tick() -> void:
	for seat in 2:
		var peer := seat_peer(seat)
		if peer == 0:
			continue
		var p: Player = Net.players.get(peer)
		if p == null or not is_instance_valid(p):
			if Net.is_host() and _system():
				sys.host_vacate(self, seat)
			continue
		if p.in_vehicle != self:
			continue
		if Net.is_host() and (p.dead or p.in_custody):
			if _system():
				sys.host_exit(p)
			continue
		var s: Node3D = _seats[seat]
		p.global_transform = Transform3D(global_basis.orthonormalized(), s.global_position)
		p.velocity = cur_velocity()


func _process(_delta: float) -> void:
	# локальный сидящий: мышь крутит голову (Player сам это делает только в _local_move)
	var me := Net.my_id()
	var seat := seat_of(me)
	if seat == -1:
		return
	var p: Player = Net.players.get(me)
	if p and is_instance_valid(p) and p.in_vehicle == self:
		p.head.rotation.y = float(p.get("_yaw"))
		p.camera.rotation.x = float(p.get("_pitch"))


func cur_velocity() -> Vector3:
	return _target_lv if proxy else linear_velocity


# ------------------------------------------------------------------ сеть

func wants_state() -> bool:
	if _force_state:
		return true
	return not sleeping


func state_data() -> Dictionary:
	_force_state = false
	return {"vid": vid, "xf": global_transform, "lv": linear_velocity, "av": angular_velocity, "st": _steer}


func apply_state(xf: Transform3D, lv: Vector3, av: Vector3, st: float) -> void:
	_target_xf = xf
	_target_lv = lv
	_target_av = av
	_steer = st
	if not _has_target or global_position.distance_to(xf.origin) > 3.0:
		global_transform = xf
		_has_target = true
		reset_physics_interpolation()


func _proxy_tick(delta: float) -> void:
	if not _has_target:
		return
	_target_xf.origin += _target_lv * delta
	global_position = global_position.lerp(_target_xf.origin, minf(1.0, delta * 10.0))
	global_basis = Basis(global_basis.get_rotation_quaternion().slerp(_target_xf.basis.get_rotation_quaternion(), minf(1.0, delta * 10.0)))
	_wheel_spin += (-global_basis.z.dot(_target_lv)) / maxf(wheel_radius, 0.05) * delta
	for w in _front_wheels:
		w.rotation = Vector3(_wheel_spin, _steer, 0)
	for w in _rear_wheels:
		w.rotation = Vector3(_wheel_spin, 0, 0)


# ------------------------------------------------------------------ звук

func _audio_tick(delta: float) -> void:
	var v := cur_velocity()
	var spd := v.length()
	_dust_tick(spd)
	# фары горят, пока кто-то за рулём (Mobile-рендер: лимит источников на меш)
	var occupied := driver_peer != 0 or test_drive
	for hl in _headlights:
		hl.visible = occupied
	if _engine.stream:
		var want := occupied
		if want and not _engine.playing:
			_engine.play()
		elif not want and _engine.playing:
			_engine.stop()
		if _engine.playing:
			_engine.pitch_scale = 0.75 + clampf(spd / top_speed, 0.0, 1.2) * 0.9 + absf(_in_throttle) * 0.1
	_skid_cd -= delta
	if _skid_cd <= 0.0 and spd > 3.0:
		var lat := absf(global_basis.x.dot(v))
		if lat > 3.0 or (not proxy and _any_wheel_skid()):
			AudioBus.play_at("tire_skid", global_position, -4.0, 0.2)
			_skid_cd = 0.45


func _any_wheel_skid() -> bool:
	for w in _wheels:
		if w is VehicleWheel3D and w.is_in_contact() and w.get_skidinfo() < 0.45:
			return true
	return false
