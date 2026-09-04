class_name Janitor
extends Node3D
## Уборка (§8, §13): дно, не старт. Котёл в нуле → бригадир в Storage даёт убрать чужую
## обнесённую ячейку: вынести хлам ($1/шт), отмыть ($2/шт), подмести пол (+$10). Те же глаголы.
## Повторяемо, никогда не soft-lock: бригадир стоит всегда, работу даёт пока котёл < $50.
## Хост считает; клиентам — janitor_boss / janitor_begin / janitor_state / cell_dirt / janitor_done.

signal job_started(anchor: LotAnchor)
signal job_finished(payout: int)

const JOB_SECONDS := 180.0
const POT_THRESHOLD := 50
const LOT_ID := "janitor"
const BOSS_NAME := "JanitorBoss"
const PAY_OUT := 1
const PAY_CLEAN := 2
const PAY_FLOOR := 10
const FLOOR_BONUS_AT := 20
const JUNK_MIN := 10
const JUNK_MAX := 16
const BROADCAST_EVERY := 1.0

var boss: JanitorBoss = null
var anchor: LotAnchor = null
var active := false
var time_left := 0.0
var payout := 0
var cell: ClearOut.CellDirt = null

var _junk: Dictionary = {} # net_id → {"out": bool, "clean": bool}
var _fallback_anchor: LotAnchor = null
var _broadcast_acc := 0.0
var _yelled: Dictionary = {}
var _chatter_acc := 0.0
var _boss_pos := Vector3.ZERO
# худ (у каждого пира свой)
var _hud_on := false
var _hud_left := 0.0


## Бригадир уборки: зелёный комбинезон, табличка «УБОРКА $», E — работа.
class JanitorBoss extends Npc:
	var system: Node = null
	var sign_lbl: Label3D = null

	func setup_boss(sys: Node) -> void:
		system = sys
		npc_group = "janitor_boss"
		body_color = Color(0.2, 0.6, 0.25)
		hat = true
		fatness = 1.15
		display_name = tr("NPC_JANITOR_BOSS")

	func attach_sign() -> void:
		if sign_lbl and is_instance_valid(sign_lbl):
			return
		sign_lbl = Label3D.new()
		sign_lbl.name = "Sign"
		sign_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sign_lbl.font_size = 72
		sign_lbl.outline_size = 14
		sign_lbl.pixel_size = 0.006
		sign_lbl.modulate = Color(0.6, 1.0, 0.5)
		sign_lbl.position.y = height + 1.0
		add_child(sign_lbl)
		set_sign(0, false)

	func set_sign(earned: int, working: bool) -> void:
		if sign_lbl == null or not is_instance_valid(sign_lbl):
			return
		sign_lbl.text = (tr("JANITOR_SIGN") + "%d" % earned) if working else tr("JANITOR_SIGN")

	func interact(player: Node) -> void:
		if system and system.has_method("on_boss_interact"):
			system.on_boss_interact(player)

	func interact_hint(_player: Node) -> String:
		if system and system.has_method("boss_hint"):
			return system.boss_hint()
		return "[E]"


func job_target() -> Vector3:
	if anchor and is_instance_valid(anchor):
		return anchor.cell_center()
	if boss and is_instance_valid(boss):
		return boss.global_position
	return Vector3.ZERO


func system_name() -> String:
	return "Janitor"


func _ready() -> void:
	_deferred_spawn_boss()


func _deferred_spawn_boss() -> void:
	# ждём город и Net.host()/join() (World._ready идёт после детей)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree() or not Net.is_host():
		return
	_ensure_boss()


# ------------------------------------------------------------------ бригадир

