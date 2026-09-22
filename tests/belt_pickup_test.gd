extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("BELT PICKUP TEST: " + message)


func _find_open_belt_cell(factory: FactoryWorld, start: Vector2i) -> Vector2i:
	for y_offset in 8:
		for x_offset in 8:
			var cell := start + Vector2i(x_offset, y_offset)
			if not factory.logistics.cell_occupied(cell):
				return cell
	return start


func _item_with_id(logistics: LogisticsNetwork, item_id: int) -> Dictionary:
	for item in logistics.all_items():
		if int(item.id) == item_id:
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

	check(not factory.simulation_active and factory.active_controls, "Preparation must pause logistics while leaving deliberate engineer interaction available")
	check(is_equal_approx(GameBalance.BELT_PICKUP_RADIUS, 54.0), "Pickup radius must use the centralized 54-pixel balance value")
	var interact_is_e := false
	for event in InputMap.action_get_events("interact"):
		if event is InputEventKey and (event.physical_keycode == KEY_E or event.keycode == KEY_E):
			interact_is_e = true
	check(interact_is_e, "The existing Interact action must remain bound to E")

	var pickup_cell := _find_open_belt_cell(factory, Vector2i(18, 16))
	check(logistics.add_belt(pickup_cell, 0), "Focused pickup belt should be created")
	var lane_zero_ore := logistics.spawn_item(pickup_cell, 0, RunInventory.ORE, 1, 0.50)
	var lane_one_stone := logistics.spawn_item(pickup_cell, 1, RunInventory.STONE, 2, 0.50)
	var lane_one_ore := logistics.spawn_item(pickup_cell, 1, RunInventory.ORE, 1, 0.10)
	check(not lane_zero_ore.is_empty() and not lane_one_stone.is_empty() and not lane_one_ore.is_empty(), "Test packets must occupy both belt lanes")

	quickbar.assign(8, RunInventory.ORE)
	factory.engineer_position = logistics.item_world_position(lane_one_stone, float(FactoryWorld.CELL))
	var count_before_idle := logistics.item_count()
	var stone_before_idle := inventory.amount(RunInventory.STONE)
	await process_frame
	await process_frame
	check(logistics.item_count() == count_before_idle and inventory.amount(RunInventory.STONE) == stone_before_idle, "Standing near a packet must never auto-pick it up")

	var target_stone_id := int(lane_one_stone.id)
	factory.interact()
	check(_item_with_id(logistics, target_stone_id).is_empty(), "One E interaction must remove the exact closest packet")
	check(logistics.item_count() == count_before_idle - 1, "One E interaction must collect only one packet")
	check(inventory.amount(RunInventory.STONE) == stone_before_idle + 2, "Pickup must preserve the packet's exact stable item ID and quantity")
	check(not _item_with_id(logistics, int(lane_zero_ore.id)).is_empty() and not _item_with_id(logistics, int(lane_one_ore.id)).is_empty(), "Non-target packets on either lane must remain physical")

	var ore_before := inventory.amount(RunInventory.ORE)
	factory.engineer_position = logistics.item_world_position(lane_zero_ore, float(FactoryWorld.CELL))
	factory.interact()
	check(inventory.amount(RunInventory.ORE) == ore_before + 1, "Collected Ore must enter the authoritative run inventory")
	check(quickbar.item_at(8) == RunInventory.ORE, "Pickup must leave the quickbar as an item-ID shortcut")
	check(str(inventory.amount(RunInventory.ORE)) in game.factory_inventory_ui.slot_buttons[8].text, "Inventory signals must refresh the assigned quickbar quantity")

	var remaining_id := int(lane_one_ore.id)
	var progress_before_gap := float(_item_with_id(logistics, remaining_id).progress)
	logistics.step(0.05, func(_item: Dictionary, _source_direction: int): return false)
	var remaining_after_step := _item_with_id(logistics, remaining_id)
	check(not remaining_after_step.is_empty() and float(remaining_after_step.progress) > progress_before_gap, "A pickup-created lane gap must continue moving normally")

	var persisted_ids: Array[int] = []
	for item in logistics.all_items():
		persisted_ids.append(int(item.id))
	var inventory_before_switch := inventory.amount(RunInventory.ORE)
	game._toggle_preparation_view()
	game._toggle_preparation_view()
	check(inventory.amount(RunInventory.ORE) == inventory_before_switch, "Factory/Defense switching must preserve collected inventory")
	check(logistics.item_count() == persisted_ids.size(), "Factory/Defense switching must preserve remaining physical packets")
	for item_id in persisted_ids:
		check(not _item_with_id(logistics, item_id).is_empty(), "Factory/Defense switching must not respawn or replace packet %d" % item_id)

	var blocked_cell := _find_open_belt_cell(factory, Vector2i(6, 24))
	check(logistics.add_belt(blocked_cell, 0), "Full-inventory pickup belt should be created")
	var blocked_packet := logistics.spawn_item(blocked_cell, 1, RunInventory.STONE, 1, 0.50)
	var stone_at_capacity := inventory.amount(RunInventory.STONE)
	check(inventory.set_capacity(RunInventory.STONE, stone_at_capacity), "Stone capacity should be capped at its current quantity")
	factory.engineer_position = logistics.item_world_position(blocked_packet, float(FactoryWorld.CELL))
	factory.interact()
	check(inventory.amount(RunInventory.STONE) == stone_at_capacity, "A full inventory must not change its quantity")
	check(not _item_with_id(logistics, int(blocked_packet.id)).is_empty(), "A full inventory must leave the exact packet untouched on the belt")

	var rollback_candidate := _item_with_id(logistics, remaining_id)
	var rollback_progress := float(rollback_candidate.progress)
	var taken := logistics.take_item(remaining_id)
	check(not taken.is_empty() and _item_with_id(logistics, remaining_id).is_empty(), "Pickup reservation must remove only the selected packet")
	check(logistics.restore_taken_item(taken), "A failed inventory commit must be able to restore its reserved packet")
	var restored := _item_with_id(logistics, remaining_id)
	check(not restored.is_empty() and int(restored.lane) == 1 and is_equal_approx(float(restored.progress), rollback_progress), "Rollback must restore packet identity, lane, and progress")
	factory.engineer_position = logistics.item_world_position(restored, float(FactoryWorld.CELL))
	factory.interact()
	check(inventory.amount(RunInventory.ORE) == inventory_before_switch + 1, "Repeated deliberate pickups must increment an existing Ore stack exactly once each")
	check(_item_with_id(logistics, remaining_id).is_empty(), "The restored packet must still be collectable exactly once")

	if failures.is_empty():
		print("BELT PICKUP TEST PASS: deliberate E pickup, both-lane targeting, exact transfer, full-inventory safety, rollback, gap motion, UI signals, and view persistence")
		quit(0)
	else:
		print("BELT PICKUP TEST FAILURES: ", failures)
		quit(1)
