class_name Gags
extends Node3D
## Приколы мира (§2.1 «каждый элемент отвечает приколом»). Хост дёргает случайные мелкие события,
## чтобы город жил и над ним ржали. Ничего не ломает прогресс, всё косметика + мелкие импульсы.

const TICK := 6.0

var _t := 0.0
var _hamster_escapes := 0
var _crow: Node3D = null
var _crow_target: ItemBody = null
var _crow_timer := 0.0
var _gag_cooldowns: Dictionary = {}


func system_name() -> String:
	return "Gags"


func _ready() -> void:
	Net.item_spawned.connect(_on_item_spawned)


func _on_item_spawned(b: Node) -> void:
	if b is ItemBody and b.def.has_facet(Types.Facet.ALIVE):
		b.opened.connect(_on_cage_opened)


## Клетку открыли — хомяк/мышь сбегает и носится (§17.2 хомяк, мышь).
func _on_cage_opened(b: ItemBody, is_open: bool) -> void:
	if not Net.is_host() or not is_open:
		return
	if b.def.tags.has("hamster") or b.def.tags.has("mouse"):
		_hamster_escapes += 1
		b.alive_awake = true
		b.apply_central_impulse(Vector3(randf_range(-2, 2), 3.0, randf_range(-2, 2)) * b.mass)
		AudioBus.play_at("mouse_squeak" if b.def.tags.has("mouse") else "squeak", b.global_position, 2.0, 0.4)
		Game.notify.emit(tr("GAG_PET_ESCAPED") % b.def.display_name(), 3.0)
		if _hamster_escapes >= 3:
			Achievements.unlock("hamster")


func _process(delta: float) -> void:
	if not Net.is_host() or Game.world == null:
		return
	_t += delta
	_crow_tick(delta)
	if _t < TICK:
		return
	_t = 0.0
	_maybe_gag()


func _cool(name: String, seconds: float) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if float(_gag_cooldowns.get(name, -999.0)) + seconds > now:
		return false
	_gag_cooldowns[name] = now
	return true


func _maybe_gag() -> void:
	var players := Net.players.values()
	if players.is_empty():
		return
	var p = players[randi() % players.size()]
	if not is_instance_valid(p) or p.dead:
		return
	var roll := randf()
	if roll < 0.14 and _cool("crow", 60.0):
		_spawn_crow(p)
	elif roll < 0.26 and _cool("chandelier", 90.0):
		_drop_something_heavy(p)
	elif roll < 0.38 and _cool("mouse", 75.0):
		_mouse_runs_by(p)
	elif roll < 0.5 and _cool("wind", 45.0):
		_gust_of_wind(p)
	elif roll < 0.6 and _cool("dog", 120.0):
		_stray_dog(p)
	elif roll < 0.72 and _cool("radio", 100.0):
		_radio_static(p)
	elif roll < 0.85 and _cool("pet", 30.0):
		_pet_noise(p)


## Ворона утаскивает мелкую блестящую вещь (и роняет через 8 с).
func _spawn_crow(p) -> void:
	if _crow and is_instance_valid(_crow):
		return
	var candidates: Array = []
	for nid in Net.items:
		var b = Net.items[nid]
		if is_instance_valid(b) and not b.is_held() and b.nested_in == null and b.arch.size_class <= Types.SizeClass.ONE_HAND \
				and b.global_position.distance_to(p.global_position) < 18.0 and b.def.value_base >= 5:
			candidates.append(b)
	if candidates.is_empty():
		return
	_crow_target = candidates[randi() % candidates.size()]
	_crow = Node3D.new()
	var body := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.09
	cm.height = 0.34
	cm.radial_segments = 8
	body.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.09, 0.09, 0.11)
	body.material_override = m
	body.rotation.x = PI / 2
	_crow.add_child(body)
	for s in [-1.0, 1.0]:
		var wing := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.3, 0.02, 0.14)
		wing.mesh = bm
		wing.material_override = m
		wing.position = Vector3(0.18 * s, 0.02, 0)
		wing.name = "Wing"
		_crow.add_child(wing)
	var beak := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.05, 0.1, 0.05)
	beak.mesh = pm
	var m2 := StandardMaterial3D.new()
	m2.albedo_color = Color(0.85, 0.7, 0.1)
	beak.material_override = m2
	beak.rotation.x = -PI / 2
	beak.position = Vector3(0, 0, -0.2)
	_crow.add_child(beak)
	Game.world.npcs_root.add_child(_crow)
	_crow.global_position = _crow_target.global_position + Vector3(0, 8, 0)
	_crow_timer = 0.0
	AudioBus.play_at("squeak", _crow.global_position, -2.0, 0.5)
	Game.notify.emit(tr("GAG_CROW"), 3.0)


