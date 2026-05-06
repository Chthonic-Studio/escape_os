extends Node

## Handles UI state and scene management.

var selected_difficulty: String = "res://Resources/Levels/easy.tres"

const DIFFICULTY_CONFIGS: Dictionary = {
	"Easy": "res://Resources/Levels/easy.tres",
	"Medium": "res://Resources/Levels/medium.tres",
	"Hard": "res://Resources/Levels/hard.tres",
}

const ASSESSMENT_SCENE = preload("res://Scenes/assessment_screen.tscn")
const MAIN_MENU_SCENE = preload("res://Scenes/main_menu.tscn")
const LOG_ENTRY_SCENE = preload("res://Scenes/log_entry.tscn")
const STORY_SELECT_SCENE = preload("res://Scenes/story_select.tscn")
const STORY_LEVEL_SELECT_SCENE = preload("res://Scenes/story_level_select.tscn")

var _max_scores: Dictionary = {}

const SCORES_PATH: String = "user://scores.json"
const STORY_PROGRESS_PATH: String = "user://story_progress.json"

## Keeps a reference so we can show/hide without re-instantiation.
var _loading_screen: LoadingScreen = null

## ── story mode state ────────────────────────────────────────────────────────

## True while the player is running a story level.
var is_story_mode: bool = false
## Set to the level .tscn path before reload; cleared once consumed by game_scene.
var pending_story_level_scene: String = ""
## The last loaded story level scene path — used to restart on scene reload.
var active_story_level_scene: String = ""
## StoryData and level index for the active story (used for progress saving).
var active_story_data: StoryData = null
var active_story_level_index: int = -1

## Per-story unlock progress: story_id (String) → Array[bool] (one per level).
var _story_progress: Dictionary = {}

func _ready() -> void:
	_load_scores()
	_load_story_progress()
	EventBus.game_start_requested.connect(_on_game_start_requested)
	EventBus.ship_generated.connect(_on_ship_generated)
	GameManager.level_complete.connect(_on_level_complete)

## Show the loading screen when a new level starts generating.
func _on_game_start_requested() -> void:
	_show_loading_screen()

func _show_loading_screen() -> void:
	if _loading_screen != null and is_instance_valid(_loading_screen):
		_loading_screen.visible = true
	elif get_tree() != null:
		_loading_screen = LoadingScreen.new()
		get_tree().root.add_child(_loading_screen)

## Hide the loading screen once the ship is fully generated.
func _on_ship_generated(_pod_positions: Array) -> void:
	## Wait one frame so all synchronous ship_generated handlers (such as
	## pathfinding warm-up) finish before the overlay is removed.
	if get_tree() != null:
		await get_tree().process_frame
	## LoadingScreen also hides itself via its own signal handler; this is a safety net.
	if _loading_screen != null and is_instance_valid(_loading_screen):
		_loading_screen.visible = false

## Called when any level completes; saves story progress if in story mode.
func _on_level_complete(_escaped: int, _died: int) -> void:
	if is_story_mode and active_story_data != null and active_story_level_index >= 0:
		_unlock_next_story_level()

## ── difficulty ──────────────────────────────────────────────────────────────

func set_difficulty(difficulty_name: String) -> void:
	if DIFFICULTY_CONFIGS.has(difficulty_name):
		selected_difficulty = DIFFICULTY_CONFIGS[difficulty_name]

func get_current_level_config() -> LevelConfig:
	return load(selected_difficulty) as LevelConfig

func get_current_difficulty_name() -> String:
	for key in DIFFICULTY_CONFIGS:
		if DIFFICULTY_CONFIGS[key] == selected_difficulty:
			return key
	return "Easy"

## ── scores ──────────────────────────────────────────────────────────────────

func update_max_score(difficulty_name: String, shv_value: float) -> void:
	if not DIFFICULTY_CONFIGS.has(difficulty_name):
		return
	var raw = _max_scores.get(difficulty_name, -INF)
	var current_best: float = float(raw) if (raw is float or raw is int) else -INF
	if shv_value > current_best:
		_max_scores[difficulty_name] = shv_value
		_save_scores()

func get_max_score(difficulty_name: String) -> Variant:
	if _max_scores.has(difficulty_name):
		return _max_scores[difficulty_name]
	return null

func _save_scores() -> void:
	var file := FileAccess.open(SCORES_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_max_scores))
		file.close()

