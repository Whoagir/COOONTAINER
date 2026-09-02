class_name YardZones
extends Node3D
## Дворы трейлер-парка: своя площадка vs чужие. Визуал рамками + лут соседей.
## Хост помечает ItemBody.stolen при подборе с чужой зоны / meta neighbor / кражи у хантера.

const PLAYER_HALF := Vector2(7.5, 9.0) ## xz half-extents вокруг трейлера
const NEIGHBOR_HALF := Vector2(5.2, 5.8)
const THEFT_POLICE_SEC := 7.0
const LOOT_PER_YARD := 6
const LOOT_VALUE_MAX := 55

const PREF_TAGS: Array[String] = [
	"junk", "household", "tiny", "toy", "bottle", "can", "cup", "kitchen",
]

var _zones: Array[Dictionary] = [] ## {id, foreign, center, half, yaw}
var _thefts: Array = [] ## {peer, t, pos}
var _pool: Array[ItemDef] = []
var _rng := RandomNumberGenerator.new()
var _hinted_player := false
var _hinted_foreign := false


func system_name() -> String:
	return "YardZones"


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame
	_setup()


func _setup() -> void:
	_zones.clear()
	var tr: Node3D = null
	if Game.world and Game.world.has_method("find_marker"):
		tr = Game.world.find_marker(Types.District.TRAILER_PARK, "Trailer") as Node3D
	var center := Vector3(0, 0, -14)
	if tr:
		center = tr.global_position
	_add_zone("player", false, center, PLAYER_HALF, 0.0)
	_paint_zone(_zones[0], Color(0.15, 0.72, 0.62, 0.5), tr("YARD_OURS"))
	_discover_neighbors()
	if Net.is_host() and not OS.get_cmdline_user_args().has("--nettest"):
		_build_pool()
		_rng.seed = hash(Game.slot) + 44017
		_spawn_neighbor_loot()
	if OS.is_debug_build():
		print("[YardZones] zones=%d" % _zones.size())


func _discover_neighbors() -> void:
	var city: Node = Game.world.city if Game.world else null
	if city == null:
		return
	var props: Node = city.get_node_or_null("Props")
	if props == null:
		return
	var idx := 0
	for c in props.get_children():
		if not str(c.name).begins_with("Neighbor"):
			continue
		if str(c.name).contains("Yard") or str(c.name).contains("F") or str(c.name).contains("M"):
			continue
		# Neighbor0..N — StaticBody трейлера
		if not (c is Node3D):
			continue
		var n: Node3D = c
		var yaw := rad_to_deg(n.global_rotation.y)
		# двор перед дверью (+Z локально у соседа)
		var front: Vector3 = n.global_transform.basis * Vector3(0, 0, 3.2)
		var yard_c: Vector3 = n.global_position + front
		yard_c.y = 0.0
		_add_zone("neighbor_%d" % idx, true, yard_c, NEIGHBOR_HALF, yaw)
		_paint_zone(_zones[_zones.size() - 1], Color(0.85, 0.22, 0.18, 0.55), tr("YARD_THEIRS"))
		idx += 1


func _add_zone(id: String, foreign: bool, center: Vector3, half: Vector2, yaw_deg: float) -> void:
	_zones.append({
		"id": id,
		"foreign": foreign,
		"center": Vector3(center.x, 0.0, center.z),
		"half": half,
		"yaw": yaw_deg,
	})


