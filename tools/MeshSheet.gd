extends Node3D
## Контактный лист архетипов: godot --path . --resolution 1800x1200 res://tools/MeshSheet.tscn
## Каждый меш строится напрямую через ArchetypeMeshes.build (без ItemBody, физики и города),
## масштабируется под свою ячейку и подписывается — модели видно рядом и можно сравнивать.
## Кадры → user://shots/meshsheet/*.png

const COLS := 6
const ROWS := 4
const CELL := 1.15
const CELL_Z := 1.75 ## ряды раздвинуты глубже: под углом задний ряд иначе лезет на передний
const FIT := 0.72 ## какую долю ячейки занимает самый большой габарит модели

var _dir := ""
var _cam: Camera3D
var _page := 0


func _ready() -> void:
	_dir = OS.get_user_data_dir().path_join("shots").path_join("meshsheet")
	DirAccess.make_dir_recursive_absolute(_dir)
	_setup_stage()
	call_deferred("_run")


func _setup_stage() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.17, 0.2)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.64, 0.7)
	e.ambient_light_energy = 0.75
	env.environment = e
	add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, -38, 0)
	key.light_energy = 1.5
	key.shadow_enabled = true
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, 132, 0)
	fill.light_energy = 0.5
	add_child(fill)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 5.7
	_cam.rotation_degrees = Vector3(-38, 16, 0)
	_cam.current = true
	add_child(_cam)


func _pairs() -> Array:
	var per_arch: Dictionary = {}
	for raw in Registry.all_items():
		var d: ItemDef = raw
		if d == null or per_arch.has(d.archetype_id):
			continue
		var a: Archetype = Registry.archetype_for(d)
		if a == null:
			continue
		per_arch[d.archetype_id] = {"arch": a, "def": d}
	var list: Array = per_arch.values()
	list.sort_custom(func(x, y): return str(x["arch"].id) < str(y["arch"].id))
	return list


func _run() -> void:
	var list := _pairs()
	var per := COLS * ROWS
	var pages := int(ceil(float(list.size()) / float(per)))
	print("[meshsheet] archetypes=%d pages=%d" % [list.size(), pages])
	for pi in pages:
		var holder := Node3D.new()
		add_child(holder)
		var chunk: Array = list.slice(pi * per, mini((pi + 1) * per, list.size()))
		for i in chunk.size():
			_place(holder, chunk[i], i)
		var cx := (COLS - 1) * CELL * 0.5
		var cz := (ROWS - 1) * CELL_Z * 0.5
		_cam.position = Vector3(cx, 0.0, cz) + Vector3(2.6, 6.0, 8.0)
		_cam.look_at(Vector3(cx, 0.0, cz), Vector3.UP)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(_dir.path_join("mesh_%02d.png" % pi))
		print("[meshsheet] page %02d: %s" % [pi, ", ".join(chunk.map(func(e): return str(e["arch"].id)))])
		holder.queue_free()
		await get_tree().process_frame
	print("[meshsheet] done → %s" % _dir)
	get_tree().quit()


func _place(holder: Node3D, entry: Dictionary, i: int) -> void:
	var arch: Archetype = entry["arch"]
	var def: ItemDef = entry["def"]
	# как в ItemBody: готовая сцена (модель из Blender) важнее процедурного билдера
	var root: Node3D
	if arch.scene:
		root = arch.scene.instantiate() as Node3D
		_tint(root, arch.base_color if def.color == Color.WHITE else def.color)
	else:
		root = ArchetypeMeshes.build(arch, def)["root"]
	var cell := Node3D.new()
	cell.position = Vector3(float(i % COLS) * CELL, 0.0, float(i / COLS) * CELL_Z)
	holder.add_child(cell)
	cell.add_child(root)
	# нормируем по реальному AABB собранного меша: dims в архетипе билдеры соблюдают не всегда
	var box := _local_aabb(root)
	var big := maxf(box.size.x, maxf(box.size.y, box.size.z))
	var k := (CELL * FIT) / maxf(big, 0.01)
	root.scale = Vector3(k, k, k)
	root.position = -box.get_center() * k
	var tag := Label3D.new()
	tag.text = arch.id
	tag.font_size = 44
	tag.pixel_size = 0.0018
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = Color(0.98, 0.93, 0.62)
	tag.outline_size = 14
	tag.position = Vector3(0, -CELL * 0.44, CELL_Z * 0.4)
	cell.add_child(tag)


## Тот же договор, что в ItemBody: материал "tint" — место под цвет карточки.
func _tint(root: Node3D, c: Color) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i)
			if m is StandardMaterial3D and str(m.resource_name).begins_with("tint"):
				var dup := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
				dup.albedo_color = c
				mi.set_surface_override_material(i, dup)


## AABB всех мешей узла в его собственных координатах.
func _local_aabb(root: Node3D) -> AABB:
	var inv := root.global_transform.affine_inverse()
	var out := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var a: AABB = (inv * mi.global_transform) * mi.mesh.get_aabb()
		if first:
			out = a
			first = false
		else:
			out = out.merge(a)
	if first:
		out = AABB(Vector3(-0.1, -0.1, -0.1), Vector3(0.2, 0.2, 0.2))
	return out
