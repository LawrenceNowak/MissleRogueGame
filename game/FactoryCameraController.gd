class_name FactoryCameraController
extends RefCounted

var min_zoom := GameBalance.FACTORY_CAMERA_MIN_ZOOM
var max_zoom := GameBalance.FACTORY_CAMERA_MAX_ZOOM
var zoom_step := GameBalance.FACTORY_CAMERA_ZOOM_STEP
var zoom_speed := GameBalance.FACTORY_CAMERA_ZOOM_SPEED

var view_size := Vector2(1280.0, 720.0)
var map_size := Vector2.ZERO
var current_zoom := 1.0
var target_zoom := 1.0
var pan_offset := Vector2.ZERO
var panning := false

var _zoom_anchor_active := false
var _zoom_anchor_screen := Vector2.ZERO
var _zoom_anchor_world := Vector2.ZERO


func setup(view_dimensions: Vector2, map_dimensions: Vector2) -> void:
	view_size = view_dimensions
	map_size = map_dimensions
	reset()


func reset() -> void:
	current_zoom = 1.0
	target_zoom = 1.0
	pan_offset = Vector2.ZERO
	panning = false
	_zoom_anchor_active = false


func request_zoom(direction: int, cursor_screen: Vector2, cursor_world: Vector2) -> bool:
	var requested := clampf(target_zoom + float(signi(direction)) * zoom_step, min_zoom, max_zoom)
	if is_equal_approx(requested, target_zoom):
		return false
	target_zoom = requested
	_zoom_anchor_screen = cursor_screen
	_zoom_anchor_world = cursor_world
	_zoom_anchor_active = true
	return true


func begin_pan() -> void:
	panning = true
	_zoom_anchor_active = false


func pan_by(screen_delta: Vector2) -> void:
	if not panning:
		return
	pan_offset -= screen_delta / maxf(current_zoom, 0.001)


func end_pan() -> void:
	panning = false


func apply_to(world: Node2D, followed_world_position: Vector2, delta: float, snap_to_target := false) -> void:
	if snap_to_target:
		current_zoom = target_zoom
	else:
		current_zoom = move_toward(current_zoom, target_zoom, zoom_speed * maxf(delta, 0.0))
	if absf(current_zoom - target_zoom) <= 0.001:
		current_zoom = target_zoom
	var focus := followed_world_position + pan_offset
	if _zoom_anchor_active:
		focus = _zoom_anchor_world - (_zoom_anchor_screen - view_size * 0.5) / current_zoom
		pan_offset = focus - followed_world_position
		if is_equal_approx(current_zoom, target_zoom):
			_zoom_anchor_active = false
	world.scale = Vector2.ONE * current_zoom
	var desired := view_size * 0.5 - focus * current_zoom
	world.position = _bounded_position(desired, current_zoom).round()


func _bounded_position(desired: Vector2, zoom_value: float) -> Vector2:
	var scaled_map := map_size * zoom_value
	var bounded := desired
	if scaled_map.x <= view_size.x:
		bounded.x = (view_size.x - scaled_map.x) * 0.5
	else:
		bounded.x = clampf(bounded.x, view_size.x - scaled_map.x, 0.0)
	if scaled_map.y <= view_size.y:
		bounded.y = (view_size.y - scaled_map.y) * 0.5
	else:
		bounded.y = clampf(bounded.y, view_size.y - scaled_map.y, 0.0)
	return bounded
