class_name AILogFeed
extends PanelContainer

## Combined T2-style log feed with status counters at the top.

const MAX_LOG_ENTRIES: int = 12
const LOG_FADE_TIME: float = 6.0

@onready var _log_container: VBoxContainer = $MarginContainer/VBoxContainer/LogContainer
@onready var _hex_bg_label: Label = $MarginContainer/HexBackground
@onready var _status_container: HBoxContainer = $MarginContainer/VBoxContainer/StatusContainer

@onready var _pod_slots_label: Label = $MarginContainer/VBoxContainer/StatusContainer/LeftColumn/PodSlotsLabel
@onready var _npc_count_label: Label = $MarginContainer/VBoxContainer/StatusContainer/LeftColumn/NpcCountLabel
@onready var _pod_timer_label: Label = $MarginContainer/VBoxContainer/StatusContainer/RightColumn/PodTimerLabel
@onready var _alien_count_label: Label = $MarginContainer/VBoxContainer/StatusContainer/RightColumn/AlienCountLabel

var _entries: Array[Label] = []

var _greybox_level: Node = null
var _greybox_level_resolved: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	EventBus.door_toggled.connect(_on_door_toggled)
	EventBus.npc_died.connect(_on_npc_died)
	EventBus.npc_escaped.connect(_on_npc_escaped)
	EventBus.airlock_activated.connect(_on_airlock_activated)
	EventBus.airlock_blocked.connect(_on_airlock_blocked)
	EventBus.room_depressurized.connect(_on_room_depressurized)
	EventBus.enemy_spawn.connect(_on_enemy_spawn)
	EventBus.comms_signal_sent.connect(_on_comms_signal_sent)
	EventBus.hazard_deployed.connect(_on_hazard_deployed)

	EventBus.enemies_have_spawned.connect(_resolve_greybox_level)

	if _hex_bg_label:
		_hex_bg_label.visible = false

func _process(_delta: float) -> void:
	_update_status_counters()

func _add_log(text: String, color: Color = Color(1.0, 0.2, 0.2, 0.8)) -> void:
	var label: Label = UIManager.create_log_entry()
	label.text = "> " + text
	label.add_theme_color_override("font_color", color)
	_log_container.add_child(label)
	_entries.append(label)

	var tween := label.create_tween()
	tween.tween_property(label, "modulate:a", 0.0, 1.0).set_delay(LOG_FADE_TIME)
	tween.tween_callback(func() -> void:
		_entries.erase(label)
		label.queue_free()
	)

	while _entries.size() > MAX_LOG_ENTRIES:
		var old: Label = _entries.pop_front()
		if is_instance_valid(old):
			old.queue_free()

func _on_door_toggled(door_id: StringName, is_open: bool) -> void:
	var state_str: String = "OPENED" if is_open else "SEALED"
	_add_log("[DOOR] %s — %s" % [door_id, state_str])

func _on_npc_died(npc: Node) -> void:
	var class_name_str: String = "UNKNOWN"
	if npc is HumanController and npc.npc_class:
		class_name_str = npc.npc_class.display_name.to_upper()
	var remarks: Array[String] = [
		"[EMAIL HR: REQUESTED MANDATORY PHYSICAL ACTIVITY TRAINING FOR EMPLOYEES]",
		"[VACANCY POSTED ON LINKEDIN]",
		"[SUBJECT CEASED BIOLOGICAL FUNCTION]",
		"[HR NOTIFIED OF VACANCY. NOTIFY CLOSEST OF KIN TO INHERIT DEBTS TO THE COMPANY]",
		"[CORPORATE INSURANCE POLICY ACTIVATED]",
	]
	_add_log("[TERMINATED] %s — %s" % [class_name_str, remarks.pick_random()], Color(1.0, 0.3, 0.3))

func _on_npc_escaped(npc: Node) -> void:
	var class_name_str: String = "UNKNOWN"
	if npc is HumanController and npc.npc_class:
		class_name_str = npc.npc_class.display_name.to_upper()
	_add_log("[EVACUATED] %s — SHAREHOLDER VALUE PRESERVED" % class_name_str, Color(0.3, 1.0, 0.3))

