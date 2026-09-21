class_name RunInventory
extends RefCounted

signal changed

const ORE := "ore"
const MISSILE_AMMO := "missile"
const GATLING_AMMO := "mg_ammo"
const WOOD := "wood"
const STONE := "stone"
const ADVANCED_RESOURCE := "advanced_resource"

var amounts: Dictionary = {}
var capacities: Dictionary = {}


func reset() -> void:
	amounts = {
		WOOD: 0,
		STONE: 0,
		ORE: GameBalance.STARTING_ORE,
		ADVANCED_RESOURCE: 0,
		MISSILE_AMMO: GameBalance.STARTING_MISSILE_AMMO,
		GATLING_AMMO: GameBalance.STARTING_GATLING_AMMO,
	}
	capacities = {
		WOOD: 999,
		STONE: 999,
		ORE: 9999,
		ADVANCED_RESOURCE: 99,
		MISSILE_AMMO: GameBalance.BASE_MISSILE_CAPACITY,
		GATLING_AMMO: GameBalance.BASE_GATLING_CAPACITY,
	}
	changed.emit()


func amount(resource_id: String) -> int:
	return int(amounts.get(resource_id, 0))


func capacity(resource_id: String) -> int:
	return int(capacities.get(resource_id, 0))


func free_space(resource_id: String) -> int:
	return maxi(0, capacity(resource_id) - amount(resource_id))


func can_consume(resource_id: String, quantity: int) -> bool:
	return quantity >= 0 and amount(resource_id) >= quantity


func consume(resource_id: String, quantity: int) -> bool:
	if not can_consume(resource_id, quantity):
		return false
	amounts[resource_id] = amount(resource_id) - quantity
	changed.emit()
	return true


func can_add_batch(resource_id: String, quantity: int) -> bool:
	return quantity >= 0 and free_space(resource_id) >= quantity


func add(resource_id: String, quantity: int) -> int:
	var accepted := mini(maxi(quantity, 0), free_space(resource_id))
	if accepted <= 0:
		return 0
	amounts[resource_id] = amount(resource_id) + accepted
	changed.emit()
	return accepted


func set_amount(resource_id: String, quantity: int) -> void:
	amounts[resource_id] = clampi(quantity, 0, capacity(resource_id))
	changed.emit()


func set_capacity(resource_id: String, quantity: int) -> void:
	capacities[resource_id] = maxi(0, quantity)
	amounts[resource_id] = mini(amount(resource_id), capacity(resource_id))
	changed.emit()
