class_name ShipGenerator
extends Node2D

@export_category("Grid Dimensions (In Tiles)")
@export var ship_grid_size := Rect2i(0, 0, 40, 30)
@export var min_room_tiles := 8
@export var padding_tiles := 1
@export var corridor_width_tiles := 2

@export_category("References")
@export var door_scene: PackedScene
@export var escape_pod_scene: PackedScene
@export var npc_scene: PackedScene
@export var nav_region: NavigationRegion2D
@export var airlock_scene: PackedScene

@export_category("Theming & Terrains")
@export var visual_tilemap: TileMapLayer
@export var floor_tileset_source_id: int = 1
@export var wall_tileset_source_id: int = 0
@export var default_floor_coord := Vector2i(0, 0)
@export var default_wall_coord := Vector2i(0, 0)
@export var room_themes: Array[RoomTheme] = []

@export_category("Level Configuration")
@export var level_config: LevelConfig

@export_category("NPC Configuration")
@export var npc_classes: Array[NPCClass] = []

@export_range(0.0, 1.0, 0.05) var extra_corridor_chance: float = 0.4
## Places airlocks in a subset of rooms (roughly 20-30% of rooms).
@export_range(0.0, 1.0, 0.05) var airlock_chance: float = 0.25

var _leaves: Array[BSPLeaf] = []
var _tile_size: Vector2i = Vector2i(16, 16)
var _room_type_map: Dictionary = {}

class BSPLeaf:
	var x: int
	var y: int
	var width: int
	var height: int
	var left_child: BSPLeaf
	var right_child: BSPLeaf
	var room_rect: Rect2i
	
	func _init(start_x: int, start_y: int, w: int, h: int) -> void:
		x = start_x
		y = start_y
		width = w
		height = h
	
	func is_leaf() -> bool:
		return left_child == null and right_child == null
	
	func split(min_size: int) -> bool:
		if left_child != null or right_child != null:
			return false
			
		var split_horizontally: bool = randf() > 0.5
		if width > height and width / float(height) >= 1.25:
			split_horizontally = false
		elif height > width and height / float(width) >= 1.25:
			split_horizontally = true
			
		var max_split: int = (height if split_horizontally else width) - min_size
		if max_split <= min_size:
			return false
			
		var split_val: int = randi_range(min_size, max_split)
		
		if split_horizontally:
			left_child = BSPLeaf.new(x, y, width, split_val)
			right_child = BSPLeaf.new(x, y + split_val, width, height - split_val)
		else:
			left_child = BSPLeaf.new(x, y, split_val, height)
			right_child = BSPLeaf.new(x + split_val, y, width - split_val, height)
			
		return true
		
	func create_rooms(pad: int) -> void:
		if left_child != null or right_child != null:
			if left_child: left_child.create_rooms(pad)
			if right_child: right_child.create_rooms(pad)
		else:
			var rx: int = x + pad
			var ry: int = y + pad
			var rw: int = width - (pad * 2)
			var rh: int = height - (pad * 2)
			room_rect = Rect2i(rx, ry, rw, rh)
	
	func get_rooms() -> Array[Rect2i]:
		var rooms: Array[Rect2i] = []
		if is_leaf():
			if room_rect.size.x > 0 and room_rect.size.y > 0:
				rooms.append(room_rect)
		else:
			if left_child:
				rooms.append_array(left_child.get_rooms())
			if right_child:
				rooms.append_array(right_child.get_rooms())
		return rooms

func _ready() -> void:
	assert(nav_region != null, "ShipGenerator requires a NavigationRegion2D to bake.")
	if visual_tilemap == null:
		push_warning("ShipGenerator: visual_tilemap is null. Visuals will not be generated.")
	else:
		_tile_size = visual_tilemap.tile_set.tile_size
		
	EventBus.game_start_requested.connect(_on_game_start_requested)

func _on_game_start_requested() -> void:
	GameManager.reset()
	var config := UIManager.get_current_level_config()
	if config:
		level_config = config
	var gameplay_music := load("res://Assets/Audio/LD59_Gameplay.wav") as AudioStream
	if gameplay_music:
		AudioManager.play_music(gameplay_music)
	generate_ship()

