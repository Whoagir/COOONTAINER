class_name World
extends Node3D
## Корень InWorld (§5). Один город на всю пати; районы — телепорт/дорога, не «матч».
## Системы лежат в $Systems и общаются через handle_action / on_net_event.

@onready var city: Node3D = $City
@onready var items: Node3D = $Items
@onready var players_root: Node3D = $Players
@onready var npcs_root: Node3D = $Npcs
@onready var systems_root: Node = $Systems
@onready var hud: CanvasLayer = $HUD
@onready var pause_menu: CanvasLayer = $Pause

const PLAYER_SCENE := preload("res://actor/player/Player.tscn")

var pins: Dictionary = {} # peer → Node3D
var _systems_cache: Dictionary = {}


func _ready() -> void:
	Game.world_ready(self)
	Game.world_mode_changed.connect(_on_mode_changed)
	Economy.broke.connect(_on_broke)
	Game.win_reached.connect(_on_win)
	_apply_slot_to_world()
	Game.check_progression() # старые сейвы / пропущенные гейты
	AudioBus.play_music("hub_loop", -12.0)
	var cine := Cinematic.new()
	cine.name = "Cinematic"
	systems_root.add_child(cine)
	var trailer_script: GDScript = load("res://tools/Trailer.gd") if ResourceLoader.exists("res://tools/Trailer.gd") else null
	var in_trailer: bool = trailer_script != null and trailer_script.wanted()
	if in_trailer:
		var tr_node: Node = trailer_script.new()
		tr_node.name = "Trailer"
		add_child(tr_node)
	var smoke_script: GDScript = load("res://tools/Smoke.gd")
	if smoke_script.wanted():
		var s: Node = smoke_script.new()
		s.name = "Smoke"
		add_child(s)
	var play_script: GDScript = load("res://tools/Playtest.gd")
	if play_script.wanted():
		var t: Node = play_script.new()
		t.name = "Playtest"
		add_child(t)
	if OS.get_cmdline_user_args().has("--autoshot") and DisplayServer.get_name() != "headless":
		_autoshot() # dev: кадр каждые 1.5 с в user://shots/auto_*.png 24 с, потом выход (интро/катсцены)
	if ResourceLoader.exists("res://tools/ArtShot.gd"):
		var art_script: GDScript = load("res://tools/ArtShot.gd")
		if art_script.wanted():
			var a: Node = art_script.new()
			a.name = "ArtShot"
			add_child(a)
	if ResourceLoader.exists("res://tools/NetTest.gd"):
		var net_script: GDScript = load("res://tools/NetTest.gd")
		if net_script.wanted():
			var n: Node = net_script.new()
			n.name = "NetTest"
			add_child(n)


func _apply_slot_to_world() -> void:
	# трейлер обрастает хламом/инструментами из слота (§12, §15) — только хост спавнит
	if not Net.is_host():
		return
	await get_tree().process_frame
	await get_tree().process_frame
	var shelf := find_marker(Types.District.TRAILER_PARK, "ToolShelf")
	var base := shelf.global_transform if shelf else Transform3D(Basis(), Vector3(0, 1, 0))
	var i := 0
	for tool_id in Game.save.get("tools", []):
		if Registry.item(tool_id):
			Net.spawn_item(tool_id, base * Transform3D(Basis(), Vector3(-0.6 + 0.4 * (i % 4), 0.05 + 0.3 * (i / 4), 0)))
			i += 1
	var junk := find_marker(Types.District.TRAILER_PARK, "JunkYard")
	if junk:
		for j in Game.save.get("trailer_junk", []):
			var d: Dictionary = j
			var pos: Array = d.get("pos", [0, 0, 0])
			var xf := Transform3D(Basis(Vector3.UP, float(d.get("rot", 0.0))), junk.global_position + Vector3(pos[0], pos[1] + 0.2, pos[2]))
			var b = Net.spawn_item(str(d["item_id"]), xf, d.get("state", {}))
	var veh_sys := system("Vehicles")
	if veh_sys and veh_sys.has_method("spawn_from_save"):
		veh_sys.spawn_from_save(Game.save.get("vehicles", []))


