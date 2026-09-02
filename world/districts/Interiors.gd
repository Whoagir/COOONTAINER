class_name Interiors
extends RefCounted
## Процедурная обстановка районов: хлам, лампы, прилавки. Вызывается из CityDress
## один раз после материалов. Дети района — узел Interior (идемпотентно).

const TEX := "res://assets/textures/"
const CLEAR := 1.2
const MAX_MESH := 900
const MAX_LIGHT := 16
const MARKER_CLEAR := [
	"PlayerStand", "Auctioneer", "PreviewSpot",
	"PlayerSpot", "NpcSpot", "DealerSpot", "LocksmithSpot",
	"TrailerDoor", "PotSlot", "CasinoPotSlot", "Bribe",
	"JailCell", "JailDoor", "EvidenceDoor", "EvidenceRoom",
	"CopSpawn0", "CopSpawn1", "CopSpawn2", "PoliceCarSpawn",
]

static var _mats: Dictionary = {}
static var _texs: Dictionary = {}
static var _mesh_n := 0
static var _light_n := 0
static var _root: Node3D
static var _dist: District
static var _keep: Array = []


static func dress(world: Node) -> int:
	_mesh_n = 0
	_light_n = 0
	_mats.clear()
	if world == null:
		return 0
	var city: Node = world.get("city") as Node
	if city == null or not city.has_method("districts"):
		return 0
	var districts: Array = city.call("districts") as Array
	for raw in districts:
		var d := raw as District
		if d == null:
			continue
		if d.get_node_or_null("Interior") != null:
			continue
		_dress_one(d, world)
	if OS.is_debug_build():
		print("[Interiors] meshes=%d lights=%d" % [_mesh_n, _light_n])
	return _mesh_n


static func _dress_one(d: District, world: Node) -> void:
	_dist = d
	_root = Node3D.new()
	_root.name = "Interior"
	d.add_child(_root)
	_collect_keepouts(d, world)
	match d.district_id:
		Types.District.HANGAR:
			_hangar()
		Types.District.STORAGE:
			_storage()
		Types.District.GARAGES:
			_garages()
		Types.District.VENDORS:
			_vendors()
		Types.District.CASINO:
			_casino()
		Types.District.POLICE:
			_police()
		Types.District.PORT:
			_port()
		Types.District.TRAILER_PARK:
			_trailer(world)
		Types.District.CAR_MARKET:
			_carmarket()
		Types.District.LOCKSMITH:
			_locksmith()


# ------------------------------------------------------------------ keep-out

static func _collect_keepouts(d: District, world: Node) -> void:
	_keep.clear()
	for raw in d.lot_anchors():
		var a := raw as LotAnchor
		if a == null:
			continue
		var cell_n: Node3D = a.cell()
		var cs: Vector3 = a.cell_size
		_keep.append({
			"k": "box",
			"xf": cell_n.global_transform,
			"h": Vector3(cs.x * 0.5 + CLEAR, cs.y + 1.0, cs.z * 0.5 + CLEAR),
		})
		if a.has_door:
			var front: Vector3 = cell_n.global_transform * Vector3(0.0, 0.2, cs.z * 0.5 + 0.9)
			_sph(front, CLEAR + 0.15)
			var door_n := a.get_node_or_null("Door") as Node3D
			if door_n:
				_sph(door_n.global_position, CLEAR)
		for hn in a.hunter_spots():
			var h := hn as Node3D
			if h:
				_sph(h.global_position, CLEAR)
		for mn in MARKER_CLEAR:
			var mk: Node3D = a.get_node_or_null(mn) as Node3D
			if mk:
				_sph(mk.global_position, CLEAR)
	for mn2 in MARKER_CLEAR:
		var m2: Node3D = d.marker(mn2)
		if m2:
			_sph(m2.global_position, CLEAR)
	for i in 4:
		var bed: Node3D = d.marker("Bed%d" % i)
		if bed:
			_keep.append({
				"k": "box",
				"xf": bed.global_transform,
				"h": Vector3(0.7 + CLEAR, 1.2, 1.2 + CLEAR),
			})
	for si in 4:
		var slot: Node3D = d.marker("CarSlot%d" % si)
		if slot:
			_sph(slot.global_position, 2.2)
	if d.district_id == Types.District.TRAILER_PARK:
		_trailer_keepouts(world)


static func _trailer_keepouts(world: Node) -> void:
	var pot: Node3D = null
	if world.has_method("find_marker"):
		pot = world.call("find_marker", Types.District.TRAILER_PARK, "PotSlot") as Node3D
	if pot == null:
		pot = _dist.marker("PotSlot")
	if pot:
		_sph(pot.global_position, CLEAR + 0.2)
	# проход от кроватей к двери (+Z)
	var door: Node3D = _dist.marker("TrailerDoor")
	var b0: Node3D = _dist.marker("Bed0")
	if door and b0:
		var a: Vector3 = b0.global_position + Vector3(1.6, 0.0, 0.4)
		var b: Vector3 = door.global_position
		for t in 6:
			_sph(a.lerp(b, float(t) / 5.0), CLEAR)


static func _sph(p: Vector3, r: float) -> void:
	_keep.append({"k": "sph", "p": p, "r": r})


static func _blocked(local: Vector3, rad := 0.45, roads := true) -> bool:
	if _dist == null:
		return true
	var wpos: Vector3 = _dist.to_global(local)
	for raw in _keep:
		var k: Dictionary = raw as Dictionary
		var kind := str(k.get("k", ""))
		if kind == "sph":
			var p: Vector3 = k["p"] as Vector3
			var r: float = float(k.get("r", CLEAR))
			var d := wpos - p
			d.y = 0.0
			if d.length() < r + rad:
				return true
		elif kind == "box":
			var xf: Transform3D = k["xf"] as Transform3D
			var h: Vector3 = k["h"] as Vector3
			var loc: Vector3 = xf.affine_inverse() * wpos
			if absf(loc.x) <= h.x + rad and absf(loc.z) <= h.z + rad and loc.y >= -0.6 and loc.y <= h.y + 1.0:
				return true
	if roads and _on_road(wpos.x, wpos.z):
		return true
	return false


static func _on_road(x: float, z: float) -> bool:
	var hw := 5.4
	if absf(x) <= 165.0 + hw:
		if absf(z + 60.0) <= hw or absf(z - 45.0) <= hw or absf(z - 110.0) <= hw:
			return true
	var segs: Array[Vector4] = [
		Vector4(-165, -60, -165, 110), Vector4(165, -60, 165, 110), Vector4(0, 45, 0, 135),
		Vector4(-75, -60, -75, 45), Vector4(75, -60, 75, 45), Vector4(0, -100, 0, -60),
		Vector4(120, -100, 120, -60), Vector4(-110, -100, -110, -60),
		Vector4(110, 45, 110, 64), Vector4(-120, 45, -120, 64),
	]
	for s in segs:
		if absf(x - s.x) <= hw and z >= minf(s.y, s.w) - hw and z <= maxf(s.y, s.w) + hw:
			return true
	return false


# ------------------------------------------------------------------ materials / prims

static func _tex(name: String) -> Texture2D:
	if _texs.has(name):
		return _texs[name] as Texture2D
	var p := TEX + name + ".png"
	var t: Texture2D = null
	if ResourceLoader.exists(p):
		t = load(p) as Texture2D
	_texs[name] = t
	return t


static func _mat(col: Color, tex := "", emit := Color(0, 0, 0, 0), emit_e := 1.0, rough := 0.88, uv := 2.0) -> StandardMaterial3D:
	var key := "%s|%s|%s|%.2f|%.2f|%.2f" % [col.to_html(false), tex, emit.to_html(), emit_e, rough, uv]
	if _mats.has(key):
		return _mats[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = 0.0
	if emit.a > 0.0:
		m.emission_enabled = true
		m.emission = emit
		m.emission_energy_multiplier = emit_e
	if tex != "":
		var t := _tex(tex)
		if t:
			m.albedo_texture = t
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_scale = Vector3.ONE / uv
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_mats[key] = m
	return m


static func _face_mat(tex_name: String, tint := Color(1, 1, 1)) -> StandardMaterial3D:
	var key := "face|%s|%s" % [tex_name, tint.to_html(false)]
	if _mats.has(key):
		return _mats[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.roughness = 0.9
	var t := _tex(tex_name)
	if t:
		m.albedo_texture = t
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_mats[key] = m
	return m


static func _grp(name: String, pos: Vector3, yaw := 0.0, collide := false, col_size := Vector3.ZERO) -> Node3D:
	var n: Node3D
	if collide:
		var b := StaticBody3D.new()
		b.collision_layer = Types.L_WORLD
		b.collision_mask = 0
		n = b
	else:
		n = Node3D.new()
	n.name = name
	n.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), pos)
	_root.add_child(n)
	if collide and col_size != Vector3.ZERO:
		_box_col(n, Vector3(0, col_size.y * 0.5, 0), col_size)
	return n


static func _mi(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material, basis := Basis()) -> MeshInstance3D:
	if _mesh_n >= MAX_MESH or mesh == null:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = Transform3D(basis, pos)
	parent.add_child(mi)
	_mesh_n += 1
	return mi


static func _box_col(parent: Node3D, pos: Vector3, size: Vector3, basis := Basis()) -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.transform = Transform3D(basis, pos)
	parent.add_child(cs)


static func _cyl_col(parent: Node3D, pos: Vector3, r: float, h: float) -> void:
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = r
	sh.height = h
	cs.shape = sh
	cs.position = pos
	parent.add_child(cs)


static func _box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, basis := Basis()) -> void:
	var sm := minf(size.x, minf(size.y, size.z))
	var mesh: Mesh
	if sm < 0.06:
		var bm := BoxMesh.new()
		bm.size = size
		mesh = bm
	else:
		mesh = LowPoly.chamfer_box(size, minf(0.045, sm * 0.16))
	_mi(parent, mesh, pos, mat, basis)


