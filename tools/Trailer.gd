extends Node
## Трейлер игры из живого геймплея (Movie Maker, детерминированный рендер):
##   godot --path . --write-movie user://trailer/raw.avi --fixed-fps 30 --resolution 1280x720 -- --trailer
##   затем tools/trailer.ps1 → ffmpeg → trailer.mp4 (h264 + aac)
## Каждая сцена: постановка (спавн/поджиг/аукцион/тачка/менты) → шот Cinematic с титром.
## Можно смотреть и без записи: godot --path . -- --trailer

const DIR := "user://trailer"

var w
var p: Player
var cine: Cinematic
var _t := 0.0
var _started := false


static func wanted() -> bool:
	return OS.get_cmdline_user_args().has("--trailer")


func _ready() -> void:
	w = Game.world
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))


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


func _tr(k: String) -> String:
	return TranslationServer.translate(k)


func _mk(d: int, m: String) -> Vector3:
	var n: Node3D = w.find_marker(d, m)
	return n.global_position if n else Vector3.ZERO


func _anchor_in(d: int) -> LotAnchor:
	for a in get_tree().get_nodes_in_group("lot_anchors"):
		var dist = w.city.district_at(a.global_position)
		if dist and dist.district_id == d:
			return a
	return null


func _spawn_many(center: Vector3, n: int, spread: float, y: float, filter: Callable = Callable()) -> Array:
	var out: Array = []
	var defs := Registry.all_items()
	var i := 0
	var tries := 0
	while i < n and tries < n * 6:
		tries += 1
		var d: ItemDef = defs[randi() % defs.size()]
		if filter.is_valid() and not filter.call(d):
			continue
		var arch := Registry.archetype_for(d)
		if arch == null or arch.size_class == Types.SizeClass.TEAM or arch.size_class == Types.SizeClass.VEHICLE:
			continue
		var pos := center + Vector3(randf_range(-spread, spread), y + randf_range(0.0, 1.2), randf_range(-spread, spread))
		var b = Net.spawn_item(d.id, Transform3D(Basis(Vector3.UP, randf() * TAU), pos))
		if b:
			b.angular_velocity = Vector3(randf_range(-3, 3), randf_range(-3, 3), randf_range(-3, 3))
			out.append(b)
			i += 1
	return out


func _shot(d: Dictionary) -> void:
	cine.run([d])
	await cine.sequence_done


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


# ------------------------------------------------------------------ сценарий

