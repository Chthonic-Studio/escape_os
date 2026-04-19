class_name HVTTracker
extends Node

## Manages the High-Value Target list in the sidebar.

const HVT_ENTRY_SCENE = preload("res://Scenes/hvt_entry.tscn")
const HVT_VALUE_THRESHOLD: float = 10.0

var _grid_container: GridContainer = null

var _entries: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_find_grid_container")
	EventBus.npc_spawned.connect(_on_npc_spawned)

func _find_grid_container() -> void:
	var grid_nodes := get_tree().get_nodes_in_group("hvt_grid")
	if not grid_nodes.is_empty():
		_grid_container = grid_nodes[0] as GridContainer

func _on_npc_spawned(_npc_class_id: StringName, _global_pos: Vector2, _room_type: int) -> void:
	call_deferred("_check_new_hvts")

func _check_new_hvts() -> void:
	if _grid_container == null:
		_find_grid_container()
	if _grid_container == null:
		return

	var npcs := get_tree().get_nodes_in_group("npcs")
	for npc in npcs:
		if not is_instance_valid(npc) or not npc is HumanController:
			continue
		var iid: int = npc.get_instance_id()
		if _entries.has(iid):
			continue
		if npc.npc_class and npc.npc_class.corporate_value >= HVT_VALUE_THRESHOLD:
			_add_hvt_entry(npc)

func _add_hvt_entry(npc: HumanController) -> void:
	var entry: HVTEntry = HVT_ENTRY_SCENE.instantiate()
	_grid_container.add_child(entry)
	entry.setup(npc)
	_entries[npc.get_instance_id()] = entry
