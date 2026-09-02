class_name Ladders
extends Node3D
## Лестницы: E — залезть / слезть, W/S — вверх/вниз. Высокие полки без них не достать.
## Постоянные — хаб и районы; на время ClearOut — ещё одна в ячейке лота.

const CLIMB_SPEED := 2.35
const RUNG_STEP := 0.32
const WOOD := Color(0.48, 0.32, 0.18)
const WOOD_DARK := Color(0.32, 0.22, 0.12)


class LadderProp extends StaticBody3D:
	var sys: Ladders
	var height := 2.6
	var ephemeral := false
	var lot_key := ""

	func interact(player: Node) -> void:
		if sys:
			sys.toggle_mount(self, player as Player)

	func interact_hint(player: Node) -> String:
		if player is Player and (player as Player).on_ladder == self:
			return tr("LADDER_HINT_OFF")
		return tr("LADDER_HINT_ON")

	func face_dir() -> Vector3:
		return global_basis.z

	func y_min() -> float:
		return global_position.y + 0.12

	func y_max() -> float:
		return global_position.y + height - 0.2

	## Точка хвата на высоте world_y (игрок стоит с лицевой стороны +Z).
	func rail_world(world_y: float) -> Vector3:
		var ly := clampf(world_y - global_position.y, 0.12, height - 0.15)
		return to_global(Vector3(0.0, ly, 0.42))

	func top_stand() -> Vector3:
		return to_global(Vector3(0.0, height - 0.05, 0.55))


var ladders: Dictionary = {} # id → LadderProp
var _lot_ladder: LadderProp = null
var _mat: StandardMaterial3D
var _mat_dark: StandardMaterial3D


func system_name() -> String:
	return "Ladders"


func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = WOOD
	_mat.roughness = 0.92
	_mat_dark = _mat.duplicate() as StandardMaterial3D
	_mat_dark.albedo_color = WOOD_DARK
	await get_tree().process_frame
	await get_tree().process_frame
	if Game.world == null:
		return
	_build_world()
	if OS.is_debug_build():
		print("[Ladders] count=%d" % ladders.size())


func send_full_state_to(peer: int) -> void:
	if _lot_ladder and is_instance_valid(_lot_ladder):
		Net.send_event(peer, "ladder_lot", {
			"act": "spawn", "anchor": _lot_ladder.lot_key,
			"x": _lot_ladder.global_position.x,
			"y": _lot_ladder.global_position.y,
			"z": _lot_ladder.global_position.z,
			"yaw": _lot_ladder.global_rotation.y,
			"h": _lot_ladder.height,
		})


func on_net_event(kind: String, data: Dictionary) -> void:
	if kind == "ladder_lot":
		handle_net_lot(data)
		return
	if kind != "ladder":
		return
	# хост уже применил в toggle_mount; событие нужно клиентам
	if Net.is_host():
		return
	var peer := int(data.get("peer", 0))
	var p: Player = Game.world.player_of(peer) if Game.world else null
	if p == null:
		return
	match str(data.get("act", "")):
		"mount":
			var path := str(data.get("path", ""))
			var n: Node = get_tree().root.get_node_or_null(path) if path != "" else null
			if n is LadderProp:
				p.mount_ladder(n as LadderProp)
		"dismount":
			var push := Vector3(
				float(data.get("px", 0.0)),
				float(data.get("py", 0.0)),
				float(data.get("pz", 0.0))
			)
			p.dismount_ladder(push)


func toggle_mount(ladder: LadderProp, player: Player) -> void:
	if not Net.is_host() or player == null or ladder == null:
		return
	if player.dead or player.cuffed or player.in_custody or player.in_vehicle or player.cinematic:
		return
	if player.on_ladder == ladder:
		_host_dismount(player, ladder.face_dir() * 1.15)
		return
	if player.on_ladder != null:
		_host_dismount(player, Vector3.ZERO)
	_host_mount(player, ladder)


func _host_mount(player: Player, ladder: LadderProp) -> void:
	player.mount_ladder(ladder)
	Net.broadcast_event("ladder", {
		"act": "mount", "peer": player.peer_id, "path": str(ladder.get_path()),
	})
	AudioBus.play_at("thud", ladder.global_position, -10.0, 0.1)


func _host_dismount(player: Player, push: Vector3) -> void:
	player.dismount_ladder(push)
	Net.broadcast_event("ladder", {
		"act": "dismount", "peer": player.peer_id,
		"px": push.x, "py": push.y, "pz": push.z,
	})


## Хост: временная лестница в ячейке лота (у задней стены).
func spawn_for_lot(anchor: LotAnchor) -> void:
	if not Net.is_host() or anchor == null:
		return
	clear_lot_ladder()
	var cell := anchor.cell()
	var h := clampf(anchor.cell_size.y - 0.2, 1.8, 2.9)
	var local := Vector3(-anchor.cell_size.x * 0.36, 0.0, -anchor.cell_size.z * 0.42)
	var pos := cell.to_global(local)
	var yaw := cell.global_rotation.y
	var lad := _make("lot_clearout", pos, yaw, h, true)
	lad.lot_key = str(anchor.get_path())
	_lot_ladder = lad
	Net.broadcast_event("ladder_lot", {
		"act": "spawn", "anchor": str(anchor.get_path()),
		"x": pos.x, "y": pos.y, "z": pos.z, "yaw": yaw, "h": h,
	})


