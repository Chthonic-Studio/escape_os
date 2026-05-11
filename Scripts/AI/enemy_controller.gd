class_name EnemyController
extends CharacterBody2D

## Enemy AI controller.

@export var ai_agent: AIAgentComponent
@export var chase_speed: float = 70.0
@export var kill_range: float = 24.0

## Optional behavior profile that overrides the per-field defaults above.
## Assign an EnemyBehaviorProfile resource to define a distinct enemy type
## without subclassing EnemyController.
@export var behavior_profile: EnemyBehaviorProfile

var _damage_per_second: float = 40.0

var _detection_range_sq: float = DETECTION_RANGE_SQ

var _current_target_npc: Node2D = null
var _is_stunned: bool = false

enum EnemyState { HUNTING, IDLE, RESTING, STUNNED, ATTACKING_DOOR, LURED }
var current_state: EnemyState = EnemyState.HUNTING

var _investigate_target_pos: Vector2 = Vector2.ZERO
var _is_investigating: bool = false

@onready var _info_label: Label = $InfoBox/InfoLabel
@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D

var _stuck_timer: float = 0.0
var _last_position: Vector2 = Vector2.ZERO

const DEADLOCK_TIME_THRESHOLD: float = 1.5
const DEADLOCK_DIST_SQ_THRESHOLD: float = 16.0

## Room-graph routing: track the last resolved rooms so we only call
## ai_agent.set_target() when the situation actually changes.
var _routing_my_room: int = -2
var _routing_target_room: int = -2
## Minimum distance the target must move within the same room before we re-path.
const SAME_ROOM_REPATH_DIST_SQ: float = 28.0 * 28.0
var _routing_last_target_pos: Vector2 = Vector2.INF

## Node-based state machine — child node, ticked from _physics_process.
var _enemy_state_machine: EnemyStateMachineNode = null

func _ready() -> void:
	assert(ai_agent != null, "EnemyController requires an AIAgentComponent.")
	add_to_group("enemies")

	## Apply behavior profile overrides when one is assigned.
	if behavior_profile:
		chase_speed = behavior_profile.chase_speed
		kill_range = behavior_profile.kill_range
		_damage_per_second = behavior_profile.damage_per_second
		var r: float = behavior_profile.detection_range
		_detection_range_sq = r * r

	ai_agent.base_speed = chase_speed * GameManager.speed_multiplier
	ai_agent.safe_velocity_computed.connect(_on_safe_velocity_computed)
	_last_position = global_position

	## Create node-based state machine before any state is used.
	_enemy_state_machine = EnemyStateMachineNode.new()
	_enemy_state_machine.name = "EnemyStateMachine"
	_enemy_state_machine.controller = self
	add_child(_enemy_state_machine)
	## Activate initial state (HUNTING) without emitting EventBus signal.
	_enemy_state_machine.activate_state(EnemyState.HUNTING)

	_pick_nearest_target()
	EventBus.comms_signal_sent.connect(_on_comms_signal_sent)

	## Register in the ShipData enemy cache via the event bus.
	EventBus.enemy_ready.emit(self)

func _physics_process(delta: float) -> void:
	if _is_stunned:
		return

	ai_agent.base_speed = chase_speed * GameManager.speed_multiplier

	_enemy_state_machine.tick(delta)

	ai_agent.update_velocity_and_path()
	_check_for_deadlock(delta)

## Detects stuck enemies and nudges them toward room center.
func _check_for_deadlock(delta: float) -> void:
	if ai_agent.nav_agent.is_navigation_finished():
		_stuck_timer = 0.0
		return

	if global_position.distance_squared_to(_last_position) < DEADLOCK_DIST_SQ_THRESHOLD:
		_stuck_timer += delta
	else:
		_stuck_timer = 0.0
		_last_position = global_position

	if _stuck_timer >= DEADLOCK_TIME_THRESHOLD:
		_stuck_timer = 0.0
		_last_position = global_position
		var my_room: int = ShipData.get_room_at_world_pos(global_position)
		if my_room >= 0:
			var room_center: Vector2 = ShipData.get_room_center_world(my_room)
			var jitter := Vector2(randf_range(-20, 20), randf_range(-20, 20))
			ai_agent.set_target(room_center + jitter)
		else:
			var random_offset := Vector2(randf_range(-60, 60), randf_range(-60, 60))
			ai_agent.set_target(global_position + random_offset)

