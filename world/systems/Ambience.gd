class_name Ambience
extends Node
## Живой фон мира (§16): два 2D-слоя эмбиенса с кроссфейдом — «где я» (район) и «когда»
## (день/ночь) — плюс точечные лупы у костра и у моря. Локально у каждого игрока, сеть не нужна.
## Всё лениво: если WAV не сгенерирован, слой просто молчит.

const FADE := 1.5
const BED_DB := -17.0
const PLACE_DB := -13.0

## район → луп «где я» (перебивает дневной/ночной слой, если есть)
const BY_DISTRICT := {
	Types.District.HANGAR: "ambient_hangar",
	Types.District.STORAGE: "ambient_storage",
	Types.District.PORT: "ambient_port",
	Types.District.CASINO: "ambient_casino",
	Types.District.GARAGES: "ambient_storage",
	Types.District.POLICE: "ambient_town",
	Types.District.VENDORS: "ambient_town",
	Types.District.CAR_MARKET: "ambient_town",
}

var _day: AudioStreamPlayer
var _place: AudioStreamPlayer
var _place_name := ""
var _day_name := ""
var _tw_day: Tween
var _tw_place: Tween
var _t := 0.0
var _dn: DayNight


func system_name() -> String:
	return "Ambience"


func _ready() -> void:
	await get_tree().process_frame
	var w := Game.world
	if w == null:
		return
	_dn = w.system("DayNight") as DayNight
	_day = _mk_player()
	_place = _mk_player()
	_spot_loops(w)
	_refresh(true)


func _mk_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "SFX"
	p.volume_db = -60.0
	add_child(p)
	return p


## Точечные лупы: костёр в трейлер-парке и плеск в порту — 3D, слышно только рядом.
func _spot_loops(w) -> void:
	var spots := [
		{"marker": "Campfire", "d": Types.District.TRAILER_PARK, "sfx": "campfire_loop", "range": 14.0, "db": -6.0},
	]
	for s in spots:
		var m: Node3D = w.find_marker(int(s["d"]), str(s["marker"]))
		if m == null:
			continue
		var stream := AudioBus.loop_stream(str(s["sfx"]))
		if stream == null:
			continue
		var p := AudioStreamPlayer3D.new()
		p.name = "Spot_" + str(s["sfx"])
		p.bus = "SFX"
		p.stream = stream
		p.max_distance = float(s["range"])
		p.unit_size = float(s["range"]) * 0.35
		p.volume_db = float(s["db"])
		w.add_child(p)
		p.global_position = m.global_position + Vector3(0, 0.6, 0)
		p.play()


func _process(delta: float) -> void:
	_t += delta
	if _t < 1.0:
		return
	_t = 0.0
	_refresh(false)


func _district_of_player() -> int:
	var w = Game.world
	if w == null or w.city == null:
		return -1
	var p: Player = w.local_player()
	if p == null:
		return -1
	var d = w.city.district_at(p.global_position)
	return d.district_id if d else -1


func _refresh(instant: bool) -> void:
	var night: bool = _dn != null and _dn.is_night()
	var want_day := "ambient_night" if night else "ambient_desert_day"
	var d := _district_of_player()
	var want_place: String = str(BY_DISTRICT.get(d, ""))
	# в помещении «где я» громче и глушит улицу
	_swap(_day, want_day, _day_name, BED_DB - (7.0 if want_place != "" else 0.0), instant, true)
	_day_name = want_day
	_swap(_place, want_place, _place_name, PLACE_DB, instant, false)
	_place_name = want_place


func _swap(p: AudioStreamPlayer, want: String, cur: String, db: float, instant: bool, is_day: bool) -> void:
	if p == null:
		return
	if want == cur:
		if p.playing:
			var tw := _tw_day if is_day else _tw_place
			if tw == null or not tw.is_valid():
				p.volume_db = db + linear_to_db(AudioBus.sfx_volume)
		return
	var target_db := db + linear_to_db(AudioBus.sfx_volume)
	var stream := AudioBus.loop_stream(want) if want != "" else null
	if stream == null:
		if p.playing:
			p.stop()
		return
	p.stream = stream
	p.volume_db = target_db if instant else -60.0
	p.play()
	if instant:
		return
	var tw := create_tween()
	tw.tween_property(p, "volume_db", target_db, FADE)
	if is_day:
		if _tw_day and _tw_day.is_valid():
			_tw_day.kill()
		_tw_day = tw
	else:
		if _tw_place and _tw_place.is_valid():
			_tw_place.kill()
		_tw_place = tw
