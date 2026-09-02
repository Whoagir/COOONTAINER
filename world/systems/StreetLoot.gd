class_name StreetLoot
extends Node3D
## Уличный хлам и мусорки: хост раскидывает подбираемые вещи по городу и держит
## порыться-в-баке (E). Клиенты видят геометрию и хинт; спавн только у хоста.

const MAX_STREET := 80
const SCATTER_N := 70
const TRICKLE_SEC := 90.0
const TRICKLE_KEEP := 50
const CHARGES := 3
const RUMMAGE_SEC := 1.2
const DAY_FALLBACK := 600.0
const BODY := Vector3(1.8, 1.2, 1.0)
const PREF_TAGS: Array[String] = ["junk", "trash", "toy", "book", "tool", "bottle", "can"]
const PREF_WORDS: Array[String] = [
	"junk", "trash", "toy", "book", "tool", "bottle", "can", "tire", "brick",
	"sock", "rag", "cup", "plate", "jar", "boot", "shoe", "hat",
]
const _ROADS: Array[Vector4] = [
	Vector4(-165, -60, 165, -60), Vector4(-165, 45, 165, 45), Vector4(-165, 110, 165, 110),
	Vector4(-165, -60, -165, 110), Vector4(165, -60, 165, 110), Vector4(0, 45, 0, 135),
	Vector4(-75, -60, -75, 45), Vector4(75, -60, 75, 45), Vector4(0, -100, 0, -60),
	Vector4(120, -100, 120, -60), Vector4(-110, -100, -110, -60),
	Vector4(110, 45, 110, 64), Vector4(-120, 45, -120, 64),
]
## Пропсы из Props.gd / City.tscn — те же координаты ±1.5 м.
const _PROP_XZ: Array[Vector2] = [
	Vector2(-108, -27), Vector2(26, -108), Vector2(92, -100), Vector2(128, 62),
	Vector2(-100, 62), Vector2(30, 12), Vector2(-30, -20), Vector2(-132.5, -4.8),
	Vector2(-107.2, -5.2), Vector2(-30, -48), Vector2(60, 58), Vector2(-154, 80),
	Vector2(140, -70), Vector2(-70, 98), Vector2(-55, 32), Vector2(58, -36),
	Vector2(-24, 142), Vector2(-12.4, -9.2), Vector2(32, 16), Vector2(-42, -88),
	Vector2(48, -82), Vector2(-92, 28), Vector2(86, 28), Vector2(18, 132),
]


class Dumpster extends StaticBody3D:
	var charges: int = 3
	var busy := false
	var system: StreetLoot
	var lid: Node3D

	func interact(player: Node) -> void:
		if system:
			system.rummage(self, player)

	func interact_hint(_player: Node) -> String:
		if charges <= 0:
			return tr("STREET_DUMPSTER_EMPTY")
		return tr("STREET_DUMPSTER")


var _rng := RandomNumberGenerator.new()
var _common: Array[ItemDef] = []
var _finds: Array[ItemDef] = []
var _dump_finds: Array[ItemDef] = []
var _dumpsters: Array[Dumpster] = []
var _trickle := 0.0
var _day_real := 0.0
var _tod := -1.0
var _hinted := false
var _mouse_id := "mouse_live"


func system_name() -> String:
	return "StreetLoot"


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	var w: World = Game.world as World
	if w == null:
		return
	_rng.seed = hash(Game.slot) + int(Game.save.get("day", 0))
	_build_pools()
	_build_dumpsters()
	if Net.is_host():
		var n := _scatter(SCATTER_N, false)
		print("[StreetLoot] spawned %d items, %d dumpsters" % [n, _dumpsters.size()])
	else:
		print("[StreetLoot] spawned 0 items, %d dumpsters" % _dumpsters.size())


func _process(delta: float) -> void:
	if not Net.is_host() or Game.world == null:
		return
	_trickle += delta
	_day_real += delta
	var dn: DayNight = Game.world.system("DayNight") as DayNight
	if dn:
		if _tod >= 0.0 and dn.time_of_day + 0.35 < _tod:
			_reset_charges()
			_day_real = 0.0
		_tod = dn.time_of_day
	if _day_real >= DAY_FALLBACK:
		_day_real = 0.0
		_reset_charges()
	if _trickle < TRICKLE_SEC:
		return
	_trickle = 0.0
	if _street_count() < TRICKLE_KEEP:
		_scatter(_rng.randi_range(3, 5), true)


# ------------------------------------------------------------------ пул

