class_name RoomTheme
extends Resource

enum RoomType {
	GENERIC,
	BARRACKS,
	CAFETERIA,
	OFFICE,
	MEDBAY,
	ENGINE_ROOM,
	BRIDGE,
	CARGO_BAY,
	RECREATION,
}

enum PropPlacement {
	ANYWHERE,
	WALL_ADJACENT,
	CORNERS,
	CENTER,
}

@export_category("Theme Info")
@export var theme_name: String = "Standard"
@export var room_type: RoomType = RoomType.GENERIC
@export var spawn_weight: float = 1.0

@export_category("Floor Tiles")
@export var floor_coords: Array[Vector2i] = []
@export var floor_weights: Array[float] = []

@export_category("Props & Obstacles")
@export var prop_scenes: Array[PackedScene] = []
@export var min_props_per_room: int = 0
@export var max_props_per_room: int = 3

@export_category("Prop Placement")
@export var prop_placement: PropPlacement = PropPlacement.ANYWHERE
@export var min_prop_spacing: float = 24.0

func get_random_floor_coord() -> Vector2i:
	if floor_coords.is_empty():
		return Vector2i.ZERO
	if floor_coords.size() == 1 or floor_weights.size() != floor_coords.size():
		return floor_coords[0]
		
	var total_weight: float = 0.0
	for w in floor_weights:
		total_weight += w
		
	var roll: float = randf_range(0.0, total_weight)
	var current_weight: float = 0.0
	
	for i in range(floor_coords.size()):
		current_weight += floor_weights[i]
		if roll <= current_weight:
			return floor_coords[i]
			
	return floor_coords[0]

func get_random_prop() -> PackedScene:
	if prop_scenes.is_empty():
		return null
	return prop_scenes.pick_random()
