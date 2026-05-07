extends Node

## Enemy Director — the "global brain" half of the two-part AI system.
##
## The Director always knows the exact world positions of all living survivors.
## It cannot command Hunter brains (EnemyControllers) directly.  Instead it
## broadcasts approximate room-level hints to idle or resting enemies, nudging
## them toward areas where survivors were last seen.
##
## This mirrors Alien Isolation's AI Director design: an omniscient layer that
## feeds imprecise information to the per-enemy hunter brain, keeping enemies
## dangerous without making them omniscient.
##
## Tuning knobs
## ─────────────
## hint_interval        – seconds between hint cycles (lower = more aggressive)
## hints_per_cycle      – max enemies that receive hints per cycle (prevents mass convergence)
## hint_accuracy        – probability the hint is the exact survivor room vs an adjacent room

## Seconds between hint dispatch cycles.
@export var hint_interval: float = 5.0

## Maximum number of enemies that receive a hint in a single cycle.
## Keeping this small prevents every enemy from rushing the same survivor at once.
@export var hints_per_cycle: int = 2

## 0.0–1.0 probability a hint points to the exact room the survivor occupies.
## Values below 1.0 may redirect the hint to an adjacent room instead, giving
## the Hunter brain an imprecise lead rather than a perfect fix.
@export_range(0.0, 1.0) var hint_accuracy: float = 0.75

var _active: bool = false
var _hint_timer: float = 0.0

## Per-enemy cooldown tracking: enemy instance_id → remaining seconds.
## An enemy that just received a hint is ineligible for a new one until its
## cooldown expires, preventing repeated nudges at the same target.
var _hint_cooldowns: Dictionary = {}

## How long an enemy must wait after receiving a hint before it can get another.
const HINT_COOLDOWN: float = 12.0

func _ready() -> void:
	EventBus.enemies_have_spawned.connect(_on_enemies_have_spawned)
	EventBus.ship_generated.connect(_on_ship_generated)
	EventBus.enemy_died.connect(_on_enemy_died)

func _on_ship_generated(_pod_positions: Array) -> void:
	_active = false
	_hint_timer = 0.0
	_hint_cooldowns.clear()

func _on_enemies_have_spawned() -> void:
	_active = true

func _on_enemy_died(enemy: Node) -> void:
	_hint_cooldowns.erase(enemy.get_instance_id())

func _process(delta: float) -> void:
	if not _active:
		return

	## Tick per-enemy cooldowns and remove expired entries.
	for id in _hint_cooldowns.keys():
		_hint_cooldowns[id] -= delta
		if _hint_cooldowns[id] <= 0.0:
			_hint_cooldowns.erase(id)

	_hint_timer += delta
	if _hint_timer >= hint_interval:
		_hint_timer = 0.0
		_run_hint_cycle()

## Dispatches room-level hints to a limited number of idle or resting enemies.
func _run_hint_cycle() -> void:
	var living_npcs: Array = _get_living_npcs()
	if living_npcs.is_empty():
		return

	var eligible: Array = _get_eligible_enemies()
	if eligible.is_empty():
		return

	## Shuffle so hints are not always biased toward the first entry in the cache.
	eligible.shuffle()

	var sent: int = 0
	for enemy in eligible:
		if sent >= hints_per_cycle:
			break

		var target_npc: Node2D = living_npcs.pick_random() as Node2D
		var exact_room: int = ShipData.get_room_at_world_pos(target_npc.global_position)
		if exact_room < 0:
			continue

		var hint_room: int = _perturb_room(exact_room)
		enemy.receive_director_hint(hint_room)
		_hint_cooldowns[enemy.get_instance_id()] = HINT_COOLDOWN
		sent += 1

## Returns all living (non-dead) NPC nodes from the ship cache.
func _get_living_npcs() -> Array:
	var result: Array = []
	for npc in ShipData.cached_npcs:
		if not is_instance_valid(npc) or not npc is Node2D:
			continue
		if npc is HumanController and npc.state_machine.current_state == NPCStateMachine.State.DEAD:
			continue
		result.append(npc)
	return result

## Returns enemy nodes that are idle or resting, have no current hint cooldown,
## and expose the receive_director_hint() method (i.e. are EnemyController instances).
func _get_eligible_enemies() -> Array:
	var result: Array = []
	for enemy in ShipData.cached_enemies:
		if not is_instance_valid(enemy):
			continue
		if not enemy.has_method("receive_director_hint"):
			continue
		if _hint_cooldowns.has(enemy.get_instance_id()):
			continue
		var ec := enemy as EnemyController
		if ec == null:
			continue
		if ec.current_state == EnemyController.EnemyState.IDLE or \
				ec.current_state == EnemyController.EnemyState.RESTING:
			result.append(ec)
	return result

## Returns room_index unchanged with probability hint_accuracy; otherwise
## returns a random adjacent room to simulate an imprecise lead.
func _perturb_room(room_index: int) -> int:
	if randf() <= hint_accuracy:
		return room_index
	var neighbors: Array = ShipData.room_adjacency.get(room_index, [])
	if neighbors.is_empty():
		return room_index
	return neighbors.pick_random()
