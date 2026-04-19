class_name EnemyController
extends CharacterBody2D

## Enemy AI controller.

@export var ai_agent: AIAgentComponent
@export var chase_speed: float = 70.0
@export var kill_range: float = 24.0

const DAMAGE_PER_SECOND: float = 40.0

var _retarget_timer: float = 0.0
const RETARGET_INTERVAL: float = 0.5

const DETECTION_RANGE_SQ: float = 250.0 * 250.0

var _current_target_npc: Node2D = null
var _is_stunned: bool = false

enum EnemyState { HUNTING, IDLE, RESTING, STUNNED, ATTACKING_DOOR, LURED }
var current_state: EnemyState = EnemyState.HUNTING

var _rest_timer: float = 0.0
var _rest_duration: float = 0.0
var _rest_wander_timer: float = 0.0

var _idle_wander_timer: float = 0.0

var _door_attack_target: DoorSystem = null
var _door_attack_timer: float = 0.0
const DOOR_ATTACK_DURATION: float = 1.0
const DOOR_ATTACK_RANGE_MULTIPLIER: float = 4.0

## Lure state — enemy follows a lure target.
var _lure_target_pos: Vector2 = Vector2.ZERO
var _lure_timer: float = 0.0
const LURE_DURATION: float = 2.5
const LURE_ARRIVAL_DIST_SQ: float = 32.0 * 32.0

var _investigate_target_pos: Vector2 = Vector2.ZERO
var _is_investigating: bool = false

@onready var _info_label: Label = $InfoBox/InfoLabel
@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D

var _stuck_timer: float = 0.0
var _last_position: Vector2 = Vector2.ZERO

const DEADLOCK_TIME_THRESHOLD: float = 1.5
const DEADLOCK_DIST_SQ_THRESHOLD: float = 16.0

func _ready() -> void:
	assert(ai_agent != null, "EnemyController requires an AIAgentComponent.")
	add_to_group("enemies")
	ai_agent.base_speed = chase_speed * GameManager.speed_multiplier
	ai_agent.safe_velocity_computed.connect(_on_safe_velocity_computed)
	_last_position = global_position
	_pick_nearest_target()
	EventBus.comms_signal_sent.connect(_on_comms_signal_sent)

func _physics_process(delta: float) -> void:
	if _is_stunned:
		return

	ai_agent.base_speed = chase_speed * GameManager.speed_multiplier

	match current_state:
		EnemyState.HUNTING:
			_process_hunting(delta)
		EnemyState.IDLE:
			_process_idle(delta)
		EnemyState.RESTING:
			_process_resting(delta)
		EnemyState.ATTACKING_DOOR:
			_process_attacking_door(delta)
		EnemyState.LURED:
			_process_lured(delta)

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

func _process_hunting(delta: float) -> void:
	_retarget_timer += delta
	if _retarget_timer >= RETARGET_INTERVAL:
		_retarget_timer = 0.0
		_pick_nearest_target()

	if not is_instance_valid(_current_target_npc):
		_check_if_trapped()
		if current_state != EnemyState.ATTACKING_DOOR:
			_enter_idle()
		return

	if _stuck_timer >= DEADLOCK_TIME_THRESHOLD * 0.5:
		var my_room: int = ShipData.get_room_at_world_pos(global_position)
		var target_room: int = ShipData.get_room_at_world_pos(_current_target_npc.global_position)
		if my_room >= 0 and target_room >= 0 and my_room != target_room:
			var blocking_door := _find_blocking_door_toward(my_room, target_room)
			if blocking_door != null:
				_enter_attacking_door(blocking_door)
				return
			var alt_target := _find_alternate_target()
			if alt_target != null:
				_current_target_npc = alt_target
				ai_agent.set_target(alt_target.global_position)
				_stuck_timer = 0.0
				return
		_check_if_trapped()
		if current_state == EnemyState.ATTACKING_DOOR:
			return

	ai_agent.set_target(_current_target_npc.global_position)

	if _is_in_kill_range(_current_target_npc):
		if _current_target_npc is HumanController:
			var killed: bool = _current_target_npc.take_damage(DAMAGE_PER_SECOND * delta)
			_update_info_label()
			if killed:
				_on_target_killed()

func _process_idle(delta: float) -> void:
	_idle_wander_timer += delta
	if _idle_wander_timer >= 2.0:
		_idle_wander_timer = 0.0
		_wander_in_current_room()

	_retarget_timer += delta
	if _retarget_timer >= RETARGET_INTERVAL:
		_retarget_timer = 0.0
		var nearest := _find_nearest_living_npc()
		if nearest != null:
			var d: float = global_position.distance_squared_to(nearest.global_position)
			if d < DETECTION_RANGE_SQ:
				_current_target_npc = nearest
				ai_agent.set_target(nearest.global_position)
				_enter_state(EnemyState.HUNTING)
		else:
			_check_if_trapped()

func _process_resting(delta: float) -> void:
	_rest_timer += delta
	_rest_wander_timer += delta

	if _rest_wander_timer >= 1.5:
		_rest_wander_timer = 0.0
		_wander_in_current_room()

	if _rest_timer >= _rest_duration:
		var nearest := _find_nearest_living_npc()
		if nearest != null:
			_current_target_npc = nearest
			ai_agent.set_target(nearest.global_position)
			_enter_state(EnemyState.HUNTING)
		else:
			_enter_idle()

