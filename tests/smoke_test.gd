extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("SMOKE TEST: " + message)

func _run() -> void:
	var packed: PackedScene = load("res://game/Main.tscn")
	var game = packed.instantiate()
	root.add_child(game)
	await process_frame

	game._start_run()
	await process_frame
	check(game.cities.size() == 5, "A run must create five cities")
	check(game.weapons.size() == 2, "The arsenal must expose two slots")
	check(game.weapons[0].unlocked and not game.weapons[1].unlocked, "Only the missile launcher starts unlocked")
	check(game.phase == game.Phase.COMBAT and game.current_wave == 1, "A new run must begin wave one")

	var city = game.cities[0]
	city.take_damage(35.0)
	check(int(city.health) == 65, "City damage must affect its independent health")
	game.credits = 500
	game.phase = game.Phase.DEFENSE
	game._select_city(0)
	game._repair_city()
	check(int(city.health) == 95 and game.credits == 470, "Repair must restore 30 HP and spend 30 Credits")
	game._buy_shield()
	check(int(city.shield_health) == 80 and game.credits == 410, "Shield purchase must install a separate 80 HP pool")
	city.take_damage(20.0)
	check(int(city.health) == 95 and int(city.shield_health) == 60, "Shields must absorb city damage first")

	game._buy_gatling()
	check(game.weapons[1].unlocked, "Gatling purchase must unlock slot two")
	var slot_event := InputEventKey.new()
	slot_event.pressed = true
	slot_event.keycode = KEY_2
	slot_event.physical_keycode = KEY_2
	game._input(slot_event)
	check(game.selected_weapon_index == 1, "Key 2 must select the unlocked Gatling slot")
	game._apply_upgrade("missile_cluster")
	game._apply_upgrade("gatling_ricochet")
	check(game.weapons[0].cluster_level == 1 and game.weapons[1].ricochet_level == 1, "Weapon upgrades must alter runtime behavior")
	game._add_charm("Reinforced Concrete")
	check(int(game.cities[1].max_health) == 120, "Reinforced Concrete must increase every city's maximum HP")

	var reward_before: int = game.credits
	var threat = game._spawn_enemy("basic", Vector2(500, 200), game.cities[1])
	threat.take_damage(999.0)
	await process_frame
	game._collect_all_pickups()
	await process_frame
	check(game.credits > reward_before, "Destroyed threats must award Credits")

	var enemy_count_before: int = game.enemies.size()
	var mirv = game._spawn_enemy("mirv", Vector2(600, 300), game.cities[2])
	game._on_mirv_split(mirv, 3)
	await process_frame
	check(game.enemies.size() >= enemy_count_before + 3, "MIRV must create three interceptable child warheads")

	game._open_upgrade_choice()
	var missile_upgrade_count: int = game.weapons[0].upgrade_labels.size()
	game._choose_upgrade(0)
	var applied_count: int = game.weapons[0].upgrade_labels.size() + game.weapons[1].upgrade_labels.size() + game.charms.size()
	game._choose_upgrade(1)
	var after_second_click: int = game.weapons[0].upgrade_labels.size() + game.weapons[1].upgrade_labels.size() + game.charms.size()
	check(applied_count >= missile_upgrade_count and after_second_click == applied_count, "Milestone choice must apply at most one upgrade")

	game.phase = game.Phase.DEFENSE
	game._toggle_pause()
	check(game.phase == game.Phase.PAUSED and game.get_tree().paused, "Escape pause flow must pause the run")
	game._resume()
	check(game.phase == game.Phase.DEFENSE and not game.get_tree().paused, "Resume must restore the prior phase")
	game._on_pickup_collected(null, "rapid", 1)
	check(game.rapid_fire_left == GameBalance.RAPID_FIRE_DURATION, "Rapid Fire pickup must apply a temporary configured duration")

	game._cleanup_run_nodes()
	game._build_battlefield()
	game.phase = game.Phase.COMBAT
	game.current_wave = 10
	var boss = game._spawn_enemy("boss")
	check(int(boss.max_hp) == 800, "Wave ten boss must use configured boss HP")
	var before_boss_shot: int = game.enemies.size()
	boss._process_boss(GameBalance.BOSS_ATTACK_CADENCE + 0.1)
	check(game.enemies.size() > before_boss_shot, "The Missile Carrier must launch normal threats toward cities")
	boss.take_damage(99999.0)
	await process_frame
	check(game.phase == game.Phase.VICTORY, "Destroying the Missile Carrier must trigger victory")

	game._start_run()
	await process_frame
	for test_city in game.cities:
		test_city.take_damage(999.0)
	await process_frame
	check(game.phase == game.Phase.DEFEAT, "Defeat must trigger only after all five cities are destroyed")

	game._start_run()
	await process_frame
	check(game.phase == game.Phase.COMBAT and game.credits == 20 and game.current_wave == 1, "New Run must reset temporary run state without restarting Godot")
	check(game.cities.all(func(test_city): return not test_city.destroyed and int(test_city.health) == 100), "New Run must rebuild healthy cities")

	game.persistent_components = 7
	game._save_persistent()
	var reloaded_game = packed.instantiate()
	root.add_child(reloaded_game)
	await process_frame
	check(reloaded_game.persistent_components == 7, "Persistent components must survive a save reload")

	check(GameBalance.wave_definition(1).size() == 5, "Wave one must contain five teaching threats")
	check(GameBalance.wave_definition(3).any(func(entry): return entry.kind == "fast"), "Wave three must introduce fast missiles")
	check(GameBalance.wave_definition(4).any(func(entry): return entry.kind == "mirv"), "Wave four must introduce MIRVs")
	check(GameBalance.wave_definition(10)[0].kind == "boss", "Wave ten must be the boss encounter")

	if failures.is_empty():
		print("SMOKE TEST PASS: core combat, economy, progression, boss, defeat, and reset")
		quit(0)
	else:
		print("SMOKE TEST FAILURES: ", failures)
		quit(1)
