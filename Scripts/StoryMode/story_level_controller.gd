class_name StoryLevelController
extends Node2D

## Master controller for story-mode (tilemap) levels.
##
## Replaces ShipGenerator for manually-designed ships.
## Reads RoomMarker children to define rooms, reads the TileMapLayer to
## extract floor/wall data, bakes navigation from room rects, spawns NPCs,
## and emits ship_generated when ready — so the rest of the game systems
## (AI, pathfinder, loading screen) work identically to arcade mode.
##
## === SETUP GUIDE ===
## 1. Duplicate story_level_base.tscn for each new level.
## 2. Paint your ship on the TileMapLayer.
## 3. Add RoomMarker children (one per room) and set room_rect_tiles to match
##    your tile layout. Mark outer rooms with is_outer_room = true.
## 4. Place door.tscn instances between rooms (auto-detected by proximity).
## 5. Place escape_pod.tscn instances where you want pods.
## 6. Optionally, place NpcSpawnPoint children for precise NPC placement.
## 7. Tweak gameplay export vars below to tune difficulty feel per-level.

@export_category("References")
## NavigationRegion2D to bake the navmesh into.
@export var nav_region: NavigationRegion2D
## The TileMapLayer holding the visual ship tiles.
@export var visual_tilemap: TileMapLayer

@export_category("Tilemap Tile Source IDs")
## Source ID of floor tiles in the TileSet. Used to populate ShipData.floor_cells.
@export var floor_tile_source_id: int = 1
## Source ID of wall tiles. Set to -1 to auto-derive walls from floor neighbours.
@export var wall_tile_source_id: int = 0

@export_category("Gameplay Variables")
## Enemy movement speed in pixels/sec.
@export var enemy_chase_speed: float = 70.0
## Seconds before the first enemy spawns after the level starts.
@export var enemy_spawn_delay: float = 4.0
## Seconds between enemy respawn checks.
@export var enemy_respawn_interval: float = 20.0
## Maximum number of enemies alive simultaneously.
@export var max_enemies_alive: int = 2
## Multiplier applied to all NPC movement speeds. 1.0 = default.
@export_range(0.1, 3.0, 0.1) var npc_speed_modifier: float = 1.0
## Seconds between pacing escalations (speed increases over time).
@export var escalation_interval: float = 30.0
## Speed multiplier increase applied each escalation step.
@export var escalation_step: float = 0.12
## Capacity override for all escape pods placed in this level. 0 = use pod's own value.
@export var escape_pod_capacity_override: int = 0

@export_category("NPC Configuration")
## The human NPC packed scene to instantiate.
@export var npc_scene: PackedScene
## NPC classes to randomly assign. Used when no NpcSpawnPoint children exist.
@export var npc_classes: Array[NPCClass] = []
## Number of NPCs to spawn when using auto-spawn (no NpcSpawnPoint children).
@export var npc_count: int = 10

## ── internal state ──────────────────────────────────────────────────────────
var _spawn_timer: float = 0.0
var _spawn_started: bool = false
var _enemies_first_spawned: bool = false
var _initial_delay_elapsed: bool = false
var _pod_respawn_timer: float = 0.0
var _continuous_pod_spawn: bool = false
var _tile_size: Vector2i = Vector2i(16, 16)
var _comms_system: CommsSystem

## Exposed for the HUD timer display (matches GreyboxLevel interface).
var next_enemy_respawn_timer: float = 0.0
var next_pod_respawn_timer: float = 0.0

const POD_RESPAWN_INTERVAL: float = 15.0
const INTERACTABLE_COLLISION_MASK: int = 2

const RIPPLE_VFX_SCENE = preload("res://Scenes/comms_ripple_vfx.tscn")
const ENEMY_SCENE = preload("res://Scenes/enemy.tscn")
const DOOR_SPARKS_SCENE = preload("res://Scenes/door_sparks.tscn")
const PIXEL_BLOOD_SCENE = preload("res://Scenes/pixel_blood.tscn")
const ESCAPE_POD_SCENE = preload("res://Scenes/escape_pod.tscn")

const SFX_DOOR = preload("res://Assets/Audio/opendoor.wav")
const SFX_EXPLOSION = preload("res://Assets/Audio/explosion.wav")
const SFX_AIRLOCK = preload("res://Assets/Audio/airlock.wav")
const SFX_HIT = preload("res://Assets/Audio/Hit9.wav")
const SFX_LVL_ENDS = preload("res://Assets/Audio/lvlends.wav")

## ── lifecycle ───────────────────────────────────────────────────────────────