static func _flat(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, basis := Basis()) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	_mi(parent, bm, pos, mat, basis)


static func _cyl(parent: Node3D, pos: Vector3, r: float, h: float, mat: Material, basis := Basis(), rt := -1.0) -> void:
	var top := r if rt < 0.0 else rt
	_mi(parent, LowPoly.cylinder(top, r, h, 8), pos, mat, basis)


static func _sph_m(parent: Node3D, pos: Vector3, r: float, mat: Material) -> void:
	_mi(parent, LowPoly.sphere(r, 8, 4), pos, mat)


static func _align_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var x := y.cross(Vector3.UP)
	if x.length_squared() < 0.0001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	return Basis(x, y, x.cross(y).normalized())


static func _light(parent: Node3D, pos: Vector3, col: Color, energy: float, rng: float) -> void:
	if _light_n >= MAX_LIGHT:
		return
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = minf(rng, 12.0)
	l.omni_attenuation = 1.15
	l.shadow_enabled = false
	l.light_specular = 0.15
	l.position = pos
	parent.add_child(l)
	_light_n += 1


# ------------------------------------------------------------------ shared props

static func _pallet_stack(name: String, pos: Vector3, yaw: float, n_boxes := 3) -> void:
	if _blocked(pos, 0.7):
		return
	var g := _grp(name, pos, yaw, true, Vector3(1.15, 0.95, 0.95))
	var wood := _mat(Color(0.72, 0.55, 0.32), "tex_planks", Color(0, 0, 0, 0), 1.0, 0.9, 1.4)
	var card := _mat(Color(0.82, 0.68, 0.42), "tex_cardboard", Color(0, 0, 0, 0), 1.0, 0.95, 1.2)
	_box(g, Vector3(0, 0.07, 0), Vector3(1.2, 0.12, 1.0), wood)
	var y := 0.18
	for i in n_boxes:
		var ox := float((i * 3) % 5 - 2) * 0.04
		var oz := float((i * 5) % 5 - 2) * 0.03
		var sx := 0.42 + float(i % 3) * 0.08
		var sy := 0.28 + float((i + 1) % 2) * 0.08
		var sz := 0.38 + float(i % 2) * 0.1
		_box(g, Vector3(ox, y + sy * 0.5, oz), Vector3(sx, sy, sz), card)
		y += sy


static func _tyre_stack(name: String, pos: Vector3, yaw: float) -> void:
	if _blocked(pos, 0.5):
		return
	var g := _grp(name, pos, yaw, true, Vector3(0.85, 0.72, 0.85))
	var rub := _mat(Color(0.09, 0.09, 0.1))
	_cyl(g, Vector3(0, 0.08, 0), 0.4, 0.16, rub)
	_cyl(g, Vector3(0.03, 0.24, 0.02), 0.39, 0.16, rub)
	_cyl(g, Vector3(-0.04, 0.40, 0.01), 0.38, 0.16, rub)
	_cyl(g, Vector3(0.05, 0.22, 0.28), 0.36, 0.15, rub, Basis(Vector3.RIGHT, deg_to_rad(78)))


static func _bunting(name: String, a: Vector3, b: Vector3, n := 8, c0 := Color(0.92, 0.22, 0.48), c1 := Color(0.95, 0.78, 0.15)) -> void:
	var g := _grp(name, Vector3.ZERO)
	var wire := _mat(Color(0.18, 0.16, 0.14))
	var d := b - a
	var len := d.length()
	if len < 0.3:
		return
	_cyl(g, (a + b) * 0.5, 0.012, len, wire, _align_y(d))
	for i in n:
		var t := (float(i) + 0.5) / float(n)
		var p: Vector3 = a.lerp(b, t)
		p.y -= 0.12 + absf(t - 0.5) * 0.18
		var col := c0 if i % 2 == 0 else c1
		var yaw := atan2(d.x, d.z)
		_flat(g, p, Vector3(0.22, 0.28, 0.02), _mat(col), Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(12)))


static func _hang_lamp(name: String, pos: Vector3, lit: bool) -> void:
	var g := _grp(name, pos)
	var metal := _mat(Color(0.22, 0.2, 0.18))
	var glow := _mat(Color(1.0, 0.88, 0.55), "", Color(1.0, 0.82, 0.4), 3.2, 0.35)
	_cyl(g, Vector3(0, 0.7, 0), 0.018, 1.5, metal)
	_cyl(g, Vector3(0, 0.02, 0), 0.42, 0.32, metal, Basis(), 0.08)
	_sph_m(g, Vector3(0, -0.12, 0), 0.11, glow)
	if lit:
		_light(g, Vector3(0, -0.28, 0), Color(1.0, 0.86, 0.62), 1.25, 11.5)


static func _crate(parent: Node3D, pos: Vector3, size: Vector3, yaw := 0.0) -> void:
	var wood := _mat(Color(0.7, 0.52, 0.3), "tex_planks", Color(0, 0, 0, 0), 1.0, 0.9, 1.3)
	_box(parent, pos, size, wood, Basis(Vector3.UP, deg_to_rad(yaw)))


static func _crate_tower(name: String, pos: Vector3, yaw: float, n := 4) -> void:
	if _blocked(pos, 0.7):
		return
	var g := _grp(name, pos, yaw, true, Vector3(1.15, 1.85, 1.0))
	var wood := _mat(Color(0.7, 0.52, 0.3), "tex_planks", Color(0, 0, 0, 0), 1.0, 0.9, 1.4)
	_box(g, Vector3(0, 0.07, 0), Vector3(1.2, 0.12, 1.05), wood)
	var tints: Array[Color] = [
		Color(0.82, 0.68, 0.42), Color(0.7, 0.55, 0.32), Color(0.75, 0.62, 0.38), Color(0.88, 0.72, 0.48),
	]
	var y := 0.16
	for i in n:
		var tint: Color = tints[i % tints.size()]
		var card := _mat(tint, "tex_cardboard", Color(0, 0, 0, 0), 1.0, 0.95, 1.15)
		var sx := 0.88 - float(i % 3) * 0.08
		var sy := 0.4 + float(i % 2) * 0.07
		var sz := 0.74 - float((i + 1) % 3) * 0.06
		var ox := float((i * 3) % 5 - 2) * 0.05
		var oz := float((i * 2) % 5 - 2) * 0.04
		_box(g, Vector3(ox, y + sy * 0.5, oz), Vector3(sx, sy, sz), card)
		y += sy


static func _barrels(name: String, pos: Vector3, yaw: float) -> void:
	if _blocked(pos, 0.55):
		return
	var g := _grp(name, pos, yaw, true, Vector3(0.95, 0.9, 0.7))
	var rust := _mat(Color(0.55, 0.32, 0.16), "tex_rust_teal")
	var blue := _mat(Color(0.2, 0.38, 0.55), "tex_rust_teal")
	_cyl(g, Vector3(-0.22, 0.42, 0), 0.22, 0.82, rust)
	_cyl(g, Vector3(0.24, 0.38, 0.06), 0.2, 0.74, blue)


static func _dumpster(name: String, pos: Vector3, yaw: float) -> void:
	if _blocked(pos, 0.85):
		return
	var g := _grp(name, pos, yaw, true, Vector3(1.7, 1.15, 0.95))
	var teal := _mat(Color(0.22, 0.42, 0.4), "tex_rust_teal", Color(0, 0, 0, 0), 1.0, 0.65, 2.0)
	_box(g, Vector3(0, 0.55, 0), Vector3(1.65, 1.05, 0.9), teal)
	_box(g, Vector3(0, 1.12, 0), Vector3(1.7, 0.08, 0.95), _mat(Color(0.18, 0.32, 0.3), "tex_corrugated"))
	_box(g, Vector3(-0.72, 0.7, 0.48), Vector3(0.08, 0.22, 0.06), _mat(Color(0.2, 0.2, 0.2)))


static func _fold_chair(name: String, pos: Vector3, yaw: float) -> void:
	if _blocked(pos, 0.35):
		return
	var g := _grp(name, pos, yaw)
	var metal := _mat(Color(0.35, 0.36, 0.38))
	var seat := _mat(Color(0.15, 0.28, 0.42))
	_box(g, Vector3(0, 0.42, 0), Vector3(0.4, 0.04, 0.38), seat)
	_box(g, Vector3(0, 0.68, -0.16), Vector3(0.4, 0.48, 0.04), seat)
	_box(g, Vector3(-0.16, 0.22, 0.12), Vector3(0.03, 0.4, 0.03), metal)
	_box(g, Vector3(0.16, 0.22, 0.12), Vector3(0.03, 0.4, 0.03), metal)


# ------------------------------------------------------------------ districts

