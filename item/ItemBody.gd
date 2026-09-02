class_name ItemBody
extends RigidBody3D
## Общий спавн вещи из ItemDef (§7). Одно физтело на карточку; меш — архетип.
## Состояния на инстансе: integrity, dirt, paint_color, wet, taped, boarded, locked, lit.
## Хост считает физику и события; клиентские прокси интерполируют снапшоты.

signal broke(body: ItemBody)
signal state_changed(body: ItemBody)
signal opened(body: ItemBody, is_open: bool)
signal picked(body: ItemBody, by: Node)
signal dropped(body: ItemBody)

const SHARD_SCENE_PATH := "res://item/shards/Shard.tscn"
const PILE_VALUE := 1
const _PuffFx := preload("res://item/PuffFx.gd")

var def: ItemDef
var arch: Archetype
var net_id: int = 0
var proxy := false

# --- состояния инстанса
var integrity: int = Types.Integrity.WHOLE
var dirt: float = 0.0
var paint_color: Color = Color(0, 0, 0, 0)
var wet: float = 0.0
var taped := false
var boarded := false
var locked := false
var lit := false
var burnt := false
var burn_hp := 1.0
var liquid_left := 1.0
var is_open := false
var open_drawers: int = 0
var torn := false # переусердствовал тряпкой
var glued := false
var alive_awake := true # хомяк/мышь бегает

# --- связи
var nested_in: ItemBody = null
var nested: Array[ItemBody] = []
var held_by: Array = [] # Hands, до 2 (TEAM)
var worn_by: Node = null
var in_vehicle_bed := false
var lot_id: String = "" # из какого лота вынесен (для janitor/broom)

# --- меш
var mesh_root: Node3D
var _materials: Array[StandardMaterial3D] = []
var _base_colors: Array[Color] = []
var _surface_overridden: Array[MeshInstance3D] = []
static var _crack_decal: Texture2D = null
var _drawers: Array[Node3D] = []
var _lid: Node3D = null
var _walls: Array[Node3D] = []
var _fire_fx: Node3D = null
var _pile_mode := false

# --- физика
var _prev_vel := Vector3.ZERO
var _touching := false
var _target_pos := Vector3.ZERO
var _target_quat := Quaternion.IDENTITY
var _target_vel := Vector3.ZERO
var _has_target := false
var _spill_cooldown := 0.0
var _last_impact_sound := 0.0
var _alive_timer := 0.0
var _shake_accum := 0.0


static func create(p_def: ItemDef) -> ItemBody:
	var b := ItemBody.new()
	b.def = p_def
	b.arch = Registry.archetype_for(p_def)
	b.name = "Item_%s" % p_def.id
	b.setup()
	return b


func setup() -> void:
	collision_layer = Types.L_ITEM
	collision_mask = Types.L_WORLD | Types.L_PLAYER | Types.L_ITEM | Types.L_VEHICLE | Types.L_NPC | Types.L_SHARD
	mass = def.mass_override if def.mass_override > 0.0 else arch.mass_default
	continuous_cd = def.is_fragile()
	contact_monitor = true
	max_contacts_reported = 4
	can_sleep = true
	linear_damp = 0.05
	angular_damp = 0.4
	var pm := PhysicsMaterial.new()
	pm.friction = arch.friction
	pm.bounce = arch.bounce
	physics_material_override = pm
	locked = def.has_facet(Types.Facet.LOCKED)
	dirt = def.dusty_default
	liquid_left = def.liquid_amount if def.liquid_id != Types.LiquidId.NONE else 0.0
	_build_visual()
	body_entered.connect(_on_body_entered)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_drop_surface_overrides()


func _build_visual() -> void:
	if mesh_root:
		_drop_surface_overrides()
		mesh_root.queue_free()
	for c in get_children():
		if c is CollisionShape3D:
			c.queue_free()
	_materials.clear()
	_base_colors.clear()
	_drawers.clear()
	_walls.clear()
	_lid = null
	var built: Dictionary
	if arch.scene:
		var inst := arch.scene.instantiate()
		built = {"root": inst, "shapes": []}
		if inst.has_method("get_shapes"):
			built["shapes"] = inst.get_shapes()
	else:
		built = ArchetypeMeshes.build(arch, def)
	mesh_root = built["root"]
	mesh_root.name = "Mesh"
	mesh_root.scale = Vector3.ONE * def.scale
	add_child(mesh_root)
	var shapes: Array = built["shapes"]
	if shapes.is_empty():
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = arch.dims * def.scale
		cs.shape = bs
		cs.position.y = arch.dims.y * 0.5 * def.scale
		add_child(cs)
	else:
		for s in shapes:
			var cs := CollisionShape3D.new()
			cs.shape = s["shape"]
			cs.transform = s["xform"]
			cs.transform.origin *= def.scale
			add_child(cs)
	_collect_materials(mesh_root)
	for path in arch.drawer_paths:
		var n := mesh_root.get_node_or_null(path)
		if n:
			_drawers.append(n)
	if _drawers.is_empty():
		_find_named(mesh_root, "Drawer", _drawers)
	var lids: Array[Node3D] = []
	_find_named(mesh_root, "Lid", lids)
	if not lids.is_empty():
		_lid = lids[0]
	_find_named(mesh_root, "Wall", _walls)
	# cracked/broken cards: decal only — integrity/value stay WHOLE
	_refresh_material()
	_refresh_nested_visibility()


func _find_named(n: Node, prefix: String, out: Array) -> void:
	for c in n.get_children():
		if c is Node3D and c.name.begins_with(prefix):
			out.append(c)
		_find_named(c, prefix, out)


