extends Node
## Дымовой тест: godot --headless --path . -- --smoke
## Меню само стартует слот 3, мир спавнит вещи всех архетипов, роняет, ломает, льёт, жжёт; печатает отчёт и выходит.
## С окном: godot --path . -- --smoke --shots  → скриншоты районов в user://shots/ (визуальная проверка).

var _t := 0.0
var _stage := 0
var _spawned: Array = []
var errors: Array[String] = []
var _shot_targets: Array = []
var _shot_i := 0
var _shot_timer := 0.0
var _shots_dir := ""


static func wanted() -> bool:
	return OS.get_cmdline_user_args().has("--smoke")


static func shots_wanted() -> bool:
	return OS.get_cmdline_user_args().has("--shots") and DisplayServer.get_name() != "headless"


func _ready() -> void:
	if shots_wanted():
		_shots_dir = OS.get_user_data_dir().path_join("shots")
		DirAccess.make_dir_recursive_absolute(_shots_dir)
		for f in DirAccess.get_files_at(_shots_dir):
			DirAccess.remove_absolute(_shots_dir.path_join(f))


func _process(delta: float) -> void:
	_t += delta
	match _stage:
		0:
			if _t > 1.0:
				_stage = 1
				_spawn_all()
		1:
			if _t > 3.0:
				_stage = 2
				_stress()
		2:
			if _t > 7.0:
				_check_drop()
				if shots_wanted():
					_stage = 10
					_prepare_shots()
				else:
					_stage = 3
					_report()
		10:
			_shots_tick(delta)


func _spawn_all() -> void:
	var i := 0
	for def in Registry.all_items():
		if i >= 240:
			break
		var pos := Vector3(-20 + (i % 16) * 1.2, 2.0 + (i / 16) * 0.1, 20 + (i / 16) * 1.2)
		var b = Net.spawn_item(def.id, Transform3D(Basis(), pos))
		if b == null:
			errors.append("spawn failed: " + def.id)
		else:
			_spawned.append(b)
		i += 1
	print("[smoke] spawned %d items (registry=%d, archetypes=%d)" % [_spawned.size(), Registry.items.size(), Registry.archetypes.size()])
	# смерть → ragdoll → оверлей → респавн на кровати через 5 с (§6.4)
	var p: Player = Game.world.local_player()
	if p:
		_death_pos = p.global_position
		p.die("fall")
	for a in Registry.archetypes.values():
		var d := ItemDef.new()
		d.id = "smoke_" + a.id
		d.archetype_id = a.id
		var built := ArchetypeMeshes.build(a, d)
		if built["root"] == null:
			errors.append("builder failed: " + a.id)
		else:
			built["root"].free()


func _stress() -> void:
	var n := 0
	for b in _spawned:
		if not is_instance_valid(b):
			continue
		n += 1
		if n % 3 == 0 and b.def.is_fragile():
			b.shatter()
		elif n % 5 == 0 and b.def.liquid_id != Types.LiquidId.NONE:
			b.is_open = true
			b.spill(0.5)
		elif n % 7 == 0 and b.is_flammable():
			b.ignite()
		elif n % 4 == 0:
			b.apply_central_impulse(Vector3(randf_range(-3, 3), 5, randf_range(-3, 3)) * b.mass)
	var p: Player = Game.world.local_player()
	if p and _spawned.size() > 0 and is_instance_valid(_spawned[0]):
		p.hands.host_grab(_spawned[0], 0)
	print("[smoke] stress applied to %d bodies" % n)
	# гарантия геймплея: ваза с 2 м на бетон обязана разбиться сама, без броска
	var vases: Array = Registry.items_with_tag("vase")
	var vd: ItemDef = vases[0] if not vases.is_empty() else Registry.random_item_with_facet(Types.Facet.FRAGILE)
	_drop_vase = Net.spawn_item(vd.id, Transform3D(Basis(), Vector3(30, 2.2, 30)))
	# вариант «как в трейлере»: с вращением, у ячейки склада
	var pos2 := Vector3(34, 2.0, 30)
	for a in get_tree().get_nodes_in_group("lot_anchors"):
		var dist = Game.world.city.district_at(a.global_position)
		if dist and dist.district_id == Types.District.STORAGE:
			pos2 = a.cell_center() + a.cell().global_basis.z * 5.0 + Vector3(0, -a.cell_size.y * 0.5 + 2.0, 0)
			break
	_drop_vase2 = Net.spawn_item(vd.id, Transform3D(Basis(), pos2))
	if _drop_vase2:
		_drop_vase2.linear_velocity = Vector3(0, -3.0, 0)
		_drop_vase2.angular_velocity = Vector3(2.0, 0.5, 1.0)


