extends SceneTree

var failures: Array[String] = []
var endpoint_mode := "accept_all"
var blocked_endpoint := Vector2i(-999, -999)
var accepted: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("LOGISTICS TEST: " + message)


func _endpoint(cell: Vector2i, item: Dictionary, _source_direction: int, source_lane: int) -> bool:
	if endpoint_mode == "reject_all":
		return false
	if endpoint_mode == "reject_ore" and str(item.resource) == RunInventory.ORE:
		return false
	if endpoint_mode == "block_cell" and cell == blocked_endpoint:
		return false
	accepted.append({"cell": cell, "resource": str(item.resource), "quantity": int(item.quantity), "lane": source_lane, "id": int(item.id)})
	return true


func _advance(network: LogisticsNetwork, seconds: float) -> void:
	for _step in ceili(seconds / GameBalance.LOGISTICS_FIXED_STEP):
		network.step(GameBalance.LOGISTICS_FIXED_STEP, _endpoint)


func _line(length: int) -> LogisticsNetwork:
	var network := LogisticsNetwork.new()
	for x in length:
		network.add_belt(Vector2i(x, 0), 0)
	return network


func _run() -> void:
	_test_two_lanes_and_mixed_order()
	_test_backpressure_and_resume()
	_test_corner_paths()
	_test_side_loading()
	_test_splitter_balance_blocking_and_filter()
	_test_data_hooks()
	if failures.is_empty():
		print("LOGISTICS TEST PASS: two lanes, spacing, backpressure, corners, side-loading, mixed items, splitters, filters, and data hooks")
		quit(0)
	else:
		print("LOGISTICS TEST FAILURES: ", failures)
		quit(1)


func _test_two_lanes_and_mixed_order() -> void:
	accepted.clear()
	endpoint_mode = "accept_all"
	var network := _line(3)
	network.spawn_item(Vector2i.ZERO, 0, RunInventory.ORE)
	network.spawn_item(Vector2i.ZERO, 1, RunInventory.STONE)
	_advance(network, 3.0)
	check(accepted.size() == 2, "Both independent lanes must deliver concurrently")
	check(accepted.any(func(event): return event.resource == RunInventory.ORE and int(event.lane) == 0), "Ore must preserve lane 0")
	check(accepted.any(func(event): return event.resource == RunInventory.STONE and int(event.lane) == 1), "Stone must preserve lane 1")

	accepted.clear()
	network = _line(2)
	network.spawn_item(Vector2i.ZERO, 0, RunInventory.ORE, 1, 0.68)
	network.spawn_item(Vector2i.ZERO, 0, RunInventory.WOOD, 1, 0.36)
	network.spawn_item(Vector2i.ZERO, 0, RunInventory.STONE, 1, 0.04)
	_advance(network, 3.0)
	var order: Array[String] = []
	for event in accepted: order.append(str(event.resource))
	check(order == [RunInventory.ORE, RunInventory.WOOD, RunInventory.STONE], "Mixed resources on one lane must retain identity and order")


func _test_backpressure_and_resume() -> void:
	accepted.clear()
	endpoint_mode = "reject_ore"
	var network := _line(4)
	var ore_spawned := 0
	var stone_spawned := 0
	var rejected_spawns := 0
	for tick in 360:
		if tick % 8 == 0:
			if network.spawn_item(Vector2i.ZERO, 0, RunInventory.ORE).is_empty(): rejected_spawns += 1
			else: ore_spawned += 1
			if not network.spawn_item(Vector2i.ZERO, 1, RunInventory.STONE).is_empty(): stone_spawned += 1
		network.step(GameBalance.LOGISTICS_FIXED_STEP, _endpoint)
	var accepted_stone := accepted.filter(func(event): return event.resource == RunInventory.STONE).size()
	check(rejected_spawns > 0 and network.count_resource(RunInventory.ORE) == ore_spawned, "A blocked lane must fill backward without losing items and eventually block its producer")
	check(accepted_stone > 0 and accepted_stone + network.count_resource(RunInventory.STONE) == stone_spawned, "The other lane must continue while lane 0 is congested")

	endpoint_mode = "accept_all"
	_advance(network, 12.0)
	var accepted_ore := accepted.filter(func(event): return event.resource == RunInventory.ORE).size()
	check(network.count_resource(RunInventory.ORE) == 0 and accepted_ore == ore_spawned, "Clearing downstream blockage must resume the entire chain without duplication")


func _test_corner_paths() -> void:
	accepted.clear()
	endpoint_mode = "reject_all"
	var network := LogisticsNetwork.new()
	network.add_belt(Vector2i(0, 0), 0)
	network.add_belt(Vector2i(1, 0), 1)
	network.add_belt(Vector2i(1, 1), 1)
	network.spawn_item(Vector2i.ZERO, 0, RunInventory.ORE, 1, 0.85)
	network.spawn_item(Vector2i.ZERO, 1, RunInventory.STONE, 1, 0.85)
	_advance(network, 0.5)
	check(network.topology_for(Vector2i(1, 0)) == "CORNER_ES", "East-to-south connectivity must resolve to an automatic corner")
	check(network.lane_items(Vector2i(1, 0), 0).size() == 1 and network.lane_items(Vector2i(1, 0), 1).size() == 1, "Both corner lanes must continue without swapping")
	for lane in 2:
		var item: Dictionary = network.lane_items(Vector2i(1, 0), lane)[0]
		var position_value := network.item_world_position(item, 32.0)
		check(Rect2(32, 0, 32, 32).grow(1.0).has_point(position_value), "Corner interpolation must keep items on a continuous in-tile path")


