class_name Props
extends Node3D
## Наполнение города (§12): фонари, пальмы/кактусы, столбы с проводами, хлам как на кей-арте.
## Данные — экспорт в City.tscn + дефолты в коде; геометрия из LowPoly в _ready().

@export var lampposts: PackedVector3Array = PackedVector3Array() ## (x, z, lit 0/1)
@export var trees: PackedVector3Array = PackedVector3Array() ## (x, z, масштаб) — 60% пальма / 40% кактус-куст
@export var dumpsters: PackedVector3Array = PackedVector3Array() ## (x, z, yaw°)
@export var billboards: PackedVector3Array = PackedVector3Array() ## (x, z, yaw°)
@export var billboard_texts: PackedStringArray = PackedStringArray()
@export var junk_cars: PackedVector4Array = PackedVector4Array() ## (x, z, yaw°, индекс цвета)

## Геройский трейлер-парк (x, z, масштаб). Не дублирует `trees` из City.tscn.
@export var park_palms: PackedVector3Array = PackedVector3Array([
	Vector3(-16.0, -8.0, 1.18),
	Vector3(-18.5, -22.0, 1.06),
	Vector3(15.2, -26.0, 1.14),
	Vector3(-11.5, 10.5, 0.98),
	Vector3(-20.0, -48.0, 1.22),
	Vector3(24.0, -48.0, 1.12),
])
@export var park_cacti: PackedVector3Array = PackedVector3Array([
	Vector3(-22.0, -12.0, 1.05),
	Vector3(20.5, 10.0, 0.88),
	Vector3(-24.0, 8.5, 0.92),
])
@export var flamingos: PackedVector3Array = PackedVector3Array([
	Vector3(-10.4, -3.0, 12.0),
	Vector3(-10.0, -7.6, 55.0),
	Vector3(-8.4, -15.6, -22.0),
	Vector3(7.8, -7.4, 42.0),
	Vector3(-11.4, -5.4, -8.0),
	Vector3(8.6, -17.2, 65.0),
])
@export var cinder_blocks: PackedVector3Array = PackedVector3Array([
	Vector3(-6.2, -6.8, -25.0),
	Vector3(6.8, -18.2, 8.0),
	Vector3(8.4, -10.2, 55.0),
])
@export var edge_trees: PackedVector3Array = PackedVector3Array([
	Vector3(42.0, -82.0, 1.15),
	Vector3(-42.0, -82.0, 1.05),
	Vector3(25.0, 176.0, 1.2),
	Vector3(-32.0, 174.0, 0.95),
])

const CAR_COLORS := [
	Color(0.6, 0.55, 0.2), Color(0.3, 0.5, 0.6), Color(0.55, 0.3, 0.15), Color(0.6, 0.2, 0.5), Color(0.85, 0.75, 0.2),
]
const FROND_TOP := Color(0.306, 0.545, 0.227) ## #4e8b3a
const FROND_UNDER := Color(0.184, 0.353, 0.149) ## #2f5a26
const PALM_TRUNK := Color(0.62, 0.5, 0.36)
const SAGE := Color(0.42, 0.48, 0.36)
const TEX_RUST := "res://assets/textures/tex_rust_teal.png"
const TEX_PLANKS := "res://assets/textures/tex_planks.png"
const TEX_CARD := "res://assets/textures/tex_cardboard.png"
const TEX_AD_CASINO := "res://assets/textures/ad_casino.png"
const TEX_AD_CAR := "res://assets/textures/ad_carmarket.png"
const TEX_CONTAINER := "res://assets/textures/tex_container.png"
const MESH_CAP := 960

const _HUBS: Array[Vector2] = [
	Vector2(0, -120), Vector2(110, -120), Vector2(-110, -120),
	Vector2(120, -8), Vector2(-120, -8), Vector2(-60, 78), Vector2(110, 78), Vector2(-120, 78),
]
const _VROADS: Array[Vector4] = [
	Vector4(-165, -60, -165, 110), Vector4(165, -60, 165, 110), Vector4(0, 45, 0, 135),
	Vector4(-75, -60, -75, 45), Vector4(75, -60, 75, 45), Vector4(0, -100, 0, -60),
	Vector4(120, -100, 120, -60), Vector4(-110, -100, -110, -60), Vector4(110, 45, 110, 64),
	Vector4(-120, 45, -120, 64),
]

var _mats: Dictionary = {}
var _light_count := 0
var _mesh_count := 0


func _ready() -> void:
	for i in lampposts.size():
		_lamppost(i, lampposts[i])
	for i in trees.size():
		_tree(i, trees[i])
	for i in dumpsters.size():
		_dumpster(i, dumpsters[i])
	for i in mini(billboards.size(), billboard_texts.size()):
		_billboard(i, billboards[i], billboard_texts[i])
	for i in junk_cars.size():
		_junk_car(i, junk_cars[i])
	for i in park_palms.size():
		var d: Vector3 = park_palms[i]
		var lean := 16.0 + float((i * 13) % 11)
		if i % 2 == 1:
			lean = -lean
		_palm(100 + i, Vector3(d.x, 0.0, d.y), d.z if d.z > 0.1 else 1.0, lean)
	for i in park_cacti.size():
		var d: Vector3 = park_cacti[i]
		_cactus(100 + i, Vector3(d.x, 0.0, d.y), d.z if d.z > 0.1 else 1.0)
	for i in flamingos.size():
		var d: Vector3 = flamingos[i]
		_flamingo(i, Vector3(d.x, 0.0, d.y), d.z)
	_dress_park()
	_build_power_grid()
	_build_wall_lamps()
	_dress_facades()
	_dress_plains()
	call_deferred("_port_heavy_maybe")
	if OS.is_debug_build():
		print("[Props] meshes=%d lights=%d nodes=%d" % [_mesh_count, _light_count, get_child_count()])


func light_count() -> int:
	return _light_count


func _mat(c: Color, em := Color(0, 0, 0, 0), em_e := 1.0, tex := "") -> StandardMaterial3D:
	var key := "%s|%s|%.2f|%s" % [c.to_html(), em.to_html(), em_e, tex]
	if _mats.has(key):
		return _mats[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	if em.a > 0.0:
		m.emission_enabled = true
		m.emission = em
		m.emission_energy_multiplier = em_e
	if tex != "":
		var t := load(tex) as Texture2D
		if t:
			m.albedo_texture = t
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_scale = Vector3.ONE / 2.0
	_mats[key] = m
	return m


func _body(name: String, pos: Vector3, yaw_deg := 0.0) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.name = name
	b.collision_layer = Types.L_WORLD
	b.collision_mask = 0
	b.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), pos)
	add_child(b)
	return b


func _group(name: String, pos: Vector3, yaw_deg := 0.0) -> Node3D:
	var n := Node3D.new()
	n.name = name
	n.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), pos)
	add_child(n)
	return n


func _mi(parent: Node3D, mesh: Mesh, pos: Vector3, m: Material, basis := Basis()) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.transform = Transform3D(basis, pos)
	parent.add_child(mi)
	_mesh_count += 1
	return mi


func _box_col(parent: Node3D, pos: Vector3, size: Vector3, basis := Basis()) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = Transform3D(basis, pos)
	parent.add_child(cs)


func _cyl_col(parent: Node3D, pos: Vector3, r: float, h: float, basis := Basis()) -> void:
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = r
	sh.height = h
	cs.shape = sh
	cs.transform = Transform3D(basis, pos)
	parent.add_child(cs)


func _box(parent: Node3D, pos: Vector3, size: Vector3, m: Material, collide := false, basis := Basis()) -> void:
	var smallest := minf(size.x, minf(size.y, size.z))
	var mesh: Mesh
	if smallest < 0.07:
		var bm := BoxMesh.new()
		bm.size = size
		mesh = bm
	else:
		mesh = LowPoly.chamfer_box(size, minf(0.05, smallest * 0.18))
	_mi(parent, mesh, pos, m, basis)
	if collide:
		_box_col(parent, pos, size, basis)


func _cyl(parent: Node3D, pos: Vector3, r: float, h: float, m: Material, collide := false, basis := Basis(), rt := -1.0) -> void:
	var top := r if rt < 0.0 else rt
	_mi(parent, LowPoly.cylinder(top, r, h, 8), pos, m, basis)
	if collide:
		_cyl_col(parent, pos, maxf(r, top), h, basis)


func _sphere(parent: Node3D, pos: Vector3, r: float, m: Material) -> void:
	_mi(parent, LowPoly.sphere(r, 8, 4), pos, m)


func _align_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var x := y.cross(Vector3.UP)
	if x.length_squared() < 0.0001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	return Basis(x, y, x.cross(y).normalized())


func _on_road(x: float, z: float, pad := 1.2) -> bool:
	var hw := 5.6 + pad
	if absf(x) <= 165.0 + hw:
		if absf(z + 60.0) <= hw or absf(z - 45.0) <= hw or absf(z - 110.0) <= hw:
			return true
	for s in _VROADS:
		var x1: float = s.x
		var z1: float = s.y
		var z2: float = s.w
		if absf(x - x1) <= hw and z >= minf(z1, z2) - hw and z <= maxf(z1, z2) + hw:
			return true
	return false


func _on_door_path(x: float, z: float) -> bool:
	return x > 0.5 and x < 4.8 and z > -12.4 and z < 3.2


func _inside_hub(x: float, z: float) -> bool:
	var p := Vector2(x, z)
	for h in _HUBS:
		if p.distance_to(h) < 35.0:
			return true
	return false


func _blocked(x: float, z: float, hubs := false) -> bool:
	if _on_road(x, z) or _on_door_path(x, z):
		return true
	return hubs and _inside_hub(x, z)


