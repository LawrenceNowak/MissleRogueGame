class_name LogisticsNetwork
extends RefCounted

const DIRECTIONS := [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
const OUTPUT_NONE := "NONE"
const OUTPUT_A_PRIORITY := "A"
const OUTPUT_B_PRIORITY := "B"
const FILTER_STRICT := "STRICT"
const FILTER_OVERFLOW := "OVERFLOW"

var belt_types: Dictionary = {
	"standard": {
		"display_name": "Standard Belt",
		"speed": GameBalance.STANDARD_BELT_SPEED,
	},
}
var belts: Dictionary = {}
var splitters: Dictionary = {}
var next_item_id := 1
var merge_cursors: Dictionary = {}


func reset() -> void:
	belts.clear()
	splitters.clear()
	merge_cursors.clear()
	next_item_id = 1


func add_belt(cell: Vector2i, direction: int, belt_type := "standard") -> bool:
	if belts.has(cell) or splitters.has(cell) or not belt_types.has(belt_type):
		return false
	belts[cell] = {
		"cell": cell,
		"direction": posmod(direction, 4),
		"belt_type": belt_type,
		"lanes": [[], []],
		"topology": _straight_topology(posmod(direction, 4)),
		"primary_input": posmod(direction, 4),
		"incoming": [],
	}
	_update_topology_near(cell)
	return true


func remove_belt(cell: Vector2i) -> bool:
	if not belts.has(cell) or not belt_empty(cell):
		return false
	belts.erase(cell)
	_update_topology_near(cell)
	return true


func rotate_belt(cell: Vector2i, direction: int) -> bool:
	if not belts.has(cell) or not belt_empty(cell):
		return false
	belts[cell].direction = posmod(direction, 4)
	_update_topology_near(cell)
	return true


func belt_empty(cell: Vector2i) -> bool:
	if not belts.has(cell):
		return true
	var lanes: Array = belts[cell].lanes
	return Array(lanes[0]).is_empty() and Array(lanes[1]).is_empty()


func add_splitter(cell: Vector2i, direction: int) -> bool:
	if belts.has(cell) or splitters.has(cell):
		return false
	splitters[cell] = {
		"cell": cell,
		"direction": posmod(direction, 4),
		"buffers": [[], []],
		"next_output": 0,
		"priority": OUTPUT_NONE,
		"filter_resource": "",
		"filter_mode": FILTER_STRICT,
		"config_index": 0,
	}
	_update_topology_near(cell)
	return true


func configure_splitter(cell: Vector2i, priority := OUTPUT_NONE, filter_resource := "", filter_mode := FILTER_STRICT) -> bool:
	if not splitters.has(cell):
		return false
	var splitter: Dictionary = splitters[cell]
	splitter.priority = priority if priority in [OUTPUT_NONE, OUTPUT_A_PRIORITY, OUTPUT_B_PRIORITY] else OUTPUT_NONE
	splitter.filter_resource = filter_resource
	splitter.filter_mode = filter_mode if filter_mode in [FILTER_STRICT, FILTER_OVERFLOW] else FILTER_STRICT
	return true


func remove_splitter(cell: Vector2i) -> bool:
	if not splitters.has(cell):
		return false
	var buffers: Array = splitters[cell].buffers
	if not Array(buffers[0]).is_empty() or not Array(buffers[1]).is_empty():
		return false
	splitters.erase(cell)
	_update_topology_near(cell)
	return true


func cell_occupied(cell: Vector2i) -> bool:
	return belts.has(cell) or splitters.has(cell)


func set_belt_type(cell: Vector2i, belt_type: String) -> bool:
	if not belts.has(cell) or not belt_types.has(belt_type):
		return false
	belts[cell].belt_type = belt_type
	return true


func speed_for(cell: Vector2i) -> float:
	if not belts.has(cell):
		return 0.0
	return float(belt_types[str(belts[cell].belt_type)].speed)


func step(delta: float, endpoint_accept: Callable) -> void:
	_move_items_within_segments(delta)
	_dispatch_splitters()
	_transfer_ready_items(endpoint_accept)


func spawn_item(cell: Vector2i, lane: int, resource_id: String, quantity := 1, progress := 0.0, entry_direction := -1) -> Dictionary:
	if not belts.has(cell) or lane < 0 or lane > 1 or quantity <= 0:
		return {}
	if not _can_accept_belt(cell, lane, progress):
		return {}
	var direction := int(belts[cell].direction) if entry_direction < 0 else posmod(entry_direction, 4)
	var item := _make_item(resource_id, quantity, cell, lane, clampf(progress, 0.0, 1.0), direction)
	var lanes: Array = belts[cell].lanes
	Array(lanes[lane]).append(item)
	_sort_lane(Array(lanes[lane]))
	return item


func try_insert_from_endpoint(cell: Vector2i, resource_id: String, quantity: int, entry_direction: int, lane_mode := "AUTO", preferred_lane := 0) -> int:
	if not belts.has(cell) or quantity <= 0 or _directions_opposed(entry_direction, int(belts[cell].direction)):
		return -1
	var candidates: Array[int] = []
	match lane_mode:
		"LANE_0": candidates = [0]
		"LANE_1": candidates = [1]
		_: candidates = [posmod(preferred_lane, 2), 1 - posmod(preferred_lane, 2)]
	for lane in candidates:
		if _can_accept_belt(cell, lane, 0.0):
			spawn_item(cell, lane, resource_id, quantity, 0.0, entry_direction)
			return lane
	return -1


func all_items() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for cell in _sorted_cells(belts.keys()):
		var lanes: Array = belts[cell].lanes
		for lane in 2:
			for item in Array(lanes[lane]):
				result.append(item)
	for cell in _sorted_cells(splitters.keys()):
		var buffers: Array = splitters[cell].buffers
		for lane in 2:
			for item in Array(buffers[lane]):
				result.append(item)
	return result


func closest_item(world_position: Vector2, max_distance: float, cell_size: float) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := max_distance
	for item in all_items():
		var item_position := item_world_position(item, cell_size) if belts.has(item.cell) else Vector2(item.cell) * cell_size + Vector2.ONE * cell_size * 0.5
		var distance := world_position.distance_to(item_position)
		if distance < best_distance or (is_equal_approx(distance, best_distance) and (best.is_empty() or int(item.id) < int(best.id))):
			best = item
			best_distance = distance
	return best


func take_item(item_id: int) -> Dictionary:
	for cell in _sorted_cells(belts.keys()):
		var lanes: Array = belts[cell].lanes
		for lane in 2:
			var items: Array = lanes[lane]
			for index in items.size():
				if int(items[index].id) == item_id:
					var item: Dictionary = items[index]
					items.remove_at(index)
					return item
	for cell in _sorted_cells(splitters.keys()):
		var buffers: Array = splitters[cell].buffers
		for lane in 2:
			var items: Array = buffers[lane]
			for index in items.size():
				if int(items[index].id) == item_id:
					var item: Dictionary = items[index]
					items.remove_at(index)
					return item
	return {}


func item_count() -> int:
	return all_items().size()


func count_resource(resource_id: String) -> int:
	var total := 0
	for item in all_items():
		if str(item.resource) == resource_id:
			total += int(item.quantity)
	return total


func lane_items(cell: Vector2i, lane: int) -> Array:
	if not belts.has(cell) or lane < 0 or lane > 1:
		return []
	return belts[cell].lanes[lane]


func leading_item_blocked(cell: Vector2i, lane: int) -> bool:
	var items: Array = lane_items(cell, lane)
	return not items.is_empty() and float(items[0].progress) >= 1.0 - GameBalance.BELT_TRANSFER_TOLERANCE


func topology_for(cell: Vector2i) -> String:
	if splitters.has(cell):
		return "SPLITTER"
	return str(belts[cell].topology) if belts.has(cell) else ""


func lane_path_points(cell: Vector2i, lane: int, cell_size: float, samples := 8) -> PackedVector2Array:
	var points := PackedVector2Array()
	if not belts.has(cell):
		return points
	var entry_direction := int(belts[cell].primary_input)
	for index in samples + 1:
		points.append(_path_position(cell, lane, float(index) / float(samples), entry_direction, cell_size))
	return points


func item_world_position(item: Dictionary, cell_size: float) -> Vector2:
	if not belts.has(item.cell):
		return Vector2(item.cell) * cell_size + Vector2.ONE * cell_size * 0.5
	return _path_position(item.cell, int(item.lane), float(item.progress), int(item.entry_direction), cell_size)


func splitter_output_cells(cell: Vector2i) -> Array[Vector2i]:
	if not splitters.has(cell):
		return []
	var direction := int(splitters[cell].direction)
	return [cell + DIRECTIONS[direction], cell + DIRECTIONS[(direction + 1) % 4]]


func side_load_destination_lane(source_direction: int, destination_direction: int) -> int:
	# Looking along the destination belt, arrivals from its left join lane 0;
	# arrivals from its right join lane 1. Both source lanes use that same lane.
	var destination_vector: Vector2i = DIRECTIONS[posmod(destination_direction, 4)]
	var source_vector: Vector2i = DIRECTIONS[posmod(source_direction, 4)]
	var cross := destination_vector.x * source_vector.y - destination_vector.y * source_vector.x
	return 0 if cross > 0 else 1


func _move_items_within_segments(delta: float) -> void:
	for cell in _sorted_cells(belts.keys()):
		var belt: Dictionary = belts[cell]
		var speed := float(belt_types[str(belt.belt_type)].speed)
		var lanes: Array = belt.lanes
		for lane in 2:
			var items: Array = lanes[lane]
			_sort_lane(items)
			var forward_limit := 1.0
			for item in items:
				var current := float(item.progress)
				var target := minf(current + speed * delta, forward_limit)
				item.progress = maxf(current, target)
				forward_limit = float(item.progress) - GameBalance.BELT_MIN_ITEM_SPACING


func _dispatch_splitters() -> void:
	for cell in _sorted_cells(splitters.keys()):
		var splitter: Dictionary = splitters[cell]
		var buffers: Array = splitter.buffers
		for lane in 2:
			var queued: Array = buffers[lane]
			if queued.is_empty():
				continue
			var item: Dictionary = queued[0]
			var outputs: Array = _splitter_output_order(splitter, str(item.resource))
			for output_index in outputs:
				var output_direction := int(splitter.direction) if int(output_index) == 0 else (int(splitter.direction) + 1) % 4
				var output_cell: Vector2i = cell + DIRECTIONS[output_direction]
				if _insert_existing(output_cell, item, lane, output_direction):
					queued.pop_front()
					if str(splitter.priority) == OUTPUT_NONE and str(splitter.filter_resource).is_empty():
						splitter.next_output = 1 - int(output_index)
					break


func _splitter_output_order(splitter: Dictionary, resource_id: String) -> Array:
	var filter_resource := str(splitter.filter_resource)
	if not filter_resource.is_empty():
		var preferred := 0 if resource_id == filter_resource else 1
		return [preferred, 1 - preferred] if str(splitter.filter_mode) == FILTER_OVERFLOW else [preferred]
	if str(splitter.priority) == OUTPUT_A_PRIORITY:
		return [0, 1]
	if str(splitter.priority) == OUTPUT_B_PRIORITY:
		return [1, 0]
	var next_output := int(splitter.next_output)
	return [next_output, 1 - next_output]


func _transfer_ready_items(endpoint_accept: Callable) -> void:
	var groups: Dictionary = {}
	for source_cell in _sorted_cells(belts.keys()):
		var belt: Dictionary = belts[source_cell]
		var lanes: Array = belt.lanes
		for source_lane in 2:
			var items: Array = lanes[source_lane]
			if items.is_empty() or float(items[0].progress) < 1.0 - GameBalance.BELT_TRANSFER_TOLERANCE:
				continue
			var item: Dictionary = items[0]
			var source_direction := int(belt.direction)
			var target_cell: Vector2i = source_cell + DIRECTIONS[source_direction]
			var target_type := "endpoint"
			var target_lane := source_lane
			if belts.has(target_cell):
				if _directions_opposed(source_direction, int(belts[target_cell].direction)):
					continue
				target_type = "belt"
				target_lane = _mapped_destination_lane(source_cell, source_lane, target_cell)
			elif splitters.has(target_cell):
				target_type = "splitter"
			var key := "%s:%d:%d:%d" % [target_type, target_cell.x, target_cell.y, target_lane]
			if not groups.has(key):
				groups[key] = []
			groups[key].append({
				"source_cell": source_cell,
				"source_lane": source_lane,
				"source_direction": source_direction,
				"target_cell": target_cell,
				"target_lane": target_lane,
				"target_type": target_type,
				"item": item,
			})
	var keys: Array = groups.keys()
	keys.sort()
	for key in keys:
		var candidates: Array = groups[key]
		candidates.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.item.id) < int(b.item.id))
		var start := int(merge_cursors.get(key, 0)) % candidates.size()
		for offset in candidates.size():
			var candidate: Dictionary = candidates[(start + offset) % candidates.size()]
			if _commit_transfer(candidate, endpoint_accept):
				merge_cursors[key] = (start + offset + 1) % candidates.size()
				break


