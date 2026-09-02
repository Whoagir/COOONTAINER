class_name ArchetypeMeshes
## Процедурные лоу-поли меши архетипов (§7.1). Вещь = карточка + архетип, не тысяча сцен.
## Каждый билдер собирает Node3D из примитивов + список коллайдеров. Origin — низ вещи (y=0 на полу).
## Именование узлов имеет смысл: "Lid*" — крышка (открывается), "Wall*" — стенки сумки (разъезжаются),
## "Drawer*" — ящики (выдвигаются), "Beam" — фонарь.

class Ctx:
	var root: Node3D
	var shapes: Array = []
	var d: Vector3
	var c1: Color
	var c2: Color
	var arch: Archetype
	var def: ItemDef

	func lift(c: Color) -> Color:
		var lum := c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
		if lum >= 0.25 or lum < 0.08:
			return c
		var s := 0.28 / lum
		return Color(minf(c.r * s, 1.0), minf(c.g * s, 1.0), minf(c.b * s, 1.0), c.a)

	func mat(c: Color, rough := 0.7, metal := 0.0, tex_name := "", emissive := false, keep_dark := false) -> StandardMaterial3D:
		var m := StandardMaterial3D.new()
		m.albedo_color = c if keep_dark else lift(c)
		m.roughness = rough
		m.metallic = metal
		if tex_name != "":
			var t := ArchetypeMeshes.tex(tex_name)
			if t:
				m.albedo_texture = t
				m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
				if emissive:
					m.emission_enabled = true
					m.emission_texture = t
					m.emission = Color(1, 1, 1)
					m.emission_energy_multiplier = 0.6
		return m

	## Хэш карточки → стабильный выбор варианта (картина/книга/плакат).
	func pick(options: Array) -> String:
		if options.is_empty():
			return ""
		var h := def.id.hash() if def else randi()
		return options[h % options.size()]

	## Текстура по тегу карточки: тег "tex:<name>" переопределяет выбор.
	func tagged_tex(default_options: Array) -> String:
		if def:
			for t in def.tags:
				if t.begins_with("tex:"):
					return t.trim_prefix("tex:")
		return pick(default_options)

	func box(size: Vector3, pos: Vector3, c: Color, rot := Vector3.ZERO, p_name := "", parent: Node3D = null, collide := true, bevel := true, keep_dark := false) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		var min_d := minf(size.x, minf(size.y, size.z))
		if bevel and min_d > 0.08:
			var bv := clampf(min_d * 0.08, 0.012, 0.05)
			mi.mesh = LowPoly.chamfer_box(size, bv)
		else:
			var bm := BoxMesh.new()
			bm.size = size
			mi.mesh = bm
		mi.material_override = mat(c, 0.7, 0.0, "", false, keep_dark)
		mi.position = pos
		mi.rotation = rot
		if p_name != "":
			mi.name = p_name
		(parent if parent else root).add_child(mi)
		if collide and parent == null:
			var s := BoxShape3D.new()
			s.size = size
			shapes.append({"shape": s, "xform": Transform3D(Basis.from_euler(rot), pos)})
		return mi

	func cyl(r_top: float, r_bot: float, h: float, pos: Vector3, c: Color, rot := Vector3.ZERO, seg := 8, p_name := "", collide := true, parent: Node3D = null, keep_dark := false) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		var radial := clampi(seg, 3, 8)
		if maxf(maxf(r_top, r_bot), h * 0.45) >= 0.18:
			radial = clampi(seg, 3, 10)
		mi.mesh = LowPoly.cylinder(r_top, r_bot, h, radial)
		mi.material_override = mat(c, 0.7, 0.0, "", false, keep_dark)
		mi.position = pos
		mi.rotation = rot
		if p_name != "":
			mi.name = p_name
		(parent if parent else root).add_child(mi)
		if collide and parent == null:
			var s := CylinderShape3D.new()
			s.radius = maxf(r_top, r_bot)
			s.height = h
			shapes.append({"shape": s, "xform": Transform3D(Basis.from_euler(rot), pos)})
		return mi

	func sph(r: float, pos: Vector3, c: Color, collide := true, p_name := "", parent: Node3D = null, keep_dark := false) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		mi.mesh = LowPoly.sphere(r, 8, 4)
		mi.material_override = mat(c, 0.7, 0.0, "", false, keep_dark)
		mi.position = pos
		if p_name != "":
			mi.name = p_name
		(parent if parent else root).add_child(mi)
		if collide and parent == null:
			var s := SphereShape3D.new()
			s.radius = r
			shapes.append({"shape": s, "xform": Transform3D(Basis(), pos)})
		return mi

	func capsule(r: float, h: float, pos: Vector3, c: Color, rot := Vector3.ZERO, collide := true) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		mi.mesh = LowPoly.capsule(r, h, 8, 3)
		mi.material_override = mat(c)
		mi.position = pos
		mi.rotation = rot
		root.add_child(mi)
		if collide:
			var s := CapsuleShape3D.new()
			s.radius = r
			s.height = h
			shapes.append({"shape": s, "xform": Transform3D(Basis.from_euler(rot), pos)})
		return mi

	func torus(r_in: float, r_out: float, pos: Vector3, c: Color, rot := Vector3.ZERO, keep_dark := false) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = r_in
		tm.outer_radius = r_out
		tm.rings = 8
		tm.ring_segments = 6
		mi.mesh = LowPoly.facet(tm, "tor|%.3f|%.3f|8|6" % [r_in, r_out])
		mi.material_override = mat(c, 0.7, 0.0, "", false, keep_dark)
		mi.position = pos
		mi.rotation = rot
		root.add_child(mi)
		return mi

	func prism(size: Vector3, pos: Vector3, c: Color, rot := Vector3.ZERO) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = size
		mi.mesh = pm
		mi.material_override = mat(c)
		mi.position = pos
		mi.rotation = rot
		root.add_child(mi)
		var s := BoxShape3D.new()
		s.size = size
		shapes.append({"shape": s, "xform": Transform3D(Basis.from_euler(rot), pos)})
		return mi

	func node(p_name: String, pos: Vector3, parent: Node3D = null) -> Node3D:
		var n := Node3D.new()
		n.name = p_name
		n.position = pos
		(parent if parent else root).add_child(n)
		return n

	func only_box_shape(size: Vector3, pos: Vector3) -> void:
		shapes.clear()
		var s := BoxShape3D.new()
		s.size = size
		shapes.append({"shape": s, "xform": Transform3D(Basis(), pos)})

	func wear_skirt(body_size: Vector3, body_pos: Vector3, c: Color) -> void:
		var sh := maxf(body_size.y * 0.15, 0.025)
		var ss := Vector3(body_size.x * 1.05, sh, body_size.z * 1.05)
		var sp := Vector3(body_pos.x, body_pos.y - body_size.y * 0.5 + sh * 0.5, body_pos.z)
		box(ss, sp, c.darkened(0.12).lerp(Color(0.48, 0.24, 0.10), 0.55), Vector3.ZERO, "", null, false)


const TEX_DIR := "res://assets/textures/"
static var _tex_cache: Dictionary = {}


static func tex(name: String) -> Texture2D:
	if _tex_cache.has(name):
		return _tex_cache[name]
	var path := TEX_DIR + name + ".png"
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path)
	_tex_cache[name] = t
	return t


const PAINTINGS := ["paint_hamster_lisa", "paint_sad_clown", "paint_splatter", "paint_landscape"]
const POSTERS := ["tex_flyer_hamster", "tex_poster_auction", "ad_pricebot", "ad_casino", "ad_carmarket"]
const BOOKS := ["tex_book_rich", "tex_book_secret"]


static func _tint(arch: Archetype, def: ItemDef) -> Color:
	if def.color == Color.WHITE:
		return arch.base_color
	return def.color


static func build(arch: Archetype, def: ItemDef) -> Dictionary:
	var ctx := Ctx.new()
	ctx.root = Node3D.new()
	ctx.d = arch.dims
	ctx.arch = arch
	ctx.def = def
	ctx.c1 = _tint(arch, def)
	ctx.c2 = arch.secondary_color
	var fn := "_b_" + arch.builder
	if _has_static(fn):
		Callable(ArchetypeMeshes, fn).call(ctx)
	else:
		_b_box(ctx)
	return {"root": ctx.root, "shapes": ctx.shapes}


static var _method_names: Dictionary = {}


static func _has_static(fn: String) -> bool:
	if _method_names.is_empty():
		var script: GDScript = load("res://item/ArchetypeMeshes.gd")
		for m in script.get_script_method_list():
			_method_names[m["name"]] = true
	return _method_names.has(fn)


static func builder_names() -> Array:
	_has_static("")
	var out: Array = []
	for k in _method_names:
		if k.begins_with("_b_"):
			out.append(k.trim_prefix("_b_"))
	out.sort()
	return out


## Кучка осколков после разлома.
static func build_pile(arch: Archetype, def: ItemDef) -> Dictionary:
	var ctx := Ctx.new()
	ctx.root = Node3D.new()
	ctx.d = arch.dims * def.scale
	ctx.arch = arch
	ctx.def = def
	ctx.c1 = _tint(arch, def)
	ctx.c2 = arch.secondary_color
	var w := maxf(0.12, ctx.d.x * 0.7)
	var l := maxf(0.12, ctx.d.z * 0.7)
	for i in 6:
		var sz := Vector3(w * randf_range(0.2, 0.4), 0.02, l * randf_range(0.2, 0.4))
		var pos := Vector3(randf_range(-w * 0.35, w * 0.35), 0.012 + 0.01 * (i % 2), randf_range(-l * 0.35, l * 0.35))
		ctx.box(sz, pos, ctx.c1.lerp(ctx.c2, randf() * 0.6), Vector3(0, randf() * TAU, randf_range(-0.2, 0.2)), "", null, false)
	if def.tags.has("gem"):
		ctx.sph(0.02, Vector3(0, 0.03, 0), Color(1, 0.3, 0.6), false)
	ctx.only_box_shape(Vector3(w, 0.04, l), Vector3(0, 0.02, 0))
	return {"root": ctx.root, "shapes": ctx.shapes}


# ============================================================ коробки / тара

static func _b_box(c: Ctx) -> void:
	var b := c.box(c.d, Vector3(0, c.d.y * 0.5, 0), Color.WHITE.lerp(c.c1, 0.35), Vector3.ZERO, "", null, true, false)
	b.material_override = c.mat(Color.WHITE.lerp(c.c1, 0.35), 0.9, 0.0, "tex_cardboard")
	c.box(Vector3(c.d.x * 1.02, 0.03, c.d.z * 0.25), Vector3(0, c.d.y + 0.005, 0), c.c2, Vector3.ZERO, "", null, false)


static func _b_box_small(c: Ctx) -> void:
	_b_box(c)


static func _b_crate(c: Ctx) -> void:
	var b := c.box(c.d, Vector3(0, c.d.y * 0.5, 0), c.c1, Vector3.ZERO, "", null, true, false)
	b.material_override = c.mat(Color.WHITE.lerp(c.c1, 0.3), 0.85, 0.0, "tex_planks")
	for i in 3:
		var y := c.d.y * (0.15 + 0.35 * i)
		c.box(Vector3(c.d.x * 1.04, 0.03, c.d.z * 1.04), Vector3(0, y, 0), c.c2, Vector3.ZERO, "", null, false)


