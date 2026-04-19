class_name CommsSystem
extends Node

## Manages the comms signal mode. Press E to toggle signal mode.

const SIGNAL_ADJACENCY_DEGREE: int = 2

var is_signal_mode: bool = false
var current_signal_type: StringName = &"move"

const SIGNAL_TYPES: Array[StringName] = [&"move", &"run", &"wait", &"lure"]

## Canonical signal type → display color mapping.
const SIGNAL_COLORS: Dictionary = {
	&"move": Color(0.3, 0.8, 1.0, 1.0),
	&"run": Color(1.0, 0.85, 0.0, 1.0),
	&"wait": Color(0.6, 0.6, 0.6, 1.0),
	&"lure": Color(0.8, 0.2, 1.0, 1.0),
}

const SIGNAL_NAMES: Dictionary = {
	&"move": "MOVE",
	&"run": "RUN",
	&"wait": "WAIT",
	&"lure": "LURE",
}

func _ready() -> void:
	add_to_group("comms_system")
	process_mode = Node.PROCESS_MODE_ALWAYS

func toggle_signal_mode() -> void:
	is_signal_mode = not is_signal_mode
	EventBus.comms_mode_changed.emit(is_signal_mode)
	_update_cursor()

func deactivate_signal_mode() -> void:
	if is_signal_mode:
		is_signal_mode = false
		EventBus.comms_mode_changed.emit(false)
		_update_cursor()

func cycle_signal_type() -> void:
	var idx: int = SIGNAL_TYPES.find(current_signal_type)
	idx = (idx + 1) % SIGNAL_TYPES.size()
	current_signal_type = SIGNAL_TYPES[idx]

func _update_cursor() -> void:
	if is_signal_mode:
		Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	else:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func send_signal_to_room(room_index: int) -> void:
	if room_index < 0:
		return

	var affected_rooms: Array = ShipData.get_rooms_within_adjacency(room_index, SIGNAL_ADJACENCY_DEGREE)
	EventBus.comms_signal_sent.emit(room_index, affected_rooms)

	var npcs := get_tree().get_nodes_in_group("npcs")
	for npc in npcs:
		if not is_instance_valid(npc) or not npc is Node2D:
			continue
		var npc_room: int = ShipData.get_room_at_world_pos(npc.global_position)
		if npc_room in affected_rooms:
			if npc.has_method("receive_comms_signal"):
				npc.receive_comms_signal(room_index, current_signal_type)

	if current_signal_type == &"lure":
		var target_pos: Vector2 = ShipData.get_room_center_world(room_index)
		var enemies := get_tree().get_nodes_in_group("enemies")
		for enemy in enemies:
			if not is_instance_valid(enemy) or not enemy is Node2D:
				continue
			if enemy.has_method("receive_lure_signal"):
				enemy.receive_lure_signal(target_pos)

	deactivate_signal_mode()
