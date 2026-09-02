class_name Sleep
extends Node
## Сон на кровати трейлера. Ночью (или поздним вечером) E на Bed0..3 → затемнение, скип до утра, хил.
## Днём кровать только «лечь отдохнуть» нельзя — иначе ломаем цикл дня. Время само идёт в DayNight (~24 мин/сутки).

const WAKE_TIME := 0.28 ## раннее утро после ночи (чуть после восхода)
const SLEEP_COOL := 45.0
const EVENING_FROM := 0.86 ## уже можно лечь «досыпать»

var _beds: Array = [] # Vendors.Interactable
var _busy := false
var _cool_until := 0.0


func system_name() -> String:
	return "Sleep"


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_hook_beds()


func _hook_beds() -> void:
	var w := Game.world
	if w == null or w.city == null:
		return
	for i in 4:
		var m: Node3D = w.find_marker(Types.District.TRAILER_PARK, "Bed%d" % i)
		if m == null:
			continue
		var bed := Vendors.Interactable.new(Vector3(2.0, 0.9, 1.2))
		bed.name = "SleepBed_%d" % i
		add_child(bed)
		bed.global_position = m.global_position + Vector3(0, 0.45, 0)
		bed.set_meta("bed_i", i)
		bed.on_interact = _on_bed.bind(bed)
		bed.on_hint = _hint.bind(bed)
		_beds.append(bed)
	if OS.is_debug_build():
		print("[Sleep] beds=%d" % _beds.size())


func _dn() -> DayNight:
	return Game.world.system("DayNight") as DayNight if Game.world else null


func can_sleep_now() -> bool:
	var dn := _dn()
	if dn == null:
		return false
	if dn.is_night():
		return true
	# поздний вечер — тоже можно «дотянуть до утра»
	return dn.time_of_day >= EVENING_FROM


## Сигнатура как у Vendors._stand_hint: (player, bound…) — bind дописывает аргументы в конец.
func _hint(_p: Player, _bed: Node = null) -> String:
	if _busy:
		return tr("SLEEP_BUSY")
	if Time.get_ticks_msec() / 1000.0 < _cool_until:
		return tr("SLEEP_COOL")
	if can_sleep_now():
		return tr("SLEEP_HINT_NIGHT")
	return tr("SLEEP_HINT_DAY")


func _on_bed(player: Player, bed: Node) -> void:
	if not Net.is_host() or player == null or _busy:
		return
	if player.dead or player.cuffed or player.in_custody or player.in_vehicle:
		return
	if Time.get_ticks_msec() / 1000.0 < _cool_until:
		player.say(tr("SLEEP_COOL"), 1.5)
		return
	if not can_sleep_now():
		player.say(tr("SLEEP_DAY"), 2.0)
		return
	_busy = true
	_do_sleep(player, int(bed.get_meta("bed_i", 0)))


func _do_sleep(p: Player, bed_i: int) -> void:
	# отпустить вещи — не спим с вазой в руках
	if p.hands:
		p.hands.host_release_all()
	p.crouching = false
	p._crouch_blend = 0.0
	if p.has_method("_apply_crouch"):
		p._apply_crouch(0.0)
	# лечь на кровать
	var m: Node3D = Game.world.find_marker(Types.District.TRAILER_PARK, "Bed%d" % bed_i) if Game.world else null
	if m:
		p.global_position = m.global_position + Vector3(0, 0.35, 0)
		p.velocity = Vector3.ZERO
		p.look_toward(m.global_position + Vector3(0, 0.35, 1.0))
	p.cinematic = true
	Net.broadcast_event("sleep", {"peer": p.peer_id, "bed": bed_i, "phase": "start"})
	var cine: Cinematic = Game.world.system("Cinematic") as Cinematic if Game.world else null
	if cine:
		await cine.fade_to_black(0.7)
		await cine.card(tr("SLEEP_CARD_TITLE"), tr("SLEEP_CARD_SUB"), 1.6)
	else:
		await get_tree().create_timer(1.2).timeout
	_skip_to_morning()
	# хил / протрезветь
	p.hp = 100.0
	p.drunk = maxf(0.0, p.drunk - 0.55)
	p.set_burning(false)
	p.stuck = 0.0
	p.slip = 0.0
	if m:
		p.global_position = m.global_position + Vector3(0, 0.55, 0)
	if cine:
		await cine.fade_from_black(0.8)
	p.cinematic = false
	p.say(tr("SLEEP_WOKE"), 2.5)
	Game.notify.emit(tr("SLEEP_WOKE"), 3.0)
	_cool_until = Time.get_ticks_msec() / 1000.0 + SLEEP_COOL
	_busy = false
	Net.broadcast_event("sleep", {"peer": p.peer_id, "bed": bed_i, "phase": "wake", "t": _dn().time_of_day if _dn() else WAKE_TIME})
	Game.stat_add("sleeps")


func _skip_to_morning() -> void:
	var dn := _dn()
	if dn == null:
		return
	dn.time_of_day = WAKE_TIME
	Game.save["time_of_day"] = WAKE_TIME
	if dn.has_method("_apply"):
		dn._apply()
	if Net.peer_count() > 1:
		Net.broadcast_event("time_of_day", {"t": WAKE_TIME})


func on_net_event(kind: String, data: Dictionary) -> void:
	if kind != "sleep":
		return
	var peer := int(data.get("peer", 0))
	var phase := str(data.get("phase", ""))
	var p: Player = Net.players.get(peer) as Player if Net.players.has(peer) else null
	if phase == "start" and p and peer != Net.my_id():
		p.cinematic = true
		var bed_i := int(data.get("bed", 0))
		var m: Node3D = Game.world.find_marker(Types.District.TRAILER_PARK, "Bed%d" % bed_i) if Game.world else null
		if m:
			p.global_position = m.global_position + Vector3(0, 0.35, 0)
	elif phase == "wake":
		var dn := _dn()
		if dn and data.has("t"):
			dn.time_of_day = float(data["t"])
		if p and peer != Net.my_id():
			p.cinematic = false
			p.hp = 100.0
