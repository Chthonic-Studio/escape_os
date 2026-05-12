class_name EnemyStateBase
extends Node

## Base class for all enemy state nodes.
## Each concrete state is a child of EnemyStateMachineNode.
##
## `controller` is the owning EnemyController (context API — helpers remain
## on the controller so state nodes call controller.helper_method()).
## `state_machine` is the parent EnemyStateMachineNode.

## Set by EnemyStateMachineNode during _ready().
var controller: EnemyController = null

## Declared as Node to prevent circular-dependency at parse time.
var state_machine: Node = null  # Actually EnemyStateMachineNode

## Optional: override in extra state nodes injected at runtime.
## Core states are registered explicitly in EnemyStateMachineNode._ready().
var bound_state: int = -1

## Called once when this state becomes active.
func on_enter() -> void:
	pass

## Called once when this state is deactivated.
func on_exit() -> void:
	pass

## Per-physics-frame update.  Trigger transitions by calling
## controller._enter_state(EnemyController.EnemyState.X).
func tick(_delta: float) -> void:
	pass