## Хлам трейлера в слот (при сейве). Вызывает Game перед write_slot через мир.
func collect_trailer_junk() -> Array:
	var out: Array = []
	var junk := find_marker(Types.District.TRAILER_PARK, "JunkYard")
	if junk == null:
		return out
	for nid in Net.items:
		var b = Net.items[nid]
		if not is_instance_valid(b) or b.nested_in or b.def.is_cash() or b.get_meta("pocket_of", 0) != 0:
			continue
		if b.global_position.distance_to(junk.global_position) < 14.0 and not (Game.save.get("tools", []) as Array).has(b.def.id):
			var rel: Vector3 = b.global_position - junk.global_position
			out.append({"item_id": b.def.id, "pos": [rel.x, maxf(rel.y, 0.0), rel.z], "rot": b.rotation.y, "state": b.state_dict()})
			if out.size() >= 80:
				break
	return out


# ------------------------------------------------------------------ доступ

func items_root() -> Node:
	return items


func system(name: String) -> Node:
	if _systems_cache.has(name):
		return _systems_cache[name]
	var n := systems_root.get_node_or_null(name)
	if n:
		_systems_cache[name] = n
	return n


func district_root(d: int) -> Node3D:
	if city.has_method("district_root"):
		return city.district_root(d)
	return null


func find_marker(d: int, marker: String) -> Node3D:
	var root := district_root(d)
	if root == null:
		return null
	var n := root.find_child(marker, true, false)
	return n as Node3D


func local_player() -> Player:
	return Net.players.get(Net.my_id())


func player_of(peer: int) -> Player:
	return Net.players.get(peer)


# ------------------------------------------------------------------ игроки

func spawn_player(id: int) -> Player:
	var p: Player = PLAYER_SCENE.instantiate()
	p.peer_id = id
	p.name = "Player_%d" % id
	players_root.add_child(p)
	var bed := _bed_for(id)
	p.respawn_point = bed
	p.global_position = bed
	var door := find_marker(Types.District.TRAILER_PARK, "TrailerDoor")
	if door:
		p.look_toward(door.global_position)
	if id == Net.my_id() and not Game.save.get("intro_seen", false) and not _headless_or_test():
		call_deferred("_play_intro")
	return p


func _headless_or_test() -> bool:
	if DisplayServer.get_name() == "headless":
		return true
	for a in OS.get_cmdline_user_args():
		if a in ["--smoke", "--playtest", "--nettest", "--trailer", "--police-test", "--artshot"]:
			return true
	return false


## Бюджет физики (§7.5): ≤200 бодрствующих тел. Лишние — самые дальние от игроков и почти
## неподвижные — усыпляем; Jolt разбудит их при касании. Осколки капает Shard.MAX_SHARDS.
const AWAKE_BUDGET := 200
var _budget_t := 0.0


func _process(delta: float) -> void:
	if not Net.is_host():
		return
	_budget_t += delta
	if _budget_t < 1.5:
		return
	_budget_t = 0.0
	var awake: Array = []
	for nid in Net.items:
		var b = Net.items[nid]
		if is_instance_valid(b) and not b.proxy and not b.freeze and not b.sleeping and b.held_by.is_empty():
			awake.append(b)
	if awake.size() <= AWAKE_BUDGET:
		return
	var anchors: Array = []
	for pid in Net.players:
		var p = Net.players[pid]
		if is_instance_valid(p):
			anchors.append(p.global_position)
	var scored: Array = []
	for b in awake:
		var d := INF
		for a in anchors:
			d = minf(d, b.global_position.distance_squared_to(a))
		scored.append([d, b])
	scored.sort_custom(func(x, y): return x[0] > y[0])
	var to_sleep := awake.size() - AWAKE_BUDGET
	for s in scored:
		if to_sleep <= 0:
			break
		var b = s[1]
		if b.linear_velocity.length() < 0.6 and s[0] > 36.0: # дальше 6 м и почти стоит
			b.sleeping = true
			to_sleep -= 1