func generate_ship() -> void:
	ShipData.clear()
	ShipData.tile_size = _tile_size
	ShipData.grid_rect = ship_grid_size

	EventBus.generation_progress.emit("PARTITIONING SHIP LAYOUT...", 0.05)

	var root := BSPLeaf.new(ship_grid_size.position.x, ship_grid_size.position.y, ship_grid_size.size.x, ship_grid_size.size.y)
	_leaves.append(root)

	var did_split := true
	while did_split:
		did_split = false
		for i in range(_leaves.size()):
			var leaf: BSPLeaf = _leaves[i]
			if leaf.is_leaf():
				if leaf.width > min_room_tiles * 2 or leaf.height > min_room_tiles * 2:
					if leaf.split(min_room_tiles):
						_leaves.append(leaf.left_child)
						_leaves.append(leaf.right_child)
						did_split = true

	root.create_rooms(padding_tiles)
	_draw_rooms_and_bake(root)

func _draw_rooms_and_bake(root: BSPLeaf) -> void:
	var nav_poly := NavigationPolygon.new()

	## Shrinks NavMesh by exactly half a tile so AI centers don't clip walls.
	nav_poly.agent_radius = float(_tile_size.x) * 0.5

	var traversable_rects: Array[Rect2i] = []
	var outer_leaves: Array[BSPLeaf] = []

	for leaf in _leaves:
		if leaf.is_leaf():
			traversable_rects.append(leaf.room_rect)

			var is_left_edge: bool = leaf.x <= ship_grid_size.position.x
			var is_right_edge: bool = (leaf.x + leaf.width) >= (ship_grid_size.position.x + ship_grid_size.size.x)
			var is_top_edge: bool = leaf.y <= ship_grid_size.position.y
			var is_bottom_edge: bool = (leaf.y + leaf.height) >= (ship_grid_size.position.y + ship_grid_size.size.y)

			if is_left_edge or is_right_edge or is_top_edge or is_bottom_edge:
				outer_leaves.append(leaf)

	EventBus.generation_progress.emit("CARVING CORRIDORS...", 0.20)
	_carve_corridors(root, traversable_rects)

	ShipData.traversable_rects = traversable_rects

	EventBus.generation_progress.emit("BAKING NAVIGATION MESH...", 0.40)
	var source_geometry := NavigationMeshSourceGeometryData2D.new()
	for rect in traversable_rects:
		var px_pos := Vector2(rect.position.x * _tile_size.x, rect.position.y * _tile_size.y)
		var px_size := Vector2(rect.size.x * _tile_size.x, rect.size.y * _tile_size.y)

		var outline := PackedVector2Array([
			px_pos,
			Vector2(px_pos.x + px_size.x, px_pos.y),
			px_pos + px_size,
			Vector2(px_pos.x, px_pos.y + px_size.y)
		])
		source_geometry.add_traversable_outline(outline)

	NavigationServer2D.bake_from_source_geometry_data(nav_poly, source_geometry)
	nav_region.navigation_polygon = nav_poly

	EventBus.generation_progress.emit("PAINTING SHIP INTERIORS...", 0.55)
	if visual_tilemap != null:
		_paint_visual_tiles(traversable_rects, _leaves)

	for leaf in outer_leaves:
		for i in range(ShipData.rooms.size()):
			if ShipData.rooms[i]["rect"] == leaf.room_rect:
				ShipData.outer_room_indices.append(i)
				break

	EventBus.generation_progress.emit("PLACING ESCAPE PODS...", 0.65)
	_place_escape_pods(outer_leaves)
	EventBus.generation_progress.emit("SPAWNING CREW...", 0.75)
	_spawn_npcs()
	EventBus.generation_progress.emit("REGISTERING DOORS...", 0.85)
	_register_door_rooms()
	_place_airlocks()
	ShipData.build_cell_to_room_cache()

	_label_rooms()

	EventBus.generation_progress.emit("COMPUTING PATHFINDING CACHE...", 0.95)
	## RoomPathfinder caches all paths when it receives ship_generated.
	EventBus.ship_generated.emit.call_deferred(ShipData.escape_pod_positions)

