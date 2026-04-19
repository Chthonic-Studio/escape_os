class_name AIAgentComponent
extends Node

signal safe_velocity_computed(safe_velocity: Vector2)

@export var body: CharacterBody2D
@export var nav_agent: NavigationAgent2D
@export var base_speed: float = 60.0

var _current_target: Vector2
var _is_path_dirty: bool = false

func _ready() -> void:
	assert(body != null, "AIAgentComponent requires a valid CharacterBody2D reference.")
	assert(nav_agent != null, "AIAgentComponent requires a NavigationAgent2D reference.")
	
	nav_agent.avoidance_enabled = true
	nav_agent.radius = 8.0 
	nav_agent.neighbor_distance = 150.0 
	nav_agent.max_neighbors = 8
	
	nav_agent.velocity_computed.connect(_on_velocity_computed)
	EventBus.nav_graph_changed.connect(_on_nav_graph_changed)
	
	nav_agent.path_desired_distance = 10.0
	nav_agent.target_desired_distance = 10.0

func set_target(target_global_position: Vector2) -> void:
	_current_target = target_global_position
	nav_agent.target_position = _current_target
	_is_path_dirty = false

func update_velocity_and_path() -> void:
	if nav_agent.is_navigation_finished():
		if nav_agent.avoidance_enabled:
			nav_agent.velocity = Vector2.ZERO
		else:
			safe_velocity_computed.emit(Vector2.ZERO)
		return
		
	var current_position: Vector2 = body.global_position
	var next_path_position: Vector2 = nav_agent.get_next_path_position()
	
	var direction: Vector2 = current_position.direction_to(next_path_position)
	
	if nav_agent.avoidance_enabled:
		var noise := Vector2(randf_range(-0.05, 0.05), randf_range(-0.05, 0.05))
		direction = (direction + noise).normalized()
		
	var raw_velocity: Vector2 = direction * base_speed
	
	if nav_agent.avoidance_enabled:
		nav_agent.velocity = raw_velocity
	else:
		safe_velocity_computed.emit(raw_velocity)

func _on_velocity_computed(safe_velocity: Vector2) -> void:
	safe_velocity_computed.emit(safe_velocity)

func _on_nav_graph_changed() -> void:
	if not _is_path_dirty and not nav_agent.is_navigation_finished():
		_is_path_dirty = true
		_staggered_repath()

func _staggered_repath() -> void:
	var jitter: float = randf_range(0.01, 0.2)
	await get_tree().create_timer(jitter, false).timeout
	
	if is_instance_valid(self) and _is_path_dirty:
		set_target(_current_target)