func _autoshot() -> void:
	var dir := OS.get_user_data_dir().path_join("shots")
	DirAccess.make_dir_recursive_absolute(dir)
	for i in 16:
		await get_tree().create_timer(1.5).timeout
		get_viewport().get_texture().get_image().save_png(dir.path_join("auto_%02d.png" % i))
	load("res://tools/Smoke.gd").cleanup_test_slot()
	get_tree().quit()


func _play_intro() -> void:
	var cine := system("Cinematic")
	if cine == null or cine.playing:
		return
	await get_tree().create_timer(0.4).timeout
	Game.save["intro_seen"] = true
	cine.play(Cutscenes.intro(self), true)


func _bed_for(id: int) -> Vector3:
	var idx := 0
	var ids := Net.players.keys()
	ids.append(id)
	ids.sort()
	idx = ids.find(id)
	var bed := find_marker(Types.District.TRAILER_PARK, "Bed%d" % (idx % 4))
	if bed:
		return bed.global_position + Vector3(0, 0.3, 0)
	return Vector3(idx * 1.5, 1.0, 0)


func on_player_died(p: Player, reason: String) -> void:
	# арест/смерть → режим DEAD только для этого игрока; мир не меняется
	if reason == "fire":
		Achievements.unlock("well_done")


# ------------------------------------------------------------------ действия игроков (хост)

func handle_action(peer: int, kind: String, data: Dictionary) -> void:
	var p := player_of(peer)
	if p == null:
		return
	match kind:
		"pocket_put":
			var b = Net.items.get(int(data.get("nid", 0)))
			if b:
				p.host_pocket_put(b)
			return
		"pocket_take":
			p.host_pocket_take()
			return
		"flip_held":
			p.hands.flip_held = bool(data.get("on", false))
			return
		"scrub":
			var t = Net.items.get(int(data.get("target", 0)))
			var rag = Net.items.get(int(data.get("rag", 0)))
			if t and rag:
				t.scrub(float(data.get("amount", 0.06)), rag.wet > 0.2)
			return
		"apply_tool":
			var tool = Net.items.get(int(data.get("tool", 0)))
			var target = Net.items.get(int(data.get("target", 0)))
			if tool and target:
				_apply_tool(p, tool, target)
			return
		"interact":
			var n := get_node_or_null(NodePath(str(data.get("path", ""))))
			if n and n.has_method("interact") and n.global_position.distance_to(p.head_position()) < 4.0:
				n.interact(p)
			return
		"grab_special":
			var n := get_node_or_null(NodePath(str(data.get("path", ""))))
			if n and n.has_method("on_grab"):
				n.on_grab(p)
			return
		"pin":
			_place_pin(peer, data.get("pos", p.global_position))
			return
	for s in systems_root.get_children():
		if s.has_method("handle_action") and s.handle_action(peer, kind, data):
			return


func _apply_tool(p: Player, tool: ItemBody, target: ItemBody) -> void:
	var tags := tool.def.tags
	if tags.has("tape") or tags.has("plank"):
		if target.apply_patch(tool.def):
			tool.consume_use(p)
	elif tags.has("lockpick"):
		if target.locked:
			if target.unlock_by(tool.def, 0.35 + Game.haggle_skill() * 0.2):
				Achievements.unlock("picked_lock")
			elif randf() < 0.2:
				tool.consume_use(p)
				p.say(tr("ITEM_LOCKPICK_BROKE"))
	elif tags.has("rag"):
		target.scrub(0.25, tool.wet > 0.2)
	elif tags.has("lighter") or tags.has("matches"):
		if target.is_flammable():
			target.ignite()
			Game.stat_add("fires_started")
			Achievements.unlock("pyro")
		else:
			p.say(tr("ITEM_WONT_BURN"))


