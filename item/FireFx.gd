class_name FireFx
extends Node3D
## Дешёвый огонь: частицы + мерцающая лампа. Для слабого ПК — мало частиц.

var _light: OmniLight3D
var _t := 0.0


static func make(dims: Vector3) -> FireFx:
	var f := FireFx.new()
	f.name = "FireFx"
	var p := GPUParticles3D.new()
	p.amount = 24
	p.lifetime = 0.7
	p.explosiveness = 0.0
	p.randomness = 0.6
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.8
	pm.gravity = Vector3(0, 1.5, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(maxf(0.05, dims.x * 0.4), 0.05, maxf(0.05, dims.z * 0.4))
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.2, 1.0))
	grad.set_color(1, Color(0.6, 0.05, 0.0, 0.0))
	grad.add_point(0.4, Color(1.0, 0.4, 0.05, 0.9))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.18, 0.28)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qm.material = mat
	p.draw_pass_1 = qm
	p.position.y = dims.y * 0.6
	f.add_child(p)
	var smoke := GPUParticles3D.new()
	smoke.amount = 8
	smoke.lifetime = 1.6
	var sm := ParticleProcessMaterial.new()
	sm.direction = Vector3(0, 1, 0)
	sm.spread = 15.0
	sm.initial_velocity_min = 0.6
	sm.initial_velocity_max = 1.2
	sm.gravity = Vector3(0, 0.5, 0)
	sm.scale_min = 1.0
	sm.scale_max = 2.0
	var sg := Gradient.new()
	sg.set_color(0, Color(0.2, 0.2, 0.2, 0.5))
	sg.set_color(1, Color(0.1, 0.1, 0.1, 0.0))
	var sgt := GradientTexture1D.new()
	sgt.gradient = sg
	sm.color_ramp = sgt
	smoke.process_material = sm
	var sq := QuadMesh.new()
	sq.size = Vector2(0.3, 0.3)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	smat.vertex_color_use_as_albedo = true
	sq.material = smat
	smoke.draw_pass_1 = sq
	smoke.position.y = dims.y * 1.1
	f.add_child(smoke)
	f._light = OmniLight3D.new()
	f._light.light_color = Color(1.0, 0.5, 0.15)
	f._light.light_energy = 1.6
	f._light.omni_range = 4.0
	f._light.shadow_enabled = false
	f._light.position.y = dims.y * 0.8
	f.add_child(f._light)
	var snd := AudioStreamPlayer3D.new()
	snd.name = "Crackle"
	f.add_child(snd)
	return f


func _ready() -> void:
	var snd := get_node_or_null("Crackle") as AudioStreamPlayer3D
	if snd and AudioBus.has("fire_loop"):
		var s: AudioStream = AudioBus._sfx["fire_loop"]
		if s is AudioStreamWAV:
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		snd.stream = s
		snd.volume_db = -6.0
		snd.max_distance = 20.0
		snd.play()


func _process(delta: float) -> void:
	_t += delta
	if _light:
		_light.light_energy = 1.4 + sin(_t * 17.0) * 0.3 + sin(_t * 7.3) * 0.25
