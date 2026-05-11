class_name NPCStateBase
extends Node

## Base class for all NPC state nodes.
## Each concrete state is a child of NPCStateMachineNode.
##
## Access the owning HumanController via `controller`.
## Access shared state-machine data via `state_machine`.
## (Both are typed as Node to avoid circular-dependency issues at parse time;
##  the actual runtime types are HumanController / NPCStateMachine.)

## Set by NPCStateMachine during _ready() — the owning HumanController.
var controller: HumanController = null

## Set by NPCStateMachine during _ready() — the parent state machine node.
## Declared as Node to prevent GDScript parse-time circular dependency;
## use as NPCStateMachine in practice.
var state_machine: Node = null  # Actually NPCStateMachine

## Called once when this state becomes active.
func on_enter() -> void:
	pass

## Called once when this state is deactivated.
func on_exit() -> void:
	pass

## Per-physics-frame update.  Called by NPCStateMachine.tick().
## Trigger state transitions by calling state_machine.transition_to(State.X).
func tick(_delta: float) -> void:
	pass