func _boss_spawn_pos() -> Vector3:
	if Game.world == null:
		return Vector3(0, 0, 6)
	var lot0: Node3D = Game.world.find_marker(Types.District.STORAGE, "Lot0")
	if lot0 is LotAnchor:
		var m: Node3D = lot0.marker("Caretaker")
		return m.global_position + m.global_basis.x * 2.2
	var storage: Node3D = Game.world.district_root(Types.District.STORAGE)
	if storage:
		return storage.global_position + Vector3(3, 0, 3)
	# Storage ещё не построен — стоим у свалки трейлер-парка, чтобы кампания не встала
	var junk: Node3D = Game.world.find_marker(Types.District.TRAILER_PARK, "JunkYard")
	if junk:
		return junk.global_position + Vector3(4, 0, 4)
	return Vector3(0, 0, 6)


func _ensure_boss() -> JanitorBoss:
	if boss and is_instance_valid(boss):
		return boss
	var root: Node = Game.world.npcs_root if Game.world and Game.world.npcs_root else self
	var old := root.get_node_or_null(BOSS_NAME) as JanitorBoss
	if old:
		boss = old
		boss.system = self
		return boss
	boss = JanitorBoss.new()
	boss.name = BOSS_NAME
	boss.setup_boss(self)
	root.add_child(boss)
	_boss_pos = _boss_spawn_pos()
	boss.global_position = _boss_pos
	boss.attach_sign()
	if Net.is_host() and Net.peer_count() > 1:
		Net.broadcast_event("janitor_boss", {"pos": _boss_pos})
	return boss


## World зовёт при Economy.broke (§13). Бригадир напоминает о себе; работа берётся через E.
func offer_job() -> void:
	if not Net.is_host():
		return
	var b := _ensure_boss()
	if active:
		return
	b.say(tr("JANITOR_OFFER"), 4.0, "shout")
	Game.stat_add("janitor_offers")


func boss_hint() -> String:
	if active:
		return tr("JANITOR_HINT_BUSY")
	if Economy.pot >= POT_THRESHOLD:
		return tr("JANITOR_HINT_SCALED")
	return tr("JANITOR_HINT_START")


## E по бригадиру (хост). Работа идёт → отчёт; нет → старт если котёл < 50.
func on_boss_interact(player: Node) -> void:
	if not Net.is_host():
		return
	if active:
		try_finish_by(player)
		return
	try_start(player)


func try_start(player: Node) -> bool:
	if not Net.is_host() or active:
		return false
	var b := _ensure_boss()
	if Game.world_mode == Types.WorldMode.CLEAR_OUT or Game.world_mode == Types.WorldMode.AUCTION:
		b.say(tr("JANITOR_BUSY_MODE"), 3.0, "shout")
		return false
	var a := _pick_anchor()
	if a == null:
		b.say(tr("JANITOR_NO_CELL"), 3.0, "shout")
		return false
	_start_job(a, player)
	return true


## Отчёт бригадиру: всё вынесено → закрываем и платим; нет → ор.
func try_finish_by(player: Node) -> bool:
	if not Net.is_host() or not active:
		return false
	var inside := _junk_inside_count()
	if inside > 0:
		if boss:
			boss.say(tr("JANITOR_NOT_DONE") % inside, 2.5, "shout")
		if player and player.has_method("say"):
			player.say(tr("JANITOR_NOT_YET") % inside)
		return false
	_finish_job(false)
	return true


# ------------------------------------------------------------------ работа

func _pick_anchor() -> LotAnchor:
	var anchors: Array = []
	if Game.world and Game.world.city and Game.world.city.has_method("lot_anchors"):
		anchors = Game.world.city.lot_anchors(Types.District.STORAGE)
	var auction: Node = Game.world.system("Auction") if Game.world else null
	var clearout: Node = Game.world.system("ClearOut") if Game.world else null
	var best: LotAnchor = null
	var best_d := 1e9
	var from := boss.global_position if boss and is_instance_valid(boss) else Vector3.ZERO
	for a in anchors:
		if not (a is LotAnchor) or a.door_closed:
			continue
		if auction and auction.has_method("is_anchor_busy") and auction.is_anchor_busy(a):
			continue
		if clearout and clearout.has_method("current_anchor") and clearout.current_anchor() == a:
			continue
		var d: float = a.global_position.distance_to(from)
		if d < best_d:
			best_d = d
			best = a
	if best:
		return best
	return _make_fallback_anchor(from)


