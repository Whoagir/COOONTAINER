class_name Hunter
extends Npc
## Хантер (§9). Мозг — AuctionBrain: оценка по тому же сигналу ± ошибка, жадность, блеф, подстава, пас по шагу.
## Хост думает; клиент только рисует (весло, реплики через npc_say). Ощущение: «этот лысый меня развёл».

## Качество сигнала по info_mode: множитель оценки и (обратно) разброс ошибки.
const INFO_QUALITY := {
	Types.InfoMode.DOOR15: 0.9,
	Types.InfoMode.SLIT: 0.55,
	Types.InfoMode.PHOTOS: 0.75,
	Types.InfoMode.DOCS: 0.8,
	Types.InfoMode.TALE: 0.5,
}
const SETUP_OVERSHOOT := 1.4 # подстава: разгоняет игрока до 1.4× своего максимума
const BLUFF_OVERSHOOT := 1.6 # блеф: один раз выше потолка, но не выше 1.6× (иначе это уже не блеф, а идиот)
const SHOVE_WINDOW := 4.0

var brain: AuctionBrain
var index: int = 0 # Hunter0..7
var auction: Node = null
var anchor: Node3D = null

# --- торги (хост)
var estimate := 0.0
var max_bid := 0
var passed := false
var will_bluff := false
var bluffed := false
var last_bid_was_bluff := false
var will_setup := false
var setup_active := false
var setup_done := false
var in_auction := false
var ragdoll_count := 0
var _decision := 0.0
var _chatter := 0.0
var _shove_count := 0
var _shove_timer := 0.0
var _last_shover: Node = null

# --- весло (доска ~0.28×0.32, мазня Paddle.draw_face; цвет/seed постоянны)
var marker_ink: Color = Color(0.12, 0.1, 0.3, 0.95)
var scrawl_seed: int = 0
var paddle_amount: int = 0
var carried: ItemBody = null
var _paddle_root: Node3D
var _paddle_face_mat: StandardMaterial3D
var _paddle_tw: Tween
var _paddle_rest := Vector3.ZERO
var _paddle_rest_rot := Vector3.ZERO
var _hand_anchor: Node3D
var _raising := false


func setup_brain(b: AuctionBrain, p_index: int) -> void:
	brain = b
	index = p_index
	npc_group = "hunter"
	body_color = b.body_color
	hat = b.hat
	bald = b.bald
	height = b.height
	fatness = b.fatness
	voice_pitch = b.voice_pitch
	display_name = b.display_name()
	if display_name == "":
		display_name = b.name_ru if TranslationServer.get_locale().begins_with("ru") else b.name_en
	if display_name == "":
		display_name = tr("NPC_HUNTER")
	_init_marker()


func _init_marker() -> void:
	var h: int = display_name.hash() ^ (index * 7919) ^ int(body_color.to_rgba32())
	if brain and brain.id != "":
		h ^= brain.id.hash()
	scrawl_seed = absi(h % 2147483647) + 1
	# лысый всегда пишет красным — узнаваемый почерк
	if bald:
		marker_ink = Color(0.82, 0.07, 0.09, 0.95)
	else:
		marker_ink = Color.from_hsv(fmod(absf(float(absi(h))) * 0.000137, 1.0), 0.82, 0.52, 0.95)


func _ready() -> void:
	npc_group = "hunter"
	if brain == null:
		brain = AuctionBrain.new()
	if scrawl_seed <= 0:
		_init_marker()
	super()
	_build_paddle()
	if paddle_amount > 0:
		paint_paddle(paddle_amount)
	_chatter = randf_range(20.0, 60.0)


