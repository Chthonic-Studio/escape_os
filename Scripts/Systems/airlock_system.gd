class_name AirlockSystem
extends Area2D

## Manages airlock activation for a specific room.

@export var outline_color: Color = Color(1.0, 0.2, 0.2, 1.0)
@export var outline_width: float = 2.0

var room_index: int = -1
var _is_active: bool = false
var _is_hovered: bool = false
var _cached_comms_system: CommsSystem = null

@onready var _label: Label = $Label
@onready var _sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	add_to_group("airlocks")
	
	if _label:
		_label.hide()
		_label.text = "Open the airlocks"
		_label.add_theme_color_override("font_color", Color.RED)
		_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_label.add_theme_constant_override("outline_size", 4)
	
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		activate()
		get_viewport().set_input_as_handled()

func activate() -> void:
	if _is_active or room_index < 0:
		return

	var doors: Array = ShipData.room_doors.get(room_index, [])
	for door in doors:
		if is_instance_valid(door) and door is DoorSystem and door.is_destroyed:
			EventBus.airlock_blocked.emit(room_index)
			return

	_is_active = true
	EventBus.airlock_activated.emit(room_index)
	_run_airlock_sequence()

func _run_airlock_sequence() -> void:
	var doors: Array = ShipData.room_doors.get(room_index, [])
	for door in doors:
		if is_instance_valid(door) and door is DoorSystem:
			door.force_close()
			door.lock()

	await get_tree().create_timer(1.0, false).timeout

	ShipData.depressurized_rooms[room_index] = true
	_kill_entities_in_room()
	EventBus.room_depressurized.emit(room_index)

	await get_tree().create_timer(3.0, false).timeout

	ShipData.depressurized_rooms.erase(room_index)
	EventBus.room_repressurized.emit(room_index)

	for door in doors:
		if is_instance_valid(door) and door is DoorSystem:
			door.unlock()

	_is_active = false

func _kill_entities_in_room() -> void:
	var room_rect_world: Rect2 = ShipData.get_room_world_rect(room_index)
	if room_rect_world.size == Vector2.ZERO:
		return

	for npc in get_tree().get_nodes_in_group("npcs"):
		if is_instance_valid(npc) and npc is Node2D and room_rect_world.has_point(npc.global_position):
			if npc.has_method("die"):
				npc.die()
			else:
				EventBus.npc_died.emit(npc)
				npc.queue_free()

	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and enemy is Node2D and room_rect_world.has_point(enemy.global_position):
			if enemy.has_method("die"):
				enemy.die()
			else:
				EventBus.enemy_died.emit(enemy)
				enemy.queue_free()

func _on_mouse_entered() -> void:
	if _cached_comms_system == null:
		var comms_nodes := get_tree().get_nodes_in_group("comms_system")
		for cs in comms_nodes:
			if cs is CommsSystem:
				_cached_comms_system = cs
				break
	if _cached_comms_system and _cached_comms_system.is_signal_mode:
		return
	_is_hovered = true
	if _label:
		_label.show()
	queue_redraw()

func _on_mouse_exited() -> void:
	_is_hovered = false
	if _label:
		_label.hide()
	queue_redraw()

func _draw() -> void:
	if _is_hovered and is_instance_valid(_sprite) and _sprite.texture:
		var tex: Texture2D = _sprite.texture
		
		var size: Vector2 = _sprite.region_rect.size if _sprite.region_enabled else tex.get_size()
		
		var pos_offset: Vector2 = _sprite.offset
		if _sprite.centered:
			pos_offset -= size * 0.5 
			
		var rect := Rect2(pos_offset, size)
		draw_rect(rect, outline_color, false, outline_width)