static func _b_suitcase(c: Ctx) -> void:
	var h := c.d.y
	var w := c.d.x
	var dp := c.d.z
	var body := c.c1.darkened(0.08)
	var metal := Color(0.28, 0.26, 0.24)
	var strap := c.c2.darkened(0.22)
	c.box(Vector3(w * 0.96, h * 0.52, dp * 0.96), Vector3(0, h * 0.26, 0), body)
	var lid := c.node("Lid", Vector3(0, h * 0.52, -dp * 0.48))
	c.box(Vector3(w * 0.96, h * 0.48, dp * 0.96), Vector3(0, h * 0.24, dp * 0.48), body, Vector3.ZERO, "", lid)
	var gx := w * 0.46
	var gz := dp * 0.46
	var signs: Array[float] = [-1.0, 1.0]
	for sx in signs:
		for sz in signs:
			c.box(Vector3(0.085, h * 0.96, 0.085), Vector3(gx * sx, h * 0.5, gz * sz), metal, Vector3.ZERO, "", null, false)
	var strap_xs: Array[float] = [-0.22, 0.22]
	for sx in strap_xs:
		c.box(Vector3(0.062, h * 1.04, dp * 1.0), Vector3(w * sx, h * 0.52, 0), strap, Vector3.ZERO, "", null, false)
	c.box(Vector3(0.03, 0.045, 0.035), Vector3(-w * 0.1, h + 0.02, 0), body, Vector3.ZERO, "", null, false)
	c.box(Vector3(0.03, 0.045, 0.035), Vector3(w * 0.1, h + 0.02, 0), body, Vector3.ZERO, "", null, false)
	c.box(Vector3(w * 0.28, 0.032, 0.042), Vector3(0, h + 0.052, 0), body.lightened(0.04), Vector3.ZERO, "", null, false)
	c.box(Vector3(0.085, 0.042, 0.032), Vector3(0, h * 0.5, dp * 0.5), Color(0.62, 0.56, 0.38), Vector3.ZERO, "", null, false)
	c.only_box_shape(c.d, Vector3(0, h * 0.5, 0))


static func _b_chest(c: Ctx) -> void:
	_b_suitcase(c)


static func _b_safe(c: Ctx) -> void:
	c.box(c.d, Vector3(0, c.d.y * 0.5, 0), c.c1)
	c.wear_skirt(c.d, Vector3(0, c.d.y * 0.5, 0), c.c1)
	c.box(Vector3(c.d.x * 0.85, c.d.y * 0.85, 0.03), Vector3(0, c.d.y * 0.5, c.d.z * 0.5), c.c1.darkened(0.2), Vector3.ZERO, "Lid", null, false)
	c.cyl(0.06, 0.06, 0.04, Vector3(-c.d.x * 0.2, c.d.y * 0.5, c.d.z * 0.52), Color(0.8, 0.8, 0.85), Vector3(PI / 2, 0, 0), 10, "", false)
	c.box(Vector3(0.04, 0.16, 0.03), Vector3(c.d.x * 0.2, c.d.y * 0.5, c.d.z * 0.53), Color(0.8, 0.8, 0.85), Vector3.ZERO, "", null, false)


static func _b_barrel(c: Ctx) -> void:
	c.cyl(c.d.x * 0.5, c.d.x * 0.5, c.d.y, Vector3(0, c.d.y * 0.5, 0), c.c1, Vector3.ZERO, 14)
	c.cyl(c.d.x * 0.54, c.d.x * 0.56, c.d.y * 0.14, Vector3(0, c.d.y * 0.07, 0), c.c1.darkened(0.25).lerp(Color(0.42, 0.26, 0.14), 0.4), Vector3.ZERO, 10, "", false)
	for y in [0.2, 0.8]:
		c.torus(c.d.x * 0.48, c.d.x * 0.53, Vector3(0, c.d.y * y, 0), c.c2, Vector3(PI / 2, 0, 0))


static func _b_bucket(c: Ctx) -> void:
	c.cyl(c.d.x * 0.5, c.d.x * 0.4, c.d.y, Vector3(0, c.d.y * 0.5, 0), c.c1, Vector3.ZERO, 12)
	c.torus(0.005, 0.012, Vector3(0, c.d.y * 1.1, 0), c.c2, Vector3(0, 0, 0))


static func _b_toolbox(c: Ctx) -> void:
	var red := Color(0.98, 0.30, 0.14).lerp(c.c1, 0.08)
	c.box(Vector3(c.d.x, c.d.y * 0.7, c.d.z), Vector3(0, c.d.y * 0.35, 0), red)
	c.wear_skirt(Vector3(c.d.x, c.d.y * 0.7, c.d.z), Vector3(0, c.d.y * 0.35, 0), red)
	var lid := c.node("Lid", Vector3(0, c.d.y * 0.7, -c.d.z * 0.5))
	c.box(Vector3(c.d.x, c.d.y * 0.3, c.d.z), Vector3(0, c.d.y * 0.15, c.d.z * 0.5), red.lightened(0.08), Vector3.ZERO, "", lid)
	c.box(Vector3(c.d.x * 0.55, 0.03, 0.03), Vector3(0, c.d.y * 1.05, 0), Color(0.72, 0.70, 0.66), Vector3.ZERO, "", null, false)
	c.box(Vector3(0.04, 0.03, 0.02), Vector3(-c.d.x * 0.22, c.d.y * 0.42, c.d.z * 0.52), Color(0.78, 0.76, 0.70), Vector3.ZERO, "", null, false)
	c.box(Vector3(0.04, 0.03, 0.02), Vector3(c.d.x * 0.22, c.d.y * 0.42, c.d.z * 0.52), Color(0.78, 0.76, 0.70), Vector3.ZERO, "", null, false)
	c.only_box_shape(c.d, Vector3(0, c.d.y * 0.5, 0))


static func _b_jewelry_box(c: Ctx) -> void:
	_b_toolbox(c)


# ============================================================ посуда / хрупкое

static func _b_vase(c: Ctx) -> void:
	var h := c.d.y
	var r := c.d.x * 0.5
	var glaze := c.c1.darkened(0.04)
	var band := c.c2.lightened(0.06)
	if absf(glaze.r - band.r) + absf(glaze.g - band.g) + absf(glaze.b - band.b) < 0.45:
		band = Color(0.28, 0.52, 0.72)
	c.cyl(r * 0.44, r * 0.52, h * 0.10, Vector3(0, h * 0.05, 0), glaze.darkened(0.10), Vector3.ZERO, 8, "", false)
	c.sph(r * 0.98, Vector3(0, h * 0.36, 0), glaze, false)
	c.cyl(r * 1.04, r * 1.04, h * 0.07, Vector3(0, h * 0.38, 0), band, Vector3.ZERO, 8, "", false)
	c.cyl(r * 0.38, r * 0.78, h * 0.18, Vector3(0, h * 0.58, 0), glaze, Vector3.ZERO, 8, "", false)
	c.cyl(r * 0.34, r * 0.38, h * 0.16, Vector3(0, h * 0.75, 0), glaze, Vector3.ZERO, 8, "", false)
	c.cyl(r * 0.42, r * 0.42, h * 0.055, Vector3(0, h * 0.78, 0), band, Vector3.ZERO, 8, "", false)
	c.cyl(r * 0.64, r * 0.34, h * 0.12, Vector3(0, h * 0.89, 0), glaze.lerp(c.c2, 0.3), Vector3.ZERO, 8, "", false)
	var s := CylinderShape3D.new()
	s.radius = r
	s.height = h
	c.shapes.append({"shape": s, "xform": Transform3D(Basis(), Vector3(0, h * 0.5, 0))})


static func _b_vase_tall(c: Ctx) -> void:
	var h := c.d.y
	var r := c.d.x * 0.5
	var glaze := c.c1.darkened(0.03)
	var band := c.c2.lightened(0.06)
	if absf(glaze.r - band.r) + absf(glaze.g - band.g) + absf(glaze.b - band.b) < 0.45:
		band = Color(0.28, 0.52, 0.72)
	c.cyl(r * 0.42, r * 0.52, h * 0.08, Vector3(0, h * 0.04, 0), glaze.darkened(0.10), Vector3.ZERO, 8, "", false)
	c.sph(r * 0.92, Vector3(0, h * 0.28, 0), glaze, false)
	c.cyl(r * 0.98, r * 0.98, h * 0.055, Vector3(0, h * 0.30, 0), band, Vector3.ZERO, 8, "", false)
	c.cyl(r * 0.34, r * 0.72, h * 0.16, Vector3(0, h * 0.46, 0), glaze, Vector3.ZERO, 8, "", false)
	c.cyl(r * 0.28, r * 0.34, h * 0.28, Vector3(0, h * 0.68, 0), glaze, Vector3.ZERO, 8, "", false)
	c.cyl(r * 0.38, r * 0.38, h * 0.05, Vector3(0, h * 0.62, 0), band, Vector3.ZERO, 8, "", false)
	c.cyl(r * 0.54, r * 0.28, h * 0.10, Vector3(0, h * 0.90, 0), glaze.lerp(c.c2, 0.32), Vector3.ZERO, 8, "", false)
	var s := CylinderShape3D.new()
	s.radius = r
	s.height = h
	c.shapes.append({"shape": s, "xform": Transform3D(Basis(), Vector3(0, h * 0.5, 0))})


static func _b_plate(c: Ctx) -> void:
	var r := c.d.x * 0.5
	c.cyl(r, r * 0.6, c.d.y, Vector3(0, c.d.y * 0.5, 0), c.c1, Vector3.ZERO, 16)
	c.torus(r * 0.7, r * 0.72, Vector3(0, c.d.y, 0), c.c2, Vector3(PI / 2, 0, 0))


static func _b_plate_stack(c: Ctx) -> void:
	var r := c.d.x * 0.5
	var n := 5
	for i in n:
		c.cyl(r, r * 0.6, c.d.y / n, Vector3(0, c.d.y / n * (i + 0.5), 0), c.c1.lerp(c.c2, 0.1 * i), Vector3.ZERO, 14, "", false)
	var s := CylinderShape3D.new()
	s.radius = r
	s.height = c.d.y
	c.shapes.append({"shape": s, "xform": Transform3D(Basis(), Vector3(0, c.d.y * 0.5, 0))})


static func _b_bowl(c: Ctx) -> void:
	var r := c.d.x * 0.5
	c.cyl(r, r * 0.5, c.d.y, Vector3(0, c.d.y * 0.5, 0), c.c1, Vector3.ZERO, 14)


static func _b_cup(c: Ctx) -> void:
	var r := c.d.x * 0.5
	c.cyl(r, r * 0.85, c.d.y, Vector3(0, c.d.y * 0.5, 0), c.c1, Vector3.ZERO, 12)
	c.torus(0.008, 0.02, Vector3(r * 1.1, c.d.y * 0.5, 0), c.c2, Vector3(0, 0, PI / 2))


static func _b_kettle(c: Ctx) -> void:
	var r := c.d.x * 0.5
	c.cyl(r * 0.7, r, c.d.y * 0.7, Vector3(0, c.d.y * 0.35, 0), c.c1, Vector3.ZERO, 12)
	c.cyl(r * 0.25, r * 0.4, c.d.y * 0.2, Vector3(0, c.d.y * 0.8, 0), c.c1, Vector3.ZERO, 10, "Lid", false)
	c.sph(0.02, Vector3(0, c.d.y * 0.95, 0), c.c2, false)
	c.cyl(0.015, 0.025, c.d.y * 0.5, Vector3(r * 0.9, c.d.y * 0.6, 0), c.c1, Vector3(0, 0, -0.9), 8, "", false)
	c.torus(0.01, 0.025, Vector3(-r * 1.05, c.d.y * 0.55, 0), c.c2, Vector3(0, 0, PI / 2))


static func _b_teapot(c: Ctx) -> void:
	_b_kettle(c)


static func _b_bottle(c: Ctx) -> void:
	var r := c.d.x * 0.5
	var h := c.d.y
	c.cyl(r, r, h * 0.62, Vector3(0, h * 0.31, 0), c.c1, Vector3.ZERO, 12)
	c.cyl(r * 0.35, r, h * 0.18, Vector3(0, h * 0.71, 0), c.c1, Vector3.ZERO, 12, "", false)
	c.cyl(r * 0.35, r * 0.35, h * 0.2, Vector3(0, h * 0.9, 0), c.c1, Vector3.ZERO, 10)
	c.cyl(r * 0.38, r * 0.38, h * 0.05, Vector3(0, h * 0.98, 0), c.c2, Vector3.ZERO, 10, "", false)
	c.box(Vector3(r * 1.6, h * 0.25, 0.002), Vector3(0, h * 0.35, r * 1.0), Color(0.95, 0.92, 0.8), Vector3.ZERO, "", null, false)


