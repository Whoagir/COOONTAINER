class_name LocksmithNpc
extends Npc
## Вскрывальщик (§11): отдельный NPC. Плати → короткая сцена → открыл или сломал. Голос: audio/voice/<lang>/locksmith/.

const LINES := {
	"greet": ["LOCK_GREET_1", "LOCK_GREET_2"],
	"pay": ["LOCK_PAY_1", "LOCK_PAY_2"],
	"work": ["LOCK_WORK_1", "LOCK_WORK_2", "LOCK_WORK_3"],
	"success": ["LOCK_SUCCESS_1", "LOCK_SUCCESS_2"],
	"fail": ["LOCK_FAIL_1", "LOCK_FAIL_2"],
	"nothing": ["LOCK_NOTHING_1"],
	"wait": ["LOCK_WAIT_1"],
}

var busy := false


func setup() -> void:
	npc_group = "locksmith"
	body_color = Color(0.35, 0.38, 0.42)
	bald = true
	height = 1.7
	fatness = 1.15
	voice_pitch = 0.85
	display_name = tr("NPC_LOCKSMITH")


func line(category: String, seconds: float = 2.5) -> void:
	var arr: Array = LINES.get(category, [])
	if arr.is_empty():
		return
	say(tr(arr[randi() % arr.size()]), seconds, category)
