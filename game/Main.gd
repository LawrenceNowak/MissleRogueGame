extends Node2D

enum Phase { MENU, COMBAT, UPGRADE, DEFENSE, VICTORY, DEFEAT, PAUSED }

const VIEW_SIZE := Vector2(1280, 720)
const GROUND_Y := 650.0
const CITY_X := [150.0, 370.0, 590.0, 810.0, 1030.0]
const SAVE_PATH := "user://missile_command_save.json"

var phase := Phase.MENU
var phase_before_pause := Phase.MENU
var current_wave := 0
var waves_cleared := 0
var credits := 0
var run_components := 0
var persistent_components := 0
var selected_weapon_index := 0
var selected_city_index := 0
var spawn_queue: Array[Dictionary] = []
var spawn_timer := 0.0
var spawn_finished := true
var rapid_fire_left := 0.0
var banner_left := 0.0
var banner_text := ""
var charms: Array[String] = []
var missile_upgrade_cursor := 0
var gatling_upgrade_cursor := 0
var dragging_weapon: PlayerWeapon
var drag_original_x := 0.0

var cities: Array[DefenseCity] = []
var weapons: Array[PlayerWeapon] = []
var enemies: Array[EnemyThreat] = []
var projectiles: Array[DefenseProjectile] = []
var pickups: Array[RewardPickup] = []
var effects: Array[Dictionary] = []

var menu_panel: Panel
var menu_components_label: Label
var hud: Control
var wave_label: Label
var credits_label: Label
var slots_label: Label
var city_status_label: Label
var heat_bar: ProgressBar
var heat_label: Label
var powerup_label: Label
var boss_bar: ProgressBar
var boss_label: Label
var defense_panel: Panel
var defense_title: Label
var defense_city_label: Label
var defense_weapons_label: Label
var defense_charms_label: Label
var repair_button: Button
var shield_button: Button
var gatling_button: Button
var missile_upgrade_button: Button
var gatling_upgrade_button: Button
var charm_button: Button
var next_wave_button: Button
var upgrade_panel: Panel
var upgrade_buttons: Array[Button] = []
var pause_panel: Panel
var result_panel: Panel
var result_title: Label
var result_summary: Label
var banner_label: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	randomize()
	_load_save()
	_build_ui()
	_show_menu()
	queue_redraw()