func _carve_corridors(node: BSPLeaf, traversable_rects: Array[Rect2i]) -> void:
	if node.left_child == null or node.right_child == null:
		return
		
	_carve_corridors(node.left_child, traversable_rects)
	_carve_corridors(node.right_child, traversable_rects)
	
	var left_rooms: Array[Rect2i] = node.left_child.get_rooms()
	var right_rooms: Array[Rect2i] = node.right_child.get_rooms()
	
	if left_rooms.is_empty() or right_rooms.is_empty():
		return
	
	var best_left: Rect2i = left_rooms[0]
	var best_right: Rect2i = right_rooms[0]
	var best_dist: float = INF
	
	for lr in left_rooms:
		var lr_center := Vector2(lr.position.x + lr.size.x / 2.0, lr.position.y + lr.size.y / 2.0)
		for rr in right_rooms:
			var rr_center := Vector2(rr.position.x + rr.size.x / 2.0, rr.position.y + rr.size.y / 2.0)
			var d: float = lr_center.distance_to(rr_center)
			if d < best_dist:
				best_dist = d
				best_left = lr
				best_right = rr
	
	_carve_single_corridor(node, best_left, best_right, traversable_rects)

	if left_rooms.size() >= 2 and right_rooms.size() >= 2 and randf() < extra_corridor_chance:
		var alt_left: Rect2i = left_rooms[0]
		var alt_right: Rect2i = right_rooms[0]
		var second_best_dist: float = INF

		for lr in left_rooms:
			for rr in right_rooms:
				if lr == best_left and rr == best_right:
					continue
				var lr_c := Vector2(lr.position.x + lr.size.x / 2.0, lr.position.y + lr.size.y / 2.0)
				var rr_c := Vector2(rr.position.x + rr.size.x / 2.0, rr.position.y + rr.size.y / 2.0)
				var d: float = lr_c.distance_to(rr_c)
				if d < second_best_dist:
					second_best_dist = d
					alt_left = lr
					alt_right = rr

		if alt_left != best_left or alt_right != best_right:
			_carve_single_corridor(node, alt_left, alt_right, traversable_rects)

func _carve_single_corridor(node: BSPLeaf, room_a: Rect2i, room_b: Rect2i, traversable_rects: Array[Rect2i]) -> void:
	var lc := Vector2i(
		room_a.position.x + room_a.size.x / 2,
		room_a.position.y + room_a.size.y / 2
	)
	var rc := Vector2i(
		room_b.position.x + room_b.size.x / 2,
		room_b.position.y + room_b.size.y / 2
	)
	
	var half_w: int = maxi(corridor_width_tiles / 2, 1)
	var is_horizontal_split: bool = node.left_child.x == node.right_child.x
	
	if is_horizontal_split:
		var vy_min: int = mini(lc.y, rc.y)
		var vy_max: int = maxi(lc.y, rc.y)
		var v_rect := Rect2i(lc.x - half_w, vy_min, corridor_width_tiles, vy_max - vy_min + 1)
		traversable_rects.append(v_rect)
		
		if absi(lc.x - rc.x) > 1:
			var hx_min: int = mini(lc.x, rc.x) - half_w
			var hx_max: int = maxi(lc.x, rc.x) + half_w
			var h_rect := Rect2i(hx_min, rc.y - half_w, hx_max - hx_min + 1, corridor_width_tiles)
			traversable_rects.append(h_rect)
		
		var boundary_y: int = node.right_child.y
		var door_px := Vector2(lc.x * _tile_size.x, boundary_y * _tile_size.y)
		_spawn_door(door_px, false, room_a, room_b)
	else:
		var hx_min: int = mini(lc.x, rc.x)
		var hx_max: int = maxi(lc.x, rc.x)
		var h_rect := Rect2i(hx_min, lc.y - half_w, hx_max - hx_min + 1, corridor_width_tiles)
		traversable_rects.append(h_rect)
		
		if absi(lc.y - rc.y) > 1:
			var vy_min: int = mini(lc.y, rc.y) - half_w
			var vy_max: int = maxi(lc.y, rc.y) + half_w
			var v_rect := Rect2i(rc.x - half_w, vy_min, corridor_width_tiles, vy_max - vy_min + 1)
			traversable_rects.append(v_rect)
		
		var boundary_x: int = node.right_child.x
		var door_px := Vector2(boundary_x * _tile_size.x, lc.y * _tile_size.y)
		_spawn_door(door_px, true, room_a, room_b)

