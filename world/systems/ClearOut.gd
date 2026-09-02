class_name ClearOut
extends Node3D
## Вывоз (§10): таймер в худе + ор смотрителя, овертайм → дверь вниз, остался внутри →
## менты/штраф/потеря невынесенного, broom clean → залог/ор/ЧС.
## Хост считает, клиенты получают события: clearout_begin / clearout_state / cell_dirt /
## clearout_lost / clearout_done. Запросы игроков: "sweep", "clearout_done".

signal finished(preset_id: String)

enum Phase { IDLE, RUNNING, OVERTIME, DONE }

const OVERTIME_SECONDS := 8.0
const DOOR_REOPEN_NORMAL := 3.0
const DOOR_REOPEN_LOCKED := 20.0
const DIRT_DEPOSIT_AT := 30
const DIRT_BLACKLIST_AT := 70
const DEPOSIT_FINE := 15
const BROADCAST_EVERY := 1.0
const TEMP_CARETAKER_NAME := "ClearOutCaretaker"

var anchor: LotAnchor = null
var preset: LotPreset = null
var winner_peer := 0
var lot_price := 0
var phase: int = Phase.IDLE
var time_left := 0.0
var cell: CellDirt = null

var _broadcast_acc := 0.0
var _yelled: Dictionary = {}
var _tick_acc := 0.0
var _caretaker: Npc = null
var _temp_caretaker := false
var _locked_players: Array = []
var _team_hint_done := false
# худ (у каждого пира свой; хост шлёт авторитетное время 1 Гц, между — тикаем локально)
var _hud_on := false
var _hud_left := 0.0
var _hud_title := "HUD_TIMER"
var _hud_overtime := false


# ====================================================================== общий пол ячейки
## Грязь на полу ячейки 0..100 (§10 broom clean, §13 уборка). Общая для ClearOut и Janitor.
## Метла в руках + внутри ячейки + идёшь → грязь уходит 4/с; ЛКМ ("sweep") — рывком.
class CellDirt extends RefCounted:
	const SWEEP_PER_SEC := 4.0
	const SWEEP_PRESS := 6.0
	const SFX_EVERY := 0.45

	var anchor: LotAnchor
	var dirt_f := 100.0
	var _last_sent := -1
	var _label: Label3D = null
	var _decal: MeshInstance3D = null
	var _decal_mat: StandardMaterial3D = null
	var _sfx_acc := 0.0

	func _init(a: LotAnchor, start := 100.0) -> void:
		anchor = a
		dirt_f = clampf(start, 0.0, 100.0)

	func dirt() -> int:
		return int(ceil(dirt_f))

	func build_visual() -> void:
		if anchor == null or not is_instance_valid(anchor) or _label != null:
			return
		var c := anchor.cell()
		_decal = MeshInstance3D.new()
		_decal.name = "DirtDecal"
		var pm := PlaneMesh.new()
		pm.size = Vector2(anchor.cell_size.x * 0.96, anchor.cell_size.z * 0.96)
		_decal.mesh = pm
		_decal_mat = StandardMaterial3D.new()
		_decal_mat.albedo_color = Color(0.35, 0.28, 0.18, 0.7)
		_decal_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_decal_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_decal.material_override = _decal_mat
		_decal.position = Vector3(0, 0.012, 0)
		c.add_child(_decal)
		_label = Label3D.new()
		_label.name = "DirtLabel"
		_label.font_size = 96
		_label.outline_size = 16
		_label.pixel_size = 0.008
		_label.rotation.x = -PI * 0.5
		_label.position = Vector3(0, 0.03, anchor.cell_size.z * 0.15)
		c.add_child(_label)
		_refresh()

	func destroy() -> void:
		if _label and is_instance_valid(_label):
			_label.queue_free()
		if _decal and is_instance_valid(_decal):
			_decal.queue_free()
		_label = null
		_decal = null

	func set_dirt(v: float) -> void:
		dirt_f = clampf(v, 0.0, 100.0)
		_refresh()

	func _refresh() -> void:
		var d := dirt()
		if _label and is_instance_valid(_label):
			_label.text = tr("CLEAROUT_DIRT") % d
			_label.modulate = Color(0.5, 1.0, 0.5) if d < 30 else (Color(1.0, 0.85, 0.4) if d < 70 else Color(1.0, 0.45, 0.35))
		if _decal_mat:
			_decal_mat.albedo_color.a = 0.72 * float(d) / 100.0

	## Изменилась ли целая часть с последней рассылки (для событий 1 раз на смену процента).
	func take_changed() -> bool:
		var d := dirt()
		if d == _last_sent:
			return false
		_last_sent = d
		return true

	static func holds_broom(p: Player) -> bool:
		return p != null and is_instance_valid(p) and p.hands != null and p.hands.holds_tag("broom") != null

	static func is_sweeping(p: Player, a: LotAnchor) -> bool:
		if p == null or not is_instance_valid(p) or p.dead or a == null:
			return false
		if not holds_broom(p) or not a.is_inside(p.global_position):
			return false
		return Vector3(p.velocity.x, 0.0, p.velocity.z).length() > 1.0

	## Рывок метлой по ЛКМ (запрос "sweep"). true — принято.
	func sweep_by(p: Player) -> bool:
		if not holds_broom(p) or not anchor.is_inside(p.global_position):
			return false
		set_dirt(dirt_f - SWEEP_PRESS)
		AudioBus.play_at("broom_sweep", p.global_position, -4.0, 0.2)
		return true

	## Хост, каждый физ-тик: кто идёт с метлой внутри — тот метёт.
	func poll(delta: float) -> void:
		if anchor == null or not is_instance_valid(anchor):
			return
		var any := false
		for pid in Net.players:
			var p: Player = Net.players[pid]
			if is_sweeping(p, anchor):
				any = true
				set_dirt(dirt_f - SWEEP_PER_SEC * delta)
				_sfx_acc += delta
				if _sfx_acc >= SFX_EVERY:
					_sfx_acc = 0.0
					AudioBus.play_at("broom_sweep", p.global_position, -8.0, 0.25)
		if not any:
			_sfx_acc = SFX_EVERY


