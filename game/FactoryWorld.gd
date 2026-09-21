class_name FactoryWorld
extends Node2D

signal wave_requested(reason: String)
signal message_requested(text: String)
signal credits_found(amount: int)
signal state_changed
signal weapon_selected(index: int)

const CELL := GameBalance.FACTORY_CELL_SIZE
const MAP_CELLS := GameBalance.FACTORY_MAP_CELLS
const VIEW_SIZE := Vector2(1280.0, 720.0)
const COMMAND_CELL := Vector2i(32, 20)
const DIRECTIONS := [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
const DEFENSE_FRONT_ROW := 3
const DEFENSE_FRONT_DEPTH := 7

const ENGINEER_TEXTURE: Texture2D = preload("res://assets/stranded/engineer.png")
const TERRAIN_TEXTURE: Texture2D = preload("res://assets/stranded/terrain_tileset.png")
const TREE_ONE_TEXTURE: Texture2D = preload("res://assets/stranded/tree_1.png")
const TREE_THREE_TEXTURE: Texture2D = preload("res://assets/stranded/tree_3.png")
const BIG_ROCK_TEXTURE: Texture2D = preload("res://assets/stranded/big_rock.png")
const SMALL_ROCK_TEXTURE: Texture2D = preload("res://assets/stranded/small_rocks.png")
const ORE_TEXTURE: Texture2D = preload("res://assets/stranded/ores.png")
const DRILL_TEXTURE: Texture2D = preload("res://assets/stranded/mining_drill.png")
const BELT_TEXTURE: Texture2D = preload("res://assets/stranded/conveyor.png")
const AMMO_FACTORY_TEXTURE: Texture2D = preload("res://assets/stranded/ammo_factory.png")
const MISSILE_FACTORY_TEXTURE: Texture2D = preload("res://assets/stranded/missile_factory.png")
const STORAGE_TEXTURE: Texture2D = preload("res://assets/stranded/storage.png")
const COMMAND_TEXTURE: Texture2D = preload("res://assets/stranded/command_center.png")
const CRATE_TEXTURE: Texture2D = preload("res://assets/stranded/crate.png")
const DEFENSE_GUN_TEXTURE: Texture2D = preload("res://assets/stranded/defense_gun_turret.png")
const DEFENSE_MISSILE_TEXTURE: Texture2D = preload("res://assets/stranded/defense_missile.png")

var inventory: RunInventory
var active_controls := false
var simulation_active := false
var transition_locked := false
var stamina := GameBalance.ENGINEER_MAX_STAMINA
var engineer_position := _cell_center(COMMAND_CELL + Vector2i(-2, 1))
var facing := Vector2.DOWN
var walk_time := 0.0
var belt_animation := 0.0
var logistics_accumulator := 0.0
var logistics_debug_visible := false
var command_confirm_left := 0.0
var exhaustion_emitted := false

var explored_cells: Dictionary = {}
var mountain_cells: Dictionary = {}
var exposed_veins: Dictionary = {}
var vein_amounts: Dictionary = {}
var world_objects: Array[Dictionary] = []
var structures: Array[Dictionary] = []
var logistics := LogisticsNetwork.new()
var belts: Dictionary = logistics.belts
var splitters: Dictionary = logistics.splitters
var belt_visuals := BeltVisualSet.new()
var effects: Array[Dictionary] = []

var build_kind := ""
var build_rotation := 0
var preview_cell := Vector2i.ZERO
var preview_valid := false
var next_structure_id := 0
var production_totals := {"ore": 0, "mg": 0, "missiles": 0}
var defense_weapons: Array = []
var defense_cities: Array = []


func setup(shared_inventory: RunInventory) -> void:
	inventory = shared_inventory
	belt_visuals.fallback = BELT_TEXTURE
	reset_run()


func bind_defense_front(shared_weapons: Array, shared_cities: Array) -> void:
	# These are references to the combat entities, not factory-side copies.
	defense_weapons = shared_weapons
	defense_cities = shared_cities
	queue_redraw()


func reset_run() -> void:
	stamina = GameBalance.ENGINEER_MAX_STAMINA
	engineer_position = _cell_center(COMMAND_CELL + Vector2i(-2, 1))
	facing = Vector2.DOWN
	transition_locked = false
	exhaustion_emitted = false
	command_confirm_left = 0.0
	build_kind = ""
	build_rotation = 0
	explored_cells.clear()
	mountain_cells.clear()
	exposed_veins.clear()
	vein_amounts.clear()
	world_objects.clear()
	structures.clear()
	logistics.reset()
	belts = logistics.belts
	splitters = logistics.splitters
	logistics_accumulator = 0.0
	effects.clear()
	next_structure_id = 0
	production_totals = {"ore": 0, "mg": 0, "missiles": 0}
	_generate_map()
	_reveal_defense_front()
	_reveal_around(COMMAND_CELL, GameBalance.FOG_REVEAL_RADIUS)
	_recalculate_capacities()
	_update_camera()
	state_changed.emit()
	queue_redraw()


func begin_preparation() -> void:
	simulation_active = false
	transition_locked = false
	exhaustion_emitted = false
	stamina = GameBalance.ENGINEER_MAX_STAMINA
	engineer_position = _cell_center(COMMAND_CELL + Vector2i(-2, 1))
	build_kind = ""
	command_confirm_left = 0.0
	for structure in structures:
		if bool(structure.active): structure.status = "PAUSED"
	active_controls = visible
	_reveal_around(_world_to_cell(engineer_position), GameBalance.FOG_REVEAL_RADIUS)
	state_changed.emit()
	queue_redraw()


func begin_defense() -> void:
	active_controls = false
	simulation_active = true
	transition_locked = false
	build_kind = ""
	command_confirm_left = 0.0
	state_changed.emit()
	queue_redraw()


func set_factory_view(is_active: bool) -> void:
	visible = is_active
	active_controls = is_active and not simulation_active and not transition_locked
	if is_active:
		_update_camera()
	queue_redraw()


func _process(delta: float) -> void:
	_update_effects(delta)
	if command_confirm_left > 0.0:
		command_confirm_left = maxf(0.0, command_confirm_left - delta)
	if simulation_active:
		simulate_factory(delta)
	if not active_controls:
		queue_redraw()
		return
	var movement := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	if movement.length_squared() > 0.01:
		movement = movement.normalized()
		facing = movement
		walk_time += delta
		var proposed := engineer_position + movement * GameBalance.ENGINEER_SPEED * delta
		if not _position_blocked(proposed):
			engineer_position = proposed
		_reveal_around(_world_to_cell(engineer_position), GameBalance.FOG_REVEAL_RADIUS)
	else:
		walk_time = 0.0
	if not build_kind.is_empty():
		preview_cell = _world_to_cell(to_local(get_viewport().get_mouse_position()))
		preview_valid = _can_build(build_kind, preview_cell)
	_update_camera()
	queue_redraw()


func simulate_factory(delta: float) -> void:
	if not simulation_active:
		return
	belt_animation = fmod(belt_animation + delta * 8.0, 16.0)
	logistics_accumulator += maxf(0.0, delta)
	while logistics_accumulator >= GameBalance.LOGISTICS_FIXED_STEP:
		_simulate_factory_step(GameBalance.LOGISTICS_FIXED_STEP)
		logistics_accumulator -= GameBalance.LOGISTICS_FIXED_STEP
	queue_redraw()


func _simulate_factory_step(delta: float) -> void:
	var changed := false
	for structure in structures:
		if bool(structure.active):
			changed = _emit_buffered_output(structure) or changed
	for structure in structures:
		if not bool(structure.active):
			continue
		match str(structure.kind):
			"drill":
				changed = _simulate_drill(structure, delta) or changed
			"ammo_factory":
				changed = _simulate_ammo_machine(structure, delta, RunInventory.GATLING_AMMO, GameBalance.AMMO_FACTORY_ORE_COST, GameBalance.AMMO_FACTORY_OUTPUT, "RUNNING — MG AMMO") or changed
			"missile_factory":
				changed = _simulate_ammo_machine(structure, delta, RunInventory.MISSILE_AMMO, GameBalance.MISSILE_FACTORY_ORE_COST, GameBalance.MISSILE_FACTORY_OUTPUT, "RUNNING — MISSILE") or changed
			"storage":
				var stored: Array = structure.get("storage_inventory", [])
				structure.status = "STORAGE %d/%d" % [stored.size(), _effective_output_capacity(structure, GameBalance.STORAGE_PACKET_CAPACITY)]
	logistics.step(delta, _accept_transport_item)
	if changed:
		state_changed.emit()


func _simulate_drill(structure: Dictionary, delta: float) -> bool:
	var output_buffer: Array = structure.output_buffer
	var capacity := _effective_output_capacity(structure, GameBalance.DRILL_OUTPUT_BUFFER_CAPACITY)
	if int(structure.deposit_remaining) <= 0:
		structure.status = "DEPOSIT EMPTY"
		return false
	if output_buffer.size() >= capacity:
		structure.status = "OUTPUT FULL"
		return false
	var production_time := _effective_production_time(structure)
	structure.timer = minf(production_time, float(structure.timer) + delta)
	structure.status = "RUNNING — EXTRACTING"
	if float(structure.timer) < production_time:
		return false
	structure.timer = 0.0
	structure.deposit_remaining = int(structure.deposit_remaining) - 1
	output_buffer.append({"resource": RunInventory.ORE, "quantity": 1})
	production_totals.ore = int(production_totals.ore) + 1
	return true


func _simulate_ammo_machine(structure: Dictionary, delta: float, ammo_resource: String, base_ore_cost: int, base_output_amount: int, active_status: String) -> bool:
	var input_buffer: Dictionary = structure.input_buffer
	var ore_cost := maxi(1, ceili(float(base_ore_cost) * float(structure.modifiers.input_consumption)))
	var ore_available := int(input_buffer.get(RunInventory.ORE, 0))
	structure.ore_buffer = ore_available
	if ore_available < ore_cost:
		structure.status = "NO INPUT — NEED %d ORE" % ore_cost
		return false
	var output_buffer: Array = structure.output_buffer
	if output_buffer.size() >= _effective_output_capacity(structure, GameBalance.MACHINE_OUTPUT_BUFFER_CAPACITY):
		structure.status = "OUTPUT FULL"
		return false
	var production_time := _effective_production_time(structure)
	structure.timer = minf(production_time, float(structure.timer) + delta)
	structure.status = active_status
	if float(structure.timer) < production_time:
		return false
	structure.timer = 0.0
	input_buffer[RunInventory.ORE] = ore_available - ore_cost
	structure.ore_buffer = int(input_buffer[RunInventory.ORE])
	var output_amount := maxi(1, roundi(float(base_output_amount) * float(structure.modifiers.output_quantity)))
	output_buffer.append({"resource": ammo_resource, "quantity": output_amount})
	if ammo_resource == RunInventory.GATLING_AMMO:
		production_totals.mg = int(production_totals.mg) + output_amount
		_add_effect(_cell_center(structure.cell), "MG CRATE READY", Color("#ffd166"))
	else:
		production_totals.missiles = int(production_totals.missiles) + output_amount
		_add_effect(_cell_center(structure.cell), "MISSILE READY", Color("#79d8ff"))
	return true


func _emit_buffered_output(structure: Dictionary) -> bool:
	var buffered: Array = structure.storage_inventory if str(structure.kind) == "storage" else structure.output_buffer
	if buffered.is_empty():
		return false
	var item: Dictionary = buffered[0]
	var output_cell: Vector2i = structure.cell + DIRECTIONS[int(structure.rotation)]
	var used_lane := logistics.try_insert_from_endpoint(output_cell, str(item.resource), int(item.quantity), int(structure.rotation), str(structure.output_lane_mode), int(structure.next_output_lane))
	if used_lane < 0:
		structure.status = "OUTPUT BLOCKED"
		return false
	buffered.pop_front()
	if str(structure.output_lane_mode) == "AUTO":
		structure.next_output_lane = 1 - used_lane
	structure.status = "DISPATCHING LANE %d" % used_lane
	return true


func _accept_transport_item(cell: Vector2i, item: Dictionary, source_direction: int, _source_lane: int) -> bool:
	var front_weapon_index := _front_weapon_index_at(cell)
	if front_weapon_index >= 0:
		var expected_resource := _ammo_resource_for_weapon(defense_weapons[front_weapon_index])
		var quantity := int(item.quantity)
		if str(item.resource) != expected_resource or inventory.free_space(expected_resource) < quantity:
			return false
		inventory.add(expected_resource, quantity)
		_add_effect(_cell_center(cell), "+%d %s" % [quantity, "MG" if expected_resource == RunInventory.GATLING_AMMO else "MISSILE"], TransportResources.definition(expected_resource).visual_color)
		state_changed.emit()
		return true
	var receiver = _find_structure_at(cell)
	if receiver == null:
		return false
	if source_direction == (int(receiver.rotation) + 2) % 4:
		return false # The configured output side is never also an input port.
	var resource_id := str(item.resource)
	var quantity := int(item.quantity)
	if str(receiver.kind) in ["ammo_factory", "missile_factory"]:
		if resource_id != RunInventory.ORE:
			return false
		var input_buffer: Dictionary = receiver.input_buffer
		var input_capacity := _effective_input_capacity(receiver, GameBalance.MACHINE_INPUT_BUFFER_CAPACITY)
		if int(input_buffer.get(resource_id, 0)) + quantity > input_capacity:
			receiver.status = "OUTPUT FULL" if Array(receiver.output_buffer).size() >= _effective_output_capacity(receiver, GameBalance.MACHINE_OUTPUT_BUFFER_CAPACITY) else "INPUT FULL"
			return false
		input_buffer[resource_id] = int(input_buffer.get(resource_id, 0)) + quantity
		receiver.ore_buffer = int(input_buffer[resource_id])
		state_changed.emit()
		return true
	if str(receiver.kind) == "storage":
		var stored: Array = receiver.storage_inventory
		if stored.size() >= _effective_output_capacity(receiver, GameBalance.STORAGE_PACKET_CAPACITY):
			receiver.status = "INPUT FULL"
			return false
		stored.append({"resource": resource_id, "quantity": quantity})
		state_changed.emit()
		return true
	return false


func _effective_production_time(structure: Dictionary) -> float:
	return maxf(0.05, float(structure.base_production_time) / maxf(0.05, float(structure.modifiers.speed)))


func _effective_input_capacity(structure: Dictionary, base_capacity: int) -> int:
	return maxi(1, roundi(float(base_capacity) * float(structure.modifiers.input_buffer)))


func _effective_output_capacity(structure: Dictionary, base_capacity: int) -> int:
	return maxi(1, roundi(float(base_capacity) * float(structure.modifiers.output_buffer)))


func select_build(kind_id: String) -> void:
	if not active_controls or transition_locked:
		return
	build_kind = kind_id
	build_rotation = 0
	message_requested.emit("PLACE %s  •  R ROTATE  •  RMB CANCEL" % kind_id.replace("_", " ").to_upper())
	queue_redraw()


func cancel_build() -> bool:
	if build_kind.is_empty():
		return false
	build_kind = ""
	preview_valid = false
	message_requested.emit("BUILD CANCELLED")
	queue_redraw()
	return true


func interact() -> void:
	if not active_controls or transition_locked:
		return
	if engineer_position.distance_to(_cell_center(COMMAND_CELL)) <= 86.0:
		if command_confirm_left > 0.0:
			_request_wave("manual")
		else:
			command_confirm_left = 3.0
			message_requested.emit("BEGIN NEXT ATTACK?  PRESS E AGAIN")
		return
	var front_weapon_index := _nearest_front_weapon_index()
	if front_weapon_index >= 0:
		var weapon = defense_weapons[front_weapon_index]
		if not bool(weapon.unlocked):
			message_requested.emit("MISSILE NODE OFFLINE — UNLOCK IN COMMAND VIEW")
			return
		weapon_selected.emit(front_weapon_index)
		message_requested.emit("LINKED %s SELECTED — SAME WEAPON IN DEFENSE" % _weapon_display_name(weapon))
		queue_redraw()
		return
	var splitter_cell := _nearest_splitter_cell()
	if splitters.has(splitter_cell):
		_cycle_splitter_configuration(splitter_cell)
		return
	var nearest_index := -1
	var nearest_distance := 62.0
	for index in world_objects.size():
		var object: Dictionary = world_objects[index]
		if not bool(object.active):
			continue
		var distance := engineer_position.distance_to(_cell_center(object.cell))
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_index = index
	if nearest_index >= 0:
		_harvest_object(nearest_index)
		return
	var cell := _nearest_adjacent_mountain()
	if mountain_cells.has(cell):
		_dig_cell(cell)
		return
	var vein_cell := _nearest_exposed_vein()
	if exposed_veins.has(vein_cell):
		_gather_vein(vein_cell)
		return
	message_requested.emit("NOTHING TO INTERACT WITH")


func _unhandled_input(event: InputEvent) -> void:
	if not active_controls:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_E:
				interact()
				get_viewport().set_input_as_handled()
			KEY_R:
				if not build_kind.is_empty():
					build_rotation = (build_rotation + 1) % 4
					message_requested.emit("ROTATION %s" % ["EAST", "SOUTH", "WEST", "NORTH"][build_rotation])
					get_viewport().set_input_as_handled()
				else:
					var rotate_cell := _world_to_cell(to_local(get_viewport().get_mouse_position()))
					if belts.has(rotate_cell):
						if logistics.rotate_belt(rotate_cell, int(belts[rotate_cell].direction) + 1):
							message_requested.emit("BELT ROTATED")
						else:
							message_requested.emit("BELT OCCUPIED — ROTATION BLOCKED")
						get_viewport().set_input_as_handled()
			KEY_V:
				logistics_debug_visible = not logistics_debug_visible
				message_requested.emit("LOGISTICS DEBUG %s" % ("ON" if logistics_debug_visible else "OFF"))
				queue_redraw()
				get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and not build_kind.is_empty():
			preview_cell = _world_to_cell(to_local(event.position))
			_place_selected_building()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if not cancel_build():
				_remove_belt_at(_world_to_cell(to_local(event.position)))
			get_viewport().set_input_as_handled()


func _generate_map() -> void:
	var tree_cells := [Vector2i(27, 18), Vector2i(28, 23), Vector2i(35, 23), Vector2i(38, 18), Vector2i(25, 15), Vector2i(40, 25), Vector2i(34, 13), Vector2i(22, 22), Vector2i(45, 28), Vector2i(16, 25)]
	for index in tree_cells.size():
		world_objects.append({"kind": "tree", "cell": tree_cells[index], "active": true, "variant": index % 2})
	var small_rocks := [Vector2i(29, 17), Vector2i(36, 17), Vector2i(38, 22), Vector2i(24, 20), Vector2i(42, 18), Vector2i(18, 27)]
	for cell in small_rocks:
		world_objects.append({"kind": "small_rock", "cell": cell, "active": true, "variant": 0})
	for cell in [Vector2i(23, 17), Vector2i(41, 22), Vector2i(47, 26)]:
		world_objects.append({"kind": "large_rock", "cell": cell, "active": true, "variant": 0})
	for cell in [Vector2i(30, 24), Vector2i(36, 24), Vector2i(39, 20)]:
		world_objects.append({"kind": "surface_ore", "cell": cell, "active": true, "variant": 0})
	for cell in [Vector2i(26, 12), Vector2i(48, 25)]:
		world_objects.append({"kind": "crate", "cell": cell, "active": true, "variant": 0})
	_add_mountain_mass(Vector2i(16, 11), Vector2i(7, 5), 1)
	_add_mountain_mass(Vector2i(49, 14), Vector2i(9, 7), 2)
	_add_mountain_mass(Vector2i(27, 34), Vector2i(10, 5), 3)
	_set_hidden_vein(Vector2i(17, 11), "ore", 24)
	_set_hidden_vein(Vector2i(48, 15), "ore", 30)
	_set_hidden_vein(Vector2i(51, 16), "rare", 12)
	_set_hidden_vein(Vector2i(27, 34), "ore", 36)
	# One exposed but initially fogged vein teaches exploration before digging.
	exposed_veins[Vector2i(42, 20)] = "ore"
	vein_amounts[Vector2i(42, 20)] = 18


func _add_mountain_mass(center: Vector2i, radii: Vector2i, seed: int) -> void:
	for x in range(center.x - radii.x, center.x + radii.x + 1):
		for y in range(center.y - radii.y, center.y + radii.y + 1):
			var normalized := pow(float(x - center.x) / float(radii.x), 2.0) + pow(float(y - center.y) / float(radii.y), 2.0)
			if normalized <= 1.0 + float((x * 7 + y * 11 + seed) % 5) * 0.035:
				var cell := Vector2i(x, y)
				mountain_cells[cell] = "hard" if (x + y + seed) % 7 == 0 else "normal"


func _set_hidden_vein(cell: Vector2i, kind_id: String, amount: int) -> void:
	mountain_cells[cell] = "rare" if kind_id == "rare" else "ore"
	vein_amounts[cell] = amount


func _harvest_object(index: int) -> void:
	var object: Dictionary = world_objects[index]
	var kind_id := str(object.kind)
	var cost := GameBalance.STAMINA_TREE
	if kind_id == "small_rock": cost = GameBalance.STAMINA_SMALL_ROCK
	if kind_id == "large_rock": cost = GameBalance.STAMINA_LARGE_ROCK
	if kind_id == "surface_ore": cost = GameBalance.STAMINA_GATHER_ORE
	if kind_id == "crate": cost = 0
	if not _spend_stamina(cost, kind_id.replace("_", " ").to_upper()):
		return
	object.active = false
	var at_position := _cell_center(object.cell)
	match kind_id:
		"tree":
			inventory.add(RunInventory.WOOD, 3)
			_add_effect(at_position, "+3 WOOD", Color("#92d06d"))
		"small_rock":
			inventory.add(RunInventory.STONE, 3)
			if (int(object.cell.x) + int(object.cell.y)) % 3 == 0: inventory.add(RunInventory.ORE, 1)
			_add_effect(at_position, "+3 STONE", Color("#c1b8aa"))
		"large_rock":
			inventory.add(RunInventory.STONE, 5)
			inventory.add(RunInventory.ORE, 1)
			_add_effect(at_position, "+5 STONE  +1 ORE", Color("#d7c7ae"))
		"surface_ore":
			inventory.add(RunInventory.ORE, 2)
			_add_effect(at_position, "+2 ORE", Color("#72d6a0"))
		"crate":
			credits_found.emit(25)
			inventory.add(RunInventory.GATLING_AMMO, 100)
			_add_effect(at_position, "CACHE: +25 CREDITS  +100 MG", Color("#ffd166"))
	message_requested.emit("%s CLEARED" % kind_id.replace("_", " ").to_upper())
	state_changed.emit()
	queue_redraw()


func _dig_cell(cell: Vector2i) -> void:
	var tile_kind := str(mountain_cells.get(cell, "normal"))
	var cost := GameBalance.STAMINA_DIG_HARD if tile_kind == "hard" or tile_kind == "rare" else GameBalance.STAMINA_DIG_NORMAL
	if not _spend_stamina(cost, "DIG"):
		return
	mountain_cells.erase(cell)
	if tile_kind in ["ore", "rare"]:
		exposed_veins[cell] = "rare" if tile_kind == "rare" else "ore"
		message_requested.emit("ENERGY CRYSTAL VEIN DISCOVERED" if tile_kind == "rare" else "RICH ORE DISCOVERED")
		_add_effect(_cell_center(cell), "DISCOVERY", Color("#c58cff") if tile_kind == "rare" else Color("#72d6a0"))
	else:
		inventory.add(RunInventory.STONE, 1)
		_add_effect(_cell_center(cell), "+1 STONE", Color("#b8afa3"))
	state_changed.emit()
	queue_redraw()


func _gather_vein(cell: Vector2i) -> void:
	if int(vein_amounts.get(cell, 0)) <= 0 or not _spend_stamina(GameBalance.STAMINA_GATHER_ORE, "GATHER ORE"):
		return
	var resource_id := RunInventory.ADVANCED_RESOURCE if str(exposed_veins[cell]) == "rare" else RunInventory.ORE
	var amount := 1 if resource_id == RunInventory.ADVANCED_RESOURCE else 2
	inventory.add(resource_id, amount)
	vein_amounts[cell] = maxi(0, int(vein_amounts[cell]) - amount)
	_add_effect(_cell_center(cell), "+%d %s" % [amount, "CRYSTAL" if resource_id == RunInventory.ADVANCED_RESOURCE else "ORE"], Color("#c58cff") if resource_id == RunInventory.ADVANCED_RESOURCE else Color("#72d6a0"))
	state_changed.emit()


func _place_selected_building() -> bool:
	if build_kind.is_empty() or not _can_build(build_kind, preview_cell):
		message_requested.emit("INVALID BUILD LOCATION")
		return false
	var recipe: Dictionary = GameBalance.BUILD_RECIPES.get(build_kind, {})
	if not _can_afford(recipe):
		message_requested.emit("MISSING BUILD MATERIALS")
		return false
	var stamina_cost := int(recipe.get("stamina", 0))
	if stamina < stamina_cost:
		message_requested.emit("NOT ENOUGH STAMINA")
		return false
	_consume_recipe(recipe)
	_spend_stamina(stamina_cost, "CONSTRUCTION")
	if build_kind == "belt":
		logistics.add_belt(preview_cell, build_rotation)
	elif build_kind == "splitter":
		logistics.add_splitter(preview_cell, build_rotation)
	else:
		var deposit_remaining := int(vein_amounts.get(preview_cell, 0)) if build_kind == "drill" else 0
		var base_production_time := GameBalance.DRILL_INTERVAL
		if build_kind == "ammo_factory": base_production_time = GameBalance.AMMO_FACTORY_INTERVAL
		if build_kind == "missile_factory": base_production_time = GameBalance.MISSILE_FACTORY_INTERVAL
		structures.append({
			"id": next_structure_id,
			"kind": build_kind,
			"cell": preview_cell,
			"rotation": build_rotation,
			"timer": 0.0,
			"ore_buffer": 0,
			"deposit_remaining": deposit_remaining,
			"active": true,
			"status": "READY",
			"input_buffer": {},
			"output_buffer": [],
			"storage_inventory": [],
			"base_production_time": base_production_time,
			"output_lane_mode": "AUTO",
			"next_output_lane": 0,
			"modifiers": {
				"speed": 1.0,
				"input_consumption": 1.0,
				"output_quantity": 1.0,
				"input_buffer": 1.0,
				"output_buffer": 1.0,
			},
		})
		next_structure_id += 1
		if build_kind == "storage": _recalculate_capacities()
	_add_effect(_cell_center(preview_cell), "BUILT", Color("#72d6a0"))
	message_requested.emit("%s BUILT" % build_kind.replace("_", " ").to_upper())
	state_changed.emit()
	queue_redraw()
	return true


func _can_build(kind_id: String, cell: Vector2i) -> bool:
	if transition_locked or not _cell_in_bounds(cell) or not explored_cells.has(cell):
		return false
	if mountain_cells.has(cell) or _active_object_at(cell) or cell.distance_to(COMMAND_CELL) < 3.0 or _front_cell_occupied(cell):
		return false
	if logistics.cell_occupied(cell) or _find_structure_at(cell) != null:
		return false
	if kind_id == "drill":
		return exposed_veins.has(cell) and int(vein_amounts.get(cell, 0)) > 0
	if kind_id not in ["belt", "splitter"] and exposed_veins.has(cell):
		return false
	return true


func _can_afford(recipe: Dictionary) -> bool:
	return inventory.can_consume(RunInventory.WOOD, int(recipe.get("wood", 0))) and inventory.can_consume(RunInventory.STONE, int(recipe.get("stone", 0))) and inventory.can_consume(RunInventory.ORE, int(recipe.get("ore", 0)))


func _consume_recipe(recipe: Dictionary) -> void:
	inventory.consume(RunInventory.WOOD, int(recipe.get("wood", 0)))
	inventory.consume(RunInventory.STONE, int(recipe.get("stone", 0)))
	inventory.consume(RunInventory.ORE, int(recipe.get("ore", 0)))


func _remove_belt_at(cell: Vector2i) -> void:
	if belts.has(cell):
		if not logistics.remove_belt(cell):
			message_requested.emit("BELT OCCUPIED — REMOVE ITEMS FIRST")
			return
		message_requested.emit("BELT REMOVED")
		state_changed.emit()
		queue_redraw()
	elif splitters.has(cell):
		if not logistics.remove_splitter(cell):
			message_requested.emit("SPLITTER OCCUPIED — REMOVE ITEMS FIRST")
			return
		message_requested.emit("SPLITTER REMOVED")
		state_changed.emit()
		queue_redraw()


func _find_structure_at(cell: Vector2i):
	for structure in structures:
		if bool(structure.active) and structure.cell == cell:
			return structure
	return null


func _recalculate_capacities() -> void:
	# Weapon depots own the authoritative ammo capacities. Factory Storage is a
	# real finite transport inventory rather than an abstract capacity upgrade.
	inventory.set_capacity(RunInventory.GATLING_AMMO, GameBalance.BASE_GATLING_CAPACITY)
	inventory.set_capacity(RunInventory.MISSILE_AMMO, GameBalance.BASE_MISSILE_CAPACITY)


func _spend_stamina(amount: int, action: String) -> bool:
	if amount <= 0:
		return true
	if stamina < amount or transition_locked:
		message_requested.emit("NOT ENOUGH STAMINA")
		return false
	stamina -= amount
	message_requested.emit("%s  -%d STAMINA" % [action, amount])
	state_changed.emit()
	if stamina <= 0 and not exhaustion_emitted:
		exhaustion_emitted = true
		call_deferred("_request_wave", "exhausted")
	return true


func _request_wave(reason: String) -> void:
	if transition_locked:
		return
	transition_locked = true
	active_controls = false
	build_kind = ""
	engineer_position = _cell_center(COMMAND_CELL + Vector2i(-2, 1))
	message_requested.emit("ENGINEER EXHAUSTED" if reason == "exhausted" else "COMMAND CONFIRMED")
	wave_requested.emit(reason)
	queue_redraw()


func _position_blocked(world_position: Vector2) -> bool:
	var cell := _world_to_cell(world_position)
	if not _cell_in_bounds(cell) or mountain_cells.has(cell):
		return true
	if cell.distance_to(COMMAND_CELL) <= 1.15:
		return true
	if _active_object_at(cell):
		return true
	if _find_structure_at(cell) != null:
		return true
	if splitters.has(cell):
		return true
	if _front_cell_occupied(cell):
		return true
	return false


func _active_object_at(cell: Vector2i) -> bool:
	for object in world_objects:
		if bool(object.active) and object.cell == cell and str(object.kind) != "surface_ore" and str(object.kind) != "crate":
			return true
	return false


func _nearest_adjacent_mountain() -> Vector2i:
	var best := Vector2i(-999, -999)
	var best_distance := 62.0
	for direction in DIRECTIONS:
		var cell: Vector2i = _world_to_cell(engineer_position) + Vector2i(direction)
		if mountain_cells.has(cell):
			var distance := engineer_position.distance_to(_cell_center(cell))
			if distance < best_distance:
				best = cell
				best_distance = distance
	return best


func _nearest_exposed_vein() -> Vector2i:
	var best := Vector2i(-999, -999)
	var best_distance := 62.0
	for cell in exposed_veins:
		var distance := engineer_position.distance_to(_cell_center(cell))
		if distance < best_distance:
			best = cell
			best_distance = distance
	return best


func _nearest_splitter_cell() -> Vector2i:
	var best := Vector2i(-999, -999)
	var best_distance := 62.0
	for cell in splitters:
		var distance := engineer_position.distance_to(_cell_center(cell))
		if distance < best_distance:
			best = cell
			best_distance = distance
	return best


func _nearest_structure():
	var best = null
	var best_distance := 62.0
	for structure in structures:
		if not bool(structure.active):
			continue
		var distance := engineer_position.distance_to(_cell_center(structure.cell))
		if distance < best_distance:
			best = structure
			best_distance = distance
	return best


func _cycle_splitter_configuration(cell: Vector2i) -> void:
	var splitter: Dictionary = splitters[cell]
	splitter.config_index = (int(splitter.config_index) + 1) % 5
	match int(splitter.config_index):
		0:
			logistics.configure_splitter(cell)
		1:
			logistics.configure_splitter(cell, LogisticsNetwork.OUTPUT_A_PRIORITY)
		2:
			logistics.configure_splitter(cell, LogisticsNetwork.OUTPUT_B_PRIORITY)
		3:
			logistics.configure_splitter(cell, LogisticsNetwork.OUTPUT_NONE, RunInventory.ORE, LogisticsNetwork.FILTER_STRICT)
		4:
			logistics.configure_splitter(cell, LogisticsNetwork.OUTPUT_NONE, RunInventory.ORE, LogisticsNetwork.FILTER_OVERFLOW)
	message_requested.emit("SPLITTER: %s" % _splitter_configuration_text(splitter))
	queue_redraw()


func _splitter_configuration_text(splitter: Dictionary) -> String:
	match int(splitter.get("config_index", 0)):
		1: return "OUTPUT A PRIORITY"
		2: return "OUTPUT B PRIORITY"
		3: return "ORE FILTER — STRICT"
		4: return "ORE FILTER — OVERFLOW"
		_: return "BALANCE"


func defense_front_cell_for_weapon(index: int) -> Vector2i:
	if index < 0 or index >= defense_weapons.size() or not is_instance_valid(defense_weapons[index]):
		return Vector2i(-999, -999)
	var normalized_x: float = clampf(float(defense_weapons[index].position.x) / VIEW_SIZE.x, 0.0, 1.0)
	return Vector2i(clampi(roundi(normalized_x * float(MAP_CELLS.x - 1)), 2, MAP_CELLS.x - 3), DEFENSE_FRONT_ROW)


func defense_front_snapshot(index: int) -> Dictionary:
	if index < 0 or index >= defense_weapons.size() or not is_instance_valid(defense_weapons[index]):
		return {}
	var weapon = defense_weapons[index]
	var ammo_resource := _ammo_resource_for_weapon(weapon)
	return {
		"weapon": weapon,
		"cell": defense_front_cell_for_weapon(index),
		"unlocked": bool(weapon.unlocked),
		"selected": bool(weapon.selected),
		"ammo_resource": ammo_resource,
		"ammo": inventory.amount(ammo_resource),
		"capacity": inventory.capacity(ammo_resource),
	}


func _front_weapon_index_at(cell: Vector2i) -> int:
	for index in defense_weapons.size():
		if defense_front_cell_for_weapon(index) == cell:
			return index
	return -1


func _front_city_cell(index: int) -> Vector2i:
	if index < 0 or index >= defense_cities.size() or not is_instance_valid(defense_cities[index]):
		return Vector2i(-999, -999)
	var normalized_x: float = clampf(float(defense_cities[index].position.x) / VIEW_SIZE.x, 0.0, 1.0)
	return Vector2i(clampi(roundi(normalized_x * float(MAP_CELLS.x - 1)), 1, MAP_CELLS.x - 2), DEFENSE_FRONT_ROW)


func _front_cell_occupied(cell: Vector2i) -> bool:
	if _front_weapon_index_at(cell) >= 0:
		return true
	for index in defense_cities.size():
		if _front_city_cell(index) == cell:
			return true
	return false


func _nearest_front_weapon_index() -> int:
	var best_index := -1
	var best_distance := 68.0
	for index in defense_weapons.size():
		var distance := engineer_position.distance_to(_cell_center(defense_front_cell_for_weapon(index)))
		if distance < best_distance:
			best_distance = distance
			best_index = index
	return best_index


func _ammo_resource_for_weapon(weapon) -> String:
	return RunInventory.MISSILE_AMMO if int(weapon.kind) == PlayerWeapon.Kind.MISSILE else RunInventory.GATLING_AMMO


func _weapon_display_name(weapon) -> String:
	return "MISSILE NODE" if int(weapon.kind) == PlayerWeapon.Kind.MISSILE else "BASIC MG"


func _reveal_defense_front() -> void:
	for x in MAP_CELLS.x:
		for y in DEFENSE_FRONT_DEPTH:
			explored_cells[Vector2i(x, y)] = true


func _reveal_around(center: Vector2i, radius: int) -> void:
	for x in range(center.x - radius, center.x + radius + 1):
		for y in range(center.y - radius, center.y + radius + 1):
			var cell := Vector2i(x, y)
			if _cell_in_bounds(cell) and cell.distance_to(center) <= float(radius) + 0.35:
				explored_cells[cell] = true


func reveal_all() -> void:
	for x in MAP_CELLS.x:
		for y in MAP_CELLS.y:
			explored_cells[Vector2i(x, y)] = true
	state_changed.emit()
	queue_redraw()


func reveal_all_veins() -> void:
	for cell in mountain_cells.keys():
		if str(mountain_cells[cell]) in ["ore", "rare"]:
			explored_cells[cell] = true
	message_requested.emit("VEIN LOCATIONS REVEALED")
	queue_redraw()


func refill_stamina() -> void:
	stamina = GameBalance.ENGINEER_MAX_STAMINA
	exhaustion_emitted = false
	state_changed.emit()


func _update_camera() -> void:
	var map_size := Vector2(MAP_CELLS.x * CELL, MAP_CELLS.y * CELL)
	var desired := VIEW_SIZE * 0.5 - engineer_position
	position = Vector2(clampf(desired.x, VIEW_SIZE.x - map_size.x, 0.0), clampf(desired.y, VIEW_SIZE.y - map_size.y, 0.0))


func _add_effect(world_position: Vector2, text_value: String, color: Color) -> void:
	effects.append({"position": world_position, "text": text_value, "color": color, "life": 1.6})


func _update_effects(delta: float) -> void:
	for index in range(effects.size() - 1, -1, -1):
		effects[index].life = float(effects[index].life) - delta
		effects[index].position = effects[index].position + Vector2.UP * 18.0 * delta
		if float(effects[index].life) <= 0.0:
			effects.remove_at(index)


func context_text() -> String:
	if not build_kind.is_empty():
		return "BUILD: %s  |  LMB place  R rotate  RMB cancel" % build_kind.replace("_", " ").to_upper()
	if engineer_position.distance_to(_cell_center(COMMAND_CELL)) <= 86.0:
		return "E  COMMAND CENTER — BEGIN NEXT ATTACK"
	var front_weapon_index := _nearest_front_weapon_index()
	if front_weapon_index >= 0:
		var snapshot := defense_front_snapshot(front_weapon_index)
		return "E  LINKED %s — %d/%d — SELECT SAME COMBAT WEAPON" % [_weapon_display_name(snapshot.weapon), snapshot.ammo, snapshot.capacity]
	var splitter_cell := _nearest_splitter_cell()
	if splitters.has(splitter_cell):
		return "E  SPLITTER — %s  •  V DEBUG LANES" % _splitter_configuration_text(splitters[splitter_cell])
	var nearby_structure = _nearest_structure()
	if nearby_structure != null:
		return "%s — %s  •  V DEBUG PORTS" % [str(nearby_structure.kind).replace("_", " ").to_upper(), str(nearby_structure.status)]
	for object in world_objects:
		if bool(object.active) and engineer_position.distance_to(_cell_center(object.cell)) < 62.0:
			return "E  %s" % str(object.kind).replace("_", " ").to_upper()
	if mountain_cells.has(_nearest_adjacent_mountain()):
		return "E  DIG MOUNTAIN"
	if exposed_veins.has(_nearest_exposed_vein()):
		return "E  GATHER ORE"
	return "WASD move  •  E interact  •  V logistics debug  •  TAB command view"


func _draw() -> void:
	var map_rect := Rect2(Vector2.ZERO, Vector2(MAP_CELLS.x * CELL, MAP_CELLS.y * CELL))
	draw_rect(map_rect, Color("#263c35"))
	for x in range(0, MAP_CELLS.x, 2):
		for y in range(0, MAP_CELLS.y, 2):
			var tint := Color(0.42, 0.55, 0.39, 0.18 + float((x * 3 + y * 5) % 3) * 0.035)
			draw_texture_rect_region(TERRAIN_TEXTURE, Rect2(Vector2(x * CELL, y * CELL), Vector2(CELL * 2, CELL * 2)), Rect2(64, 64, 16, 16), tint)
	_draw_defense_front_ground()
	for cell in mountain_cells:
		var kind_id := str(mountain_cells[cell])
		var color := Color("#4b4744") if kind_id != "hard" else Color("#35383b")
		draw_rect(Rect2(Vector2(cell.x * CELL, cell.y * CELL), Vector2(CELL, CELL)), color)
		draw_rect(Rect2(Vector2(cell.x * CELL + 2, cell.y * CELL + 2), Vector2(CELL - 4, CELL - 4)), Color("#777069"), false, 2.0)
		if kind_id == "hard": draw_circle(_cell_center(cell), 5.0, Color("#282a2d"))
	for cell in exposed_veins:
		var source_x := 0.0 if str(exposed_veins[cell]) == "ore" else 64.0
		draw_texture_rect_region(ORE_TEXTURE, Rect2(_cell_center(cell) - Vector2(16, 16), Vector2(32, 32)), Rect2(source_x, 0, 16, 16))
	for object in world_objects:
		if not bool(object.active): continue
		var center := _cell_center(object.cell)
		match str(object.kind):
			"tree":
				var texture := TREE_ONE_TEXTURE if int(object.variant) == 0 else TREE_THREE_TEXTURE
				draw_texture_rect(texture, Rect2(center - Vector2(36, 45), Vector2(72, 58)), false)
			"small_rock": draw_texture_rect(SMALL_ROCK_TEXTURE, Rect2(center - Vector2(24, 14), Vector2(48, 24)), false)
			"large_rock": draw_texture_rect(BIG_ROCK_TEXTURE, Rect2(center - Vector2(48, 23), Vector2(96, 46)), false)
			"surface_ore": draw_texture_rect_region(ORE_TEXTURE, Rect2(center - Vector2(16, 16), Vector2(32, 32)), Rect2(0, 0, 16, 16))
			"crate": draw_texture_rect_region(CRATE_TEXTURE, Rect2(center - Vector2(20, 20), Vector2(40, 40)), Rect2(0, 0, 32, 32))
	_draw_belt_network()
	for structure in structures:
		if not bool(structure.active): continue
		_draw_structure(structure)
	_draw_defense_front_entities()
	var command_center := _cell_center(COMMAND_CELL)
	draw_texture_rect_region(COMMAND_TEXTURE, Rect2(command_center - Vector2(48, 48), Vector2(96, 96)), Rect2(0, 0, 32, 32))
	draw_arc(command_center, 53.0, 0.0, TAU, 36, Color("#79d8ff"), 3.0)
	draw_string(ThemeDB.fallback_font, command_center + Vector2(-70, 68), "COMMAND CENTER", HORIZONTAL_ALIGNMENT_CENTER, 140, 13, Color("#d9f5ff"))
	var walk_frame := int(walk_time * 8.0) % 5 if walk_time > 0.0 else 0
	draw_texture_rect_region(ENGINEER_TEXTURE, Rect2(engineer_position - Vector2(24, 28), Vector2(48, 48)), Rect2(walk_frame * 32, 0, 32, 32))
	draw_circle(engineer_position + Vector2(0, 21), 14.0, Color(0.1, 0.05, 0.03, 0.24))
	for effect in effects:
		draw_string(ThemeDB.fallback_font, effect.position, str(effect.text), HORIZONTAL_ALIGNMENT_CENTER, 120, 13, Color(effect.color, clampf(float(effect.life), 0.0, 1.0)))
	_draw_fog()
	if not build_kind.is_empty():
		var preview_color := Color(0.3, 1.0, 0.55, 0.72) if preview_valid else Color(1.0, 0.28, 0.3, 0.72)
		draw_rect(Rect2(Vector2(preview_cell.x * CELL, preview_cell.y * CELL), Vector2(CELL, CELL)), Color(preview_color, 0.24))
		draw_rect(Rect2(Vector2(preview_cell.x * CELL, preview_cell.y * CELL), Vector2(CELL, CELL)), preview_color, false, 3.0)


func _draw_structure(structure: Dictionary) -> void:
	var center := _cell_center(structure.cell)
	var texture: Texture2D = DRILL_TEXTURE
	var source := Rect2(0, 0, 32, 32)
	match str(structure.kind):
		"ammo_factory": texture = AMMO_FACTORY_TEXTURE
		"missile_factory": texture = MISSILE_FACTORY_TEXTURE
		"storage":
			texture = STORAGE_TEXTURE
			source = Rect2(0, 0, 32, 32)
	draw_texture_rect_region(texture, Rect2(center - Vector2(32, 32), Vector2(64, 64)), source)
	if str(structure.kind) in ["drill", "ammo_factory", "missile_factory", "storage"]:
		var output_direction := Vector2(DIRECTIONS[int(structure.rotation)])
		draw_line(center, center + output_direction * 27.0, Color("#ffd166"), 4.0)
		draw_circle(center + output_direction * 27.0, 3.5, Color("#fff2b2"))
	if str(structure.kind) in ["ammo_factory", "missile_factory"]:
		var interval := _effective_production_time(structure)
		var progress := clampf(float(structure.timer) / interval, 0.0, 1.0)
		draw_rect(Rect2(center + Vector2(-24, 27), Vector2(48, 5)), Color("#17242d"))
		draw_rect(Rect2(center + Vector2(-24, 27), Vector2(48 * progress, 5)), Color("#72d6a0"))
	if str(structure.kind) == "storage":
		var stored_count: int = Array(structure.get("storage_inventory", [])).size()
		draw_string(ThemeDB.fallback_font, center + Vector2(-28, 35), "%d/%d" % [stored_count, GameBalance.STORAGE_PACKET_CAPACITY], HORIZONTAL_ALIGNMENT_CENTER, 56, 11, Color("#e8f0ff"))
	if logistics_debug_visible:
		for port_direction in 4:
			var port_color := Color("#ffd166") if port_direction == int(structure.rotation) else Color("#72d6a0")
			draw_circle(center + Vector2(DIRECTIONS[port_direction]) * 25.0, 4.0, port_color)
		var input_count := 0
		for amount in Dictionary(structure.input_buffer).values(): input_count += int(amount)
		var output_count := Array(structure.output_buffer).size() if str(structure.kind) != "storage" else Array(structure.storage_inventory).size()
		draw_string(ThemeDB.fallback_font, center + Vector2(-60, -42), "%s  IN:%d OUT:%d" % [str(structure.status), input_count, output_count], HORIZONTAL_ALIGNMENT_CENTER, 120, 10, Color("#ffffff"))


func _draw_belt_network() -> void:
	for cell in belts:
		var rect := Rect2(Vector2(cell.x * CELL, cell.y * CELL), Vector2(CELL, CELL))
		draw_rect(rect, Color("#1d2b31"))
		draw_rect(rect.grow(-1.0), Color("#657078"), false, 1.5)
		var topology := logistics.topology_for(cell)
		var texture := belt_visuals.texture_for(topology)
		if texture != null:
			if texture == BELT_TEXTURE:
				var frame := int(belt_animation) % 16
				draw_texture_rect_region(texture, rect, Rect2(frame * 16, 0, 16, 16), Color(1, 1, 1, 0.34))
			else:
				draw_texture_rect(texture, rect, false)
		for lane in 2:
			var points := logistics.lane_path_points(cell, lane, float(CELL), 8)
			var lane_color := Color("#63d4ff") if lane == 0 else Color("#ff9bc9")
			draw_polyline(points, Color(lane_color, 0.95 if logistics_debug_visible else 0.48), 2.0 if logistics_debug_visible else 1.2, true)
			if logistics_debug_visible and logistics.leading_item_blocked(cell, lane):
				draw_circle(points[points.size() - 1], 4.0, Color("#ff4f64"))
		if logistics_debug_visible:
			for incoming_direction in Array(belts[cell].incoming):
				if int(incoming_direction) == int(belts[cell].primary_input):
					continue
				var destination_lane := logistics.side_load_destination_lane(int(incoming_direction), int(belts[cell].direction))
				var source_edge := _cell_center(cell) - Vector2(DIRECTIONS[int(incoming_direction)]) * CELL * 0.48
				var lane_points := logistics.lane_path_points(cell, destination_lane, float(CELL), 8)
				draw_line(source_edge, lane_points[2], Color("#ffdf70"), 2.0)
				draw_string(ThemeDB.fallback_font, source_edge + Vector2(-8, -4), "L%d" % destination_lane, HORIZONTAL_ALIGNMENT_CENTER, 16, 8, Color("#ffdf70"))
		var direction := Vector2(DIRECTIONS[int(belts[cell].direction)])
		draw_line(_cell_center(cell) - direction * 4.0, _cell_center(cell) + direction * 7.0, Color("#fff2b2"), 2.0)
	for cell in splitters:
		_draw_splitter(cell, splitters[cell])
	for item in logistics.all_items():
		if belts.has(item.cell):
			_draw_transport_item(item)


func _draw_transport_item(item: Dictionary) -> void:
	var position_value := logistics.item_world_position(item, float(CELL))
	var definition := TransportResources.definition(str(item.resource))
	var texture: Texture2D = definition.texture
	var scale_value: Vector2 = definition.visual_scale
	var offset: Vector2 = definition.visual_offset
	if texture != null:
		var size := Vector2(12, 12) * scale_value
		draw_texture_rect(texture, Rect2(position_value + offset - size * 0.5, size), false)
	else:
		var color: Color = definition.visual_color
		draw_circle(position_value, 5.5, color)
		draw_circle(position_value, 2.5, Color("#152028"))
	if int(item.quantity) > 1:
		draw_string(ThemeDB.fallback_font, position_value + Vector2(5, -5), str(item.quantity), HORIZONTAL_ALIGNMENT_LEFT, 34, 9, Color.WHITE)


func _draw_splitter(cell: Vector2i, splitter: Dictionary) -> void:
	var center := _cell_center(cell)
	var rect := Rect2(center - Vector2(15, 15), Vector2(30, 30))
	draw_rect(rect, Color("#273944"))
	draw_rect(rect, Color("#d59bff"), false, 2.0)
	var outputs := logistics.splitter_output_cells(cell)
	for output_cell in outputs:
		draw_line(center, _cell_center(output_cell), Color("#d59bff"), 2.0)
	draw_string(ThemeDB.fallback_font, center + Vector2(-10, 4), "S", HORIZONTAL_ALIGNMENT_CENTER, 20, 12, Color.WHITE)
	var buffers: Array = splitter.buffers
	for lane in 2:
		if not Array(buffers[lane]).is_empty():
			var item: Dictionary = Array(buffers[lane])[0]
			draw_circle(center + Vector2(0, -5 if lane == 0 else 5), 4.0, TransportResources.definition(str(item.resource)).visual_color)
	if logistics_debug_visible:
		var filter_text := str(splitter.filter_resource)
		var mode_text := "BAL" if filter_text.is_empty() else ("F:" + filter_text)
		draw_string(ThemeDB.fallback_font, center + Vector2(-32, -22), mode_text, HORIZONTAL_ALIGNMENT_CENTER, 64, 9, Color("#f3dcff"))


func _draw_defense_front_ground() -> void:
	var front_rect := Rect2(0, 0, MAP_CELLS.x * CELL, DEFENSE_FRONT_DEPTH * CELL)
	draw_rect(front_rect, Color("#38454a"))
	for x in MAP_CELLS.x:
		var cell_rect := Rect2(x * CELL, 0, CELL, DEFENSE_FRONT_DEPTH * CELL)
		draw_rect(cell_rect, Color(0.18, 0.24, 0.25, 0.18 if x % 2 == 0 else 0.08))
	draw_line(Vector2(0, DEFENSE_FRONT_DEPTH * CELL), Vector2(MAP_CELLS.x * CELL, DEFENSE_FRONT_DEPTH * CELL), Color("#f0b84b"), 5.0)
	draw_string(ThemeDB.fallback_font, Vector2(18, 23), "NORTHERN DEFENSE FRONT  •  LIVE WEAPON LOGISTICS", HORIZONTAL_ALIGNMENT_LEFT, 520, 15, Color("#d9f5ff"))
	for x in range(1, MAP_CELLS.x, 4):
		draw_texture_rect_region(CRATE_TEXTURE, Rect2(Vector2(x * CELL, (DEFENSE_FRONT_DEPTH - 1) * CELL + 4), Vector2(24, 24)), Rect2(0, 0, 32, 32), Color(0.78, 0.82, 0.82, 0.72))


func _draw_defense_front_entities() -> void:
	for index in defense_cities.size():
		var city = defense_cities[index]
		if not is_instance_valid(city):
			continue
		var center := _cell_center(_front_city_cell(index))
		var city_color := Color("#4de3a4")
		if bool(city.destroyed):
			city_color = Color("#6a5258")
		elif float(city.health_ratio()) < 0.4:
			city_color = Color("#ff5d73")
		elif float(city.health_ratio()) < 0.75:
			city_color = Color("#ffb84d")
		draw_rect(Rect2(center + Vector2(-20, -17), Vector2(40, 30)), Color("#202d38"))
		for building in [Rect2(center + Vector2(-17, -10), Vector2(9, 20)), Rect2(center + Vector2(-6, -19), Vector2(11, 29)), Rect2(center + Vector2(8, -6), Vector2(8, 16))]:
			draw_rect(building, city_color)
		if float(city.shield_health) > 0.0:
			draw_arc(center, 25.0, PI, TAU, 20, Color("#62e8ff"), 3.0)
		draw_rect(Rect2(center + Vector2(-21, 17), Vector2(42, 4)), Color("#18242c"))
		draw_rect(Rect2(center + Vector2(-21, 17), Vector2(42.0 * float(city.health_ratio()), 4)), city_color)
		draw_string(ThemeDB.fallback_font, center + Vector2(-25, 34), "C%d" % (index + 1), HORIZONTAL_ALIGNMENT_CENTER, 50, 11, Color("#e8f0ff"))
	for index in defense_weapons.size():
		var weapon = defense_weapons[index]
		if not is_instance_valid(weapon):
			continue
		var snapshot := defense_front_snapshot(index)
		var center := _cell_center(snapshot.cell)
		var is_missile := int(weapon.kind) == PlayerWeapon.Kind.MISSILE
		var accent := Color("#79d8ff") if is_missile else Color("#ffd166")
		if not bool(snapshot.unlocked): accent = Color("#697680")
		draw_circle(center, 31.0, Color("#17242d"))
		draw_arc(center, 31.0, 0.0, TAU, 28, Color("#ffffff") if bool(snapshot.selected) else accent, 3.0)
		if is_missile:
			draw_texture_rect_region(DEFENSE_MISSILE_TEXTURE, Rect2(center - Vector2(18, 24), Vector2(36, 48)), Rect2(48, 40, 32, 40), Color.WHITE if bool(snapshot.unlocked) else Color(0.45, 0.48, 0.5, 0.8))
		else:
			draw_texture_rect_region(DEFENSE_GUN_TEXTURE, Rect2(center - Vector2(25, 25), Vector2(50, 50)), Rect2(0, 32, 32, 32))
		for direction in DIRECTIONS:
			draw_circle(center + Vector2(direction) * 31.0, 3.5, accent)
		var status := "OFFLINE" if not bool(snapshot.unlocked) else "%d/%d" % [snapshot.ammo, snapshot.capacity]
		draw_string(ThemeDB.fallback_font, center + Vector2(-66, 43), "%s  %s" % [_weapon_display_name(weapon), status], HORIZONTAL_ALIGNMENT_CENTER, 132, 11, accent)


func _draw_fog() -> void:
	for x in MAP_CELLS.x:
		for y in MAP_CELLS.y:
			var cell := Vector2i(x, y)
			if not explored_cells.has(cell):
				draw_rect(Rect2(Vector2(x * CELL, y * CELL), Vector2(CELL + 1, CELL + 1)), Color(0.015, 0.025, 0.035, 0.96))


static func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * CELL + CELL * 0.5, cell.y * CELL + CELL * 0.5)


static func _world_to_cell(world_position: Vector2) -> Vector2i:
	return Vector2i(floori(world_position.x / CELL), floori(world_position.y / CELL))


static func _cell_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < MAP_CELLS.x and cell.y < MAP_CELLS.y
