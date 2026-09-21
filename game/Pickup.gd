class_name RewardPickup
extends Node2D

signal collected(pickup, reward_kind: String, amount: int)

var reward_kind := "credits"
var amount := 1
var life := 1.0
var resolved := false

func setup(kind: String, value: int, world_position: Vector2) -> void:
	reward_kind = kind
	amount = value
	position = world_position

func _process(delta: float) -> void:
	position.y += 20.0 * delta
	life -= delta
	if life <= 0.0:
		collect()
	queue_redraw()

func collect() -> void:
	if resolved:
		return
	resolved = true
	collected.emit(self, reward_kind, amount)
	queue_free()

func _draw() -> void:
	var color := Color("ffe66d")
	if reward_kind == "component": color = Color("c58cff")
	elif reward_kind == "rapid": color = Color("4de3a4")
	draw_circle(Vector2.ZERO, 9.0, Color(color, 0.25))
	draw_circle(Vector2.ZERO, 5.0, color)
