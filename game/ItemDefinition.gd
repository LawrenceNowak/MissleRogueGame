class_name ItemDefinition
extends Resource

enum Category { RESOURCE, BUILDING, WEAPON, AMMUNITION, COMPONENT, UTILITY }

@export var stable_id := ""
@export var display_name := ""
@export var category := Category.RESOURCE
@export var icon: Texture2D
@export var max_stack := 99
@export var placeable := false
@export var placement_definition := ""
@export var transportable := false
@export_multiline var description := ""
@export var visual_color := Color.WHITE
@export var visual_scale := Vector2.ONE
@export var visual_offset := Vector2.ZERO


func setup(
	item_id: String,
	item_name: String,
	item_category: Category,
	stack_limit: int,
	is_transportable: bool,
	color: Color,
	is_placeable := false,
	placement_id := "",
	details := ""
) -> ItemDefinition:
	stable_id = item_id
	display_name = item_name
	category = item_category
	max_stack = maxi(1, stack_limit)
	transportable = is_transportable
	visual_color = color
	placeable = is_placeable
	placement_definition = placement_id
	description = details
	return self
