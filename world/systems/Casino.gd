class_name Casino
extends Node3D
## Казино (§13): отдельная дыра. Вещь и/или котёл на красное/чёрное. EV ощутимо против игрока:
## красное 42%, чёрное 42%, зелёное 16% — дом забирает всё. Проигрыш на глазах пати (тост всем).
##
## Действия (клиент → хост): casino_bet {amount, red}
## События (хост → все):     casino_open {peer, max} · casino_spin {outcome, dur} ·
##                           casino_result {outcome, won[names], lost[names], pot_win, pot_lost, total_win, total_lost}
## Маркеры (район CASINO):    CasinoTable/{BetZoneRed, BetZoneBlack, Wheel, DealerSpot, CasinoPotSlot}

enum Outcome { RED, BLACK, GREEN }

const SPIN_SEC := 5.0
const P_RED := 0.42
const P_BLACK := 0.42
const BIG := 200
const UI_SCENE := "res://ui/haggle_bar/HaggleBar.tscn"

var table: Node3D
var zone_red: Area3D
var zone_black: Area3D
var wheel: Node3D
var dealer_spot: Node3D
var dealer: Dealer
var bets_red: Array[ItemBody] = []
var bets_black: Array[ItemBody] = []
var pot_bets: Array[Dictionary] = [] # {peer, amount, red}
var spinning := false
var _pending_outcome := 0
var _spin_left := 0.0
var _last_result: Dictionary = {}
var ui: HaggleBar
var interact_node: Vendors.Interactable
var _result_label: Label3D
var _district_players := 0
var _greet_cd := 0.0


func system_name() -> String:
	return "Casino"


func _ready() -> void:
	Net.item_despawned.connect(_on_item_despawned)
	var ui_scene: PackedScene = load(UI_SCENE)
	if ui_scene:
		ui = ui_scene.instantiate() as HaggleBar
		add_child(ui)
		ui.bet_sent.connect(func(amount: int, red: bool):
			Net.request_action("casino_bet", {"amount": amount, "red": red}))
	_deferred_setup()


func _deferred_setup() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var w := Game.world as World
	if w == null:
		return
	var t := w.find_marker(Types.District.CASINO, "CasinoTable")
	if t == null and w.city:
		t = w.city.find_child("CasinoTable", true, false) as Node3D
	if t:
		register_table(t)
	_hook_district()


## Публично: стол из готового корня (дети BetZoneRed/BetZoneBlack/Wheel/DealerSpot — все опциональны).
func register_table(root: Node3D) -> void:
	if root == null or table != null:
		return
	table = root
	zone_red = _zone(root, "BetZoneRed", Vector3(-0.6, 1.1, 0.0), Color(0.8, 0.1, 0.1))
	zone_black = _zone(root, "BetZoneBlack", Vector3(0.6, 1.1, 0.0), Color(0.05, 0.05, 0.05))
	zone_red.body_entered.connect(_on_zone_enter.bind(true))
	zone_red.body_exited.connect(_on_zone_exit.bind(true))
	zone_black.body_entered.connect(_on_zone_enter.bind(false))
	zone_black.body_exited.connect(_on_zone_exit.bind(false))
	wheel = root.find_child("Wheel", true, false) as Node3D
	dealer_spot = root.find_child("DealerSpot", true, false) as Node3D
	var front := _front()
	interact_node = Vendors.Interactable.new(Vector3(1.8, 0.7, 0.18))
	interact_node.name = "CasinoInteract"
	add_child(interact_node)
	interact_node.global_position = table.global_position + front * 0.75 + Vector3(0, 0.85, 0)
	interact_node.global_basis = Basis.looking_at(front, Vector3.UP)
	interact_node.on_interact = _on_interact
	interact_node.on_hint = _hint
	_result_label = Label3D.new()
	_result_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_result_label.font_size = 80
	_result_label.outline_size = 14
	_result_label.pixel_size = 0.006
	_result_label.text = tr("CASINO_SIGN")
	_result_label.modulate = Color(1, 0.85, 0.3)
	add_child(_result_label)
	_result_label.global_position = (wheel.global_position if wheel else table.global_position) + Vector3(0, 2.2, 0)
	_spawn_dealer(front)


