class_name Terrain
extends RefCounted
## Гранёная земля, как на кей-арте: плоский бокс города и грунтовые «блины» районов заменяем на сетку
## квадратов с шумом Перлина. Нормали плоские → каждый квадрат ловит закат по-своему; ямки-выбоины
## темнее (vertex color). Коллизия остаётся плоской (y = 0 у города): рельеф только ВНИЗ (0…-POTHOLE),
## поэтому вещи и люди не висят в воздухе, а в выбоине чуть «утопают» в пыли.
## Плюс россыпь камней/кирпичей/гальки (MultiMesh, без коллизии) по пустырям — не на дорогах и не в районах.

const CELL := 2.5
const POTHOLE := 0.07 # глубина выбоин на пустырях
const MICRO := 0.012 # микронеровность (везде, в т.ч. внутри районов — иначе там гладкий стол)
const DISTRICT_FLAT := 0.02 # внутри районов ямок нет: полы и стены стоят на y=0
const PEBBLES := 1400
const BRICKS := 260
const ROCKS := 160

static var _n_hole: FastNoiseLite
static var _n_micro: FastNoiseLite


static func _noise() -> void:
	if _n_hole:
		return
	_n_hole = FastNoiseLite.new()
	_n_hole.seed = 7031
	_n_hole.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_hole.frequency = 0.16 # выбоины ~3–6 м
	_n_micro = FastNoiseLite.new()
	_n_micro.seed = 9113
	_n_micro.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_n_micro.frequency = 0.55


## Высота рельефа (мировая) относительно плоскости коллизии. in_district → только микрошум.
static func height(x: float, z: float, in_district: bool) -> float:
	_noise()
	var h := _n_micro.get_noise_2d(x, z) * MICRO
	if in_district:
		return h - MICRO # всегда ≤ 0
	var n := _n_hole.get_noise_2d(x, z) # -1..1
	var hole := smoothstep(0.35, 0.85, n) # редкие круглые ямы
	return h - MICRO - hole * POTHOLE


## Темнее в яме, чуть светлее на «горбике» — читается рельеф даже без теней.
static func tint(h: float) -> Color:
	var k := clampf(-h / POTHOLE, 0.0, 1.0)
	return Color(1.0, 1.0, 1.0).lerp(Color(0.72, 0.66, 0.66), k)


static func _flat_mat(src: Material) -> StandardMaterial3D:
	var m: StandardMaterial3D = (src as StandardMaterial3D).duplicate() if src is StandardMaterial3D else StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	return m


const TILT := 0.085 # случайный наклон нормали квадрата (рад): «плитки» ловят закат по-разному при почти плоской земле

static func _push_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	# лицевая грань в Godot — обход по часовой, если смотреть сверху (+Y): a→b→c и a→c→d
	# при a=(x0,z0) b=(x1,z0) c=(x1,z1) d=(x0,z1). Нормаль — одна на квадрат (не на треугольник),
	# иначе читаются диагонали. Геометрический наклон крошечный, поэтому подмешиваем детерминированный
	# случайный: именно он даёт кей-артовые квадраты разной яркости.
	var n: Vector3 = (b - a).cross(c - a).normalized()
	if n.y < 0.0:
		n = -n
	var hsh := absi(hash(Vector2i(roundi(a.x * 10.0), roundi(a.z * 10.0))))
	var ang := float(hsh % 1000) / 1000.0 * TAU
	var mag := pow(float((hsh / 1000) % 1000) / 1000.0, 1.7) * TILT # большинство плиток почти ровные, редкие — заметно
	n = (n + Vector3(cos(ang) * mag, 0.0, sin(ang) * mag)).normalized()
	st.set_normal(n)
	for tri in [[a, b, c, ca, cb, cc], [a, c, d, ca, cc, cd]]:
		for i in 3:
			st.set_color(tri[3 + i])
			st.add_vertex(tri[i])