func _build_pools() -> void:
	_common.clear()
	_finds.clear()
	_dump_finds.clear()
	for raw in Registry.all_items():
		var d: ItemDef = raw as ItemDef
		if d == null or not _eligible(d):
			continue
		if d.value_base <= 60:
			_common.append(d)
		if d.value_base >= 60 and d.value_base <= 200:
			_finds.append(d)
		if d.value_base >= 60 and d.value_base <= 300:
			_dump_finds.append(d)
	_mouse_id = _resolve_mouse()


func _eligible(d: ItemDef) -> bool:
	if d.illegal or d.is_cash() or d.has_facet(Types.Facet.ILLEGAL) or d.has_facet(Types.Facet.ALIVE):
		return false
	var arch: Archetype = Registry.archetype_for(d)
	if arch == null:
		return false
	if arch.size_class == Types.SizeClass.TEAM or arch.size_class == Types.SizeClass.VEHICLE:
		return false
	return true


func _weight(d: ItemDef) -> float:
	var w := 1.0
	for t in PREF_TAGS:
		if d.tags.has(t):
			w += 4.0
	var blob := (d.id + " " + d.archetype_id).to_lower()
	for t in PREF_WORDS:
		if blob.contains(t):
			w += 2.4
			break
	return w


func _pick_weighted(pool: Array[ItemDef]) -> ItemDef:
	if pool.is_empty():
		return null
	var total := 0.0
	var weights: Array[float] = []
	for d in pool:
		var w := _weight(d)
		weights.append(w)
		total += w
	var roll := _rng.randf() * total
	var acc := 0.0
	for i in pool.size():
		acc += weights[i]
		if roll <= acc:
			return pool[i]
	return pool[pool.size() - 1]


func _pick_item(find_p: float, find_pool: Array[ItemDef]) -> ItemDef:
	if _rng.randf() < find_p and not find_pool.is_empty():
		return _pick_weighted(find_pool)
	if not _common.is_empty():
		return _pick_weighted(_common)
	if not find_pool.is_empty():
		return _pick_weighted(find_pool)
	return null


func _resolve_mouse() -> String:
	for id in ["mouse_live", "mouse_white", "mouse"]:
		if Registry.item(id):
			return id
	for raw in Registry.all_items():
		var d: ItemDef = raw as ItemDef
		if d == null:
			continue
		var idl := d.id.to_lower()
		if (idl.contains("mouse") or idl.contains("rat")) and d.has_facet(Types.Facet.ALIVE):
			return d.id
	return "mouse_live"


# ------------------------------------------------------------------ спавн

func _street_count() -> int:
	var n := 0
	for nid in Net.items:
		var b: ItemBody = Net.items[nid] as ItemBody
		if b != null and is_instance_valid(b) and bool(b.get_meta("street", false)):
			n += 1
	return n


func _scatter(want: int, far_players: bool) -> int:
	if not Net.is_host() or (_common.is_empty() and _finds.is_empty()):
		return 0
	var placed := 0
	var spots: Array[Vector3] = []
	var guard := 0
	var cap := mini(want, MAX_STREET - _street_count())
	while placed < cap and guard < 480:
		guard += 1
		var xz: Vector2 = _candidate(_rng)
		if far_players and not _far_from_players(xz):
			continue
		var g: Variant = _ground_at(xz)
		if typeof(g) != TYPE_VECTOR3:
			continue
		var pos: Vector3 = g as Vector3
		if not _ok_spot(pos, spots):
			continue
		var def: ItemDef = _pick_item(0.10, _finds)
		if def == null:
			break
		if _spawn_street(def, pos, false) == null:
			continue
		spots.append(pos)
		placed += 1
	return placed


func _spawn_street(def: ItemDef, pos: Vector3, impulse: bool) -> ItemBody:
	if def == null:
		return null
	var xf := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), pos + Vector3(0, 0.3, 0))
	var b: ItemBody = Net.spawn_item(def.id, xf) as ItemBody
	if b == null:
		return null
	b.set_meta("street", true)
	if impulse:
		b.sleeping = false
		b.apply_central_impulse(Vector3(_rng.randf_range(-0.5, 0.5), 2.4, _rng.randf_range(-0.5, 0.5)) * maxf(b.mass, 0.15))
	else:
		b.sleeping = true
	if not b.picked.is_connected(_on_street_picked):
		b.picked.connect(_on_street_picked)
	return b


func _on_street_picked(_b: ItemBody, _by: Node) -> void:
	if _hinted:
		return
	_hinted = true
	Game.notify.emit(tr("STREET_HINT"), 4.0)


