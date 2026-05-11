class_name NPCClass
extends Resource

@export_category("Identity")
@export var class_name_id: StringName = &"Crewmember"
@export var display_name: String = "Crewmember"
@export var class_color: Color = Color(0.608, 0.678, 0.718, 1.0)

@export_category("Corporate Metrics")
@export var corporate_value: float = 1.0 
@export_range(0.5, 2.0, 0.1) var speed_modifier: float = 1.0

@export_category("Spawn Preferences")
@export var room_type_weights: Dictionary = {}

@export_category("Specialist")
## Optional scene containing the specialist-specific state node to add to the
## StateMachine at runtime.  Null for generic crewmembers.
@export var specialist_state_scene: PackedScene = null

func pick_spawn_room_type(available_types: Array) -> int:
	if room_type_weights.is_empty() or available_types.is_empty():
		return -1

	var enum_keys: PackedStringArray = RoomTheme.RoomType.keys()
	var total_weight: float = 0.0
	var candidates: Array = []

	for room_type in available_types:
		if room_type < 0 or room_type >= enum_keys.size():
			continue
		var key: String = enum_keys[room_type]
		if room_type_weights.has(key):
			var w: float = room_type_weights[key]
			total_weight += w
			candidates.append({ "type": room_type, "weight": w })

	if total_weight <= 0.0 or candidates.is_empty():
		return -1

	var roll: float = randf_range(0.0, total_weight)
	var accum: float = 0.0
	for c in candidates:
		accum += c["weight"]
		if roll <= accum:
			return c["type"]
	return candidates[-1]["type"]
