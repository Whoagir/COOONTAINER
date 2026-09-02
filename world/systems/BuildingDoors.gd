class_name BuildingDoors
extends Node3D
## Двери соседских трейлеров/сараев (маркеры `EnterDoor` в группе enterable_building).
## E → fade → карманный интерьер вдалеке; выход той же дверью. Без CSG-дыр в пропах.

const POCKET_ORIGIN := Vector3(820, 0, 820)
const POCKET_STEP := 36.0
const ROOM := Vector3(7.2, 2.7, 5.4)

var _entries: Array = [] # {id, door:Interactable, exit:Interactable, outside:Vector3, inside:Vector3, kind}
var _busy := false
var _mats: Dictionary = {}


func system_name() -> String:
	return "BuildingDoors"


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_hook_all()


func _hook_all() -> void:
	var id := 0
	for b in get_tree().get_nodes_in_group("enterable_building"):
		if not (b is Node3D):
			continue
		var marker: Node3D = b.get_node_or_null("EnterDoor") as Node3D
		if marker == null:
			continue
		var kind := str(marker.get_meta("building_kind", "house"))
		_make_entry(id, marker, kind)
		id += 1
	if OS.is_debug_build():
		print("[BuildingDoors] entries=%d" % _entries.size())


func _make_entry(id: int, marker: Node3D, kind: String) -> void:
	var outside := marker.global_position
	var yaw := marker.global_transform.basis.get_euler().y
	# чуть снаружи — marker уже снаружи корпуса
	var door := Vendors.Interactable.new(Vector3(1.1, 2.1, 0.55))
	door.name = "BDoor_%d" % id
	add_child(door)
	door.global_position = outside
	door.rotation.y = yaw
	var pocket := _build_pocket(id, kind)
	var inside_pos: Vector3 = pocket["spawn"]
	var exit_pos: Vector3 = pocket["exit"]
	var exit := Vendors.Interactable.new(Vector3(1.1, 2.1, 0.55))
	exit.name = "BExit_%d" % id
	add_child(exit)
	exit.global_position = exit_pos
	var entry := {
		"id": id,
		"door": door,
		"exit": exit,
		"outside": outside + Vector3(0, 0, 0),
		"outside_look": outside + marker.global_transform.basis.z * 1.2,
		"inside": inside_pos,
		"kind": kind,
	}
	# снаружи: чуть отодвинуть точку выхода от двери
	var out_back := outside + marker.global_transform.basis.z * 1.4
	out_back.y = outside.y
	entry["outside"] = out_back
	door.on_interact = _enter.bind(entry)
	door.on_hint = _hint_enter
	exit.on_interact = _leave.bind(entry)
	exit.on_hint = _hint_exit
	_entries.append(entry)


func _hint_enter(_p: Player) -> String:
	return tr("DOOR_ENTER")


func _hint_exit(_p: Player) -> String:
	return tr("DOOR_EXIT")


## Как Vendors: call(player) + bind(entry) → (player, entry).
func _enter(player: Player, entry: Dictionary) -> void:
	if not Net.is_host() or player == null or _busy:
		return
	if player.dead or player.cuffed or player.in_custody or player.in_vehicle:
		return
	_busy = true
	await _teleport(player, entry["inside"] as Vector3, true, int(entry["id"]))
	_busy = false


func _leave(player: Player, entry: Dictionary) -> void:
	if not Net.is_host() or player == null or _busy:
		return
	if player.dead or player.cuffed or player.in_custody:
		return
	_busy = true
	await _teleport(player, entry["outside"] as Vector3, false, int(entry["id"]))
	_busy = false


func _teleport(p: Player, to: Vector3, going_in: bool, id: int) -> void:
	if p.hands:
		p.hands.host_release_all()
	p.cinematic = true
	Net.broadcast_event("building_door", {"peer": p.peer_id, "id": id, "in": going_in, "pos": to})
	var cine: Cinematic = Game.world.system("Cinematic") as Cinematic if Game.world else null
	if cine:
		await cine.fade_to_black(0.35)
	else:
		await get_tree().create_timer(0.25).timeout
	p.global_position = to
	p.velocity = Vector3.ZERO
	if cine:
		await cine.fade_from_black(0.4)
	p.cinematic = false
	p.say(tr("DOOR_ENTERED") if going_in else tr("DOOR_LEFT"), 1.6)


