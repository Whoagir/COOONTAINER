class_name HomeClutter
extends Node3D
## Одноразовый «домашний» хлам у трейлера: кружки, пиво, пульт, гитара у стены.
## Хост спавнит 35–50 мелких ItemBody на поверхностях (рейкаст вниз), спящими.
## Флаг `home_clutter_done` в сейве — не респавнить после уборки.

const MIN_ITEMS := 35
const MAX_ITEMS := 50
const SURFACE_LIFT := 0.02
const RAY_UP := 3.5
const RAY_DOWN := 2.5

const PREF_TAGS: Array[String] = [
	"junk", "household", "tiny", "toy", "book", "bottle", "can", "cup", "mug", "kitchen",
]
const PREF_WORDS: Array[String] = [
	"mug", "cup", "can", "bottle", "beer", "remote", "slipper", "shoe", "cassette", "boombox",
	"kettle", "teddy", "bear", "card", "dice", "lighter", "match", "key", "magazine", "paper",
	"plate", "fork", "spoon", "soap", "comb", "wallet", "tin", "guitar", "mop", "bucket",
	"jar", "letter", "bill", "book", "ashtray", "fishing",
]
const FIXED_IDS: Array[String] = [
	"guitar_acoustic", "guitar_kids", "hamster_cage_empty", "mop_grey", "mop_gross",
	"bucket_kfs", "bucket_ice", "fishing_rod_worn",
]

var _rng := RandomNumberGenerator.new()
var _pool: Array[ItemDef] = []
var _hinted := false


func system_name() -> String:
	return "HomeClutter"


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	if OS.get_cmdline_user_args().has("--nettest"):
		print("[HomeClutter] skipped (--nettest)")
		return
	if not Net.is_host():
		print("[HomeClutter] spawned 0 items (client)")
		return
	if bool(Game.save.get("home_clutter_done", false)):
		print("[HomeClutter] skipped (already done)")
		return
	var w: World = Game.world as World
	if w == null:
		return
	_rng.seed = hash(Game.slot) + 7919
	_build_pool()
	var n := _scatter()
	Game.save["home_clutter_done"] = true
	print("[HomeClutter] spawned %d items" % n)


func _build_pool() -> void:
	_pool.clear()
	for raw in Registry.all_items():
		var d: ItemDef = raw as ItemDef
		if d == null or not _eligible(d):
			continue
		_pool.append(d)


func _eligible(d: ItemDef) -> bool:
	if d.illegal or d.is_cash() or d.has_facet(Types.Facet.ILLEGAL) or d.has_facet(Types.Facet.ALIVE):
		return false
	if d.value_base < 1 or d.value_base > 80:
		return false
	var arch: Archetype = Registry.archetype_for(d)
	if arch == null:
		return false
	if arch.size_class == Types.SizeClass.TEAM or arch.size_class == Types.SizeClass.VEHICLE:
		return false
	if arch.size_class == Types.SizeClass.TWO_HAND and not FIXED_IDS.has(d.id):
		return false
	if not _liquid_ok(d, arch):
		return false
	return true


func _liquid_ok(d: ItemDef, arch: Archetype) -> bool:
	if d.liquid_id == Types.LiquidId.NONE:
		return true
	return arch.id == "bottle" or arch.id == "glass"


func _weight(d: ItemDef) -> float:
	var w := 1.0
	for t in PREF_TAGS:
		if d.tags.has(t):
			w += 3.5
	var blob := (d.id + " " + d.archetype_id).to_lower()
	for t in PREF_WORDS:
		if blob.contains(t):
			w += 2.0
			break
	return w


func _pick_item() -> ItemDef:
	if _pool.is_empty():
		return null
	var total := 0.0
	var weights: Array[float] = []
	for d in _pool:
		var w := _weight(d)
		weights.append(w)
		total += w
	var roll := _rng.randf() * total
	var acc := 0.0
	for i in _pool.size():
		acc += weights[i]
		if roll <= acc:
			return _pool[i]
	return _pool[_pool.size() - 1]


