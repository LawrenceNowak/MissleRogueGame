class_name SettlementBuildGrid
extends RefCounted

const GRID_SIZE := 32.0
const BUILD_ZONE := Rect2(32.0, 480.0, 1216.0, 128.0)

func snap_position(world_position: Vector2, definition: BuildingDefinition) -> Vector2:
	var parity_offset := Vector2(definition.footprint.x % 2, definition.footprint.y % 2) * GRID_SIZE * 0.5
	var relative := (world_position - BUILD_ZONE.position - parity_offset) / GRID_SIZE
	return BUILD_ZONE.position + parity_offset + Vector2(roundf(relative.x), roundf(relative.y)) * GRID_SIZE

func footprint_rect(definition: BuildingDefinition, snapped_position: Vector2) -> Rect2:
	var size := Vector2(definition.footprint) * GRID_SIZE
	return Rect2(snapped_position - size * 0.5, size)

func validate(definition: BuildingDefinition, snapped_position: Vector2, buildings: Array[BuildingInstance], protected_areas: Array[Rect2]) -> Dictionary:
	if definition == null:
		return {"valid": false, "reason": "No building selected"}
	var candidate := footprint_rect(definition, snapped_position)
	if not BUILD_ZONE.has_point(candidate.position) or not BUILD_ZONE.has_point(candidate.end - Vector2(0.01, 0.01)):
		return {"valid": false, "reason": "Outside settlement build zone"}
	for building in buildings:
		if is_instance_valid(building) and candidate.intersects(building.placement_rect()):
			return {"valid": false, "reason": "Overlaps an existing building"}
	for protected_area in protected_areas:
		if candidate.intersects(protected_area):
			return {"valid": false, "reason": "Space reserved for a city or weapon"}
	return {"valid": true, "reason": "Valid placement"}
