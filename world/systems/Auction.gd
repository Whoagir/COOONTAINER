class_name Auction
extends Node3D
## Аукцион (§9): превью по info_mode → торги вёслами (игроки + хантеры) → молот → вывоз (ClearOut) / увоз хантером.
## Хост считает всё; клиенты получают события auction_* и только рисуют. Одна активная сессия на район.
##
## События (хост → все): auction_state, auction_bid, auction_npcs, auction_preview, auction_clear,
##   auction_sold, auction_door_slit, auction_npc_goto, auction_hunter_pass, auction_shove,
##   auction_teleport, auction_paddle, hunter_carry. Действия (клиент → хост): bid{amount}, paddle_show, paddle_value{v}.

signal bid_placed(anchor: Node3D, amount: int, bidder_name: String, is_player: bool)
signal sold(anchor: Node3D, amount: int, winner_name: String, winner_peer: int)
signal session_state(anchor_key: String, state: int)

enum State { IDLE, PREVIEW, BIDDING, HAMMER, COOLDOWN }

const GOING_SECONDS := 5.0 # «идёт… идёт…» после последней ставки
const SETTLE_SECONDS := 0.7 # минимум между ставками хантеров
const SETTLE_AFTER_PLAYER := 1.4 # …и после ставки игрока
const NO_BID_SECONDS := 9.0 # никто не дал стартовую → лот снят
const HAMMER_SECONDS := 2.2
const COOLDOWN_SECONDS := 20.0
const AUTO_START_SECONDS := 10.0
const STAND_RADIUS := 4.0
const HUD_RADIUS := 45.0
const HAUL_SECONDS := 8.0
const PHOTO_SIZE := Vector2i(256, 192)
const SLIT_OPEN := 0.4
const STATE_NAMES := ["IDLE", "PREVIEW", "BIDDING", "HAMMER", "COOLDOWN"]


class Session extends RefCounted:
	var anchor: LotAnchor
	var key := ""
	var district_id := -1
	var preset: LotPreset
	var state := 0
	var timer := 0.0
	var min_bid := 0
	var current_bid := 0
	var has_bids := false
	var leader_kind := 0 # 0 нет, 1 игрок (peer), 2 хантер (index)
	var leader_id := 0
	var leader_name := ""
	var going := 0.0
	var going_said := 0
	var settle := 0.0 # пауза после ставки: хантеры не перебивают мгновенно, цену успеваешь прочитать
	var items: Array = []
	var hunters: Array = []
	var auctioneer: Auctioneer
	var caretaker: Caretaker
	var stand_timer := 0.0
	var trespass: Dictionary = {} # peer → предупреждений
	var inside: Dictionary = {} # peer → был внутри
	var props: Array = []
	var bluff_amount := 0
	var bluff_hunter := -1
	var bluff_called := false
	var handed_off := false
	var brawl_flagged := false
	var haul_timer := -1.0
	var haul_hunter: Hunter = null
	var haul_picked := false
	var gloat_said := false
	var state_age := 0.0
	var players_bid := false


var sessions: Array = []
var _by_key: Dictionary = {} # key (путь якоря) → Session
var _view: Dictionary = {} # key → последнее auction_state (хост и клиент; худ/подсказки)
var _client_npcs: Dictionary = {} # клиент: key → {"auctioneer", "caretaker", "hunters": []}
var _client_props: Dictionary = {} # клиент: key → Array[Node]
var _rescan := 0.0
var _hud_key := ""


func system_name() -> String:
	return "Auction"


func _ready() -> void:
	await get_tree().process_frame
	if Net.is_host():
		_collect_anchors()


# ------------------------------------------------------------------ якоря / сессии

func _collect_anchors() -> void:
	for a in get_tree().get_nodes_in_group("lot_anchors"):
		if a is LotAnchor and is_instance_valid(a) and a.is_inside_tree():
			register_anchor(a)


static func key_of(anchor: Node) -> String:
	return str(anchor.get_path())


func session_for(anchor: Node) -> Session:
	if anchor == null:
		return null
	return _by_key.get(key_of(anchor))


## Хост: якорь становится площадкой — аукционист + смотритель у маркеров, дверь закрыта, лот выбран.
func register_anchor(a: LotAnchor) -> Session:
	var key := key_of(a)
	if _by_key.has(key):
		return _by_key[key]
	var s := Session.new()
	s.anchor = a
	s.key = key
	s.district_id = _district_of(a)
	sessions.append(s)
	_by_key[key] = s
	a.close_door(false)
	_spawn_staff(s)
	s.preset = _next_preset(s)
	s.min_bid = s.preset.min_bid if s.preset else 10
	a.tree_exiting.connect(_on_anchor_gone.bind(s), CONNECT_ONE_SHOT)
	return s


func _on_anchor_gone(s: Session) -> void:
	_free_hunters(s)
	for n in [s.auctioneer, s.caretaker]:
		if n and is_instance_valid(n):
			n.queue_free()
	sessions.erase(s)
	_by_key.erase(s.key)
	_view.erase(s.key)


func _district_of(a: Node3D) -> int:
	var n := a.get_parent()
	while n:
		if n is District:
			return n.district_id
		n = n.get_parent()
	if Game.world and Game.world.get("city") and Game.world.city.has_method("district_at"):
		var d = Game.world.city.district_at(a.global_position)
		if d:
			return d.district_id
	return -1


func _npc_name(key: String, role: String) -> String:
	return "AucNpc_%d_%s" % [absi(key.hash()), role]


func _spawn_staff(s: Session) -> void:
	var root: Node = Game.world.npcs_root if Game.world else get_parent()
	var auc := Auctioneer.new()
	auc.name = _npc_name(s.key, "A")
	auc.auction = self
	auc.anchor = s.anchor
	auc.body_color = Color(0.2, 0.2, 0.25)
	auc.hat = true
	auc.height = 1.8
	root.add_child(auc)
	auc.global_position = _spot(s.anchor, "Auctioneer", Vector3(2.0, 0, 3.5))
	auc.face(_stand_pos(s.anchor))
	s.auctioneer = auc
	var care := Caretaker.new()
	care.name = _npc_name(s.key, "C")
	care.auction = self
	care.anchor = s.anchor
	care.body_color = Color(0.25, 0.35, 0.25)
	care.fatness = 1.25
	care.bald = true
	root.add_child(care)
	care.global_position = _spot(s.anchor, "Caretaker", Vector3(-2.2, 0, 2.5))
	care.face(_stand_pos(s.anchor))
	s.caretaker = care


## Позиция маркера якоря; нет маркера — точка перед ячейкой (fallback_local относительно входа по +Z).
func _spot(anchor: LotAnchor, marker: String, fallback_local: Vector3) -> Vector3:
	if marker != "":
		var m := anchor.get_node_or_null(marker) as Node3D
		if m:
			return m.global_position
	var c := anchor.cell().global_transform
	var p := c * (fallback_local + Vector3(0, 0, anchor.cell_size.z * 0.5))
	p.y = anchor.global_position.y
	return p


func _hunter_spot(anchor: LotAnchor, i: int) -> Vector3:
	var m := anchor.get_node_or_null("Hunter%d" % i) as Node3D
	if m:
		return m.global_position
	var ang := lerpf(-1.1, 1.1, float(i) / 7.0)
	return _spot(anchor, "", Vector3(sin(ang) * 3.8, 0, 3.0 + cos(ang) * 1.2))


func _stand_pos(anchor: LotAnchor) -> Vector3:
	return _spot(anchor, "PlayerStand", Vector3(0, 0, 4.0))


func _free_hunters(s: Session) -> void:
	for h in s.hunters:
		if is_instance_valid(h):
			if h.get_parent():
				h.get_parent().remove_child(h)
			h.queue_free()
	s.hunters.clear()


