class_name TransportResources
extends RefCounted

static func definition(resource_id: String) -> Dictionary:
	var item := ItemCatalog.definition(resource_id)
	return {
		"stable_id": item.stable_id,
		"display_name": item.display_name,
		"category": ItemCatalog.category_name(item.category).to_lower(),
		"texture": item.icon,
		"visual_color": item.visual_color,
		"visual_scale": item.visual_scale,
		"visual_offset": item.visual_offset,
	}
