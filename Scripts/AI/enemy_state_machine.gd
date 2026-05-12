class_name EnemyStateMachineNode
extends Node

## Thin router node — delegates tick() to the active enemy state node.
## EnemyController owns this as a child and calls tick() explicitly.
## current_state lives on EnemyController (preserved for EnemyDirector reads).

## EnemyController reference — set before add_child().
var controller: EnemyController = null

var _active_state: EnemyStateBase = null

## EnemyController.EnemyState (int) → EnemyStateBase node.
var _state_map: Dictionary = {}

func _ready() -> void:
	set_physics_process(false)
	set_process(false)
	assert(controller != null, "EnemyStateMachineNode: controller must be set before add_child().")

	_register_state(EnemyController.EnemyState.HUNTING,       EnemyHuntingState.new())
	_register_state(EnemyController.EnemyState.IDLE,          EnemyIdleState.new())
	_register_state(EnemyController.EnemyState.RESTING,       EnemyRestingState.new())
	_register_state(EnemyController.EnemyState.STUNNED,       EnemyStunnedState.new())
	_register_state(EnemyController.EnemyState.ATTACKING_DOOR, EnemyAttackingDoorState.new())
	_register_state(EnemyController.EnemyState.LURED,         EnemyLuredState.new())

func _register_state(state: EnemyController.EnemyState, node: EnemyStateBase) -> void:
	node.name = EnemyController.EnemyState.keys()[state]
	node.controller = controller
	node.state_machine = self
	add_child(node)
	_state_map[int(state)] = node

## Called by EnemyController._physics_process().
func tick(delta: float) -> void:
	if _active_state != null:
		_active_state.tick(delta)

## Activate a new state node.  Called by EnemyController._enter_state().
func activate_state(state: EnemyController.EnemyState) -> void:
	if _active_state != null:
		_active_state.on_exit()
	_active_state = _state_map.get(int(state), null) as EnemyStateBase
	if _active_state != null:
		_active_state.on_enter()

## Returns the state node for the given enum value (null if not registered).
func get_state(state: EnemyController.EnemyState) -> EnemyStateBase:
	return _state_map.get(int(state), null) as EnemyStateBase
