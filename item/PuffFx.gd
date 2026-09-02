extends GPUParticles3D
## Одноразовый пылевой плюх при ударе/разбитии. Общие материалы, не больше 6 живых.

const MAX_ALIVE := 6
const DUST := Color(0.72, 0.6, 0.45, 0.5)

const _Self := preload("res://item/PuffFx.gd")

static var _alive: int = 0
static var _pm_dust: ParticleProcessMaterial
static var _pm_shard: ParticleProcessMaterial
static var _quad: QuadMesh


static func _make_pm(from_c: Color) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 80.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3(0, -1.4, 0)
	pm.scale_min = 0.10
	pm.scale_max = 0.26
	var grad := Gradient.new()
	grad.set_color(0, from_c)
	grad.set_color(1, Color(from_c.r, from_c.g, from_c.b, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	return pm


static func _ensure() -> void:
	if _pm_dust != null:
		return
	_pm_dust = _make_pm(DUST)
	_pm_shard = _make_pm(Color(1, 1, 1, 0.65))
	_quad = QuadMesh.new()
	_quad.size = Vector2(0.16, 0.16)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_quad.material = mat


static func burst(host: Node, at: Vector3, strength: float, tint: Color, count: int) -> void:
	if host == null or not host.is_inside_tree() or _alive >= MAX_ALIVE:
		return
	_ensure()
	var tree: SceneTree = host.get_tree()
	if tree == null:
		return
	var parent: Node = tree.current_scene
	if parent == null:
		parent = host
	var p: GPUParticles3D = _Self.new() as GPUParticles3D
	p.amount = clampi(count, 8, 16)
	p.lifetime = 0.6
	p.one_shot = true
	p.explosiveness = 0.9
	p.speed_scale = clampf(0.55 + strength * 0.10, 0.55, 2.2)
	if count >= 16:
		_pm_shard.color = tint
		p.process_material = _pm_shard
	else:
		p.process_material = _pm_dust
	p.draw_pass_1 = _quad
	p.emitting = false
	parent.add_child(p)
	p.global_position = at + Vector3(0, 0.04, 0)
	_alive += 1
	p.restart()
	p.emitting = true
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = 1.0
	t.timeout.connect(p.queue_free)
	p.add_child(t)
	t.start()


func _exit_tree() -> void:
	_alive = maxi(_alive - 1, 0)
