extends StaticBody3D
## Корпус щели котла — проксирует interact к PotSlot (луч взгляда ловит твёрдое тело).

var slot: PotSlot


func interact(player: Player) -> void:
	if slot:
		slot.interact(player)


func interact_hint(p: Player) -> String:
	return slot.interact_hint(p) if slot else ""
