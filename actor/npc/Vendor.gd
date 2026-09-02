class_name Vendor
extends Npc
## Скупщик-NPC (§11): стоит за прилавком, шаркает, смотрит на ближнего игрока,
## здоровается когда подходят, шарахается от фобий и 6 с отказывается говорить.
## Реплики — из VendorDef (ru/en), голос — audio/voice/<lang>/<vendor_id>/.

const GREET_COOLDOWN := 20.0
const GREET_RADIUS := 3.0
const LOOK_RADIUS := 8.0

var def: VendorDef
var spot: Vector3
var face_pos: Vector3
var player_spot: Vector3
var refuse_until := 0.0
var _greet_cd := 3.0
var _shuffle_t := 5.0
var _scare_back_t := 0.0


## Внешность/голос из карточки. Звать ДО add_child (Npc._ready строит меш).
func setup(p_def: VendorDef) -> void:
	def = p_def
	npc_group = def.id
	body_color = def.body_color
	voice_pitch = def.voice_pitch
	display_name = def.display_name()
	speed = 2.0
	match def.vendor_type:
		Types.VendorType.ANTIQUE:
			hat = true
			height = 1.7
			fatness = 0.9
		Types.VendorType.HOUSEHOLD:
			height = 1.65
			fatness = 1.3
		Types.VendorType.TECH:
			bald = true
			height = 1.8
			fatness = 0.85
		Types.VendorType.DARK:
			hat = true
			bald = true
			height = 1.85


func place(p_spot: Vector3, p_face: Vector3, p_player_spot: Vector3) -> void:
	spot = p_spot
	face_pos = p_face
	player_spot = p_player_spot
	global_position = spot
	face(face_pos)


func line(category: String) -> String:
	if def == null:
		return ""
	match category:
		"greet": return def.pick(def.lines_greet_ru, def.lines_greet_en)
		"scream": return def.pick(def.lines_scream_ru, def.lines_scream_en)
		"deal": return def.pick(def.lines_deal_ru, def.lines_deal_en)
		"reject": return def.pick(def.lines_reject_ru, def.lines_reject_en)
		"phobia": return def.pick(def.lines_phobia_ru, def.lines_phobia_en)
	return ""


## Реплика категории из карточки; если карточка пустая — строка по ключу.
func say_line(category: String, fallback_key: String, seconds: float = 2.5) -> void:
	var t := line(category)
	if t == "":
		t = tr(fallback_key)
	say(t, seconds, category)


func is_refusing() -> bool:
	return Time.get_ticks_msec() / 1000.0 < refuse_until


## Фобия: отпрыгнуть от прилавка (away — направление от игрока) и не разговаривать refuse_sec.
func scare(away: Vector3, refuse_sec: float = 6.0) -> void:
	refuse_until = Time.get_ticks_msec() / 1000.0 + refuse_sec
	var flat := Vector3(away.x, 0.0, away.z)
	if flat.length() < 0.01:
		flat = -global_basis.z
	var back := spot + flat.normalized() * 1.2
	if Net.is_host():
		move_to(back)
		_scare_back_t = 2.5
	else:
		var tw := create_tween()
		tw.tween_property(self, "global_position", back, 0.3)
		tw.tween_interval(2.0)
		tw.tween_property(self, "global_position", spot, 0.6)
	AudioBus.play_at("oof", global_position, -2.0, 0.3)


func _nearest_player() -> Player:
	var best: Player = null
	var best_d := 1e9
	for pid in Net.players:
		var p = Net.players[pid]
		if p == null or not is_instance_valid(p) or p.dead:
			continue
		var d: float = p.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


func _physics_process(delta: float) -> void:
	super(delta)
	if ragdolled or def == null:
		return
	var near := _nearest_player()
	if not moving:
		if near and near.global_position.distance_to(global_position) < LOOK_RADIUS:
			face(near.global_position)
		else:
			face(face_pos)
	if not Net.is_host():
		return
	if _scare_back_t > 0.0:
		_scare_back_t -= delta
		if _scare_back_t <= 0.0:
			move_to(spot)
		return
	_greet_cd -= delta
	if near and _greet_cd <= 0.0 and not is_refusing() and near.global_position.distance_to(player_spot) < GREET_RADIUS:
		_greet_cd = GREET_COOLDOWN
		say_line("greet", "VEND_GREET_DEFAULT")
	_shuffle_t -= delta
	if _shuffle_t <= 0.0 and not moving:
		_shuffle_t = randf_range(4.0, 9.0)
		move_to(spot + Vector3(randf_range(-0.25, 0.25), 0.0, randf_range(-0.15, 0.15)))
