class_name RadialMenu
extends Node

## Radial specialist command menu.
## Singleton/autoload pattern — call RadialMenu.open_for(npc, screen_pos)
## to show the command wheel.

## The active menu overlay if one is open.
var _active_menu: Control = null

## Opens the radial menu for a specialist NPC at the given screen position.
## If a menu is already open it is closed first.
func open_for(npc: Node, screen_pos: Vector2) -> void:
	close()
	if not is_instance_valid(npc):
		return

	var overlay := _build_menu(npc, screen_pos)
	## Add the overlay to the current viewport so it draws on top.
	var root := get_tree().root
	root.add_child(overlay)
	_active_menu = overlay

## Closes the radial menu if it is open.
func close() -> void:
	if is_instance_valid(_active_menu):
		_active_menu.queue_free()
	_active_menu = null

## Builds the menu Control tree for a given NPC.
func _build_menu(npc: Node, screen_pos: Vector2) -> Control:
	var overlay := Control.new()
	overlay.name = "RadialMenuOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100

	## Panel background.
	var panel := PanelContainer.new()
	panel.name = "MenuPanel"
	overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	## Title.
	var title := Label.new()
	title.text = "COMMAND"
	title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1.0))
	vbox.add_child(title)

	## Options.
	var options: Array[Dictionary] = [
		{ "label": "Move Here", "command": &"move" },
		{ "label": "Hold Position", "command": &"hold" },
	]
	## Dynamically expose specialist class commands if available.
	if npc.has_method("get_specialist_commands"):
		for cmd in npc.get_specialist_commands():
			options.append(cmd)

	for opt in options:
		var btn := Button.new()
		btn.text = opt["label"]
		var cmd: StringName = opt["command"]
		btn.pressed.connect(_on_command_selected.bind(npc, cmd))
		vbox.add_child(btn)

	## Close button.
	var close_btn := Button.new()
	close_btn.text = "Cancel"
	close_btn.pressed.connect(close)
	vbox.add_child(close_btn)

	## Click outside to close.
	overlay.gui_input.connect(_on_overlay_input)

	## Position the panel near the click.
	panel.position = screen_pos + Vector2(8, 8)

	return overlay

func _on_command_selected(npc: Node, command: StringName) -> void:
	close()
	if not is_instance_valid(npc):
		return
	EventBus.npc_command_issued.emit(npc, command)
	if npc.has_method("receive_comms_signal"):
		npc.receive_comms_signal(-1, command)

func _on_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_LEFT:
			## Click outside the panel → close.
			close()
