class_name RestartConfirm
extends CanvasLayer

## Restart confirmation popup shown from the assessment screen.
##
## Emits confirmed or cancelled.  The popup frees itself after either signal.

signal confirmed
signal cancelled

func _ready() -> void:
	layer = 101
	process_mode = Node.PROCESS_MODE_ALWAYS

func _on_confirm_pressed() -> void:
	confirmed.emit()
	queue_free()

func _on_cancel_pressed() -> void:
	cancelled.emit()
	queue_free()