## Updates the nav-agent target using room-graph A* routing.
## Calls ai_agent.set_target() only when the routing situation changes,
## dramatically reducing NavigationServer2D path queries.
func _update_routing_target() -> void:
	if not is_instance_valid(_current_target_npc):
		return

	var my_room: int = ShipData.get_room_at_world_pos(global_position)
	var target_room: int = ShipData.get_room_at_world_pos(_current_target_npc.global_position)

	if my_room < 0:
		## Outside the nav graph — fall back to direct targeting.
		var tpos: Vector2 = _current_target_npc.global_position
		if tpos.distance_squared_to(_routing_last_target_pos) > SAME_ROOM_REPATH_DIST_SQ:
			_routing_last_target_pos = tpos
			ai_agent.set_target(tpos)
		return

	if my_room == target_room:
		## Same room: target the NPC directly, but throttle re-paths by distance moved.
		var tpos: Vector2 = _current_target_npc.global_position
		if (my_room != _routing_my_room or target_room != _routing_target_room or
				tpos.distance_squared_to(_routing_last_target_pos) > SAME_ROOM_REPATH_DIST_SQ):
			_routing_my_room = my_room
			_routing_target_room = target_room
			_routing_last_target_pos = tpos
			ai_agent.set_target(tpos)
		return

	## Different rooms: route via the room graph.
	## Re-path only when the enemy or target changes rooms.
	if my_room == _routing_my_room and target_room == _routing_target_room:
		return

	_routing_my_room = my_room
	_routing_target_room = target_room

	var next_room: int = RoomPathfinder.get_next_room(my_room, target_room)
	if next_room < 0 or next_room == my_room:
		## No path through the room graph — aim at the target directly.
		_routing_last_target_pos = _current_target_npc.global_position
		ai_agent.set_target(_routing_last_target_pos)
	else:
		## Aim at the door leading toward the target room.
		var door_pos: Vector2 = RoomPathfinder.get_door_pos(my_room, next_room)
		_routing_last_target_pos = door_pos
		ai_agent.set_target(door_pos)

func _enter_idle() -> void:
	_current_target_npc = null
	_is_investigating = false
	_routing_my_room = -2
	_routing_target_room = -2
	_enter_state(EnemyState.IDLE)

func _enter_resting() -> void:
	_current_target_npc = null
	_is_investigating = false
	_routing_my_room = -2
	_routing_target_room = -2
	_enter_state(EnemyState.RESTING)

## Attacks a closed door if no NPCs are reachable.
func _check_if_trapped() -> void:
	var can_break: bool = behavior_profile.can_break_doors if behavior_profile else true
	if not can_break:
		return

	var my_room: int = ShipData.get_room_at_world_pos(global_position)
	if my_room < 0:
		return

	var nearest := _find_nearest_living_npc()
	if nearest != null:
		return

	var room_doors_arr: Array = ShipData.room_doors.get(my_room, [])
	if room_doors_arr.is_empty():
		return

	var closest_door: DoorSystem = null
	var closest_dist_sq: float = INF

	for door in room_doors_arr:
		if not is_instance_valid(door) or not door is DoorSystem:
			continue
		if door.is_destroyed:
			continue
		if door.is_open:
			continue
		var d: float = global_position.distance_squared_to(door.global_position)
		if d < closest_dist_sq:
			closest_dist_sq = d
			closest_door = door

	if closest_door != null:
		_enter_attacking_door(closest_door)

func _enter_attacking_door(door: DoorSystem) -> void:
	_enter_state(EnemyState.ATTACKING_DOOR)
	var ads := _enemy_state_machine.get_state(EnemyState.ATTACKING_DOOR) as EnemyAttackingDoorState
	if ads:
		ads.set_door(door)

func _enter_state(new_state: EnemyState) -> void:
	current_state = new_state
	if _enemy_state_machine != null:
		_enemy_state_machine.activate_state(new_state)
	_update_info_label()

func _wander_in_current_room() -> void:
	var room_index: int = ShipData.get_room_at_world_pos(global_position)
	if room_index >= 0:
		var room_rect: Rect2 = ShipData.get_room_world_rect(room_index)
		var padding: float = 16.0
		var target := Vector2(
			randf_range(room_rect.position.x + padding, room_rect.end.x - padding),
			randf_range(room_rect.position.y + padding, room_rect.end.y - padding)
		)
		ai_agent.set_target(target)
	else:
		var random_offset := Vector2(randf_range(-100, 100), randf_range(-100, 100))
		ai_agent.set_target(global_position + random_offset)

func _find_nearest_living_npc() -> Node2D:
	var best_npc: Node2D = null
	var best_dist_sq: float = INF
	var my_room: int = ShipData.get_room_at_world_pos(global_position)

	for npc in ShipData.cached_npcs:
		if not is_instance_valid(npc) or not npc is Node2D:
			continue
		if npc is HumanController and npc.state_machine.current_state == NPCStateMachine.State.DEAD:
			continue
		var d: float = global_position.distance_squared_to(npc.global_position)
		if d >= best_dist_sq:
			continue
		var npc_room: int = ShipData.get_room_at_world_pos(npc.global_position)
		if my_room >= 0 and npc_room >= 0 and my_room != npc_room:
			if not _can_reach_room(my_room, npc_room, 6):
				continue
		best_dist_sq = d
		best_npc = npc

	return best_npc