func _load_scores() -> void:
	if not FileAccess.file_exists(SCORES_PATH):
		return
	var file := FileAccess.open(SCORES_PATH, FileAccess.READ)
	if not file:
		return
	var text: String = file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		return
	_max_scores.clear()
	for key in DIFFICULTY_CONFIGS.keys():
		if not parsed.has(key):
			continue
		var raw = parsed[key]
		if raw is float or raw is int:
			var val: float = float(raw)
			if is_finite(val):
				_max_scores[key] = val

## ── story mode navigation ───────────────────────────────────────────────────

## Begins a story level: sets up pending state, shows loading screen, reloads scene.
func start_story_level(story_data: StoryData, level_index: int, difficulty_name: String) -> void:
	var lvl_data: StoryLevelData = story_data.levels[level_index]
	if lvl_data.level_scene_path.is_empty():
		push_error("UIManager.start_story_level: level_scene_path is empty for '%s' level %d" % [story_data.story_name, level_index])
		return

	set_difficulty(difficulty_name)
	is_story_mode = true
	pending_story_level_scene = lvl_data.level_scene_path
	active_story_level_scene = lvl_data.level_scene_path
	active_story_data = story_data
	active_story_level_index = level_index

	_show_loading_screen()
	EventBus.story_level_started.emit(story_data.story_id, level_index)
	get_tree().call_deferred("reload_current_scene")

## Returns the pending story level scene path and clears it (consume once).
func consume_pending_story_level() -> String:
	var path: String = pending_story_level_scene
	pending_story_level_scene = ""
	return path

## Clears all story mode state and returns to arcade mode.
func exit_story_mode() -> void:
	is_story_mode = false
	pending_story_level_scene = ""
	active_story_level_scene = ""
	active_story_data = null
	active_story_level_index = -1

## Adds the story selection screen overlay to the given parent node.
func add_story_select(parent: Node) -> Node:
	var scene := STORY_SELECT_SCENE.instantiate()
	scene.name = "StorySelect"
	parent.add_child(scene)
	return scene

## Adds the story level selection overlay for the given StoryData.
func add_story_level_select(parent: Node, story_data: StoryData) -> Node:
	var scene := STORY_LEVEL_SELECT_SCENE.instantiate()
	scene.name = "StoryLevelSelect"
	if scene.has_method("setup"):
		scene.setup(story_data)
	parent.add_child(scene)
	return scene

## ── story progress ──────────────────────────────────────────────────────────

## Returns true if a given level index in a story is unlocked.
func is_level_unlocked(story_data: StoryData, level_index: int) -> bool:
	if level_index == 0:
		return true
	var sid: String = str(story_data.story_id)
	if not _story_progress.has(sid):
		return false
	var unlocks: Array = _story_progress[sid]
	return level_index < unlocks.size() and unlocks[level_index]

## Unlocks the level immediately after the one that was just completed.
func _unlock_next_story_level() -> void:
	if active_story_data == null:
		return
	var sid: String = str(active_story_data.story_id)
	var count: int = active_story_data.levels.size()
	if not _story_progress.has(sid):
		_story_progress[sid] = []
	var unlocks: Array = _story_progress[sid]
	## Grow the array to cover all levels, first level is always unlocked.
	while unlocks.size() < count:
		unlocks.append(false)
	unlocks[0] = true
	## Unlock the completed level so it shows as "done".
	unlocks[active_story_level_index] = true
	## Unlock the next level.
	var next: int = active_story_level_index + 1
	if next < count:
		unlocks[next] = true
	_story_progress[sid] = unlocks
	_save_story_progress()

func _save_story_progress() -> void:
	var file := FileAccess.open(STORY_PROGRESS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_story_progress))
		file.close()

func _load_story_progress() -> void:
	if not FileAccess.file_exists(STORY_PROGRESS_PATH):
		return
	var file := FileAccess.open(STORY_PROGRESS_PATH, FileAccess.READ)
	if not file:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		_story_progress = parsed

## ── UI helpers ──────────────────────────────────────────────────────────────

func add_assessment_screen(parent: Node) -> Node:
	var assessment := ASSESSMENT_SCENE.instantiate()
	assessment.name = "AssessmentScreen"
	parent.add_child(assessment)
	return assessment

func add_main_menu(parent: Node) -> Node:
	var menu := MAIN_MENU_SCENE.instantiate()
	menu.name = "MainMenu"
	parent.add_child(menu)
	return menu

func create_log_entry() -> Label:
	return LOG_ENTRY_SCENE.instantiate()