static func _hangar() -> void:
	var wood := _mat(Color(0.7, 0.52, 0.3), "tex_planks")
	var card := _mat(Color(0.8, 0.66, 0.4), "tex_cardboard")
	# паллеты у боковых стен, вдали от лотов (z ≈ −12)
	var lefts: Array[Vector3] = [
		Vector3(-20.4, 0, -17.6), Vector3(-20.4, 0, -1.2), Vector3(-20.4, 0, 3.6), Vector3(-20.2, 0, 9.4),
		Vector3(-14.8, 0, 7.6), Vector3(-12.6, 0, 5.2),
	]
	var rights: Array[Vector3] = [
		Vector3(20.4, 0, -17.4), Vector3(20.4, 0, -1.8), Vector3(20.3, 0, 3.2), Vector3(20.2, 0, 6.4),
		Vector3(13.8, 0, 7.2), Vector3(11.4, 0, 5.0),
	]
	for i in lefts.size():
		_pallet_stack("PalL%d" % i, lefts[i], 90.0, 3 + i % 2)
	for i in rights.size():
		_pallet_stack("PalR%d" % i, rights[i], -90.0, 2 + i % 3)
	# лампы под крышей — крупнее, ближе к центру кадра
	var lamps: Array[Vector3] = [
		Vector3(-8.0, 6.6, 2.0), Vector3(0.0, 6.7, 1.2), Vector3(8.0, 6.6, 2.0),
		Vector3(-5.0, 6.55, 6.4), Vector3(5.0, 6.55, 6.4),
	]
	for i in lamps.size():
		_hang_lamp("Lamp%d" % i, lamps[i], true)
	_forklift("Forklift", Vector3(8.4, 0, 7.2), -28.0)
	_bunting("BuntBack", Vector3(-17.5, 6.6, -14.2), Vector3(17.5, 6.6, -14.2), 11)
	_bunting("BuntMid", Vector3(-16.0, 6.45, 2.0), Vector3(16.0, 6.45, 2.0), 10, Color(0.2, 0.62, 0.7), Color(0.95, 0.45, 0.15))
	# касса у аукциониста лота 1, за подиумом у задней стены
	if not _blocked(Vector3(-1.6, 0, -16.4), 0.7):
		var tab := _grp("CashTable", Vector3(-1.6, 0, -16.4), 8.0, true, Vector3(1.15, 0.78, 0.55))
		_box(tab, Vector3(0, 0.38, 0), Vector3(1.1, 0.06, 0.52), wood)
		_box(tab, Vector3(-0.48, 0.18, 0), Vector3(0.06, 0.36, 0.48), wood)
		_box(tab, Vector3(0.48, 0.18, 0), Vector3(0.06, 0.36, 0.48), wood)
		var cash := _mat(Color(0.22, 0.24, 0.22))
		_box(tab, Vector3(0.12, 0.48, 0.02), Vector3(0.28, 0.14, 0.2), cash)
		_flat(tab, Vector3(0.12, 0.56, 0.02), Vector3(0.22, 0.02, 0.14), _mat(Color(0.15, 0.55, 0.22)))
		_coffee_urn(tab, Vector3(-0.32, 0.41, 0.0))
	_tyre_stack("HangTires", Vector3(-10.8, 0, 7.0), 18.0)
	_tyre_stack("HangTires2", Vector3(15.2, 0, 4.4), -12.0)
	# ряды коробок вдоль стен (камера смотрит с +Z в дверь)
	var wall_z: Array[float] = [-18.2, -15.6, -13.2, -6.4, -3.8, -1.2, 1.4, 3.8, 6.2, 8.6]
	for i in wall_z.size():
		_crate_tower("WL%d" % i, Vector3(-20.55, 0, wall_z[i]), 90.0, 4 + i % 2)
		_crate_tower("WR%d" % i, Vector3(20.55, 0, wall_z[i]), -90.0, 3 + (i + 1) % 2)
	# входные кучи — читаются с порога, центр зала свободен
	_crate_tower("EntL0", Vector3(-16.4, 0, 7.6), 8.0, 5)
	_crate_tower("EntL1", Vector3(-18.6, 0, 8.8), -12.0, 4)
	_crate_tower("EntR0", Vector3(16.2, 0, 7.4), -14.0, 5)
	_dumpster("HangDump", Vector3(18.4, 0, 8.6), -8.0)
	_barrels("HangBar0", Vector3(-17.2, 0, 6.4), 20.0)
	_barrels("HangBar1", Vector3(12.6, 0, 8.2), -15.0)
	_fold_chair("ChairL0", Vector3(-17.6, 0, 2.2), 95.0)
	_fold_chair("ChairL1", Vector3(-17.4, 0, 3.4), 88.0)
	_fold_chair("ChairR0", Vector3(17.5, 0, 2.4), -92.0)
	_fold_chair("ChairR1", Vector3(17.3, 0, 3.6), -85.0)
	_bunting("BuntDoor", Vector3(-15.0, 5.8, 8.2), Vector3(15.0, 5.8, 8.2), 10, Color(0.95, 0.2, 0.25), Color(0.95, 0.85, 0.15))
	# потёртости пола
	var scuff := _mat(Color(0.12, 0.1, 0.09, 0.85))
	var scuffs: Array[Vector4] = [
		Vector4(-8.2, 0.012, 1.4, 22.0), Vector4(6.4, 0.012, 2.2, -15.0),
		Vector4(0.5, 0.012, 6.8, 40.0), Vector4(-14.0, 0.012, 5.0, 8.0),
		Vector4(12.5, 0.012, -0.8, -30.0), Vector4(-3.2, 0.012, 8.5, 55.0),
		Vector4(4.8, 0.012, 7.6, 12.0), Vector4(-6.0, 0.012, 7.2, -28.0),
	]
	var sg := _grp("Scuffs", Vector3.ZERO)
	for s in scuffs:
		if _blocked(Vector3(s.x, 0, s.z), 0.2):
			continue
		_flat(sg, Vector3(s.x, s.y, s.z), Vector3(1.8, 0.012, 0.6), scuff, Basis(Vector3.UP, deg_to_rad(s.w)))
	# постеры
	if not _blocked(Vector3(0.0, 0, -19.4), 0.2):
		var pg := _grp("Poster", Vector3(0.0, 2.4, -19.55), 0.0)
		_flat(pg, Vector3.ZERO, Vector3(1.4, 1.6, 0.03), _face_mat("tex_poster_auction"))
	var side_p := _grp("SidePoster", Vector3(-21.85, 2.55, 4.2), 90.0)
	_flat(side_p, Vector3.ZERO, Vector3(1.2, 1.5, 0.03), _face_mat("tex_poster_auction"))
	var fly := _grp("SideFlyer", Vector3(21.85, 2.2, 5.0), -90.0)
	_flat(fly, Vector3.ZERO, Vector3(0.7, 0.9, 0.02), _face_mat("tex_flyer_hamster"))
	var extra := _grp("HangExtra", Vector3.ZERO)
	if not _blocked(Vector3(-8.4, 0, 6.2), 0.4):
		_box(extra, Vector3(-8.4, 0.28, 6.2), Vector3(0.62, 0.52, 0.5), card)
		_box(extra, Vector3(-8.1, 0.68, 6.35), Vector3(0.4, 0.28, 0.36), card)
	if not _blocked(Vector3(7.2, 0, 4.8), 0.35):
		_box(extra, Vector3(7.2, 0.24, 4.8), Vector3(0.55, 0.42, 0.48), card)
	_crate_tower("PalMid0", Vector3(-8.6, 0, 5.2), 12.0, 4)
	_crate_tower("PalMid1", Vector3(4.6, 0, 5.0), -18.0, 3)
	_tyre_stack("HangTires3", Vector3(-3.4, 0, 8.6), 40.0)


static func _coffee_urn(parent: Node3D, pos: Vector3) -> void:
	var steel := _mat(Color(0.55, 0.56, 0.58), "", Color(0, 0, 0, 0), 1.0, 0.35)
	var black := _mat(Color(0.12, 0.1, 0.09))
	_cyl(parent, pos + Vector3(0, 0.22, 0), 0.11, 0.42, steel)
	_cyl(parent, pos + Vector3(0, 0.44, 0), 0.12, 0.04, black)
	_box(parent, pos + Vector3(0.13, 0.18, 0), Vector3(0.08, 0.04, 0.04), steel)


static func _forklift(name: String, pos: Vector3, yaw: float) -> void:
	if _blocked(pos, 1.1):
		return
	var g := _grp(name, pos, yaw, true, Vector3(2.05, 1.15, 1.05))
	var yel := _mat(Color(0.92, 0.72, 0.12))
	var org := _mat(Color(0.88, 0.42, 0.1))
	var blk := _mat(Color(0.1, 0.1, 0.11))
	var gry := _mat(Color(0.35, 0.36, 0.38))
	_box(g, Vector3(-0.15, 0.62, 0), Vector3(1.55, 0.7, 0.95), yel)
	_box(g, Vector3(-0.55, 1.15, 0), Vector3(0.7, 0.55, 0.88), org)
	_flat(g, Vector3(-0.55, 1.22, 0.42), Vector3(0.5, 0.28, 0.03), _mat(Color(0.35, 0.7, 0.85), "", Color(0.3, 0.55, 0.7), 0.6))
	_box(g, Vector3(0.72, 1.15, 0), Vector3(0.14, 2.15, 0.42), gry)
	_box(g, Vector3(1.28, 0.22, -0.22), Vector3(1.05, 0.07, 0.12), gry)
	_box(g, Vector3(1.28, 0.22, 0.22), Vector3(1.05, 0.07, 0.12), gry)
	var wb := Basis(Vector3.FORWARD, deg_to_rad(90))
	_cyl(g, Vector3(-0.55, 0.22, 0.48), 0.22, 0.16, blk, wb)
	_cyl(g, Vector3(-0.55, 0.22, -0.48), 0.22, 0.16, blk, wb)
	_cyl(g, Vector3(0.45, 0.2, 0.48), 0.2, 0.16, blk, wb)
	_cyl(g, Vector3(0.45, 0.2, -0.48), 0.2, 0.16, blk, wb)


