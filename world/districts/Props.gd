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
const TEX_CORRUGATED := "res://assets/textures/tex_corrugated.png"
const TEX_WALL := "res://assets/textures/tex_wall_exterior.png"
const TEX_TRAILER := "res://assets/textures/tex_trailer_siding.png"
const TEX_RUG := "res://assets/textures/tex_rug.png"
const GHETTO_SEED := 20260902
const TEX_AD_CASINO := "res://assets/textures/ad_casino.png"
const TEX_AD_CAR := "res://assets/textures/ad_carmarket.png"
const TEX_CONTAINER := "res://assets/textures/tex_container.png"
const MESH_CAP := 3200

const _HUBS: Array[Vector2] = [
	Vector2(0, -120), Vector2(110, -120), Vector2(-110, -120),
	Vector2(120, -8), Vector2(-120, -8), Vector2(-60, 78), Vector2(110, 78), Vector2(-120, 78),
]
const _VROADS: Array[Vector4] = [
	Vector4(-165, -60, -165, 110), Vector4(165, -60, 165, 110), Vector4(0, 45, 0, 135),
	Vector4(-75, -60, -75, 45), Vector4(75, -60, 75, 45), Vector4(0, -100, 0, -60),
	Vector4(120, -100, 120, -60), Vector4(-110, -100, -110, -60), Vector4(110, 45, 110, 64),
	Vector4(-120, 45, -120, 64), Vector4(-165, -20, 165, -20), Vector4(-165, 78, 165, 78),
	Vector4(0, 110, 0, 160), Vector4(40, -100, 40, -60), Vector4(-40, -100, -40, -60),
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
	_dress_ghetto()
	_build_power_grid()
	_build_wall_lamps()
	_dress_facades()
	_dress_plains()
	call_deferred("_port_heavy_maybe")
	if OS.is_debug_build():
		print("[Props] ghetto meshes=%d lights=%d nodes=%d" % [_mesh_count, _light_count, get_child_count()])


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
	# CityDress подменяет картинку только этому мешу — по имени; опоры и рама остаются металлом
	var ad := b.get_child(b.get_child_count() - 1)
	if ad:
		ad.name = "AdFace%d" % i
	# слоган живёт на своей тёмной плашке внизу щита: поверх рекламной картинки он не читался,
	# а прежним кеглем шесть строк вылезали за края
	_box(b, Vector3(0, 6.02, 0.03), Vector3(8.0, 1.9, 0.02), _mat(Color(0.09, 0.08, 0.11)))
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 60
	lbl.outline_size = 6
	lbl.pixel_size = 0.006
	lbl.width = 1230.0
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.modulate = Color(0.98, 0.96, 0.92)
	lbl.outline_modulate = Color(0.05, 0.05, 0.07, 0.9)
	lbl.position = Vector3(0, 6.02, 0.05)
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


## Реквизит трейлер-парка вылеплен в Blender (assets/models/park_*.glb): у дивана просевшие
## подушки и заплатка, у ящика отходит доска, у штакетника выломана штакетина.
## Коллизии остаются кодовыми — модель только заменяет вид.
func _model(parent: Node3D, file: String, pos := Vector3.ZERO, yaw_deg := 0.0, tilt_deg := 0.0) -> void:
	var path := "res://assets/models/%s.glb" % file
	if not ResourceLoader.exists(path):
		push_warning("[Props] нет модели %s" % path)
		return
	var packed: PackedScene = load(path)
	if packed == null:
		return
	var mdl := packed.instantiate() as Node3D
	if mdl == null:
		return
	var b := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	if absf(tilt_deg) > 0.01:
		b = b * Basis(Vector3.FORWARD, deg_to_rad(tilt_deg))
	mdl.transform = Transform3D(b, pos)
	mdl.set_meta("no_dress", true) # CityDress мимо: материалы уже запечены в модель
	parent.add_child(mdl)


## Газонный фламинго — модель из Blender (assets/models/flamingo_*.glb), а не сборка из брусков:
## у птицы каплевидный корпус, S-шея, чёрный кончик клюва и штыри вместо ног.
const FLAMINGO_STAND := "res://assets/models/flamingo_stand.glb"
const FLAMINGO_FEED := "res://assets/models/flamingo_feed.glb"


func _flamingo(i: int, pos: Vector3, yaw: float) -> void:
	var n := _group("Flamingo%d" % i, pos, yaw)
	var path := FLAMINGO_FEED if i == 1 else FLAMINGO_STAND
	var packed: PackedScene = load(path) if ResourceLoader.exists(path) else null
	if packed == null:
		push_warning("[Props] нет модели фламинго: %s" % path)
		return
	var mdl := packed.instantiate()
	mdl.set_meta("no_dress", true)
	n.add_child(mdl)


func _cinder(i: int, pos: Vector3, yaw: float) -> void:
	var n := _group("Cinder%d" % i, pos, yaw)
	_box(n, Vector3(0, 0.1, 0), Vector3(0.44, 0.2, 0.22), _mat(Color(0.56, 0.55, 0.52)))
	_box(n, Vector3(-0.1, 0.12, 0), Vector3(0.11, 0.16, 0.14), _mat(Color(0.3, 0.3, 0.29)))


func _tire(parent: Node3D, pos: Vector3, basis: Basis, r := 0.38) -> void:
	_cyl(parent, pos, r, 0.16, _mat(Color(0.08, 0.08, 0.09)), false, basis)


func _tire_pile(name: String, pos: Vector3, yaw: float, collide := true) -> void:
	var b := _body(name, pos, yaw) if collide else _group(name, pos, yaw)
	_model(b, "park_tire_pile")
	if collide:
		_cyl_col(b, Vector3(0, 0.28, 0), 0.45, 0.6)


func _barrel(name: String, pos: Vector3, yaw: float) -> void:
	var b := _body(name, pos, yaw)
	_model(b, "park_barrel")
	_cyl_col(b, Vector3(0, 0.48, 0), 0.34, 0.96)


func _crate(name: String, pos: Vector3, yaw: float, size := Vector3(0.7, 0.55, 0.7)) -> void:
	var b := _body(name, pos, yaw)
	# модель park_crate слеплена под 0.7 x 0.55 x 0.7 — тянем по осям, иначе меш не совпадёт с коллайдером
	var k := Vector3(size.x / 0.7, size.y / 0.55, size.z / 0.7)
	_model(b, "park_crate")
	for c in b.get_children():
		if c is Node3D and c is not CollisionShape3D:
			(c as Node3D).scale = k
	_box_col(b, Vector3(0, size.y * 0.5, 0), size)


func _sofa(name: String, pos: Vector3, yaw: float) -> void:
	var b := _body(name, pos, yaw)
	_model(b, "park_sofa")
	_box_col(b, Vector3(0, 0.35, 0), Vector3(1.85, 0.7, 0.82))


func _chair(name: String, pos: Vector3, yaw: float) -> void:
	var n := _group(name, pos, yaw)
	_model(n, "park_chair")


func _mailbox(name: String, pos: Vector3, yaw: float) -> void:
	var n := _group(name, pos, yaw)
	_model(n, "park_mailbox")


func _fridge(name: String, pos: Vector3, yaw: float) -> void:
	var b := _body(name, pos, yaw)
	_model(b, "park_fridge")
	_box_col(b, Vector3(0, 0.31, 0), Vector3(1.5, 0.62, 0.72))


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
	var metal := _mat(Color(0.38, 0.38, 0.4))
	var y0 := 0.0 if on_roof else 1.35
	if not on_roof:
		_cyl(n, Vector3(0, 0.68, 0), 0.035, 1.36, metal)
	_model(n, "park_dish", Vector3(0, y0 + 0.34, 0))


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
	var seg_len := d.length()
	if seg_len < 0.04:
		return
	_cyl(parent, (a + b) * 0.5, 0.022, seg_len, m, false, _align_y(d))


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
	_model(b, "park_tire_planter")
	_cyl_col(b, Vector3(0, 0.22, 0), 0.42, 0.5)


func _barrel_table(name: String, pos: Vector3, yaw: float) -> void:
	var b := _body(name, pos, yaw)
	_model(b, "park_barrel_table")
	_cyl_col(b, Vector3(0, 0.48, 0), 0.34, 0.96)


func _lean_mailbox(name: String, pos: Vector3, yaw: float) -> void:
	var n := _group(name, pos, yaw)
	_model(n, "park_mailbox", Vector3.ZERO, 0.0, 14.0)


func _picket_bit(name: String, pos: Vector3, yaw: float) -> void:
	var n := _group(name, pos, yaw)
	_model(n, "park_picket")


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
	_skin_player_trailer()
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


## Сайдинг + бирюзовая полоса на геройском трейлере (как у соседей).
func _skin_player_trailer() -> void:
	var city := _city()
	if city == null:
		return
	var dist: Node = null
	if city.has_method("district_root"):
		dist = city.district_root(Types.District.TRAILER_PARK)
	if dist == null:
		return
	var tr: Node = dist.get_node_or_null("Trailer")
	if tr == null:
		return
	var wall := _mat(Color(0.92, 0.88, 0.78), Color(0, 0, 0, 0), 1.0, TEX_TRAILER)
	var stripe := _mat(Color(0.12, 0.55, 0.62))
	var cream := Color(0.9, 0.86, 0.72)
	var teal := Color(0.12, 0.6, 0.6)
	for c in tr.get_children():
		if not (c is MeshInstance3D):
			continue
		var mi := c as MeshInstance3D
		var m: Material = mi.material_override
		if m == null or not (m is StandardMaterial3D):
			continue
		var sm := m as StandardMaterial3D
		var col := sm.albedo_color
		if col.is_equal_approx(cream) or (absf(col.r - cream.r) < 0.04 and absf(col.g - cream.g) < 0.04 and absf(col.b - cream.b) < 0.04):
			mi.material_override = wall
		elif col.is_equal_approx(teal) or (absf(col.r - teal.r) < 0.04 and absf(col.g - teal.g) < 0.04):
			mi.material_override = stripe
	# внешняя полоса сайдинга по длинной стене
	var stripe_bar := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(8.2, 0.16, 0.06)
	stripe_bar.mesh = bm
	stripe_bar.material_override = stripe
	stripe_bar.position = Vector3(0, 1.7, 1.92)
	tr.add_child(stripe_bar)
	_mesh_count += 1
	var stripe_back := stripe_bar.duplicate() as MeshInstance3D
	stripe_back.position = Vector3(0, 1.7, -1.92)
	tr.add_child(stripe_back)
	_mesh_count += 1



func _city() -> City:
	return get_parent() as City


func _trailer_xz() -> Vector2:
	return Vector2(0.0, -14.0)


func _road_clear(x: float, z: float, min_d := 7.0) -> bool:
	if absf(x) <= 165.0 + min_d:
		if absf(z + 60.0) <= min_d or absf(z - 45.0) <= min_d or absf(z - 110.0) <= min_d:
			return false
	for s in _VROADS:
		var x1: float = s.x
		var z1: float = s.y
		var z2: float = s.w
		if absf(x - x1) <= min_d and z >= minf(z1, z2) - min_d and z <= maxf(z1, z2) + min_d:
			return false
	return true


func _wasteland_ok(x: float, z: float) -> bool:
	if not _road_clear(x, z, 8.0):
		return false
	if _on_door_path(x, z):
		return false
	var city := _city()
	if city and city.district_at(Vector3(x, 0.0, z)) != null:
		return false
	return true


func _park_keepouts() -> Array[Vector3]:
	## (x, z, radius)
	return [
		Vector3(0.0, -14.0, 6.2), Vector3(5.0, 0.0, 2.8), Vector3(-2.0, -14.7, 3.0),
		Vector3(-8.0, -11.0, 2.2), Vector3(15.2, -5.0, 2.8), Vector3(-10.0, 22.0, 3.2),
		Vector3(-7.6, -6.0, 1.6), Vector3(8.8, 3.2, 1.8), Vector3(18.0, -6.0, 2.5),
		Vector3(-5.0, 25.0, 5.5), Vector3(21.0, 0.0, 4.5), Vector3(-4.0, -19.0, 2.5),
		Vector3(9.0, 30.0, 1.8), Vector3(6.4, -13.2, 2.5), Vector3(-26.0, -6.0, 3.5),
		Vector3(24.0, 22.0, 3.5),
	]


func _park_keepout_hit(x: float, z: float, rad: float) -> bool:
	if not _road_clear(x, z, 5.5):
		return true
	if _on_door_path(x, z):
		return true
	for k in _park_keepouts():
		if Vector2(k.x, k.y).distance_to(Vector2(x, z)) < k.z + rad:
			return true
	return false


func _park_ok(x: float, z: float, rad := 0.5) -> bool:
	var tp := _trailer_xz()
	var p := Vector2(x, z)
	if p.distance_to(tp) > 35.0 or p.distance_to(tp) < 6.5:
		return false
	return not _park_keepout_hit(x, z, rad)


func _yard_ok(x: float, z: float, rad := 0.45) -> bool:
	var tp := _trailer_xz()
	var p := Vector2(x, z)
	var d := p.distance_to(tp)
	if d > 14.0 or d < 6.5:
		return false
	return not _park_keepout_hit(x, z, rad)


func _neighbor_ok(x: float, z: float, rad: float, placed: Array[Vector2]) -> bool:
	var tp := _trailer_xz()
	var p := Vector2(x, z)
	var d := p.distance_to(tp)
	if d < 16.0 or d > 34.0:
		return false
	if not _road_clear(x, z, 7.0):
		return false
	if _park_keepout_hit(x, z, rad):
		return false
	for c in placed:
		if p.distance_to(c) < 6.0 + rad:
			return false
	return true


func _horizon_ok(x: float, z: float, rad := 2.5) -> bool:
	var tp := _trailer_xz()
	var d := Vector2(x, z).distance_to(tp)
	if d < 36.0 or d > 60.0:
		return false
	if not _wasteland_ok(x, z):
		return false
	for c in _horizon_placed:
		if Vector2(x, z).distance_to(c) < 5.0 + rad:
			return false
	return true


var _horizon_placed: Array[Vector2] = []


func _mat_shiny(c: Color, metal := 0.0, rough := 0.5) -> StandardMaterial3D:
	var key := "sh|%s|%.2f|%.2f" % [c.to_html(), metal, rough]
	if _mats.has(key):
		return _mats[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	_mats[key] = m
	return m


func _flat_disc(parent: Node3D, pos: Vector3, r: float, m: Material) -> void:
	_mi(parent, LowPoly.cylinder(r, r, 0.016, 8), pos, m)


func _sofa_stained(name: String, pos: Vector3, yaw: float) -> void:
	var b := _body(name, pos, yaw)
	var tan_mat := _mat(Color(0.62, 0.42, 0.26))
	var dark := _mat(Color(0.38, 0.24, 0.14))
	var stain := _mat(Color(0.42, 0.18, 0.22))
	_box(b, Vector3(0, 0.28, 0), Vector3(1.85, 0.36, 0.78), tan_mat, true)
	_box(b, Vector3(0, 0.62, -0.28), Vector3(1.85, 0.55, 0.24), tan_mat)
	_box(b, Vector3(-0.92, 0.42, 0.04), Vector3(0.18, 0.42, 0.78), dark)
	_box(b, Vector3(0.92, 0.42, 0.04), Vector3(0.18, 0.42, 0.78), dark)
	_box(b, Vector3(0.22, 0.48, 0.12), Vector3(0.55, 0.12, 0.42), stain)


func _tent(name: String, pos: Vector3, yaw: float) -> void:
	var n := _group(name, pos, yaw)
	var canvas := _mat(Color(0.68, 0.62, 0.46))
	var floor_m := _mat(Color(0.34, 0.30, 0.26))
	var rope := _mat(Color(0.14, 0.13, 0.12))
	_box(n, Vector3(0, 0.05, 0), Vector3(2.2, 0.1, 2.2), floor_m)
	var lean_l := Basis(Vector3.FORWARD, deg_to_rad(54))
	var lean_r := Basis(Vector3.FORWARD, deg_to_rad(-54))
	_box(n, Vector3(-0.55, 0.88, 0), Vector3(0.07, 1.62, 2.2), canvas, false, lean_l)
	_box(n, Vector3(0.55, 0.88, 0), Vector3(0.07, 1.62, 2.2), canvas, false, lean_r)
	_box(n, Vector3(0, 1.52, 0), Vector3(2.0, 0.06, 2.0), canvas)
	for peg in [-1.0, 1.0]:
		_cyl(n, Vector3(peg * 1.05, 0.35, 1.05), 0.012, 0.7, rope, false, _align_y(Vector3(peg * 0.35, 0.55, 0.35)))
		_cyl(n, Vector3(peg * 1.05, 0.35, -1.05), 0.012, 0.7, rope, false, _align_y(Vector3(peg * 0.35, 0.55, -0.35)))


func _sheet_fence(name: String, pos: Vector3, yaw: float, graffiti := false) -> void:
	if not _room():
		return
	var n := _group(name, pos, yaw)
	var metal := _mat(Color(0.48, 0.50, 0.52), Color(0, 0, 0, 0), 1.0, TEX_CORRUGATED)
	var wood := _mat(Color(0.52, 0.38, 0.22), Color(0, 0, 0, 0), 1.0, TEX_PLANKS)
	var lean := Basis(Vector3.FORWARD, deg_to_rad(12.0 if graffiti else -8.0))
	_box(n, Vector3(0, 0.95, 0), Vector3(2.4, 1.9, 0.06), metal if not graffiti else wood, false, lean)
	if graffiti:
		_box(n, Vector3(0.35, 1.05, 0.05), Vector3(0.55, 0.42, 0.02), _mat(Color(0.92, 0.18, 0.55)), false, lean)


func _clothesline_ghetto(name: String, pos: Vector3, yaw: float) -> void:
	var n := _group(name, pos, yaw)
	var wood := _mat(Color(0.45, 0.28, 0.14), Color(0, 0, 0, 0), 1.0, TEX_PLANKS)
	var wire := _mat(Color(0.15, 0.14, 0.13))
	_box(n, Vector3(-2.8, 1.05, 0), Vector3(0.09, 2.1, 0.09), wood)
	_box(n, Vector3(2.8, 1.05, 0), Vector3(0.09, 2.1, 0.09), wood)
	var a := Vector3(-2.75, 2.05, 0)
	var mid := Vector3(0, 1.52, 0)
	var c := Vector3(2.75, 2.05, 0)
	_wire_seg(n, a, mid, wire)
	_wire_seg(n, mid, c, wire)
	var cols: Array[Color] = [
		Color(0.95, 0.35, 0.7), Color(0.25, 0.58, 0.32), Color(0.95, 0.55, 0.12),
		Color(0.22, 0.48, 0.82), Color(0.88, 0.22, 0.38),
	]
	var xs: Array[float] = [-1.6, -0.55, 0.55, 1.55, 0.0]
	for i in 5:
		_box(n, Vector3(xs[i], 1.22, 0), Vector3(0.52, 0.68, 0.035), _mat(cols[i]))


func _tv_antenna(pos: Vector3) -> void:
	var n := _group("ParkAntenna", pos, 22.0)
	var metal := _mat(Color(0.38, 0.38, 0.4))
	_cyl(n, Vector3(0, 0.55, 0), 0.018, 1.1, metal)
	_box(n, Vector3(0, 1.12, 0), Vector3(0.9, 0.04, 0.04), metal)
	_box(n, Vector3(0, 1.02, 0), Vector3(0.04, 0.04, 0.55), metal)
	_cyl(n, Vector3(0.38, 1.12, 0), 0.012, 0.38, metal, false, Basis(Vector3.FORWARD, deg_to_rad(90)))


func _mattress(name: String, pos: Vector3, yaw: float, lean := false) -> void:
	var n := _group(name, pos, yaw)
	var cloth := _mat(Color(0.58, 0.48, 0.38))
	var stain := _mat(Color(0.35, 0.28, 0.22))
	var basis := Basis(Vector3.FORWARD, deg_to_rad(-22.0)) if lean else Basis()
	_box(n, Vector3(0, 0.55 if lean else 0.12, 0), Vector3(1.85, 0.22, 0.95), cloth, false, basis)
	if lean:
		_box(n, Vector3(0.15, 0.42, 0.08), Vector3(0.65, 0.18, 0.55), stain, false, basis)


func _trash_bag(parent: Node3D, pos: Vector3, seed_i: int) -> void:
	var dark := _mat(Color(0.12, 0.11, 0.10))
	var squash := 0.72 + float(seed_i % 5) * 0.04
	_mi(parent, LowPoly.sphere(0.16, 8, 4, false, 0.12 * squash), pos + Vector3(0, 0.08 * squash, 0), dark)


func _puddle(name: String, pos: Vector3, r: float) -> void:
	var n := _group(name, pos)
	var wet := _mat_shiny(Color(0.14, 0.18, 0.24), 0.6, 0.1)
	_flat_disc(n, Vector3(0, 0.015, 0), r, wet)


func _oil_stain(name: String, pos: Vector3, r: float) -> void:
	var n := _group(name, pos)
	var oil := _mat_shiny(Color(0.12, 0.10, 0.08), 0.0, 0.3)
	_flat_disc(n, Vector3(0, 0.012, 0), r, oil)


func _paint_bucket(name: String, pos: Vector3, yaw: float, tipped := false) -> void:
	var n := _group(name, pos, yaw)
	var bucket_m := _mat(Color(0.32, 0.33, 0.35))
	if not tipped:
		_cyl(n, Vector3(0, 0.16, 0), 0.14, 0.32, bucket_m, false, Basis(), 0.16)
		_cyl(n, Vector3(0, 0.34, 0), 0.15, 0.04, _mat(Color(0.22, 0.22, 0.24)))
	else:
		var side := Basis(Vector3.FORWARD, deg_to_rad(88))
		_cyl(n, Vector3(0.12, 0.09, 0), 0.14, 0.32, bucket_m, false, side, 0.16)
		var mag := _mat(Color(0.86, 0.08, 0.52))
		_flat_disc(n, Vector3(0.42, 0.011, 0.08), 0.38, mag)
		_flat_disc(n, Vector3(0.58, 0.012, 0.18), 0.28, mag)


func _shopping_cart(name: String, pos: Vector3, yaw: float) -> void:
	if not _room():
		return
	var n := _group(name, pos, yaw)
	var wire := _mat(Color(0.55, 0.56, 0.58))
	var dark := _mat(Color(0.18, 0.18, 0.2))
	var wb := Basis(Vector3.FORWARD, deg_to_rad(90))
	_cyl(n, Vector3(-0.2, 0.42, 0), 0.018, 0.82, wire)
	_cyl(n, Vector3(0.2, 0.42, 0), 0.018, 0.82, wire)
	_cyl(n, Vector3(0, 0.42, -0.2), 0.018, 0.82, wire, false, Basis(Vector3.RIGHT, deg_to_rad(90)))
	_cyl(n, Vector3(0, 0.42, 0.2), 0.018, 0.82, wire, false, Basis(Vector3.RIGHT, deg_to_rad(90)))
	_cyl(n, Vector3(-0.2, 0.82, -0.2), 0.018, 0.42, wire)
	_cyl(n, Vector3(0.2, 0.82, -0.2), 0.018, 0.42, wire)
	_cyl(n, Vector3(0, 0.88, -0.2), 0.018, 0.38, wire, false, Basis(Vector3.RIGHT, deg_to_rad(18)))
	for wx in [-0.18, 0.18]:
		for wz in [-0.14, 0.14]:
			_cyl(n, Vector3(wx, 0.06, wz), 0.05, 0.04, dark, false, wb)


func _burnt_car(name: String, pos: Vector3, yaw: float) -> void:
	var b := _body(name, pos, yaw)
	b.rotate_object_local(Vector3.RIGHT, deg_to_rad(4.0))
	var blk := _mat(Color(0.07, 0.06, 0.05))
	var rust := _mat(Color(0.18, 0.12, 0.08), Color(0, 0, 0, 0), 1.0, TEX_RUST)
	_box(b, Vector3(0, 0.72, 0), Vector3(3.6, 0.65, 1.7), blk)
	_box(b, Vector3(-0.2, 1.28, 0), Vector3(1.8, 0.42, 1.5), rust)
	_box_col(b, Vector3(0, 0.85, 0), Vector3(3.6, 1.2, 1.7))
	var tire := _mat(Color(0.05, 0.05, 0.05))
	var wheel_basis := Basis(Vector3.BACK, deg_to_rad(90))
	var wxs: Array[float] = [-1.2, 1.2]
	var wzs: Array[float] = [-0.9, 0.9]
	for wx in wxs:
		for wz in wzs:
			_cyl(b, Vector3(wx, 0.28, wz), 0.32, 0.22, tire, false, wheel_basis)


func _shack(name: String, pos: Vector3, yaw: float, seed_i: int) -> void:
	if not _room():
		return
	var w := 3.8 + float(seed_i % 3) * 0.7
	var d := 4.2 + float((seed_i + 1) % 3) * 0.6
	var h := 2.6 + float(seed_i % 2) * 0.4
	var b := _body(name, pos, yaw)
	var wall_tex := TEX_CORRUGATED if seed_i % 2 == 0 else TEX_PLANKS
	var wall := _mat(Color(0.62, 0.48, 0.34), Color(0, 0, 0, 0), 1.0, wall_tex)
	var roof := _mat(Color(0.38, 0.22, 0.16))
	var glass := _mat(Color(0.55, 0.75, 0.9), Color(0.3, 0.45, 0.6), 0.5)
	_box(b, Vector3(0, h * 0.5, 0), Vector3(w, h, d), wall, true)
	if seed_i % 3 != 1:
		var pitch := Basis(Vector3.FORWARD, deg_to_rad(26))
		_box(b, Vector3(0, h + 0.35, 0), Vector3(w + 0.5, 0.12, d + 0.4), roof, false, pitch)
	else:
		_box(b, Vector3(0, h + 0.08, 0), Vector3(w + 0.2, 0.14, d + 0.2), roof)
	_box(b, Vector3(0, h * 0.42, d * 0.5 + 0.04), Vector3(0.75, 1.35, 0.05), _mat(Color(0.32, 0.20, 0.12)))
	var wx := -w * 0.22 if seed_i % 2 == 0 else w * 0.18
	_box(b, Vector3(wx, h * 0.55, d * 0.5 + 0.04), Vector3(0.65, 0.55, 0.04), glass)
	if seed_i % 2 == 0:
		_box(b, Vector3(w * 0.5 + 0.04, h * 0.55, 0.2), Vector3(0.65, 0.55, 0.04), glass)
	_cyl(b, Vector3(w * 0.42, 0.55, d * 0.42), 0.05, 1.1, _mat(Color(0.42, 0.28, 0.16), Color(0, 0, 0, 0), 1.0, TEX_PLANKS))
	_cyl(b, Vector3(w * 0.42, 0.55, d * 0.42 + 0.55), 0.05, 1.1, _mat(Color(0.42, 0.28, 0.16), Color(0, 0, 0, 0), 1.0, TEX_PLANKS))
	if seed_i % 3 == 0:
		_cyl(b, Vector3(-w * 0.35, h + 0.55, 0), 0.22, 0.55, _mat(Color(0.55, 0.32, 0.18), Color(0, 0, 0, 0), 1.0, TEX_RUST), false, Basis(), 0.08)
	elif seed_i % 3 == 1:
		_cyl(b, Vector3(w * 0.2, h + 0.35, -d * 0.2), 0.12, 0.85, _mat(Color(0.28, 0.26, 0.24)))
	_mark_enter(b, Vector3(0, 1.05, d * 0.5 + 0.55), "shack")


func _junk_cluster(name: String, pos: Vector3, yaw: float, seed_i: int) -> void:
	if not _room():
		return
	var n := _group(name, pos, yaw)
	_tire(n, Vector3(0, 0.08, 0), Basis(), 0.36)
	_cyl(n, Vector3(0.55, 0.38, 0.22), 0.22, 0.72, _mat(Color(0.55, 0.32, 0.16), Color(0, 0, 0, 0), 1.0, TEX_RUST))
	_box(n, Vector3(-0.35, 0.04, 0.35), Vector3(0.75, 0.08, 0.14), _mat(Color(0.52, 0.38, 0.22), Color(0, 0, 0, 0), 1.0, TEX_PLANKS), false, Basis(Vector3.UP, deg_to_rad(18.0)))
	_chair(name + "C", pos + Vector3(-0.4, 0, -0.35), yaw + 40.0)
	_cinder_pile(name + "B", pos + Vector3(0.42, 0, -0.28), yaw + 12.0)
	var bag := _group(name + "G", pos + Vector3(0.15, 0, 0.45), yaw)
	_trash_bag(bag, Vector3.ZERO, seed_i)


func _mat_fence_wire() -> StandardMaterial3D:
	var key := "wire_fence"
	if _mats.has(key):
		return _mats[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.52, 0.54, 0.56, 0.42)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.85
	_mats[key] = m
	return m


func _chain_fence(name: String, pos: Vector3, yaw: float, span := 4.2) -> void:
	if not _room():
		return
	var n := _group(name, pos, yaw)
	var post := _mat(Color(0.35, 0.36, 0.38))
	var wire := _mat_fence_wire()
	_cyl(n, Vector3(-span * 0.5, 0.55, 0), 0.035, 1.1, post)
	_cyl(n, Vector3(span * 0.5, 0.55, 0), 0.035, 1.1, post)
	_box(n, Vector3(0, 0.72, 0), Vector3(span, 0.9, 0.02), wire)


func _wood_fence(name: String, pos: Vector3, yaw: float, span := 3.8) -> void:
	if not _room():
		return
	var n := _group(name, pos, yaw)
	var white := _mat(Color(0.93, 0.91, 0.86))
	_box(n, Vector3(0, 0.42, 0), Vector3(span, 0.05, 0.04), white)
	for i in 5:
		var x := -span * 0.42 + float(i) * span * 0.21
		_box(n, Vector3(x, 0.5, 0), Vector3(0.07, 0.95, 0.04), white)


func _neighbor_trailer(name: String, pos: Vector3, yaw: float, seed_i: int) -> void:
	if not _room():
		return
	var w := 9.0 + float(seed_i % 2) * 0.8
	var h := 2.8
	var d := 3.0
	var b := _body(name, pos, yaw)
	var tex := TEX_TRAILER if seed_i % 2 == 0 else TEX_CORRUGATED
	var body_c := Color(0.82, 0.78, 0.68) if seed_i % 2 == 0 else Color(0.62, 0.58, 0.52)
	var body_m := _mat(body_c, Color(0, 0, 0, 0), 1.0, tex)
	var stripe_cols: Array[Color] = [Color(0.12, 0.55, 0.62), Color(0.82, 0.18, 0.42), Color(0.22, 0.48, 0.32)]
	var stripe := stripe_cols[seed_i % 3]
	var roof_m := _mat(Color(0.38, 0.24, 0.16))
	var glass := _mat(Color(0.55, 0.75, 0.9), Color(0.3, 0.45, 0.6), 0.5)
	_box(b, Vector3(0, h * 0.5, 0), Vector3(w, h, d), body_m, true)
	_box(b, Vector3(0, h + 0.06, 0), Vector3(w + 0.12, 0.12, d + 0.1), roof_m)
	_box(b, Vector3(0, h * 0.62, d * 0.5 + 0.03), Vector3(w * 0.92, 0.14, 0.05), _mat(stripe))
	_box(b, Vector3(w * 0.22, h + 0.18, -0.15), Vector3(0.55, 0.32, 0.42), _mat(Color(0.72, 0.74, 0.76)))
	var door_z := d * 0.5 + 0.04
	_box(b, Vector3(0, h * 0.42, door_z), Vector3(0.72, 1.45, 0.05), _mat(Color(0.32, 0.22, 0.14)))
	_box(b, Vector3(-w * 0.28, h * 0.58, door_z), Vector3(0.85, 0.62, 0.04), glass)
	_box(b, Vector3(w * 0.22, h * 0.58, door_z), Vector3(0.85, 0.62, 0.04), glass)
	_box(b, Vector3(0, 0.22, door_z + 0.08), Vector3(0.72, 0.44, 0.42), _mat(Color(0.48, 0.32, 0.18), Color(0, 0, 0, 0), 1.0, TEX_PLANKS))
	_cyl(b, Vector3(-w * 0.38, 0.42, -d * 0.35), 0.18, 0.72, _mat(Color(0.78, 0.72, 0.68)), false, Basis(), 0.16)
	var wood := _mat(Color(0.45, 0.28, 0.14), Color(0, 0, 0, 0), 1.0, TEX_PLANKS)
	_cyl(b, Vector3(w * 0.35, 1.85, door_z + 0.55), 0.045, 1.65, wood)
	_cyl(b, Vector3(w * 0.35 + 1.4, 1.85, door_z + 0.55), 0.045, 1.65, wood)
	_box(b, Vector3(w * 0.35 + 0.7, 2.55, door_z + 0.62), Vector3(1.5, 0.06, 0.55), _mat(Color(0.95, 0.55, 0.12)))
	_box(b, Vector3(w * 0.35 + 0.7, 2.48, door_z + 0.62), Vector3(1.5, 0.04, 0.55), _mat(Color(0.15, 0.42, 0.62)))
	if seed_i % 3 == 0:
		_box(b, Vector3(-w * 0.42, 0.12, door_z + 0.65), Vector3(1.1, 0.24, 0.85), _mat(Color(0.52, 0.38, 0.22), Color(0, 0, 0, 0), 1.0, TEX_PLANKS))
	_model(b, "trailer_rig_neighbor") # соседи тоже на колёсах: шасси, дышло, баллон
	_mark_enter(b, Vector3(0, 1.05, door_z + 0.55), "trailer")


func _mark_enter(b: StaticBody3D, local_pos: Vector3, kind: String) -> void:
	var m := Marker3D.new()
	m.name = "EnterDoor"
	m.position = local_pos
	m.set_meta("building_kind", kind)
	b.add_child(m)
	b.add_to_group("enterable_building")


func _neighbor_yard(name: String, pos: Vector3, yaw: float, seed_i: int) -> void:
	if not _room():
		return
	if seed_i % 2 == 0:
		_chain_fence(name + "F", pos + Vector3(0, 0, 2.2), yaw, 4.0)
	else:
		_wood_fence(name + "F", pos + Vector3(0, 0, 2.0), yaw, 3.6)
	_mailbox(name + "M", pos + Vector3(1.8, 0, 3.2), yaw + float(seed_i * 7))
	var props: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
	var p0: int = props[(seed_i * 3) % props.size()]
	var p1: int = props[(seed_i * 3 + 5) % props.size()]
	var off := Vector3(-1.6 + float(seed_i % 3) * 0.4, 0, 3.8)
	match p0:
		0: _sofa(name + "S", pos + off, yaw + 12.0)
		1: _tire_pile(name + "T", pos + off, yaw, false)
		2:
			var bg := _group(name + "B", pos + off, yaw)
			_trash_bag(bg, Vector3.ZERO, seed_i)
			_trash_bag(bg, Vector3(0.35, 0, 0.12), seed_i + 1)
		3: _mattress(name + "M2", pos + off, yaw, seed_i % 2 == 0)
		4: _clothesline_ghetto(name + "L", pos + off, yaw)
		5: _cinder_pile(name + "C", pos + off, yaw)
		6: _barrel(name + "Bar", pos + off, yaw)
		7: _pallet_out(name + "P", pos + off, yaw)
		8: _shopping_cart(name + "Cart", pos + off, yaw)
		9: _puddle(name + "Pd", pos + off, 0.75)
		10: _oil_stain(name + "Oil", pos + off, 0.55)
		11: _dish(name + "D", pos + off + Vector3(0, 2.85, 0), yaw, true)
	match p1:
		0: _flamingo(seed_i + 200, pos + Vector3(2.2, 0, 2.8), yaw + 20.0)
		1: _tire_pile(name + "T2", pos + Vector3(-2.0, 0, 3.5), yaw + 30.0, false)
		2: _barrel(name + "Bar2", pos + Vector3(0.8, 0, 4.2), yaw - 10.0)
		3: _crate(name + "Cr", pos + Vector3(-1.2, 0, 4.0), yaw, Vector3(0.52, 0.38, 0.48))
		_: _oil_stain(name + "O2", pos + Vector3(1.5, 0, 2.5), 0.45)


func _junk_heap(name: String, pos: Vector3, yaw: float, seed_i: int) -> void:
	if not _room():
		return
	var n := _group(name, pos, yaw)
	var cols: Array[Color] = [
		Color(0.55, 0.32, 0.16), Color(0.18, 0.42, 0.48), Color(0.42, 0.28, 0.18),
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = GHETTO_SEED + seed_i * 17
	for i in 8:
		var cm: Color = cols[i % cols.size()]
		var tex := TEX_RUST if i % 2 == 0 else TEX_CORRUGATED
		var m := _mat(cm, Color(0, 0, 0, 0), 1.0, tex)
		var ox := rng.randf_range(-0.9, 0.9)
		var oz := rng.randf_range(-0.8, 0.8)
		var oy := float(i) * 0.08
		if i % 3 == 0:
			_cyl(n, Vector3(ox, 0.12 + oy, oz), rng.randf_range(0.14, 0.28), rng.randf_range(0.12, 0.38), m, false, Basis(), rng.randf_range(0.1, 0.22))
		else:
			_box(n, Vector3(ox, 0.14 + oy, oz), Vector3(rng.randf_range(0.3, 0.75), rng.randf_range(0.12, 0.42), rng.randf_range(0.25, 0.65)), m, false, Basis(Vector3.UP, rng.randf_range(-0.5, 0.5)))


func _tire_stack10(name: String, pos: Vector3, yaw: float) -> void:
	if not _room():
		return
	var n := _group(name, pos, yaw)
	var rub := _mat(Color(0.08, 0.08, 0.09))
	var mm := MultiMeshInstance3D.new()
	var mm_res := MultiMesh.new()
	mm_res.transform_format = MultiMesh.TRANSFORM_3D
	mm_res.mesh = LowPoly.cylinder(0.36, 0.36, 0.14, 8)
	mm_res.instance_count = 9
	var idx := 0
	for row in 3:
		for col in 3:
			if idx >= 9:
				break
			var ox := float(col - 1) * 0.42 + float(row) * 0.04
			var oz := float(row) * 0.38
			var oy := 0.08 + float(row) * 0.15
			mm_res.set_instance_transform(idx, Transform3D(Basis.IDENTITY, Vector3(ox, oy, oz)))
			idx += 1
	mm.multimesh = mm_res
	mm.material_override = rub
	n.add_child(mm)
	_mesh_count += 1


func _broken_tv(name: String, pos: Vector3, yaw: float) -> void:
	var n := _group(name, pos, yaw)
	var shell := _mat(Color(0.22, 0.22, 0.24))
	var crack := _mat(Color(0.12, 0.14, 0.18))
	_box(n, Vector3(0, 0.42, 0), Vector3(0.95, 0.72, 0.42), shell)
	_box(n, Vector3(0, 0.42, 0.22), Vector3(0.82, 0.58, 0.03), crack)
	_box(n, Vector3(0.12, 0.52, 0.24), Vector3(0.04, 0.32, 0.02), _mat(Color(0.35, 0.36, 0.38)))


func _rolled_carpet(name: String, pos: Vector3, yaw: float) -> void:
	var n := _group(name, pos, yaw)
	var rug := _mat(Color(0.62, 0.38, 0.22), Color(0, 0, 0, 0), 1.0, TEX_RUG)
	_cyl(n, Vector3(0, 0.18, 0), 0.22, 0.36, rug, false, Basis(Vector3.FORWARD, deg_to_rad(90)))


func _bathtub(name: String, pos: Vector3, yaw: float) -> void:
	var n := _group(name, pos, yaw)
	var white := _mat(Color(0.88, 0.89, 0.86))
	var inner := _mat(Color(0.72, 0.74, 0.76))
	_box(n, Vector3(0, 0.28, 0), Vector3(1.55, 0.56, 0.72), white)
	_box(n, Vector3(0, 0.34, 0.02), Vector3(1.25, 0.38, 0.52), inner)


func _lawn_chair(name: String, pos: Vector3, yaw: float) -> void:
	var n := _group(name, pos, yaw)
	var plastic := _mat(Color(0.15, 0.52, 0.68) if int(yaw) % 2 == 0 else Color(0.88, 0.35, 0.55))
	var metal := _mat(Color(0.35, 0.36, 0.38))
	_box(n, Vector3(0, 0.38, 0), Vector3(0.48, 0.05, 0.46), plastic)
	_box(n, Vector3(0, 0.62, -0.18), Vector3(0.48, 0.42, 0.05), plastic, false, Basis(Vector3.RIGHT, deg_to_rad(-16)))
	_cyl(n, Vector3(-0.18, 0.18, 0.16), 0.018, 0.36, metal)
	_cyl(n, Vector3(0.18, 0.18, 0.16), 0.018, 0.36, metal)


func _bbq_grill(name: String, pos: Vector3, yaw: float) -> void:
	var n := _group(name, pos, yaw)
	var blk := _mat(Color(0.12, 0.12, 0.13))
	var coal := _mat(Color(0.18, 0.16, 0.14))
	_cyl(n, Vector3(0, 0.42, 0), 0.28, 0.84, blk, false, Basis(), 0.22)
	_cyl(n, Vector3(0, 0.88, 0), 0.32, 0.06, blk)
	_box(n, Vector3(0, 0.78, 0), Vector3(0.55, 0.04, 0.55), coal)


func _bicycle_lean(pos: Vector3, yaw: float) -> void:
	var n := _group("GhettoBike", pos, yaw)
	var metal := _mat(Color(0.45, 0.46, 0.48))
	var lean := Basis(Vector3.FORWARD, deg_to_rad(72))
	_cyl(n, Vector3(0, 0.55, 0), 0.018, 1.05, metal, false, lean)
	_cyl(n, Vector3(0.35, 0.35, 0.08), 0.32, 0.04, metal, false, Basis(Vector3.FORWARD, deg_to_rad(90)))
	_cyl(n, Vector3(-0.08, 0.12, 0.22), 0.14, 0.04, metal, false, Basis(Vector3.FORWARD, deg_to_rad(90)))
	_cyl(n, Vector3(0.42, 0.12, -0.08), 0.14, 0.04, metal, false, Basis(Vector3.FORWARD, deg_to_rad(90)))


func _dog_house(name: String, pos: Vector3, yaw: float) -> void:
	var n := _group(name, pos, yaw)
	var wood := _mat(Color(0.52, 0.36, 0.2), Color(0, 0, 0, 0), 1.0, TEX_PLANKS)
	_box(n, Vector3(0, 0.28, 0), Vector3(0.85, 0.56, 0.72), wood)
	_box(n, Vector3(0, 0.62, 0), Vector3(0.95, 0.12, 0.82), wood, false, Basis(Vector3.FORWARD, deg_to_rad(28)))
	_box(n, Vector3(0, 0.22, 0.38), Vector3(0.32, 0.32, 0.05), _mat(Color(0.18, 0.14, 0.12)))


func _shack_near(name: String, pos: Vector3, yaw: float, variant: int) -> void:
	if not _room():
		return
	var w := 4.2 + float(variant % 3) * 0.6
	var d := 4.8 + float((variant + 1) % 2) * 0.5
	var h := 2.8 + float(variant % 2) * 0.5
	var b := _body(name, pos, yaw)
	var wall_tex := TEX_CORRUGATED if variant % 2 == 0 else TEX_PLANKS
	var wall := _mat(Color(0.58, 0.46, 0.32), Color(0, 0, 0, 0), 1.0, wall_tex)
	var roof := _mat(Color(0.35, 0.20, 0.14))
	var glass := _mat(Color(0.55, 0.75, 0.9), Color(0.3, 0.45, 0.6), 0.5)
	match variant % 4:
		0:
			_box(b, Vector3(0, h * 0.5, 0), Vector3(w, h, d), wall, true)
			_box(b, Vector3(0, h + 0.32, 0), Vector3(w + 0.4, 0.12, d + 0.35), roof, false, Basis(Vector3.FORWARD, deg_to_rad(26)))
			_cyl(b, Vector3(w * 0.3, h + 0.75, 0), 0.1, 0.65, _mat(Color(0.28, 0.26, 0.24)))
		1:
			_box(b, Vector3(0, h * 0.5, 0), Vector3(w, h, d), wall, true)
			_box(b, Vector3(0, h + 0.08, 0), Vector3(w + 0.15, 0.14, d + 0.12), roof)
			_box(b, Vector3(0, h + 1.05, 0), Vector3(w * 0.82, 1.35, d * 0.82), wall)
			_box(b, Vector3(0, h + 1.85, 0), Vector3(w * 0.72, 0.12, d * 0.72), roof)
		2:
			_box(b, Vector3(0, h * 0.5, 0), Vector3(w, h, d), wall, true)
			_box(b, Vector3(0, h + 0.08, 0), Vector3(w + 0.15, 0.14, d + 0.12), roof)
			_box(b, Vector3(0, h * 0.38, d * 0.5 + 0.04), Vector3(w * 0.72, 1.15, 0.06), _mat(Color(0.42, 0.44, 0.46), Color(0, 0, 0, 0), 1.0, TEX_CORRUGATED))
		3:
			_box(b, Vector3(0, h * 0.5, 0), Vector3(w, h, d), wall, true)
			_box(b, Vector3(0, h + 0.08, 0), Vector3(w + 0.15, 0.14, d + 0.12), roof)
			for leg in [-0.35, 0.35]:
				_cyl(b, Vector3(leg * w, h + 0.55, 0), 0.05, 1.1, _mat(Color(0.35, 0.34, 0.32)))
			_cyl(b, Vector3(0, h + 1.35, 0), 0.42, 0.55, _mat(Color(0.55, 0.32, 0.18), Color(0, 0, 0, 0), 1.0, TEX_RUST), false, Basis(), 0.35)
	_box(b, Vector3(-w * 0.2, h * 0.55, d * 0.5 + 0.04), Vector3(0.62, 0.52, 0.04), glass)
	_box(b, Vector3(0, h * 0.42, d * 0.5 + 0.04), Vector3(0.68, 1.25, 0.05), _mat(Color(0.30, 0.18, 0.12)))
	_mark_enter(b, Vector3(0, 1.0, d * 0.5 + 0.55), "shack")


func _build_neighbors() -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = GHETTO_SEED + 77
	var tp := _trailer_xz()
	var placed: Array[Vector2] = []
	var built := 0
	var guard := 0
	while built < 9 and guard < 200 and _room():
		guard += 1
		var ang := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(17.0, 33.0)
		var x := tp.x + cos(ang) * dist
		var z := tp.y + sin(ang) * dist
		if not _neighbor_ok(x, z, 5.5, placed):
			continue
		var yaw := rad_to_deg(ang) + 90.0 + rng.randf_range(-25.0, 25.0)
		_neighbor_trailer("Neighbor%d" % built, Vector3(x, 0, z), yaw, built)
		_neighbor_yard("NeighborYard%d" % built, Vector3(x, 0, z), yaw, built)
		placed.append(Vector2(x, z))
		built += 1
	return built


func _build_horizon_near() -> int:
	_horizon_placed.clear()
	var tp := _trailer_xz()
	## art_00 / art_01 look past trailer toward +x / −z (see ArtShot.gd)
	var view := Vector2(0.707, -0.707).normalized()
	var perp := Vector2(-view.y, view.x)
	var rng := RandomNumberGenerator.new()
	rng.seed = GHETTO_SEED + 311
	var built := 0
	var guard := 0
	while built < 9 and guard < 140 and _room():
		guard += 1
		var dist := rng.randf_range(38.0, 56.0)
		var lat := rng.randf_range(-14.0, 14.0)
		var p := tp + view * dist + perp * lat
		if not _horizon_ok(p.x, p.y, 2.5):
			continue
		var yaw := rad_to_deg(atan2(view.x, view.y)) + rng.randf_range(-30.0, 30.0)
		_shack_near("NearShack%d" % built, Vector3(p.x, 0, p.y), yaw, built)
		_horizon_placed.append(p)
		built += 1
	if built >= 2 and _room():
		var wires := _group("NearShackWires", Vector3.ZERO)
		var a := _pole("NearPole0", Vector3(tp.x + view.x * 42.0, 0, tp.y + view.y * 42.0), 0.0)
		var b := _pole("NearPole1", Vector3(tp.x + view.x * 50.0 + perp.x * 8.0, 0, tp.y + view.y * 50.0 + perp.y * 8.0), 0.0)
		_span_wires(wires, a, b)
	return built


func _dress_yard_dense() -> void:
	if _yard_ok(-8.5, -22.5, 0.8):
		_junk_heap("YardHeap0", Vector3(-8.5, 0, -22.5), 35.0, 0)
	if _yard_ok(9.5, -20.8, 0.8):
		_junk_heap("YardHeap1", Vector3(9.5, 0, -20.8), -20.0, 1)
	if _yard_ok(-5.5, -24.2, 0.6):
		_tire_stack10("YardTires10", Vector3(-5.5, 0, -24.2), 15.0)
	if _yard_ok(7.8, -23.5, 0.5):
		_broken_tv("YardTV", Vector3(7.8, 0, -23.5), -12.0)
	if _yard_ok(-3.2, -25.8, 0.45):
		_rolled_carpet("YardRug", Vector3(-3.2, 0, -25.8), 22.0)
	if _yard_ok(11.2, -22.0, 0.55):
		_bathtub("YardTub", Vector3(11.2, 0, -22.0), -8.0)
	if _yard_ok(3.5, -25.2, 0.35):
		_lawn_chair("YardChair0", Vector3(3.5, 0, -25.2), 40.0)
	if _yard_ok(5.2, -24.8, 0.35):
		_lawn_chair("YardChair1", Vector3(5.2, 0, -24.8), -25.0)
	if _yard_ok(-6.8, -20.5, 0.45):
		_bbq_grill("YardBBQ", Vector3(-6.8, 0, -20.5), 18.0)
	if _yard_ok(-4.5, -11.8, 0.35):
		_bicycle_lean(Vector3(-4.5, 0, -11.8), 75.0)
	if _yard_ok(10.8, -18.5, 0.5):
		_dog_house("YardDog", Vector3(10.8, 0, -18.5), -15.0)
	var bag2 := _group("YardBags", Vector3.ZERO)
	var bag2_pts: Array[Vector3] = [
		Vector3(-7.2, 0, -21.8), Vector3(-2.8, 0, -23.2), Vector3(6.5, 0, -21.5),
		Vector3(8.8, 0, -24.5), Vector3(-9.5, 0, -19.2), Vector3(12.2, 0, -20.8),
	]
	var bi2 := 0
	for bp in bag2_pts:
		if _yard_ok(bp.x, bp.z, 0.22):
			_trash_bag(bag2, bp, bi2)
			bi2 += 1
	var card2_pts: Array[Vector3] = [
		Vector3(-10.2, 0, -22.8), Vector3(-6.5, 0, -24.5), Vector3(4.2, 0, -22.2),
		Vector3(9.8, 0, -23.8), Vector3(-1.5, 0, -26.2), Vector3(13.5, 0, -21.2),
	]
	for i in card2_pts.size():
		var cp: Vector3 = card2_pts[i]
		if _yard_ok(cp.x, cp.z, 0.35):
			_crate("YardCard%d" % i, cp, float(i * 19 - 8), Vector3(0.52, 0.38, 0.48))


func _dress_ghetto() -> void:
	var g0 := _mesh_count
	_dress_yard_dense()
	var neighbors := _build_neighbors()
	var near_shacks := _build_horizon_near()
	## --- yard pack (within ~35 m of trailer) ---
	if _park_ok(16.2, -18.4, 1.0):
		_sofa_stained("GhettoSofa1", Vector3(16.2, 0, -18.4), -28.0)
	if _park_ok(-19.5, -5.8, 1.2):
		_tent("GhettoTent0", Vector3(-19.5, 0, -5.8), 35.0)
	if _park_ok(22.8, -22.5, 1.2):
		_tent("GhettoTent1", Vector3(22.8, 0, -22.5), -18.0)
	if _park_ok(28.5, -19.8, 0.6):
		_tire_pile("GhettoTires1", Vector3(28.5, 0, -19.8), -12.0, false)
	if _park_ok(-20.8, 3.5, 0.6):
		_cinder_pile("GhettoCinder0", Vector3(-20.8, 0, 3.5), 22.0)
	if _park_ok(11.5, -28.2, 0.6):
		_cinder_pile("GhettoCinder1", Vector3(11.5, 0, -28.2), -15.0)
	var fences: Array[Vector4] = [
		Vector4(-28.5, -24.0, 90.0, 0.0), Vector4(30.2, -10.5, -75.0, 1.0),
		Vector4(-12.8, 24.5, 12.0, 0.0), Vector4(25.5, 8.0, -105.0, 1.0),
	]
	for i in fences.size():
		var f: Vector4 = fences[i]
		if _park_ok(f.x, f.y, 0.4):
			_sheet_fence("GhettoFence%d" % i, Vector3(f.x, 0, f.y), f.z, int(f.w) == 1)
	if _park_ok(-22.5, 12.8, 1.5):
		_clothesline_ghetto("GhettoLine", Vector3(-22.5, 0, 12.8), 8.0)
	_dish("GhettoDish0", Vector3(1.8, 3.02, -12.1), -35.0, true)
	_dish("GhettoDish1", Vector3(-3.4, 3.02, -11.6), 48.0, true)
	_tv_antenna(Vector3(0.6, 2.85, -12.8))
	if _park_ok(12.5, -25.8, 0.5):
		_shopping_cart("GhettoCart", Vector3(12.5, 0, -25.8), 42.0)
	if _park_ok(4.8, -11.2, 0.6):
		_mattress("GhettoMatt0", Vector3(4.8, 0, -11.2), 90.0, true)
	if _park_ok(-15.8, 6.2, 0.6):
		_mattress("GhettoMatt1", Vector3(-15.8, 0, 6.2), -20.0, false)
	var bags := _group("GhettoBags", Vector3.ZERO)
	var bag_pts: Array[Vector3] = [
		Vector3(-17.2, 0, -16.5), Vector3(-11.8, 0, -22.8), Vector3(8.5, 0, -24.2),
		Vector3(18.8, 0, -12.5), Vector3(-24.5, 0, -2.5), Vector3(26.2, 0, -6.8),
		Vector3(-6.5, 0, 18.5), Vector3(14.2, 0, 14.8),
	]
	var bi := 0
	for bp in bag_pts:
		if _park_ok(bp.x, bp.z, 0.25):
			_trash_bag(bags, bp, bi)
			bi += 1
	var crates: Array[Vector3] = [Vector3(-21.5, 0, -12.8), Vector3(19.5, 0, -15.2), Vector3(-9.5, 0, 22.5)]
	for i in crates.size():
		var cp: Vector3 = crates[i]
		if _park_ok(cp.x, cp.z, 0.4):
			_crate("GhettoCard%d" % i, cp, float(i * 29 - 10), Vector3(0.58, 0.42, 0.55))
	var puddle_rs: Array[float] = [1.1, 0.9, 1.8, 1.4, 2.0, 0.85]
	var puddle_pts: Array[Vector3] = [
		Vector3(-13.5, 0, -18.2), Vector3(7.2, 0, -20.5), Vector3(-25.2, 0, 8.5),
		Vector3(20.5, 0, -8.2), Vector3(-8.5, 0, 16.2), Vector3(16.8, 0, 6.5),
	]
	for i in mini(puddle_pts.size(), puddle_rs.size()):
		var pp: Vector3 = puddle_pts[i]
		if _park_ok(pp.x, pp.z, 0.2):
			_puddle("GhettoPuddle%d" % i, pp, puddle_rs[i])
	var oil_pts: Array[Vector3] = [Vector3(-18.8, 0, -8.5), Vector3(24.2, 0, -14.5), Vector3(-5.5, 0, 24.8)]
	for i in oil_pts.size():
		var op: Vector3 = oil_pts[i]
		if _park_ok(op.x, op.z, 0.2):
			_oil_stain("GhettoOil%d" % i, op, 0.75 + float(i) * 0.18)
	if _park_ok(-14.5, 19.5, 2.5):
		_burnt_car("GhettoBurnt", Vector3(-14.5, 0, 19.5), 65.0)
	var pal_pts: Array[Vector3] = [Vector3(-22.8, 0, -15.5), Vector3(18.2, 0, -8.5), Vector3(-7.8, 0, 27.5)]
	for i in pal_pts.size():
		var pp2: Vector3 = pal_pts[i]
		if _park_ok(pp2.x, pp2.z, 0.55):
			_pallet_out("GhettoPal%d" % i, pp2, float(i * 24))
	if _park_ok(-16.5, -10.2, 0.2):
		_paint_bucket("GhettoPaint0", Vector3(-16.5, 0, -10.2), 15.0, false)
	if _park_ok(20.2, -17.5, 0.2):
		_paint_bucket("GhettoPaint1", Vector3(20.2, 0, -17.5), -22.0, false)
	if _park_ok(-23.8, 15.2, 0.3):
		_paint_bucket("GhettoPaint2", Vector3(-23.8, 0, 15.2), 48.0, true)
	## extra perimeter clutter (reads in art_00 / wide shots)
	if _park_ok(-27.5, -8.5, 0.5):
		_tire_pile("GhettoTires2", Vector3(-27.5, 0, -8.5), 40.0, false)
	if _park_ok(26.8, -4.2, 0.5):
		_barrel("GhettoBarrelY", Vector3(26.8, 0, -4.2), -30.0)
	if _park_ok(-25.5, 18.5, 0.5):
		_pallet_out("GhettoPalY0", Vector3(-25.5, 0, 18.5), 15.0)
	if _park_ok(23.5, 14.2, 0.5):
		_crate("GhettoCardY", Vector3(23.5, 0, 14.2), -8.0, Vector3(0.55, 0.4, 0.52))
	if _park_ok(10.5, 22.5, 0.5):
		_cart("GhettoCartY", Vector3(10.5, 0, 22.5), -55.0)
	if _park_ok(-30.5, 2.5, 0.5):
		_sheet_fence("GhettoFenceY", Vector3(-30.5, 0, 2.5), 0.0, true)
	if _park_ok(31.2, -18.5, 0.4):
		_oil_stain("GhettoOilY", Vector3(31.2, 0, -18.5), 0.95)
	if _park_ok(-18.5, 26.5, 0.3):
		_puddle("GhettoPuddleY", Vector3(-18.5, 0, 26.5), 1.6)
	## --- horizon shacks (45–90 m, wasteland only) ---
	var rng := RandomNumberGenerator.new()
	rng.seed = GHETTO_SEED
	var tp := _trailer_xz()
	var shack_angles: Array[float] = [0.35, 0.95, 1.65, 2.35, 3.05, 3.75, 4.45, 5.15]
	var shack_dists: Array[float] = [58.0, 64.0, 70.0, 76.0, 62.0, 68.0, 74.0, 80.0]
	var shack_n := 0
	for i in mini(shack_angles.size(), shack_dists.size()):
		if not _room():
			break
		var ang: float = shack_angles[i]
		var dist: float = shack_dists[i]
		var x := tp.x + cos(ang) * dist
		var z := tp.y + sin(ang) * dist
		if not _wasteland_ok(x, z):
			continue
		if Vector2(x, z).distance_to(tp) < 45.0 or Vector2(x, z).distance_to(tp) > 92.0:
			continue
		var yaw := rad_to_deg(ang) + 90.0 + float(i * 11 - 22)
		_shack("HorizonShack%d" % shack_n, Vector3(x, 0, z), yaw, shack_n)
		shack_n += 1
	var guard := 0
	while shack_n < 12 and guard < 100 and _room():
		guard += 1
		var ang2 := rng.randf_range(0.0, TAU)
		var dist2 := rng.randf_range(48.0, 88.0)
		var x2 := tp.x + cos(ang2) * dist2
		var z2 := tp.y + sin(ang2) * dist2
		if not _wasteland_ok(x2, z2):
			continue
		if Vector2(x2, z2).distance_to(tp) < 45.0 or Vector2(x2, z2).distance_to(tp) > 92.0:
			continue
		_shack("HorizonShack%d" % shack_n, Vector3(x2, 0, z2), rad_to_deg(ang2) + 90.0, shack_n)
		shack_n += 1
	## --- wasteland junk clusters between districts ---
	var cluster_n := 0
	guard = 0
	while cluster_n < 20 and guard < 320 and _room():
		guard += 1
		var x2 := rng.randf_range(-150.0, 150.0)
		var z2 := rng.randf_range(-135.0, 165.0)
		if not _wasteland_ok(x2, z2):
			continue
		if Vector2(x2, z2).distance_to(tp) < 38.0:
			continue
		_junk_cluster("WasteJunk%d" % cluster_n, Vector3(x2, 0, z2), rng.randf_range(0.0, 180.0), cluster_n)
		cluster_n += 1
	if OS.is_debug_build():
		print("[Props] ghetto added=%d neighbors=%d near_shacks=%d far_shacks=%d clusters=%d" % [_mesh_count - g0, neighbors, near_shacks, shack_n, cluster_n])


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
	var seg_len := d.length()
	if seg_len < 4.0:
		return
	var mid := (a + b) * 0.5
	mid.y = 0.012
	var yaw := atan2(d.x, d.z)
	var basis := Basis(Vector3.UP, yaw)
	var side := basis * Vector3(0.8, 0, 0)
	_box(n, mid + side, Vector3(0.4, 0.02, seg_len), dirt, false, basis)
	_box(n, mid - side, Vector3(0.4, 0.02, seg_len), dirt, false, basis)


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
	_ad_board("AdCasinoHwy", Vector3(84.0, 0, 36.0), 8.0, TEX_AD_CASINO) # 9 м от обеих осей: опоры не на дороге
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
