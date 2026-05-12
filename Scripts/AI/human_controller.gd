class_name HumanController
extends CharacterBody2D

@export var ai_agent: AIAgentComponent

const MAX_HEALTH: float = 100.0
var health: float = MAX_HEALTH

var _stuck_timer: float = 0.0
var _last_position: Vector2 = Vector2.ZERO

const DEADLOCK_TIME_THRESHOLD: float = 1.0
const DEADLOCK_DIST_SQ_THRESHOLD: float = 16.0

var state_machine: NPCStateMachine
var personality: NPCPersonality.Type

var npc_class: NPCClass = null

@onready var _info_label: Label = $InfoBox/InfoLabel
@onready var _alert_label: Label = $AlertLabel
@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _box_outline: ReferenceRect = $InfoBox/BoxOutline

var _comms_flash_timer: float = 0.0
const COMMS_FLASH_DURATION: float = 1.0
var _original_material: Material = null
var _outline_material: ShaderMaterial = null

var _alert_vibrate_time: float = 0.0
const ALERT_BASE_X: float = -4.0
const ALERT_BASE_Y: float = -40.0
const ALERT_VIBRATE_AMP_X: float = 2.0
const ALERT_VIBRATE_AMP_Y: float = 1.5
const ALERT_VIBRATE_SPEED: float = 20.0
const ALERT_VIBRATE_Y_FREQ: float = 1.3

const GLOW_SHADER = preload("res://Assets/Shaders/shareholder_glow.gdshader")
var _glow_material: ShaderMaterial = null

const CLASS_COLOR_SHADER = preload("res://Assets/Shaders/class_color_swap.gdshader")
const OUTLINE_SHADER = preload("res://Assets/Shaders/green_outline.gdshader")
var _class_color_material: ShaderMaterial = null

func _ready() -> void:
	assert(ai_agent != null, "HumanController is missing its AIAgentComponent.")
	add_to_group("npcs")
	_last_position = global_position
	ai_agent.safe_velocity_computed.connect(_on_safe_velocity_computed)

	personality = NPCPersonality.pick_random()

	## Create the state machine as a child node so its state nodes can also
	## be children.  The controller reference must be set before add_child()
	## so that _ready() on the state machine can access it immediately.
	state_machine = NPCStateMachine.new()
	state_machine.name = "StateMachine"
	state_machine.controller = self
	state_machine.personality = personality
	add_child(state_machine)

	## Single dispatch point for radial-menu commands.
	EventBus.npc_command_issued.connect(_on_npc_command_issued)

	_init_glow_shader()

	_init_class_color()

	## Register in the ShipData NPC cache via the event bus.
	EventBus.npc_ready.emit(self)

func _init_glow_shader() -> void:
	if _box_outline and npc_class:
		if GLOW_SHADER:
			_glow_material = ShaderMaterial.new()
			_glow_material.shader = GLOW_SHADER
			_glow_material.set_shader_parameter("time_offset", randf() * 100.0)
			_box_outline.material = _glow_material
			_update_glow_shader()

## Applies class color to the sprite.
func _init_class_color() -> void:
	if _sprite and npc_class and CLASS_COLOR_SHADER:
		_class_color_material = ShaderMaterial.new()
		_class_color_material.shader = CLASS_COLOR_SHADER
		_class_color_material.set_shader_parameter("class_color", npc_class.class_color)
		_sprite.material = _class_color_material
		_original_material = _class_color_material

## Updates glow based on corporate value.
func _update_glow_shader() -> void:
	if _glow_material == null or npc_class == null:
		return
	var value: float = npc_class.corporate_value
	if value <= 1.0 and value >= 0.0:
		_glow_material.set_shader_parameter("glow_intensity", 0.0)
		_glow_material.set_shader_parameter("is_negative", 0.0)
	elif value > 1.0:
		var intensity: float = clampf((value - 1.0) / 24.0, 0.0, 0.7)
		_glow_material.set_shader_parameter("glow_intensity", intensity)
		_glow_material.set_shader_parameter("is_negative", 0.0)
	else:
		var intensity: float = clampf(absf(value) / 10.0, 0.1, 0.7)
		_glow_material.set_shader_parameter("glow_intensity", intensity)
		_glow_material.set_shader_parameter("is_negative", 1.0)

func _physics_process(delta: float) -> void:
	if state_machine.current_state == NPCStateMachine.State.DEAD:
		return

	state_machine.tick(delta)

	_update_speed_modifier()

	ai_agent.update_velocity_and_path()
	_check_for_deadlock(delta)

	_update_info_label()

	if _comms_flash_timer > 0.0:
		_comms_flash_timer -= delta
		if _comms_flash_timer <= 0.0:
			_comms_flash_timer = 0.0
			if _sprite and _outline_material:
				_sprite.material = _original_material
		elif _outline_material:
			_outline_material.set_shader_parameter("fade_progress", 1.0 - (_comms_flash_timer / COMMS_FLASH_DURATION))

	_update_alert_label(delta)

func _check_for_deadlock(delta: float) -> void:
	if ai_agent.nav_agent.is_navigation_finished():
		_stuck_timer = 0.0
		return
		
	if global_position.distance_squared_to(_last_position) < DEADLOCK_DIST_SQ_THRESHOLD:
		_stuck_timer += delta
	else:
		_stuck_timer = 0.0
		_last_position = global_position
		
	if _stuck_timer >= DEADLOCK_TIME_THRESHOLD:
		_stuck_timer = 0.0
		_panic_repath()