func _can_reach_room(from_room: int, to_room: int, max_depth: int) -> bool:
	var visited: Dictionary = {}
	var frontier: Array = [from_room]
	visited[from_room] = true

	for _depth in range(max_depth):
		var next_frontier: Array = []
		for room_idx in frontier:
			if not ShipData.room_adjacency.has(room_idx):
				continue
			for neighbor_idx in ShipData.room_adjacency[room_idx]:
				if visited.has(neighbor_idx):
					continue
				if not _doors_open_between(room_idx, neighbor_idx):
					continue
				if neighbor_idx == to_room:
					return true
				visited[neighbor_idx] = true
				next_frontier.append(neighbor_idx)
		frontier = next_frontier
		if frontier.is_empty():
			break

	return false

## Finds a blocking door toward the target room.
func _find_blocking_door_toward(my_room: int, target_room: int) -> DoorSystem:
	var room_doors_arr: Array = ShipData.room_doors.get(my_room, [])
	if room_doors_arr.is_empty():
		return null

	var closest_door: DoorSystem = null
	var closest_dist_sq: float = INF
	for door in room_doors_arr:
		if not is_instance_valid(door) or not door is DoorSystem:
			continue
		if door.is_destroyed or door.is_open:
			continue
		if door.room_a_index == target_room or door.room_b_index == target_room:
			return door
		var d: float = global_position.distance_squared_to(door.global_position)
		if d < closest_dist_sq:
			closest_dist_sq = d
			closest_door = door

	return closest_door

## Finds a different reachable NPC target.
func _find_alternate_target() -> Node2D:
	var best_npc: Node2D = null
	var best_dist_sq: float = INF
	var my_room: int = ShipData.get_room_at_world_pos(global_position)

	for npc in ShipData.cached_npcs:
		if not is_instance_valid(npc) or not npc is Node2D:
			continue
		if npc == _current_target_npc:
			continue
		if npc is HumanController and npc.state_machine.current_state == NPCStateMachine.State.DEAD:
			continue
		var d: float = global_position.distance_squared_to(npc.global_position)
		if d >= best_dist_sq:
			continue
		var npc_room: int = ShipData.get_room_at_world_pos(npc.global_position)
		if my_room >= 0 and npc_room >= 0 and my_room != npc_room:
			if not _can_reach_room(my_room, npc_room, 6):
				continue
		best_dist_sq = d
		best_npc = npc

	return best_npc

## True if all doors between two rooms are open.
func _doors_open_between(room_a: int, room_b: int) -> bool:
	var doors_a: Array = ShipData.room_doors.get(room_a, [])
	var doors_b: Array = ShipData.room_doors.get(room_b, [])
	for door in doors_a:
		if door in doors_b:
			if is_instance_valid(door) and door is DoorSystem:
				if not door.is_open:
					return false
	return true

func _pick_nearest_target() -> void:
	var best_npc := _find_nearest_living_npc()
	_current_target_npc = best_npc
	_routing_my_room = -2
	_routing_target_room = -2
	if is_instance_valid(_current_target_npc):
		## Found a real target — cancel any ongoing investigation.
		_is_investigating = false
		ai_agent.set_target(_current_target_npc.global_position)

func _on_target_killed() -> void:
	_current_target_npc = null
	_routing_my_room = -2
	_routing_target_room = -2

	var nearest := _find_nearest_living_npc()
	if nearest != null:
		var d: float = global_position.distance_squared_to(nearest.global_position)
		if d < _detection_range_sq:
			_current_target_npc = nearest
			_enter_state(EnemyState.HUNTING)
			return

	_enter_resting()

func _on_safe_velocity_computed(safe_velocity: Vector2) -> void:
	velocity = safe_velocity

	move_and_slide()

	_update_sprite_animation()

	var dt: float = get_physics_process_delta_time()
	for i in range(get_slide_collision_count()):
		var collision: KinematicCollision2D = get_slide_collision(i)
		var collider: Object = collision.get_collider()
		if collider is HumanController:
			if collider.state_machine.current_state != NPCStateMachine.State.DEAD:
				var killed: bool = collider.take_damage(_damage_per_second * dt)
				if killed:
					_on_target_killed()

func _is_in_kill_range(target: Node2D) -> bool:
	var dist_sq: float = global_position.distance_squared_to(target.global_position)
	return dist_sq <= kill_range * kill_range

