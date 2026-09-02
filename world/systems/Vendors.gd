class_name Vendors
extends Node3D
## Скупщики (§11). Хост считает, клиент просит. Прилавок = физика: DropZone ловит вещи.
## Поток: положил → орёт → оффер (или враньё телефона) → ок / часть / отказ → ПОЛОСКА → котёл → деспавн.
## Витрины нет. Скупщик всегда покупает — спор только о цене (§2.3). Скупщики анлокятся с одного крошечного.
##
## Действия (клиент → хост):  vendor_offer {stand, nid, amount} · haggle_result {nid, hit, precision}
## События (хост → все):      vendor_open {peer, stand, vendor, items[{nid,name,fair}]} · haggle_start {...}
##                            vendor_sold {stand, nid, name, amount, peer, why} · vendor_unlocked {stand, silent}
##                            vendor_scare {stand}
## Маркеры (район VENDORS):   VendorStand_<vendor_id>/{Counter, DropZone, NpcSpot, PlayerSpot, PhotoSpot}

const HAGGLE_TIMEOUT := 20.0
const PHOBIA_REFUSE_SEC := 6.0
const INTERACT_RANGE := 7.0
const UI_SCENE := "res://ui/haggle_bar/HaggleBar.tscn"
const PHONE_SCENE := "res://ui/phone/Phone.tscn"


## Интерактив, которым владеет система (сцены районов не трогаем): тонкий невидимый бокс на L_TRIGGER,
## игрок жмёт E → хост зовёт interact(player) → on_interact. Хинт на прицеле — on_hint.
class Interactable extends StaticBody3D:
	var on_interact: Callable
	var on_hint: Callable

	func _init(size: Vector3 = Vector3(1.2, 0.5, 0.15)) -> void:
		collision_layer = Types.L_TRIGGER
		collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		add_child(cs)

	func interact(player: Player) -> void:
		if on_interact.is_valid():
			on_interact.call(player)

	func interact_hint(player: Player) -> String:
		if on_hint.is_valid():
			return str(on_hint.call(player))
		return "[E]"


class Stand:
	var def: VendorDef
	var root: Node3D
	var counter: Node3D
	var drop_zone: Area3D
	var npc_spot: Node3D
	var player_spot: Node3D
	var photo_spot: Node3D
	var vendor: Vendor
	var items: Array[ItemBody] = []
	var unlocked := false
	var closed_label: Label3D
	var sign: Label3D
	var interact: Interactable

	func counter_pos() -> Vector3:
		if counter:
			return counter.global_position
		return root.global_position

	## Горизонтальное направление от прилавка к игроку.
	func front() -> Vector3:
		var f := Vector3.ZERO
		if player_spot:
			f = player_spot.global_position - counter_pos()
		elif npc_spot:
			f = counter_pos() - npc_spot.global_position
		else:
			f = root.global_basis.z
		f.y = 0.0
		return f.normalized() if f.length() > 0.01 else Vector3.FORWARD

	func sellable() -> Array[ItemBody]:
		var out: Array[ItemBody] = []
		for b in items:
			if b == null or not is_instance_valid(b):
				continue
			if b.is_held() or b.nested_in != null or b.def.is_cash() or b.has_meta("vendor_refused"):
				continue
			out.append(b)
		return out


var stands: Dictionary = {} # vendor_id → Stand
var ui: HaggleBar
var phone: PhoneOverlay
var _pending: Dictionary = {} # peer → {stand, nid, hit, miss, green_w, t}
var _unlocked_ids: Dictionary = {} # клиент: что хост сказал открытым
var _district_players := 0


func system_name() -> String:
	return "Vendors"