func _lamppost(i: int, d: Vector3) -> void:
	var b := _body("Lamp%d" % i, Vector3(d.x, 0, d.y))
	var metal := _mat(Color(0.2, 0.22, 0.26))
	_cyl(b, Vector3(0, 2.5, 0), 0.09, 5.0, metal, true)
	_box(b, Vector3(0.6, 5.0, 0), Vector3(1.3, 0.1, 0.1), metal)
	_box(b, Vector3(1.15, 4.92, 0), Vector3(0.6, 0.22, 0.32), _mat(Color(1, 0.95, 0.75), Color(1, 0.9, 0.6), 2.5))
	if d.z > 0.5:
		var l := OmniLight3D.new()
		l.light_color = Color(1, 0.9, 0.7)
		l.light_energy = 1.1
		l.omni_range = 13.0
		l.omni_attenuation = 1.2
		l.shadow_enabled = false
		l.position = Vector3(1.15, 4.6, 0)
		b.add_child(l)
		_light_count += 1


func _tree(i: int, d: Vector3) -> void:
	var s := d.z if d.z > 0.1 else 1.0
	var seed_v := int(round(absf(d.z) * 10.0)) + i * 3
	var kind := seed_v % 5
	var pos := Vector3(d.x, 0.0, d.y)
	var from_park := Vector2(d.x, d.y + 14.0).length()
	## Дальние «ёлки» с дешёвым 1-сегментом читаются как пихты — вдали только сагуаро.
	if from_park > 80.0:
		_cactus(i, pos, s, false)
		return
	if kind < 3:
		var lean := float((seed_v % 17) - 8) * 1.15
		_palm(i, pos, s, lean, false)
	else:
		_cactus(i, pos, s, false)


func _palm(i: int, pos: Vector3, s: float, lean_deg: float, fancy := false) -> void:
	var b := _body("Palm%d" % i, pos, float(i * 37 % 360))
	b.rotate_object_local(Vector3.FORWARD, deg_to_rad(lean_deg))
	var wood := _mat(PALM_TRUNK, Color(0, 0, 0, 0), 1.0, TEX_PLANKS)
	var trunk_h := 4.2 * s
	if fancy or i >= 100:
		fancy = true
		var rings: Array[Vector3] = [
			Vector3(0.28 * s, 0.22 * s, trunk_h * 0.30),
			Vector3(0.20 * s, 0.15 * s, trunk_h * 0.34),
			Vector3(0.14 * s, 0.09 * s, trunk_h * 0.36),
		]
		var y_acc := 0.0
		for ring in rings:
			var rb: float = ring.x
			var rt: float = ring.y
			var rh: float = ring.z
			_cyl(b, Vector3(0, y_acc + rh * 0.5, 0), rb, rh, wood, false, Basis(), rt)
			y_acc += rh
	else:
		_cyl(b, Vector3(0, trunk_h * 0.5, 0), 0.24 * s, trunk_h, wood, false, Basis(), 0.10 * s)
	_cyl_col(b, Vector3(0, trunk_h * 0.5, 0), 0.28 * s, trunk_h)
	var top_m := _mat(FROND_TOP)
	var under_m := _mat(FROND_UNDER)
	var n_fronds := 6
	var crown := Vector3(0.0, trunk_h - 0.02 * s, 0.0)
	for f in n_fronds:
		var yaw := float(f) * TAU / float(n_fronds) + float(i) * 0.11 + float(f) * 0.04
		_palm_frond(b, crown, yaw, s, 2, top_m, under_m)
	if fancy:
		var nut := _mat(Color(0.42, 0.28, 0.14))
		_sphere(b, crown + Vector3(0.12 * s, -0.20 * s, 0.06 * s), 0.09 * s, nut)
		_sphere(b, crown + Vector3(-0.10 * s, -0.18 * s, 0.10 * s), 0.08 * s, nut)
		_sphere(b, crown + Vector3(0.02 * s, -0.22 * s, -0.12 * s), 0.075 * s, nut)


func _palm_frond(parent: Node3D, crown: Vector3, yaw: float, s: float, segs: int, top_m: Material, under_m: Material) -> void:
	## Ленты: почти горизонтально у кроны, кончик ~−45°. Никаких конусов.
	var pitches: Array[float]
	var lengths: Array[float]
	var widths: Array[float]
	pitches = [6.0, 52.0]
	lengths = [0.68 * s, 0.95 * s]
	widths = [0.26 * s, 0.12 * s]
	var cursor := crown + Vector3(sin(yaw), 0.0, cos(yaw)) * (0.16 * s)
	var n := mini(segs, pitches.size())
	for si in n:
		var pitch := deg_to_rad(pitches[si])
		var z_axis := Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch))
		if z_axis.length_squared() < 0.0001:
			z_axis = Vector3.DOWN
		z_axis = z_axis.normalized()
		var x_axis := Vector3.UP.cross(z_axis)
		if x_axis.length_squared() < 0.0001:
			x_axis = Vector3.RIGHT
		x_axis = x_axis.normalized()
		var basis := Basis(x_axis, z_axis.cross(x_axis), z_axis)
		var slen: float = lengths[si]
		var mid: Vector3 = cursor + z_axis * (slen * 0.5)
		var mat := top_m if si == 0 else under_m
		_box(parent, mid, Vector3(widths[si], 0.045 * s, slen), mat, false, basis)
		cursor = cursor + z_axis * slen


func _cactus(i: int, pos: Vector3, s: float, detail := false) -> void:
	var b := _body("Cactus%d" % i, pos, float(i * 51 % 360))
	var sage := _mat(SAGE)
	var rib_m := _mat(Color(0.36, 0.42, 0.30))
	var h := 2.05 * s
	var r := 0.22 * s
	_cyl(b, Vector3(0, h * 0.5, 0), r, h, sage, true, Basis(), r * 0.90)
	_mi(b, LowPoly.sphere(r * 0.90, 6, 3, true), Vector3(0, h, 0), sage)
	if detail or i >= 100:
		for k in 2:
			var ang := float(k) * PI + float(i) * 0.15
			var rx := cos(ang) * r * 0.84
			var rz := sin(ang) * r * 0.84
			_box(b, Vector3(rx, h * 0.46, rz), Vector3(0.03 * s, h * 0.72, 0.035 * s), rib_m)
		var stub2 := Basis(Vector3.RIGHT, deg_to_rad(86))
		_cyl(b, Vector3(0.0, 1.15 * s, -0.26 * s), 0.07 * s, 0.32 * s, sage, false, stub2, 0.06 * s)
		_cyl(b, Vector3(0.0, 1.42 * s, -0.38 * s), 0.065 * s, 0.44 * s, sage, false, Basis(), 0.055 * s)
		_mi(b, LowPoly.sphere(0.06 * s, 6, 3, true), Vector3(0.0, 1.64 * s, -0.38 * s), sage)
	var stub := Basis(Vector3.FORWARD, deg_to_rad(-86))
	_cyl(b, Vector3(0.30 * s, 0.95 * s, 0), 0.08 * s, 0.36 * s, sage, false, stub, 0.07 * s)
	_cyl(b, Vector3(0.44 * s, 1.28 * s, 0), 0.075 * s, 0.56 * s, sage, false, Basis(), 0.065 * s)
	_mi(b, LowPoly.sphere(0.07 * s, 6, 3, true), Vector3(0.44 * s, 1.56 * s, 0), sage)


func _dumpster(i: int, d: Vector3) -> void:
	var b := _body("Dumpster%d" % i, Vector3(d.x, 0, d.y), d.z)
	var col := Color(0.2, 0.5, 0.3) if i % 2 == 0 else Color(0.2, 0.35, 0.6)
	_box(b, Vector3(0, 0.65, 0), Vector3(1.9, 1.3, 1.0), _mat(col), true)
	_box(b, Vector3(0, 1.37, -0.08), Vector3(1.9, 0.08, 1.05), _mat(col.darkened(0.3)), false, Basis(Vector3.RIGHT, deg_to_rad(-12)))
	var wheels: Array[float] = [-0.7, 0.7]
	for wx in wheels:
		_cyl(b, Vector3(wx, 0.08, 0.45), 0.08, 0.1, _mat(Color(0.05, 0.05, 0.05)))


func _billboard(i: int, d: Vector3, text: String) -> void:
	var b := _body("Billboard%d" % i, Vector3(d.x, 0, d.y), d.z)
	var metal := _mat(Color(0.35, 0.36, 0.4))
	var posts: Array[float] = [-3.0, 3.0]
	for px in posts:
		_cyl(b, Vector3(px, 2.5, 0), 0.16, 5.0, metal, true)
	_box(b, Vector3(0, 6.8, -0.12), Vector3(8.6, 3.8, 0.2), _mat(Color(0.95, 0.95, 0.9)))
	var face: Array[Color] = [Color(0.95, 0.85, 0.2), Color(0.9, 0.3, 0.5), Color(0.3, 0.8, 0.9), Color(0.6, 0.9, 0.3), Color(0.95, 0.5, 0.2)]
	_box(b, Vector3(0, 6.8, 0.0), Vector3(8.2, 3.4, 0.05), _mat(face[i % 5]))
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 60
	lbl.outline_size = 8
	lbl.pixel_size = 0.012
	lbl.width = 640.0
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.modulate = Color(0.08, 0.08, 0.1)
	lbl.outline_modulate = Color(1, 1, 1, 0.6)
	lbl.position = Vector3(0, 6.8, 0.04)
	b.add_child(lbl)


