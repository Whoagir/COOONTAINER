class_name Cop
extends Npc
## Мент (§13): NPC группы "cop". Хост гоняет его через Police; на клиенте — прокси (позиции из cop_pos).
## E на менте с купюрой в руке — взятка в руку (§6.3). ЛКМ (толчок) — толкнёт в ответ; 3 раза → арест на месте.

var cop_id := 0
var police: Node = null
var stationary := false
var proxy := false
var proxy_target := Vector3.ZERO
var proxy_yaw := 0.0
var _has_proxy_target := false


func _init() -> void:
	npc_group = "cop"
	body_color = Color(0.13, 0.17, 0.38)
	hat = true
	bald = false
	height = 1.8
	fatness = 1.05
	speed = 5.0
	voice_pitch = 0.9
	display_name = tr("NPC_COP")


func _process(delta: float) -> void:
	if proxy and _has_proxy_target:
		global_position = global_position.lerp(proxy_target, minf(1.0, delta * 10.0))
		rotation.y = lerp_angle(rotation.y, proxy_yaw, minf(1.0, delta * 10.0))


func set_proxy_target(pos: Vector3, yaw: float) -> void:
	if not _has_proxy_target:
		global_position = pos
		rotation.y = yaw
	proxy_target = pos
	proxy_yaw = yaw
	_has_proxy_target = true


static func held_cash(player: Player) -> ItemBody:
	if player == null or player.hands == null:
		return null
	for h in player.hands.held:
		if h and is_instance_valid(h) and h.def.is_cash():
			return h
	return null


## E на менте (хост). Купюра в руке → взятка; иначе — отмахнётся.
func interact(player: Player) -> void:
	if not Net.is_host() or police == null or player == null:
		return
	var bill := held_cash(player)
	if bill and police.has_method("bribe_in_hand"):
		police.bribe_in_hand(bill, player, self)
	elif police.has_method("cop_line"):
		face(player.global_position)
		say(police.cop_line("IDLE"), 2.0, "idle")


func interact_hint(player: Player) -> String:
	if held_cash(player):
		return tr("POLICE_HINT_BRIBE")
	return tr("NPC_COP")


## Схватили/толкнули мента (ЛКМ): он отвечает и запоминает.
func on_grab(player: Node) -> void:
	if police and police.has_method("on_cop_shoved"):
		police.on_cop_shoved(self, player)
	else:
		super(player)
