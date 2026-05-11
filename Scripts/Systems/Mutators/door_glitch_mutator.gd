class_name DoorGlitchMutator
extends CorruptionMutator

## Corruption Mutator: Door Glitch
##
## After ship generation, randomly locks N doors (prevents them from being
## opened by clicks), fragmenting the map and forcing NPCs onto alternate paths.

## Number of doors to lock.  Scales slightly with stability_tier.
const DOORS_TO_LOCK_BASE: int = 2
const DOORS_TO_LOCK_MAX: int = 5

func _init() -> void:
	mutator_id = &"door_glitch"
	display_name = "Door Glitch"
	description = "Several doors are permanently locked after level generation."
	stability_tier = 6

func _connect_hooks() -> void:
	EventBus.ship_generated.connect(_on_ship_generated)

func _on_run_end() -> void:
	if EventBus.ship_generated.is_connected(_on_ship_generated):
		EventBus.ship_generated.disconnect(_on_ship_generated)

func _on_ship_generated(_pod_positions: Array) -> void:
	## Collect all valid DoorSystem nodes in the scene.
	var doors: Array = []
	for room_idx in ShipData.room_doors:
		for door in ShipData.room_doors[room_idx]:
			if is_instance_valid(door) and door is DoorSystem and not door.is_destroyed:
				if not doors.has(door):
					doors.append(door)

	if doors.is_empty():
		return

	doors.shuffle()
	var count: int = mini(DOORS_TO_LOCK_MAX, maxi(DOORS_TO_LOCK_BASE, doors.size()))
	for i in range(count):
		## Mark the door as permanently non-interactive by closing it.
		## Full "locked" mechanic is a future extension; for now we simply
		## close it so NPCs treat it as a barrier.
		if doors[i].has_method("set_locked"):
			doors[i].set_locked(true)
		elif doors[i].is_open:
			doors[i].toggle_door()
