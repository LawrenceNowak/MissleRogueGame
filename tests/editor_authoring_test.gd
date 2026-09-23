extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("EDITOR AUTHORING TEST: " + message)

func _run() -> void:
	var packed: PackedScene = load("res://game/Main.tscn")
	var game = packed.instantiate()
	root.add_child(game)
	await process_frame

	var background := game.get_node("Battlefield/Background") as Sprite2D
	var ground := game.get_node("Battlefield/Ground") as Sprite2D
	var build_zone := game.get_node("Battlefield/BuildZone") as Area2D
	var zone_shape := game.get_node("Battlefield/BuildZone/CollisionShape2D") as CollisionShape2D
	var city_nodes := game.get_node("Battlefield/Settlement/Cities").get_children()
	var machine_gun := game.get_node("Battlefield/Settlement/StartingWeapons/MachineGun") as PlayerWeapon
	var missile := game.get_node("Battlefield/Settlement/StartingWeapons/MissileLauncher") as PlayerWeapon
	var base_sprite := machine_gun.get_node("BaseSprite") as Sprite2D
	var turret_pivot := machine_gun.get_node("TurretPivot") as Node2D
	var turret_sprite := machine_gun.get_node("TurretPivot/TurretSprite") as Sprite2D
	var muzzle := machine_gun.get_node("TurretPivot/MuzzlePoint") as Marker2D

	check(background.texture != null and ground.texture != null, "Background and ground must be authored textured nodes")
	check(city_nodes.size() == GameBalance.CITY_COUNT and city_nodes[0].get_node("CitySprite") is Sprite2D, "All starting cities must be authored scene instances with selectable sprites")
	check(base_sprite.texture != null and turret_sprite.texture != null, "Machine Gun base and turret must have independently assignable textures")
	check(turret_pivot != null and muzzle != null, "Machine Gun pivot and muzzle must be selectable authored nodes")
	check(build_zone.get_node("ZoneVisual") is Polygon2D and zone_shape.shape is RectangleShape2D, "Build zone must expose an editor-visible guide and collision shape")
	check((zone_shape.shape as RectangleShape2D).size == SettlementBuildGrid.BUILD_ZONE.size, "Authored build-zone shape must match gameplay validation bounds")

	var city_position_before: Vector2 = city_nodes[0].position
	var mg_position_before: Vector2 = machine_gun.position
	game._start_run()
	await process_frame
	check(city_nodes[0].position == city_position_before and machine_gun.position == mg_position_before, "Run setup must preserve manually authored city and weapon transforms")
	check(game.cities[0] == city_nodes[0] and game.weapons[0] == machine_gun and game.weapons[1] == missile, "Runtime must reuse the exact authored city and weapon instances")

	machine_gun.aim_position = turret_pivot.global_position + Vector2(100, -50)
	machine_gun._update_authored_visuals()
	var expected_angle := (machine_gun.aim_position - turret_pivot.global_position).angle()
	check(is_equal_approx(turret_pivot.global_rotation, expected_angle), "Authored TurretPivot must rotate toward the gameplay aim position")
	check(machine_gun.muzzle_position().is_equal_approx(muzzle.global_position), "Shots must originate from the authored MuzzlePoint")

	var lab_scene: PackedScene = load("res://game/ResearchLab.tscn")
	var lab := lab_scene.instantiate()
	check(lab.get_node("LabSprite") is Sprite2D and lab.get_node("PlacementOrigin") is Marker2D and lab.get_node("HealthBarAnchor") is Marker2D, "Research Lab must expose editable visual, placement, and health anchors")
	lab.free()

	game._begin_build()
	check(build_zone.visible and game.build_panel.visible, "Authored build-zone guide must appear with Build UI")
	game._start_next_wave()
	check(not build_zone.visible and game.phase == game.Phase.DEFENSE, "Build-zone guide must hide when Defense resumes")

	game.queue_free()
	if failures.is_empty():
		print("EDITOR AUTHORING TEST PASS: authored battlefield, sprites, pivots, muzzle, build zone, and runtime reuse")
		quit(0)
	else:
		print("EDITOR AUTHORING TEST FAILURES: ", failures)
		quit(1)