## Storage без ячеек (ещё не собран) — временная ячейка у бригадира. Никакого soft-lock.
func _make_fallback_anchor(near: Vector3) -> LotAnchor:
	if _fallback_anchor and is_instance_valid(_fallback_anchor):
		return _fallback_anchor
	var a := LotAnchor.new()
	a.name = "JanitorCell"
	a.lot_kind = Types.LotKind.STORAGE
	a.has_door = false
	a.cell_size = Vector3(3, 2.5, 3)
	var c := Node3D.new()
	c.name = "Cell"
	a.add_child(c)
	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(a.cell_size.x, a.cell_size.z)
	floor_mesh.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.45, 0.45, 0.48)
	floor_mesh.material_override = m
	floor_mesh.position.y = 0.005
	c.add_child(floor_mesh)
	var parent: Node = Game.world if Game.world else self
	parent.add_child(a)
	a.global_position = near + Vector3(0, 0, -6)
	_fallback_anchor = a
	return a


func _start_job(a: LotAnchor, player: Node) -> void:
	anchor = a
	active = true
	time_left = JOB_SECONDS
	payout = 0
	_junk.clear()
	_yelled.clear()
	_chatter_acc = 0.0
	_broadcast_acc = 0.0
	Game.world.despawn_lot_items(LOT_ID)
	_spawn_junk()
	_spawn_tools_if_needed(player)
	cell = ClearOut.CellDirt.new(anchor, 100.0)
	cell.build_visual()
	Game.set_world_mode(Types.WorldMode.JANITOR_JOB)
	if boss:
		boss.set_sign(0, true)
		boss.face(anchor.cell_center())
		boss.say(tr(_pick(["JANITOR_START_A", "JANITOR_START_B"])), 3.5, "start")
	Game.notify.emit(tr("JANITOR_TOAST_START"), 6.0)
	Game.stat_add("janitor_jobs_started")
	Net.broadcast_event("janitor_begin", _begin_dict())
	job_started.emit(anchor)
	_broadcast_state()


func _junk_pool() -> Array:
	var pool: Array = []
	var loose: Array = []
	for d in Registry.all_items():
		if d.is_cash() or d.tags.has("broom") or d.tags.has("rag") or d.tags.has("bucket"):
			continue
		if d.value_base <= 5:
			loose.append(d)
			if d.has_facet(Types.Facet.DIRTYABLE):
				pool.append(d)
	if pool.is_empty():
		pool = loose
	return pool


func _spawn_junk() -> void:
	var pool := _junk_pool()
	if pool.is_empty():
		push_warning("[Janitor] no junk items in Registry (value_base <= 5)")
		return
	var n := randi_range(JUNK_MIN, JUNK_MAX)
	var cs := anchor.cell_size
	var cell_xf := anchor.cell().global_transform
	for i in n:
		var d: ItemDef = pool[randi() % pool.size()]
		var local := Vector3(randf_range(-cs.x * 0.38, cs.x * 0.38), 0.15 + 0.12 * floorf(i / 6.0), randf_range(-cs.z * 0.38, cs.z * 0.2))
		var xf := cell_xf * Transform3D(Basis(Vector3.UP, randf() * TAU), local)
		var b = Net.spawn_item(d.id, xf, {"d": 1.0, "lot": LOT_ID})
		if b:
			_junk[b.net_id] = {"out": false, "clean": false}


