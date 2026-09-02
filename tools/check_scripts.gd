extends SceneTree
## Быстрая проверка: компилирует все .gd в проекте и грузит все .tscn/.tres.
## Запуск: godot --headless --path . -s res://tools/check_scripts.gd

var errors := 0


func _init() -> void:
	var files: Array[String] = []
	_walk("res://", files)
	var scripts := 0
	var scenes := 0
	for f in files:
		if f.ends_with(".gd") and not f.begins_with("res://tools/"):
			var s = load(f)
			scripts += 1
			if s == null or not (s as GDScript).can_instantiate() and not _is_static_only(s):
				# can_instantiate false для abstract/ошибочных; печатаем только если reload даёт ошибку
				var err: int = (s as GDScript).reload() if s else ERR_PARSE_ERROR
				if err != OK:
					errors += 1
					printerr("SCRIPT ERROR: %s (%d)" % [f, err])
		elif f.ends_with(".tscn") or f.ends_with(".tres"):
			var r = load(f)
			scenes += 1
			if r == null:
				errors += 1
				printerr("RESOURCE ERROR: %s" % f)
	print("[check] scripts=%d resources=%d errors=%d" % [scripts, scenes, errors])
	quit(1 if errors > 0 else 0)


func _is_static_only(s: GDScript) -> bool:
	return true


func _walk(path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if dir.current_is_dir():
			if not f.begins_with(".") and f != "addons":
				_walk(path.path_join(f), out)
		else:
			out.append(path.path_join(f))
		f = dir.get_next()
	dir.list_dir_end()