func _ready() -> void:
	GameManager.reset()
	GameManager.npc_global_speed_multiplier = npc_speed_modifier
	GameManager.ESCALATION_INTERVAL = escalation_interval
	GameManager.ESCALATION_STEP = escalation_step

	var gameplay_music := load("res://Assets/Audio/LD59_Gameplay.wav") as AudioStream
	if gameplay_music:
		AudioManager.play_music(gameplay_music)

	## Add runtime systems.
	var enemy_spawner := EnemySpawnManager.new()
	enemy_spawner.name = "EnemySpawnManager"
	add_child(enemy_spawner)

	_comms_system = CommsSystem.new()
	_comms_system.name = "CommsSystem"
	add_child(_comms_system)

	var bark_system := BarkSystem.new()
	bark_system.name = "BarkSystem"
	add_child(bark_system)

	## Apply difficulty scaling on top of the exported gameplay values.
	var config = UIManager.get_current_level_config()
	if config:
		_apply_difficulty_scaling(config)

	## Connect game-event signals.
	EventBus.ship_generated.connect(_on_ship_generated)
	EventBus.enemy_spawn.connect(_on_enemy_spawn)
	EventBus.comms_signal_sent.connect(_on_comms_signal_sent)
	EventBus.door_toggled.connect(_on_door_toggled)
	EventBus.door_destroyed.connect(_on_door_destroyed)
	EventBus.npc_killed_by_enemy.connect(_on_npc_killed_by_enemy)
	EventBus.room_depressurized.connect(_on_room_depressurized_sfx)
	EventBus.npc_died.connect(_on_npc_died_sfx)
	GameManager.level_complete.connect(_on_level_complete_sfx)

	## Defer setup so all child nodes (doors, pods, room markers) are ready.
	call_deferred("_setup_level")

func _apply_difficulty_scaling(config: LevelConfig) -> void:
	var d: float = config.difficulty
	if config.max_enemies_alive > 0:
		max_enemies_alive = config.max_enemies_alive
	enemy_respawn_interval = config.enemy_respawn_interval * lerpf(1.0, 0.6, d)
	enemy_spawn_delay = config.enemy_spawn_delay

## ── level setup (deferred) ──────────────────────────────────────────────────

func _setup_level() -> void:
	ShipData.clear()

	if visual_tilemap and visual_tilemap.tile_set:
		_tile_size = visual_tilemap.tile_set.tile_size
	ShipData.tile_size = _tile_size

	EventBus.generation_progress.emit("LOADING SHIP LAYOUT...", 0.10)
	_register_rooms()

	EventBus.generation_progress.emit("BAKING NAVIGATION...", 0.35)
	_bake_navigation()

	EventBus.generation_progress.emit("SCANNING FLOOR CELLS...", 0.55)
	_scan_floor_cells()

	EventBus.generation_progress.emit("REGISTERING DOORS...", 0.65)
	_register_doors()

	EventBus.generation_progress.emit("REGISTERING ESCAPE PODS...", 0.75)
	_register_escape_pods()

	ShipData.build_cell_to_room_cache()

	EventBus.generation_progress.emit("SPAWNING CREW...", 0.85)
	_spawn_npcs()

	EventBus.generation_progress.emit("WARMING UP PATHFINDING...", 0.95)
	EventBus.ship_generated.emit.call_deferred(ShipData.escape_pod_positions)

func _register_rooms() -> void:
	var markers: Array[RoomMarker] = _collect_room_markers()

	if markers.is_empty():
		## Fallback: one big room covering the entire tilemap.
		if visual_tilemap:
			var used: Rect2i = visual_tilemap.get_used_rect()
			if used.size.x > 0 and used.size.y > 0:
				ShipData.rooms.append({ "rect": used, "room_type": RoomTheme.RoomType.GENERIC })
				ShipData.grid_rect = used
				ShipData.outer_room_indices.append(0)
		return

	var bounding := Rect2i()
	for i in range(markers.size()):
		var m: RoomMarker = markers[i]
		ShipData.rooms.append({ "rect": m.room_rect_tiles, "room_type": m.room_type })
		if m.is_outer_room:
			ShipData.outer_room_indices.append(i)
		bounding = m.room_rect_tiles if i == 0 else bounding.merge(m.room_rect_tiles)

	ShipData.grid_rect = bounding

func _collect_room_markers() -> Array[RoomMarker]:
	var result: Array[RoomMarker] = []
	for child in get_children():
		if child is RoomMarker:
			result.append(child)
		for sub in child.get_children():
			if sub is RoomMarker:
				result.append(sub)
	return result