func _junk_car(i: int, d: Vector4) -> void:
	var b := _body("JunkCar%d" % i, Vector3(d.x, 0, d.y), d.z)
	b.rotate_object_local(Vector3.RIGHT, deg_to_rad(6.0))
	var tint: Color = CAR_COLORS[int(d.w) % CAR_COLORS.size()].lightened(0.25)
	var body_mat := _mat(tint, Color(0, 0, 0, 0), 1.0, TEX_RUST)
	_box(b, Vector3(0, 0.82, 0), Vector3(3.9, 0.8, 1.8), body_mat)
	_box(b, Vector3(-0.3, 1.52, 0), Vector3(2.0, 0.65, 1.6), _mat(Color(0.22, 0.2, 0.18), Color(0, 0, 0, 0), 1.0, TEX_RUST))
	_box_col(b, Vector3(0, 0.95, 0), Vector3(3.9, 1.5, 1.8))
	var tire := _mat(Color(0.07, 0.07, 0.08))
	var wheel_basis := Basis(Vector3.BACK, deg_to_rad(90))
	var wxs: Array[float] = [-1.3, 1.3]
	var wzs: Array[float] = [-0.95, 0.95]
	var skip_x := 1.3
	var skip_z := 0.95
	for wx in wxs:
		for wz in wzs:
			if is_equal_approx(wx, skip_x) and is_equal_approx(wz, skip_z):
				continue
			_cyl(b, Vector3(wx, 0.35, wz), 0.35, 0.28, tire, false, wheel_basis)


func _flamingo(i: int, pos: Vector3, yaw: float) -> void:
	var n := _group("Flamingo%d" % i, pos, yaw)
	var pink := _mat(Color(0.96, 0.22, 0.58))
	var black := _mat(Color(0.08, 0.07, 0.07))
	var stick := _mat(Color(0.16, 0.12, 0.1))
	var feeding := i == 1
	## Пластиковая газонная птица: коробчатое тело на тонких ногах, низ y=0, рост ≈ 0.85.
	_box(n, Vector3(0.0, 0.54, 0.02), Vector3(0.16, 0.16, 0.32), pink)
	_box(n, Vector3(0.0, 0.56, -0.14), Vector3(0.10, 0.10, 0.10), pink)
	if feeding:
		## S-шея: сначала вверх-вперёд, потом вниз к земле — птица стоит.
		var n1 := Basis(Vector3.RIGHT, deg_to_rad(-16))
		_cyl(n, Vector3(0.0, 0.62, 0.18), 0.018, 0.16, pink, false, n1)
		var n2 := Basis(Vector3.RIGHT, deg_to_rad(48))
		_cyl(n, Vector3(0.0, 0.54, 0.32), 0.016, 0.16, pink, false, n2)
		_box(n, Vector3(0.0, 0.44, 0.42), Vector3(0.07, 0.055, 0.08), pink)
		_box(n, Vector3(0.0, 0.42, 0.48), Vector3(0.022, 0.016, 0.055), black)
		_box(n, Vector3(0.0, 0.40, 0.53), Vector3(0.018, 0.012, 0.04), black, false, Basis(Vector3.RIGHT, deg_to_rad(16)))
	else:
		var n1 := Basis(Vector3.RIGHT, deg_to_rad(-20))
		_cyl(n, Vector3(0.0, 0.66, 0.12), 0.018, 0.16, pink, false, n1)
		var n2 := Basis(Vector3.RIGHT, deg_to_rad(-50))
		_cyl(n, Vector3(0.0, 0.76, 0.22), 0.016, 0.16, pink, false, n2)
		_box(n, Vector3(0.0, 0.80, 0.30), Vector3(0.07, 0.055, 0.08), pink)
		_box(n, Vector3(0.0, 0.80, 0.36), Vector3(0.022, 0.016, 0.055), black)
		_box(n, Vector3(0.0, 0.78, 0.41), Vector3(0.018, 0.012, 0.04), black, false, Basis(Vector3.RIGHT, deg_to_rad(26)))
	_cyl(n, Vector3(-0.035, 0.19, 0.04), 0.015, 0.38, stick)
	_cyl(n, Vector3(0.040, 0.19, -0.02), 0.015, 0.38, stick)


func _cinder(i: int, pos: Vector3, yaw: float) -> void:
	var n := _group("Cinder%d" % i, pos, yaw)
	_box(n, Vector3(0, 0.1, 0), Vector3(0.44, 0.2, 0.22), _mat(Color(0.56, 0.55, 0.52)))
	_box(n, Vector3(-0.1, 0.12, 0), Vector3(0.11, 0.16, 0.14), _mat(Color(0.3, 0.3, 0.29)))


func _tire(parent: Node3D, pos: Vector3, basis: Basis, r := 0.38) -> void:
	_cyl(parent, pos, r, 0.16, _mat(Color(0.08, 0.08, 0.09)), false, basis)


func _tire_pile(name: String, pos: Vector3, yaw: float, collide := true) -> void:
	var b := _body(name, pos, yaw) if collide else _group(name, pos, yaw)
	var flat := Basis()
	_tire(b, Vector3(0, 0.08, 0), flat, 0.4)
	_tire(b, Vector3(0.04, 0.26, 0.03), Basis(Vector3.FORWARD, deg_to_rad(8)), 0.39)
	_tire(b, Vector3(-0.06, 0.22, 0.28), Basis(Vector3.RIGHT, deg_to_rad(72)), 0.38)
	if collide:
		_cyl_col(b, Vector3(0, 0.28, 0), 0.45, 0.6)


func _barrel(name: String, pos: Vector3, yaw: float) -> void:
	var b := _body(name, pos, yaw)
	var rust := _mat(Color(0.88, 0.82, 0.72), Color(0, 0, 0, 0), 1.0, TEX_RUST)
	_cyl(b, Vector3(0, 0.48, 0), 0.32, 0.96, rust, true)
	_cyl(b, Vector3(0, 0.97, 0), 0.33, 0.05, _mat(Color(0.25, 0.18, 0.12)))


func _crate(name: String, pos: Vector3, yaw: float, size := Vector3(0.7, 0.55, 0.7)) -> void:
	var b := _body(name, pos, yaw)
	_box(b, Vector3(0, size.y * 0.5, 0), size, _mat(Color(0.78, 0.62, 0.4), Color(0, 0, 0, 0), 1.0, TEX_CARD if size.x < 0.65 else TEX_PLANKS), true)


func _sofa(name: String, pos: Vector3, yaw: float) -> void:
	var b := _body(name, pos, yaw)
	var tan := _mat(Color(0.62, 0.42, 0.26))
	var dark := _mat(Color(0.38, 0.24, 0.14))
	_box(b, Vector3(0, 0.28, 0), Vector3(1.85, 0.36, 0.78), tan, true)
	_box(b, Vector3(0, 0.62, -0.28), Vector3(1.85, 0.55, 0.24), tan)
	_box(b, Vector3(-0.92, 0.42, 0.04), Vector3(0.18, 0.42, 0.78), dark)
	_box(b, Vector3(0.92, 0.42, 0.04), Vector3(0.18, 0.42, 0.78), dark)


func _chair(name: String, pos: Vector3, yaw: float) -> void:
	var n := _group(name, pos, yaw)
	var metal := _mat(Color(0.45, 0.42, 0.38))
	var cloth := _mat(Color(0.55, 0.62, 0.38))
	_box(n, Vector3(0, 0.38, 0), Vector3(0.52, 0.05, 0.48), cloth)
	_box(n, Vector3(0, 0.68, -0.22), Vector3(0.52, 0.48, 0.05), cloth, false, Basis(Vector3.RIGHT, deg_to_rad(-18)))
	_cyl(n, Vector3(-0.2, 0.18, 0.18), 0.02, 0.36, metal)
	_cyl(n, Vector3(0.2, 0.18, 0.18), 0.02, 0.36, metal)
	_cyl(n, Vector3(-0.2, 0.16, -0.18), 0.02, 0.32, metal, false, Basis(Vector3.FORWARD, deg_to_rad(38)))


func _mailbox(name: String, pos: Vector3, yaw: float) -> void:
	var n := _group(name, pos, yaw)
	var wood := _mat(Color(0.4, 0.26, 0.14), Color(0, 0, 0, 0), 1.0, TEX_PLANKS)
	var boxc := _mat(Color(0.82, 0.18, 0.14))
	_box(n, Vector3(0, 0.55, 0), Vector3(0.08, 1.1, 0.08), wood)
	_box(n, Vector3(0.12, 1.18, 0), Vector3(0.42, 0.22, 0.24), boxc)


func _fridge(name: String, pos: Vector3, yaw: float) -> void:
	var b := _body(name, pos, yaw)
	var white := _mat(Color(0.78, 0.8, 0.76))
	var rust := _mat(Color(0.7, 0.45, 0.28), Color(0, 0, 0, 0), 1.0, TEX_RUST)
	_box(b, Vector3(0, 0.32, 0), Vector3(1.55, 0.64, 0.72), white, true)
	_box(b, Vector3(0, 0.34, 0.28), Vector3(1.4, 0.5, 0.06), rust)


func _paint_spill(name: String, pos: Vector3, yaw: float) -> void:
	var n := _group(name, pos, yaw)
	var bucket_m := _mat(Color(0.32, 0.33, 0.35))
	var mag := _mat(Color(0.86, 0.08, 0.52))
	_mi(n, LowPoly.cylinder(0.38, 0.38, 0.02, 6), Vector3(0.0, 0.011, 0.0), mag)
	_mi(n, LowPoly.cylinder(0.28, 0.28, 0.018, 6), Vector3(0.16, 0.012, 0.10), mag)
	var side := Basis(Vector3.FORWARD, deg_to_rad(88))
	_cyl(n, Vector3(0.40, 0.09, 0.02), 0.085, 0.18, bucket_m, false, side)
	_cyl(n, Vector3(0.40, 0.09, 0.12), 0.088, 0.025, _mat(Color(0.22, 0.22, 0.24)), false, side)
	_mi(n, LowPoly.cylinder(0.04, 0.04, 0.016, 6), Vector3(0.40, 0.09, -0.08), mag, side)


