class_name ResearchProjects
extends RefCounted

const MISSILE_LAUNCHER_DEVELOPMENT := "missile_launcher_development"

const BRANCH_BALLISTICS := "BALLISTICS"
const BRANCH_GUIDED_WEAPONS := "GUIDED WEAPONS"
const BRANCH_DETECTION := "DETECTION"
const BRANCH_LOGISTICS := "LOGISTICS"
const BRANCH_PRODUCTION_ENGINEERING := "PRODUCTION ENGINEERING"

static var definitions := {
	MISSILE_LAUNCHER_DEVELOPMENT: {
		"stable_id": MISSILE_LAUNCHER_DEVELOPMENT,
		"display_name": "Missile Launcher Development",
		"description": "Recover guidance principles and engineer a reusable launcher blueprint.",
		"branch": BRANCH_GUIDED_WEAPONS,
		"prerequisites": [],
		"costs": {
			ItemCatalog.ORE: 12,
			ItemCatalog.ADVANCED_RESOURCE: 1,
		},
		"unlock_results": [
			{"type": "blueprint", "id": ItemCatalog.MISSILE_LAUNCHER},
		],
		"persistence": "permanent",
		"reveal_hint": "Clear the first defense wave.",
		"icon": null,
	},
}


static func definition(project_id: String) -> Dictionary:
	return Dictionary(definitions.get(project_id, {})).duplicate(true)


static func all_ids() -> Array[String]:
	var result: Array[String] = []
	for project_id in definitions:
		result.append(str(project_id))
	return result