func _spawn_hunters(s: Session) -> void:
	_free_hunters(s)
	var brains: Array = Registry.all_hunters().duplicate()
	if brains.is_empty():
		brains = _fallback_brains()
	brains.shuffle()
	var n := clampi(s.preset.hunters_count if s.preset else 6, 6, 8)
	n = mini(n, brains.size())
	var root: Node = Game.world.npcs_root if Game.world else get_parent()
	for i in n:
		var h := Hunter.new()
		h.setup_brain(brains[i], i)
		h.name = _npc_name(s.key, "H%d" % i)
		h.auction = self
		h.anchor = s.anchor
		root.add_child(h)
		h.global_position = _hunter_spot(s.anchor, i)
		h.face(s.anchor.cell_center())
		s.hunters.append(h)


func _hunter_by_index(s: Session, idx: int) -> Hunter:
	for h in s.hunters:
		if is_instance_valid(h) and h.index == idx:
			return h
	return null


static func _fallback_brains() -> Array:
	var ru := ["Лысый", "Тётя в леопарде", "Очкарик", "Дед", "Качок", "Мамкин барыга", "Тихий", "Крикун"]
	var en := ["Baldy", "Leopard Lady", "Glasses", "Gramps", "Gym Bro", "Mom's Dealer", "Quiet One", "Screamer"]
	var out: Array = []
	for i in 8:
		var b := AuctionBrain.new()
		b.id = "fallback_hunter_%02d" % (i + 1)
		b.nickname_ru = ru[i]
		b.nickname_en = en[i]
		b.name_ru = ru[i]
		b.name_en = en[i]
		b.estimate_error = randf_range(0.15, 0.4)
		b.greed = randf_range(0.3, 0.9)
		b.bluff_chance = randf_range(0.05, 0.3)
		b.setup_chance = randf_range(0.05, 0.25)
		b.patience = randf_range(0.2, 0.9)
		b.aggression = randf_range(0.2, 0.9)
		b.brawl_temper = randf_range(0.1, 0.7)
		b.info_sensitivity = randf_range(0.7, 1.3)
		b.body_color = Color.from_hsv(randf(), randf_range(0.4, 0.8), randf_range(0.5, 0.9))
		b.bald = i == 0 or randf() < 0.2
		b.hat = i % 3 == 1
		b.height = randf_range(1.6, 1.95)
		b.fatness = randf_range(0.85, 1.4)
		b.voice_pitch = randf_range(0.8, 1.3)
		b.set_meta("fallback", true)
		out.append(b)
	return out


# ------------------------------------------------------------------ пресеты (§8)

func _next_preset(s: Session) -> LotPreset:
	var d := s.district_id if s.district_id >= 0 else Types.District.HANGAR
	var list: Array = Registry.lots_for_district(d)
	var same_kind: Array = list.filter(func(p): return p.lot_kind == s.anchor.lot_kind)
	if not same_kind.is_empty():
		list = same_kind
	if list.is_empty():
		return _fallback_preset(d, s.anchor)
	var cur: Dictionary = Game.save.get("lot_cursor", {})
	var idx := int(cur.get(str(d), 0)) % list.size()
	return list[idx]


func _advance_cursor(s: Session) -> void:
	if s.preset == null or s.preset.get_meta("fallback", false):
		return
	if not Game.save.has("lot_cursor"):
		Game.save["lot_cursor"] = {}
	var cur: Dictionary = Game.save["lot_cursor"]
	var d := s.district_id if s.district_id >= 0 else Types.District.HANGAR
	cur[str(d)] = int(cur.get(str(d), 0)) + 1


## Контента нет → временный лот из случайных карточек Registry. Помечен meta "fallback" и id fallback_*.
func _fallback_preset(d: int, anchor: LotAnchor) -> LotPreset:
	var p := LotPreset.new()
	p.id = "fallback_%d_%s_%d" % [d, anchor.name, randi() % 1000]
	p.district_id = d
	p.lot_kind = anchor.lot_kind
	p.min_bid = [10, 40, 120, 300, 600][clampi(anchor.lot_kind, 0, 4)]
	p.info_mode = randi() % 5
	p.preview_seconds = 12.0
	p.clearout_seconds = 120.0
	p.hunters_count = randi_range(6, 8)
	p.cell_size = anchor.cell_size
	p.dark = anchor.dark
	p.tale_ru = tr("AUCTION_FALLBACK_TALE")
	p.tale_en = p.tale_ru
	p.docs_ru = tr("AUCTION_FALLBACK_DOCS")
	p.docs_en = p.docs_ru
	p.set_meta("fallback", true)
	var pool: Array = Registry.all_items().filter(func(def): return not def.is_cash())
	if pool.is_empty():
		push_warning("[Auction] fallback preset without items: Registry is empty")
		return p
	var n := randi_range(3, 8)
	var hx := maxf(anchor.cell_size.x * 0.5 - 0.5, 0.2)
	var hz := maxf(anchor.cell_size.z * 0.5 - 0.5, 0.2)
	for i in n:
		var def: ItemDef = pool[randi() % pool.size()]
		var pos := Vector3(randf_range(-hx, hx), 0.15 + float(i / 4) * 0.6, randf_range(-hz, hz))
		p.spawn_list.append(LotSpawn.make(def.id, pos, randf() * 360.0))
		if randf() < 0.7:
			p.photo_item_ids.append(def.id)
	if randf() < 0.5: # фото врут
		p.photo_item_ids.append(pool[randi() % pool.size()].id)
	return p


# ------------------------------------------------------------------ публичное API (хост)

## Начать сессию на якоре (E по аукционисту / автостарт / тест). preset — переопределить лот.
func start_session(anchor: LotAnchor, preset: LotPreset = null) -> bool:
	if not Net.is_host() or anchor == null:
		return false
	var s := register_anchor(anchor)
	if s.state != State.IDLE:
		return false
	if _district_busy(s):
		return false
	if preset:
		s.preset = preset
	if s.preset == null:
		s.preset = _next_preset(s)
	_begin_preview(s)
	return true


func request_start(anchor: Node3D, player: Node) -> void:
	var s := session_for(anchor)
	if s == null:
		return
	if s.district_id >= 0 and not Game.is_district_unlocked(s.district_id):
		s.auctioneer.announce("angry", line("AUC_LOCKED"))
		return
	if s.state != State.IDLE or _district_busy(s):
		s.auctioneer.announce("angry", line("AUC_BUSY"), 2.0)
		return
	start_session(anchor)


func interact_hint_for(anchor: Node3D, _player: Node) -> String:
	var v: Dictionary = _view.get(key_of(anchor), {})
	var st := int(v.get("state", State.IDLE))
	match st:
		State.PREVIEW: return tr("AUCTION_HINT_PREVIEW")
		State.BIDDING: return tr("AUCTION_HINT_BIDDING")
		State.HAMMER: return tr("AUCTION_HINT_HAMMER")
		State.COOLDOWN: return tr("AUCTION_HINT_COOLDOWN")
	var s := session_for(anchor)
	if s and s.district_id >= 0 and Net.is_host() and not Game.is_district_unlocked(s.district_id):
		return tr("AUCTION_HINT_LOCKED")
	return tr("AUCTION_INTERACT_HINT")


func state_of(anchor: Node3D) -> int:
	var s := session_for(anchor)
	return s.state if s else State.IDLE


func current_preset(anchor: Node3D) -> LotPreset:
	var s := session_for(anchor)
	return s.preset if s else null


func is_active_anywhere() -> bool:
	for s in sessions:
		if s.state != State.IDLE and s.state != State.COOLDOWN:
			return true
	return false


static func step_for(bid: int) -> int:
	if bid < 100:
		return 5
	if bid < 500:
		return 10
	if bid < 2000:
		return 25
	if bid < 5000:
		return 50
	return 100


func required_bid(s: Session) -> int:
	return s.min_bid if not s.has_bids else s.current_bid + step_for(s.current_bid)


## Случайная строка из PREFIX_1..PREFIX_N.
static func line(prefix: String) -> String:
	var n := 1
	while n < 16:
		var k := "%s_%d" % [prefix, n + 1]
		if str(TranslationServer.translate(k)) == k:
			break
		n += 1
	return str(TranslationServer.translate("%s_%d" % [prefix, randi() % n + 1]))


