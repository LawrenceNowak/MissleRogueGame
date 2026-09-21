class_name QuickbarState
extends RefCounted

signal slots_changed
signal selected_changed(item_id: String, slot_index: int)

const SLOT_COUNT := 10

var slots: Array[String] = []
var selected_slot := -1
var inventory: RunInventory
var seen_item_ids: Dictionary = {}


func setup(shared_inventory: RunInventory) -> void:
	if inventory != null and inventory.item_changed.is_connected(_on_item_changed):
		inventory.item_changed.disconnect(_on_item_changed)
	inventory = shared_inventory
	inventory.item_changed.connect(_on_item_changed)
	reset_run()


func reset_run() -> void:
	slots.clear()
	for _index in SLOT_COUNT:
		slots.append("")
	selected_slot = -1
	seen_item_ids.clear()
	if inventory != null:
		for entry in inventory.stack_entries():
			seen_item_ids[str(entry.item_id)] = true
		for starter_id in [RunInventory.BELT, RunInventory.MINING_DRILL]:
			if inventory.amount(starter_id) > 0:
				assign_first_empty(starter_id)
	slots_changed.emit()


func item_at(slot_index: int) -> String:
	return slots[slot_index] if slot_index >= 0 and slot_index < slots.size() else ""


func assign(slot_index: int, item_id: String) -> bool:
	if slot_index < 0 or slot_index >= SLOT_COUNT or not ItemCatalog.has(item_id):
		return false
	var old_slot := slots.find(item_id)
	if old_slot >= 0 and old_slot != slot_index:
		slots[old_slot] = ""
	slots[slot_index] = item_id
	slots_changed.emit()
	if selected_slot == slot_index:
		selected_changed.emit(item_id, selected_slot)
	return true


func assign_first_empty(item_id: String) -> bool:
	if slots.has(item_id):
		return false
	var empty_slot := slots.find("")
	return assign(empty_slot, item_id) if empty_slot >= 0 else false


func clear(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= SLOT_COUNT:
		return false
	slots[slot_index] = ""
	if selected_slot == slot_index:
		selected_slot = -1
		selected_changed.emit("", -1)
	slots_changed.emit()
	return true


func select(slot_index: int) -> String:
	if slot_index < 0 or slot_index >= SLOT_COUNT:
		return ""
	selected_slot = slot_index
	var item_id := slots[slot_index]
	selected_changed.emit(item_id, selected_slot)
	slots_changed.emit()
	return item_id


func selected_item_id() -> String:
	return item_at(selected_slot)


func deselect() -> void:
	selected_slot = -1
	selected_changed.emit("", -1)
	slots_changed.emit()


func _on_item_changed(item_id: String, quantity: int, delta: int) -> void:
	var old_quantity := quantity - delta
	if old_quantity <= 0 and quantity > 0 and not seen_item_ids.has(item_id):
		seen_item_ids[item_id] = true
		assign_first_empty(item_id)
	slots_changed.emit()