func _zone(root: Node3D, name: String, fallback_local: Vector3, tint: Color) -> Area3D:
	var z := root.find_child(name, true, false) as Area3D
	if z == null:
		z = Area3D.new()
		z.name = name + "_rt"
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.0, 0.8, 1.0)
		cs.shape = bs
		z.add_child(cs)
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(0.9, 0.9)
		mi.mesh = pm
		var m := StandardMaterial3D.new()
		m.albedo_color = tint
		mi.material_override = m
		mi.position.y = -0.38
		z.add_child(mi)
		add_child(z)
		z.global_position = root.global_position + fallback_local
	z.collision_layer = z.collision_layer | Types.L_TRIGGER
	z.collision_mask = z.collision_mask | Types.L_ITEM
	z.monitoring = true
	return z


func _front() -> Vector3:
	var f := Vector3.ZERO
	if dealer_spot:
		f = table.global_position - dealer_spot.global_position
	else:
		f = table.global_basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.01 else Vector3.FORWARD


func _spawn_dealer(front: Vector3) -> void:
	dealer = Dealer.new()
	dealer.setup()
	dealer.name = "Dealer"
	var w := Game.world as World
	var parent: Node = w.npcs_root if (w and w.npcs_root) else self
	parent.add_child(dealer)
	var pos := dealer_spot.global_position if dealer_spot else table.global_position - front * 1.2
	dealer.global_position = pos + Vector3(0, 0.05, 0)
	dealer.face(table.global_position + front * 2.0)


# ------------------------------------------------------------------ ставки-вещи (хост)

func _on_zone_enter(b: Node, red: bool) -> void:
	if not (b is ItemBody):
		return
	var arr := bets_red if red else bets_black
	if not arr.has(b):
		arr.append(b as ItemBody)
	if Net.is_host() and not spinning and _greet_cd <= 0.0 and dealer:
		_greet_cd = 8.0
		dealer.line("greet", 2.0)


func _on_zone_exit(b: Node, red: bool) -> void:
	if b is ItemBody:
		(bets_red if red else bets_black).erase(b as ItemBody)


func _on_item_despawned(_nid: int) -> void:
	for arr in [bets_red, bets_black]:
		for i in range(arr.size() - 1, -1, -1):
			if not is_instance_valid(arr[i]):
				arr.remove_at(i)


func _live(arr: Array[ItemBody]) -> Array[ItemBody]:
	var out: Array[ItemBody] = []
	for b in arr:
		if b and is_instance_valid(b) and not b.is_held() and b.nested_in == null:
			out.append(b)
	return out


func has_bets() -> bool:
	return not _live(bets_red).is_empty() or not _live(bets_black).is_empty() or not pot_bets.is_empty()


func _hint(_p: Player) -> String:
	if spinning:
		return tr("CASINO_HINT_SPINNING")
	if has_bets():
		return tr("CASINO_HINT_SPIN")
	return tr("CASINO_HINT_BET")


# ------------------------------------------------------------------ E на столе (хост)

func _on_interact(player: Player) -> void:
	if not Net.is_host() or dealer == null:
		return
	if spinning:
		dealer.line("wait", 2.0)
		return
	if has_bets():
		spin()
		return
	Net.broadcast_event("casino_open", {"peer": player.peer_id, "max": Economy.pot})


func handle_action(peer: int, kind: String, data: Dictionary) -> bool:
	if kind != "casino_bet":
		return false
	if spinning or table == null:
		return true
	var amount := int(data.get("amount", 0))
	var red := bool(data.get("red", true))
	if amount <= 0:
		return true
	var w := Game.world as World
	var p: Player = w.player_of(peer) if w else null
	if p and p.global_position.distance_to(table.global_position) > 8.0:
		return true
	if not Economy.try_spend(amount, "casino_bet"):
		if p:
			p.say(tr("POT_EMPTY"))
		if dealer:
			dealer.line("broke", 2.5)
		return true
	pot_bets.append({"peer": peer, "amount": amount, "red": red})
	Game.stat_add("casino_bets")
	spin()
	return true


## Крутим: крупье орёт, колесо 5 с, дом решает. Итог — всем на глаза.
func spin() -> void:
	if spinning or not Net.is_host():
		return
	spinning = true
	var r := randf()
	var outcome := Outcome.RED if r < P_RED else (Outcome.BLACK if r < P_RED + P_BLACK else Outcome.GREEN)
	_pending_outcome = outcome
	_spin_left = SPIN_SEC
	if dealer:
		dealer.line("spin", 3.0)
	Net.broadcast_event("casino_spin", {"outcome": outcome, "dur": SPIN_SEC})
	await get_tree().create_timer(SPIN_SEC).timeout
	_resolve(outcome)
	spinning = false
	_spin_left = 0.0