static func _b_jar(c: Ctx) -> void:
	var r := c.d.x * 0.5
	c.cyl(r, r, c.d.y * 0.85, Vector3(0, c.d.y * 0.425, 0), c.c1, Vector3.ZERO, 12)
	c.cyl(r * 0.9, r * 0.9, c.d.y * 0.15, Vector3(0, c.d.y * 0.925, 0), c.c2, Vector3.ZERO, 12, "Lid", false)


static func _b_can_paint(c: Ctx) -> void:
	var r := c.d.x * 0.5
	c.cyl(r, r, c.d.y, Vector3(0, c.d.y * 0.5, 0), Color(0.75, 0.75, 0.78), Vector3.ZERO, 14)
	c.box(Vector3(r * 1.9, c.d.y * 0.5, 0.002), Vector3(0, c.d.y * 0.5, r), c.c1, Vector3.ZERO, "", null, false)
	c.cyl(r * 0.95, r * 0.95, 0.01, Vector3(0, c.d.y + 0.005, 0), c.c1, Vector3.ZERO, 14, "Lid", false)
	c.torus(0.005, 0.012, Vector3(0, c.d.y * 1.15, 0), Color(0.6, 0.6, 0.62))


static func _b_canister(c: Ctx) -> void:
	c.box(c.d, Vector3(0, c.d.y * 0.5, 0), c.c1)
	c.cyl(0.03, 0.03, 0.06, Vector3(c.d.x * 0.3, c.d.y + 0.03, 0), c.c2, Vector3.ZERO, 8, "", false)
	c.box(Vector3(c.d.x * 0.5, 0.03, 0.03), Vector3(-c.d.x * 0.1, c.d.y + 0.05, 0), c.c1.darkened(0.3), Vector3.ZERO, "", null, false)


static func _b_jug(c: Ctx) -> void:
	c.box(Vector3(c.d.x, c.d.y * 0.8, c.d.z), Vector3(0, c.d.y * 0.4, 0), c.c1)
	c.cyl(0.03, 0.035, c.d.y * 0.2, Vector3(0, c.d.y * 0.9, 0), c.c2, Vector3.ZERO, 8, "", false)


static func _b_glass(c: Ctx) -> void:
	c.cyl(c.d.x * 0.5, c.d.x * 0.4, c.d.y, Vector3(0, c.d.y * 0.5, 0), c.c1, Vector3.ZERO, 10)


static func _b_perfume(c: Ctx) -> void:
	c.box(Vector3(c.d.x, c.d.y * 0.75, c.d.z), Vector3(0, c.d.y * 0.375, 0), c.c1)
	c.cyl(c.d.x * 0.25, c.d.x * 0.25, c.d.y * 0.25, Vector3(0, c.d.y * 0.875, 0), c.c2, Vector3.ZERO, 8, "", false)


static func _b_candle(c: Ctx) -> void:
	c.cyl(c.d.x * 0.5, c.d.x * 0.5, c.d.y, Vector3(0, c.d.y * 0.5, 0), c.c1, Vector3.ZERO, 10)
	c.cyl(0.003, 0.003, 0.02, Vector3(0, c.d.y + 0.01, 0), Color(0.1, 0.1, 0.1), Vector3.ZERO, 6, "", false)


# ============================================================ техника

static func _b_tv_plasma(c: Ctx) -> void:
	var w := c.d.x
	var h := c.d.y
	var t := c.d.z
	var bezel := Color(0.62, 0.58, 0.50)
	c.box(Vector3(w * 0.45, 0.04, maxf(t * 4.0, 0.22)), Vector3(0, 0.02, 0), Color(0.50, 0.48, 0.45))
	c.box(Vector3(0.07, h * 0.16, 0.07), Vector3(0, h * 0.11, 0), Color(0.48, 0.46, 0.44), Vector3.ZERO, "", null, false)
	c.box(Vector3(w, h * 0.85, 0.12), Vector3(0, h * 0.575, 0), bezel)
	var screen := c.box(Vector3(w * 0.70, h * 0.56, 0.006), Vector3(0, h * 0.58, 0.064), Color(0.10, 0.11, 0.12), Vector3.ZERO, "Screen", null, false, false, true)
	screen.material_override = c.mat(Color(0.75, 0.75, 0.72), 0.28, 0.0, "tex_tv_screen", true)
	c.sph(0.010, Vector3(w * 0.42, h * 0.22, 0.06), Color(0.95, 0.25, 0.18), false)


static func _b_tv_crt(c: Ctx) -> void:
	var w := c.d.x
	var h := c.d.y
	var t := c.d.z
	var plastic := Color(0.62, 0.58, 0.50)
	c.box(Vector3(w, h, t * 0.62), Vector3(0, h * 0.5, t * 0.12), plastic)
	c.box(Vector3(w * 0.70, h * 0.60, t * 0.42), Vector3(0, h * 0.48, -t * 0.18), plastic.darkened(0.06), Vector3.ZERO, "", null, false)
	c.sph(minf(w, h) * 0.30, Vector3(0, h * 0.50, -t * 0.28), plastic.darkened(0.08), false)
	var front_z := t * 0.42
	var scr_w := w * 0.58
	var scr_h := h * 0.52
	var scr_x := -w * 0.08
	c.box(Vector3(scr_w + 0.16, scr_h + 0.16, 0.08), Vector3(scr_x, h * 0.54, front_z + 0.010), plastic.darkened(0.06), Vector3.ZERO, "", null, false)
	var scr := c.box(Vector3(scr_w * 0.88, scr_h * 0.86, 0.012), Vector3(scr_x, h * 0.54, front_z - 0.028), Color(0.14, 0.15, 0.16), Vector3.ZERO, "Screen", null, false, false, true)
	scr.material_override = c.mat(Color(0.62, 0.62, 0.58), 0.22, 0.0, "tex_tv_screen", true)
	var lens := MeshInstance3D.new()
	var cap_r := minf(scr_w, scr_h) * 0.50
	lens.mesh = LowPoly.sphere(cap_r, 8, 3)
	lens.scale = Vector3((scr_w * 0.92) / (cap_r * 2.0), (scr_h * 0.90) / (cap_r * 2.0), 0.42)
	lens.position = Vector3(scr_x, h * 0.54, front_z + 0.028)
	lens.material_override = c.mat(Color(0.34, 0.36, 0.38), 0.12, 0.18, "", false, true)
	c.root.add_child(lens)
	var px := w * 0.39
	c.box(Vector3(w * 0.18, h * 0.74, 0.045), Vector3(px, h * 0.50, front_z + 0.016), plastic.darkened(0.08), Vector3.ZERO, "", null, false)
	var knob := Color(0.42, 0.38, 0.32).lerp(c.c2, 0.3)
	c.cyl(0.036, 0.040, 0.048, Vector3(px, h * 0.68, front_z + 0.040), knob, Vector3(PI / 2, 0, 0), 8, "", false)
	c.cyl(0.026, 0.030, 0.040, Vector3(px, h * 0.50, front_z + 0.038), knob, Vector3(PI / 2, 0, 0), 8, "", false)
	for i in 4:
		c.box(Vector3(w * 0.11, 0.009, 0.009), Vector3(px, h * 0.24 + float(i) * 0.024, front_z + 0.028), Color(0.22, 0.20, 0.18), Vector3.ZERO, "", null, false)
	c.only_box_shape(c.d, Vector3(0, h * 0.5, 0))


static func _b_monitor(c: Ctx) -> void:
	_b_tv_plasma(c)


static func _b_laptop(c: Ctx) -> void:
	c.box(Vector3(c.d.x, 0.02, c.d.z), Vector3(0, 0.01, 0), c.c1)
	var lid := c.node("Lid", Vector3(0, 0.02, -c.d.z * 0.5))
	c.box(Vector3(c.d.x, 0.012, c.d.z), Vector3(0, 0.006, c.d.z * 0.5), c.c1, Vector3.ZERO, "", lid)
	lid.rotation.x = -1.9
	c.box(Vector3(c.d.x * 0.85, 0.002, c.d.z * 0.5), Vector3(0, 0.022, -c.d.z * 0.05), Color(0.2, 0.2, 0.22), Vector3.ZERO, "", null, false)
	c.only_box_shape(Vector3(c.d.x, c.d.y, c.d.z), Vector3(0, c.d.y * 0.5, 0))


static func _b_phone(c: Ctx) -> void:
	c.box(c.d, Vector3(0, c.d.y * 0.5, 0), c.c1)
	c.box(Vector3(c.d.x * 0.9, 0.002, c.d.z * 0.9), Vector3(0, c.d.y + 0.001, 0), Color(0.05, 0.05, 0.08), Vector3.ZERO, "", null, false)


static func _b_tablet(c: Ctx) -> void:
	_b_phone(c)


static func _b_camera(c: Ctx) -> void:
	c.box(c.d, Vector3(0, c.d.y * 0.5, 0), c.c1)
	c.cyl(c.d.y * 0.35, c.d.y * 0.4, 0.05, Vector3(0, c.d.y * 0.5, c.d.z * 0.5 + 0.02), c.c2, Vector3(PI / 2, 0, 0), 12, "", false)
	c.box(Vector3(0.04, 0.02, 0.03), Vector3(c.d.x * 0.3, c.d.y + 0.01, 0), c.c2, Vector3.ZERO, "", null, false)


static func _b_boombox(c: Ctx) -> void:
	var silver := Color(0.74, 0.76, 0.80)
	c.box(c.d, Vector3(0, c.d.y * 0.5, 0), silver)
	var xs: Array[float] = [-0.32, 0.32]
	for x in xs:
		c.cyl(c.d.y * 0.32, c.d.y * 0.32, 0.02, Vector3(c.d.x * x, c.d.y * 0.5, c.d.z * 0.5), Color(0.28, 0.28, 0.30), Vector3(PI / 2, 0, 0), 8, "", false)
		c.cyl(c.d.y * 0.12, c.d.y * 0.12, 0.012, Vector3(c.d.x * x, c.d.y * 0.5, c.d.z * 0.52), Color(0.45, 0.45, 0.48), Vector3(PI / 2, 0, 0), 8, "", false)
	c.box(Vector3(c.d.x * 0.18, c.d.y * 0.12, 0.012), Vector3(0, c.d.y * 0.62, c.d.z * 0.51), Color(0.95, 0.25, 0.18), Vector3.ZERO, "", null, false)
	c.box(Vector3(c.d.x * 0.10, c.d.y * 0.10, 0.012), Vector3(-c.d.x * 0.08, c.d.y * 0.38, c.d.z * 0.51), Color(0.20, 0.75, 0.35), Vector3.ZERO, "", null, false)
	c.box(Vector3(c.d.x * 0.10, c.d.y * 0.10, 0.012), Vector3(c.d.x * 0.08, c.d.y * 0.38, c.d.z * 0.51), Color(0.95, 0.78, 0.18), Vector3.ZERO, "", null, false)
	c.box(Vector3(c.d.x * 0.7, 0.02, 0.02), Vector3(0, c.d.y + 0.08, 0), Color(0.55, 0.56, 0.58), Vector3.ZERO, "", null, false)
	for x in xs:
		c.box(Vector3(0.02, 0.09, 0.02), Vector3(c.d.x * (x * 1.06), c.d.y + 0.04, 0), Color(0.55, 0.56, 0.58), Vector3.ZERO, "", null, false)


static func _b_radio(c: Ctx) -> void:
	c.box(c.d, Vector3(0, c.d.y * 0.5, 0), c.c1)
	c.box(Vector3(c.d.x * 0.5, c.d.y * 0.4, 0.01), Vector3(-c.d.x * 0.15, c.d.y * 0.55, c.d.z * 0.5), c.c2, Vector3.ZERO, "", null, false)
	c.cyl(0.02, 0.02, 0.02, Vector3(c.d.x * 0.3, c.d.y * 0.5, c.d.z * 0.5), c.c2, Vector3(PI / 2, 0, 0), 8, "", false)
	c.cyl(0.004, 0.004, c.d.y * 1.2, Vector3(c.d.x * 0.4, c.d.y * 1.5, 0), Color(0.7, 0.7, 0.7), Vector3(0, 0, 0.3), 6, "", false)


