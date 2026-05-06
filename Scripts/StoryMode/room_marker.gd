class_name RoomMarker
extends Node2D

## Marks a room region in a story-mode level.
##
## Place this node as a child of StoryLevelController in your level .tscn.
## Set room_rect_tiles to match the tile-coordinate bounds of the room.
## The StoryLevelController reads these to populate ShipData.rooms,
## build the navigation mesh, and drive room-graph pathfinding.
##
## Doors placed in the level are auto-assigned to rooms based on proximity.

@export_category("Room Info")
@export var room_type: RoomTheme.RoomType = RoomTheme.RoomType.GENERIC
## Room bounds in tile coordinates (x, y, width, height in tiles).
@export var room_rect_tiles: Rect2i = Rect2i(0, 0, 10, 8)
## Whether this room is on the ship's outer edge (eligible for escape pod placement).
@export var is_outer_room: bool = false

## Returns the room's world-space Rect2 given a tile size.
func get_world_rect(tile_size: Vector2i) -> Rect2:
	var pos := Vector2(room_rect_tiles.position.x * tile_size.x, room_rect_tiles.position.y * tile_size.y)
	var size := Vector2(room_rect_tiles.size.x * tile_size.x, room_rect_tiles.size.y * tile_size.y)
	return Rect2(pos, size)

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	## Draw a semi-transparent overlay in the editor for visual feedback.
	var ts := Vector2i(16, 16)
	var r: Rect2 = get_world_rect(ts)
	var local_r := Rect2(r.position - global_position, r.size)
	draw_rect(local_r, Color(0.3, 0.7, 1.0, 0.15), true)
	draw_rect(local_r, Color(0.3, 0.7, 1.0, 0.6), false, 1.0)
	draw_string(ThemeDB.fallback_font, local_r.position + Vector2(4, 12),
			RoomTheme.RoomType.keys()[room_type], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.9, 1.0, 0.8))