static func _storage() -> void:
	var metal := _mat(Color(0.42, 0.44, 0.48), "tex_rust_teal", Color(0, 0, 0, 0), 1.0, 0.55, 2.2)
	var plank := _mat(Color(0.55, 0.42, 0.28), "tex_planks")
	# стеллажи по торцам коридора
	var racks: Array[Vector4] = [
		Vector4(-10.6, 0, -2.4, 90.0), Vector4(-10.6, 0, 2.6, 90.0),
		Vector4(10.6, 0, -2.2, -90.0), Vector4(10.6, 0, 2.8, -90.0),
	]
	for i in racks.size():
		var r: Vector4 = racks[i]
		var p := Vector3(r.x, 0, r.z)
		if _blocked(p, 0.55):
			continue
		var g := _grp("Rack%d" % i, p, r.w, true, Vector3(1.35, 2.05, 0.48))
		for yv in [0.35, 1.05, 1.75]:
			_box(g, Vector3(0, yv, 0), Vector3(1.3, 0.04, 0.42), plank)
		_box(g, Vector3(-0.62, 1.05, 0), Vector3(0.05, 2.05, 0.42), metal)
		_box(g, Vector3(0.62, 1.05, 0), Vector3(0.05, 2.05, 0.42), metal)
		_box(g, Vector3(-0.2, 0.55, 0.02), Vector3(0.28, 0.22, 0.22), _mat(Color(0.78, 0.62, 0.38), "tex_cardboard"))
		_box(g, Vector3(0.25, 1.22, 0.0), Vector3(0.32, 0.18, 0.2), _mat(Color(0.35, 0.42, 0.55)))
	# рамы роллет у дверей ячеек (на фасаде, без коллизии в проходе)
	var lots: Array = _dist.lot_anchors()
	var fi := 0
	for raw in lots:
		var a := raw as LotAnchor
		if a == null or not a.has_door:
			continue
		var cell_n: Node3D = a.cell()
		var cs: Vector3 = a.cell_size
		var local_front := Vector3(0.0, 1.25, cs.z * 0.5 + 0.06)
		var wpos: Vector3 = cell_n.global_transform * local_front
		var lp: Vector3 = _dist.to_local(wpos)
		var yaw := rad_to_deg(cell_n.global_transform.basis.get_euler().y - _dist.global_transform.basis.get_euler().y)
		var fr := _grp("DoorFrame%d" % fi, lp, yaw)
		var rust := _mat(Color(0.38, 0.4, 0.42), "tex_corrugated", Color(0, 0, 0, 0), 1.0, 0.7, 2.0)
		_box(fr, Vector3(-cs.x * 0.52, 0.15, 0), Vector3(0.08, 2.55, 0.1), rust)
		_box(fr, Vector3(cs.x * 0.52, 0.15, 0), Vector3(0.08, 2.55, 0.1), rust)
		_box(fr, Vector3(0, 1.38, 0), Vector3(cs.x + 0.16, 0.1, 0.1), rust)
		_flat(fr, Vector3(0, 1.55, 0.04), Vector3(0.28, 0.18, 0.02), _mat(Color(0.15, 0.15, 0.16)))
		fi += 1
	# тележка уборщика
	if not _blocked(Vector3(9.4, 0, 0.2), 0.55):
		var cart := _grp("Cart", Vector3(9.4, 0, 0.2), -12.0, true, Vector3(0.75, 0.95, 0.48))
		var yel := _mat(Color(0.9, 0.78, 0.15))
		_box(cart, Vector3(0, 0.42, 0), Vector3(0.7, 0.55, 0.42), yel)
		_box(cart, Vector3(-0.22, 0.85, 0), Vector3(0.06, 0.7, 0.06), _mat(Color(0.25, 0.25, 0.26)))
		_cyl(cart, Vector3(0.18, 0.95, 0.02), 0.04, 1.15, _mat(Color(0.45, 0.32, 0.18)))
		_box(cart, Vector3(0.18, 1.52, 0.02), Vector3(0.18, 0.08, 0.04), _mat(Color(0.55, 0.55, 0.5)))
		_cyl(cart, Vector3(0.22, 0.22, 0.28), 0.12, 0.22, _mat(Color(0.2, 0.45, 0.75)), Basis(), 0.14)
	_pallet_stack("StorCard0", Vector3(-9.6, 0, -4.6), 15.0, 4)
	_pallet_stack("StorCard1", Vector3(9.5, 0, 4.8), -20.0, 3)
	_pallet_stack("StorCard2", Vector3(-8.8, 0, 4.2), -8.0, 3)
	_pallet_stack("StorCard3", Vector3(8.2, 0, -3.8), 22.0, 2)
	# северный двор — камеры смотрят с +Z на спину ряда B
	_crate_tower("StorYard0", Vector3(-11.2, 0, 12.4), 18.0, 4)
	_crate_tower("StorYard1", Vector3(10.8, 0, 13.2), -12.0, 5)
	_crate_tower("StorYard2", Vector3(-6.4, 0, 14.6), 6.0, 3)
	_crate_tower("StorYard3", Vector3(5.2, 0, 15.0), -22.0, 4)
	_dumpster("StorDump", Vector3(13.6, 0, 11.8), -90.0)
	_barrels("StorBar0", Vector3(-13.4, 0, 11.2), 10.0)
	_barrels("StorBar1", Vector3(0.8, 0, 13.8), -8.0)
	_tyre_stack("StorTires", Vector3(-14.2, 0, 14.8), 30.0)
	# в кадре ground-камеры (6,1.7,10) → origin: торец коридора справа
	# не ближе 2 м к (9, 0, 9): там стоит NPC-пикап (Vehicles.NPC_CARS), иначе он спавнится на бочках
	_crate_tower("StorCam0", Vector3(12.9, 0, 5.2), -18.0, 4)
	_barrels("StorCam1", Vector3(12.6, 0, 8.6), 22.0)
	_pallet_stack("StorCam2", Vector3(-8.8, 0, 6.8), 14.0, 3)
	# огнетушитель + камера
	var wall := _grp("WallKit", Vector3(-10.85, 0, 0.0), 90.0)
	var red := _mat(Color(0.82, 0.12, 0.12))
	_cyl(wall, Vector3(0, 1.15, 0.08), 0.07, 0.42, red)
	_cyl(wall, Vector3(0, 1.38, 0.08), 0.03, 0.08, _mat(Color(0.15, 0.15, 0.16)))
	var cam := _grp("Cam", Vector3(0.0, 3.15, 0.0), 0.0)
	var blk := _mat(Color(0.12, 0.12, 0.13))
	_box(cam, Vector3(0, 0, -0.08), Vector3(0.08, 0.06, 0.22), blk)
	_box(cam, Vector3(0, -0.04, 0.12), Vector3(0.16, 0.1, 0.18), blk)
	_cyl(cam, Vector3(0, -0.04, 0.22), 0.04, 0.08, _mat(Color(0.2, 0.2, 0.22), "", Color(0.6, 0.1, 0.1), 1.2))


static func _garages() -> void:
	var oil := _mat(Color(0.08, 0.06, 0.04))
	var stains: Array[Vector3] = [
		Vector3(-8.2, 0.012, 3.4), Vector3(-2.6, 0.012, 4.1), Vector3(3.0, 0.012, 3.2), Vector3(8.6, 0.012, 4.6),
		Vector3(1.2, 0.012, 6.2), Vector3(-5.4, 0.012, 7.0),
	]
	var sg := _grp("Oil", Vector3.ZERO)
	for s in stains:
		if _blocked(s, 0.2):
			continue
		_cyl(sg, s, 0.95, 0.014, oil, Basis(), 0.55)
		_cyl(sg, s + Vector3(0.35, 0.0, 0.22), 0.55, 0.012, oil, Basis(), 0.32)
	if not _blocked(Vector3(-13.2, 0, 3.6), 0.7):
		var wb := _grp("Workbench", Vector3(-13.2, 0, 3.6), 90.0, true, Vector3(1.55, 0.92, 0.62))
		var wood := _mat(Color(0.42, 0.3, 0.18), "tex_planks")
		var steel := _mat(Color(0.4, 0.42, 0.44))
		_box(wb, Vector3(0, 0.78, 0), Vector3(1.5, 0.08, 0.58), wood)
		_box(wb, Vector3(-0.65, 0.38, 0), Vector3(0.08, 0.76, 0.54), steel)
		_box(wb, Vector3(0.65, 0.38, 0), Vector3(0.08, 0.76, 0.54), steel)
		# гаечный ключ / молоток
		_box(wb, Vector3(-0.25, 0.86, 0.08), Vector3(0.38, 0.04, 0.08), steel)
		_cyl(wb, Vector3(-0.42, 0.86, 0.08), 0.05, 0.04, steel, Basis(Vector3.FORWARD, deg_to_rad(90)))
		_box(wb, Vector3(0.35, 0.88, -0.1), Vector3(0.06, 0.05, 0.32), _mat(Color(0.35, 0.22, 0.12)))
		_box(wb, Vector3(0.35, 0.9, 0.12), Vector3(0.14, 0.08, 0.08), steel)
		_jerry(wb, Vector3(0.52, 0.42, 0.28))
	_tyre_stack("GarTires", Vector3(10.4, 0, 7.2), -18.0)
	_tyre_stack("GarTires2", Vector3(-9.6, 0, 7.6), 25.0)
	_tyre_stack("GarTires3", Vector3(-13.6, 0, 8.8), 8.0)
	_pallet_stack("GarPal", Vector3(7.4, 0, 8.2), 12.0, 3)
	_pallet_stack("GarPal2", Vector3(-4.2, 0, 8.0), -14.0, 3)
	_pallet_stack("GarPal3", Vector3(2.8, 0, 7.4), 8.0, 2)
	_crate_tower("GarYard0", Vector3(-12.6, 0, 9.4), 16.0, 4)
	_crate_tower("GarYard1", Vector3(12.2, 0, 10.2), -10.0, 3)
	_dumpster("GarDump", Vector3(14.4, 0, 7.6), 90.0)
	_barrels("GarBar0", Vector3(-14.2, 0, 6.2), 22.0)
	_barrels("GarBar1", Vector3(5.6, 0, 10.6), -18.0)
	if not _blocked(Vector3(12.8, 0, 8.4), 0.7):
		var pal := _grp("EnginePal", Vector3(12.8, 0, 8.4), 25.0, true, Vector3(1.05, 0.85, 0.85))
		_box(pal, Vector3(0, 0.07, 0), Vector3(1.05, 0.12, 0.85), _mat(Color(0.65, 0.48, 0.28), "tex_planks"))
		var iron := _mat(Color(0.22, 0.22, 0.24), "tex_rust_teal", Color(0, 0, 0, 0), 1.0, 0.45, 1.6)
		_box(pal, Vector3(0, 0.42, 0), Vector3(0.72, 0.48, 0.5), iron)
		_cyl(pal, Vector3(-0.22, 0.62, 0.18), 0.06, 0.22, iron)
		_cyl(pal, Vector3(0.22, 0.62, 0.18), 0.06, 0.22, iron)
	# переноска
	if not _blocked(Vector3(-13.0, 0, 2.2), 0.2):
		var tl := _grp("Trouble", Vector3(-13.0, 2.85, 2.2), 0.0)
		var cage := _mat(Color(0.55, 0.35, 0.1))
		_cyl(tl, Vector3(0, 0.35, 0), 0.01, 0.7, _mat(Color(0.15, 0.15, 0.15)))
		_cyl(tl, Vector3(0, 0.0, 0), 0.12, 0.16, cage, Basis(), 0.08)
		_sph_m(tl, Vector3(0, -0.06, 0), 0.06, _mat(Color(1, 0.9, 0.55), "", Color(1, 0.85, 0.4), 2.0))
		_light(tl, Vector3(0, -0.2, 0), Color(1.0, 0.82, 0.5), 0.85, 8.0)
	# календарь на торце ряда
	var cal := _grp("Calendar", Vector3(-11.35, 1.7, -2.8), 90.0)
	_flat(cal, Vector3.ZERO, Vector3(0.42, 0.55, 0.02), _face_mat("tex_flyer_hamster"))


