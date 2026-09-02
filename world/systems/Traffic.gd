class_name Traffic
extends Node3D
## Косметический трафик по `Roads.segments`. Не Vehicles / не физика — только Mesh + tween-движок.
## 2–4 машины, объезд реальных Vehicle, без теней/Omni. Хост и клиенты крутят локально одинаково.

const MAX_CARS := 4
const SPEED := 11.5
const LANE := 2.15
const AVOID_R := 9.0
const COLORS: Array[Color] = [
	Color(0.72, 0.22, 0.18), Color(0.18, 0.32, 0.62), Color(0.88, 0.82, 0.55),
	Color(0.22, 0.22, 0.24), Color(0.35, 0.55, 0.38), Color(0.55, 0.35, 0.55),
]

var _roads: Roads
var _cars: Array = [] # Dictionary


func system_name() -> String:
	return "Traffic"


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if Game.world == null or Game.world.city == null:
		return
	_roads = Game.world.city.roads() as Roads
	if _roads == null or _roads.segments.is_empty():
		return
	var n := mini(MAX_CARS, maxi(2, _roads.segments.size() / 3))
	for i in n:
		_spawn_car(i)
	if OS.is_debug_build():
		print("[Traffic] cars=%d segs=%d" % [_cars.size(), _roads.segments.size()])


func _process(delta: float) -> void:
	if _roads == null:
		return
	for c in _cars:
		_tick_car(c, delta)


func _spawn_car(i: int) -> void:
	var root := Node3D.new()
	root.name = "TrafficCar%d" % i
	add_child(root)
	_build_mesh(root, COLORS[i % COLORS.size()])
	var seg := i % _roads.segments.size()
	var lane_side := 1.0 if i % 2 == 0 else -1.0
	var d := _seg_data(seg)
	var car := {
		"root": root,
		"seg": seg,
		"t": fposmod(0.12 * float(i), 1.0),
		"dir": 1.0 if i % 2 == 0 else -1.0,
		"lane": lane_side,
		"paused": 0.0,
		"len": d.len,
		"a": d.a,
		"b": d.b,
		"along": d.along,
		"normal": d.normal,
	}
	_place(car)
	_cars.append(car)


func _seg_data(i: int) -> Dictionary:
	var s: Vector4 = _roads.segments[i]
	var a := Vector3(s.x, 0.0, s.y)
	var b := Vector3(s.z, 0.0, s.w)
	var along := b - a
	var length := along.length()
	if length < 0.01:
		return {"a": a, "b": b, "along": Vector3.FORWARD, "normal": Vector3.RIGHT, "len": 1.0}
	along /= length
	return {"a": a, "b": b, "along": along, "normal": Vector3(-along.z, 0, along.x), "len": length}


func _tick_car(c: Dictionary, delta: float) -> void:
	var root: Node3D = c["root"]
	if c["paused"] > 0.0:
		c["paused"] = float(c["paused"]) - delta
		return
	var pos: Vector3 = root.global_position
	if _near_real_vehicle(pos):
		c["paused"] = 0.6
		return
	var step := (SPEED * delta) / maxf(float(c["len"]), 1.0)
	c["t"] = float(c["t"]) + step * float(c["dir"])
	if float(c["t"]) > 1.0 or float(c["t"]) < 0.0:
		_reroute(c)
	_place(c)


func _reroute(c: Dictionary) -> void:
	var next := int(c["seg"])
	# предпочитаем соседний сегмент с общей точкой
	var cur_a: Vector3 = c["a"]
	var cur_b: Vector3 = c["b"]
	var end: Vector3 = cur_b if float(c["dir"]) > 0.0 else cur_a
	var candidates: Array[int] = []
	for i in _roads.segments.size():
		if i == next:
			continue
		var d := _seg_data(i)
		if d.a.distance_to(end) < 6.0 or d.b.distance_to(end) < 6.0:
			candidates.append(i)
	if candidates.is_empty():
		c["dir"] = -float(c["dir"])
		c["t"] = clampf(float(c["t"]), 0.0, 1.0)
		return
	next = candidates[hash(str(c["root"].name) + str(Time.get_ticks_msec())) % candidates.size()]
	var d2 := _seg_data(next)
	c["seg"] = next
	c["a"] = d2.a
	c["b"] = d2.b
	c["along"] = d2.along
	c["normal"] = d2.normal
	c["len"] = d2.len
	# выбрать направление от точки стыка
	if d2.a.distance_to(end) <= d2.b.distance_to(end):
		c["dir"] = 1.0
		c["t"] = 0.02
	else:
		c["dir"] = -1.0
		c["t"] = 0.98


func _place(c: Dictionary) -> void:
	var t := clampf(float(c["t"]), 0.0, 1.0)
	var a: Vector3 = c["a"]
	var b: Vector3 = c["b"]
	var along: Vector3 = c["along"]
	var normal: Vector3 = c["normal"]
	var dir_sign := float(c["dir"])
	var root: Node3D = c["root"]
	var y := 0.12
	if _roads:
		var top := _roads.road_top_at(a.lerp(b, t))
		if top >= 0.0:
			y = top + 0.02
	var p := a.lerp(b, t) + normal * (LANE * float(c["lane"]))
	p.y = y
	root.global_position = p
	var look := along * dir_sign
	if look.length_squared() > 0.01:
		root.look_at(p + look, Vector3.UP)


func _near_real_vehicle(pos: Vector3) -> bool:
	var vs = Game.world.system("Vehicles") if Game.world else null
	if vs and vs.get("vehicles") is Dictionary:
		for v in vs.vehicles.values():
			if v is Node3D and (v as Node3D).global_position.distance_to(pos) < AVOID_R:
				return true
	return false


func _build_mesh(root: Node3D, col: Color) -> void:
	var body := _box(root, Vector3(1.85, 0.62, 4.0), Vector3(0, 0.62, 0), col)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cabin := _box(root, Vector3(1.65, 0.5, 1.9), Vector3(0, 1.15, -0.15), col.darkened(0.12))
	cabin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var glass_c := Color(0.35, 0.45, 0.55, 0.55)
	var glass := _box(root, Vector3(1.68, 0.38, 1.92), Vector3(0, 1.18, -0.15), glass_c)
	var gm := glass.material_override as StandardMaterial3D
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tire_m := StandardMaterial3D.new()
	tire_m.albedo_color = Color(0.08, 0.08, 0.08)
	tire_m.roughness = 1.0
	for x in [-0.9, 0.9]:
		for z in [-1.25, 1.25]:
			var w := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.32
			cm.bottom_radius = 0.32
			cm.height = 0.24
			cm.radial_segments = 8
			w.mesh = cm
			w.material_override = tire_m
			w.position = Vector3(x, 0.32, z)
			w.rotation.z = PI * 0.5
			w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(w)


func _box(parent: Node3D, size: Vector3, pos: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.85
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi
