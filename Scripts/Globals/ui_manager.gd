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

var _max_scores: Dictionary = {}

const SCORES_PATH: String = "user://scores.json"

func _ready() -> void:
	_load_scores()

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
