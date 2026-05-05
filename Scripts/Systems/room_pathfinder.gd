extends Node

## Room-graph A* pathfinder.
##
## Replaces per-frame NavigationServer2D path queries for high-level routing.
## The room adjacency graph is small (~8-20 nodes), so A* is near-instant.
## Paths and door world-positions are pre-computed during the loading screen
## and cached for the lifetime of a level. The cache is invalidated whenever
## a door opens or closes (nav_graph_changed).

## Cached paths: Vector2i(from_room, to_room) → Array[int]
var _path_cache: Dictionary = {}

## Cached door world-positions: Vector2i(min_room, max_room) → Vector2
var _door_pos_cache: Dictionary = {}

func _ready() -> void:
	EventBus.nav_graph_changed.connect(_on_nav_graph_changed)
	EventBus.ship_generated.connect(_on_ship_generated)

## Called after ship generation completes.
## Builds door-position lookup and pre-warms the path cache for all room pairs.
func _on_ship_generated(_pod_positions: Array) -> void:
	_path_cache.clear()
	_build_door_pos_cache()
	_precompute_all_paths()

## Builds a door world-position lookup keyed by the sorted room-index pair.
func _build_door_pos_cache() -> void:
	_door_pos_cache.clear()
	for room_a: int in ShipData.room_doors:
		for door in ShipData.room_doors[room_a]:
			if not is_instance_valid(door):
				continue
			var room_b: int = -1
			if door.room_a_index == room_a:
				room_b = door.room_b_index
			elif door.room_b_index == room_a:
				room_b = door.room_a_index
			if room_b < 0:
				continue
			var key := Vector2i(mini(room_a, room_b), maxi(room_a, room_b))
			if not _door_pos_cache.has(key):
				_door_pos_cache[key] = door.global_position

## Returns the world position of the door between two adjacent rooms.
## Falls back to the center of room_b when no door is cached.
func get_door_pos(room_a: int, room_b: int) -> Vector2:
	var key := Vector2i(mini(room_a, room_b), maxi(room_a, room_b))
	return _door_pos_cache.get(key, ShipData.get_room_center_world(room_b))

## Returns the ordered list of room indices from from_room to to_room.
## Results are cached after the first query.
func find_path(from_room: int, to_room: int) -> Array[int]:
	if from_room == to_room:
		return [from_room]

	var cache_key := Vector2i(from_room, to_room)
	if _path_cache.has(cache_key):
		return _path_cache[cache_key]

	var came_from: Dictionary = {}
	var g_score: Dictionary = {}
	var f_score: Dictionary = {}
	## open_set: room_idx → true
	var open_set: Dictionary = {}

	var start_pos: Vector2 = ShipData.get_room_center_world(from_room)
	var end_pos: Vector2 = ShipData.get_room_center_world(to_room)

	g_score[from_room] = 0.0
	f_score[from_room] = start_pos.distance_to(end_pos)
	open_set[from_room] = true

	while not open_set.is_empty():
		var current: int = -1
		var best_f: float = INF
		for room_idx: int in open_set:
			var f: float = f_score.get(room_idx, INF)
			if f < best_f:
				best_f = f
				current = room_idx

		if current == to_room:
			var path: Array[int] = []
			var node: int = current
			while came_from.has(node):
				path.push_front(node)
				node = came_from[node]
			path.push_front(from_room)
			_path_cache[cache_key] = path
			return path

		open_set.erase(current)

		if not ShipData.room_adjacency.has(current):
			continue

		for neighbor: int in ShipData.room_adjacency[current]:
			var edge_cost: float = ShipData.get_room_center_world(current).distance_to(
				ShipData.get_room_center_world(neighbor))
			var tentative_g: float = g_score.get(current, INF) + edge_cost
			if tentative_g < g_score.get(neighbor, INF):
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				f_score[neighbor] = tentative_g + ShipData.get_room_center_world(neighbor).distance_to(end_pos)
				open_set[neighbor] = true

	## No path found — return a single-element path so callers can fall back gracefully.
	var fallback: Array[int] = [from_room]
	_path_cache[cache_key] = fallback
	return fallback

## Returns the immediate next room to enter when travelling from from_room to to_room.
## Returns to_room when already adjacent or no path exists.
func get_next_room(from_room: int, to_room: int) -> int:
	if from_room == to_room:
		return to_room
	var path: Array[int] = find_path(from_room, to_room)
	if path.size() >= 2:
		return path[1]
	return to_room

## Invalidate cached paths when doors open/close — open doors change reachability costs.
func _on_nav_graph_changed() -> void:
	_path_cache.clear()

## Pre-compute paths for every room pair so the first hunt/flee is instant.
func _precompute_all_paths() -> void:
	var count: int = ShipData.rooms.size()
	for i: int in range(count):
		for j: int in range(count):
			if i != j:
				find_path(i, j)
