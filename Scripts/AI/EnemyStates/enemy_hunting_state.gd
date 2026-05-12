class_name EnemyHuntingState
extends EnemyStateBase

## Enemy is actively pursuing a target NPC.
## All routing helpers remain on EnemyController as the "context API".

var _retarget_timer: float = 0.0
const RETARGET_INTERVAL: float = 0.5

func on_enter() -> void:
	_retarget_timer = 0.0

func tick(delta: float) -> void:
	_retarget_timer += delta
	if _retarget_timer >= RETARGET_INTERVAL:
		_retarget_timer = 0.0
		controller._pick_nearest_target()

	if not is_instance_valid(controller._current_target_npc):
		if controller._is_investigating:
			## Navigating toward a hint/signal — wait for arrival.
			if controller.ai_agent.nav_agent.is_navigation_finished():
				controller._is_investigating = false
				controller._check_if_trapped()
				if controller.current_state != EnemyController.EnemyState.ATTACKING_DOOR:
					controller._enter_idle()
			return
		controller._check_if_trapped()
		if controller.current_state != EnemyController.EnemyState.ATTACKING_DOOR:
			controller._enter_idle()
		return

	## When half-stuck, try door break or alternate target.
	if controller._stuck_timer >= EnemyController.DEADLOCK_TIME_THRESHOLD * 0.5:
		var my_room: int = ShipData.get_room_at_world_pos(controller.global_position)
		var target_room: int = ShipData.get_room_at_world_pos(
				controller._current_target_npc.global_position)
		if my_room >= 0 and target_room >= 0 and my_room != target_room:
			var can_break: bool = controller.behavior_profile.can_break_doors \
					if controller.behavior_profile else true
			var blocking_door: DoorSystem = controller._find_blocking_door_toward(
					my_room, target_room) if can_break else null
			if blocking_door != null:
				controller._enter_attacking_door(blocking_door)
				return
			var alt := controller._find_alternate_target()
			if alt != null:
				controller._current_target_npc = alt
				controller._routing_my_room = -2
				controller._routing_target_room = -2
				controller._stuck_timer = 0.0
				return
		controller._check_if_trapped()
		if controller.current_state == EnemyController.EnemyState.ATTACKING_DOOR:
			return

	## Route toward target.
	controller._update_routing_target()

	## Deal damage when in kill range.
	if controller._is_in_kill_range(controller._current_target_npc):
		if controller._current_target_npc is HumanController:
			var killed: bool = controller._current_target_npc.take_damage(
					controller.damage_per_second * delta)
			controller._update_info_label()
			if killed:
				controller._on_target_killed()