## Пожар (World.on_lot_burned): активный лот с этим id — торги отменяются.
func on_lot_burned(lot_id: String) -> void:
	for s in sessions:
		if s.preset and s.preset.id == lot_id and (s.state == State.PREVIEW or s.state == State.BIDDING):
			s.auctioneer.announce("angry", line("AUC_FIRE"), 3.0)
			_notify_near(s, tr("AUCTION_BURNED"))
			_clear_props(s)
			for h in s.hunters:
				if is_instance_valid(h):
					h.on_result(false, "")
			_to_cooldown(s)


# ------------------------------------------------------------------ тик (хост)

func _physics_process(delta: float) -> void:
	if not Net.is_host():
		return
	_rescan -= delta
	if _rescan <= 0.0:
		_rescan = 5.0
		_collect_anchors()
	for s in sessions.duplicate():
		if not is_instance_valid(s.anchor):
			continue
		s.state_age += delta
		match s.state:
			State.IDLE: _tick_idle(s, delta)
			State.PREVIEW: _tick_preview(s, delta)
			State.BIDDING: _tick_bidding(s, delta)
			State.HAMMER: _tick_hammer(s, delta)
			State.COOLDOWN: _tick_cooldown(s, delta)


func _district_busy(s: Session) -> bool:
	if _clearout_busy(s.anchor):
		return true
	for o: Session in sessions:
		if o == s or o.district_id != s.district_id:
			continue
		if o.state != State.IDLE and o.state != State.COOLDOWN:
			return true
		if o.state == State.COOLDOWN and o.handed_off: # вывоз идёт — толпу не собираем
			return true
	return false


func _tick_idle(s: Session, delta: float) -> void:
	if s.district_id >= 0 and not Game.is_district_unlocked(s.district_id):
		return
	var stand := _stand_pos(s.anchor)
	var near := false
	for pid in Net.players:
		var p = Net.players[pid]
		if is_instance_valid(p) and not p.dead and p.global_position.distance_to(stand) < STAND_RADIUS:
			near = true
			break
	if near:
		s.stand_timer += delta
		if s.stand_timer >= AUTO_START_SECONDS and not _district_busy(s):
			s.stand_timer = 0.0
			start_session(s.anchor)
	else:
		s.stand_timer = 0.0


func _tick_preview(s: Session, delta: float) -> void:
	s.timer -= delta
	_check_trespass(s)
	if s.timer <= 0.0:
		_begin_bidding(s)


func _tick_bidding(s: Session, delta: float) -> void:
	_check_trespass(s)
	var req := required_bid(s)
	s.settle -= delta
	for h in s.hunters:
		if not is_instance_valid(h):
			continue
		var amt: int = h.think(delta, req, s.leader_kind == 2 and s.leader_id == h.index, s.leader_kind == 1)
		if amt > 0 and s.settle <= 0.0:
			var bluff: bool = h.last_bid_was_bluff
			h.last_bid_was_bluff = false
			var outbid_player := s.leader_kind == 1
			_place_bid(s, amt, 2, h.index, h.display_name, bluff)
			# перебили игрока — пауза дольше: пусть увидит и ответит
			s.settle = SETTLE_AFTER_PLAYER if outbid_player else SETTLE_SECONDS
			break
	s.going -= delta
	if s.has_bids:
		if s.going <= 2.6 and s.going_said < 1:
			s.going_said = 1
			s.auctioneer.announce("going", line("AUC_GOING"), 1.2)
		elif s.going <= 1.3 and s.going_said < 2:
			s.going_said = 2
			s.auctioneer.announce("going", line("AUC_GOING2"), 1.2)
		if s.going <= 0.0:
			_hammer(s)
			return
	elif s.going <= 0.0:
		_no_sale(s)
		return
	if s.state_age - floorf(s.state_age) < delta: # раз в секунду — таймер клиентам
		_broadcast_state(s)


func _tick_hammer(s: Session, delta: float) -> void:
	s.timer -= delta
	if s.timer <= 0.0:
		_resolve(s)


func _tick_cooldown(s: Session, delta: float) -> void:
	if s.haul_timer > 0.0:
		s.haul_timer -= delta
		_tick_haul(s)
		if s.haul_timer <= 0.0:
			_finish_haul(s)
	if s.handed_off and s.timer > 100.0 and not _clearout_busy(s.anchor):
		s.timer = 5.0 # вывоз закончился без колбэка — освобождаем площадку
	s.timer -= delta
	if s.timer <= 0.0:
		_to_idle(s)


# ------------------------------------------------------------------ фазы

func _begin_preview(s: Session) -> void:
	s.state = State.PREVIEW
	s.state_age = 0.0
	s.timer = maxf(s.preset.preview_seconds, 3.0)
	s.min_bid = maxi(s.preset.min_bid, 1)
	s.current_bid = 0
	s.has_bids = false
	s.leader_kind = 0
	s.leader_id = 0
	s.leader_name = ""
	s.going = 0.0
	s.going_said = 0
	s.bluff_amount = 0
	s.bluff_hunter = -1
	s.bluff_called = false
	s.players_bid = false
	s.handed_off = false
	s.brawl_flagged = false
	s.haul_timer = -1.0
	s.haul_hunter = null
	s.haul_picked = false
	s.gloat_said = false
	s.trespass.clear()
	s.inside.clear()
	s.anchor.current_lot_id = s.preset.id
	Game.set_world_mode(Types.WorldMode.AUCTION)
	_spawn_hunters(s)
	s.items = Game.world.spawn_lot_contents(s.preset, s.anchor.cell())
	for b in s.items:
		if is_instance_valid(b):
			b.freeze = true
	var value := s.preset.total_value(Registry)
	for h in s.hunters:
		h.prepare(value, s.preset.info_mode, s.min_bid)
	_broadcast_npcs(s)
	_apply_preview(s.key, _preview_payload(s))
	Net.broadcast_event("auction_preview", _preview_payload(s))
	var lot_name := s.preset.id.to_upper().replace("_", " ")
	s.auctioneer.announce("start", tr("AUC_START_FMT") % [lot_name, s.min_bid], 3.0)
	_broadcast_state(s)
	session_state.emit(s.key, s.state)


func _begin_bidding(s: Session) -> void:
	s.state = State.BIDDING
	s.state_age = 0.0
	s.going = NO_BID_SECONDS
	s.going_said = 0
	if s.anchor.has_door and s.preset.info_mode == Types.InfoMode.DOOR15:
		s.anchor.close_door() # смотрели 15 сек — хватит
	_clear_props(s)
	Net.broadcast_event("auction_clear", {"anchor": s.key})
	s.auctioneer.announce("start", line("AUC_BIDDING_OPEN"), 2.0)
	s.auctioneer.set_murmur(true)
	for h in s.hunters:
		if is_instance_valid(h):
			h.face(s.auctioneer.global_position)
	_broadcast_state(s)
	session_state.emit(s.key, s.state)