func _commit_transfer(candidate: Dictionary, endpoint_accept: Callable) -> bool:
	var source_items: Array = belts[candidate.source_cell].lanes[int(candidate.source_lane)]
	if source_items.is_empty() or int(source_items[0].id) != int(candidate.item.id):
		return false
	var accepted := false
	match str(candidate.target_type):
		"belt":
			accepted = _insert_existing(candidate.target_cell, candidate.item, int(candidate.target_lane), int(candidate.source_direction))
		"splitter":
			var buffers: Array = splitters[candidate.target_cell].buffers
			var queue: Array = buffers[int(candidate.target_lane)]
			if queue.is_empty():
				candidate.item.cell = candidate.target_cell
				candidate.item.lane = int(candidate.target_lane)
				candidate.item.progress = 0.0
				queue.append(candidate.item)
				accepted = true
		_:
			accepted = bool(endpoint_accept.call(candidate.target_cell, candidate.item, int(candidate.source_direction), int(candidate.source_lane)))
	if accepted:
		source_items.pop_front()
	return accepted


func _insert_existing(cell: Vector2i, item: Dictionary, lane: int, entry_direction: int) -> bool:
	if not belts.has(cell) or _directions_opposed(entry_direction, int(belts[cell].direction)) or not _can_accept_belt(cell, lane, 0.0):
		return false
	item.cell = cell
	item.lane = lane
	item.progress = 0.0
	item.entry_direction = entry_direction
	var lanes: Array = belts[cell].lanes
	Array(lanes[lane]).append(item)
	_sort_lane(Array(lanes[lane]))
	return true