func _bake_navigation() -> void:
	if nav_region == null:
		push_warning("StoryLevelController: nav_region not assigned — navigation will not work.")
		return

	var nav_poly := NavigationPolygon.new()
	nav_poly.agent_radius = float(_tile_size.x) * 0.5

	var geo := NavigationMeshSourceGeometryData2D.new()
	for room_info in ShipData.rooms:
		var rect: Rect2i = room_info["rect"]
		var px_pos := Vector2(rect.position.x * _tile_size.x, rect.position.y * _tile_size.y)
		var px_size := Vector2(rect.size.x * _tile_size.x, rect.size.y * _tile_size.y)
		var outline := PackedVector2Array([
			px_pos,
			Vector2(px_pos.x + px_size.x, px_pos.y),
			px_pos + px_size,
			Vector2(px_pos.x, px_pos.y + px_size.y),
		])
		geo.add_traversable_outline(outline)

	NavigationServer2D.bake_from_source_geometry_data(nav_poly, geo)
	nav_region.navigation_polygon = nav_poly

func _scan_floor_cells() -> void:
	if visual_tilemap == null:
		return

	var floor_cells: Dictionary = {}
	var wall_cells: Dictionary = {}
	var used: Rect2i = visual_tilemap.get_used_rect()

	for x in range(used.position.x, used.end.x):
		for y in range(used.position.y, used.end.y):
			var cell := Vector2i(x, y)
			var src: int = visual_tilemap.get_cell_source_id(cell)
			if src == floor_tile_source_id:
				floor_cells[cell] = true
			elif wall_tile_source_id >= 0 and src == wall_tile_source_id:
				wall_cells[cell] = true

	## Auto-derive wall cells from floor neighbours if none were painted.
	if wall_cells.is_empty():
		var dirs := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT,
				Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]
		for cell in floor_cells.keys():
			for d in dirs:
				var nb: Vector2i = cell + d
				if not floor_cells.has(nb):
					wall_cells[nb] = true

	ShipData.floor_cells = floor_cells
	ShipData.wall_cells = wall_cells

func _register_doors() -> void:
	_walk_children_for_doors(self)

func _walk_children_for_doors(parent: Node) -> void:
	for child in parent.get_children():
		if child is DoorSystem:
			_register_door(child)
		else:
			_walk_children_for_doors(child)

func _register_door(door: DoorSystem) -> void:
	var door_tile := Vector2i(
		int(door.global_position.x / _tile_size.x),
		int(door.global_position.y / _tile_size.y)
	)
	var touching: Array[int] = []
	for i in range(ShipData.rooms.size()):
		var rect: Rect2i = ShipData.rooms[i]["rect"]
		## Expand the rect by 2 tiles on each side (4 total) to catch doors placed
		## exactly on room borders, which would otherwise fall just outside both rects.
		var expanded_rect = Rect2i(rect.position - Vector2i(2, 2), rect.size + Vector2i(4, 4))
		if expanded_rect.has_point(door_tile):
			touching.append(i)
			if touching.size() >= 2:
				break

	if touching.size() >= 2:
		door.room_a_index = touching[0]
		door.room_b_index = touching[1]
		ShipData.register_door_connection(door, touching[0], touching[1])
	elif touching.size() == 1:
		## Single-room door (outer wall): connect to itself so it still works.
		door.room_a_index = touching[0]
		door.room_b_index = touching[0]

func _register_escape_pods() -> void:
	_walk_children_for_pods(self)

func _walk_children_for_pods(parent: Node) -> void:
	for child in parent.get_children():
		if child is EscapePod:
			_register_pod(child)
		else:
			_walk_children_for_pods(child)

func _register_pod(pod: EscapePod) -> void:
	if escape_pod_capacity_override > 0:
		pod.capacity = escape_pod_capacity_override
	ShipData.escape_pod_positions.append(pod.global_position)
	var room_idx: int = ShipData.get_room_at_world_pos(pod.global_position)
	if room_idx >= 0 and room_idx not in ShipData.outer_room_indices:
		ShipData.outer_room_indices.append(room_idx)

func _spawn_npcs() -> void:
	if npc_scene == null or ShipData.rooms.is_empty():
		return

	var spawn_points: Array[NpcSpawnPoint] = _collect_spawn_points()
	if not spawn_points.is_empty():
		_spawn_from_points(spawn_points)
	else:
		_spawn_in_rooms()

func _collect_spawn_points() -> Array[NpcSpawnPoint]:
	var result: Array[NpcSpawnPoint] = []
	_walk_for_spawn_points(self, result)
	return result

func _walk_for_spawn_points(parent: Node, out: Array[NpcSpawnPoint]) -> void:
	for child in parent.get_children():
		if child is NpcSpawnPoint:
			out.append(child)
		else:
			_walk_for_spawn_points(child, out)

