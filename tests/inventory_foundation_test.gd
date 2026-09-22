extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("INVENTORY FOUNDATION TEST: " + message)


func _clear_cell(factory: FactoryWorld, cell: Vector2i) -> void:
	factory.explored_cells[cell] = true
	factory.mountain_cells.erase(cell)
	factory.exposed_veins.erase(cell)
	for object in factory.world_objects:
		if object.cell == cell:
			object.active = false


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

	check(ItemCatalog.definition(RunInventory.WOOD).stable_id == "wood" and ItemCatalog.definition(RunInventory.STONE).stable_id == "stone" and ItemCatalog.definition(RunInventory.ORE).stable_id == "ore" and ItemCatalog.definition(RunInventory.BELT).stable_id == "belt", "Wood, Stone, Ore, and Belt must use stable shared definitions")
	check(inventory.slot_capacity == GameBalance.PLAYER_INVENTORY_SLOTS and inventory.get_quantity(RunInventory.BELT) == GameBalance.STARTING_BELTS, "Run inventory must use centralized capacity and starting Belt configuration")
	check(quickbar.slots.size() == 10 and quickbar.item_at(0) == RunInventory.BELT, "Factory quickbar must contain ten item-ID shortcuts")
	var stamina_before_inventory_ui: int = factory.stamina
	game.factory_inventory_ui.toggle_inventory()
	check(game.factory_inventory_ui.inventory_panel.visible and not factory.active_controls and factory.stamina == stamina_before_inventory_ui, "Opening inventory must pause engineer input without spending stamina")
	game.factory_inventory_ui.toggle_inventory()
	check(not game.factory_inventory_ui.inventory_panel.visible and factory.active_controls, "Closing inventory must restore factory controls")

	var tree_index := factory.world_objects.find_custom(func(object): return object.kind == "tree" and object.active)
	var tree: Dictionary = factory.world_objects[tree_index]
	var normal_capacity: int = inventory.slot_capacity
	inventory.slot_capacity = inventory.used_slots()
	factory.engineer_position = factory._cell_center(tree.cell + Vector2i.RIGHT)
	var stamina_before_full: int = factory.stamina
	factory.interact()
	check(bool(tree.active) and inventory.get_quantity(RunInventory.WOOD) == 0 and factory.stamina == stamina_before_full, "Full inventory must leave the gatherable and stamina untouched")
	inventory.slot_capacity = normal_capacity

	factory._harvest_object(tree_index)
	var rock_indices: Array[int] = []
	for index in factory.world_objects.size():
		if str(factory.world_objects[index].kind) == "small_rock" and bool(factory.world_objects[index].active):
			rock_indices.append(index)
			if rock_indices.size() == 2: break
	var stamina_before_stone: int = factory.stamina
	factory._harvest_object(rock_indices[0])
	factory._harvest_object(rock_indices[1])
	check(inventory.get_quantity(RunInventory.STONE) == 6 and factory.stamina == stamina_before_stone - GameBalance.STAMINA_SMALL_ROCK * 2, "Two manual rock gathers must stack Stone and retain stamina costs")
	var ore_index := factory.world_objects.find_custom(func(object): return object.kind == "surface_ore" and object.active)
	factory._harvest_object(ore_index)
	check(inventory.get_quantity(RunInventory.WOOD) == 3 and inventory.get_quantity(RunInventory.STONE) == 6 and inventory.get_quantity(RunInventory.ORE) >= 2, "Manual Wood, Stone, and Ore yields must enter one authoritative inventory")
	check(quickbar.slots.has(RunInventory.WOOD) and quickbar.slots.has(RunInventory.STONE) and quickbar.slots.has(RunInventory.ORE), "First acquisition of each resource must auto-fill separate empty quickbar slots")

	var belts_before_assignment: int = inventory.get_quantity(RunInventory.BELT)
	game.factory_inventory_ui.inventory_panel.visible = true
	game.factory_inventory_ui._on_inventory_item_pressed(RunInventory.BELT)
	game.factory_inventory_ui._on_slot_pressed(9)
	game.factory_inventory_ui.close_inventory()
	check(quickbar.item_at(9) == RunInventory.BELT and inventory.get_quantity(RunInventory.BELT) == belts_before_assignment, "Manual quickbar assignment must move only the Belt shortcut")
	var select_ten := InputEventAction.new()
	select_ten.action = "quickbar_slot_10"
	select_ten.pressed = true
	game._input(select_ten)
	check(quickbar.selected_slot == 9 and quickbar.selected_item_id() == RunInventory.BELT and factory.selected_item_id == RunInventory.BELT and factory.build_kind == "belt", "Factory key 0 must select Belt and activate existing Belt placement")

	inventory.set_amount(RunInventory.BELT, 3)
	factory.refill_stamina()
	var placement_cells := [Vector2i(27, 20), Vector2i(27, 21), Vector2i(27, 22)]
	for cell in placement_cells: _clear_cell(factory, cell)
	var stamina_before_builds: int = factory.stamina
	for index in placement_cells.size():
		factory.preview_cell = placement_cells[index]
		factory.preview_valid = factory._can_build("belt", factory.preview_cell)
		check(factory._place_selected_building(), "Inventory-backed Belt %d must place through the existing grid" % (index + 1))
		check(inventory.get_quantity(RunInventory.BELT) == 2 - index, "Each successful Belt placement must consume exactly one Belt")
		if index == 0:
			var quantity_before_invalid: int = inventory.get_quantity(RunInventory.BELT)
			factory.preview_cell = placement_cells[0]
			check(not factory._place_selected_building() and inventory.get_quantity(RunInventory.BELT) == quantity_before_invalid, "Invalid occupied-cell placement must consume nothing")
	check(factory.stamina == stamina_before_builds - GameBalance.STAMINA_BELT * 3, "Inventory-backed Belt placement must preserve construction stamina cost")
	check(quickbar.item_at(9) == RunInventory.BELT and inventory.get_quantity(RunInventory.BELT) == 0, "Belt shortcut must remain assigned at zero quantity")
	factory.preview_cell = Vector2i(27, 23)
	_clear_cell(factory, factory.preview_cell)
	check(not factory._can_build("belt", factory.preview_cell) and not factory._place_selected_building() and inventory.get_quantity(RunInventory.BELT) == 0, "Zero Belts must show invalid placement and never create a negative stack")
	check(game.factory_inventory_ui.slot_buttons[9].modulate.a < 1.0, "Zero-count Belt shortcut must be visibly unavailable")

	var stone_before_switch: int = inventory.get_quantity(RunInventory.STONE)
	var shortcuts_before_switch := quickbar.slots.duplicate()
	game._toggle_preparation_view()
	game._toggle_preparation_view()
	check(inventory.get_quantity(RunInventory.STONE) == stone_before_switch and quickbar.slots == shortcuts_before_switch and quickbar.selected_item_id() == RunInventory.BELT, "Factory/Defense view switching must preserve inventory, shortcuts, and selection")
	check(factory.build_kind == "belt", "Returning to Factory must restore the selected Belt placement adapter")
	game.weapons[1].unlocked = true
	game._begin_wave(1)
	var select_defense_two := InputEventAction.new()
	select_defense_two.action = "select_slot_2"
	select_defense_two.pressed = true
	game._input(select_defense_two)
	check(game.selected_weapon_index == 1, "Defense mode must retain its existing weapon-slot controls")

	game._start_run()
	await process_frame
	check(game.inventory.get_quantity(RunInventory.STONE) == 0 and game.inventory.get_quantity(RunInventory.WOOD) == 0 and game.inventory.get_quantity(RunInventory.BELT) == GameBalance.STARTING_BELTS, "New Run must reset carried resources and Belt quantity")
	check(game.quickbar.slots.size() == 10 and game.quickbar.item_at(0) == RunInventory.BELT and game.quickbar.selected_slot == -1, "New Run must reset quickbar assignment and selection state")
	for slot_index in QuickbarState.SLOT_COUNT:
		check(InputMap.has_action("quickbar_slot_%d" % (slot_index + 1)), "Every factory quickbar slot must have an InputMap action")
	check(InputMap.has_action("inventory_toggle"), "Inventory panel must use its named InputMap action")

	if failures.is_empty():
		print("INVENTORY FOUNDATION TEST PASS: gathering, capacity, quickbar, Belt consumption, screen switching, and run reset")
		quit(0)
	else:
		print("INVENTORY FOUNDATION TEST FAILURES: ", failures)
		quit(1)