func _enter_idle() -> void:
	_current_target_npc = null
	_idle_wander_timer = 0.0
	_is_investigating = false
	_enter_state(EnemyState.IDLE)
	_wander_in_current_room()

func _enter_resting() -> void:
	_current_target_npc = null
	_rest_timer = 0.0
	_rest_wander_timer = 0.0
	_rest_duration = randf_range(3.0, 5.0)
	_is_investigating = false
	_enter_state(EnemyState.RESTING)
	_wander_in_current_room()

## Attacks a closed door if no NPCs are reachable.
func _check_if_trapped() -> void:
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
	_door_attack_target = door
	_door_attack_timer = 0.0
	_enter_state(EnemyState.ATTACKING_DOOR)
	ai_agent.set_target(door.global_position)

func _process_attacking_door(delta: float) -> void:
	if not is_instance_valid(_door_attack_target) or _door_attack_target.is_destroyed:
		_door_attack_target = null
		var nearest := _find_nearest_living_npc()
		if nearest != null:
			_current_target_npc = nearest
			ai_agent.set_target(nearest.global_position)
			_enter_state(EnemyState.HUNTING)
		else:
			_enter_idle()
		return

	ai_agent.set_target(_door_attack_target.global_position)

	var dist_sq: float = global_position.distance_squared_to(_door_attack_target.global_position)
	if dist_sq <= kill_range * kill_range * DOOR_ATTACK_RANGE_MULTIPLIER:
		_door_attack_timer += delta
		_update_info_label()
		if _door_attack_timer >= DOOR_ATTACK_DURATION:
			_door_attack_target.destroy()
			_door_attack_target = null
			var nearest := _find_nearest_living_npc()
			if nearest != null:
				_current_target_npc = nearest
				ai_agent.set_target(nearest.global_position)
				_enter_state(EnemyState.HUNTING)
			else:
				_enter_idle()
	else:
		_door_attack_timer = 0.0

func _enter_state(new_state: EnemyState) -> void:
	current_state = new_state
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
	var npcs := get_tree().get_nodes_in_group("npcs")
	var best_npc: Node2D = null
	var best_dist_sq: float = INF
	var my_room: int = ShipData.get_room_at_world_pos(global_position)

	for npc in npcs:
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
	var npcs := get_tree().get_nodes_in_group("npcs")
	var best_npc: Node2D = null
	var best_dist_sq: float = INF
	var my_room: int = ShipData.get_room_at_world_pos(global_position)

	for npc in npcs:
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
	if is_instance_valid(_current_target_npc):
		ai_agent.set_target(_current_target_npc.global_position)

func _on_target_killed() -> void:
	_current_target_npc = null

	var nearest := _find_nearest_living_npc()
	if nearest != null:
		var d: float = global_position.distance_squared_to(nearest.global_position)
		if d < DETECTION_RANGE_SQ:
			_current_target_npc = nearest
			ai_agent.set_target(nearest.global_position)
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
				var killed: bool = collider.take_damage(DAMAGE_PER_SECOND * dt)
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
		var nearest := _find_nearest_living_npc()
		if nearest != null:
			_current_target_npc = nearest
			ai_agent.set_target(nearest.global_position)
			_enter_state(EnemyState.HUNTING)
		else:
			_enter_idle()

## Handles incoming lure signal.
func receive_lure_signal(lure_pos: Vector2) -> void:
	if _is_stunned:
		return
	_current_target_npc = null
	_lure_target_pos = lure_pos
	_lure_timer = 0.0
	ai_agent.set_target(lure_pos)
	_enter_state(EnemyState.LURED)

## Enemies investigate signal broadcasts.
func _on_comms_signal_sent(room_index: int, _affected_rooms: Array) -> void:
	if _is_stunned:
		return
	if room_index < 0:
		return
	if is_instance_valid(_current_target_npc) and current_state == EnemyState.HUNTING:
		var dist_sq: float = global_position.distance_squared_to(_current_target_npc.global_position)
		if dist_sq < DETECTION_RANGE_SQ:
			return
	_investigate_target_pos = ShipData.get_room_center_world(room_index)
	_is_investigating = true
	if current_state == EnemyState.IDLE or current_state == EnemyState.RESTING:
		ai_agent.set_target(_investigate_target_pos)
		_enter_state(EnemyState.HUNTING)

## Moves toward lure target until arrival or timeout.
func _process_lured(delta: float) -> void:
	_lure_timer += delta

	ai_agent.set_target(_lure_target_pos)

	var dist_sq: float = global_position.distance_squared_to(_lure_target_pos)
	var arrived: bool = dist_sq <= LURE_ARRIVAL_DIST_SQ
	var expired: bool = _lure_timer >= LURE_DURATION

	if arrived or expired:
		var nearest := _find_nearest_living_npc()
		if nearest != null:
			_current_target_npc = nearest
			ai_agent.set_target(nearest.global_position)
			_enter_state(EnemyState.HUNTING)
		else:
			_enter_idle()

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
			var pct: int = roundi((_door_attack_timer / DOOR_ATTACK_DURATION) * 100.0)
			status = "BREAKING %d%%" % pct
		EnemyState.HUNTING:
			if is_instance_valid(_current_target_npc) and _current_target_npc is HumanController:
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