static func _b_console(c: Ctx) -> void:
	c.box(c.d, Vector3(0, c.d.y * 0.5, 0), c.c1)
	c.box(Vector3(c.d.x * 0.3, 0.004, c.d.z * 0.3), Vector3(0, c.d.y + 0.002, 0), c.c2, Vector3.ZERO, "", null, false)


static func _b_microwave(c: Ctx) -> void:
	c.box(c.d, Vector3(0, c.d.y * 0.5, 0), c.c1)
	c.wear_skirt(c.d, Vector3(0, c.d.y * 0.5, 0), c.c1)
	c.box(Vector3(c.d.x * 0.6, c.d.y * 0.7, 0.01), Vector3(-c.d.x * 0.15, c.d.y * 0.5, c.d.z * 0.5), Color(0.18, 0.18, 0.20), Vector3.ZERO, "", null, false, true, true)
	c.box(Vector3(c.d.x * 0.2, c.d.y * 0.7, 0.01), Vector3(c.d.x * 0.35, c.d.y * 0.5, c.d.z * 0.5), Color(0.55, 0.52, 0.48).lerp(c.c2, 0.3), Vector3.ZERO, "", null, false)


static func _b_fan(c: Ctx) -> void:
	c.cyl(c.d.x * 0.4, c.d.x * 0.45, 0.03, Vector3(0, 0.015, 0), c.c2, Vector3.ZERO, 12)
	c.cyl(0.02, 0.02, c.d.y * 0.6, Vector3(0, c.d.y * 0.33, 0), c.c2, Vector3.ZERO, 8, "", false)
	c.cyl(c.d.x * 0.5, c.d.x * 0.5, 0.06, Vector3(0, c.d.y * 0.75, 0), c.c1, Vector3(PI / 2, 0, 0), 16)


static func _b_lamp_table(c: Ctx) -> void:
	var h := c.d.y
	var r := c.d.x * 0.5
	var metal := c.c2.darkened(0.12)
	var shade := c.c1.darkened(0.10)
	c.cyl(r * 0.62, r * 0.88, h * 0.12, Vector3(0, h * 0.06, 0), metal, Vector3.ZERO, 8)
	c.cyl(r * 0.34, r * 0.52, h * 0.06, Vector3(0, h * 0.14, 0), metal, Vector3.ZERO, 8, "", false)
	c.cyl(0.012, 0.014, h * 0.36, Vector3(0, h * 0.36, 0), metal, Vector3.ZERO, 6, "", false)
	c.cyl(r * 0.36, r * 1.00, h * 0.40, Vector3(0, h * 0.78, 0), shade, Vector3.ZERO, 8)
	c.cyl(r * 0.36, r * 0.36, 0.008, Vector3(0, h * 0.61, 0), Color(1.0, 0.90, 0.68), Vector3.ZERO, 8, "", false)


static func _b_lamp_floor(c: Ctx) -> void:
	var h := c.d.y
	var r := c.d.x * 0.5
	var metal := c.c2.darkened(0.08)
	var shade := c.c1.darkened(0.12)
	c.cyl(r * 0.65, r * 0.95, 0.06, Vector3(0, 0.03, 0), metal, Vector3.ZERO, 8)
	c.cyl(r * 0.24, r * 0.48, 0.045, Vector3(0, 0.075, 0), metal, Vector3.ZERO, 8, "", false)
	c.cyl(0.014, 0.016, h * 0.68, Vector3(0, h * 0.42, 0), metal, Vector3.ZERO, 6)
	c.cyl(r * 0.32, r * 0.98, h * 0.24, Vector3(0, h * 0.87, 0), shade, Vector3.ZERO, 8)
	c.cyl(r * 0.32, r * 0.32, 0.008, Vector3(0, h * 0.78, 0), Color(1.0, 0.90, 0.68), Vector3.ZERO, 8, "", false)


static func _b_chandelier(c: Ctx) -> void:
	c.cyl(0.01, 0.01, c.d.y * 0.3, Vector3(0, c.d.y * 0.85, 0), c.c2, Vector3.ZERO, 6, "", false)
	c.torus(c.d.x * 0.42, c.d.x * 0.5, Vector3(0, c.d.y * 0.6, 0), c.c2, Vector3(PI / 2, 0, 0))
	for i in 6:
		var a := TAU * i / 6.0
		var p := Vector3(cos(a) * c.d.x * 0.45, c.d.y * 0.6, sin(a) * c.d.x * 0.45)
		c.cyl(0.015, 0.02, 0.1, p + Vector3(0, 0.07, 0), c.c1, Vector3.ZERO, 6, "", false)
		c.sph(0.025, p + Vector3(0, 0.15, 0), Color(1, 0.95, 0.7), false)
		c.sph(0.02, p + Vector3(0, -0.06, 0), Color(0.85, 0.95, 1.0, 0.8), false)
	var s := CylinderShape3D.new()
	s.radius = c.d.x * 0.5
	s.height = c.d.y
	c.shapes.append({"shape": s, "xform": Transform3D(Basis(), Vector3(0, c.d.y * 0.5, 0))})


static func _b_clock(c: Ctx) -> void:
	c.cyl(c.d.x * 0.5, c.d.x * 0.5, c.d.z, Vector3(0, c.d.y * 0.5, 0), c.c1, Vector3(PI / 2, 0, 0), 16)
	c.cyl(c.d.x * 0.45, c.d.x * 0.45, 0.004, Vector3(0, c.d.y * 0.5, c.d.z * 0.5), Color(0.95, 0.95, 0.9), Vector3(PI / 2, 0, 0), 16, "", false)
	c.box(Vector3(0.01, c.d.x * 0.3, 0.004), Vector3(0, c.d.y * 0.6, c.d.z * 0.51), Color(0.1, 0.1, 0.1), Vector3.ZERO, "", null, false)
	c.box(Vector3(c.d.x * 0.22, 0.01, 0.004), Vector3(c.d.x * 0.1, c.d.y * 0.5, c.d.z * 0.51), Color(0.1, 0.1, 0.1), Vector3.ZERO, "", null, false)


static func _b_clock_grandfather(c: Ctx) -> void:
	c.box(Vector3(c.d.x, c.d.y * 0.75, c.d.z), Vector3(0, c.d.y * 0.375, 0), c.c1)
	c.box(Vector3(c.d.x * 1.1, c.d.y * 0.25, c.d.z * 1.1), Vector3(0, c.d.y * 0.875, 0), c.c1)
	c.cyl(c.d.x * 0.4, c.d.x * 0.4, 0.004, Vector3(0, c.d.y * 0.875, c.d.z * 0.56), Color(0.95, 0.95, 0.9), Vector3(PI / 2, 0, 0), 16, "", false)
	c.cyl(0.01, 0.01, c.d.y * 0.5, Vector3(0, c.d.y * 0.4, c.d.z * 0.3), Color(0.8, 0.7, 0.3), Vector3.ZERO, 6, "", false)
	c.cyl(0.05, 0.05, 0.01, Vector3(0, c.d.y * 0.15, c.d.z * 0.3), Color(0.8, 0.7, 0.3), Vector3(PI / 2, 0, 0), 12, "", false)


# ============================================================ картины / плоское

static func _b_painting(c: Ctx) -> void:
	c.box(c.d, Vector3(0, c.d.y * 0.5, 0), c.c2)
	var canvas := c.box(Vector3(c.d.x * 0.86, c.d.y * 0.84, 0.004), Vector3(0, c.d.y * 0.5, c.d.z * 0.5), Color.WHITE, Vector3.ZERO, "", null, false, false)
	var t := c.tagged_tex(PAINTINGS)
	if ArchetypeMeshes.tex(t):
		canvas.material_override = c.mat(Color.WHITE, 0.8, 0.0, t)
	else:
		canvas.material_override = c.mat(c.c1)
		c.sph(c.d.x * 0.12, Vector3(-c.d.x * 0.15, c.d.y * 0.6, c.d.z * 0.5), c.c1.lightened(0.4), false)
		c.box(Vector3(c.d.x * 0.5, c.d.y * 0.15, 0.003), Vector3(c.d.x * 0.1, c.d.y * 0.3, c.d.z * 0.51), c.c1.darkened(0.4), Vector3.ZERO, "", null, false)


static func _b_frame_photo(c: Ctx) -> void:
	_b_painting(c)


static func _b_mirror(c: Ctx) -> void:
	c.box(c.d, Vector3(0, c.d.y * 0.5, 0), c.c2)
	var mi := c.box(Vector3(c.d.x * 0.88, c.d.y * 0.88, 0.004), Vector3(0, c.d.y * 0.5, c.d.z * 0.5), Color(0.8, 0.9, 1.0), Vector3.ZERO, "", null, false)
	(mi.material_override as StandardMaterial3D).metallic = 1.0
	(mi.material_override as StandardMaterial3D).roughness = 0.05


static func _b_poster(c: Ctx) -> void:
	var b := c.box(c.d, Vector3(0, c.d.y * 0.5, 0), Color.WHITE, Vector3.ZERO, "", null, true, false)
	b.material_override = c.mat(Color.WHITE, 0.9, 0.0, c.tagged_tex(POSTERS))


static func _b_rug(c: Ctx) -> void:
	var b := c.box(c.d, Vector3(0, c.d.y * 0.5, 0), Color.WHITE.lerp(c.c1, 0.2), Vector3.ZERO, "", null, true, false)
	b.material_override = c.mat(Color.WHITE.lerp(c.c1, 0.2), 1.0, 0.0, "tex_rug")


# ============================================================ мебель

static func _b_dresser(c: Ctx) -> void:
	var w := c.d.x
	var h := c.d.y
	var dp := c.d.z
	c.box(Vector3(w, h, dp), Vector3(0, h * 0.5, 0), c.c1)
	c.wear_skirt(Vector3(w, h, dp), Vector3(0, h * 0.5, 0), c.c1)
	var n := 3
	for i in n:
		var y := h * (0.15 + 0.7 * i / float(n - 1) * 0.85 + 0.05)
		y = h * (0.18 + i * (0.64 / (n - 1)))
		var dr := c.node("Drawer%d" % i, Vector3(0, y, dp * 0.5))
		c.box(Vector3(w * 0.9, h * 0.6 / n, 0.03), Vector3(0, 0, 0.015), c.c1.lightened(0.15), Vector3.ZERO, "", dr)
		c.box(Vector3(w * 0.25, 0.02, 0.02), Vector3(0, 0, 0.04), c.c2, Vector3.ZERO, "", dr)
	c.only_box_shape(Vector3(w, h, dp), Vector3(0, h * 0.5, 0))


static func _b_nightstand(c: Ctx) -> void:
	var w := c.d.x
	var h := c.d.y
	var dp := c.d.z
	c.box(Vector3(w, h, dp), Vector3(0, h * 0.5, 0), c.c1)
	var dr := c.node("Drawer0", Vector3(0, h * 0.7, dp * 0.5))
	c.box(Vector3(w * 0.9, h * 0.3, 0.03), Vector3(0, 0, 0.015), c.c1.lightened(0.15), Vector3.ZERO, "", dr)
	c.box(Vector3(w * 0.2, 0.02, 0.02), Vector3(0, 0, 0.04), c.c2, Vector3.ZERO, "", dr)
	c.only_box_shape(Vector3(w, h, dp), Vector3(0, h * 0.5, 0))


static func _b_shelf(c: Ctx) -> void:
	var w := c.d.x
	var h := c.d.y
	var dp := c.d.z
	for x in [-0.5, 0.5]:
		c.box(Vector3(0.03, h, dp), Vector3(w * x, h * 0.5, 0), c.c1)
	for i in 4:
		c.box(Vector3(w, 0.03, dp), Vector3(0, h * (0.02 + i * 0.32), 0), c.c1.lightened(0.1), Vector3.ZERO, "Shelf%d" % i)
	c.only_box_shape(Vector3(w, h, dp), Vector3(0, h * 0.5, 0))


