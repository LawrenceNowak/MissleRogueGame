class_name BuildingInstance
extends Node2D

signal health_changed(current: float, maximum: float)
signal destroyed(building)

enum State { ACTIVE, DAMAGED, DESTROYED }

const GRID_SIZE := 32.0

var runtime_id := 0
var definition_id := ""
var definition: BuildingDefinition
var current_health := 0.0
var max_health := 0.0
var state := State.ACTIVE
@onready var building_sprite := get_node_or_null("LabSprite") as Sprite2D
@onready var health_bar_anchor := get_node_or_null("HealthBarAnchor") as Marker2D

func setup(id: int, building_definition: BuildingDefinition, world_position: Vector2) -> void:
	runtime_id = id
	definition = building_definition
	definition_id = building_definition.stable_id
	position = world_position
	max_health = building_definition.max_health
	current_health = max_health
	state = State.ACTIVE
	_update_authored_visual()
	queue_redraw()

func placement_rect() -> Rect2:
	if definition == null:
		return Rect2(position, Vector2.ZERO)
	var size := Vector2(definition.footprint) * GRID_SIZE
	return Rect2(position - size * 0.5, size)

func take_damage(amount: float) -> void:
	if state == State.DESTROYED or amount <= 0.0:
		return
	current_health = maxf(0.0, current_health - amount)
	if current_health <= 0.0:
		state = State.DESTROYED
		destroyed.emit(self)
	elif current_health < max_health:
		state = State.DAMAGED
	_update_authored_visual()
	health_changed.emit(current_health, max_health)
	queue_redraw()

func repair(amount: float) -> bool:
	if state == State.DESTROYED or amount <= 0.0 or current_health >= max_health:
		return false
	current_health = minf(max_health, current_health + amount)
	state = State.ACTIVE if is_equal_approx(current_health, max_health) else State.DAMAGED
	_update_authored_visual()
	health_changed.emit(current_health, max_health)
	queue_redraw()
	return true

func is_destroyed() -> bool:
	return state == State.DESTROYED

func _update_authored_visual() -> void:
	if not is_instance_valid(building_sprite):
		return
	building_sprite.visible = state != State.DESTROYED
	building_sprite.self_modulate = Color("ffd3a1") if state == State.DAMAGED else Color.WHITE

func _draw() -> void:
	if definition == null:
		return
	var size := Vector2(definition.footprint) * GRID_SIZE
	var bounds := Rect2(-size * 0.5 + Vector2(3, 3), size - Vector2(6, 6))
	if state == State.DESTROYED:
		draw_rect(bounds, Color("2f3542"))
		draw_line(bounds.position, bounds.end, Color("7c5964"), 5.0)
		draw_line(Vector2(bounds.end.x, bounds.position.y), Vector2(bounds.position.x, bounds.end.y), Color("7c5964"), 5.0)
		return
	if not is_instance_valid(building_sprite):
		var body_color := Color("5d6ee8") if state == State.ACTIVE else Color("be7952")
		draw_rect(bounds, Color("172344"))
		draw_rect(Rect2(bounds.position + Vector2(5, 18), bounds.size - Vector2(10, 23)), body_color)
		draw_circle(Vector2(0, -8), 15.0, Color("7ce6ef"))
		draw_arc(Vector2(0, -8), 15.0, PI, TAU, 18, Color("e6ffff"), 3.0)
		draw_line(Vector2(-18, 12), Vector2(18, 12), Color("e6ffff"), 3.0)
	var health_ratio := current_health / max_health if max_health > 0.0 else 0.0
	var bar_y := health_bar_anchor.position.y if is_instance_valid(health_bar_anchor) else -size.y * 0.5 - 8
	draw_rect(Rect2(-size.x * 0.5, bar_y, size.x, 4), Color("291e2d"))
	draw_rect(Rect2(-size.x * 0.5, bar_y, size.x * health_ratio, 4), Color("4de3a4"))