func _scatter() -> int:
	var w: World = Game.world as World
	if w == null:
		return 0
	var dist: District = w.district_root(Types.District.TRAILER_PARK) as District
	var tr: Node3D = w.find_marker(Types.District.TRAILER_PARK, "Trailer")
	if dist == null or tr == null:
		return 0
	var o: Vector3 = dist.to_local(tr.global_position)
	var want := _rng.randi_range(MIN_ITEMS, MAX_ITEMS)
	var placed := 0
	var spots: Array[Vector3] = []
	var slots: Array[Dictionary] = _build_slots(w, dist, o)
	for slot in slots:
		if placed >= want:
			break
		var def_id := str(slot.get("item_id", ""))
		var def: ItemDef = Registry.item(def_id) if def_id != "" else _pick_item()
		if def == null:
			continue
		var target: Vector3 = slot["pos"] as Vector3
		var spread: Vector2 = slot.get("spread", Vector2.ZERO) as Vector2
		if spread.length_squared() > 0.0001:
			target += Vector3(
				_rng.randf_range(-spread.x, spread.x),
				0.0,
				_rng.randf_range(-spread.y, spread.y),
			)
		if not _ok_spot(target, spots):
			continue
		var yaw: float = float(slot.get("yaw", _rng.randf() * TAU))
		var lean: bool = bool(slot.get("lean", false))
		var fixed_y: bool = bool(slot.get("fixed_y", false))
		var b: ItemBody = _spawn_home(def, target, yaw, lean, fixed_y)
		if b == null:
			continue
		spots.append(b.global_position)
		placed += 1
	var guard := 0
	while placed < want and guard < 200:
		guard += 1
		var def2: ItemDef = _pick_item()
		if def2 == null:
			break
		var xz: Vector2 = _random_yard(_rng, o)
		var pos: Vector3 = dist.to_global(o + Vector3(xz.x, 0.5, xz.y))
		if not _ok_spot(pos, spots):
			continue
		var b2: ItemBody = _spawn_home(def2, pos, _rng.randf() * TAU, false)
		if b2 == null:
			continue
		spots.append(b2.global_position)
		placed += 1
	return placed


func _build_slots(w: World, dist: District, o: Vector3) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var to_g := func(local: Vector3) -> Vector3: return dist.to_global(o + local)

	# стол (Interiors: ~1.6, 0.82, −1.1)
	for i in 8:
		out.append({
			"pos": to_g.call(Vector3(1.15 + float(i % 4) * 0.28, 0.82, -1.05 + float(i / 4) * 0.22)),
			"spread": Vector2(0.08, 0.08),
			"fixed_y": true,
		})
	# кухонная стойка (+X)
	for i in 5:
		out.append({
			"pos": to_g.call(Vector3(3.25, 0.86, -0.05 + float(i) * 0.18)),
			"spread": Vector2(0.06, 0.04),
			"fixed_y": true,
		})
	# полка (−Z стена)
	for i in 4:
		out.append({
			"pos": to_g.call(Vector3(-0.15 + float(i) * 0.22, 1.62, -1.58)),
			"spread": Vector2(0.05, 0.03),
			"fixed_y": true,
		})
	out.append({
		"pos": to_g.call(Vector3(0.1, 1.62, -1.58)),
		"item_id": "hamster_cage_empty",
		"fixed_y": true,
	})
	# кровати
	for bi in 4:
		var bed: Node3D = w.find_marker(Types.District.TRAILER_PARK, "Bed%d" % bi)
		if bed:
			for j in 3:
				out.append({
					"pos": bed.global_position + Vector3(-0.25 + float(j) * 0.25, 0.48, 0.05),
					"spread": Vector2(0.12, 0.18),
					"fixed_y": true,
				})
	# пол внутри трейлера — углы
	var floor_in: Array[Vector3] = [
		Vector3(-3.35, 0.12, 0.9), Vector3(-3.2, 0.12, -0.7), Vector3(2.9, 0.12, -1.45),
		Vector3(2.6, 0.12, 0.95), Vector3(0.6, 0.12, -1.55), Vector3(-1.8, 0.12, 0.35),
	]
	for p in floor_in:
		out.append({"pos": to_g.call(p), "spread": Vector2(0.14, 0.14)})
	# крыльцо / ступени у двери
	var door: Node3D = w.find_marker(Types.District.TRAILER_PARK, "TrailerDoor")
	if door:
		for i in 5:
			out.append({
				"pos": door.global_position + Vector3(-0.6 + float(i) * 0.3, 0.08, 0.55 + float(i % 2) * 0.25),
				"spread": Vector2(0.1, 0.08),
			})
	# гитара у стены
	out.append({
		"pos": to_g.call(Vector3(-3.55, 0.55, -0.35)),
		"item_id": "guitar_acoustic",
		"yaw": deg_to_rad(78.0),
		"lean": true,
		"fixed_y": true,
	})
	# швабра + ведро у кухни
	out.append({"pos": to_g.call(Vector3(3.05, 0.12, 0.85)), "item_id": "mop_grey", "yaw": deg_to_rad(-15.0)})
	out.append({"pos": to_g.call(Vector3(3.35, 0.12, 1.05)), "item_id": "bucket_kfs"})
	# костёр и двор
	var cf: Node3D = w.find_marker(Types.District.TRAILER_PARK, "Campfire")
	if cf:
		for i in 10:
			var ang := _rng.randf() * TAU
			var r := _rng.randf_range(0.55, 1.65)
			out.append({
				"pos": cf.global_position + Vector3(cos(ang) * r, 0.12, sin(ang) * r),
				"spread": Vector2(0.12, 0.12),
			})
		out.append({
			"pos": cf.global_position + Vector3(1.35, 0.15, -0.85),
			"item_id": "boombox_90s",
			"yaw": deg_to_rad(32.0),
		})
		out.append({
			"pos": cf.global_position + Vector3(-1.1, 0.12, 1.2),
			"item_id": "bucket_ice",
		})
	# удочка у стены трейлера снаружи
	out.append({
		"pos": to_g.call(Vector3(-3.85, 0.45, 1.25)),
		"item_id": "fishing_rod_worn",
		"yaw": deg_to_rad(-70.0),
		"lean": true,
		"fixed_y": true,
	})
	return out