func _ok_spot(pos: Vector3, spots: Array[Vector3]) -> bool:
	if _road_dist(pos.x, pos.z) < 3.0:
		return false
	if _near_lot(pos):
		return false
	for s in spots:
		if Vector2(pos.x - s.x, pos.z - s.z).length() < 1.35:
			return false
	return true


func _near_lot(pos: Vector3) -> bool:
	for raw in get_tree().get_nodes_in_group("lot_anchors"):
		if not (raw is LotAnchor):
			continue
		var a: LotAnchor = raw
		var c: Vector3 = a.cell_center()
		var hs: Vector3 = a.cell_size
		if absf(pos.x - c.x) <= hs.x * 0.5 + 2.5 and absf(pos.z - c.z) <= hs.z * 0.5 + 2.5:
			return true
	return false


func _road_dist(x: float, z: float) -> float:
	var best := 1.0e9
	for s in _ROADS:
		var d := _seg_dist(x, z, s.x, s.y, s.z, s.w)
		if d < best:
			best = d
	return best


func _seg_dist(px: float, pz: float, x1: float, z1: float, x2: float, z2: float) -> float:
	var dx := x2 - x1
	var dz := z2 - z1
	var len2 := dx * dx + dz * dz
	if len2 < 0.0001:
		return Vector2(px - x1, pz - z1).length()
	var t := clampf(((px - x1) * dx + (pz - z1) * dz) / len2, 0.0, 1.0)
	return Vector2(px - (x1 + dx * t), pz - (z1 + dz * t)).length()


func _ground_at(xz: Vector2) -> Variant:
	var space := get_world_3d().direct_space_state
	if space == null:
		return null
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(xz.x, 6.0, xz.y), Vector3(xz.x, -2.0, xz.y), Types.L_WORLD)
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return null
	var col: Node = hit.get("collider") as Node
	if col == null or col.name != "Ground":
		return null
	var pos: Vector3 = hit["position"] as Vector3
	if pos.y > 0.45 or pos.y < -0.25:
		return null
	return pos


func _far_from_players(xz: Vector2) -> bool:
	for ppos in _player_positions():
		if Vector2(xz.x - ppos.x, xz.y - ppos.z).length() < 25.0:
			return false
	return true


func _player_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var w: World = Game.world as World
	if w and w.players_root:
		for c in w.players_root.get_children():
			if c is Node3D and is_instance_valid(c):
				out.append((c as Node3D).global_position)
	for raw in Net.players.values():
		var p: Node3D = raw as Node3D
		if p != null and is_instance_valid(p):
			out.append(p.global_position)
	return out


func _candidate(rng: RandomNumberGenerator) -> Vector2:
	var roll := rng.randf()
	if roll < 0.18:
		var ang := rng.randf() * TAU
		var r := rng.randf_range(11.0, 18.5)
		return Vector2(cos(ang) * r, -8.0 + sin(ang) * r)
	if roll < 0.42:
		var s: Vector4 = _ROADS[rng.randi() % _ROADS.size()]
		var t := rng.randf()
		var mid := Vector2(lerpf(s.x, s.z, t), lerpf(s.y, s.w, t))
		var dir := Vector2(s.z - s.x, s.w - s.y)
		var nrm := Vector2(-dir.y, dir.x)
		if nrm.length() < 0.01:
			nrm = Vector2.RIGHT
		nrm = nrm.normalized() * rng.randf_range(5.8, 8.4) * (1.0 if rng.randf() < 0.5 else -1.0)
		return mid + nrm
	if roll < 0.68:
		var p: Vector2 = _PROP_XZ[rng.randi() % _PROP_XZ.size()]
		return p + Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
	var hubs: Array[Vector2] = [
		Vector2(0, -142), Vector2(-16, -142), Vector2(16, -141),
		Vector2(-14, 182), Vector2(0, 180), Vector2(16, 182), Vector2(8, 176),
		Vector2(-120, 8), Vector2(-108, 6), Vector2(-132, 10), Vector2(-118, -22),
		Vector2(98, 56), Vector2(118, 54), Vector2(124, 64), Vector2(102, 50),
		Vector2(128, -108), Vector2(96, -108), Vector2(-128, -108),
	]
	var h: Vector2 = hubs[rng.randi() % hubs.size()]
	return h + Vector2(rng.randf_range(-2.2, 2.2), rng.randf_range(-2.2, 2.2))


# ------------------------------------------------------------------ мусорки

