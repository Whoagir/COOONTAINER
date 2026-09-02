extends Node
## Автоплейтест: бот проходит игровой цикл без человека.
##   godot --headless --path . -- --playtest
##   godot --path . -- --playtest --shots      (с окном + скриншоты этапов)
## Этапы: трейлер → ангар → аукцион (ставка, молот) → вывоз (вынести лут) → скупщик (оффер + полоска)
##        → казино → полиция → тачка → дом. На каждом этапе — проверки и лог.

signal stage_done(name: String, ok: bool, info: String)

const STAGE_TIMEOUT := 90.0

var results: Array = []
var _stage := 0
var _t := 0.0
var _stage_t := 0.0
var _shots := false
var _shots_dir := ""
var _shot_n := 0
var p: Player
var w
var _bid_sent := false
var _bid_kbd_tested := false
var _carried: Array = []
var _sold := 0
var _log: Array[String] = []


static func wanted() -> bool:
	return OS.get_cmdline_user_args().has("--playtest")


func _ready() -> void:
	_shots = OS.get_cmdline_user_args().has("--shots") and DisplayServer.get_name() != "headless"
	if _shots:
		_shots_dir = OS.get_user_data_dir().path_join("playtest")
		DirAccess.make_dir_recursive_absolute(_shots_dir)
	w = Game.world
	_say("playtest start: items=%d lots=%d hunters=%d vendors=%d" % [Registry.items.size(), Registry.lots.size(), Registry.hunters.size(), Registry.vendors.size()])


func _say(s: String) -> void:
	_log.append(s)
	print("[play] " + s)


func _ok(name: String, ok: bool, info: String = "") -> void:
	results.append({"stage": name, "ok": ok, "info": info})
	_say("%s %s %s" % ["PASS" if ok else "FAIL", name, info])
	_shot(name)


func _shot(tag: String) -> void:
	if not _shots:
		return
	var img := get_viewport().get_texture().get_image()
	img.save_png(_shots_dir.path_join("%02d_%s.png" % [_shot_n, tag.replace(" ", "_")]))
	_shot_n += 1


func _process(delta: float) -> void:
	_t += delta
	_stage_t += delta
	if p == null:
		p = w.local_player()
		if p == null:
			return
		p.set_process_input(false) # ботом рулим сами
	if _busy:
		return
	_busy = true
	match _stage:
		0: await _s_boot()
		1: await _s_grab()
		2: await _s_travel_hangar()
		3: await _s_auction()
		4: await _s_clearout()
		5: await _s_vendor()
		6: await _s_casino()
		7: await _s_police()
		8: await _s_vehicle()
		9: await _s_janitor()
		10: await _s_jobs()
		11: await _s_house()
		12: _finish()
	_busy = false


var _busy := false
var _started := false


func _next() -> void:
	_stage += 1
	_stage_t = 0.0
	_bid_sent = false
	_bid_kbd_tested = false


func _timeout(name: String, limit: float = STAGE_TIMEOUT) -> bool:
	if _stage_t > limit:
		_ok(name, false, "timeout %.0fs" % limit)
		_next()
		return true
	return false


# ------------------------------------------------------------------ этапы

func _s_boot() -> void:
	if _stage_t < 1.5:
		return
	var systems := ["Liquids", "Fire", "Auction", "ClearOut", "Vendors", "Casino", "Police", "Janitor", "Vehicles", "Locksmith", "TrailerHub", "Gags", "DayNight", "Jobs", "Interactables", "HomeClutter"]
	var missing: Array = []
	for s in systems:
		if w.system(s) == null:
			missing.append(s)
	_ok("systems", missing.is_empty(), "missing=%s" % str(missing))
	var districts: Array = w.city.districts() if w.city.has_method("districts") else []
	_ok("districts", districts.size() >= 8, "%d districts" % districts.size())
	var anchors := get_tree().get_nodes_in_group("lot_anchors")
	_ok("lot_anchors", anchors.size() >= 10, "%d anchors" % anchors.size())
	var home_n := 0
	for nid in Net.items:
		var hb: ItemBody = Net.items[nid] as ItemBody
		if hb != null and is_instance_valid(hb) and bool(hb.get_meta("home", false)):
			home_n += 1
	_ok("home_clutter", home_n >= 30, "%d home items" % home_n)
	_ok("player_spawn", p != null and p.global_position.length() < 500.0, str(p.global_position.round()))
	var inter = w.system("Interactables")
	var vm: Node = inter.get_node_or_null("Vending_0") if inter else null
	if vm and vm.has_method("interact"):
		var n0: int = Net.items.size()
		Economy.set_pot(maxi(Economy.pot, 20), "playtest")
		var pot0: int = Economy.pot
		vm.interact(p)
		if Net.items.size() <= n0:
			vm.interact(p)
		_ok("vending_buy", Economy.pot == pot0 - 2 and Net.items.size() > n0, "pot %d→%d items +%d" % [pot0, Economy.pot, Net.items.size() - n0])
	else:
		_ok("vending_buy", false, "no vending")
	_next()