# ====================================================================== система

func system_name() -> String:
	return "ClearOut"


func is_active() -> bool:
	return phase == Phase.RUNNING or phase == Phase.OVERTIME


func current_anchor() -> LotAnchor:
	return anchor if is_active() else null


## Аукцион зовёт после молотка. Вещи уже стоят в ячейке (превью, freeze) — размораживаем;
## если их нет — спавним. price — сколько заплатили за лот (для штрафа 10%).
func begin(p_anchor: LotAnchor, p_preset: LotPreset, p_winner_peer: int, price: int = 0) -> void:
	if not Net.is_host() or p_anchor == null or p_preset == null:
		return
	if is_active():
		push_warning("[ClearOut] begin while active (%s) — finishing previous" % preset.id)
		finish()
	anchor = p_anchor
	preset = p_preset
	winner_peer = p_winner_peer
	lot_price = price if price > 0 else preset.min_bid
	anchor.current_lot_id = preset.id
	_yelled.clear()
	_locked_players.clear()
	_team_hint_done = false
	_tick_acc = 0.0
	_broadcast_acc = 0.0
	var existing := _lot_items()
	if existing.is_empty():
		Game.world.spawn_lot_contents(preset, anchor.cell())
	else:
		for b in existing:
			if b.nested_in == null and not b.proxy:
				b.freeze = false
				b.sleeping = false
	anchor.open_door()
	if preset.broom_required:
		cell = CellDirt.new(anchor, 100.0)
		cell.build_visual()
	else:
		cell = null
	phase = Phase.RUNNING
	time_left = maxf(5.0, preset.clearout_seconds)
	Game.set_world_mode(Types.WorldMode.CLEAR_OUT)
	_caretaker = _find_caretaker()
	Net.broadcast_event("clearout_begin", _begin_dict())
	_yell("start", _pick(["CARETAKER_START_A", "CARETAKER_START_B"]))
	_broadcast_state()