var _pending_door_registrations: Array[Dictionary] = []

func _spawn_door(px_pos: Vector2, is_vertical: bool, room_a_rect: Rect2i = Rect2i(), room_b_rect: Rect2i = Rect2i()) -> void:
	if door_scene == null: return
	var door: Node2D = door_scene.instantiate()
	door.global_position = px_pos
	if is_vertical:
		door.rotation = PI / 2.0
	call_deferred("add_child", door)

	_pending_door_registrations.append({
		"door": door,
		"room_a_rect": room_a_rect,
		"room_b_rect": room_b_rect,
	})

func _place_escape_pods(outer_leaves: Array[BSPLeaf]) -> void:
	if escape_pod_scene == null or outer_leaves.is_empty(): return
	outer_leaves.shuffle()

	var pod_count: int = 3
	if level_config:
		pod_count = level_config.get_escape_pod_count()
	pod_count = mini(pod_count, outer_leaves.size())
	
	for i in range(pod_count):
		var leaf: BSPLeaf = outer_leaves[i]
		var room: Rect2i = leaf.room_rect
		var pod_pos := _get_border_position(leaf, room)
		
		var pod: Node2D = escape_pod_scene.instantiate()
		pod.global_position = pod_pos
		call_deferred("add_child", pod)
		ShipData.escape_pod_positions.append(pod_pos)

func _get_border_position(leaf: BSPLeaf, room: Rect2i) -> Vector2:
	var cx: float = (room.position.x + room.size.x / 2.0) * _tile_size.x
	var cy: float = (room.position.y + room.size.y / 2.0) * _tile_size.y

	var is_left: bool = leaf.x <= ship_grid_size.position.x
	var is_right: bool = (leaf.x + leaf.width) >= (ship_grid_size.position.x + ship_grid_size.size.x)
	var is_top: bool = leaf.y <= ship_grid_size.position.y
	var is_bottom: bool = (leaf.y + leaf.height) >= (ship_grid_size.position.y + ship_grid_size.size.y)

	if is_left: return Vector2(room.position.x * _tile_size.x, cy)
	elif is_right: return Vector2(room.end.x * _tile_size.x, cy)
	elif is_top: return Vector2(cx, room.position.y * _tile_size.y)
	elif is_bottom: return Vector2(cx, room.end.y * _tile_size.y)

	return Vector2(cx, cy)

func _paint_visual_tiles(traversable_rects: Array[Rect2i], leaves: Array[BSPLeaf]) -> void:
	var floor_cells: Dictionary = {}
	var wall_cell_set: Dictionary = {}
	
	for leaf in leaves:
		if not leaf.is_leaf():
			continue
			
		var theme: RoomTheme = _pick_weighted_theme()
		var assigned_type: int = theme.room_type if theme else RoomTheme.RoomType.GENERIC
		_room_type_map[leaf.room_rect] = assigned_type
		
		ShipData.rooms.append({ "rect": leaf.room_rect, "room_type": assigned_type })
		
		for x in range(leaf.room_rect.position.x, leaf.room_rect.end.x):
			for y in range(leaf.room_rect.position.y, leaf.room_rect.end.y):
				var cell := Vector2i(x, y)
				floor_cells[cell] = true
				
				var floor_coord: Vector2i = theme.get_random_floor_coord() if theme else default_floor_coord
				visual_tilemap.set_cell(cell, floor_tileset_source_id, floor_coord)
				
		if theme:
			_spawn_props_in_room(leaf.room_rect, theme)

	for rect in traversable_rects:
		for x in range(rect.position.x, rect.end.x):
			for y in range(rect.position.y, rect.end.y):
				var cell := Vector2i(x, y)
				if not floor_cells.has(cell):
					floor_cells[cell] = true
					visual_tilemap.set_cell(cell, floor_tileset_source_id, default_floor_coord)
					
	var neighbors := [
		Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT,
		Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)
	]
	
	for cell in floor_cells.keys():
		for offset in neighbors:
			var neighbor: Vector2i = cell + offset
			if not floor_cells.has(neighbor) and not wall_cell_set.has(neighbor):
				wall_cell_set[neighbor] = true
	
	for cell in wall_cell_set.keys():
		visual_tilemap.set_cell(cell, wall_tileset_source_id, default_wall_coord)

	ShipData.floor_cells = floor_cells
	ShipData.wall_cells = wall_cell_set

