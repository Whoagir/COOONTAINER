class_name PotSlot
extends Area3D
## Щель котла в трейлере (§6.3): купюра внутрь → число в котле. [E] → снять $20 бумажками.
## Такие же слоты могут стоять у скупщика/казино (deposit_only).

@export var withdraw_amount: int = 20
@export var deposit_only: bool = false

var _body: StaticBody3D


func _ready() -> void:
	collision_layer = Types.L_TRIGGER
	collision_mask = Types.L_ITEM
	monitoring = true
	body_entered.connect(_on_body_entered)
	# статик-коллайдер для луча взгляда (Area тоже ловится, но пусть будет твёрдый корпус)
	if get_node_or_null("Body") == null:
		_body = StaticBody3D.new()
		_body.name = "Body"
		_body.collision_layer = Types.L_TRIGGER
		_body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.5, 0.5, 0.3)
		cs.shape = bs
		_body.add_child(cs)
		add_child(_body)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.5, 0.5, 0.3)
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.2, 0.55, 0.3)
		mi.material_override = m
		_body.add_child(mi)
		var slot := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.3, 0.03, 0.05)
		slot.mesh = sm
		var m2 := StandardMaterial3D.new()
		m2.albedo_color = Color(0.05, 0.05, 0.05)
		slot.material_override = m2
		slot.position = Vector3(0, 0.15, 0.16)
		_body.add_child(slot)
		var lbl := Label3D.new()
		lbl.text = "$"
		lbl.font_size = 96
		lbl.pixel_size = 0.005
		lbl.position = Vector3(0, 0.02, 0.16)
		lbl.modulate = Color(1, 0.9, 0.4)
		_body.add_child(lbl)
		_body.set_script(load("res://world/trailer/PotSlotBody.gd"))
		_body.slot = self


func _on_body_entered(b: Node) -> void:
	if not Net.is_host():
		return
	if b is ItemBody and b.def.is_cash() and b.held_by.is_empty():
		AudioBus.play_at("coin", global_position, 0.0)
		Economy.deposit_bill(b)
		Game.stat_add("bills_deposited")


func interact(player: Player) -> void:
	if deposit_only:
		return
	if not Economy.withdraw_bills(withdraw_amount, global_position + global_basis.z * 0.5 + Vector3(0, 0.3, 0)):
		player.say(tr("POT_EMPTY"))
	else:
		AudioBus.play_at("cash_register", global_position, 0.0)


func interact_hint(_p: Player) -> String:
	if deposit_only:
		return tr("POT_DEPOSIT_HINT")
	return tr("POT_WITHDRAW_HINT") % withdraw_amount
