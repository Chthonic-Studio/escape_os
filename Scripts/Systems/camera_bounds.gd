@tool
class_name CameraBounds
extends Node2D

## A visual bounding box for the camera. Editable in the Godot editor.

@export var bounds_size: Vector2 = Vector2(1600, 800)
@export var bounds_color: Color = Color(0.2, 0.8, 1.0, 0.3)
@export var show_at_runtime: bool = false

func get_bounds_rect() -> Rect2:
	return Rect2(global_position, bounds_size)

func _draw() -> void:
	if Engine.is_editor_hint() or show_at_runtime:
		draw_rect(Rect2(Vector2.ZERO, bounds_size), bounds_color, true)
		draw_rect(Rect2(Vector2.ZERO, bounds_size), Color(bounds_color.r, bounds_color.g, bounds_color.b, 0.8), false, 2.0)

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()
