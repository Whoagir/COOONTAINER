class_name LotSpawn
extends Resource
## Одна строчка spawn_list лота (§8): вещь + трансформ + вложенное.

@export var item_id: String = ""
@export var xform: Transform3D = Transform3D.IDENTITY
@export var nested: Array[String] = [] # id вещей внутри (глубина 1; они сами могут иметь nest_loot → глубина 2–3)
@export var locked_override: int = -1 # -1 = по карточке, 0 = открыт, 1 = заперт
@export var dirt_override: float = -1.0


static func make(p_id: String, pos: Vector3, rot_y_deg: float = 0.0, p_nested: Array[String] = []) -> LotSpawn:
	var s := LotSpawn.new()
	s.item_id = p_id
	s.xform = Transform3D(Basis(Vector3.UP, deg_to_rad(rot_y_deg)), pos)
	s.nested = p_nested
	return s
