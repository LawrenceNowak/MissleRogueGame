class_name EnemyThreat
extends Node2D

signal removed(threat, killed: bool, reward: int)
signal split_requested(threat, child_count: int)
signal boss_shot_requested(kind: String)
signal hp_changed(current: float, maximum: float)

var kind := "basic"
var max_hp := 1.0
var hp := 1.0
var speed := 1.0
var impact_damage := 1.0
var reward := 0
var radius := 8.0
var visual_color := Color.WHITE
var target
var target_provider := Callable()
var resolved := false
var has_split := false
var boss_direction := 1.0
var attack_timer := 0.0
var hit_flash := 0.0
var trail: Array[Vector2] = []

func setup(threat_kind: String, world_position: Vector2, city_target, provider: Callable) -> void:
	kind = threat_kind
	position = world_position
	target = city_target
	target_provider = provider
	var stats := GameBalance.enemy_stats(kind)
	max_hp = stats.hp
	hp = max_hp
	speed = stats.speed
	impact_damage = stats.damage
	reward = stats.reward
	visual_color = stats.color
	radius = stats.radius
	attack_timer = GameBalance.BOSS_ATTACK_CADENCE
	queue_redraw()

func take_damage(amount: float) -> void:
	if resolved:
		return
	hp -= amount
	hit_flash = 0.08
	hp_changed.emit(maxf(0.0, hp), max_hp)
	if hp <= 0.0:
		resolved = true
		removed.emit(self, true, reward)
		queue_free()

func _process(delta: float) -> void:
	if resolved:
		return
	hit_flash = maxf(0.0, hit_flash - delta)
	if kind == "boss":
		_process_boss(delta)
		queue_redraw()
		return
	if not is_instance_valid(target) or target.destroyed:
		target = target_provider.call() if target_provider.is_valid() else null
	if not is_instance_valid(target):
		return
	trail.push_front(position)
	if trail.size() > 12:
		trail.pop_back()
	position = position.move_toward(target.position, speed * delta)
	if kind == "mirv" and not has_split and position.y > 285.0:
		has_split = true
		resolved = true
		split_requested.emit(self, 3)
		queue_free()
		return
	if position.distance_to(target.position) <= radius + 15.0:
		resolved = true
		target.take_damage(impact_damage)
		removed.emit(self, false, 0)
		queue_free()
	queue_redraw()

func _process_boss(delta: float) -> void:
	position.x += speed * boss_direction * delta
	if position.x > 1080.0:
		boss_direction = -1.0
	elif position.x < 200.0:
		boss_direction = 1.0
	attack_timer -= delta
	if attack_timer <= 0.0:
		var ratio := hp / max_hp
		var next_kind := "basic"
		if ratio < 0.3 and randf() < 0.28:
			next_kind = "mirv"
		elif ratio < 0.65 and randf() < 0.45:
			next_kind = "fast"
		boss_shot_requested.emit(next_kind)
		attack_timer = GameBalance.BOSS_ATTACK_CADENCE * lerpf(0.55, 1.0, ratio)

func _draw() -> void:
	for index in range(1, trail.size()):
		var alpha := (1.0 - float(index) / float(trail.size())) * 0.36
		draw_line(to_local(trail[index - 1]), to_local(trail[index]), Color(visual_color, alpha), maxf(1.0, radius * 0.42))
	var color := Color.WHITE if hit_flash > 0.0 else visual_color
	if kind == "boss":
		draw_polygon(PackedVector2Array([Vector2(-58,-12),Vector2(-18,-24),Vector2(54,-18),Vector2(68,0),Vector2(45,18),Vector2(-26,20),Vector2(-64,7)]), PackedColorArray([color]))
		draw_circle(Vector2(30, 0), 11.0, Color("37284f"))
		draw_line(Vector2(-35, 15), Vector2(-54, 34), Color("ff795e"), 6.0)
	else:
		var direction := Vector2.DOWN
		if is_instance_valid(target):
			direction = position.direction_to(target.position)
		var side := direction.orthogonal()
		draw_polygon(PackedVector2Array([direction * radius * 1.7, side * radius, -direction * radius, -side * radius]), PackedColorArray([color]))
		draw_line(-direction * radius, -direction * radius * 2.1, Color("ff9f43"), maxf(2.0, radius * 0.45))