## Свой экземпляр материала на каждый меш, чтобы красить/пачкать вещь независимо.
## Меши архетипов одноповерхностные и/или с material_override — берём override целиком:
## per-surface override у общего (кэшированного LowPoly) меша при free() ловит ошибку
## рендер-сервера «Parameter material is null» (Godot 4.6), material_override — нет.
func _collect_materials(n: Node) -> void:
	if n is MeshInstance3D and n.mesh:
		var mi := n as MeshInstance3D
		var surfaces := mi.mesh.get_surface_count()
		if surfaces <= 1 or mi.material_override != null:
			var sm := _own_material(mi.get_active_material(0))
			mi.material_override = sm
			_materials.append(sm)
			_base_colors.append(sm.albedo_color)
		else:
			for i in surfaces:
				var sm := _own_material(mi.get_active_material(i))
				mi.set_surface_override_material(i, sm)
				_materials.append(sm)
				_base_colors.append(sm.albedo_color)
			_surface_overridden.append(mi)
	for child in n.get_children():
		_collect_materials(child)


static func _own_material(src: Material) -> StandardMaterial3D:
	if src is StandardMaterial3D:
		return (src as StandardMaterial3D).duplicate() as StandardMaterial3D
	return StandardMaterial3D.new()


## Снять per-surface override до освобождения узла (см. _collect_materials).
func _drop_surface_overrides() -> void:
	for mi in _surface_overridden:
		if is_instance_valid(mi) and mi.mesh:
			for i in mi.mesh.get_surface_count():
				mi.set_surface_override_material(i, null)
	_surface_overridden.clear()


## Визуал состояния — всё на модели, не в худе (§16).
func _refresh_material() -> void:
	var dims := Vector3(0.3, 0.3, 0.3)
	if arch:
		dims = arch.dims
	if def:
		dims *= def.scale
	var extent := maxf(maxf(dims.x, dims.y), dims.z)
	var crack_scale := 0.75 / maxf(extent, 0.08)
	var show_crack := integrity == Types.Integrity.CHIPPED
	if def:
		var idl: String = def.id
		if idl.contains("cracked") or idl.contains("broken"):
			show_crack = true
		else:
			for tag in def.tags:
				var ts: String = tag
				if ts == "cracked" or ts == "broken":
					show_crack = true
					break
	if show_crack and _crack_decal == null:
		var crack_path := "res://assets/textures/tex_crack_decal.png"
		if ResourceLoader.exists(crack_path):
			_crack_decal = load(crack_path) as Texture2D
	for i in _materials.size():
		var m: StandardMaterial3D = _materials[i]
		var c: Color = _base_colors[i]
		if paint_color.a > 0.01:
			c = c.lerp(Color(paint_color.r, paint_color.g, paint_color.b), paint_color.a * 0.9)
		var dust := clampf(dirt, 0.0, 1.0)
		if dust > 0.01:
			var lum := c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
			c = c.lerp(Color(lum, lum, lum), dust * 0.45)
			c = c.lerp(Color(0.62, 0.58, 0.52), dust * 0.35)
		if wet > 0.01:
			c = c.darkened(0.20 * wet)
			m.roughness = lerpf(lerpf(0.7, 1.0, dust), 0.15, wet)
		else:
			m.roughness = lerpf(0.7, 1.0, dust)
		if burnt:
			c = c.lerp(Color(0.05, 0.04, 0.03), 0.9)
		m.albedo_color = c
		if lit:
			m.emission_enabled = true
			m.emission = Color(1.0, 0.45, 0.1)
			m.emission_energy_multiplier = 1.5
		else:
			m.emission_enabled = false
		if show_crack and _crack_decal:
			m.detail_enabled = true
			m.detail_albedo = _crack_decal
			m.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
			var crack_uv := Vector3(crack_scale, crack_scale, crack_scale)
			var crack_off := Vector3(0.5, 0.5, 0.5)
			if m.albedo_texture:
				m.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
				m.uv2_triplanar = true
				m.uv2_world_triplanar = false
				m.uv2_triplanar_sharpness = 4.0
				m.uv2_scale = crack_uv
				m.uv2_offset = crack_off
			else:
				m.detail_uv_layer = BaseMaterial3D.DETAIL_UV_1
				m.uv1_triplanar = true
				m.uv1_world_triplanar = false
				m.uv1_triplanar_sharpness = 4.0
				m.uv1_scale = crack_uv
				m.uv1_offset = crack_off
		else:
			m.detail_enabled = false
			m.uv1_triplanar = false
			m.uv2_triplanar = false
			if m.albedo_texture == null:
				m.uv1_scale = Vector3.ONE
				m.uv1_offset = Vector3.ZERO
			m.uv2_scale = Vector3.ONE
			m.uv2_offset = Vector3.ZERO
	_update_fire_fx()


# ------------------------------------------------------------------ сеть

func set_proxy(v: bool) -> void:
	proxy = v
	if proxy:
		freeze = true
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		contact_monitor = false


func state_dict() -> Dictionary:
	return {
		"i": integrity, "d": dirt, "p": [paint_color.r, paint_color.g, paint_color.b, paint_color.a],
		"w": wet, "t": taped, "b": boarded, "lk": locked, "l": lit, "bu": burnt, "lq": liquid_left,
		"o": is_open, "od": open_drawers, "tr": torn, "g": glued, "lot": lot_id, "sl": sleeping,
	}


