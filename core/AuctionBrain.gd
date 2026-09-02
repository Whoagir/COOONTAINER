class_name AuctionBrain
extends Resource
## Мозг хантера (§9). Оценка по тому же сигналу ± ошибка, жадность, блеф, подстава, пас.

@export var id: String = ""
@export var name_ru: String = ""
@export var name_en: String = ""
@export var nickname_ru: String = "" # «Лысый», «Тётя в леопарде»
@export var nickname_en: String = ""
@export var estimate_error: float = 0.25 # σ ошибки оценки (доля от истинной стоимости)
@export var greed: float = 0.6 # 0..1 — до какой доли оценки готов идти
@export var bluff_chance: float = 0.15 # поднять выше оценки, чтоб потом пасануть
@export var setup_chance: float = 0.1 # подстава: разогнать соперника и сбросить
@export var patience: float = 0.5 # 0..1 — как долго держится на шаге
@export var aggression: float = 0.5 # скорость ответа на ставку
@export var brawl_temper: float = 0.3 # вероятность полезть в драку при толчке
@export var info_sensitivity: float = 1.0 # насколько сильнее реагирует на богатый info_mode
@export var body_color: Color = Color(0.6, 0.4, 0.3)
@export var hat: bool = false
@export var bald: bool = false
@export var voice_pitch: float = 1.0
@export var catchphrases_ru: Array[String] = []
@export var catchphrases_en: Array[String] = []
@export var height: float = 1.75
@export var fatness: float = 1.0


func display_name() -> String:
	return nickname_ru if TranslationServer.get_locale().begins_with("ru") else nickname_en