func zone_at(pos: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_d := 1e9
	for z in _zones:
		if not _inside(z, pos):
			continue
		var c: Vector3 = z["center"]
		var d := Vector2(pos.x - c.x, pos.z - c.z).length_squared()
		if d < best_d:
			best_d = d
			best = z
	return best


func is_foreign_at(pos: Vector3) -> bool:
	var z := zone_at(pos)
	return not z.is_empty() and bool(z.get("foreign", false))


func is_player_yard(pos: Vector3) -> bool:
	var z := zone_at(pos)
	return not z.is_empty() and not bool(z.get("foreign", false))


func should_mark_stolen(b: ItemBody) -> bool:
	if b == null or not is_instance_valid(b) or b.stolen:
		return false
	if b.def and b.def.is_cash():
		return false
	if b.get_meta("home", false):
		return false
	if b.get_meta("street", false):
		return false
	if b.get_meta("evidence", false):
		return false
	if b.get_meta("neighbor", false):
		return true
	# свой активный clear-out — легальный вынос
	if b.lot_id != "" and _is_party_clearout_lot(b.lot_id):
		return false
	return is_foreign_at(b.global_position)


func _is_party_clearout_lot(lot_id: String) -> bool:
	if Game.world_mode != Types.WorldMode.CLEAR_OUT:
		return false
	var co: Node = Game.world.system("ClearOut") if Game.world else null
	if co == null or not co.has_method("is_active") or not co.is_active():
		return false
	var preset = co.get("preset")
	return preset != null and str(preset.get("id")) == lot_id


## Хост: после успешного grab.
func on_host_grab(player: Player, b: ItemBody) -> void:
	if not Net.is_host() or player == null or b == null:
		return
	if not should_mark_stolen(b):
		if is_player_yard(b.global_position) and b.get_meta("home", false) and not _hinted_player:
			_hinted_player = true
			Game.notify.emit(tr("YARD_HINT_OURS"), 3.5)
		return
	b.mark_stolen()
	Game.stat_add("items_stolen")
	if not _hinted_foreign:
		_hinted_foreign = true
		Game.notify.emit(tr("YARD_HINT_STOLEN"), 4.0)
	elif player.is_local():
		Game.notify.emit(tr("YARD_STOLEN_TOAST"), 2.5)
	_thefts.append({"peer": player.peer_id, "t": THEFT_POLICE_SEC, "pos": b.global_position})


## Хост: украли у хантера на аукционе.
func on_hunter_steal(player: Player, b: ItemBody) -> void:
	if not Net.is_host() or b == null:
		return
	if not b.stolen:
		b.mark_stolen()
		Game.stat_add("items_stolen")
	if player:
		_thefts.append({"peer": player.peer_id, "t": THEFT_POLICE_SEC * 0.7, "pos": b.global_position})
	Game.notify.emit(tr("YARD_HINT_STOLEN"), 3.5)


func _process(delta: float) -> void:
	if not Net.is_host() or _thefts.is_empty():
		return
	for i in range(_thefts.size() - 1, -1, -1):
		var th: Dictionary = _thefts[i]
		th["t"] = float(th["t"]) - delta
		if float(th["t"]) > 0.0:
			_thefts[i] = th
			continue
		_thefts.remove_at(i)
		var police: Node = Game.world.system("Police") if Game.world else null
		if police == null or not police.has_method("trigger"):
			continue
		var p: Player = Net.players.get(int(th.get("peer", 0)))
		police.trigger(Types.PoliceTrigger.PROPERTY_THEFT, th.get("pos", Vector3.ZERO), p)


# ------------------------------------------------------------------ лут соседей

func _build_pool() -> void:
	_pool.clear()
	for raw in Registry.all_items():
		var d: ItemDef = raw as ItemDef
		if d == null:
			continue
		if d.illegal or d.is_cash() or d.has_facet(Types.Facet.ILLEGAL) or d.has_facet(Types.Facet.ALIVE):
			continue
		if d.value_base < 1 or d.value_base > LOOT_VALUE_MAX:
			continue
		var arch: Archetype = Registry.archetype_for(d)
		if arch == null:
			continue
		if arch.size_class == Types.SizeClass.TEAM or arch.size_class == Types.SizeClass.VEHICLE:
			continue
		if arch.size_class == Types.SizeClass.TWO_HAND:
			continue
		_pool.append(d)


func _pick() -> ItemDef:
	if _pool.is_empty():
		return null
	var weighted: Array[ItemDef] = []
	for d in _pool:
		var w := 1
		for t in PREF_TAGS:
			if d.tags.has(t):
				w += 2
				break
		for _i in w:
			weighted.append(d)
	return weighted[_rng.randi() % weighted.size()]


func _spawn_neighbor_loot() -> void:
	var n := 0
	for z in _zones:
		if not bool(z.get("foreign", false)):
			continue
		for _i in LOOT_PER_YARD:
			var def := _pick()
			if def == null:
				break
			var c: Vector3 = z["center"]
			var half: Vector2 = z["half"]
			var yaw := deg_to_rad(float(z.get("yaw", 0.0)))
			var lx := _rng.randf_range(-half.x * 0.7, half.x * 0.7)
			var lz := _rng.randf_range(-half.y * 0.55, half.y * 0.55)
			var local := Vector3(lx, 0.4, lz).rotated(Vector3.UP, yaw)
			var aim := c + local
			var b := _spawn_at(def, aim)
			if b:
				n += 1
	if OS.is_debug_build():
		print("[YardZones] neighbor loot=%d" % n)


func _spawn_at(def: ItemDef, aim: Vector3) -> ItemBody:
	var arch: Archetype = Registry.archetype_for(def)
	if arch == null:
		return null
	var half_h := arch.dims.y * 0.5 * def.scale
	var space := get_world_3d().direct_space_state
	var pos := aim
	if space:
		var q := PhysicsRayQueryParameters3D.create(
			aim + Vector3(0, 3.0, 0), aim + Vector3(0, -4.0, 0), Types.L_WORLD
		)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			pos = (hit["position"] as Vector3) + Vector3(0, half_h + 0.02, 0)
	var xf := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), pos)
	var b: ItemBody = Net.spawn_item(def.id, xf) as ItemBody
	if b == null:
		return null
	b.set_meta("neighbor", true)
	b.sleeping = true
	return b