func _s_grab() -> void:
	# спавним хрупкое и тяжёлое, проверяем хват/бросок/разлом/карман
	if _stage_t < 0.2:
		return
	var vase := Registry.random_item_with_facet(Types.Facet.FRAGILE)
	var pocketable: ItemDef = null
	for d in Registry.all_items():
		if Registry.archetype_for(d).size_class == Types.SizeClass.POCKET:
			pocketable = d
			break
	p.hands.host_release_all()
	var pos := p.global_position + Vector3(0, 1.2, 0) - p.head.global_basis.z * 1.2
	var b1 = Net.spawn_item(vase.id, Transform3D(Basis(), pos))
	var b2 = Net.spawn_item(pocketable.id, Transform3D(Basis(), pos + Vector3(0.4, 0, 0))) if pocketable else null
	await get_tree().physics_frame
	p.hands.host_grab(b1, 0)
	_ok("grab", p.hands.any_held() == b1, b1.def.id)
	# вещь должна сесть в ладонь, а не висеть в воздухе перед лицом
	for i in 8:
		await get_tree().physics_frame
	var palm_d: float = b1.global_position.distance_to(p.hands.hand_r.global_position)
	_ok("grab_in_palm", palm_d < 0.85, "d=%.2f" % palm_d)
	p.hands.active_hand = 1
	_ok("swap_hand", p.hands.active_hand == 1, "active=%d" % p.hands.active_hand)
	p.hands.active_hand = 0
	# короткий хват: точка за REACH недоступна
	_ok("reach_short", not p.can_reach_point(p.shoulder_world(0) + Vector3(0, 0, -3.5)), "reach=%.2f" % Hands.REACH)
	if b2:
		p.host_pocket_put(b2)
		_ok("pocket", p.pockets.has(b2), b2.def.id)
	# TEAM-вещь одному — должно быть медленно, но можно
	var team_def: ItemDef = null
	for d in Registry.all_items():
		if Registry.archetype_for(d).size_class == Types.SizeClass.TEAM:
			team_def = d
			break
	if team_def:
		var b3 = Net.spawn_item(team_def.id, Transform3D(Basis(), pos + Vector3(0.6, 0, 0)))
		await get_tree().physics_frame
		p.hands.host_release_all()
		p.hands.host_grab(b3, 0)
		for i in 4:
			await get_tree().physics_frame
		_ok("team_carry", p.hands.any_held() == b3 and p.encumbrance <= 0.5, "enc=%.2f size=%d" % [p.encumbrance, b3.arch.size_class])
		p.hands.host_release_all()
		Net.despawn_item(b3.net_id)
	# разлом
	p.hands.host_grab(b1, 0)
	p.hands.host_release_body(b1, 20.0)
	await get_tree().create_timer(1.2).timeout
	_ok("shatter", b1.integrity == Types.Integrity.SHARDS or b1.integrity == Types.Integrity.CHIPPED, "integrity=%d" % b1.integrity)
	# CHIPPED (бросок пришёлся вскользь) — цена лишь падает; SHARDS — копейки
	var v_after: int = b1.current_value()
	_ok("shard_value", (v_after <= 5) if b1.integrity == Types.Integrity.SHARDS else (v_after < b1.def.value_base), "$%d int=%d" % [v_after, b1.integrity])
	# жидкость + огонь
	var liq_def: ItemDef = null
	for d in Registry.all_items():
		if d.liquid_id == Types.LiquidId.GASOLINE:
			liq_def = d
			break
	if liq_def:
		var b4 = Net.spawn_item(liq_def.id, Transform3D(Basis(), pos))
		b4.is_open = true
		b4.spill(0.6)
		await get_tree().create_timer(0.5).timeout
		var liq = w.system("Liquids")
		_ok("puddle", liq.puddles.size() > 0, "%d puddles" % liq.puddles.size())
		liq.ignite_at(b4.global_position)
		await get_tree().create_timer(0.5).timeout
		var burning := 0
		for pd in liq.puddles:
			if pd.burning:
				burning += 1
		_ok("fire", burning > 0, "%d burning" % burning)
		Net.despawn_item(b4.net_id)
	# костёр у трейлера — настоящий очаг: бочка с маслом в нём вспыхивает
	var fire_sys = w.system("Fire")
	var camp: Node3D = w.find_marker(Types.District.TRAILER_PARK, "Campfire")
	if fire_sys and camp and Registry.item("oil_barrel"):
		var oil: ItemBody = Net.spawn_item("oil_barrel", Transform3D(Basis(), camp.global_position + Vector3(0, 0.6, 0)))
		oil.freeze = true
		await get_tree().create_timer(2.0).timeout
		_ok("campfire_ignites", is_instance_valid(oil) and (oil.lit or oil.burnt), "hearths=%d lit=%s" % [fire_sys.hearths.size(), str(oil.lit if is_instance_valid(oil) else "?")])
		if is_instance_valid(oil):
			Net.despawn_item(oil.net_id)
	_next()


