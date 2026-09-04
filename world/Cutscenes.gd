class_name Cutscenes
extends RefCounted
## Сценарии катсцен (списки шотов для Cinematic). Интро при первом заезде в слот и финал с домом.
## Не туториал: интро — три кадра и записка Петровича, всё скипается любой клавишей.


static func _m(w, d: int, name: String, fallback: Vector3) -> Vector3:
	var n: Node3D = w.find_marker(d, name)
	return n.global_position if n else fallback


static func intro(w) -> Array:
	var TP := Types.District.TRAILER_PARK
	var trailer := _m(w, TP, "Trailer", Vector3.ZERO)
	var house_sign := _m(w, TP, "HouseSign", trailer + Vector3(15, 0, 9))
	var pot := _m(w, TP, "PotSlot", trailer + Vector3(5, 1.1, 2.4))
	var door := _m(w, TP, "TrailerDoor", trailer + Vector3(2.5, 0, 2.5))
	var p: Player = w.local_player()
	var me: Vector3 = p.global_position if p else trailer
	var sign_fwd := Vector3(0.57, 0, 0.82) # знак повёрнут к дороге
	return [
		{
			"from": trailer + Vector3(-30, 26, 48), "to": trailer + Vector3(-8, 9, 22),
			"look": trailer + Vector3(0, 1, 0), "dur": 6.0, "fov": 55.0,
			"fade_in": 1.4, "title": "COOONTAINER", "sub": TranslationServer.translate("CINE_INTRO_1"), "text_delay": 1.2,
		},
		{
			"from": house_sign + sign_fwd * 5.0 + Vector3(0, 1.9, 0), "to": house_sign + sign_fwd * 2.6 + Vector3(0.3, 1.5, 0),
			"look": house_sign + Vector3(0, 1.6, 0), "dur": 4.2, "fov": 50.0,
			"sub": TranslationServer.translate("CINE_INTRO_2"), "text_delay": 0.2,
		},
		{
			"from": pot + Vector3(0.9, 0.8, 2.8), "to": pot + Vector3(0.6, 0.5, 1.7),
			"look": pot + Vector3(0.5, 0.2, 0), "dur": 3.8, "fov": 55.0,
			"sub": TranslationServer.translate("CINE_INTRO_3"), "text_delay": 0.2,
		},
		{
			# внутри трейлера, от двери к кроватям: игрок в кадре
			"from": door + Vector3(0, 1.6, -0.9), "to": door + Vector3(0.2, 1.45, -1.5),
			"look": me + Vector3(0, 1.0, 0), "dur": 3.6, "fov": 68.0, "shake": 0.3,
			"sub": TranslationServer.translate("CINE_INTRO_4"), "text_delay": 0.1, "fade_out": 0.5,
		},
	]


static func ending(w) -> Array:
	var TP := Types.District.TRAILER_PARK
	var trailer := _m(w, TP, "Trailer", Vector3.ZERO)
	var house_sign := _m(w, TP, "HouseSign", trailer + Vector3(15, 0, 9))
	var p: Player = w.local_player()
	var me: Vector3 = p.global_position if p else trailer
	var sign_fwd := Vector3(0.57, 0, 0.82)
	return [
		{
			"from": me + Vector3(2.2, 1.6, 2.2), "to": me + Vector3(5.5, 4.5, 5.5),
			"look": me + Vector3(0, 1.3, 0), "dur": 4.5, "fov": 55.0,
			"fade_in": 0.8, "title": TranslationServer.translate("CINE_END_TITLE"), "sub": TranslationServer.translate("CINE_END_1"), "text_delay": 0.8,
		},
		{
			"from": house_sign + sign_fwd * 4.0 + Vector3(0, 1.8, 0), "to": house_sign + sign_fwd * 2.2 + Vector3(0, 1.6, 0),
			"look": house_sign + Vector3(0, 1.7, 0), "dur": 4.0, "fov": 50.0,
			"sub": TranslationServer.translate("CINE_END_2"), "text_delay": 0.3,
			"on_start": func(): _stamp_sold(w, house_sign),
		},
		{
			"from": trailer + Vector3(10, 4, 12), "to": trailer + Vector3(34, 38, 40),
			"look": trailer + Vector3(0, 1, 0), "dur": 7.5, "fov": 60.0, "fov_to": 70.0,
			"sub": TranslationServer.translate("CINE_END_3"), "text_delay": 1.0, "fade_out": 1.5,
		},
	]


## Табличка «ПРОДАНО» поверх знака дома — навсегда в этой сессии (в сейве дом уже куплен).
static func _stamp_sold(w, sign_pos: Vector3) -> void:
	var l := Label3D.new()
	l.text = TranslationServer.translate("CINE_SOLD")
	l.font_size = 140
	l.pixel_size = 0.01
	l.modulate = Color(0.85, 0.12, 0.1)
	l.outline_modulate = Color(0.2, 0.02, 0.02)
	l.outline_size = 18
	l.double_sided = false
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.global_position = sign_pos + Vector3(0.57, 0, 0.82) * 0.35 + Vector3(0, 1.75, 0)
	l.rotation.y = atan2(0.57, 0.82)
	l.rotation.z = -0.18
	w.add_child(l)
	AudioBus.play_at("hammer", sign_pos, 0.0)


## Хроника для титров: что натворили за кампанию.
static func chronicle() -> String:
	var st: Dictionary = Game.save.get("stats", {})
	var lines: Array[String] = []
	var rows := [
		["CRED_STAT_LOTS", "lots_cleared", false],
		["CRED_STAT_HAUL", "haul_value", true],
		["CRED_STAT_SOLD", "items_sold", false],
		["CRED_STAT_BROKEN", "items_broken", false],
		["CRED_STAT_FIRES", "fires_started", false],
		["CRED_STAT_CASINO", "casino_lost", true],
		["CRED_STAT_ARRESTS", "arrests", false],
		["CRED_STAT_FINES", "fines_paid", true],
		["CRED_STAT_BRIBES", "bribes", true],
		["CRED_STAT_DEATHS", "deaths", false],
		["CRED_STAT_DRINKS", "drinks", false],
		["CRED_STAT_THROWS", "throws", false],
		["CRED_STAT_JANITOR", "janitor_jobs", false],
	]
	for r in rows:
		var v := float(st.get(r[1], 0.0))
		if v <= 0.0:
			continue
		var val := ("$%d" % int(v)) if r[2] else str(int(v))
		lines.append("%s — %s" % [TranslationServer.translate(r[0]), val])
	var t := Game.playtime
	lines.append("%s — %d:%02d" % [TranslationServer.translate("CRED_STAT_TIME"), int(t) / 3600, (int(t) % 3600) / 60])
	return "\n".join(lines)