static func _jerry(parent: Node3D, pos: Vector3) -> void:
	var red := _mat(Color(0.75, 0.18, 0.1))
	_box(parent, pos, Vector3(0.22, 0.32, 0.16), red)
	_box(parent, pos + Vector3(0, 0.2, 0), Vector3(0.08, 0.06, 0.08), _mat(Color(0.15, 0.15, 0.15)))


static func _vendors() -> void:
	var stands: Array[Dictionary] = [
		{"n": "tiny", "p": Vector3(-9, 0, -15.2), "a": Color(0.92, 0.28, 0.22), "b": Color(0.95, 0.88, 0.7)},
		{"n": "antique", "p": Vector3(-3, 0, -15.2), "a": Color(0.28, 0.45, 0.28), "b": Color(0.9, 0.78, 0.4)},
		{"n": "household", "p": Vector3(3, 0, -15.2), "a": Color(0.2, 0.45, 0.75), "b": Color(0.95, 0.85, 0.35)},
		{"n": "tech", "p": Vector3(9, 0, -15.2), "a": Color(0.15, 0.15, 0.18), "b": Color(0.2, 0.85, 0.9)},
		{"n": "dark", "p": Vector3(3, 0, -21.1), "a": Color(0.35, 0.12, 0.4), "b": Color(0.85, 0.55, 0.15)},
	]
	var i := 0
	for s in stands:
		var p: Vector3 = s["p"] as Vector3
		_vendor_stall(str(s["n"]), p, s["a"] as Color, s["b"] as Color, i)
		i += 1
	# площадь перед лавками — видна с аэро-камеры
	_crate_tower("VenPlaza0", Vector3(-14.2, 0, -8.2), 12.0, 4)
	_crate_tower("VenPlaza1", Vector3(14.4, 0, -7.6), -16.0, 3)
	_dumpster("VenDump", Vector3(-16.2, 0, -4.4), 8.0)
	_barrels("VenBar0", Vector3(15.6, 0, -3.8), -20.0)
	_barrels("VenBar1", Vector3(-12.8, 0, -5.2), 14.0)


static func _vendor_stall(name: String, origin: Vector3, c0: Color, c1: Color, seed_i: int) -> void:
	# навес над прилавком, ящики сбоку (не на PlayerSpot +Z)
	var awn := _grp("Awning_" + name, origin + Vector3(0, 2.18, 0.35))
	for k in 7:
		var col := c0 if k % 2 == 0 else c1
		_flat(awn, Vector3(-1.2 + float(k) * 0.4, 0, 0.55), Vector3(0.38, 0.1, 2.15), _mat(col), Basis(Vector3.RIGHT, deg_to_rad(-16)))
	var crate_p := origin + Vector3(-1.35, 0, 0.15)
	if not _blocked(crate_p, 0.4):
		var cg := _grp("Crates_" + name, crate_p, 12.0 + float(seed_i * 7), true, Vector3(0.7, 0.7, 0.7))
		_crate(cg, Vector3(0, 0.22, 0), Vector3(0.55, 0.42, 0.5))
		_crate(cg, Vector3(0.08, 0.52, 0.04), Vector3(0.4, 0.22, 0.38), 18.0)
		if seed_i == 0 or seed_i == 3:
			_box(cg, Vector3(0.02, 0.7, 0.0), Vector3(0.16, 0.1, 0.12), _mat(Color(0.25, 0.22, 0.2)))
			_cyl(cg, Vector3(0.02, 0.78, 0.0), 0.05, 0.06, _mat(Color(0.4, 0.42, 0.38)))
	var side := origin + Vector3(1.2, 0, 0.35)
	if not _blocked(side, 0.35):
		var ch := _grp("Chair_" + name, side, -25.0)
		var plastic := _mat(Color(0.2, 0.55, 0.62) if seed_i % 2 == 0 else Color(0.85, 0.35, 0.55))
		_box(ch, Vector3(0, 0.38, 0), Vector3(0.42, 0.05, 0.4), plastic)
		_box(ch, Vector3(0, 0.62, -0.16), Vector3(0.42, 0.42, 0.05), plastic)
		_cyl(ch, Vector3(-0.15, 0.18, 0.14), 0.02, 0.34, _mat(Color(0.4, 0.4, 0.4)))
		_cyl(ch, Vector3(0.15, 0.18, 0.14), 0.02, 0.34, _mat(Color(0.4, 0.4, 0.4)))
	# весы + ценник
	var kit := _grp("Kit_" + name, origin + Vector3(0.55, 1.55, -0.05))
	var steel := _mat(Color(0.55, 0.56, 0.58))
	_cyl(kit, Vector3(0, 0.25, 0), 0.015, 0.5, steel)
	_box(kit, Vector3(0, -0.02, 0), Vector3(0.28, 0.04, 0.2), steel)
	_box(kit, Vector3(0, 0.08, 0), Vector3(0.18, 0.03, 0.14), _mat(Color(0.15, 0.15, 0.16)))
	_flat(kit, Vector3(-0.7, 0.15, -0.12), Vector3(0.38, 0.28, 0.02), _mat(Color(0.92, 0.9, 0.82)))


static func _casino() -> void:
	# автоматы у правой стены (слева уже есть)
	var faces: Array[Color] = [
		Color(1.0, 0.35, 0.55), Color(0.35, 0.95, 0.55), Color(1.0, 0.85, 0.2), Color(0.45, 0.7, 1.0),
	]
	var zs: Array[float] = [-2.4, 0.6, 3.8, 6.6]
	for i in zs.size():
		var p := Vector3(9.6, 0, zs[i])
		if _blocked(p, 0.55):
			continue
		_slot("SlotR%d" % i, p, -90.0, faces[i])
	# ближе к камере (+Z)
	if not _blocked(Vector3(7.8, 0, 8.8), 0.5):
		_slot("SlotCam", Vector3(7.8, 0, 8.8), -110.0, Color(1.0, 0.45, 0.2))
	# бархатный канат перед столом
	if not _blocked(Vector3(0.0, 0, 3.6), 0.3):
		var rope := _grp("Rope", Vector3(0.0, 0, 3.6), 0.0)
		var post := _mat(Color(0.55, 0.42, 0.12))
		var vel := _mat(Color(0.55, 0.05, 0.12))
		_cyl(rope, Vector3(-1.6, 0.45, 0), 0.035, 0.9, post)
		_cyl(rope, Vector3(1.6, 0.45, 0), 0.035, 0.9, post)
		_cyl(rope, Vector3(0, 0.82, 0), 0.02, 3.2, vel, Basis(Vector3.FORWARD, deg_to_rad(90)))
		_sph_m(rope, Vector3(-1.6, 0.92, 0), 0.05, post)
		_sph_m(rope, Vector3(1.6, 0.92, 0), 0.05, post)
	# сцена у дальней стены
	if not _blocked(Vector3(0.0, 0, 11.4), 1.0):
		var st := _grp("Stage", Vector3(0.0, 0, 11.4), 0.0, true, Vector3(4.4, 0.42, 1.6))
		var wood := _mat(Color(0.35, 0.12, 0.14), "tex_planks")
		_box(st, Vector3(0, 0.18, 0), Vector3(4.4, 0.36, 1.55), wood)
		_flat(st, Vector3(0, 1.4, -0.7), Vector3(3.8, 1.8, 0.05), _mat(Color(0.45, 0.06, 0.12)))
		var spot := _mat(Color(1, 0.92, 0.7), "", Color(1, 0.85, 0.5), 2.8)
		_cyl(st, Vector3(0, 2.55, 0.1), 0.12, 0.18, _mat(Color(0.15, 0.15, 0.16)), Basis(), 0.28)
		_cyl(st, Vector3(0, 2.35, 0.15), 0.06, 0.2, spot, Basis(Vector3.RIGHT, deg_to_rad(25)), 0.18)
	# неон по стенам
	var neon := _mat(Color(1.0, 0.15, 0.35), "", Color(1.0, 0.12, 0.32), 3.2, 0.3)
	var ng := _grp("Neon", Vector3.ZERO)
	_flat(ng, Vector3(-12.35, 3.4, 3.0), Vector3(0.06, 0.1, 14.0), neon)
	_flat(ng, Vector3(12.35, 3.4, 3.0), Vector3(0.06, 0.1, 14.0), neon)
	_flat(ng, Vector3(0.0, 3.55, 12.85), Vector3(18.0, 0.1, 0.06), neon)
	# фишки на боковом столике
	if not _blocked(Vector3(4.2, 0, 5.2), 0.45):
		var ct := _grp("ChipTable", Vector3(4.2, 0, 5.2), 20.0, true, Vector3(0.7, 0.78, 0.7))
		_cyl(ct, Vector3(0, 0.38, 0), 0.28, 0.76, _mat(Color(0.28, 0.1, 0.12)))
		_box(ct, Vector3(0, 0.78, 0), Vector3(0.7, 0.05, 0.7), _mat(Color(0.12, 0.45, 0.18)))
		var gold := _mat(Color(0.85, 0.7, 0.2))
		var white := _mat(Color(0.92, 0.9, 0.85))
		for k in 5:
			_cyl(ct, Vector3(-0.08, 0.84 + float(k) * 0.035, 0.04), 0.05, 0.03, gold if k % 2 == 0 else white)
		_cyl(ct, Vector3(0.14, 0.86, -0.08), 0.045, 0.03, _mat(Color(0.15, 0.15, 0.7)))
		_cyl(ct, Vector3(0.14, 0.89, -0.08), 0.045, 0.03, _mat(Color(0.7, 0.12, 0.15)))
	# два тусклых омни
	_light(_root, Vector3(-4.0, 3.4, 6.0), Color(1.0, 0.45, 0.4), 0.55, 10.0)
	_light(_root, Vector3(4.5, 3.5, 10.5), Color(1.0, 0.7, 0.45), 0.5, 9.0)


