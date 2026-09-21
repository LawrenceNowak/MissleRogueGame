class_name WeaponRecipes
extends RefCounted

const MISSILE_LAUNCHER_RECIPE := "missile_launcher"

static var definitions := {
	MISSILE_LAUNCHER_RECIPE: {
		"stable_id": MISSILE_LAUNCHER_RECIPE,
		"display_name": "Fabricate Missile Launcher",
		"required_blueprint": ItemCatalog.MISSILE_LAUNCHER,
		"inputs": {
			ItemCatalog.WOOD: 4,
			ItemCatalog.STONE: 6,
			ItemCatalog.ORE: 8,
		},
		"output_item_id": ItemCatalog.MISSILE_LAUNCHER,
		"output_quantity": 1,
		"fabrication": "instant_preparation",
	},
}


static func definition(recipe_id: String) -> Dictionary:
	return Dictionary(definitions.get(recipe_id, {})).duplicate(true)


static func all_ids() -> Array[String]:
	var result: Array[String] = []
	for recipe_id in definitions:
		result.append(str(recipe_id))
	return result
