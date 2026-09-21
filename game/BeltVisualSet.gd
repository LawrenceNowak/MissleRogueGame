class_name BeltVisualSet
extends Resource

# Optional art hooks. When a slot is empty FactoryWorld draws normalized lane
# paths, so replacing belt art never changes transport geometry or simulation.
@export var straight_ew: Texture2D
@export var straight_ns: Texture2D
@export var corner_en: Texture2D
@export var corner_es: Texture2D
@export var corner_wn: Texture2D
@export var corner_ws: Texture2D
@export var corner_ne: Texture2D
@export var corner_nw: Texture2D
@export var corner_se: Texture2D
@export var corner_sw: Texture2D
@export var splitter: Texture2D
@export var fallback: Texture2D


func texture_for(topology: String) -> Texture2D:
	var texture: Texture2D
	match topology:
		"STRAIGHT_EW": texture = straight_ew
		"STRAIGHT_NS": texture = straight_ns
		"CORNER_EN": texture = corner_en
		"CORNER_ES": texture = corner_es
		"CORNER_WN": texture = corner_wn
		"CORNER_WS": texture = corner_ws
		"CORNER_NE": texture = corner_ne
		"CORNER_NW": texture = corner_nw
		"CORNER_SE": texture = corner_se
		"CORNER_SW": texture = corner_sw
		"SPLITTER": texture = splitter
	return texture if texture != null else fallback
