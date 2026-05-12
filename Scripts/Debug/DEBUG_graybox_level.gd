class_name GreyboxLevel
extends Node2D

const INTERACTABLE_COLLISION_MASK: int = 2 

var _enemy_spawn_points: Array[Vector2] = []
var _npc_spawn_points: Array[Vector2] = []
var _pod_spawn_points: Array[Vector2] = []

var _comms_system: CommsSystem

var _spawn_timer: float = 0.0
var _spawn_started: bool = false
var _enemies_first_spawned: bool = false
var _initial_delay_elapsed: bool = false

const RIPPLE_VFX_SCENE = preload("res://Scenes/comms_ripple_vfx.tscn")
const ENEMY_SCENE = preload("res://Scenes/enemy.tscn")
const DOOR_SPARKS_SCENE = preload("res://Scenes/door_sparks.tscn")
const PIXEL_BLOOD_SCENE = preload("res://Scenes/pixel_blood.tscn")

const SFX_DOOR = preload("res://Assets/Audio/opendoor.wav")
const SFX_EXPLOSION = preload("res://Assets/Audio/explosion.wav")
const SFX_AIRLOCK = preload("res://Assets/Audio/airlock.wav")
const SFX_HIT = preload("res://Assets/Audio/Hit9.wav")
const SFX_LVL_ENDS = preload("res://Assets/Audio/lvlends.wav")

func _ready() -> void:
	var enemy_spawner := EnemySpawnManager.new()
	enemy_spawner.name = "EnemySpawnManager"
	add_child(enemy_spawner)
	
	_comms_system = CommsSystem.new()
	_comms_system.name = "CommsSystem"
	add_child(_comms_system)
	
	EventBus.ship_generated.connect(_on_ship_generated)
	EventBus.npc_spawned.connect(_on_npc_spawned)
	EventBus.enemy_spawn.connect(_on_enemy_spawn)
	EventBus.comms_signal_sent.connect(_on_comms_signal_sent)

	if not _is_in_subviewport():
		UIManager.add_assessment_screen(self)
		UIManager.add_main_menu(self)

	var bark_system := BarkSystem.new()
	bark_system.name = "BarkSystem"
	add_child(bark_system)

	EventBus.door_toggled.connect(_on_door_toggled)
	EventBus.door_destroyed.connect(_on_door_destroyed)
	EventBus.npc_killed_by_enemy.connect(_on_npc_killed_by_enemy)
	EventBus.room_depressurized.connect(_on_room_depressurized_sfx)
	EventBus.npc_died.connect(_on_npc_died_sfx)
	GameManager.level_complete.connect(_on_level_complete_sfx)

## Spawns new pods when all existing ones are full.
const POD_RESPAWN_INTERVAL: float = 15.0
var _pod_respawn_timer: float = 0.0
var next_enemy_respawn_timer: float = 0.0
var next_pod_respawn_timer: float = 0.0

const ESCAPE_POD_SCENE_RESPAWN = preload("res://Scenes/escape_pod.tscn")

