class_name ItemCatalog
extends RefCounted

const WOOD := "wood"
const STONE := "stone"
const ORE := "ore"
const ADVANCED_RESOURCE := "advanced_resource"
const MG_AMMO := "mg_ammo"
const MISSILE := "missile"
const BELT := "belt"
const SPLITTER := "splitter"
const MINING_DRILL := "mining_drill"
const AMMO_FACTORY := "ammo_factory"
const MISSILE_FACTORY := "missile_factory"
const STORAGE := "storage"
const MISSILE_LAUNCHER := "missile_launcher"

static var _definitions: Dictionary = {}


static func definition(item_id: String) -> ItemDefinition:
	_ensure_definitions()
	if _definitions.has(item_id):
		return _definitions[item_id]
	return ItemDefinition.new().setup(item_id, item_id.replace("_", " ").capitalize(), ItemDefinition.Category.UTILITY, 99, false, Color.WHITE, false, "", "Unregistered prototype item.")


static func has(item_id: String) -> bool:
	_ensure_definitions()
	return _definitions.has(item_id)


static func all_ids() -> Array[String]:
	_ensure_definitions()
	var result: Array[String] = []
	for item_id in _definitions:
		result.append(str(item_id))
	return result


static func item_id_for_placement(placement_id: String) -> String:
	_ensure_definitions()
	for item_id_value in _definitions:
		var item_id := str(item_id_value)
		var item: ItemDefinition = _definitions[item_id]
		if item.placeable and item.placement_definition == placement_id:
			return item_id
	return ""


static func category_name(category: ItemDefinition.Category) -> String:
	return ItemDefinition.Category.keys()[int(category)].capitalize()


static func _ensure_definitions() -> void:
	if not _definitions.is_empty():
		return
	_register(WOOD, "Wood", ItemDefinition.Category.RESOURCE, 99, true, Color("#92d06d"), false, "", "Salvaged timber used for construction.")
	_register(STONE, "Stone", ItemDefinition.Category.RESOURCE, 99, true, Color("#c1b8aa"), false, "", "Common construction stone.")
	_register(ORE, "Ore", ItemDefinition.Category.RESOURCE, 99, true, Color("#72d6a0"), false, "", "Metal-bearing ore used by research and factories.")
	_register(ADVANCED_RESOURCE, "Energy Crystal", ItemDefinition.Category.COMPONENT, 20, true, Color("#c58cff"), false, "", "A rare component suitable for guidance research.")
	_register(MG_AMMO, "MG Ammo Crate", ItemDefinition.Category.AMMUNITION, 500, true, Color("#ffd166"), false, "", "Ammunition for the Basic Machine Gun.", GameBalance.AMMO_FACTORY_OUTPUT)
	_register(MISSILE, "Missile", ItemDefinition.Category.AMMUNITION, 12, true, Color("#79d8ff"), false, "", "A missile round; launchers are fabricated separately.")
	_register(BELT, "Conveyor Belt", ItemDefinition.Category.BUILDING, 100, false, Color("#8db7c9"), true, "belt", "A placeable standard two-lane conveyor segment.")
	_register(SPLITTER, "Splitter", ItemDefinition.Category.BUILDING, 20, false, Color("#67a7c8"), true, "splitter", "A configurable two-output belt junction.")
	_register(MINING_DRILL, "Mining Drill", ItemDefinition.Category.BUILDING, 10, false, Color("#e0b36b"), true, "drill", "Extracts Ore from an exposed deposit during defense.")
	_register(AMMO_FACTORY, "MG Ammo Factory", ItemDefinition.Category.BUILDING, 10, false, Color("#ffd166"), true, "ammo_factory", "Turns Ore packets into MG ammunition crates.")
	_register(MISSILE_FACTORY, "Missile Factory", ItemDefinition.Category.BUILDING, 10, false, Color("#79d8ff"), true, "missile_factory", "Turns Ore packets into missiles.")
	_register(STORAGE, "Storage", ItemDefinition.Category.BUILDING, 10, false, Color("#d7c7ae"), true, "storage", "Finite physical packet storage.")
	_register(MISSILE_LAUNCHER, "Missile Launcher", ItemDefinition.Category.WEAPON, 5, false, Color("#50b8d8"), true, "missile_launcher", "A fabricated launcher that links to the shared defense-front weapon.")


static func _register(item_id: String, item_name: String, item_category: ItemDefinition.Category, stack_limit: int, transportable: bool, color: Color, placeable: bool, placement_id: String, description: String, transport_quantity := 1) -> void:
	_definitions[item_id] = ItemDefinition.new().setup(item_id, item_name, item_category, stack_limit, transportable, color, placeable, placement_id, description, transport_quantity)
