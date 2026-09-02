extends StaticBody3D
## Табличка «ПРОДАЁТСЯ ДОМ» у трейлера (§1, §17.3): [E] — купить за Game.HOUSE_PRICE → титры → песочница.

var _label: Label3D


func _ready() -> void:
	collision_layer = Types.L_TRIGGER
	collision_mask = 0
	if get_child_count() == 0:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.6, 1.2, 0.1)
		cs.shape = bs
		cs.position.y = 1.4
		add_child(cs)
		var post := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.08, 1.6, 0.08)
		post.mesh = pm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.5, 0.35, 0.2)
		post.material_override = m
		post.position.y = 0.8
		add_child(post)
		var board := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.6, 1.0, 0.06)
		board.mesh = bm
		var m2 := StandardMaterial3D.new()
		m2.albedo_color = Color(0.95, 0.95, 0.9)
		board.material_override = m2
		board.position.y = 1.4
		add_child(board)
	_label = Label3D.new()
	_label.font_size = 64
	_label.pixel_size = 0.004
	_label.modulate = Color(0.8, 0.1, 0.1)
	_label.outline_size = 6
	_label.position = Vector3(0, 1.45, 0.04)
	_label.width = 380
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_label)
	_refresh()
	Game.win_reached.connect(_refresh)


func _refresh() -> void:
	if Game.save.get("house_bought", false):
		_label.text = tr("HOUSE_SOLD")
	else:
		_label.text = tr("HOUSE_FOR_SALE") % Game.HOUSE_PRICE


func interact(player: Player) -> void:
	if Game.save.get("house_bought", false):
		player.say(tr("HOUSE_ALREADY"))
		return
	if Game.try_buy_house():
		AudioBus.play_at("fanfare", global_position, 4.0)
	else:
		AudioBus.play_at("buzzer", global_position, 0.0)


func interact_hint(_p: Player) -> String:
	if Game.save.get("house_bought", false):
		return tr("HOUSE_SOLD")
	return tr("HOUSE_BUY_HINT") % Game.HOUSE_PRICE
