class_name NPCIdleState
extends NPCStateBase

## NPC is idle: wanders randomly.
## When enemies activate, immediately begins fleeing to a pod.
## If an enemy is nearby, triggers panic.

func on_enter() -> void:
	if is_instance_valid(controller):
		controller._wander_to_random_point()

func tick(_delta: float) -> void:
	var sm: NPCStateMachine = state_machine as NPCStateMachine
	if sm.try_rush_pod_in_current_room():
		return
	if sm.try_rush_pod_in_nearby_rooms():
		return
	if sm.should_panic():
		sm.enter_panic()
		return
	if sm._enemies_active:
		sm.begin_flee_to_pod()
