## Нарезка меша на осколки при разломе вещи.
class_name MeshShatter
extends RefCounted

const _EPS := 1e-5
const _TINY_VOL := 1e-8
const _LowPoly = preload("res://core/LowPoly.gd")


## Collect triangle soup from a MeshInstance3D subtree, in `root` local space.
## Returns PackedVector3Array of verts as triplets (a,b,c, a,b,c, ...). Empty if none.
static func collect_tris(root: Node3D) -> PackedVector3Array:
	if root == null:
		return PackedVector3Array()
	var out := PackedVector3Array()
	for mi in _gather_mesh_instances(root):
		if mi.mesh == null:
			continue
		var to_root := _xform_to_root(mi, root)
		var mesh: Mesh = mi.mesh
		for s in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(s)
			if arrays.is_empty() or arrays.size() <= Mesh.ARRAY_VERTEX:
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			if verts.is_empty():
				continue
			var indices := PackedInt32Array()
			if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
				indices = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
			if indices.size() >= 3:
				for i in range(0, indices.size(), 3):
					out.append(to_root * verts[indices[i]])
					out.append(to_root * verts[indices[i + 1]])
					out.append(to_root * verts[indices[i + 2]])
			else:
				for i in range(0, verts.size(), 3):
					if i + 2 >= verts.size():
						break
					out.append(to_root * verts[i])
					out.append(to_root * verts[i + 1])
					out.append(to_root * verts[i + 2])
	return out


## Shatter into `count` pieces (3..8). Deterministic for same seed.
## Returns Array of Dictionaries:
##   { "mesh": ArrayMesh, "centroid": Vector3 (in root local), "extents": Vector3 (AABB size) }
static func shatter(root: Node3D, count: int, rng_seed: int) -> Array:
	if root == null:
		return []
	var all_tris := collect_tris(root)
	if all_tris.is_empty():
		return []
	var piece_count := clampi(count, 3, 8)
	var aabb := _tris_aabb(all_tris)
	var seeds := _place_seeds(aabb, piece_count, rng_seed)
	var result: Array = []
	for i in piece_count:
		var cell_tris := _extract_cell(all_tris, seeds, i)
		var piece: Dictionary = _build_piece(cell_tris)
		if not piece.is_empty():
			result.append(piece)
	return result


static func _gather_mesh_instances(root: Node3D) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for child in root.find_children("*", "MeshInstance3D", true, false):
		out.append(child as MeshInstance3D)
	if root is MeshInstance3D:
		out.append(root as MeshInstance3D)
	return out


static func _xform_to_root(mi: Node3D, root: Node3D) -> Transform3D:
	var xf := mi.transform
	var parent: Node = mi.get_parent()
	while parent != null and parent != root:
		if parent is Node3D:
			xf = (parent as Node3D).transform * xf
		parent = parent.get_parent()
	return xf


static func _tris_aabb(tris: PackedVector3Array) -> AABB:
	if tris.is_empty():
		return AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
	var mn := tris[0]
	var mx := tris[0]
	for v in tris:
		mn = mn.min(v)
		mx = mx.max(v)
	return AABB(mn, mx - mn)


static func _place_seeds(aabb: AABB, n: int, rng_seed: int) -> Array[Vector3]:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var seeds: Array[Vector3] = []
	var sz := aabb.size
	if sz.length_squared() < _EPS:
		sz = Vector3.ONE
	for _i in n:
		seeds.append(
			aabb.position + Vector3(
				rng.randf() * sz.x,
				rng.randf() * sz.y,
				rng.randf() * sz.z
			)
		)
	return seeds