## Игрок отчитался смотрителю (Auction зовёт из Caretaker.interact, либо запрос "clearout_done").
## true — вывоз закрыт; false — ещё есть вещи внутри / не тот момент.
func try_finish_by(player: Node) -> bool:
	if not Net.is_host() or not is_active():
		return false
	if phase == Phase.OVERTIME:
		_yell("overtime", "CARETAKER_OVERTIME")
		return false
	var inside := _items_inside()
	if not inside.is_empty():
		_yell("hurry", tr("CARETAKER_NOT_DONE") % inside.size())
		if player and player.has_method("say"):
			player.say(tr("CLEAROUT_NOT_YET") % inside.size())
		return false
	finish()
	return true


## Закрыть вывоз: хаул посчитан, режим → TRAVEL, дверь откроется через 3 с (20 с если кого-то заперли).
func finish() -> void:
	if not Net.is_host() or anchor == null or preset == null or phase == Phase.IDLE or phase == Phase.DONE:
		return
	var was_overtime := phase == Phase.OVERTIME
	phase = Phase.DONE
	var pid := preset.id
	var a := anchor
	var locked := _locked_players.size() > 0
	var haul := _haul_items()
	var haul_value := 0
	var has_gem := false
	var best: ItemBody = null
	var broken := 0
	for b in haul:
		haul_value += b.current_value()
		if b.def.tags.has("gem"):
			has_gem = true
		if best == null or b.current_value() > best.current_value():
			best = b
		if b.integrity != Types.Integrity.WHOLE:
			broken += 1
	var dirt_now := cell.dirt() if cell else 0
	var blacklist := false
	var broom_key := ""
	if cell:
		if dirt_now > DIRT_BLACKLIST_AT:
			blacklist = true
			broom_key = "CLEAROUT_BROOM_BLACKLIST"
			_yell("broom", "CARETAKER_BROOM_BAD")
		elif dirt_now > DIRT_DEPOSIT_AT:
			Economy.try_spend(mini(Economy.pot, DEPOSIT_FINE), "broom_deposit")
			broom_key = "CLEAROUT_BROOM_DEPOSIT"
			_yell("broom", "CARETAKER_BROOM")
		else:
			broom_key = "CLEAROUT_CLEAN_OK"
			_yell("done", "CARETAKER_CLEAN")
	if not was_overtime and not locked and not blacklist:
		_yell("done", _pick(["CARETAKER_DONE_A", "CARETAKER_DONE_B"]))
	# §15: слот пишем только после вывоза — режим уже TRAVEL
	Game.set_world_mode(Types.WorldMode.TRAVEL)
	Game.lot_done(pid)
	Game.stat_add("lots_cleared")
	Game.stat_add("haul_value", haul_value)
	var cursor: Dictionary = Game.save.get("lot_cursor", {})
	var dkey := str(preset.district_id)
	cursor[dkey] = int(cursor.get(dkey, 0)) + 1
	Game.save["lot_cursor"] = cursor
	if blacklist:
		Game.blacklist(preset.district_id)
	if has_gem:
		Achievements.count("gem_hauls", "needle", 1)
	_hud_on = false
	# итоговый тост приходит через событие (с задержкой — чтобы не заваливать худ в один кадр)
	Net.broadcast_event("clearout_done", {
		"anchor": str(a.get_path()), "lot": pid, "haul": haul.size(), "value": haul_value,
		"dirt": dirt_now, "broom": broom_key, "paid": lot_price, "broken": broken,
		"best": best.def.display_name() if best else "", "best_value": best.current_value() if best else 0,
		"overtime": was_overtime, "locked": locked,
	})
	finished.emit(pid)
	# дверь и Auction — позже, чтобы запертые успели выйти; временный смотритель уходит с ними
	var reopen := DOOR_REOPEN_LOCKED if locked else DOOR_REOPEN_NORMAL
	var temp_npc: Npc = _caretaker if _temp_caretaker else null
	get_tree().create_timer(reopen).timeout.connect(func():
		if is_instance_valid(a):
			a.open_door()
			a.current_lot_id = ""
		if temp_npc and is_instance_valid(temp_npc):
			Net.broadcast_event("npc_despawn", {"path": str(temp_npc.get_path())})
			temp_npc.queue_free()
		var auction: Node = Game.world.system("Auction") if Game.world else null
		if auction and auction.has_method("on_clearout_finished"):
			auction.on_clearout_finished(a))
	_cleanup()