# ------------------------------------------------------------------ визуал

func _paint_zone(z: Dictionary, col: Color, label: String) -> void:
	var c: Vector3 = z["center"]
	var half: Vector2 = z["half"]
	var yaw := deg_to_rad(float(z.get("yaw", 0.0)))
	var basis := Basis(Vector3.UP, yaw)
	var y := 0.08
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space:
		var q := PhysicsRayQueryParameters3D.create(c + Vector3(0, 2, 0), c + Vector3(0, -2, 0), Types.L_WORLD)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			y = (hit["position"] as Vector3).y + 0.1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var w := half.x * 2.0
	var d := half.y * 2.0
	var thick := 0.14
	# рамка: 4 полосы на земле
	var bars: Array[Vector3] = [
		Vector3(0, 0, -half.y), Vector3(0, 0, half.y),
		Vector3(-half.x, 0, 0), Vector3(half.x, 0, 0),
	]
	var sizes: Array[Vector2] = [
		Vector2(w, thick), Vector2(w, thick),
		Vector2(thick, d), Vector2(thick, d),
	]
	for i in 4:
		var mi := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = sizes[i]
		mi.mesh = qm
		mi.material_override = mat
		add_child(mi)
		mi.global_position = c + basis * bars[i] + Vector3(0, y, 0)
		mi.global_basis = basis * Basis(Vector3.RIGHT, -PI / 2)
	# лёгкая заливка пола
	var fill := MeshInstance3D.new()
	var fq := QuadMesh.new()
	fq.size = Vector2(w * 0.92, d * 0.92)
	fill.mesh = fq
	var fm := mat.duplicate() as StandardMaterial3D
	fm.albedo_color = Color(col.r, col.g, col.b, col.a * 0.22)
	fill.material_override = fm
	add_child(fill)
	fill.global_position = c + Vector3(0, y - 0.01, 0)
	fill.global_basis = basis * Basis(Vector3.RIGHT, -PI / 2)
	var lbl := Label3D.new()
	lbl.text = label
	lbl.font_size = 72
	lbl.outline_size = 10
	lbl.pixel_size = 0.0032
	lbl.modulate = Color(col.r, col.g, col.b, 0.95).lightened(0.35)
	lbl.outline_modulate = Color(0.05, 0.04, 0.03, 0.9)
	lbl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	add_child(lbl)
	lbl.global_position = c + Vector3(0, y + 0.02, 0)
	lbl.global_basis = basis * Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, -PI / 2)


func _inside(z: Dictionary, pos: Vector3) -> bool:
	var c: Vector3 = z["center"]
	var half: Vector2 = z["half"]
	var yaw := deg_to_rad(float(z.get("yaw", 0.0)))
	var local := (pos - c).rotated(Vector3.UP, -yaw)
	return absf(local.x) <= half.x and absf(local.z) <= half.y