func _place_bid(s: Session, amount: int, kind: int, id: int, bidder_name: String, is_bluff := false) -> bool:
	if s.state != State.BIDDING:
		return false
	var req := required_bid(s)
	if amount < req:
		return false
	var prev := s.current_bid if s.has_bids else s.min_bid
	# лидер-блефовщик перебит → блеф вскрыт, толпа ржёт
	if s.bluff_hunter >= 0 and s.leader_kind == 2 and s.leader_id == s.bluff_hunter and not s.bluff_called:
		s.bluff_called = true
		s.auctioneer.crowd("crowd_laugh")
		var bl := _hunter_by_index(s, s.bluff_hunter)
		if bl:
			bl.say(line("HUNTER_BLUFF_FAIL"), 2.0, "lose")
	s.current_bid = amount
	s.has_bids = true
	s.leader_kind = kind
	s.leader_id = id
	s.leader_name = bidder_name
	if kind == 1:
		s.players_bid = true
		s.settle = SETTLE_AFTER_PLAYER
	s.going = GOING_SECONDS
	s.going_said = 0
	if is_bluff:
		s.bluff_hunter = id
		s.bluff_amount = amount
	if amount - prev >= 3 * step_for(prev):
		s.auctioneer.crowd("crowd_gasp")
	s.auctioneer.ding()
	if kind == 1 or randf() < 0.4:
		s.auctioneer.announce("step", "$%d! %s" % [amount, line("AUC_STEP")], 1.0)
	var leader_pos := _leader_pos(s)
	for h in s.hunters:
		if not is_instance_valid(h):
			continue
		if kind == 2 and h.index == id:
			h.raise_paddle(amount)
			if not is_bluff:
				h.say("%d!" % amount, 1.2, "bid")
		elif leader_pos != Vector3.ZERO:
			h.face(leader_pos)
	Net.broadcast_event("auction_bid", {"anchor": s.key, "amount": amount, "kind": kind, "id": id, "name": bidder_name})
	_broadcast_state(s)
	bid_placed.emit(s.anchor, amount, bidder_name, kind == 1)
	return true


func _leader_pos(s: Session) -> Vector3:
	if s.leader_kind == 1:
		var p = Net.players.get(s.leader_id)
		if p and is_instance_valid(p):
			return p.global_position
	elif s.leader_kind == 2:
		var h := _hunter_by_index(s, s.leader_id)
		if h:
			return h.global_position
	return Vector3.ZERO


func _hammer(s: Session) -> void:
	s.state = State.HAMMER
	s.state_age = 0.0
	s.timer = HAMMER_SECONDS
	s.auctioneer.set_murmur(false)
	s.auctioneer.gavel_hit()
	s.auctioneer.announce("sold", tr("AUC_SOLD_FMT") % [s.leader_name, s.current_bid], 2.5)
	_broadcast_state(s)
	session_state.emit(s.key, s.state)


func _no_sale(s: Session) -> void:
	s.auctioneer.set_murmur(false)
	s.auctioneer.announce("sold", line("AUC_NO_BIDS"), 2.5)
	_notify_near(s, tr("AUCTION_NO_SALE"))
	for h in s.hunters:
		if is_instance_valid(h):
			h.on_result(false, "")
	_start_haul(s, null)


func _resolve(s: Session) -> void:
	var amount := s.current_bid
	if s.leader_kind == 1:
		var peer := s.leader_id
		var p = Net.players.get(peer)
		if not Economy.try_spend(amount, "auction"):
			s.auctioneer.announce("angry", line("AUC_CANT_PAY"), 3.0)
			if p and is_instance_valid(p):
				p.say(tr("AUCTION_CANT_PAY"))
			for h in s.hunters:
				if is_instance_valid(h):
					h.on_result(false, "")
			_start_haul(s, null)
			return
		Game.stat_add("auctions_won")
		Achievements.unlock("first_hammer")
		if s.bluff_hunter >= 0 and s.bluff_called:
			Achievements.unlock("bluffed")
		for b in s.items:
			if is_instance_valid(b):
				b.freeze = false
				b.sleeping = false
		s.anchor.open_door()
		s.anchor.set_lamp(not s.anchor.dark)
		for h in s.hunters:
			if is_instance_valid(h):
				h.on_result(false, s.leader_name, true)
		s.auctioneer.announce("sold", line("AUC_SOLD_PLAYER"), 2.5)
		Net.broadcast_event("auction_sold", {"anchor": s.key, "amount": amount, "name": s.leader_name, "peer": peer, "hunter": -1})
		sold.emit(s.anchor, amount, s.leader_name, peer)
		var co = Game.world.system("ClearOut")
		s.items.clear()
		if co and co.has_method("begin"):
			# ClearOut сам двигает lot_cursor / lot_done и позовёт on_clearout_finished(anchor)
			s.handed_off = true
			co.begin(s.anchor, s.preset, peer, amount)
			_to_cooldown(s)
			s.timer = 1e9 # площадка занята вывозом, пока ClearOut не отчитается
		else:
			Game.lot_done(s.preset.id)
			_advance_cursor(s)
			if p and is_instance_valid(p):
				p.say(tr("AUCTION_YOU_WON_TAKE"), 4.0)
			_to_cooldown(s)
	else:
		var h := _hunter_by_index(s, s.leader_id)
		Game.stat_add("auctions_lost")
		_advance_cursor(s)
		for hh in s.hunters:
			if is_instance_valid(hh):
				hh.on_result(hh == h, s.leader_name, false, s.players_bid)
		s.auctioneer.announce("sold", line("AUC_SOLD_HUNTER"), 2.5)
		Net.broadcast_event("auction_sold", {"anchor": s.key, "amount": amount, "name": s.leader_name, "peer": 0, "hunter": s.leader_id})
		sold.emit(s.anchor, amount, s.leader_name, 0)
		_start_haul(s, h)


## Хантер заходит в ячейку, хватает самую ценную вещь, уносит к двери — остальные деспавнятся.
func _start_haul(s: Session, h: Hunter) -> void:
	s.haul_hunter = h
	s.haul_timer = HAUL_SECONDS
	s.haul_picked = false
	s.gloat_said = false
	s.anchor.open_door()
	if h and is_instance_valid(h):
		h.set_meta("home", h.global_position)
		_npc_goto(h, _cell_floor(s.anchor, Vector3(0, 0, -s.anchor.cell_size.z * 0.18)), 2.4)
	_to_cooldown(s)


func _tick_haul(s: Session) -> void:
	var h: Hunter = s.haul_hunter
	if h and is_instance_valid(h) and not s.haul_picked and not h.ragdolled:
		var inside: Vector3 = _cell_floor(s.anchor, Vector3(0, 0, -s.anchor.cell_size.z * 0.18))
		if h.global_position.distance_to(inside) < 0.85 or s.haul_timer < HAUL_SECONDS - 2.7:
			_haul_pick(s)
	var can_gloat: bool = s.haul_picked or h == null or not is_instance_valid(h)
	if not s.gloat_said and can_gloat and s.haul_timer < HAUL_SECONDS - 3.4:
		s.gloat_said = true
		if s.caretaker:
			s.caretaker.shout("gloat", line("CARE_GLOAT"))
		if h and is_instance_valid(h):
			h.say(line("HUNTER_HAUL"), 2.0, "win")


func _haul_pick(s: Session) -> void:
	s.haul_picked = true
	var h: Hunter = s.haul_hunter
	if h == null or not is_instance_valid(h) or h.ragdolled:
		return
	var best := _best_top_item(s)
	if best:
		h.attach_carry(best)
		_broadcast_carry(s, true, false)
	_npc_goto(h, _spot(s.anchor, "", Vector3(0, 0, 1.2)), 2.4)


func _best_top_item(s: Session) -> ItemBody:
	var best: ItemBody = null
	var best_v := -1
	var pool: Array = s.items.duplicate()
	if pool.is_empty() and s.preset:
		for nid in Net.items:
			var it = Net.items[nid]
			if is_instance_valid(it) and it is ItemBody and it.lot_id == s.preset.id:
				pool.append(it)
	for it in pool:
		if not is_instance_valid(it) or not (it is ItemBody):
			continue
		var b: ItemBody = it
		if b.nested_in != null:
			continue
		var v: int = b.current_value()
		if v > best_v:
			best_v = v
			best = b
	return best


func _cell_floor(anchor: LotAnchor, local_xz: Vector3) -> Vector3:
	var p: Vector3 = anchor.cell().global_transform * Vector3(local_xz.x, 0.0, local_xz.z)
	p.y = anchor.global_position.y
	return p


func _carry_payload(s: Session, on: bool, steal: bool) -> Dictionary:
	var h: Hunter = s.haul_hunter
	var nid := 0
	if h and is_instance_valid(h) and h.carried and is_instance_valid(h.carried):
		nid = h.carried.net_id
	return {
		"anchor": s.key,
		"hunter": str(h.get_path()) if h and is_instance_valid(h) else "",
		"idx": h.index if h and is_instance_valid(h) else -1,
		"nid": nid,
		"on": on,
		"steal": steal,
	}


