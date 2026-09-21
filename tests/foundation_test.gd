extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("FOUNDATION TEST: " + message)


func _run() -> void:
	_test_item_catalog_and_inventory()
	_test_quickbar_references()
	_test_belt_pickup()
	_test_research_and_workshop()
	_test_input_map()
	if failures.is_empty():
		print("FOUNDATION TEST PASS: unified items, atomic inventory, quickbar references, belt pickup, research persistence, and fabrication")
		quit(0)
	else:
		print("FOUNDATION TEST FAILURES: ", failures)
		quit(1)


func _test_item_catalog_and_inventory() -> void:
	var ore := ItemCatalog.definition(ItemCatalog.ORE)
	check(ore.stable_id == RunInventory.ORE and ore.transportable, "Ore must have one stable transport/inventory definition")
	check(TransportResources.definition(RunInventory.ORE).stable_id == ore.stable_id, "Belt rendering must resolve the authoritative ItemDefinition")
	var inventory := RunInventory.new()
	inventory.slot_capacity = 1
	check(inventory.add_exact(RunInventory.STONE, ore.max_stack), "A stack should fit within configured capacity")
	check(not inventory.add_exact(RunInventory.ORE, 1), "A different item must not overfill the stack inventory")
	check(inventory.amount(RunInventory.ORE) == 0, "Rejected additions must not partially mutate inventory")
	check(inventory.remove(RunInventory.STONE, ore.max_stack), "Centralized removal must remove an exact valid quantity")
	check(not inventory.remove(RunInventory.STONE, 1) and inventory.amount(RunInventory.STONE) == 0, "Inventory quantities must never become negative")


func _test_quickbar_references() -> void:
	var inventory := RunInventory.new()
	inventory.reset()
	var quickbar := QuickbarState.new()
	quickbar.setup(inventory)
	check(quickbar.item_at(0) == RunInventory.BELT and quickbar.item_at(1) == RunInventory.MINING_DRILL, "Starting placeables should use quickbar shortcuts")
	check(inventory.add_exact(RunInventory.STONE, 3), "Stone pickup should enter inventory")
	var stone_slot := quickbar.slots.find(RunInventory.STONE)
	check(stone_slot >= 0, "A first-time pickup should fill the first empty quickbar slot")
	check(inventory.remove(RunInventory.STONE, 3), "Stone should be removable through inventory state")
	check(quickbar.item_at(stone_slot) == RunInventory.STONE and inventory.get_quantity(RunInventory.STONE) == 0, "A zero-count shortcut must remain assigned and read inventory quantity")
	quickbar.assign(5, RunInventory.BELT)
	check(quickbar.item_at(0).is_empty() and quickbar.item_at(5) == RunInventory.BELT and inventory.amount(RunInventory.BELT) == GameBalance.STARTING_BELTS, "Quickbar reassignment must move only the reference, never items")


func _test_belt_pickup() -> void:
	var inventory := RunInventory.new()
	inventory.reset()
	var factory := FactoryWorld.new()
	root.add_child(factory)
	factory.setup(inventory)
	var cell := Vector2i(10, 10)
	check(factory.logistics.add_belt(cell, 0), "Pickup test belt should be created")
	var packet := factory.logistics.spawn_item(cell, 1, RunInventory.ORE, 1, 0.5)
	factory.engineer_position = factory.logistics.item_world_position(packet, float(FactoryWorld.CELL))
	check(factory.pickup_nearby_transport_item(), "Deliberate interaction should find a nearby lane item")
	check(factory.logistics.item_count() == 0 and inventory.amount(RunInventory.ORE) == 1, "Pickup must remove the exact physical packet and add the same item ID once")
	check(inventory.set_capacity(RunInventory.ORE, 1), "Test inventory should accept a finite Ore capacity")
	var blocked_packet := factory.logistics.spawn_item(cell, 0, RunInventory.ORE, 1, 0.5)
	check(factory.pickup_nearby_transport_item(), "Full-inventory interaction should still identify the packet")
	check(factory.logistics.item_count() == 1 and int(factory.logistics.all_items()[0].id) == int(blocked_packet.id) and inventory.amount(RunInventory.ORE) == 1, "A full inventory must leave the exact belt packet untouched")
	factory.queue_free()


func _test_research_and_workshop() -> void:
	var inventory := RunInventory.new()
	inventory.reset()
	var research := ResearchState.new()
	research.begin_run()
	var project_id := ResearchProjects.MISSILE_LAUNCHER_DEVELOPMENT
	check(research.status(project_id, inventory) == ResearchState.ProjectStatus.HIDDEN, "Engineering project must start hidden")
	check(research.reveal_project(project_id), "Wave/discovery hooks must be able to reveal a project")
	var before := inventory.amount(RunInventory.ORE)
	check(not research.complete_project(project_id, inventory) and inventory.amount(RunInventory.ORE) == before, "Insufficient research completion must consume nothing")
	var research_costs: Dictionary = ResearchProjects.definition(project_id).costs
	check(inventory.add_many(research_costs), "Prototype research materials should enter inventory")
	check(research.complete_project(project_id, inventory), "Complete finite project costs should unlock knowledge")
	check(research.has_blueprint(RunInventory.MISSILE_LAUNCHER) and inventory.amount(RunInventory.MISSILE_LAUNCHER) == 0, "Research must unlock a blueprint, not grant a free weapon")
	var workshop := WeaponWorkshop.new()
	workshop.setup(inventory, research)
	var recipe_id := WeaponRecipes.MISSILE_LAUNCHER_RECIPE
	var missiles_before_fabrication := inventory.amount(RunInventory.MISSILE_AMMO)
	check(not workshop.fabricate(recipe_id), "Fabrication without per-copy materials must fail atomically")
	var fabrication_costs: Dictionary = WeaponRecipes.definition(recipe_id).inputs
	check(inventory.add_many(fabrication_costs), "Prototype fabrication materials should enter inventory")
	check(workshop.fabricate(recipe_id) and inventory.amount(RunInventory.MISSILE_LAUNCHER) == 1, "Workshop must exchange one configured material set for one physical launcher")
	check(inventory.amount(RunInventory.MISSILE_AMMO) == missiles_before_fabrication, "Fabricating a launcher must not include free ammunition")
	check(not workshop.fabricate(recipe_id) and inventory.amount(RunInventory.MISSILE_LAUNCHER) == 1, "Known blueprints must not create free duplicate weapons")
	var saved := research.export_persistent()
	var reloaded := ResearchState.new()
	reloaded.import_persistent(saved)
	check(reloaded.has_blueprint(RunInventory.MISSILE_LAUNCHER), "Permanent blueprint knowledge must survive state reload")
	inventory.reset()
	check(inventory.amount(RunInventory.MISSILE_LAUNCHER) == 0 and reloaded.has_blueprint(RunInventory.MISSILE_LAUNCHER), "New Run must reset physical weapons while retaining blueprint knowledge")


func _test_input_map() -> void:
	check(InputMap.has_action("interact") and InputMap.has_action("inventory_toggle"), "Factory interaction and inventory must use named InputMap actions")
	for slot_index in QuickbarState.SLOT_COUNT:
		check(InputMap.has_action("quickbar_slot_%d" % (slot_index + 1)), "All ten quickbar slots must have InputMap actions")
