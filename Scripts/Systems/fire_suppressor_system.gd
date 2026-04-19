class_name FireSuppressorSystem
extends Area2D

## Fire suppressor / extinguisher hazard.

@export var outline_color: Color = Color(0.3, 0.6, 1.0, 1.0)
@export var outline_width: float = 2.0
@export var stun_duration: float = 4.0
@export var slow_multiplier: float = 0.4

var room_index: int = -1
var _is_active: bool = false
var _is_hovered: bool = false

@onready var _label: Label = $Label
@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	add_to_group("fire_suppressors")

	if _label:
		_label.hide()
		_label.text = "Fire Suppressor"
		_label.add_theme_color_override("font_color", Color(0.3, 0.6, 1.0))
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
	_is_active = true
	EventBus.hazard_deployed.emit(&"fire_suppressor", global_position)
	_run_suppressor_sequence()

func _run_suppressor_sequence() -> void:
	var room_rect_world: Rect2 = ShipData.get_room_world_rect(room_index)
	if room_rect_world.size == Vector2.ZERO:
		_is_active = false
		return

	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and enemy is Node2D and room_rect_world.has_point(enemy.global_position):
			if enemy is EnemyController:
				enemy.stun(stun_duration)

	var slowed_npcs: Array[Dictionary] = []
	for npc in get_tree().get_nodes_in_group("npcs"):
		if is_instance_valid(npc) and npc is Node2D and room_rect_world.has_point(npc.global_position):
			if npc is HumanController:
				var original_speed: float = npc.ai_agent.base_speed
				npc.ai_agent.base_speed *= slow_multiplier
				slowed_npcs.append({ "npc": npc, "original_speed": original_speed })

	await get_tree().create_timer(stun_duration, false).timeout

	for entry in slowed_npcs:
		var npc: Node = entry["npc"]
		if is_instance_valid(npc) and npc is HumanController:
			npc.ai_agent.base_speed = entry["original_speed"]

	_is_active = false

func _on_mouse_entered() -> void:
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
	if _is_hovered and is_instance_valid(_sprite) and _sprite.sprite_frames:
		var tex: Texture2D = _sprite.sprite_frames.get_frame_texture(_sprite.animation, _sprite.frame)
		if tex:
			var size: Vector2 = tex.get_size()
			var pos_offset: Vector2 = -size * 0.5
			var rect := Rect2(pos_offset, size)
			draw_rect(rect, outline_color, false, outline_width)
