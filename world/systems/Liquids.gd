class_name Liquids
extends Node3D
## Жидкости (§7.3): струя из горла (частицы) + лужа (декаль + slip). Хост решает, клиенты рисуют.
## Типы: виски, краска, масло, бензин, клей (опц.), вода (пожарные).

const MAX_PUDDLES := 60
const PUDDLE_MERGE_DIST := 0.6

var puddles: Array[Puddle] = []
var _next_id := 1


class Puddle:
	extends Area3D
	var liquid: int
	var radius: float = 0.2
	var puddle_id: int
	var burning := false
	var burn_left := 0.0
	var decal: Decal
	var shape: CylinderShape3D
	var fire: Node3D
	var age := 0.0

	func setup(p_liquid: int, r: float) -> void:
		liquid = p_liquid
		radius = r
		collision_layer = Types.L_LIQUID
		collision_mask = Types.L_ITEM | Types.L_PLAYER | Types.L_NPC
		monitoring = true
		monitorable = true
		var cs := CollisionShape3D.new()
		shape = CylinderShape3D.new()
		shape.radius = radius
		shape.height = 0.12
		cs.shape = shape
		cs.position.y = 0.06
		add_child(cs)
		decal = Decal.new()
		decal.texture_albedo = Liquids._puddle_texture()
		decal.modulate = Types.liquid_color(liquid)
		decal.albedo_mix = 1.0
		decal.upper_fade = 0.3
		decal.lower_fade = 0.3
		decal.cull_mask = 0xFFFFF
		add_child(decal)
		_resize()

	func _resize() -> void:
		shape.radius = radius
		decal.size = Vector3(radius * 2.0, 0.4, radius * 2.0)
		decal.position.y = 0.0

	func grow(amount: float) -> void:
		radius = minf(1.6, sqrt(radius * radius + amount * 0.6))
		_resize()

	func ignite() -> void:
		if burning or not Types.liquid_flammable(liquid):
			return
		burning = true
		burn_left = 6.0 + radius * 6.0
		fire = FireFx.make(Vector3(radius * 2.0, 0.1, radius * 2.0))
		add_child(fire)
		AudioBus.play_at("ignite", global_position, 2.0)

	func extinguish() -> void:
		if not burning:
			return
		burning = false
		if fire:
			fire.queue_free()
			fire = null
		AudioBus.play_at("hiss", global_position, 0.0)


static var _tex: Texture2D