static func _b_bookshelf(c: Ctx) -> void:
	_b_shelf(c)
	c.box(Vector3(c.d.x, c.d.y, 0.02), Vector3(0, c.d.y * 0.5, -c.d.z * 0.5), c.c1.darkened(0.2), Vector3.ZERO, "", null, false)


static func _b_chair(c: Ctx) -> void:
	var w := c.d.x
	var h := c.d.y
	for x in [-0.4, 0.4]:
		for z in [-0.4, 0.4]:
			c.box(Vector3(0.04, h * 0.45, 0.04), Vector3(w * x, h * 0.225, c.d.z * z), c.c2, Vector3.ZERO, "", null, false)
	c.box(Vector3(w, 0.05, c.d.z), Vector3(0, h * 0.47, 0), c.c1)
	c.box(Vector3(w, h * 0.5, 0.05), Vector3(0, h * 0.75, -c.d.z * 0.45), c.c1)


static func _b_stool(c: Ctx) -> void:
	c.cyl(c.d.x * 0.5, c.d.x * 0.5, 0.04, Vector3(0, c.d.y - 0.02, 0), c.c1, Vector3.ZERO, 12)
	for i in 3:
		var a := TAU * i / 3.0
		c.cyl(0.015, 0.02, c.d.y - 0.04, Vector3(cos(a) * c.d.x * 0.35, (c.d.y - 0.04) * 0.5, sin(a) * c.d.x * 0.35), c.c2, Vector3.ZERO, 6, "", false)


static func _b_table(c: Ctx) -> void:
	var w := c.d.x
	var h := c.d.y
	for x in [-0.45, 0.45]:
		for z in [-0.45, 0.45]:
			c.box(Vector3(0.06, h - 0.05, 0.06), Vector3(w * x, (h - 0.05) * 0.5, c.d.z * z), c.c2, Vector3.ZERO, "", null, false)
	c.box(Vector3(w, 0.05, c.d.z), Vector3(0, h - 0.025, 0), c.c1)
	c.only_box_shape(Vector3(w, h, c.d.z), Vector3(0, h * 0.5, 0))


static func _b_mattress(c: Ctx) -> void:
	c.box(c.d, Vector3(0, c.d.y * 0.5, 0), c.c1)
	for i in 3:
		c.box(Vector3(c.d.x * 0.9, 0.005, 0.02), Vector3(0, c.d.y + 0.002, c.d.z * (-0.3 + 0.3 * i)), c.c2, Vector3.ZERO, "", null, false)


static func _b_pillow(c: Ctx) -> void:
	c.box(c.d, Vector3(0, c.d.y * 0.5, 0), c.c1)


static func _b_sofa(c: Ctx) -> void:
	var w := c.d.x
	var h := c.d.y
	var dp := c.d.z
	c.box(Vector3(w, h * 0.45, dp), Vector3(0, h * 0.225, 0), c.c1)
	c.box(Vector3(w, h * 0.55, dp * 0.25), Vector3(0, h * 0.72, -dp * 0.375), c.c1)
	for x in [-0.5, 0.5]:
		c.box(Vector3(dp * 0.2, h * 0.7, dp), Vector3((w * 0.5 - dp * 0.1) * sign(x), h * 0.35, 0), c.c1.darkened(0.15))
	c.only_box_shape(Vector3(w, h, dp), Vector3(0, h * 0.5, 0))


static func _b_wardrobe(c: Ctx) -> void:
	c.box(c.d, Vector3(0, c.d.y * 0.5, 0), c.c1)
	var lid := c.node("Lid", Vector3(-c.d.x * 0.5, 0, c.d.z * 0.5))
	c.box(Vector3(c.d.x * 0.98, c.d.y * 0.95, 0.03), Vector3(c.d.x * 0.49, c.d.y * 0.5, 0.015), c.c1.lightened(0.1), Vector3.ZERO, "", lid)
	c.only_box_shape(c.d, Vector3(0, c.d.y * 0.5, 0))


static func _b_fridge(c: Ctx) -> void:
	c.box(c.d, Vector3(0, c.d.y * 0.5, 0), c.c1)
	c.wear_skirt(c.d, Vector3(0, c.d.y * 0.5, 0), c.c1)
	c.box(Vector3(0.03, c.d.y * 0.4, 0.03), Vector3(c.d.x * 0.35, c.d.y * 0.55, c.d.z * 0.52), c.c2, Vector3.ZERO, "", null, false)
	c.box(Vector3(c.d.x, 0.01, c.d.z * 1.02), Vector3(0, c.d.y * 0.7, 0), c.c2, Vector3.ZERO, "", null, false)


static func _b_piano(c: Ctx) -> void:
	c.box(Vector3(c.d.x, c.d.y, c.d.z), Vector3(0, c.d.y * 0.5, 0), c.c1)
	c.box(Vector3(c.d.x * 0.9, 0.04, c.d.z * 0.4), Vector3(0, c.d.y * 0.6, c.d.z * 0.5), Color(0.95, 0.95, 0.9), Vector3.ZERO, "", null, false)
	for i in 14:
		c.box(Vector3(c.d.x * 0.9 / 24.0, 0.03, c.d.z * 0.22), Vector3(-c.d.x * 0.43 + i * c.d.x * 0.9 / 14.0, c.d.y * 0.63, c.d.z * 0.45), Color(0.05, 0.05, 0.05), Vector3.ZERO, "", null, false)


# ============================================================ бумага / мелкое

static func _b_book(c: Ctx) -> void:
	c.box(c.d, Vector3(0, c.d.y * 0.5, 0), c.c1)
	c.box(Vector3(c.d.x * 0.92, c.d.y * 0.8, c.d.z * 0.96), Vector3(c.d.x * 0.05, c.d.y * 0.5, 0), Color(0.95, 0.92, 0.85), Vector3.ZERO, "", null, false)
	# обложка сверху
	var cover := c.box(Vector3(c.d.x * 0.98, 0.003, c.d.z * 0.98), Vector3(0, c.d.y + 0.0015, 0), Color.WHITE, Vector3.ZERO, "", null, false, false)
	var t := c.tagged_tex(BOOKS)
	if ArchetypeMeshes.tex(t):
		cover.material_override = c.mat(Color.WHITE, 0.8, 0.0, t)
	else:
		cover.material_override = c.mat(c.c1)


static func _b_letter(c: Ctx) -> void:
	c.box(c.d, Vector3(0, c.d.y * 0.5, 0), c.c1)
	c.prism(Vector3(c.d.x, c.d.z * 0.5, 0.002), Vector3(0, c.d.y + 0.001, 0), c.c2, Vector3(-PI / 2, 0, 0))
	c.only_box_shape(c.d, Vector3(0, c.d.y * 0.5, 0))


static func _b_document(c: Ctx) -> void:
	c.box(c.d, Vector3(0, c.d.y * 0.5, 0), c.c1)
	for i in 5:
		c.box(Vector3(c.d.x * 0.7, 0.001, 0.008), Vector3(0, c.d.y + 0.001, c.d.z * (-0.3 + i * 0.15)), Color(0.2, 0.2, 0.25), Vector3.ZERO, "", null, false)


static func _b_folder(c: Ctx) -> void:
	_b_book(c)


static func _b_usb(c: Ctx) -> void:
	c.box(c.d, Vector3(0, c.d.y * 0.5, 0), c.c1)
	c.box(Vector3(c.d.x * 0.6, c.d.y * 0.6, c.d.z * 0.4), Vector3(0, c.d.y * 0.5, c.d.z * 0.65), Color(0.75, 0.75, 0.78), Vector3.ZERO, "", null, false)


static func _b_cd(c: Ctx) -> void:
	c.cyl(c.d.x * 0.5, c.d.x * 0.5, c.d.y, Vector3(0, c.d.y * 0.5, 0), c.c1, Vector3.ZERO, 16)


static func _b_cassette(c: Ctx) -> void:
	c.box(c.d, Vector3(0, c.d.y * 0.5, 0), c.c1)
	for x in [-0.25, 0.25]:
		c.cyl(0.008, 0.008, c.d.y * 1.1, Vector3(c.d.x * x, c.d.y * 0.5, 0), Color(0.9, 0.9, 0.9), Vector3.ZERO, 8, "", false)


static func _b_bill(c: Ctx) -> void:
	var b := c.box(c.d, Vector3(0, c.d.y * 0.5, 0), c.c1)
	if ArchetypeMeshes.tex("tex_bill"):
		b.material_override = c.mat(Color.WHITE.lerp(c.c1, 0.4), 0.9, 0.0, "tex_bill")
	else:
		c.cyl(c.d.z * 0.3, c.d.z * 0.3, 0.001, Vector3(0, c.d.y + 0.0005, 0), c.c2, Vector3.ZERO, 10, "", false)


static func _b_coin_jar(c: Ctx) -> void:
	_b_jar(c)
	for i in 6:
		c.cyl(0.012, 0.012, 0.003, Vector3(randf_range(-0.03, 0.03), c.d.y * 0.1 + i * 0.006, randf_range(-0.03, 0.03)), Color(0.85, 0.7, 0.25), Vector3.ZERO, 8, "", false)


static func _b_ring(c: Ctx) -> void:
	c.torus(c.d.x * 0.35, c.d.x * 0.5, Vector3(0, c.d.y * 0.5, 0), c.c1, Vector3(PI / 2, 0, 0))
	c.sph(c.d.x * 0.18, Vector3(0, c.d.y * 0.5 + c.d.x * 0.5, 0), c.c2, false)
	var s := SphereShape3D.new()
	s.radius = c.d.x * 0.55
	c.shapes.append({"shape": s, "xform": Transform3D(Basis(), Vector3(0, c.d.y * 0.5, 0))})


static func _b_watch(c: Ctx) -> void:
	c.cyl(c.d.x * 0.5, c.d.x * 0.5, c.d.y, Vector3(0, c.d.y * 0.5, 0), c.c1, Vector3.ZERO, 12)
	c.box(Vector3(c.d.x * 0.5, c.d.y * 0.5, c.d.x * 2.2), Vector3(0, c.d.y * 0.25, 0), c.c2, Vector3.ZERO, "", null, false)


static func _b_necklace(c: Ctx) -> void:
	c.torus(c.d.x * 0.42, c.d.x * 0.5, Vector3(0, c.d.y * 0.5, 0), c.c1, Vector3(PI / 2, 0, 0))
	c.sph(c.d.x * 0.12, Vector3(0, c.d.y * 0.5, c.d.x * 0.5), c.c2, false)
	c.only_box_shape(Vector3(c.d.x, c.d.y, c.d.x), Vector3(0, c.d.y * 0.5, 0))


static func _b_trophy(c: Ctx) -> void:
	c.box(Vector3(c.d.x * 0.7, c.d.y * 0.15, c.d.x * 0.7), Vector3(0, c.d.y * 0.075, 0), c.c2)
	c.cyl(0.015, 0.02, c.d.y * 0.25, Vector3(0, c.d.y * 0.275, 0), c.c1, Vector3.ZERO, 8, "", false)
	c.cyl(c.d.x * 0.5, c.d.x * 0.25, c.d.y * 0.55, Vector3(0, c.d.y * 0.675, 0), c.c1, Vector3.ZERO, 12)
	for x in [-0.55, 0.55]:
		c.torus(0.01, 0.03, Vector3(c.d.x * x, c.d.y * 0.7, 0), c.c1, Vector3(0, 0, PI / 2))


static func _b_statue(c: Ctx) -> void:
	c.box(Vector3(c.d.x, c.d.y * 0.15, c.d.z), Vector3(0, c.d.y * 0.075, 0), c.c2)
	c.capsule(c.d.x * 0.3, c.d.y * 0.55, Vector3(0, c.d.y * 0.45, 0), c.c1)
	c.sph(c.d.x * 0.22, Vector3(0, c.d.y * 0.85, 0), c.c1)