var _drop_vase: ItemBody
var _drop_vase2: ItemBody


func _check_drop() -> void:
	for pair in [[_drop_vase, "plain"], [_drop_vase2, "spinning"]]:
		var v: ItemBody = pair[0]
		if v and is_instance_valid(v):
			if v.integrity == Types.Integrity.WHOLE:
				errors.append("drop test (%s): %s from 2m did not break (threshold %.1f) at %s" % [pair[1], v.def.id, v.def.break_threshold, str(v.global_position.round())])
			else:
				print("[smoke] drop test ok (%s): %s integrity=%d" % [pair[1], v.def.id, v.integrity])


var _death_pos := Vector3.ZERO


func _report() -> void:
	var p: Player = Game.world.local_player()
	if p:
		if p.dead:
			errors.append("death test: player still dead 5s+ after die()")
		elif p.hp < 99.0:
			errors.append("death test: hp not restored (%.0f)" % p.hp)
		else:
			print("[smoke] death test ok: respawned at %s (died at %s)" % [str(p.global_position.round()), str(_death_pos.round())])
	var alive := 0
	for b in _spawned:
		if is_instance_valid(b):
			alive += 1
	var liq = Game.world.system("Liquids")
	var fire = Game.world.system("Fire")
	print("[smoke] alive=%d puddles=%d lit=%d pot=%d mode=%d" % [alive, liq.puddles.size() if liq else -1, fire.lit_bodies.size() if fire else -1, Economy.pot, Game.world_mode])
	for e in errors:
		printerr("[smoke] " + e)
	print("[smoke] DONE errors=%d" % errors.size())
	cleanup_test_slot()
	get_tree().quit(1 if errors.size() > 0 else 0)


## Тестовые прогоны живут в слоте 3 — не оставляем игроку мусорный «Слот 4».
static func cleanup_test_slot() -> void:
	if Game.slot == 3:
		Game.slot = -1 # блокируем автосейв при выходе
		Game.delete_slot(3)


# ------------------------------------------------------------------ скриншоты

func _prepare_shots() -> void:
	_shot_targets.clear()
	# вещи, которые наспавнили
	_shot_targets.append({"name": "items", "pos": Vector3(-12, 4, 12), "look": Vector3(-12, 0.5, 26)})
	var city = Game.world.city
	if city and city.has_method("districts"):
		for d in city.districts():
			var c: Vector3 = d.global_position
			_shot_targets.append({"name": d.name, "pos": c + Vector3(-18, 9, 22), "look": c + Vector3(0, 1, 0)})
			_shot_targets.append({"name": d.name + "_ground", "pos": c + Vector3(6, 1.7, 10), "look": c + Vector3(0, 1.2, 0)})
	_shot_i = 0
	_shot_timer = 0.0
	var p: Player = Game.world.local_player()
	if p:
		p.set_physics_process(false)
		p.set_process_input(false)
	var hud = Game.world.hud
	if hud:
		hud.visible = false # чистые кадры без худа
	print("[smoke] shots: %d targets" % _shot_targets.size())


func _shots_tick(delta: float) -> void:
	_shot_timer += delta
	if _shot_i >= _shot_targets.size():
		print("[smoke] shots saved to %s" % _shots_dir)
		_report()
		_stage = 99
		return
	var t: Dictionary = _shot_targets[_shot_i]
	var p: Player = Game.world.local_player()
	if p:
		p.camera.global_position = t["pos"]
		p.camera.look_at(t["look"], Vector3.UP)
	if _shot_timer > 0.6:
		_shot_timer = 0.0
		var img := get_viewport().get_texture().get_image()
		img.save_png(_shots_dir.path_join("%02d_%s.png" % [_shot_i, t["name"]]))
		_shot_i += 1
