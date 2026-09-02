class_name LowPoly
extends RefCounted
## Гранёный стиль кей-арта: у примитивов Godot сглаженные нормали, из-за чего шары/капсулы
## выглядят «пластилином». Здесь снимаем индексацию и пересчитываем нормали по фасетам,
## режем сегменты до 6–8 и строим скошенные (chamfer) коробки. Всё кэшируется по параметрам,
## так что 200 предметов + толпа NPC не плодят меши.

static var _cache: Dictionary = {}


## Плоские нормали для любого меша (материалы поверхностей сохраняются).
static func facet(src: Mesh, key: String = "") -> ArrayMesh:
	if src == null:
		return null
	if key != "" and _cache.has(key):
		return _cache[key]
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		var st := SurfaceTool.new()
		st.create_from(src, s)
		st.deindex()
		st.generate_normals()
		st.set_material(src.surface_get_material(s))
		st.commit(out)
	if key != "":
		_cache[key] = out
	return out


static func sphere(r: float, seg := 8, rings := 4, hemi := false, h := -1.0) -> ArrayMesh:
	var key := "sph|%.3f|%d|%d|%s|%.3f" % [r, seg, rings, hemi, h]
	if _cache.has(key):
		return _cache[key]
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = (r * 2.0) if h < 0.0 else h
	sm.radial_segments = seg
	sm.rings = rings
	sm.is_hemisphere = hemi
	return facet(sm, key)


static func capsule(r: float, h: float, seg := 8, rings := 3) -> ArrayMesh:
	var key := "cap|%.3f|%.3f|%d|%d" % [r, h, seg, rings]
	if _cache.has(key):
		return _cache[key]
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = seg
	c.rings = rings
	return facet(c, key)


static func cylinder(rt: float, rb: float, h: float, seg := 8) -> ArrayMesh:
	var key := "cyl|%.3f|%.3f|%.3f|%d" % [rt, rb, h, seg]
	if _cache.has(key):
		return _cache[key]
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return facet(c, key)


## Коробка со скошенными рёбрами — «рубленый» силуэт телевизоров, чемоданов, кузовов.
static func chamfer_box(size: Vector3, bevel: float) -> ArrayMesh:
	var key := "chb|%.3f|%.3f|%.3f|%.3f" % [size.x, size.y, size.z, bevel]
	if _cache.has(key):
		return _cache[key]
	var h := size * 0.5
	var b := clampf(bevel, 0.001, minf(minf(h.x, h.y), h.z) * 0.9)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# три точки на каждый угол: полная координата по одной оси, вжатые на b по двум другим
	var px := func(sx, sy, sz) -> Vector3: return Vector3(sx * h.x, sy * (h.y - b), sz * (h.z - b))
	var py := func(sx, sy, sz) -> Vector3: return Vector3(sx * (h.x - b), sy * h.y, sz * (h.z - b))
	var pz := func(sx, sy, sz) -> Vector3: return Vector3(sx * (h.x - b), sy * (h.y - b), sz * h.z)
	var S := [-1.0, 1.0]
	# грани
	for sx in S:
		_quad(st, px.call(sx, -1, -1), px.call(sx, 1, -1), px.call(sx, 1, 1), px.call(sx, -1, 1))
	for sy in S:
		_quad(st, py.call(-1, sy, -1), py.call(1, sy, -1), py.call(1, sy, 1), py.call(-1, sy, 1))
	for sz in S:
		_quad(st, pz.call(-1, -1, sz), pz.call(1, -1, sz), pz.call(1, 1, sz), pz.call(-1, 1, sz))
	# рёбра
	for sy in S:
		for sz in S:
			_quad(st, py.call(-1, sy, sz), py.call(1, sy, sz), pz.call(1, sy, sz), pz.call(-1, sy, sz))
	for sx in S:
		for sz in S:
			_quad(st, px.call(sx, -1, sz), px.call(sx, 1, sz), pz.call(sx, 1, sz), pz.call(sx, -1, sz))
	for sx in S:
		for sy in S:
			_quad(st, px.call(sx, sy, -1), px.call(sx, sy, 1), py.call(sx, sy, 1), py.call(sx, sy, -1))
	# углы
	for sx in S:
		for sy in S:
			for sz in S:
				_tri(st, px.call(sx, sy, sz), py.call(sx, sy, sz), pz.call(sx, sy, sz))
	st.generate_normals()
	var m := st.commit()
	_cache[key] = m
	return m


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	# выпуклое тело вокруг начала координат: нормаль должна смотреть от центра
	var n := (b - a).cross(c - a)
	if n.dot(a + b + c) < 0.0:
		var t := b
		b = c
		c = t
		n = -n
	var uv_axis := n.abs()
	for v in [a, b, c]:
		var uv: Vector2
		if uv_axis.x >= uv_axis.y and uv_axis.x >= uv_axis.z:
			uv = Vector2(v.z, v.y)
		elif uv_axis.y >= uv_axis.z:
			uv = Vector2(v.x, v.z)
		else:
			uv = Vector2(v.x, v.y)
		st.set_uv(uv)
		st.add_vertex(v)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_tri(st, a, b, c)
	_tri(st, a, c, d)


## Проходит по MeshInstance3D в поддереве и заменяет круглые примитивы на гранёные копии
## с урезанными сегментами. Материалы примитива переносятся в override поверхности.
static func flatten(root: Node, max_seg := 8, max_rings := 4) -> int:
	var n := 0
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if _flatten_one(mi as MeshInstance3D, max_seg, max_rings):
			n += 1
	if root is MeshInstance3D and _flatten_one(root as MeshInstance3D, max_seg, max_rings):
		n += 1
	return n


static func _flatten_one(mi: MeshInstance3D, max_seg: int, max_rings: int) -> bool:
	var m := mi.mesh
	if m == null or m is ArrayMesh:
		return false
	var mat: Material = null
	var out: ArrayMesh = null
	if m is SphereMesh:
		var s := m as SphereMesh
		mat = s.material
		out = sphere(s.radius, mini(s.radial_segments, max_seg), mini(s.rings, max_rings), s.is_hemisphere, s.height)
	elif m is CapsuleMesh:
		var c := m as CapsuleMesh
		mat = c.material
		out = capsule(c.radius, c.height, mini(c.radial_segments, max_seg), mini(c.rings, max_rings))
	elif m is CylinderMesh:
		var cy := m as CylinderMesh
		mat = cy.material
		out = cylinder(cy.top_radius, cy.bottom_radius, cy.height, mini(cy.radial_segments, max_seg))
	else:
		return false
	mi.mesh = out
	# именно material_override: per-surface override у общего меша при free() узла
	# даёт ошибку рендер-сервера «Parameter material is null» (Godot 4.6)
	if mat and mi.material_override == null and mi.get_surface_override_material(0) == null:
		mi.material_override = mat
	return true