func _mapped_destination_lane(source_cell: Vector2i, source_lane: int, target_cell: Vector2i) -> int:
	var source_direction := int(belts[source_cell].direction)
	var target: Dictionary = belts[target_cell]
	if source_direction == int(target.primary_input):
		return source_lane
	# Factorio-style side loading: looking along the destination belt, an
	# arrival from its left always joins lane 0; an arrival from its right joins
	# lane 1. Both source lanes therefore merge deterministically into one lane.
	return side_load_destination_lane(source_direction, int(target.direction))


func _can_accept_belt(cell: Vector2i, lane: int, entry_progress := 0.0) -> bool:
	if not belts.has(cell):
		return false
	var items: Array = belts[cell].lanes[lane]
	if items.is_empty():
		return true
	_sort_lane(items)
	var back_progress := float(items[items.size() - 1].progress)
	return back_progress - entry_progress >= GameBalance.BELT_MIN_ITEM_SPACING - GameBalance.BELT_TRANSFER_TOLERANCE


func _make_item(resource_id: String, quantity: int, cell: Vector2i, lane: int, progress: float, entry_direction: int) -> Dictionary:
	var item := {
		"id": next_item_id,
		"resource": resource_id,
		"quantity": quantity,
		"cell": cell,
		"lane": lane,
		"progress": progress,
		"entry_direction": entry_direction,
	}
	next_item_id += 1
	return item