func _pick_weighted_theme() -> RoomTheme:
	if room_themes.is_empty(): return null
	if room_themes.size() == 1: return room_themes[0]

	var total: float = 0.0
	for t in room_themes: total += t.spawn_weight

	var roll: float = randf_range(0.0, total)
	var accum: float = 0.0
	for t in room_themes:
		accum += t.spawn_weight
		if roll <= accum: return t
	return room_themes[0]

func _spawn_props_in_room(room_rect_grid: Rect2i, theme: RoomTheme) -> void:
	if not theme or theme.max_props_per_room <= 0 or theme.prop_scenes.is_empty():
		return
		
	var prop_count: int = randi_range(theme.min_props_per_room, theme.max_props_per_room)
	if prop_count == 0: return
		
	var px_pos := Vector2(room_rect_grid.position.x * _tile_size.x, room_rect_grid.position.y * _tile_size.y)
	var px_size := Vector2(room_rect_grid.size.x * _tile_size.x, room_rect_grid.size.y * _tile_size.y)
	
	var safe_padding: int = 20
	var safe_width: int = int(px_size.x) - (safe_padding * 2)
	var safe_height: int = int(px_size.y) - (safe_padding * 2)
	
	if safe_width <= 0 or safe_height <= 0: return
	
	var placed_positions: Array[Vector2] = []
	var min_spacing_sq: float = theme.min_prop_spacing * theme.min_prop_spacing
	var max_attempts: int = 15
		
	for _i in range(prop_count):
		var prop_scene: PackedScene = theme.get_random_prop()
		if not prop_scene:
			continue
			
		var candidate_pos := Vector2.ZERO
		var found_valid: bool = false
		
		for _attempt in range(max_attempts):
			candidate_pos = _get_prop_position(theme.prop_placement, px_pos, px_size, safe_padding)
			
			var too_close: bool = false
			for placed in placed_positions:
				if candidate_pos.distance_squared_to(placed) < min_spacing_sq:
					too_close = true
					break
			
			if not too_close:
				found_valid = true
				break
		
		if not found_valid:
			continue
		
		var prop: Node2D = prop_scene.instantiate()
		prop.global_position = candidate_pos
		placed_positions.append(candidate_pos)
		call_deferred("add_child", prop)

