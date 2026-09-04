class_name Locksmith
extends Node3D
## Вскрывальщик (§11): отдельный NPC. Положил запертое на верстак → E → плати → 3 с сцены → открыл
## или сломал (риск). Синхронизация через события; хост считает.
##
## События (хост → все): locksmith_work {nid, pos} · locksmith_done {nid, ok, pos, name}
## Маркеры (район LOCKSMITH): LocksmithBench (StaticBody3D), LocksmithSpot, LocksmithDropZone (Area3D)

const WORK_SEC := 3.0
const RATTLE_TIMES := [0.6, 1.4, 2.2]
const INTERACT_RANGE := 6.0

var bench: Node3D
var spot: Node3D
var drop_zone: Area3D
var npc: LocksmithNpc
var items: Array[ItemBody] = []
var busy := false
var interact_node: Vendors.Interactable
var _greet_cd := 0.0


func system_name() -> String:
	return "Locksmith"


func _ready() -> void:
	Net.item_despawned.connect(_on_item_despawned)
	_deferred_setup()


func _deferred_setup() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var w := Game.world as World
	if w == null:
		return
	var b := w.find_marker(Types.District.LOCKSMITH, "LocksmithBench")
	if b == null and w.city:
		b = w.city.find_child("LocksmithBench", true, false) as Node3D
	if b == null:
		return
	var s := w.find_marker(Types.District.LOCKSMITH, "LocksmithSpot")
	var z := w.find_marker(Types.District.LOCKSMITH, "LocksmithDropZone") as Area3D
	register_bench(b, s, z)


## Публично: верстак из готовых узлов (spot/zone опциональны — построим сами).
func register_bench(p_bench: Node3D, p_spot: Node3D = null, p_zone: Area3D = null) -> void:
	if p_bench == null or bench != null:
		return
	bench = p_bench
	spot = p_spot
	drop_zone = p_zone
	var front := _front()
	if drop_zone == null:
		drop_zone = Area3D.new()
		drop_zone.name = "LocksmithDropZone_rt"
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.6, 0.9, 0.9)
		cs.shape = bs
		drop_zone.add_child(cs)
		add_child(drop_zone)
		drop_zone.global_position = bench.global_position + Vector3(0, 1.45, 0)
	drop_zone.collision_layer = drop_zone.collision_layer | Types.L_TRIGGER
	drop_zone.collision_mask = drop_zone.collision_mask | Types.L_ITEM
	drop_zone.monitoring = true
	drop_zone.body_entered.connect(_on_zone_enter)
	drop_zone.body_exited.connect(_on_zone_exit)
	interact_node = Vendors.Interactable.new(Vector3(1.6, 0.7, 0.18))
	interact_node.name = "LocksmithInteract"
	add_child(interact_node)
	interact_node.global_position = bench.global_position + front * 0.6 + Vector3(0, 0.85, 0)
	interact_node.global_basis = Basis.looking_at(front, Vector3.UP)
	interact_node.on_interact = _on_interact
	interact_node.on_hint = _hint
	var lbl := Label3D.new()
	lbl.text = tr("LOCK_SIGN")
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 64
	lbl.outline_size = 12
	lbl.pixel_size = 0.006
	lbl.modulate = Color(0.8, 0.9, 1.0)
	add_child(lbl)
	lbl.global_position = bench.global_position + Vector3(0, 2.3, 0)
	_spawn_npc(front)


func _front() -> Vector3:
	var f := Vector3.ZERO
	if spot:
		f = bench.global_position - spot.global_position
	else:
		f = bench.global_basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.01 else Vector3.FORWARD


func _spawn_npc(front: Vector3) -> void:
	npc = LocksmithNpc.new()
	npc.setup()
	npc.name = "LocksmithNpc"
	var w := Game.world as World
	var parent: Node = w.npcs_root if (w and w.npcs_root) else self
	parent.add_child(npc)
	var pos := spot.global_position if spot else bench.global_position - front * 0.9
	npc.global_position = pos + Vector3(0, 0.05, 0)
	npc.face(bench.global_position + front * 1.5)


# ------------------------------------------------------------------ верстак

