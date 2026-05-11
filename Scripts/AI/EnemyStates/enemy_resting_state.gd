class_name EnemyRestingState
extends EnemyStateBase

## Enemy is resting after a kill before resuming the hunt.

var _rest_timer: float = 0.0
var _rest_duration: float = 0.0
var _rest_wander_timer: float = 0.0
const REST_WANDER_INTERVAL: float = 1.5

func on_enter() -> void:
	_rest_timer = 0.0
	_rest_wander_timer = 0.0
	var bp: EnemyBehaviorProfile = controller.behavior_profile
	var min_d: float = bp.rest_duration_min if bp else 3.0
	var max_d: float = bp.rest_duration_max if bp else 5.0
	_rest_duration = randf_range(min_d, max_d)
	controller._wander_in_current_room()

func tick(delta: float) -> void:
	_rest_timer += delta
	if _rest_timer >= _rest_duration:
		## Rest over — look for a new target.
		var nearest := controller._find_nearest_living_npc()
		if nearest != null:
			controller._current_target_npc = nearest
			controller._routing_my_room = -2
			controller._routing_target_room = -2
			controller._enter_state(EnemyController.EnemyState.HUNTING)
		else:
			controller._enter_idle()
		return

	## Occasionally wander while resting.
	_rest_wander_timer += delta
	if _rest_wander_timer >= REST_WANDER_INTERVAL:
		_rest_wander_timer = 0.0
		controller._wander_in_current_room()