func _resolve(outcome: int) -> void:
	var win_items: Array[ItemBody] = []
	var lose_items: Array[ItemBody] = []
	var red_live := _live(bets_red)
	var black_live := _live(bets_black)
	match outcome:
		Outcome.RED:
			win_items = red_live
			lose_items = black_live
		Outcome.BLACK:
			win_items = black_live
			lose_items = red_live
		_:
			lose_items.append_array(red_live)
			lose_items.append_array(black_live)
	var won: Array = []
	var lost: Array = []
	var total_win := 0
	var total_lost := 0
	for b in win_items:
		var v: int = b.current_value()
		total_win += v
		won.append("%s ($%d)" % [b.def.display_name(), v])
		var i := 0
		for id in Registry.bills_for(v):
			var pos: Vector3 = b.global_position + Vector3(randf_range(-0.2, 0.2), 0.25 + 0.02 * i, randf_range(-0.2, 0.2))
			Net.spawn_item(id, Transform3D(Basis(Vector3.UP, randf() * TAU), pos))
			i += 1
	for b in lose_items:
		var v: int = b.current_value()
		total_lost += v
		lost.append("%s ($%d)" % [b.def.display_name(), v])
		if v >= BIG:
			Achievements.unlock("casino_bust")
		for h in b.held_by.duplicate():
			h.host_release_body(b)
		Net.despawn_item(b.net_id)
	var pot_win := 0
	var pot_lost := 0
	for pb in pot_bets:
		var hit := (outcome == Outcome.RED and bool(pb["red"])) or (outcome == Outcome.BLACK and not bool(pb["red"]))
		if hit:
			pot_win += int(pb["amount"]) * 2
			total_win += int(pb["amount"])
		else:
			pot_lost += int(pb["amount"])
			total_lost += int(pb["amount"])
	pot_bets.clear()
	if pot_win > 0:
		Economy.add(pot_win, "casino_win")
	if total_win >= BIG:
		Achievements.unlock("casino_win")
	Game.stat_add("casino_lost", total_lost)
	Game.stat_add("casino_won", total_win)
	_last_result = {
		"outcome": outcome, "won": won, "lost": lost, "pot_win": pot_win, "pot_lost": pot_lost,
		"total_win": total_win, "total_lost": total_lost,
	}
	Net.broadcast_event("casino_result", _last_result)


# ------------------------------------------------------------------ события (все)

func on_net_event(kind: String, data: Dictionary) -> void:
	match kind:
		"casino_open":
			if int(data.get("peer", 0)) == Net.my_id() and ui:
				ui.open_bet(int(data.get("max", Economy.pot)))
		"casino_spin":
			_animate_wheel(int(data.get("outcome", 0)), float(data.get("dur", SPIN_SEC)))
		"casino_result":
			_show_result(data)


func _animate_wheel(outcome: int, dur: float) -> void:
	var pos := wheel.global_position if wheel else (table.global_position if table else Vector3.ZERO)
	AudioBus.play_at("wheel_spin", pos, 0.0, 0.05)
	if _result_label:
		_result_label.text = tr("CASINO_SPINNING")
		_result_label.modulate = Color(1, 0.85, 0.3)
	if wheel:
		var final := 0.0
		match outcome:
			Outcome.RED: final = 0.0
			Outcome.BLACK: final = PI
			_: final = PI * 0.5
		var target := wheel.rotation.y + TAU * 6.0 + final - fposmod(wheel.rotation.y, TAU)
		var tw := create_tween()
		tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(wheel, "rotation:y", target, dur)
	get_tree().create_timer(dur).timeout.connect(func(): AudioBus.play_at("wheel_stop", pos, 2.0, 0.05))


