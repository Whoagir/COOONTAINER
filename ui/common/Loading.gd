class_name LoadingOverlay
extends Control
## Заставка на кадр перед сменой сцены: кейарт, крутящийся хлам, случайная шутка.

const LINE_COUNT := 20

var _junk: Node3D
var _line: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	theme = UiTheme.make()
	_build()
	roll_line()


func roll_line() -> void:
	if _line:
		_line.text = tr("SET_LOAD_%02d" % (randi() % LINE_COUNT + 1))


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)
	if ResourceLoader.exists("res://assets/textures/keyart_menu.png"):
		var art := TextureRect.new()
		art.texture = load("res://assets/textures/keyart_menu.png")
		art.set_anchors_preset(PRESET_FULL_RECT)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.modulate = Color(0.55, 0.5, 0.48)
		add_child(art)
		var shade := ColorRect.new()
		shade.color = Color(0.06, 0.04, 0.07, 0.62)
		shade.set_anchors_preset(PRESET_FULL_RECT)
		add_child(shade)
	var stripe := ColorRect.new()
	stripe.color = UiTheme.ACCENT
	stripe.set_anchors_preset(PRESET_TOP_WIDE)
	stripe.custom_minimum_size = Vector2(0, 12)
	add_child(stripe)
	var title := UiTheme.header("COOONTAINER", 56)
	title.set_anchors_preset(PRESET_CENTER_TOP)
	title.position = Vector2(-360, 48)
	title.custom_minimum_size = Vector2(720, 0)
	add_child(title)
	if DisplayServer.get_name() != "headless":
		_add_junk()
	_line = UiTheme.body("", 26)
	_line.set_anchors_preset(PRESET_CENTER_BOTTOM)
	_line.position = Vector2(-420, -96)
	_line.custom_minimum_size = Vector2(840, 0)
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.add_theme_color_override("font_color", UiTheme.TEXT)
	add_child(_line)
	var sub := UiTheme.body(tr("SET_LOADING"), 18, true)
	sub.set_anchors_preset(PRESET_CENTER_BOTTOM)
	sub.position = Vector2(-200, -48)
	sub.custom_minimum_size = Vector2(400, 0)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sub)


func _add_junk() -> void:
	var host := SubViewportContainer.new()
	host.set_anchors_preset(PRESET_CENTER)
	host.position = Vector2(-90, -70)
	host.custom_minimum_size = Vector2(180, 180)
	host.stretch = true
	add_child(host)
	var vp := SubViewport.new()
	vp.size = Vector2i(180, 180)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	host.add_child(vp)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.15, 1.6)
	cam.current = true
	vp.add_child(cam)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, 35, 0)
	light.light_color = Color(1.0, 0.85, 0.55)
	vp.add_child(light)
	_junk = Node3D.new()
	vp.add_child(_junk)
	_junk.add_child(_box(Vector3(0.42, 0.5, 0.32), Color(0.88, 0.54, 0.14), Vector3.ZERO))
	_junk.add_child(_box(Vector3(0.18, 0.22, 0.18), Color(0.75, 0.72, 0.65), Vector3(0.28, 0.28, 0.1)))
	var cyl := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.08
	cm.bottom_radius = 0.11
	cm.height = 0.28
	cyl.mesh = cm
	cyl.position = Vector3(-0.22, 0.12, 0.08)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.22, 0.18)
	mat.roughness = 0.55
	cyl.material_override = mat
	_junk.add_child(cyl)


func _box(size: Vector3, color: Color, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	mi.material_override = mat
	return mi


func _process(delta: float) -> void:
	if _junk:
		_junk.rotate_y(delta * 1.6)
		_junk.rotate_x(delta * 0.45)
	if _line:
		_line.rotation = sin(Time.get_ticks_msec() * 0.003) * 0.02
