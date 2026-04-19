class_name EnemySpawnManager
extends Node

## Picks wall-adjacent spawn spots for enemies.

@export var jitter_tiles: int = 3

func _ready() -> void:
	EventBus.enemy_spawn_requested.connect(_on_spawn_requested)

func _on_spawn_requested(spawn_type: StringName, count: int) -> void:
	match spawn_type:
		&"far":
			_spawn_far_from_pods(count)
		&"mid":
			_spawn_mid_map(count)
		&"near_pod":
			_spawn_near_pod(count)
		_:
			push_warning("EnemySpawnManager: unknown spawn_type '%s'" % spawn_type)

func _spawn_far_from_pods(count: int) -> void:
	var candidates := _get_wall_adjacent_candidates()
	if candidates.is_empty():
		return
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _min_pod_distance(a) > _min_pod_distance(b)
	)
	_emit_positions(candidates, count)

func _spawn_mid_map(count: int) -> void:
	var candidates := _get_wall_adjacent_candidates()
	if candidates.is_empty():
		return
	var center := Vector2(
		ShipData.grid_rect.position.x + ShipData.grid_rect.size.x * 0.5,
		ShipData.grid_rect.position.y + ShipData.grid_rect.size.y * 0.5
	)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return Vector2(a).distance_to(center) < Vector2(b).distance_to(center)
	)
	_emit_positions(candidates, count)

func _spawn_near_pod(count: int) -> void:
	if ShipData.escape_pod_positions.is_empty():
		_spawn_mid_map(count)
		return
	var pod_pos: Vector2 = ShipData.escape_pod_positions.pick_random()
	var pod_tile := Vector2i(
		int(pod_pos.x / ShipData.tile_size.x),
		int(pod_pos.y / ShipData.tile_size.y)
	)
	var candidates := _get_wall_adjacent_candidates()
	if candidates.is_empty():
		return
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return Vector2(a).distance_to(Vector2(pod_tile)) < Vector2(b).distance_to(Vector2(pod_tile))
	)
	_emit_positions(candidates, count)

func _get_wall_adjacent_candidates() -> Array[Vector2i]:
	return ShipData.get_wall_adjacent_floor_cells()

func _min_pod_distance(cell: Vector2i) -> float:
	var min_dist: float = INF
	for pod_pos in ShipData.escape_pod_positions:
		var pod_tile := Vector2i(
			int(pod_pos.x / ShipData.tile_size.x),
			int(pod_pos.y / ShipData.tile_size.y)
		)
		var d: float = Vector2(cell).distance_to(Vector2(pod_tile))
		if d < min_dist:
			min_dist = d
	return min_dist

func _emit_positions(sorted_candidates: Array[Vector2i], count: int) -> void:
	var used: int = 0
	var max_index: int = mini(sorted_candidates.size(), count * 4)
	var indices: Array[int] = []
	for i in range(max_index):
		indices.append(i)
	indices.shuffle()

	for i in indices:
		if used >= count:
			break
		var cell: Vector2i = sorted_candidates[i]
		var jx: int = randi_range(-jitter_tiles, jitter_tiles)
		var jy: int = randi_range(-jitter_tiles, jitter_tiles)
		var jittered := cell + Vector2i(jx, jy)
		if ShipData.floor_cells.has(jittered):
			cell = jittered
		var world_pos: Vector2 = ShipData.cell_to_world(cell)
		EventBus.enemy_spawn.emit(world_pos)
		used += 1

	if used < count:
		for i in range(sorted_candidates.size()):
			if used >= count:
				break
			var world_pos: Vector2 = ShipData.cell_to_world(sorted_candidates[i])
			EventBus.enemy_spawn.emit(world_pos)
			used += 1