func _cleanup() -> void:
	if cell:
		cell.destroy()
		cell = null
	_caretaker = null
	_temp_caretaker = false
	_locked_players.clear()
	anchor = null
	preset = null
	phase = Phase.IDLE


# ------------------------------------------------------------------ тик (хост)

func _physics_process(delta: float) -> void:
	if not Net.is_host() or not is_active():
		return
	if anchor == null or not is_instance_valid(anchor):
		_cleanup()
		return
	time_left -= delta
	if cell:
		cell.poll(delta)
		if cell.take_changed():
			Net.broadcast_event("cell_dirt", {"anchor": str(anchor.get_path()), "dirt": cell.dirt()})
	match phase:
		Phase.RUNNING:
			_yell_thresholds()
			_team_hint()
			if time_left <= 10.0:
				_tick_acc += delta
				if _tick_acc >= 1.0:
					_tick_acc = 0.0
					AudioBus.play_at("haggle_tick", anchor.cell_center(), -2.0, 0.05)
			if time_left <= 0.0:
				_start_overtime()
		Phase.OVERTIME:
			if time_left <= 0.0:
				_end_overtime()
				return
	_broadcast_acc += delta
	if _broadcast_acc >= BROADCAST_EVERY:
		_broadcast_acc = 0.0
		_broadcast_state()


func _process(delta: float) -> void:
	if not _hud_on:
		return
	_hud_left = maxf(0.0, _hud_left - delta)
	var hud: Node = Game.world.hud if Game.world else null
	if hud and hud.has_method("set_timer"):
		hud.set_timer(_hud_left, _hud_title, _hud_overtime)


func _yell_thresholds() -> void:
	var t := time_left
	if t <= 60.0 and not _yelled.has(60):
		_yelled[60] = true
		_yell("hurry", _pick(["CARETAKER_HURRY_60_A", "CARETAKER_HURRY_60_B"]))
	elif t <= 30.0 and not _yelled.has(30):
		_yelled[30] = true
		_yell("hurry", _pick(["CARETAKER_HURRY_30_A", "CARETAKER_HURRY_30_B"]))
	elif t <= 10.0 and not _yelled.has(10):
		_yelled[10] = true
		_yell("hurry", "CARETAKER_HURRY_10")
	elif t <= 5.0:
		var n := int(ceil(t))
		if n >= 1 and n <= 5 and not _yelled.has(n):
			_yelled[n] = true
			_yell("hurry", tr("CARETAKER_COUNT") % n, 0.9)


func _team_hint() -> void:
	if _team_hint_done or time_left > 30.0 or Net.peer_count() != 1:
		return
	for b in _items_inside():
		if b.arch.size_class == Types.SizeClass.TEAM:
			_team_hint_done = true
			_yell("team", "CARETAKER_TEAM")
			return
	_team_hint_done = true


func _start_overtime() -> void:
	phase = Phase.OVERTIME
	time_left = OVERTIME_SECONDS
	_hud_title = "HUD_OVERTIME"
	_hud_overtime = true
	anchor.close_door()
	_locked_players.clear()
	for pid in Net.players:
		var p: Player = Net.players[pid]
		if is_instance_valid(p) and not p.dead and anchor.is_inside(p.global_position):
			_locked_players.append(p)
	_yell("overtime", "CARETAKER_OVERTIME")
	if not _locked_players.is_empty():
		_yell("overtime", "CARETAKER_LOCKED", 3.5)
	_broadcast_state()