func clear_lot_ladder() -> void:
	if _lot_ladder and is_instance_valid(_lot_ladder):
		_kick_climbers(_lot_ladder)
		ladders.erase(_lot_ladder.name)
		_lot_ladder.queue_free()
	_lot_ladder = null
	if Net.is_host():
		Net.broadcast_event("ladder_lot", {"act": "clear"})


func _kick_climbers(lad: LadderProp) -> void:
	if Game.world == null:
		return
	for peer in Net.players:
		var p: Player = Net.players[peer]
		if p and is_instance_valid(p) and p.on_ladder == lad:
			if Net.is_host():
				_host_dismount(p, lad.face_dir() * 1.2)
			else:
				p.dismount_ladder(lad.face_dir() * 1.2)


func handle_net_lot(data: Dictionary) -> void:
	if Net.is_host():
		return
	match str(data.get("act", "")):
		"spawn":
			clear_lot_ladder()
			var pos := Vector3(float(data.get("x", 0)), float(data.get("y", 0)), float(data.get("z", 0)))
			var lad := _make("lot_clearout", pos, float(data.get("yaw", 0)), float(data.get("h", 2.4)), true)
			lad.lot_key = str(data.get("anchor", ""))
			_lot_ladder = lad
		"clear":
			clear_lot_ladder()


func _build_world() -> void:
	var w := Game.world
	# трейлер: полка на −Z стене
	var tr: Node3D = w.find_marker(Types.District.TRAILER_PARK, "Trailer")
	if tr:
		var sh := tr.to_global(Vector3(0.15, 0.0, -1.35))
		_make("hub_shelf", sh, tr.global_rotation.y, 2.15, false)
	# у полки инструментов снаружи
	var shelf: Node3D = w.find_marker(Types.District.TRAILER_PARK, "ToolShelf")
	if shelf:
		_make("hub_tools", shelf.global_position + Vector3(-0.85, -0.9, 0.35), deg_to_rad(90.0), 2.4, false)
	# районы с высокими лотами — по лестнице у Lot0
	for d in [Types.District.HANGAR, Types.District.STORAGE, Types.District.GARAGES, Types.District.PORT]:
		_place_district(d)


func _place_district(d: int) -> void:
	var w := Game.world
	if w == null or w.city == null:
		return
	var root: Node3D = w.district_root(d)
	if root == null:
		return
	var anchors: Array = w.city.lot_anchors(d) if w.city.has_method("lot_anchors") else []
	if anchors.is_empty():
		for n in root.find_children("Lot*", "Node3D", true, false):
			if n is LotAnchor:
				anchors.append(n)
	var i := 0
	for a in anchors:
		if not (a is LotAnchor):
			continue
		var la := a as LotAnchor
		# снаружи у входа (+Z), не блокируя дверь
		var cell: Node3D = la.cell() as Node3D
		if cell == null:
			continue
		var pos := cell.to_global(Vector3(la.cell_size.x * 0.42, 0.0, la.cell_size.z * 0.55))
		var yaw: float = cell.global_rotation.y # лицом наружу (+Z ячейки)
		_make("dist_%d_%d" % [d, i], pos, yaw, clampf(la.cell_size.y, 2.0, 2.8), false)
		i += 1
		if i >= 3: # не лес лестниц
			break


func _make(id: String, pos: Vector3, yaw: float, height: float, ephemeral: bool) -> LadderProp:
	if ladders.has(id) and is_instance_valid(ladders[id]):
		ladders[id].queue_free()
	var lad := LadderProp.new()
	lad.name = id
	lad.sys = self
	lad.height = height
	lad.ephemeral = ephemeral
	lad.collision_layer = Types.L_WORLD
	lad.collision_mask = 0
	lad.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	_build_mesh(lad)
	add_child(lad)
	ladders[id] = lad
	return lad


func _build_mesh(lad: LadderProp) -> void:
	var h := lad.height
	var rail_x := 0.28
	# стойки
	for sx in [-rail_x, rail_x]:
		var pole := MeshInstance3D.new()
		pole.mesh = LowPoly.chamfer_box(Vector3(0.06, h, 0.06), 0.008)
		pole.material_override = _mat_dark
		pole.position = Vector3(sx, h * 0.5, 0.0)
		lad.add_child(pole)
	# перекладины
	var n := maxi(3, int(h / RUNG_STEP))
	for i in n:
		var t := (float(i) + 0.5) / float(n)
		var rung := MeshInstance3D.new()
		rung.mesh = LowPoly.chamfer_box(Vector3(rail_x * 2.0 + 0.04, 0.045, 0.055), 0.006)
		rung.material_override = _mat
		rung.position = Vector3(0.0, t * h, 0.02)
		lad.add_child(rung)
	# коллизия — тонкий объём (лазать через interact, не упираться лбом)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.7, h, 0.22)
	col.shape = box
	col.position = Vector3(0.0, h * 0.5, 0.0)
	lad.add_child(col)
	# зона взаимодействия чуть шире — луч взгляда ловит
	var hit := CollisionShape3D.new()
	var hit_box := BoxShape3D.new()
	hit_box.size = Vector3(0.85, h, 0.55)
	hit.shape = hit_box
	hit.position = Vector3(0.0, h * 0.5, 0.28)
	lad.add_child(hit)