func _broadcast_carry(s: Session, on: bool, steal: bool) -> void:
	Net.broadcast_event("hunter_carry", _carry_payload(s, on, steal))


func on_hunter_drop(h: Hunter, _item: ItemBody) -> void:
	var s := session_for(h.anchor) if h else null
	if s == null:
		s = _session_of_hunter(h)
	if s:
		Net.broadcast_event("hunter_carry", {
			"anchor": s.key,
			"hunter": str(h.get_path()),
			"idx": h.index,
			"nid": _item.net_id if _item and is_instance_valid(_item) else 0,
			"on": false,
			"steal": true,
		})


func _session_of_hunter(h: Hunter) -> Session:
	if h == null:
		return null
	for s: Session in sessions:
		if s.haul_hunter == h:
			return s
		for hh in s.hunters:
			if hh == h:
				return s
	return null


func _finish_haul(s: Session) -> void:
	s.haul_timer = -1.0
	var h: Hunter = s.haul_hunter
	if h and is_instance_valid(h) and h.carried and is_instance_valid(h.carried):
		# уносит с собой — деспавн вместе с остатком лота
		h.drop_carry(false)
		_broadcast_carry(s, false, false)
	if s.preset:
		Game.world.despawn_lot_items(s.preset.id)
	s.items.clear()
	s.anchor.close_door()
	if h and is_instance_valid(h) and h.has_meta("home"):
		_npc_goto(h, h.get_meta("home"), 2.0)
	s.haul_hunter = null
	s.haul_picked = false


func _to_cooldown(s: Session) -> void:
	s.state = State.COOLDOWN
	s.state_age = 0.0
	s.timer = COOLDOWN_SECONDS
	s.auctioneer.set_murmur(false)
	_broadcast_state(s)
	session_state.emit(s.key, s.state)


## ClearOut закончил вывоз на якоре → короткий кулдаун и следующий лот.
func on_clearout_finished(anchor: Node3D) -> void:
	var s := session_for(anchor)
	if s and s.state == State.COOLDOWN and s.handed_off:
		s.timer = minf(s.timer, 5.0)


func _clearout_busy(anchor: LotAnchor) -> bool:
	var co = Game.world.system("ClearOut") if Game.world else null
	if co and co.has_method("is_active") and co.has_method("current_anchor"):
		return co.is_active() and co.current_anchor() == anchor
	return false


func _to_idle(s: Session) -> void:
	s.state = State.IDLE
	s.state_age = 0.0
	s.stand_timer = 0.0
	s.anchor.current_lot_id = ""
	if s.anchor.has_door:
		s.anchor.close_door()
	s.preset = _next_preset(s)
	s.min_bid = s.preset.min_bid if s.preset else 10
	if not s.handed_off and Game.world_mode == Types.WorldMode.AUCTION and not is_active_anywhere():
		Game.set_world_mode(Types.WorldMode.TRAVEL)
	_broadcast_state(s)
	session_state.emit(s.key, s.state)


# ------------------------------------------------------------------ превью (§9): DOOR15 / SLIT / PHOTOS / DOCS / TALE

func _preview_payload(s: Session) -> Dictionary:
	var photos: Array = []
	for id in s.preset.photo_item_ids:
		var d := Registry.item(id)
		photos.append(d.display_name() if d else str(id))
	return {
		"anchor": s.key, "info": s.preset.info_mode, "photos": photos,
		"docs_ru": s.preset.docs_ru, "docs_en": s.preset.docs_en,
		"tale_ru": s.preset.tale_ru, "tale_en": s.preset.tale_en, "sec": s.timer,
	}


## Общее для хоста и клиента: дверь, доска с фото/документами, байка.
func _apply_preview(key: String, d: Dictionary) -> void:
	var anchor := get_node_or_null(NodePath(key)) as LotAnchor
	if anchor == null:
		return
	var ru := TranslationServer.get_locale().begins_with("ru")
	var props: Array = []
	match int(d.get("info", 0)):
		Types.InfoMode.DOOR15:
			if Net.is_host():
				anchor.open_door()
			anchor.set_lamp(not anchor.dark)
		Types.InfoMode.SLIT:
			if Net.is_host():
				_door_slit(anchor)
				Net.broadcast_event("auction_door_slit", {"anchor": key})
		Types.InfoMode.PHOTOS:
			var lines: Array = d.get("photos", [])
			var headless := DisplayServer.get_name() == "headless"
			var body := "\n".join(PackedStringArray(lines)) if headless else ""
			var board := _make_board(anchor, tr("AUCTION_PHOTOS_TITLE"), body, Color(0.95, 0.95, 0.9))
			props.append(board)
			if not headless:
				_kick_polaroids(anchor, board)
		Types.InfoMode.DOCS:
			var text: String = str(d.get("docs_ru", "")) if ru else str(d.get("docs_en", ""))
			props.append(_make_board(anchor, tr("AUCTION_DOCS_TITLE"), text, Color(0.9, 0.85, 0.7)))
		Types.InfoMode.TALE:
			var tale: String = str(d.get("tale_ru", "")) if ru else str(d.get("tale_en", ""))
			if Net.is_host():
				var s: Session = _by_key.get(key)
				if s and s.auctioneer:
					s.auctioneer.announce("tale", tale, float(d.get("sec", 10.0)))
			if _local_near(anchor.global_position) and Game.world and Game.world.hud:
				Game.world.hud.show_subtitle(tale, float(d.get("sec", 10.0)))
	if Net.is_host():
		var s: Session = _by_key.get(key)
		if s:
			s.props.append_array(props)
	else:
		if not _client_props.has(key):
			_client_props[key] = []
		_client_props[key].append_array(props)


func _make_board(anchor: LotAnchor, title: String, text: String, paper: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "PreviewBoard"
	var spot := anchor.get_node_or_null("PreviewSpot") as Node3D
	anchor.add_child(root)
	if spot:
		root.global_position = spot.global_position
	else:
		root.global_position = _spot(anchor, "", Vector3(1.6, 0, 1.6))
	var stand := _stand_pos(anchor)
	stand.y = root.global_position.y
	if stand.distance_to(root.global_position) > 0.05:
		root.look_at(stand, Vector3.UP)
	var post := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.03
	pm.bottom_radius = 0.04
	pm.height = 1.3
	pm.radial_segments = 6
	post.mesh = pm
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.4, 0.28, 0.15)
	post.material_override = wood
	post.position.y = 0.65
	root.add_child(post)
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.1, 0.8, 0.04)
	board.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = paper
	board.material_override = mat
	board.position.y = 1.65
	root.add_child(board)
	var lbl := Label3D.new()
	lbl.text = title + "\n" + text
	lbl.font_size = 30
	lbl.outline_size = 4
	lbl.pixel_size = 0.0035
	lbl.width = 290
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.modulate = Color(0.12, 0.1, 0.1)
	lbl.position = Vector3(0, 1.65, -0.025)
	lbl.rotation.y = PI
	root.add_child(lbl)
	return root


func _kick_polaroids(anchor: LotAnchor, board: Node3D) -> void:
	if board == null or not is_instance_valid(board):
		return
	get_tree().create_timer(0.05).timeout.connect(func() -> void:
		await _render_and_pin_polaroids(anchor, board)
	, CONNECT_ONE_SHOT)


