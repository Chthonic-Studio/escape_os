class_name AIAgentComponent
extends Node

signal safe_velocity_computed(safe_velocity: Vector2)

@export var body: CharacterBody2D
@export var nav_agent: NavigationAgent2D
@export var base_speed: float = 60.0

var _current_target: Vector2
var _is_path_dirty: bool = false

## Separation: push agents apart when they overlap, replacing expensive RVO.
const SEPARATION_RADIUS: float = 18.0
const SEPARATION_RADIUS_SQ: float = SEPARATION_RADIUS * SEPARATION_RADIUS
const SEPARATION_STRENGTH: float = 55.0

func _ready() -> void:
	assert(body != null, "AIAgentComponent requires a valid CharacterBody2D reference.")
	assert(nav_agent != null, "AIAgentComponent requires a NavigationAgent2D reference.")

	## Disable RVO — separation is handled in _compute_separation() instead.
	## RVO is O(n * max_neighbors) per frame per agent; our simple force is cheaper
	## and scales better when many NPCs are on screen simultaneously.
	nav_agent.avoidance_enabled = false
	nav_agent.radius = 8.0

	nav_agent.path_desired_distance = 10.0
	nav_agent.target_desired_distance = 10.0

	EventBus.nav_graph_changed.connect(_on_nav_graph_changed)

func set_target(target_global_position: Vector2) -> void:
	_current_target = target_global_position
	nav_agent.target_position = _current_target
	_is_path_dirty = false

func update_velocity_and_path() -> void:
	if nav_agent.is_navigation_finished():
		safe_velocity_computed.emit(Vector2.ZERO)
		return

	var current_position: Vector2 = body.global_position
	var next_path_position: Vector2 = nav_agent.get_next_path_position()

	var direction: Vector2 = current_position.direction_to(next_path_position)

	var separation: Vector2 = _compute_separation()
	var raw_velocity: Vector2 = (direction * base_speed + separation).limit_length(base_speed)

	safe_velocity_computed.emit(raw_velocity)

## Lightweight separation force: pushes this agent away from overlapping neighbours
## in the same room. Uses per-room buckets from ShipData (built once per _process
## frame) so each agent only iterates the k agents sharing its room — O(k) instead
## of iterating all N cached agents (which would be O(n²) total).
func _compute_separation() -> Vector2:
	var force := Vector2.ZERO
	var my_pos: Vector2 = body.global_position
	var my_room: int = ShipData.get_room_at_world_pos(my_pos)

	## Fall back to full-cache scan when the agent is outside every room
	## (e.g. briefly crossing a corridor threshold). This is rare, so the
	## O(n) cost for that single agent is acceptable.
	var nearby_npcs: Array = ShipData.npc_nodes_by_room.get(my_room, ShipData.cached_npcs) if my_room >= 0 else ShipData.cached_npcs
	var nearby_enemies: Array = ShipData.enemy_nodes_by_room.get(my_room, ShipData.cached_enemies) if my_room >= 0 else ShipData.cached_enemies

	for npc in nearby_npcs:
		if not is_instance_valid(npc) or npc == body:
			continue
		var delta: Vector2 = my_pos - npc.global_position
		var dist_sq: float = delta.length_squared()
		if dist_sq < SEPARATION_RADIUS_SQ and dist_sq > 0.01:
			var dist: float = sqrt(dist_sq)
			force += (delta / dist) * (1.0 - dist / SEPARATION_RADIUS) * SEPARATION_STRENGTH

	for enemy in nearby_enemies:
		if not is_instance_valid(enemy) or enemy == body:
			continue
		var delta: Vector2 = my_pos - enemy.global_position
		var dist_sq: float = delta.length_squared()
		if dist_sq < SEPARATION_RADIUS_SQ and dist_sq > 0.01:
			var dist: float = sqrt(dist_sq)
			force += (delta / dist) * (1.0 - dist / SEPARATION_RADIUS) * SEPARATION_STRENGTH

	return force

func _on_nav_graph_changed() -> void:
	if not _is_path_dirty and not nav_agent.is_navigation_finished():
		_is_path_dirty = true
		_staggered_repath()

func _staggered_repath() -> void:
	var jitter: float = randf_range(0.01, 0.2)
	await get_tree().create_timer(jitter, false).timeout

	if is_instance_valid(self) and _is_path_dirty:
		set_target(_current_target)
