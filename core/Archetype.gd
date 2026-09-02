class_name Archetype
extends Resource
## Архетип-меш (§7.1). Общая геометрия для многих карточек.
## Меш собирается процедурно билдером `builder` (см. item/ArchetypeMeshes.gd),
## либо, если задана `scene`, инстансится сцена-герой.

@export var id: String = ""
@export var builder: String = "box" # ключ в ArchetypeMeshes
@export var scene: PackedScene # герой (уникальная сцена) — приоритетнее билдера
@export var shard_scenes: Array[PackedScene] = []
@export var shard_count: int = 5
@export var size_class: int = Types.SizeClass.ONE_HAND
@export var mass_default: float = 1.0
@export var dims: Vector3 = Vector3(0.3, 0.3, 0.3) # габариты для билдера/коллайдера
@export var cloth: bool = false
@export var container: bool = false
@export var container_capacity: int = 3
@export var drawer_paths: Array[NodePath] = []
@export var shelf_paths: Array[NodePath] = []
@export var light_fixture: bool = false
@export var hand_offset: Vector3 = Vector3(0, 0, 0)
@export var base_color: Color = Color(0.8, 0.8, 0.8)
@export var secondary_color: Color = Color(0.4, 0.4, 0.4)
@export var friction: float = 0.8
@export var bounce: float = 0.05


func is_team() -> bool:
	return size_class == Types.SizeClass.TEAM
