class_name BarkSystem
extends Node

const BARK_DURATION: float = 2.5
const BARK_RISE_SPEED: float = 15.0

var _active_barks: Dictionary = {}

const PANIC_BARKS: Array[String] = [
	"AHHHHH!",
	"WE'RE ALL GONNA DIE!",
	"I didn't sign up for this!",
	"PLEASE TELL ME THAT'S A HOLOGRAM!",
	"NOT LIKE THIS!",
	"I WANT MY MOMMY!",
	"THIS ISN'T IN MY CONTRACT!",
	"I SHOULD'VE CALLED IN SICK!",
]

const DEATH_BARKS: Array[String] = [
	"Tell my cat I love h—",
	"*splat*",
	"I didn't even get to finish my tax return!",
	"Aurg—",
	"I really wanted... that promotion",
	"My performance review...",
	"Ph'nglui mglw'nafh...",
]

const ESCAPE_BARKS: Array[String] = [
	"I'M FREE!",
	"THANK YOU, ELONGATED MUSKETEER!",
	"PRAISE BE THE ALT-MAN",
	"I'm never leaving Mars Station again!",
	"I'm putting in my two weeks!",
	"NEVER. AGAIN.",
	"Fuck space",
	"Best evacuation drill ever!",
	"Just like in Alien: Isolation!"
]

const SIGNAL_BARKS: Array[String] = [
	"Are you sure?",
	"On my way!",
	"Moving!",
	"This damn AI...",
	"Going!",
]

const FLEEING_BARKS: Array[String] = [
	"WHERE ARE THE PODS?!",
	"GOTTA FIND AN ESCAPE POD!",
	"This way... I think?!",
	"Wait, was it left or right?!",
	"I need a minute... *wheeze*",
	"EVERYONE OUT!",
	"WHICH WAY IS THE POD?!",
	"Oh god oh god oh god...",
	"WHO MADE THIS LAYOUT SO CONFUSING?!",
	"WHY IS THE SHIP SQUARE?!"
]

func _ready() -> void:
	EventBus.npc_state_changed.connect(_on_npc_state_changed)
	EventBus.npc_died.connect(_on_npc_died)
	EventBus.npc_escaped.connect(_on_npc_escaped)
	EventBus.npc_died.connect(_cleanup_bark_entry)
	EventBus.npc_escaped.connect(_cleanup_bark_entry)

func _cleanup_bark_entry(npc: Node) -> void:
	if not is_instance_valid(npc):
		return
	var npc_id: int = npc.get_instance_id()
	_active_barks.erase(npc_id)

func _on_npc_state_changed(npc: Node, new_state: StringName) -> void:
	if not is_instance_valid(npc) or not npc is Node2D:
		return
	match new_state:
		&"panicking":
			if randf() < 0.4:
				_spawn_bark(npc, PANIC_BARKS.pick_random(), Color(1.0, 0.4, 0.4))
		&"moving_to_signal":
			if randf() < 0.3:
				_spawn_bark(npc, SIGNAL_BARKS.pick_random(), Color(0.5, 0.8, 1.0))
		&"fleeing_to_pod":
			if randf() < 0.25:
				_spawn_bark(npc, FLEEING_BARKS.pick_random(), Color(1.0, 0.7, 0.3))

func _on_npc_died(npc: Node) -> void:
	if not is_instance_valid(npc) or not npc is Node2D:
		return
	_spawn_bark_world(npc, DEATH_BARKS.pick_random(), Color(1.0, 0.2, 0.2))

func _on_npc_escaped(npc: Node) -> void:
	if not is_instance_valid(npc) or not npc is Node2D:
		return
	_spawn_bark_world(npc, ESCAPE_BARKS.pick_random(), Color(0.3, 1.0, 0.3))

## Spawns a bark label on the NPC.
func _spawn_bark(npc: Node2D, text: String, color: Color) -> void:
	var npc_id: int = npc.get_instance_id()

	if _active_barks.has(npc_id):
		var old_label: Label = _active_barks[npc_id]
		if is_instance_valid(old_label):
			old_label.queue_free()
		_active_barks.erase(npc_id)

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 3)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-40, -45)
	label.z_index = 100

	npc.add_child(label)
	_active_barks[npc_id] = label

	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 20.0, BARK_DURATION)
	tween.tween_property(label, "modulate:a", 0.0, BARK_DURATION).set_delay(BARK_DURATION * 0.5)
	tween.set_parallel(false)
	tween.tween_callback(func() -> void:
		_active_barks.erase(npc_id)
		if is_instance_valid(label):
			label.queue_free()
	)

func _spawn_bark_world(npc: Node2D, text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 3)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = npc.global_position + Vector2(-40, -45)
	label.z_index = 100

	get_tree().current_scene.add_child(label)

	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 30.0, BARK_DURATION)
	tween.tween_property(label, "modulate:a", 0.0, BARK_DURATION).set_delay(BARK_DURATION * 0.5)
	tween.set_parallel(false)
	tween.tween_callback(label.queue_free)