static func _slot(name: String, pos: Vector3, yaw: float, face: Color) -> void:
	var g := _grp(name, pos, yaw, true, Vector3(0.72, 1.55, 0.58))
	var cab := _mat(Color(0.18, 0.08, 0.14))
	_box(g, Vector3(0, 0.78, 0), Vector3(0.7, 1.52, 0.55), cab)
	_flat(g, Vector3(0, 0.95, 0.28), Vector3(0.52, 0.42, 0.03), _mat(face, "", face, 2.6, 0.35))
	_box(g, Vector3(0, 0.42, 0.22), Vector3(0.48, 0.12, 0.12), _mat(Color(0.12, 0.12, 0.13)))
	var lev := Basis(Vector3.FORWARD, deg_to_rad(-28))
	_cyl(g, Vector3(0.4, 1.05, 0.05), 0.025, 0.42, _mat(Color(0.55, 0.55, 0.58)), lev)
	_sph_m(g, Vector3(0.52, 1.22, 0.05), 0.055, _mat(Color(0.85, 0.12, 0.15)))


static func _police() -> void:
	# бумаги и лампа на существующем столе (0, −1)
	var desk := _grp("DeskBits", Vector3(0.0, 0, -1.0), 0.0)
	var paper := _mat(Color(0.93, 0.91, 0.84))
	_flat(desk, Vector3(0.35, 1.05, 0.12), Vector3(0.22, 0.01, 0.28), paper)
	_flat(desk, Vector3(0.38, 1.065, 0.1), Vector3(0.2, 0.01, 0.26), paper, Basis(Vector3.UP, deg_to_rad(8)))
	_flat(desk, Vector3(0.36, 1.08, 0.11), Vector3(0.2, 0.01, 0.24), paper, Basis(Vector3.UP, deg_to_rad(-6)))
	_cyl(desk, Vector3(-0.55, 1.22, 0.15), 0.04, 0.28, _mat(Color(0.25, 0.25, 0.22)))
	_cyl(desk, Vector3(-0.55, 1.4, 0.15), 0.1, 0.06, _mat(Color(0.95, 0.88, 0.55), "", Color(1, 0.85, 0.5), 1.8), Basis(), 0.04)
	_light(desk, Vector3(-0.55, 1.35, 0.2), Color(1.0, 0.9, 0.7), 0.7, 6.5)
	# скамейки
	_bench("BenchL", Vector3(-8.2, 0, 1.8), 90.0)
	_bench("BenchR", Vector3(8.2, 0, 2.2), -90.0)
	_bench("BenchCam", Vector3(3.6, 0, 6.4), 8.0)
	if not _blocked(Vector3(-9.6, 0, 6.4), 0.4):
		var cm := _grp("Coffee", Vector3(-9.6, 0, 6.4), 90.0, true, Vector3(0.48, 1.15, 0.42))
		var cream := _mat(Color(0.78, 0.76, 0.72))
		_box(cm, Vector3(0, 0.55, 0), Vector3(0.42, 1.08, 0.38), cream)
		_flat(cm, Vector3(0, 0.72, 0.2), Vector3(0.28, 0.18, 0.02), _mat(Color(0.12, 0.12, 0.12)))
		_cyl(cm, Vector3(0, 1.12, 0.05), 0.06, 0.08, _mat(Color(0.25, 0.18, 0.12)))
	# пробковая доска
	var cb := _grp("Cork", Vector3(-11.55, 1.7, 4.0), 90.0)
	_flat(cb, Vector3.ZERO, Vector3(1.15, 0.8, 0.03), _mat(Color(0.62, 0.42, 0.22)))
	_flat(cb, Vector3(-0.28, 0.12, 0.02), Vector3(0.28, 0.22, 0.01), _mat(Color(0.92, 0.9, 0.78)))
	_flat(cb, Vector3(0.22, -0.08, 0.02), Vector3(0.24, 0.2, 0.01), _face_mat("tex_flyer_hamster"))
	_flat(cb, Vector3(0.05, 0.22, 0.02), Vector3(0.2, 0.16, 0.01), _mat(Color(0.85, 0.2, 0.2)))
	# шлагбаум снаружи у входа
	if not _blocked(Vector3(0.0, 0, -8.0), 0.55, false):
		var gate := _grp("Barrier", Vector3(0.0, 0, -8.0), 0.0, true, Vector3(0.25, 1.1, 0.25))
		var yel := _mat(Color(0.95, 0.75, 0.1))
		var blk := _mat(Color(0.1, 0.1, 0.1))
		_cyl(gate, Vector3(-1.4, 0.5, 0), 0.07, 1.0, _mat(Color(0.35, 0.36, 0.38)))
		_box(gate, Vector3(0.15, 0.95, 0), Vector3(3.1, 0.08, 0.08), yel)
		_flat(gate, Vector3(-0.6, 0.95, 0.05), Vector3(0.35, 0.08, 0.02), blk)
		_flat(gate, Vector3(0.4, 0.95, 0.05), Vector3(0.35, 0.08, 0.02), blk)
		_flat(gate, Vector3(1.3, 0.95, 0.05), Vector3(0.35, 0.08, 0.02), blk)
	var cones: Array[Vector3] = [
		Vector3(-3.4, 0, -9.2), Vector3(3.6, 0, -9.4), Vector3(-7.2, 0, -10.6), Vector3(7.4, 0, -10.4),
		Vector3(-13.6, 0, 8.2), Vector3(-12.8, 0, 11.4), Vector3(-14.2, 0, 4.6),
	]
	for i in cones.size():
		_cone("Cone%d" % i, cones[i])
	if not _blocked(Vector3(-10.4, 0, 3.2), 0.45):
		var cab := _grp("FileCab", Vector3(-10.4, 0, 3.2), 90.0, true, Vector3(0.48, 1.15, 0.42))
		_box(cab, Vector3(0, 0.55, 0), Vector3(0.44, 1.08, 0.4), _mat(Color(0.28, 0.32, 0.38)))
		_flat(cab, Vector3(0.2, 0.35, 0), Vector3(0.02, 0.16, 0.28), _mat(Color(0.7, 0.72, 0.75)))
		_flat(cab, Vector3(0.2, 0.72, 0), Vector3(0.02, 0.16, 0.28), _mat(Color(0.7, 0.72, 0.75)))


static func _bench(name: String, pos: Vector3, yaw: float) -> void:
	if _blocked(pos, 0.7):
		return
	var g := _grp(name, pos, yaw, true, Vector3(1.7, 0.55, 0.48))
	var wood := _mat(Color(0.45, 0.32, 0.18), "tex_planks")
	var metal := _mat(Color(0.3, 0.32, 0.35))
	_box(g, Vector3(0, 0.42, 0), Vector3(1.65, 0.07, 0.42), wood)
	_box(g, Vector3(0, 0.68, -0.16), Vector3(1.65, 0.42, 0.06), wood)
	_box(g, Vector3(-0.75, 0.22, 0), Vector3(0.08, 0.42, 0.4), metal)
	_box(g, Vector3(0.75, 0.22, 0), Vector3(0.08, 0.42, 0.4), metal)


static func _cone(name: String, pos: Vector3) -> void:
	if _blocked(pos, 0.25, false):
		return
	var g := _grp(name, pos)
	_cyl(g, Vector3(0, 0.28, 0), 0.16, 0.55, _mat(Color(0.92, 0.38, 0.08)), Basis(), 0.04)
	_cyl(g, Vector3(0, 0.32, 0), 0.12, 0.08, _mat(Color(0.95, 0.95, 0.92)))