func _sort_lane(items: Array) -> void:
	items.sort_custom(func(a: Dictionary, b: Dictionary):
		if not is_equal_approx(float(a.progress), float(b.progress)):
			return float(a.progress) > float(b.progress)
		return int(a.id) < int(b.id)
	)


func _update_topology_near(cell: Vector2i) -> void:
	var affected: Dictionary = {cell: true}
	for direction in DIRECTIONS:
		affected[cell + direction] = true
		affected[cell - direction] = true
	for affected_cell in affected:
		_update_belt_topology(affected_cell)


func _update_belt_topology(cell: Vector2i) -> void:
	if not belts.has(cell):
		return
	var belt: Dictionary = belts[cell]
	var incoming: Array[int] = []
	for direction_index in 4:
		var neighbor: Vector2i = cell - DIRECTIONS[direction_index]
		if belts.has(neighbor) and int(belts[neighbor].direction) == direction_index:
			incoming.append(direction_index)
	incoming.sort()
	belt.incoming = incoming
	var output_direction := int(belt.direction)
	var primary := output_direction
	if output_direction not in incoming and not incoming.is_empty():
		primary = incoming[0]
	belt.primary_input = primary
	belt.topology = _topology_for_directions(primary, output_direction)


func _topology_for_directions(input_direction: int, output_direction: int) -> String:
	if input_direction == output_direction:
		return _straight_topology(output_direction)
	return "CORNER_%s%s" % [_direction_letter(input_direction), _direction_letter(output_direction)]


