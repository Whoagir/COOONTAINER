extends Node
## Реестр контента: ItemDef / Archetype / LotPreset / AuctionBrain / VendorDef.
## Грузит все .tres из res://data/** при старте. Архитектура держит 3000–10000 карточек:
## словари по id, ленивых сцен нет — карточки лёгкие, меши строятся при спавне.

const ITEMS_DIR := "res://data/items"
const ARCH_DIR := "res://data/archetypes"
const LOTS_DIR := "res://data/lots"
const HUNTERS_DIR := "res://data/hunters"
const VENDORS_DIR := "res://data/vendors"

var items: Dictionary = {} # id → ItemDef
var archetypes: Dictionary = {} # id → Archetype
var lots: Dictionary = {} # id → LotPreset
var hunters: Dictionary = {} # id → AuctionBrain
var vendors: Dictionary = {} # id → VendorDef

var _items_by_tag: Dictionary = {}
var _lots_by_district: Dictionary = {}
var loaded := false


func _ready() -> void:
	_load_extra_strings()
	load_all()


## Доп. таблицы строк: res://data/strings/strings_*.csv (keys,ru,en) грузятся в рантайме,
## чтобы системы могли держать свои строки отдельно без правки project.godot.
func _load_extra_strings() -> void:
	var dir := DirAccess.open("res://data/strings")
	if dir == null:
		return
	var tr_ru := Translation.new()
	tr_ru.locale = "ru"
	var tr_en := Translation.new()
	tr_en.locale = "en"
	var count := 0
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.begins_with("strings_") and f.ends_with(".csv"):
			var fa := FileAccess.open("res://data/strings".path_join(f), FileAccess.READ)
			if fa:
				var header := fa.get_csv_line()
				var ru_i := header.find("ru")
				var en_i := header.find("en")
				while not fa.eof_reached():
					var line := fa.get_csv_line()
					if line.size() < 2 or line[0].strip_edges() == "":
						continue
					var key := line[0].strip_edges()
					if ru_i >= 0 and ru_i < line.size():
						tr_ru.add_message(key, line[ru_i])
					if en_i >= 0 and en_i < line.size():
						tr_en.add_message(key, line[en_i])
					count += 1
		f = dir.get_next()
	dir.list_dir_end()
	if count > 0:
		TranslationServer.add_translation(tr_ru)
		TranslationServer.add_translation(tr_en)
	var sys_locale := OS.get_locale_language()
	TranslationServer.set_locale("ru" if sys_locale == "ru" else "en")


func load_all() -> void:
	items.clear(); archetypes.clear(); lots.clear(); hunters.clear(); vendors.clear()
	_items_by_tag.clear(); _lots_by_district.clear()
	for r in _load_dir(ARCH_DIR):
		if r is Archetype:
			archetypes[r.id] = r
	for r in _load_dir(ITEMS_DIR):
		if r is ItemDef:
			items[r.id] = r
			for t in r.tags:
				if not _items_by_tag.has(t):
					_items_by_tag[t] = []
				_items_by_tag[t].append(r)
	for r in _load_dir(LOTS_DIR):
		if r is LotPreset:
			lots[r.id] = r
			if not _lots_by_district.has(r.district_id):
				_lots_by_district[r.district_id] = []
			_lots_by_district[r.district_id].append(r)
	for d in _lots_by_district:
		_lots_by_district[d].sort_custom(func(a, b): return a.order < b.order)
	for r in _load_dir(HUNTERS_DIR):
		if r is AuctionBrain:
			hunters[r.id] = r
	for r in _load_dir(VENDORS_DIR):
		if r is VendorDef:
			vendors[r.id] = r
	_ensure_cash_defs()
	_validate()
	loaded = true
	print("[Registry] items=%d archetypes=%d lots=%d hunters=%d vendors=%d" % [
		items.size(), archetypes.size(), lots.size(), hunters.size(), vendors.size()])


