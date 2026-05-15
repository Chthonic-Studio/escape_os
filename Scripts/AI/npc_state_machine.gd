class_name NPCStateMachine
extends Node

## Node-based finite state machine for NPC civilians.
##
## Each concrete behaviour lives in a child NPCStateBase node.  This node
## owns the shared helpers, volatile state accessed by multiple states, and
## the public API expected by HumanController and external callers.
##
## External API (unchanged from the old RefCounted version):
##   state_machine.current_state   : NPCStateMachine.State enum
##   state_machine.transition_to() : immediate state change
##   state_machine.receive_signal(): player comms input
##   state_machine.repath_flee()   : nudge flee state to re-pick target
##   state_machine._run_boost_timer: read by HumanController speed logic
##   NPCStateMachine.RUN_BOOST_MULTIPLIER: const read by HumanController

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

## Reference to the owning HumanController \u2014 set just before add_child().
var controller: HumanController = null

## \u2500\u2500 Shared volatile state (read by multiple state nodes) \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

var signal_target_room: int = -1
var _enemies_active: bool = false

var _avoided_room: int = -1
var _avoid_room_timer: float = 0.0
const AVOID_ROOM_DURATION: float = 15.0

var _run_boost_timer: float = 0.0
const RUN_BOOST_DURATION: float = 2.0
const RUN_BOOST_MULTIPLIER: float = 1.5

var _panic_cooldown_timer: float = 0.0
const PANIC_COOLDOWN_DURATION: float = 8.0

## PANIC_RECOVERY_CHECK is defined here so NPCPanicState can reference it.
const PANIC_RECOVERY_CHECK: float = 1.5

const POD_ENTRY_OVERSHOOT: float = 20.0

## \u2500\u2500 State-node bookkeeping \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

var _active_state: NPCStateBase = null

## State enum value (int) \u2192 NPCStateBase node.
var _state_map: Dictionary = {}

## \u2500\u2500 Lifecycle \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

func _ready() -> void:
	## Disable built-in process so HumanController drives us via tick().
	set_physics_process(false)
	set_process(false)

	## Auto-detect the owning HumanController from the parent node when this
	## state machine is declared as a child in the .tscn scene file.
	## If controller was already set (programmatic add_child path), keep it.
	if controller == null:
		controller = get_parent() as HumanController
	assert(controller != null, "NPCStateMachine: must be a child of HumanController or have controller set before add_child().")

	## Register any state nodes that were added as children in the .tscn.
	## This allows designers to see and edit state nodes in the editor without
	## needing to change GDScript code.
	_try_register_tscn_children()

	## Create any states that were not provided by the .tscn (fallback).
	if not _state_map.has(int(State.IDLE)):
		_register_state(State.IDLE, NPCIdleState.new())
	if not _state_map.has(int(State.MOVING_TO_SIGNAL)):
		_register_state(State.MOVING_TO_SIGNAL, NPCMovingToSignalState.new())
	if not _state_map.has(int(State.PANICKING)):
		_register_state(State.PANICKING, NPCPanicState.new())
	if not _state_map.has(int(State.HIDING)):
		_register_state(State.HIDING, NPCHidingState.new())
	if not _state_map.has(int(State.FLEEING_TO_POD)):
		_register_state(State.FLEEING_TO_POD, NPCFleeingToPodState.new())

	EventBus.enemies_have_spawned.connect(_on_enemies_have_spawned)

	## Start in IDLE without emitting a state-changed signal.
	_activate_state(State.IDLE)

