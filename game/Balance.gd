class_name GameBalance
extends RefCounted

const CITY_MAX_HP := 100.0
const CITY_COUNT := 5
const CITY_REPAIR_AMOUNT := 30.0
const CITY_REPAIR_COST := 30
const SHIELD_COST := 60
const SHIELD_HP := 80.0
const GATLING_COST := 80
const WEAPON_UPGRADE_COST := 50

const MISSILE_DAMAGE := 48.0
const MISSILE_RADIUS := 82.0
const MISSILE_SPEED := 430.0
const MISSILE_COOLDOWN := 0.62

const GATLING_DAMAGE := 10.0
const GATLING_FIRE_RATE := 10.0
const GATLING_HEAT_PER_SHOT := 8.0
const GATLING_COOLING := 26.0
const GATLING_MAX_HEAT := 100.0

const BOSS_HP := 800.0
const BOSS_ATTACK_CADENCE := 1.8

static func enemy_stats(kind: String) -> Dictionary:
	match kind:
		"fast":
			return {"hp": 18.0, "speed": 165.0, "damage": 20.0, "reward": 12, "color": Color("ff6b91"), "radius": 7.0}
		"mirv":
			return {"hp": 52.0, "speed": 64.0, "damage": 0.0, "reward": 24, "color": Color("c58cff"), "radius": 13.0}
		"child":
			return {"hp": 12.0, "speed": 125.0, "damage": 16.0, "reward": 5, "color": Color("ffd166"), "radius": 5.0}
		"boss":
			return {"hp": BOSS_HP, "speed": 68.0, "damage": 0.0, "reward": 150, "color": Color("ff9f43"), "radius": 42.0}
		_:
			return {"hp": 32.0, "speed": 78.0, "damage": 24.0, "reward": 10, "color": Color("77d9ff"), "radius": 9.0}

static func wave_definition(number: int) -> Array[Dictionary]:
	match number:
		1: return _repeat("basic", 5, 1.15)
		2: return _repeat("basic", 7, 0.95)
		3: return _mix([["basic", 5], ["fast", 3]], 0.82)
		4: return _mix([["basic", 5], ["mirv", 2]], 0.9)
		5: return _mix([["basic", 7], ["fast", 4], ["mirv", 2]], 0.68)
		6: return _mix([["basic", 8], ["fast", 6]], 0.58)
		7: return _mix([["basic", 7], ["fast", 5], ["mirv", 3]], 0.55)
		8: return _mix([["basic", 9], ["fast", 7], ["mirv", 3]], 0.46)
		9: return _mix([["basic", 11], ["fast", 8], ["mirv", 4]], 0.39)
		10: return [{"kind": "boss", "delay": 0.5}]
		_: return []

static func _repeat(kind: String, count: int, delay: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in count:
		result.append({"kind": kind, "delay": delay if index > 0 else 0.4})
	return result

static func _mix(groups: Array, delay: float) -> Array[Dictionary]:
	var buckets: Array[Array] = []
	for group in groups:
		var bucket: Array = []
		for index in int(group[1]):
			bucket.append(String(group[0]))
		buckets.append(bucket)
	var result: Array[Dictionary] = []
	var remaining := true
	while remaining:
		remaining = false
		for bucket in buckets:
			if not bucket.is_empty():
				remaining = true
				result.append({"kind": bucket.pop_front(), "delay": delay})
	return result