func _random_yard(rng: RandomNumberGenerator, o: Vector3) -> Vector2:
	var roll := rng.randf()
	if roll < 0.45:
		return Vector2(rng.randf_range(-3.8, 3.6), rng.randf_range(-1.6, 1.5))
	if roll < 0.75:
		return Vector2(rng.randf_range(-2.5, 2.8), rng.randf_range(-2.2, -0.8))
	return Vector2(rng.randf_range(3.8, 7.5), rng.randf_range(-2.0, 2.5))


func _ok_spot(pos: Vector3, spots: Array[Vector3]) -> bool:
	for s in spots:
		if Vector2(pos.x - s.x, pos.z - s.z).length() < 0.22:
			return false
	return true


func _half_height(def: ItemDef) -> float:
	var arch: Archetype = Registry.archetype_for(def)
	if arch == null:
		return 0.05
	return arch.dims.y * 0.5 * def.scale


func _surface_at(aim: Vector3, half_h: float) -> Variant:
	var space := get_world_3d().direct_space_state
	if space == null:
		return null
	var q := PhysicsRayQueryParameters3D.create(
		aim + Vector3(0, RAY_UP, 0),
		aim + Vector3(0, -RAY_DOWN, 0),
		Types.L_WORLD,
	)
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return null
	var pos: Vector3 = hit["position"] as Vector3
	return pos + Vector3(0, half_h + SURFACE_LIFT, 0)


func _spawn_home(def: ItemDef, aim: Vector3, yaw: float, lean: bool, fixed_y: bool = false) -> ItemBody:
	if def == null:
		return null
	var half_h := _half_height(def)
	var pos: Vector3
	if fixed_y:
		pos = aim + Vector3(0, half_h + SURFACE_LIFT, 0)
	else:
		var g: Variant = _surface_at(aim, half_h)
		if typeof(g) != TYPE_VECTOR3:
			return null
		pos = g as Vector3
	var basis := Basis(Vector3.UP, yaw)
	if lean:
		basis = basis * Basis(Vector3.RIGHT, deg_to_rad(-72.0))
	var xf := Transform3D(basis, pos)
	var b: ItemBody = Net.spawn_item(def.id, xf) as ItemBody
	if b == null:
		return null
	b.set_meta("home", true)
	b.sleeping = true
	if not b.picked.is_connected(_on_home_picked):
		b.picked.connect(_on_home_picked)
	return b


func _on_home_picked(_b: ItemBody, _by: Node) -> void:
	if _hinted:
		return
	_hinted = true
	Game.notify.emit(tr("HOME_HINT"), 4.0)
