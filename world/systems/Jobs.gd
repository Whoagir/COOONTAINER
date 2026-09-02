class_name Jobs
extends Node3D
## Доски объявлений (§13): три вакансии, одна активная работа на пати. Хост считает;
## клиентам — jobs_menu / jobs_state. После штрафа/нуля котла — suggest_work → доска у трейлера.

const OFFER_COUNT := 3
const REFRESH_SEC := 360.0
const SUGGEST_SEC := 90.0

const JOB_PAY := {
	"janitor": 0,
	"trash": 45,
	"delivery": 60,
	"flyers": 50,
	"car_wash": 40,
	"night_watch": 35,
}

const FLYER_DISTRICTS := [
	Types.District.HANGAR,
	Types.District.GARAGES,
	Types.District.PORT,
	Types.District.CASINO,
]

## Доска: E — меню вакансий (хост шлёт jobs_menu одному пиру).
class JobBoard extends StaticBody3D:
	var jobs: Jobs = null
	var board_id := 0
	var bin: Area3D = null

	func _init(j: Jobs, id: int) -> void:
		jobs = j
		board_id = id
		name = "JobBoard_%d" % id
		collision_layer = Types.L_TRIGGER
		collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.4, 1.6, 0.35)
		cs.shape = bs
		cs.position = Vector3(0, 1.1, 0)
		add_child(cs)
		_build_visual()

	func _build_visual() -> void:
		var wood := StandardMaterial3D.new()
		wood.albedo_color = Color(0.62, 0.44, 0.26)
		wood.roughness = 0.9
		var planks := CityDress.tex("tex_planks")
		if planks:
			wood.albedo_texture = planks
			wood.uv1_scale = Vector3(1.5, 1.5, 1.5)
		var cork := StandardMaterial3D.new()
		cork.albedo_color = Color(0.55, 0.38, 0.22)
		cork.roughness = 1.0
		var pin := StandardMaterial3D.new()
		pin.albedo_color = Color(0.9, 0.15, 0.12)
		for side in [-0.6, 0.6]:
			var post := MeshInstance3D.new()
			post.mesh = LowPoly.chamfer_box(Vector3(0.12, 1.9, 0.12), 0.02)
			post.material_override = wood
			post.position = Vector3(side, 0.95, 0)
			add_child(post)
		var frame := MeshInstance3D.new()
		frame.mesh = LowPoly.chamfer_box(Vector3(1.4, 1.0, 0.08), 0.03)
		frame.material_override = wood
		frame.position = Vector3(0, 1.3, 0)
		add_child(frame)
		var board := MeshInstance3D.new()
		board.mesh = BoxMesh.new()
		(board.mesh as BoxMesh).size = Vector3(1.24, 0.84, 0.03)
		board.material_override = cork
		board.position = Vector3(0, 1.3, 0.035)
		add_child(board)
		# козырёк — читается как доска объявлений даже издалека
		var roof := MeshInstance3D.new()
		roof.mesh = LowPoly.chamfer_box(Vector3(1.6, 0.06, 0.45), 0.02)
		roof.material_override = wood
		roof.position = Vector3(0, 1.92, 0.12)
		roof.rotation_degrees = Vector3(12, 0, 0)
		add_child(roof)
		var paper_cols := [Color(0.97, 0.95, 0.86), Color(1.0, 0.92, 0.45), Color(0.98, 0.72, 0.8), Color(0.72, 0.9, 1.0)]
		var rng := RandomNumberGenerator.new()
		rng.seed = 7011 + board_id
		for i in 4:
			var note := MeshInstance3D.new()
			var qm := QuadMesh.new()
			qm.size = Vector2(0.24, 0.3) if i < 3 else Vector2(0.3, 0.2)
			note.mesh = qm
			var pm := StandardMaterial3D.new()
			pm.albedo_color = paper_cols[i]
			pm.roughness = 1.0
			note.material_override = pm
			var nx := -0.4 + i * 0.27 if i < 3 else 0.32
			var ny := 1.36 if i < 3 else 1.0
			note.position = Vector3(nx, ny, 0.055)
			note.rotation_degrees = Vector3(0, 0, rng.randf_range(-9, 9))
			add_child(note)
			var tack := MeshInstance3D.new()
			tack.mesh = LowPoly.sphere(0.02, 6, 3)
			tack.material_override = pin
			tack.position = note.position + Vector3(0, qm.size.y * 0.45, 0.01)
			add_child(tack)
		var hdr_plank := MeshInstance3D.new()
		hdr_plank.mesh = LowPoly.chamfer_box(Vector3(1.1, 0.2, 0.05), 0.02)
		hdr_plank.material_override = wood
		hdr_plank.position = Vector3(0, 1.66, 0.06)
		add_child(hdr_plank)
		var hdr := Label3D.new()
		hdr.text = tr("JOBS_TITLE")
		hdr.font_size = 64
		hdr.outline_size = 12
		hdr.pixel_size = 0.0022
		hdr.modulate = Color(1.0, 0.86, 0.3)
		hdr.outline_modulate = Color(0.2, 0.1, 0.05)
		hdr.position = Vector3(0, 1.66, 0.09)
		add_child(hdr)
		bin = Area3D.new()
		bin.name = "TrashBin"
		bin.collision_layer = 0
		bin.collision_mask = Types.L_ITEM
		bin.monitoring = true
		var bcs := CollisionShape3D.new()
		var bbs := BoxShape3D.new()
		bbs.size = Vector3(0.9, 0.7, 0.9)
		bcs.shape = bbs
		bin.add_child(bcs)
		bin.position = Vector3(1.1, 0.35, 0)
		add_child(bin)
		var metal := StandardMaterial3D.new()
		metal.albedo_color = Color(0.32, 0.36, 0.38)
		metal.roughness = 0.6
		metal.metallic = 0.4
		var can := MeshInstance3D.new()
		can.mesh = LowPoly.cylinder(0.36, 0.32, 0.7, 10)
		can.material_override = metal
		can.position = bin.position
		add_child(can)
		var rim := MeshInstance3D.new()
		rim.mesh = LowPoly.cylinder(0.4, 0.4, 0.06, 10)
		rim.material_override = metal
		rim.position = bin.position + Vector3(0, 0.36, 0)
		add_child(rim)
		var tag := Label3D.new()
		tag.text = tr("JOBS_BIN_LABEL")
		tag.font_size = 40
		tag.outline_size = 8
		tag.pixel_size = 0.0025
		tag.modulate = Color(1.0, 0.86, 0.3)
		tag.outline_modulate = Color(0.1, 0.1, 0.12)
		tag.position = bin.position + Vector3(0, 0.05, 0.37)
		add_child(tag)

	func interact(player: Node) -> void:
		if jobs:
			jobs.on_board_interact(self, player)

	func interact_hint(_player: Node) -> String:
		return tr("JOBS_BOARD_HINT")


