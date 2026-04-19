class_name NPCStateMachine
extends RefCounted

enum State {
	IDLE,
	MOVING_TO_SIGNAL,
	PANICKING,
	HIDING,
	FLEEING_TO_POD,
	DEAD,
}

var current_state: State = State.IDLE
var personality: NPCPersonality.Type = NPCPersonality.Type.NORMAL

var target_position: Vector2 = Vector2.ZERO

var hide_timer: float = 0.0
var hide_duration: float = 0.0

var panic_recovery_timer: float = 0.0
const PANIC_RECOVERY_CHECK: float = 1.5

var _panic_duration_timer: float = 0.0
const PANIC_DURATION_MAX: float = 8.0
var _panic_cooldown_timer: float = 0.0
const PANIC_COOLDOWN_DURATION: float = 3.0

var signal_target_room: int = -1

## Room to avoid, set by Wait signal.
var _avoided_room: int = -1
var _avoid_room_timer: float = 0.0
const AVOID_ROOM_DURATION: float = 15.0

var _run_boost_timer: float = 0.0
const RUN_BOOST_DURATION: float = 2.0
const RUN_BOOST_MULTIPLIER: float = 1.5

## Lingering timer after reaching signal target.
var _signal_linger_timer: float = 0.0
const SIGNAL_LINGER_DURATION: float = 1.5

var controller: Node = null

var _enemies_active: bool = false

var _flee_rethink_timer: float = 0.0
var _flee_rethink_interval: float = 0.0
var _flee_pause_timer: float = 0.0
var _flee_is_paused: bool = false
var _flee_detour_active: bool = false
var _flee_target_pod_pos: Vector2 = Vector2.ZERO

## Blacklisted pods that were full when the NPC last checked.
var _blacklisted_pods: Dictionary = {}
var _blacklist_recheck_timer: float = 0.0
const BLACKLIST_RECHECK_INTERVAL: float = 5.0

## Overshoot distance to enter the pod's area.
const POD_ENTRY_OVERSHOOT: float = 20.0

func _init(ctrl: Node, ptype: NPCPersonality.Type) -> void:
	controller = ctrl
	personality = ptype
	EventBus.enemies_have_spawned.connect(_on_enemies_have_spawned)
	_flee_rethink_interval = randf_range(2.0, 5.0)

func _on_enemies_have_spawned() -> void:
	_enemies_active = true
	if current_state == State.IDLE:
		_begin_flee_to_pod()

func transition_to(new_state: State) -> void:
	if current_state == State.DEAD:
		return
	current_state = new_state
	if is_instance_valid(controller):
		EventBus.npc_state_changed.emit(controller, _state_name(new_state))

func process(delta: float) -> void:
	if _panic_cooldown_timer > 0.0:
		_panic_cooldown_timer -= delta

	if _avoided_room >= 0:
		_avoid_room_timer += delta
		if _avoid_room_timer >= AVOID_ROOM_DURATION:
			_avoided_room = -1
			_avoid_room_timer = 0.0
		elif is_instance_valid(controller):
			var npc_room: int = ShipData.get_room_at_world_pos(controller.global_position)
			if npc_room == _avoided_room and current_state != State.DEAD:
				_flee_from_avoided_room()

	if _run_boost_timer > 0.0:
		_run_boost_timer -= delta
		if _run_boost_timer <= 0.0:
			_run_boost_timer = 0.0

	match current_state:
		State.IDLE:
			_process_idle(delta)
		State.MOVING_TO_SIGNAL:
			_process_moving_to_signal(delta)
		State.PANICKING:
			_process_panicking(delta)
		State.HIDING:
			_process_hiding(delta)
		State.FLEEING_TO_POD:
			_process_fleeing_to_pod(delta)

func _process_idle(delta: float) -> void:
	if _try_rush_pod_in_current_room():
		return

	if _try_rush_pod_in_nearby_rooms():
		return

	if _should_panic():
		_enter_panic()
		return
	if _enemies_active:
		_begin_flee_to_pod()

