class_name EngineeringUI
extends Panel

signal close_requested
signal project_completion_requested(project_id: String)
signal fabrication_requested(recipe_id: String)

var inventory: RunInventory
var research: ResearchState
var workshop: WeaponWorkshop
var project_label: Label
var project_cost_label: Label
var research_button: Button
var workshop_label: Label
var fabrication_button: Button


func setup(shared_inventory: RunInventory, shared_research: ResearchState, shared_workshop: WeaponWorkshop) -> void:
	inventory = shared_inventory
	research = shared_research
	workshop = shared_workshop
	position = Vector2(300, 60)
	size = Vector2(680, 600)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.055, 0.09, 0.99)
	style.border_color = Color("#4f88a8")
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	add_theme_stylebox_override("panel", style)
	_build_ui()
	inventory.changed.connect(refresh)
	research.changed.connect(refresh)
	visible = false


func open() -> void:
	visible = true
	refresh()


func close() -> void:
	visible = false
	close_requested.emit()


func refresh() -> void:
	if inventory == null:
		return
	var project_id := ResearchProjects.MISSILE_LAUNCHER_DEVELOPMENT
	var project := ResearchProjects.definition(project_id)
	var state := research.status(project_id, inventory)
	if state == ResearchState.ProjectStatus.HIDDEN:
		project_label.text = "UNDISCOVERED ENGINEERING PROJECT\n%s — HIDDEN\n%s" % [str(project.branch), str(project.reveal_hint)]
		project_cost_label.text = "Requirements and unlock remain hidden until discovery."
	else:
		project_label.text = "%s\n%s — %s\n%s" % [str(project.display_name).to_upper(), str(project.branch), research.status_name(state), str(project.description)]
		var prerequisites := "None" if Array(project.prerequisites).is_empty() else ", ".join(Array(project.prerequisites))
		project_cost_label.text = "PREREQUISITES\n%s\n\nRESEARCH REQUIREMENTS\n%s\n\nUNLOCK\nMissile Launcher Blueprint" % [prerequisites, _cost_text(project.costs)]
	research_button.disabled = state != ResearchState.ProjectStatus.AVAILABLE
	research_button.text = "BLUEPRINT UNLOCKED" if state == ResearchState.ProjectStatus.COMPLETED else ("COMPLETE PROJECT" if state == ResearchState.ProjectStatus.AVAILABLE else "REQUIREMENTS NOT MET")
	var recipe_id := WeaponRecipes.MISSILE_LAUNCHER_RECIPE
	var recipe := WeaponRecipes.definition(recipe_id)
	var known := workshop.is_recipe_known(recipe_id)
	workshop_label.text = "WEAPON WORKSHOP\n%s\n%s\n\nOutput: Missile Launcher x1 (ammunition not included)" % ["BLUEPRINT KNOWN" if known else "LOCKED — COMPLETE RESEARCH", _cost_text(recipe.inputs)]
	fabrication_button.disabled = not workshop.can_fabricate(recipe_id)
	fabrication_button.text = "FABRICATE LAUNCHER" if known else "RECIPE LOCKED"


func _build_ui() -> void:
	var title := _label("ENGINEERING PROJECTS", 26, Color("#8ef5ff"), Rect2(24, 18, 540, 38))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	project_label = _label("", 15, Color("#e8f0ff"), Rect2(24, 67, 632, 92))
	project_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	project_cost_label = _label("", 14, Color("#c6d7ea"), Rect2(24, 172, 390, 198))
	research_button = _button("COMPLETE PROJECT", Rect2(438, 252, 218, 44), func(): project_completion_requested.emit(ResearchProjects.MISSILE_LAUNCHER_DEVELOPMENT))
	var separator := HSeparator.new()
	separator.position = Vector2(24, 385)
	separator.size = Vector2(632, 8)
	add_child(separator)
	workshop_label = _label("", 14, Color("#e8f0ff"), Rect2(24, 405, 400, 130))
	fabrication_button = _button("FABRICATE LAUNCHER", Rect2(438, 455, 218, 44), func(): fabrication_requested.emit(WeaponRecipes.MISSILE_LAUNCHER_RECIPE))
	_button("CLOSE", Rect2(520, 545, 136, 38), close)


func _label(text_value: String, font_size: int, color: Color, rect: Rect2) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = rect.position
	label.size = rect.size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	return label


func _button(text_value: String, rect: Rect2, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.position = rect.position
	button.size = rect.size
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	add_child(button)
	return button


func _cost_text(costs: Dictionary) -> String:
	var lines: Array[String] = []
	for item_id in costs:
		var definition := ItemCatalog.definition(str(item_id))
		lines.append("%s   %d / %d" % [definition.display_name, inventory.amount(str(item_id)), int(costs[item_id])])
	return "\n".join(lines)
