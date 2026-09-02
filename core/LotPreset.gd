class_name LotPreset
extends Resource
## Ручной пресет лота (§8). Никакого генератора этажей.

@export var id: String = ""
@export var district_id: int = Types.District.HANGAR
@export var lot_kind: int = Types.LotKind.BAG
@export var min_bid: int = 10
@export var info_mode: int = Types.InfoMode.DOOR15
@export var preview_seconds: float = 15.0
@export var clearout_seconds: float = 120.0
@export var lock_chance: float = 0.2
@export var spawn_list: Array[LotSpawn] = []
@export var pacing_tag: int = Types.PacingTag.LEAN
@export var broom_required: bool = false
@export var hunters_count: int = 6
@export var order: int = 0 # порядок в волне района
@export var tale_ru: String = "" # для InfoMode.TALE — байка аукциониста
@export var tale_en: String = ""
@export var docs_ru: String = "" # для InfoMode.DOCS
@export var docs_en: String = ""
@export var photo_item_ids: Array[String] = [] # для InfoMode.PHOTOS — что на фото (может врать)
@export var cell_size: Vector3 = Vector3(3, 2.5, 3) # внутренний объём ячейки/контейнера
@export var dark: bool = false # лампы нет → фонарь


## Честная сумма value_base всего содержимого (для мозга хантера и пейсинга).
func total_value(registry) -> int:
	var sum := 0
	for s in spawn_list:
		var d = registry.item(s.item_id)
		if d:
			sum += d.value_base
		for n in s.nested:
			var nd = registry.item(n)
			if nd:
				sum += nd.value_base
	return sum


func item_count() -> int:
	var c := 0
	for s in spawn_list:
		c += 1 + s.nested.size()
	return c