static func _port() -> void:
	# контейнеры сбоку от лотов, ближе к воде
	var cols: Array[Color] = [Color(0.15, 0.42, 0.48), Color(0.72, 0.22, 0.14), Color(0.85, 0.7, 0.15)]
	if not _blocked(Vector3(-14.5, 0, 16.5), 1.6):
		var st := _grp("Containers", Vector3(-14.5, 0, 16.5), 8.0, true, Vector3(6.4, 5.4, 2.6))
		for i in 3:
			var y := 1.15 + float(i) * 2.15
			var ox := float(i % 2) * 0.15
			_box(st, Vector3(ox, y, 0), Vector3(6.1, 2.1, 2.4), _mat(cols[i], "tex_container", Color(0, 0, 0, 0), 1.0, 0.7, 2.4))
	_crane("Crane", Vector3(16.0, 0, 14.5), -25.0)
	var boll_xs: Array[float] = [-18.0, -6.0, 8.0, 20.0]
	for i in boll_xs.size():
		_bollard("Boll%d" % i, Vector3(boll_xs[i], 0, 27.8))
	var buoys: Array[Vector3] = [Vector3(-12.0, 0.15, 30.4), Vector3(2.0, 0.12, 30.6), Vector3(16.0, 0.14, 30.3)]
	for i in buoys.size():
		var bg := _grp("Buoy%d" % i, buoys[i])
		_sph_m(bg, Vector3(0, 0.22, 0), 0.22, _mat(Color(0.92, 0.35, 0.08)))
		_cyl(bg, Vector3(0, 0.42, 0), 0.04, 0.22, _mat(Color(0.9, 0.9, 0.88)))
	if not _blocked(Vector3(22.0, 0, 16.5), 0.7):
		var pb := _grp("BarrelPal", Vector3(22.0, 0, 16.5), -8.0, true, Vector3(1.2, 0.95, 1.15))
		_box(pb, Vector3(0, 0.07, 0), Vector3(1.15, 0.12, 1.1), _mat(Color(0.62, 0.45, 0.26), "tex_planks"))
		var rust := _mat(Color(0.55, 0.32, 0.18), "tex_rust_teal")
		_cyl(pb, Vector3(-0.28, 0.55, 0.05), 0.28, 0.85, rust)
		_cyl(pb, Vector3(0.3, 0.52, -0.08), 0.26, 0.8, rust)


static func _crane(name: String, pos: Vector3, yaw: float) -> void:
	if _blocked(pos, 1.2):
		return
	var g := _grp(name, pos, yaw, true, Vector3(1.4, 2.2, 1.4))
	var yel := _mat(Color(0.9, 0.7, 0.12))
	var gry := _mat(Color(0.3, 0.32, 0.34))
	_box(g, Vector3(0, 1.1, 0), Vector3(1.35, 2.2, 1.35), yel)
	_box(g, Vector3(0, 6.2, 0), Vector3(0.55, 8.2, 0.55), yel)
	_box(g, Vector3(3.4, 10.15, 0), Vector3(7.2, 0.35, 0.4), yel)
	_box(g, Vector3(6.6, 8.4, 0), Vector3(0.12, 3.4, 0.12), gry)
	_box(g, Vector3(6.6, 6.6, 0), Vector3(0.35, 0.25, 0.25), gry)


static func _bollard(name: String, pos: Vector3) -> void:
	if _blocked(pos, 0.35):
		return
	var g := _grp(name, pos, 0.0, true, Vector3.ZERO)
	var iron := _mat(Color(0.28, 0.28, 0.3))
	_cyl(g, Vector3(0, 0.38, 0), 0.22, 0.76, iron)
	_cyl_col(g, Vector3(0, 0.38, 0), 0.24, 0.76)
	# петля каната
	var rope := _mat(Color(0.55, 0.4, 0.18))
	_cyl(g, Vector3(0.18, 0.55, 0), 0.04, 0.22, rope, Basis(Vector3.FORWARD, deg_to_rad(90)), 0.04)
	# чайки
	var poop := _mat(Color(0.88, 0.86, 0.78))
	_flat(g, Vector3(0.04, 0.77, 0.03), Vector3(0.06, 0.015, 0.05), poop)
	_flat(g, Vector3(-0.05, 0.77, -0.04), Vector3(0.04, 0.012, 0.04), poop)


## Обшивка из TrailerPark.tscn / Trailer: стены 0.2, внутренние грани x=±4.0 z=±1.7,
## пол M0 верх y=0.06, потолок M7 низ y=2.60, дверь +Z x=2.0..3.0 до y=2.10,
## окна M13/M14 (+Z) и M15 (−Z) — светло-голубые 1.3×0.8 / 2.0×0.8 @ y=1.65.
static func _trailer_skin(o: Vector3) -> void:
	var wall_m := _mat(Color(0.9, 0.82, 0.7), "tex_wall_interior", Color(0, 0, 0, 0), 1.0, 0.9, 1.6)
	var ceil_m := _mat(Color(0.86, 0.82, 0.76), "", Color(0, 0, 0, 0), 1.0, 1.0)
	var floor_m := _mat(Color(0.78, 0.62, 0.42), "tex_planks", Color(0, 0, 0, 0), 1.0, 0.92, 1.3)
	var glass_m := _mat(Color(0.55, 0.75, 0.9), "", Color(0.3, 0.45, 0.6), 0.7, 0.35)
	var g := _grp("TrailerSkin", o)
	const T := 0.02
	const IN := 0.01
	# внутренние грани стен
	const XI := 4.0
	const ZI := 1.7
	const Y0 := 0.08
	const Y1 := 2.56
	var yh := Y1 - Y0
	var yc := Y0 + yh * 0.5
	var zlen := (ZI - IN - T) * 2.0
	var xlen := (XI - IN - T) * 2.0
	# пол и потолок — чуть короче, чтобы не заезжать в панели стен
	_flat(g, Vector3(0.0, 0.07, 0.0), Vector3(xlen, 0.016, zlen), floor_m)
	_flat(g, Vector3(0.0, 2.58, 0.0), Vector3(xlen, T, zlen), ceil_m)
	# ±X сплошные
	_flat(g, Vector3(-(XI - IN - T * 0.5), yc, 0.0), Vector3(T, yh, zlen), wall_m)
	_flat(g, Vector3(XI - IN - T * 0.5, yc, 0.0), Vector3(T, yh, zlen), wall_m)
	var zp := ZI - IN - T * 0.5
	var zm := -zp
	var xa := -xlen * 0.5
	var xb := xlen * 0.5
	# −Z: окно M15
	var holes_m: Array = [Vector4(-2.5, -0.5, 1.25, 2.05)]
	_skin_wall_holes(g, zm, wall_m, xa, xb, Y0, Y1, holes_m)
	_flat(g, Vector3(-1.5, 1.65, zm), Vector3(1.96, 0.76, 0.012), glass_m)
	# +Z: окна M13/M14 и дверь 1 м
	var holes_p: Array = [
		Vector4(-3.25, -1.95, 1.25, 2.05),
		Vector4(-0.25, 1.05, 1.25, 2.05),
		Vector4(2.0, 3.0, Y0, 2.10),
	]
	_skin_wall_holes(g, zp, wall_m, xa, xb, Y0, Y1, holes_p)
	_flat(g, Vector3(-2.6, 1.65, zp), Vector3(1.26, 0.76, 0.012), glass_m)
	_flat(g, Vector3(0.4, 1.65, zp), Vector3(1.26, 0.76, 0.012), glass_m)


## holes: Vector4(x0, x1, y0, y1) — вырезы в плоскости z=const.
static func _skin_wall_holes(parent: Node3D, z: float, mat: Material, x0: float, x1: float, y0: float, y1: float, holes: Array) -> void:
	var raw: Array[float] = [x0, x1]
	for h in holes:
		var hv: Vector4 = h as Vector4
		raw.append(hv.x)
		raw.append(hv.y)
	raw.sort()
	var xs: Array[float] = []
	for v in raw:
		if xs.is_empty() or absf(v - xs[xs.size() - 1]) > 0.005:
			xs.append(v)
	for i in range(xs.size() - 1):
		var a := xs[i]
		var b := xs[i + 1]
		if b - a < 0.03:
			continue
		var midx := (a + b) * 0.5
		var blocked_y: Array[Vector2] = []
		for h2 in holes:
			var hv2: Vector4 = h2 as Vector4
			if midx > hv2.x + 0.001 and midx < hv2.y - 0.001:
				blocked_y.append(Vector2(hv2.z, hv2.w))
		var ys: Array[float] = [y0, y1]
		for by in blocked_y:
			ys.append(by.x)
			ys.append(by.y)
		ys.sort()
		var ysu: Array[float] = []
		for yv in ys:
			if ysu.is_empty() or absf(yv - ysu[ysu.size() - 1]) > 0.005:
				ysu.append(yv)
		for j in range(ysu.size() - 1):
			var ya := ysu[j]
			var yb := ysu[j + 1]
			if yb - ya < 0.03:
				continue
			var midy := (ya + yb) * 0.5
			var cover := true
			for by2 in blocked_y:
				if midy > by2.x + 0.001 and midy < by2.y - 0.001:
					cover = false
					break
			if cover:
				_flat(parent, Vector3(midx, midy, z), Vector3(b - a, yb - ya, 0.02), mat)


