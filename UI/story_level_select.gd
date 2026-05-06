class_name StoryLevelSelect
extends CanvasLayer

## Level and difficulty selection screen for a chosen story.
## Shows levels in order (unlocked / locked), mouse-over shows description
## on the right panel. Difficulty selection affects gameplay variables but
## not the level's ship design.

const FONT_PATH = "res://Assets/PeaberryMono.ttf"

const COLOR_BG = Color(0.02, 0.02, 0.05, 1.0)
const COLOR_TITLE = Color(1.0, 0.2, 0.2, 1.0)
const COLOR_NORMAL = Color(0.7, 0.7, 0.7, 1.0)
const COLOR_DIM = Color(0.4, 0.4, 0.4, 1.0)
const COLOR_HOVER = Color(1.0, 0.85, 0.3, 1.0)
const COLOR_LOCKED = Color(0.3, 0.3, 0.3, 1.0)
const COLOR_SELECTED = Color(0.3, 1.0, 0.5, 1.0)

var _font: FontFile = null
var _story_data: StoryData = null
var _selected_level_index: int = -1
var _selected_difficulty: String = "Easy"

@onready var _story_title_label: Label = $Background/VBox/TopMargin/StoryTitleLabel
@onready var _level_list: VBoxContainer = $Background/VBox/HBox/LeftPanel/InnerVBox/ScrollContainer/LevelList
@onready var _desc_title: Label = $Background/VBox/HBox/RightPanel/Margin/VBox/DescTitle
@onready var _desc_text: Label = $Background/VBox/HBox/RightPanel/Margin/VBox/DescText
@onready var _start_button: Button = $Background/VBox/BottomRow/BottomMargin/BottomButtons/StartButton
@onready var _diff_buttons: HBoxContainer = $Background/VBox/DifficultyRow/DiffMargin/DiffInner/DifficultyButtons

func _ready() -> void:
	layer = 100
	_font = load(FONT_PATH) as FontFile

func setup(story_data: StoryData) -> void:
	_story_data = story_data
	## Update UI after nodes are ready.
	call_deferred("_populate_ui")

func _populate_ui() -> void:
	if _story_title_label:
		_story_title_label.text = ("═══ %s ═══" % _story_data.story_name).to_upper()

	_build_level_buttons()
	_build_difficulty_buttons()

	if _start_button:
		_start_button.disabled = true

func _build_level_buttons() -> void:
	if _level_list == null:
		return
	for child in _level_list.get_children():
		child.queue_free()

	for i in range(_story_data.levels.size()):
		var lvl: StoryLevelData = _story_data.levels[i]
		var unlocked: bool = UIManager.is_level_unlocked(_story_data, i)

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(200, 36)
		if _font:
			btn.add_theme_font_override("font", _font)
		btn.add_theme_font_size_override("font_size", 10)

		if unlocked:
			btn.text = "%d. %s" % [i + 1, lvl.level_name.to_upper()]
			btn.disabled = false
			btn.mouse_entered.connect(_on_level_hover.bind(i))
			btn.pressed.connect(_on_level_selected.bind(i))
		else:
			btn.text = "%d. [ LOCKED ]" % (i + 1)
			btn.disabled = true
			if _font:
				btn.add_theme_color_override("font_disabled_color", COLOR_LOCKED)

		_level_list.add_child(btn)

func _build_difficulty_buttons() -> void:
	if _diff_buttons == null:
		return
	for child in _diff_buttons.get_children():
		child.queue_free()

	for diff_name in UIManager.DIFFICULTY_CONFIGS.keys():
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(80, 32)
		btn.text = diff_name.to_upper()
		if _font:
			btn.add_theme_font_override("font", _font)
		btn.add_theme_font_size_override("font_size", 10)
		btn.toggle_mode = true
		btn.button_pressed = (diff_name == _selected_difficulty)
		btn.pressed.connect(_on_difficulty_selected.bind(diff_name))
		_diff_buttons.add_child(btn)

func _on_level_hover(level_index: int) -> void:
	if _story_data == null:
		return
	var lvl: StoryLevelData = _story_data.levels[level_index]
	if _desc_title:
		_desc_title.text = lvl.level_name.to_upper()
	if _desc_text:
		_desc_text.text = lvl.level_description

func _on_level_selected(level_index: int) -> void:
	_selected_level_index = level_index
	_update_start_button_state()
	_refresh_level_button_colors()

func _on_difficulty_selected(difficulty_name: String) -> void:
	_selected_difficulty = difficulty_name
	## Toggle-off all other difficulty buttons.
	for btn in _diff_buttons.get_children():
		if btn is Button:
			btn.set_pressed_no_signal(btn.text.to_lower() == difficulty_name.to_lower())

func _update_start_button_state() -> void:
	if _start_button:
		_start_button.disabled = (_selected_level_index < 0)

func _refresh_level_button_colors() -> void:
	var buttons := _level_list.get_children()
	for i in range(buttons.size()):
		var btn: Button = buttons[i]
		if btn is Button and not btn.disabled:
			if i == _selected_level_index:
				btn.add_theme_color_override("font_color", COLOR_SELECTED)
			else:
				btn.remove_theme_color_override("font_color")

func _on_start_pressed() -> void:
	if _story_data == null or _selected_level_index < 0:
		return
	## Validate path before closing the screen so the player isn't stranded if
	## the level resource is misconfigured.
	var lvl_data: StoryLevelData = _story_data.levels[_selected_level_index]
	if lvl_data.level_scene_path.is_empty():
		push_warning("StoryLevelSelect: level_scene_path is empty for level %d — cannot start." % _selected_level_index)
		return
	UIManager.start_story_level(_story_data, _selected_level_index, _selected_difficulty)
	queue_free()

func _on_back_pressed() -> void:
	UIManager.add_story_select(get_parent())
	queue_free()