func _build_paddle() -> void:
	_paddle_root = Node3D.new()
	_paddle_root.name = "HunterPaddle"
	var handle := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.014
	hm.bottom_radius = 0.018
	hm.height = 0.36
	hm.radial_segments = 6
	handle.mesh = hm
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.5, 0.33, 0.18)
	handle.material_override = wood
	handle.position.y = 0.18
	_paddle_root.add_child(handle)
	# восьмиугольная деревянная лопатка, как на кей-арте; поверх — бумажка с числом
	var board := MeshInstance3D.new()
	board.mesh = LowPoly.cylinder(0.185, 0.185, 0.022, 8)
	board.rotation.x = PI * 0.5
	board.rotation.y = PI / 8.0
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color(0.6, 0.4, 0.22)
	paper.roughness = 0.9
	board.material_override = paper
	board.position.y = 0.53
	_paddle_root.add_child(board)
	var rim := MeshInstance3D.new()
	rim.mesh = LowPoly.cylinder(0.2, 0.2, 0.012, 8)
	rim.rotation.x = PI * 0.5
	rim.rotation.y = PI / 8.0
	var rim_m := StandardMaterial3D.new()
	rim_m.albedo_color = Color(0.38, 0.24, 0.12)
	rim.material_override = rim_m
	rim.position.y = 0.53
	_paddle_root.add_child(rim)
	var face := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.24, 0.26)
	face.mesh = qm
	face.position = Vector3(0, 0.53, 0.013)
	_paddle_face_mat = StandardMaterial3D.new()
	_paddle_face_mat.albedo_color = Color(0.95, 0.93, 0.85)
	_paddle_face_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	face.material_override = _paddle_face_mat
	_paddle_root.add_child(face)
	var face_back := MeshInstance3D.new()
	face_back.mesh = qm
	face_back.position = Vector3(0, 0.53, -0.013)
	face_back.rotation.y = PI
	face_back.material_override = _paddle_face_mat
	_paddle_root.add_child(face_back)
	# к телу, не к руке: walk-аним не прячет доску; лицо смотрит вперёд (−Z)
	add_child(_paddle_root)
	_paddle_rest = Vector3(0.42 * fatness, height * 0.58, 0.14)
	_paddle_root.position = _paddle_rest
	_paddle_rest_rot = Vector3(deg_to_rad(-20.0), PI, deg_to_rad(-8.0))
	_paddle_root.rotation = _paddle_rest_rot
	_hand_anchor = Node3D.new()
	_hand_anchor.name = "CarryAnchor"
	add_child(_hand_anchor)
	_hand_anchor.position = Vector3(0.34 * fatness, height * 0.55, -0.22)


# ------------------------------------------------------------------ мозг (хост)

## Новый лот: приватная оценка и потолок. lot_value — честная сумма value_base содержимого.
func prepare(lot_value: int, info_mode: int, min_bid: int) -> void:
	var q: float = INFO_QUALITY.get(info_mode, 0.7)
	var sigma := brain.estimate_error * brain.info_sensitivity * (1.4 - q)
	estimate = maxf(0.0, float(lot_value) * q * (1.0 + randfn(0.0, sigma)))
	max_bid = maxi(min_bid, int(estimate * (0.35 + brain.greed * 0.6)))
	passed = false
	bluffed = false
	last_bid_was_bluff = false
	setup_active = false
	setup_done = false
	will_bluff = randf() < brain.bluff_chance
	will_setup = randf() < brain.setup_chance
	if is_nemesis():
		# обида: +10% к потолку за каждое поражение (до +50%) и чаще лезет в подставу
		var g := clampi(grudge(), 0, 5)
		max_bid = int(max_bid * (1.0 + 0.1 * g))
		if g >= 2 and randf() < 0.35:
			will_setup = true
	ragdoll_count = 0
	in_auction = true
	_reset_decision()
	paint_paddle(min_bid)


func _reset_decision() -> void:
	_decision = randf_range(0.6, 2.5) * lerpf(1.5, 0.5, clampf(brain.aggression, 0.0, 1.0))


## Каждый тик торгов. req — сколько надо дать, чтобы перебить. Возвращает ставку (>0) или 0.
## Блеф: один раз выше потолка, потом только пас (last_bid_was_bluff = true в этот тик).
## Подстава: пока ведёт ИГРОК — разгоняет до 1.4× своего потолка и сбрасывает с насмешкой.
func think(delta: float, req: int, leader_is_me: bool, leader_is_player: bool) -> int:
	if brain == null or passed or ragdolled or leader_is_me:
		return 0
	_decision -= delta
	if _decision > 0.0:
		return 0
	_reset_decision()
	if req <= max_bid:
		# терпение: чем ближе к потолку, тем чаще думает/пасует
		var ratio := float(req) / float(maxi(max_bid, 1))
		var p_hesitate := pow(ratio, 3.0) * (1.0 - clampf(brain.patience, 0.0, 1.0) * 0.7)
		if randf() < p_hesitate:
			if randf() < 0.5:
				_pass("pass", "HUNTER_PASS")
			return 0
		# далеко до потолка — агрессивный перепрыгивает через 1–3 шага (толпа ахает)
		if ratio < 0.5 and randf() < brain.aggression * 0.4:
			return mini(req + Auction.step_for(req) * randi_range(1, 3), max_bid)
		return req
	# выше собственного потолка
	if leader_is_player and will_setup and not setup_done:
		if req <= int(max_bid * SETUP_OVERSHOOT):
			if not setup_active:
				setup_active = true
				say(Auction.line("HUNTER_SETUP"), 2.0, "taunt")
			return req
		setup_done = true
		setup_active = false
		_pass("taunt", "HUNTER_SETUP_DROP")
		return 0
	if setup_active:
		setup_done = true
		setup_active = false
	if will_bluff and not bluffed and req <= int(max_bid * BLUFF_OVERSHOOT):
		bluffed = true
		last_bid_was_bluff = true
		passed = true
		say(Auction.line("HUNTER_BLUFF"), 1.5, "bid")
		return req
	_pass("pass", "HUNTER_PASS")
	return 0