static func _trailer(world: Node) -> void:
	# интерьер ~8×2.6×3.8, центр маркера Trailer, пол y≈0.3, дверь +Z
	var tr: Node3D = _dist.marker("Trailer")
	if tr == null and world.has_method("find_marker"):
		tr = world.call("find_marker", Types.District.TRAILER_PARK, "Trailer") as Node3D
	if tr == null:
		return
	var o: Vector3 = _dist.to_local(tr.global_position)
	_trailer_skin(o)
	# кухня у +X, середина (не кровати, не дверь)
	var kit_p := o + Vector3(3.28, 0.0, 0.15)
	if not _blocked(kit_p, 0.4):
		var kit := _grp("Kitchen", kit_p, -90.0, true, Vector3(1.15, 0.92, 0.48))
		var cream := _mat(Color(0.78, 0.72, 0.58), "tex_wall_interior")
		var steel := _mat(Color(0.55, 0.58, 0.6), "", Color(0, 0, 0, 0), 1.0, 0.35)
		_box(kit, Vector3(0, 0.42, 0), Vector3(1.1, 0.82, 0.46), cream)
		_cyl(kit, Vector3(-0.22, 0.86, 0.05), 0.12, 0.05, steel)
		_cyl(kit, Vector3(-0.22, 0.84, 0.05), 0.04, 0.04, _mat(Color(0.35, 0.5, 0.7), "", Color(0.3, 0.45, 0.65), 0.4))
		_cyl(kit, Vector3(0.28, 0.95, 0.0), 0.07, 0.16, _mat(Color(0.25, 0.25, 0.26)))
		_cyl(kit, Vector3(0.28, 1.06, 0.0), 0.05, 0.06, steel)
		_box(kit, Vector3(0.28, 1.12, 0.0), Vector3(0.08, 0.04, 0.08), steel)
	var fr_p := o + Vector3(-3.42, 0.0, 0.45)
	if not _blocked(fr_p, 0.4):
		var fr := _grp("Fridge", fr_p, 90.0, true, Vector3(0.55, 1.45, 0.5))
		_box(fr, Vector3(0, 0.72, 0), Vector3(0.52, 1.42, 0.48), _mat(Color(0.82, 0.84, 0.8)))
		_box(fr, Vector3(0.24, 0.85, 0.12), Vector3(0.04, 0.14, 0.03), _mat(Color(0.25, 0.25, 0.26)))
	# табуреты у существующего стола (1.6, −1.1 локально трейлера)
	var st0 := o + Vector3(1.15, 0.0, -0.55)
	var st1 := o + Vector3(2.05, 0.0, -0.55)
	_stool("Stool0", st0)
	_stool("Stool1", st1)
	# ковёр у стола, не на проходе к двери
	var rug_p := o + Vector3(1.5, 0.015, -0.85)
	if not _blocked(rug_p, 0.25):
		var rg := _grp("Rug", rug_p)
		_flat(rg, Vector3.ZERO, Vector3(1.35, 0.02, 0.95), _mat(Color(0.75, 0.35, 0.22), "tex_rug", Color(0, 0, 0, 0), 1.0, 0.95, 1.1))
	# полка на −Z обшивке (внутренняя грань панели z≈−1.67)
	var sh_p := o + Vector3(0.55, 1.55, -1.56)
	var sh := _grp("Shelf", sh_p)
	var wood := _mat(Color(0.5, 0.35, 0.2), "tex_planks")
	_box(sh, Vector3.ZERO, Vector3(0.95, 0.05, 0.18), wood)
	_sph_m(sh, Vector3(-0.28, 0.1, 0), 0.06, _mat(Color(0.75, 0.2, 0.45)))
	_cyl(sh, Vector3(0.02, 0.1, 0), 0.04, 0.12, _mat(Color(0.2, 0.45, 0.55)))
	_box(sh, Vector3(0.3, 0.08, 0), Vector3(0.1, 0.1, 0.08), _mat(Color(0.9, 0.7, 0.15)))
	# пробковая доска
	var cork := _grp("TCork", o + Vector3(2.15, 1.55, -1.66))
	_flat(cork, Vector3.ZERO, Vector3(0.55, 0.42, 0.02), _mat(Color(0.62, 0.44, 0.24)))
	_flat(cork, Vector3(-0.1, 0.05, 0.015), Vector3(0.16, 0.14, 0.01), _face_mat("tex_flyer_hamster"))
	# декоративный абажур над столом (без света)
	var shd := _grp("Shade", o + Vector3(1.6, 2.15, -1.1))
	_cyl(shd, Vector3(0, 0.12, 0), 0.008, 0.28, _mat(Color(0.2, 0.2, 0.2)))
	_cyl(shd, Vector3(0, 0.0, 0), 0.16, 0.12, _mat(Color(0.85, 0.72, 0.4)), Basis(), 0.05)
	# конический абажур вокруг лампы M30 (сфера r=0.16 @ 0.5, 2.5, 0.6) — без своего света
	var bulb := _grp("BulbShade", o + Vector3(0.5, 2.48, 0.6))
	var shade_m := _mat(Color(0.86, 0.82, 0.76), "", Color(0, 0, 0, 0), 1.0, 1.0)
	_cyl(bulb, Vector3(0.0, 0.16, 0.0), 0.012, 0.22, _mat(Color(0.22, 0.2, 0.18)))
	_cyl(bulb, Vector3.ZERO, 0.26, 0.26, shade_m, Basis(), 0.055)
	var duf := o + Vector3(0.7, 0.0, -1.55)
	if not _blocked(duf, 0.3):
		var dg := _grp("Duffel", duf, 22.0)
		_box(dg, Vector3(0, 0.18, 0), Vector3(0.55, 0.28, 0.28), _mat(Color(0.22, 0.32, 0.42)))
		_cyl(dg, Vector3(0, 0.32, 0), 0.04, 0.22, _mat(Color(0.15, 0.15, 0.16)), Basis(Vector3.FORWARD, deg_to_rad(90)))
	var beer := o + Vector3(3.25, 0.0, 1.15)
	if not _blocked(beer, 0.3):
		var bg := _grp("BeerCrate", beer, -8.0)
		_box(bg, Vector3(0, 0.14, 0), Vector3(0.38, 0.22, 0.28), _mat(Color(0.55, 0.32, 0.14), "tex_planks"))
		var glass := _mat(Color(0.25, 0.45, 0.22), "", Color(0.1, 0.25, 0.1), 0.3)
		_cyl(bg, Vector3(-0.08, 0.32, 0.04), 0.04, 0.16, glass)
		_cyl(bg, Vector3(0.08, 0.32, -0.04), 0.04, 0.16, glass)


static func _stool(name: String, pos: Vector3) -> void:
	if _blocked(pos, 0.25):
		return
	var g := _grp(name, pos)
	var wood := _mat(Color(0.4, 0.26, 0.14), "tex_planks")
	_cyl(g, Vector3(0, 0.28, 0), 0.16, 0.06, wood)
	_cyl(g, Vector3(0, 0.14, 0), 0.03, 0.26, wood)


static func _carmarket() -> void:
	_bunting("CmBunt0", Vector3(-16.0, 3.4, 10.0), Vector3(16.0, 3.4, 10.0), 10, Color(0.95, 0.75, 0.12), Color(0.15, 0.35, 0.7))
	_bunting("CmBunt1", Vector3(-18.0, 3.2, -16.0), Vector3(18.0, 3.2, -16.0), 9, Color(0.9, 0.2, 0.2), Color(0.95, 0.85, 0.2))
	if not _blocked(Vector3(13.6, 0, 4.2), 0.4):
		var sb := _grp("Sandwich", Vector3(13.6, 0, 4.2), -25.0)
		var wood := _mat(Color(0.42, 0.3, 0.16), "tex_planks")
		_flat(sb, Vector3(0, 0.55, 0.08), Vector3(0.7, 0.95, 0.04), wood, Basis(Vector3.RIGHT, deg_to_rad(-18)))
		_flat(sb, Vector3(0, 0.55, -0.08), Vector3(0.7, 0.95, 0.04), wood, Basis(Vector3.RIGHT, deg_to_rad(18)))
		_flat(sb, Vector3(0, 0.58, 0.1), Vector3(0.58, 0.72, 0.01), _mat(Color(0.92, 0.9, 0.82)), Basis(Vector3.RIGHT, deg_to_rad(-18)))
	_tyre_stack("CmTires0", Vector3(-17.4, 0, 12.2), 22.0)
	_tyre_stack("CmTires1", Vector3(17.2, 0, -14.6), -12.0)


static func _locksmith() -> void:
	_bunting("LsBunt", Vector3(-1.8, 2.85, 1.75), Vector3(1.8, 2.85, 1.75), 6, Color(0.2, 0.55, 0.35), Color(0.92, 0.78, 0.15))
	if not _blocked(Vector3(2.4, 0, 3.15), 0.35):
		var sb := _grp("LsBoard", Vector3(2.4, 0, 3.15), 18.0)
		var wood := _mat(Color(0.4, 0.28, 0.14), "tex_planks")
		_flat(sb, Vector3(0, 0.52, 0.07), Vector3(0.62, 0.85, 0.04), wood, Basis(Vector3.RIGHT, deg_to_rad(-20)))
		_flat(sb, Vector3(0, 0.52, -0.07), Vector3(0.62, 0.85, 0.04), wood, Basis(Vector3.RIGHT, deg_to_rad(20)))
		_flat(sb, Vector3(0, 0.55, 0.09), Vector3(0.5, 0.62, 0.01), _mat(Color(0.9, 0.88, 0.78)), Basis(Vector3.RIGHT, deg_to_rad(-20)))
	_tyre_stack("LsTires", Vector3(-2.7, 0, 2.6), 30.0)
	# станок на прилавке (0, 1.6), крышка ~y=1.02
	var mach := _grp("KeyCut", Vector3(0.55, 1.04, 1.58), 0.0)
	var steel := _mat(Color(0.45, 0.48, 0.5), "", Color(0, 0, 0, 0), 1.0, 0.35)
	_box(mach, Vector3(0, 0.12, 0), Vector3(0.42, 0.22, 0.28), steel)
	_cyl(mach, Vector3(0.12, 0.28, 0.02), 0.08, 0.04, _mat(Color(0.2, 0.2, 0.22)), Basis(Vector3.FORWARD, deg_to_rad(90)))
	_box(mach, Vector3(-0.08, 0.22, 0.04), Vector3(0.16, 0.08, 0.06), _mat(Color(0.7, 0.55, 0.15)))
	_box(mach, Vector3(0, 0.32, -0.08), Vector3(0.12, 0.16, 0.04), _mat(Color(0.15, 0.15, 0.16)))
