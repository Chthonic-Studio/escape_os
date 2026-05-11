class_name CrowdingMutator
extends CorruptionMutator

## Corruption Mutator: Crowding
##
## Removes 1–2 escape pods from ShipData after ship generation, reducing the
## number of available evacuation slots and forcing NPCs to compete.

func _init() -> void:
	mutator_id = &"crowding"
	display_name = "Crowding"
	description = "1–2 escape pods are removed from the level after generation."
	stability_tier = 3

func _connect_hooks() -> void:
	EventBus.ship_generated.connect(_on_ship_generated)

func _on_run_end() -> void:
	if EventBus.ship_generated.is_connected(_on_ship_generated):
		EventBus.ship_generated.disconnect(_on_ship_generated)

func _on_ship_generated(_pod_positions: Array) -> void:
	var pods_to_remove: int = randi_range(1, 2)
	for _i in range(pods_to_remove):
		if ShipData.escape_pod_positions.is_empty():
			break
		## Remove the pod position furthest from ship centre to keep at
		## least one pod reachable near the start area.
		var center: Vector2 = Vector2(
			ShipData.grid_rect.position.x + ShipData.grid_rect.size.x * 0.5,
			ShipData.grid_rect.position.y + ShipData.grid_rect.size.y * 0.5
		) * Vector2(ShipData.tile_size)
		var worst_idx: int = 0
		var worst_dist: float = -1.0
		for i in range(ShipData.escape_pod_positions.size()):
			var d: float = ShipData.escape_pod_positions[i].distance_to(center)
			if d > worst_dist:
				worst_dist = d
				worst_idx = i
		ShipData.escape_pod_positions.remove_at(worst_idx)