## Локальное меню вакансий (мышь, Esc).
class JobsMenu extends CanvasLayer:
	signal take_pressed(job_id: String)
	signal closed

	var _root: Control
	var _panel: PanelContainer
	var _open := false
	var _mouse_was := Input.MOUSE_MODE_CAPTURED

	func _ready() -> void:
		layer = 25
		visible = false
		process_mode = Node.PROCESS_MODE_ALWAYS
		_root = Control.new()
		_root.set_anchors_preset(Control.PRESET_FULL_RECT)
		_root.theme = UiTheme.make()
		add_child(_root)
		var dim := ColorRect.new()
		dim.color = Color(0.05, 0.03, 0.08, 0.55)
		dim.set_anchors_preset(Control.PRESET_FULL_RECT)
		dim.mouse_filter = Control.MOUSE_FILTER_STOP
		_root.add_child(dim)
		# CenterContainer — панель любой высоты остаётся в центре и не уезжает за низ экрана
		var center := CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(center)
		_panel = PanelContainer.new()
		_panel.custom_minimum_size = Vector2(560, 0)
		_panel.add_theme_stylebox_override("panel", UiTheme.card_panel())
		center.add_child(_panel)

	func show_offers(offers: Array) -> void:
		for c in _panel.get_children():
			c.queue_free()
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		_panel.add_child(box)
		box.add_child(UiTheme.header(tr("JOBS_TITLE"), 32))
		for o in offers:
			var row := PanelContainer.new()
			row.add_theme_stylebox_override("panel", UiTheme.pill_panel(UiTheme.PANEL_HI, 12))
			# слева заголовок+описание, справа цена и кнопка — компактно, 3 вакансии влезают в 720p
			var hb := HBoxContainer.new()
			hb.add_theme_constant_override("separation", 12)
			row.add_child(hb)
			var vb := VBoxContainer.new()
			vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hb.add_child(vb)
			var pay: int = int(o.get("pay", 0))
			var jid := str(o.get("id", ""))
			var pay_txt := tr("JOBS_PAY_VARIES") if jid == "janitor" else ("$%d" % pay)
			vb.add_child(UiTheme.body(str(o.get("title", "")), 20))
			var desc := UiTheme.body(str(o.get("desc", "")), 15, true)
			desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			desc.custom_minimum_size = Vector2(340, 0)
			vb.add_child(desc)
			var right := VBoxContainer.new()
			right.alignment = BoxContainer.ALIGNMENT_CENTER
			hb.add_child(right)
			var pay_l := UiTheme.body(pay_txt, 22)
			pay_l.add_theme_color_override("font_color", UiTheme.SUCCESS)
			pay_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			right.add_child(pay_l)
			var take := UiTheme.fat_button(tr("JOBS_TAKE"), 120)
			var job_id := jid
			take.pressed.connect(func():
				take_pressed.emit(job_id)
				hide_menu())
			right.add_child(take)
			box.add_child(row)
		var close_row := HBoxContainer.new()
		close_row.alignment = BoxContainer.ALIGNMENT_CENTER
		var close := UiTheme.fat_button(tr("JOBS_CLOSE"), 200)
		close.pressed.connect(hide_menu)
		close_row.add_child(close)
		box.add_child(close_row)
		_open = true
		visible = true
		_mouse_was = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	func hide_menu() -> void:
		if not _open:
			return
		_open = false
		visible = false
		Input.mouse_mode = _mouse_was
		closed.emit()

	func _input(event: InputEvent) -> void:
		if not _open:
			return
		if event.is_action_pressed("ui_cancel"):
			hide_menu()
			get_viewport().set_input_as_handled()