func apply_state(s: Dictionary) -> void:
	if s.is_empty():
		return
	var was_integrity := integrity
	integrity = int(s.get("i", integrity))
	dirt = float(s.get("d", dirt))
	if s.has("p"):
		var p: Array = s["p"]
		paint_color = Color(p[0], p[1], p[2], p[3])
	wet = float(s.get("w", wet))
	taped = bool(s.get("t", taped))
	boarded = bool(s.get("b", boarded))
	locked = bool(s.get("lk", locked))
	lit = bool(s.get("l", lit))
	burnt = bool(s.get("bu", burnt))
	liquid_left = float(s.get("lq", liquid_left))
	is_open = bool(s.get("o", is_open))
	open_drawers = int(s.get("od", open_drawers))
	torn = bool(s.get("tr", torn))
	glued = bool(s.get("g", glued))
	lot_id = str(s.get("lot", lot_id))
	if integrity == Types.Integrity.SHARDS and was_integrity != Types.Integrity.SHARDS:
		_become_pile()
	_apply_open_visual(false)
	_refresh_material()
	_refresh_tape_visual()
	state_changed.emit(self)


func _push_state() -> void:
	_refresh_material()
	state_changed.emit(self)
	if not proxy:
		Net.sync_item_state(self)


func parent_net_id() -> int:
	return nested_in.net_id if nested_in else 0


func apply_snapshot(pos: Vector3, q: Quaternion, vel: Vector3) -> void:
	_target_pos = pos
	_target_quat = q
	_target_vel = vel
	if not _has_target:
		global_position = pos
		global_basis = Basis(q)
		_has_target = true
		return
	# §14: большая ошибка → телепорт + хлюп
	if global_position.distance_to(pos) > Net.TELEPORT_ERROR:
		global_position = pos
		global_basis = Basis(q)
		AudioBus.play_at("squelch", pos, -4.0, 0.3)


func _process(delta: float) -> void:
	if proxy and _has_target and nested_in == null:
		_target_pos += _target_vel * delta
		global_position = global_position.lerp(_target_pos, minf(1.0, delta * 12.0))
		global_basis = Basis(global_basis.get_rotation_quaternion().slerp(_target_quat, minf(1.0, delta * 12.0)))
	if _fire_fx:
		_fire_fx.visible = lit


# ------------------------------------------------------------------ физика (хост)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if proxy or freeze:
		return
	var v := state.linear_velocity
	var pre := _prev_vel
	var dv := (v - pre).length()
	_prev_vel = v
	var touching := state.get_contact_count() > 0
	# первый контакт после полёта: удар = вся скорость подлёта (вращающаяся ваза иначе «размазывает» dv
	# по нескольким тикам и падает с 1.5 м целой). Держимую вещь не трогаем — ей скорость задают руки.
	if touching and not _touching and held_by.is_empty() and pre.length() > 2.5:
		dv = maxf(dv, pre.length() * 0.9)
	_touching = touching
	if touching and dv > 1.5:
		_on_impact(dv, state.get_contact_local_position(0))


func _on_impact(dv: float, at: Vector3) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var threshold := def.break_threshold
	if taped:
		threshold *= 1.6
	if boarded:
		threshold *= 2.2
	var will_shatter := integrity != Types.Integrity.SHARDS and def.is_fragile() and dv >= threshold
	if now - _last_impact_sound > 0.12:
		_last_impact_sound = now
		var snd := "thud"
		if def.is_fragile():
			snd = "clink"
		elif def.has_facet(Types.Facet.HEAVY_CHEAP) or def.has_facet(Types.Facet.HEAVY_EXPENSIVE):
			snd = "thud_heavy"
		elif arch.cloth:
			snd = "flop"
		AudioBus.play_at(snd, global_position, clampf(-14.0 + dv * 2.0, -14.0, 4.0), 0.2)
		if not will_shatter:
			var n := clampi(8 + int(dv * 0.4), 8, 12)
			_PuffFx.burst(self, to_global(at), dv, _PuffFx.DUST, n)
	# замах оружием: попал по вещи — ломает сильнее, попал по челу — больно (§9 потасовка)
	var swing_ms: int = get_meta("swinging", 0)
	var swinging := swing_ms > 0 and Time.get_ticks_msec() - swing_ms < 700
	if swinging and dv > 3.0:
		set_meta("swinging", 0)
		for other in get_colliding_bodies():
			if other is ItemBody and other != self:
				other._on_impact(dv * 2.2, at)
			elif other is Player:
				other.take_damage(12.0 + dv * 2.0, "melee")
				other.velocity += (other.global_position - global_position).normalized() * 4.0
				AudioBus.play_at("oof", other.global_position, 0.0)
			elif other is Npc:
				other.shove((other.global_position - global_position).normalized() * 7.0 + Vector3.UP * 2.0)
	if integrity == Types.Integrity.SHARDS:
		return
	if def.is_fragile():
		if dv >= threshold:
			shatter()
		elif dv >= threshold * 0.55 and integrity == Types.Integrity.WHOLE:
			integrity = Types.Integrity.CHIPPED
			AudioBus.play_at("crack", global_position, -2.0)
			_push_state()
	elif dv >= threshold * 2.0 and integrity == Types.Integrity.WHOLE and not def.has_facet(Types.Facet.LIQUID):
		# нехрупкое тоже мнётся при сильном ударе
		integrity = Types.Integrity.CHIPPED
		_push_state()
	# жидкость выплёскивается при ударе если бутылка открыта/сколота
	if def.liquid_id != Types.LiquidId.NONE and liquid_left > 0.0 and dv >= threshold * 0.5:
		spill(0.15)
	# живое пугается
	if def.has_facet(Types.Facet.ALIVE) and dv > 3.0:
		AudioBus.play_at("squeak", global_position, 0.0, 0.4)