func _process_moving_to_signal(delta: float) -> void:
	if _try_rush_pod_in_current_room():
		return

	if _try_rush_pod_in_nearby_rooms():
		return

	if _should_panic():
		_enter_panic()
		return

	if is_instance_valid(controller):
		var ai_agent: AIAgentComponent = controller.ai_agent
		if ai_agent and ai_agent.nav_agent and ai_agent.nav_agent.is_navigation_finished():
			_signal_linger_timer += delta
			if _signal_linger_timer >= SIGNAL_LINGER_DURATION:
				_signal_linger_timer = 0.0
				if _enemies_active:
					_begin_flee_to_pod()
				else:
					transition_to(State.IDLE)

func _process_panicking(delta: float) -> void:
	_panic_duration_timer += delta
	if _panic_duration_timer >= PANIC_DURATION_MAX:
		_panic_duration_timer = 0.0
		_panic_cooldown_timer = PANIC_COOLDOWN_DURATION
		if _enemies_active:
			_begin_flee_to_pod()
		else:
			transition_to(State.IDLE)
		return

	if _try_rush_pod_in_current_room():
		return
	if _try_rush_pod_in_nearby_rooms():
		return

	match personality:
		NPCPersonality.Type.BRAVE:
			if _enemies_active:
				_begin_flee_to_pod()
			else:
				transition_to(State.IDLE)
		NPCPersonality.Type.COWARD:
			_coward_flee()
		NPCPersonality.Type.RECKLESS, NPCPersonality.Type.NORMAL:
			if _should_panic():
				panic_recovery_timer = 0.0
				if is_instance_valid(controller) and controller.ai_agent.nav_agent.is_navigation_finished():
					controller._wander_to_random_point()
			else:
				panic_recovery_timer += delta
				if panic_recovery_timer >= PANIC_RECOVERY_CHECK:
					panic_recovery_timer = 0.0
					if _enemies_active:
						_begin_flee_to_pod()
					else:
						transition_to(State.IDLE)

func _process_hiding(delta: float) -> void:
	if _try_rush_pod_in_current_room():
		return
	if _try_rush_pod_in_nearby_rooms():
		return

	if _should_panic():
		hide_timer = 0.0
		_enter_panic()
		return
	hide_timer += delta
	if hide_timer >= hide_duration:
		hide_timer = 0.0
		if _enemies_active:
			_begin_flee_to_pod()
		else:
			transition_to(State.IDLE)

func _process_fleeing_to_pod(delta: float) -> void:
	_blacklist_recheck_timer += delta
	if _blacklist_recheck_timer >= BLACKLIST_RECHECK_INTERVAL:
		_blacklist_recheck_timer = 0.0
		_blacklisted_pods.clear()

	if _try_rush_pod_in_current_room():
		return
	if _try_rush_pod_in_nearby_rooms():
		return

	if _should_panic():
		_enter_panic()
		return

	if _flee_is_paused:
		_flee_pause_timer -= delta
		if _flee_pause_timer <= 0.0:
			_flee_is_paused = false
			_pick_flee_target()
		return

	_flee_rethink_timer += delta
	if _flee_rethink_timer >= _flee_rethink_interval:
		_flee_rethink_timer = 0.0
		_flee_rethink_interval = randf_range(2.0, 5.0)
		_rethink_flee_behavior()

	if controller.ai_agent.nav_agent.is_navigation_finished():
		_pick_flee_target()

func _navigate_into_pod(pod: Node2D) -> void:
	var dir_to_pod : Vector2 = (pod.global_position - controller.global_position)
	if dir_to_pod.length_squared() > 1.0:
		dir_to_pod = dir_to_pod.normalized()
		controller.ai_agent.set_target(pod.global_position + dir_to_pod * POD_ENTRY_OVERSHOOT)
	else:
		controller.ai_agent.set_target(pod.global_position)

func _begin_flee_to_pod() -> void:
	_flee_rethink_timer = 0.0
	_flee_is_paused = false
	_flee_detour_active = false
	transition_to(State.FLEEING_TO_POD)
	_pick_flee_target()

func repath_flee() -> void:
	_pick_flee_target()

