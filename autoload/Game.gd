extends Node
## Стейт аппа + слот сейва (§5, §15).
## App: MENU → LOAD_SLOT → IN_WORLD. InWorld.mode: Types.WorldMode.

signal app_state_changed(state: int)
signal world_mode_changed(mode: int, prev: int)
signal slot_loaded(slot: int)
signal slot_saved(slot: int)
signal win_reached()
signal notify(text: String, seconds: float) # худ-тост (не туториал — ор/статус)

enum AppState { MENU, LOAD_SLOT, IN_WORLD }

const SAVE_VERSION := 1
const SLOT_COUNT := 4
const HOUSE_PRICE := 25000
const SAVE_DIR := "user://slots"

var app_state: int = AppState.MENU
var world_mode: int = Types.WorldMode.TRAILER_HUB
var slot: int = -1
var save: Dictionary = {}
var world: Node = null # текущая сцена World (res://world/World.tscn)
var playtime: float = 0.0
var pending_host := true # что делать после загрузки слота: host или join
var pending_join_address := ""
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)


func _process(delta: float) -> void:
	if app_state == AppState.IN_WORLD:
		playtime += delta


# ------------------------------------------------------------------ slots

func default_save() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"pot": 40,
		"unlocked_districts": [Types.District.TRAILER_PARK, Types.District.HANGAR, Types.District.VENDORS],
		"unlocked_vendors": ["vendor_tiny"],
		"vehicles": [],
		"trailer_junk": [],
		"tools": ["tool_flashlight", "tool_rag"],
		"blacklist": [],
		"won": false,
		"haggle_skill": 0.0,
		"house_bought": false,
		"lots_done": [],
		"burned_lots": [],
		"lot_cursor": {}, # district → индекс следующего пресета в волне
		"evidence": [],
		"playtime": 0.0,
		"achievements": [],
		"stats": {},
		"created": Time.get_datetime_string_from_system(),
	}


func slot_path(i: int) -> String:
	return "%s/slot_%d.json" % [SAVE_DIR, i]


func slot_exists(i: int) -> bool:
	return FileAccess.file_exists(slot_path(i))