static func _b_bust(c: Ctx) -> void:
	c.box(Vector3(c.d.x, c.d.y * 0.2, c.d.z), Vector3(0, c.d.y * 0.1, 0), c.c2)
	c.box(Vector3(c.d.x * 0.9, c.d.y * 0.35, c.d.z * 0.6), Vector3(0, c.d.y * 0.375, 0), c.c1)
	c.cyl(c.d.x * 0.15, c.d.x * 0.2, c.d.y * 0.1, Vector3(0, c.d.y * 0.6, 0), c.c1, Vector3.ZERO, 8, "", false)
	c.sph(c.d.x * 0.3, Vector3(0, c.d.y * 0.8, 0), c.c1)


static func _b_globe(c: Ctx) -> void:
	c.cyl(c.d.x * 0.3, c.d.x * 0.35, 0.03, Vector3(0, 0.015, 0), c.c2, Vector3.ZERO, 10)
	c.cyl(0.01, 0.01, c.d.y * 0.3, Vector3(0, c.d.y * 0.18, 0), c.c2, Vector3.ZERO, 6, "", false)
	c.sph(c.d.x * 0.5, Vector3(0, c.d.y * 0.6, 0), c.c1)
	c.box(Vector3(c.d.x * 0.3, c.d.x * 0.2, c.d.x * 0.1), Vector3(c.d.x * 0.15, c.d.y * 0.7, c.d.x * 0.4), Color(0.35, 0.6, 0.3), Vector3.ZERO, "", null, false)


static func _b_skull(c: Ctx) -> void:
	c.sph(c.d.x * 0.5, Vector3(0, c.d.y * 0.55, 0), c.c1)
	c.box(Vector3(c.d.x * 0.6, c.d.y * 0.3, c.d.x * 0.5), Vector3(0, c.d.y * 0.2, c.d.x * 0.1), c.c1, Vector3.ZERO, "", null, false)
	for x in [-0.2, 0.2]:
		c.sph(c.d.x * 0.12, Vector3(c.d.x * x, c.d.y * 0.6, c.d.x * 0.42), Color(0.05, 0.05, 0.05), false)


static func _b_plant_pot(c: Ctx) -> void:
	c.cyl(c.d.x * 0.5, c.d.x * 0.38, c.d.y * 0.45, Vector3(0, c.d.y * 0.225, 0), c.c2, Vector3.ZERO, 12)
	c.cyl(0.015, 0.02, c.d.y * 0.4, Vector3(0, c.d.y * 0.6, 0), Color(0.3, 0.5, 0.2), Vector3.ZERO, 6, "", false)
	c.sph(c.d.x * 0.45, Vector3(0, c.d.y * 0.85, 0), c.c1)


# ============================================================ живое

static func _b_hamster_cage(c: Ctx) -> void:
	var w := c.d.x
	var h := c.d.y
	var dp := c.d.z
	var frame := c.c2.lerp(Color(0.22, 0.48, 0.82), 0.6)
	var bar := Color(0.78, 0.82, 0.90)
	c.box(Vector3(w, h * 0.12, dp), Vector3(0, h * 0.06, 0), frame.darkened(0.08))
	var corners: Array[float] = [-0.5, 0.5]
	for sx in corners:
		for sz in corners:
			c.cyl(0.009, 0.009, h * 0.84, Vector3(w * sx * 0.92, h * 0.54, dp * sz * 0.92), frame, Vector3.ZERO, 6, "", false)
	c.box(Vector3(w * 0.96, 0.014, 0.014), Vector3(0, h * 0.96, dp * 0.46), frame, Vector3.ZERO, "", null, false)
	c.box(Vector3(w * 0.96, 0.014, 0.014), Vector3(0, h * 0.96, -dp * 0.46), frame, Vector3.ZERO, "", null, false)
	c.box(Vector3(0.014, 0.014, dp * 0.96), Vector3(w * 0.46, h * 0.96, 0), frame, Vector3.ZERO, "", null, false)
	c.box(Vector3(0.014, 0.014, dp * 0.96), Vector3(-w * 0.46, h * 0.96, 0), frame, Vector3.ZERO, "", null, false)
	for i in 10:
		var t := -0.42 + float(i) * 0.093
		c.cyl(0.008, 0.008, h * 0.78, Vector3(w * t, h * 0.54, dp * 0.46), bar, Vector3.ZERO, 5, "", false)
		c.cyl(0.008, 0.008, h * 0.78, Vector3(w * t, h * 0.54, -dp * 0.46), bar, Vector3.ZERO, 5, "", false)
	for i in 10:
		var t := -0.42 + float(i) * 0.093
		c.cyl(0.008, 0.008, h * 0.78, Vector3(w * 0.46, h * 0.54, dp * t), bar, Vector3.ZERO, 5, "", false)
		c.cyl(0.008, 0.008, h * 0.78, Vector3(-w * 0.46, h * 0.54, dp * t), bar, Vector3.ZERO, 5, "", false)
	c.box(Vector3(w, 0.02, dp), Vector3(0, h, 0), frame, Vector3.ZERO, "Lid", null, false)
	c.torus(h * 0.14, h * 0.22, Vector3(-w * 0.24, h * 0.46, 0), Color(0.90, 0.48, 0.18), Vector3(0, PI / 2, 0))
	c.cyl(0.008, 0.008, 0.04, Vector3(-w * 0.24, h * 0.46, 0), Color(0.72, 0.40, 0.16), Vector3(0, 0, PI / 2), 6, "", false)
	var ham := Color(1.0, 0.62, 0.38)
	var hx := w * 0.08
	var hy := 0.08 + h * 0.12
	var hz := dp * 0.22
	c.sph(0.08, Vector3(hx, hy, hz), ham, false)
	c.sph(0.048, Vector3(hx + 0.07, hy + 0.02, hz + 0.02), ham, false)
	c.sph(0.018, Vector3(hx + 0.05, hy + 0.06, hz - 0.01), ham, false)
	c.sph(0.018, Vector3(hx + 0.08, hy + 0.06, hz), ham, false)
	c.sph(0.011, Vector3(hx + 0.11, hy + 0.018, hz + 0.04), Color(0.08, 0.05, 0.05), false, "", null, true)
	c.cyl(0.014, 0.014, 0.005, Vector3(hx + 0.095, hy + 0.03, hz + 0.055), Color(0.06, 0.04, 0.04), Vector3(0.5, 0.2, 0), 6, "", false, null, true)
	c.cyl(0.014, 0.014, 0.005, Vector3(hx + 0.075, hy + 0.03, hz + 0.058), Color(0.06, 0.04, 0.04), Vector3(0.5, -0.15, 0), 6, "", false, null, true)
	c.cyl(0.016, 0.018, 0.055, Vector3(w * 0.52, h * 0.42, 0), Color(0.55, 0.82, 0.95), Vector3.ZERO, 8, "", false)
	c.cyl(0.004, 0.004, 0.06, Vector3(w * 0.46, h * 0.38, 0), Color(0.70, 0.75, 0.80), Vector3(0, 0, PI * 0.5), 5, "", false)
	c.only_box_shape(c.d, Vector3(0, h * 0.5, 0))


static func _b_mouse(c: Ctx) -> void:
	c.capsule(c.d.x * 0.5, c.d.z, Vector3(0, c.d.y * 0.5, 0), c.c1, Vector3(PI / 2, 0, 0))
	for x in [-0.5, 0.5]:
		c.sph(c.d.x * 0.25, Vector3(c.d.x * x * 0.8, c.d.y * 0.85, c.d.z * 0.35), Color(0.95, 0.7, 0.7), false)
	c.cyl(0.003, 0.003, c.d.z * 0.8, Vector3(0, c.d.y * 0.4, -c.d.z * 0.75), Color(0.95, 0.7, 0.7), Vector3(PI / 2, 0, 0), 4, "", false)
	c.sph(0.006, Vector3(0, c.d.y * 0.6, c.d.z * 0.5), Color(0, 0, 0), false)


static func _b_fish_bowl(c: Ctx) -> void:
	c.sph(c.d.x * 0.5, Vector3(0, c.d.y * 0.5, 0), Color(0.6, 0.8, 1.0, 0.5))
	c.sph(c.d.x * 0.12, Vector3(c.d.x * 0.1, c.d.y * 0.45, 0), c.c1, false)


static func _b_bird_cage(c: Ctx) -> void:
	c.cyl(c.d.x * 0.5, c.d.x * 0.5, 0.03, Vector3(0, 0.015, 0), c.c2, Vector3.ZERO, 12)
	for i in 10:
		var a := TAU * i / 10.0
		c.cyl(0.003, 0.003, c.d.y * 0.8, Vector3(cos(a) * c.d.x * 0.47, c.d.y * 0.42, sin(a) * c.d.x * 0.47), Color(0.85, 0.8, 0.3), Vector3.ZERO, 4, "", false)
	c.sph(c.d.x * 0.5, Vector3(0, c.d.y * 0.8, 0), c.c2, false)
	c.sph(c.d.x * 0.12, Vector3(0, c.d.y * 0.4, 0), c.c1, false)
	c.only_box_shape(c.d, Vector3(0, c.d.y * 0.5, 0))


# ============================================================ одежда / ткань

static func _b_cloth(c: Ctx) -> void:
	c.box(c.d, Vector3(0, c.d.y * 0.5, 0), c.c1)
	c.box(Vector3(c.d.x * 0.5, c.d.y * 0.5, c.d.z * 1.02), Vector3(c.d.x * 0.1, c.d.y * 0.75, 0), c.c1.darkened(0.12), Vector3.ZERO, "", null, false)


static func _b_costume(c: Ctx) -> void:
	c.box(Vector3(c.d.x, c.d.y * 0.6, c.d.z), Vector3(0, c.d.y * 0.45, 0), c.c1)
	c.sph(c.d.x * 0.35, Vector3(0, c.d.y * 0.9, 0), c.c2)
	for x in [-0.6, 0.6]:
		c.capsule(c.d.x * 0.15, c.d.y * 0.45, Vector3(c.d.x * x, c.d.y * 0.45, 0), c.c1, Vector3.ZERO, false)
	c.cyl(c.d.x * 0.4, c.d.x * 0.45, c.d.y * 0.15, Vector3(0, c.d.y * 0.075, 0), c.c2, Vector3.ZERO, 10)


static func _b_hat(c: Ctx) -> void:
	c.cyl(c.d.x * 0.5, c.d.x * 0.5, 0.01, Vector3(0, 0.005, 0), c.c1, Vector3.ZERO, 14)
	c.cyl(c.d.x * 0.3, c.d.x * 0.32, c.d.y, Vector3(0, c.d.y * 0.5, 0), c.c1, Vector3.ZERO, 12)
	c.torus(c.d.x * 0.3, c.d.x * 0.34, Vector3(0, 0.03, 0), c.c2, Vector3(PI / 2, 0, 0))


static func _b_shoe(c: Ctx) -> void:
	c.box(Vector3(c.d.x, c.d.y * 0.5, c.d.z), Vector3(0, c.d.y * 0.25, 0), c.c1)
	c.box(Vector3(c.d.x * 0.9, c.d.y * 0.5, c.d.z * 0.5), Vector3(0, c.d.y * 0.75, -c.d.z * 0.2), c.c1.darkened(0.1))
	c.box(Vector3(c.d.x, 0.015, c.d.z), Vector3(0, 0.0075, 0), c.c2, Vector3.ZERO, "", null, false)


