class_name GameScene
extends Control

## Master layout orchestrator.
## Loads either the arcade (GreyboxLevel) or a story level scene into the
## SubViewport depending on UIManager's current mode.

const ARCADE_LEVEL_SCENE = preload("res://Scenes/greybox_level.tscn")

@onready var game_viewport: SubViewport = $MarginContainer/HBoxContainer/VBoxContainer/SubViewportContainer/SubViewport

func _ready() -> void:
	UIManager.add_assessment_screen(self)
	_load_level_scene()

func _load_level_scene() -> void:
	## Check for a pending story level first (initial load), then fall back to
	## the active story level (restart), then default to arcade mode.
	var story_scene_path := UIManager.consume_pending_story_level()
	if story_scene_path.is_empty() and UIManager.is_story_mode:
		story_scene_path = UIManager.active_story_level_scene

	if not story_scene_path.is_empty():
		## Story mode: load the designed level scene.
		var packed := load(story_scene_path) as PackedScene
		if packed:
			var level := packed.instantiate()
			game_viewport.add_child(level)
			## Loading screen is already visible from before the reload.
		else:
			push_error("GameScene: failed to load story level scene '%s'" % story_scene_path)
			## Fall back gracefully to arcade mode.
			_load_arcade_level()
	else:
		_load_arcade_level()

func _load_arcade_level() -> void:
	var level := ARCADE_LEVEL_SCENE.instantiate()
	game_viewport.add_child(level)
	UIManager.add_main_menu(self)
