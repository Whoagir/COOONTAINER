class_name City
extends Node3D
## Город (§12): районы + короткие дороги. Дети — District-сцены. Миникарты нет: знаки и пин.

var _districts: Dictionary = {} # Types.District → District


func _ready() -> void:
	for c in get_children():
		if c is District:
			_districts[c.district_id] = c
	for c in get_children():
		if c.has_method("build_roads"):
			c.build_roads()


func district_root(d: int) -> Node3D:
	return _districts.get(d)


func districts() -> Array:
	return _districts.values()


func district_at(pos: Vector3) -> District:
	var best: District = null
	var best_d := 1e9
	for d in _districts.values():
		var dist: float = d.global_position.distance_to(pos)
		if dist < d.radius and dist < best_d:
			best_d = dist
			best = d
	return best


func lot_anchors(d: int) -> Array:
	var root := district_root(d)
	if root == null:
		return []
	return root.lot_anchors()


## Маркер по имени внутри района (см. «Контракт имён» в ARCHITECTURE.md).
func marker(d: int, name: String) -> Node3D:
	var root := district_root(d)
	if root == null:
		return null
	return root.find_child(name, true, false) as Node3D


## Точки появления игроков — кровати трейлера (Bed0..3), глобальные позиции.
func spawn_points() -> Array:
	var out: Array = []
	var tp := district_root(Types.District.TRAILER_PARK)
	if tp == null:
		return out
	for i in 4:
		var b := tp.find_child("Bed%d" % i, true, false) as Node3D
		if b:
			out.append(b.global_position + Vector3(0, 0.3, 0))
	return out


func roads() -> Node3D:
	return get_node_or_null("Roads") as Node3D


## Кочки Bump* (StaticBody3D) — для тачек/ачивок.
func road_bumps() -> Array:
	var r := roads()
	return r.bump_nodes() if r and r.has_method("bump_nodes") else []


## Знаки RoadSign* (Label3D).
func road_signs() -> Array:
	var r := roads()
	return r.sign_nodes() if r and r.has_method("sign_nodes") else []
