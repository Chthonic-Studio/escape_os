class_name GameScene
extends Control

## Master layout orchestrator.
## Loads either the arcade (GreyboxLevel) or a story level scene into the
## SubViewport depending on UIManager's current mode.
##
## Also owns the pause menu (Esc key) and coordinates SubViewport pausing so
## that gameplay/AI freezes while the pause menu or other overlays are up.

const ARCADE_LEVEL_SCENE = preload("res://Scenes/greybox_level.tscn")
const PAUSE_MENU_SCENE = preload("res://Scenes/pause_menu.tscn")

@onready var game_viewport: SubViewport = $MarginContainer/HBoxContainer/VBoxContainer/SubViewportContainer/SubViewport

var _pause_menu: PauseMenu = null
var _assessment_screen: Node = null

func _ready() -> void:
	_assessment_screen = UIManager.add_assessment_screen(self)

	_pause_menu = PAUSE_MENU_SCENE.instantiate() as PauseMenu
	add_child(_pause_menu)
	_pause_menu.resume_pressed.connect(_on_pause_resume)
	_pause_menu.main_menu_pressed.connect(_on_pause_main_menu)

	## Auto-dismiss the pause menu when the level ends so the assessment
	## screen is never blocked by a lingering pause overlay.
	GameManager.level_complete.connect(_on_level_complete)

	_load_level_scene()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if (event as InputEventKey).keycode != KEY_ESCAPE:
		return
	## Don't intercept Esc while the assessment screen is showing.
	if _assessment_screen != null and _assessment_screen.visible:
		return
	get_viewport().set_input_as_handled()
	if _pause_menu.visible:
		_hide_pause_menu()
	else:
		_show_pause_menu()

func _show_pause_menu() -> void:
	_pause_menu.visible = true
	## Pause the scene tree so NPCs/enemies freeze; PROCESS_MODE_ALWAYS UI nodes
	## (pause menu, HUD) remain active because they bypass the tree pause.
	get_tree().paused = true

func _hide_pause_menu() -> void:
	_pause_menu.visible = false
	get_tree().paused = false

func _on_pause_resume() -> void:
	_hide_pause_menu()

func _on_pause_main_menu() -> void:
	_hide_pause_menu()
	UIManager.exit_story_mode()
	GameManager.reset()
	get_tree().reload_current_scene()

func _on_level_complete(_escaped: int, _died: int) -> void:
	if _pause_menu != null and _pause_menu.visible:
		_hide_pause_menu()

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
