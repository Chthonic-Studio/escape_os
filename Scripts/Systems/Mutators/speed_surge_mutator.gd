class_name SpeedSurgeMutator
extends CorruptionMutator

## Corruption Mutator: Speed Surge
##
## When the first wave of enemies spawns, permanently increases their movement
## speed by 30 % for the duration of the run.

const SPEED_MULTIPLIER: float = 1.30

func _init() -> void:
	mutator_id = &"speed_surge"
	display_name = "Speed Surge"
	description = "Enemies move 30% faster after first spawn."
	stability_tier = 5

func _connect_hooks() -> void:
	EventBus.enemies_have_spawned.connect(_on_enemies_have_spawned)

func _on_run_end() -> void:
	if EventBus.enemies_have_spawned.is_connected(_on_enemies_have_spawned):
		EventBus.enemies_have_spawned.disconnect(_on_enemies_have_spawned)
	## Restore global speed multiplier to its pre-run value.
	GameManager.speed_multiplier = 1.0

func _on_enemies_have_spawned() -> void:
	## Boost is applied to the GameManager global speed multiplier.
	## EnemyController reads GameManager.speed_multiplier every frame.
	GameManager.set_speed_multiplier(GameManager.speed_multiplier * SPEED_MULTIPLIER)