func _end_overtime() -> void:
	# кто остался внутри — заперт (§10): ачивка, менты, штраф
	var still: Array = []
	for p in _locked_players:
		if is_instance_valid(p) and not p.dead and anchor.is_inside(p.global_position):
			still.append(p)
	_locked_players = still
	var msg := ""
	if not still.is_empty():
		Achievements.unlock("locked_inside")
		var fine := mini(Economy.pot, 25 + int(lot_price * 0.1))
		if fine > 0:
			Economy.try_spend(fine, "overtime_fine")
		msg = tr("CLEAROUT_LOCKED") % fine
		var police: Node = Game.world.system("Police") if Game.world else null
		if police and police.has_method("trigger"):
			police.trigger(Types.PoliceTrigger.OVERTIME, anchor.cell_center(), still[0])
		Game.stat_add("locked_inside")
	# невынесенное — пропало
	var lost := _despawn_inside()
	if lost > 0:
		msg += ("\n" if msg != "" else "") + tr("CLEAROUT_LOST") % lost
		_yell("overtime", "CARETAKER_LOST")
		Game.stat_add("items_lost", lost)
	# один тост на всё (худ не любит пачку тостов в один кадр)
	Net.broadcast_event("clearout_lost", {"anchor": str(anchor.get_path()), "lot": preset.id, "count": lost, "text": msg})
	finish()


# ------------------------------------------------------------------ вещи лота

func _lot_items() -> Array:
	var out: Array = []
	if preset == null:
		return out
	for nid in Net.items:
		var b = Net.items[nid]
		if is_instance_valid(b) and b.lot_id == preset.id:
			out.append(b)
	return out


func _items_inside() -> Array:
	var out: Array = []
	for b in _lot_items():
		if anchor.is_inside(b.global_position):
			out.append(b)
	return out


func _haul_items() -> Array:
	var out: Array = []
	for b in _lot_items():
		if not anchor.is_inside(b.global_position):
			out.append(b)
	return out


## Деспавн вещей лота, оставшихся внутри ячейки (точнее радиуса: по объёму Cell).
func _despawn_inside() -> int:
	var n := 0
	for b in _items_inside():
		if is_instance_valid(b):
			for h in b.held_by.duplicate():
				h.host_release_body(b)
			Net.despawn_item(b.net_id)
			n += 1
	return n


# ------------------------------------------------------------------ смотритель

func _find_caretaker() -> Npc:
	_temp_caretaker = false
	var marker := anchor.marker("Caretaker")
	var mpos := marker.global_position
	var best: Npc = null
	var best_d := 1e9
	if Game.world and Game.world.npcs_root:
		for n in Game.world.npcs_root.get_children():
			if n is Npc and n.npc_group == "caretaker" and is_instance_valid(n):
				var d: float = n.global_position.distance_to(mpos)
				if d < best_d:
					best_d = d
					best = n
	if best and best_d <= 12.0:
		return best
	# Аукцион не поставил смотрителя — временный, чтобы вывоз не был немым
	var c := Npc.new()
	c.name = TEMP_CARETAKER_NAME
	c.npc_group = "caretaker"
	c.body_color = Color(0.35, 0.35, 0.4)
	c.hat = true
	c.display_name = tr("NPC_CARETAKER")
	var root: Node = Game.world.npcs_root if Game.world and Game.world.npcs_root else self
	var old := root.get_node_or_null(TEMP_CARETAKER_NAME) as Npc
	if old:
		c.free()
		c = old
	else:
		root.add_child(c)
	c.global_position = mpos
	c.face(anchor.cell_center())
	_temp_caretaker = true
	if Net.peer_count() > 1:
		Net.broadcast_event("clearout_caretaker", {"pos": c.global_position, "path": str(c.get_path())})
	return c


## Ор смотрителя. Caretaker.shout(category, text) если есть, иначе Npc.say.
func _yell(category: String, key_or_text: String, sec: float = 2.5) -> void:
	if _caretaker == null or not is_instance_valid(_caretaker):
		_caretaker = _find_caretaker() if anchor and is_instance_valid(anchor) else null
		if _caretaker == null:
			return
	var text := tr(key_or_text) if key_or_text.begins_with("CARETAKER_") else key_or_text
	if _caretaker.has_method("shout"):
		_caretaker.shout(category, text)
	else:
		_caretaker.say(text, sec, category)


