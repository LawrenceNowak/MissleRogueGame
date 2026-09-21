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

func _run() -> void:
	var packed: PackedScene = load("res://game/Main.tscn")
	var game = packed.instantiate()
	root.add_child(game)
	await process_frame
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

	var initial_fog_count: int = factory.explored_cells.size()
	factory._reveal_around(Vector2i(45, 25), GameBalance.FOG_REVEAL_RADIUS)
	check(factory.explored_cells.size() > initial_fog_count, "Exploration must permanently reveal additional fog cells")
	var tree_index := factory.world_objects.find_custom(func(object): return object.kind == "tree" and object.active)
	var tree: Dictionary = factory.world_objects[tree_index]
	factory.engineer_position = factory._cell_center(tree.cell + Vector2i.RIGHT)
	var stamina_before_tree: int = factory.stamina
	factory.interact()
	check(not bool(tree.active) and game.inventory.amount(RunInventory.WOOD) == 3 and factory.stamina == stamina_before_tree - 5, "Chopping a tree must cost 5 stamina and award Wood")
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
	var mountain_cell: Vector2i = factory.mountain_cells.keys()[0]
	var mountain_kind := str(factory.mountain_cells[mountain_cell])
	var dig_cost := GameBalance.STAMINA_DIG_HARD if mountain_kind in ["hard", "rare"] else GameBalance.STAMINA_DIG_NORMAL
	var stamina_before_dig: int = factory.stamina
	factory._dig_cell(mountain_cell)
	check(not factory.mountain_cells.has(mountain_cell) and factory.stamina == stamina_before_dig - dig_cost, "Digging must remove mountain collision and spend configured stamina")

	_grant_build_materials(game)
	factory.refill_stamina()
	check(_place(factory, "storage", Vector2i(35, 26)), "Storage must place on explored open terrain")
	check(game.inventory.capacity(RunInventory.GATLING_AMMO) == 2000 and game.inventory.capacity(RunInventory.MISSILE_AMMO) == 10, "Storage must expand both ammunition capacities")
	var drill_cell := Vector2i(40, 20)
	factory.exposed_veins[drill_cell] = "ore"
	factory.vein_amounts[drill_cell] = 12
	for x in range(40, 45): factory.explored_cells[Vector2i(x, 20)] = true
	check(_place(factory, "drill", drill_cell, 0), "Mining Drill must place on an exposed vein")
	check(_place(factory, "belt", Vector2i(41, 20), 0), "First directional belt must place")
	check(_place(factory, "belt", Vector2i(42, 20), 0), "Second directional belt must place")
	check(_place(factory, "ammo_factory", Vector2i(43, 20)), "Ammo Factory must place at the belt output")
	check(_place(factory, "missile_factory", Vector2i(44, 20)), "Missile Factory must place on open terrain")
	var missile_factory: Dictionary = factory.structures.back()
	missile_factory.ore_buffer = 2
	var paused_timer := float(missile_factory.timer)
	factory.simulation_active = false
	factory.simulate_factory(10.0)
	check(float(missile_factory.timer) == paused_timer, "Factory timers must not advance during preparation")

	game._toggle_preparation_view()
	check(game.phase == game.Phase.PREPARATION and not game.factory_view_active and not factory.simulation_active, "Tab must inspect Defense without starting combat or production")
	game._toggle_preparation_view()
	check(game.factory_view_active and factory.stamina > 0, "Tab must return to the persistent Factory state without changing stamina")
	game._begin_wave(1)
	check(game.phase == game.Phase.DEFENSE and factory.simulation_active and not factory.visible, "Starting a wave must hide Factory controls but activate off-screen simulation")
	var mg_before_production: int = game.inventory.amount(RunInventory.GATLING_AMMO)
	factory.simulate_factory(GameBalance.DRILL_INTERVAL + 0.1)
	factory.simulate_factory(GameBalance.BELT_STEP_TIME + 0.02)
	factory.simulate_factory(GameBalance.BELT_STEP_TIME + 0.02)
	var ammo_factory: Dictionary = factory.structures[factory.structures.size() - 2]
	check(int(ammo_factory.ore_buffer) >= 1, "Belts must logically deliver mined Ore to the Ammo Factory")
	factory.simulate_factory(GameBalance.MISSILE_FACTORY_INTERVAL + 0.1)
	check(game.inventory.amount(RunInventory.GATLING_AMMO) >= mg_before_production + 125, "Ammo Factory must create MG rounds during combat")
	check(game.inventory.amount(RunInventory.MISSILE_AMMO) == 4, "Missile Factory must consume 2 Ore over 25 active-combat seconds for one missile")

	game.weapons[0].aim_position = Vector2(600, 240)
	game.weapons[0].cooldown_left = 0.0
	var mg_before_shot: int = game.inventory.amount(RunInventory.GATLING_AMMO)
	check(game._attempt_fire_weapon(game.weapons[0]) and game.inventory.amount(RunInventory.GATLING_AMMO) == mg_before_shot - 1, "Basic MG manual fire must consume exactly one round")
	game.credits = 100
	game.current_wave = 1
	game._buy_gatling()
	check(game.weapons[1].unlocked and game.credits == 40, "Missile Launcher must unlock after wave one for 60 Credits")
	game.weapons[1].aim_position = Vector2(620, 220)
	game.weapons[1].cooldown_left = 0.0
	var missiles_before_shot: int = game.inventory.amount(RunInventory.MISSILE_AMMO)
	check(game._attempt_fire_weapon(game.weapons[1]) and game.inventory.amount(RunInventory.MISSILE_AMMO) == missiles_before_shot - 1, "A missile launch must consume one scarce missile")

	game.spawn_queue.clear()
	game.spawn_finished = true
	for enemy in game.enemies.duplicate():
		if is_instance_valid(enemy): enemy.queue_free()
	game.enemies.clear()
	game.phase = game.Phase.DEFENSE
	game._check_wave_clear()
	check(game.phase == game.Phase.PREPARATION and factory.visible and not factory.simulation_active and factory.stamina == 100, "Wave clear must freeze production, return to Factory, and restore stamina")
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
	check(game.phase == game.Phase.PREPARATION and game.factory_world.structures.is_empty() and game.inventory.amount(RunInventory.GATLING_AMMO) == 1000, "New Run must reset Factory construction, ammunition, and phase")
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
	check(GameBalance.wave_definition(1).size() == 5, "Wave one must retain its five-threat teaching wave")
	check(GameBalance.wave_definition(4).any(func(entry): return entry.kind == "mirv"), "Wave four must still introduce MIRVs")
	if failures.is_empty():
		print("SMOKE TEST PASS: two-screen exploration, stamina, logistics, combat production, arsenal, boss, defeat, and reset")
		quit(0)
	else:
		print("SMOKE TEST FAILURES: ", failures)
		quit(1)