func _spawn_from_points(points: Array[NpcSpawnPoint]) -> void:
	for sp in points:
		var npc: Node2D = npc_scene.instantiate()
		npc.global_position = sp.global_position
		if npc is HumanController:
			if sp.npc_class:
				npc.npc_class = sp.npc_class
			elif not npc_classes.is_empty():
				npc.npc_class = npc_classes.pick_random()
		add_child(npc)
		var class_id: StringName = _get_npc_class_id(npc)
		var raw_room_idx: int = ShipData.get_room_at_world_pos(npc.global_position)
		var room_idx: int = maxi(raw_room_idx, 0)
		var room_type: int = ShipData.rooms[room_idx].get("room_type", 0)
		EventBus.npc_spawned.emit(class_id, npc.global_position, room_type)

func _spawn_in_rooms() -> void:
	for _i in range(npc_count):
		var room_info: Dictionary = ShipData.rooms.pick_random()
		var rect: Rect2i = room_info["rect"]
		var px := Vector2(rect.position.x * _tile_size.x, rect.position.y * _tile_size.y)
		var sz := Vector2(rect.size.x * _tile_size.x, rect.size.y * _tile_size.y)
		var spawn_pos := Vector2(px.x + randf() * sz.x, px.y + randf() * sz.y)

		var npc: Node2D = npc_scene.instantiate()
		npc.global_position = spawn_pos
		if npc is HumanController and not npc_classes.is_empty():
			npc.npc_class = npc_classes.pick_random()
		add_child(npc)

		var class_id: StringName = _get_npc_class_id(npc)
		EventBus.npc_spawned.emit(class_id, spawn_pos, room_info.get("room_type", 0))

func _get_npc_class_id(npc: Node2D) -> StringName:
	if npc is HumanController and npc.npc_class:
		return npc.npc_class.class_name_id
	return &"Crewmember"

## ── per-frame logic ─────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not _spawn_started:
		return

	_spawn_timer += delta

	if not _initial_delay_elapsed:
		if _spawn_timer >= enemy_spawn_delay:
			_initial_delay_elapsed = true
			_spawn_timer = enemy_respawn_interval
		return

	if _spawn_timer >= enemy_respawn_interval:
		if GameManager.enemies_alive < max_enemies_alive:
			_spawn_timer = 0.0
			if not _enemies_first_spawned:
				_enemies_first_spawned = true
				EventBus.enemies_have_spawned.emit()
			EventBus.enemy_spawn_requested.emit(&"far", 1)

	if GameManager.enemies_alive < max_enemies_alive:
		next_enemy_respawn_timer = maxf(enemy_respawn_interval - _spawn_timer, 0.0)
	else:
		next_enemy_respawn_timer = 0.0

	if _enemies_first_spawned:
		_update_pod_respawning(delta)

func _update_pod_respawning(delta: float) -> void:
	var living: int = GameManager.total_npcs_spawned - GameManager.npcs_escaped - GameManager.npcs_died
	if living <= 0:
		next_pod_respawn_timer = 0.0
		return

	if not _continuous_pod_spawn:
		if not _are_all_pods_full():
			_pod_respawn_timer = 0.0
			next_pod_respawn_timer = POD_RESPAWN_INTERVAL
			return
		_continuous_pod_spawn = true

	_pod_respawn_timer += delta
	next_pod_respawn_timer = maxf(POD_RESPAWN_INTERVAL - _pod_respawn_timer, 0.0)
	if _pod_respawn_timer >= POD_RESPAWN_INTERVAL:
		_pod_respawn_timer = 0.0
		_spawn_new_escape_pod()

func _are_all_pods_full() -> bool:
	var pods := get_tree().get_nodes_in_group("escape_pods")
	if pods.is_empty():
		return true
	for pod in pods:
		if is_instance_valid(pod) and pod is EscapePod and not pod.is_full():
			return false
	return true

func _spawn_new_escape_pod() -> void:
	if ShipData.rooms.is_empty():
		return
	var candidates: Array = ShipData.outer_room_indices.duplicate()
	if candidates.is_empty():
		for i in range(ShipData.rooms.size()):
			candidates.append(i)
	candidates.shuffle()
	var idx: int = candidates[0]
	var rect: Rect2i = ShipData.rooms[idx]["rect"]
	var pos := Vector2(
		(rect.position.x + rect.size.x * 0.5) * _tile_size.x,
		(rect.position.y + rect.size.y * 0.5) * _tile_size.y
	)
	var pod: Node2D = ESCAPE_POD_SCENE.instantiate()
	pod.global_position = pos
	add_child(pod)
	if pod is EscapePod:
		pod._on_enemies_have_spawned()
	ShipData.escape_pod_positions.append(pos)