func _photo_views(anchor: LotAnchor) -> Array[Dictionary]:
	var cell: Node3D = anchor.cell()
	var xf: Transform3D = cell.global_transform
	var sz: Vector3 = anchor.cell_size
	var center: Vector3 = anchor.cell_center()
	return [
		{
			"origin": xf * Vector3(0.0, 1.15, sz.z * 0.52 + 1.35),
			"look": center,
			"fov": 52.0,
			"bad": false,
		},
		{
			"origin": xf * Vector3(sz.x * 0.42, 1.35, sz.z * 0.38),
			"look": xf * Vector3(-sz.x * 0.15, 0.4, -sz.z * 0.1),
			"fov": 60.0,
			"bad": false,
		},
		{
			# нарочно плохое: в потолок в угол, тёмное
			"origin": xf * Vector3(-sz.x * 0.08, 0.28, sz.z * 0.18),
			"look": xf * Vector3(sz.x * 0.45, sz.y + 0.6, -sz.z * 0.45),
			"fov": 78.0,
			"bad": true,
		},
	]


func _render_and_pin_polaroids(anchor: LotAnchor, board: Node3D) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if not is_instance_valid(anchor) or not is_instance_valid(board):
		return
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(anchor) or not is_instance_valid(board):
		return
	var vp := SubViewport.new()
	vp.size = PHOTO_SIZE
	vp.transparent_bg = false
	vp.disable_3d = false
	vp.own_world_3d = false
	vp.world_3d = get_viewport().world_3d
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.handle_input_locally = false
	add_child(vp)
	var cam := Camera3D.new()
	cam.current = true
	cam.near = 0.08
	cam.far = 48.0
	vp.add_child(cam)
	var shots: Array[Image] = []
	for view in _photo_views(anchor):
		if not is_instance_valid(cam):
			break
		cam.fov = float(view["fov"])
		cam.global_position = view["origin"]
		var look_pt: Vector3 = view["look"]
		if cam.global_position.distance_to(look_pt) > 0.05:
			var dir: Vector3 = (look_pt - cam.global_position).normalized()
			var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.97 else Vector3.FORWARD
			cam.look_at(look_pt, up)
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		if not is_instance_valid(vp):
			break
		var tex: ViewportTexture = vp.get_texture()
		if tex == null:
			continue
		var img: Image = tex.get_image()
		if img == null:
			continue
		var copy: Image = img.duplicate() as Image
		if copy == null:
			continue
		if copy.get_format() != Image.FORMAT_RGBA8:
			copy.convert(Image.FORMAT_RGBA8)
		if bool(view.get("bad", false)):
			copy.adjust_bcs(0.22, 1.12, 0.65)
		shots.append(copy)
	if is_instance_valid(vp):
		vp.queue_free()
	if is_instance_valid(board) and not shots.is_empty():
		_pin_polaroids(board, shots)


func _pin_polaroids(board: Node3D, shots: Array[Image]) -> void:
	var poses: Array[Vector3] = [
		Vector3(-0.28, 1.72, -0.032),
		Vector3(0.06, 1.80, -0.038),
		Vector3(0.24, 1.52, -0.030),
	]
	var rots: Array[float] = [-0.14, 0.10, 0.20]
	var sizes: Array[Vector2] = [Vector2(0.34, 0.28), Vector2(0.32, 0.26), Vector2(0.30, 0.25)]
	for i in mini(shots.size(), 3):
		var mi := _make_polaroid_quad(shots[i], sizes[i])
		mi.position = poses[i]
		mi.rotation = Vector3(0.0, PI, rots[i])
		board.add_child(mi)


func _make_polaroid_quad(img: Image, size: Vector2) -> MeshInstance3D:
	var bw := 10
	var bh := 22
	var framed := Image.create(img.get_width() + bw * 2, img.get_height() + bw + bh, false, Image.FORMAT_RGBA8)
	framed.fill(Color(0.98, 0.97, 0.94))
	framed.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(bw, bw))
	var tex := ImageTexture.create_from_image(framed)
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color.WHITE
	mat.albedo_texture = tex
	mi.material_override = mat
	return mi


func _door_slit(anchor: LotAnchor) -> void:
	var door := anchor.get_node_or_null("Door") as Node3D
	if door == null:
		return
	var closed_y: float = anchor._door_open_y - anchor.cell_size.y
	var tw := create_tween()
	tw.tween_property(door, "position:y", closed_y + SLIT_OPEN, 1.0)
	AudioBus.play_at("door_roll", door.global_position, -4.0)


func _clear_props(s: Session) -> void:
	for p in s.props:
		if is_instance_valid(p):
			p.queue_free()
	s.props.clear()


func _client_clear(key: String) -> void:
	for p in _client_props.get(key, []):
		if is_instance_valid(p):
			p.queue_free()
	_client_props.erase(key)


# ------------------------------------------------------------------ превью: смотритель против нарушителей

func _check_trespass(s: Session) -> void:
	for pid in Net.players:
		var p = Net.players[pid]
		if not is_instance_valid(p) or p.dead:
			continue
		var inside: bool = s.anchor.is_inside(p.global_position)
		var was: bool = s.inside.get(pid, false)
		if inside and not was:
			var n: int = int(s.trespass.get(pid, 0)) + 1
			s.trespass[pid] = n
			if n == 1:
				s.caretaker.shout("warn", line("CARE_WARN"))
				p.say(tr("AUCTION_TRESPASS_WARN"), 3.0)
			else:
				s.caretaker.shout("angry", line("CARE_BAN"), 3.0)
				p.say(tr("AUCTION_TRESPASS_BAN"), 3.0)
				if s.district_id >= 0:
					Game.blacklist(s.district_id)
				var police = Game.world.system("Police")
				if police and police.has_method("trigger"):
					police.trigger(Types.PoliceTrigger.BLACKLIST_ENTRY, p.global_position, p)
		s.inside[pid] = inside


# ------------------------------------------------------------------ угроза (§9) и потасовка

## Игрок тычет стволом в аукциониста: 50% скидка, 30% выгон + ЧС, 20% менты.
func threaten(anchor: Node3D, player: Node, auctioneer: Auctioneer) -> void:
	var s := session_for(anchor)
	if s == null:
		return
	Achievements.unlock("threat")
	Game.stat_add("threats")
	var r := randf()
	if r < 0.5:
		s.min_bid = maxi(1, s.min_bid / 2)
		if s.preset and s.state == State.IDLE:
			s.min_bid = maxi(1, s.preset.min_bid / 2)
		auctioneer.announce("threatened", line("AUC_THREATENED"), 3.0)
		_broadcast_state(s)
	elif r < 0.8:
		auctioneer.announce("angry", line("AUC_EJECT"), 3.0)
		_eject(player, s)
		if s.district_id >= 0:
			Game.blacklist(s.district_id)
	else:
		auctioneer.announce("police", line("AUC_POLICE"), 3.0)
		var police = Game.world.system("Police")
		if police and police.has_method("trigger"):
			police.trigger(Types.PoliceTrigger.THREAT, player.global_position, player)
		if "wanted" in player:
			player.wanted = maxf(player.wanted, 1.0)


func _eject(player: Node, s: Session) -> void:
	var root: Node3D = Game.world.district_root(s.district_id) if s.district_id >= 0 else null
	var pos: Vector3
	if root:
		var dir: Vector3 = player.global_position - root.global_position
		dir.y = 0.0
		dir = dir.normalized() if dir.length() > 0.1 else Vector3.BACK
		var radius: float = root.get("radius") if "radius" in root else 30.0
		pos = root.global_position + dir * (radius + 4.0)
	else:
		pos = s.anchor.global_position + Vector3(0, 0, 18.0)
	pos.y += 1.0
	_teleport_player(player, pos)
	if player.has_method("say"):
		player.say(tr("NOTIFY_BLACKLISTED"))


func _teleport_player(player: Node, pos: Vector3) -> void:
	player.global_position = pos
	if "velocity" in player:
		player.velocity = Vector3.ZERO
	if player.get("peer_id") != null and not player.is_local():
		Net.broadcast_event("auction_teleport", {"peer": player.peer_id, "pos": pos})


func on_hunter_pass(h: Hunter) -> void:
	if h.anchor:
		Net.broadcast_event("auction_hunter_pass", {"anchor": key_of(h.anchor), "idx": h.index})


func on_hunter_shoved(_h: Hunter, _player: Node) -> void:
	Game.stat_add("hunter_shoves")