func _ready() -> void:
	Net.item_despawned.connect(_on_item_despawned)
	var ui_scene: PackedScene = load(UI_SCENE)
	if ui_scene:
		ui = ui_scene.instantiate() as HaggleBar
		add_child(ui)
		ui.offer_sent.connect(func(stand: String, nid: int, amount: int):
			Net.request_action("vendor_offer", {"stand": stand, "nid": nid, "amount": amount}))
		ui.bar_finished.connect(func(nid: int, hit: bool, precision: float):
			Net.request_action("haggle_result", {"nid": nid, "hit": hit, "precision": precision}))
		ui.phone_requested.connect(_on_phone_requested)
	var phone_scene: PackedScene = load(PHONE_SCENE)
	if phone_scene:
		phone = phone_scene.instantiate() as PhoneOverlay
		add_child(phone)
	_deferred_setup()


func _deferred_setup() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_setup_city()
	_hook_district()


func _world() -> World:
	return Game.world as World


# ------------------------------------------------------------------ стенды

func _find_stand_root(vendor_id: String) -> Node3D:
	var w := _world()
	if w == null:
		return null
	var name := "VendorStand_%s" % vendor_id
	var n := w.find_marker(Types.District.VENDORS, name)
	if n == null and w.city:
		n = w.city.find_child(name, true, false) as Node3D
	return n


func _setup_city() -> void:
	for def in Registry.all_vendors():
		if stands.has(def.id):
			continue
		var root := _find_stand_root(def.id)
		if root == null:
			continue
		register_stand(def, root)


## Публично: стенд из готового корня (дети Counter/DropZone/NpcSpot/PlayerSpot/PhotoSpot; все опциональны).
func register_stand(def: VendorDef, root: Node3D) -> Stand:
	if def == null or root == null:
		return null
	if stands.has(def.id):
		return stands[def.id]
	var s := Stand.new()
	s.def = def
	s.root = root
	s.counter = root.find_child("Counter", true, false) as Node3D
	s.drop_zone = root.find_child("DropZone", true, false) as Area3D
	s.npc_spot = root.find_child("NpcSpot", true, false) as Node3D
	s.player_spot = root.find_child("PlayerSpot", true, false) as Node3D
	s.photo_spot = root.find_child("PhotoSpot", true, false) as Node3D
	if s.drop_zone == null:
		s.drop_zone = Area3D.new()
		s.drop_zone.name = "DropZone_%s" % def.id
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.6, 0.9, 0.9)
		cs.shape = bs
		s.drop_zone.add_child(cs)
		add_child(s.drop_zone)
		s.drop_zone.global_position = s.counter_pos() + Vector3(0, 1.45, 0)
	s.drop_zone.collision_layer = s.drop_zone.collision_layer | Types.L_TRIGGER
	s.drop_zone.collision_mask = s.drop_zone.collision_mask | Types.L_ITEM
	s.drop_zone.monitoring = true
	s.drop_zone.body_entered.connect(_on_zone_enter.bind(s))
	s.drop_zone.body_exited.connect(_on_zone_exit.bind(s))
	s.unlocked = def.unlock_cost <= 0 or _unlocked_ids.has(def.id) or (Net.is_host() and Game.is_vendor_unlocked(def.id))
	# интерактив у передней кромки прилавка
	var front := s.front()
	var extent := _extent_along(s.counter, front) if s.counter else 0.5
	s.interact = Interactable.new(Vector3(1.6, 0.7, 0.18))
	s.interact.name = "StandInteract_%s" % def.id
	add_child(s.interact)
	s.interact.global_position = s.counter_pos() + front * (extent + 0.1) + Vector3(0, 0.85, 0)
	s.interact.global_basis = Basis.looking_at(front, Vector3.UP)
	s.interact.on_interact = _on_stand_interact.bind(s)
	s.interact.on_hint = _stand_hint.bind(s)
	# вывеска
	s.sign = Label3D.new()
	s.sign.text = def.display_name()
	s.sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.sign.font_size = 72
	s.sign.outline_size = 12
	s.sign.pixel_size = 0.006
	s.sign.modulate = Color(1, 0.9, 0.5)
	add_child(s.sign)
	s.sign.global_position = s.counter_pos() + Vector3(0, 2.3, 0)
	stands[def.id] = s
	_apply_open_state(s)
	return s