func _on_airlock_activated(room_index: int) -> void:
	_add_log("[AIRLOCK] ROOM %d — DEPRESSURIZATION SEQUENCE INITIATED" % room_index, Color(1.0, 0.6, 0.2))

func _on_airlock_blocked(room_index: int) -> void:
	_add_log("[AIRLOCK] ROOM %d — SEAL BREACH DETECTED. CANNOT DEPRESSURIZE." % room_index, Color(1.0, 0.3, 0.3))

func _on_room_depressurized(room_index: int) -> void:
	_add_log("[AIRLOCK] ROOM %d — ROOM DEPRESSURIZED. ALL PRESENT ENTITIES PURGED." % room_index, Color(1.0, 0.4, 0.4))

func _on_enemy_spawn(global_pos: Vector2) -> void:
	_add_log("[ALERT] HOSTILE DETECTED AT SECTOR (%.0f, %.0f)" % [global_pos.x, global_pos.y], Color(1.0, 0.2, 0.2))

func _on_comms_signal_sent(room_index: int, _affected_rooms: Array) -> void:
	var signal_name: String = "MOVE"
	var signal_color: Color = Color(0.5, 0.8, 1.0)
	var comms_nodes := get_tree().get_nodes_in_group("comms_system")
	for cs in comms_nodes:
		if cs is CommsSystem:
			signal_name = CommsSystem.SIGNAL_NAMES.get(cs.current_signal_type, "MOVE")
			signal_color = CommsSystem.SIGNAL_COLORS.get(cs.current_signal_type, signal_color)
			break
	var pa_messages: Array[String] = [
		"[PA SYSTEM] ATTENTION ALL PERSONNEL: %s — ROOM %d",
		"[PA SYSTEM] NEW C-LEVEL DIRECTIVE: %s — SECTOR %d",
		"[PA SYSTEM] COMPLIANCE REQUIRED: %s — ZONE %d",
	]
	_add_log(pa_messages.pick_random() % [signal_name, room_index], signal_color)

func _on_hazard_deployed(type: StringName, _global_loc: Vector2) -> void:
	_add_log("[HAZARD] %s DEPLOYED" % str(type).to_upper(), Color(0.3, 0.6, 1.0))

func _resolve_greybox_level() -> void:
	if _greybox_level_resolved:
		return
	_greybox_level_resolved = true
	_find_greybox_level(get_tree().root)

func _update_status_counters() -> void:
	if not GameManager.enemies_active:
		if _status_container:
			_status_container.visible = false
		return
	if _status_container:
		_status_container.visible = true

	var total_slots: int = 0
	var used_slots: int = 0
	var pods := get_tree().get_nodes_in_group("escape_pods")
	for pod in pods:
		if is_instance_valid(pod) and pod is EscapePod:
			total_slots += pod.capacity
			used_slots += pod._escaped_count
	var available_slots: int = total_slots - used_slots
	if _pod_slots_label:
		_pod_slots_label.text = "POD SLOTS: %d / %d" % [available_slots, total_slots]

	var npcs_alive: int = GameManager.total_npcs_spawned - GameManager.npcs_escaped - GameManager.npcs_died
	if _npc_count_label:
		_npc_count_label.text = "CREW: %d ALIVE | %d DEAD" % [npcs_alive, GameManager.npcs_died]

	if _pod_timer_label:
		if _greybox_level != null and is_instance_valid(_greybox_level) and available_slots <= 0 and npcs_alive > 0:
			var pod_time: float = _greybox_level.next_pod_respawn_timer
			_pod_timer_label.text = "NEW POD IN: %.0fs" % pod_time
		else:
			_pod_timer_label.text = "POD STATUS: STANDBY"

	if _alien_count_label:
		var enemies: int = GameManager.enemies_alive
		var enemy_timer_str: String = ""
		if _greybox_level != null and is_instance_valid(_greybox_level):
			var enemy_time: float = _greybox_level.next_enemy_respawn_timer
			if enemy_time > 0.0:
				enemy_timer_str = " | NEXT: %.0fs" % enemy_time
		_alien_count_label.text = "HOSTILES: %d%s" % [enemies, enemy_timer_str]

func _find_greybox_level(node: Node) -> void:
	if node is GreyboxLevel:
		_greybox_level = node
		return
	for child in node.get_children():
		if _greybox_level != null:
			return
		_find_greybox_level(child)
