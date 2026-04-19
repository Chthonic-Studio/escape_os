extends Node

## TimeManager autoload — controls game pause state.

var is_paused: bool = false

signal pause_state_changed(paused: bool)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_pause"):
		toggle_pause()
		get_viewport().set_input_as_handled()

func toggle_pause() -> void:
	set_paused(not is_paused)

func set_paused(paused: bool) -> void:
	if is_paused == paused:
		return
	is_paused = paused
	get_tree().paused = is_paused
	pause_state_changed.emit(is_paused)

func reset() -> void:
	set_paused(false)