func _show_result(data: Dictionary) -> void:
	var outcome := int(data.get("outcome", 0))
	var color_key := "CASINO_RED" if outcome == Outcome.RED else ("CASINO_BLACK" if outcome == Outcome.BLACK else "CASINO_GREEN")
	if _result_label:
		_result_label.text = tr(color_key)
		_result_label.modulate = Color(1, 0.3, 0.25) if outcome == Outcome.RED else (Color(0.85, 0.85, 0.9) if outcome == Outcome.BLACK else Color(0.3, 1, 0.4))
	if bool(data.get("sync", false)):
		return
	var won: Array = data.get("won", [])
	var lost: Array = data.get("lost", [])
	var pot_win := int(data.get("pot_win", 0))
	var pot_lost := int(data.get("pot_lost", 0))
	var total_win := int(data.get("total_win", 0))
	var total_lost := int(data.get("total_lost", 0))
	var pos := wheel.global_position if wheel else (table.global_position if table else Vector3.ZERO)
	var parts: Array[String] = []
	if not lost.is_empty():
		parts.append(", ".join(PackedStringArray(lost)))
	if pot_lost > 0:
		parts.append("$%d" % pot_lost)
	var msg := tr(color_key)
	if total_lost > 0:
		msg += "  " + tr("CASINO_LOST_TOAST") % ", ".join(PackedStringArray(parts))
		AudioBus.play_at("coin_loss", pos, 2.0)
	if total_win > 0:
		var wparts: Array[String] = []
		if not won.is_empty():
			wparts.append(", ".join(PackedStringArray(won)))
		if pot_win > 0:
			wparts.append("$%d" % pot_win)
		msg += "  " + tr("CASINO_WON_TOAST") % ", ".join(PackedStringArray(wparts))
		AudioBus.play_at("fanfare", pos, 0.0)
	if total_win == 0 and total_lost == 0:
		msg += "  " + tr("CASINO_NOTHING")
	Game.notify.emit(msg, 5.0)
	if Net.is_host() and dealer:
		dealer.line("red" if outcome == Outcome.RED else ("black" if outcome == Outcome.BLACK else "green"), 2.5)
		get_tree().create_timer(2.2).timeout.connect(func():
			if dealer and is_instance_valid(dealer):
				dealer.line("win" if total_win > total_lost else "lose", 3.0))


func send_full_state_to(peer: int) -> void:
	if table == null:
		return
	if not _last_result.is_empty():
		var last := _last_result.duplicate(true)
		last["sync"] = true
		Net.send_event(peer, "casino_result", last)
	if spinning:
		Net.send_event(peer, "casino_spin", {
			"outcome": _pending_outcome,
			"dur": maxf(_spin_left, 0.35),
		})
	elif has_bets():
		Net.send_event(peer, "casino_result", _bets_sync_payload())


func _bets_sync_payload() -> Dictionary:
	var won: Array = []
	var lost: Array = []
	for b in _live(bets_red):
		won.append("%s ($%d)" % [b.def.display_name(), b.current_value()])
	for b in _live(bets_black):
		lost.append("%s ($%d)" % [b.def.display_name(), b.current_value()])
	var pot_red := 0
	var pot_black := 0
	for pb in pot_bets:
		if bool(pb["red"]):
			pot_red += int(pb["amount"])
		else:
			pot_black += int(pb["amount"])
	if pot_red > 0:
		won.append("$%d" % pot_red)
	if pot_black > 0:
		lost.append("$%d" % pot_black)
	return {
		"outcome": _pending_outcome,
		"won": won, "lost": lost,
		"pot_win": 0, "pot_lost": 0, "total_win": 0, "total_lost": 0,
		"sync": true,
	}


# ------------------------------------------------------------------ режим CASINO по району

func _hook_district() -> void:
	var w := Game.world as World
	if w == null:
		return
	var d := w.district_root(Types.District.CASINO)
	if d == null or not d.has_signal("player_entered"):
		return
	d.player_entered.connect(func(_p: Player):
		_district_players += 1
		if Net.is_host() and (Game.world_mode == Types.WorldMode.TRAVEL or Game.world_mode == Types.WorldMode.TRAILER_HUB):
			Game.set_world_mode(Types.WorldMode.CASINO))
	d.player_exited.connect(func(_p: Player):
		_district_players = maxi(0, _district_players - 1)
		if Net.is_host() and _district_players == 0 and Game.world_mode == Types.WorldMode.CASINO:
			Game.set_world_mode(Types.WorldMode.TRAVEL))


func _process(delta: float) -> void:
	if _greet_cd > 0.0:
		_greet_cd -= delta
	if _spin_left > 0.0:
		_spin_left = maxf(0.0, _spin_left - delta)
