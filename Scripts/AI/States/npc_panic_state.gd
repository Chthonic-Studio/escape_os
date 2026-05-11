class_name NPCPanicState
extends NPCStateBase

## NPC is panicking: runs erratically and may hide or flee to pod.

var _panic_duration_timer: float = 0.0
## Maximum time spent in panic before forcing a transition.
const PANIC_DURATION_MAX: float = 8.0
## Cooldown before the NPC can panic again (set on state machine).
const PANIC_COOLDOWN_DURATION: float = 3.0

var panic_recovery_timer: float = 0.0

func on_enter() -> void:
	_panic_duration_timer = 0.0
	panic_recovery_timer = 0.0

func tick(delta: float) -> void:
	var sm: NPCStateMachine = state_machine as NPCStateMachine

	_panic_duration_timer += delta
	if _panic_duration_timer >= PANIC_DURATION_MAX:
		_panic_duration_timer = 0.0
		sm._panic_cooldown_timer = PANIC_COOLDOWN_DURATION
		if sm._enemies_active:
			sm.begin_flee_to_pod()
		else:
			sm.transition_to(NPCStateMachine.State.IDLE)
		return

	if sm.try_rush_pod_in_current_room():
		return
	if sm.try_rush_pod_in_nearby_rooms():
		return

	match sm.personality:
		NPCPersonality.Type.BRAVE:
			if sm._enemies_active:
				sm.begin_flee_to_pod()
			else:
				sm.transition_to(NPCStateMachine.State.IDLE)

		NPCPersonality.Type.COWARD:
			sm.coward_flee()

		NPCPersonality.Type.RECKLESS, NPCPersonality.Type.NORMAL:
			if sm.should_panic():
				panic_recovery_timer = 0.0
				if is_instance_valid(controller) and controller.ai_agent.nav_agent.is_navigation_finished():
					controller._wander_to_random_point()
			else:
				panic_recovery_timer += delta
				if panic_recovery_timer >= NPCStateMachine.PANIC_RECOVERY_CHECK:
					panic_recovery_timer = 0.0
					if sm._enemies_active:
						sm.begin_flee_to_pod()
					else:
						sm.transition_to(NPCStateMachine.State.IDLE)