var _boards: Array[JobBoard] = []
var _offers: Array[String] = []
var _refresh_t := 0.0
var _active: Dictionary = {}
var _suggest_t := 0.0
var _suggesting := false
var _menu: JobsMenu = null
var _trailer_board_pos := Vector3.ZERO


func system_name() -> String:
	return "Jobs"


func _ready() -> void:
	call_deferred("_deferred_setup")


func _deferred_setup() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_build_boards()
	if Net.is_host():
		_refresh_offers()
		var jan: Node = Game.world.system("Janitor") if Game.world else null
		if jan and jan.has_signal("job_finished"):
			jan.job_finished.connect(_on_janitor_finished)
	_menu = JobsMenu.new()
	_menu.take_pressed.connect(_on_menu_take)
	add_child(_menu)


func _physics_process(delta: float) -> void:
	if not Net.is_host():
		return
	_refresh_t += delta
	if _refresh_t >= REFRESH_SEC:
		_refresh_t = 0.0
		_refresh_offers()
	if _suggesting:
		_suggest_t -= delta
		if _suggest_t <= 0.0:
			_suggesting = false
			_broadcast_jobs_state(true)
	if _active.is_empty():
		return
	match str(_active.get("id", "")):
		"trash":
			_tick_trash()
		"delivery":
			_tick_delivery()
		"flyers":
			_tick_flyers()
		"car_wash":
			_tick_car_wash(delta)
		"night_watch":
			_tick_night_watch(delta)


func _road_dir(pos: Vector3) -> Vector3:
	var to_center := -Vector3(pos.x, 0.0, pos.z)
	if to_center.length() < 5.0:
		return Vector3.RIGHT
	return to_center.normalized()


func _board_positions() -> Array:
	var out: Array = []
	var sign: Node3D = Game.world.find_marker(Types.District.TRAILER_PARK, "HouseSign") if Game.world else null
	if sign:
		var yard := -_road_dir(sign.global_position)
		out.append(sign.global_position + yard * 3.0)
	else:
		var tp: Node3D = Game.world.district_root(Types.District.TRAILER_PARK) if Game.world else null
		out.append(tp.global_position + Vector3(3, 0, 2) if tp else Vector3(0, 0, 6))
	var vend: Node3D = Game.world.district_root(Types.District.VENDORS) if Game.world else null
	if vend:
		out.append(vend.global_position + _road_dir(vend.global_position) * 6.0)
	else:
		out.append(Vector3(40, 0, 0))
	var spawn: Node3D = Game.world.find_marker(Types.District.POLICE, "PoliceCarSpawn") if Game.world else null
	var pol: Node3D = Game.world.district_root(Types.District.POLICE) if Game.world else null
	if spawn:
		out.append(spawn.global_position + _road_dir(spawn.global_position) * 2.5)
	elif pol:
		out.append(pol.global_position + _road_dir(pol.global_position) * 8.0)
	else:
		out.append(Vector3(-40, 0, 0))
	return out


