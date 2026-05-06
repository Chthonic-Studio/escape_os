class_name StorySelect
extends CanvasLayer

## Story selection screen.
## Displays all available stories loaded from Resources/Stories/.
## Mouse-over a story card to see its description on the right panel.
## Click a story to proceed to the level selection screen.

const FONT_PATH = "res://Assets/PeaberryMono.ttf"
const STORIES_DIR = "res://Resources/Stories/"

## Colors matching the game's visual style.
const COLOR_BG = Color(0.02, 0.02, 0.05, 1.0)
const COLOR_TITLE = Color(1.0, 0.2, 0.2, 1.0)
const COLOR_NORMAL = Color(0.7, 0.7, 0.7, 1.0)
const COLOR_DIM = Color(0.4, 0.4, 0.4, 1.0)
const COLOR_HOVER = Color(1.0, 0.85, 0.3, 1.0)
const COLOR_DESC = Color(0.6, 0.6, 0.6, 1.0)

var _font: FontFile = null
var _stories: Array[StoryData] = []

@onready var _desc_title: Label = $Background/HBox/RightPanel/VBox/DescTitle
@onready var _desc_text: Label = $Background/HBox/RightPanel/VBox/DescText
@onready var _story_list: VBoxContainer = $Background/HBox/LeftPanel/VBox/StoryList

func _ready() -> void:
	layer = 100
	_font = load(FONT_PATH) as FontFile
	_load_stories()
	_build_story_buttons()

func _load_stories() -> void:
	var dir := DirAccess.open(STORIES_DIR)
	if dir == null:
		push_warning("StorySelect: could not open stories directory '%s'" % STORIES_DIR)
		return
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if fname.ends_with(".tres") and not fname.ends_with(".remap"):
			var path: String = STORIES_DIR + fname
			var res := load(path) as StoryData
			if res:
				_stories.append(res)
		fname = dir.get_next()
	dir.list_dir_end()

func _build_story_buttons() -> void:
	for child in _story_list.get_children():
		child.queue_free()

	if _stories.is_empty():
		var lbl := _make_label("NO STORIES FOUND\nAdd StoryData .tres files to\nres://Resources/Stories/", COLOR_DIM, 10)
		_story_list.add_child(lbl)
		return

	for story_data in _stories:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(220, 40)
		btn.text = story_data.story_name.to_upper()
		if _font:
			btn.add_theme_font_override("font", _font)
		btn.add_theme_font_size_override("font_size", 11)

		## Hover → update description panel.
		btn.mouse_entered.connect(_on_story_hover.bind(story_data))
		## Click → open level select.
		btn.pressed.connect(_on_story_selected.bind(story_data))
		_story_list.add_child(btn)

func _on_story_hover(story_data: StoryData) -> void:
	if _desc_title:
		_desc_title.text = story_data.story_name.to_upper()
	if _desc_text:
		var body: String = story_data.story_description
		if not story_data.story_subtitle.is_empty():
			body = story_data.story_subtitle + "\n\n" + body
		_desc_text.text = body

func _on_story_selected(story_data: StoryData) -> void:
	UIManager.add_story_level_select(get_parent(), story_data)
	queue_free()

func _on_back_pressed() -> void:
	UIManager.add_main_menu(get_parent())
	queue_free()

## Helper to create a plain label.
func _make_label(text: String, color: Color, font_size: int = 10) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", font_size)
	if _font:
		lbl.add_theme_font_override("font", _font)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return lbl
