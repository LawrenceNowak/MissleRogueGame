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

	game._cleanup_run_nodes()
	game._build_battlefield()
	game.phase = game.Phase.COMBAT
	game.current_wave = 10
	var boss = game._spawn_enemy("boss")
	check(int(boss.max_hp) == 800, "Wave ten boss must use configured boss HP")
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

	if failures.is_empty():
		print("SMOKE TEST PASS: core combat, economy, progression, boss, defeat, and reset")
		quit(0)
	else:
		print("SMOKE TEST FAILURES: ", failures)
		quit(1)