func _pick(keys: Array) -> String:
	return keys[randi() % keys.size()]


# ------------------------------------------------------------------ сеть

func _begin_dict() -> Dictionary:
	return {
		"anchor": str(anchor.get_path()), "lot": preset.id, "sec": time_left,
		"broom": preset.broom_required, "dirt": cell.dirt() if cell else 0,
	}


func _state_dict() -> Dictionary:
	return {
		"anchor": str(anchor.get_path()), "lot": preset.id, "sec": maxf(time_left, 0.0),
		"overtime": phase == Phase.OVERTIME,
	}


func _broadcast_state() -> void:
	if not is_active():
		return
	Net.broadcast_event("clearout_state", _state_dict())


func handle_action(peer: int, kind: String, _data: Dictionary) -> bool:
	if not is_active():
		return false
	var p: Player = Game.world.player_of(peer) if Game.world else null
	if p == null:
		return false
	match kind:
		"sweep":
			if cell:
				cell.sweep_by(p)
			return true
		"clearout_done":
			try_finish_by(p)
			return true
	return false


func on_net_event(kind: String, data: Dictionary) -> void:
	match kind:
		"clearout_begin":
			_hud_on = true
			_hud_left = float(data.get("sec", 0.0))
			_hud_title = "HUD_TIMER"
			_hud_overtime = false
			if not Net.is_host():
				var a := get_node_or_null(NodePath(str(data.get("anchor", "")))) as LotAnchor
				if a and bool(data.get("broom", false)):
					if cell:
						cell.destroy()
					cell = CellDirt.new(a, float(data.get("dirt", 100)))
					cell.build_visual()
		"clearout_state":
			_hud_on = true
			_hud_left = float(data.get("sec", 0.0))
			_hud_overtime = bool(data.get("overtime", false))
			_hud_title = "HUD_OVERTIME" if _hud_overtime else "HUD_TIMER"
		"cell_dirt":
			if not Net.is_host() and cell and cell.anchor and str(cell.anchor.get_path()) == str(data.get("anchor", "")):
				cell.set_dirt(float(data.get("dirt", 0)))
		"clearout_lost":
			var t := str(data.get("text", ""))
			if t != "":
				Game.notify.emit(t, 5.0)
		"clearout_done":
			_hud_on = false
			var hud: Node = Game.world.hud if Game.world else null
			if hud and hud.has_method("clear_timer"):
				hud.clear_timer()
			var broom_key := str(data.get("broom", ""))
			if hud and hud.has_method("show_lot_card"):
				get_tree().create_timer(0.7).timeout.connect(func(): hud.show_lot_card(data))
			else:
				var text := tr("CLEAROUT_DONE") % [int(data.get("haul", 0)), int(data.get("value", 0))]
				if broom_key != "":
					text += "\n" + tr(broom_key)
				get_tree().create_timer(0.7).timeout.connect(func(): Game.notify.emit(text, 6.0))
			if not Net.is_host() and cell:
				cell.destroy()
				cell = null
		"clearout_caretaker":
			if not Net.is_host() and Game.world and Game.world.npcs_root and Game.world.npcs_root.get_node_or_null(TEMP_CARETAKER_NAME) == null:
				var c := Npc.new()
				c.name = TEMP_CARETAKER_NAME
				c.npc_group = "caretaker"
				c.body_color = Color(0.35, 0.35, 0.4)
				c.hat = true
				c.display_name = tr("NPC_CARETAKER")
				Game.world.npcs_root.add_child(c)
				c.global_position = data.get("pos", Vector3.ZERO)
				c.set_meta("host_path", str(data.get("path", "")))


func send_full_state_to(peer: int) -> void:
	if not is_active():
		return
	Net.send_event(peer, "clearout_begin", _begin_dict())
	Net.send_event(peer, "clearout_state", _state_dict())
	if _temp_caretaker and _caretaker and is_instance_valid(_caretaker):
		Net.send_event(peer, "clearout_caretaker", {"pos": _caretaker.global_position, "path": str(_caretaker.get_path())})
