class_name EnemyAttackingDoorState
extends EnemyStateBase

## Enemy is trying to break down a door blocking its path to the target.

var _door_attack_target: DoorSystem = null
var _door_attack_timer: float = 0.0
const DOOR_ATTACK_DURATION: float = 1.0
const DOOR_ATTACK_RANGE_MULTIPLIER: float = 4.0

## Public read for info-label display.
var attack_progress: float = 0.0

func on_enter() -> void:
	_door_attack_timer = 0.0
	attack_progress = 0.0

func set_door(door: DoorSystem) -> void:
	_door_attack_target = door
	_door_attack_timer = 0.0
	attack_progress = 0.0
	if is_instance_valid(door):
		controller.ai_agent.set_target(door.global_position)

func tick(delta: float) -> void:
	if not is_instance_valid(_door_attack_target):
		_abort()
		return

	if _door_attack_target.is_destroyed or _door_attack_target.is_open:
		_abort()
		return

	var dist_sq: float = controller.global_position.distance_squared_to(_door_attack_target.global_position)
	var attack_range: float = controller.kill_range * DOOR_ATTACK_RANGE_MULTIPLIER
	if dist_sq > attack_range * attack_range:
		## Not in range yet — navigate toward the door.
		controller.ai_agent.set_target(_door_attack_target.global_position)
		return

	_door_attack_timer += delta
	attack_progress = _door_attack_timer / DOOR_ATTACK_DURATION
	controller._update_info_label()

	if _door_attack_timer >= DOOR_ATTACK_DURATION:
		_door_attack_target.destroy()
		_door_attack_target = null
		_door_attack_timer = 0.0
		attack_progress = 0.0
		## Resume hunting after door is broken.
		if is_instance_valid(controller._current_target_npc):
			controller._routing_my_room = -2
			controller._routing_target_room = -2
			controller._enter_state(EnemyController.EnemyState.HUNTING)
		else:
			controller._enter_idle()

func _abort() -> void:
	_door_attack_target = null
	if is_instance_valid(controller._current_target_npc):
		controller._routing_my_room = -2
		controller._routing_target_room = -2
		controller._enter_state(EnemyController.EnemyState.HUNTING)
	else:
		controller._enter_idle()