func _update_sprite_animation() -> void:
	if not _sprite:
		return
	var anim: StringName
	if current_state == EnemyState.HUNTING and is_instance_valid(_current_target_npc):
		if _is_in_kill_range(_current_target_npc):
			anim = &"eating"
			if _sprite.animation != anim:
				_sprite.play(anim)
			return
	var is_moving: bool = velocity.length_squared() > 1.0
	anim = &"moving" if is_moving else &"idle"
	if _sprite.animation != anim:
		_sprite.play(anim)
	if is_moving:
		_sprite.flip_h = velocity.x < 0

func stun(duration: float) -> void:
	if _is_stunned:
		return
	_is_stunned = true
	_enter_state(EnemyState.STUNNED)
	velocity = Vector2.ZERO
	await get_tree().create_timer(duration, false).timeout
	if is_instance_valid(self):
		_is_stunned = false
		_routing_my_room = -2
		_routing_target_room = -2
		var nearest := _find_nearest_living_npc()
		if nearest != null:
			_current_target_npc = nearest
			_enter_state(EnemyState.HUNTING)
		else:
			_enter_idle()

## Receives a room-level hint from the Enemy Director (global brain).
## When the hunter is idle or resting, this nudges it toward the hinted room
## so it can hunt locally once it arrives.  The hint_receptiveness value in the
## behavior profile controls the probability of acting on the hint.
func receive_director_hint(room_index: int) -> void:
	if _is_stunned:
		return
	if current_state != EnemyState.IDLE and current_state != EnemyState.RESTING:
		return
	var receptiveness: float = behavior_profile.hint_receptiveness if behavior_profile else 0.85
	if randf() > receptiveness:
		return
	var hint_pos: Vector2 = ShipData.get_room_center_world(room_index)
	if hint_pos == Vector2.ZERO:
		return
	_investigate_target_pos = hint_pos
	_is_investigating = true
	_routing_my_room = -2
	_routing_target_room = -2
	ai_agent.set_target(hint_pos)
	_enter_state(EnemyState.HUNTING)

## Handles incoming lure signal.
func receive_lure_signal(lure_pos: Vector2) -> void:
	if _is_stunned:
		return
	_current_target_npc = null
	_routing_my_room = -2
	_routing_target_room = -2
	var lured := _enemy_state_machine.get_state(EnemyState.LURED) as EnemyLuredState
	if lured:
		lured._lure_target_pos = lure_pos
	_enter_state(EnemyState.LURED)

## Enemies investigate signal broadcasts.
func _on_comms_signal_sent(room_index: int, _affected_rooms: Array) -> void:
	if _is_stunned:
		return
	if room_index < 0:
		return
	## If actively hunting a close target, ignore the broadcast.
	if is_instance_valid(_current_target_npc) and current_state == EnemyState.HUNTING:
		var dist_sq: float = global_position.distance_squared_to(_current_target_npc.global_position)
		if dist_sq < _detection_range_sq:
			return
	## Always update the nav target alongside _is_investigating so the two stay
	## in sync.  If the current target later becomes invalid, _process_hunting()
	## will navigate to this position rather than whatever stale target was set.
	var comms_pos: Vector2 = ShipData.get_room_center_world(room_index)
	_investigate_target_pos = comms_pos
	_is_investigating = true
	_routing_my_room = -2
	_routing_target_room = -2
	ai_agent.set_target(comms_pos)
	if current_state != EnemyState.HUNTING:
		_enter_state(EnemyState.HUNTING)

func _update_info_label() -> void:
	if not _info_label:
		return
	var status: String = "HUNTING"
	match current_state:
		EnemyState.IDLE:
			status = "IDLE"
		EnemyState.RESTING:
			status = "RESTING"
		EnemyState.STUNNED:
			status = "STUNNED"
		EnemyState.LURED:
			status = "LURED"
		EnemyState.ATTACKING_DOOR:
			var ads := _enemy_state_machine.get_state(EnemyState.ATTACKING_DOOR) \
					as EnemyAttackingDoorState if _enemy_state_machine else null
			var pct: int = roundi(ads.attack_progress * 100.0) if ads else 0
			status = "BREAKING %d%%" % pct
		EnemyState.HUNTING:
			if _is_investigating:
				status = "INVESTIGATING"
			elif is_instance_valid(_current_target_npc) and _current_target_npc is HumanController:
				if _is_in_kill_range(_current_target_npc):
					var hp_pct: int = roundi((_current_target_npc.health / HumanController.MAX_HEALTH) * 100.0)
					status = "KILLING %d%%" % hp_pct
				else:
					status = "HUNTING"
			else:
				status = "HUNTING"
	_info_label.text = "HOSTILE // %s" % status

func die() -> void:
	EventBus.enemy_died.emit(self)
	_explode_and_free()

func _explode_and_free() -> void:
	if has_node("CollisionShape2D"):
		$CollisionShape2D.set_deferred("disabled", true)
		
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", scale * 1.5, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.set_parallel(false)
	tween.tween_callback(queue_free)
