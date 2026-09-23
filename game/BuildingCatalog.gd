class_name BuildingCatalog
extends RefCounted

const RESEARCH_LAB_ID := "research_lab"
const RESEARCH_LAB_COST := 15

static var _definitions: Dictionary = {}

static func definition(stable_id: String) -> BuildingDefinition:
	_ensure_catalog()
	return _definitions.get(stable_id) as BuildingDefinition

static func _ensure_catalog() -> void:
	if not _definitions.is_empty():
		return
	var research_lab := BuildingDefinition.new()
	research_lab.stable_id = RESEARCH_LAB_ID
	research_lab.display_name = "Research Lab"
	research_lab.cost = RESEARCH_LAB_COST
	research_lab.footprint = Vector2i(2, 2)
	research_lab.max_health = 120.0
	research_lab.scene = preload("res://game/ResearchLab.tscn")
	research_lab.category = BuildingDefinition.Category.RESEARCH
	research_lab.description = "Prototype support building. Research functionality comes later."
	_definitions[research_lab.stable_id] = research_lab