func shatter() -> void:
	if proxy or integrity == Types.Integrity.SHARDS:
		return
	integrity = Types.Integrity.SHARDS
	AudioBus.play_at("shatter", global_position, 2.0, 0.15)
	var puff_c: Color = _base_colors[0] if not _base_colors.is_empty() else Color(0.7, 0.65, 0.55)
	puff_c.a = 0.65
	_PuffFx.burst(self, global_position, 10.0, puff_c, 16)
	Game.stat_add("items_broken")
	if def.tags.has("vase"):
		Achievements.unlock("vase_one_dollar")
	Achievements.count("items_broken", "butterfingers", 25)
	# содержимое вылетает
	var spawn_pos := global_position
	for n in nested.duplicate():
		unnest_child(n)
		n.apply_central_impulse(Vector3(randf_range(-1, 1), 2.0, randf_range(-1, 1)) * n.mass)
	# жидкость разливается целиком
	if def.liquid_id != Types.LiquidId.NONE and liquid_left > 0.0:
		spill(liquid_left)
	_spawn_loose_shards(spawn_pos)
	_become_pile()
	broke.emit(self)
	Net.broadcast_event("break", {"nid": net_id, "pos": spawn_pos})
	_push_state()


func _spawn_loose_shards(at: Vector3) -> void:
	var root := Net._items_root()
	if root == null:
		return
	var count := arch.shard_count
	for i in count:
		var sh := Shard.make(arch, def, i, count)
		root.add_child(sh)
		sh.global_position = at + Vector3(randf_range(-0.1, 0.1), 0.05 + 0.05 * i, randf_range(-0.1, 0.1))
		sh.linear_velocity = Vector3(randf_range(-2, 2), randf_range(1, 3), randf_range(-2, 2))
		sh.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
		Shard.register(sh)


## Само тело становится кучкой осколков — можно продать за $1 (§7.2).
func _become_pile() -> void:
	if _pile_mode:
		return
	_pile_mode = true
	if mesh_root:
		mesh_root.queue_free()
	for c in get_children():
		if c is CollisionShape3D:
			c.queue_free()
	var built := ArchetypeMeshes.build_pile(arch, def)
	mesh_root = built["root"]
	mesh_root.name = "Mesh"
	add_child(mesh_root)
	for s in built["shapes"]:
		var cs := CollisionShape3D.new()
		cs.shape = s["shape"]
		cs.transform = s["xform"]
		add_child(cs)
	_materials.clear()
	_base_colors.clear()
	_collect_materials(mesh_root)
	mass = maxf(0.2, mass * 0.5)
	_drawers.clear()
	_lid = null
	_walls.clear()


# ------------------------------------------------------------------ вложенность (§7.2: оптимум 2, потолок 3)

func nest_depth() -> int:
	var d := 0
	var p := nested_in
	while p:
		d += 1
		p = p.nested_in
	return d


func can_nest(child: ItemBody) -> bool:
	if not (arch.container or def.is_container()):
		return false
	if nest_depth() >= 2:
		return false
	if nested.size() >= arch.container_capacity:
		return false
	if child == self or child.nested.has(self):
		return false
	var child_size: int = child.arch.size_class
	return child_size < arch.size_class or (child_size == Types.SizeClass.POCKET)


func nest_child(child: ItemBody) -> void:
	if child.nested_in == self:
		return
	if child.nested_in:
		child.nested_in.unnest_child(child)
	for h in child.held_by.duplicate():
		h.host_release_body(child)
	nested.append(child)
	child.nested_in = self
	child.freeze = true
	child.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	child.collision_layer = 0
	child.collision_mask = 0
	child.linear_velocity = Vector3.ZERO
	child.angular_velocity = Vector3.ZERO
	_place_nested(child, nested.size() - 1)
	_refresh_nested_visibility()
	if not proxy:
		Net.sync_item_parent(child, net_id)


func _place_nested(child: ItemBody, index: int) -> void:
	var inner := arch.dims * def.scale * 0.6
	var slots := maxi(1, arch.container_capacity)
	var t := float(index) / float(slots)
	var local_pos := Vector3(
		lerpf(-inner.x * 0.3, inner.x * 0.3, t),
		inner.y * 0.35 + 0.05 * index,
		randf_range(-inner.z * 0.2, inner.z * 0.2))
	child.global_transform = global_transform * Transform3D(Basis(Vector3.UP, randf() * TAU), local_pos)


func unnest_child(child: ItemBody) -> void:
	if not nested.has(child):
		return
	nested.erase(child)
	child.nested_in = null
	child.freeze = child.proxy
	child.collision_layer = Types.L_ITEM
	child.collision_mask = Types.L_WORLD | Types.L_PLAYER | Types.L_ITEM | Types.L_VEHICLE | Types.L_NPC | Types.L_SHARD
	child.visible = true
	child.sleeping = false
	_refresh_nested_visibility()
	if not proxy:
		Net.sync_item_parent(child, 0)


func unnest() -> void:
	if nested_in:
		nested_in.unnest_child(self)


func _refresh_nested_visibility() -> void:
	var show := is_open or open_drawers > 0 or not (arch.container or def.is_container()) or _lid == null and _walls.is_empty() and _drawers.is_empty()
	for n in nested:
		if is_instance_valid(n):
			n.visible = show