## Picks a flee destination, preferring less-crowded paths.
func _pick_flee_target() -> void:
	if not is_instance_valid(controller):
		return

	var npc_pos: Vector2 = controller.global_position
	var npc_room: int = ShipData.get_room_at_world_pos(npc_pos)

	var best_pod_pos: Vector2 = Vector2.ZERO
	var best_dist: float = INF
	var pods := controller.get_tree().get_nodes_in_group("escape_pods")
	for pod in pods:
		if not is_instance_valid(pod) or not pod is Node2D:
			continue
		if not pod.has_method("is_full"):
			continue
		if pod.is_full():
			_blacklisted_pods[pod.get_instance_id()] = true
			continue
		if _blacklisted_pods.has(pod.get_instance_id()):
			continue
		var d: float = npc_pos.distance_to(pod.global_position)
		if d < best_dist:
			best_dist = d
			best_pod_pos = pod.global_position

	if best_pod_pos == Vector2.ZERO:
		controller._wander_to_random_point()
		return

	_flee_target_pod_pos = best_pod_pos

	if npc_room >= 0 and ShipData.room_adjacency.has(npc_room):
		var neighbors: Array = ShipData.room_adjacency[npc_room]
		if not neighbors.is_empty():
			var best_neighbor: int = neighbors[0]
			var best_score: float = INF
			## Penalty per NPC to avoid crowded rooms.
			const CONGESTION_PENALTY_PER_NPC: float = 80.0
			const AVOID_ROOM_PENALTY: float = 500.0
			for n_idx in neighbors:
				var n_center: Vector2 = ShipData.get_room_center_world(n_idx)
				var dist_score: float = n_center.distance_to(best_pod_pos)
				var congestion: int = ShipData.npc_room_counts.get(n_idx, 0)
				var avoid_penalty: float = AVOID_ROOM_PENALTY if n_idx == _avoided_room else 0.0
				var score: float = dist_score + congestion * CONGESTION_PENALTY_PER_NPC + avoid_penalty
				if score < best_score:
					best_score = score
					best_neighbor = n_idx

			var target: Vector2 = ShipData.get_room_center_world(best_neighbor)
			var jitter := Vector2(randf_range(-30, 30), randf_range(-30, 30))
			controller.ai_agent.set_target(target + jitter)
			return

	var offset := Vector2(randf_range(-40, 40), randf_range(-40, 40))
	controller.ai_agent.set_target(best_pod_pos + offset)

func _rethink_flee_behavior() -> void:
	if not is_instance_valid(controller):
		return

	var roll: float = randf()

	if roll < 0.15:
		_flee_is_paused = true
		_flee_pause_timer = randf_range(0.5, 1.5)
	elif roll < 0.30:
		var npc_room: int = ShipData.get_room_at_world_pos(controller.global_position)
		if npc_room >= 0 and ShipData.room_adjacency.has(npc_room):
			var neighbors: Array = ShipData.room_adjacency[npc_room]
			if not neighbors.is_empty():
				var detour_room: int = neighbors.pick_random()
				var target: Vector2 = ShipData.get_room_center_world(detour_room)
				controller.ai_agent.set_target(target)
				_flee_detour_active = true
	elif roll < 0.40:
		var npc_room: int = ShipData.get_room_at_world_pos(controller.global_position)
		if npc_room >= 0:
			var room_rect: Rect2 = ShipData.get_room_world_rect(npc_room)
			var padding: float = 16.0
			var random_pos := Vector2(
				randf_range(room_rect.position.x + padding, room_rect.end.x - padding),
				randf_range(room_rect.position.y + padding, room_rect.end.y - padding)
			)
			controller.ai_agent.set_target(random_pos)
	else:
		_pick_flee_target()

## Tries to rush to an escape pod in or near the current room.
func _try_rush_pod_in_current_room() -> bool:
	if not _enemies_active or not is_instance_valid(controller):
		return false
		
	var pod_in_room: Node2D = null
	var npc_room: int = ShipData.get_room_at_world_pos(controller.global_position)
	if npc_room >= 0:
		pod_in_room = _get_active_pod_in_room(npc_room)
		
	if pod_in_room == null:
		pod_in_room = _get_closest_active_pod_within(150.0)
		
	if pod_in_room == null:
		return false
		
	_navigate_into_pod(pod_in_room)
	transition_to(State.FLEEING_TO_POD)
	return true

