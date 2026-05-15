class_name SignalIndicator
extends PanelContainer

## Shows the full signal-type list with the currently active type highlighted.
## All four signals are displayed as a vertical stack; the active one is
## rendered at full opacity with a colored accent, others are dimmed.

@onready var _signal_label: Label = $MarginContainer/HBoxContainer/SignalLabel
@onready var _mode_label: Label = $MarginContainer/HBoxContainer/ModeLabel
@onready var _color_indicator: ColorRect = $MarginContainer/HBoxContainer/ColorIndicator

var _comms_system: CommsSystem = null
var _comms_active: bool = true
var _last_signal_type: StringName = &""

## Programmatically built list rows.
var _list_root: VBoxContainer = null
var _list_rows: Array[Label] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.comms_mode_changed.connect(_on_comms_mode_changed)
	var tree := get_tree()
	tree.node_added.connect(_on_tree_node_added)
	tree.node_removed.connect(_on_tree_node_removed)
	_resolve_comms_system()
	_build_signal_list()
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
	## node_added fires before the node's _ready(), so is_in_group() would be
	## false here (CommsSystem calls add_to_group in _ready()).  Check by class
	## type instead, which is available as soon as the node is instantiated.
	if _comms_system == null and node is CommsSystem:
		_comms_system = node
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

## Builds the signal-list rows as children of the existing HBoxContainer parent.
func _build_signal_list() -> void:
	if not _signal_label:
		return
	## Hide legacy single-line label/mode pair.
	_signal_label.visible = false
	if _mode_label:
		_mode_label.visible = false
	if _color_indicator:
		_color_indicator.visible = false

	## Append a VBoxContainer for the full list.
	var hbox: HBoxContainer = _signal_label.get_parent() as HBoxContainer
	if hbox == null:
		return
	_list_root = VBoxContainer.new()
	_list_root.name = "SignalList"
	hbox.add_child(_list_root)

	for sig_type in CommsSystem.SIGNAL_TYPES:
		var row := Label.new()
		row.name = "Row_" + sig_type
		row.text = CommsSystem.SIGNAL_NAMES.get(sig_type, sig_type.to_upper())
		_list_root.add_child(row)
		_list_rows.append(row)

func _update_display() -> void:
	var signal_type: StringName = &"move"
	if _comms_system:
		signal_type = _comms_system.current_signal_type

	## Update the full signal list rows.
	for i in _list_rows.size():
		var sig := CommsSystem.SIGNAL_TYPES[i]
		var row: Label = _list_rows[i]
		var sig_color: Color = CommsSystem.SIGNAL_COLORS.get(sig, Color.WHITE)
		var sig_name: String = CommsSystem.SIGNAL_NAMES.get(sig, sig.to_upper())
		if sig == signal_type:
			row.text = "> %s <" % sig_name
			row.add_theme_color_override("font_color", sig_color)
			row.modulate.a = 1.0
		else:
			row.text = "  %s" % sig_name
			row.add_theme_color_override("font_color", Color(sig_color.r, sig_color.g, sig_color.b, 0.4))
			row.modulate.a = 1.0

	## Keep the legacy label in sync for any code that reads it externally.
	if _signal_label:
		var color: Color = CommsSystem.SIGNAL_COLORS.get(signal_type, Color.WHITE)
		var name_str: String = CommsSystem.SIGNAL_NAMES.get(signal_type, "UNKNOWN")
		_signal_label.text = "SIGNAL: %s" % name_str
		_signal_label.add_theme_color_override("font_color", color)
	if _color_indicator:
		_color_indicator.color = CommsSystem.SIGNAL_COLORS.get(signal_type, Color.WHITE)
	if _mode_label:
		_mode_label.text = "[Q/E]"
		_mode_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3, 0.9))
