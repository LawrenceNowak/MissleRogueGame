class_name DefenseProjectile
extends Node2D

signal exploded(projectile, at_position: Vector2, damage: float, radius: float, cluster: int)
signal bullet_hit(projectile, threat, damage: float, ricochet: int)

var projectile_type := "missile"
var target_position := Vector2.ZERO
var velocity := Vector2.ZERO
var speed := 1.0
var damage := 1.0
var explosion_radius := 1.0
var cluster_level := 0
var ricochet_level := 0
var enemy_provider := Callable()
var life := 2.0
var resolved := false
var trail: Array[Vector2] = []

func setup_missile(start: Vector2, target: Vector2, travel_speed: float, hit_damage: float, blast_radius: float, cluster: int) -> void:
	projectile_type = "missile"
	position = start
	target_position = target
	speed = travel_speed
	damage = hit_damage
	explosion_radius = blast_radius
	cluster_level = cluster

func setup_bullet(start: Vector2, shot_velocity: Vector2, hit_damage: float, ricochet: int, provider: Callable) -> void:
	projectile_type = "bullet"
	position = start
	velocity = shot_velocity
	damage = hit_damage
	ricochet_level = ricochet
	enemy_provider = provider
	life = 1.5

func _process(delta: float) -> void:
	if resolved:
		return
	trail.push_front(position)
	if trail.size() > 10:
		trail.pop_back()
	if projectile_type == "missile":
		position = position.move_toward(target_position, speed * delta)
		if position.distance_to(target_position) < 7.0:
			resolved = true
			exploded.emit(self, target_position, damage, explosion_radius, cluster_level)
			queue_free()
	else:
		position += velocity * delta
		life -= delta
		if enemy_provider.is_valid():
			for threat in enemy_provider.call():
				if is_instance_valid(threat) and not threat.resolved and position.distance_to(threat.position) <= threat.radius + 4.0:
					resolved = true
					bullet_hit.emit(self, threat, damage, ricochet_level)
					queue_free()
					break
		if life <= 0.0 or position.x < -20.0 or position.x > 1300.0 or position.y < -20.0 or position.y > 690.0:
			resolved = true
			queue_free()
	queue_redraw()

func _draw() -> void:
	for index in range(1, trail.size()):
		var alpha := (1.0 - float(index) / float(trail.size())) * 0.6
		var color := Color(0.25, 0.9, 1.0, alpha) if projectile_type == "missile" else Color(1.0, 0.86, 0.3, alpha)
		draw_line(to_local(trail[index - 1]), to_local(trail[index]), color, 2.0)
	if projectile_type == "missile":
		draw_circle(Vector2.ZERO, 5.0, Color("8ef5ff"))
	else:
		draw_circle(Vector2.ZERO, 3.0, Color("ffe66d"))
