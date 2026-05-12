class_name EnemyStunnedState
extends EnemyStateBase

## Enemy is stunned and cannot move or attack.
## Stun duration is managed by EnemyController.stun() via a timer.

func on_enter() -> void:
	controller.velocity = Vector2.ZERO

func tick(_delta: float) -> void:
	## All stun logic is handled by the coroutine in EnemyController.stun().
	## This state just holds until stun() transitions away.
	pass
