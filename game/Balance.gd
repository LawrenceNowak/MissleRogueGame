class_name GameBalance
extends RefCounted

const CITY_MAX_HP := 100.0
const CITY_COUNT := 5
const CITY_REPAIR_AMOUNT := 30.0
const CITY_REPAIR_COST := 30
const SHIELD_COST := 60
const SHIELD_HP := 80.0
const WEAPON_UPGRADE_COST := 50
const CHARM_COST := 40
const COMPONENT_DROP_CHANCE := 0.08
const POWERUP_DROP_CHANCE := 0.07
const RAPID_FIRE_DURATION := 10.0

const STARTING_ORE := 0
const STARTING_MISSILE_AMMO := 3
const BASE_MISSILE_CAPACITY := 6
const STARTING_GATLING_AMMO := 1000
const BASE_GATLING_CAPACITY := 1500
const PLAYER_INVENTORY_SLOTS := 24
const STARTING_BELTS := 6
const STARTING_DRILLS := 1

const ENGINEER_MAX_STAMINA := 100
const ENGINEER_SPEED := 155.0
const STAMINA_TREE := 5
const STAMINA_SMALL_ROCK := 5
const STAMINA_LARGE_ROCK := 8
const STAMINA_DIG_NORMAL := 2
const STAMINA_DIG_HARD := 4
const STAMINA_GATHER_ORE := 3
const STAMINA_DRILL := 8
const STAMINA_MACHINE := 10
const STAMINA_STORAGE := 6
const STAMINA_BELT := 1
const STAMINA_SPLITTER := 3
const STAMINA_MACHINE_REPAIR := 6

const FACTORY_MAP_CELLS := Vector2i(64, 40)
const FACTORY_CELL_SIZE := 32
const FOG_REVEAL_RADIUS := 5
const FACTORY_CAMERA_MIN_ZOOM := 0.6
const FACTORY_CAMERA_MAX_ZOOM := 2.0
const FACTORY_CAMERA_ZOOM_STEP := 0.2
const FACTORY_CAMERA_ZOOM_SPEED := 6.0
const DRILL_INTERVAL := 6.0
const AMMO_FACTORY_INTERVAL := 5.0
const MISSILE_FACTORY_INTERVAL := 25.0
const AMMO_FACTORY_ORE_COST := 1
const AMMO_FACTORY_OUTPUT := 125
const MISSILE_FACTORY_ORE_COST := 2
const MISSILE_FACTORY_OUTPUT := 1
const LOGISTICS_FIXED_STEP := 1.0 / 30.0
const STANDARD_BELT_SPEED := 1.6
const BELT_MIN_ITEM_SPACING := 0.28
const BELT_TRANSFER_TOLERANCE := 0.001
const PICKUP_RADIUS := 54.0
const BELT_PICKUP_RADIUS := PICKUP_RADIUS
const PICKUP_MAX_PER_TICK := 64
const DRILL_OUTPUT_BUFFER_CAPACITY := 4
const MACHINE_INPUT_BUFFER_CAPACITY := 6
const MACHINE_OUTPUT_BUFFER_CAPACITY := 4
const STORAGE_PACKET_CAPACITY := 8
const BUILD_RECIPES := {
	"drill": {"wood": 3, "stone": 6, "ore": 0, "stamina": STAMINA_DRILL},
	"belt": {"wood": 0, "stone": 1, "ore": 0, "stamina": STAMINA_BELT},
	"splitter": {"wood": 2, "stone": 4, "ore": 0, "stamina": STAMINA_SPLITTER},
	"ammo_factory": {"wood": 6, "stone": 8, "ore": 2, "stamina": STAMINA_MACHINE},
	"missile_factory": {"wood": 6, "stone": 10, "ore": 4, "stamina": STAMINA_MACHINE},
	"storage": {"wood": 8, "stone": 4, "ore": 0, "stamina": STAMINA_STORAGE},
}

const MISSILE_DAMAGE := 48.0
const MISSILE_RADIUS := 82.0
const MISSILE_SPEED := 430.0
const MISSILE_COOLDOWN := 0.62

const GATLING_DAMAGE := 9.0
const GATLING_FIRE_RATE := 12.0
const GATLING_HEAT_PER_SHOT := 2.5
const GATLING_COOLING := 22.0
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
