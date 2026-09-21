class_name ResearchState
extends RefCounted

signal project_revealed(project_id: String)
signal project_completed(project_id: String)
signal blueprint_unlocked(blueprint_id: String)
signal changed

enum ProjectStatus { HIDDEN, REVEALED, AVAILABLE, COMPLETED }

var revealed_projects: Dictionary = {}
var completed_projects: Dictionary = {}
var unlocked_blueprints: Dictionary = {}
var generic_unlocks: Dictionary = {}


func begin_run() -> void:
	revealed_projects.clear()
	for project_id in completed_projects:
		revealed_projects[project_id] = true
	changed.emit()


func reveal_project(project_id: String) -> bool:
	if ResearchProjects.definition(project_id).is_empty() or revealed_projects.has(project_id):
		return false
	revealed_projects[project_id] = true
	project_revealed.emit(project_id)
	changed.emit()
	return true


func status(project_id: String, inventory: RunInventory) -> ProjectStatus:
	if completed_projects.has(project_id):
		return ProjectStatus.COMPLETED
	if not revealed_projects.has(project_id):
		return ProjectStatus.HIDDEN
	var project := ResearchProjects.definition(project_id)
	if not _prerequisites_met(project):
		return ProjectStatus.REVEALED
	return ProjectStatus.AVAILABLE if inventory.can_remove_many(project.get("costs", {})) else ProjectStatus.REVEALED


func complete_project(project_id: String, inventory: RunInventory) -> bool:
	if status(project_id, inventory) != ProjectStatus.AVAILABLE:
		return false
	var project := ResearchProjects.definition(project_id)
	if not inventory.remove_many(project.get("costs", {})):
		return false
	completed_projects[project_id] = true
	for unlock in Array(project.get("unlock_results", [])):
		var unlock_type := str(unlock.get("type", ""))
		var unlock_id := str(unlock.get("id", ""))
		if unlock_type == "blueprint":
			unlocked_blueprints[unlock_id] = true
			blueprint_unlocked.emit(unlock_id)
		else:
			if not generic_unlocks.has(unlock_type): generic_unlocks[unlock_type] = {}
			generic_unlocks[unlock_type][unlock_id] = true
	project_completed.emit(project_id)
	changed.emit()
	return true


func has_blueprint(blueprint_id: String) -> bool:
	return unlocked_blueprints.has(blueprint_id)


func export_persistent() -> Dictionary:
	return {
		"completed_projects": completed_projects.keys(),
		"unlocked_blueprints": unlocked_blueprints.keys(),
		"generic_unlocks": generic_unlocks.duplicate(true),
	}


func import_persistent(data: Dictionary) -> void:
	completed_projects.clear()
	unlocked_blueprints.clear()
	generic_unlocks = Dictionary(data.get("generic_unlocks", {})).duplicate(true)
	for project_id in Array(data.get("completed_projects", [])):
		completed_projects[str(project_id)] = true
	for blueprint_id in Array(data.get("unlocked_blueprints", [])):
		unlocked_blueprints[str(blueprint_id)] = true
	begin_run()


func status_name(project_status: ProjectStatus) -> String:
	return ProjectStatus.keys()[int(project_status)]


func _prerequisites_met(project: Dictionary) -> bool:
	for prerequisite in Array(project.get("prerequisites", [])):
		if not completed_projects.has(str(prerequisite)):
			return false
	return true
