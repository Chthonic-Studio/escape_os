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

	## Auto-detect the owning EnemyController from the parent node when this
	## state machine is declared as a child in the .tscn scene file.
	if controller == null:
		controller = get_parent() as EnemyController
	assert(controller != null, "EnemyStateMachineNode: must be a child of EnemyController or have controller set before add_child().")

	## Register any state nodes provided by the .tscn scene file.
	_try_register_tscn_children()

	## Create any states that were not provided by the .tscn (fallback).
	if not _state_map.has(int(EnemyController.EnemyState.HUNTING)):
		_register_state(EnemyController.EnemyState.HUNTING, EnemyHuntingState.new())
	if not _state_map.has(int(EnemyController.EnemyState.IDLE)):
		_register_state(EnemyController.EnemyState.IDLE, EnemyIdleState.new())
	if not _state_map.has(int(EnemyController.EnemyState.RESTING)):
		_register_state(EnemyController.EnemyState.RESTING, EnemyRestingState.new())
	if not _state_map.has(int(EnemyController.EnemyState.STUNNED)):
		_register_state(EnemyController.EnemyState.STUNNED, EnemyStunnedState.new())
	if not _state_map.has(int(EnemyController.EnemyState.ATTACKING_DOOR)):
		_register_state(EnemyController.EnemyState.ATTACKING_DOOR, EnemyAttackingDoorState.new())
	if not _state_map.has(int(EnemyController.EnemyState.LURED)):
		_register_state(EnemyController.EnemyState.LURED, EnemyLuredState.new())

## Scans existing children (from .tscn) and registers them by class type.
func _try_register_tscn_children() -> void:
	for child in get_children():
		if not child is EnemyStateBase:
			continue
		if child is EnemyHuntingState and not _state_map.has(int(EnemyController.EnemyState.HUNTING)):
			_register_existing_state(EnemyController.EnemyState.HUNTING, child)
		elif child is EnemyIdleState and not _state_map.has(int(EnemyController.EnemyState.IDLE)):
			_register_existing_state(EnemyController.EnemyState.IDLE, child)
		elif child is EnemyRestingState and not _state_map.has(int(EnemyController.EnemyState.RESTING)):
			_register_existing_state(EnemyController.EnemyState.RESTING, child)
		elif child is EnemyStunnedState and not _state_map.has(int(EnemyController.EnemyState.STUNNED)):
			_register_existing_state(EnemyController.EnemyState.STUNNED, child)
		elif child is EnemyAttackingDoorState and not _state_map.has(int(EnemyController.EnemyState.ATTACKING_DOOR)):
			_register_existing_state(EnemyController.EnemyState.ATTACKING_DOOR, child)
		elif child is EnemyLuredState and not _state_map.has(int(EnemyController.EnemyState.LURED)):
			_register_existing_state(EnemyController.EnemyState.LURED, child)

func _register_state(state: EnemyController.EnemyState, node: EnemyStateBase) -> void:
	node.name = EnemyController.EnemyState.keys()[state]
	node.controller = controller
	node.state_machine = self
	add_child(node)
	_state_map[int(state)] = node

## Registers a state node that already exists as a child (from the .tscn scene).
func _register_existing_state(state: EnemyController.EnemyState, node: EnemyStateBase) -> void:
	node.controller = controller
	node.state_machine = self
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