func _spawn_tools_if_needed(player: Node) -> void:
	var has_tool := false
	for pid in Net.players:
		var p: Player = Net.players[pid]
		if is_instance_valid(p) and (p.hands.holds_tag("broom") or p.hands.holds_tag("rag")):
			has_tool = true
	if not has_tool:
		for nid in Net.items:
			var b = Net.items[nid]
			if is_instance_valid(b) and (b.def.tags.has("broom") or b.def.tags.has("rag")) and b.global_position.distance_to(anchor.global_position) < 20.0:
				has_tool = true
				break
	if has_tool:
		return
	var entrance := anchor.cell().global_transform * Vector3(0, 0.1, anchor.cell_size.z * 0.5 + 0.7)
	var i := 0
	for tool_id in ["tool_broom", "tool_rag"]:
		if Registry.item(tool_id) == null:
			continue
		Net.spawn_item(tool_id, Transform3D(Basis(Vector3.UP, randf() * TAU), entrance + Vector3(-0.4 + 0.8 * i, 0.05 * i, 0)), {"lot": LOT_ID})
		i += 1
	if i == 0 and player and player.has_method("say"):
		player.say(tr("JANITOR_NO_TOOLS"))


func _physics_process(delta: float) -> void:
	if not Net.is_host() or not active:
		return
	if anchor == null or not is_instance_valid(anchor):
		_finish_job(true)
		return
	time_left -= delta
	_poll_junk()
	if cell:
		cell.poll(delta)
		if cell.take_changed():
			Net.broadcast_event("cell_dirt", {"anchor": str(anchor.get_path()), "dirt": cell.dirt()})
	_yell_thresholds(delta)
	_broadcast_acc += delta
	if _broadcast_acc >= BROADCAST_EVERY:
		_broadcast_acc = 0.0
		_broadcast_state()
	if time_left <= 0.0:
		_finish_job(true)


func _process(delta: float) -> void:
	if not _hud_on:
		return
	_hud_left = maxf(0.0, _hud_left - delta)
	var hud: Node = Game.world.hud if Game.world else null
	if hud and hud.has_method("set_timer"):
		hud.set_timer(_hud_left, "HUD_TIMER", false)


func _poll_junk() -> void:
	var changed := false
	for nid in _junk.keys():
		var b = Net.items.get(nid)
		if b == null or not is_instance_valid(b):
			continue
		var rec: Dictionary = _junk[nid]
		if not rec["out"] and b.nested_in == null and not anchor.is_inside(b.global_position):
			rec["out"] = true
			payout += PAY_OUT
			changed = true
			AudioBus.play_at("coin", b.global_position, -8.0)
		if not rec["clean"] and b.dirt < 0.1:
			rec["clean"] = true
			payout += PAY_CLEAN
			changed = true
			AudioBus.play_at("coin", b.global_position, -6.0)
	if changed and boss:
		boss.set_sign(payout, true)


func _junk_inside_count() -> int:
	var n := 0
	for nid in _junk:
		var b = Net.items.get(nid)
		if b and is_instance_valid(b) and anchor.is_inside(b.global_position):
			n += 1
	return n


func _yell_thresholds(delta: float) -> void:
	if boss == null or not is_instance_valid(boss):
		return
	for th in [60, 30, 10]:
		if time_left <= th and not _yelled.has(th):
			_yelled[th] = true
			boss.say(tr("JANITOR_TIME_%d" % th), 2.5, "shout")
			return
	_chatter_acc += delta
	if _chatter_acc >= 25.0:
		_chatter_acc = 0.0
		boss.say(tr(_pick(["JANITOR_SHOUT_A", "JANITOR_SHOUT_B", "JANITOR_SHOUT_C"])), 2.5, "shout")


