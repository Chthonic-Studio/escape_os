extends Node

## Persistent data about the most recently generated ship.

var floor_cells: Dictionary = {}

var wall_cells: Dictionary = {}

## Room rects in tile coordinates, paired with assigned RoomType.
var rooms: Array[Dictionary] = []

var escape_pod_positions: Array[Vector2] = []

var tile_size: Vector2i = Vector2i(16, 16)

var grid_rect: Rect2i = Rect2i()

var traversable_rects: Array[Rect2i] = []

## Maps room_index → Array of adjacent room indices.
var room_adjacency: Dictionary = {}

var door_rooms: Dictionary = {}

var room_doors: Dictionary = {}

var airlock_rooms: Array[int] = []

## Room indices that are on the outer edge of the ship (leaf touches grid border).
var outer_room_indices: Array[int] = []

var depressurized_rooms: Dictionary = {}

## Cached NPC counts per room, updated centrally via update_npc_room_counts().
var npc_room_counts: Dictionary = {}

## Pre-computed lookup: tile cell (Vector2i) → room index (int).
var _cell_to_room: Dictionary = {}

## Live NPC node cache — maintained via npc_ready / npc_died signals.
## Use instead of get_tree().get_nodes_in_group("npcs").
var cached_npcs: Array = []

## Live enemy node cache — maintained via enemy_ready / enemy_died signals.
## Use instead of get_tree().get_nodes_in_group("enemies").
var cached_enemies: Array = []

func _ready() -> void:
	EventBus.npc_ready.connect(_on_npc_ready)
	EventBus.npc_died.connect(_on_npc_died)
	EventBus.npc_escaped.connect(_on_npc_escaped)
	EventBus.enemy_ready.connect(_on_enemy_ready)
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.ship_generated.connect(_on_ship_generated)

func _on_ship_generated(_pod_positions: Array) -> void:
	## Cache clearing is handled in clear() which is called at the start of generate_ship().
	## Nothing to do here — NPCs and enemies register themselves via npc_ready/enemy_ready
	## signals during their _ready() calls, which fire before ship_generated.
	pass

func _on_npc_ready(npc: Node) -> void:
	if not cached_npcs.has(npc):
		cached_npcs.append(npc)

func _on_npc_died(npc: Node) -> void:
	_remove_npc_from_cache(npc)

func _on_npc_escaped(npc: Node) -> void:
	_remove_npc_from_cache(npc)

func _remove_npc_from_cache(npc: Node) -> void:
	cached_npcs.erase(npc)

func _on_enemy_ready(enemy: Node) -> void:
	if not cached_enemies.has(enemy):
		cached_enemies.append(enemy)

func _on_enemy_died(enemy: Node) -> void:
	cached_enemies.erase(enemy)

func clear() -> void:
	floor_cells.clear()
	wall_cells.clear()
	rooms.clear()
	escape_pod_positions.clear()
	traversable_rects.clear()
	room_adjacency.clear()
	door_rooms.clear()
	room_doors.clear()
	airlock_rooms.clear()
	outer_room_indices.clear()
	depressurized_rooms.clear()
	npc_room_counts.clear()
	_cell_to_room.clear()
	cached_npcs.clear()
	cached_enemies.clear()

func get_wall_adjacent_floor_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var neighbors := [
		Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT
	]
	for cell in floor_cells.keys():
		for offset in neighbors:
			if wall_cells.has(cell + offset):
				result.append(cell)
				break
	return result

func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * tile_size.x + tile_size.x * 0.5,
				   cell.y * tile_size.y + tile_size.y * 0.5)

func get_room_at_world_pos(world_pos: Vector2) -> int:
	var cell := Vector2i(
		int(world_pos.x / tile_size.x),
		int(world_pos.y / tile_size.y)
	)
	return _cell_to_room.get(cell, -1)

## Call once after generation to populate the cell→room lookup table.
func build_cell_to_room_cache() -> void:
	_cell_to_room.clear()
	for i in range(rooms.size()):
		var rect: Rect2i = rooms[i]["rect"]
		for x in range(rect.position.x, rect.end.x):
			for y in range(rect.position.y, rect.end.y):
				_cell_to_room[Vector2i(x, y)] = i

func get_room_center_world(room_index: int) -> Vector2:
	if room_index < 0 or room_index >= rooms.size():
		return Vector2.ZERO
	var rect: Rect2i = rooms[room_index]["rect"]
	var cx: float = (rect.position.x + rect.size.x * 0.5) * tile_size.x
	var cy: float = (rect.position.y + rect.size.y * 0.5) * tile_size.y
	return Vector2(cx, cy)

func get_room_world_rect(room_index: int) -> Rect2:
	if room_index < 0 or room_index >= rooms.size():
		return Rect2()
	var rect: Rect2i = rooms[room_index]["rect"]
	var pos := Vector2(rect.position.x * tile_size.x, rect.position.y * tile_size.y)
	var size := Vector2(rect.size.x * tile_size.x, rect.size.y * tile_size.y)
	return Rect2(pos, size)

func get_rooms_within_adjacency(source_room: int, degree: int) -> Array:
	var visited: Dictionary = {}
	var frontier: Array = [source_room]
	visited[source_room] = true

	for _d in range(degree):
		var next_frontier: Array = []
		for room_idx in frontier:
			if not room_adjacency.has(room_idx):
				continue
			for neighbor_idx in room_adjacency[room_idx]:
				if not visited.has(neighbor_idx):
					visited[neighbor_idx] = true
					next_frontier.append(neighbor_idx)
		frontier = next_frontier

	var result: Array = []
	for key in visited.keys():
		result.append(key)
	return result

func register_door_connection(door_node: Node, room_a_index: int, room_b_index: int) -> void:
	door_rooms[door_node] = { "room_a": room_a_index, "room_b": room_b_index }

	if not room_doors.has(room_a_index):
		room_doors[room_a_index] = []
	if door_node not in room_doors[room_a_index]:
		room_doors[room_a_index].append(door_node)

	if not room_doors.has(room_b_index):
		room_doors[room_b_index] = []
	if door_node not in room_doors[room_b_index]:
		room_doors[room_b_index].append(door_node)

	if not room_adjacency.has(room_a_index):
		room_adjacency[room_a_index] = []
	if room_b_index not in room_adjacency[room_a_index]:
		room_adjacency[room_a_index].append(room_b_index)

	if not room_adjacency.has(room_b_index):
		room_adjacency[room_b_index] = []
	if room_a_index not in room_adjacency[room_b_index]:
		room_adjacency[room_b_index].append(room_a_index)

## Updates NPC counts per room each frame using the cached NPC list.
func update_npc_room_counts() -> void:
	npc_room_counts.clear()
	for npc in cached_npcs:
		if not is_instance_valid(npc) or not npc is Node2D:
			continue
		var room_idx: int = get_room_at_world_pos(npc.global_position)
		if room_idx >= 0:
			npc_room_counts[room_idx] = npc_room_counts.get(room_idx, 0) + 1