func _run() -> void:
	print("[trailer] start")
	var dn = w.system("DayNight")
	var TP := Types.District.TRAILER_PARK
	var trailer := _mk(TP, "Trailer")
	p.hands.host_release_all()
	Economy.set_pot(5000, "trailer")
	cine.begin(false)
	AudioBus.play_music("credits", -9.0)

	# 1. Заезд: трейлер-парк на закате
	if dn:
		dn.time_of_day = 0.79
	await _shot({
		"from": trailer + Vector3(-34, 24, 52), "to": trailer + Vector3(-9, 7, 20),
		"look": trailer + Vector3(0, 1, 0), "dur": 6.0, "fov": 55.0, "fade_in": 1.2,
		"title": "COOONTAINER", "sub": _tr("TRL_1"), "text_delay": 1.0,
	})

	# 2. Аукцион в ангаре: хантеры поднимают вёсла
	var ha := _anchor_in(Types.District.HANGAR)
	var auc = w.system("Auction")
	if ha and auc:
		p.global_position = ha.marker("PlayerStand").global_position + Vector3(0, 1.0, 0)
		p.look_toward(ha.cell_center())
		auc.start_session(ha)
		var s = auc.session_for(ha)
		if s:
			s.timer = 0.6
		var spots: Array = ha.hunter_spots()
		var a := (spots[0] as Node3D).global_position if spots.size() > 0 else ha.global_position + Vector3(-3, 0, 5)
		var b := (spots[spots.size() - 1] as Node3D).global_position if spots.size() > 1 else ha.global_position + Vector3(3, 0, 5)
		var mid := (a + b) * 0.5
		var to_cell := ha.cell_center() - mid
		to_cell.y = 0.0
		to_cell = to_cell.normalized()
		var row := (b - a).normalized()
		_bid_loop(ha, auc, 6.5)
		# камера перед рядом хантеров (между ними и ячейкой), едет вдоль ряда и смотрит им в лица
		await _shot({
			"from": mid + to_cell * 3.6 - row * 2.2 + Vector3(0, 1.45, 0), "to": mid + to_cell * 3.0 + row * 2.2 + Vector3(0, 1.3, 0),
			"look": mid - row * 1.0 + Vector3(0, 1.35, 0), "look_to": mid + row * 1.0 + Vector3(0, 1.3, 0),
			"dur": 7.0, "fov": 62.0, "title": _tr("TRL_2_T"), "sub": _tr("TRL_2"), "text_delay": 0.5,
		})
		if s and s.state != Auction.State.IDLE:
			auc._to_idle(s)

	# 3. Вывоз: лавина барахла в ячейке
	var sa := _anchor_in(Types.District.STORAGE)
	if sa == null:
		sa = ha
	if sa:
		var c := sa.cell_center()
		var fwd := sa.cell().global_basis.z # вход по +Z
		_spawn_many(c + Vector3(0, 0.8, 0), 48, 1.1, 0.4)
		await _shot({
			"from": c + fwd * 3.2 + Vector3(0.6, -0.4, 0), "to": c + fwd * 1.6 + Vector3(-0.3, -0.6, 0),
			"look": c + Vector3(0, -0.7, 0), "dur": 5.5, "fov": 70.0, "shake": 0.5,
			"title": _tr("TRL_3_T"), "sub": _tr("TRL_3"), "text_delay": 0.6,
		})

		# 4. Хрупкое: ваза с высоты
		var vases: Array = Registry.items_with_tag("vase")
		var vase_def: ItemDef = vases[0] if not vases.is_empty() else Registry.random_item_with_facet(Types.Facet.FRAGILE)
		var drop := c + fwd * 5.0 + Vector3(0, -sa.cell_size.y * 0.5, 0)
		var vase = Net.spawn_item(vase_def.id, Transform3D(Basis(), drop + Vector3(0, 2.0, 0)))
		if vase:
			vase.linear_velocity = Vector3(0, -3.0, 0)
			vase.angular_velocity = Vector3(2.0, 0.5, 1.0)
		await _shot({
			"from": drop + Vector3(1.7, 0.5, 1.3), "to": drop + Vector3(1.1, 0.35, 0.8),
			"look": drop + Vector3(0, 0.6, 0), "look_to": drop + Vector3(0, 0.15, 0), "dur": 3.8, "fov": 55.0,
			"sub": _tr("TRL_4"), "text_delay": 1.2,
		})

		# 5. Жидкости и огонь
		var fire_spot := c + fwd * 7.5 + Vector3(2.0, -sa.cell_size.y * 0.5, 0)
		var junk := _spawn_many(fire_spot, 10, 1.4, 0.3, func(d: ItemDef): return d.flammable)
		var gas: ItemDef = null
		var booze: ItemDef = null
		for d in Registry.all_items():
			if d.liquid_id == Types.LiquidId.GASOLINE and gas == null:
				gas = d
			if d.liquid_id == Types.LiquidId.WHISKEY and booze == null:
				booze = d
		var liq = w.system("Liquids")
		if gas:
			var g = Net.spawn_item(gas.id, Transform3D(Basis(), fire_spot + Vector3(-0.8, 0.5, 0.6)))
			if g:
				g.is_open = true
				g.spill(0.9)
		if booze:
			var bz = Net.spawn_item(booze.id, Transform3D(Basis(), fire_spot + Vector3(0.9, 0.5, -0.5)))
			if bz:
				bz.is_open = true
				bz.spill(0.7)
		await _wait(0.8)
		if liq:
			liq.ignite_at(fire_spot + Vector3(-0.8, 0.0, 0.6))
		for j in junk:
			if is_instance_valid(j) and randf() < 0.5:
				j.ignite()
		await _shot({
			"from": fire_spot + Vector3(3.0, 0.5, 2.6), "to": fire_spot + Vector3(1.6, 1.2, 1.4),
			"look": fire_spot + Vector3(0, 0.4, 0), "dur": 6.0, "fov": 62.0, "shake": 0.3,
			"title": _tr("TRL_5_T"), "sub": _tr("TRL_5"), "text_delay": 0.6,
		})

	# 6. Тачка с кузовом по кочкам
	var veh_sys = w.system("Vehicles")
	if veh_sys and "vehicles" in veh_sys and veh_sys.vehicles.size() > 0:
		var v = veh_sys.vehicles.values()[0]
		var bed: Node3D = v.get_node_or_null("Bed") if v.has_node("Bed") else v
		if v._price_label:
			v._price_label.visible = false
		var start := _road_run_start(v)
		if not start.is_empty():
			v.global_transform = Transform3D(Basis.looking_at(start["dir"], Vector3.UP), start["pos"])
		v.linear_velocity = Vector3.ZERO
		v.angular_velocity = Vector3.ZERO
		await get_tree().physics_frame
		await get_tree().physics_frame
		# лут кладём в кузов заранее и мягко: тачка заморожена, вещи — небольшие, с высоты пола кузова,
		# иначе куча падает с метра, пробивает подвеску и тачка «тонет» в грунте на камеру
		v.freeze = true
		var small: Array = []
		for d in Registry.all_items():
			if d.value_base >= 20 and not d.illegal and not d.is_cash() and d.liquid_id == Types.LiquidId.NONE:
				var a: Archetype = Registry.archetype_for(d)
				if a == null or a.size_class == Types.SizeClass.ONE_HAND or a.size_class == Types.SizeClass.TWO_HAND:
					small.append(d)
		if small.is_empty():
			small = Registry.all_items()
		var floor_y: float = v.bed_floor_world_y() if v.has_method("bed_floor_world_y") else bed.global_position.y + 0.8
		for i in 7:
			var d: ItemDef = small[randi() % small.size()]
			var lp: Vector3 = v.bed_point(Vector2(randf_range(-0.35, 0.35), randf_range(-0.55, 0.55)), 0.15 + (i / 4) * 0.3) if v.has_method("bed_point") else bed.global_position + Vector3(randf_range(-0.4, 0.4), floor_y - bed.global_position.y + 0.2, randf_range(-0.6, 0.6))
			Net.spawn_item(d.id, Transform3D(Basis(Vector3.UP, randf() * TAU), lp))
			await get_tree().physics_frame
		await _wait(0.8)
		v.freeze = false
		await _wait(0.4)
		print("[trailer] pickup loaded: y=%.2f bed_items=%d" % [v.global_position.y, v.bed_items.size()])
		AudioBus.play_music("car_rock_loop", -8.0)
		v.test_drive = true
		v.apply_input(0.0, 1.0, 0.0, false)
		await _shot({
			"follow": v, "from": Vector3(4.5, 1.6, 3.5), "to": Vector3(3.2, 1.2, -2.5),
			"look": Vector3(0, 0.9, 0), "dur": 7.0, "fov": 60.0,
			"title": _tr("TRL_6_T"), "sub": _tr("TRL_6"), "text_delay": 0.6,
		})
		v.apply_input(0.0, 0.0, 1.0, true)
		v.test_drive = false
		AudioBus.play_music("credits", -9.0)

	# 7. Скупщик
	var stand: Node3D = w.find_marker(Types.District.VENDORS, "VendorStand_vendor_tiny")
	if stand:
		var spot: Node3D = stand.get_node_or_null("PlayerSpot")
		var counter: Node3D = stand.get_node_or_null("Counter")
		p.global_position = (spot.global_position if spot else stand.global_position) + Vector3(0, 1.0, 0)
		p.look_toward(counter.global_position if counter else stand.global_position)
		var pick: ItemDef = null
		for d in Registry.all_items():
			if d.value_base >= 150 and d.value_base <= 500 and not d.is_fragile() and not d.illegal:
				pick = d
				break
		var cpos: Vector3 = counter.global_position if counter else stand.global_position
		var item: ItemBody = Net.spawn_item(pick.id, Transform3D(Basis(), cpos + Vector3(0, 1.25, 0)))
		await _wait(1.0)
		if item:
			w.handle_action(p.peer_id, "vendor_offer", {"stand": "vendor_tiny", "nid": item.net_id, "amount": int(item.current_value() * 1.8)})
		var vdir := (cpos - p.global_position)
		vdir.y = 0.0
		vdir = vdir.normalized()
		var side := Vector3(-vdir.z, 0, vdir.x)
		# через плечо игрока: в кадре скупщик, вещь на прилавке и полоска торга (худ — часть шоу)
		var pp := p.global_position
		await _shot({
			# головы у персонажей теперь огромные — камера дальше, чтобы не влезать в затылок
			"from": pp - vdir * 2.4 + side * 1.9 + Vector3(0, 2.1, 0), "to": pp - vdir * 1.7 + side * 1.4 + Vector3(0, 1.9, 0),
			"look": cpos + vdir * 0.3 + Vector3(0, 1.2, 0), "look_to": cpos + Vector3(0, 1.3, 0), "dur": 5.5, "fov": 58.0,
			"title": _tr("TRL_7_T"), "text_delay": 0.6,
		})
		var ven = w.system("Vendors")
		if ven and ven.ui and ven.ui.has_method("close"):
			ven.ui.close()
		if item and is_instance_valid(item):
			Net.despawn_item(item.net_id)

	# 8. Казино
	var cas = w.system("Casino")
	var table: Node3D = w.find_marker(Types.District.CASINO, "CasinoTable")
	if cas and table:
		p.global_position = table.global_position + Vector3(0, 1.0, 1.6)
		p.look_toward(table.global_position)
		w.handle_action(p.peer_id, "casino_bet", {"amount": 1500, "red": true})
		await _wait(0.5)
		cas.spin()
		await _shot({
			"from": table.global_position + Vector3(2.2, 1.9, -1.4), "to": table.global_position + Vector3(0.9, 1.5, -0.7),
			"look": table.global_position + Vector3(0, 1.0, 0.3), "dur": 6.0, "fov": 55.0,
			"title": _tr("TRL_8_T"), "sub": _tr("TRL_8"), "text_delay": 0.6,
		})

	# 9. Менты
	var pol = w.system("Police")
	if pol:
		var seg := _road_segment(-1)
		var run_from: Vector3 = seg.get("pos", trailer + Vector3(20, 0, 20))
		var dir: Vector3 = seg.get("dir", Vector3(1, 0, 0))
		run_from -= dir * 12.0
		p.global_position = run_from + Vector3(0, 1.0, 0)
		p.look_toward(run_from + dir)
		pol.trigger(Types.PoliceTrigger.THREAT, p.global_position, p)
		pol.trigger(Types.PoliceTrigger.ARSON, p.global_position, p)
		await _wait(1.5)
		p.cine_move = dir
		AudioBus.play_music("police_loop", -8.0)
		await _shot({
			"follow": p, "from": dir * 4.0 + Vector3(1.5, 1.6, 0), "to": dir * 3.2 + Vector3(-1.2, 1.3, 0),
			"look": Vector3(0, 1.2, 0) - dir * 3.0, "dur": 7.0, "fov": 62.0, "shake": 0.4,
			"title": _tr("TRL_9_T"), "sub": _tr("TRL_9"), "text_delay": 0.6,
		})
		p.cine_move = Vector3.ZERO
		p.wanted = 0.0
		p.set_cuffed(false)
		p.in_custody = false
		AudioBus.play_music("credits", -9.0)

	# 10. Ночной город
	if dn:
		dn.time_of_day = 0.965
	var vend_pos := _mk(Types.District.VENDORS, "VendorStand_vendor_tiny")
	if vend_pos == Vector3.ZERO:
		vend_pos = trailer
	await _shot({
		"from": vend_pos + Vector3(14, 3.5, 22), "to": vend_pos + Vector3(4, 2.2, 12),
		"look": vend_pos + Vector3(0, 2.2, 0), "dur": 6.0, "fov": 60.0,
		"title": _tr("TRL_10_T"), "sub": _tr("TRL_10"), "text_delay": 0.5, "fade_out": 1.0,
	})

	# 11. Финальная карточка
	await cine.card("COOONTAINER", _tr("TRL_END"), 4.0)
	await _wait(0.5)
	cine.end()
	print("[trailer] DONE")
	load("res://tools/Smoke.gd").cleanup_test_slot()
	await _wait(0.3)
	get_tree().quit()