## Держат за вещь → снапшоты идут через родителя.
func _physics_process(delta: float) -> void:
	if proxy:
		return
	if nested_in and is_instance_valid(nested_in):
		# следуем за родителем (kinematic)
		var idx := nested_in.nested.find(self)
		if idx >= 0 and (Engine.get_physics_frames() + idx) % 4 == 0:
			pass
		return
	_spill_cooldown -= delta
	if def.liquid_id != Types.LiquidId.NONE and liquid_left > 0.0 and _spill_cooldown <= 0.0:
		_check_spill()
	if def.has_facet(Types.Facet.ALIVE) and alive_awake and integrity == Types.Integrity.WHOLE and held_by.is_empty():
		_alive_tick(delta)
	if def.has_facet(Types.Facet.SHAKE_OUT) and not held_by.is_empty() and not nested.is_empty():
		var w := angular_velocity.length() + linear_velocity.length() * 0.5
		_shake_accum = maxf(0.0, _shake_accum + (w - 4.0) * delta)
		if _shake_accum > 1.2:
			_shake_accum = 0.0
			shake_out()
	# зонт-парашют (прикол): открытый зонт в руках тормозит падение владельца
	if get_meta("parachute", false) and get_meta("open", false) and not held_by.is_empty():
		var p = held_by[0].player
		if p and p.velocity.y < -3.0:
			p.velocity.y = maxf(p.velocity.y, -3.0)
	# открытая сумка/коробка в руках вверх дном → всё вылетает (§6.2 «вытряхнуть = перевернуть меш»)
	if (arch.container or def.is_container()) and is_open and not nested.is_empty() and not held_by.is_empty():
		if global_basis.y.dot(Vector3.UP) < -0.35:
			_shake_accum += delta * 3.0
			if _shake_accum > 0.6:
				_shake_accum = 0.0
				dump_all()
				AudioBus.play_at("flop", global_position, -4.0)
	if wet > 0.0:
		wet = maxf(0.0, wet - delta * 0.02)
		if wet <= 0.0:
			_refresh_material()


func _alive_tick(delta: float) -> void:
	_alive_timer -= delta
	if _alive_timer <= 0.0:
		_alive_timer = randf_range(0.6, 2.5)
		if sleeping:
			sleeping = false
		var dir := Vector3(randf_range(-1, 1), 0.3, randf_range(-1, 1)).normalized()
		apply_central_impulse(dir * mass * randf_range(1.5, 3.0))
		if randf() < 0.3:
			AudioBus.play_at("squeak", global_position, -6.0, 0.4)


# ------------------------------------------------------------------ жидкость (§7.3)

func _check_spill() -> void:
	var up := global_basis.y.normalized()
	var tilt := up.dot(Vector3.UP) # 1 = стоит, -1 = вверх ногами
	var open_neck := is_open or integrity != Types.Integrity.WHOLE
	if not open_neck:
		return
	if tilt < 0.25:
		var rate := 0.12 * (1.0 - clampf(tilt, -1.0, 1.0)) * 0.5
		spill(rate * 0.5)
		_spill_cooldown = 0.25


func spill(amount: float) -> void:
	if proxy or def.liquid_id == Types.LiquidId.NONE or liquid_left <= 0.0:
		return
	var a := minf(amount, liquid_left)
	liquid_left -= a
	var neck := global_transform * Vector3(0, arch.dims.y * def.scale, 0)
	var sys := _world_system("Liquids")
	if sys:
		sys.pour(def.liquid_id, neck, -global_basis.y if global_basis.y.dot(Vector3.UP) < 0 else global_basis.y, a, self)
	if liquid_left <= 0.001:
		liquid_left = 0.0
	_push_state()


func _world_system(name: String) -> Node:
	if Game.world and Game.world.has_method("system"):
		return Game.world.system(name)
	return null


# ------------------------------------------------------------------ огонь (§7.4)

func is_flammable() -> bool:
	if burnt:
		return false
	if def.flammable or arch.cloth or def.has_facet(Types.Facet.DOCUMENT):
		return true
	if Types.liquid_flammable(def.liquid_id) and liquid_left > 0.0:
		return true
	# облитая горючим (масло/бензин/виски) вещь горит
	return wet > 0.3 and get_meta("wet_liquid", Types.LiquidId.NONE) in [Types.LiquidId.OIL, Types.LiquidId.GASOLINE, Types.LiquidId.WHISKEY]


func ignite() -> void:
	if proxy or lit or burnt:
		return
	lit = true
	burn_hp = 1.0 if not (def.liquid_id == Types.LiquidId.GASOLINE) else 0.4
	AudioBus.play_at("ignite", global_position, 0.0, 0.2)
	Net.broadcast_event("ignite", {"nid": net_id})
	_push_state()


func extinguish() -> void:
	if not lit:
		return
	lit = false
	AudioBus.play_at("hiss", global_position, -4.0)
	_push_state()


func burn_tick(dt: float) -> void:
	if not lit:
		return
	burn_hp -= dt * (0.25 if arch.cloth or def.flammable else 0.1)
	if burn_hp <= 0.0:
		lit = false
		burnt = true
		if def.liquid_id != Types.LiquidId.NONE:
			liquid_left = 0.0
		for n in nested.duplicate():
			n.burnt = true
			n._push_state()
		_push_state()


func _update_fire_fx() -> void:
	if lit and _fire_fx == null:
		_fire_fx = FireFx.make(arch.dims * def.scale)
		add_child(_fire_fx)
	elif not lit and _fire_fx:
		_fire_fx.queue_free()
		_fire_fx = null


# ------------------------------------------------------------------ грязь / краска / скотч

func add_dirt(v: float) -> void:
	if not def.has_facet(Types.Facet.DIRTYABLE) and v > 0.0:
		return
	dirt = clampf(dirt + v, 0.0, 1.0)
	_push_state()


