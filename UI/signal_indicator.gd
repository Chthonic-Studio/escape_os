class_name SignalIndicator
extends PanelContainer

## Shows current comms signal type.

@onready var _signal_label: Label = $MarginContainer/HBoxContainer/SignalLabel
@onready var _mode_label: Label = $MarginContainer/HBoxContainer/ModeLabel
@onready var _color_indicator: ColorRect = $MarginContainer/HBoxContainer/ColorIndicator

var _comms_system: CommsSystem = null
var _comms_active: bool = false
var _last_signal_type: StringName = &""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.comms_mode_changed.connect(_on_comms_mode_changed)
	var tree := get_tree()
	tree.node_added.connect(_on_tree_node_added)
	tree.node_removed.connect(_on_tree_node_removed)
	_resolve_comms_system()
	_update_display()

func _exit_tree() -> void:
	var tree := get_tree()
	if tree.node_added.is_connected(_on_tree_node_added):
		tree.node_added.disconnect(_on_tree_node_added)
	if tree.node_removed.is_connected(_on_tree_node_removed):
		tree.node_removed.disconnect(_on_tree_node_removed)

func _resolve_comms_system() -> void:
	_comms_system = get_tree().get_first_node_in_group("comms_system") as CommsSystem
	if _comms_system:
		_last_signal_type = _comms_system.current_signal_type
	else:
		_last_signal_type = &""

func _on_tree_node_added(node: Node) -> void:
	if _comms_system == null and node.is_in_group("comms_system"):
		_comms_system = node as CommsSystem
		if _comms_system:
			_last_signal_type = _comms_system.current_signal_type
			_update_display()

func _on_tree_node_removed(node: Node) -> void:
	if node == _comms_system:
		_comms_system = null
		_last_signal_type = &""
		_update_display()

func _process(_delta: float) -> void:
	if _comms_system and _comms_system.current_signal_type != _last_signal_type:
		_last_signal_type = _comms_system.current_signal_type
		_update_display()

func _on_comms_mode_changed(active: bool) -> void:
	_comms_active = active
	_update_display()

func _update_display() -> void:
	if not _signal_label or not _mode_label or not _color_indicator:
		return

	var signal_type: StringName = &"move"
	if _comms_system:
		signal_type = _comms_system.current_signal_type

	var color: Color = CommsSystem.SIGNAL_COLORS.get(signal_type, Color.WHITE)
	var signal_name: String = CommsSystem.SIGNAL_NAMES.get(signal_type, "UNKNOWN")

	_signal_label.text = "SIGNAL: %s" % signal_name
	_signal_label.add_theme_color_override("font_color", color)
	_color_indicator.color = color

	if _comms_active:
		_mode_label.text = "[ACTIVE]"
		_mode_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3, 0.9))
	else:
		_mode_label.text = "[E]COMMS"
		_mode_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 0.7))