func _place_pin(peer: int, pos: Vector3) -> void:
	Net.broadcast_event("pin", {"peer": peer, "pos": pos})
	_show_pin(peer, pos)


func _show_pin(peer: int, pos: Vector3) -> void:
	var old = pins.get(peer)
	if old and is_instance_valid(old):
		old.queue_free()
	var pin := Node3D.new()
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.04
	cm.bottom_radius = 0.12
	cm.height = 3.0
	beam.mesh = cm
	var m := StandardMaterial3D.new()
	var p := player_of(peer)
	m.albedo_color = p._body_mat.albedo_color if p else Color(1, 1, 0)
	m.emission_enabled = true
	m.emission = m.albedo_color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color.a = 0.55
	beam.material_override = m
	beam.position.y = 1.5
	pin.add_child(beam)
	var lbl := Label3D.new()
	lbl.text = "📍 %s" % (p.name_plate.text if p else "")
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 48
	lbl.outline_size = 10
	lbl.position.y = 3.3
	lbl.pixel_size = 0.006
	pin.add_child(lbl)
	add_child(pin)
	pin.global_position = pos
	pins[peer] = pin
	AudioBus.play_at("pin", pos, -4.0)
	get_tree().create_timer(25.0).timeout.connect(func(): if is_instance_valid(pin): pin.queue_free())


# ------------------------------------------------------------------ события (все)

func on_net_event(kind: String, data: Dictionary) -> void:
	match kind:
		"hands":
			var p := player_of(int(data["peer"]))
			if p and not Net.is_host():
				p.hands.apply_remote_hands(data["h"], bool(data["same"]))
		"pocket":
			var p := player_of(int(data["peer"]))
			if p and not Net.is_host():
				p.apply_pocket_event(int(data["nid"]), int(data["slot"]), bool(data["put"]))
		"wear":
			var p := player_of(int(data["peer"]))
			if p and not Net.is_host():
				p.apply_wear_event(int(data["nid"]), bool(data["on"]))
		"player_death":
			var p := player_of(int(data["peer"]))
			if p and not Net.is_host():
				p.on_remote_death(data["pos"], float(data["yaw"]), str(data.get("reason", "")))
		"player_respawn":
			var p := player_of(int(data["peer"]))
			if p and not Net.is_host():
				p.on_remote_respawn()
		"player_burn":
			var p := player_of(int(data["peer"]))
			if p and not Net.is_host():
				p.set_burning(bool(data["on"]))
		"player_splash":
			var p := player_of(int(data["peer"]))
			if p and not Net.is_host():
				p.splash(int(data["liquid"]), 0.5)
		"say":
			var p := player_of(int(data["peer"]))
			if p and not Net.is_host():
				p.say(str(data["text"]))
		"cuffed":
			var p := player_of(int(data["peer"]))
			if p and not Net.is_host():
				p.cuffed = bool(data["on"])
		"read_doc":
			if int(data["peer"]) == Net.my_id():
				Game.notify.emit("📄 " + str(data["text"]), 5.0)
		"achievement":
			if not Net.is_host():
				Achievements.unlock(str(data["id"]))
		"pin":
			if not Net.is_host():
				_show_pin(int(data["peer"]), data["pos"])
		"puddle":
			var liq := system("Liquids")
			if liq:
				liq.apply_puddle_event(data)
		"break":
			if not Net.is_host():
				var b = Net.items.get(int(data["nid"]))
				if b:
					b._spawn_loose_shards(data["pos"])
					AudioBus.play_at("shatter", data["pos"], 2.0)
		"npc_say":
			var n := get_node_or_null(NodePath(str(data["path"])))
			if n and n is Npc and not Net.is_host():
				n.remote_say(str(data["text"]), float(data["sec"]), str(data.get("cat", "")))
		"npc_ragdoll":
			var n := get_node_or_null(NodePath(str(data["path"])))
			if n and n is Npc and not Net.is_host():
				n.ragdoll_for(float(data["sec"]))
		"npc_spawn":
			if not Net.is_host() and str(data.get("kind", "")) == "firefighter":
				var ff := Npc.new()
				ff.npc_group = "firefighter"
				ff.body_color = Color(0.85, 0.15, 0.1)
				ff.hat = true
				ff.display_name = tr("NPC_FIREFIGHTER")
				npcs_root.add_child(ff)
				ff.global_position = data["pos"]
				ff.set_meta("host_path", str(data["path"]))
		"npc_spray":
			if not Net.is_host():
				var liq := system("Liquids")
				if liq:
					liq._stream_fx(Types.LiquidId.WATER, data["from"], data["dir"])
		"npc_despawn":
			if not Net.is_host():
				for n in npcs_root.get_children():
					if n.get_meta("host_path", "") == str(data["path"]):
						n.queue_free()
		"district_unlocked":
			if not Net.is_host():
				var arr: Array = Game.save.get("unlocked_districts", [])
				if not arr.has(int(data["d"])):
					arr.append(int(data["d"]))
					if not data.get("quiet", false):
						Game.notify.emit(tr("NOTIFY_DISTRICT_UNLOCKED"), 5.0)
						AudioBus.play_ui("achievement", -4.0)
	for s in systems_root.get_children():
		if s.has_method("on_net_event"):
			s.on_net_event(kind, data)