func _s_travel_hangar() -> void:
	var hangar = w.city.district_root(Types.District.HANGAR)
	if hangar == null:
		_ok("travel_hangar", false, "no hangar district")
		_next()
		return
	var anchors: Array = hangar.lot_anchors()
	if anchors.is_empty():
		_ok("travel_hangar", false, "hangar has no LotAnchor")
		_next()
		return
	var target: Node3D = anchors[0].marker("PlayerStand")
	p.global_position = target.global_position + Vector3(0, 1.0, 0)
	p.velocity = Vector3.ZERO
	await get_tree().physics_frame
	_ok("travel_hangar", true, "teleported to %s" % anchors[0].name)
	_next()


func _s_auction() -> void:
	var auc = w.system("Auction")
	if auc == null:
		_ok("auction", false, "no Auction system")
		_next()
		return
	var anchors := get_tree().get_nodes_in_group("lot_anchors")
	var anchor = null
	for a in anchors:
		if a.get_parent() and w.city.district_at(a.global_position) and w.city.district_at(a.global_position).district_id == Types.District.HANGAR:
			anchor = a
			break
	if anchor == null and not anchors.is_empty():
		anchor = anchors[0]
	if _stage_t < 0.3:
		return
	# стартуем аукцион любым доступным путём
	if not _started:
		_started = true
		Economy.set_pot(8000, "playtest")
		var started: bool = auc.start_session(anchor)
		_ok("auction_start", started, "anchor=%s preset=%s" % [anchor.name, str(auc.current_preset(anchor).id if auc.current_preset(anchor) else "-")])
		return
	var state: int = auc.state_of(anchor)
	var s = auc.session_for(anchor)
	if state == 2 and s != null and not _bid_kbd_tested:
		await _test_bid_keyboard(auc, s)
	# ставим ставку каждый раз, когда сессия в BIDDING и лидер не мы
	if state == 2 and s != null:
		var need: int = auc.required_bid(s)
		if need <= 6000 and not (s.leader_kind == 1 and s.leader_id == p.peer_id):
			w.handle_action(p.peer_id, "bid", {"amount": need})
			if not _bid_sent:
				_bid_sent = true
				_say("first bid %d" % need)
	if Game.world_mode == Types.WorldMode.CLEAR_OUT:
		_ok("auction_win", true, "won → CLEAR_OUT, pot=%d" % Economy.pot)
		_next()
		return
	if _stage_t > 70.0:
		_ok("auction_win", false, "mode=%d state=%s bid_sent=%s" % [Game.world_mode, Auction.STATE_NAMES[state], str(_bid_sent)])
		_next()


func _inject_key(code: int) -> void:
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.echo = false
	ev.keycode = code
	ev.physical_keycode = code
	Input.parse_input_event(ev)
	if p.is_processing_input():
		p._input(ev)


