class_name DoorSystem
extends Node2D

@export var sprite: AnimatedSprite2D
@export var is_open: bool = true

var is_locked: bool = false

var is_destroyed: bool = false

var room_a_index: int = -1
var room_b_index: int = -1

@onready var _collider: CollisionShape2D = $static_body/CollisionShape2D
@onready var _static_body: StaticBody2D = $static_body

func _ready() -> void:
	add_to_group("doors")
	_update_state(true)

func toggle_door() -> void:
	if is_locked or is_destroyed:
		return
	is_open = not is_open
	_update_state(false)
	
	EventBus.door_toggled.emit(name, is_open)

func force_close() -> void:
	if is_destroyed or not is_open:
		return
	is_open = false
	_update_state(false)
	EventBus.door_toggled.emit(name, is_open)

func force_open() -> void:
	if is_open:
		return
	is_open = true
	_update_state(false)
	EventBus.door_toggled.emit(name, is_open)

func lock() -> void:
	if is_destroyed:
		return
	is_locked = true

func unlock() -> void:
	is_locked = false

func _update_state(instant: bool = false) -> void:
	if _static_body:
		_static_body.set_collision_layer_value(1, not is_open)
		_static_body.set_collision_layer_value(2, true)
	
	if is_open:
		sprite.play("open")
		if instant:
			var last_frame: int = sprite.sprite_frames.get_frame_count("open") - 1
			sprite.set_frame_and_progress(last_frame, 1.0)
	else:
		sprite.play("close")
		if instant:
			var last_frame: int = sprite.sprite_frames.get_frame_count("close") - 1
			sprite.set_frame_and_progress(last_frame, 1.0)

## Destroy the door permanently (called by enemies breaking through).
func destroy() -> void:
	if is_destroyed:
		return
	is_destroyed = true
	is_locked = false
	is_open = true
	if _static_body:
		_static_body.set_collision_layer_value(1, false)
		_static_body.set_collision_layer_value(2, false)
	sprite.play("open")
	sprite.modulate = Color(1.0, 0.3, 0.3, 0.5)
	EventBus.door_toggled.emit(name, true)
	EventBus.door_destroyed.emit(name, global_position)