func _pass(category: String, prefix: String) -> void:
	passed = true
	say(Auction.line(prefix), 1.6, category)
	show_pass()
	if auction and auction.has_method("on_hunter_pass"):
		auction.on_hunter_pass(self)


## player_won — лот ушёл игрокам; players_bid — игроки вообще поднимали весло в этом лоте.
func on_result(won: bool, winner_name: String, player_won: bool = false, players_bid: bool = false) -> void:
	in_auction = false
	if is_nemesis() and Net.is_host():
		if player_won:
			var n := int(Game.save.get("nemesis_losses", 0)) + 1
			Game.save["nemesis_losses"] = n
			Game.stat_add("nemesis_beaten")
			if n >= 5:
				Achievements.unlock("grudge_match")
			say(_nemesis_line("NEMESIS_LOSE", n), 3.0, "lose")
			return
		if won and players_bid:
			var w := int(Game.save.get("nemesis_wins", 0)) + 1
			Game.save["nemesis_wins"] = w
			say(_nemesis_line("NEMESIS_WIN", w), 3.0, "win")
			return
	if won:
		say(Auction.line("HUNTER_WIN"), 2.5, "win")
	elif randf() < 0.6:
		say(Auction.line("HUNTER_LOSE"), 2.0, "lose")


## Немезида (§9 «этот лысый меня развёл»): Толик Лысый помнит, сколько раз его перебили, злится и
## поднимает потолок против игроков. Память живёт в слоте — он злопамятный на всю кампанию.
func is_nemesis() -> bool:
	return brain != null and brain.id == "hunter_01"


func grudge() -> int:
	return int(Game.save.get("nemesis_losses", 0)) - int(Game.save.get("nemesis_wins", 0)) / 2


## NEMESIS_LOSE_1..N — реплика по номеру поражения; если такого номера нет — последняя.
func _nemesis_line(prefix: String, n: int) -> String:
	var k := "%s_%d" % [prefix, n]
	var t := TranslationServer.translate(k)
	while t == k and n > 1:
		n -= 1
		k = "%s_%d" % [prefix, n]
		t = TranslationServer.translate(k)
	return t if t != k else Auction.line("HUNTER_LOSE" if prefix.ends_with("LOSE") else "HUNTER_WIN")


func catchphrase() -> String:
	var arr: Array = brain.catchphrases_ru if TranslationServer.get_locale().begins_with("ru") else brain.catchphrases_en
	if arr.is_empty():
		return Auction.line("HUNTER_TAUNT")
	return arr[randi() % arr.size()]


# ------------------------------------------------------------------ визуал весла (хост и клиент)

func paint_paddle(amount: int) -> void:
	paddle_amount = maxi(amount, 0)
	if _paddle_face_mat == null:
		return
	_paddle_face_mat.albedo_texture = Paddle.draw_face(paddle_amount, scrawl_seed, marker_ink)


