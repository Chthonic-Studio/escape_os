class_name PauseMenu
extends CanvasLayer

## In-game pause menu.
##
## Shown when the player presses Esc during active gameplay.
## Emits resume_pressed or main_menu_pressed so the parent (GameScene)
## can restore/change state.  The pause menu itself does NOT manipulate
## get_tree().paused — GameScene handles that so only the SubViewport
## (game world) is frozen while the UI stays fully responsive.

signal resume_pressed
signal main_menu_pressed

func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

## Close the menu and resume when Esc is pressed again.
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			resume_pressed.emit()

func _on_resume_pressed() -> void:
	resume_pressed.emit()

func _on_main_menu_pressed() -> void:
	main_menu_pressed.emit()