func _test_bid_keyboard(auc: Auction, s: Auction.Session) -> void:
	_bid_kbd_tested = true
	p.paddle_up = true
	p._update_paddle_visual()
	await get_tree().physics_frame
	if Game.world and Game.world.hud and Game.world.hud.has_method("set_bid_paddle_up"):
		Game.world.hud.set_bid_paddle_up(true)
	var had_input := p.is_processing_input()
	p.set_process_input(true)
	for code in [KEY_1, KEY_5, KEY_0]:
		_inject_key(code)
	var paddle = p.paddle()
	var typed: int = int(paddle.value) if paddle else -1
	_inject_key(KEY_ENTER)
	await get_tree().create_timer(0.5).timeout
	var ok150: bool = s.has_bids and s.current_bid == 150 and s.leader_kind == 1 and s.leader_id == p.peer_id
	_ok("auction_bid_type", ok150, "typed=%d bid=%d req=%d leader=P%d" % [typed, s.current_bid, auc.required_bid(s), s.leader_id if s.has_bids else 0])
	var prev: int = s.current_bid
	w.handle_action(p.peer_id, "bid", {"amount": 1})
	await get_tree().create_timer(0.1).timeout
	_ok("auction_bid_reject", s.current_bid == prev, "bid still $%d" % s.current_bid)
	p.set_process_input(had_input)
	if DisplayServer.get_name() != "headless":
		var dir := OS.get_user_data_dir().path_join("shots")
		DirAccess.make_dir_recursive_absolute(dir)
		get_viewport().get_texture().get_image().save_png(dir.path_join("bid_hud.png"))


func _s_clearout() -> void:
	var co = w.system("ClearOut")
	if _stage_t < 0.5:
		return
	# выносим всё, что помечено лотом, наружу
	var moved := 0
	for nid in Net.items:
		var b = Net.items[nid]
		if is_instance_valid(b) and b.lot_id != "" and b.nested_in == null:
			b.global_position = p.global_position + Vector3(randf_range(-2, 2), 0.3, randf_range(-2, 2)) + Vector3(0, 0, 6)
			b.linear_velocity = Vector3.ZERO
			_carried.append(b)
			moved += 1
			if moved >= 12:
				break
	_ok("clearout_haul", moved > 0 or Game.world_mode != Types.WorldMode.CLEAR_OUT, "%d items moved out" % moved)
	if co and co.has_method("try_finish_by"):
		co.try_finish_by(p)
	elif co and co.has_method("finish"):
		co.finish()
	await get_tree().create_timer(1.0).timeout
	_ok("clearout_finish", Game.world_mode != Types.WorldMode.CLEAR_OUT, "mode=%d" % Game.world_mode)
	_next()


