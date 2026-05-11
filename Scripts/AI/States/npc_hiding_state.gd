class_name NPCHidingState
extends NPCStateBase

## NPC is hiding in a corner of a room after a coward-flee.
## Exits once the hide timer expires, or if pod / panic is triggered.

var hide_timer: float = 0.0
var hide_duration: float = 0.0

func on_enter() -> void:
	## hide_duration and the nav target are set externally before transitioning
	## into this state (see NPCStateMachine.hide_in_room()).
	hide_timer = 0.0

func tick(delta: float) -> void:
	var sm: NPCStateMachine = state_machine as NPCStateMachine

	if sm.try_rush_pod_in_current_room():
		return
	if sm.try_rush_pod_in_nearby_rooms():
		return

	if sm.should_panic():
		hide_timer = 0.0
		sm.enter_panic()
		return

	hide_timer += delta
	if hide_timer >= hide_duration:
		hide_timer = 0.0
		if sm._enemies_active:
			sm.begin_flee_to_pod()
		else:
			sm.transition_to(NPCStateMachine.State.IDLE)