static func _puddle_texture() -> Texture2D:
	if _tex:
		return _tex
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var dx := (x - 32) / 32.0
			var dy := (y - 32) / 32.0
			var d := sqrt(dx * dx + dy * dy)
			var wob := 0.85 + 0.15 * sin(atan2(dy, dx) * 5.0) * cos(atan2(dy, dx) * 3.0)
			var a := clampf((wob - d) * 6.0, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_tex = ImageTexture.create_from_image(img)
	return _tex


func system_name() -> String:
	return "Liquids"


## Струя: from — горло, dir — направление потока, amount — доля объёма (0..1).
func pour(liquid: int, from: Vector3, dir: Vector3, amount: float, source: Node = null) -> void:
	_stream_fx(liquid, from, dir)
	if not Net.is_host():
		return
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 4.0 + dir * 0.5, Types.L_WORLD | Types.L_ITEM | Types.L_PLAYER | Types.L_NPC | Types.L_VEHICLE)
	if source is CollisionObject3D:
		q.exclude = [source.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var col = hit["collider"]
	if col is ItemBody:
		col.soak(amount * 2.0, liquid)
		if liquid == Types.LiquidId.WATER and col.lit:
			col.extinguish()
		# сливаем ниже на пол
		var q2 := PhysicsRayQueryParameters3D.create(hit["position"] + Vector3.DOWN * 0.05, hit["position"] + Vector3.DOWN * 4.0, Types.L_WORLD | Types.L_VEHICLE)
		var hit2 := space.intersect_ray(q2)
		if hit2.is_empty():
			return
		add_puddle(liquid, hit2["position"], amount * 0.5)
		return
	if col is Player:
		col.splash(liquid, amount)
		return
	if col is Npc:
		if col.has_method("on_splash"):
			col.on_splash(liquid)
		return
	add_puddle(liquid, hit["position"], amount)


func add_puddle(liquid: int, pos: Vector3, amount: float) -> void:
	if not Net.is_host():
		return
	for p in puddles:
		if p.liquid == liquid and p.global_position.distance_to(pos) < PUDDLE_MERGE_DIST + p.radius * 0.5:
			p.grow(amount)
			Net.broadcast_event("puddle", {"id": p.puddle_id, "liquid": liquid, "pos": p.global_position, "r": p.radius})
			return
	var id := _next_id
	_next_id += 1
	var p := _make_puddle(id, liquid, pos, 0.18 + amount * 0.4)
	Net.broadcast_event("puddle", {"id": id, "liquid": liquid, "pos": pos, "r": p.radius})
	Game.stat_add("puddles")
	Achievements.count("puddles", "slippery", 30)


func _make_puddle(id: int, liquid: int, pos: Vector3, r: float) -> Puddle:
	var p := Puddle.new()
	p.puddle_id = id
	p.setup(liquid, r)
	add_child(p)
	p.global_position = pos + Vector3(0, 0.01, 0)
	p.body_entered.connect(_on_puddle_body.bind(p))
	puddles.append(p)
	AudioBus.play_at("splash", pos, -6.0, 0.2)
	while puddles.size() > MAX_PUDDLES:
		var old: Puddle = puddles.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	return p


func apply_puddle_event(d: Dictionary) -> void:
	# клиент: косметика + локальный slip
	if Net.is_host():
		return
	var id := int(d["id"])
	for p in puddles:
		if p.puddle_id == id:
			p.radius = float(d["r"])
			p._resize()
			return
	_make_puddle(id, int(d["liquid"]), d["pos"], float(d["r"]))


func _on_puddle_body(body: Node, p: Puddle) -> void:
	if body is Player:
		body.on_puddle(p.liquid, Types.liquid_slip(p.liquid))
		if p.burning and Net.is_host():
			body.set_burning(true)
		if p.liquid == Types.LiquidId.PAINT:
			body.splash(Types.LiquidId.PAINT, 0.3)
		return
	if not Net.is_host():
		return
	if body is ItemBody:
		var b: ItemBody = body
		if p.liquid == Types.LiquidId.PAINT:
			b.paint(Types.liquid_color(p.liquid), 0.4)
		elif p.liquid == Types.LiquidId.GLUE:
			b.glued = true
			b.linear_damp = 6.0
		elif p.liquid == Types.LiquidId.WATER:
			b.soak(0.3, p.liquid)
			if b.lit:
				b.extinguish()
		else:
			b.soak(0.2, p.liquid)
		if b.lit and Types.liquid_flammable(p.liquid):
			p.ignite()
		if p.burning and b.is_flammable():
			b.ignite()


func _physics_process(delta: float) -> void:
	for p in puddles.duplicate():
		if not is_instance_valid(p):
			puddles.erase(p)
			continue
		p.age += delta
		# лужа сохнет (вода/виски быстрее, масло/краска почти нет)
		var dry := 0.0
		match p.liquid:
			Types.LiquidId.WATER: dry = 0.02
			Types.LiquidId.WHISKEY: dry = 0.006
			Types.LiquidId.GASOLINE: dry = 0.01
			Types.LiquidId.GLUE: dry = 0.004
		if dry > 0.0 and p.age > 20.0:
			p.radius -= dry * delta
			if p.radius < 0.08:
				puddles.erase(p)
				p.queue_free()
				continue
			p._resize()
		if not Net.is_host():
			continue
		# горение лужи (§7.4): поджигает всё, что в ней, и соседние лужи
		if p.burning:
			p.burn_left -= delta
			for b in p.get_overlapping_bodies():
				if b is ItemBody and b.is_flammable() and not b.lit:
					b.ignite()
				elif b is Player:
					b.set_burning(true)
			for o in puddles:
				if o != p and not o.burning and Types.liquid_flammable(o.liquid) and o.global_position.distance_to(p.global_position) < p.radius + o.radius + 0.2:
					o.ignite()
			if p.burn_left <= 0.0:
				p.extinguish()
				puddles.erase(p)
				p.queue_free()
		else:
			# горящая вещь в горючей луже
			if Types.liquid_flammable(p.liquid):
				for b in p.get_overlapping_bodies():
					if b is ItemBody and b.lit:
						p.ignite()
						break
			# вода тушит
			elif p.liquid == Types.LiquidId.WATER:
				for b in p.get_overlapping_bodies():
					if b is ItemBody and b.lit:
						b.extinguish()
					elif b is Player and b.burning:
						b.set_burning(false)


func puddle_at(pos: Vector3) -> Puddle:
	for p in puddles:
		if p.global_position.distance_to(pos) < p.radius:
			return p
	return null


func ignite_at(pos: Vector3) -> void:
	for p in puddles:
		if Types.liquid_flammable(p.liquid) and p.global_position.distance_to(pos) < p.radius + 0.3:
			p.ignite()


func _stream_fx(liquid: int, from: Vector3, dir: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = 14
	p.lifetime = 0.6
	p.one_shot = true
	p.explosiveness = 0.3
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir.normalized() if dir.length() > 0.01 else Vector3.DOWN
	pm.spread = 8.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 1.8
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.0
	pm.color = Types.liquid_color(liquid)
	p.process_material = pm
	var m := CapsuleMesh.new()
	m.radius = 0.02
	m.height = 0.08
	m.radial_segments = 6
	m.rings = 2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Types.liquid_color(liquid)
	mat.vertex_color_use_as_albedo = true
	m.material = mat
	p.draw_pass_1 = m
	add_child(p)
	p.global_position = from
	p.emitting = true
	AudioBus.play_at("pour", from, -8.0, 0.2)
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)


## Сколько всего луж в радиусе (для фобии скупщика «мокро»).
func wet_around(pos: Vector3, r: float) -> int:
	var n := 0
	for p in puddles:
		if p.global_position.distance_to(pos) < r:
			n += 1
	return n
