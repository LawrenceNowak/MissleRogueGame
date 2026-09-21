class_name PlayerWeapon
extends Node2D

enum Kind { MISSILE, GATLING }

var kind := Kind.MISSILE
var unlocked := true
var selected := false
var aim_position := Vector2.ZERO
var cooldown_left := 0.0
var heat := 0.0
var overheated := false
var dragging := false

var damage := 0.0
var projectile_speed := 0.0
var cooldown := 0.0
var blast_radius := 0.0
var heat_per_shot := 0.0
var cooling := 0.0
var cluster_level := 0
var ricochet_level := 0
var upgrade_labels: Array[String] = []

func setup(weapon_kind: Kind, world_position: Vector2, is_unlocked: bool = true) -> void:
	kind = weapon_kind
	position = world_position
	unlocked = is_unlocked
	reset_stats()

func reset_stats() -> void:
	cooldown_left = 0.0
	heat = 0.0
	overheated = false
	cluster_level = 0
	ricochet_level = 0
	upgrade_labels.clear()
	if kind == Kind.MISSILE:
		damage = GameBalance.MISSILE_DAMAGE
		projectile_speed = GameBalance.MISSILE_SPEED
		cooldown = GameBalance.MISSILE_COOLDOWN
		blast_radius = GameBalance.MISSILE_RADIUS
	else:
		damage = GameBalance.GATLING_DAMAGE
		projectile_speed = 780.0
		cooldown = 1.0 / GameBalance.GATLING_FIRE_RATE
		heat_per_shot = GameBalance.GATLING_HEAT_PER_SHOT
		cooling = GameBalance.GATLING_COOLING
	queue_redraw()

func _process(delta: float) -> void:
	cooldown_left = maxf(0.0, cooldown_left - delta)
	if kind == Kind.GATLING and (cooldown_left <= 0.0 or not Input.is_action_pressed("fire")):
		heat = maxf(0.0, heat - cooling * delta)
		if overheated and heat <= GameBalance.GATLING_MAX_HEAT * 0.35:
			overheated = false
	queue_redraw()

func try_fire(rapid_multiplier: float = 1.0) -> Dictionary:
	if not unlocked or cooldown_left > 0.0:
		return {}
	if kind == Kind.GATLING:
		if overheated:
			return {}
		heat += heat_per_shot
		if heat >= GameBalance.GATLING_MAX_HEAT:
			heat = GameBalance.GATLING_MAX_HEAT
			overheated = true
		cooldown_left = cooldown / rapid_multiplier
		var direction := position.direction_to(aim_position)
		return {"type": "bullet", "position": muzzle_position(), "velocity": direction * projectile_speed, "damage": damage, "ricochet": ricochet_level}
	cooldown_left = cooldown / rapid_multiplier
	return {"type": "missile", "position": muzzle_position(), "target": aim_position, "speed": projectile_speed, "damage": damage, "radius": blast_radius, "cluster": cluster_level}

func muzzle_position() -> Vector2:
	return position + position.direction_to(aim_position) * (34.0 if kind == Kind.MISSILE else 30.0)

func apply_upgrade(id: String) -> bool:
	match id:
		"missile_radius":
			if kind != Kind.MISSILE: return false
			blast_radius += 20.0
			upgrade_labels.append("Larger Explosion")
		"missile_cluster":
			if kind != Kind.MISSILE: return false
			cluster_level += 1
			upgrade_labels.append("Cluster Warhead")
		"missile_speed":
			if kind != Kind.MISSILE: return false
			projectile_speed *= 1.25
			upgrade_labels.append("Faster Missile")
		"gatling_rate":
			if kind != Kind.GATLING: return false
			cooldown *= 0.78
			upgrade_labels.append("Faster Spin")
		"gatling_cooling":
			if kind != Kind.GATLING: return false
			cooling *= 1.35
			heat_per_shot *= 0.9
			upgrade_labels.append("Improved Cooling")
		"gatling_ricochet":
			if kind != Kind.GATLING: return false
			ricochet_level += 1
			upgrade_labels.append("Ricochet")
		_:
			return false
	queue_redraw()
	return true

func _draw() -> void:
	if not unlocked:
		return
	var base_color := Color("50b8d8") if kind == Kind.MISSILE else Color("f6b94b")
	if selected:
		draw_circle(Vector2.ZERO, 28.0, Color(base_color, 0.18))
		draw_arc(Vector2.ZERO, 29.0, 0.0, TAU, 32, Color("ffffff"), 2.0)
	if dragging:
		draw_arc(Vector2.ZERO, 36.0, 0.0, TAU, 32, Color("ffe66d"), 3.0)
	draw_rect(Rect2(-18, -9, 36, 18), Color("263b55"))
	var local_aim := aim_position - position
	var direction := local_aim.normalized() if local_aim.length() > 0.1 else Vector2.UP
	if kind == Kind.MISSILE:
		draw_line(Vector2.ZERO, direction * 31.0, base_color, 9.0)
		draw_circle(direction * 31.0, 5.0, Color("e9fbff"))
	else:
		var side := direction.orthogonal() * 3.0
		draw_line(side, direction * 29.0 + side, base_color, 4.0)
		draw_line(-side, direction * 29.0 - side, base_color, 4.0)
		if overheated:
			draw_circle(Vector2(0, 14), 5.0, Color("ff4f64"))
