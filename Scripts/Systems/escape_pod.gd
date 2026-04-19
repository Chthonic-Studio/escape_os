class_name EscapePod
extends Area2D

## When an NPC enters the escape pod's detection area, they "escape."

const SFX_PODS_FULL = preload("res://Assets/Audio/pods_full.wav")

@export var capacity: int = 4
var _escaped_count: int = 0
var _is_active: bool = false

@onready var _label: Label = $Label
@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	add_to_group("escape_pods")
	body_entered.connect(_on_body_entered)
	EventBus.enemies_have_spawned.connect(_on_enemies_have_spawned)
	_update_label()

func _on_enemies_have_spawned() -> void:
	_is_active = true
	_update_label()

func _on_body_entered(body: Node2D) -> void:
	if not _is_active:
		return
	if _escaped_count >= capacity:
		return
	if body is HumanController:
		if body.state_machine.current_state == NPCStateMachine.State.DEAD:
			return
		_escaped_count += 1
		_update_label()
		body.state_machine.transition_to(NPCStateMachine.State.DEAD)
		EventBus.npc_escaped.emit(body)
		body.queue_free()
		if _escaped_count >= capacity:
			AudioManager.play_sfx(SFX_PODS_FULL, AudioManager.BUS_VFX3)
			hide()
			set_deferred("monitoring", false)
			set_deferred("monitorable", false)

func _update_label() -> void:
	if _label:
		if _is_active:
			_label.text = "POD %d/%d" % [_escaped_count, capacity]
		else:
			_label.text = "POD [INACTIVE]"

func is_full() -> bool:
	return _escaped_count >= capacity

func is_active() -> bool:
	return _is_active
