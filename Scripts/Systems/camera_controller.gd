class_name CameraController
extends Camera2D

@export var pan_speed: float = 600.0

@export var zoom_speed: float = 0.1

@export var min_zoom: float = 0.2
@export var max_zoom: float = 2.0

var _bounds_node: CameraBounds = null

var _trauma: float = 0.0
const MAX_SHAKE_OFFSET: float = 8.0
const MAX_SHAKE_ROTATION: float = 0.02
const TRAUMA_DECAY: float = 2.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("cameras")
	_bounds_node = _find_camera_bounds()
	EventBus.door_destroyed.connect(_on_door_destroyed)
	EventBus.room_depressurized.connect(_on_room_depressurized)

func _find_camera_bounds() -> CameraBounds:
	var parent: Node = get_parent()
	if parent:
		for child in parent.get_children():
			if child is CameraBounds:
				return child
	return null

func _process(delta: float) -> void:
	var input_dir := Vector2.ZERO

	if Input.is_action_pressed("camera_pan_left"):
		input_dir.x -= 1.0
	if Input.is_action_pressed("camera_pan_right"):
		input_dir.x += 1.0
	if Input.is_action_pressed("camera_pan_up"):
		input_dir.y -= 1.0
	if Input.is_action_pressed("camera_pan_down"):
		input_dir.y += 1.0

	if input_dir != Vector2.ZERO:
		position += input_dir.normalized() * pan_speed * delta / zoom.x

	if _bounds_node:
		_clamp_to_bounds()

	_apply_shake(delta)

func _clamp_to_bounds() -> void:
	var bounds: Rect2 = _bounds_node.get_bounds_rect()
	var viewport_size: Vector2 = get_viewport_rect().size / zoom
	var half_vp: Vector2 = viewport_size * 0.5

	var min_pos: Vector2 = bounds.position + half_vp
	var max_pos: Vector2 = bounds.end - half_vp

	if min_pos.x > max_pos.x:
		position.x = bounds.position.x + bounds.size.x * 0.5
	else:
		position.x = clampf(position.x, min_pos.x, max_pos.x)

	if min_pos.y > max_pos.y:
		position.y = bounds.position.y + bounds.size.y * 0.5
	else:
		position.y = clampf(position.y, min_pos.y, max_pos.y)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			var new_zoom: float = clampf(zoom.x + zoom_speed, min_zoom, max_zoom)
			zoom = Vector2(new_zoom, new_zoom)
			if _bounds_node:
				_clamp_to_bounds()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			var new_zoom: float = clampf(zoom.x - zoom_speed, min_zoom, max_zoom)
			zoom = Vector2(new_zoom, new_zoom)
			if _bounds_node:
				_clamp_to_bounds()
			get_viewport().set_input_as_handled()

func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)

func _apply_shake(delta: float) -> void:
	if _trauma <= 0.0:
		offset = Vector2.ZERO
		rotation = 0.0
		return

	var shake_intensity: float = _trauma * _trauma
	offset.x = MAX_SHAKE_OFFSET * shake_intensity * randf_range(-1.0, 1.0)
	offset.y = MAX_SHAKE_OFFSET * shake_intensity * randf_range(-1.0, 1.0)
	rotation = MAX_SHAKE_ROTATION * shake_intensity * randf_range(-1.0, 1.0)

	_trauma = maxf(_trauma - TRAUMA_DECAY * delta, 0.0)
	if _trauma <= 0.01:
		_trauma = 0.0
		offset = Vector2.ZERO
		rotation = 0.0

func snap_to(world_pos: Vector2) -> void:
	global_position = world_pos
	if _bounds_node:
		_clamp_to_bounds()

func _on_door_destroyed(_door_id: StringName, _global_pos: Vector2) -> void:
	add_trauma(0.4)

func _on_room_depressurized(_room_index: int) -> void:
	add_trauma(0.6)