func _s_vendor() -> void:
	var ven = w.system("Vendors")
	if ven == null:
		_ok("vendor", false, "no Vendors system")
		_next()
		return
	if _stage_t < 0.3:
		return
	var stand: Node3D = w.find_marker(Types.District.VENDORS, "VendorStand_vendor_tiny")
	if stand == null:
		_ok("vendor", false, "no VendorStand_vendor_tiny")
		_next()
		return
	var spot: Node3D = stand.get_node_or_null("PlayerSpot")
	var counter: Node3D = stand.get_node_or_null("Counter")
	p.global_position = (spot.global_position if spot else stand.global_position) + Vector3(0, 1.0, 0)
	await get_tree().physics_frame
	# кладём вещь на прилавок
	# продаём заведомо дорогую целую вещь, чтобы проверить арифметику
	var pick: ItemDef = null
	for d in Registry.all_items():
		if d.value_base >= 120 and d.value_base <= 400 and not d.is_fragile() and not d.illegal:
			pick = d
			break
	if pick == null:
		pick = Registry.all_items()[0]
	var item: ItemBody = Net.spawn_item(pick.id, Transform3D(Basis(), p.global_position + Vector3(0, 1.5, 0)))
	var drop_pos: Vector3 = (counter.global_position + Vector3(0, 1.2, 0)) if counter else p.global_position + Vector3(0, 1.2, 0)
	item.global_position = drop_pos
	item.linear_velocity = Vector3.ZERO
	await get_tree().create_timer(1.2).timeout
	var pot_before := Economy.pot
	var fair := item.current_value(Registry.vendor("vendor_tiny"))
	var nid := item.net_id
	# оффер + полоска
	w.handle_action(p.peer_id, "vendor_offer", {"stand": "vendor_tiny", "nid": nid, "amount": fair})
	await get_tree().create_timer(0.6).timeout
	w.handle_action(p.peer_id, "haggle_result", {"nid": nid, "hit": true, "precision": 0.95})
	await get_tree().create_timer(0.8).timeout
	var gained := Economy.pot - pot_before
	_sold = gained
	_ok("vendor_sale", gained > 0, "%s base=$%d fair=$%d gained=+$%d" % [pick.id, pick.value_base, fair, gained])
	_ok("vendor_despawn", not Net.items.has(nid), "item removed from world")
	# крупную вещь на прилавок не поставишь — жёлтая зона на земле перед ним тоже продаёт
	var st: Vendors.Stand = ven.stands.get("vendor_tiny")
	if st:
		var zone_c: Vector3 = st.root.get_meta("sell_zone_center", st.counter_pos() + st.front() * 1.6)
		var floor_item: ItemBody = Net.spawn_item(pick.id, Transform3D(Basis(), zone_c + Vector3(0, 0.6, 0)))
		await get_tree().create_timer(1.5).timeout
		var listed := st.sellable().has(floor_item)
		var pot2 := Economy.pot
		if listed:
			w.handle_action(p.peer_id, "vendor_offer", {"stand": "vendor_tiny", "nid": floor_item.net_id, "amount": floor_item.current_value(Registry.vendor("vendor_tiny"))})
			await get_tree().create_timer(1.0).timeout
		_ok("vendor_floor_zone", listed and Economy.pot > pot2, "listed=%s +$%d" % [str(listed), Economy.pot - pot2])
		if is_instance_valid(floor_item):
			Net.despawn_item(floor_item.net_id)
	# фобия: мышь на прилавок к vendor_tiny (§11)
	var mice: Array = Registry.items_with_tag("mouse")
	if not mice.is_empty():
		var m = Net.spawn_item(mice[0].id, Transform3D(Basis(), drop_pos))
		await get_tree().create_timer(1.5).timeout
		_ok("vendor_phobia", Achievements.is_unlocked("phobia"), "mouse on the counter of a mouse-phobic vendor")
		if is_instance_valid(m):
			Net.despawn_item(m.net_id)
	# вскрывальщик: запертую вещь — на верстак
	var locksmith = w.system("Locksmith")
	var locked_def: ItemDef = null
	for d in Registry.all_items():
		if d.has_facet(Types.Facet.LOCKED):
			locked_def = d
			break
	if locksmith and locked_def and locksmith.bench:
		var lb = Net.spawn_item(locked_def.id, Transform3D(Basis(), locksmith.bench.global_position + Vector3(0, 1.3, 0)), {"lk": true})
		p.global_position = locksmith.bench.global_position + Vector3(0, 1.0, 1.2)
		await get_tree().create_timer(1.2).timeout
		Economy.add(500, "playtest")
		locksmith._on_interact(p)
		await get_tree().create_timer(4.5).timeout
		_ok("locksmith", is_instance_valid(lb) and (not lb.locked or lb.integrity != Types.Integrity.WHOLE), "locked=%s integrity=%d" % [str(lb.locked if is_instance_valid(lb) else "?"), lb.integrity if is_instance_valid(lb) else -1])
		if is_instance_valid(lb):
			Net.despawn_item(lb.net_id)
	_next()


func _s_casino() -> void:
	var cas = w.system("Casino")
	if cas == null or _stage_t < 0.3:
		if cas == null:
			_ok("casino", false, "no Casino system")
			_next()
		return
	var table: Node3D = w.find_marker(Types.District.CASINO, "CasinoTable")
	if table:
		p.global_position = table.global_position + Vector3(0, 1.0, 1.5)
		await get_tree().physics_frame
	Economy.set_pot(maxi(Economy.pot, 500), "playtest")
	var before := Economy.pot
	w.handle_action(p.peer_id, "casino_bet", {"amount": 100, "red": true})
	await get_tree().create_timer(0.4).timeout
	_ok("casino_bet", Economy.pot == before - 100, "pot %d → %d, bets=%d" % [before, Economy.pot, cas.pot_bets.size()])
	cas.spin()
	await get_tree().create_timer(float(Casino.SPIN_SEC) + 1.5).timeout
	_ok("casino_spin", not cas.spinning and cas.pot_bets.is_empty(), "pot after=%d" % Economy.pot)
	_next()


