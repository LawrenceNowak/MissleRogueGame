class_name FactoryInventoryUI
extends Control

signal panel_visibility_changed(is_open: bool)

var inventory: RunInventory
var quickbar: QuickbarState
var quickbar_panel: Panel
var inventory_panel: Panel
var inventory_list: VBoxContainer
var assignment_label: Label
var slot_buttons: Array[Button] = []
var pending_item_id := ""
var factory_visible := false


func setup(shared_inventory: RunInventory, shared_quickbar: QuickbarState) -> void:
	inventory = shared_inventory
	quickbar = shared_quickbar
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	inventory.changed.connect(refresh)
	quickbar.slots_changed.connect(refresh)
	refresh()


func set_factory_visible(value: bool) -> void:
	factory_visible = value
	quickbar_panel.visible = value
	if not value:
		inventory_panel.visible = false
		pending_item_id = ""
	panel_visibility_changed.emit(inventory_panel.visible)


func toggle_inventory() -> void:
	if not factory_visible:
		return
	inventory_panel.visible = not inventory_panel.visible
	if not inventory_panel.visible:
		pending_item_id = ""
	refresh()
	panel_visibility_changed.emit(inventory_panel.visible)


func close_inventory() -> void:
	if inventory_panel.visible:
		inventory_panel.visible = false
		pending_item_id = ""
		refresh()
		panel_visibility_changed.emit(false)


func refresh() -> void:
	if inventory == null or quickbar == null:
		return
	for index in slot_buttons.size():
		var button := slot_buttons[index]
		var item_id := quickbar.item_at(index)
		var key_name := str(index + 1) if index < 9 else "0"
		if item_id.is_empty():
			button.icon = null
			button.text = "%s\nEMPTY" % key_name
			button.tooltip_text = "Empty quickbar shortcut"
			button.modulate = Color(1, 1, 1, 0.6)
		else:
			var definition := ItemCatalog.definition(item_id)
			var quantity := inventory.get_quantity(item_id)
			button.icon = definition.icon
			var placeholder := "□ " if definition.icon == null else ""
			button.text = "%s\n%s%s  %d" % [key_name, placeholder, _short_name(definition.display_name), quantity]
			button.tooltip_text = "%s\n%s\nRight-click to clear shortcut." % [definition.display_name, definition.description]
			button.modulate = Color.WHITE if quantity > 0 else Color(0.55, 0.58, 0.62, 0.55)
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#244b59") if quickbar.selected_slot == index else Color("#102735")
		style.border_color = Color("#8ef5ff") if quickbar.selected_slot == index else Color("#31506f")
		style.set_border_width_all(2)
		style.set_corner_radius_all(5)
		button.add_theme_stylebox_override("normal", style)
	_rebuild_inventory_list()


func _build_ui() -> void:
	quickbar_panel = _panel(Rect2(50, 642, 1180, 74), Color(0.025, 0.055, 0.07, 0.97))
	for index in QuickbarState.SLOT_COUNT:
		var button := Button.new()
		button.position = Vector2(8 + index * 116, 7)
		button.size = Vector2(108, 60)
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(_on_slot_pressed.bind(index))
		button.gui_input.connect(_on_slot_gui_input.bind(index))
		quickbar_panel.add_child(button)
		slot_buttons.append(button)

	inventory_panel = _panel(Rect2(820, 150, 430, 420), Color(0.025, 0.055, 0.08, 0.98))
	inventory_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var title := Label.new()
	title.text = "ENGINEER INVENTORY"
	title.position = Vector2(18, 12)
	title.size = Vector2(394, 30)
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("#8ef5ff"))
	inventory_panel.add_child(title)
	var capacity_label := Label.new()
	capacity_label.name = "CapacityLabel"
	capacity_label.position = Vector2(18, 43)
	capacity_label.size = Vector2(394, 22)
	capacity_label.add_theme_font_size_override("font_size", 13)
	inventory_panel.add_child(capacity_label)
	assignment_label = Label.new()
	assignment_label.position = Vector2(18, 68)
	assignment_label.size = Vector2(394, 42)
	assignment_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	assignment_label.add_theme_font_size_override("font_size", 12)
	assignment_label.add_theme_color_override("font_color", Color("#ffe66d"))
	inventory_panel.add_child(assignment_label)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(16, 112)
	scroll.size = Vector2(398, 250)
	inventory_panel.add_child(scroll)
	inventory_list = VBoxContainer.new()
	inventory_list.custom_minimum_size = Vector2(374, 0)
	scroll.add_child(inventory_list)
	var close_button := Button.new()
	close_button.text = "CLOSE [I]"
	close_button.position = Vector2(145, 370)
	close_button.size = Vector2(140, 38)
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(toggle_inventory)
	inventory_panel.add_child(close_button)
	inventory_panel.visible = false


func _panel(rect: Rect2, color: Color) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("#31506f")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	return panel


func _rebuild_inventory_list() -> void:
	if inventory_list == null:
		return
	for child in inventory_list.get_children():
		child.queue_free()
	var capacity_label := inventory_panel.get_node("CapacityLabel") as Label
	capacity_label.text = "Stacks %d / %d" % [inventory.used_slots(), inventory.slot_capacity]
	assignment_label.text = "Click an item, then a quickbar slot to assign it. Right-click a quickbar slot to clear." if pending_item_id.is_empty() else "Assigning: %s — click a quickbar slot." % ItemCatalog.definition(pending_item_id).display_name
	for entry in inventory.stack_entries():
		var definition: ItemDefinition = entry.definition
		var button := Button.new()
		button.icon = definition.icon
		var placeholder := "□ " if definition.icon == null else ""
		button.text = "%s%s  x%d   [%s]" % [placeholder, definition.display_name, int(entry.quantity), ItemCatalog.category_name(definition.category)]
		button.tooltip_text = definition.description
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(365, 34)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_inventory_item_pressed.bind(str(entry.item_id)))
		inventory_list.add_child(button)


func _on_inventory_item_pressed(item_id: String) -> void:
	pending_item_id = item_id
	refresh()


func _on_slot_pressed(slot_index: int) -> void:
	if inventory_panel.visible and not pending_item_id.is_empty():
		quickbar.assign(slot_index, pending_item_id)
		pending_item_id = ""
		refresh()
	else:
		quickbar.select(slot_index)


func _on_slot_gui_input(event: InputEvent, slot_index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		quickbar.clear(slot_index)
		accept_event()


func _short_name(display_name: String) -> String:
	if display_name.length() <= 12:
		return display_name.to_upper()
	return display_name.substr(0, 11).to_upper() + "…"
