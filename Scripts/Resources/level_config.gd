class_name LevelConfig
extends Resource

@export_category("Difficulty")
## Overall difficulty from 0.0 (easiest) to 1.0 (hardest).
@export_range(0.0, 1.0, 0.05) var difficulty: float = 0.5

const DEFAULT_NPC_COUNT: int = 20

@export_category("Escape Pods")
@export var min_escape_pods: int = 2
@export var max_escape_pods: int = 5

@export_category("Enemies")
## Max enemies alive at once.
@export var max_enemies_alive: int = 2
@export var enemy_respawn_interval: float = 20.0
@export var enemy_spawn_delay: float = 4.0

@export_category("NPCs")
@export var npc_count: int = 20

## Returns the number of escape pods for the current difficulty.
func get_escape_pod_count() -> int:
	var range_size: int = max_escape_pods - min_escape_pods
	var pod_count: int = max_escape_pods - roundi(difficulty * range_size)
	return clampi(pod_count, min_escape_pods, max_escape_pods)

func get_max_enemies_alive() -> int:
	return max_enemies_alive

## Returns the interval in seconds between individual enemy spawns.
func get_respawn_interval() -> float:
	return enemy_respawn_interval * lerpf(1.0, 0.6, difficulty)