func _s_police() -> void:
	var pol = w.system("Police")
	if pol == null:
		_ok("police", false, "no Police system")
		_next()
		return
	if _stage_t < 0.3:
		return
	pol.trigger(Types.PoliceTrigger.THREAT, p.global_position, p)
	await get_tree().create_timer(3.0).timeout
	var cops := 0
	for n in w.npcs_root.get_children():
		if n is Npc and n.npc_group == "cop":
			cops += 1
	_ok("police_dispatch", cops > 0 or p.wanted > 0.0, "cops=%d wanted=%.2f" % [cops, p.wanted])
	# арест
	pol.trigger(Types.PoliceTrigger.ARSON, p.global_position, p)
	await get_tree().create_timer(4.0).timeout
	_ok("police_heat", p.wanted > 0.5 or p.cuffed or p.in_custody, "wanted=%.2f cuffed=%s custody=%s" % [p.wanted, str(p.cuffed), str(p.in_custody)])
	p.wanted = 0.0
	p.set_cuffed(false)
	p.in_custody = false
	# решётка камеры: на старте поднята (проём свободен), при посадке опускается, после срока снова поднимается
	var door: Node3D = w.find_marker(Types.District.POLICE, "JailDoor")
	if door:
		var base: float = door.get_meta("base_y", door.position.y)
		var open_y := base + Police.DOOR_SLIDE
		_ok("jail_open_start", absf(door.position.y - open_y) < 0.05, "y=%.2f open=%.2f" % [door.position.y, open_y])
		# гасим дело/арест из предыдущих проверок, чтобы машина с ментами не закрыла дверь посреди теста
		for c in pol._cases.values().duplicate():
			pol._end_case(c, "playtest")
		for peer in pol._custody.keys().duplicate():
			pol._release(peer, "playtest")
		await get_tree().create_timer(1.5).timeout
		pol._set_jail_door(true)
		await get_tree().create_timer(1.5).timeout
		_ok("jail_closes", absf(door.position.y - base) < 0.05, "y=%.2f base=%.2f" % [door.position.y, base])
		pol._set_jail_door(false)
		await get_tree().create_timer(1.5).timeout
		_ok("jail_reopens", absf(door.position.y - open_y) < 0.05, "y=%.2f open=%.2f" % [door.position.y, open_y])
	_next()


func _s_vehicle() -> void:
	var veh = w.system("Vehicles")
	if veh == null:
		_ok("vehicles", false, "no Vehicles system")
		_next()
		return
	if _stage_t < 0.3:
		return
	var count := 0
	if "vehicles" in veh:
		count = veh.vehicles.size()
	_ok("vehicles_present", count > 0, "%d vehicles" % count)
	if count > 0:
		var v = veh.vehicles.values()[0]
		var bed: Node3D = v.get_node_or_null("Bed") if v.has_node("Bed") else v
		var loaded := 0
		for b in _carried:
			if is_instance_valid(b):
				b.global_position = bed.global_position + Vector3(randf_range(-0.3, 0.3), 1.0, randf_range(-0.5, 0.5))
				b.linear_velocity = Vector3.ZERO
				loaded += 1
				if loaded >= 4:
					break
		await get_tree().create_timer(1.5).timeout
		var still := 0
		for b in _carried:
			if is_instance_valid(b) and b.global_position.distance_to(v.global_position) < 6.0:
				still += 1
		_ok("vehicle_bed", loaded == 0 or still > 0, "%d/%d items in bed" % [still, loaded])
	_next()


func _s_janitor() -> void:
	var jan = w.system("Janitor")
	if jan == null:
		_ok("janitor", false, "no Janitor system")
		_next()
		return
	if _stage_t < 0.3:
		return
	Economy.set_pot(0, "playtest")
	jan.offer_job()
	await get_tree().create_timer(0.8).timeout
	_ok("janitor_boss", jan.boss != null, "boss spawned")
	if jan.boss:
		p.global_position = jan.boss.global_position + Vector3(0, 1.0, 1.5)
		await get_tree().physics_frame
		var started: bool = jan.try_start(p)
		await get_tree().create_timer(1.2).timeout
		_ok("janitor_start", started and jan.active, "mode=%d junk=%d" % [Game.world_mode, jan._junk.size()])
		# выносим мусор наружу и моем
		var out := 0
		for nid in Net.items.keys():
			var b = Net.items.get(nid)
			if is_instance_valid(b) and b.lot_id == Janitor.LOT_ID:
				b.global_position = jan.anchor.cell().global_position + Vector3(0, 0.4, 14.0)
				b.dirt = 0.0
				out += 1
		await get_tree().create_timer(1.5).timeout
		jan.try_finish_by(p)
		await get_tree().create_timer(1.0).timeout
		_ok("janitor_pay", Economy.pot > 0 and not jan.active, "payout=$%d (вынесено %d)" % [Economy.pot, out])
	_next()