static func _extract_cell(all_tris: PackedVector3Array, seeds: Array[Vector3], idx: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var tri_count := all_tris.size() / 3
	var my_seed: Vector3 = seeds[idx]
	for t in tri_count:
		var poly := PackedVector3Array([
			all_tris[t * 3],
			all_tris[t * 3 + 1],
			all_tris[t * 3 + 2],
		])
		for j in seeds.size():
			if j == idx:
				continue
			var other: Vector3 = seeds[j]
			var plane := _bisector_plane(my_seed, other)
			poly = _clip_polygon(poly, plane["normal"], plane["point"])
			if poly.size() < 3:
				break
		if poly.size() < 3:
			continue
		for k in range(1, poly.size() - 1):
			out.append(poly[0])
			out.append(poly[k])
			out.append(poly[k + 1])
	return out


static func _bisector_plane(si: Vector3, sj: Vector3) -> Dictionary:
	var n := si - sj
	if n.length_squared() < _EPS:
		n = Vector3.UP
	else:
		n = n.normalized()
	var pt := (si + sj) * 0.5
	return {"normal": n, "point": pt}


static func _plane_dist(p: Vector3, normal: Vector3, point: Vector3) -> float:
	return (p - point).dot(normal)


static func _segment_plane_intersect(a: Vector3, b: Vector3, normal: Vector3, point: Vector3) -> Vector3:
	var ab := b - a
	var denom := normal.dot(ab)
	if absf(denom) < _EPS:
		return a.lerp(b, 0.5)
	var t := -(a - point).dot(normal) / denom
	return a.lerp(b, clampf(t, 0.0, 1.0))


static func _clip_polygon(poly: PackedVector3Array, normal: Vector3, point: Vector3) -> PackedVector3Array:
	if poly.size() < 3:
		return PackedVector3Array()
	var out := PackedVector3Array()
	var count := poly.size()
	var prev: Vector3 = poly[count - 1]
	var prev_in := _plane_dist(prev, normal, point) >= -_EPS
	for i in count:
		var cur: Vector3 = poly[i]
		var cur_in := _plane_dist(cur, normal, point) >= -_EPS
		if cur_in:
			if not prev_in:
				out.append(_segment_plane_intersect(prev, cur, normal, point))
			out.append(cur)
		elif prev_in:
			out.append(_segment_plane_intersect(prev, cur, normal, point))
		prev = cur
		prev_in = cur_in
	return out


static func _build_piece(cell_tris: PackedVector3Array) -> Dictionary:
	var tri_count := cell_tris.size() / 3
	var verts := cell_tris
	var extents := _aabb_size(verts)
	var centroid := _centroid(verts)
	if tri_count < 3 or extents.x * extents.y * extents.z < _TINY_VOL:
		return _fallback_piece(verts, centroid, extents)
	var mesh: ArrayMesh = _tris_to_mesh(cell_tris)
	return {"mesh": mesh, "centroid": centroid, "extents": extents}


static func _aabb_size(verts: PackedVector3Array) -> Vector3:
	if verts.is_empty():
		return Vector3.ZERO
	var mn := verts[0]
	var mx := verts[0]
	for v in verts:
		mn = mn.min(v)
		mx = mx.max(v)
	return mx - mn


static func _centroid(verts: PackedVector3Array) -> Vector3:
	if verts.is_empty():
		return Vector3.ZERO
	var sum := Vector3.ZERO
	for v in verts:
		sum += v
	return sum / float(verts.size())


static func _fallback_piece(verts: PackedVector3Array, centroid: Vector3, extents: Vector3) -> Dictionary:
	var size := extents * 0.9
	if verts.is_empty():
		centroid = Vector3.ZERO
		size = Vector3(0.05, 0.05, 0.05)
		extents = size / 0.9
	size.x = maxf(size.x, 0.02)
	size.y = maxf(size.y, 0.02)
	size.z = maxf(size.z, 0.02)
	var bevel := minf(minf(size.x, size.y), size.z) * 0.15
	var mesh: ArrayMesh = _LowPoly.chamfer_box(size, bevel)
	return {"mesh": mesh, "centroid": centroid, "extents": extents}


static func _tris_to_mesh(tris: PackedVector3Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0, tris.size(), 3):
		if i + 2 >= tris.size():
			break
		st.add_vertex(tris[i])
		st.add_vertex(tris[i + 1])
		st.add_vertex(tris[i + 2])
	st.generate_normals()
	return st.commit()
