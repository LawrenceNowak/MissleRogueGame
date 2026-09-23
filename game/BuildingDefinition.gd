class_name BuildingDefinition
extends Resource

enum Category { CITY, WEAPON, RESEARCH, SUPPORT, DEFENSE, UTILITY, SPECIAL }

@export var stable_id := ""
@export var display_name := ""
@export var cost := 0
@export var footprint := Vector2i.ONE
@export var max_health := 100.0
@export var scene: PackedScene
@export var category := Category.SUPPORT
@export var icon: Texture2D
@export_multiline var description := ""