func _build_boards() -> void:
	for b in _boards:
		if is_instance_valid(b):
			b.queue_free()
	_boards.clear()
	var positions := _board_positions()
	for i in positions.size():
		var board := JobBoard.new(self, i)
		add_child(board)
		board.global_position = positions[i]
		board.look_at(board.global_position + _road_dir(board.global_position), Vector3.UP)
		_boards.append(board)
	if not _boards.is_empty():
		_trailer_board_pos = _boards[0].global_position


func board_position(index: int) -> Vector3:
	if index >= 0 and index < _boards.size():
		return _boards[index].global_position
	return _trailer_board_pos


func on_board_interact(_board: JobBoard, player: Node) -> void:
	if not Net.is_host():
		return
	var peer := (player as Player).peer_id if player is Player else Net.my_id()
	_send_menu_to(peer)


func _send_menu_to(peer: int) -> void:
	var payload: Array = []
	for id in _offers:
		payload.append(_offer_payload(id))
	Net.send_event(peer, "jobs_menu", {"offers": payload})


func _show_menu(offers: Array) -> void:
	if _menu:
		_menu.show_offers(offers)


func _on_menu_take(job_id: String) -> void:
	Net.request_action("job_take", {"id": job_id})


func _job_pool() -> Array:
	var pool: Array = ["janitor", "trash", "delivery", "flyers", "car_wash"]
	var dn: Node = Game.world.system("DayNight") if Game.world else null
	if dn and dn.has_method("is_night") and dn.is_night():
		pool.append("night_watch")
	return pool


func _refresh_offers() -> void:
	var pool: Array = _job_pool()
	pool.shuffle()
	_offers.clear()
	for i in mini(OFFER_COUNT, pool.size()):
		_offers.append(str(pool[i]))


func _offer_payload(id: String) -> Dictionary:
	return {
		"id": id,
		"title": tr("JOB_%s_TITLE" % id.to_upper()),
		"desc": tr("JOB_%s_DESC" % id.to_upper()),
		"pay": JOB_PAY.get(id, 0),
	}


func offer_count() -> int:
	return _offers.size()


func flyer_waypoints() -> Array:
	return _flyer_waypoints()


func trash_bin_at(board_idx: int) -> Area3D:
	if board_idx >= 0 and board_idx < _boards.size():
		return _boards[board_idx].bin
	return _boards[0].bin if not _boards.is_empty() else null


func playtest_set_offers(ids: Array) -> void:
	if not Net.is_host():
		return
	_offers.clear()
	for id in ids:
		_offers.append(str(id))


func suggest_work(_reason: String = "") -> void:
	if not Net.is_host():
		return
	_suggesting = true
	_suggest_t = SUGGEST_SEC
	_broadcast_jobs_state(false, tr("JOBS_SUGGEST"), _trailer_board_pos)


func handle_action(peer: int, kind: String, data: Dictionary) -> bool:
	match kind:
		"job_take":
			return _take_job(peer, str(data.get("id", "")))
	return false


func _take_job(peer: int, id: String) -> bool:
	if not Net.is_host() or id == "" or not _offers.has(id):
		return false
	var p: Player = Game.world.player_of(peer) if Game.world else null
	if p == null:
		return false
	if not _active.is_empty():
		_cancel_active(true)
	var board_idx := _nearest_board_idx(p.global_position)
	if not _start_job(id, p, board_idx):
		return false
	Game.notify.emit(tr("JOBS_TAKEN_FMT") % tr("JOB_%s_TITLE" % id.to_upper()), 4.0)
	_suggesting = false
	_suggest_t = 0.0
	_broadcast_jobs_state(false)
	return true


func _nearest_board_idx(pos: Vector3) -> int:
	var best := 0
	var best_d := 1e9
	for i in _boards.size():
		var d: float = _boards[i].global_position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = i
	return best


