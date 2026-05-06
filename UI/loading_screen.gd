class_name LoadingScreen
extends CanvasLayer

## Shown during ship generation.
## Listens for generation_progress to update the status label,
## then hides itself when ship_generated fires.

var _panel: ColorRect
var _vbox: VBoxContainer
var _status_label: Label
var _sub_label: Label
var _bar: ProgressBar

const FLAVOR_LINES: Array[String] = [
	"ALLOCATING SHAREHOLDERS...",
	"CALCULATING ACCEPTABLE LOSSES...",
	"BRIBING SAFETY INSPECTORS...",
	"DEPRESSURIZING ESCAPE ROUTES...",
	"OPTIMIZING CORRIDOR CAPACITY...",
	"REVIEWING LIABILITY WAIVERS...",
	"CALIBRATING BLAST DOORS...",
	"AUDITING CREW EXPENDITURE...",
]

func _ready() -> void:
	layer = 90
	_build_ui()
	EventBus.ship_generated.connect(_on_ship_generated)
	EventBus.generation_progress.connect(_on_generation_progress)

func _build_ui() -> void:
	_panel = ColorRect.new()
	_panel.color = Color(0.0, 0.0, 0.0, 0.92)
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)

	_vbox = VBoxContainer.new()
	_vbox.set_anchors_preset(Control.PRESET_CENTER)
	_vbox.custom_minimum_size = Vector2(320, 100)
	_vbox.offset_left = -160.0
	_vbox.offset_top = -50.0
	_vbox.offset_right = 160.0
	_vbox.offset_bottom = 50.0
	_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(_vbox)

	_status_label = Label.new()
	_status_label.text = "GENERATING SHIP..."
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vbox.add_child(_status_label)

	_sub_label = Label.new()
	_sub_label.text = FLAVOR_LINES[0]
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5, 1.0))
	_vbox.add_child(_sub_label)

	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.value = 0.0
	_bar.custom_minimum_size = Vector2(280, 14)
	_bar.show_percentage = false
	_vbox.add_child(_bar)

func _on_generation_progress(step: String, pct: float) -> void:
	if _status_label:
		_status_label.text = step
	if _bar:
		_bar.value = pct
	if _sub_label:
		_sub_label.text = FLAVOR_LINES[randi() % FLAVOR_LINES.size()]

func _on_ship_generated(_pod_positions: Array) -> void:
	## Defer the hide so the final progress update is visible for one frame.
	call_deferred("hide")
