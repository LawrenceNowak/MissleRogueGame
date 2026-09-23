extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("SETTLEMENT FOUNDATION TEST: " + message)

func _run() -> void:
	var packed: PackedScene = load("res://game/Main.tscn")
	var game = packed.instantiate()
	root.add_child(game)
	await process_frame
	game._start_run()
	await process_frame
	check(game.phase == game.Phase.DEFENSE and game.current_wave == 1, "New Run must enter wave-one Defense immediately")
	check(not is_instance_valid(game.factory_world), "The obsolete FactoryWorld must not be instantiated in the canonical loop")
	check(not game.build_panel.visible, "Build controls must remain hidden during Defense")
	check(game.weapons.size() == 2 and game.weapons[0].unlocked and game.weapons[1].unlocked, "Existing Basic MG and Missile weapons must remain available")
	game.weapons[0].aim_position = Vector2(640, 220)
	game.weapons[0].cooldown_left = 0.0
	var mg_ammo_before: int = game.inventory.amount(RunInventory.GATLING_AMMO)
	check(game._attempt_fire_weapon(game.weapons[0]), "Existing manual Basic MG firing must still work")
	check(game.inventory.amount(RunInventory.GATLING_AMMO) == mg_ammo_before - 1, "Basic MG fire must still consume exactly one round")
	game._select_weapon(1)
	check(game.selected_weapon_index == 1, "Existing weapon switching must still select the Missile Launcher")
	var city_health_before: float = game.cities[0].health
	game.cities[0].take_damage(5.0)
	check(game.cities[0].health == city_health_before - 5.0, "Existing city damage/health must remain functional")
	game._process_spawning(1.0)
	check(not game.enemies.is_empty(), "Existing wave spawning must still create enemies during Defense")

	game.spawn_queue.clear()
	game.spawn_finished = true
	for enemy in game.enemies.duplicate():
		if is_instance_valid(enemy): enemy.queue_free()
	game.enemies.clear()
	game._check_wave_clear()
	check(game.phase == game.Phase.BUILD and game.build_panel.visible and game.defense_panel.visible, "Wave clear must enter the untimed Build phase on the same battlefield")
	check(game.hud.visible and game.cities[0].visible and game.weapons[0].visible, "The battlefield settlement must remain visible during Build")

	var lab := BuildingCatalog.definition(BuildingCatalog.RESEARCH_LAB_ID)
	check(lab.stable_id == "research_lab" and lab.cost == BuildingCatalog.RESEARCH_LAB_COST, "Research Lab must use one centralized data definition and cost")
	check(lab.footprint == Vector2i(2, 2) and lab.max_health > 0.0 and lab.scene != null, "Research Lab definition must include footprint, health, and scene")
	var valid_point := Vector2(640, 512)
	var snapped: Vector2 = game.settlement_grid.snap_position(valid_point + Vector2(7, 5), lab)
	check(snapped == valid_point, "Placement preview must snap to the 32-pixel settlement grid")

	game.credits = 100
	game._select_building_for_placement(lab.stable_id)
	var credits_before: int = game.credits
	check(game._try_place_selected_building(valid_point), "A valid affordable Research Lab placement must succeed")
	check(game.settlement_buildings.size() == 1 and game.credits == credits_before - lab.cost, "Valid placement must create and charge exactly once")
	var placed: BuildingInstance = game.settlement_buildings[0]
	check(placed.runtime_id == 1 and placed.definition_id == lab.stable_id and placed.current_health == placed.max_health, "Placed buildings must own unique runtime identity and health")

	var credits_after_valid: int = game.credits
	check(not game._try_place_selected_building(valid_point), "Overlapping an existing building must be rejected")
	check(game.credits == credits_after_valid and game.settlement_buildings.size() == 1, "Rejected overlap must create nothing and spend nothing")
	check(not game._try_place_selected_building(Vector2(10, 100)), "Placement outside the build zone must be rejected")
	check(game.credits == credits_after_valid, "Out-of-zone placement must spend nothing")
	check(not game._try_place_selected_building(Vector2(590, 576)), "Placement over a protected city area must be rejected")
	check(game.credits == credits_after_valid, "Protected-area rejection must spend nothing")

	game.credits = lab.cost - 1
	check(not game._try_place_selected_building(Vector2(736, 512)), "Unaffordable placement must be rejected")
	check(game.credits == lab.cost - 1, "Insufficient currency must never become negative")
	var count_before_cancel: int = game.settlement_buildings.size()
	var credits_before_cancel: int = game.credits
	game._cancel_building_placement()
	check(game.selected_building_id.is_empty() and game.settlement_buildings.size() == count_before_cancel and game.credits == credits_before_cancel, "Cancel must clear the ghost without creating or charging")

	placed.take_damage(20.0)
	check(placed.state == BuildingInstance.State.DAMAGED and placed.current_health == placed.max_health - 20.0, "Building damage hook must update reusable health state")
	game._start_next_wave()
	check(game.phase == game.Phase.DEFENSE and game.current_wave == 2 and game.settlement_buildings[0] == placed, "Start Next Wave must resume combat without resetting settlement buildings")
	game._begin_build()
	check(game.settlement_buildings.size() == 1 and game.settlement_buildings[0].current_health == placed.current_health, "Settlement runtime state must persist into later Build phases")

	game._start_run()
	await process_frame
	check(game.phase == game.Phase.DEFENSE and game.current_wave == 1 and game.settlement_buildings.is_empty(), "New Run must reset run-specific settlement state")

	game.queue_free()
	if failures.is_empty():
		print("SETTLEMENT FOUNDATION TEST PASS: defense/build loop, placement, cost, health, persistence, and reset")
		quit(0)
	else:
		print("SETTLEMENT FOUNDATION TEST FAILURES: ", failures)
		quit(1)
