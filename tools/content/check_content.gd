extends SceneTree
## Проверка сгенерированного контента без автолоадов:
## godot --headless --path . --script tools/content/check_content.gd
## Грузит все .tres из data/{items,archetypes,hunters,vendors}, проверяет типы полей и ссылки nest_loot.


func _init() -> void:
	var errors := 0
	var archs := {}
	for r in _load_dir("res://data/archetypes"):
		if not (r is Archetype):
			printerr("not Archetype: ", r)
			errors += 1
			continue
		archs[r.id] = r
	var items := {}
	var with_loot := 0
	var loot_refs := 0
	for r in _load_dir("res://data/items"):
		if not (r is ItemDef):
			printerr("not ItemDef: ", r)
			errors += 1
			continue
		items[r.id] = r
	for id in items:
		var d: ItemDef = items[id]
		if not archs.has(d.archetype_id):
			printerr("%s: missing archetype %s" % [id, d.archetype_id])
			errors += 1
		if d.nest_loot.size() > 0:
			with_loot += 1
		for l in d.nest_loot:
			loot_refs += 1
			if not (l is LootRef):
				printerr("%s: nest_loot entry is not LootRef: %s" % [id, l])
				errors += 1
			elif not (items.has(l.item_id) or l.item_id.begins_with("cash_")):
				printerr("%s: nest_loot -> unknown %s" % [id, l.item_id])
				errors += 1
		for f in d.facets:
			if f < 0 or f >= Types.Facet.size():
				printerr("%s: bad facet %d" % [id, f])
				errors += 1
	var hunters := 0
	for r in _load_dir("res://data/hunters"):
		if r is AuctionBrain and r.catchphrases_ru.size() >= 5 and r.catchphrases_en.size() >= 5:
			hunters += 1
		else:
			printerr("bad hunter: ", r)
			errors += 1
	var vendors := 0
	for r in _load_dir("res://data/vendors"):
		if r is VendorDef and r.lines_greet_ru.size() >= 5 and r.lines_phobia_en.size() >= 5:
			vendors += 1
		else:
			printerr("bad vendor: ", r)
			errors += 1
	var sample: ItemDef = items.get("suitcase_leather")
	if sample:
		print("[check] suitcase_leather facets=%s nest=%d locked=%s color=%s vendors=%s" % [
			str(sample.facets), sample.nest_loot.size(), sample.has_facet(Types.Facet.LOCKED), str(sample.color), str(sample.vendor_affinity)])
	print("[check] archetypes=%d items=%d items_with_loot=%d loot_refs=%d hunters=%d vendors=%d errors=%d" % [
		archs.size(), items.size(), with_loot, loot_refs, hunters, vendors, errors])
	quit(1 if errors > 0 else 0)


func _load_dir(path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.ends_with(".tres"):
			var res := ResourceLoader.load(path.path_join(f))
			if res:
				out.append(res)
			else:
				printerr("failed to load ", path.path_join(f))
		f = dir.get_next()
	dir.list_dir_end()
	return out
