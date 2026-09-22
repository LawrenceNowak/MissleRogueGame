extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("HOLD PICKUP TEST: " + message)


func _run() -> void:
	Input.action_release("interact")
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
	var pickup_cell := Vector2i(10, 10)
	var far_cell := Vector2i(14, 10)
	check(GameBalance.PICKUP_RADIUS == GameBalance.BELT_PICKUP_RADIUS and GameBalance.PICKUP_RADIUS == 54.0, "Belt and loose-world pickup must share one centralized small radius")
	check(logistics.add_belt(pickup_cell, 0, "standard", RunInventory.BELT) and logistics.add_belt(far_cell, 0, "standard", RunInventory.BELT), "Pickup test Belts should exist")

	var packets := [
		logistics.spawn_item(pickup_cell, 0, RunInventory.ORE, 1, 0.75),
		logistics.spawn_item(pickup_cell, 0, RunInventory.ORE, 1, 0.35),
		logistics.spawn_item(pickup_cell, 1, RunInventory.STONE, 1, 0.65),
		logistics.spawn_item(pickup_cell, 1, RunInventory.STONE, 1, 0.25),
	]
	check(packets.all(func(packet): return not Dictionary(packet).is_empty()), "Both physical lanes should contain valid packets")
	var loose_wood := factory.spawn_loose_pickup(RunInventory.WOOD, 3, factory._cell_center(pickup_cell) + Vector2(2.0, 0.0))
	var far_ore := logistics.spawn_item(far_cell, 0, RunInventory.ORE, 1, 0.5)
	check(not loose_wood.is_empty() and not far_ore.is_empty(), "Loose and distant physical items should be created")
	factory.engineer_position = factory._cell_center(pickup_cell)
	quickbar.assign(8, RunInventory.ORE)

	var belt_count_without_e := logistics.item_count()
	factory._process(0.0)
	check(inventory.amount(RunInventory.ORE) == 0 and inventory.amount(RunInventory.STONE) == 0 and inventory.amount(RunInventory.WOOD) == 0, "Walking or standing over physical items without E must collect nothing")
	check(logistics.item_count() == belt_count_without_e and factory.loose_pickups.size() == 1, "No-E movement must leave Belt and loose-world items physical")
	var nearest := factory._nearest_pickup_candidate()
	check(str(nearest.kind) == "loose" and int(nearest.id) == int(loose_wood.id), "Multiple in-range items must select the nearest candidate deterministically")

	Input.action_press("interact")
	factory._process(0.0)
	check(inventory.amount(RunInventory.ORE) == 2 and inventory.amount(RunInventory.STONE) == 2 and inventory.amount(RunInventory.WOOD) == 3, "One held-E update must collect every eligible in-range packet at exact quantities")
	check(factory.loose_pickups.is_empty(), "Held E must use the same pickup path for loose physical resources")
	check(logistics.item_count() == 1 and int(logistics.all_items()[0].id) == int(far_ore.id), "Far packets must remain while all nearby packets from both lanes are removed exactly once")
	check("2" in game.factory_inventory_ui.slot_buttons[8].text, "Quickbar Ore quantity must update through inventory signals")
	check(logistics.belts.has(pickup_cell) and logistics.belts.has(far_cell), "Held pickup must never dismantle placed Belt structures")

	Input.action_release("interact")
	factory.engineer_position = logistics.item_world_position(far_ore, float(FactoryWorld.CELL))
	factory._process(0.0)
	check(inventory.amount(RunInventory.ORE) == 2 and logistics.item_count() == 1, "Releasing E must stop pickup immediately even when another packet enters range")
	Input.action_press("interact")
	factory._process(0.0)
	check(inventory.amount(RunInventory.ORE) == 3 and logistics.item_count() == 0, "Holding E again must collect the newly encountered packet once")

	check(inventory.set_capacity(RunInventory.STONE, inventory.amount(RunInventory.STONE)), "Stone inventory should be capped at its current quantity")
	var blocked_belt_stone := logistics.spawn_item(far_cell, 0, RunInventory.STONE, 1, 0.5)
	var blocked_loose_stone := factory.spawn_loose_pickup(RunInventory.STONE, 1, factory.engineer_position + Vector2(3.0, 0.0))
	factory._process(0.0)
	check(inventory.amount(RunInventory.STONE) == 2, "Full inventory must not change while E is held")
	check(not blocked_belt_stone.is_empty() and logistics.item_count() == 1 and not blocked_loose_stone.is_empty() and factory.loose_pickups.size() == 1, "Full-inventory Belt and loose items must both remain exactly where they were")
	Input.action_release("interact")

	factory.engineer_position = factory._cell_center(FactoryWorld.COMMAND_CELL)
	factory.interact()
	check(game.engineering_ui.visible, "Contextual E interaction at the Command Center must remain available")

	Input.action_release("interact")
	if failures.is_empty():
		print("HOLD PICKUP TEST PASS: no-E safety, continuous nearest-first pickup, two lanes, loose items, release behavior, full inventory, and interaction priority")
		quit(0)
	else:
		print("HOLD PICKUP TEST FAILURES: ", failures)
		quit(1)
