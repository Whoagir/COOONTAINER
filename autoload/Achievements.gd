extends Node
## Ачивки (§16): пара десятков угарных. Описания в res://steam/achievements.json.
## Локально — в слоте сейва; в Steam — через SteamBoot.

signal unlocked(id: String, title: String)

var defs: Dictionary = {} # id → {title_key, desc_key, hidden}
var _session_unlocked: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var f := FileAccess.open("res://steam/achievements.json", FileAccess.READ)
	if f:
		var parsed = JSON.parse_string(f.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY and parsed.has("achievements"):
			for a in parsed["achievements"]:
				defs[a["id"]] = a


func is_unlocked(id: String) -> bool:
	if Game.save.is_empty():
		return _session_unlocked.has(id)
	return (Game.save.get("achievements", []) as Array).has(id)


func unlock(id: String) -> void:
	if not defs.has(id):
		push_warning("[Achievements] unknown %s" % id)
		return
	if is_unlocked(id):
		return
	if not Game.save.is_empty():
		(Game.save["achievements"] as Array).append(id)
	_session_unlocked.append(id)
	SteamBoot.set_achievement(id)
	var title := tr(defs[id].get("title_key", id))
	unlocked.emit(id, title)
	AudioBus.play_ui("achievement")
	# в коопе ачивки общие: хост шлёт всем
	if Net.is_host() and Net.peer_count() > 1:
		Net.broadcast_event("achievement", {"id": id})


## Счётчик-ачивки: увеличиваем стат, при пороге — анлок.
func count(stat_key: String, achievement_id: String, threshold: int, add: float = 1.0) -> void:
	var v := Game.stat_add(stat_key, add)
	if v >= threshold:
		unlock(achievement_id)
