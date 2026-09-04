class_name Roads
extends Node3D
## Дороги города (§12): короткие полосы асфальта с тротуарами и жёлтой разметкой (MultiMesh),
## дизайнерские кочки `Bump*` (StaticBody3D + PrismMesh) и знаки `RoadSign*` (Label3D).
## Данные лежат в City.tscn (экспорт), геометрия строится в build_roads() — зовёт City._ready().
## Все отрезки — вдоль осей X/Z; на пересечениях тротуар вырезается.

@export var width := 8.0
@export var sidewalk := 1.6
@export var segments: PackedVector4Array = PackedVector4Array() ## (x1, z1, x2, z2)
@export var bumps: PackedVector4Array = PackedVector4Array() ## (x, z, yaw°, высота)
@export var sign_positions: PackedVector3Array = PackedVector3Array() ## (x, z, yaw°)
@export var sign_texts: PackedStringArray = PackedStringArray()

const DASH_STEP := 4.0
const DASH_LEN := 1.8
const ASPHALT_THICK := 0.12
## Каждый следующий отрезок чуть выше — снимает z-fighting на перекрёстках.
## Больше пары миллиметров нельзя: на 18 отрезках шаг в сантиметр давал ступеньку в 17 см,
## из-за неё тротуары обрывались в воздухе, а на стыках зияли чёрные щели.
const LAYER_STEP := 0.0025
## Тротуар сидит в грунте: тонкая плита мерцала о песок вдоль всей кромки.
const CURB_H := 0.36
const CURB_TOP := 0.10
## Бордюр заходит на асфальт — иначе на стыке видна щель.
const CURB_OVERLAP := 0.06

var _built := false
var _mat_asphalt: StandardMaterial3D
var _mat_curb: StandardMaterial3D
var _mat_dash: StandardMaterial3D
var _mat_bump: StandardMaterial3D
var _mat_post: StandardMaterial3D
var _mat_board: StandardMaterial3D
var _dash_mesh: BoxMesh
var _bumps: Array = []
var _signs: Array = []


func build_roads() -> void:
	if _built:
		return
	_built = true
	_mat_asphalt = _mat(Color(0.17, 0.17, 0.19))
	_mat_curb = _mat(Color(0.74, 0.72, 0.66))
	_mat_dash = _mat(Color(0.97, 0.82, 0.12))
	_mat_bump = _mat(Color(0.98, 0.75, 0.1))
	_mat_post = _mat(Color(0.5, 0.52, 0.56))
	_mat_board = _mat(Color(0.1, 0.4, 0.2))
	_dash_mesh = BoxMesh.new()
	_dash_mesh.size = Vector3(DASH_LEN, 0.02, 0.18)
	for i in segments.size():
		_build_segment(i, segments[i])
	for i in bumps.size():
		_build_bump(i, bumps[i])
	for i in mini(sign_positions.size(), sign_texts.size()):
		_build_sign(i, sign_positions[i], sign_texts[i])


func bump_nodes() -> Array:
	return _bumps


func sign_nodes() -> Array:
	return _signs


## Высота верха асфальта в точке (для спавна тачек/кочек). -1 если не на дороге.
func road_top_at(pos: Vector3) -> float:
	var best := -1.0
	for i in segments.size():
		var s := segments[i]
		var a := Vector3(s.x, 0, s.y)
		var b := Vector3(s.z, 0, s.w)
		var dir := b - a
		var seg_len := dir.length()
		if seg_len < 0.01:
			continue
		dir /= seg_len
		var rel := Vector3(pos.x, 0, pos.z) - (a + b) * 0.5
		var along := rel.dot(dir)
		var across := rel.dot(Vector3(-dir.z, 0, dir.x))
		if absf(along) <= seg_len * 0.5 + width * 0.5 and absf(across) <= width * 0.5:
			best = maxf(best, ASPHALT_THICK * 0.5 + LAYER_STEP * i)
	return best


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	return m


func _frame(s: Vector4) -> Dictionary:
	var a := Vector3(s.x, 0, s.y)
	var b := Vector3(s.z, 0, s.w)
	var dir := b - a
	var seg_len := dir.length()
	if seg_len < 0.01:
		return {}
	dir /= seg_len
	return {"a": a, "b": b, "dir": dir, "len": seg_len, "center": (a + b) * 0.5, "normal": Vector3(-dir.z, 0, dir.x)}


