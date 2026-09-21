class_name RunInventory
extends RefCounted

signal changed
signal item_changed(item_id: String, quantity: int, delta: int)

const ORE := ItemCatalog.ORE
const MISSILE_AMMO := ItemCatalog.MISSILE
const GATLING_AMMO := ItemCatalog.MG_AMMO
const WOOD := ItemCatalog.WOOD
const STONE := ItemCatalog.STONE
const ADVANCED_RESOURCE := ItemCatalog.ADVANCED_RESOURCE
const BELT := ItemCatalog.BELT
const SPLITTER := ItemCatalog.SPLITTER
const MINING_DRILL := ItemCatalog.MINING_DRILL
const AMMO_FACTORY := ItemCatalog.AMMO_FACTORY
const MISSILE_FACTORY := ItemCatalog.MISSILE_FACTORY
const STORAGE := ItemCatalog.STORAGE
const MISSILE_LAUNCHER := ItemCatalog.MISSILE_LAUNCHER

var amounts: Dictionary = {}
var capacities: Dictionary = {}
var slot_capacity := GameBalance.PLAYER_INVENTORY_SLOTS


func reset() -> void:
	var previous := amounts.duplicate()
	amounts = {
		WOOD: 0,
		STONE: 0,
		ORE: GameBalance.STARTING_ORE,
		ADVANCED_RESOURCE: 0,
		MISSILE_AMMO: GameBalance.STARTING_MISSILE_AMMO,
		GATLING_AMMO: GameBalance.STARTING_GATLING_AMMO,
		BELT: GameBalance.STARTING_BELTS,
		MINING_DRILL: GameBalance.STARTING_DRILLS,
	}
	capacities = {
		MISSILE_AMMO: GameBalance.BASE_MISSILE_CAPACITY,
		GATLING_AMMO: GameBalance.BASE_GATLING_CAPACITY,
	}
	_emit_differences(previous)


func amount(item_id: String) -> int:
	return int(amounts.get(item_id, 0))


func get_quantity(item_id: String) -> int:
	return amount(item_id)


func capacity(item_id: String) -> int:
	return int(capacities.get(item_id, ItemCatalog.definition(item_id).max_stack * slot_capacity))


func used_slots() -> int:
	return _used_slots_for(amounts)


func free_space(item_id: String) -> int:
	var current := amount(item_id)
	var stack_limit := ItemCatalog.definition(item_id).max_stack
	var current_slots := ceili(float(current) / float(stack_limit)) if current > 0 else 0
	var partial_space := current_slots * stack_limit - current
	var unoccupied_slots := maxi(0, slot_capacity - used_slots())
	return mini(capacity(item_id) - current, partial_space + unoccupied_slots * stack_limit)


func can_add(item_id: String, quantity: int) -> bool:
	return quantity >= 0 and can_apply_transaction({item_id: quantity})


func can_add_batch(item_id: String, quantity: int) -> bool:
	return can_add(item_id, quantity)


func add(item_id: String, quantity: int) -> int:
	return quantity if add_exact(item_id, quantity) else 0


func add_exact(item_id: String, quantity: int) -> bool:
	return quantity >= 0 and apply_transaction({item_id: quantity})


func can_remove(item_id: String, quantity: int) -> bool:
	return quantity >= 0 and amount(item_id) >= quantity


func can_consume(item_id: String, quantity: int) -> bool:
	return can_remove(item_id, quantity)


func remove(item_id: String, quantity: int) -> bool:
	return quantity >= 0 and apply_transaction({item_id: -quantity})


func consume(item_id: String, quantity: int) -> bool:
	return remove(item_id, quantity)


func can_add_many(items: Dictionary) -> bool:
	var transaction := {}
	for item_id in items:
		transaction[str(item_id)] = int(items[item_id])
	return can_apply_transaction(transaction)


func add_many(items: Dictionary) -> bool:
	var transaction := {}
	for item_id in items:
		transaction[str(item_id)] = int(items[item_id])
	return apply_transaction(transaction)


func can_remove_many(costs: Dictionary) -> bool:
	var transaction := {}
	for item_id in costs:
		transaction[str(item_id)] = -int(costs[item_id])
	return can_apply_transaction(transaction)


func remove_many(costs: Dictionary) -> bool:
	var transaction := {}
	for item_id in costs:
		transaction[str(item_id)] = -int(costs[item_id])
	return apply_transaction(transaction)


func can_apply_transaction(deltas: Dictionary) -> bool:
	var proposed := amounts.duplicate()
	for item_id_value in deltas:
		var item_id := str(item_id_value)
		var next_quantity := int(proposed.get(item_id, 0)) + int(deltas[item_id_value])
		if next_quantity < 0 or next_quantity > capacity(item_id):
			return false
		proposed[item_id] = next_quantity
	return _used_slots_for(proposed) <= slot_capacity


func apply_transaction(deltas: Dictionary) -> bool:
	if not can_apply_transaction(deltas):
		return false
	var previous := amounts.duplicate()
	for item_id_value in deltas:
		var item_id := str(item_id_value)
		amounts[item_id] = amount(item_id) + int(deltas[item_id_value])
	_emit_differences(previous)
	return true


func set_amount(item_id: String, quantity: int) -> bool:
	if quantity < 0:
		return false
	return apply_transaction({item_id: quantity - amount(item_id)})


func set_capacity(item_id: String, quantity: int) -> bool:
	if quantity < amount(item_id) or quantity < 0:
		return false
	capacities[item_id] = quantity
	changed.emit()
	return true


func stack_entries(include_zero := false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item_id in ItemCatalog.all_ids():
		var quantity := amount(item_id)
		if include_zero or quantity > 0:
			result.append({"item_id": item_id, "quantity": quantity, "definition": ItemCatalog.definition(item_id)})
	return result


func _used_slots_for(values: Dictionary) -> int:
	var result := 0
	for item_id_value in values:
		var quantity := int(values[item_id_value])
		if quantity <= 0:
			continue
		var stack_limit := ItemCatalog.definition(str(item_id_value)).max_stack
		result += ceili(float(quantity) / float(stack_limit))
	return result


func _emit_differences(previous: Dictionary) -> void:
	var ids := {}
	for item_id in previous: ids[item_id] = true
	for item_id in amounts: ids[item_id] = true
	for item_id_value in ids:
		var item_id := str(item_id_value)
		var old_quantity := int(previous.get(item_id, 0))
		var new_quantity := amount(item_id)
		if old_quantity != new_quantity:
			item_changed.emit(item_id, new_quantity, new_quantity - old_quantity)
	changed.emit()
