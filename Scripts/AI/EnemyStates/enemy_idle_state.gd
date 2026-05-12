class_name EnemyIdleState
extends EnemyStateBase

## Enemy has no target and is wandering, looking for prey.

var _idle_wander_timer: float = 0.0
const IDLE_WANDER_INTERVAL: float = 2.0

var _retarget_timer: float = 0.0
const RETARGET_INTERVAL: float = 0.5

func on_enter() -> void:
	_idle_wander_timer = 0.0
	_retarget_timer = 0.0
	controller._wander_in_current_room()

func tick(delta: float) -> void:
	## Periodic wander.
	_idle_wander_timer += delta
	if _idle_wander_timer >= IDLE_WANDER_INTERVAL:
		_idle_wander_timer = 0.0
		controller._wander_in_current_room()

	## Periodic target scan.
	_retarget_timer += delta
	if _retarget_timer >= RETARGET_INTERVAL:
		_retarget_timer = 0.0
		var nearest := controller._find_nearest_living_npc()
		if nearest != null:
			var dist_sq: float = controller.global_position.distance_squared_to(nearest.global_position)
			if dist_sq < controller._detection_range_sq:
				controller._current_target_npc = nearest
				controller._routing_my_room = -2
				controller._routing_target_room = -2
				controller._enter_state(EnemyController.EnemyState.HUNTING)
		else:
			controller._check_if_trapped()