## Прямоугольная сетка size_x×size_z (локальные координаты меша), верх на top_y. world_of(x,z) → мировая точка
## для шума и проверки района. inside(x,z) → false для клеток, которые пропускаем (под блином района).
static func build_grid(size_x: float, size_z: float, top_y: float, cell: float, to_world: Callable, in_district: Callable, skip: Callable) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := int(ceil(size_x / cell))
	var nz := int(ceil(size_z / cell))
	var cx := size_x / float(nx)
	var cz := size_z / float(nz)
	var x0 := -size_x * 0.5
	var z0 := -size_z * 0.5
	var hmap := PackedFloat32Array()
	hmap.resize((nx + 1) * (nz + 1))
	for j in nz + 1:
		for i in nx + 1:
			var lx := x0 + i * cx
			var lz := z0 + j * cz
			var wp: Vector3 = to_world.call(lx, lz)
			hmap[j * (nx + 1) + i] = height(wp.x, wp.z, bool(in_district.call(wp)))
	for j in nz:
		for i in nx:
			var lx := x0 + i * cx
			var lz := z0 + j * cz
			var wp: Vector3 = to_world.call(lx + cx * 0.5, lz + cz * 0.5)
			if bool(skip.call(wp)):
				continue
			var h00 := hmap[j * (nx + 1) + i]
			var h10 := hmap[j * (nx + 1) + i + 1]
			var h11 := hmap[(j + 1) * (nx + 1) + i + 1]
			var h01 := hmap[(j + 1) * (nx + 1) + i]
			_push_quad(st,
				Vector3(lx, top_y + h00, lz), Vector3(lx + cx, top_y + h10, lz),
				Vector3(lx + cx, top_y + h11, lz + cz), Vector3(lx, top_y + h01, lz + cz),
				tint(h00), tint(h10), tint(h11), tint(h01))
	return st.commit()


## Круглый блин радиуса r (грунт района): сетка, обрезанная по кругу, крайние вершины прижаты к окружности.
static func build_disc(r: float, top_y: float, cell: float, to_world: Callable) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := int(ceil(2.0 * r / cell))
	var c := 2.0 * r / float(n)
	var clampc := func(x: float, z: float) -> Vector2:
		var v := Vector2(x, z)
		return v if v.length() <= r else v.normalized() * r
	for j in n:
		for i in n:
			var lx := -r + i * c
			var lz := -r + j * c
			var corners: Array[Vector2] = [clampc.call(lx, lz), clampc.call(lx + c, lz), clampc.call(lx + c, lz + c), clampc.call(lx, lz + c)]
			# клетка целиком за кругом — все четыре угла легли на окружность в одну «дугу»: пропускаем
			var inside := 0
			for q in [Vector2(lx, lz), Vector2(lx + c, lz), Vector2(lx + c, lz + c), Vector2(lx, lz + c)]:
				if q.length() <= r:
					inside += 1
			if inside == 0:
				continue
			var pts: Array[Vector3] = []
			var cols: Array[Color] = []
			for q in corners:
				var wp: Vector3 = to_world.call(q.x, q.y)
				var h := height(wp.x, wp.z, true) * 1.5 # на блине микрорельеф чуть сильнее — двор виден вблизи
				pts.append(Vector3(q.x, top_y + h, q.y))
				cols.append(tint(h * 2.0))
			_push_quad(st, pts[0], pts[1], pts[2], pts[3], cols[0], cols[1], cols[2], cols[3])
	return st.commit()


## Точка входа: зовёт CityDress после раскраски (материалы уже назначены).
static func dress(w) -> int:
	var city = w.city
	if city == null:
		return 0
	var done := 0
	var discs: Array = [] # [{pos, r}] — под ними земля города плоская и утоплена
	for d in city.districts():
		var g: Node = d.get_node_or_null("Ground")
		if g == null:
			continue
		for mi in g.get_children():
			if mi is MeshInstance3D and mi.mesh is CylinderMesh:
				var cyl := mi.mesh as CylinderMesh
				if cyl.top_radius >= 6.0 and cyl.height <= 0.6:
					discs.append({"pos": mi.global_position, "r": cyl.top_radius})
					var xf: Transform3D = mi.global_transform
					mi.mesh = build_disc(cyl.top_radius, cyl.height * 0.5, 1.5, func(x: float, z: float) -> Vector3: return xf * Vector3(x, 0, z))
					mi.material_override = _flat_mat(mi.material_override)
					done += 1
	var ground: Node = city.get_node_or_null("Ground/M0")
	if ground is MeshInstance3D and ground.mesh is BoxMesh:
		var gm := ground as MeshInstance3D
		var bm := gm.mesh as BoxMesh
		var xf: Transform3D = gm.global_transform
		var under_disc := func(wp: Vector3) -> bool:
			for dd in discs:
				if Vector2(wp.x - dd["pos"].x, wp.z - dd["pos"].z).length() < float(dd["r"]) - CELL:
					return true
			return false
		var in_d := func(wp: Vector3) -> bool: return city.district_at(wp) != null or bool(under_disc.call(wp))
		gm.mesh = build_grid(bm.size.x, bm.size.z, bm.size.y * 0.5, CELL,
			func(x: float, z: float) -> Vector3: return xf * Vector3(x, 0, z), in_d, func(_wp: Vector3) -> bool: return false)
		gm.material_override = _flat_mat(gm.material_override)
		done += 1
	_scatter(w, city, discs)
	return done