func _process(delta: float) -> void:
	if not _spawn_started:
		return

	_spawn_timer += delta

	var spawn_delay: float = 4.0
	var max_alive: int = 2
	var respawn_interval: float = 20.0
	var ship_gen: Node = get_node_or_null("ShipGenerator")
	if ship_gen is ShipGenerator and ship_gen.level_config:
		spawn_delay = ship_gen.level_config.enemy_spawn_delay
		max_alive = ship_gen.level_config.get_max_enemies_alive()
		respawn_interval = ship_gen.level_config.get_respawn_interval()

	if not _initial_delay_elapsed:
		if _spawn_timer >= spawn_delay:
			_initial_delay_elapsed = true
			_spawn_timer = respawn_interval
		return

	if _spawn_timer >= respawn_interval:
		if GameManager.enemies_alive < max_alive:
			_spawn_timer = 0.0
			if not _enemies_first_spawned:
				_enemies_first_spawned = true
				EventBus.enemies_have_spawned.emit()
			EventBus.enemy_spawn_requested.emit(&"far", 1)

	if GameManager.enemies_alive < max_alive:
		next_enemy_respawn_timer = maxf(respawn_interval - _spawn_timer, 0.0)
	else:
		next_enemy_respawn_timer = 0.0

	if _enemies_first_spawned:
		_update_pod_respawning(delta)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("cycle_signal_forward"):
			_comms_system.cycle_signal_forward()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("cycle_signal_backward"):
			_comms_system.cycle_signal_backward()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			## Left click: interact with a clickable object under the cursor first.
			## Only send a comms signal when no interactable is found.
			if not _try_interact_at(event.position):
				_handle_comms_click(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			## Right click: check for a specialist NPC under the cursor.
			_try_open_radial_menu(event.position)

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				print("[DEBUG] Requesting 5 'far' enemies.")
				EventBus.enemy_spawn_requested.emit(&"far", 5)
			KEY_2:
				print("[DEBUG] Requesting 5 'mid' enemies.")
				EventBus.enemy_spawn_requested.emit(&"mid", 5)
			KEY_3:
				print("[DEBUG] Requesting 5 'near_pod' enemies.")
				EventBus.enemy_spawn_requested.emit(&"near_pod", 5)
			KEY_R:
				print("[DEBUG] Reloading Greybox...")
				get_viewport().set_input_as_handled()
				GameManager.reset()
				get_tree().reload_current_scene()

## Returns true and performs the interaction when a clickable object (door,
## airlock, etc.) is found under the cursor; returns false otherwise.
func _try_interact_at(screen_position: Vector2) -> bool:
	var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
	query.position = get_canvas_transform().affine_inverse() * screen_position
	query.collision_mask = INTERACTABLE_COLLISION_MASK
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var results: Array[Dictionary] = space_state.intersect_point(query)
	for result in results:
		var collider: Node = result.collider
		var interactable_parent: Node = collider.get_parent()
		if interactable_parent is DoorSystem:
			interactable_parent.toggle_door()
			return true
	return false

func _try_open_radial_menu(screen_position: Vector2) -> void:
	var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
	query.position = get_canvas_transform().affine_inverse() * screen_position
	query.collision_mask = INTERACTABLE_COLLISION_MASK
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var results: Array[Dictionary] = space_state.intersect_point(query)
	for result in results:
		var node: Node = result.collider
		while node != null:
			if node.is_in_group("specialists"):
				RadialMenu.open_for(node, screen_position)
				get_viewport().set_input_as_handled()
				return
			node = node.get_parent()
	## Fall back to door interaction when no specialist is under cursor.
	_try_interact_at(screen_position)

func _handle_comms_click(screen_position: Vector2) -> void:
	var world_pos: Vector2 = get_canvas_transform().affine_inverse() * screen_position
	var room_index: int = ShipData.get_room_at_world_pos(world_pos)
	if room_index >= 0:
		_comms_system.send_signal_to_room(room_index)

var _continuous_pod_spawn: bool = false

func _update_pod_respawning(delta: float) -> void:
	var living_npcs: int = GameManager.total_npcs_spawned - GameManager.npcs_escaped - GameManager.npcs_died
	if living_npcs <= 0:
		next_pod_respawn_timer = 0.0
		return

	if not _continuous_pod_spawn:
		var all_full: bool = _are_all_pods_full()
		if not all_full:
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
		if is_instance_valid(pod) and pod.has_method("is_full") and not pod.is_full():
			return false
	return true

func _spawn_new_escape_pod() -> void:
	if ShipData.rooms.is_empty():
		return

	var outer_rooms: Array[int] = []
	for i in ShipData.outer_room_indices:
		if i >= 0 and i < ShipData.rooms.size():
			outer_rooms.append(i)

	if outer_rooms.is_empty():
		outer_rooms.resize(ShipData.rooms.size())
		for i in range(ShipData.rooms.size()):
			outer_rooms[i] = i

	outer_rooms.shuffle()
	var room_index: int = outer_rooms[0]
	var rect: Rect2i = ShipData.rooms[room_index]["rect"]

	var grid := ShipData.grid_rect
	var tile_size := ShipData.tile_size
	var pod_pos := _get_border_pod_position(rect, grid, tile_size)

	var pod: Node2D = ESCAPE_POD_SCENE_RESPAWN.instantiate()
	pod.global_position = pod_pos
	add_child(pod)

	if pod is EscapePod:
		pod._on_enemies_have_spawned()

	ShipData.escape_pod_positions.append(pod_pos)

## Returns a border position for a pod inside an outer room.
func _get_border_pod_position(rect: Rect2i, grid: Rect2i, tile_size: Vector2i) -> Vector2:
	var cx: float = (rect.position.x + rect.size.x / 2.0) * tile_size.x
	var cy: float = (rect.position.y + rect.size.y / 2.0) * tile_size.y
	var edge_pad: int = 2
	if rect.position.x <= grid.position.x + edge_pad:
		return Vector2(rect.position.x * tile_size.x, cy)
	elif rect.end.x >= grid.end.x - edge_pad:
		return Vector2(rect.end.x * tile_size.x, cy)
	elif rect.position.y <= grid.position.y + edge_pad:
		return Vector2(cx, rect.position.y * tile_size.y)
	elif rect.end.y >= grid.end.y - edge_pad:
		return Vector2(cx, rect.end.y * tile_size.y)
	return Vector2(cx, cy)

func get_total_pod_slots() -> int:
	var total: int = 0
	var pods := get_tree().get_nodes_in_group("escape_pods")
	for pod in pods:
		if is_instance_valid(pod) and pod is EscapePod:
			total += pod.capacity
	return total

func get_used_pod_slots() -> int:
	var total: int = 0
	var pods := get_tree().get_nodes_in_group("escape_pods")
	for pod in pods:
		if is_instance_valid(pod) and pod is EscapePod:
			total += pod._escaped_count
	return total

func get_available_pod_slots() -> int:
	return get_total_pod_slots() - get_used_pod_slots()

func _on_ship_generated(escape_pod_positions: Array[Vector2]) -> void:
	_pod_spawn_points = escape_pod_positions
	_spawn_started = true
	_spawn_timer = 0.0
	queue_redraw()

func _on_npc_spawned(npc_class_id: StringName, global_pos: Vector2, _room_type: int) -> void:
	_npc_spawn_points.append(global_pos)
	queue_redraw()

func _on_enemy_spawn(global_pos: Vector2) -> void:
	_enemy_spawn_points.append(global_pos)
	var enemy: Node2D = ENEMY_SCENE.instantiate()
	enemy.global_position = global_pos
	add_child(enemy)
	queue_redraw()

func _on_comms_signal_sent(room_index: int, _affected_rooms: Array) -> void:
	if room_index < 0:
		return
		
	var target_pos: Vector2 = ShipData.get_room_center_world(room_index)
	
	var signal_color: Color = Color(1.0, 0.2, 0.2, 1.0)
	if _comms_system:
		signal_color = CommsSystem.SIGNAL_COLORS.get(_comms_system.current_signal_type, signal_color)
	
	var vfx: ColorRect = RIPPLE_VFX_SCENE.instantiate()
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
	var timer := get_tree().create_timer(sparks.lifetime + 0.5, false)
	timer.timeout.connect(sparks.queue_free)
	AudioManager.play_sfx(SFX_EXPLOSION, AudioManager.BUS_VFX1)

func _on_npc_killed_by_enemy(_npc: Node, global_pos: Vector2) -> void:
	var blood: GPUParticles2D = PIXEL_BLOOD_SCENE.instantiate()
	blood.global_position = global_pos
	add_child(blood)
	blood.emitting = true
	var timer := get_tree().create_timer(blood.lifetime + 1.0, false)
	timer.timeout.connect(blood.queue_free)

func _on_room_depressurized_sfx(_room_index: int) -> void:
	AudioManager.play_sfx(SFX_AIRLOCK, AudioManager.BUS_VFX2)

func _on_npc_died_sfx(_npc: Node) -> void:
	AudioManager.play_sfx(SFX_HIT, AudioManager.BUS_VFX1)

func _on_level_complete_sfx(_escaped: int, _died: int) -> void:
	AudioManager.play_sfx(SFX_LVL_ENDS, AudioManager.BUS_VFX3)

func _is_in_subviewport() -> bool:
	return get_viewport() != get_tree().root

func _draw() -> void:
	for pos in _pod_spawn_points:
		draw_circle(pos, 16.0, Color.DEEP_SKY_BLUE)
		draw_string(ThemeDB.fallback_font, pos + Vector2(-12, 4), "POD", HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color.WHITE)
		
	for pos in _npc_spawn_points:
		draw_circle(pos, 6.0, Color.LIME_GREEN)
		
	for pos in _enemy_spawn_points:
		draw_rect(Rect2(pos - Vector2(6, 6), Vector2(12, 12)), Color.CRIMSON)

	for room_idx in ShipData.airlock_rooms:
		var room_center: Vector2 = ShipData.get_room_center_world(room_idx)
		draw_circle(room_center, 10.0, Color(1.0, 0.5, 0.0, 0.6))
		draw_string(ThemeDB.fallback_font, room_center + Vector2(-16, 4), "AIR", HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color.WHITE)