## Scans existing children (from .tscn) and registers them by class type.
func _try_register_tscn_children() -> void:
	for child in get_children():
		if not child is NPCStateBase:
			continue
		if child is NPCIdleState and not _state_map.has(int(State.IDLE)):
			_register_existing_state(State.IDLE, child)
		elif child is NPCMovingToSignalState and not _state_map.has(int(State.MOVING_TO_SIGNAL)):
			_register_existing_state(State.MOVING_TO_SIGNAL, child)
		elif child is NPCPanicState and not _state_map.has(int(State.PANICKING)):
			_register_existing_state(State.PANICKING, child)
		elif child is NPCHidingState and not _state_map.has(int(State.HIDING)):
			_register_existing_state(State.HIDING, child)
		elif child is NPCFleeingToPodState and not _state_map.has(int(State.FLEEING_TO_POD)):
			_register_existing_state(State.FLEEING_TO_POD, child)
		## Specialist nodes with an explicit bound_state override.
		elif child.bound_state >= 0 and not _state_map.has(child.bound_state):
			child.controller = controller
			child.state_machine = self
			_state_map[child.bound_state] = child

func _register_state(state: State, node: NPCStateBase) -> void:
	node.name = State.keys()[state]
	node.controller = controller
	node.state_machine = self
	add_child(node)
	_state_map[int(state)] = node

## Registers a state node that already exists as a child (from the .tscn scene).
func _register_existing_state(state: State, node: NPCStateBase) -> void:
	node.controller = controller
	node.state_machine = self
	_state_map[int(state)] = node

## \u2500\u2500 Tick (called by HumanController._physics_process) \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

func tick(delta: float) -> void:
	if current_state == State.DEAD:
		return

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
		if _run_boost_timer < 0.0:
			_run_boost_timer = 0.0

	if _active_state != null:
		_active_state.tick(delta)

## \u2500\u2500 State transitions \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

func transition_to(new_state: State) -> void:
	if current_state == State.DEAD:
		return
	if _active_state != null:
		_active_state.on_exit()
	_activate_state(new_state)
	if is_instance_valid(controller):
		EventBus.npc_state_changed.emit(controller, _state_name(new_state))

func _activate_state(state: State) -> void:
	current_state = state
	_active_state = _state_map.get(int(state), null) as NPCStateBase
	if _active_state != null:
		_active_state.on_enter()

## \u2500\u2500 Public API \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

func receive_signal(room_index: int, signal_type: StringName = &"move") -> void:
	if current_state == State.DEAD:
		return

	## Reset recovery timers when a comms signal arrives mid-panic or mid-hide.
	if current_state == State.PANICKING:
		var ps := _state_map.get(int(State.PANICKING)) as NPCPanicState
		if ps:
			ps.panic_recovery_timer = 0.0
	if current_state == State.HIDING:
		var hs := _state_map.get(int(State.HIDING)) as NPCHidingState
		if hs:
			hs.hide_timer = 0.0

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
			if is_instance_valid(controller):
				controller.ai_agent.set_target(ShipData.get_room_center_world(room_index))
			## Reset signal linger in the MovingToSignal state.
			var ms := _state_map.get(int(State.MOVING_TO_SIGNAL)) as NPCMovingToSignalState
			if ms:
				ms._signal_linger_timer = 0.0
			transition_to(State.MOVING_TO_SIGNAL)

func repath_flee() -> void:
	var fs := _state_map.get(int(State.FLEEING_TO_POD)) as NPCFleeingToPodState
	if fs:
		fs.pick_flee_target()

## \u2500\u2500 Helpers called by state nodes \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

func _on_enemies_have_spawned() -> void:
	_enemies_active = true
	if current_state == State.IDLE:
		begin_flee_to_pod()

func begin_flee_to_pod() -> void:
	var fs := _state_map.get(int(State.FLEEING_TO_POD)) as NPCFleeingToPodState
	if fs:
		fs.reset_flee_state()
	transition_to(State.FLEEING_TO_POD)

func enter_panic() -> void:
	## on_enter() on NPCPanicState resets the timer.
	transition_to(State.PANICKING)

