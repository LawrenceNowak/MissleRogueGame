extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("WORLD INVENTORY TEST: " + message)


func _clear_cell(factory: FactoryWorld, cell: Vector2i) -> void:
	factory.explored_cells[cell] = true
	factory.mountain_cells.erase(cell)
	factory.exposed_veins.erase(cell)
	factory.vein_amounts.erase(cell)
	for object in factory.world_objects:
		if object.cell == cell:
			object.active = false


func _place_inventory_building(factory: FactoryWorld, item_id: String, cell: Vector2i, clear_cell := true) -> bool:
	if clear_cell:
		_clear_cell(factory, cell)
	factory.select_inventory_item(item_id)
	factory.preview_cell = cell
	factory.preview_valid = factory._can_build(factory.build_kind, cell)
	return factory._place_selected_building()


func _item_on_cell(logistics: LogisticsNetwork, cell: Vector2i, item_id: String) -> Dictionary:
	for item in logistics.all_items():
		if item.cell == cell and str(item.resource) == item_id:
			return item
	return {}


func _run() -> void:
	var packed: PackedScene = load("res://game/Main.tscn")
	var game = packed.instantiate()
	root.add_child(game)
	await process_frame
	game._start_run()
	await process_frame

	var factory: FactoryWorld = game.factory_world
	var inventory: RunInventory = game.inventory
	var quickbar: QuickbarState = game.quickbar
	var logistics: LogisticsNetwork = factory.logistics

	check(ItemCatalog.item_id_for_placement("belt") == RunInventory.BELT and ItemCatalog.item_id_for_placement("drill") == RunInventory.MINING_DRILL, "Placement definitions must map back to stable inventory item IDs")
	check(ItemCatalog.definition(RunInventory.ORE).transportable and ItemCatalog.definition(RunInventory.ORE).transport_quantity == 1, "Ore must remain a one-unit transportable item")
	check(ItemCatalog.definition(RunInventory.GATLING_AMMO).transport_quantity == GameBalance.AMMO_FACTORY_OUTPUT, "MG ammunition must use its configured crate packet quantity")

	var reversible_belt_cell := Vector2i(10, 10)
	inventory.set_amount(RunInventory.BELT, 3)
	check(_place_inventory_building(factory, RunInventory.BELT, reversible_belt_cell), "An inventory Belt should place through the existing construction system")
	check(inventory.amount(RunInventory.BELT) == 2 and str(factory.belts[reversible_belt_cell].source_item_id) == RunInventory.BELT, "Belt placement must consume one item and record its source item ID")
	check(factory.dismantle_at(reversible_belt_cell), "An empty placed Belt should dismantle")
	check(not factory.belts.has(reversible_belt_cell) and inventory.amount(RunInventory.BELT) == 3, "Dismantling must return exactly one Belt")
	var belt_quickbar_slot := quickbar.slots.find(RunInventory.BELT)
	check(belt_quickbar_slot >= 0 and "3" in game.factory_inventory_ui.slot_buttons[belt_quickbar_slot].text, "Dismantle inventory signals must refresh the Belt quickbar quantity")
	check(_place_inventory_building(factory, RunInventory.BELT, reversible_belt_cell) and factory.dismantle_at(reversible_belt_cell), "Belt placement and dismantling should be repeatable")
	check(inventory.amount(RunInventory.BELT) == 3, "Repeated Belt place/remove cycles must neither duplicate nor delete items")

	check(_place_inventory_building(factory, RunInventory.BELT, reversible_belt_cell), "A Belt should place for full-inventory testing")
	var belt_quantity_after_place := inventory.amount(RunInventory.BELT)
	check(inventory.set_capacity(RunInventory.BELT, belt_quantity_after_place), "Belt capacity should be capped at its current quantity")
	check(not factory.dismantle_at(reversible_belt_cell), "Dismantling must be blocked when the returned Belt cannot fit")
	check(factory.belts.has(reversible_belt_cell) and inventory.amount(RunInventory.BELT) == belt_quantity_after_place, "Full-inventory dismantling must leave both world and inventory unchanged")
	check(inventory.set_capacity(RunInventory.BELT, 100), "Belt capacity should be restored for later checks")

	var occupied_packet := logistics.spawn_item(reversible_belt_cell, 0, RunInventory.ORE, 1, 0.4)
	check(not occupied_packet.is_empty(), "Ore should be physically placed on the occupied-Belt test segment")
	check(not factory.dismantle_at(reversible_belt_cell), "An occupied Belt must not dismantle")
	check(factory.belts.has(reversible_belt_cell) and not _item_on_cell(logistics, reversible_belt_cell, RunInventory.ORE).is_empty(), "Occupied-Belt blocking must preserve the exact transported item")
	factory.engineer_position = logistics.item_world_position(occupied_packet, float(FactoryWorld.CELL))
	check(factory.pickup_nearby_transport_item(), "The occupied packet should remain collectable through normal Belt pickup")
	check(factory.dismantle_at(reversible_belt_cell), "The Belt should dismantle after its packet is removed")
	check(inventory.amount(RunInventory.BELT) == 3, "Clearing then dismantling the Belt must return one item")

	var drill_cell := Vector2i(12, 10)
	_clear_cell(factory, drill_cell)
	factory.exposed_veins[drill_cell] = "ore"
	factory.vein_amounts[drill_cell] = 20
	var drill_before := inventory.amount(RunInventory.MINING_DRILL)
	check(_place_inventory_building(factory, RunInventory.MINING_DRILL, drill_cell, false), "A Mining Drill item should place on an exposed deposit")
	var drill = factory._find_structure_at(drill_cell)
	check(drill != null and str(drill.source_item_id) == RunInventory.MINING_DRILL and inventory.amount(RunInventory.MINING_DRILL) == drill_before - 1, "Placed Drill must record and consume its source item")
	check(factory.dismantle_at(drill_cell), "An empty Mining Drill should dismantle safely")
	check(factory._find_structure_at(drill_cell) == null and inventory.amount(RunInventory.MINING_DRILL) == drill_before, "Dismantling the Drill must return the same physical item")

	var storage_cell := Vector2i(14, 10)
	check(inventory.add_exact(RunInventory.STORAGE, 1), "A Storage item should be available for content-safety testing")
	check(_place_inventory_building(factory, RunInventory.STORAGE, storage_cell), "Storage should place from its inventory item")
	var storage: Dictionary = factory._find_structure_at(storage_cell)
	storage.storage_inventory.append({"resource": RunInventory.STONE, "quantity": 2})
	check(not factory.dismantle_at(storage_cell), "Non-empty Storage dismantling must be blocked")
	check(bool(storage.active) and inventory.amount(RunInventory.STORAGE) == 0 and storage.storage_inventory.size() == 1, "Blocked Storage dismantling must preserve the structure and contents")
	storage.storage_inventory.clear()
	check(factory.dismantle_at(storage_cell) and inventory.amount(RunInventory.STORAGE) == 1, "Empty Storage should return its source item")

	var insertion_cell := Vector2i(16, 10)
	check(_place_inventory_building(factory, RunInventory.BELT, insertion_cell), "A Belt should place for manual insertion testing")
	inventory.set_amount(RunInventory.ORE, 5)
	quickbar.assign(8, RunInventory.ORE)
	quickbar.select(8)
	factory.engineer_position = factory._cell_center(insertion_cell)
	var handling_stamina := factory.stamina
	check(factory.selected_item_id == RunInventory.ORE, "Manual insertion must use the existing selected quickbar item")
	check(factory.insert_selected_item_on_belt(insertion_cell), "Selected Ore should insert onto a nearby Belt")
	var inserted_ore := _item_on_cell(logistics, insertion_cell, RunInventory.ORE)
	check(not inserted_ore.is_empty() and int(inserted_ore.quantity) == 1 and inventory.amount(RunInventory.ORE) == 4, "Ore insertion must create one physical packet and remove exactly one inventory unit")
	check("4" in game.factory_inventory_ui.slot_buttons[8].text, "Inventory events must refresh the Ore quickbar quantity after insertion")

	game._toggle_preparation_view()
	game._toggle_preparation_view()
	check(inventory.amount(RunInventory.ORE) == 4 and not _item_on_cell(logistics, insertion_cell, RunInventory.ORE).is_empty(), "Factory/Defense switching must preserve inserted inventory and Belt state")
	factory.engineer_position = logistics.item_world_position(inserted_ore, float(FactoryWorld.CELL))
	check(factory.pickup_nearby_transport_item(), "The manually inserted packet should be collectable through the existing pickup path")
	check(inventory.amount(RunInventory.ORE) == 5 and _item_on_cell(logistics, insertion_cell, RunInventory.ORE).is_empty(), "Insert then pickup must restore inventory without leaving a duplicate packet")
	check("5" in game.factory_inventory_ui.slot_buttons[8].text, "Quickbar must refresh through inventory events after pickup")
	check(factory.dismantle_at(insertion_cell), "The cleared insertion Belt should dismantle")
	check(factory.stamina == handling_stamina, "Insertion, pickup, and dismantling must not add stamina costs")
	game._toggle_preparation_view()
	game._toggle_preparation_view()
	check(not factory.belts.has(insertion_cell) and inventory.amount(RunInventory.ORE) == 5, "Removed structures and packets must not reappear after a view switch")

	var full_belt_cell := Vector2i(18, 10)
	_clear_cell(factory, full_belt_cell)
	check(logistics.add_belt(full_belt_cell, 0, "standard", RunInventory.BELT), "A segment should exist for full-Belt insertion testing")
	check(not logistics.spawn_item(full_belt_cell, 0, RunInventory.STONE, 1, 0.0).is_empty() and not logistics.spawn_item(full_belt_cell, 1, RunInventory.STONE, 1, 0.0).is_empty(), "Both existing lanes should be blocked at their insertion points")
	factory.select_inventory_item(RunInventory.ORE)
	factory.engineer_position = factory._cell_center(full_belt_cell)
	var ore_before_blocked_insert := inventory.amount(RunInventory.ORE)
	var packets_before_blocked_insert := logistics.item_count()
	check(not factory.insert_selected_item_on_belt(full_belt_cell), "A physically full Belt must reject manual insertion")
	check(inventory.amount(RunInventory.ORE) == ore_before_blocked_insert and logistics.item_count() == packets_before_blocked_insert, "Failed insertion must change neither inventory nor physical transport state")

	var belts_before_invalid := inventory.amount(RunInventory.BELT)
	factory.select_inventory_item(RunInventory.BELT)
	check(not factory.insert_selected_item_on_belt(full_belt_cell), "A non-transportable ItemDefinition must be rejected")
	check(inventory.amount(RunInventory.BELT) == belts_before_invalid and logistics.item_count() == packets_before_blocked_insert, "Invalid-item insertion must consume nothing and spawn nothing")
	factory.cancel_build()

	var ammo_cell := Vector2i(20, 10)
	_clear_cell(factory, ammo_cell)
	check(logistics.add_belt(ammo_cell, 0, "standard", RunInventory.BELT), "A segment should exist for batch insertion testing")
	factory.select_inventory_item(RunInventory.GATLING_AMMO)
	factory.engineer_position = factory._cell_center(ammo_cell)
	var ammo_before := inventory.amount(RunInventory.GATLING_AMMO)
	check(factory.insert_selected_item_on_belt(ammo_cell), "A transportable MG ammo crate should insert")
	var ammo_packet := _item_on_cell(logistics, ammo_cell, RunInventory.GATLING_AMMO)
	check(int(ammo_packet.quantity) == GameBalance.AMMO_FACTORY_OUTPUT and inventory.amount(RunInventory.GATLING_AMMO) == ammo_before - GameBalance.AMMO_FACTORY_OUTPUT, "Batch insertion must preserve the ItemDefinition packet quantity")
	factory.engineer_position = logistics.item_world_position(ammo_packet, float(FactoryWorld.CELL))
	factory.pickup_nearby_transport_item()
	check(inventory.amount(RunInventory.GATLING_AMMO) == ammo_before and _item_on_cell(logistics, ammo_cell, RunInventory.GATLING_AMMO).is_empty(), "Batch pickup must symmetrically restore the exact inserted quantity")

	if failures.is_empty():
		print("WORLD INVENTORY TEST PASS: reversible placement, safe dismantle, selected-item Belt insertion, batch quantities, quickbar signals, and view persistence")
		quit(0)
	else:
		print("WORLD INVENTORY TEST FAILURES: ", failures)
		quit(1)