## Скребок тряпкой: убирает грязь, при переусердствовании — дырка (§13).
func scrub(amount: float, wet_rag: bool) -> void:
	if proxy:
		return
	var eff := amount * (1.0 if wet_rag else 0.35)
	if dirt > 0.0:
		dirt = maxf(0.0, dirt - eff)
		if dirt == 0.0:
			Game.stat_add("items_cleaned")
	elif paint_color.a > 0.0 and wet_rag:
		paint_color.a = maxf(0.0, paint_color.a - eff * 0.7)
	else:
		# уже чисто — рвём
		if def.has_facet(Types.Facet.DOCUMENT) or def.tags.has("painting") or arch.cloth:
			_shake_accum += eff * 2.0
			if _shake_accum > 1.0 and not torn:
				torn = true
				integrity = Types.Integrity.CHIPPED
				AudioBus.play_at("rip", global_position, 0.0)
				Achievements.unlock("overcleaned")
	if wet_rag:
		wet = clampf(wet + amount * 0.5, 0.0, 1.0)
	_push_state()


func paint(c: Color, strength: float) -> void:
	if proxy:
		return
	if paint_color.a <= 0.01:
		paint_color = Color(c.r, c.g, c.b, 0.0)
	else:
		paint_color = paint_color.lerp(Color(c.r, c.g, c.b, paint_color.a), 0.5)
	paint_color.a = clampf(paint_color.a + strength, 0.0, 1.0)
	_push_state()


func soak(amount: float, liquid: int) -> void:
	if proxy:
		return
	wet = clampf(wet + amount, 0.0, 1.0)
	set_meta("wet_liquid", liquid)
	if liquid == Types.LiquidId.PAINT:
		paint(Types.liquid_color(liquid), amount)
	elif liquid == Types.LiquidId.GLUE:
		glued = true
	if def.has_facet(Types.Facet.DOCUMENT) and amount > 0.3:
		integrity = maxi(integrity, Types.Integrity.CHIPPED)
	_push_state()


func apply_patch(patch_def: ItemDef) -> bool:
	if proxy:
		return false
	if patch_def.tags.has("tape") and not taped:
		taped = true
		AudioBus.play_at("tape", global_position, 0.0)
		Game.stat_add("taped")
		Achievements.count("taped", "duct_tape_doctor", 15)
		_refresh_tape_visual()
		_push_state()
		return true
	if patch_def.tags.has("plank") and not boarded and arch.size_class >= Types.SizeClass.TWO_HAND:
		boarded = true
		AudioBus.play_at("hammer_nail", global_position, 0.0)
		_refresh_tape_visual()
		_push_state()
		return true
	return false


func _refresh_tape_visual() -> void:
	if mesh_root == null:
		return
	var t := mesh_root.get_node_or_null("TapeOverlay")
	if taped and t == null:
		var mi := MeshInstance3D.new()
		mi.name = "TapeOverlay"
		var bm := BoxMesh.new()
		bm.size = Vector3(arch.dims.x * 1.06, arch.dims.y * 0.18, arch.dims.z * 1.06)
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.55, 0.55, 0.58)
		mi.material_override = m
		mi.position = Vector3(0, arch.dims.y * 0.5, 0)
		mesh_root.add_child(mi)
	elif not taped and t:
		t.queue_free()
	var bo := mesh_root.get_node_or_null("BoardOverlay")
	if boarded and bo == null:
		var mi := MeshInstance3D.new()
		mi.name = "BoardOverlay"
		var bm := BoxMesh.new()
		bm.size = Vector3(arch.dims.x * 1.1, 0.03, 0.12)
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.6, 0.45, 0.25)
		mi.material_override = m
		mi.position = Vector3(0, arch.dims.y * 0.6, arch.dims.z * 0.52)
		mi.rotation.z = 0.3
		mesh_root.add_child(mi)
	elif not boarded and bo:
		bo.queue_free()


# ------------------------------------------------------------------ контейнеры / ящики / открытие

func toggle_open(by: Node = null) -> void:
	if proxy:
		return
	if locked:
		AudioBus.play_at("locked_rattle", global_position, 0.0)
		if by and by.has_method("say"):
			by.say(tr("ITEM_LOCKED"))
		return
	is_open = not is_open
	_apply_open_visual(true)
	AudioBus.play_at("zip_open" if arch.cloth else "lid_open", global_position, -3.0)
	if is_open and not nested.is_empty():
		Game.stat_add("containers_opened")
	if not is_open and arch.cloth and not nested.is_empty():
		# закрыл сумку: то, что не влезло — вылетает (§6.2)
		while nested.size() > arch.container_capacity:
			var n: ItemBody = nested.back()
			unnest_child(n)
			n.apply_central_impulse(Vector3(randf_range(-1, 1), 2.5, randf_range(-1, 1)) * n.mass)
	opened.emit(self, is_open)
	_refresh_nested_visibility()
	_push_state()


func toggle_drawer() -> void:
	if proxy or _drawers.is_empty():
		return
	if locked:
		AudioBus.play_at("locked_rattle", global_position, 0.0)
		return
	open_drawers = (open_drawers + 1) % (_drawers.size() + 1)
	_apply_open_visual(true)
	AudioBus.play_at("drawer", global_position, -2.0)
	_refresh_nested_visibility()
	_push_state()