func _load_dir(path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("[Registry] no dir %s" % path)
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if dir.current_is_dir():
			if not f.begins_with("."):
				out.append_array(_load_dir(path.path_join(f)))
		else:
			var name := f
			if name.ends_with(".remap"):
				name = name.trim_suffix(".remap")
			if name.ends_with(".tres") or name.ends_with(".res"):
				var res := ResourceLoader.load(path.path_join(name))
				if res:
					out.append(res)
		f = dir.get_next()
	dir.list_dir_end()
	return out


## Купюры (§6.3) — гарантированно существуют даже если контент их не описал.
func _ensure_cash_defs() -> void:
	for nominal in [1, 5, 10, 20, 50, 100, 500]:
		var id := "cash_%d" % nominal
		if items.has(id):
			continue
		var d := ItemDef.new()
		d.id = id
		d.name_ru = "Купюра $%d" % nominal
		d.name_en = "$%d bill" % nominal
		d.archetype_id = "bill"
		d.value_base = nominal
		d.facets = [Types.Facet.DOCUMENT]
		d.flammable = true
		d.color = Color(0.55, 0.75, 0.5) if nominal < 100 else Color(0.9, 0.75, 0.3)
		items[id] = d
	if not archetypes.has("bill"):
		var a := Archetype.new()
		a.id = "bill"
		a.builder = "bill"
		a.size_class = Types.SizeClass.POCKET
		a.mass_default = 0.01
		a.dims = Vector3(0.156, 0.002, 0.066)
		archetypes["bill"] = a
	_ensure_shard_def()


func _ensure_shard_def() -> void:
	if not archetypes.has("shard_piece"):
		var a := Archetype.new()
		a.id = "shard_piece"
		a.builder = "box_small"
		a.size_class = Types.SizeClass.ONE_HAND
		a.mass_default = 0.25
		a.dims = Vector3(0.12, 0.1, 0.12)
		a.shard_count = 0
		a.base_color = Color(0.65, 0.6, 0.55)
		archetypes["shard_piece"] = a
	if items.has("shard_piece"):
		return
	var d := ItemDef.new()
	d.id = "shard_piece"
	d.name_ru = "Осколок"
	d.name_en = "Shard"
	d.archetype_id = "shard_piece"
	d.value_base = 1
	d.break_threshold = 999.0
	d.tags = ["shard", "scrap"]
	d.vendor_affinity = ["vendor_household", "vendor_junk"]
	d.lore_ru = "Кусок от разбитой вещи. Можно поднять и продать за копейки."
	d.lore_en = "A piece of something broken. Pick it up and sell for pennies."
	items["shard_piece"] = d
	if not _items_by_tag.has("shard"):
		_items_by_tag["shard"] = []
	_items_by_tag["shard"].append(d)


func _validate() -> void:
	var missing := 0
	for id in items:
		var d: ItemDef = items[id]
		if not archetypes.has(d.archetype_id):
			missing += 1
			if missing <= 5:
				push_warning("[Registry] item %s → no archetype %s" % [id, d.archetype_id])
	if missing > 0:
		push_warning("[Registry] %d items with missing archetypes (fallback box_small)" % missing)


func item(id: String) -> ItemDef:
	return items.get(id)


func archetype(id: String) -> Archetype:
	var a: Archetype = archetypes.get(id)
	if a == null:
		a = archetypes.get("box_small")
	return a


func archetype_for(def: ItemDef) -> Archetype:
	return archetype(def.archetype_id)


func lot(id: String) -> LotPreset:
	return lots.get(id)


func lots_for_district(d: int) -> Array:
	return _lots_by_district.get(d, [])


func hunter(id: String) -> AuctionBrain:
	return hunters.get(id)


func all_hunters() -> Array:
	return hunters.values()


func vendor(id: String) -> VendorDef:
	return vendors.get(id)


func all_vendors() -> Array:
	return vendors.values()


func items_with_tag(tag: String) -> Array:
	return _items_by_tag.get(tag, [])


func all_items() -> Array:
	return items.values()


func random_item_with_facet(f: int) -> ItemDef:
	var pool: Array = []
	for d in items.values():
		if d.has_facet(f):
			pool.append(d)
	if pool.is_empty():
		return null
	return pool[randi() % pool.size()]


## Купюры под сумму: жадный разбор по номиналам.
func bills_for(amount: int) -> Array[String]:
	var out: Array[String] = []
	var left := amount
	for nominal in [500, 100, 50, 20, 10, 5, 1]:
		while left >= nominal:
			out.append("cash_%d" % nominal)
			left -= nominal
			if out.size() > 60: # не заваливать сцену бумажками
				return out
	return out