func _get_prop_position(placement: RoomTheme.PropPlacement, px_pos: Vector2, px_size: Vector2, padding: int) -> Vector2:
	var inner_x_min: float = px_pos.x + padding
	var inner_x_max: float = px_pos.x + px_size.x - padding
	var inner_y_min: float = px_pos.y + padding
	var inner_y_max: float = px_pos.y + px_size.y - padding
	
	match placement:
		RoomTheme.PropPlacement.WALL_ADJACENT:
			var edge_band: float = px_size.x * 0.2
			var side: int = randi_range(0, 3)
			match side:
				0:
					return Vector2(randf_range(inner_x_min, inner_x_max), randf_range(inner_y_min, inner_y_min + edge_band))
				1:
					return Vector2(randf_range(inner_x_min, inner_x_max), randf_range(inner_y_max - edge_band, inner_y_max))
				2:
					return Vector2(randf_range(inner_x_min, inner_x_min + edge_band), randf_range(inner_y_min, inner_y_max))
				3:
					return Vector2(randf_range(inner_x_max - edge_band, inner_x_max), randf_range(inner_y_min, inner_y_max))
		
		RoomTheme.PropPlacement.CORNERS:
			var corner_zone: float = minf(px_size.x, px_size.y) * 0.3
			var corner: int = randi_range(0, 3)
			match corner:
				0: return Vector2(randf_range(inner_x_min, inner_x_min + corner_zone), randf_range(inner_y_min, inner_y_min + corner_zone))
				1: return Vector2(randf_range(inner_x_max - corner_zone, inner_x_max), randf_range(inner_y_min, inner_y_min + corner_zone))
				2: return Vector2(randf_range(inner_x_min, inner_x_min + corner_zone), randf_range(inner_y_max - corner_zone, inner_y_max))
				3: return Vector2(randf_range(inner_x_max - corner_zone, inner_x_max), randf_range(inner_y_max - corner_zone, inner_y_max))
		
		RoomTheme.PropPlacement.CENTER:
			var cx: float = px_pos.x + px_size.x * 0.5
			var cy: float = px_pos.y + px_size.y * 0.5
			var spread_x: float = px_size.x * 0.2
			var spread_y: float = px_size.y * 0.2
			return Vector2(randf_range(cx - spread_x, cx + spread_x), randf_range(cy - spread_y, cy + spread_y))
	
	return Vector2(
		randf_range(inner_x_min, inner_x_max),
		randf_range(inner_y_min, inner_y_max)
	)

func _spawn_npcs() -> void:
	if npc_scene == null: return
	var total_npcs: int = LevelConfig.DEFAULT_NPC_COUNT
	if level_config: total_npcs = level_config.npc_count
	if ShipData.rooms.is_empty() or total_npcs <= 0: return

	var available_types: Array = []
	for room_info in ShipData.rooms:
		var rt: int = room_info["room_type"]
		if rt not in available_types: available_types.append(rt)

	var room_pod_distances: Array[float] = []
	for i in range(ShipData.rooms.size()):
		var room_center: Vector2 = ShipData.get_room_center_world(i)
		var min_dist: float = INF
		for pod_pos in ShipData.escape_pod_positions:
			var d: float = room_center.distance_to(pod_pos)
			if d < min_dist:
				min_dist = d
		room_pod_distances.append(min_dist)

	for _i in range(total_npcs):
		var chosen_class: NPCClass = null
		var target_room_type: int = -1

		if not npc_classes.is_empty():
			chosen_class = npc_classes.pick_random()
			target_room_type = chosen_class.pick_spawn_room_type(available_types)

		var room_info: Dictionary = _pick_room_for_type_inverse(target_room_type, room_pod_distances)
		var room_rect: Rect2i = room_info["rect"]

		var px_pos := Vector2(room_rect.position.x * _tile_size.x, room_rect.position.y * _tile_size.y)
		var px_size := Vector2(room_rect.size.x * _tile_size.x, room_rect.size.y * _tile_size.y)

		var spawn_x: float = px_pos.x + randf() * px_size.x
		var spawn_y: float = px_pos.y + randf() * px_size.y

		var npc: Node2D = npc_scene.instantiate()
		npc.global_position = Vector2(spawn_x, spawn_y)
		if chosen_class and npc is HumanController:
			npc.npc_class = chosen_class
		call_deferred("add_child", npc)

		var class_id: StringName = &"Crewmember"
		if chosen_class: class_id = StringName(chosen_class.class_name_id)
		EventBus.npc_spawned.emit(class_id, Vector2(spawn_x, spawn_y), room_info["room_type"])

