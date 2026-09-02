class_name Shard
extends RigidBody3D
## Свободный осколок (§7.5): кап на количество, потом деспавн в «мусор». Не сетевой — клиенты
## спавнят свои по событию break (косметика).

const MAX_SHARDS := 120
const LIFETIME := 25.0

static var _live: Array = []

var _life := LIFETIME


static func make(arch: Archetype, def: ItemDef, index: int, count: int) -> Shard:
	var s := Shard.new()
	s.collision_layer = Types.L_SHARD
	s.collision_mask = Types.L_WORLD | Types.L_ITEM | Types.L_SHARD
	s.mass = maxf(0.05, arch.mass_default / float(count) * 0.5)
	s.can_sleep = true
	var mi := MeshInstance3D.new()
	var d := arch.dims * def.scale
	var sz := Vector3(d.x, d.y, d.z) * randf_range(0.18, 0.36)
	sz.y = maxf(0.01, sz.y * 0.5)
	var mesh: Mesh
	if index % 2 == 0:
		var pm := PrismMesh.new()
		pm.size = sz
		pm.left_to_right = randf()
		mesh = pm
	else:
		var bm := BoxMesh.new()
		bm.size = sz
		mesh = bm
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	var base := arch.base_color if def.color == Color.WHITE else def.color * arch.base_color
	mat.albedo_color = base.lerp(arch.secondary_color, randf() * 0.5)
	mi.material_override = mat
	s.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = sz
	cs.shape = bs
	s.add_child(cs)
	s.name = "Shard"
	return s


static func register(s: Shard) -> void:
	_live.append(s)
	while _live.size() > MAX_SHARDS:
		var old = _live.pop_front()
		if is_instance_valid(old):
			old.queue_free()


func _physics_process(delta: float) -> void:
	_life -= delta
	if _life < 3.0:
		scale = Vector3.ONE * maxf(0.01, _life / 3.0)
	if _life <= 0.0:
		_live.erase(self)
		queue_free()
