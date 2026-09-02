class_name ItemDef
extends Resource
## Карточка вещи (§7.2). Канон контента: данные, не сцена.

@export var id: String = ""
@export var name_ru: String = ""
@export var name_en: String = ""
@export var archetype_id: String = "box_small"
@export var facets: Array[int] = [] # Types.Facet
@export var value_base: int = 10
@export var mass_override: float = 0.0 # 0 → берём из архетипа
@export var liquid_id: int = Types.LiquidId.NONE
@export var liquid_amount: float = 1.0 # 0..1 сколько налито
@export var flammable: bool = false
@export var illegal: bool = false
@export var dusty_default: float = 0.0
@export var nest_loot: Array[LootRef] = []
@export var vendor_affinity: Array[String] = [] # VendorDef.id
@export var wearable_slot: String = "none" # none | body
@export var break_threshold: float = 6.0 # импульс/масса, м/с
@export var color: Color = Color(1, 1, 1, 1) # тинт архетипа для этой карточки
@export var scale: float = 1.0
@export var tags: Array[String] = [] # свободные теги для ачивок / фобий: "mouse", "hamster", "gag"
@export var lore_ru: String = ""
@export var lore_en: String = ""


func has_facet(f: int) -> bool:
	return facets.has(f)


func display_name() -> String:
	return name_ru if TranslationServer.get_locale().begins_with("ru") else name_en


func is_fragile() -> bool:
	return has_facet(Types.Facet.FRAGILE)


func is_container() -> bool:
	return has_facet(Types.Facet.CONTAINER) or has_facet(Types.Facet.SHAKE_OUT)


func is_cash() -> bool:
	return id.begins_with("cash_")


func cash_value() -> int:
	if not is_cash():
		return 0
	return int(id.trim_prefix("cash_"))