## Центр и направление дорожного сегмента (самый длинный, если idx вне диапазона).
func _road_segment(idx: int) -> Dictionary:
	var roads = w.city.roads()
	if roads == null or roads.segments.is_empty():
		return {}
	var best_i := -1
	var best_len := 0.0
	for i in roads.segments.size():
		var s: Vector4 = roads.segments[i]
		var l := Vector2(s.z - s.x, s.w - s.y).length()
		if l > best_len:
			best_len = l
			best_i = i
	var use_i := idx if idx >= 0 and idx < roads.segments.size() else best_i
	var sg: Vector4 = roads.segments[use_i]
	var a := Vector3(sg.x, 0, sg.y)
	var b := Vector3(sg.z, 0, sg.w)
	var d := (b - a).normalized()
	var c := (a + b) * 0.5
	c.y = maxf(roads.road_top_at(c), 0.0)
	return {"pos": c, "dir": d, "len": (b - a).length()}


## Старт заезда: 16 м до первой кочки по её дороге, носом на кочку. {} если дорог нет.
func _road_run_start(_v) -> Dictionary:
	var roads = w.city.roads()
	if roads == null or roads.bumps.is_empty() or roads.segments.is_empty():
		return {}
	var bp: Vector4 = roads.bumps[0]
	var bump := Vector3(bp.x, 0, bp.y)
	for s in roads.segments:
		var a := Vector3(s.x, 0, s.y)
		var b := Vector3(s.z, 0, s.w)
		var d := b - a
		var len := d.length()
		if len < 0.01:
			continue
		d /= len
		var rel := bump - (a + b) * 0.5
		var along := rel.dot(d)
		var across := rel.dot(Vector3(-d.z, 0, d.x))
		if absf(along) <= len * 0.5 and absf(across) <= roads.width * 0.5:
			# едем вдоль сегмента к кочке с той стороны, где больше места
			var dir := d if along > 0.0 else -d
			var pos := bump - dir * 16.0
			pos.y = maxf(roads.road_top_at(pos), 0.0) + 0.7
			return {"pos": pos, "dir": dir}
	return {}


## Пока идёт шот аукциона — игрок перебивает хантеров, чтобы шёл бой вёсел.
func _bid_loop(anchor: LotAnchor, auc, sec: float) -> void:
	var t := 0.0
	while t < sec:
		await _wait(0.9)
		t += 0.9
		var s = auc.session_for(anchor)
		if s == null or s.state != Auction.State.BIDDING:
			continue
		if not (s.leader_kind == 1 and s.leader_id == p.peer_id):
			w.handle_action(p.peer_id, "bid", {"amount": auc.required_bid(s)})