## ── input ───────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E:
			_comms_system.toggle_signal_mode()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("cycle_signal"):
			_comms_system.cycle_signal_type()
			get_viewport().set_input_as_handled()

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if _comms_system and _comms_system.is_signal_mode:
				_handle_comms_click(event.position)
			else:
				_query_interactables_at_mouse(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if _comms_system and _comms_system.is_signal_mode:
				_comms_system.deactivate_signal_mode()

func _handle_comms_click(screen_pos: Vector2) -> void:
	var world_pos: Vector2 = get_canvas_transform().affine_inverse() * screen_pos
	var room_index: int = ShipData.get_room_at_world_pos(world_pos)
	if room_index >= 0:
		_comms_system.send_signal_to_room(room_index)

func _query_interactables_at_mouse(screen_pos: Vector2) -> void:
	var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.position = get_canvas_transform().affine_inverse() * screen_pos
	query.collision_mask = INTERACTABLE_COLLISION_MASK
	query.collide_with_areas = true
	query.collide_with_bodies = true
	for result in space_state.intersect_point(query):
		var parent: Node = result["collider"].get_parent()
		if parent is DoorSystem:
			parent.toggle_door()
			break

## ── signal callbacks ────────────────────────────────────────────────────────

func _on_ship_generated(_pod_positions: Array) -> void:
	_spawn_started = true
	_spawn_timer = 0.0

func _on_enemy_spawn(global_pos: Vector2) -> void:
	var enemy: Node2D = ENEMY_SCENE.instantiate()
	enemy.global_position = global_pos
	if enemy is EnemyController:
		enemy.chase_speed = enemy_chase_speed
	add_child(enemy)

func _on_comms_signal_sent(room_index: int, _affected_rooms: Array) -> void:
	if room_index < 0:
		return
	var target_pos: Vector2 = ShipData.get_room_center_world(room_index)
	var signal_color := Color(1.0, 0.2, 0.2, 1.0)
	if _comms_system:
		signal_color = CommsSystem.SIGNAL_COLORS.get(_comms_system.current_signal_type, signal_color)
	var vfx : CommsRippleVFX = RIPPLE_VFX_SCENE.instantiate()
	vfx.global_position = target_pos
	if vfx is CommsRippleVFX:
		vfx.ripple_color = signal_color
	add_child(vfx)

func _on_door_toggled(_door_id: StringName, _is_open: bool) -> void:
	EventBus.nav_graph_changed.emit()
	AudioManager.play_sfx(SFX_DOOR, AudioManager.BUS_VFX2)

func _on_door_destroyed(_door_id: StringName, global_pos: Vector2) -> void:
	var sparks: GPUParticles2D = DOOR_SPARKS_SCENE.instantiate()
	sparks.global_position = global_pos
	add_child(sparks)
	sparks.emitting = true
	get_tree().create_timer(sparks.lifetime + 0.5, false).timeout.connect(sparks.queue_free)
	AudioManager.play_sfx(SFX_EXPLOSION, AudioManager.BUS_VFX1)

func _on_npc_killed_by_enemy(_npc: Node, global_pos: Vector2) -> void:
	var blood: GPUParticles2D = PIXEL_BLOOD_SCENE.instantiate()
	blood.global_position = global_pos
	add_child(blood)
	blood.emitting = true
	get_tree().create_timer(blood.lifetime + 1.0, false).timeout.connect(blood.queue_free)

func _on_room_depressurized_sfx(_room_index: int) -> void:
	AudioManager.play_sfx(SFX_AIRLOCK, AudioManager.BUS_VFX2)

func _on_npc_died_sfx(_npc: Node) -> void:
	AudioManager.play_sfx(SFX_HIT, AudioManager.BUS_VFX1)

func _on_level_complete_sfx(_escaped: int, _died: int) -> void:
	AudioManager.play_sfx(SFX_LVL_ENDS, AudioManager.BUS_VFX3)

## ── HUD helpers (mirror GreyboxLevel interface) ─────────────────────────────

func get_total_pod_slots() -> int:
	var total: int = 0
	for pod in get_tree().get_nodes_in_group("escape_pods"):
		if is_instance_valid(pod) and pod is EscapePod:
			total += pod.capacity
	return total

func get_used_pod_slots() -> int:
	var total: int = 0
	for pod in get_tree().get_nodes_in_group("escape_pods"):
		if is_instance_valid(pod) and pod is EscapePod:
			total += pod._escaped_count
	return total
