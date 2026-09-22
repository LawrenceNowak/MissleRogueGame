extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("SMOKE TEST: " + message)

func _grant_build_materials(game) -> void:
	game.inventory.set_amount(RunInventory.WOOD, 80)
	game.inventory.set_amount(RunInventory.STONE, 80)
	game.inventory.set_amount(RunInventory.ORE, 40)

func _place(factory: FactoryWorld, kind_id: String, cell: Vector2i, rotation: int = 0) -> bool:
	factory.explored_cells[cell] = true
	factory.select_build(kind_id)
	factory.preview_cell = cell
	factory.build_rotation = rotation
	factory.preview_valid = factory._can_build(kind_id, cell)
	return factory._place_selected_building()


func _clear_factory_cell(factory: FactoryWorld, cell: Vector2i) -> void:
	factory.explored_cells[cell] = true
	factory.mountain_cells.erase(cell)
	for object in factory.world_objects:
		if object.cell == cell:
			object.active = false


func structures_are_paused(structures: Array[Dictionary]) -> bool:
	for structure in structures:
		if bool(structure.active) and str(structure.status) != "PAUSED":
			return false
	return true

func _run() -> void:
	var packed: PackedScene = load("res://game/Main.tscn")
	var game = packed.instantiate()
	root.add_child(game)
	await process_frame
	game.research.completed_projects.clear()
	game.research.unlocked_blueprints.clear()
	game.research.revealed_projects.clear()
	game._start_run()
	await process_frame
	var factory: FactoryWorld = game.factory_world
	check(game.phase == game.Phase.PREPARATION and game.current_wave == 0, "A new run must begin in preparation before wave one")
	check(is_instance_valid(factory) and factory.visible and factory.active_controls, "The separate Factory screen must be active at run start")
	check(factory.stamina == 100, "Engineer stamina must start at 100")
	check(game.weapons.size() == 2 and game.weapons[0].kind == PlayerWeapon.Kind.GATLING and game.weapons[0].unlocked, "The Basic MG must be the unlocked starting weapon")
	check(game.weapons[1].kind == PlayerWeapon.Kind.MISSILE and not game.weapons[1].unlocked, "The Missile Launcher must begin locked")
	check(game.inventory.amount(RunInventory.GATLING_AMMO) == 1000, "Basic MG must start with 1000 rounds")
	check(game.inventory.amount(RunInventory.MISSILE_AMMO) == 3 and game.inventory.capacity(RunInventory.MISSILE_AMMO) == 6, "Missiles must start scarce at 3 of 6")
	check(game.inventory.amount(RunInventory.BELT) == GameBalance.STARTING_BELTS and game.quickbar.item_at(0) == RunInventory.BELT, "Starting placeables must exist in authoritative inventory and quickbar references")
	check(factory.defense_weapons[0] == game.weapons[0] and factory.defense_weapons[1] == game.weapons[1], "Factory front nodes must reference the exact combat weapon objects")
	check(factory.defense_cities[0] == game.cities[0] and factory.defense_front_cell_for_weapon(0).y == FactoryWorld.DEFENSE_FRONT_ROW, "The northern front must reference the exact combat cities and weapons")
	var original_mg_front_cell := factory.defense_front_cell_for_weapon(0)
	game.weapons[0].position.x += 96.0
	check(factory.defense_front_cell_for_weapon(0) != original_mg_front_cell, "Defense weapon placement must update its strategic front position")
	game.weapons[0].position.x -= 96.0

	var initial_fog_count: int = factory.explored_cells.size()
	factory._reveal_around(Vector2i(45, 25), GameBalance.FOG_REVEAL_RADIUS)
	check(factory.explored_cells.size() > initial_fog_count, "Exploration must permanently reveal additional fog cells")
	var tree_index := factory.world_objects.find_custom(func(object): return object.kind == "tree" and object.active)
	var tree: Dictionary = factory.world_objects[tree_index]
	factory.engineer_position = factory._cell_center(tree.cell + Vector2i.RIGHT)
	var stamina_before_tree: int = factory.stamina
	var normal_slot_capacity: int = game.inventory.slot_capacity
	game.inventory.slot_capacity = game.inventory.used_slots()
	factory.interact()
	check(bool(tree.active) and factory.stamina == stamina_before_tree and game.inventory.amount(RunInventory.WOOD) == 0, "Full inventory must leave a gathered resource and stamina untouched")
	game.inventory.slot_capacity = normal_slot_capacity
	factory.interact()
	check(not bool(tree.active) and game.inventory.amount(RunInventory.WOOD) == 3 and factory.stamina == stamina_before_tree - 5, "Chopping a tree must cost 5 stamina and award Wood")
	check(game.quickbar.slots.has(RunInventory.WOOD), "First manual acquisition must auto-assign the item to an empty quickbar shortcut")
	var rock_index := factory.world_objects.find_custom(func(object): return object.kind == "small_rock" and object.active)
	var rock: Dictionary = factory.world_objects[rock_index]
	factory.engineer_position = factory._cell_center(rock.cell + Vector2i.RIGHT)
	var stamina_before_rock: int = factory.stamina
	factory.interact()
	check(not bool(rock.active) and game.inventory.amount(RunInventory.STONE) >= 3 and factory.stamina == stamina_before_rock - 5, "Breaking a small rock must cost 5 stamina and award Stone")
	var ore_index := factory.world_objects.find_custom(func(object): return object.kind == "surface_ore" and object.active)
	var surface_ore: Dictionary = factory.world_objects[ore_index]
	factory.engineer_position = factory._cell_center(surface_ore.cell + Vector2i.RIGHT)
	var ore_before: int = game.inventory.amount(RunInventory.ORE)
	factory.interact()
	check(game.inventory.amount(RunInventory.ORE) == ore_before + 2, "Surface Ore must bootstrap the run inventory")
	var inventory_belt_cell := Vector2i(27, 20)
	_clear_factory_cell(factory, inventory_belt_cell)
	var belts_before: int = game.inventory.amount(RunInventory.BELT)
	factory.select_inventory_item(RunInventory.BELT)
	factory.preview_cell = inventory_belt_cell
	factory.preview_valid = factory._can_build("belt", inventory_belt_cell)
	check(factory._place_selected_building() and game.inventory.amount(RunInventory.BELT) == belts_before - 1, "Valid quickbar placement must consume exactly one physical Belt item")
	var belts_after_valid: int = game.inventory.amount(RunInventory.BELT)
	factory.preview_cell = inventory_belt_cell
	check(not factory._place_selected_building() and game.inventory.amount(RunInventory.BELT) == belts_after_valid, "Invalid placement must not consume the selected inventory item")
	factory.cancel_build()
	var mountain_cell: Vector2i = factory.mountain_cells.keys()[0]
	var mountain_kind := str(factory.mountain_cells[mountain_cell])
	var dig_cost := GameBalance.STAMINA_DIG_HARD if mountain_kind in ["hard", "rare"] else GameBalance.STAMINA_DIG_NORMAL
	var stamina_before_dig: int = factory.stamina
	factory._dig_cell(mountain_cell)
	check(not factory.mountain_cells.has(mountain_cell) and factory.stamina == stamina_before_dig - dig_cost, "Digging must remove mountain collision and spend configured stamina")

	_grant_build_materials(game)
	factory.refill_stamina()
	var mg_front_cell := factory.defense_front_cell_for_weapon(0)
	var missile_front_cell := factory.defense_front_cell_for_weapon(1)
	for x_value in [mg_front_cell.x, missile_front_cell.x]:
		for y_value in range(4, 11):
			_clear_factory_cell(factory, Vector2i(x_value, y_value))
	var mg_drill_cell := Vector2i(mg_front_cell.x, 10)
	var missile_drill_cell := Vector2i(missile_front_cell.x, 10)
	factory.exposed_veins[mg_drill_cell] = "ore"
	factory.vein_amounts[mg_drill_cell] = 100
	factory.exposed_veins[missile_drill_cell] = "ore"
	factory.vein_amounts[missile_drill_cell] = 100
	check(_place(factory, "drill", mg_drill_cell, 3), "MG chain Mining Drill must place on an exposed vein")
	check(_place(factory, "belt", Vector2i(mg_front_cell.x, 9), 3) and _place(factory, "belt", Vector2i(mg_front_cell.x, 8), 3), "MG Ore must use a direct two-lane belt input")
	check(_place(factory, "ammo_factory", Vector2i(mg_front_cell.x, 7), 3), "Ammo Factory must connect directly without an inserter")
	for y_value in [6, 5, 4]: check(_place(factory, "belt", Vector2i(mg_front_cell.x, y_value), 3), "MG output belt segment must place")
	var ammo_factory: Dictionary = factory.structures.back()
	check(_place(factory, "drill", missile_drill_cell, 3), "Missile chain Mining Drill must place on an exposed vein")
	check(_place(factory, "belt", Vector2i(missile_front_cell.x, 9), 3) and _place(factory, "belt", Vector2i(missile_front_cell.x, 8), 3), "Missile Ore must use a direct two-lane belt input")
	check(_place(factory, "missile_factory", Vector2i(missile_front_cell.x, 7), 3), "Missile Factory must connect directly without an inserter")
	for y_value in [6, 5, 4]: check(_place(factory, "belt", Vector2i(missile_front_cell.x, y_value), 3), "Missile output belt segment must place")
	var missile_factory: Dictionary = factory.structures.back()

	for cell in [Vector2i(19, 20), Vector2i(20, 20), Vector2i(21, 20), Vector2i(22, 20), Vector2i(23, 20), Vector2i(22, 21)]: _clear_factory_cell(factory, cell)
	check(_place(factory, "belt", Vector2i(19, 20), 0), "Storage input belt must place")
	check(_place(factory, "storage", Vector2i(20, 20), 0), "Storage must place as a finite physical inventory")
	var physical_storage: Dictionary = factory.structures.back()
	check(_place(factory, "belt", Vector2i(21, 20), 0), "Storage output belt must place")
	check(_place(factory, "splitter", Vector2i(22, 20), 0), "Physical splitter must place")
	check(_place(factory, "belt", Vector2i(23, 20), 0) and _place(factory, "belt", Vector2i(22, 21), 1), "Both splitter outputs must connect directly to belts")
	for _index in GameBalance.STORAGE_PACKET_CAPACITY:
		check(factory._accept_transport_item(physical_storage.cell, {"resource": RunInventory.ADVANCED_RESOURCE, "quantity": 1}, 0, 0), "Storage must accept mixed transported resources until finite capacity")
	check(not factory._accept_transport_item(physical_storage.cell, {"resource": RunInventory.ADVANCED_RESOURCE, "quantity": 1}, 0, 0), "Full Storage must reject an item without deleting it")
	check(game.inventory.capacity(RunInventory.GATLING_AMMO) == GameBalance.BASE_GATLING_CAPACITY and game.inventory.capacity(RunInventory.MISSILE_AMMO) == GameBalance.BASE_MISSILE_CAPACITY, "Physical Storage must not act as an abstract depot-capacity multiplier")

	var wrong_wood := factory.logistics.spawn_item(Vector2i(mg_front_cell.x, 8), 1, RunInventory.WOOD, 1, 0.9, 3)
	check(not wrong_wood.is_empty(), "Mixed resources must be placeable on either physical belt lane")
	var base_machine_time: float = factory._effective_production_time(ammo_factory)
	ammo_factory.modifiers.speed = 2.0
	check(is_equal_approx(factory._effective_production_time(ammo_factory), base_machine_time * 0.5), "Future augment/overclock speed modifiers must change factory speed without changing belt speed")
	ammo_factory.modifiers.speed = 1.0
	ammo_factory.modifiers.output_buffer = 2.0
	check(factory._effective_output_capacity(ammo_factory, GameBalance.MACHINE_OUTPUT_BUFFER_CAPACITY) == GameBalance.MACHINE_OUTPUT_BUFFER_CAPACITY * 2, "Future augments must be able to modify finite machine buffers")
	ammo_factory.modifiers.output_buffer = 1.0
	var paused_timer := float(missile_factory.timer)
	factory.simulation_active = false
	factory.simulate_factory(10.0)
	check(float(missile_factory.timer) == paused_timer, "Factory timers must not advance during preparation")

	game._toggle_preparation_view()
	check(game.phase == game.Phase.PREPARATION and not game.factory_view_active and not factory.simulation_active, "Tab must inspect Defense without starting combat or production")
	game._toggle_preparation_view()
	check(game.factory_view_active and factory.stamina > 0, "Tab must return to the persistent Factory state without changing stamina")
	game.current_wave = 1
	game._begin_preparation(false)
	check(game.research.revealed_projects.has(ResearchProjects.MISSILE_LAUNCHER_DEVELOPMENT), "Returning after wave one must reveal the Guided Weapons project without granting a launcher")
	check(game.inventory.amount(RunInventory.MISSILE_LAUNCHER) == 0 and not game.weapons[1].unlocked, "Research reveal must not create or place a weapon")
	var research_project := ResearchProjects.definition(ResearchProjects.MISSILE_LAUNCHER_DEVELOPMENT)
	var locked_missiles: int = game.inventory.amount(RunInventory.MISSILE_AMMO)
	check(not factory._accept_transport_item(missile_front_cell, {"resource": RunInventory.MISSILE_AMMO, "quantity": 1}, 3, 0) and game.inventory.amount(RunInventory.MISSILE_AMMO) == locked_missiles, "Locked weapon supply endpoints must reject packets without deleting them")
	var ore_before_failed_research: int = game.inventory.amount(RunInventory.ORE)
	game.inventory.set_amount(RunInventory.ADVANCED_RESOURCE, 0)
	check(not game.research.complete_project(ResearchProjects.MISSILE_LAUNCHER_DEVELOPMENT, game.inventory) and game.inventory.amount(RunInventory.ORE) == ore_before_failed_research, "Insufficient research must consume no partial materials")
	for item_id in Dictionary(research_project.costs): game.inventory.set_amount(str(item_id), int(research_project.costs[item_id]))
	check(game.research.complete_project(ResearchProjects.MISSILE_LAUNCHER_DEVELOPMENT, game.inventory), "Configured project costs must complete Missile Launcher research")
	check(game.research.has_blueprint(RunInventory.MISSILE_LAUNCHER) and game.inventory.amount(RunInventory.MISSILE_LAUNCHER) == 0, "Completed research must grant permanent knowledge, not a free launcher")
	var launcher_recipe := WeaponRecipes.definition(WeaponRecipes.MISSILE_LAUNCHER_RECIPE)
	check(not game.workshop.fabricate(WeaponRecipes.MISSILE_LAUNCHER_RECIPE), "Workshop must reject fabrication without the separate per-launcher cost")
	for item_id in Dictionary(launcher_recipe.inputs): game.inventory.set_amount(str(item_id), int(launcher_recipe.inputs[item_id]))
	check(game.workshop.fabricate(WeaponRecipes.MISSILE_LAUNCHER_RECIPE) and game.inventory.amount(RunInventory.MISSILE_LAUNCHER) == 1, "Workshop must fabricate one carried Missile Launcher")
	var launcher_slot: int = game.quickbar.slots.find(RunInventory.MISSILE_LAUNCHER)
	check(launcher_slot >= 0, "First fabricated launcher must be assigned to the first empty quickbar slot")
	game.quickbar.select(launcher_slot)
	factory.preview_cell = missile_front_cell
	factory.preview_valid = factory._can_build("missile_launcher", missile_front_cell)
	check(factory._place_selected_building(), "Fabricated launcher must place only on its defense-front node")
	check(game.inventory.amount(RunInventory.MISSILE_LAUNCHER) == 0 and game.weapons[1].unlocked and factory.defense_front_snapshot(1).weapon == game.weapons[1], "Weapon placement must consume one item and activate the one shared defense/factory weapon identity")
	game._begin_wave(1)
	check(game.phase == game.Phase.DEFENSE and factory.simulation_active and not factory.visible, "Starting a wave must hide Factory controls but activate off-screen simulation")
	var mg_before_production: int = game.inventory.amount(RunInventory.GATLING_AMMO)
	factory.simulate_factory(60.0)
	check(int(factory.production_totals.ore) > 0 and int(factory.production_totals.mg) > 0 and int(factory.production_totals.missiles) > 0, "Both drills and factories must operate through physical off-screen logistics")
	check(game.inventory.amount(RunInventory.GATLING_AMMO) > mg_before_production, "Complete Ore-to-Ammo-to-MG-Depot chain must resupply the actual Basic MG")
	check(game.inventory.amount(RunInventory.MISSILE_AMMO) > 3, "Complete Ore-to-Missile-to-Silo chain must resupply the actual Missile Launcher")
	check(factory.logistics.count_resource(RunInventory.WOOD) == 1, "Wrong machine ingredients must remain physically present and create lane congestion")
	var buffered_ore := int(ammo_factory.input_buffer.get(RunInventory.ORE, 0))
	while buffered_ore < GameBalance.MACHINE_INPUT_BUFFER_CAPACITY:
		check(factory._accept_transport_item(ammo_factory.cell, {"resource": RunInventory.ORE, "quantity": 1}, 3, 0), "Direct machine port must accept valid Ore until input capacity")
		buffered_ore += 1
	check(not factory._accept_transport_item(ammo_factory.cell, {"resource": RunInventory.ORE, "quantity": 1}, 3, 0), "Full machine input must reject Ore and create upstream backpressure")
	var missiles_before_wrong_depot: int = game.inventory.amount(RunInventory.MISSILE_AMMO)
	check(not factory._accept_transport_item(mg_front_cell, {"resource": RunInventory.MISSILE_AMMO, "quantity": 1}, 3, 0) and game.inventory.amount(RunInventory.MISSILE_AMMO) == missiles_before_wrong_depot, "MG Depot must reject Missile items without deleting or converting them")
	var preserved_advanced := factory.logistics.count_resource(RunInventory.ADVANCED_RESOURCE) + Array(physical_storage.storage_inventory).size()
	check(preserved_advanced == GameBalance.STORAGE_PACKET_CAPACITY, "Storage and splitter backpressure must preserve every buffered item")
	check(factory.visible == false and factory.logistics.item_count() > 0, "Two-lane logistics must continue while the Factory view is hidden")
	var front_snapshot := factory.defense_front_snapshot(0)
	check(front_snapshot.weapon == game.weapons[0] and int(front_snapshot.ammo) == game.inventory.amount(RunInventory.GATLING_AMMO), "Factory and Defense views must expose one synchronized weapon identity and ammo count")

	game.weapons[0].aim_position = Vector2(600, 240)
	game.weapons[0].cooldown_left = 0.0
	var mg_before_shot: int = game.inventory.amount(RunInventory.GATLING_AMMO)
	check(game._attempt_fire_weapon(game.weapons[0]) and game.inventory.amount(RunInventory.GATLING_AMMO) == mg_before_shot - 1, "Basic MG manual fire must consume exactly one round")
	check(int(factory.defense_front_snapshot(0).ammo) == mg_before_shot - 1, "Factory-front MG ammo must update immediately when that exact combat gun fires")
	game.weapons[1].aim_position = Vector2(620, 220)
	game.weapons[1].cooldown_left = 0.0
	var missiles_before_shot: int = game.inventory.amount(RunInventory.MISSILE_AMMO)
	check(game._attempt_fire_weapon(game.weapons[1]) and game.inventory.amount(RunInventory.MISSILE_AMMO) == missiles_before_shot - 1, "A missile launch must consume one scarce missile")

	game.inventory.set_amount(RunInventory.GATLING_AMMO, game.inventory.capacity(RunInventory.GATLING_AMMO))
	factory.simulate_factory(300.0)
	var buffered_before_clear: int = Array(ammo_factory.output_buffer).size()
	check(buffered_before_clear == GameBalance.MACHINE_OUTPUT_BUFFER_CAPACITY and str(ammo_factory.status) == "OUTPUT FULL", "Blocked depot and full belts must fill the finite factory output buffer and stop production")
	var mg_output_lanes: Dictionary = {}
	for transport_item in factory.logistics.all_items():
		if str(transport_item.resource) == RunInventory.GATLING_AMMO: mg_output_lanes[int(transport_item.lane)] = true
	check(mg_output_lanes.has(0) and mg_output_lanes.has(1), "Machine output AUTO mode must alternate physical crates across available lanes")
	check(Array(factory.structures[0].output_buffer).size() == GameBalance.DRILL_OUTPUT_BUFFER_CAPACITY or str(factory.structures[0].status) in ["OUTPUT FULL", "RUNNING — EXTRACTING"], "Backpressure must propagate toward the extractor without deleting Ore")
	game.inventory.set_amount(RunInventory.GATLING_AMMO, 0)
	factory.simulate_factory(5.0)
	check(game.inventory.amount(RunInventory.GATLING_AMMO) >= GameBalance.AMMO_FACTORY_OUTPUT, "A physically waiting MG crate must restore combat ammunition during the same wave")
	check(Array(ammo_factory.output_buffer).size() <= buffered_before_clear, "Clearing depot capacity must resume downstream transport and factory output")

	game.spawn_queue.clear()
	game.spawn_finished = true
	for enemy in game.enemies.duplicate():
		if is_instance_valid(enemy): enemy.queue_free()
	game.enemies.clear()
	game.phase = game.Phase.DEFENSE
	game._check_wave_clear()
	check(game.phase == game.Phase.PREPARATION and factory.visible and not factory.simulation_active and factory.stamina == 100, "Wave clear must freeze production, return to Factory, and restore stamina")
	check(structures_are_paused(factory.structures), "Preparation must report machines paused without advancing logistics")
	factory.stamina = 1
	factory._spend_stamina(1, "TEST EXHAUSTION")
	await process_frame
	check(factory.transition_locked and game.incoming_timer > 0.0 and game.pending_wave_number == 2, "Zero stamina must trigger exactly one incoming-attack transition")
	var transition_time: float = game.incoming_timer
	factory._request_wave("exhausted")
	check(game.incoming_timer <= transition_time and game.pending_wave_number == 2, "Exhaustion must not queue duplicate wave starts")
	game.incoming_timer = 0.001
	await process_frame
	await process_frame
	check(game.phase == game.Phase.DEFENSE and game.current_wave == 2, "The incoming warning must hand control to exactly the pending defense wave")

	game._start_run()
	await process_frame
	check(game.phase == game.Phase.PREPARATION, "New Run must return to preparation")
	check(game.factory_world.structures.is_empty(), "New Run must clear Factory construction")
	check(game.factory_world.logistics.item_count() == 0, "New Run must clear physical transport items")
	check(game.inventory.amount(RunInventory.GATLING_AMMO) == GameBalance.STARTING_GATLING_AMMO, "New Run must reset Basic MG ammunition")
	check(game.research.has_blueprint(RunInventory.MISSILE_LAUNCHER) and game.inventory.amount(RunInventory.MISSILE_LAUNCHER) == 0 and not game.weapons[1].unlocked, "New Run must retain blueprint knowledge but reset fabricated and placed launchers")
	check(game.factory_world.explored_cells.size() == initial_fog_count, "New Run must reset fog to the starting reveal")
	for cycle_wave in range(1, 4):
		game._begin_wave(cycle_wave)
		game.factory_world.simulate_factory(1.0)
		game.spawn_queue.clear()
		game.spawn_finished = true
		for cycle_enemy in game.enemies.duplicate():
			if is_instance_valid(cycle_enemy): cycle_enemy.queue_free()
		game.enemies.clear()
		game._check_wave_clear()
		check(game.phase == game.Phase.PREPARATION and not game.factory_world.simulation_active, "Cycle %d must return directly to preparation without a reward modal" % cycle_wave)
	game._begin_wave(10)
	var boss = game._spawn_enemy("boss")
	check(int(boss.max_hp) == 800, "The existing wave-ten boss must retain configured HP")
	boss.take_damage(99999.0)
	await process_frame
	check(game.phase == game.Phase.VICTORY, "Destroying the Missile Carrier must still trigger victory")
	game._start_run()
	await process_frame
	for city in game.cities: city.take_damage(999.0)
	await process_frame
	check(game.phase == game.Phase.DEFEAT, "All five destroyed cities must still trigger defeat")
	game.persistent_components = 7
	game._save_persistent()
	var reloaded_game = packed.instantiate()
	root.add_child(reloaded_game)
	await process_frame
	check(reloaded_game.persistent_components == 7, "Persistent components must survive a save reload")
	check(reloaded_game.research.has_blueprint(RunInventory.MISSILE_LAUNCHER), "Completed weapon blueprint knowledge must survive the existing profile save")
	check(GameBalance.wave_definition(1).size() == 5, "Wave one must retain its five-threat teaching wave")
	check(GameBalance.wave_definition(4).any(func(entry): return entry.kind == "mirv"), "Wave four must still introduce MIRVs")
	if failures.is_empty():
		print("SMOKE TEST PASS: inventory quickbar, research/fabrication, two-screen logistics, combat, boss, defeat, and reset")
		quit(0)
	else:
		print("SMOKE TEST FAILURES: ", failures)
		quit(1)