func _s_jobs() -> void:
	var jobs = w.system("Jobs")
	if jobs == null:
		_ok("jobs_system", false, "no Jobs system")
		_next()
		return
	if _stage_t < 0.5:
		return
	_ok("jobs_system", true, "Jobs node ok")
	jobs.playtest_set_offers(["flyers", "trash", "delivery"])
	_ok("jobs_offers", jobs.offer_count() == 3, "%d offers" % jobs.offer_count())
	var pot_before := Economy.pot
	w.handle_action(p.peer_id, "job_take", {"id": "flyers"})
	await get_tree().create_timer(0.3).timeout
	for wp in jobs.flyer_waypoints():
		p.global_position = wp + Vector3(0, 1.0, 0)
		await get_tree().create_timer(0.35).timeout
	await get_tree().create_timer(0.8).timeout
	var flyers_gain := Economy.pot - pot_before
	_ok("jobs_flyers", flyers_gain >= 50, "pot +$%d" % flyers_gain)
	pot_before = Economy.pot
	jobs.playtest_set_offers(["trash", "flyers", "delivery"])
	w.handle_action(p.peer_id, "job_take", {"id": "trash"})
	await get_tree().create_timer(0.3).timeout
	var bin: Area3D = jobs.trash_bin_at(0)
	var bin_pos: Vector3 = bin.global_position if bin else p.global_position
	for i in 6:
		var cheap: ItemDef = null
		for d in Registry.all_items():
			if d.value_base <= 30 and not d.is_cash():
				cheap = d
				break
		if cheap == null:
			break
		var b: ItemBody = Net.spawn_item(cheap.id, Transform3D(Basis(), bin_pos + Vector3(randf_range(-0.2, 0.2), 0.5, randf_range(-0.2, 0.2))))
		if b:
			b.set_meta("street", true)
		await get_tree().physics_frame
	await get_tree().create_timer(1.2).timeout
	var trash_gain := Economy.pot - pot_before
	_ok("jobs_trash", trash_gain >= 45, "pot +$%d" % trash_gain)
	_next()


func _s_house() -> void:
	if _stage_t < 0.3:
		return
	# прогрессия районов (§12): заработок открывает склады → гаражи → порт
	var before_unlocked := Game.is_district_unlocked(Types.District.STORAGE)
	Economy.set_pot(0, "playtest")
	Economy.add(300, "playtest_earn")
	var storage_ok := Game.is_district_unlocked(Types.District.STORAGE)
	Economy.add(7000, "playtest_earn")
	var port_ok := Game.is_district_unlocked(Types.District.PORT) and Game.is_district_unlocked(Types.District.GARAGES)
	_ok("district_progression", storage_ok and port_ok, "storage(before=%s) garages+port after $7300 earned; unlocked=%s" % [str(before_unlocked), str(Game.save["unlocked_districts"])])
	Economy.set_pot(Game.HOUSE_PRICE + 100, "playtest")
	var ok: bool = Game.try_buy_house()
	await get_tree().create_timer(0.5).timeout
	_ok("buy_house", ok and Game.save.get("won", false), "mode=%d" % Game.world_mode)
	_ok("achievement_moved_out", Achievements.is_unlocked("moved_out"), "")
	_next()


func _finish() -> void:
	var pass_n := 0
	var fail_n := 0
	var failed: Array = []
	for r in results:
		if r["ok"]:
			pass_n += 1
		else:
			fail_n += 1
			failed.append("%s (%s)" % [r["stage"], r["info"]])
	print("\n=== PLAYTEST: %d pass, %d fail ===" % [pass_n, fail_n])
	for f in failed:
		print("  FAIL: %s" % f)
	print("ачивок открыто: %d" % (Game.save.get("achievements", []) as Array).size())
	print("статы: %s" % str(Game.save.get("stats", {})))
	if _shots:
		print("скриншоты: %s" % _shots_dir)
	load("res://tools/Smoke.gd").cleanup_test_slot()
	get_tree().quit(0 if fail_n == 0 else 2)
