class_name NPCFleeingToPodState
extends NPCStateBase

## NPC is actively fleeing toward an escape pod.
## Periodically rethinks its route to avoid congestion.

var _flee_rethink_timer: float = 0.0
var _flee_rethink_interval: float = 0.0
var _flee_pause_timer: float = 0.0
var _flee_is_paused: bool = false
var _flee_detour_active: bool = false
var _flee_target_pod_pos: Vector2 = Vector2.ZERO

## Blacklisted pods (full when last checked) → true.
var _blacklisted_pods: Dictionary = {}
var _blacklist_recheck_timer: float = 0.0
const BLACKLIST_RECHECK_INTERVAL: float = 5.0

func on_enter() -> void:
	reset_flee_state()
	pick_flee_target()

func on_exit() -> void:
	_blacklisted_pods.clear()

func reset_flee_state() -> void:
	_flee_rethink_timer = 0.0
	_flee_is_paused = false
	_flee_detour_active = false
	_flee_rethink_interval = randf_range(2.0, 5.0)

func tick(delta: float) -> void:
	var sm: NPCStateMachine = state_machine as NPCStateMachine

	_blacklist_recheck_timer += delta
	if _blacklist_recheck_timer >= BLACKLIST_RECHECK_INTERVAL:
		_blacklist_recheck_timer = 0.0
		_blacklisted_pods.clear()

	if sm.try_rush_pod_in_current_room():
		return
	if sm.try_rush_pod_in_nearby_rooms():
		return

	if sm.should_panic():
		sm.enter_panic()
		return

	if _flee_is_paused:
		_flee_pause_timer -= delta
		if _flee_pause_timer <= 0.0:
			_flee_is_paused = false
			pick_flee_target()
		return

	_flee_rethink_timer += delta
	if _flee_rethink_timer >= _flee_rethink_interval:
		_flee_rethink_timer = 0.0
		_flee_rethink_interval = randf_range(2.0, 5.0)
		_rethink_flee_behavior()

	if is_instance_valid(controller) and controller.ai_agent.nav_agent.is_navigation_finished():
		pick_flee_target()

## Picks the best available pod as flee destination.
func pick_flee_target() -> void:
	var sm: NPCStateMachine = state_machine as NPCStateMachine
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

	## Use the room-graph pathfinder to route toward the pod's room via the
	## correct door, rather than blindly picking the nearest adjacent room.
	## This prevents NPCs from ignoring available pods in non-adjacent rooms.
	if npc_room >= 0:
		var pod_room: int = ShipData.get_room_at_world_pos(best_pod_pos)
		if pod_room >= 0 and pod_room != npc_room:
			var next_room: int = RoomPathfinder.get_next_room(npc_room, pod_room)
			if next_room >= 0 and next_room != npc_room:
				## Navigate toward the door leading to the next room on the path.
				var door_pos: Vector2 = RoomPathfinder.get_door_pos(npc_room, next_room)
				## Apply congestion-aware jitter to spread NPCs through the door.
				var congestion: int = ShipData.npc_room_counts.get(next_room, 0)
				var jitter_scale: float = clampf(1.0 + congestion * 0.15, 1.0, 2.5)
				var jitter := Vector2(
					randf_range(-20, 20) * jitter_scale,
					randf_range(-20, 20) * jitter_scale
				)
				controller.ai_agent.set_target(door_pos + jitter)
				return
		elif pod_room == npc_room:
			## Already in the pod's room — head straight for it.
			var offset := Vector2(randf_range(-20, 20), randf_range(-20, 20))
			controller.ai_agent.set_target(best_pod_pos + offset)
			return
		## pod_room < 0: the pod's world position isn't inside any recognised
		## room rect (e.g. placed near a boundary).  Navigate directly to it
		## rather than falling through to the adjacent-room heuristic, which
		## would send the NPC away from a perfectly valid nearby pod.
		var dist_to_pod: float = npc_pos.distance_to(best_pod_pos)
		if dist_to_pod < 220.0:
			var offset := Vector2(randf_range(-15, 15), randf_range(-15, 15))
			controller.ai_agent.set_target(best_pod_pos + offset)
			return

	## Fallback: greedy adjacent-room selection with congestion weighting.
	if npc_room >= 0 and ShipData.room_adjacency.has(npc_room):
		var neighbors: Array = ShipData.room_adjacency[npc_room]
		if not neighbors.is_empty():
			var best_neighbor: int = neighbors[0]
			var best_score: float = INF
			const CONGESTION_PENALTY_PER_NPC: float = 80.0
			const AVOID_ROOM_PENALTY: float = 500.0
			for n_idx in neighbors:
				var n_center: Vector2 = ShipData.get_room_center_world(n_idx)
				var dist_score: float = n_center.distance_to(best_pod_pos)
				var congestion: int = ShipData.npc_room_counts.get(n_idx, 0)
				var avoid_penalty: float = AVOID_ROOM_PENALTY if n_idx == sm._avoided_room else 0.0
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
		pick_flee_target()