## Полуразмер коллайдера/меша узла вдоль направления (для точки интерактива у кромки стола).
func _extent_along(n: Node3D, dir: Vector3) -> float:
	var best := 0.0
	var local_dir := (n.global_basis.inverse() * dir).abs()
	for c in n.get_children():
		if c is CollisionShape3D and c.shape is BoxShape3D:
			var half: Vector3 = (c.shape as BoxShape3D).size * 0.5
			best = maxf(best, absf(local_dir.dot(half)) + absf(local_dir.dot((c as Node3D).position)))
		elif c is MeshInstance3D and c.mesh:
			var aabb: AABB = (c as MeshInstance3D).mesh.get_aabb()
			best = maxf(best, absf(local_dir.dot(aabb.size * 0.5)) + absf(local_dir.dot((c as Node3D).position)))
	return best if best > 0.05 else 0.5


func _apply_open_state(s: Stand) -> void:
	if s.unlocked:
		if s.closed_label:
			s.closed_label.queue_free()
			s.closed_label = null
		if s.vendor == null:
			_spawn_vendor(s)
	else:
		if s.closed_label == null:
			s.closed_label = Label3D.new()
			s.closed_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			s.closed_label.font_size = 48
			s.closed_label.outline_size = 10
			s.closed_label.pixel_size = 0.005
			s.closed_label.modulate = Color(1, 0.4, 0.3)
			add_child(s.closed_label)
			s.closed_label.global_position = s.counter_pos() + Vector3(0, 1.7, 0)
		s.closed_label.text = tr("VEND_CLOSED") % s.def.unlock_cost


func _spawn_vendor(s: Stand) -> void:
	var v := Vendor.new()
	v.setup(s.def)
	v.name = "Vendor_%s" % s.def.id
	var w := _world()
	var parent: Node = w.npcs_root if (w and w.npcs_root) else self
	parent.add_child(v)
	var front := s.front()
	var spot := s.npc_spot.global_position if s.npc_spot else s.counter_pos() - front * 0.9
	var face_pos := s.player_spot.global_position if s.player_spot else s.counter_pos() + front * 1.5
	v.place(spot + Vector3(0, 0.05, 0), face_pos, face_pos)
	s.vendor = v


func _stand_hint(_player: Player, s: Stand) -> String:
	if not s.unlocked:
		var req := s.def.unlock_requires_vendor
		if req != "" and not _is_unlocked_id(req):
			var rd := Registry.vendor(req)
			return tr("VEND_NEED_PREV") % (rd.display_name() if rd else req)
		return tr("VEND_UNLOCK_HINT") % s.def.unlock_cost
	if s.vendor and s.vendor.is_refusing():
		return tr("VEND_HINT_REFUSING")
	var n := s.sellable().size()
	if n == 0:
		return tr("VEND_HINT_EMPTY")
	return tr("VEND_HINT_SELL") % n


func _is_unlocked_id(id: String) -> bool:
	if Net.is_host():
		return Game.is_vendor_unlocked(id)
	var s: Stand = stands.get(id)
	return _unlocked_ids.has(id) or (s != null and s.unlocked)


# ------------------------------------------------------------------ прилавок (хост)

func _on_zone_enter(b: Node, s: Stand) -> void:
	if not Net.is_host() or not (b is ItemBody):
		return
	var item := b as ItemBody
	if item.nested_in != null:
		return
	if item.is_held():
		# ждём, пока отпустят, и проверяем, осталось ли на прилавке
		if item.has_meta("vend_wait"):
			return
		item.set_meta("vend_wait", s.def.id)
		item.dropped.connect(func(bb: ItemBody): _recheck_dropped(bb, s), CONNECT_ONE_SHOT)
		return
	_on_landed(item, s)


func _recheck_dropped(b: ItemBody, s: Stand) -> void:
	await get_tree().create_timer(0.4).timeout
	if not is_instance_valid(b):
		return
	b.remove_meta("vend_wait")
	if b.is_held() or not is_instance_valid(s.drop_zone):
		return
	if s.drop_zone.overlaps_body(b):
		_on_landed(b, s)


