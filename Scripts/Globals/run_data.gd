class_name RunData
extends Resource

## Transient resource that exists for the duration of a single run.
## Created by RunManager at run-start; serialised by SaveManager after each level.

## Random seed used for this run's procedural generation.
var run_seed: int = 0

## Kernel Corruption level: 1 (minimal instability) → 10 (full chaos).
var stability_level: int = 1

## Accumulated SHV earned this run (not yet banked to MetaProgress).
var shv_earned: float = 0.0

## Number of levels cleared in this run.
var levels_cleared: int = 0

## Mutator instances active for this run (subset of all available mutators).
var active_mutators: Array[CorruptionMutator] = []

## Story module IDs unlocked during this run (synced to MetaProgress on end).
var story_modules_unlocked: Array[StringName] = []

## True if the player has a resumable mid-run save.
var is_active: bool = false

func add_shv(amount: float) -> void:
	shv_earned += amount

func to_dict() -> Dictionary:
	var mutator_ids: Array[StringName] = []
	for m in active_mutators:
		mutator_ids.append(m.mutator_id)
	return {
		"run_seed": run_seed,
		"stability_level": stability_level,
		"shv_earned": shv_earned,
		"levels_cleared": levels_cleared,
		"active_mutator_ids": mutator_ids,
		"story_modules_unlocked": story_modules_unlocked,
		"is_active": is_active,
	}

func from_dict(d: Dictionary) -> void:
	run_seed = int(d.get("run_seed", 0))
	stability_level = int(d.get("stability_level", 1))
	shv_earned = float(d.get("shv_earned", 0.0))
	levels_cleared = int(d.get("levels_cleared", 0))
	story_modules_unlocked = Array(d.get("story_modules_unlocked", []), TYPE_STRING_NAME, &"", null)
	is_active = bool(d.get("is_active", false))
	## active_mutators are re-hydrated by RunManager using the stored IDs.