## Хантера уронили. 2+ раза за аукцион → менты за драку и (50%) бан площадки.
func on_hunter_ragdoll(h: Hunter, culprit: Node, count: int) -> void:
	if culprit == null:
		return
	Achievements.unlock("brawler")
	var s := session_for(h.anchor)
	if s == null or s.brawl_flagged or count < 2:
		return
	s.brawl_flagged = true
	s.auctioneer.announce("angry", line("AUC_BRAWL"), 3.0)
	var police = Game.world.system("Police")
	if police and police.has_method("trigger"):
		police.trigger(Types.PoliceTrigger.BRAWL, h.global_position, culprit)
	if randf() < 0.5 and s.district_id >= 0:
		Game.blacklist(s.district_id)


# ------------------------------------------------------------------ действия игроков (хост)

func handle_action(peer: int, kind: String, data: Dictionary) -> bool:
	match kind:
		"bid":
			_player_bid(peer, int(data.get("amount", 0)))
			return true
		"paddle_show":
			return true
		"paddle_value":
			if Net.peer_count() > 1:
				Net.broadcast_event("auction_paddle", {"peer": peer, "v": int(data.get("v", 0))})
			return true
	return false


func _player_bid(peer: int, amount: int) -> void:
	var p = Net.players.get(peer)
	if p == null or not is_instance_valid(p) or p.dead:
		return
	var s := _nearest_session(p.global_position, State.BIDDING)
	if s == null:
		p.say(tr("AUCTION_NO_AUCTION"))
		return
	if s.leader_kind == 1 and s.leader_id == peer:
		p.say(tr("AUCTION_ALREADY_LEADING"))
		return
	var req := required_bid(s)
	if amount < req:
		_notify_bid_too_low(peer, req)
		return
	if not Economy.can_afford(amount):
		p.say(tr("AUCTION_TOO_POOR"))
		AudioBus.play_at("buzzer", p.global_position, -6.0)
		return
	var pname: String = p.name_plate.text if p.get("name_plate") else "P%d" % peer
	_place_bid(s, amount, 1, peer, pname)


func _notify_bid_too_low(peer: int, req: int) -> void:
	if not Net.is_host():
		return
	Net.send_event(peer, "auction_bid_reject", {"req": req})


func _nearest_session(pos: Vector3, want_state: int) -> Session:
	var best: Session = null
	var best_d := HUD_RADIUS
	for s: Session in sessions:
		if s.state != want_state or not is_instance_valid(s.anchor):
			continue
		var d: float = s.anchor.global_position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = s
	return best


# ------------------------------------------------------------------ сеть: рассылка

func _state_payload(s: Session) -> Dictionary:
	return {
		"anchor": s.key, "state": s.state,
		"bid": s.current_bid if s.has_bids else s.min_bid, "has_bids": s.has_bids,
		"min_bid": s.min_bid, "req": required_bid(s), "step": step_for(s.current_bid if s.has_bids else s.min_bid),
		"leader_name": s.leader_name, "leader_is_player": s.leader_kind == 1,
		"leader_peer": s.leader_id if s.leader_kind == 1 else 0,
		"going": s.going if s.state == State.BIDDING else 0.0, "timer": s.timer,
		"lot": s.preset.id if s.preset else "", "info": s.preset.info_mode if s.preset else 0,
		"pos": s.anchor.global_position,
	}


func _broadcast_state(s: Session) -> void:
	Net.broadcast_event("auction_state", _state_payload(s))


func _look_of(n: Npc, extra: Dictionary = {}) -> Dictionary:
	var d := {
		"node": n.name, "name": n.display_name, "color": [n.body_color.r, n.body_color.g, n.body_color.b],
		"h": n.height, "f": n.fatness, "hat": n.hat, "bald": n.bald, "pitch": n.voice_pitch,
		"pos": n.global_position, "yaw": n.rotation.y,
	}
	d.merge(extra)
	return d


func _npcs_payload(s: Session) -> Dictionary:
	var hs: Array = []
	for h in s.hunters:
		if is_instance_valid(h):
			hs.append(_look_of(h, {
				"idx": h.index,
				"ink": [h.marker_ink.r, h.marker_ink.g, h.marker_ink.b],
				"scrawl": h.scrawl_seed,
				"amt": h.paddle_amount,
			}))
	return {"anchor": s.key, "auctioneer": _look_of(s.auctioneer), "caretaker": _look_of(s.caretaker), "hunters": hs}


func _broadcast_npcs(s: Session) -> void:
	if Net.peer_count() > 1:
		Net.broadcast_event("auction_npcs", _npcs_payload(s))


func _npc_goto(n: Node3D, pos: Vector3, sec: float) -> void:
	_goto_visual(n, pos, sec)
	if Net.peer_count() > 1:
		Net.broadcast_event("auction_npc_goto", {"path": str(n.get_path()), "pos": pos, "sec": sec})


func _goto_visual(n: Node3D, pos: Vector3, sec: float) -> void:
	if n is Npc:
		n.face(pos)
	var tw := n.create_tween()
	tw.tween_property(n, "global_position", pos, sec)


func send_full_state_to(peer: int) -> void:
	for s in sessions:
		if not is_instance_valid(s.anchor):
			continue
		Net.send_event(peer, "auction_npcs", _npcs_payload(s))
		Net.send_event(peer, "lot_door", {"path": s.key, "closed": s.anchor.door_closed})
		if s.state == State.PREVIEW or s.state == State.BIDDING:
			Net.send_event(peer, "auction_preview", _preview_payload(s))
		Net.send_event(peer, "auction_state", _state_payload(s))
		if s.haul_hunter and is_instance_valid(s.haul_hunter) and s.haul_hunter.carried:
			Net.send_event(peer, "hunter_carry", _carry_payload(s, true, false))


# ------------------------------------------------------------------ сеть: приём (хост и клиент)

func on_net_event(kind: String, data: Dictionary) -> void:
	match kind:
		"auction_state":
			var key := str(data.get("anchor", ""))
			_view[key] = data
			if not Net.is_host():
				session_state.emit(key, int(data.get("state", 0)))
		"auction_npcs":
			if not Net.is_host():
				_client_apply_npcs(data)
		"auction_bid":
			if not Net.is_host():
				_client_bid_fx(data)
		"auction_preview":
			if not Net.is_host():
				_apply_preview(str(data.get("anchor", "")), data)
		"auction_clear":
			if not Net.is_host():
				_client_clear(str(data.get("anchor", "")))
		"auction_sold":
			_sold_fx(data)
		"auction_door_slit":
			if not Net.is_host():
				var a := get_node_or_null(NodePath(str(data.get("anchor", "")))) as LotAnchor
				if a:
					_door_slit(a)
		"auction_npc_goto":
			if not Net.is_host():
				var n := get_node_or_null(NodePath(str(data.get("path", "")))) as Node3D
				if n:
					_goto_visual(n, data.get("pos", n.global_position), float(data.get("sec", 1.0)))
		"auction_hunter_pass":
			if not Net.is_host():
				var h := _client_hunter(str(data.get("anchor", "")), int(data.get("idx", -1)))
				if h:
					h.show_pass()
		"auction_shove":
			if int(data.get("peer", 0)) == Net.my_id() and not Net.is_host():
				var p = Game.world.local_player() if Game.world else null
				if p:
					p.velocity += data.get("imp", Vector3.ZERO)
		"auction_teleport":
			if int(data.get("peer", 0)) == Net.my_id() and not Net.is_host():
				var p = Game.world.local_player() if Game.world else null
				if p:
					p.global_position = data.get("pos", p.global_position)
					p.velocity = Vector3.ZERO
		"lot_door":
			if not Net.is_host():
				var a := get_node_or_null(NodePath(str(data.get("path", "")))) as LotAnchor
				if a:
					if bool(data.get("closed", false)):
						a.close_door()
					else:
						a.open_door()
		"hunter_carry":
			if not Net.is_host():
				_client_hunter_carry(data)