func send_full_state_to(peer: int) -> void:
	for d in Game.save.get("unlocked_districts", []):
		Net.send_event(peer, "district_unlocked", {"d": int(d), "quiet": true})
	for s in systems_root.get_children():
		if s.has_method("send_full_state_to"):
			s.send_full_state_to(peer)
	for pid in Net.players:
		var p: Player = Net.players[pid]
		if p and is_instance_valid(p):
			var ids: Array = [p.hands.held[0].net_id if p.hands.held[0] else 0, p.hands.held[1].net_id if p.hands.held[1] else 0]
			Net.send_event(peer, "hands", {"peer": pid, "h": ids, "same": p.hands.two_hands_same})
			if p.worn:
				Net.send_event(peer, "wear", {"peer": pid, "nid": p.worn.net_id, "on": true})


# ------------------------------------------------------------------ режимы

func _on_mode_changed(m: int, prev: int) -> void:
	match m:
		Types.WorldMode.TRAILER_HUB, Types.WorldMode.TRAVEL:
			AudioBus.play_music("hub_loop", -12.0)
		Types.WorldMode.AUCTION:
			AudioBus.play_music("auction_loop", -10.0)
		Types.WorldMode.CLEAR_OUT:
			AudioBus.play_music("clearout_loop", -10.0)
		Types.WorldMode.CASINO:
			AudioBus.play_music("casino_loop", -10.0)
		Types.WorldMode.VENDOR:
			AudioBus.play_music("vendor_loop", -12.0)
		Types.WorldMode.POLICE_CUSTODY:
			AudioBus.play_music("police_loop", -12.0)
		Types.WorldMode.CREDITS:
			AudioBus.play_music("credits", -8.0)
			_play_ending()
		Types.WorldMode.JANITOR_JOB:
			AudioBus.play_music("janitor_loop", -12.0)


func _on_broke() -> void:
	# котёл в нуле → доска объявлений + бригадир (§13). Не soft-lock.
	Game.notify.emit(tr("NOTIFY_BROKE"), 5.0)
	var jobs := system("Jobs")
	if jobs and jobs.has_method("suggest_work"):
		jobs.suggest_work("broke")
	var jan := system("Janitor")
	if jan and jan.has_method("offer_job"):
		jan.offer_job()