func _on_zone_exit(b: Node, s: Stand) -> void:
	if b is ItemBody:
		s.items.erase(b as ItemBody)


func _on_item_despawned(_nid: int) -> void:
	for id in stands:
		var s: Stand = stands[id]
		for i in range(s.items.size() - 1, -1, -1):
			if not is_instance_valid(s.items[i]):
				s.items.remove_at(i)


func _on_landed(b: ItemBody, s: Stand) -> void:
	if s.items.has(b):
		return
	if b.def.is_cash():
		# купюра на прилавке → в котёл (сдача в котёл, §6.3)
		AudioBus.play_at("coin", b.global_position, 0.0)
		Economy.deposit_bill(b)
		Game.stat_add("bills_deposited")
		return
	s.items.append(b)
	if not s.unlocked or s.vendor == null:
		return
	var v := s.vendor
	var ph := _phobia_for(s.def, b)
	if ph != Types.Phobia.NONE:
		v.say_line("phobia", "VEND_PHOBIA_DEFAULT", 3.0)
		v.scare(-s.front(), PHOBIA_REFUSE_SEC)
		if ph == Types.Phobia.TAPE or ph == Types.Phobia.PAINT:
			b.set_meta("phobia_discount", true)
		Achievements.unlock("phobia")
		Net.broadcast_event("vendor_scare", {"stand": s.def.id})
		return
	if _is_illegal(b):
		if s.def.buys_illegal:
			v.say(tr("VEND_ILLEGAL_OK"), 2.5, "deal")
		elif s.def.calls_police_on_illegal:
			v.say(tr("VEND_ILLEGAL_POLICE"), 3.0, "scream")
			b.set_meta("vendor_refused", true)
			var w := _world()
			var police: Node = w.system("Police") if w else null
			if police and police.has_method("trigger"):
				police.trigger(Types.PoliceTrigger.ILLEGAL_SALE, b.global_position, _nearest_player(b.global_position))
			return
	if b.integrity == Types.Integrity.SHARDS:
		v.say(tr("VEND_SHARDS_LAND"), 2.5, "scream")
	else:
		v.say_line("scream", "VEND_SCREAM_DEFAULT", 2.5)


func _phobia_for(def: VendorDef, b: ItemBody) -> int:
	for ph in def.phobias:
		match int(ph):
			Types.Phobia.MOUSE:
				if b.def.tags.has("mouse"): return ph
			Types.Phobia.HAMSTER:
				if b.def.tags.has("hamster"): return ph
			Types.Phobia.TAPE:
				if b.taped: return ph
			Types.Phobia.PAINT:
				if b.paint_color.a > 0.2: return ph
			Types.Phobia.WET:
				if b.wet > 0.2: return ph
			Types.Phobia.FIRE:
				if b.lit: return ph
	return Types.Phobia.NONE


func _is_illegal(b: ItemBody) -> bool:
	return b.def.illegal or b.def.has_facet(Types.Facet.ILLEGAL)


func _nearest_player(pos: Vector3) -> Player:
	var best: Player = null
	var best_d := 8.0
	for pid in Net.players:
		var p = Net.players[pid]
		if p and is_instance_valid(p) and not p.dead:
			var d: float = p.global_position.distance_to(pos)
			if d < best_d:
				best_d = d
				best = p
	return best


## «Честная» цена скупщика с учётом фобий/незаконки. Осколки — $1.
func price_for(stand_id: String, b: ItemBody) -> int:
	var s: Stand = stands.get(stand_id)
	if s == null:
		return b.current_value()
	return _price_for(s, b)


func _price_for(s: Stand, b: ItemBody) -> int:
	if b.integrity == Types.Integrity.SHARDS:
		return b.current_value(s.def)
	var v := float(b.current_value(s.def))
	if b.get_meta("phobia_discount", false):
		v *= 0.5
	if _is_illegal(b) and s.def.buys_illegal:
		v *= 1.3
	return maxi(1, int(round(v)))


# ------------------------------------------------------------------ E на стенде (хост)