func _hide_stock_dish() -> void:
	var city := get_parent()
	if city == null:
		return
	var tp := city.get_node_or_null("TrailerPark") as Node3D
	if tp == null:
		return
	var trailer := tp.get_node_or_null("Trailer") as Node3D
	if trailer == null:
		return
	for child in trailer.get_children():
		var mi := child as MeshInstance3D
		if mi == null:
			continue
		if mi.name == "M21" or mi.name == "M22":
			mi.visible = false
			continue
		if mi.position.y < 2.7:
			continue
		if mi.mesh is CylinderMesh:
			var cy := mi.mesh as CylinderMesh
			if cy.bottom_radius > 0.35 or cy.top_radius > 0.35:
				mi.visible = false
		elif mi.mesh is BoxMesh:
			var bx := mi.mesh as BoxMesh
			if bx.size.y < 0.6 and bx.size.x < 0.15:
				mi.visible = false


func _dish(name: String, pos: Vector3, yaw: float, on_roof: bool) -> void:
	var n := _group(name, pos, yaw)
	var grey := _mat(Color(0.62, 0.63, 0.65))
	var metal := _mat(Color(0.38, 0.38, 0.4))
	var y0 := 0.0 if on_roof else 1.35
	if not on_roof:
		_cyl(n, Vector3(0, 0.68, 0), 0.035, 1.36, metal)
	_box(n, Vector3(0, y0 + 0.04, 0), Vector3(0.1, 0.08, 0.08), metal)
	var arm_b := Basis(Vector3.RIGHT, deg_to_rad(-40))
	_cyl(n, Vector3(0.0, y0 + 0.14, 0.08), 0.018, 0.22, metal, false, arm_b)
	var dish_b := Basis(Vector3.RIGHT, deg_to_rad(-50))
	_cyl(n, Vector3(0.0, y0 + 0.20, 0.14), 0.04, 0.10, grey, false, dish_b, 0.26)
	var horn_b := Basis(Vector3.RIGHT, deg_to_rad(-50))
	_cyl(n, Vector3(0.0, y0 + 0.28, 0.26), 0.016, 0.07, metal, false, horn_b, 0.01)


func _clothesline(name: String, pos: Vector3, yaw: float) -> void:
	var n := _group(name, pos, yaw)
	var wood := _mat(Color(0.45, 0.28, 0.14), Color(0, 0, 0, 0), 1.0, TEX_PLANKS)
	var wire := _mat(Color(0.15, 0.14, 0.13))
	_box(n, Vector3(-2.6, 1.05, 0), Vector3(0.09, 2.1, 0.09), wood)
	_box(n, Vector3(2.6, 1.05, 0), Vector3(0.09, 2.1, 0.09), wood)
	var a := Vector3(-2.55, 2.05, 0)
	var mid := Vector3(0, 1.55, 0)
	var c := Vector3(2.55, 2.05, 0)
	_wire_seg(n, a, mid, wire)
	_wire_seg(n, mid, c, wire)
	var cols: Array[Color] = [Color(0.95, 0.35, 0.7), Color(0.25, 0.58, 0.32), Color(0.95, 0.55, 0.12)]
	var xs: Array[float] = [-1.3, 0.05, 1.35]
	for i in 3:
		_box(n, Vector3(xs[i], 1.25, 0), Vector3(0.55, 0.72, 0.035), _mat(cols[i]))


func _wire_seg(parent: Node3D, a: Vector3, b: Vector3, m: Material) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.04:
		return
	_cyl(parent, (a + b) * 0.5, 0.022, len, m, false, _align_y(d))


func _pole(name: String, pos: Vector3, yaw: float) -> Vector3:
	var b := _body(name, pos, yaw)
	var wood := _mat(Color(0.42, 0.26, 0.13), Color(0, 0, 0, 0), 1.0, TEX_PLANKS)
	_box(b, Vector3(0, 4.0, 0), Vector3(0.22, 8.0, 0.22), wood, true)
	_box(b, Vector3(0, 7.55, 0), Vector3(1.85, 0.14, 0.16), wood)
	return pos + Vector3(0, 7.42, 0)


func _span_wires(parent: Node3D, a: Vector3, b: Vector3) -> void:
	var wire := _mat(Color(0.1, 0.09, 0.08))
	var sag := clampf(a.distance_to(b) * 0.055, 0.7, 1.8)
	var mid := a.lerp(b, 0.5)
	mid.y -= sag
	_wire_seg(parent, a, mid, wire)
	_wire_seg(parent, mid, b, wire)


func _power_line(name: String, xs: Array[float], z: float, yaw: float) -> void:
	var wires := _group(name + "Wires", Vector3.ZERO)
	var tops: Array[Vector3] = []
	for i in xs.size():
		var x: float = xs[i]
		if _on_door_path(x, z):
			continue
		tops.append(_pole("%s%d" % [name, i], Vector3(x, 0, z), yaw))
	for i in range(1, tops.size()):
		_span_wires(wires, tops[i - 1], tops[i])


func _build_power_grid() -> void:
	var xs: Array[float] = [-122.5, -87.5, -52.5, -17.5, 17.5, 52.5, 87.5, 122.5]
	_power_line("PoleS", xs, -54.4, 0.0)
	_power_line("PoleN", xs, 39.4, 0.0)
	var park_xs: Array[float] = [-26.0, -8.0, 24.0]
	_power_line("PolePark", park_xs, -31.5, 12.0)


func _wall_lamp(name: String, pos: Vector3, yaw: float) -> void:
	var n := _group(name, pos, yaw)
	var hood := _mat(Color(0.28, 0.26, 0.22))
	var glow := _mat(Color(1.0, 0.92, 0.65), Color(1.0, 0.85, 0.45), 2.2)
	_box(n, Vector3(0, 0.08, -0.08), Vector3(0.12, 0.1, 0.28), hood)
	_box(n, Vector3(0, 0.02, 0.16), Vector3(0.38, 0.16, 0.34), hood, false, Basis(Vector3.RIGHT, deg_to_rad(18)))
	_box(n, Vector3(0, -0.04, 0.14), Vector3(0.16, 0.06, 0.16), glow)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.88, 0.55)
	l.light_energy = 1.15
	l.omni_range = 9.0
	l.omni_attenuation = 1.4
	l.shadow_enabled = false
	l.position = Vector3(0, -0.2, 0.2)
	n.add_child(l)
	_light_count += 1


func _build_wall_lamps() -> void:
	# 2 у трейлера, 2 на фасаде ангара, 2 на гаражах, 2 на складе — всего 8.
	_wall_lamp("WallLampTrailerDoor", Vector3(2.5, 2.55, -11.52), 0.0)
	_wall_lamp("WallLampTrailerWest", Vector3(-4.22, 2.42, -13.6), 90.0)
	_wall_lamp("WallLampHangarL", Vector3(-14.0, 6.1, -109.6), 0.0)
	_wall_lamp("WallLampHangarR", Vector3(14.0, 6.1, -109.6), 0.0)
	_wall_lamp("WallLampGarageL", Vector3(-124.0, 4.7, -104.2), 0.0)
	_wall_lamp("WallLampGarageR", Vector3(-96.0, 4.7, -104.2), 0.0)
	_wall_lamp("WallLampStorageL", Vector3(98.0, 4.4, -99.2), 0.0)
	_wall_lamp("WallLampStorageR", Vector3(122.0, 4.4, -99.2), 0.0)


func _tumbleweed(name: String, pos: Vector3) -> void:
	var n := _group(name, pos, float(int(pos.x * 13.0) % 360))
	_mi(n, LowPoly.sphere(0.38, 6, 3, false, 0.62), Vector3(0, 0.32, 0), _mat(Color(0.55, 0.4, 0.22)))


func _chain(name: String, pos: Vector3, yaw: float) -> void:
	var n := _group(name, pos, yaw)
	var post := _mat(Color(0.35, 0.36, 0.34))
	var mesh := _mat(Color(0.55, 0.56, 0.52))
	_cyl(n, Vector3(-1.2, 0.7, 0), 0.04, 1.4, post)
	_cyl(n, Vector3(1.2, 0.7, 0), 0.04, 1.4, post)
	_box(n, Vector3(0, 1.25, 0), Vector3(2.4, 0.03, 0.03), mesh)
	_box(n, Vector3(0, 0.35, 0), Vector3(2.4, 0.03, 0.03), mesh)
	_box(n, Vector3(0, 0.8, 0), Vector3(2.4, 0.9, 0.015), _mat(Color(0.5, 0.52, 0.48)))


func _cinder_pile(name: String, pos: Vector3, yaw: float) -> void:
	var n := _group(name, pos, yaw)
	var gray := _mat(Color(0.56, 0.55, 0.52))
	var hole := _mat(Color(0.3, 0.3, 0.29))
	var bricks: Array[Vector4] = [
		Vector4(-0.16, 0.10, 0.0, 8.0),
		Vector4(0.18, 0.10, 0.04, -12.0),
		Vector4(0.02, 0.10, 0.22, 70.0),
		Vector4(0.0, 0.30, 0.06, 18.0),
	]
	for i in bricks.size():
		var br: Vector4 = bricks[i]
		var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(br.w)), Vector3(br.x, br.y, br.z))
		var hold := Node3D.new()
		hold.transform = xf
		n.add_child(hold)
		_box(hold, Vector3.ZERO, Vector3(0.42, 0.2, 0.2), gray)
		_box(hold, Vector3(-0.09, 0.02, 0), Vector3(0.1, 0.14, 0.12), hole)


