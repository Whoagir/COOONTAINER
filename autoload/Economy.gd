extends Node
## Котёл — один счётчик денег пати (§1, §6.3). Только хост меняет; клиенты получают через Net.

signal pot_changed(new_value: int, delta: int, reason: String)
signal broke() # котёл в нуле → уборка (§13)

var pot: int = 0
var min_pot_ever: int = 999999


func set_pot(v: int, reason: String = "sync") -> void:
	var delta := v - pot
	pot = maxi(v, 0)
	min_pot_ever = mini(min_pot_ever, pot)
	pot_changed.emit(pot, delta, reason)
	if pot <= 0 and delta < 0:
		broke.emit()


func add(amount: int, reason: String = "") -> void:
	if not Net.is_host():
		return
	if amount == 0:
		return
	set_pot(pot + amount, reason)
	if amount > 0:
		Game.stat_add("earned_total", amount)
		Game.check_progression() # районы открываются по заработку (§12)
	Net.broadcast_pot(pot, amount, reason)


func can_afford(amount: int) -> bool:
	return pot >= amount


func try_spend(amount: int, reason: String = "") -> bool:
	if not Net.is_host():
		return false
	if pot < amount:
		return false
	set_pot(pot - amount, reason)
	Game.stat_add("spent_total", amount)
	Net.broadcast_pot(pot, -amount, reason)
	return true


## Снять наличку купюрами (§6.3). Спавнит бумажки в мире рядом с позицией.
func withdraw_bills(amount: int, at: Vector3) -> bool:
	if not Net.is_host():
		return false
	if not try_spend(amount, "withdraw"):
		return false
	var ids := Registry.bills_for(amount)
	var i := 0
	for id in ids:
		var pos := at + Vector3(randf_range(-0.15, 0.15), 0.05 * i, randf_range(-0.15, 0.15))
		Net.spawn_item(id, Transform3D(Basis(Vector3.UP, randf() * TAU), pos))
		i += 1
	return true


## Купюра-предмет ушла в котёл (положили на стол / в слот трейлера).
func deposit_bill(body) -> void:
	if not Net.is_host():
		return
	var def: ItemDef = body.def
	if def == null or not def.is_cash():
		return
	add(def.cash_value(), "deposit")
	Net.despawn_item(body.net_id)