static func _b_bag(c: Ctx) -> void:
	# сумка со стенками (§6.2): Wall0..3 разъезжаются при открытии
	var w := c.d.x
	var h := c.d.y
	var dp := c.d.z
	c.box(Vector3(w, 0.02, dp), Vector3(0, 0.01, 0), c.c1.darkened(0.2))
	var w0 := c.node("Wall0", Vector3(-w * 0.5, 0.02, 0))
	c.box(Vector3(0.015, h, dp), Vector3(0.0075, h * 0.5, 0), c.c1, Vector3.ZERO, "", w0)
	var w1 := c.node("Wall1", Vector3(0, 0.02, -dp * 0.5))
	c.box(Vector3(w, h, 0.015), Vector3(0, h * 0.5, 0.0075), c.c1, Vector3.ZERO, "", w1)
	var w2 := c.node("Wall2", Vector3(w * 0.5, 0.02, 0))
	c.box(Vector3(0.015, h, dp), Vector3(-0.0075, h * 0.5, 0), c.c1, Vector3.ZERO, "", w2)
	var w3 := c.node("Wall3", Vector3(0, 0.02, dp * 0.5))
	c.box(Vector3(w, h, 0.015), Vector3(0, h * 0.5, -0.0075), c.c1, Vector3.ZERO, "", w3)
	c.torus(0.01, 0.02, Vector3(0, h * 1.15, 0), c.c2, Vector3(0, 0, 0)).scale = Vector3(w * 3.0, 1, 1)
	c.only_box_shape(Vector3(w, h, dp), Vector3(0, h * 0.5, 0))


static func _b_backpack(c: Ctx) -> void:
	c.box(c.d, Vector3(0, c.d.y * 0.5, 0), c.c1)
	var lid := c.node("Lid", Vector3(0, c.d.y, -c.d.z * 0.5))
	c.box(Vector3(c.d.x, 0.02, c.d.z), Vector3(0, 0.01, c.d.z * 0.5), c.c1.darkened(0.1), Vector3.ZERO, "", lid)
	c.box(Vector3(c.d.x * 0.6, c.d.y * 0.4, 0.06), Vector3(0, c.d.y * 0.3, c.d.z * 0.53), c.c2, Vector3.ZERO, "", null, false)
	for x in [-0.3, 0.3]:
		c.box(Vector3(0.04, c.d.y * 0.8, 0.02), Vector3(c.d.x * x, c.d.y * 0.5, -c.d.z * 0.52), c.c2, Vector3.ZERO, "", null, false)
	c.only_box_shape(c.d, Vector3(0, c.d.y * 0.5, 0))


static func _b_mannequin(c: Ctx) -> void:
	_b_costume(c)


# ============================================================ оружие / инструменты

static func _b_gun_gag(c: Ctx) -> void:
	c.box(Vector3(c.d.x, c.d.y * 0.45, c.d.z), Vector3(0, c.d.y * 0.75, 0), c.c1)
	c.box(Vector3(c.d.x, c.d.y * 0.6, c.d.z * 0.3), Vector3(0, c.d.y * 0.3, c.d.z * 0.3), c.c2, Vector3(0.3, 0, 0))
	c.cyl(0.012, 0.012, c.d.z * 0.6, Vector3(0, c.d.y * 0.8, -c.d.z * 0.7), Color(0.2, 0.2, 0.22), Vector3(PI / 2, 0, 0), 8, "", false)


static func _b_knife(c: Ctx) -> void:
	c.box(Vector3(c.d.x, c.d.y, c.d.z * 0.4), Vector3(0, c.d.y * 0.5, c.d.z * 0.3), c.c2)
	c.prism(Vector3(c.d.x * 0.5, c.d.z * 0.6, c.d.y * 0.3), Vector3(0, c.d.y * 0.5, -c.d.z * 0.2), Color(0.85, 0.85, 0.9), Vector3(-PI / 2, 0, 0))


static func _b_bat(c: Ctx) -> void:
	c.cyl(c.d.x * 0.5, c.d.x * 0.3, c.d.y, Vector3(0, c.d.y * 0.5, 0), c.c1, Vector3.ZERO, 10)


static func _b_sword(c: Ctx) -> void:
	c.box(Vector3(c.d.x * 0.35, c.d.y * 0.2, c.d.z), Vector3(0, c.d.y * 0.1, 0), c.c2)
	c.box(Vector3(c.d.x, c.d.y * 0.03, c.d.z * 1.5), Vector3(0, c.d.y * 0.21, 0), c.c2, Vector3.ZERO, "", null, false)
	c.box(Vector3(c.d.x * 0.2, c.d.y * 0.78, c.d.z * 0.3), Vector3(0, c.d.y * 0.6, 0), Color(0.85, 0.85, 0.9))


static func _b_hammer(c: Ctx) -> void:
	c.cyl(0.015, 0.018, c.d.y * 0.8, Vector3(0, c.d.y * 0.4, 0), c.c1, Vector3.ZERO, 8)
	c.box(Vector3(c.d.x, c.d.y * 0.2, c.d.z), Vector3(0, c.d.y * 0.9, 0), Color(0.4, 0.4, 0.42))


static func _b_wrench(c: Ctx) -> void:
	c.box(Vector3(c.d.x * 0.3, c.d.y, c.d.z), Vector3(0, c.d.y * 0.5, 0), c.c1)
	c.box(Vector3(c.d.x, c.d.y * 0.2, c.d.z), Vector3(0, c.d.y * 0.9, 0), c.c1, Vector3.ZERO, "", null, false)


static func _b_drill(c: Ctx) -> void:
	c.box(Vector3(c.d.x, c.d.y * 0.5, c.d.z), Vector3(0, c.d.y * 0.75, 0), c.c1)
	c.box(Vector3(c.d.x * 0.6, c.d.y * 0.5, c.d.z * 0.35), Vector3(0, c.d.y * 0.25, c.d.z * 0.2), c.c2)
	c.cyl(0.006, 0.006, c.d.z * 0.5, Vector3(0, c.d.y * 0.75, -c.d.z * 0.7), Color(0.6, 0.6, 0.65), Vector3(PI / 2, 0, 0), 6, "", false)


static func _b_tape_roll(c: Ctx) -> void:
	c.torus(c.d.x * 0.25, c.d.x * 0.5, Vector3(0, c.d.y * 0.5, 0), c.c1, Vector3(PI / 2, 0, 0))
	var s := CylinderShape3D.new()
	s.radius = c.d.x * 0.5
	s.height = c.d.y
	c.shapes.append({"shape": s, "xform": Transform3D(Basis(), Vector3(0, c.d.y * 0.5, 0))})


static func _b_plank(c: Ctx) -> void:
	var b := c.box(c.d, Vector3(0, c.d.y * 0.5, 0), c.c1, Vector3.ZERO, "", null, true, false)
	b.material_override = c.mat(Color.WHITE.lerp(c.c1, 0.3), 0.9, 0.0, "tex_planks")


static func _b_nail_box(c: Ctx) -> void:
	c.box(c.d, Vector3(0, c.d.y * 0.5, 0), c.c1)
	for i in 5:
		c.cyl(0.002, 0.002, c.d.z * 0.8, Vector3(c.d.x * (-0.3 + i * 0.15), c.d.y + 0.004, 0), Color(0.7, 0.7, 0.72), Vector3(PI / 2, 0, 0), 4, "", false)


static func _b_rag(c: Ctx) -> void:
	c.box(c.d, Vector3(0, c.d.y * 0.5, 0), c.c1)
	c.box(Vector3(c.d.x * 0.6, c.d.y * 0.6, c.d.z * 0.6), Vector3(c.d.x * 0.15, c.d.y * 0.8, -c.d.z * 0.1), c.c1.darkened(0.1), Vector3(0, 0.4, 0), "", null, false)


static func _b_sponge(c: Ctx) -> void:
	c.box(Vector3(c.d.x, c.d.y * 0.7, c.d.z), Vector3(0, c.d.y * 0.35, 0), c.c1)
	c.box(Vector3(c.d.x, c.d.y * 0.3, c.d.z), Vector3(0, c.d.y * 0.85, 0), c.c2, Vector3.ZERO, "", null, false)


static func _b_broom(c: Ctx) -> void:
	c.cyl(0.012, 0.012, c.d.y * 0.8, Vector3(0, c.d.y * 0.6, 0), c.c1, Vector3.ZERO, 6)
	c.box(Vector3(c.d.x, c.d.y * 0.2, c.d.z), Vector3(0, c.d.y * 0.1, 0), c.c2)


static func _b_mop(c: Ctx) -> void:
	c.cyl(0.012, 0.012, c.d.y * 0.85, Vector3(0, c.d.y * 0.575, 0), c.c1, Vector3.ZERO, 6)
	c.cyl(c.d.x * 0.5, c.d.x * 0.35, c.d.y * 0.15, Vector3(0, c.d.y * 0.075, 0), c.c2, Vector3.ZERO, 10)


static func _b_flashlight(c: Ctx) -> void:
	c.cyl(c.d.x * 0.5, c.d.x * 0.5, c.d.z * 0.7, Vector3(0, c.d.y * 0.5, c.d.z * 0.15), c.c1, Vector3(PI / 2, 0, 0), 10)
	c.cyl(c.d.x * 0.7, c.d.x * 0.5, c.d.z * 0.3, Vector3(0, c.d.y * 0.5, -c.d.z * 0.35), c.c2, Vector3(PI / 2, 0, 0), 10)
	c.cyl(c.d.x * 0.6, c.d.x * 0.6, 0.005, Vector3(0, c.d.y * 0.5, -c.d.z * 0.5), Color(1.0, 1.0, 0.85), Vector3(PI / 2, 0, 0), 10, "", false)


static func _b_lockpick(c: Ctx) -> void:
	c.box(c.d, Vector3(0, c.d.y * 0.5, 0), c.c1)
	c.box(Vector3(c.d.x * 0.4, c.d.y * 0.5, c.d.z * 0.15), Vector3(-c.d.x * 0.3, c.d.y * 0.5, -c.d.z * 0.5), c.c1, Vector3.ZERO, "", null, false)


static func _b_lighter(c: Ctx) -> void:
	c.box(c.d, Vector3(0, c.d.y * 0.5, 0), c.c1)
	c.box(Vector3(c.d.x, c.d.y * 0.2, c.d.z), Vector3(0, c.d.y * 1.05, 0), Color(0.7, 0.7, 0.72), Vector3.ZERO, "", null, false)


# ============================================================ игрушки / спорт / музыка

static func _b_toy_bear(c: Ctx) -> void:
	c.sph(c.d.x * 0.45, Vector3(0, c.d.y * 0.35, 0), c.c1)
	c.sph(c.d.x * 0.35, Vector3(0, c.d.y * 0.8, 0), c.c1)
	for x in [-0.3, 0.3]:
		c.sph(c.d.x * 0.13, Vector3(c.d.x * x, c.d.y * 1.02, 0), c.c1, false)
		c.sph(c.d.x * 0.15, Vector3(c.d.x * x * 1.7, c.d.y * 0.4, c.d.z * 0.2), c.c1, false)
	c.sph(c.d.x * 0.08, Vector3(0, c.d.y * 0.76, c.d.x * 0.3), c.c2, false)


static func _b_doll(c: Ctx) -> void:
	c.capsule(c.d.x * 0.3, c.d.y * 0.5, Vector3(0, c.d.y * 0.4, 0), c.c1)
	c.sph(c.d.x * 0.32, Vector3(0, c.d.y * 0.82, 0), Color(0.98, 0.85, 0.75))
	c.sph(c.d.x * 0.36, Vector3(0, c.d.y * 0.9, -0.01), c.c2, false)


static func _b_toy_car(c: Ctx) -> void:
	c.box(Vector3(c.d.x, c.d.y * 0.5, c.d.z), Vector3(0, c.d.y * 0.4, 0), c.c1)
	c.box(Vector3(c.d.x * 0.8, c.d.y * 0.4, c.d.z * 0.5), Vector3(0, c.d.y * 0.8, -c.d.z * 0.05), c.c1.darkened(0.2))
	for x in [-0.5, 0.5]:
		for z in [-0.35, 0.35]:
			c.cyl(c.d.y * 0.2, c.d.y * 0.2, 0.02, Vector3(c.d.x * x, c.d.y * 0.2, c.d.z * z), Color(0.1, 0.1, 0.1), Vector3(0, 0, PI / 2), 8, "", false)


