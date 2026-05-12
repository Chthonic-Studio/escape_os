extends Node

## RunManager — autoload that owns the current run lifecycle.
##
## Responsibilities:
##  • Create / resume RunData at run-start.
##  • Activate CorruptionMutators appropriate for the stability level.
##  • Route the game to either a procedural level (ShipGenerator) or a static
##    story level (UIManager.pending_story_level_scene) after each level.
##  • Bank SHV and sync story modules to MetaProgress on run-end.

## The live run state; null between runs.
var current_run: RunData = null

## All registered mutators (exposed for UI inspection).
var all_mutators: Array[CorruptionMutator] = []

func _ready() -> void:
	_build_mutator_pool()
	GameManager.level_complete.connect(_on_level_complete)

## Convenience wrapper: starts a new run with default parameters.
func start_run() -> void:
	start_new_run()

## Creates a new run and starts it.
func start_new_run(stability_level: int = 1, seed_value: int = -1) -> void:
	current_run = RunData.new()
	current_run.run_seed = seed_value if seed_value >= 0 else randi()
	current_run.stability_level = clampi(stability_level, 1, 10)
	current_run.is_active = true
	_select_mutators()
	_activate_mutators()
	SaveManager.save_run(current_run)
	EventBus.run_started.emit(current_run)

## Resumes an in-progress run from a saved RunData.
func resume_run(saved: RunData) -> void:
	current_run = saved
	_select_mutators()
	_activate_mutators()
	EventBus.run_started.emit(current_run)

## Returns the stability level to use for the next run.
func next_stability_level() -> int:
	if current_run != null:
		return current_run.stability_level
	return 1

## Called when a level completes (player escaped or all NPCs dead).
func _on_level_complete(_escaped: int, _died: int) -> void:
	if current_run == null:
		return
	current_run.levels_cleared += 1
	## TODO: calculate and add SHV from level performance.
	SaveManager.save_run(current_run)

## Ends the current run and banks progress to MetaProgress.
func end_run() -> void:
	if current_run == null:
		return
	_deactivate_mutators()
	var meta: MetaProgress = SaveManager.load_meta_progress()
	meta.total_shv_banked += current_run.shv_earned
	meta.runs_completed += 1
	for module_id in current_run.story_modules_unlocked:
		meta.unlock_module(module_id)
	SaveManager.save_meta_progress(meta)
	current_run.is_active = false
	SaveManager.save_run(current_run)
	EventBus.run_ended.emit(current_run)
	current_run = null

## Returns true when a run is currently active.
func is_run_active() -> bool:
	return current_run != null and current_run.is_active

## ── Internal ────────────────────────────────────────────────────────────────

func _build_mutator_pool() -> void:
	all_mutators.append(PacketLossMutator.new())
	all_mutators.append(CrowdingMutator.new())
	all_mutators.append(SpeedSurgeMutator.new())
	all_mutators.append(DoorGlitchMutator.new())

func _select_mutators() -> void:
	if current_run == null:
		return
	current_run.active_mutators.clear()
	for mutator in all_mutators:
		## Mutator is active when stability_level <= stability_tier
		## (lower stability = more corruption = more mutators active).
		if current_run.stability_level <= mutator.stability_tier:
			current_run.active_mutators.append(mutator)

func _activate_mutators() -> void:
	if current_run == null:
		return
	for mutator in current_run.active_mutators:
		mutator._on_run_start()
		mutator._connect_hooks()

func _deactivate_mutators() -> void:
	if current_run == null:
		return
	for mutator in current_run.active_mutators:
		mutator._on_run_end()
