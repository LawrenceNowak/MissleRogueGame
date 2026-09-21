class_name WeaponWorkshop
extends RefCounted

signal weapon_fabricated(item_id: String, quantity: int)

var inventory: RunInventory
var research: ResearchState


func setup(shared_inventory: RunInventory, shared_research: ResearchState) -> void:
	inventory = shared_inventory
	research = shared_research


func is_recipe_known(recipe_id: String) -> bool:
	var recipe := WeaponRecipes.definition(recipe_id)
	return not recipe.is_empty() and research.has_blueprint(str(recipe.required_blueprint))


func can_fabricate(recipe_id: String) -> bool:
	if not is_recipe_known(recipe_id):
		return false
	var recipe := WeaponRecipes.definition(recipe_id)
	var transaction := {}
	for item_id in Dictionary(recipe.inputs):
		transaction[str(item_id)] = -int(recipe.inputs[item_id])
	transaction[str(recipe.output_item_id)] = int(recipe.output_quantity)
	return inventory.can_apply_transaction(transaction)


func fabricate(recipe_id: String) -> bool:
	if not is_recipe_known(recipe_id):
		return false
	var recipe := WeaponRecipes.definition(recipe_id)
	var transaction := {}
	for item_id in Dictionary(recipe.inputs):
		transaction[str(item_id)] = -int(recipe.inputs[item_id])
	transaction[str(recipe.output_item_id)] = int(recipe.output_quantity)
	if not inventory.apply_transaction(transaction):
		return false
	weapon_fabricated.emit(str(recipe.output_item_id), int(recipe.output_quantity))
	return true
