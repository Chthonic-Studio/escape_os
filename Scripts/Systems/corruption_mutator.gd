class_name CorruptionMutator
extends Resource

## Base class for Kernel Corruption mutators.
##
## A CorruptionMutator is a composable modifier injected into a run based on
## the current Stability level.  Subclasses override _connect_hooks() to attach
## EventBus listeners, and _on_run_start/_on_run_end for lifecycle callbacks.
##
## Usage (in RunManager):
##   mutator._on_run_start()
##   mutator._connect_hooks()
##   …run plays…
##   mutator._on_run_end()
##
## Mutators must disconnect all listeners in _on_run_end() to avoid leaks
## across runs.

@export_category("Identity")
@export var mutator_id: StringName = &""
@export var display_name: String = "Unknown Mutator"
@export var description: String = ""

@export_category("Activation")
## The mutator is only active when run stability_level ≤ this tier.
## Tier 10 = always active; tier 1 = only active at maximum corruption.
@export_range(1, 10) var stability_tier: int = 5

## Override in subclasses — called once when the run begins.
func _on_run_start() -> void:
	pass

## Override in subclasses — connect EventBus signals here.
func _connect_hooks() -> void:
	pass

## Override in subclasses — disconnect all hooks here to prevent leaks.
func _on_run_end() -> void:
	pass
