class_name EnemyLuredState
extends EnemyStateBase

## Enemy is following a lure signal (comms type: lure).
## Follows the lure target for a fixed duration or until arriving.

var _lure_target_pos: Vector2 = Vector2.ZERO
var _lure_timer: float = 0.0
const LURE_DURATION: float = 2.5
const LURE_ARRIVAL_DIST_SQ: float = 32.0 * 32.0

func on_enter() -> void:
	## _lure_target_pos is set by EnemyController.receive_lure_signal()
	## before transitioning into this state.
	_lure_timer = 0.0
	controller.ai_agent.set_target(_lure_target_pos)

func set_lure_target(target_pos: Vector2) -> void:
	_lure_target_pos = target_pos
	_lure_timer = 0.0
	controller.ai_agent.set_target(_lure_target_pos)

func tick(delta: float) -> void:
	_lure_timer += delta
	controller.ai_agent.set_target(_lure_target_pos)

	var dist_sq: float = controller.global_position.distance_squared_to(_lure_target_pos)
	var arrived: bool = dist_sq <= LURE_ARRIVAL_DIST_SQ
	var expired: bool = _lure_timer >= LURE_DURATION

	if arrived or expired:
		var nearest := controller._find_nearest_living_npc()
		if nearest != null:
			controller._current_target_npc = nearest
			controller._routing_my_room = -2
			controller._routing_target_room = -2
			controller._enter_state(EnemyController.EnemyState.HUNTING)
		else:
			controller._enter_idle()