func _build_dumpsters() -> void:
	var spots: Array[Vector3] = [
		Vector3(-18.0, 0, -142.0), # за ангаром
		Vector3(128.0, 0, -108.0), # двор склада
		Vector3(-128.0, 0, -142.0), # за гаражами
		Vector3(-138.0, 0, 6.0), # за скупщиками
		Vector3(124.0, 0, 94.0), # тыл казино
		Vector3(-134.0, 0, 90.0), # тыл участка
		Vector3(-22.0, 0, 178.0), # причал
		Vector3(10.5, 0, -36.0), # въезд в трейлер-парк
		Vector3(98.0, 0, 52.0), # парковка казино
		Vector3(138.0, 0, 12.0), # авторынок
	]
	var yaws: Array[float] = [8.0, 90.0, -6.0, 95.0, 180.0, 175.0, 0.0, 12.0, 8.0, -18.0]
	for i in spots.size():
		var d := _make_dumpster(i, spots[i], yaws[i])
		_dumpsters.append(d)


func _make_dumpster(i: int, pos: Vector3, yaw_deg: float) -> Dumpster:
	var d := Dumpster.new()
	d.name = "Dumpster%d" % i
	d.system = self
	d.charges = CHARGES
	d.collision_layer = Types.L_WORLD
	d.collision_mask = 0
	d.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), pos)
	var rust := CityDress.tex("tex_rust_teal")
	var green := i % 2 == 0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.48, 0.28) if green else Color(0.42, 0.38, 0.28)
	mat.roughness = 0.95
	if rust:
		mat.albedo_texture = rust
		mat.uv1_triplanar = true
		mat.uv1_world_triplanar = true
		mat.uv1_scale = Vector3.ONE / 1.6
	var body := MeshInstance3D.new()
	body.mesh = LowPoly.chamfer_box(BODY, 0.05)
	body.material_override = mat
	body.position = Vector3(0, BODY.y * 0.5, 0)
	d.add_child(body)
	var lid_mat := mat.duplicate() as StandardMaterial3D
	lid_mat.albedo_color = mat.albedo_color.darkened(0.28)
	var lid := MeshInstance3D.new()
	lid.mesh = LowPoly.chamfer_box(Vector3(BODY.x + 0.04, 0.08, BODY.z + 0.06), 0.02)
	lid.material_override = lid_mat
	lid.position = Vector3(0, BODY.y + 0.04, -0.06)
	lid.rotation.x = deg_to_rad(-12)
	d.add_child(lid)
	d.lid = lid
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(BODY.x, BODY.y + 0.1, BODY.z)
	cs.shape = bs
	cs.position = Vector3(0, (BODY.y + 0.1) * 0.5, 0)
	d.add_child(cs)
	add_child(d)
	return d


func rummage(d: Dumpster, _player: Node) -> void:
	if not Net.is_host() or d == null or not is_instance_valid(d) or d.busy:
		return
	if d.charges <= 0:
		AudioBus.play_at("locked_rattle", d.global_position)
		return
	d.busy = true
	d.charges -= 1
	AudioBus.play_at("lid_open", d.global_position)
	_flip_lid(d)
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = RUMMAGE_SEC
	d.add_child(t)
	t.start()
	await t.timeout
	if is_instance_valid(t):
		t.queue_free()
	if not is_instance_valid(d):
		return
	_pop_loot(d)
	d.busy = false


func _flip_lid(d: Dumpster) -> void:
	if d.lid == null:
		return
	var tw := d.create_tween()
	tw.tween_property(d.lid, "rotation:x", deg_to_rad(-62), 0.22)
	tw.tween_property(d.lid, "rotation:x", deg_to_rad(-12), 0.5)


func _pop_loot(d: Dumpster) -> void:
	var pos: Vector3 = d.global_position + Vector3(0, BODY.y + 0.15, 0)
	if _rng.randf() < 0.10 and Registry.item(_mouse_id):
		var rat: ItemBody = _spawn_street(Registry.item(_mouse_id), pos, true)
		if rat:
			rat.set_meta("street", true)
		AudioBus.play_at("mouse_squeak", pos)
		Game.notify.emit(tr("STREET_RAT"), 3.0)
		return
	var find := _rng.randf() < 0.20
	var def: ItemDef = _pick_item(1.0 if find else 0.0, _dump_finds)
	if def == null:
		return
	_spawn_street(def, pos, true)
	if find:
		Game.notify.emit(tr("STREET_FIND_%d" % _rng.randi_range(0, 5)), 3.0)


func _reset_charges() -> void:
	for d in _dumpsters:
		if is_instance_valid(d):
			d.charges = CHARGES
			d.busy = false