func _start_job(id: String, player: Player, board_idx: int) -> bool:
	match id:
		"janitor":
			var jan: Janitor = Game.world.system("Janitor") as Janitor
			if jan == null or not jan.try_start(player):
				return false
			_active = {"id": id, "board": board_idx, "peer": player.peer_id}
			return true
		"trash":
			_active = {
				"id": id, "board": board_idx, "peer": player.peer_id,
				"count": 0, "need": 6, "dist": _board_district_name(board_idx),
			}
			return true
		"delivery":
			var vend: VendorDef = _pick_vendor()
			if vend == null:
				return false
			var stand: Node3D = Game.world.find_marker(Types.District.VENDORS, "VendorStand_%s" % vend.id)
			if stand == null:
				return false
			var crate_id := _pick_crate_id()
			var pos: Vector3 = board_position(board_idx) + Vector3(0, 0.9, 0.4)
			var body = Net.spawn_item(crate_id, Transform3D(Basis(), pos), {"lot": "job_delivery"})
			if body == null:
				return false
			_active = {
				"id": id, "board": board_idx, "peer": player.peer_id,
				"crate": body.net_id, "target": stand.global_position,
				"vendor_id": vend.id,
			}
			return true
		"flyers":
			_active = {
				"id": id, "board": board_idx, "peer": player.peer_id,
				"idx": 0, "need": FLYER_DISTRICTS.size(), "wps": _flyer_waypoints(),
			}
			return true
		"car_wash":
			var sponge_id := _pick_sponge_id()
			Net.spawn_item(sponge_id, Transform3D(Basis(), board_position(board_idx) + Vector3(0.6, 0.85, 0.2)))
			var slot: Node3D = Game.world.find_marker(Types.District.CAR_MARKET, "CarSlot0")
			_active = {
				"id": id, "board": board_idx, "peer": player.peer_id,
				"target": slot.global_position if slot else Vector3.ZERO,
				"scrub": 0.0, "need": 8.0,
			}
			return true
		"night_watch":
			var storage: Node3D = Game.world.district_root(Types.District.STORAGE)
			_active = {
				"id": id, "board": board_idx, "peer": player.peer_id,
				"target": storage.global_position if storage else Vector3.ZERO,
				"stand": 0.0, "need": 60.0,
			}
			return true
	return false


func _board_district_name(board_idx: int) -> String:
	match board_idx:
		0:
			return tr("DISTRICT_TRAILER_PARK")
		1:
			return tr("DISTRICT_VENDORS")
		_:
			return tr("DISTRICT_POLICE")


func _pick_vendor() -> VendorDef:
	var all := Registry.all_vendors()
	if all.is_empty():
		return null
	return all[randi() % all.size()]


func _pick_crate_id() -> String:
	for tag in ["crate", "box"]:
		var items: Array = Registry.items_with_tag(tag)
		if not items.is_empty():
			return (items[0] as ItemDef).id
	if Registry.item("crate_wooden"):
		return "crate_wooden"
	return Registry.all_items()[0].id


func _pick_sponge_id() -> String:
	for sid in ["sponge_kitchen", "sponge_loofah", "sponge_robert", "tool_rag"]:
		if Registry.item(sid):
			return sid
	var cloth: Array = Registry.items_with_tag("cloth")
	if not cloth.is_empty():
		return (cloth[0] as ItemDef).id
	for d in Registry.all_items():
		if "sponge" in d.id:
			return d.id
	return "sponge_kitchen"


func _flyer_waypoints() -> Array:
	var out: Array = []
	for d in FLYER_DISTRICTS:
		var root: Node3D = Game.world.district_root(d) if Game.world else null
		if root:
			out.append(root.global_position + _road_dir(root.global_position) * 4.0)
	return out


func _cancel_active(abandon_toast: bool) -> void:
	if _active.is_empty():
		return
	if abandon_toast:
		Game.notify.emit(tr("JOBS_ABANDON"), 3.0)
	var id := str(_active.get("id", ""))
	if id == "janitor":
		var jan: Janitor = Game.world.system("Janitor") as Janitor
		if jan and jan.active:
			jan._finish_job(true)
	elif id == "delivery":
		var nid: int = int(_active.get("crate", 0))
		if Net.items.has(nid):
			Net.despawn_item(nid)
	_active.clear()
	_broadcast_jobs_state(true)