func _apply_open_visual(animate: bool) -> void:
	var dur := 0.25 if animate else 0.0
	if _lid:
		var target_rot := -1.9 if is_open else 0.0
		if dur > 0.0:
			var tw := create_tween()
			tw.tween_property(_lid, "rotation:x", target_rot, dur)
		else:
			_lid.rotation.x = target_rot
	for i in _walls.size():
		var w := _walls[i]
		var open_rot := 1.2 if is_open else 0.0
		var axis := "rotation:z" if i % 2 == 0 else "rotation:x"
		var sign := 1.0 if i < 2 else -1.0
		if dur > 0.0:
			var tw := create_tween()
			tw.tween_property(w, axis, open_rot * sign, dur)
		else:
			w.set_indexed(axis, open_rot * sign)
	for i in _drawers.size():
		var d := _drawers[i]
		var out := 0.28 if i < open_drawers else 0.0
		var base_z: float = d.get_meta("base_z", d.position.z)
		d.set_meta("base_z", base_z)
		if dur > 0.0:
			var tw := create_tween()
			tw.tween_property(d, "position:z", base_z + out, dur)
		else:
			d.position.z = base_z + out
	# вложенные в ящиках сдвигаем вперёд вместе с ящиком
	for i in nested.size():
		var n := nested[i]
		if is_instance_valid(n) and not _drawers.is_empty():
			var di := i % _drawers.size()
			var out := 0.28 if di < open_drawers else 0.0
			n.global_transform = global_transform * Transform3D(Basis(), _drawers[di].position + Vector3(0, 0.12, out) + Vector3(-0.15 + 0.15 * (i / _drawers.size()), 0, 0))


func shake_out() -> void:
	if proxy or nested.is_empty():
		return
	var n: ItemBody = nested.back()
	unnest_child(n)
	n.global_position = global_position + Vector3(0, 0.05, 0)
	n.apply_central_impulse((Vector3.DOWN + Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5))) * n.mass * 1.5)
	AudioBus.play_at("flop", global_position, -6.0)
	Game.stat_add("shaken_out")
	Achievements.count("shaken_out", "bookworm", 10)


## Вытряхнуть сумку/чемодан: перевернул меш → всё летит (§6.2).
func dump_all() -> void:
	if proxy:
		return
	for n in nested.duplicate():
		unnest_child(n)
		n.global_position = global_position + Vector3(randf_range(-0.2, 0.2), 0.05, randf_range(-0.2, 0.2))
		n.apply_central_impulse(Vector3(randf_range(-1, 1), -0.5, randf_range(-1, 1)) * n.mass)


func unlock_by(tool_def: ItemDef, chance: float) -> bool:
	if proxy or not locked:
		return false
	if randf() < chance:
		locked = false
		AudioBus.play_at("unlock", global_position, 0.0)
		Game.stat_add("unlocked")
		_push_state()
		return true
	AudioBus.play_at("locked_rattle", global_position, 0.0)
	return false


# ------------------------------------------------------------------ использование (E) — прикол на каждую вещь (§2.1)

## Хост вызывает по запросу игрока. mode 0 = E на вещь в руке / перед носом.
func host_use(player: Node, mode: int) -> void:
	if proxy:
		return
	# что в другой руке? скотч/доска → патч
	var other: ItemBody = player.hands.other_held(self) if player.hands else null
	if other and other.def.has_facet(Types.Facet.PATCHABLE) == false and (other.def.tags.has("tape") or other.def.tags.has("plank")):
		if apply_patch(other.def):
			other.consume_use(player)
		return
	if other and other.def.tags.has("lockpick") and locked:
		if unlock_by(other.def, 0.35 + Game.haggle_skill() * 0.2):
			Achievements.unlock("picked_lock")
		elif randf() < 0.2:
			other.consume_use(player)
			player.say(tr("ITEM_LOCKPICK_BROKE"))
		return
	if other and other.def.tags.has("rag") and def.has_facet(Types.Facet.DIRTYABLE):
		scrub(0.25, other.wet > 0.2)
		return
	# прикол карточки — раньше дефолтов (§2.1)
	if ItemGags.use(self, player, other):
		return
	if def.tags.has("rag"):
		# тряпка: E — окунуть/выжать
		wet = 0.0 if wet > 0.5 else 1.0
		_push_state()
		return
	if def.tags.has("flashlight"):
		lit = not lit
		_toggle_flashlight()
		_push_state()
		return
	if def.tags.has("lighter") or def.tags.has("matches"):
		var target: ItemBody = other if other else null
		if target and target.is_flammable():
			target.ignite()
			Game.stat_add("fires_started")
		else:
			# поджечь то, на что смотрит
			var look = player.look_target()
			if look is ItemBody and look.is_flammable():
				look.ignite()
				Game.stat_add("fires_started")
			elif look and look.has_method("ignite"):
				look.ignite()
		return
	if def.tags.has("gag_gun") and def.has_facet(Types.Facet.WEAPON):
		_fire_gag_gun(player)
		return
	if def.liquid_id == Types.LiquidId.WHISKEY and liquid_left > 0.0:
		if not is_open:
			is_open = true
		liquid_left = maxf(0.0, liquid_left - 0.2)
		player.drink(0.25)
		AudioBus.play_at("gulp", global_position, 0.0)
		_push_state()
		return
	if def.has_facet(Types.Facet.WEARABLE):
		player.wear(self)
		return
	if not _drawers.is_empty():
		toggle_drawer()
		return
	if def.liquid_id != Types.LiquidId.NONE and integrity == Types.Integrity.WHOLE:
		is_open = not is_open
		AudioBus.play_at("cork", global_position, -2.0)
		_push_state()
		return
	if def.is_container() or arch.container:
		if def.has_facet(Types.Facet.SHAKE_OUT):
			shake_out()
		else:
			toggle_open(player)
		return
	if def.has_facet(Types.Facet.DOCUMENT):
		player.read_document(self)
		return
	if def.has_facet(Types.Facet.ALIVE):
		AudioBus.play_at("squeak", global_position, 0.0, 0.5)
		player.say(tr("ITEM_PET"))
		return
	if def.is_cash():
		# купюра в руке: E — в котёл
		Economy.deposit_bill(self)
		return
	# дефолт: ткнуть/постучать
	AudioBus.play_at("tap", global_position, -6.0)