func _test_side_loading() -> void:
	accepted.clear()
	endpoint_mode = "reject_all"
	var network := LogisticsNetwork.new()
	# The southbound belt is primary. The eastbound branch enters from its
	# right and therefore maps both of its source lanes to destination lane 1.
	network.add_belt(Vector2i(1, 0), 1)
	network.add_belt(Vector2i(1, 1), 1)
	network.add_belt(Vector2i(1, -1), 1)
	network.add_belt(Vector2i(0, 0), 0)
	network.spawn_item(Vector2i(1, -1), 0, RunInventory.ORE, 1, 0.9)
	network.spawn_item(Vector2i(0, 0), 0, RunInventory.WOOD, 1, 0.9)
	network.spawn_item(Vector2i(0, 0), 1, RunInventory.STONE, 1, 0.9)
	_advance(network, 0.8)
	var all_items := network.all_items()
	check(all_items.any(func(item): return item.resource == RunInventory.ORE and int(item.lane) == 0), "Straight input must preserve its destination lane")
	var side_resources: Array[String] = []
	for item in all_items:
		if str(item.resource) in [RunInventory.WOOD, RunInventory.STONE]: side_resources.append(str(item.resource))
	check(RunInventory.WOOD in side_resources and RunInventory.STONE in side_resources, "Side-loaded items must remain present when their deterministic destination lane is busy")
	check(not all_items.any(func(item): return item.resource in [RunInventory.WOOD, RunInventory.STONE] and item.cell != Vector2i(0, 0) and int(item.lane) == 0), "Side-loading must not spill randomly into the independent lane")


func _test_splitter_balance_blocking_and_filter() -> void:
	accepted.clear()
	endpoint_mode = "accept_all"
	var network := LogisticsNetwork.new()
	network.add_belt(Vector2i(0, 0), 0)
	network.add_splitter(Vector2i(1, 0), 0)
	network.add_belt(Vector2i(2, 0), 0)
	network.add_belt(Vector2i(1, 1), 1)
	for resource_id in [RunInventory.ORE, RunInventory.WOOD, RunInventory.STONE, RunInventory.ADVANCED_RESOURCE]:
		network.spawn_item(Vector2i.ZERO, 0, resource_id)
		_advance(network, 2.0)
	var destinations: Array[Vector2i] = []
	for event in accepted: destinations.append(event.cell)
	check(destinations == [Vector2i(3, 0), Vector2i(1, 2), Vector2i(3, 0), Vector2i(1, 2)], "Balanced splitter output must alternate A/B deterministically")

	accepted.clear()
	network = LogisticsNetwork.new()
	network.add_belt(Vector2i(0, 0), 0)
	network.add_splitter(Vector2i(1, 0), 0)
	network.add_belt(Vector2i(2, 0), 0)
	network.add_belt(Vector2i(1, 1), 1)
	network.configure_splitter(Vector2i(1, 0), LogisticsNetwork.OUTPUT_NONE, RunInventory.ORE, LogisticsNetwork.FILTER_STRICT)
	for resource_id in [RunInventory.ORE, RunInventory.WOOD]:
		network.spawn_item(Vector2i.ZERO, 0, resource_id)
		_advance(network, 2.0)
	check(accepted.any(func(event): return event.resource == RunInventory.ORE and event.cell == Vector2i(3, 0)), "Strict filter must send Ore to output A")
	check(accepted.any(func(event): return event.resource == RunInventory.WOOD and event.cell == Vector2i(1, 2)), "Strict filter must send other resources to output B")

	accepted.clear()
	endpoint_mode = "block_cell"
	blocked_endpoint = Vector2i(3, 0)
	network.configure_splitter(Vector2i(1, 0), LogisticsNetwork.OUTPUT_A_PRIORITY, "", LogisticsNetwork.FILTER_STRICT)
	var produced := 0
	for tick in 300:
		if tick % 12 == 0 and not network.spawn_item(Vector2i.ZERO, 0, RunInventory.ORE).is_empty(): produced += 1
		network.step(GameBalance.LOGISTICS_FIXED_STEP, _endpoint)
	check(accepted.any(func(event): return event.cell == Vector2i(1, 2)), "A splitter must keep using output B when priority output A is blocked")
	var retained := network.count_resource(RunInventory.ORE)
	var delivered := accepted.filter(func(event): return event.resource == RunInventory.ORE).size()
	check(retained + delivered == produced, "Splitter blocking must never duplicate or delete items")

	endpoint_mode = "reject_all"
	for tick in 300:
		if tick % 10 == 0 and not network.spawn_item(Vector2i.ZERO, 1, RunInventory.STONE).is_empty(): produced += 1
		network.step(GameBalance.LOGISTICS_FIXED_STEP, _endpoint)
	check(network.item_count() > 0, "When both splitter outputs block, items must remain physical and back up upstream")


func _test_data_hooks() -> void:
	var network := LogisticsNetwork.new()
	check(network.belt_types.standard.speed == GameBalance.STANDARD_BELT_SPEED, "Standard belt speed must come from a data definition")
	network.belt_types["test_fast"] = {"display_name": "Test Fast", "speed": GameBalance.STANDARD_BELT_SPEED * 2.0}
	network.add_belt(Vector2i.ZERO, 0, "test_fast")
	check(is_equal_approx(network.speed_for(Vector2i.ZERO), GameBalance.STANDARD_BELT_SPEED * 2.0), "A future faster belt type must work without changing transport code")
	check(TransportResources.definition(RunInventory.GATLING_AMMO).category == "ammunition", "Stable resource definitions must expose display/category/texture hooks")