func _straight_topology(direction: int) -> String:
	return "STRAIGHT_EW" if posmod(direction, 2) == 0 else "STRAIGHT_NS"


func _direction_letter(direction: int) -> String:
	return ["E", "S", "W", "N"][posmod(direction, 4)]


func _directions_opposed(first: int, second: int) -> bool:
	return posmod(first + 2, 4) == posmod(second, 4)


func _path_position(cell: Vector2i, lane: int, progress: float, entry_direction: int, cell_size: float) -> Vector2:
	var center := Vector2(cell) * cell_size + Vector2.ONE * cell_size * 0.5
	var output_direction := int(belts[cell].direction)
	var input_vector := Vector2(DIRECTIONS[posmod(entry_direction, 4)])
	var output_vector := Vector2(DIRECTIONS[output_direction])
	var lane_distance := cell_size * 0.18
	var input_offset := Vector2(input_vector.y, -input_vector.x) * (lane_distance if lane == 0 else -lane_distance)
	var output_offset := Vector2(output_vector.y, -output_vector.x) * (lane_distance if lane == 0 else -lane_distance)
	var start := center - input_vector * cell_size * 0.5 + input_offset
	var finish := center + output_vector * cell_size * 0.5 + output_offset
	var t := clampf(progress, 0.0, 1.0)
	if posmod(entry_direction, 4) == output_direction:
		return start.lerp(finish, t)
	var control := center + (input_offset + output_offset) * 0.35
	return start * pow(1.0 - t, 2.0) + control * 2.0 * (1.0 - t) * t + finish * t * t


func _sorted_cells(cells_value: Array) -> Array:
	var cells := cells_value.duplicate()
	cells.sort_custom(func(a: Vector2i, b: Vector2i):
		return a.y < b.y if a.y != b.y else a.x < b.x
	)
	return cells
