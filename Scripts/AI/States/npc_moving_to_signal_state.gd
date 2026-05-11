class_name NPCMovingToSignalState
extends NPCStateBase

## NPC is moving to a player-issued signal target room.
## Lingers briefly at the destination before returning to idle or fleeing.

var _signal_linger_timer: float = 0.0
const SIGNAL_LINGER_DURATION: float = 1.5

func on_enter() -> void:
	_signal_linger_timer = 0.0

func on_exit() -> void:
	_signal_linger_timer = 0.0

func tick(delta: float) -> void:
	var sm: NPCStateMachine = state_machine as NPCStateMachine
	if sm.try_rush_pod_in_current_room():
		return
	if sm.try_rush_pod_in_nearby_rooms():
		return
	if sm.should_panic():
		sm.enter_panic()
		return

	if is_instance_valid(controller):
		var nav = controller.ai_agent.nav_agent
		if nav and nav.is_navigation_finished():
			_signal_linger_timer += delta
			if _signal_linger_timer >= SIGNAL_LINGER_DURATION:
				_signal_linger_timer = 0.0
				if sm._enemies_active:
					sm.begin_flee_to_pod()
				else:
					sm.transition_to(NPCStateMachine.State.IDLE)
