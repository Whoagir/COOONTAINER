extends Node
## Арт-ревью: снимает «геройские» ракурсы на золотом часу в user://shots/art_*.png и выходит.
##   godot --path . -- --artshot            (все ракурсы)
##   godot --path . -- --artshot --time=0.97 (тот же набор ночью)
## Ракурсы: трейлер-парк как на кей-арте, толпа хантеров крупно, куча барахла, пикап,
## игрок от третьего лица, торговец, ангар внутри. Сверяем с assets/textures/keyart_menu.png.

var w
var p: Player
var cine: Cinematic
var _t := 0.0
var _started := false
var _n := 0
var _dir := ""


static func wanted() -> bool:
	return OS.get_cmdline_user_args().has("--artshot") and DisplayServer.get_name() != "headless"


func _ready() -> void:
	w = Game.world
	_dir = OS.get_user_data_dir().path_join("shots")
	for a in OS.get_cmdline_user_args(): # --artdir=name → user://shots/name (параллельные прогоны)
		if str(a).begins_with("--artdir="):
			_dir = _dir.path_join(str(a).substr(9))
	DirAccess.make_dir_recursive_absolute(_dir)


func _process(delta: float) -> void:
	_t += delta
	if _started or _t < 1.0:
		return
	p = w.local_player()
	cine = w.system("Cinematic")
	if p == null or cine == null:
		return
	_started = true
	_run()


func _mk(d: int, m: String) -> Vector3:
	var n: Node3D = w.find_marker(d, m)
	return n.global_position if n else Vector3.ZERO


func _anchor_in(d: int) -> LotAnchor:
	for a in get_tree().get_nodes_in_group("lot_anchors"):
		var dist = w.city.district_at(a.global_position)
		if dist and dist.district_id == d:
			return a
	return null


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _snap(name: String, pos: Vector3, look: Vector3, fov := 55.0, settle := 1.2) -> void:
	cine.snap(pos, look, fov)
	await _wait(settle)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_dir.path_join("art_%02d_%s.png" % [_n, name]))
	print("[artshot] %02d %s" % [_n, name])
	_n += 1


func _spawn_pile(center: Vector3, ids: Array, spread: float) -> Array:
	var out: Array = []
	for i in ids.size():
		var id: String = ids[i]
		if Registry.item(id) == null:
			continue
		var pos := center + Vector3(randf_range(-spread, spread), 0.6 + i * 0.35, randf_range(-spread, spread))
		var b = Net.spawn_item(id, Transform3D(Basis(Vector3.UP, randf() * TAU), pos))
		if b:
			out.append(b)
	return out


## Геройские вещи кей-арта: телевизор, ваза, чемодан, клетка с хомяком, лампа, гитара…
const HERO_IDS := [
	"tv_crt_soviet", "vase_floor_tall", "suitcase_leather", "hamster_cage_deluxe", "lamp_table_tiffany",
	"guitar_acoustic", "microwave_yellow", "boombox_90s", "clock_cuckoo", "globe_school", "toolbox_red",
	"tv_plasma_cracked", "fridge_mini", "bicycle_rusty", "barrel_rusty", "suitcase_kids",
]


func _hero_ids() -> Array:
	var out: Array = []
	for id in HERO_IDS:
		if Registry.item(id) != null:
			out.append(id)
	return out


## Витрина: вещи стоят рядком на земле (заморожены), чтобы судить о моделях, а не о физике.
func _spawn_showcase(center: Vector3, ids: Array, facing: Vector3) -> void:
	var right := facing.cross(Vector3.UP).normalized()
	var n := ids.size()
	var cols := 4
	for i in n:
		var id: String = ids[i]
		if Registry.item(id) == null:
			continue
		var col := i % cols
		var row := i / cols
		var pos := center + right * ((col - (cols - 1) * 0.5) * 1.1) - facing * (row * 1.1) + Vector3(0, 0.05, 0)
		var yaw := atan2(facing.x, facing.z) + PI
		var b = Net.spawn_item(id, Transform3D(Basis(Vector3.UP, yaw), pos))
		if b:
			b.freeze = true