func _complete_job(pay: bool, amount: int = 0) -> void:
	var id := str(_active.get("id", ""))
	if pay and amount > 0:
		Economy.add(amount, "job")
		Game.notify.emit(tr("JOBS_DONE_FMT") % amount, 5.0)
		AudioBus.play_ui("cash_register")
	if id != "janitor" or pay:
		Game.stat_add("jobs_done")
	_active.clear()
	_refresh_offers()
	_broadcast_jobs_state(true)


func _on_janitor_finished(_payout: int) -> void:
	if str(_active.get("id", "")) == "janitor":
		Game.stat_add("jobs_done")
		_active.clear()
		_refresh_offers()
		_broadcast_jobs_state(true)


func _is_trash_item(b: ItemBody) -> bool:
	if b == null or not is_instance_valid(b):
		return false
	if b.get_meta("street", false):
		return true
	return b.def != null and b.def.value_base <= 30


func _tick_trash() -> void:
	var board_idx: int = int(_active.get("board", 0))
	if board_idx < 0 or board_idx >= _boards.size():
		return
	var area: Area3D = _boards[board_idx].bin
	if area == null:
		return
	for body in area.get_overlapping_bodies():
		if not (body is ItemBody):
			continue
		var b: ItemBody = body
		if not _is_trash_item(b):
			continue
		Net.despawn_item(b.net_id)
		var n: int = int(_active.get("count", 0)) + 1
		_active["count"] = n
		var need: int = int(_active.get("need", 6))
		Game.notify.emit(tr("JOBS_PROGRESS_FMT") % [n, need], 2.0)
		_broadcast_jobs_state(false)
		if n >= need:
			_complete_job(true, JOB_PAY["trash"])
		return


func _tick_delivery() -> void:
	var nid: int = int(_active.get("crate", 0))
	var b = Net.items.get(nid)
	if b == null or not is_instance_valid(b):
		_cancel_active(false)
		return
	var target: Vector3 = _active.get("target", Vector3.ZERO)
	if b.global_position.distance_to(target) <= 2.5:
		Net.despawn_item(nid)
		_complete_job(true, JOB_PAY["delivery"])


func _tick_flyers() -> void:
	var wps: Array = _active.get("wps", [])
	var idx: int = int(_active.get("idx", 0))
	if idx >= wps.size():
		_complete_job(true, JOB_PAY["flyers"])
		return
	var wp: Vector3 = wps[idx]
	for pid in Net.players:
		var pl: Player = Net.players[pid]
		if is_instance_valid(pl) and pl.global_position.distance_to(wp) <= 4.0:
			pl.say(tr("FLYER_LINE_%d" % idx))
			Game.notify.emit(tr("JOBS_PROGRESS_FMT") % [idx + 1, wps.size()], 2.5)
			_active["idx"] = idx + 1
			_broadcast_jobs_state(false)
			if int(_active["idx"]) >= wps.size():
				_complete_job(true, JOB_PAY["flyers"])
			return


func _player_holds_scrub_item(p: Player) -> bool:
	var held := p.hands.any_held()
	if held == null:
		return false
	if held.def.tags.has("cloth") or held.def.tags.has("rag"):
		return true
	for tag in ["sponge", "rag"]:
		if held.def.tags.has(tag):
			return true
	return "sponge" in held.def.id


func _tick_car_wash(delta: float) -> void:
	var target: Vector3 = _active.get("target", Vector3.ZERO)
	var near_car := false
	var veh_sys: Node = Game.world.system("Vehicles") if Game.world else null
	if veh_sys and "vehicles" in veh_sys:
		for v in veh_sys.vehicles.values():
			if not is_instance_valid(v):
				continue
			if v.global_position.distance_to(target) > 25.0:
				continue
			for pid in Net.players:
				var pl: Player = Net.players[pid]
				if not is_instance_valid(pl):
					continue
				if pl.global_position.distance_to(v.global_position) <= 3.0 and _player_holds_scrub_item(pl):
					near_car = true
					break
			if near_car:
				break
	if near_car:
		var t: float = float(_active.get("scrub", 0.0)) + delta
		_active["scrub"] = t
		_broadcast_jobs_state(false)
		if t >= float(_active.get("need", 8.0)):
			_complete_job(true, JOB_PAY["car_wash"])


