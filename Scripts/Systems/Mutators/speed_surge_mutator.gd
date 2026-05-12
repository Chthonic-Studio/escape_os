class_name SpeedSurgeMutator
extends CorruptionMutator

## Corruption Mutator: Speed Surge
##
## When the first wave of enemies spawns, permanently increases their movement
## speed by 30 % for the duration of the run.

const SPEED_MULTIPLIER: float = 1.30

## Stores the GameManager speed_multiplier value before the mutator applied its
## boost, so _on_run_end() can restore it instead of hard-coding 1.0.
var _pre_mutator_speed: float = 1.0

func _init() -> void:
	mutator_id = &"speed_surge"
	display_name = "Speed Surge"
	description = "Enemies move 30% faster after first spawn."
	stability_tier = 5

func _on_run_start() -> void:
	## Snapshot the current speed so we can restore it exactly on run end,
	## regardless of any other system that may have modified the multiplier.
	_pre_mutator_speed = GameManager.speed_multiplier

func _connect_hooks() -> void:
	EventBus.enemies_have_spawned.connect(_on_enemies_have_spawned)

func _on_run_end() -> void:
	if EventBus.enemies_have_spawned.is_connected(_on_enemies_have_spawned):
		EventBus.enemies_have_spawned.disconnect(_on_enemies_have_spawned)
	## Restore the multiplier to its pre-run snapshot rather than assuming 1.0.
	GameManager.speed_multiplier = _pre_mutator_speed

func _on_enemies_have_spawned() -> void:
	## Boost is applied to the GameManager global speed multiplier.
	## EnemyController reads GameManager.speed_multiplier every frame.
	GameManager.set_speed_multiplier(GameManager.speed_multiplier * SPEED_MULTIPLIER)
