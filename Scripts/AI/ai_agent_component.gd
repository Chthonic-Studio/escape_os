class_name AIAgentComponent
extends Node

signal safe_velocity_computed(safe_velocity: Vector2)

@export var body: CharacterBody2D
@export var nav_agent: NavigationAgent2D
@export var base_speed: float = 60.0

## How far agents detect each other for separation forces (pixels).
@export var separation_radius: float = 22.0
## Strength of the lateral-drift separation push.
@export var separation_strength: float = 28.0
## Multiplier applied to base_speed for the drift velocity cap.
## Values > 1.0 allow agents to briefly overshoot while drifting past each other.
@export var drift_limit_multiplier: float = 1.3

## Squared-magnitude threshold below which the lateral separation component
## is considered negligible (used for inline-stack detection).
const INLINE_LATERAL_THRESHOLD: float = 0.5
## Fraction of the backward separation magnitude applied as a lateral push
## when agents are detected as stacked inline.
const INLINE_SEPARATION_SCALE: float = 0.65

var _current_target: Vector2
var _is_path_dirty: bool = false

func _ready() -> void:
	assert(body != null, "AIAgentComponent requires a valid CharacterBody2D reference.")
	assert(nav_agent != null, "AIAgentComponent requires a NavigationAgent2D reference.")

	## Disable RVO — separation is handled in _compute_separation() instead.
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

	## Primary velocity: always move toward the next path waypoint at full speed.
	var nav_vel: Vector2 = direction * base_speed

	## Secondary (drift): separation pushes agents laterally so they slip past
	## each other through narrow doors rather than clumping into a blob.
	## Only the component perpendicular to travel (lateral drift) and any forward
	## push are applied — backward separation is discarded so the agent always
	## makes forward progress.
	var sep: Vector2 = _compute_separation()
	var sep_forward_dot: float = sep.dot(direction) if direction.length_squared() > 0.001 else 0.0
	var sep_lateral: Vector2 = sep - direction * sep_forward_dot
	## Allow only forward separation (not backward).
	var effective_sep: Vector2 = sep_lateral
	if sep_forward_dot > 0.0:
		effective_sep += direction * sep_forward_dot
	elif sep_lateral.length_squared() < INLINE_LATERAL_THRESHOLD and sep.length_squared() > INLINE_LATERAL_THRESHOLD:
		## Inline-stack case: agents directly behind each other share the same
		## travel direction, so the separation force is entirely backward and the
		## lateral component cancels to zero.  Rotate the force 90° using a
		## per-agent deterministic sign so adjacent agents fan out in opposite
		## directions instead of all piling toward the same side.
		var lat_sign: float = 1.0 if (body.get_instance_id() & 1) == 0 else -1.0
		var perp: Vector2 = Vector2(-direction.y, direction.x) * lat_sign
		effective_sep = perp * sep.length() * INLINE_SEPARATION_SCALE

	var raw_velocity: Vector2 = (nav_vel + effective_sep).limit_length(base_speed * drift_limit_multiplier)

	safe_velocity_computed.emit(raw_velocity)

## Lightweight separation force: pushes this agent away from overlapping neighbours
## in the same room. Uses per-room buckets from ShipData (built once per _process
## frame) so each agent only iterates the k agents sharing its room — O(k) instead
## of iterating all N cached agents (which would be O(n²) total).
func _compute_separation() -> Vector2:
	var force := Vector2.ZERO
	var my_pos: Vector2 = body.global_position
	var my_room: int = ShipData.get_room_at_world_pos(my_pos)
	var radius_sq: float = separation_radius * separation_radius

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
		if dist_sq < radius_sq and dist_sq > 0.01:
			var dist: float = sqrt(dist_sq)
			force += (delta / dist) * (1.0 - dist / separation_radius) * separation_strength

	for enemy in nearby_enemies:
		if not is_instance_valid(enemy) or enemy == body:
			continue
		var delta: Vector2 = my_pos - enemy.global_position
		var dist_sq: float = delta.length_squared()
		if dist_sq < radius_sq and dist_sq > 0.01:
			var dist: float = sqrt(dist_sq)
			force += (delta / dist) * (1.0 - dist / separation_radius) * separation_strength

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