func _process(delta: float) -> void:
	_cleanup_arrays()
	_update_effects(delta)
	if banner_left > 0.0:
		banner_left -= delta
		banner_label.visible = banner_left > 0.0
	if rapid_fire_left > 0.0:
		rapid_fire_left = maxf(0.0, rapid_fire_left - delta)
	if phase == Phase.COMBAT:
		_process_spawning(delta)
		_process_firing()
		_check_wave_clear()
	elif phase == Phase.DEFENSE and is_instance_valid(dragging_weapon):
		dragging_weapon.position.x = clampf(get_global_mouse_position().x, 65.0, 1135.0)
		dragging_weapon.queue_redraw()
	for weapon in weapons:
		if is_instance_valid(weapon):
			weapon.aim_position = get_global_mouse_position()
			weapon.queue_redraw()
	_update_hud()
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game"):
		_toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if phase == Phase.PAUSED or phase == Phase.MENU or phase == Phase.VICTORY or phase == Phase.DEFEAT or phase == Phase.UPGRADE:
		return
	if event.is_action_pressed("select_slot_1"):
		_select_weapon(0)
	elif event.is_action_pressed("select_slot_2"):
		_select_weapon(1)
	if phase == Phase.DEFENSE and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_defense_click(event.position)
		else:
			_finish_drag()
	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F5:
				credits += 100
				_show_banner("DEBUG +100 CREDITS")
			KEY_F6:
				_debug_skip_wave()
			KEY_F7:
				if not cities.is_empty(): cities[selected_city_index].take_damage(25.0)
			KEY_F8:
				_debug_kill_enemies()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW_SIZE), Color("081326"))
	for index in 36:
		var x := float((index * 97 + 43) % 1260)
		var y := float((index * 53 + 19) % 470)
		draw_circle(Vector2(x, y), 1.2, Color(0.55, 0.78, 1.0, 0.45))
	draw_rect(Rect2(0, GROUND_Y, 1280, 70), Color("142d36"))
	draw_line(Vector2(0, GROUND_Y), Vector2(1280, GROUND_Y), Color("3b7683"), 4.0)
	if phase == Phase.COMBAT:
		var mouse := get_global_mouse_position()
		draw_arc(mouse, 12.0, 0.0, TAU, 24, Color(0.55, 0.95, 1.0, 0.9), 2.0)
		draw_line(mouse - Vector2(18,0), mouse - Vector2(7,0), Color("8ef5ff"), 2.0)
		draw_line(mouse + Vector2(7,0), mouse + Vector2(18,0), Color("8ef5ff"), 2.0)
		draw_line(mouse - Vector2(0,18), mouse - Vector2(0,7), Color("8ef5ff"), 2.0)
		draw_line(mouse + Vector2(0,7), mouse + Vector2(0,18), Color("8ef5ff"), 2.0)
	for effect in effects:
		var ratio: float = effect.life / effect.max_life
		var radius: float = effect.radius * (1.0 - ratio * 0.35)
		draw_circle(effect.position, radius, Color(effect.color, ratio * 0.16))
		draw_arc(effect.position, radius, 0.0, TAU, 32, Color(effect.color, ratio), 3.0)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	menu_panel = _panel(layer, Rect2(350, 150, 580, 410), Color(0.035, 0.075, 0.14, 0.96))
	var title := _label(menu_panel, "MISSILE COMMAND x PIT", 36, Color("8ef5ff"), Rect2(30, 48, 520, 55))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var subtitle := _label(menu_panel, "ACTIVE DEFENSE ROGUELITE", 16, Color("9fb4cd"), Rect2(30, 108, 520, 30))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var premise := _label(menu_panel, "Protect five cities. Aim every shot.\nBuild a defense machine between waves.", 20, Color("e8f0ff"), Rect2(40, 165, 500, 62))
	premise.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_components_label = _label(menu_panel, "Components: 0", 18, Color("c58cff"), Rect2(40, 248, 500, 30))
	menu_components_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var start_button := _button(menu_panel, "START RUN", Rect2(165, 310, 250, 56), _start_run)
	start_button.add_theme_font_size_override("font_size", 20)

	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)
	wave_label = _label(hud, "WAVE 0 / 10", 20, Color("eaf6ff"), Rect2(20, 16, 190, 28))
	credits_label = _label(hud, "CREDITS 0", 20, Color("ffe66d"), Rect2(215, 16, 180, 28))
	slots_label = _label(hud, "[1] MISSILE   [2] LOCKED", 17, Color("8ef5ff"), Rect2(405, 16, 430, 28))
	city_status_label = _label(hud, "", 14, Color("c6d7ea"), Rect2(20, 52, 780, 26))
	heat_label = _label(hud, "GATLING HEAT", 13, Color("f6b94b"), Rect2(850, 14, 120, 20))
	heat_bar = ProgressBar.new()
	heat_bar.position = Vector2(850, 36)
	heat_bar.size = Vector2(180, 18)
	heat_bar.max_value = GameBalance.GATLING_MAX_HEAT
	heat_bar.show_percentage = false
	hud.add_child(heat_bar)
	powerup_label = _label(hud, "", 15, Color("4de3a4"), Rect2(1050, 16, 210, 28))
	boss_label = _label(hud, "MISSILE CARRIER", 15, Color("ffad66"), Rect2(430, 82, 420, 22))
	boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_bar = ProgressBar.new()
	boss_bar.position = Vector2(430, 105)
	boss_bar.size = Vector2(420, 20)
	boss_bar.max_value = GameBalance.BOSS_HP
	boss_bar.show_percentage = true
	hud.add_child(boss_bar)
	banner_label = _label(hud, "", 30, Color("ffffff"), Rect2(330, 146, 620, 48))
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	defense_panel = _panel(layer, Rect2(18, 80, 350, 510), Color(0.035, 0.075, 0.14, 0.96))
	defense_title = _label(defense_panel, "DEFENSE PHASE", 24, Color("8ef5ff"), Rect2(18, 16, 314, 34))
	defense_city_label = _label(defense_panel, "", 16, Color("e8f0ff"), Rect2(18, 56, 314, 48))
	repair_button = _button(defense_panel, "REPAIR CITY — 30", Rect2(18, 108, 314, 38), _repair_city)
	shield_button = _button(defense_panel, "BUILD SHIELD — 60", Rect2(18, 151, 314, 38), _buy_shield)
	gatling_button = _button(defense_panel, "BUY GATLING — 80", Rect2(18, 199, 314, 38), _buy_gatling)
	missile_upgrade_button = _button(defense_panel, "UPGRADE MISSILE — 50", Rect2(18, 242, 314, 38), _buy_missile_upgrade)
	gatling_upgrade_button = _button(defense_panel, "UPGRADE GATLING — 50", Rect2(18, 285, 314, 38), _buy_gatling_upgrade)
	charm_button = _button(defense_panel, "BUY CHARM — 40", Rect2(18, 328, 314, 38), _buy_charm)
	defense_weapons_label = _label(defense_panel, "", 13, Color("9fb4cd"), Rect2(18, 373, 314, 40))
	defense_charms_label = _label(defense_panel, "", 13, Color("c58cff"), Rect2(18, 416, 314, 38))
	next_wave_button = _button(defense_panel, "START NEXT WAVE", Rect2(18, 460, 314, 38), _start_next_wave)

	upgrade_panel = _panel(layer, Rect2(270, 176, 740, 365), Color(0.04, 0.065, 0.13, 0.98))
	var upgrade_title := _label(upgrade_panel, "CHOOSE 1 OF 3", 28, Color("ffe66d"), Rect2(30, 24, 680, 42))
	upgrade_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var upgrade_subtitle := _label(upgrade_panel, "Free milestone upgrade", 15, Color("9fb4cd"), Rect2(30, 68, 680, 24))
	upgrade_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for index in 3:
		var choice := _button(upgrade_panel, "OPTION", Rect2(55, 112 + index * 72, 630, 56), func(): _choose_upgrade(index))
		choice.add_theme_font_size_override("font_size", 17)
		upgrade_buttons.append(choice)

	pause_panel = _panel(layer, Rect2(440, 185, 400, 340), Color(0.025, 0.045, 0.09, 0.98))
	var pause_title := _label(pause_panel, "PAUSED", 32, Color("eaf6ff"), Rect2(40, 35, 320, 45))
	pause_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_button(pause_panel, "RESUME", Rect2(75, 110, 250, 46), _resume)
	_button(pause_panel, "RESTART RUN", Rect2(75, 172, 250, 46), _start_run)
	_button(pause_panel, "MAIN MENU", Rect2(75, 234, 250, 46), _show_menu)

	result_panel = _panel(layer, Rect2(340, 150, 600, 430), Color(0.025, 0.055, 0.11, 0.98))
	result_title = _label(result_panel, "VICTORY", 42, Color("4de3a4"), Rect2(40, 44, 520, 60))
	result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_summary = _label(result_panel, "", 19, Color("e8f0ff"), Rect2(70, 135, 460, 130))
	result_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_button(result_panel, "NEW RUN", Rect2(80, 320, 200, 52), _start_run)
	_button(result_panel, "MAIN MENU", Rect2(320, 320, 200, 52), _show_menu)