func _get_closest_active_pod_within(max_dist: float) -> Node2D:
	if not is_instance_valid(controller):
		return null
	var best_pod: Node2D = null
	var best_dist_sq: float = max_dist * max_dist
	var pods := controller.get_tree().get_nodes_in_group("escape_pods")
	for pod in pods:
		if not is_instance_valid(pod) or not pod is Node2D:
			continue
		if pod.has_method("is_full") and pod.is_full():
			continue
		if pod is EscapePod and not pod.is_active():
			continue
		var d_sq: float = controller.global_position.distance_squared_to(pod.global_position)
		if d_sq < best_dist_sq:
			best_dist_sq = d_sq
			best_pod = pod
	return best_pod

## Returns an active non-full pod in the given room.
func _get_active_pod_in_room(room_index: int) -> Node2D:
	if not is_instance_valid(controller):
		return null
	var room_rect: Rect2 = ShipData.get_room_world_rect(room_index)
	var pods := controller.get_tree().get_nodes_in_group("escape_pods")
	for pod in pods:
		if not is_instance_valid(pod) or not pod is Node2D:
			continue
		if pod.has_method("is_full") and pod.is_full():
			continue
		if pod is EscapePod and not pod.is_active():
			continue
		if room_rect.has_point(pod.global_position):
			return pod
	return null

## Finds the closest active pod in adjacent rooms.
func _get_active_pod_in_adjacent_rooms(room_index: int) -> Node2D:
	if not is_instance_valid(controller):
		return null
	if not ShipData.room_adjacency.has(room_index):
		return null
	var best_pod: Node2D = null
	var best_dist_sq: float = INF
	for neighbor_idx in ShipData.room_adjacency[room_index]:
		var pod := _get_active_pod_in_room(neighbor_idx)
		if pod != null:
			var d: float = controller.global_position.distance_squared_to(pod.global_position)
			if d < best_dist_sq:
				best_dist_sq = d
				best_pod = pod
	return best_pod

## Rushes to a pod in an adjacent room if available.
func _try_rush_pod_in_nearby_rooms() -> bool:
	if not _enemies_active or not is_instance_valid(controller):
		return false
	var npc_room: int = ShipData.get_room_at_world_pos(controller.global_position)
	if npc_room < 0:
		return false
	var pod_nearby := _get_active_pod_in_adjacent_rooms(npc_room)
	if pod_nearby == null:
		return false
	_navigate_into_pod(pod_nearby)
	transition_to(State.FLEEING_TO_POD)
	return true

## Checks if an enemy is reachable through same room or open doors.
func _should_panic() -> bool:
	if personality == NPCPersonality.Type.BRAVE:
		return false
	if _panic_cooldown_timer > 0.0:
		return false
	if not is_instance_valid(controller):
		return false

	var npc_room: int = ShipData.get_room_at_world_pos(controller.global_position)
	if npc_room < 0:
		return false

	const PANIC_RANGE_SQ: float = 300.0 * 300.0

	var enemies := controller.get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue
		if controller.global_position.distance_squared_to(enemy.global_position) > PANIC_RANGE_SQ:
			continue
		var enemy_room: int = ShipData.get_room_at_world_pos(enemy.global_position)
		if enemy_room == npc_room:
			return true
		if enemy_room >= 0 and _are_rooms_connected_with_open_doors(npc_room, enemy_room):
			return true
	return false

## True if rooms are adjacent with all doors open.
func _are_rooms_connected_with_open_doors(room_a: int, room_b: int) -> bool:
	if not ShipData.room_adjacency.has(room_a):
		return false
	if room_b not in ShipData.room_adjacency[room_a]:
		return false
	var doors_a: Array = ShipData.room_doors.get(room_a, [])
	var doors_b: Array = ShipData.room_doors.get(room_b, [])
	var found_door: bool = false
	for door in doors_a:
		if door in doors_b:
			found_door = true
			if is_instance_valid(door) and door is DoorSystem:
				if not door.is_open:
					return false
	return found_door

func _enter_panic() -> void:
	_panic_duration_timer = 0.0
	transition_to(State.PANICKING)

