extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("FACTORY CAMERA TEST: " + message)


func _inside_camera_bounds(factory: FactoryWorld) -> bool:
	var zoom_value := factory.camera_controller.current_zoom
	var scaled_map := Vector2(FactoryWorld.MAP_CELLS * FactoryWorld.CELL) * zoom_value
	var position_value := factory.position
	var x_valid := absf(position_value.x - (FactoryWorld.VIEW_SIZE.x - scaled_map.x) * 0.5) <= 1.0 if scaled_map.x <= FactoryWorld.VIEW_SIZE.x else position_value.x <= 0.0 and position_value.x >= FactoryWorld.VIEW_SIZE.x - scaled_map.x - 1.0
	var y_valid := absf(position_value.y - (FactoryWorld.VIEW_SIZE.y - scaled_map.y) * 0.5) <= 1.0 if scaled_map.y <= FactoryWorld.VIEW_SIZE.y else position_value.y <= 0.0 and position_value.y >= FactoryWorld.VIEW_SIZE.y - scaled_map.y - 1.0
	return x_valid and y_valid


func _run() -> void:
	var packed: PackedScene = load("res://game/Main.tscn")
	var game = packed.instantiate()
	root.add_child(game)
	await process_frame
	game._start_run()
	await process_frame

	var factory: FactoryWorld = game.factory_world
	var camera: FactoryCameraController = factory.camera_controller
	var inventory: RunInventory = game.inventory
	var ui_scale_before: Vector2 = game.factory_inventory_ui.get_global_transform().get_scale()
	var engineer_before := factory.engineer_position
	check(is_equal_approx(camera.current_zoom, 1.0) and factory.scale == Vector2.ONE, "A new run must begin at the normal factory zoom")
	check(camera.min_zoom == GameBalance.FACTORY_CAMERA_MIN_ZOOM and camera.max_zoom == GameBalance.FACTORY_CAMERA_MAX_ZOOM, "Camera limits must come from centralized balance data")

	var cursor := FactoryWorld.VIEW_SIZE * 0.5 + Vector2(90.0, -45.0)
	var world_under_cursor := factory.to_local(cursor)
	var wheel_up := InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	wheel_up.position = cursor
	factory._unhandled_input(wheel_up)
	check(is_equal_approx(camera.target_zoom, 1.0 + GameBalance.FACTORY_CAMERA_ZOOM_STEP), "Mouse wheel up must request one configured zoom-in step")
	factory._update_camera(0.01)
	check(camera.current_zoom > 1.0 and camera.current_zoom < camera.target_zoom, "Factory zoom must smooth toward its target")
	for _index in 10:
		factory._update_camera(0.05)
	var world_after_zoom := factory.to_local(cursor)
	check(is_equal_approx(camera.current_zoom, camera.target_zoom), "Smoothed zoom must converge to the requested value")
	check(world_under_cursor.distance_to(world_after_zoom) <= 2.0, "The world point under the cursor must remain approximately stable while zooming")
	check(factory.scale == Vector2.ONE * camera.current_zoom and game.factory_inventory_ui.get_global_transform().get_scale() == ui_scale_before, "World zoom must not scale CanvasLayer inventory/quickbar UI")
	check(factory.engineer_position == engineer_before and factory.active_controls, "Zoom must not move or disable the engineer")

	for _index in 20:
		camera.request_zoom(1, cursor, factory.to_local(cursor))
	factory._update_camera(0.0, true)
	check(is_equal_approx(camera.current_zoom, GameBalance.FACTORY_CAMERA_MAX_ZOOM), "Repeated zoom-in must stop at the maximum")
	check(_inside_camera_bounds(factory), "Maximum zoom must remain inside factory-map bounds")
	for _index in 30:
		camera.request_zoom(-1, cursor, factory.to_local(cursor))
	factory._update_camera(0.0, true)
	check(is_equal_approx(camera.current_zoom, GameBalance.FACTORY_CAMERA_MIN_ZOOM), "Repeated zoom-out must stop at the minimum")
	check(_inside_camera_bounds(factory), "Maximum zoom-out must remain inside factory-map bounds")

	camera.reset()
	factory._update_camera(0.0, true)
	var position_before_pan := factory.position
	camera.begin_pan()
	camera.pan_by(Vector2(96.0, 48.0))
	factory._update_camera()
	camera.end_pan()
	check(camera.pan_offset != Vector2.ZERO and factory.position != position_before_pan, "Middle-mouse camera panning must offset the view independently of the engineer")
	check(factory.engineer_position == engineer_before and _inside_camera_bounds(factory), "Panning must preserve engineer position and camera bounds")

	var belt_cell := Vector2i(30, 22)
	check(factory.logistics.add_belt(belt_cell, 0, "standard", RunInventory.BELT), "A Belt should exist for zoomed interaction alignment testing")
	var lane_zero_point := factory.logistics.lane_path_points(belt_cell, 0, float(FactoryWorld.CELL), 12)[6]
	var lane_one_point := factory.logistics.lane_path_points(belt_cell, 1, float(FactoryWorld.CELL), 12)[6]
	check(factory.logistics.nearest_lane(belt_cell, lane_zero_point, float(FactoryWorld.CELL)) == 0 and factory.logistics.nearest_lane(belt_cell, lane_one_point, float(FactoryWorld.CELL)) == 1, "Clicked Belt geometry must resolve deterministically to the nearest physical lane")

	camera.target_zoom = 1.6
	factory._update_camera(0.0, true)
	inventory.set_amount(RunInventory.ORE, 5)
	factory.select_inventory_item(RunInventory.ORE)
	factory.engineer_position = factory._cell_center(belt_cell)
	factory._update_camera(0.0, true)
	var lane_one_screen := factory.to_global(lane_one_point)
	var lane_click := InputEventMouseButton.new()
	lane_click.button_index = MOUSE_BUTTON_LEFT
	lane_click.pressed = true
	lane_click.position = lane_one_screen
	factory._unhandled_input(lane_click)
	check(inventory.amount(RunInventory.ORE) == 4 and factory.logistics.lane_items(belt_cell, 1).size() == 1 and factory.logistics.lane_items(belt_cell, 0).is_empty(), "Zoomed click placement must remain aligned and insert onto the clicked physical lane")
	var inserted: Dictionary = factory.logistics.lane_items(belt_cell, 1)[0]
	factory.engineer_position = factory.logistics.item_world_position(inserted, float(FactoryWorld.CELL))
	check(factory.pickup_nearby_transport_item() and inventory.amount(RunInventory.ORE) == 5, "Zoomed Belt interaction must preserve exact insertion/pickup symmetry")

	if failures.is_empty():
		print("FACTORY CAMERA TEST PASS: smooth bounded cursor zoom, independent pan, screen-space UI, aligned placement, and physical lane clicks")
		quit(0)
	else:
		print("FACTORY CAMERA TEST FAILURES: ", failures)
		quit(1)