static func _b_ball(c: Ctx) -> void:
	c.sph(c.d.x * 0.5, Vector3(0, c.d.x * 0.5, 0), c.c1)
	c.torus(c.d.x * 0.49, c.d.x * 0.51, Vector3(0, c.d.x * 0.5, 0), c.c2, Vector3(PI / 2, 0, 0))


static func _b_bicycle(c: Ctx) -> void:
	var h := c.d.y
	var wr := h * 0.36
	var frame := c.c1.darkened(0.12)
	var zs: Array[float] = [-0.35, 0.35]
	for z in zs:
		c.torus(wr * 0.74, wr, Vector3(0, wr, c.d.z * z), Color(0.08, 0.07, 0.07), Vector3(0, PI / 2, 0), true)
		c.cyl(0.028, 0.028, 0.045, Vector3(0, wr, c.d.z * z), c.c2, Vector3(0, 0, PI / 2), 8, "", false)
	c.box(Vector3(0.055, 0.055, c.d.z * 0.58), Vector3(0, h * 0.62, 0), frame, Vector3(0.25, 0, 0), "", null, false)
	c.box(Vector3(0.055, h * 0.42, 0.055), Vector3(0, h * 0.58, c.d.z * 0.18), frame, Vector3.ZERO, "", null, false)
	c.box(Vector3(0.055, h * 0.48, 0.055), Vector3(0, h * 0.58, -c.d.z * 0.28), frame, Vector3(0.18, 0, 0), "", null, false)
	c.box(Vector3(c.d.x * 0.72, 0.04, 0.04), Vector3(0, h * 0.92, -c.d.z * 0.28), c.c2, Vector3.ZERO, "", null, false)
	c.box(Vector3(0.16, 0.045, 0.22), Vector3(0, h * 0.82, c.d.z * 0.16), c.c2, Vector3.ZERO, "", null, false)
	c.only_box_shape(c.d, Vector3(0, h * 0.5, 0))


static func _b_tire(c: Ctx) -> void:
	var r := c.d.x * 0.5
	var h := c.d.y
	var rubber := c.c1.darkened(0.04)
	var rim := Color(0.42, 0.38, 0.34).lerp(c.c2, 0.35)
	c.torus(r * 0.30, r * 0.50, Vector3(0, h * 0.5, 0), rubber, Vector3(PI / 2, 0, 0), true)
	c.cyl(r * 0.32, r * 0.32, h * 0.38, Vector3(0, h * 0.5, 0), rim, Vector3.ZERO, 8, "", false)
	c.cyl(r * 0.10, r * 0.10, h * 0.48, Vector3(0, h * 0.5, 0), rim.lightened(0.12), Vector3.ZERO, 8, "", false)
	for i in 5:
		var a := TAU * float(i) / 5.0
		c.box(Vector3(r * 0.52, h * 0.14, 0.045), Vector3(cos(a) * r * 0.16, h * 0.5, sin(a) * r * 0.16), rim, Vector3(0, -a, 0), "", null, false)
	var s := CylinderShape3D.new()
	s.radius = r
	s.height = h
	c.shapes.append({"shape": s, "xform": Transform3D(Basis(), Vector3(0, h * 0.5, 0))})


static func _b_skateboard(c: Ctx) -> void:
	c.box(Vector3(c.d.x, c.d.y * 0.3, c.d.z), Vector3(0, c.d.y * 0.7, 0), c.c1)
	for x in [-0.35, 0.35]:
		for z in [-0.35, 0.35]:
			c.cyl(c.d.y * 0.25, c.d.y * 0.25, 0.02, Vector3(c.d.x * x, c.d.y * 0.25, c.d.z * z), c.c2, Vector3(0, 0, PI / 2), 8, "", false)


static func _b_guitar(c: Ctx) -> void:
	var h := c.d.y
	var wood := c.c1.darkened(0.10).lerp(Color(0.55, 0.28, 0.10), 0.22)
	var dark := c.c2.darkened(0.05)
	c.cyl(c.d.x * 0.50, c.d.x * 0.50, c.d.z * 1.25, Vector3(0, h * 0.22, 0), wood, Vector3(PI / 2, 0, 0), 8)
	c.cyl(c.d.x * 0.38, c.d.x * 0.38, c.d.z * 1.15, Vector3(0, h * 0.40, 0), wood, Vector3(PI / 2, 0, 0), 8, "", false)
	c.cyl(c.d.x * 0.12, c.d.x * 0.12, 0.008, Vector3(0, h * 0.30, c.d.z * 0.55), Color(0.08, 0.04, 0.02), Vector3(PI / 2, 0, 0), 8, "", false)
	c.box(Vector3(c.d.x * 0.28, 0.028, 0.022), Vector3(0, h * 0.14, c.d.z * 0.52), dark, Vector3.ZERO, "", null, false)
	c.box(Vector3(0.07, h * 0.48, 0.042), Vector3(0, h * 0.70, 0), dark)
	c.box(Vector3(0.095, h * 0.10, 0.038), Vector3(0, h * 0.96, 0), dark, Vector3.ZERO, "", null, false)
	var tuners: Array[float] = [-0.032, 0.032]
	for x in tuners:
		c.cyl(0.008, 0.008, 0.028, Vector3(x, h * 0.97, 0), Color(0.72, 0.64, 0.32), Vector3(0, 0, PI / 2), 6, "", false)


static func _b_drum(c: Ctx) -> void:
	c.cyl(c.d.x * 0.5, c.d.x * 0.5, c.d.y, Vector3(0, c.d.y * 0.5, 0), c.c1, Vector3.ZERO, 14)
	c.cyl(c.d.x * 0.48, c.d.x * 0.48, 0.01, Vector3(0, c.d.y + 0.005, 0), Color(0.95, 0.93, 0.85), Vector3.ZERO, 14, "", false)


static func _b_trumpet(c: Ctx) -> void:
	c.cyl(0.02, 0.02, c.d.z * 0.7, Vector3(0, c.d.y * 0.5, c.d.z * 0.15), c.c1, Vector3(PI / 2, 0, 0), 8)
	c.cyl(c.d.x * 0.5, 0.03, c.d.z * 0.3, Vector3(0, c.d.y * 0.5, -c.d.z * 0.35), c.c1, Vector3(PI / 2, 0, 0), 10)


static func _b_keyboard_music(c: Ctx) -> void:
	c.box(c.d, Vector3(0, c.d.y * 0.5, 0), c.c1)
	for i in 20:
		c.box(Vector3(c.d.x * 0.9 / 20.0 * 0.9, 0.01, c.d.z * 0.5), Vector3(-c.d.x * 0.45 + i * c.d.x * 0.9 / 20.0, c.d.y + 0.005, c.d.z * 0.15), Color(0.95, 0.95, 0.9) if i % 3 != 1 else Color(0.05, 0.05, 0.05), Vector3.ZERO, "", null, false)


# ============================================================ тяжёлое

static func _b_engine(c: Ctx) -> void:
	c.box(c.d, Vector3(0, c.d.y * 0.5, 0), c.c1)
	for i in 4:
		c.cyl(0.04, 0.04, 0.1, Vector3(c.d.x * (-0.3 + i * 0.2), c.d.y + 0.05, 0), c.c2, Vector3.ZERO, 8, "", false)
	c.box(Vector3(c.d.x * 0.5, 0.06, c.d.z * 0.6), Vector3(0, c.d.y * 0.5, c.d.z * 0.55), c.c2, Vector3.ZERO, "", null, false)


static func _b_anvil(c: Ctx) -> void:
	c.box(Vector3(c.d.x * 0.5, c.d.y * 0.5, c.d.z * 0.6), Vector3(0, c.d.y * 0.25, 0), c.c1)
	c.box(Vector3(c.d.x, c.d.y * 0.3, c.d.z), Vector3(0, c.d.y * 0.65, 0), c.c1)
	c.cyl(0.03, c.d.y * 0.15, c.d.x * 0.4, Vector3(c.d.x * 0.6, c.d.y * 0.7, 0), c.c1, Vector3(0, 0, -PI / 2), 8, "", false)


static func _b_dumbbell(c: Ctx) -> void:
	c.cyl(0.015, 0.015, c.d.x, Vector3(0, c.d.y * 0.5, 0), c.c2, Vector3(0, 0, PI / 2), 8)
	for x in [-0.4, 0.4]:
		c.cyl(c.d.y * 0.5, c.d.y * 0.5, 0.06, Vector3(c.d.x * x, c.d.y * 0.5, 0), c.c1, Vector3(0, 0, PI / 2), 12)


static func _b_pallet(c: Ctx) -> void:
	for i in 5:
		c.box(Vector3(c.d.x, 0.02, c.d.z * 0.15), Vector3(0, c.d.y - 0.01, c.d.z * (-0.42 + i * 0.21)), c.c1, Vector3.ZERO, "", null, false)
	for x in [-0.45, 0, 0.45]:
		c.box(Vector3(0.08, c.d.y - 0.02, c.d.z), Vector3(c.d.x * x, (c.d.y - 0.02) * 0.5, 0), c.c1.darkened(0.15), Vector3.ZERO, "", null, false)
	c.only_box_shape(c.d, Vector3(0, c.d.y * 0.5, 0))


static func _b_brick(c: Ctx) -> void:
	c.box(c.d, Vector3(0, c.d.y * 0.5, 0), c.c1)


static func _b_sink(c: Ctx) -> void:
	c.box(Vector3(c.d.x, c.d.y * 0.4, c.d.z), Vector3(0, c.d.y * 0.8, 0), c.c1)
	c.cyl(0.03, 0.03, c.d.y * 0.6, Vector3(0, c.d.y * 0.3, 0), c.c2, Vector3.ZERO, 8, "", false)
	c.cyl(0.01, 0.01, 0.15, Vector3(0, c.d.y * 1.1, -c.d.z * 0.35), Color(0.8, 0.8, 0.85), Vector3.ZERO, 6, "", false)


static func _b_umbrella(c: Ctx) -> void:
	c.cyl(0.008, 0.008, c.d.y, Vector3(0, c.d.y * 0.5, 0), c.c2, Vector3.ZERO, 6)
	c.cyl(0.02, c.d.x * 0.5, c.d.y * 0.2, Vector3(0, c.d.y * 0.9, 0), c.c1, Vector3.ZERO, 10)


static func _b_remote(c: Ctx) -> void:
	c.box(c.d, Vector3(0, c.d.y * 0.5, 0), c.c1)
	for i in 4:
		c.sph(0.006, Vector3(c.d.x * (-0.25 + i * 0.16), c.d.y + 0.003, 0), c.c2, false)


static func _b_typewriter(c: Ctx) -> void:
	c.box(Vector3(c.d.x, c.d.y * 0.5, c.d.z), Vector3(0, c.d.y * 0.25, 0), c.c1)
	c.cyl(c.d.y * 0.2, c.d.y * 0.2, c.d.x * 1.05, Vector3(0, c.d.y * 0.75, -c.d.z * 0.3), c.c2, Vector3(0, 0, PI / 2), 10)
	for r in 3:
		for i in 8:
			c.cyl(0.008, 0.008, 0.01, Vector3(c.d.x * (-0.35 + i * 0.1), c.d.y * 0.55 - r * 0.02, c.d.z * (0.1 + r * 0.12)), Color(0.15, 0.15, 0.15), Vector3.ZERO, 6, "", false)


static func _b_sewing_machine(c: Ctx) -> void:
	c.box(Vector3(c.d.x, c.d.y * 0.15, c.d.z), Vector3(0, c.d.y * 0.075, 0), c.c2)
	c.box(Vector3(c.d.x * 0.25, c.d.y * 0.85, c.d.z * 0.5), Vector3(c.d.x * 0.35, c.d.y * 0.575, 0), c.c1)
	c.box(Vector3(c.d.x * 0.8, c.d.y * 0.2, c.d.z * 0.4), Vector3(0, c.d.y * 0.9, 0), c.c1)
	c.cyl(0.004, 0.004, c.d.y * 0.5, Vector3(-c.d.x * 0.3, c.d.y * 0.55, 0), Color(0.7, 0.7, 0.72), Vector3.ZERO, 4, "", false)