## Picks a room weighted by area and pod distance.
func _pick_room_for_type_inverse(room_type: int, room_pod_distances: Array[float]) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var candidate_indices: Array[int] = []

	if room_type >= 0:
		for i in range(ShipData.rooms.size()):
			if ShipData.rooms[i]["room_type"] == room_type:
				candidates.append(ShipData.rooms[i])
				candidate_indices.append(i)

	if candidates.is_empty():
		for i in range(ShipData.rooms.size()):
			candidates.append(ShipData.rooms[i])
			candidate_indices.append(i)

	if candidates.size() == 1:
		return candidates[0]

	var total_weight: float = 0.0
	var weights: Array[float] = []
	for idx in range(candidates.size()):
		var room_rect: Rect2i = candidates[idx]["rect"]
		var area: float = float(room_rect.size.x * room_rect.size.y)
		var pod_dist: float = room_pod_distances[candidate_indices[idx]]
		var pod_factor: float = clampf(pod_dist / 200.0, 0.5, 1.0)
		var w: float = area * pod_factor
		weights.append(w)
		total_weight += w

	if total_weight <= 0.0:
		return candidates.pick_random()

	var roll: float = randf_range(0.0, total_weight)
	var accum: float = 0.0
	for i in range(candidates.size()):
		accum += weights[i]
		if roll <= accum:
			return candidates[i]
	return candidates[-1]

func _register_door_rooms() -> void:
	for entry in _pending_door_registrations:
		var door: Node = entry["door"]
		var room_a_rect: Rect2i = entry["room_a_rect"]
		var room_b_rect: Rect2i = entry["room_b_rect"]

		var room_a_index: int = _find_room_index(room_a_rect)
		var room_b_index: int = _find_room_index(room_b_rect)

		if room_a_index >= 0 and room_b_index >= 0 and door is DoorSystem:
			door.room_a_index = room_a_index
			door.room_b_index = room_b_index
			ShipData.register_door_connection(door, room_a_index, room_b_index)

	_pending_door_registrations.clear()

func _find_room_index(room_rect: Rect2i) -> int:
	for i in range(ShipData.rooms.size()):
		if ShipData.rooms[i]["rect"] == room_rect:
			return i
	return -1

func _place_airlocks() -> void:
	if airlock_scene == null:
		push_warning("ShipGenerator: airlock_scene is not assigned.")
		return
		
	for i in range(ShipData.rooms.size()):
		if randf() < airlock_chance:
			ShipData.airlock_rooms.append(i)
			var airlock: Node2D = airlock_scene.instantiate()
			airlock.room_index = i
			airlock.name = "Airlock_%d" % i
			
			airlock.global_position = _get_safe_position_for_airlock(i)
			
			call_deferred("add_child", airlock)

## Finds a position away from props for airlock placement.
func _get_safe_position_for_airlock(room_index: int) -> Vector2:
	var room_rect: Rect2i = ShipData.rooms[room_index]["rect"]
	var px_pos := Vector2(room_rect.position.x * _tile_size.x, room_rect.position.y * _tile_size.y)
	var px_size := Vector2(room_rect.size.x * _tile_size.x, room_rect.size.y * _tile_size.y)
	
	var safe_padding: int = 24
	var max_attempts: int = 10
	var best_pos := px_pos + (px_size * 0.5)
	
	var child_positions: Array[Vector2] = []
	for child in get_children():
		if child is Node2D and not child is DoorSystem:
			child_positions.append(child.global_position)
			
	for attempt in range(max_attempts):
		var rx: float = px_pos.x + safe_padding + randf() * (px_size.x - safe_padding * 2)
		var ry: float = px_pos.y + safe_padding + randf() * (px_size.y - safe_padding * 2)
		var candidate_pos := Vector2(rx, ry)
		
		var is_safe := true
		for prop_pos in child_positions:
			if candidate_pos.distance_squared_to(prop_pos) < 1600.0:
				is_safe = false
				break
				
		if is_safe:
			return candidate_pos
			
	return best_pos

func _label_rooms() -> void:
	var room_type_names: PackedStringArray = RoomTheme.RoomType.keys()
	for i in range(ShipData.rooms.size()):
		var room_info: Dictionary = ShipData.rooms[i]
		var room_rect: Rect2i = room_info["rect"]
		var room_type: int = room_info["room_type"]

		var type_name: String = "Room"
		if room_type >= 0 and room_type < room_type_names.size():
			type_name = room_type_names[room_type].capitalize()

		var label := Label.new()
		label.text = type_name
		label.add_theme_font_size_override("font_size", 10)
		label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.5))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

		var world_pos: Vector2 = ShipData.get_room_center_world(i)
		label.position = world_pos - Vector2(40, 8)
		call_deferred("add_child", label)