func slot_summary(i: int) -> Dictionary:
	if not slot_exists(i):
		return {}
	var f := FileAccess.open(slot_path(i), FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return {
		"pot": int(parsed.get("pot", 0)),
		"won": bool(parsed.get("won", false)),
		"playtime": float(parsed.get("playtime", 0.0)),
		"lots_done": (parsed.get("lots_done", []) as Array).size(),
		"created": parsed.get("created", ""),
	}


func new_slot(i: int) -> void:
	slot = i
	save = default_save()
	playtime = 0.0
	if Economy:
		Economy.set_pot(int(save["pot"]), "new") # иначе write_slot перепишет стартовые $40 нулём из Economy
	write_slot()


func load_slot(i: int) -> bool:
	_restore_from_cloud(i)
	if not slot_exists(i):
		new_slot(i)
		return true
	var f := FileAccess.open(slot_path(i), FileAccess.READ)
	if f == null:
		return false
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	slot = i
	save = default_save()
	for k in parsed:
		save[k] = parsed[k]
	# JSON превращает int в float — приводим ключевые поля
	save["pot"] = int(save["pot"])
	var ud: Array = []
	for d in save["unlocked_districts"]:
		ud.append(int(d))
	save["unlocked_districts"] = ud
	var bl: Array = []
	for d in save["blacklist"]:
		bl.append(int(d))
	save["blacklist"] = bl
	playtime = float(save.get("playtime", 0.0))
	slot_loaded.emit(i)
	return true


## Steam Cloud (§15): если в облаке слот новее локального (или локального нет) — берём облачный.
## Сравниваем по playtime: больше наиграно — тот и актуальнее. Без Steam — no-op.
func _restore_from_cloud(i: int) -> void:
	if not SteamBoot or not SteamBoot.enabled:
		return
	var bytes := SteamBoot.cloud_read("slot_%d.json" % i)
	if bytes.is_empty():
		return
	var cloud = JSON.parse_string(bytes.get_string_from_utf8())
	if typeof(cloud) != TYPE_DICTIONARY:
		return
	var use_cloud := true
	if slot_exists(i):
		var f := FileAccess.open(slot_path(i), FileAccess.READ)
		if f:
			var local = JSON.parse_string(f.get_as_text())
			if typeof(local) == TYPE_DICTIONARY and float(local.get("playtime", 0.0)) >= float(cloud.get("playtime", 0.0)):
				use_cloud = false
	if use_cloud:
		var out := FileAccess.open(slot_path(i), FileAccess.WRITE)
		if out:
			out.store_string(bytes.get_string_from_utf8())
			out.close()
			print("[Game] slot %d restored from Steam Cloud" % i)


func write_slot() -> void:
	if slot < 0:
		return
	save["playtime"] = playtime
	save["version"] = SAVE_VERSION
	if Economy:
		save["pot"] = Economy.pot
	var f := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if f == null:
		push_error("[Game] cannot write slot %d" % slot)
		return
	var text := JSON.stringify(save, "\t")
	f.store_string(text)
	f.close()
	if SteamBoot and SteamBoot.enabled:
		SteamBoot.cloud_write("slot_%d.json" % slot, text.to_utf8_buffer())
	slot_saved.emit(slot)


func delete_slot(i: int) -> void:
	if slot_exists(i):
		DirAccess.remove_absolute(slot_path(i))


# ------------------------------------------------------------------ app flow

func set_app_state(s: int) -> void:
	if app_state == s:
		return
	app_state = s
	app_state_changed.emit(s)


func start_world_from_slot(i: int, as_host: bool = true, join_address: String = "") -> void:
	set_app_state(AppState.LOAD_SLOT)
	pending_host = as_host
	pending_join_address = join_address
	if as_host:
		load_slot(i)
		Economy.set_pot(int(save["pot"]), "load")
	else:
		# клиент играет в слоте хоста; локальный слот только как кэш котла
		slot = i
		save = default_save()
	get_tree().change_scene_to_file("res://world/World.tscn")


func world_ready(w: Node) -> void:
	world = w
	set_app_state(AppState.IN_WORLD)
	if pending_host:
		Net.host()
	else:
		Net.join(pending_join_address)
	set_world_mode(Types.WorldMode.TRAILER_HUB)


func back_to_menu() -> void:
	if app_state == AppState.IN_WORLD and Net.is_host():
		write_slot()
	Net.shutdown()
	world = null
	set_app_state(AppState.MENU)
	get_tree().paused = false
	get_tree().change_scene_to_file("res://ui/menu/MainMenu.tscn")


func set_world_mode(m: int) -> void:
	if world_mode == m:
		return
	var prev := world_mode
	world_mode = m
	world_mode_changed.emit(m, prev)
	if Net.is_host():
		Net.broadcast_world_mode(m)


# ------------------------------------------------------------------ slot helpers

func is_district_unlocked(d: int) -> bool:
	return (save.get("unlocked_districts", []) as Array).has(d)


func unlock_district(d: int) -> void:
	var arr: Array = save["unlocked_districts"]
	if not arr.has(d):
		arr.append(d)
		var name := tr("DISTRICT_%s" % Types.District.keys()[d]) if d < Types.District.keys().size() else ""
		notify.emit(tr("NOTIFY_DISTRICT_UNLOCKED") + (": " + name if name != "" else ""), 5.0)
		if AudioBus:
			AudioBus.play_ui("achievement", -4.0)
		if Net.players.size() > 1:
			Net.broadcast_event("district_unlocked", {"d": d})
		write_slot()


func is_vendor_unlocked(id: String) -> bool:
	return (save.get("unlocked_vendors", []) as Array).has(id)


func unlock_vendor(id: String) -> void:
	var arr: Array = save["unlocked_vendors"]
	if not arr.has(id):
		arr.append(id)
		write_slot()


func is_blacklisted(d: int) -> bool:
	return (save.get("blacklist", []) as Array).has(d)


func blacklist(d: int) -> void:
	var arr: Array = save["blacklist"]
	if not arr.has(d):
		arr.append(d)
		notify.emit(tr("NOTIFY_BLACKLISTED"), 3.0)
		write_slot()


func lot_done(id: String) -> void:
	var arr: Array = save["lots_done"]
	if not arr.has(id):
		arr.append(id)
	check_progression()
	write_slot()


## Кривая районов (§12: ангар → склады → гаражи → порт) — по заработку ИЛИ по числу вывезенных лотов,
## чтобы ни жадный, ни невезучий не застряли. Зовётся после лота и при росте котла.
const DISTRICT_GATES := [
	[Types.District.STORAGE, 250, 2],
	[Types.District.GARAGES, 2000, 7],
	[Types.District.PORT, 7000, 13],
	[Types.District.CAR_MARKET, 600, 4],
	[Types.District.LOCKSMITH, 150, 1],
	[Types.District.CASINO, 400, 3],
	[Types.District.POLICE, 0, 0],
]


func check_progression() -> void:
	if not Net.is_host():
		return
	var earned := stat("earned_total")
	var lots := (save.get("lots_done", []) as Array).size()
	for g in DISTRICT_GATES:
		var d: int = g[0]
		if is_district_unlocked(d):
			continue
		if earned >= float(g[1]) or lots >= int(g[2]):
			unlock_district(d)


## Что откроется следующим и сколько до него — для вывески в трейлере / подсказки.
func next_gate() -> Dictionary:
	var earned := stat("earned_total")
	var lots := (save.get("lots_done", []) as Array).size()
	for g in DISTRICT_GATES:
		if not is_district_unlocked(g[0]) and g[1] > 0:
			return {"district": g[0], "need_earned": maxf(0.0, float(g[1]) - earned), "need_lots": maxi(0, int(g[2]) - lots)}
	return {}


func lot_burned(id: String) -> void:
	var arr: Array = save["burned_lots"]
	if not arr.has(id):
		arr.append(id)
	write_slot()


func is_lot_burned(id: String) -> bool:
	return (save.get("burned_lots", []) as Array).has(id)


func stat_add(key: String, v: float = 1.0) -> float:
	var st: Dictionary = save["stats"]
	st[key] = float(st.get(key, 0.0)) + v
	return st[key]


func stat(key: String) -> float:
	return float((save["stats"] as Dictionary).get(key, 0.0))


func haggle_skill() -> float:
	return float(save.get("haggle_skill", 0.0))


func haggle_skill_gain(v: float) -> void:
	save["haggle_skill"] = clampf(haggle_skill() + v, 0.0, 1.0)


## Покупка дома → титры → песочница (§17.3).
func try_buy_house() -> bool:
	if save.get("house_bought", false):
		return false
	if not Economy.try_spend(HOUSE_PRICE, "house"):
		notify.emit(tr("NOTIFY_HOUSE_TOO_POOR"), 3.0)
		return false
	save["house_bought"] = true
	save["won"] = true
	write_slot()
	Achievements.unlock("moved_out")
	win_reached.emit()
	set_world_mode(Types.WorldMode.CREDITS)
	return true
