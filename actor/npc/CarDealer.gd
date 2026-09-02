class_name CarDealer
extends Npc
## Барыга авторынка (§10, §12): стоит у DealerSpot, орёт цены, продаёт витринные тачки.
## Спавнится системой Vehicles на всех машинах (детерминированно, путь /World/Npcs/CarDealer).

const PITCH := ["DEALER_PITCH_0", "DEALER_PITCH_1", "DEALER_PITCH_2"]
const SELL := ["DEALER_SELL_0", "DEALER_SELL_1", "DEALER_SELL_2"]
const POOR := ["DEALER_POOR_0", "DEALER_POOR_1"]
const GREET := ["DEALER_GREET_0", "DEALER_GREET_1"]
const GREET_RADIUS := 9.0
const GREET_COOLDOWN := 25.0

var _pitch_i := 0
var _greet_cd := 4.0
var _check_t := 0.0


func _ready() -> void:
	npc_group = "car_dealer"
	body_color = Color(0.85, 0.7, 0.15)
	height = 1.7
	fatness = 1.3
	hat = true
	voice_pitch = 0.85
	display_name = tr("NPC_CAR_DEALER")
	super()


func _physics_process(delta: float) -> void:
	super(delta)
	if not Net.is_host() or ragdolled:
		return
	_greet_cd -= delta
	_check_t -= delta
	if _greet_cd > 0.0 or _check_t > 0.0:
		return
	_check_t = 1.0
	for p in Net.players.values():
		if p and is_instance_valid(p) and not p.dead and p.global_position.distance_to(global_position) < GREET_RADIUS:
			face(p.global_position)
			say(tr(GREET.pick_random()), 2.5, "greet")
			_greet_cd = GREET_COOLDOWN
			return


func interact(player: Player) -> void:
	if not Net.is_host():
		return
	face(player.global_position)
	say(tr(PITCH[_pitch_i % PITCH.size()]), 3.0, "pitch")
	_pitch_i += 1


func interact_hint(_p: Player) -> String:
	return tr("VEH_DEALER_HINT")


func say_sell() -> void:
	say(tr(SELL.pick_random()), 3.0, "sell")


func say_poor() -> void:
	say(tr(POOR.pick_random()), 3.0, "poor")


func say_theft() -> void:
	say(tr("DEALER_THEFT"), 2.5, "angry")
