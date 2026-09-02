class_name Dealer
extends Npc
## Крупье (§13): стоит у стола, крутит колесо, комментирует проигрыш пати. Голос: audio/voice/<lang>/dealer/.

const LINES := {
	"greet": ["DEALER_GREET_1", "DEALER_GREET_2"],
	"spin": ["DEALER_SPIN_1", "DEALER_SPIN_2", "DEALER_SPIN_3"],
	"red": ["DEALER_RED_1", "DEALER_RED_2"],
	"black": ["DEALER_BLACK_1", "DEALER_BLACK_2"],
	"green": ["DEALER_GREEN_1", "DEALER_GREEN_2"],
	"win": ["DEALER_WIN_1", "DEALER_WIN_2"],
	"lose": ["DEALER_LOSE_1", "DEALER_LOSE_2", "DEALER_LOSE_3"],
	"nobets": ["DEALER_NOBETS_1"],
	"wait": ["DEALER_WAIT_1"],
	"broke": ["DEALER_BROKE_1"],
}


func setup() -> void:
	npc_group = "dealer"
	body_color = Color(0.16, 0.1, 0.14)
	hat = true
	height = 1.8
	fatness = 0.9
	voice_pitch = 0.9
	display_name = tr("NPC_DEALER")


func line(category: String, seconds: float = 2.5) -> void:
	var arr: Array = LINES.get(category, [])
	if arr.is_empty():
		return
	say(tr(arr[randi() % arr.size()]), seconds, category)