func on_net_event(kind: String, data: Dictionary) -> void:
	if kind != "building_door":
		return
	var peer := int(data.get("peer", 0))
	if peer == Net.my_id():
		return
	var p: Player = Net.players.get(peer) as Player if Net.players.has(peer) else null
	if p == null:
		return
	p.global_position = data.get("pos", p.global_position) as Vector3
	p.cinematic = false


func _mat(c: Color, rough := 1.0) -> StandardMaterial3D:
	var key := "%s_%.2f" % [c.to_html(false), rough]
	if _mats.has(key):
		return _mats[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	_mats[key] = m
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, collide := false) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.position = pos
		parent.add_child(cs)


func _build_pocket(id: int, kind: String) -> Dictionary:
	var origin := POCKET_ORIGIN + Vector3(float(id % 6) * POCKET_STEP, 0, float(id / 6) * POCKET_STEP)
	var root := StaticBody3D.new()
	root.name = "Pocket_%d" % id
	root.collision_layer = Types.L_WORLD
	root.collision_mask = 0
	root.position = origin
	add_child(root)
	var w := ROOM.x
	var h := ROOM.y
	var d := ROOM.z
	var wall := _mat(Color(0.55, 0.42, 0.32) if kind == "trailer" else Color(0.48, 0.40, 0.34))
	var floor_m := _mat(Color(0.35, 0.28, 0.22))
	var ceil_m := _mat(Color(0.72, 0.68, 0.62))
	var wood := _mat(Color(0.42, 0.28, 0.16))
	_box(root, Vector3(w, 0.12, d), Vector3(0, 0.06, 0), floor_m, true)
	_box(root, Vector3(w, 0.1, d), Vector3(0, h, 0), ceil_m, true)
	# стены: проём на -Z
	_box(root, Vector3(w, h, 0.12), Vector3(0, h * 0.5, d * 0.5), wall, true)
	_box(root, Vector3(0.12, h, d), Vector3(-w * 0.5, h * 0.5, 0), wall, true)
	_box(root, Vector3(0.12, h, d), Vector3(w * 0.5, h * 0.5, 0), wall, true)
	_box(root, Vector3(w * 0.32, h, 0.12), Vector3(-w * 0.34, h * 0.5, -d * 0.5), wall, true)
	_box(root, Vector3(w * 0.32, h, 0.12), Vector3(w * 0.34, h * 0.5, -d * 0.5), wall, true)
	_box(root, Vector3(w * 0.36, h * 0.28, 0.12), Vector3(0, h * 0.86, -d * 0.5), wall, true)
	# дверь в проёме (декор)
	_box(root, Vector3(0.85, 1.9, 0.06), Vector3(0, 0.95, -d * 0.5 + 0.02), wood, false)
	# мебель — мало мешей
	_box(root, Vector3(2.0, 0.55, 0.85), Vector3(-1.6, 0.4, 1.2), _mat(Color(0.25, 0.35, 0.55)), true)
	_box(root, Vector3(1.1, 0.45, 0.7), Vector3(1.5, 0.35, 0.3), wood, true)
	_box(root, Vector3(1.4, 0.35, 1.8), Vector3(0.2, 0.3, 1.4), _mat(Color(0.55, 0.22, 0.22)), true)
	if kind == "trailer":
		_box(root, Vector3(1.8, 0.25, 0.9), Vector3(-1.4, 0.45, -1.2), _mat(Color(0.75, 0.72, 0.65)), true)
	else:
		_box(root, Vector3(0.55, 1.1, 0.45), Vector3(2.2, 0.7, -1.3), wood, true)
	# лампа без теней
	var lamp := OmniLight3D.new()
	lamp.light_energy = 1.1
	lamp.omni_range = 8.0
	lamp.shadow_enabled = false
	lamp.light_color = Color(1.0, 0.92, 0.75)
	lamp.position = Vector3(0, h - 0.35, 0)
	root.add_child(lamp)
	var spawn := origin + Vector3(0, 0.15, -d * 0.15)
	var exit := origin + Vector3(0, 1.0, -d * 0.5 + 0.35)
	return {"spawn": spawn, "exit": exit}
