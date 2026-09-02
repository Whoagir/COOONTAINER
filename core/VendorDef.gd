class_name VendorDef
extends Resource
## Характер скупщика (§11). Всегда покупает — спор только о цене.

@export var id: String = ""
@export var name_ru: String = ""
@export var name_en: String = ""
@export var vendor_type: int = Types.VendorType.HOUSEHOLD
@export var phobias: Array[int] = [] # Types.Phobia
@export var favorite_facets: Array[int] = [] # Types.Facet — за них платит больше
@export var hated_facets: Array[int] = []
@export var base_multiplier: float = 0.6 # доля от value_base в «честной» цене
@export var buys_illegal: bool = false
@export var calls_police_on_illegal: bool = true
@export var green_zone_base: float = 0.35 # ширина зелёного при честном оффере (0..1 полоски)
@export var greed: float = 0.5
@export var unlock_cost: int = 0 # 0 = открыт сразу
@export var unlock_requires_vendor: String = "" # анлок с одного крошечного
@export var body_color: Color = Color(0.5, 0.5, 0.6)
@export var voice_pitch: float = 1.0
@export var lines_greet_ru: Array[String] = []
@export var lines_greet_en: Array[String] = []
@export var lines_scream_ru: Array[String] = []
@export var lines_scream_en: Array[String] = []
@export var lines_deal_ru: Array[String] = []
@export var lines_deal_en: Array[String] = []
@export var lines_reject_ru: Array[String] = []
@export var lines_reject_en: Array[String] = []
@export var lines_phobia_ru: Array[String] = []
@export var lines_phobia_en: Array[String] = []


func display_name() -> String:
	return name_ru if TranslationServer.get_locale().begins_with("ru") else name_en


func pick(lines_ru: Array[String], lines_en: Array[String]) -> String:
	var arr := lines_ru if TranslationServer.get_locale().begins_with("ru") else lines_en
	if arr.is_empty():
		return ""
	return arr[randi() % arr.size()]