func _finish_job(timed_out: bool) -> void:
	if not active:
		return
	active = false
	var floor_dirt := cell.dirt() if cell else 100
	var bonus := floor_dirt < FLOOR_BONUS_AT
	if bonus:
		payout += PAY_FLOOR
	if payout > 0:
		if Economy.pot >= POT_THRESHOLD:
			payout = int(ceil(payout * 0.6))
		Economy.add(payout, "janitor")
	var msg := (tr("JANITOR_TIMEOUT") if timed_out else tr("JANITOR_PAID")) % payout
	if bonus:
		msg += "\n" + tr("JANITOR_FLOOR_BONUS") % PAY_FLOOR
	Game.notify.emit(msg, 5.0)
	if boss and is_instance_valid(boss):
		boss.say(tr(_pick(["JANITOR_DONE_A", "JANITOR_DONE_B"])) if not timed_out else tr("JANITOR_DONE_TIMEOUT"), 3.5, "done")
		boss.set_sign(0, false)
	Game.world.despawn_lot_items(LOT_ID)
	Game.set_world_mode(Types.WorldMode.TRAVEL)
	Achievements.unlock("janitor")
	Game.stat_add("janitor_jobs")
	Game.stat_add("janitor_earned", payout)
	_hud_on = false
	Net.broadcast_event("janitor_done", {"anchor": str(anchor.get_path()) if anchor and is_instance_valid(anchor) else "", "pay": payout, "timeout": timed_out})
	job_finished.emit(payout)
	if cell:
		cell.destroy()
		cell = null
	_junk.clear()
	anchor = null
	Game.write_slot()


func _pick(keys: Array) -> String:
	return keys[randi() % keys.size()]


# ------------------------------------------------------------------ сеть

func _begin_dict() -> Dictionary:
	return {"anchor": str(anchor.get_path()), "sec": time_left, "dirt": cell.dirt() if cell else 100}


func _state_dict() -> Dictionary:
	return {"anchor": str(anchor.get_path()), "sec": maxf(time_left, 0.0), "pay": payout}


func _broadcast_state() -> void:
	if not active:
		return
	Net.broadcast_event("janitor_state", _state_dict())


func handle_action(peer: int, kind: String, _data: Dictionary) -> bool:
	var p: Player = Game.world.player_of(peer) if Game.world else null
	if p == null:
		return false
	match kind:
		"sweep":
			if active and cell:
				cell.sweep_by(p)
				return true
		"janitor_start":
			return try_start(p)
		"janitor_done":
			if active:
				try_finish_by(p)
				return true
	return false


func on_net_event(kind: String, data: Dictionary) -> void:
	match kind:
		"janitor_boss":
			if not Net.is_host() and Game.world and Game.world.npcs_root and Game.world.npcs_root.get_node_or_null(BOSS_NAME) == null:
				var b := JanitorBoss.new()
				b.name = BOSS_NAME
				b.setup_boss(self)
				Game.world.npcs_root.add_child(b)
				b.global_position = data.get("pos", Vector3.ZERO)
				b.attach_sign()
				boss = b
		"janitor_begin":
			_hud_on = true
			_hud_left = float(data.get("sec", JOB_SECONDS))
			if not Net.is_host():
				active = true
				var a := get_node_or_null(NodePath(str(data.get("anchor", "")))) as LotAnchor
				if a:
					if cell:
						cell.destroy()
					cell = ClearOut.CellDirt.new(a, float(data.get("dirt", 100)))
					cell.build_visual()
				if boss and is_instance_valid(boss):
					boss.set_sign(0, true)
		"janitor_state":
			_hud_on = true
			_hud_left = float(data.get("sec", 0.0))
			if not Net.is_host() and boss and is_instance_valid(boss):
				boss.set_sign(int(data.get("pay", 0)), true)
		"cell_dirt":
			if not Net.is_host() and cell and cell.anchor and str(cell.anchor.get_path()) == str(data.get("anchor", "")):
				cell.set_dirt(float(data.get("dirt", 0)))
		"janitor_done":
			_hud_on = false
			var hud: Node = Game.world.hud if Game.world else null
			if hud and hud.has_method("clear_timer"):
				hud.clear_timer()
			if not Net.is_host():
				active = false
				Game.notify.emit(tr("JANITOR_PAID") % int(data.get("pay", 0)), 5.0)
				if cell:
					cell.destroy()
					cell = null
				if boss and is_instance_valid(boss):
					boss.set_sign(0, false)


func send_full_state_to(peer: int) -> void:
	if boss and is_instance_valid(boss):
		Net.send_event(peer, "janitor_boss", {"pos": boss.global_position})
	if active:
		Net.send_event(peer, "janitor_begin", _begin_dict())
		Net.send_event(peer, "janitor_state", _state_dict())