func _on_stand_interact(player: Player, s: Stand) -> void:
	if not Net.is_host():
		return
	if not s.unlocked:
		_try_unlock(player, s)
		return
	if s.vendor == null:
		return
	if s.vendor.is_refusing():
		s.vendor.say_line("phobia", "VEND_PHOBIA_DEFAULT", 2.0)
		return
	if _pending.has(player.peer_id):
		return
	var list := s.sellable()
	if list.is_empty():
		s.vendor.say(tr("VEND_COUNTER_EMPTY"), 2.5, "greet")
		return
	var arr: Array = []
	for b in list:
		arr.append({"nid": b.net_id, "name": b.describe(), "fair": _price_for(s, b)})
	Net.broadcast_event("vendor_open", {"peer": player.peer_id, "stand": s.def.id, "vendor": s.def.display_name(), "items": arr})


func _try_unlock(player: Player, s: Stand) -> void:
	var req := s.def.unlock_requires_vendor
	if req != "" and not Game.is_vendor_unlocked(req):
		var rd := Registry.vendor(req)
		player.say(tr("VEND_NEED_PREV") % (rd.display_name() if rd else req))
		AudioBus.play_at("buzzer", s.counter_pos(), 0.0)
		return
	if not Economy.try_spend(s.def.unlock_cost, "vendor_unlock"):
		player.say(tr("VEND_TOO_POOR") % s.def.unlock_cost)
		AudioBus.play_at("buzzer", s.counter_pos(), 0.0)
		return
	Game.unlock_vendor(s.def.id)
	Game.stat_add("vendors_unlocked")
	Net.broadcast_event("vendor_unlocked", {"stand": s.def.id})


## Публично: открыть скупщика кодом (тест/другие системы). Только хост.
func unlock_stand(vendor_id: String) -> void:
	if not Net.is_host() or not stands.has(vendor_id):
		return
	Game.unlock_vendor(vendor_id)
	Net.broadcast_event("vendor_unlocked", {"stand": vendor_id})


# ------------------------------------------------------------------ оффер / полоска (хост)

func handle_action(peer: int, kind: String, data: Dictionary) -> bool:
	match kind:
		"vendor_offer":
			_host_offer(peer, data)
			return true
		"haggle_result":
			_host_haggle_result(peer, data)
			return true
	return false


func _host_offer(peer: int, data: Dictionary) -> void:
	var s: Stand = stands.get(str(data.get("stand", "")))
	if s == null or not s.unlocked or s.vendor == null:
		return
	var w := _world()
	var p: Player = w.player_of(peer) if w else null
	if p == null:
		return
	var b = Net.items.get(int(data.get("nid", 0)))
	if b == null or not is_instance_valid(b) or not s.items.has(b) or b.is_held() or b.has_meta("vendor_refused"):
		return
	if _pending.has(peer) or s.vendor.is_refusing():
		return
	if p.global_position.distance_to(s.counter_pos()) > INTERACT_RANGE:
		return
	var v := s.vendor
	var fair := _price_for(s, b)
	var amount := maxi(1, int(data.get("amount", fair)))
	if b.integrity == Types.Integrity.SHARDS:
		# осколки: $1 и издёвка, спорить не о чём
		v.say(tr("VEND_SHARDS_DEAL"), 3.0, "reject")
		_sell(s, b, fair, peer, "shards")
		return
	var ratio := float(amount) / float(maxi(1, fair))
	var skill := Game.haggle_skill()
	if ratio <= 1.05:
		v.say_line("deal", "VEND_DEAL_DEFAULT", 2.5)
		Game.haggle_skill_gain(0.002)
		_sell(s, b, amount, peer, "deal")
		return
	var kind := ""
	var green_w := 0.3
	var hit_amt := 0
	var miss_amt := 0
	if ratio <= 1.35:
		kind = "partial"
		hit_amt = maxi(fair, int(round(amount * 0.7 + fair * 0.3)))
		miss_amt = maxi(1, int(round(fair * 0.75)))
		green_w = clampf(s.def.green_zone_base * (1.6 - ratio) * (1.0 + skill * 0.5), 0.06, 0.6)
		v.say(tr("VEND_COUNTER_OFFER") % hit_amt, 3.0, "reject")
	else:
		kind = "reject"
		hit_amt = amount
		miss_amt = maxi(1, int(round(fair * 0.55)))
		green_w = clampf(randf_range(0.06, 0.1) * (1.0 + skill * 0.3), 0.06, 0.12)
		v.say_line("reject", "VEND_REJECT_DEFAULT", 3.0)
	var green_pos := randf_range(green_w * 0.5 + 0.02, 1.0 - green_w * 0.5 - 0.02)
	var speed := (1.5 / (0.7 + skill)) * randf_range(0.9, 1.1)
	_pending[peer] = {"stand": s.def.id, "nid": b.net_id, "hit": hit_amt, "miss": miss_amt, "green_w": green_w, "t": Time.get_ticks_msec() / 1000.0}
	Net.broadcast_event("haggle_start", {
		"peer": peer, "stand": s.def.id, "nid": b.net_id, "kind": kind,
		"green_w": green_w, "green_pos": green_pos, "speed": speed,
		"amount_hit": hit_amt, "amount_miss": miss_amt, "counter": hit_amt,
	})