func _panel(parent: Node, rect: Rect2, color: Color) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("31506f")
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel

func _label(parent: Node, text_value: String, size: int, color: Color, rect: Rect2) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = rect.position
	label.size = rect.size
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _button(parent: Node, text_value: String, rect: Rect2, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.position = rect.position
	button.size = rect.size
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _start_run() -> void:
	get_tree().paused = false
	_cleanup_run_nodes()
	current_wave = 0
	waves_cleared = 0
	credits = 20
	run_components = 0
	rapid_fire_left = 0.0
	charms.clear()
	missile_upgrade_cursor = 0
	gatling_upgrade_cursor = 0
	selected_weapon_index = 0
	selected_city_index = 0
	_build_battlefield()
	menu_panel.visible = false
	result_panel.visible = false
	pause_panel.visible = false
	upgrade_panel.visible = false
	defense_panel.visible = false
	hud.visible = true
	_begin_wave(1)

func _build_battlefield() -> void:
	for index in GameBalance.CITY_COUNT:
		var city := DefenseCity.new()
		city.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(city)
		city.setup(index, Vector2(CITY_X[index], 642.0))
		city.changed.connect(_refresh_defense_ui)
		city.fell.connect(_on_city_fell)
		cities.append(city)
	var missile := PlayerWeapon.new()
	missile.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(missile)
	missile.setup(PlayerWeapon.Kind.MISSILE, Vector2(260, 620), true)
	weapons.append(missile)
	var gatling := PlayerWeapon.new()
	gatling.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(gatling)
	gatling.setup(PlayerWeapon.Kind.GATLING, Vector2(920, 620), false)
	weapons.append(gatling)
	_select_weapon(0)
	cities[0].selected = true

func _cleanup_run_nodes() -> void:
	for list in [cities, weapons, enemies, projectiles, pickups]:
		for node in list:
			if is_instance_valid(node): node.queue_free()
	cities.clear()
	weapons.clear()
	enemies.clear()
	projectiles.clear()
	pickups.clear()
	effects.clear()
	spawn_queue.clear()
	dragging_weapon = null

func _begin_wave(number: int) -> void:
	if number > 10:
		_victory()
		return
	phase = Phase.COMBAT
	current_wave = number
	spawn_queue = GameBalance.wave_definition(number).duplicate(true)
	spawn_timer = 0.35
	spawn_finished = spawn_queue.is_empty()
	defense_panel.visible = false
	upgrade_panel.visible = false
	result_panel.visible = false
	_show_banner("WAVE %d" % current_wave, 1.8)
	_refresh_defense_ui()

func _process_spawning(delta: float) -> void:
	if spawn_finished:
		return
	spawn_timer -= delta
	if spawn_timer > 0.0:
		return
	if spawn_queue.is_empty():
		spawn_finished = true
		return
	var entry: Dictionary = spawn_queue.pop_front()
	_spawn_enemy(entry.kind)
	spawn_timer = float(entry.delay)
	if spawn_queue.is_empty():
		spawn_finished = true

func _spawn_enemy(kind: String, source_position: Vector2 = Vector2(-1, -1), forced_target = null) -> EnemyThreat:
	var target = forced_target if is_instance_valid(forced_target) else _random_surviving_city()
	if kind != "boss" and not is_instance_valid(target):
		return null
	var spawn_position := source_position
	if spawn_position.x < 0.0:
		spawn_position = Vector2(randf_range(70.0, 1210.0), -18.0)
	if kind == "boss":
		spawn_position = Vector2(640, 125)
	var threat := EnemyThreat.new()
	threat.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(threat)
	threat.setup(kind, spawn_position, target, _random_surviving_city)
	threat.removed.connect(_on_enemy_removed)
	threat.split_requested.connect(_on_mirv_split)
	threat.boss_shot_requested.connect(func(shot_kind: String): _spawn_enemy(shot_kind, threat.position + Vector2(0, 32)))
	if kind == "boss":
		threat.hp_changed.connect(_on_boss_hp_changed)
		boss_bar.value = threat.hp
	enemies.append(threat)
	return threat

func _random_surviving_city():
	var living: Array[DefenseCity] = []
	for city in cities:
		if is_instance_valid(city) and not city.destroyed:
			living.append(city)
	return living.pick_random() if not living.is_empty() else null

func _process_firing() -> void:
	if weapons.is_empty() or selected_weapon_index >= weapons.size():
		return
	var weapon := weapons[selected_weapon_index]
	if not weapon.unlocked:
		return
	var wants_fire := Input.is_action_pressed("fire") if weapon.kind == PlayerWeapon.Kind.GATLING else Input.is_action_just_pressed("fire")
	if not wants_fire:
		return
	var rapid_multiplier := 1.6 if rapid_fire_left > 0.0 else 1.0
	var shot := weapon.try_fire(rapid_multiplier)
	if shot.is_empty():
		return
	var projectile := DefenseProjectile.new()
	projectile.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(projectile)
	if shot.type == "missile":
		projectile.setup_missile(shot.position, shot.target, shot.speed, shot.damage, shot.radius, shot.cluster)
		projectile.exploded.connect(_on_missile_exploded)
	else:
		projectile.setup_bullet(shot.position, shot.velocity, shot.damage, shot.ricochet, _living_enemies)
		projectile.bullet_hit.connect(_on_bullet_hit)
	projectiles.append(projectile)
	_add_effect(weapon.muzzle_position(), 12.0, 0.12, Color("ffe66d"))

func _living_enemies() -> Array[EnemyThreat]:
	var living: Array[EnemyThreat] = []
	for enemy in enemies:
		if is_instance_valid(enemy) and not enemy.resolved:
			living.append(enemy)
	return living

func _on_missile_exploded(_projectile, at_position: Vector2, damage: float, radius: float, cluster: int) -> void:
	_apply_explosion(at_position, damage, radius)
	if cluster > 0:
		for index in 3:
			var angle := TAU * float(index) / 3.0
			var child_position := at_position + Vector2.from_angle(angle) * radius * 0.48
			_apply_explosion(child_position, damage * 0.45, radius * 0.48)

func _apply_explosion(at_position: Vector2, damage: float, radius: float) -> void:
	_add_effect(at_position, radius, 0.34, Color("62e8ff"))
	for enemy in _living_enemies():
		if enemy.position.distance_to(at_position) <= radius + enemy.radius:
			var falloff := clampf(1.25 - enemy.position.distance_to(at_position) / maxf(radius, 1.0), 0.35, 1.0)
			enemy.take_damage(damage * falloff)

func _on_bullet_hit(_projectile, threat, damage: float, ricochet: int) -> void:
	if not is_instance_valid(threat):
		return
	var hit_position: Vector2 = threat.position
	threat.take_damage(damage)
	_add_effect(hit_position, 14.0, 0.12, Color("ffe66d"))
	if ricochet > 0:
		var nearest = null
		var nearest_distance := 145.0
		for candidate in _living_enemies():
			if candidate == threat:
				continue
			var distance := candidate.position.distance_to(hit_position)
			if distance < nearest_distance:
				nearest = candidate
				nearest_distance = distance
		if is_instance_valid(nearest):
			_add_effect(nearest.position, 11.0, 0.12, Color("ffe66d"))
			nearest.take_damage(damage * 0.65)

func _on_enemy_removed(threat, killed: bool, reward: int) -> void:
	if not is_instance_valid(threat):
		return
	var was_boss: bool = threat.kind == "boss"
	var death_position: Vector2 = threat.position
	enemies.erase(threat)
	if killed:
		_add_effect(death_position, 30.0 if not was_boss else 95.0, 0.45, threat.visual_color)
		_spawn_pickup("credits", reward, death_position)
		if randf() < 0.08:
			_spawn_pickup("component", 1, death_position + Vector2(12, 0))
		if not was_boss and randf() < 0.07:
			_spawn_pickup("rapid", 1, death_position + Vector2(-12, 0))
	if was_boss and killed:
		for enemy in enemies.duplicate():
			if is_instance_valid(enemy): enemy.queue_free()
		enemies.clear()
		_collect_all_pickups()
		_victory()

func _on_mirv_split(threat, child_count: int) -> void:
	if not is_instance_valid(threat):
		return
	var split_position: Vector2 = threat.position
	enemies.erase(threat)
	_add_effect(split_position, 48.0, 0.38, Color("c58cff"))
	var targets: Array[DefenseCity] = []
	for city in cities:
		if not city.destroyed: targets.append(city)
	targets.shuffle()
	for index in child_count:
		var chosen = targets[index % targets.size()] if not targets.is_empty() else null
		_spawn_enemy("child", split_position + Vector2((index - 1) * 16, 0), chosen)

func _spawn_pickup(kind: String, amount: int, at_position: Vector2) -> void:
	var pickup := RewardPickup.new()
	pickup.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(pickup)
	pickup.setup(kind, amount, at_position)
	pickup.collected.connect(_on_pickup_collected)
	pickups.append(pickup)

func _on_pickup_collected(pickup, kind: String, amount: int) -> void:
	pickups.erase(pickup)
	match kind:
		"credits": credits += amount
		"component":
			run_components += amount
			persistent_components += amount
			_save_persistent()
		"rapid":
			rapid_fire_left = maxf(rapid_fire_left, 10.0)
			_show_banner("RAPID FIRE", 1.2)

func _collect_all_pickups() -> void:
	for pickup in pickups.duplicate():
		if is_instance_valid(pickup): pickup.collect()

func _check_wave_clear() -> void:
	if phase != Phase.COMBAT or not spawn_finished:
		return
	if not _living_enemies().is_empty():
		return
	if current_wave == 10:
		return
	waves_cleared = current_wave
	_collect_all_pickups()
	_show_banner("WAVE CLEAR", 1.6)
	if current_wave in [2, 5, 8]:
		_open_upgrade_choice()
	else:
		_enter_defense()

func _enter_defense() -> void:
	phase = Phase.DEFENSE
	defense_panel.visible = true
	upgrade_panel.visible = false
	_refresh_defense_ui()

func _open_upgrade_choice() -> void:
	phase = Phase.UPGRADE
	upgrade_panel.visible = true
	defense_panel.visible = false
	var pool: Array[Dictionary] = [
		{"id":"missile_radius", "name":"LARGER EXPLOSION", "desc":"Missile blast radius +20"},
		{"id":"missile_cluster", "name":"CLUSTER WARHEAD", "desc":"Missile detonations create 3 secondary blasts"},
		{"id":"missile_speed", "name":"FASTER MISSILE", "desc":"Missile travel speed +25%"},
		{"id":"charm_targeting", "name":"TARGETING COMPUTER", "desc":"All projectile speed +20%"},
		{"id":"charm_reinforced", "name":"REINFORCED CONCRETE", "desc":"Every city gains 20 maximum HP"}
	]
	if "Targeting Computer" in charms:
		pool = pool.filter(func(option): return option.id != "charm_targeting")
	if "Reinforced Concrete" in charms:
		pool = pool.filter(func(option): return option.id != "charm_reinforced")
	if weapons.size() > 1 and weapons[1].unlocked:
		pool.append_array([
			{"id":"gatling_rate", "name":"FASTER SPIN", "desc":"Gatling fire rate +28%"},
			{"id":"gatling_cooling", "name":"IMPROVED COOLING", "desc":"Cool faster and generate less heat"},
			{"id":"gatling_ricochet", "name":"RICOCHET", "desc":"Bullets jump once for 65% damage"},
			{"id":"charm_cooling", "name":"COOLING UNIT", "desc":"Gatling cooling +35%"}
		])
		if "Cooling Unit" in charms:
			pool = pool.filter(func(option): return option.id != "charm_cooling")
	pool.shuffle()
	for index in upgrade_buttons.size():
		var option: Dictionary = pool[index]
		upgrade_buttons[index].text = "%s\n%s" % [option.name, option.desc]
		upgrade_buttons[index].set_meta("upgrade_id", option.id)

func _choose_upgrade(index: int) -> void:
	if phase != Phase.UPGRADE or index < 0 or index >= upgrade_buttons.size():
		return
	var upgrade_id: String = upgrade_buttons[index].get_meta("upgrade_id", "")
	_apply_upgrade(upgrade_id)
	_enter_defense()

func _apply_upgrade(id: String) -> void:
	if id.begins_with("missile_"):
		weapons[0].apply_upgrade(id)
	elif id.begins_with("gatling_") and weapons.size() > 1:
		weapons[1].apply_upgrade(id)
	elif id == "charm_targeting":
		_add_charm("Targeting Computer")
	elif id == "charm_cooling":
		_add_charm("Cooling Unit")
	elif id == "charm_reinforced":
		_add_charm("Reinforced Concrete")

func _add_charm(display_name: String) -> bool:
	if display_name in charms:
		return false
	charms.append(display_name)
	match display_name:
		"Targeting Computer":
			for weapon in weapons: weapon.projectile_speed *= 1.2
		"Cooling Unit":
			weapons[1].cooling *= 1.35
			weapons[1].heat_per_shot *= 0.9
		"Reinforced Concrete":
			for city in cities: city.reinforce(20.0)
	_refresh_defense_ui()
	return true

func _begin_defense_click(mouse_position: Vector2) -> void:
	for weapon in weapons:
		if weapon.unlocked and mouse_position.distance_to(weapon.position) < 38.0:
			dragging_weapon = weapon
			drag_original_x = weapon.position.x
			weapon.dragging = true
			return
	for city in cities:
		if mouse_position.distance_to(city.position) < 55.0:
			_select_city(city.city_index)
			return

func _finish_drag() -> void:
	if not is_instance_valid(dragging_weapon):
		return
	for weapon in weapons:
		if weapon != dragging_weapon and weapon.unlocked and absf(weapon.position.x - dragging_weapon.position.x) < 82.0:
			dragging_weapon.position.x = drag_original_x
			_show_banner("PLACEMENT BLOCKED", 1.0)
	dragging_weapon.dragging = false
	dragging_weapon.queue_redraw()
	dragging_weapon = null

func _select_weapon(index: int) -> void:
	if index < 0 or index >= weapons.size() or not weapons[index].unlocked:
		if index == 1:
			_show_banner("GATLING LOCKED", 0.9)
		return
	selected_weapon_index = index
	for weapon_index in weapons.size():
		weapons[weapon_index].selected = weapon_index == selected_weapon_index
		weapons[weapon_index].queue_redraw()

func _select_city(index: int) -> void:
	selected_city_index = clampi(index, 0, cities.size() - 1)
	for city_index in cities.size():
		cities[city_index].selected = city_index == selected_city_index
		cities[city_index].queue_redraw()
	_refresh_defense_ui()

func _repair_city() -> void:
	var city := cities[selected_city_index]
	if credits >= GameBalance.CITY_REPAIR_COST and city.repair(GameBalance.CITY_REPAIR_AMOUNT):
		credits -= GameBalance.CITY_REPAIR_COST
		_show_banner("CITY REPAIRED", 0.9)
	_refresh_defense_ui()

func _buy_shield() -> void:
	var city := cities[selected_city_index]
	if credits >= GameBalance.SHIELD_COST and city.install_shield():
		credits -= GameBalance.SHIELD_COST
		_show_banner("SHIELD ONLINE", 0.9)
	_refresh_defense_ui()

func _buy_gatling() -> void:
	if credits < GameBalance.GATLING_COST or weapons[1].unlocked:
		return
	credits -= GameBalance.GATLING_COST
	weapons[1].unlocked = true
	weapons[1].queue_redraw()
	_show_banner("GATLING UNLOCKED — PRESS 2", 1.4)
	_refresh_defense_ui()

func _buy_missile_upgrade() -> void:
	if credits < GameBalance.WEAPON_UPGRADE_COST:
		return
	var ids := ["missile_radius", "missile_cluster", "missile_speed"]
	credits -= GameBalance.WEAPON_UPGRADE_COST
	weapons[0].apply_upgrade(ids[missile_upgrade_cursor % ids.size()])
	missile_upgrade_cursor += 1
	_refresh_defense_ui()

func _buy_gatling_upgrade() -> void:
	if credits < GameBalance.WEAPON_UPGRADE_COST or not weapons[1].unlocked:
		return
	var ids := ["gatling_rate", "gatling_cooling", "gatling_ricochet"]
	credits -= GameBalance.WEAPON_UPGRADE_COST
	weapons[1].apply_upgrade(ids[gatling_upgrade_cursor % ids.size()])
	gatling_upgrade_cursor += 1
	_refresh_defense_ui()

func _buy_charm() -> void:
	if credits < 40:
		return
	for charm_name in ["Targeting Computer", "Cooling Unit", "Reinforced Concrete"]:
		if charm_name not in charms:
			credits -= 40
			_add_charm(charm_name)
			_show_banner(charm_name.to_upper(), 1.0)
			break
	_refresh_defense_ui()

func _start_next_wave() -> void:
	if phase == Phase.DEFENSE:
		_finish_drag()
		_begin_wave(current_wave + 1)

func _on_city_fell(_city) -> void:
	var all_destroyed := true
	for city in cities:
		if not city.destroyed:
			all_destroyed = false
			break
	if all_destroyed:
		_defeat()

func _victory() -> void:
	if phase == Phase.VICTORY:
		return
	waves_cleared = 10
	phase = Phase.VICTORY
	_stop_combat_nodes()
	_show_result(true)

func _defeat() -> void:
	if phase == Phase.DEFEAT:
		return
	phase = Phase.DEFEAT
	_stop_combat_nodes()
	_show_result(false)

func _stop_combat_nodes() -> void:
	spawn_queue.clear()
	spawn_finished = true
	for node in enemies + projectiles + pickups:
		if is_instance_valid(node): node.queue_free()
	enemies.clear()
	projectiles.clear()
	pickups.clear()

func _show_result(won: bool) -> void:
	defense_panel.visible = false
	upgrade_panel.visible = false
	pause_panel.visible = false
	result_panel.visible = true
	result_title.text = "VICTORY" if won else "DEFEAT"
	result_title.add_theme_color_override("font_color", Color("4de3a4") if won else Color("ff5d73"))
	var surviving := 0
	for city in cities:
		if not city.destroyed: surviving += 1
	result_summary.text = "Waves cleared: %d / 10\nCities surviving: %d / 5\nCredits remaining: %d\nComponents earned: %d\nPersistent components: %d" % [waves_cleared, surviving, credits, run_components, persistent_components]

func _show_menu() -> void:
	get_tree().paused = false
	phase = Phase.MENU
	_cleanup_run_nodes()
	menu_panel.visible = true
	menu_components_label.text = "Persistent Components: %d" % persistent_components
	hud.visible = false
	defense_panel.visible = false
	upgrade_panel.visible = false
	pause_panel.visible = false
	result_panel.visible = false

func _toggle_pause() -> void:
	if phase == Phase.MENU or phase == Phase.VICTORY or phase == Phase.DEFEAT:
		return
	if phase == Phase.PAUSED:
		_resume()
	else:
		phase_before_pause = phase
		phase = Phase.PAUSED
		pause_panel.visible = true
		get_tree().paused = true

func _resume() -> void:
	get_tree().paused = false
	phase = phase_before_pause
	pause_panel.visible = false

func _refresh_defense_ui() -> void:
	if cities.is_empty() or weapons.is_empty():
		return
	selected_city_index = clampi(selected_city_index, 0, cities.size() - 1)
	var city := cities[selected_city_index]
	var shield_text := "none" if city.shield_max <= 0.0 else "%d / %d" % [int(city.shield_health), int(city.shield_max)]
	defense_city_label.text = "CITY %d   HP %d / %d\nShield: %s" % [selected_city_index + 1, int(city.health), int(city.max_health), shield_text]
	repair_button.disabled = credits < GameBalance.CITY_REPAIR_COST or city.destroyed or city.health >= city.max_health
	shield_button.disabled = credits < GameBalance.SHIELD_COST or city.destroyed or city.shield_max > 0.0
	gatling_button.disabled = credits < GameBalance.GATLING_COST or weapons[1].unlocked
	gatling_button.text = "GATLING OWNED" if weapons[1].unlocked else "BUY GATLING — 80"
	missile_upgrade_button.disabled = credits < GameBalance.WEAPON_UPGRADE_COST
	gatling_upgrade_button.disabled = credits < GameBalance.WEAPON_UPGRADE_COST or not weapons[1].unlocked
	charm_button.disabled = credits < 40 or charms.size() >= 3
	defense_weapons_label.text = "Missile: %s\nGatling: %s" % [", ".join(weapons[0].upgrade_labels) if not weapons[0].upgrade_labels.is_empty() else "base", ", ".join(weapons[1].upgrade_labels) if not weapons[1].upgrade_labels.is_empty() else ("base" if weapons[1].unlocked else "locked")]
	defense_charms_label.text = "Charms: %s" % (", ".join(charms) if not charms.is_empty() else "none")
	next_wave_button.text = "START WAVE %d" % (current_wave + 1)

func _update_hud() -> void:
	if not hud.visible or cities.is_empty() or weapons.is_empty():
		return
	wave_label.text = "WAVE %d / 10" % current_wave
	credits_label.text = "CREDITS %d" % credits
	var slot2 := "GATLING" if weapons[1].unlocked else "LOCKED"
	slots_label.text = "%s [1] MISSILE     %s [2] %s" % [">" if selected_weapon_index == 0 else " ", ">" if selected_weapon_index == 1 else " ", slot2]
	var city_parts: Array[String] = []
	for city in cities:
		var value := "X" if city.destroyed else str(int(city.health))
		if city.shield_health > 0.0: value += "+S%d" % int(city.shield_health)
		city_parts.append("C%d:%s" % [city.city_index + 1, value])
	city_status_label.text = "   ".join(city_parts)
	heat_label.visible = weapons[1].unlocked
	heat_bar.visible = weapons[1].unlocked
	heat_bar.value = weapons[1].heat
	powerup_label.text = "RAPID FIRE %.1fs" % rapid_fire_left if rapid_fire_left > 0.0 else ""
	var boss = _get_boss()
	boss_label.visible = is_instance_valid(boss)
	boss_bar.visible = is_instance_valid(boss)
	if is_instance_valid(boss): boss_bar.value = maxf(0.0, boss.hp)
	_refresh_defense_ui()

func _get_boss():
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.kind == "boss": return enemy
	return null

func _on_boss_hp_changed(current: float, _maximum: float) -> void:
	boss_bar.value = current

func _add_effect(at_position: Vector2, radius: float, lifetime: float, color: Color) -> void:
	effects.append({"position": at_position, "radius": radius, "life": lifetime, "max_life": lifetime, "color": color})

func _update_effects(delta: float) -> void:
	for index in range(effects.size() - 1, -1, -1):
		effects[index].life -= delta
		if effects[index].life <= 0.0:
			effects.remove_at(index)

func _show_banner(text_value: String, duration: float = 1.0) -> void:
	banner_text = text_value
	banner_label.text = text_value
	banner_left = duration
	banner_label.visible = true

func _cleanup_arrays() -> void:
	enemies = enemies.filter(func(node): return is_instance_valid(node) and not node.is_queued_for_deletion())
	projectiles = projectiles.filter(func(node): return is_instance_valid(node) and not node.is_queued_for_deletion())
	pickups = pickups.filter(func(node): return is_instance_valid(node) and not node.is_queued_for_deletion())

func _debug_skip_wave() -> void:
	if phase != Phase.COMBAT:
		return
	spawn_queue.clear()
	spawn_finished = true
	_debug_kill_enemies()

func _debug_kill_enemies() -> void:
	for enemy in enemies.duplicate():
		if is_instance_valid(enemy): enemy.take_damage(99999.0)

func _load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		persistent_components = int(parsed.get("components", 0))

func _save_persistent() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"components": persistent_components}))
