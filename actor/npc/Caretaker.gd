class_name Caretaker
extends Npc
## Смотритель площадки (§9, §10): стоит у своего маркера, орёт на тех, кто лезет в ячейку на превью.
## ClearOut тоже орёт через него: shout(category, text). В IDLE молчит.

var auction: Node = null
var anchor: Node3D = null


func _ready() -> void:
	npc_group = "caretaker"
	if display_name == "":
		display_name = tr("NPC_CARETAKER")
	super()


## Категория — префикс файлов озвучки (warn, angry, gloat, overtime, ...).
func shout(category: String, text: String, seconds: float = 2.5) -> void:
	say(text, seconds, category)


## E по смотрителю во время вывоза — «мы закончили» (ClearOut.try_finish_by). В остальное время молчит.
func interact(player: Node) -> void:
	if not Net.is_host():
		return
	var co = Game.world.system("ClearOut") if Game.world else null
	if co and co.has_method("is_active") and co.is_active() and co.has_method("try_finish_by"):
		if not co.has_method("current_anchor") or co.current_anchor() == anchor:
			co.try_finish_by(player)


func interact_hint(_player: Node) -> String:
	if Game.world_mode == Types.WorldMode.CLEAR_OUT:
		return tr("AUCTION_CARETAKER_DONE_HINT")
	return ""
