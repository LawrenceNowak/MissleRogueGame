class_name TransportResources
extends RefCounted

# Stable transport IDs are shared with RunInventory. Assign a texture here later;
# belt and machine simulation never branches on texture or sprite dimensions.
static var definitions: Dictionary = {
	RunInventory.WOOD: {
		"display_name": "Wood",
		"category": "raw",
		"texture": null,
		"visual_color": Color("#92d06d"),
		"visual_scale": Vector2.ONE,
		"visual_offset": Vector2.ZERO,
	},
	RunInventory.STONE: {
		"display_name": "Stone",
		"category": "raw",
		"texture": null,
		"visual_color": Color("#c1b8aa"),
		"visual_scale": Vector2.ONE,
		"visual_offset": Vector2.ZERO,
	},
	RunInventory.ORE: {
		"display_name": "Ore",
		"category": "raw",
		"texture": null,
		"visual_color": Color("#72d6a0"),
		"visual_scale": Vector2.ONE,
		"visual_offset": Vector2.ZERO,
	},
	RunInventory.ADVANCED_RESOURCE: {
		"display_name": "Advanced Resource",
		"category": "raw",
		"texture": null,
		"visual_color": Color("#c58cff"),
		"visual_scale": Vector2.ONE,
		"visual_offset": Vector2.ZERO,
	},
	RunInventory.GATLING_AMMO: {
		"display_name": "MG Ammo Crate",
		"category": "ammunition",
		"texture": null,
		"visual_color": Color("#ffd166"),
		"visual_scale": Vector2.ONE,
		"visual_offset": Vector2.ZERO,
	},
	RunInventory.MISSILE_AMMO: {
		"display_name": "Missile",
		"category": "ammunition",
		"texture": null,
		"visual_color": Color("#79d8ff"),
		"visual_scale": Vector2.ONE,
		"visual_offset": Vector2.ZERO,
	},
}


static func definition(resource_id: String) -> Dictionary:
	return definitions.get(resource_id, {
		"display_name": resource_id.replace("_", " ").capitalize(),
		"category": "unknown",
		"texture": null,
		"visual_color": Color.WHITE,
		"visual_scale": Vector2.ONE,
		"visual_offset": Vector2.ZERO,
	})


static func register_texture(resource_id: String, texture: Texture2D, scale := Vector2.ONE, offset := Vector2.ZERO) -> void:
	var entry := definition(resource_id).duplicate(true)
	entry.texture = texture
	entry.visual_scale = scale
	entry.visual_offset = offset
	definitions[resource_id] = entry