func _tire_planter(name: String, pos: Vector3, yaw: float) -> void:
	var b := _body(name, pos, yaw)
	_tire(b, Vector3(0, 0.08, 0), Basis(), 0.40)
	_tire(b, Vector3(0.03, 0.26, 0.02), Basis(Vector3.FORWARD, deg_to_rad(6)), 0.39)
	_cyl_col(b, Vector3(0, 0.22, 0), 0.42, 0.5)
	var leaf := _mat(Color(0.22, 0.48, 0.2))
	_cyl(b, Vector3(0.02, 0.52, 0.0), 0.03, 0.36, leaf, false, Basis(), 0.015)
	var lean := Basis(Vector3.FORWARD, deg_to_rad(-28))
	_cyl(b, Vector3(0.12, 0.48, 0.04), 0.025, 0.28, leaf, false, lean, 0.012)
	_mi(b, LowPoly.sphere(0.1, 6, 3), Vector3(0.02, 0.72, 0.0), leaf)
	_mi(b, LowPoly.sphere(0.08, 6, 3), Vector3(0.14, 0.64, 0.05), leaf)


func _barrel_table(name: String, pos: Vector3, yaw: float) -> void:
	var b := _body(name, pos, yaw)
	var rust := _mat(Color(0.88, 0.82, 0.72), Color(0, 0, 0, 0), 1.0, TEX_RUST)
	_cyl(b, Vector3(0, 0.48, 0), 0.32, 0.96, rust, true)
	_box(b, Vector3(0.05, 1.02, 0), Vector3(1.15, 0.05, 0.38), _mat(Color(0.55, 0.38, 0.2), Color(0, 0, 0, 0), 1.0, TEX_PLANKS))
	var gold := _mat(Color(0.72, 0.55, 0.18))
	var silver := _mat(Color(0.55, 0.56, 0.52))
	_cyl(b, Vector3(-0.22, 1.12, 0.04), 0.035, 0.12, gold)
	_cyl(b, Vector3(0.18, 1.12, -0.06), 0.032, 0.11, silver)


func _lean_mailbox(name: String, pos: Vector3, yaw: float) -> void:
	var n := _group(name, pos, yaw)
	n.rotate_object_local(Vector3.FORWARD, deg_to_rad(14.0))
	var wood := _mat(Color(0.42, 0.28, 0.16), Color(0, 0, 0, 0), 1.0, TEX_PLANKS)
	var rust := _mat(Color(0.7, 0.42, 0.28), Color(0, 0, 0, 0), 1.0, TEX_RUST)
	_box(n, Vector3(0, 0.55, 0), Vector3(0.07, 1.1, 0.07), wood)
	_box(n, Vector3(0.14, 1.16, 0), Vector3(0.4, 0.2, 0.22), rust)
	_box(n, Vector3(0.28, 1.16, 0), Vector3(0.04, 0.08, 0.06), _mat(Color(0.25, 0.2, 0.16)))


func _picket_bit(name: String, pos: Vector3, yaw: float) -> void:
	var n := _group(name, pos, yaw)
	var white := _mat(Color(0.93, 0.91, 0.86))
	_box(n, Vector3(0, 0.42, 0), Vector3(1.7, 0.05, 0.04), white)
	_box(n, Vector3(0, 0.72, 0), Vector3(1.7, 0.05, 0.04), white)
	for i in 6:
		var x := -0.75 + float(i) * 0.3
		if i == 3:
			_box(n, Vector3(x, 0.28, 0.02), Vector3(0.07, 0.42, 0.04), white, false, Basis(Vector3.FORWARD, deg_to_rad(28)))
		else:
			_box(n, Vector3(x, 0.5, 0), Vector3(0.07, 0.95, 0.04), white)


func _gnome(name: String, pos: Vector3, yaw: float) -> void:
	var n := _group(name, pos, yaw)
	var body := _mat(Color(0.18, 0.32, 0.55))
	var skin := _mat(Color(0.86, 0.62, 0.45))
	var hat := _mat(Color(0.82, 0.12, 0.12))
	_cyl(n, Vector3(0, 0.16, 0), 0.09, 0.22, body, false, Basis(), 0.07)
	_mi(n, LowPoly.sphere(0.07, 6, 3), Vector3(0, 0.32, 0), skin)
	_cyl(n, Vector3(0, 0.42, 0), 0.09, 0.18, hat, false, Basis(), 0.0)
	_box(n, Vector3(0, 0.31, 0.07), Vector3(0.03, 0.025, 0.04), skin)


func _dress_park() -> void:
	_tire_pile("ParkTires", Vector3(-12.4, 0, -9.2), 22.0)
	_sofa("ParkSofa", Vector3(-14.2, 0, -4.6), 32.0)
	_barrel("ParkBarrel0", Vector3(-13.2, 0, -11.6), 10.0)
	_crate("ParkCrate0", Vector3(-14.8, 0, -8.6), 15.0)
	_crate("ParkCrate1", Vector3(11.2, 0, -20.6), -25.0, Vector3(0.62, 0.48, 0.62))
	_hide_stock_dish()
	_dish("ParkDishRoof", Vector3(-2.15, 3.02, -12.35), 55.0, true)
	_dish("ParkDishPost", Vector3(-6.4, 0, -21.8), 30.0, false)
	_clothesline("ParkLine", Vector3(-14.6, 0, -11.4), 6.0)
	_chair("ParkChair", Vector3(11.8, 0, -8.6), -50.0)
	_mailbox("ParkMail", Vector3(5.5, 0, -10.15), -12.0)
	_fridge("ParkFridge", Vector3(-15.8, 0, 2.4), 55.0)
	_paint_spill("ParkPaint", Vector3(-12.2, 0, -6.8), 22.0)
	_tire_planter("ParkTirePlant", Vector3(-12.6, 0, -8.6), -18.0)
	_barrel_table("ParkBarrelTable", Vector3(12.4, 0, -10.2), 25.0)
	_lean_mailbox("ParkDriveMail", Vector3(6.2, 0, -33.4), 8.0)
	_picket_bit("ParkPicket", Vector3(-8.4, 0, -4.6), 18.0)


func _dress_edges() -> void:
	var weeds: Array[Vector3] = [Vector3(28, 0, 18), Vector3(-34, 0, 16), Vector3(48, 0, -36)]
	for i in weeds.size():
		var p: Vector3 = weeds[i]
		if _blocked(p.x, p.z, true):
			continue
		_tumbleweed("Tumble%d" % i, p)
	_barrel("EdgeBarrel0", Vector3(40.0, 0, -78.0), 8.0)
	_crate("EdgeCrate0", Vector3(38.5, 0, -80.2), 20.0)
	_tire_pile("EdgeTires0", Vector3(32.0, 0, 16.0), -15.0)
	_chain("EdgeChain0", Vector3(38.0, 0, -88.0), 0.0)


func _room() -> bool:
	return _mesh_count < MESH_CAP