func _client_apply_npcs(d: Dictionary) -> void:
	var key := str(d.get("anchor", ""))
	var anchor := get_node_or_null(NodePath(key)) as LotAnchor
	var old: Dictionary = _client_npcs.get(key, {})
	var stale: Array = old.get("hunters", []).duplicate()
	for k in ["auctioneer", "caretaker"]:
		if old.has(k):
			stale.append(old[k])
	for n in stale:
		if is_instance_valid(n):
			if n.get_parent():
				n.get_parent().remove_child(n)
			n.queue_free()
	var root: Node = Game.world.npcs_root if Game.world else get_parent()
	var rec := {"hunters": []}
	var auc := Auctioneer.new()
	auc.auction = self
	auc.anchor = anchor
	_apply_look(auc, d.get("auctioneer", {}))
	root.add_child(auc)
	_place_look(auc, d.get("auctioneer", {}))
	rec["auctioneer"] = auc
	var care := Caretaker.new()
	care.auction = self
	care.anchor = anchor
	_apply_look(care, d.get("caretaker", {}))
	root.add_child(care)
	_place_look(care, d.get("caretaker", {}))
	rec["caretaker"] = care
	for hd in d.get("hunters", []):
		var h := Hunter.new()
		h.index = int(hd.get("idx", 0))
		h.auction = self
		h.anchor = anchor
		_apply_look(h, hd)
		root.add_child(h)
		_place_look(h, hd)
		rec["hunters"].append(h)
	_client_npcs[key] = rec


func _apply_look(n: Npc, d: Dictionary) -> void:
	if d.is_empty():
		return
	n.name = str(d.get("node", n.name))
	n.display_name = str(d.get("name", ""))
	var c: Array = d.get("color", [0.6, 0.5, 0.4])
	n.body_color = Color(c[0], c[1], c[2])
	n.height = float(d.get("h", 1.75))
	n.fatness = float(d.get("f", 1.0))
	n.hat = bool(d.get("hat", false))
	n.bald = bool(d.get("bald", false))
	n.voice_pitch = float(d.get("pitch", 1.0))
	if n is Hunter:
		var hh: Hunter = n
		if d.has("ink"):
			var ic: Array = d["ink"]
			hh.marker_ink = Color(float(ic[0]), float(ic[1]), float(ic[2]), 0.95)
		if d.has("scrawl"):
			hh.scrawl_seed = int(d["scrawl"])
		hh.paddle_amount = int(d.get("amt", 0))


func _place_look(n: Npc, d: Dictionary) -> void:
	if d.is_empty():
		return
	n.global_position = d.get("pos", Vector3.ZERO)
	n.rotation.y = float(d.get("yaw", 0.0))


func _client_hunter_carry(data: Dictionary) -> void:
	var h := get_node_or_null(NodePath(str(data.get("hunter", "")))) as Hunter
	if h == null:
		h = _client_hunter(str(data.get("anchor", "")), int(data.get("idx", -1)))
	if h == null:
		return
	if bool(data.get("on", false)):
		var b = Net.items.get(int(data.get("nid", 0)))
		if b is ItemBody:
			h.attach_carry(b)
	else:
		h.drop_carry(bool(data.get("steal", false)))


func _client_hunter(key: String, idx: int) -> Hunter:
	for h in _client_npcs.get(key, {}).get("hunters", []):
		if is_instance_valid(h) and h.index == idx:
			return h
	return null


func _client_bid_fx(d: Dictionary) -> void:
	var key := str(d.get("anchor", ""))
	var rec: Dictionary = _client_npcs.get(key, {})
	var auc = rec.get("auctioneer")
	if auc and is_instance_valid(auc):
		auc.ding()
	var kind := int(d.get("kind", 0))
	var id := int(d.get("id", 0))
	var leader_pos := Vector3.ZERO
	if kind == 1:
		var p = Net.players.get(id)
		if p and is_instance_valid(p):
			leader_pos = p.global_position
	for h in rec.get("hunters", []):
		if not is_instance_valid(h):
			continue
		if kind == 2 and h.index == id:
			h.raise_paddle(int(d.get("amount", 0)))
			leader_pos = h.global_position
	if leader_pos != Vector3.ZERO:
		for h in rec.get("hunters", []):
			if is_instance_valid(h) and not (kind == 2 and h.index == id):
				h.face(leader_pos)


func _sold_fx(d: Dictionary) -> void:
	var key := str(d.get("anchor", ""))
	if not Net.is_host():
		var rec: Dictionary = _client_npcs.get(key, {})
		var auc = rec.get("auctioneer")
		if auc and is_instance_valid(auc):
			auc.gavel_hit()
	var anchor := get_node_or_null(NodePath(key)) as Node3D
	if anchor == null or not _local_near(anchor.global_position):
		return
	var hud = Game.world.hud if Game.world else null
	if hud == null:
		return
	var amount := int(d.get("amount", 0))
	if int(d.get("peer", 0)) == Net.my_id():
		hud.toast(tr("AUCTION_YOU_WON") % amount, 5.0)
		AudioBus.play_ui("fanfare", -4.0)
	else:
		hud.toast(tr("AUCTION_SOLD_TO") % [str(d.get("name", "")), amount], 4.0)


func _local_near(pos: Vector3) -> bool:
	var p = Game.world.local_player() if Game.world else null
	return p != null and is_instance_valid(p) and p.global_position.distance_to(pos) < HUD_RADIUS


func _notify_near(s: Session, text: String) -> void:
	for pid in Net.players:
		var p = Net.players[pid]
		if is_instance_valid(p) and p.global_position.distance_to(s.anchor.global_position) < HUD_RADIUS:
			p.say(text, 3.0)


# ------------------------------------------------------------------ худ (локально, из последнего auction_state)

func _process(delta: float) -> void:
	if Game.world == null:
		return
	var p = Game.world.local_player()
	var hud = Game.world.hud
	if p == null or not is_instance_valid(p) or hud == null:
		return
	var best: Dictionary = {}
	var best_d := HUD_RADIUS
	for k in _view:
		var v: Dictionary = _view[k]
		var st := int(v.get("state", 0))
		if st != State.PREVIEW and st != State.BIDDING and st != State.HAMMER:
			continue
		var dpos: float = (v.get("pos", Vector3.ZERO) as Vector3).distance_to(p.global_position)
		if dpos < best_d:
			best_d = dpos
			best = v
	if best.is_empty():
		if _hud_key != "":
			_hud_key = ""
			hud.set_bid(-1, "", false)
			if Game.world_mode == Types.WorldMode.AUCTION:
				hud.clear_timer()
		return
	if not bool(Game.save.get("bid_coached", false)) and int(best.get("state", 0)) == State.BIDDING:
		Game.save["bid_coached"] = true
		hud.toast(tr("AUC_COACH"), 6.0)
	_hud_key = str(best["anchor"])
	best["timer"] = maxf(0.0, float(best.get("timer", 0.0)) - delta)
	best["going"] = maxf(0.0, float(best.get("going", 0.0)) - delta)
	var mine := int(best.get("leader_peer", 0)) == Net.my_id() and bool(best.get("leader_is_player", false))
	match int(best["state"]):
		State.PREVIEW:
			hud.set_timer(float(best["timer"]), "HUD_PREVIEW")
			hud.set_bid(int(best.get("min_bid", 0)), tr("AUCTION_START_PRICE"), false, int(best.get("req", 0)))
		State.BIDDING:
			hud.set_timer(float(best["going"]), "HUD_BID")
			var leader := str(best.get("leader_name", ""))
			hud.set_bid(int(best.get("bid", 0)), leader if bool(best.get("has_bids", false)) else tr("AUCTION_NO_BIDS"), mine, int(best.get("req", 0)))
		State.HAMMER:
			hud.set_timer(0.0, "HUD_BID")
			hud.set_bid(int(best.get("bid", 0)), str(best.get("leader_name", "")), mine, int(best.get("req", 0)))