func _on_win() -> void:
	Game.notify.emit(tr("NOTIFY_WIN"), 6.0)


## Финал: катсцена с домом (у каждого локально) → титры с хроникой → песочница.
func _play_ending() -> void:
	var cine := system("Cinematic")
	if cine and not cine.playing and not DisplayServer.get_name() == "headless":
		cine.play(Cutscenes.ending(self), true)
		await cine.finished
	if hud.has_method("show_credits"):
		hud.show_credits()


func on_lot_burned(lot_id: String) -> void:
	var auction := system("Auction")
	if auction and auction.has_method("on_lot_burned"):
		auction.on_lot_burned(lot_id)


# ------------------------------------------------------------------ лоты (общий helper для Auction/ClearOut/Janitor)

## Спавн содержимого лота в ячейку (ручной пресет → трансформы относительно Cell).
func spawn_lot_contents(preset: LotPreset, cell: Node3D) -> Array:
	var out: Array = []
	if not Net.is_host():
		return out
	var burned := Game.is_lot_burned(preset.id)
	for s in preset.spawn_list:
		var def := Registry.item(s.item_id)
		if def == null:
			continue
		var xf: Transform3D = cell.global_transform * s.xform
		var state := {"lot": preset.id}
		if s.locked_override == 1:
			state["lk"] = true
		elif s.locked_override == 0:
			state["lk"] = false
		elif def.has_facet(Types.Facet.LOCKED):
			# lock_chance пресета — доля замков по лоту; у запираемых вещей шанс выше, но ангар (0.05) не 50%
			state["lk"] = randf() < clampf(preset.lock_chance * 2.5 + 0.1, 0.1, 0.9)
		if s.dirt_override >= 0.0:
			state["d"] = s.dirt_override
		elif preset.broom_required:
			state["d"] = clampf(def.dusty_default + 0.3, 0.0, 1.0)
		if burned:
			state["bu"] = true
		var b = Net.spawn_item(s.item_id, xf, state)
		if b == null:
			continue
		out.append(b)
		var nested_ids: Array = s.nested.duplicate()
		# nest_loot карточки — шанс
		for lr in def.nest_loot:
			if randf() < lr.chance:
				var n := randi_range(lr.count_min, lr.count_max)
				for k in n:
					nested_ids.append(lr.item_id)
		for nid in nested_ids:
			if not Registry.item(nid):
				continue
			var child = Net.spawn_item(nid, xf, {"lot": preset.id, "bu": burned} if burned else {"lot": preset.id}, b.net_id)
			if child:
				out.append(child)
				# глубина 2: у вложенного тоже может быть nest_loot (чемодан → книга → купюра)
				var cdef := Registry.item(nid)
				for lr2 in cdef.nest_loot:
					if randf() < lr2.chance and child.nest_depth() < 2:
						var gc = Net.spawn_item(lr2.item_id, xf, {"lot": preset.id}, child.net_id)
						if gc:
							out.append(gc)
	return out


func despawn_lot_items(lot_id: String, only_inside: Node3D = null, radius: float = 0.0) -> int:
	var n := 0
	for nid in Net.items.keys():
		var b = Net.items.get(nid)
		if not is_instance_valid(b) or b.lot_id != lot_id:
			continue
		if only_inside and b.global_position.distance_to(only_inside.global_position) > radius:
			continue
		Net.despawn_item(nid)
		n += 1
	return n


func items_in_radius(pos: Vector3, r: float) -> Array:
	var out: Array = []
	for nid in Net.items:
		var b = Net.items[nid]
		if is_instance_valid(b) and b.nested_in == null and b.global_position.distance_to(pos) < r:
			out.append(b)
	return out


func _unhandled_input(event: InputEvent) -> void:
	var cine := system("Cinematic")
	if cine and cine.playing:
		return
	if event.is_action_pressed("pause"):
		if pause_menu.has_method("toggle"):
			pause_menu.toggle()