func _build_segment(i: int, s: Vector4) -> void:
	var f := _frame(s)
	if f.is_empty():
		return
	var dir: Vector3 = f["dir"]
	var length: float = f["len"]
	var center: Vector3 = f["center"]
	var normal: Vector3 = f["normal"]
	var yaw := atan2(-dir.z, dir.x) # ось X бокса вдоль дороги
	var body := StaticBody3D.new()
	body.name = "Road%d" % i
	body.collision_layer = Types.L_WORLD
	body.collision_mask = 0
	body.transform = Transform3D(Basis(Vector3.UP, yaw), center + Vector3(0, LAYER_STEP * i, 0))
	add_child(body)
	var full_len := length + width
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(full_len, ASPHALT_THICK, width)
	mi.mesh = bm
	mi.material_override = _mat_asphalt
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = bm.size
	cs.shape = bs
	body.add_child(cs)
	# разметка
	var n := int(floor(length / DASH_STEP))
	if n > 0:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _dash_mesh
		mm.instance_count = n
		var x0 := -length * 0.5 + DASH_STEP * 0.5
		for k in n:
			mm.set_instance_transform(k, Transform3D(Basis(), Vector3(x0 + k * DASH_STEP, ASPHALT_THICK * 0.5 + 0.012, 0)))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _mat_dash
		body.add_child(mmi)
	# тротуары с вырезами под перекрёстки
	var half := width * 0.5 + sidewalk
	for side in [-1.0, 1.0]:
		var cuts: Array = []
		for j in segments.size():
			if j == i:
				continue
			var o := _frame(segments[j])
			if o.is_empty():
				continue
			var odir: Vector3 = o["dir"]
			if absf(odir.dot(dir)) > 0.5:
				continue # параллельные не режут
			var p1: Vector3 = o["a"] - center
			var p2: Vector3 = o["b"] - center
			var along := p1.dot(dir)
			var c1 := p1.dot(normal)
			var c2 := p2.dot(normal)
			var cmin := minf(c1, c2)
			var cmax := maxf(c1, c2)
			if cmax < -half or cmin > half:
				continue # не касается нас
			var reaches := (cmax > width * 0.5) if side > 0 else (cmin < -width * 0.5)
			if not reaches:
				continue
			cuts.append(Vector2(along - half, along + half))
		var pieces := _subtract([Vector2(-full_len * 0.5, full_len * 0.5)], cuts)
		for pc in pieces:
			var plen: float = pc.y - pc.x
			if plen < 0.3:
				continue
			var pm := MeshInstance3D.new()
			var pbm := BoxMesh.new()
			pbm.size = Vector3(plen, CURB_H, sidewalk + CURB_OVERLAP)
			pm.mesh = pbm
			pm.material_override = _mat_curb
			var cz := width * 0.5 + sidewalk * 0.5 - CURB_OVERLAP * 0.5
			pm.position = Vector3((pc.x + pc.y) * 0.5, CURB_TOP - CURB_H * 0.5, side * cz)
			body.add_child(pm)
			var pcs := CollisionShape3D.new()
			var pbs := BoxShape3D.new()
			pbs.size = pbm.size
			pcs.shape = pbs
			pcs.position = pm.position
			body.add_child(pcs)


func _subtract(pieces: Array, cuts: Array) -> Array:
	var out: Array = pieces
	for c in cuts:
		var next: Array = []
		for p in out:
			if c.y <= p.x or c.x >= p.y:
				next.append(p)
				continue
			if c.x > p.x:
				next.append(Vector2(p.x, c.x))
			if c.y < p.y:
				next.append(Vector2(c.y, p.y))
		out = next
	return out


func _build_bump(i: int, b: Vector4) -> void:
	# b = (x, z, yaw°, высота)
	var h := b.w if b.w > 0.05 else 0.3
	var top := road_top_at(Vector3(b.x, 0, b.y))
	if top < 0.0:
		top = ASPHALT_THICK * 0.5
	var depth := width + 0.4
	var body := StaticBody3D.new()
	body.name = "Bump%d" % i
	body.collision_layer = Types.L_WORLD
	body.collision_mask = 0
	body.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(b.z)), Vector3(b.x, top + h * 0.5 - 0.005, b.y))
	add_child(body)
	var mi := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(1.8, h, depth)
	mi.mesh = pm
	mi.material_override = _mat_bump
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var conv := ConvexPolygonShape3D.new()
	var hh := h * 0.5
	var hd := depth * 0.5
	conv.points = PackedVector3Array([
		Vector3(-0.9, -hh, -hd), Vector3(0.9, -hh, -hd), Vector3(0, hh, -hd),
		Vector3(-0.9, -hh, hd), Vector3(0.9, -hh, hd), Vector3(0, hh, hd),
	])
	cs.shape = conv
	body.add_child(cs)
	_bumps.append(body)


func _build_sign(i: int, p: Vector3, text: String) -> void:
	var lbl := Label3D.new()
	lbl.name = "RoadSign%d" % i
	lbl.text = text
	lbl.font_size = 64
	lbl.outline_size = 10
	lbl.pixel_size = 0.011
	lbl.modulate = Color(1, 1, 1)
	lbl.outline_modulate = Color(0.02, 0.15, 0.08)
	lbl.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(p.z)), Vector3(p.x, 2.5, p.y))
	add_child(lbl)
	var board := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(4.4, 1.2, 0.06)
	board.mesh = bb
	board.material_override = _mat_board
	board.position = Vector3(0, 0, -0.05)
	lbl.add_child(board)
	var post := StaticBody3D.new()
	post.collision_layer = Types.L_WORLD
	post.collision_mask = 0
	post.position = Vector3(0, -1.25, -0.1)
	lbl.add_child(post)
	var pm := MeshInstance3D.new()
	var pbm := BoxMesh.new()
	pbm.size = Vector3(0.12, 2.5, 0.12)
	pm.mesh = pbm
	pm.material_override = _mat_post
	post.add_child(pm)
	var pcs := CollisionShape3D.new()
	var pbs := BoxShape3D.new()
	pbs.size = pbm.size
	pcs.shape = pbs
	post.add_child(pcs)
	_signs.append(lbl)