func _host_haggle_result(peer: int, data: Dictionary) -> void:
	var pd = _pending.get(peer)
	if pd == null:
		return
	if int(data.get("nid", 0)) != int(pd["nid"]):
		return
	_pending.erase(peer)
	var s: Stand = stands.get(str(pd["stand"]))
	var b = Net.items.get(int(pd["nid"]))
	if s == null or b == null or not is_instance_valid(b):
		return
	var hit := bool(data.get("hit", false))
	var precision := clampf(float(data.get("precision", 0.0)), 0.0, 1.0)
	var amount: int = int(pd["hit"]) if hit else int(pd["miss"])
	AudioBus.play_at("haggle_hit" if hit else "haggle_miss", s.counter_pos(), 0.0)
	if s.vendor:
		if hit:
			s.vendor.say_line("deal", "VEND_DEAL_DEFAULT", 2.5)
		else:
			s.vendor.say(_tr_rand("VEND_MISS", 3), 2.5, "reject")
	Game.haggle_skill_gain(0.01 if hit else 0.003)
	if hit and precision > 0.9 and float(pd["green_w"]) < 0.12:
		Achievements.unlock("haggle_perfect")
	_sell(s, b, amount, peer, "hit" if hit else "miss")


func _tr_rand(prefix: String, n: int) -> String:
	return tr("%s_%d" % [prefix, randi_range(1, n)])


## Итог пишет хост в котёл, вещь деспавнится, всем — тост.
func _sell(s: Stand, b: ItemBody, amount: int, peer: int, why: String) -> void:
	amount = maxi(1, amount)
	var nm := b.def.display_name()
	var nid := b.net_id
	Economy.add(amount, "vendor")
	Game.stat_add("items_sold")
	Game.stat_add("vendor_earned", amount)
	AudioBus.play_at("cash_register", s.counter_pos(), 0.0)
	s.items.erase(b)
	for h in b.held_by.duplicate():
		h.host_release_body(b)
	Net.despawn_item(nid)
	Net.broadcast_event("vendor_sold", {"stand": s.def.id, "nid": nid, "name": nm, "amount": amount, "peer": peer, "why": why})


# ------------------------------------------------------------------ события (все)

func on_net_event(kind: String, data: Dictionary) -> void:
	match kind:
		"vendor_open":
			if int(data.get("peer", 0)) == Net.my_id() and ui:
				ui.open_offer(data)
		"haggle_start":
			if int(data.get("peer", 0)) == Net.my_id() and ui:
				ui.start_bar(data)
		"vendor_sold":
			Game.notify.emit(tr("VEND_SOLD_TOAST") % [str(data.get("name", "")), int(data.get("amount", 0))], 3.0)
			if ui:
				ui.on_item_gone(int(data.get("nid", 0)))
		"vendor_unlocked":
			var id := str(data.get("stand", ""))
			_unlocked_ids[id] = true
			var s: Stand = stands.get(id)
			if s:
				s.unlocked = true
				_apply_open_state(s)
				if not bool(data.get("silent", false)):
					AudioBus.play_at("fanfare", s.counter_pos(), 2.0)
			if not bool(data.get("silent", false)):
				var d := Registry.vendor(id)
				Game.notify.emit(tr("VEND_UNLOCKED") % (d.display_name() if d else id), 4.0)
		"vendor_scare":
			if not Net.is_host():
				var s: Stand = stands.get(str(data.get("stand", "")))
				if s and s.vendor:
					s.vendor.scare(-s.front(), PHOBIA_REFUSE_SEC)


