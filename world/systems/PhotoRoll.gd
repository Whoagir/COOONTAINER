class_name PhotoRoll
extends Node
## Плёнка (§16): снимок телефона больше не живёт три секунды и не умирает. Кадр падает
## в плёнку и в `user://shots/roll`, а после вывоза лота пати смотрит «выпуск передачи» —
## что наснимали, пока таскали хлам. Локально у каждого игрока: телефон и так локальный.

const MAX_SHOTS := 24
const SHOT_W := 480

var shots: Array = [] ## {tex: ImageTexture, caption: String, ts: float}
var _dir := ""


func system_name() -> String:
	return "PhotoRoll"


const KEEP_FILES := 120 ## плёнка на диске копится между сессиями — держим только свежие

func _ready() -> void:
	_dir = OS.get_user_data_dir().path_join("shots").path_join("roll")
	DirAccess.make_dir_recursive_absolute(_dir)
	_prune()


func _prune() -> void:
	var files := DirAccess.get_files_at(_dir)
	if files.size() <= KEEP_FILES:
		return
	var names: Array = []
	for f in files:
		if f.ends_with(".png"):
			names.append(f)
	names.sort() # shot_<ticks>.png — лексикографически совпадает с порядком съёмки в пределах запуска
	for i in range(names.size() - KEEP_FILES):
		DirAccess.remove_absolute(_dir.path_join(str(names[i])))


## Кадр уже снят и обрезан вызывающим (Phone прячет свой оверлей и худ на кадр).
func add_shot(img: Image, caption: String) -> void:
	if img == null or img.is_empty() or img.get_width() < 8:
		return
	var h := int(round(float(SHOT_W) * float(img.get_height()) / float(img.get_width())))
	img.resize(SHOT_W, maxi(1, h), Image.INTERPOLATE_BILINEAR)
	img.save_png(_dir.path_join("shot_%d.png" % Time.get_ticks_msec()))
	shots.append({
		"tex": ImageTexture.create_from_image(img),
		"caption": caption,
		"ts": Time.get_ticks_msec() / 1000.0,
	})
	while shots.size() > MAX_SHOTS:
		shots.pop_front()


## Снимки за последние sec секунд — «что было на этом лоте». Старые не тянем: выпуск про лот.
func recent(sec: float, limit: int) -> Array:
	var now := Time.get_ticks_msec() / 1000.0
	var out: Array = []
	for i in range(shots.size() - 1, -1, -1):
		if now - float(shots[i].get("ts", 0.0)) > sec:
			break
		out.push_front(shots[i])
		if out.size() >= limit:
			break
	return out


func dir() -> String:
	return _dir
