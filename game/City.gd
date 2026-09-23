class_name DefenseCity
extends Node2D

signal changed
signal fell(city)

var city_index := 0
var max_health := GameBalance.CITY_MAX_HP
var health := GameBalance.CITY_MAX_HP
var shield_health := 0.0
var shield_max := 0.0
var destroyed := false
var selected := false
var flash := 0.0
@onready var city_sprite := get_node_or_null("CitySprite") as Sprite2D

func _ready() -> void:
	_update_visual()

func initialize(index: int) -> void:
	city_index = index
	reset_city()

func setup(index: int, world_position: Vector2) -> void:
	position = world_position
	initialize(index)

func reset_city(extra_max_hp: float = 0.0) -> void:
	max_health = GameBalance.CITY_MAX_HP + extra_max_hp
	health = max_health
	shield_health = 0.0
	shield_max = 0.0
	destroyed = false
	selected = false
	_update_visual()
	queue_redraw()
	changed.emit()

func take_damage(amount: float) -> void:
	if destroyed:
		return
	var remaining := amount
	if shield_health > 0.0:
		var absorbed: float = minf(shield_health, remaining)
		shield_health -= absorbed
		remaining -= absorbed
	if remaining > 0.0:
		health = maxf(0.0, health - remaining)
	flash = 0.24
	if health <= 0.0 and not destroyed:
		destroyed = true
		fell.emit(self)
	_update_visual()
	queue_redraw()
	changed.emit()

func repair(amount: float) -> bool:
	if destroyed or health >= max_health:
		return false
	health = minf(max_health, health + amount)
	_update_visual()
	queue_redraw()
	changed.emit()
	return true

func install_shield() -> bool:
	if destroyed or shield_max > 0.0:
		return false
	shield_max = GameBalance.SHIELD_HP
	shield_health = shield_max
	_update_visual()
	queue_redraw()
	changed.emit()
	return true

func reinforce(amount: float) -> void:
	max_health += amount
	health += amount
	_update_visual()
	queue_redraw()
	changed.emit()

func health_ratio() -> float:
	return health / max_health if max_health > 0.0 else 0.0

func _process(delta: float) -> void:
	if flash > 0.0:
		flash = maxf(0.0, flash - delta)
		_update_visual()
		queue_redraw()

func _update_visual() -> void:
	if not is_instance_valid(city_sprite):
		return
	city_sprite.visible = not destroyed
	if flash > 0.0:
		city_sprite.self_modulate = Color.WHITE
	elif health_ratio() < 0.4:
		city_sprite.self_modulate = Color("ff667b")
	elif health_ratio() < 0.75:
		city_sprite.self_modulate = Color("ffbe62")
	else:
		city_sprite.self_modulate = Color.WHITE

func _draw() -> void:
	if selected:
		draw_arc(Vector2.ZERO, 45.0, PI, TAU, 28, Color("ffe66d"), 3.0)
	if shield_max > 0.0 and shield_health > 0.0:
		var shield_alpha := 0.32 + (0.35 if flash > 0.0 else 0.0)
		draw_arc(Vector2.ZERO, 39.0, PI, TAU, 32, Color(0.25, 0.9, 1.0, shield_alpha), 5.0)
	if destroyed:
		draw_rect(Rect2(-31, -8, 62, 12), Color("322f3d"))
		draw_polygon(PackedVector2Array([Vector2(-26,-8),Vector2(-12,-24),Vector2(-2,-8)]), PackedColorArray([Color("5b4650")]))
		draw_polygon(PackedVector2Array([Vector2(3,-8),Vector2(15,-18),Vector2(28,-8)]), PackedColorArray([Color("493c48")]))
		return
	if is_instance_valid(city_sprite):
		return
	var ratio := health_ratio()
	var color := Color("4de3a4")
	if ratio < 0.4:
		color = Color("ff5d73")
	elif ratio < 0.75:
		color = Color("ffb84d")
	if flash > 0.0:
		color = Color.WHITE
	for building in [Rect2(-31,-20,14,20), Rect2(-14,-32,16,32), Rect2(5,-25,13,25), Rect2(21,-16,10,16)]:
		draw_rect(building, color)
		draw_rect(Rect2(building.position + Vector2(4,5), Vector2(3,4)), Color("13233b"))
	draw_rect(Rect2(-34, 3, 68, 5), Color("263b55"))