func _crow_tick(delta: float) -> void:
	if _crow == null or not is_instance_valid(_crow):
		return
	_crow_timer += delta
	for w in _crow.get_children():
		if w.name == "Wing":
			w.rotation.z = sin(Time.get_ticks_msec() * 0.02) * 0.8
	if _crow_timer < 1.6:
		# пикирует
		if is_instance_valid(_crow_target):
			_crow.global_position = _crow.global_position.lerp(_crow_target.global_position + Vector3(0, 0.25, 0), delta * 3.0)
			var flat := _crow_target.global_position - _crow.global_position
			flat.y = 0.0
			if flat.length() > 0.05: # над целью взгляд был бы вертикальным → colinear warning
				_crow.look_at(_crow.global_position + flat, Vector3.UP)
	elif _crow_timer < 9.0:
		# уносит
		if is_instance_valid(_crow_target) and not _crow_target.is_held():
			_crow.global_position += (Vector3.UP * 1.2 + _crow.global_basis.z * -2.0) * delta
			_crow_target.global_position = _crow.global_position + Vector3(0, -0.25, 0)
			_crow_target.linear_velocity = Vector3.ZERO
		else:
			_crow_timer = 9.5
	else:
		if is_instance_valid(_crow_target):
			_crow_target.linear_velocity = Vector3(randf_range(-2, 2), -1, randf_range(-2, 2))
			AudioBus.play_at("whoosh", _crow_target.global_position, -4.0)
		_crow.queue_free()
		_crow = null
		_crow_target = null


## Люстра/полка срывается рядом с игроком (§7.1 light_fixture: «люстра, падает»).
func _drop_something_heavy(p) -> void:
	for nid in Net.items:
		var b = Net.items[nid]
		if is_instance_valid(b) and b.arch.light_fixture and not b.is_held() \
				and b.global_position.distance_to(p.global_position) < 6.0 and b.global_position.y > p.global_position.y + 1.0:
			b.sleeping = false
			b.apply_central_impulse(Vector3(0, -3, 0) * b.mass)
			AudioBus.play_at("crack", b.global_position, 0.0)
			Game.notify.emit(tr("GAG_CHANDELIER"), 3.0)
			return


## Мышь пробегает: звук + мелкий импульс по хламу.
func _mouse_runs_by(p) -> void:
	var pos: Vector3 = p.global_position + Vector3(randf_range(-3, 3), 0.1, randf_range(-3, 3))
	AudioBus.play_at("mouse_squeak", pos, 0.0, 0.5)
	for b in Game.world.items_in_radius(pos, 1.5):
		if b.mass < 3.0:
			b.sleeping = false
			b.apply_central_impulse(Vector3(randf_range(-0.6, 0.6), 0.2, randf_range(-0.6, 0.6)) * b.mass)
	Game.notify.emit(tr("GAG_MOUSE"), 2.0)


## Порыв ветра: бумажки и тряпки летят.
func _gust_of_wind(p) -> void:
	var dir := Vector3(randf_range(-1, 1), 0.15, randf_range(-1, 1)).normalized()
	var moved := 0
	for b in Game.world.items_in_radius(p.global_position, 12.0):
		if b.mass <= 0.6 and not b.is_held():
			b.sleeping = false
			b.apply_central_impulse(dir * b.mass * randf_range(2.0, 5.0))
			moved += 1
	if moved > 0:
		AudioBus.play_at("wind_gust" if AudioBus.has("wind_gust") else "whoosh", p.global_position, -2.0, 0.3)
		if moved >= 4:
			Game.notify.emit(tr("GAG_WIND"), 2.5)


## Бродячая собака: тявкает, толкает вещь, убегает.
func _stray_dog(p) -> void:
	var dog := Npc.new()
	dog.npc_group = "generic"
	dog.display_name = tr("GAG_DOG_NAME")
	dog.body_color = Color(0.55, 0.42, 0.25)
	dog.height = 0.7
	dog.fatness = 0.8
	dog.bald = true
	dog.speed = 5.5
	dog.voice_pitch = 1.6
	Game.world.npcs_root.add_child(dog)
	dog.global_position = p.global_position + Vector3(randf_range(-9, 9), 0.4, randf_range(-9, 9))
	dog.say(tr("GAG_DOG_BARK"), 1.5)
	AudioBus.play_at("squeak", dog.global_position, 2.0, 0.5)
	var loot: Array = Game.world.items_in_radius(dog.global_position, 8.0)
	if not loot.is_empty():
		var t: ItemBody = loot[randi() % loot.size()]
		dog.move_to(t.global_position)
		dog.arrived.connect(func():
			if is_instance_valid(t) and not t.is_held():
				t.sleeping = false
				t.apply_central_impulse((t.global_position - dog.global_position).normalized() * t.mass * 4.0 + Vector3.UP * t.mass)
				AudioBus.play_at("flop", t.global_position, -2.0)
			dog.move_to(dog.global_position + Vector3(randf_range(-25, 25), 0, randf_range(-25, 25)))
			, CONNECT_ONE_SHOT)
	await get_tree().create_timer(22.0).timeout
	if is_instance_valid(dog):
		dog.queue_free()


func _radio_static(p) -> void:
	for nid in Net.items:
		var b = Net.items[nid]
		if is_instance_valid(b) and (b.arch.builder == "radio" or b.arch.builder == "boombox") and b.global_position.distance_to(p.global_position) < 12.0:
			AudioBus.play_at("police_radio", b.global_position, -2.0, 0.4)
			Game.notify.emit(tr("GAG_RADIO"), 2.5)
			return


func _pet_noise(p) -> void:
	for nid in Net.items:
		var b = Net.items[nid]
		if is_instance_valid(b) and b.def.has_facet(Types.Facet.ALIVE) and b.global_position.distance_to(p.global_position) < 10.0:
			AudioBus.play_at("hamster_wheel" if b.def.tags.has("hamster") else "squeak", b.global_position, -4.0, 0.3)
			return