func _run() -> void:
	var dn = w.system("DayNight")
	var has_time := false
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--time="):
			has_time = true
	if dn and not has_time:
		dn.time_of_day = 0.79
	var TP := Types.District.TRAILER_PARK
	var trailer := _mk(TP, "Trailer")
	p.hands.host_release_all()
	cine.begin(false)
	if w.hud:
		w.hud.visible = false

	# --probe=NodeName[,dist] — один кадр на любой узел мира с двух сторон (отладка пропсов)
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--probe="):
			var parts := str(a).substr(8).split(",")
			var target := get_tree().root.find_child(parts[0], true, false) as Node3D
			var dist := float(parts[1]) if parts.size() > 1 else 4.0
			if target:
				var c := target.global_position + Vector3(0, 0.8, 0)
				await _snap("probe_%s_a" % parts[0], c + Vector3(dist * 0.7, dist * 0.45, dist * 0.7), c, 50.0)
				await _snap("probe_%s_b" % parts[0], c + Vector3(-dist * 0.7, dist * 0.45, -dist * 0.7), c, 50.0)
			else:
				print("[artshot] probe: node '%s' not found" % parts[0])
			print("[artshot] done: %d shots in %s" % [_n, _dir])
			load("res://tools/Smoke.gd").cleanup_test_slot()
			get_tree().quit()
			return

	# 1. трейлер-парк, ракурс кей-арта: низкая камера, пикап + трейлер + закат
	# пикап игрока у трейлера, как на арте (свой, чтобы не снимать витрину под крышей)
	var veh_pos := trailer + Vector3(7.5, 0.6, 6.0)
	var veh_sys = w.system("Vehicles")
	var v = null
	if veh_sys and veh_sys.has_method("spawn"):
		v = veh_sys.spawn("pickup_rusty", Transform3D(Basis(Vector3.UP, 0.6), veh_pos), true)
		print("[artshot] pickup: %s host=%s" % [v, Net.is_host()])
		if v and "bed_point" in v:
			await _wait(0.8)
			print("[artshot] pickup at %s (wanted %s)" % [v.global_position, veh_pos])
			veh_pos = v.global_position
			# лут падает в кузов с высоты — заодно проверяем, что пикап не проседает в грунт (_sink_check)
			_spawn_pile(v.global_position + Vector3(0, 1.2, 0.9), _hero_ids().slice(0, 5), 0.35)
			await _wait(2.0)
			print("[artshot] pickup after load y=%.2f" % v.global_position.y)
	_spawn_pile(trailer + Vector3(3, 0, 6), _hero_ids().slice(0, 8), 1.4)
	await _wait(1.5)
	await _snap("trailer_park", trailer + Vector3(-9, 2.2, 13), trailer + Vector3(2, 1.2, 2), 58.0)
	await _snap("trailer_park_wide", trailer + Vector3(-26, 9, 30), trailer + Vector3(0, 1, 0), 50.0)

	# 2. пикап крупно, солнце за камерой
	if v:
		# три четверти сзади-справа, низко — как на кей-арте (кузов с лутом, кабина впереди)
		var vb: Basis = v.global_basis
		var cam_rel: Vector3 = vb * Vector3(3.4, 1.35, 4.6)
		await _snap("pickup", v.global_position + cam_rel, v.global_position + vb * Vector3(0, 0.9, -0.6), 50.0)
		var cam_f: Vector3 = vb * Vector3(-3.6, 1.2, -4.4)
		await _snap("pickup_front", v.global_position + cam_f, v.global_position + vb * Vector3(0, 0.8, 0.3), 50.0)
		await _snap("pickup_side_low", v.global_position + vb * Vector3(6.0, 0.6, 0.5), v.global_position + vb * Vector3(0, 0.6, 0), 45.0)
		print("[artshot] pickup y=%.2f wheels=%s" % [v.global_position.y, str(v._wheels.map(func(wn): return "%.2f" % wn.global_position.y))])

	# 3. хантеры: стартуем сессию, ждём пока встанут, снимаем лица
	var ha := _anchor_in(Types.District.HANGAR)
	var auc = w.system("Auction")
	if ha and auc:
		p.global_position = ha.marker("PlayerStand").global_position + Vector3(0, 1.0, 0)
		auc.start_session(ha)
		await _wait(4.0)
		var spots: Array = ha.hunter_spots()
		if spots.size() > 1:
			var a := (spots[0] as Node3D).global_position
			var b := (spots[spots.size() - 1] as Node3D).global_position
			var mid := (a + b) * 0.5
			# хантеры смотрят на аукциониста — камера с его стороны, им в лица
			var front_n: Node3D = ha.marker("Auctioneer")
			var front: Vector3 = front_n.global_position if front_n else ha.cell_center()
			var to_front := (front - mid)
			to_front.y = 0.0
			to_front = to_front.normalized()
			await _snap("hunters", mid + to_front * 4.2 + Vector3(0, 1.5, 0), mid + Vector3(0, 1.0, 0), 62.0)
			var face_dir := -(b - a).normalized() * 0.35 + to_front
			await _snap("hunter_face", a + face_dir.normalized() * 2.0 + Vector3(0, 1.45, 0), a + Vector3(0, 1.25, 0), 45.0)
		await _snap("hangar", ha.global_position + Vector3(8, 3.5, 10), ha.cell_center() + Vector3(0, 0.8, 0), 60.0)
		var s = auc.session_for(ha)
		if s and s.state != Auction.State.IDLE:
			auc._to_idle(s)

	# 4. куча барахла на земле у трейлера, в открытом золотом свете (низкая камера)
	var pile_c := trailer + Vector3(-9.0, 0.0, 10.0)
	var cam_dir := Vector3(-2.4, 0.0, 3.0).normalized()
	_spawn_showcase(pile_c, _hero_ids(), cam_dir)
	await _wait(1.5)
	await _snap("junk_pile", pile_c + cam_dir * 4.2 + Vector3(0, 1.6, 0), pile_c + Vector3(0, 0.4, -0.6), 52.0)
	await _snap("junk_close", pile_c + cam_dir * 2.4 + Vector3(0, 0.9, 0), pile_c + Vector3(0, 0.35, 0), 45.0)

	# 5. игрок от третьего лица (в лицо)
	p.global_position = trailer + Vector3(-3, 1.0, 5)
	p.look_toward(trailer + Vector3(-3, 1.0, 12))
	p.set_third_person(true)
	await _wait(0.6)
	await _snap("player_3p", p.global_position + Vector3(0.9, 0.7, 2.4), p.global_position + Vector3(0, 0.75, 0), 45.0)
	p.set_third_person(false)

	# 6. торговец
	var stand: Node3D = w.find_marker(Types.District.VENDORS, "VendorStand_vendor_tiny")
	if stand:
		await _snap("vendor", stand.global_position + Vector3(0, 1.6, 3.0), stand.global_position + Vector3(0, 1.2, 0), 50.0)
		# жёлтая зона «сюда хлам» перед прилавком — глазами игрока, который подходит с вещью
		await _snap("vendor_zone", stand.global_position + Vector3(1.2, 1.7, 4.2), stand.global_position + Vector3(0, 0.3, 1.6), 62.0)

	# 7. доска объявлений + меню вакансий (то, что видит игрок без денег)
	var jobs = w.system("Jobs")
	if jobs and jobs.has_method("board_position"):
		var bp: Vector3 = jobs.board_position(0)
		var fwd: Vector3 = jobs._boards[0].global_basis.z if jobs._boards.size() > 0 else Vector3.BACK
		await _snap("jobs_board", bp + fwd * 3.2 + Vector3(0.8, 1.7, 0), bp + Vector3(0, 1.3, 0), 50.0)
		if jobs._boards.size() > 0:
			jobs._boards[0].interact(p)
			await _wait(0.8)
			await _snap("jobs_menu", bp + fwd * 3.2 + Vector3(0.8, 1.7, 0), bp + Vector3(0, 1.3, 0), 50.0)
			if "_menu" in jobs and jobs._menu and jobs._menu.has_method("hide_menu"):
				jobs._menu.hide_menu()

	# 8. город с высоты
	await _snap("city", trailer + Vector3(0, 28, 62), Vector3(0, 0, -30), 60.0)

	print("[artshot] done: %d shots in %s" % [_n, _dir])
	load("res://tools/Smoke.gd").cleanup_test_slot()
	get_tree().quit()