func hide_in_room(room_index: int) -> void:
	var room_rect: Rect2 = ShipData.get_room_world_rect(room_index)
	if room_rect.size == Vector2.ZERO:
		if _enemies_active:
			begin_flee_to_pod()
		else:
			transition_to(State.IDLE)
		return

	var padding: float = 16.0
	var corners: Array[Vector2] = [
		Vector2(room_rect.position.x + padding, room_rect.position.y + padding),
		Vector2(room_rect.end.x   - padding, room_rect.position.y + padding),
		Vector2(room_rect.position.x + padding, room_rect.end.y   - padding),
		Vector2(room_rect.end.x   - padding, room_rect.end.y   - padding),
	]
	var target_pos: Vector2 = corners.pick_random()
	if is_instance_valid(controller):
		controller.ai_agent.set_target(target_pos)

	var hs := _state_map.get(int(State.HIDING)) as NPCHidingState
	if hs:
		hs.hide_duration = randf_range(3.0, 8.0)
	transition_to(State.HIDING)

func coward_flee() -> void:
	if not is_instance_valid(controller):
		return
	var current_room: int = ShipData.get_room_at_world_pos(controller.global_position)
	if current_room < 0:
		if _enemies_active:
			begin_flee_to_pod()
		else:
			transition_to(State.IDLE)
		return

	var neighbors: Array = ShipData.room_adjacency.get(current_room, [])
	if neighbors.is_empty():
		hide_in_room(current_room)
		return

	var safe_rooms: Array = []
	for n_idx in neighbors:
		var n_rect: Rect2 = ShipData.get_room_world_rect(n_idx)
		var has_alien: bool = false
		for enemy in ShipData.cached_enemies:
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
	hide_in_room(chosen_room)

## \u2500\u2500 Shared helpers (called by state nodes via state_machine.X()) \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

func should_panic() -> bool:
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
	for enemy in ShipData.cached_enemies:
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

func try_rush_pod_in_current_room() -> bool:
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
	## Transition first so the NPC enters flee speed/behaviour, then override
	## the navigation target with the exact pod position.  When already in
	## FLEEING_TO_POD, skip re-entry so pick_flee_target() doesn't overwrite
	## the target we're about to set.
	if current_state != State.FLEEING_TO_POD:
		transition_to(State.FLEEING_TO_POD)
	_navigate_into_pod(pod_in_room)
	return true

func try_rush_pod_in_nearby_rooms() -> bool:
	if not _enemies_active or not is_instance_valid(controller):
		return false
	var npc_room: int = ShipData.get_room_at_world_pos(controller.global_position)
	if npc_room < 0:
		return false
	var pod_nearby := _get_active_pod_in_adjacent_rooms(npc_room)
	if pod_nearby == null:
		return false
	if current_state != State.FLEEING_TO_POD:
		transition_to(State.FLEEING_TO_POD)
	_navigate_into_pod(pod_nearby)
	return true

func _navigate_into_pod(pod: Node2D) -> void:
	var dir_to_pod: Vector2 = pod.global_position - controller.global_position
	if dir_to_pod.length_squared() > 1.0:
		dir_to_pod = dir_to_pod.normalized()
		controller.ai_agent.set_target(pod.global_position + dir_to_pod * POD_ENTRY_OVERSHOOT)
	else:
		controller.ai_agent.set_target(pod.global_position)

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
		for enemy in ShipData.cached_enemies:
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

func _are_rooms_connected_with_open_doors(room_a: int, room_b: int) -> bool:
	if not ShipData.room_adjacency.has(room_a):
		return false
	if room_b not in ShipData.room_adjacency[room_a]:
		return false
	var doors_a: Array = ShipData.room_doors.get(room_a, [])
	var doors_b: Array = ShipData.room_doors.get(room_b, [])
	var found_shared_door: bool = false
	for door in doors_a:
		if door in doors_b:
			found_shared_door = true
			if is_instance_valid(door) and door is DoorSystem:
				if not door.is_open:
					return false
	return found_shared_door

func _state_name(state: State) -> StringName:
	match state:
		State.IDLE:            return &"idle"
		State.MOVING_TO_SIGNAL: return &"moving_to_signal"
		State.PANICKING:       return &"panicking"
		State.HIDING:          return &"hiding"
		State.FLEEING_TO_POD:  return &"fleeing_to_pod"
		State.DEAD:            return &"dead"
	return &"unknown"