func consume_use(player: Node) -> void:
	# расходник: скотч/доска/отмычка — счётчик использований на карточке нет, делаем 1 вещь = 3 применения
	var uses: int = get_meta("uses", 3) - 1
	set_meta("uses", uses)
	if uses <= 0:
		for h in held_by.duplicate():
			h.host_release_body(self)
		Net.despawn_item(net_id)


func _toggle_flashlight() -> void:
	var l := mesh_root.get_node_or_null("Beam") as SpotLight3D
	if l == null:
		l = SpotLight3D.new()
		l.name = "Beam"
		l.spot_range = 18.0
		l.spot_angle = 30.0
		l.light_energy = 3.0
		l.light_color = Color(1.0, 0.95, 0.8)
		l.position = Vector3(0, arch.dims.y * 0.5, -arch.dims.z * 0.5)
		l.rotation.y = PI
		l.shadow_enabled = false
		mesh_root.add_child(l)
	l.visible = lit


func _fire_gag_gun(player: Node) -> void:
	AudioBus.play_at("gag_bang", global_position, 4.0, 0.1)
	var flag := mesh_root.get_node_or_null("BangFlag")
	if flag == null:
		flag = MeshInstance3D.new()
		flag.name = "BangFlag"
		var bm := BoxMesh.new()
		bm.size = Vector3(0.25, 0.15, 0.01)
		flag.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1, 0.2, 0.2)
		flag.material_override = m
		flag.position = Vector3(0, 0.12, -0.3)
		mesh_root.add_child(flag)
	flag.visible = true
	Game.stat_add("gag_shots")
	Achievements.unlock("bang_flag")
	# 1 из 12 — гаг-пистолет всё-таки стреляет: кореш → ragdoll (§1: пуля кореша)
	var look = player.look_target()
	if randf() < 0.085 and look and look.has_method("die"):
		look.die("gag_gun")
		Achievements.unlock("friendly_fire")
	elif look is ItemBody:
		look.apply_central_impulse(-look.global_position.direction_to(player.head_position()) * -4.0 * look.mass)


# ------------------------------------------------------------------ цена (§7.2)

## Цена = f(value_base, integrity, dirt, vendor, tape). Осколок может стоить $1. Помыл и порвал — хуже грязной.
func current_value(vendor: VendorDef = null) -> int:
	if def.is_cash():
		return def.cash_value()
	var v := float(def.value_base)
	match integrity:
		Types.Integrity.CHIPPED: v *= 0.45
		Types.Integrity.SHARDS: return PILE_VALUE if not def.tags.has("gem") else maxi(PILE_VALUE, int(def.value_base * 0.1))
	if burnt:
		v *= 0.05
	if torn:
		v *= 0.3
	v *= 1.0 - clampf(dirt, 0.0, 1.0) * 0.5
	if paint_color.a > 0.05:
		v *= 1.0 - paint_color.a * 0.6
	if wet > 0.3 and def.has_facet(Types.Facet.DOCUMENT):
		v *= 0.5
	if taped:
		v *= 0.8 if integrity == Types.Integrity.WHOLE else 1.3
	if boarded:
		v *= 0.9 if integrity == Types.Integrity.WHOLE else 1.25
	if glued:
		v *= 0.85
	if def.liquid_id != Types.LiquidId.NONE:
		v *= 0.25 + 0.75 * liquid_left
	if locked and def.has_facet(Types.Facet.LOCKED):
		v *= 0.7 # никто не знает, что внутри — скупщик не доплатит
	if vendor:
		v *= vendor.base_multiplier
		for f in def.facets:
			if vendor.favorite_facets.has(f):
				v *= 1.35
			if vendor.hated_facets.has(f):
				v *= 0.6
		if def.vendor_affinity.has(vendor.id):
			v *= 1.4
	return maxi(1, int(round(v)))


# ------------------------------------------------------------------ хват

func on_grabbed(hands: Node) -> void:
	if not held_by.has(hands):
		held_by.append(hands)
	sleeping = false
	picked.emit(self, hands)


func on_released(hands: Node) -> void:
	held_by.erase(hands)
	dropped.emit(self)


func is_held() -> bool:
	return not held_by.is_empty()


func needs_two_players() -> bool:
	return arch.size_class == Types.SizeClass.TEAM


func _on_body_entered(other: Node) -> void:
	# краска на людях/вещах при контакте с мокрой окрашенной вещью
	if paint_color.a > 0.3 and wet > 0.3 and other is ItemBody and not proxy:
		other.paint(paint_color, 0.15)
	if lit and other is ItemBody and other.is_flammable() and not proxy:
		other.ignite()


func describe() -> String:
	var s := def.display_name()
	match integrity:
		Types.Integrity.CHIPPED: s += " (%s)" % tr("STATE_CHIPPED")
		Types.Integrity.SHARDS: s += " (%s)" % tr("STATE_SHARDS")
	if burnt:
		s += " (%s)" % tr("STATE_BURNT")
	if locked:
		s += " 🔒"
	return s