func _tick_night_watch(delta: float) -> void:
	var target: Vector3 = _active.get("target", Vector3.ZERO)
	var inside := false
	for pid in Net.players:
		var pl: Player = Net.players[pid]
		if is_instance_valid(pl) and pl.global_position.distance_to(target) <= 6.0:
			inside = true
			break
	if inside:
		var t: float = float(_active.get("stand", 0.0)) + delta
		_active["stand"] = t
		_broadcast_jobs_state(false)
		if t >= float(_active.get("need", 60.0)):
			_complete_job(true, JOB_PAY["night_watch"])


func _objective_for_active() -> Dictionary:
	if _active.is_empty():
		if _suggesting:
			return {"text": tr("JOBS_SUGGEST"), "target": _trailer_board_pos, "progress": []}
		return {"text": "", "target": Vector3.INF, "progress": []}
	var id := str(_active.get("id", ""))
	var target := Vector3.INF
	var text := ""
	match id:
		"janitor":
			var jan: Janitor = Game.world.system("Janitor") as Janitor
			text = tr("JOB_JANITOR_OBJ")
			if jan and jan.has_method("job_target"):
				target = jan.job_target()
		"trash":
			text = tr("JOB_TRASH_OBJ") % str(_active.get("dist", ""))
			target = board_position(int(_active.get("board", 0)))
		"delivery":
			var vend: VendorDef = Registry.vendor(str(_active.get("vendor_id", "")))
			var vname := vend.display_name() if vend else str(_active.get("vendor_id", ""))
			text = tr("JOB_DELIVERY_OBJ") % vname
			target = _active.get("target", Vector3.ZERO)
		"flyers":
			text = tr("JOB_FLYERS_OBJ")
			var wps: Array = _active.get("wps", [])
			var idx: int = int(_active.get("idx", 0))
			if idx < wps.size():
				target = wps[idx]
		"car_wash":
			text = tr("JOB_CAR_WASH_OBJ")
			target = _active.get("target", Vector3.ZERO)
		"night_watch":
			text = tr("JOB_NIGHT_WATCH_OBJ")
			target = _active.get("target", Vector3.ZERO)
	return {"text": text, "target": target, "progress": _progress_pair()}


func _progress_pair() -> Array:
	var id := str(_active.get("id", ""))
	match id:
		"trash":
			return [int(_active.get("count", 0)), int(_active.get("need", 6))]
		"flyers":
			return [int(_active.get("idx", 0)), int(_active.get("need", 4))]
		"car_wash":
			return [int(_active.get("scrub", 0.0)), int(_active.get("need", 8.0))]
		"night_watch":
			return [int(_active.get("stand", 0.0)), int(_active.get("need", 60.0))]
	return []


func _broadcast_jobs_state(clear: bool, text_override: String = "", target_override: Vector3 = Vector3.INF) -> void:
	var obj := _objective_for_active()
	if clear and not _suggesting:
		obj = {"text": "", "target": Vector3.INF, "progress": []}
	elif text_override != "":
		obj["text"] = text_override
		obj["target"] = target_override
	var data := {
		"active": str(_active.get("id", "")),
		"text": obj["text"],
		"target": obj["target"],
		"progress": obj["progress"],
	}
	Net.broadcast_event("jobs_state", data)
	_apply_jobs_state(data)


func _apply_jobs_state(data: Dictionary) -> void:
	var hud: Node = Game.world.hud if Game.world else null
	if hud == null:
		return
	var txt: String = str(data.get("text", ""))
	if txt.strip_edges() == "":
		if hud.has_method("clear_objective"):
			hud.clear_objective()
		return
	var target: Vector3 = data.get("target", Vector3.INF)
	if hud.has_method("set_objective"):
		hud.set_objective(txt, target)


func on_net_event(kind: String, data: Dictionary) -> void:
	match kind:
		"jobs_menu":
			_show_menu(data.get("offers", []))
		"jobs_state":
			_apply_jobs_state(data)


func send_full_state_to(peer: int) -> void:
	var obj := _objective_for_active()
	var payload := {
		"active": str(_active.get("id", "")),
		"text": obj["text"],
		"target": obj["target"],
		"progress": obj["progress"],
	}
	Net.send_event(peer, "jobs_state", payload)