func raise_paddle(amount: int) -> void:
	if _paddle_root == null:
		return
	paint_paddle(amount)
	if _paddle_tw and _paddle_tw.is_valid():
		_paddle_tw.kill()
	_raising = true
	var raised_x: float = _paddle_rest_rot.x - deg_to_rad(110.0)
	_paddle_tw = create_tween()
	_paddle_tw.set_parallel(true)
	_paddle_tw.tween_property(_paddle_root, "rotation:x", raised_x, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_paddle_tw.tween_property(_paddle_root, "position:y", _paddle_rest.y + 0.08, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_paddle_tw.chain().tween_interval(1.2)
	_paddle_tw.chain().tween_property(_paddle_root, "rotation:x", _paddle_rest_rot.x, 0.22)
	_paddle_tw.parallel().tween_property(_paddle_root, "position:y", _paddle_rest.y, 0.22)
	_paddle_tw.finished.connect(func() -> void:
		_raising = false)


func show_pass() -> void:
	if _paddle_root == null:
		return
	if _paddle_tw and _paddle_tw.is_valid():
		_paddle_tw.kill()
	_raising = false
	_paddle_tw = create_tween()
	_paddle_tw.tween_property(_paddle_root, "rotation:x", _paddle_rest_rot.x + deg_to_rad(25.0), 0.28)
	_paddle_tw.parallel().tween_property(_paddle_root, "position:y", _paddle_rest.y - 0.06, 0.28)


# ------------------------------------------------------------------ хаул: нести вещь (хост считает, клиент зеркалит)

func attach_carry(b: ItemBody) -> void:
	if b == null or not is_instance_valid(b):
		return
	if carried and carried != b:
		drop_carry(false)
	if Net.is_host():
		if b.nested_in:
			b.unnest()
		b.freeze = true
		b.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		b.linear_velocity = Vector3.ZERO
		b.angular_velocity = Vector3.ZERO
		b.sleeping = false
		b.collision_layer = 0
		b.collision_mask = 0
	carried = b
	_follow_carry()


func drop_carry(steal: bool) -> ItemBody:
	var b: ItemBody = carried
	carried = null
	if b == null or not is_instance_valid(b):
		return null
	if Net.is_host() and not b.proxy:
		b.collision_layer = Types.L_ITEM
		b.collision_mask = Types.L_WORLD | Types.L_PLAYER | Types.L_ITEM | Types.L_VEHICLE | Types.L_NPC | Types.L_SHARD
		b.freeze = false
		b.sleeping = false
		if steal:
			b.lot_id = ""
			var yards: Node = Game.world.system("YardZones") if Game.world else null
			if yards and yards.has_method("on_hunter_steal"):
				var cul: Player = _last_shover as Player if _last_shover is Player else null
				yards.on_hunter_steal(cul, b)
			elif not b.stolen:
				b.mark_stolen()
	return b


func _follow_carry() -> void:
	if carried == null or not is_instance_valid(carried) or _hand_anchor == null:
		return
	var lift: float = 0.12
	if carried.arch:
		lift = maxf(carried.arch.dims.y * 0.35 * carried.def.scale, 0.08)
	carried.global_position = _hand_anchor.global_position + Vector3(0.0, lift, 0.0)
	carried.global_basis = global_basis


func _drop_and_notify(steal: bool) -> void:
	var b := drop_carry(steal)
	if Net.is_host() and auction and auction.has_method("on_hunter_drop"):
		auction.on_hunter_drop(self, b)


# ------------------------------------------------------------------ потасовка (§9)

func shove(impulse: Vector3) -> void:
	if carried:
		_drop_and_notify(true)
	super.shove(impulse)


func on_grab(player: Node) -> void:
	if carried:
		_drop_and_notify(true)
	_last_shover = player
	_shove_count = _shove_count + 1 if _shove_timer > 0.0 else 1
	_shove_timer = SHOVE_WINDOW
	var dir: Vector3 = global_position - player.global_position
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.BACK
	var force := 3.0 + 2.0 * float(_shove_count - 1) # третий толчок подряд → ragdoll
	shove(dir * force + Vector3.UP)
	if not ragdolled and randf() < brain.brawl_temper:
		var imp: Vector3 = -dir * 6.0 + Vector3.UP * 2.5
		if player.has_method("take_damage"):
			player.take_damage(5.0, "brawl")
		if "velocity" in player:
			player.velocity += imp
		if player.get("peer_id") != null:
			Net.broadcast_event("auction_shove", {"peer": player.peer_id, "imp": imp})
		say(Auction.line("HUNTER_BRAWL"), 2.0, "angry")
	if auction and auction.has_method("on_hunter_shoved"):
		auction.on_hunter_shoved(self, player)


func ragdoll_for(seconds: float) -> void:
	if ragdolled:
		return
	ragdoll_count += 1
	if carried:
		_drop_and_notify(true)
	if _paddle_root:
		_paddle_root.visible = false
	if Net.is_host() and auction and auction.has_method("on_hunter_ragdoll"):
		auction.on_hunter_ragdoll(self, _last_shover, ragdoll_count)
	await super.ragdoll_for(seconds)
	if _paddle_root:
		_paddle_root.visible = true


func _physics_process(delta: float) -> void:
	super(delta)
	if _shove_timer > 0.0:
		_shove_timer -= delta
	if carried:
		if not is_instance_valid(carried):
			carried = null
		elif ragdolled:
			if Net.is_host():
				_drop_and_notify(true)
		else:
			_follow_carry()
	if not Net.is_host() or in_auction or ragdolled:
		return
	# редкий трёп между аукционами
	_chatter -= delta
	if _chatter <= 0.0:
		_chatter = randf_range(25.0, 70.0)
		if randf() < 0.5:
			say(catchphrase(), 2.5, "taunt")
