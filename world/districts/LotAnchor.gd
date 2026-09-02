class_name LotAnchor
extends Node3D
## Место лота на площадке (§8–10): ячейка, дверь, толпа, аукционист, смотритель.
## Дети (по имени): Cell (пол ячейки, вход по +Z), Door (AnimatableBody3D, опускается),
## Hunter0..7, Auctioneer, Caretaker, PlayerStand, PreviewSpot, Lamp (опц.).

@export var lot_kind: int = Types.LotKind.BAG
@export var cell_size: Vector3 = Vector3(3, 2.5, 3)
@export var has_door: bool = true
@export var dark: bool = false

var current_lot_id: String = ""
var door_closed := false
var _door: Node3D
var _door_open_y := 0.0
var _lamp: Light3D


func _ready() -> void:
	add_to_group("lot_anchors")
	_door = get_node_or_null("Door")
	if _door:
		_door_open_y = _door.position.y
	_lamp = get_node_or_null("Lamp") as Light3D
	if _lamp:
		_lamp.visible = not dark


func cell() -> Node3D:
	var c := get_node_or_null("Cell") as Node3D
	return c if c else self


func marker(name: String) -> Node3D:
	var n := get_node_or_null(name) as Node3D
	return n if n else self


func hunter_spots() -> Array:
	var out: Array = []
	for i in 8:
		var n := get_node_or_null("Hunter%d" % i)
		if n:
			out.append(n)
	return out


func cell_center() -> Vector3:
	return cell().global_transform * Vector3(0, cell_size.y * 0.5, 0)


func is_inside(pos: Vector3) -> bool:
	var local := cell().global_transform.affine_inverse() * pos
	return absf(local.x) <= cell_size.x * 0.5 + 0.2 and absf(local.z) <= cell_size.z * 0.5 + 0.2 and local.y >= -0.5 and local.y <= cell_size.y + 0.5


## Дверь вниз (овертайм §10). Можно остаться внутри.
func close_door(animated := true) -> void:
	if _door == null or door_closed:
		return
	door_closed = true
	var target := _door_open_y - cell_size.y
	if animated:
		var tw := create_tween()
		tw.tween_property(_door, "position:y", target, 1.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		AudioBus.play_at("door_slam", _door.global_position, 4.0, 0.05)
	else:
		_door.position.y = target
	if Net.is_host():
		Net.broadcast_event("lot_door", {"path": str(get_path()), "closed": true})


func open_door(animated := true) -> void:
	if _door == null or not door_closed:
		return
	door_closed = false
	if animated:
		var tw := create_tween()
		tw.tween_property(_door, "position:y", _door_open_y, 1.2)
		AudioBus.play_at("door_roll", _door.global_position, 0.0)
	else:
		_door.position.y = _door_open_y
	if Net.is_host():
		Net.broadcast_event("lot_door", {"path": str(get_path()), "closed": false})


func set_lamp(on: bool) -> void:
	if _lamp:
		_lamp.visible = on
