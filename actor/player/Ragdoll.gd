class_name Ragdoll
extends RigidBody3D
## Мультяшный ragdoll (§6.4): торс-капсула + голова на пине + четыре палки. Косметика, не сеть.

var _parts: Array[RigidBody3D] = []


static func make(color: Color) -> Ragdoll:
	var r := Ragdoll.new()
	r.name = "Ragdoll"
	r.mass = 40.0
	r.collision_layer = Types.L_RAGDOLL
	r.collision_mask = Types.L_WORLD | Types.L_ITEM | Types.L_VEHICLE
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	mat.metallic = 0.0
	var torso := MeshInstance3D.new()
	torso.mesh = LowPoly.capsule(0.30, 0.72, 8, 3)
	torso.material_override = mat
	r.add_child(torso)
	var cs := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.30
	shape.height = 0.72
	cs.shape = shape
	r.add_child(cs)
	r.set_meta("mat", mat)
	return r


func _ready() -> void:
	var mat: StandardMaterial3D = get_meta("mat") as StandardMaterial3D
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.96, 0.68, 0.46)
	skin.roughness = 0.88
	skin.metallic = 0.0
	_add_part(Vector3(0, 0.58, 0), 0.28, 0.56, skin, 5.0, true)
	for x in [-0.32, 0.32]:
		_add_part(Vector3(x, 0.12, 0), 0.09, 0.42, mat, 3.0, false)
		_add_part(Vector3(x * 0.45, -0.58, 0), 0.11, 0.50, mat, 6.0, false)
	angular_damp = 1.0
	linear_damp = 0.3


func _add_part(offset: Vector3, radius: float, height: float, mat: Material, p_mass: float, as_head := false) -> void:
	var p := RigidBody3D.new()
	p.mass = p_mass
	p.collision_layer = Types.L_RAGDOLL
	p.collision_mask = Types.L_WORLD | Types.L_ITEM
	var mi := MeshInstance3D.new()
	if as_head:
		mi.mesh = LowPoly.sphere(radius, 8, 4)
	else:
		mi.mesh = LowPoly.capsule(radius, height, 8, 3)
	mi.material_override = mat
	p.add_child(mi)
	var cs := CollisionShape3D.new()
	if as_head:
		var sph := SphereShape3D.new()
		sph.radius = radius
		cs.shape = sph
	else:
		var s := CapsuleShape3D.new()
		s.radius = radius
		s.height = height
		cs.shape = s
	p.add_child(cs)
	get_parent().add_child.call_deferred(p)
	p.set_deferred("global_position", global_position + offset)
	var j := PinJoint3D.new()
	j.node_a = get_path()
	j.node_b = NodePath("")
	add_child(j)
	j.position = offset * 0.6
	_parts.append(p)
	p.tree_entered.connect(func(): j.node_b = p.get_path(), CONNECT_ONE_SHOT)


func kick(impulse: Vector3) -> void:
	apply_central_impulse(impulse * mass)
	apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * mass * 2.0)


func _exit_tree() -> void:
	for p in _parts:
		if is_instance_valid(p):
			p.queue_free()