func _mat_face(c: Color, tex: String) -> StandardMaterial3D:
	var key := "face|%s|%s" % [c.to_html(), tex]
	if _mats.has(key):
		return _mats[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	var t := load(tex) as Texture2D
	if t:
		m.albedo_texture = t
	_mats[key] = m
	return m


func _plain_ok(x: float, z: float, hub_r := 22.0) -> bool:
	if _on_road(x, z, 3.0) or _on_door_path(x, z):
		return false
	if Vector2(x, z).length() < 16.0:
		return false
	if z > 188.0:
		return false
	var pts: Array[Vector2] = [
		Vector2(0, -120), Vector2(110, -120), Vector2(-110, -120), Vector2(0, 160),
		Vector2(120, -8), Vector2(-120, -8), Vector2(-60, 78), Vector2(110, 78), Vector2(-120, 78),
	]
	var p := Vector2(x, z)
	for h in pts:
		if p.distance_to(h) < hub_r:
			return false
	return true


func _scrub(name: String, pos: Vector3, s: float) -> void:
	if not _room():
		return
	var n := _group(name, pos, pos.x * 17.0)
	var sage := _mat(Color(0.38, 0.42, 0.34))
	_mi(n, LowPoly.sphere(0.28 * s, 6, 3, false, 0.42 * s), Vector3(0.0, 0.22 * s, 0.0), sage)
	_mi(n, LowPoly.sphere(0.22 * s, 6, 3, false, 0.34 * s), Vector3(0.16 * s, 0.18 * s, 0.08 * s), sage)
	if s > 0.75 and _room():
		_mi(n, LowPoly.sphere(0.16 * s, 6, 3, false, 0.24 * s), Vector3(-0.12 * s, 0.16 * s, -0.1 * s), sage)


func _tuft(name: String, pos: Vector3, yaw: float) -> void:
	if not _room():
		return
	var n := _group(name, pos, yaw)
	var dry := _mat(Color(0.72, 0.62, 0.32))
	_box(n, Vector3(0, 0.15, 0), Vector3(0.28, 0.30, 0.03), dry)
	_box(n, Vector3(0, 0.15, 0), Vector3(0.03, 0.28, 0.26), dry)


func _rock(name: String, pos: Vector3, s: float) -> void:
	if not _room():
		return
	var n := _group(name, pos, pos.z * 11.0) if s < 1.15 else _body(name, pos, pos.z * 11.0)
	var col := _mat(Color(0.58, 0.5, 0.4) if int(pos.x) % 2 == 0 else Color(0.5, 0.48, 0.46))
	_mi(n, LowPoly.sphere(0.22 * s, 6, 3, false, 0.16 * s), Vector3(0, 0.08 * s, 0), col)
	if s >= 1.15:
		_cyl_col(n, Vector3(0, 0.12 * s, 0), 0.28 * s, 0.28 * s)


func _cart(name: String, pos: Vector3, yaw: float) -> void:
	if not _room():
		return
	var n := _group(name, pos, yaw)
	var wire := _mat(Color(0.55, 0.56, 0.58))
	var dark := _mat(Color(0.18, 0.18, 0.2))
	_box(n, Vector3(0, 0.42, 0), Vector3(0.62, 0.04, 0.42), wire)
	_box(n, Vector3(0, 0.28, 0), Vector3(0.58, 0.28, 0.38), _mat(Color(0.45, 0.46, 0.48)))
	_box(n, Vector3(-0.22, 0.62, -0.12), Vector3(0.04, 0.36, 0.04), wire)
	_box(n, Vector3(0.0, 0.78, -0.18), Vector3(0.42, 0.04, 0.04), wire)
	var wxs: Array[float] = [-0.22, 0.22]
	var wzs: Array[float] = [-0.14, 0.14]
	var wb := Basis(Vector3.FORWARD, deg_to_rad(90))
	for wx in wxs:
		for wz in wzs:
			_cyl(n, Vector3(wx, 0.06, wz), 0.06, 0.04, dark, false, wb)


func _ad_board(name: String, pos: Vector3, yaw: float, tex: String) -> void:
	if not _room():
		return
	var b := _body(name, pos, yaw)
	var metal := _mat(Color(0.35, 0.36, 0.4))
	_cyl(b, Vector3(-2.2, 3.2, 0), 0.12, 6.4, metal, true)
	_cyl(b, Vector3(2.2, 3.2, 0), 0.12, 6.4, metal, true)
	_box(b, Vector3(0, 5.6, 0), Vector3(5.4, 2.6, 0.12), _mat(Color(0.88, 0.86, 0.8)))
	_box(b, Vector3(0, 5.6, 0.07), Vector3(5.1, 2.35, 0.04), _mat_face(Color(1, 1, 1), tex))


func _fence_bit(name: String, pos: Vector3, yaw: float) -> void:
	if not _room():
		return
	_picket_bit(name, pos, yaw)


func _ruts(name: String, a: Vector3, b: Vector3) -> void:
	if not _room():
		return
	var n := _group(name, Vector3.ZERO)
	var dirt := _mat(Color(0.62, 0.5, 0.4))
	var d := b - a
	d.y = 0.0
	var len := d.length()
	if len < 4.0:
		return
	var mid := (a + b) * 0.5
	mid.y = 0.012
	var yaw := atan2(d.x, d.z)
	var basis := Basis(Vector3.UP, yaw)
	var side := basis * Vector3(0.8, 0, 0)
	_box(n, mid + side, Vector3(0.4, 0.02, len), dirt, false, basis)
	_box(n, mid - side, Vector3(0.4, 0.02, len), dirt, false, basis)


func _decal_pad(name: String, pos: Vector3, yaw: float) -> void:
	if not _room():
		return
	var n := _group(name, pos, yaw)
	var oil := _mat(Color(0.22, 0.18, 0.14))
	var card := _mat(Color(0.72, 0.58, 0.36), Color(0, 0, 0, 0), 1.0, TEX_CARD)
	_mi(n, LowPoly.cylinder(0.55, 0.55, 0.016, 6), Vector3(0.0, 0.01, 0.0), oil)
	_mi(n, LowPoly.cylinder(0.32, 0.32, 0.014, 6), Vector3(0.7, 0.011, 0.35), oil)
	_box(n, Vector3(-0.45, 0.015, 0.4), Vector3(0.28, 0.012, 0.22), card, false, Basis(Vector3.UP, 0.4))
	_box(n, Vector3(0.35, 0.014, -0.5), Vector3(0.2, 0.01, 0.16), card, false, Basis(Vector3.UP, -0.7))


func _forklift_out(name: String, pos: Vector3, yaw: float) -> void:
	if not _room():
		return
	var b := _body(name, pos, yaw)
	var yel := _mat(Color(0.88, 0.7, 0.12))
	var blk := _mat(Color(0.12, 0.12, 0.13))
	_box(b, Vector3(0, 0.55, 0.1), Vector3(1.05, 0.7, 1.35), yel, true)
	_box(b, Vector3(0, 1.15, -0.25), Vector3(0.85, 0.55, 0.7), yel)
	_box(b, Vector3(0, 0.85, 0.85), Vector3(0.08, 1.1, 0.08), _mat(Color(0.4, 0.4, 0.42)))
	_box(b, Vector3(0, 0.28, 0.95), Vector3(0.55, 0.06, 0.7), _mat(Color(0.35, 0.35, 0.36)))
	var wb := Basis(Vector3.FORWARD, deg_to_rad(90))
	_cyl(b, Vector3(-0.42, 0.22, 0.35), 0.2, 0.14, blk, false, wb)
	_cyl(b, Vector3(0.42, 0.22, 0.35), 0.2, 0.14, blk, false, wb)
	_cyl(b, Vector3(-0.42, 0.22, -0.4), 0.22, 0.14, blk, false, wb)
	_cyl(b, Vector3(0.42, 0.22, -0.4), 0.22, 0.14, blk, false, wb)


func _pallet_out(name: String, pos: Vector3, yaw: float) -> void:
	if not _room():
		return
	var n := _group(name, pos, yaw)
	var wood := _mat(Color(0.62, 0.45, 0.26), Color(0, 0, 0, 0), 1.0, TEX_PLANKS)
	_box(n, Vector3(0, 0.06, 0), Vector3(1.15, 0.12, 1.05), wood)
	_box(n, Vector3(0, 0.20, 0.02), Vector3(1.1, 0.12, 1.0), wood)
	_box(n, Vector3(0.04, 0.34, -0.03), Vector3(1.05, 0.12, 0.95), wood)


func _tube_man(name: String, pos: Vector3, yaw: float) -> void:
	if not _room():
		return
	var n := _group(name, pos, yaw)
	n.rotate_object_local(Vector3.FORWARD, deg_to_rad(12.0))
	var yel := _mat(Color(0.95, 0.82, 0.12))
	_cyl(n, Vector3(0, 0.7, 0), 0.18, 1.4, yel, false, Basis(), 0.22)
	_cyl(n, Vector3(0.08, 2.0, 0), 0.2, 1.3, yel, false, Basis(), 0.16)
	_cyl(n, Vector3(0.18, 3.15, 0.04), 0.14, 1.05, yel, false, Basis(), 0.22)
	_mi(n, LowPoly.sphere(0.28, 6, 3), Vector3(0.22, 3.75, 0.06), yel)
	_box(n, Vector3(0.42, 2.4, 0), Vector3(0.7, 0.12, 0.12), yel, false, Basis(Vector3.FORWARD, deg_to_rad(-35)))
	_box(n, Vector3(-0.12, 2.2, 0.1), Vector3(0.55, 0.1, 0.1), yel, false, Basis(Vector3.FORWARD, deg_to_rad(40)))


func _cop_car(name: String, pos: Vector3, yaw: float) -> void:
	if not _room():
		return
	var n := _group(name, pos, yaw)
	var white := _mat(Color(0.9, 0.9, 0.92))
	var blue := _mat(Color(0.12, 0.22, 0.62))
	var blk := _mat(Color(0.1, 0.1, 0.11))
	_box(n, Vector3(0, 0.48, 0), Vector3(1.85, 0.5, 4.1), white)
	_box(n, Vector3(0, 0.95, -0.15), Vector3(1.7, 0.45, 2.2), blue)
	_box(n, Vector3(0, 1.22, 0.05), Vector3(0.55, 0.12, 0.7), _mat(Color(0.85, 0.1, 0.12), Color(0.9, 0.08, 0.12), 2.4))
	_box(n, Vector3(0, 1.22, -0.35), Vector3(0.55, 0.12, 0.55), _mat(Color(0.15, 0.25, 0.95), Color(0.2, 0.3, 1.0), 2.4))
	var wb := Basis(Vector3.FORWARD, deg_to_rad(90))
	var zs: Array[float] = [-1.25, 1.25]
	for z in zs:
		_cyl(n, Vector3(-0.85, 0.28, z), 0.28, 0.22, blk, false, wb)
		_cyl(n, Vector3(0.85, 0.28, z), 0.28, 0.22, blk, false, wb)


func _cone_out(name: String, pos: Vector3) -> void:
	if not _room():
		return
	var n := _group(name, pos, 0.0)
	_cyl(n, Vector3(0, 0.28, 0), 0.14, 0.55, _mat(Color(0.92, 0.38, 0.08)), false, Basis(), 0.04)
	_cyl(n, Vector3(0, 0.32, 0), 0.11, 0.07, _mat(Color(0.95, 0.95, 0.92)))


func _dress_facades() -> void:
	_facade_casino()
	_facade_police()
	_facade_port()
	_facade_carmarket()
	_facade_vendors()
	_facade_hangar()


func _facade_casino() -> void:
	## Дверь на −Z (к дороге z=45). Здание сдвинуто на +3 по z.
	var door := Vector3(110.0, 0.0, 70.8)
	var n := _group("CasinoFace", door, 180.0)
	var gold := _mat(Color(0.72, 0.55, 0.16))
	var bulb := _mat(Color(1.0, 0.88, 0.35), Color(1.0, 0.85, 0.3), 3.2)
	var neon := _mat(Color(0.95, 0.08, 0.18), Color(1.0, 0.1, 0.2), 3.6)
	_box(n, Vector3(0, 5.85, 0.15), Vector3(8.4, 0.28, 0.55), gold)
	for i in 12:
		var x := -3.3 + float(i) * 0.6
		_mi(n, LowPoly.sphere(0.07, 6, 3), Vector3(x, 5.72, 0.42), bulb)
	## Неон по кромке крыши — юг (вход) и север (глухая стена с аэро-камеры).
	_box(n, Vector3(0, 6.35, 0.2), Vector3(24.5, 0.28, 0.22), neon)
	var north := _group("CasinoRear", Vector3(110.0, 0.0, 91.35), 0.0)
	_box(north, Vector3(0, 6.2, 0.12), Vector3(25.2, 0.32, 0.24), neon)
	_box(north, Vector3(-12.6, 4.4, 0.12), Vector3(0.22, 3.6, 0.22), neon)
	_box(north, Vector3(12.6, 4.4, 0.12), Vector3(0.22, 3.6, 0.22), neon)
	var win := _mat(Color(0.95, 0.55, 0.2), Color(1.0, 0.45, 0.15), 2.2)
	var win2 := _mat(Color(0.9, 0.15, 0.45), Color(0.95, 0.12, 0.4), 2.4)
	for i in 6:
		var wx := -8.8 + float(i) * 3.5
		_box(north, Vector3(wx, 2.7, 0.1), Vector3(1.7, 1.35, 0.08), win if i % 2 == 0 else win2)
	var pyl := _group("CasinoPylon", Vector3(118.5, 0, 52.4), 12.0)
	var post := _mat(Color(0.28, 0.28, 0.3))
	_box(pyl, Vector3(0, 3.4, 0), Vector3(0.28, 6.8, 0.28), post, true)
	_box(pyl, Vector3(0, 7.4, 0.06), Vector3(2.4, 1.5, 0.22), _mat(Color(0.85, 0.08, 0.55), Color(0.95, 0.1, 0.6), 2.8))
	_box(pyl, Vector3(0, 6.45, 0.08), Vector3(2.1, 0.35, 0.16), _mat(Color(0.95, 0.82, 0.15), Color(1.0, 0.85, 0.2), 2.4))
	_palm(50, Vector3(102.5, 0, 71.2), 0.92, -14.0)
	_palm(51, Vector3(117.4, 0, 71.4), 0.88, 12.0)
	_box(n, Vector3(0, 0.015, 2.4), Vector3(2.2, 0.02, 4.6), _mat(Color(0.55, 0.06, 0.1)))
	var brass := _mat(Color(0.7, 0.52, 0.18))
	var rope := _mat(Color(0.45, 0.08, 0.1))
	var posts: Array[Vector3] = [
		Vector3(-1.15, 0.45, 0.6), Vector3(1.15, 0.45, 0.6),
		Vector3(-1.15, 0.45, 3.8), Vector3(1.15, 0.45, 3.8),
	]
	for p in posts:
		_cyl(n, p, 0.04, 0.9, brass)
		_mi(n, LowPoly.sphere(0.055, 6, 3), p + Vector3(0, 0.48, 0), brass)
	_cyl(n, Vector3(-1.15, 0.82, 2.2), 0.018, 3.2, rope, false, Basis(Vector3.RIGHT, deg_to_rad(90)))
	_cyl(n, Vector3(1.15, 0.82, 2.2), 0.018, 3.2, rope, false, Basis(Vector3.RIGHT, deg_to_rad(90)))
	var l0 := OmniLight3D.new()
	l0.light_color = Color(1.0, 0.55, 0.7)
	l0.light_energy = 1.35
	l0.omni_range = 10.0
	l0.shadow_enabled = false
	l0.position = Vector3(0, 4.2, 1.2)
	n.add_child(l0)
	_light_count += 1
	var l1 := OmniLight3D.new()
	l1.light_color = Color(1.0, 0.75, 0.35)
	l1.light_energy = 1.1
	l1.omni_range = 8.0
	l1.shadow_enabled = false
	l1.position = Vector3(8.5, 6.2, -18.4)
	n.add_child(l1)
	_light_count += 1


func _facade_police() -> void:
	var n := _group("PoliceFace", Vector3(-120.0, 0, 70.0), 180.0)
	var yel := _mat(Color(0.95, 0.78, 0.12))
	var blu := _mat(Color(0.12, 0.22, 0.7))
	var wh := _mat(Color(0.92, 0.92, 0.94))
	_cyl(n, Vector3(-2.2, 0.55, 0), 0.08, 1.1, _mat(Color(0.32, 0.33, 0.35)))
	_box(n, Vector3(0.2, 0.98, 0), Vector3(4.6, 0.1, 0.1), yel)
	_box(n, Vector3(-1.1, 0.98, 0.06), Vector3(0.55, 0.1, 0.04), blu)
	_box(n, Vector3(0.4, 0.98, 0.06), Vector3(0.55, 0.1, 0.04), wh)
	_box(n, Vector3(1.8, 0.98, 0.06), Vector3(0.55, 0.1, 0.04), blu)
	_cyl(n, Vector3(3.6, 2.1, 0.2), 0.05, 4.2, _mat(Color(0.4, 0.4, 0.42)))
	_box(n, Vector3(3.85, 3.85, 0.2), Vector3(0.7, 0.42, 0.04), _mat(Color(0.15, 0.22, 0.65)))
	_cop_car("PoliceCarSil", Vector3(-113.0, 0, 64.0), 8.0)
	_cyl(n, Vector3(0.0, 2.2, -18.0), 0.05, 4.4, _mat(Color(0.4, 0.4, 0.42)))
	_box(n, Vector3(0.22, 4.0, -18.0), Vector3(0.7, 0.42, 0.04), _mat(Color(0.15, 0.22, 0.65)))
	var cones: Array[Vector3] = [
		Vector3(-123.6, 0, 66.5), Vector3(-116.4, 0, 66.2), Vector3(-124.2, 0, 86.4), Vector3(-115.8, 0, 86.8),
	]
	for i in cones.size():
		_cone_out("PolCone%d" % i, cones[i])
	var bench := _group("PolDonut", Vector3(-126.5, 0, 68.4), 90.0)
	var wood := _mat(Color(0.45, 0.32, 0.18), Color(0, 0, 0, 0), 1.0, TEX_PLANKS)
	_box(bench, Vector3(0, 0.42, 0), Vector3(1.5, 0.07, 0.4), wood)
	_box(bench, Vector3(-0.65, 0.22, 0), Vector3(0.08, 0.4, 0.38), wood)
	_box(bench, Vector3(0.65, 0.22, 0), Vector3(0.08, 0.4, 0.38), wood)
	_box(bench, Vector3(0.1, 0.52, 0.02), Vector3(0.28, 0.1, 0.22), _mat(Color(0.82, 0.55, 0.22), Color(0, 0, 0, 0), 1.0, TEX_CARD))
	_cyl(bench, Vector3(0.1, 0.6, 0.02), 0.07, 0.05, _mat(Color(0.85, 0.45, 0.2)))


func _facade_port() -> void:
	var n := _group("PortEdge", Vector3(0, 0, 186.5), 0.0)
	var wood := _mat(Color(0.42, 0.28, 0.14), Color(0, 0, 0, 0), 1.0, TEX_PLANKS)
	var rope := _mat(Color(0.35, 0.28, 0.18))
	var xs: Array[float] = [-16.0, -8.0, 0.0, 8.0, 16.0, 22.0]
	for i in xs.size():
		_cyl(n, Vector3(xs[i], 0.55, 0), 0.06, 1.1, wood)
	for i in range(1, xs.size()):
		var mid := (xs[i - 1] + xs[i]) * 0.5
		_cyl(n, Vector3(mid, 0.95, 0), 0.02, absf(xs[i] - xs[i - 1]), rope, false, Basis(Vector3.FORWARD, deg_to_rad(90)))
	var iron := _mat(Color(0.28, 0.28, 0.3))
	var bxs: Array[float] = [-18.0, -4.0, 10.0, 20.0]
	for i in bxs.size():
		var b := _body("PortBoll%d" % i, Vector3(bxs[i], 0, 187.2))
		_cyl(b, Vector3(0, 0.38, 0), 0.2, 0.76, iron, true)
		_cyl(b, Vector3(0, 0.78, 0), 0.24, 0.1, iron)
	for i in 2:
		var bg := _group("PortBuoy%d" % i, Vector3(-10.0 + float(i) * 18.0, 0.12, 189.4))
		_mi(bg, LowPoly.sphere(0.22, 6, 3), Vector3(0, 0.22, 0), _mat(Color(0.92, 0.35, 0.08)))
		_cyl(bg, Vector3(0, 0.42, 0), 0.04, 0.2, _mat(Color(0.9, 0.9, 0.88)))


func _port_heavy_maybe() -> void:
	var city := get_parent()
	if city == null:
		return
	var port := city.get_node_or_null("Port") as Node3D
	if port == null:
		return
	var inn := port.get_node_or_null("Interior") as Node3D
	if inn != null and inn.get_child_count() > 20:
		return
	if not _room():
		return
	var st := _body("PortCans", Vector3(-14.5, 0, 176.5), 8.0)
	var cols: Array[Color] = [Color(0.15, 0.42, 0.48), Color(0.72, 0.22, 0.14)]
	for i in 2:
		_box(st, Vector3(0, 1.15 + float(i) * 2.15, 0), Vector3(6.1, 2.1, 2.4), _mat(cols[i], Color(0, 0, 0, 0), 1.0, TEX_CONTAINER), true)
	var cr := _body("PortCrane", Vector3(16.0, 0, 174.5), -25.0)
	var yel := _mat(Color(0.9, 0.7, 0.12))
	_box(cr, Vector3(0, 1.1, 0), Vector3(1.35, 2.2, 1.35), yel, true)
	_box(cr, Vector3(0, 6.2, 0), Vector3(0.55, 8.2, 0.55), yel)
	_box(cr, Vector3(3.4, 10.15, 0), Vector3(7.2, 0.35, 0.4), yel)


func _facade_carmarket() -> void:
	var poles: Array[Vector3] = [
		Vector3(102.0, 3.2, 8.0), Vector3(138.0, 3.2, 8.0),
		Vector3(102.0, 3.2, -24.0), Vector3(138.0, 3.2, -24.0),
	]
	_bunting_line("CmBuntA", poles[0], poles[1])
	_bunting_line("CmBuntB", poles[2], poles[3])
	_bulb_string("CmBulbs", Vector3(104.0, 3.5, -8.0), Vector3(136.0, 3.5, -8.0), 8)
	_tube_man("CmTube", Vector3(101.5, 0, -2.0), -70.0)


func _bunting_line(name: String, a: Vector3, b: Vector3) -> void:
	if not _room():
		return
	var n := _group(name, Vector3.ZERO)
	var wire := _mat(Color(0.2, 0.18, 0.16))
	_wire_seg(n, a, b, wire)
	var cols: Array[Color] = [Color(0.92, 0.22, 0.48), Color(0.95, 0.78, 0.15), Color(0.15, 0.4, 0.75)]
	for i in 7:
		var t := (float(i) + 0.5) / 7.0
		var p: Vector3 = a.lerp(b, t)
		p.y -= 0.15
		_box(n, p, Vector3(0.28, 0.32, 0.02), _mat(cols[i % 3]))


func _bulb_string(name: String, a: Vector3, b: Vector3, n_bulbs: int) -> void:
	if not _room():
		return
	var n := _group(name, Vector3.ZERO)
	var wire := _mat(Color(0.18, 0.16, 0.14))
	var glow := _mat(Color(1.0, 0.88, 0.4), Color(1.0, 0.82, 0.3), 2.6)
	_wire_seg(n, a, b, wire)
	for i in n_bulbs:
		var t := float(i) / float(maxi(n_bulbs - 1, 1))
		_mi(n, LowPoly.sphere(0.06, 5, 3), a.lerp(b, t) + Vector3(0, -0.08, 0), glow)


func _facade_vendors() -> void:
	var n := _group("VenLot", Vector3(-120.0, 0, -10.0), 0.0)
	_box(n, Vector3(0, 0.035, 0), Vector3(29.6, 0.018, 15.7), _mat(Color(0.50, 0.46, 0.42)))
	var line := _mat(Color(0.88, 0.86, 0.80))
	for i in 5:
		var x := -10.0 + float(i) * 5.0
		_box(n, Vector3(x, 0.046, 0.2), Vector3(0.14, 0.012, 5.2), line)
	_dumpster(40, Vector3(-132.5, -4.8, 8.0))
	_dumpster(41, Vector3(-107.2, -5.2, -12.0))
	_crate("VenCrateA", Vector3(-133.8, 0, -4.2), 18.0)
	_crate("VenCrateB", Vector3(-106.4, 0, -3.6), -22.0, Vector3(0.62, 0.48, 0.62))


func _facade_hangar() -> void:
	_pallet_out("HangPalOut0", Vector3(-9.5, 0, -104.2), 8.0)
	_pallet_out("HangPalOut1", Vector3(-7.8, 0, -103.4), -14.0)
	_forklift_out("HangForkOut", Vector3(9.2, 0, -103.6), -18.0)
	_barrel("HangOil0", Vector3(12.4, 0, -105.0), 10.0)
	_barrel("HangOil1", Vector3(13.2, 0, -104.2), -20.0)
	_barrel("HangOil2", Vector3(-11.6, 0, -105.4), 6.0)
	_wall_lamp("WallLampHangarSign", Vector3(0.0, 7.4, -108.6), 0.0)


func _dress_plains() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260902
	_extend_power()
	_ruts("RutVendors", Vector3(-22.0, 0, -18.0), Vector3(-96.0, 0, -16.0))
	_ruts("RutCasino", Vector3(22.0, 0, 18.0), Vector3(92.0, 0, 58.0))
	_ruts("RutPort", Vector3(8.0, 0, 22.0), Vector3(6.0, 0, 128.0))
	_ad_board("AdCasinoHwy", Vector3(78.0, 0, 38.5), 8.0, TEX_AD_CASINO)
	_ad_board("AdCarHwy", Vector3(98.0, 0, -48.5), -6.0, TEX_AD_CAR)
	var palms: Array[Vector3] = [
		Vector3(-102.0, 0, 10.5), Vector3(96.0, 0, 68.0), Vector3(132.5, 0, 8.2), Vector3(-98.0, 0, 62.0),
	]
	for i in palms.size():
		var pp: Vector3 = palms[i]
		if _plain_ok(pp.x, pp.z, 16.0):
			_palm(52 + i, pp, 1.05, 14.0 if i % 2 == 0 else -12.0)
	var cacti: Array[Vector3] = [
		Vector3(-48.0, 0, 28.0), Vector3(52.0, 0, 22.0), Vector3(-88.0, 0, -38.0),
		Vector3(42.0, 0, 98.0), Vector3(-38.0, 0, 118.0), Vector3(88.0, 0, -88.0),
	]
	for i in cacti.size():
		var cp: Vector3 = cacti[i]
		if _plain_ok(cp.x, cp.z, 18.0):
			_cactus(30 + i, cp, 0.95 + float(i) * 0.04, false)
	var tires: Array[Vector3] = [
		Vector3(-42.0, 0, -88.0), Vector3(48.0, 0, -82.0), Vector3(-92.0, 0, 28.0),
		Vector3(86.0, 0, 28.0), Vector3(18.0, 0, 132.0),
	]
	for i in tires.size():
		if _plain_ok(tires[i].x, tires[i].z, 20.0):
			_tire_pile("PlainTires%d" % i, tires[i], float(i * 22), false)
	var barrels: Array[Vector3] = [
		Vector3(-36.0, 0, 38.0), Vector3(38.0, 0, -38.0), Vector3(-78.0, 0, 98.0), Vector3(72.0, 0, 108.0),
	]
	for i in barrels.size():
		if _plain_ok(barrels[i].x, barrels[i].z, 20.0):
			_barrel("PlainBar%d" % i, barrels[i], float(i * 18))
	var carts: Array[Vector3] = [
		Vector3(-108.0, 0, 12.0), Vector3(108.0, 0, 12.0), Vector3(-28.0, 0, 88.0),
	]
	for i in carts.size():
		if _plain_ok(carts[i].x, carts[i].z, 18.0):
			_cart("PlainCart%d" % i, carts[i], float(i * 40))
	var cars: Array[Vector4] = [
		Vector4(-55.0, 32.0, 70.0, 1.0), Vector4(58.0, -36.0, 200.0, 2.0), Vector4(-24.0, 142.0, 15.0, 0.0),
	]
	for i in cars.size():
		if _plain_ok(cars[i].x, cars[i].y, 22.0):
			_junk_car(20 + i, cars[i])
	var fences: Array[Vector3] = [
		Vector3(-44.0, 0, -36.0), Vector3(46.0, 0, 36.0), Vector3(-96.0, 0, -28.0),
		Vector3(94.0, 0, -28.0), Vector3(-28.0, 0, 96.0),
	]
	for i in fences.size():
		if _plain_ok(fences[i].x, fences[i].z, 18.0):
			_fence_bit("PlainFence%d" % i, fences[i], float(i * 25))
	var decals: Array[Vector3] = [
		Vector3(0.0, 0, -108.0), Vector3(110.0, 0, -108.0), Vector3(-110.0, 0, -108.0),
		Vector3(0.0, 0, 138.0), Vector3(104.0, 0, 6.0), Vector3(-120.0, 0, 6.0),
		Vector3(-60.0, 0, 66.0), Vector3(110.0, 0, 66.0), Vector3(-120.0, 0, 66.0), Vector3(6.0, 0, 10.0),
	]
	for i in decals.size():
		_decal_pad("Decal%d" % i, decals[i], float(i * 17))
	var placed := 0
	var guard := 0
	while placed < 48 and guard < 200 and _room():
		guard += 1
		var x := rng.randf_range(-155.0, 155.0)
		var z := rng.randf_range(-145.0, 175.0)
		if not _plain_ok(x, z, 20.0):
			continue
		_scrub("Scrub%d" % placed, Vector3(x, 0, z), rng.randf_range(0.55, 0.92))
		placed += 1
	placed = 0
	guard = 0
	while placed < 32 and guard < 160 and _room():
		guard += 1
		var x2 := rng.randf_range(-155.0, 155.0)
		var z2 := rng.randf_range(-145.0, 175.0)
		if not _plain_ok(x2, z2, 18.0):
			continue
		_tuft("Tuft%d" % placed, Vector3(x2, 0, z2), rng.randf_range(0.0, 180.0))
		placed += 1
	placed = 0
	guard = 0
	while placed < 20 and guard < 120 and _room():
		guard += 1
		var x3 := rng.randf_range(-155.0, 155.0)
		var z3 := rng.randf_range(-145.0, 175.0)
		if not _plain_ok(x3, z3, 20.0):
			continue
		var rs := rng.randf_range(0.35, 1.22)
		_rock("Rock%d" % placed, Vector3(x3, 0, z3), rs)
		placed += 1
	placed = 0
	guard = 0
	while placed < 8 and guard < 80 and _room():
		guard += 1
		var x4 := rng.randf_range(-150.0, 150.0)
		var z4 := rng.randf_range(-140.0, 170.0)
		if not _plain_ok(x4, z4, 22.0):
			continue
		_tumbleweed("PlainTumble%d" % placed, Vector3(x4, 0, z4))
		placed += 1


func _extend_power() -> void:
	## 10 столбов: дорога к порту, рукава к казино и полиции.
	var xs_port: Array[float] = [-87.5, -17.5, 17.5, 87.5]
	_power_line("PolePortRd", xs_port, 104.6, 0.0)
	var wires := _group("PoleArmWires", Vector3.ZERO)
	var cas := _pole("PoleCas0", Vector3(104.8, 0, 52.2), 90.0)
	var cas2 := _pole("PoleCas1", Vector3(104.8, 0, 68.0), 90.0)
	_span_wires(wires, cas, cas2)
	var pol := _pole("PolePol0", Vector3(-126.5, 0, 52.2), 90.0)
	var pol2 := _pole("PolePol1", Vector3(-126.5, 0, 68.0), 90.0)
	_span_wires(wires, pol, pol2)
	var prt := _pole("PolePortN0", Vector3(-6.8, 0, 128.0), 0.0)
	var prt2 := _pole("PolePortN1", Vector3(-6.8, 0, 148.0), 0.0)
	_span_wires(wires, prt, prt2)
