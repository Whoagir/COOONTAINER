class_name TrailerHub
extends Node3D
## Хаб (§12): слот мира, трейлер обрастает хламом, инструменты «лучше появились», кровати = респавн.
## Автосейв хоста по таймеру и при смене режима. Не сейвим ворох середины вывоза (§15).

const AUTOSAVE_SEC := 45.0

var _t := 0.0
var _tool_tiers := {
	# порог заработка → инструмент появляется в трейлере
	150: "tool_bucket",
	400: "tool_tape",
	800: "tool_lockpick",
	1500: "tool_lighter",
	3000: "tool_plank",
	6000: "tool_broom",
}


func system_name() -> String:
	return "TrailerHub"


func _ready() -> void:
	Game.world_mode_changed.connect(_on_mode)
	Economy.pot_changed.connect(_on_pot)
	Economy.pot_changed.connect(func(_v, _d, _r): _board_dirty = true)
	call_deferred("_make_board")


## Записка Петровича на почтовом ящике: сколько до дома и что откроется следующим (§12 «знаки в мире»,
## миникарты и меню прогресса нет — всё написано на бумажке).
var _board: Label3D
var _board_dirty := true
var _board_t := 0.0


func _make_board() -> void:
	if Game.world == null:
		return
	# рядом с котлом на стене трейлера (котёл стоит у южной стены, бумажка смотрит на юг, к двору)
	var slot: Node3D = Game.world.find_marker(Types.District.TRAILER_PARK, "PotSlot")
	var anchor: Node3D = slot if slot else Game.world.find_marker(Types.District.TRAILER_PARK, "Mailbox")
	if anchor == null:
		return
	var paper := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.9, 0.62)
	paper.mesh = qm
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.93, 0.88, 0.72)
	pm.roughness = 1.0
	paper.material_override = pm
	Game.world.add_child(paper)
	paper.global_position = anchor.global_position + Vector3(1.05, 0.45, 0.12)
	paper.rotation = Vector3(0, 0, 0.03)
	_board = Label3D.new()
	_board.font_size = 30
	_board.pixel_size = 0.0016 # 0.9 м бумажки ≈ 560 px текста
	_board.width = 520
	_board.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_board.line_spacing = -2.0
	_board.modulate = Color(0.16, 0.1, 0.06)
	_board.outline_size = 0
	_board.double_sided = false
	_board.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_board.position = Vector3(-0.41, 0, 0.005) # LEFT: origin Label3D — левый край текста
	paper.add_child(_board)
	_refresh_board()


func _refresh_board() -> void:
	if _board == null or not is_instance_valid(_board):
		return
	_board_dirty = false
	var lines: Array[String] = []
	lines.append(tr("BOARD_TITLE"))
	if Game.save.get("house_bought", false):
		lines.append(tr("BOARD_HOUSE_DONE"))
	else:
		lines.append(tr("BOARD_HOUSE") % [Economy.pot, Game.HOUSE_PRICE])
	var g := Game.next_gate()
	if not g.is_empty():
		var dname := tr("DISTRICT_%s" % Types.District.keys()[int(g["district"])])
		lines.append(tr("BOARD_NEXT") % [dname.capitalize(), int(g["need_earned"]), int(g["need_lots"])])
	else:
		lines.append(tr("BOARD_ALL_OPEN"))
	var lots := (Game.save.get("lots_done", []) as Array).size()
	lines.append(tr("BOARD_LOTS") % lots)
	_board.text = "\n".join(lines)


func _process(delta: float) -> void:
	_board_t += delta
	if (_board_dirty and _board_t > 0.5) or _board_t > 4.0:
		_board_t = 0.0
		_refresh_board()
	if not Net.is_host():
		return
	_t += delta
	if _t >= AUTOSAVE_SEC:
		_t = 0.0
		_autosave()


func _autosave() -> void:
	if Game.world_mode == Types.WorldMode.CLEAR_OUT or Game.world_mode == Types.WorldMode.AUCTION:
		return
	if Game.world:
		Game.save["trailer_junk"] = Game.world.collect_trailer_junk()
		var veh: Node = Game.world.system("Vehicles")
		if veh and veh.has_method("collect_save"):
			Game.save["vehicles"] = veh.collect_save()
	Game.write_slot()


func _on_mode(m: int, prev: int) -> void:
	if not Net.is_host():
		return
	if prev == Types.WorldMode.CLEAR_OUT or prev == Types.WorldMode.VENDOR or m == Types.WorldMode.TRAILER_HUB:
		_autosave()


func _on_pot(_v: int, _delta: int, _reason: String) -> void:
	if not Net.is_host():
		return
	var earned := Game.stat("earned_total")
	var tools: Array = Game.save["tools"]
	for threshold in _tool_tiers:
		var id: String = _tool_tiers[threshold]
		if earned >= threshold and not tools.has(id) and Registry.item(id):
			tools.append(id)
			var shelf: Node3D = Game.world.find_marker(Types.District.TRAILER_PARK, "ToolShelf") if Game.world else null
			var pos: Vector3 = shelf.global_position if shelf else Vector3(0, 1, 0)
			Net.spawn_item(id, Transform3D(Basis(), pos + Vector3(randf_range(-0.5, 0.5), 0.3, randf_range(-0.2, 0.2))))
			Game.notify.emit(tr("NOTIFY_NEW_TOOL") % Registry.item(id).display_name(), 4.0)
