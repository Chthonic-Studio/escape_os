class_name MetaProgress
extends Resource

## Persistent cross-run progress saved to user://meta.json by SaveManager.

## Total SHV accumulated across all runs (spent SHV is subtracted when purchasing).
var total_shv_banked: float = 0.0

## upgrade_id → current purchase level (int).
var upgrade_levels: Dictionary = {}

## Set of story module IDs that have been unlocked.
var unlocked_modules: Array[StringName] = []

## Total number of completed runs.
var runs_completed: int = 0

func has_upgrade(upgrade_id: StringName) -> bool:
	return upgrade_levels.has(upgrade_id) and upgrade_levels[upgrade_id] > 0

func get_upgrade_level(upgrade_id: StringName) -> int:
	return upgrade_levels.get(upgrade_id, 0)

func purchase_upgrade(upgrade: PermanentUpgrade) -> bool:
	var level: int = get_upgrade_level(upgrade.upgrade_id)
	if level >= upgrade.max_level:
		return false
	if total_shv_banked < upgrade.cost_shv:
		return false
	total_shv_banked -= upgrade.cost_shv
	upgrade_levels[upgrade.upgrade_id] = level + 1
	return true

func unlock_module(module_id: StringName) -> void:
	if module_id not in unlocked_modules:
		unlocked_modules.append(module_id)