## Галька / кирпичи / камни по пустырям. Без коллизии, лежат на рельефе.
static func _scatter(w, city, discs: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var roads: Node = city.roads()
	var segs: PackedVector4Array = roads.segments if roads and "segments" in roads else PackedVector4Array()
	var half_w: float = (float(roads.width) * 0.5 + float(roads.sidewalk) + 1.0) if roads else 6.6
	var ok := func(p: Vector3) -> bool:
		if city.district_at(p) != null:
			return false
		for dd in discs:
			if Vector2(p.x - dd["pos"].x, p.z - dd["pos"].z).length() < float(dd["r"]) + 1.0:
				return false
		for s in segs:
			if _seg_dist(p.x, p.z, s.x, s.y, s.z, s.w) < half_w:
				return false
		return true
	var kinds := [
		{"n": PEBBLES, "mesh": LowPoly.sphere(0.09, 6, 3), "c": Color(0.58, 0.5, 0.42), "cv": 0.12, "s": Vector2(0.5, 1.3), "flat": 0.55},
		{"n": BRICKS, "mesh": LowPoly.chamfer_box(Vector3(0.24, 0.07, 0.11), 0.008), "c": Color(0.6, 0.28, 0.18), "cv": 0.08, "s": Vector2(0.9, 1.1), "flat": 1.0},
		{"n": ROCKS, "mesh": LowPoly.sphere(0.3, 7, 4), "c": Color(0.5, 0.44, 0.4), "cv": 0.1, "s": Vector2(0.6, 1.6), "flat": 0.6},
	]
	for k in kinds:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = k["mesh"]
		var xfs: Array[Transform3D] = []
		var cols: Array[Color] = []
		var tries := 0
		while xfs.size() < int(k["n"]) and tries < int(k["n"]) * 6:
			tries += 1
			var p := Vector3(rng.randf_range(-190.0, 190.0), 0.0, rng.randf_range(-125.0, 185.0))
			if not bool(ok.call(p)):
				continue
			var h := height(p.x, p.z, false)
			var sc: float = rng.randf_range(k["s"].x, k["s"].y)
			var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * float(k["flat"]), sc))
			var aabb_h: float = (k["mesh"] as Mesh).get_aabb().size.y * sc * float(k["flat"])
			xfs.append(Transform3D(b, Vector3(p.x, h + aabb_h * 0.35, p.z)))
			var cv := float(k["cv"])
			cols.append((k["c"] as Color) * Color(1.0 + rng.randf_range(-cv, cv), 1.0 + rng.randf_range(-cv, cv), 1.0 + rng.randf_range(-cv, cv)))
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
			mm.set_instance_color(i, cols[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Scatter_%d" % kinds.find(k)
		mmi.multimesh = mm
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.albedo_color = Color(1, 1, 1)
		m.roughness = 1.0
		mmi.material_override = m
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		w.add_child(mmi)


static func _seg_dist(px: float, pz: float, x1: float, z1: float, x2: float, z2: float) -> float:
	var dx := x2 - x1
	var dz := z2 - z1
	var len2 := dx * dx + dz * dz
	if len2 < 0.0001:
		return Vector2(px - x1, pz - z1).length()
	var t := clampf(((px - x1) * dx + (pz - z1) * dz) / len2, 0.0, 1.0)
	return Vector2(px - (x1 + dx * t), pz - (z1 + dz * t)).length()
