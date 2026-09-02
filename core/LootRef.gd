class_name LootRef
extends Resource
## Что может лежать внутри вещи / вытряхнуться (§7.2 nest_loot).

@export var item_id: String = ""
@export var chance: float = 1.0
@export var count_min: int = 1
@export var count_max: int = 1


static func make(p_item_id: String, p_chance: float = 1.0, p_min: int = 1, p_max: int = 1) -> LootRef:
	var r := LootRef.new()
	r.item_id = p_item_id
	r.chance = p_chance
	r.count_min = p_min
	r.count_max = p_max
	return r
