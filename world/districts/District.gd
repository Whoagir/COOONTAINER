class_name District
extends Node3D
## Район (§12). Корень сцены района: знак, зона входа (ЧС/менты), якоря лотов, точки NPC.
## Маркеры ищутся по имени через find_child — расстановка руками в редакторе.

signal player_entered(player: Player)
signal player_exited(player: Player)

@export var district_id: int = Types.District.TRAILER_PARK
@export var name_key: String = "DISTRICT_TRAILER_PARK"
@export var radius: float = 40.0
@export var unlock_cost: int = 0
@export var sign_height: float = 6.0

var players_inside: Array = []
var _sign: Label3D
var _entry: Area3D


func _ready() -> void:
	add_to_group("districts")
	_entry = get_node_or_null("Entry") as Area3D
	if _entry == null:
		_entry = Area3D.new()
		_entry.name = "Entry"
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = radius
		sh.height = 30.0
		cs.shape = sh
		cs.position.y = 10.0
		_entry.add_child(cs)
		add_child(_entry)
	_entry.collision_layer = Types.L_TRIGGER
	_entry.collision_mask = Types.L_PLAYER
	_entry.monitoring = true
	_entry.body_entered.connect(_on_body_entered)
	_entry.body_exited.connect(_on_body_exited)
	if get_node_or_null("Sign") == null:
		_sign = Label3D.new()
		_sign.name = "Sign"
		_sign.text = tr(name_key)
		_sign.font_size = 160
		_sign.outline_size = 24
		_sign.pixel_size = 0.01
		_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_sign.position.y = sign_height
		_sign.modulate = Color(1, 0.9, 0.4)
		add_child(_sign)
	else:
		_sign = get_node("Sign")
		_sign.text = tr(name_key)


func _on_body_entered(b: Node) -> void:
	if b is Player and not players_inside.has(b):
		players_inside.append(b)
		player_entered.emit(b)
		if b.is_local():
			Game.notify.emit(tr(name_key), 2.0)
			if district_id != Types.District.TRAILER_PARK and Game.world_mode == Types.WorldMode.TRAILER_HUB:
				Game.set_world_mode(Types.WorldMode.TRAVEL)
			elif district_id == Types.District.TRAILER_PARK and Game.world_mode == Types.WorldMode.TRAVEL:
				Game.set_world_mode(Types.WorldMode.TRAILER_HUB)
		if Net.is_host():
			if Game.is_blacklisted(district_id):
				var police = Game.world.system("Police")
				if police and players_inside.size() > 1:
					police.trigger(Types.PoliceTrigger.BLACKLIST_ENTRY, b.global_position, b)
				elif police:
					b.say(tr("NOTIFY_BLACKLIST_WARN"))


func _on_body_exited(b: Node) -> void:
	if b is Player:
		players_inside.erase(b)
		player_exited.emit(b)


func lot_anchors() -> Array:
	var out: Array = []
	_collect(self, out)
	return out


func _collect(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is LotAnchor:
			out.append(c)
		_collect(c, out)


func marker(name: String) -> Node3D:
	return find_child(name, true, false) as Node3D