func send_full_state_to(peer: int) -> void:
	for id in stands:
		var s: Stand = stands[id]
		if s.unlocked and s.def.unlock_cost > 0:
			Net._rpc_event.rpc_id(peer, "vendor_unlocked", {"stand": id, "silent": true})


# ------------------------------------------------------------------ тик

func _process(_delta: float) -> void:
	if Net.is_host() and not _pending.is_empty():
		var now := Time.get_ticks_msec() / 1000.0
		for peer in _pending.keys():
			var pd: Dictionary = _pending[peer]
			if now - float(pd["t"]) > HAGGLE_TIMEOUT:
				_host_haggle_result(peer, {"nid": pd["nid"], "hit": false, "precision": 0.0})
	_phone_tick()


## Телефон (§11): держишь вещь с тегом phone, E — открыть видоискатель, E — снять.
func _phone_tick() -> void:
	if phone == null:
		return
	var w := _world()
	var p: Player = w.local_player() if w else null
	if p == null or p.dead or p.hands == null:
		if phone.is_open():
			phone.close()
		return
	var held := p.hands.holds_tag("phone")
	if held == null:
		if phone.is_open():
			phone.close()
		return
	if not Input.is_action_just_pressed("use"):
		return
	if ui and ui.is_open():
		return
	if w.pause_menu and w.pause_menu.has_method("is_open") and w.pause_menu.is_open():
		return
	var t = p.look_target()
	if t and not (t is ItemBody) and t.has_method("interact"):
		return # Player отдаёт E интерактиву мира — телефон не мешаем
	if phone.is_open():
		phone.snap(p)
	else:
		phone.open()


## «Позвонить» в окне оффера: оценка ЦеноБота (врёт, если вещь не в прицеле).
func _on_phone_requested(_nid: int) -> void:
	if ui == null:
		return
	var w := _world()
	var p: Player = w.local_player() if w else null
	if p == null:
		return
	var has_phone := p.hands.holds_tag("phone") != null
	if not has_phone:
		for b in p.pockets:
			if b and is_instance_valid(b) and b.def.tags.has("phone"):
				has_phone = true
				break
	if not has_phone:
		ui.show_estimate(tr("PHONE_NONE"))
		AudioBus.play_ui("buzzer", -6.0)
		return
	var res := PhoneOverlay.estimate(p)
	AudioBus.play_ui("camera_shutter", -4.0)
	if float(res.get("lie", 1.0)) > 3.0:
		Achievements.unlock("phone_liar")
	ui.show_estimate(str(res.get("text", "")))


# ------------------------------------------------------------------ режим VENDOR по району

func _hook_district() -> void:
	var w := _world()
	if w == null:
		return
	var d := w.district_root(Types.District.VENDORS)
	if d == null or not d.has_signal("player_entered"):
		return
	d.player_entered.connect(func(_p: Player):
		_district_players += 1
		if Net.is_host() and (Game.world_mode == Types.WorldMode.TRAVEL or Game.world_mode == Types.WorldMode.TRAILER_HUB):
			Game.set_world_mode(Types.WorldMode.VENDOR))
	d.player_exited.connect(func(_p: Player):
		_district_players = maxi(0, _district_players - 1)
		if Net.is_host() and _district_players == 0 and Game.world_mode == Types.WorldMode.VENDOR:
			Game.set_world_mode(Types.WorldMode.TRAVEL))