## Reroutes stuck NPCs to clear bottlenecks.
func _panic_repath() -> void:
	_last_position = global_position
	match state_machine.current_state:
		NPCStateMachine.State.IDLE, NPCStateMachine.State.PANICKING:
			_wander_to_random_point()
		NPCStateMachine.State.FLEEING_TO_POD:
			state_machine.repath_flee()

func _on_safe_velocity_computed(safe_velocity: Vector2) -> void:
	velocity = safe_velocity
	
	move_and_slide()
	
	_update_sprite_animation()
	
	if ai_agent.nav_agent.is_navigation_finished() and velocity == Vector2.ZERO:
		if state_machine.current_state == NPCStateMachine.State.IDLE:
			_wander_to_random_point()

func _update_sprite_animation() -> void:
	if not _sprite:
		return
	var is_moving: bool = velocity.length_squared() > 1.0
	var anim: StringName = &"moving" if is_moving else &"idle"
	if _sprite.animation != anim:
		_sprite.play(anim)
	if is_moving:
		_sprite.flip_h = velocity.x < 0

func _wander_to_random_point() -> void:
	var random_offset := Vector2(randf_range(-200, 200), randf_range(-200, 200))
	ai_agent.set_target(global_position + random_offset)

func receive_comms_signal(target_room_index: int, signal_type: StringName = &"move") -> void:
	state_machine.receive_signal(target_room_index, signal_type)
	var outline_color: Color = CommsSystem.SIGNAL_COLORS.get(signal_type, Color(0.3, 1.0, 0.3, 1.0))
	_start_comms_flash(outline_color)

## Handles npc_command_issued from the radial menu (single dispatch point).
## Uses the NPC's own current room so commands always target a valid position.
func _on_npc_command_issued(npc: Node, command: StringName) -> void:
	if npc != self:
		return
	var my_room: int = ShipData.get_room_at_world_pos(global_position)
	receive_comms_signal(my_room, command)

func _start_comms_flash(outline_color: Color = Color(0.3, 1.0, 0.3, 1.0)) -> void:
	_comms_flash_timer = COMMS_FLASH_DURATION
	if _sprite:
		_original_material = _sprite.material
		if _outline_material == null and OUTLINE_SHADER:
			_outline_material = ShaderMaterial.new()
			_outline_material.shader = OUTLINE_SHADER
		if _outline_material:
			_outline_material.set_shader_parameter("fade_progress", 0.0)
			_outline_material.set_shader_parameter("outline_color", outline_color)
			_sprite.material = _outline_material

func _update_speed_modifier() -> void:
	var class_mod: float = 1.0
	if npc_class:
		class_mod = npc_class.speed_modifier
	var pacing: float = GameManager.speed_multiplier
	var global_mod: float = GameManager.npc_global_speed_multiplier

	match state_machine.current_state:
		NPCStateMachine.State.PANICKING:
			if personality == NPCPersonality.Type.RECKLESS:
				ai_agent.base_speed = 60.0 * class_mod * pacing * global_mod
			else:
				ai_agent.base_speed = 50.0 * class_mod * pacing * global_mod
		NPCStateMachine.State.FLEEING_TO_POD:
			ai_agent.base_speed = 42.0 * class_mod * pacing * global_mod
		_:
			ai_agent.base_speed = 40.0 * class_mod * pacing * global_mod

	if state_machine._run_boost_timer > 0.0:
		ai_agent.base_speed *= NPCStateMachine.RUN_BOOST_MULTIPLIER

func die(killed_by_enemy: bool = false) -> void:
	if state_machine.current_state == NPCStateMachine.State.DEAD:
		return
	state_machine.transition_to(NPCStateMachine.State.DEAD)
	EventBus.npc_died.emit(self)
	if npc_class and npc_class.corporate_value >= 10.0:
		EventBus.vip_killed.emit(self)
	if killed_by_enemy:
		EventBus.npc_killed_by_enemy.emit(self, global_position)
	
	_explode_and_free()

func _explode_and_free() -> void:
	$CollisionShape2D.set_deferred("disabled", true)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", scale * 1.5, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.set_parallel(false)
	tween.tween_callback(queue_free)

func take_damage(amount: float) -> bool:
	if state_machine.current_state == NPCStateMachine.State.DEAD:
		return false
	health -= amount
	if health <= 0.0:
		health = 0.0
		die(true)
		return true
	return false

func _update_info_label() -> void:
	if not _info_label:
		return
	var class_id_str: String = "NPC"
	if npc_class:
		class_id_str = npc_class.display_name.to_upper().left(6)
	var state_str: String = "IDLE"
	match state_machine.current_state:
		NPCStateMachine.State.PANICKING: state_str = "PANIC"
		NPCStateMachine.State.MOVING_TO_SIGNAL: state_str = "MOVING"
		NPCStateMachine.State.HIDING: state_str = "HIDING"
		NPCStateMachine.State.FLEEING_TO_POD: state_str = "FLEEING"
		NPCStateMachine.State.DEAD: state_str = "DEAD"
	_info_label.text = "%s // %s" % [class_id_str, state_str]

func _update_alert_label(delta: float) -> void:
	if not _alert_label:
		return
	var is_alert: bool = (
		state_machine.current_state == NPCStateMachine.State.PANICKING or
		state_machine.current_state == NPCStateMachine.State.FLEEING_TO_POD
	)
	_alert_label.visible = is_alert
	if is_alert:
		_alert_vibrate_time += delta * ALERT_VIBRATE_SPEED
		_alert_label.position.x = ALERT_BASE_X + sin(_alert_vibrate_time) * ALERT_VIBRATE_AMP_X
		_alert_label.position.y = ALERT_BASE_Y + cos(_alert_vibrate_time * ALERT_VIBRATE_Y_FREQ) * ALERT_VIBRATE_AMP_Y
