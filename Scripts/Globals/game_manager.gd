extends Node

## Tracks game state: NPC counts, level end conditions, and scoring data.

var total_npcs_spawned: int = 0
var npcs_escaped: int = 0
var npcs_died: int = 0

var class_results: Dictionary = {}

var level_ended: bool = false

## Controls speed and pacing over time.
var speed_multiplier: float = 1.0
var current_wave: int = 0
var enemies_alive: int = 0
var enemies_active: bool = false
var level_elapsed_time: float = 0.0
var _timer_running: bool = false

const ESCALATION_INTERVAL: float = 30.0
const ESCALATION_STEP: float = 0.12
var _last_escalation_time: float = 0.0

signal level_complete(escaped: int, died: int)

var _time_dilation_active: bool = false
var _prev_time_scale: float = 1.0

func _ready() -> void:
	EventBus.npc_spawned.connect(_on_npc_spawned)
	EventBus.npc_died.connect(_on_npc_died)
	EventBus.npc_escaped.connect(_on_npc_escaped)
	EventBus.enemy_spawn.connect(_on_enemy_spawned)
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.enemies_have_spawned.connect(_on_enemies_have_spawned)
	EventBus.vip_killed.connect(_on_vip_killed)

func _process(delta: float) -> void:
	if _timer_running and not level_ended:
		level_elapsed_time += delta
		_check_pacing_escalation()
	ShipData.update_npc_room_counts()

func reset() -> void:
	total_npcs_spawned = 0
	npcs_escaped = 0
	npcs_died = 0
	class_results.clear()
	level_ended = false
	speed_multiplier = 1.0
	current_wave = 0
	enemies_alive = 0
	enemies_active = false
	level_elapsed_time = 0.0
	_timer_running = false
	_last_escalation_time = 0.0
	TimeManager.reset()

func start_level_timer() -> void:
	_timer_running = true

func _on_npc_spawned(npc_class_id: StringName, _global_pos: Vector2, _room_type: int) -> void:
	total_npcs_spawned += 1
	if not class_results.has(npc_class_id):
		class_results[npc_class_id] = { "escaped": 0, "died": 0, "value": 0.0 }

func _on_npc_died(npc: Node) -> void:
	if level_ended:
		return
	npcs_died += 1
	var class_id: StringName = &"Crewmember"
	if npc is HumanController and npc.npc_class:
		class_id = npc.npc_class.class_name_id
		if class_results.has(class_id):
			class_results[class_id]["died"] += 1
			class_results[class_id]["value"] -= npc.npc_class.corporate_value
	_check_level_end()

func _on_npc_escaped(npc: Node) -> void:
	if level_ended:
		return
	npcs_escaped += 1
	var class_id: StringName = &"Crewmember"
	if npc is HumanController and npc.npc_class:
		class_id = npc.npc_class.class_name_id
		if class_results.has(class_id):
			class_results[class_id]["escaped"] += 1
			class_results[class_id]["value"] += npc.npc_class.corporate_value
	_check_level_end()

func _on_enemy_spawned(_global_pos: Vector2) -> void:
	enemies_alive += 1

func _on_enemy_died(_enemy: Node) -> void:
	enemies_alive = maxi(enemies_alive - 1, 0)

func _on_enemies_have_spawned() -> void:
	enemies_active = true
	start_level_timer()

func _check_level_end() -> void:
	var resolved: int = npcs_escaped + npcs_died
	if resolved >= total_npcs_spawned and total_npcs_spawned > 0:
		level_ended = true
		_timer_running = false
		print("[GAME] Level complete! Escaped: %d, Died: %d (%.1fs)" % [npcs_escaped, npcs_died, level_elapsed_time])
		level_complete.emit(npcs_escaped, npcs_died)

func get_shareholder_value() -> float:
	var total: float = 0.0
	for class_id in class_results:
		total += class_results[class_id]["value"]
	return total

func get_rating_grade() -> String:
	var value: float = get_shareholder_value()
	if value >= 50.0: return "S"
	elif value >= 30.0: return "A"
	elif value >= 15.0: return "B"
	elif value >= 0.0: return "C"
	elif value >= -15.0: return "D"
	else: return "F"

func get_progress() -> float:
	if total_npcs_spawned <= 0:
		return 0.0
	return float(npcs_escaped + npcs_died) / float(total_npcs_spawned)

func set_speed_multiplier(mult: float) -> void:
	speed_multiplier = clampf(mult, 0.1, 3.0)

## Increases speed over time.
func _check_pacing_escalation() -> void:
	if level_elapsed_time - _last_escalation_time >= ESCALATION_INTERVAL:
		_last_escalation_time += ESCALATION_INTERVAL
		var new_mult: float = speed_multiplier + ESCALATION_STEP
		set_speed_multiplier(new_mult)
		print("[PACING] Escalation! Speed multiplier: %.2f (elapsed: %.0fs)" % [speed_multiplier, level_elapsed_time])

func _on_vip_killed(_npc: Node) -> void:
	if _time_dilation_active:
		return
	_time_dilation_active = true
	_prev_time_scale = Engine.time_scale
	Engine.time_scale = 0.1
	var timer := get_tree().create_timer(0.3, true, false, true)
	timer.timeout.connect(_restore_time_scale)

func _restore_time_scale() -> void:
	Engine.time_scale = _prev_time_scale
	_time_dilation_active = false
