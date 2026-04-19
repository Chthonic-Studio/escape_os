class_name HVTEntry
extends Control

## HVT sidebar entry with locate button.

@onready var _name_label: Label = $MarginContainer/VBoxContainer/NameLabel
@onready var _status_label: Label = $MarginContainer/VBoxContainer/StatusLabel
@onready var _locate_btn: Button = $MarginContainer/VBoxContainer/LocateButton
@onready var _portrait: Sprite2D = $MarginContainer/VBoxContainer/Portrait

const CLASS_COLOR_SHADER = preload("res://Assets/Shaders/class_color_swap.gdshader")

var tracked_npc: Node = null

var is_dead: bool = false

var _flash_timer: float = 0.0
const FLASH_DURATION: float = 1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _locate_btn:
		_locate_btn.pressed.connect(_on_locate_pressed)

func setup(npc: Node) -> void:
	tracked_npc = npc
	if npc is HumanController and npc.npc_class:
		if _name_label:
			_name_label.text = npc.npc_class.display_name.to_upper()
		if _portrait and CLASS_COLOR_SHADER:
			var mat: ShaderMaterial = _portrait.material as ShaderMaterial
			if mat == null or mat.shader != CLASS_COLOR_SHADER:
				mat = ShaderMaterial.new()
				mat.shader = CLASS_COLOR_SHADER
				_portrait.material = mat
			mat.set_shader_parameter("class_color", npc.npc_class.class_color)
	_update_status()

func _process(delta: float) -> void:
	_update_status()

	if _flash_timer > 0.0:
		_flash_timer -= delta
		var t: float = 1.0 - (_flash_timer / FLASH_DURATION)
		var flash_color: Color = Color.WHITE.lerp(Color(1.0, 0.2, 0.2, 1.0), t)
		if _name_label:
			_name_label.add_theme_color_override("font_color", flash_color)
		if _status_label:
			_status_label.add_theme_color_override("font_color", flash_color)
		if _flash_timer <= 0.0:
			_flash_timer = 0.0

func _update_status() -> void:
	if not _status_label:
		return

	if not is_instance_valid(tracked_npc):
		if not is_dead:
			is_dead = true
			_status_label.text = "TERMINATED"
			_status_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2, 1.0))
			_name_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2, 1.0))
			_flash_timer = FLASH_DURATION
			if _locate_btn:
				_locate_btn.disabled = true
		return

	if tracked_npc is HumanController:
		var state: NPCStateMachine.State = tracked_npc.state_machine.current_state
		match state:
			NPCStateMachine.State.DEAD:
				_status_label.text = "TERMINATED"
				if not is_dead:
					is_dead = true
					_status_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2, 1.0))
					if _name_label:
						_name_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2, 1.0))
					_flash_timer = FLASH_DURATION
					if _locate_btn:
						_locate_btn.disabled = true
			NPCStateMachine.State.PANICKING:
				_status_label.text = "PANIC"
				_status_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2, 0.9))
			NPCStateMachine.State.FLEEING_TO_POD:
				_status_label.text = "FLEEING"
				_status_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0, 0.9))
			NPCStateMachine.State.HIDING:
				_status_label.text = "HIDING"
				_status_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.9))
			NPCStateMachine.State.MOVING_TO_SIGNAL:
				_status_label.text = "MOVING"
				_status_label.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0, 0.9))
			_:
				_status_label.text = "ACTIVE"
				_status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3, 0.9))

		if not is_dead and _name_label:
			_name_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3, 0.9))

func _on_locate_pressed() -> void:
	if not is_instance_valid(tracked_npc):
		return
	var cameras := get_tree().get_nodes_in_group("cameras")
	for cam in cameras:
		if cam is CameraController:
			cam.snap_to(tracked_npc.global_position)
			return
	var viewport: Viewport = tracked_npc.get_viewport()
	if viewport:
		var cam := viewport.get_camera_2d()
		if cam is CameraController:
			cam.snap_to(tracked_npc.global_position)