func _on_zone_enter(b: Node) -> void:
	if b is ItemBody and not items.has(b):
		items.append(b as ItemBody)


func _on_zone_exit(b: Node) -> void:
	if b is ItemBody:
		items.erase(b as ItemBody)


func _on_item_despawned(_nid: int) -> void:
	for i in range(items.size() - 1, -1, -1):
		if not is_instance_valid(items[i]):
			items.remove_at(i)


func _locked_item() -> ItemBody:
	for b in items:
		if b and is_instance_valid(b) and b.locked and not b.is_held() and b.nested_in == null:
			return b
	return null


func price_for(b: ItemBody) -> int:
	return maxi(10, int(b.def.value_base * 0.15))


func _hint(_p: Player) -> String:
	if busy:
		return tr("LOCK_HINT_BUSY")
	var b := _locked_item()
	if b == null:
		return tr("LOCK_HINT_EMPTY")
	return tr("LOCK_HINT") % [b.def.display_name(), price_for(b)]


func _on_interact(player: Player) -> void:
	if not Net.is_host() or npc == null:
		return
	if busy:
		npc.line("wait", 2.0)
		return
	var b := _locked_item()
	if b == null:
		npc.line("nothing", 2.5)
		return
	var cost := price_for(b)
	if not Economy.try_spend(cost, "locksmith"):
		npc.line("pay", 2.5)
		player.say(tr("LOCK_TOO_POOR") % cost)
		AudioBus.play_at("buzzer", bench.global_position, 0.0)
		return
	_work(b, player)


## Короткая сцена: NPC ковыряется, трижды дёргает замок, потом бросок кубика — открыл или сломал.
func _work(b: ItemBody, _player: Player) -> void:
	busy = true
	npc.line("work", 3.0)
	npc.face(b.global_position)
	Net.broadcast_event("locksmith_work", {"nid": b.net_id, "pos": b.global_position})
	await get_tree().create_timer(WORK_SEC).timeout
	busy = false
	if not is_instance_valid(b) or not b.locked:
		return
	var chance := 0.75 + Game.haggle_skill() * 0.1
	var ok := randf() < chance
	var nm := b.def.display_name()
	if ok:
		b.locked = false
		b._push_state()
		Game.stat_add("unlocked")
		Game.stat_add("locksmith_jobs")
		npc.line("success", 2.5)
		if b.def.tags.has("safe"):
			Achievements.unlock("safe_cracked")
	else:
		npc.line("fail", 3.0)
		Game.stat_add("locksmith_broken")
		if b.def.is_fragile():
			b.shatter()
		else:
			b.integrity = Types.Integrity.CHIPPED
			b._push_state()
	Net.broadcast_event("locksmith_done", {"nid": b.net_id, "ok": ok, "pos": b.global_position, "name": nm})


func handle_action(_peer: int, _kind: String, _data: Dictionary) -> bool:
	return false


func on_net_event(kind: String, data: Dictionary) -> void:
	match kind:
		"locksmith_work":
			var pos: Vector3 = data.get("pos", Vector3.ZERO)
			for t in RATTLE_TIMES:
				get_tree().create_timer(float(t)).timeout.connect(func(): AudioBus.play_at("locked_rattle", pos, 0.0, 0.2))
		"locksmith_done":
			var pos: Vector3 = data.get("pos", Vector3.ZERO)
			var ok := bool(data.get("ok", false))
			AudioBus.play_at("unlock" if ok else "crack", pos, 2.0)
			Game.notify.emit(tr("LOCK_TOAST_OK" if ok else "LOCK_TOAST_FAIL") % str(data.get("name", "")), 3.0)


func _physics_process(delta: float) -> void:
	if npc == null or not Net.is_host():
		return
	_greet_cd -= delta
	if _greet_cd > 0.0:
		return
	for pid in Net.players:
		var p = Net.players[pid]
		if p and is_instance_valid(p) and not p.dead and p.global_position.distance_to(bench.global_position) < 3.0:
			_greet_cd = 25.0
			npc.line("greet", 2.5)
			return
	_greet_cd = 0.5