func _coward_flee() -> void:
	if not is_instance_valid(controller):
		return

	var current_room: int = ShipData.get_room_at_world_pos(controller.global_position)
	if current_room < 0:
		if _enemies_active:
			_begin_flee_to_pod()
		else:
			transition_to(State.IDLE)
		return

	var neighbors: Array = ShipData.room_adjacency.get(current_room, [])
	if neighbors.is_empty():
		_hide_in_room(current_room)
		return

	var safe_rooms: Array = []
	for n_idx in neighbors:
		var n_rect: Rect2 = ShipData.get_room_world_rect(n_idx)
		var has_alien: bool = false
		var enemies := controller.get_tree().get_nodes_in_group("enemies")
		for enemy in enemies:
			if is_instance_valid(enemy) and enemy is Node2D:
				if n_rect.has_point(enemy.global_position):
					has_alien = true
					break
		if not has_alien:
			safe_rooms.append(n_idx)

	var chosen_room: int
	if not safe_rooms.is_empty():
		chosen_room = safe_rooms.pick_random()
	else:
		chosen_room = neighbors.pick_random()

	_hide_in_room(chosen_room)

func _hide_in_room(room_index: int) -> void:
	var room_rect: Rect2 = ShipData.get_room_world_rect(room_index)
	if room_rect.size == Vector2.ZERO:
		if _enemies_active:
			_begin_flee_to_pod()
		else:
			transition_to(State.IDLE)
		return

	var padding: float = 16.0
	var corners: Array[Vector2] = [
		Vector2(room_rect.position.x + padding, room_rect.position.y + padding),
		Vector2(room_rect.end.x - padding, room_rect.position.y + padding),
		Vector2(room_rect.position.x + padding, room_rect.end.y - padding),
		Vector2(room_rect.end.x - padding, room_rect.end.y - padding),
	]
	target_position = corners.pick_random()

	if is_instance_valid(controller):
		controller.ai_agent.set_target(target_position)

	hide_duration = randf_range(3.0, 8.0)
	hide_timer = 0.0
	transition_to(State.HIDING)

func receive_signal(room_index: int, signal_type: StringName = &"move") -> void:
	if current_state == State.DEAD:
		return

	if current_state == State.PANICKING or current_state == State.HIDING:
		panic_recovery_timer = 0.0
		hide_timer = 0.0

	match signal_type:
		&"wait":
			_avoided_room = room_index
			_avoid_room_timer = 0.0
			if is_instance_valid(controller):
				var npc_room: int = ShipData.get_room_at_world_pos(controller.global_position)
				if npc_room == room_index:
					_flee_from_avoided_room()
			return
		&"run":
			_run_boost_timer = RUN_BOOST_DURATION
			return
		_:
			signal_target_room = room_index
			target_position = ShipData.get_room_center_world(room_index)
			_signal_linger_timer = 0.0
			if is_instance_valid(controller):
				controller.ai_agent.set_target(target_position)
			transition_to(State.MOVING_TO_SIGNAL)

func _flee_from_avoided_room() -> void:
	if not is_instance_valid(controller) or _avoided_room < 0:
		return
	var neighbors: Array = ShipData.room_adjacency.get(_avoided_room, [])
	if neighbors.is_empty():
		controller._wander_to_random_point()
		return
	var safe_rooms: Array = []
	for n_idx in neighbors:
		if n_idx == _avoided_room:
			continue
		var n_rect: Rect2 = ShipData.get_room_world_rect(n_idx)
		var has_enemy: bool = false
		var enemies := controller.get_tree().get_nodes_in_group("enemies")
		for enemy in enemies:
			if is_instance_valid(enemy) and enemy is Node2D and n_rect.has_point(enemy.global_position):
				has_enemy = true
				break
		if not has_enemy:
			safe_rooms.append(n_idx)
	var target_room: int
	if not safe_rooms.is_empty():
		target_room = safe_rooms.pick_random()
	else:
		target_room = neighbors.pick_random()
	var target_pos: Vector2 = ShipData.get_room_center_world(target_room)
	var jitter := Vector2(randf_range(-20, 20), randf_range(-20, 20))
	controller.ai_agent.set_target(target_pos + jitter)

func _state_name(state: State) -> StringName:
	match state:
		State.IDLE: return &"idle"
		State.MOVING_TO_SIGNAL: return &"moving_to_signal"
		State.PANICKING: return &"panicking"
		State.HIDING: return &"hiding"
		State.FLEEING_TO_POD: return &"fleeing_to_pod"
		State.DEAD: return &"dead"
	return &"unknown"
